// Las pruebas de pedidos, POR HTTP y pasando por el router de verdad.
//
// Va en el paquete `api` y no en `api_test` a propósito: `rutasPedidos` es del paquete, y
// montarlas desde fuera obligaría a tocar `servidor.go`. Así se prueba EL MONTAJE —que
// cada ruta lleva su sesión y su alcance, y que el 405 del alta retirada sale del router—
// que es justo donde se escapan estas cosas.
//
// Sin base de datos: el doble del `sqlc.Querier` embebe la interfaz sin implementarla, así
// que cualquier consulta que una prueba no haya previsto revienta con un puntero nil en
// vez de devolver un cero que parezca bueno. Un doble que contesta a todo aprueba
// cualquier cosa.
package api

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

const (
	secretoPedidos = "otro-secreto-de-pruebas-de-al-menos-32-caracteres"
	llavePedidos   = "la-llave-de-servicio"
)

var (
	pedidosSucStg = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	pedidosSucHol = uuid.MustParse("22222222-2222-2222-2222-222222222222")

	pedidosStgA = uuid.MustParse("aaaaaaaa-1111-1111-1111-000000000001")
	pedidosStgB = uuid.MustParse("aaaaaaaa-1111-1111-1111-000000000002")
	pedidosHolA = uuid.MustParse("bbbbbbbb-2222-2222-2222-000000000001")
)

// --------------------------------------------------------------------------- el doble

// dobleDePedidos repite del SQL de verdad SÓLO lo que estas pruebas ejercitan: el alcance
// por sucursal y la búsqueda de `q` —incluida la que va contra los RENGLONES, que es la
// que antes miraba `productosTexto`—. Los demás filtros los prueba el SQL, no esto.
type dobleDePedidos struct {
	sqlc.Querier

	pedidos     []sqlc.ListarPedidosRow
	disponibles []sqlc.ListarPedidosDisponiblesRow
	renglones   map[uuid.UUID][]sqlc.ListarRenglonesDePedidosRow

	// totalDisponibles es lo que devuelve el CONTADOR, aparte de las filas. Se pone a
	// mano para poder probar el `truncated`: la lista viene recortada a 2000 y el total
	// no.
	totalDisponibles int64

	pesos     []sqlc.PesosDelCatalogoPorFuenteRow
	sinPeso   []sqlc.RenglonesSinPesoPorFuenteRow
	facetas   []sqlc.FacetasSucursalesRow
	municipio []sqlc.FacetasMunicipiosRow

	// Lo que se vio pasar.
	pesosEscritos []sqlc.ActualizarPesoDePedidoParams
	ultimoPatch   sqlc.ActualizarPedidoParams
}

func (d *dobleDePedidos) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	switch id {
	case pedidosSucStg:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: pedidosSucStg, Name: "Santiago", ExternalID: &c}, nil
	case pedidosSucHol:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: pedidosSucHol, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

// pedidosEnAlcance es el `(sucursal IS NULL OR o.branch_id = sucursal)` del SQL.
func pedidosEnAlcance(sucursal, delPedido pgtype.UUID) bool {
	return !sucursal.Valid || (delPedido.Valid && delPedido.Bytes == sucursal.Bytes)
}

// casaLaBusqueda repite el `q`: los campos del pedido MÁS el EXISTS contra `order_items`.
func (d *dobleDePedidos) casaLaBusqueda(id uuid.UUID, cliente string, q *string) bool {
	if q == nil {
		return true
	}
	aguja := strings.ToLower(*q)
	if strings.Contains(strings.ToLower(cliente), aguja) {
		return true
	}
	for _, g := range d.renglones[id] {
		if strings.Contains(strings.ToLower(g.Description), aguja) {
			return true
		}
	}
	return false
}

func (d *dobleDePedidos) ListarPedidos(_ context.Context, arg sqlc.ListarPedidosParams) ([]sqlc.ListarPedidosRow, error) {
	var salida []sqlc.ListarPedidosRow
	for _, p := range d.pedidos {
		if pedidosEnAlcance(arg.Sucursal, p.BranchID) && d.casaLaBusqueda(p.ID, p.CustomerName, arg.Q) {
			salida = append(salida, p)
		}
	}
	if int(arg.Desplazamiento) >= len(salida) {
		return nil, nil
	}
	salida = salida[arg.Desplazamiento:]
	if int(arg.Limite) < len(salida) {
		salida = salida[:arg.Limite]
	}
	return salida, nil
}

func (d *dobleDePedidos) ContarPedidos(_ context.Context, arg sqlc.ContarPedidosParams) (int64, error) {
	var n int64
	for _, p := range d.pedidos {
		if pedidosEnAlcance(arg.Sucursal, p.BranchID) && d.casaLaBusqueda(p.ID, p.CustomerName, arg.Q) {
			n++
		}
	}
	return n, nil
}

func (d *dobleDePedidos) ListarPedidosDisponibles(_ context.Context, arg sqlc.ListarPedidosDisponiblesParams) ([]sqlc.ListarPedidosDisponiblesRow, error) {
	var salida []sqlc.ListarPedidosDisponiblesRow
	for _, p := range d.disponibles {
		if pedidosEnAlcance(arg.Sucursal, p.BranchID) {
			salida = append(salida, p)
		}
	}
	if int(arg.Limite) < len(salida) {
		salida = salida[:arg.Limite]
	}
	return salida, nil
}

func (d *dobleDePedidos) ContarPedidosDisponibles(_ context.Context, _ sqlc.ContarPedidosDisponiblesParams) (int64, error) {
	return d.totalDisponibles, nil
}

func (d *dobleDePedidos) ListarRenglonesDePedidos(_ context.Context, arg sqlc.ListarRenglonesDePedidosParams) ([]sqlc.ListarRenglonesDePedidosRow, error) {
	var salida []sqlc.ListarRenglonesDePedidosRow
	for _, id := range arg.PedidoIds {
		salida = append(salida, d.renglones[id]...)
	}
	return salida, nil
}

func (d *dobleDePedidos) ListarRenglonesDePedido(_ context.Context, arg sqlc.ListarRenglonesDePedidoParams) ([]sqlc.ListarRenglonesDePedidoRow, error) {
	var salida []sqlc.ListarRenglonesDePedidoRow
	for _, g := range d.renglones[arg.PedidoID] {
		salida = append(salida, sqlc.ListarRenglonesDePedidoRow{
			ID: g.ID, OrderID: g.OrderID, Linea: g.Linea, Description: g.Description,
			Quantity: g.Quantity, Packs: g.Packs, ProductID: g.ProductID,
		})
	}
	return salida, nil
}

func (d *dobleDePedidos) ResumenPreDespacho(_ context.Context, arg sqlc.ResumenPreDespachoParams) ([]sqlc.ResumenPreDespachoRow, error) {
	porNombre := map[string]int64{}
	var orden []string
	for _, id := range arg.PedidoIds {
		for _, g := range d.renglones[id] {
			if _, visto := porNombre[g.Description]; !visto {
				orden = append(orden, g.Description)
			}
			porNombre[g.Description] += int64(g.Quantity)
		}
	}
	var salida []sqlc.ResumenPreDespachoRow
	for _, nombre := range orden {
		salida = append(salida, sqlc.ResumenPreDespachoRow{
			Producto: nombre,
			Formatos: porNombre[nombre],
			Unidades: porNombre[nombre],
			// 12.50 escrito como lo escribe Postgres: entero y exponente.
			PesoKg: pgtype.Numeric{Int: big.NewInt(1250), Exp: -2, Valid: true},
		})
	}
	return salida, nil
}

func (d *dobleDePedidos) FacetasMunicipios(_ context.Context, _ pgtype.UUID) ([]sqlc.FacetasMunicipiosRow, error) {
	return d.municipio, nil
}

func (d *dobleDePedidos) FacetasVendedores(_ context.Context, _ pgtype.UUID) ([]sqlc.FacetasVendedoresRow, error) {
	return nil, nil
}

func (d *dobleDePedidos) FacetasSucursales(_ context.Context, _ pgtype.UUID) ([]sqlc.FacetasSucursalesRow, error) {
	return d.facetas, nil
}

func (d *dobleDePedidos) ObtenerPedido(_ context.Context, arg sqlc.ObtenerPedidoParams) (sqlc.ObtenerPedidoRow, error) {
	for _, p := range d.pedidos {
		if p.ID != arg.ID {
			continue
		}
		if !pedidosEnAlcance(arg.Sucursal, p.BranchID) {
			break
		}
		return sqlc.ObtenerPedidoRow{
			ID: p.ID, CustomerName: p.CustomerName, Address: p.Address,
			Weight: p.Weight, Status: p.Status, BranchID: p.BranchID,
			RouteID: p.RouteID, RutaNombre: p.RutaNombre,
			// La duda del peso viaja también en el detalle: si el doble la tirara aquí,
			// la pantalla que más mira una persona sería la única que no la enseña y
			// ninguna prueba lo notaría.
			PesoRespaldado: p.PesoRespaldado,
		}, nil
	}
	return sqlc.ObtenerPedidoRow{}, pgx.ErrNoRows
}

func (d *dobleDePedidos) ActualizarPedido(_ context.Context, arg sqlc.ActualizarPedidoParams) (sqlc.ActualizarPedidoRow, error) {
	d.ultimoPatch = arg
	for i, p := range d.pedidos {
		if p.ID != arg.ID {
			continue
		}
		if !pedidosEnAlcance(arg.Sucursal, p.BranchID) {
			break
		}
		if arg.CustomerName != nil {
			d.pedidos[i].CustomerName = *arg.CustomerName
		}
		if arg.TocarRouteID {
			d.pedidos[i].RouteID = arg.RouteID
		}
		// CON SU `BranchID`: de la fila que vuelve del UPDATE sale la sucursal del aviso en
		// vivo. Sin él, un aviso que saliera pelado pasaría por bueno aquí.
		return sqlc.ActualizarPedidoRow{ID: p.ID, CustomerName: d.pedidos[i].CustomerName,
			BranchID: d.pedidos[i].BranchID}, nil
	}
	return sqlc.ActualizarPedidoRow{}, pgx.ErrNoRows
}

// BorrarPedido devuelve la SUCURSAL del pedido borrado, como el `RETURNING branch_id` de
// verdad, y `pgx.ErrNoRows` cuando no borró nada (que es el 404).
func (d *dobleDePedidos) BorrarPedido(_ context.Context, arg sqlc.BorrarPedidoParams) (pgtype.UUID, error) {
	for i, p := range d.pedidos {
		if p.ID != arg.ID {
			continue
		}
		if !pedidosEnAlcance(arg.Sucursal, p.BranchID) {
			break
		}
		suc := p.BranchID
		d.pedidos = append(d.pedidos[:i], d.pedidos[i+1:]...)
		return suc, nil
	}
	return pgtype.UUID{}, pgx.ErrNoRows
}

func (d *dobleDePedidos) PesosDelCatalogoPorFuente(_ context.Context, _ sqlc.Procedencia) ([]sqlc.PesosDelCatalogoPorFuenteRow, error) {
	return d.pesos, nil
}

func (d *dobleDePedidos) RenglonesSinPesoPorFuente(_ context.Context, _ sqlc.Procedencia) ([]sqlc.RenglonesSinPesoPorFuenteRow, error) {
	return d.sinPeso, nil
}

func (d *dobleDePedidos) ActualizarPesoDePedido(_ context.Context, arg sqlc.ActualizarPesoDePedidoParams) error {
	d.pesosEscritos = append(d.pesosEscritos, arg)
	return nil
}

type fuenteDePedidos struct{ q *dobleDePedidos }

func (f fuenteDePedidos) Consultas() sqlc.Querier { return f.q }
func (f fuenteDePedidos) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// --------------------------------------------------------------------------- montaje

func pedidosPg(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

func pedidosPtr[T any](v T) *T { return &v }

// datosDePedidos deja dos pedidos de Santiago y uno de Holguín, con sus renglones.
func datosDePedidos() *dobleDePedidos {
	d := &dobleDePedidos{
		renglones: map[uuid.UUID][]sqlc.ListarRenglonesDePedidosRow{},
	}
	d.pedidos = []sqlc.ListarPedidosRow{
		{ID: pedidosStgA, CustomerName: "Bar de Santiago", Address: "Calle 1", Weight: 10,
			Status: sqlc.OrderStatusPending, BranchID: pedidosPg(pedidosSucStg),
			SucursalNombre: pedidosPtr("Santiago")},
		{ID: pedidosStgB, CustomerName: "Cafetería del puerto", Address: "Calle 2", Weight: 5,
			Status: sqlc.OrderStatusPending, BranchID: pedidosPg(pedidosSucStg),
			SucursalNombre: pedidosPtr("Santiago")},
		{ID: pedidosHolA, CustomerName: "Almacén de Holguín", Address: "Calle 3", Weight: 7,
			Status: sqlc.OrderStatusPending, BranchID: pedidosPg(pedidosSucHol),
			SucursalNombre: pedidosPtr("Holguín")},
	}
	d.renglones[pedidosStgA] = []sqlc.ListarRenglonesDePedidosRow{
		{ID: uuid.New(), OrderID: pedidosStgA, Linea: 1, Description: "Malta Bucanero", Quantity: 24},
	}
	d.renglones[pedidosStgB] = []sqlc.ListarRenglonesDePedidosRow{
		{ID: uuid.New(), OrderID: pedidosStgB, Linea: 1, Description: "Cerveza Parranda", Quantity: 12},
	}
	return d
}

// servidorDePedidos monta SÓLO las rutas de pedidos, con los mismos middlewares que les
// pone `Rutas()`. Así la prueba cubre el montaje real y no una versión de laboratorio.
func servidorDePedidos(t *testing.T, d *dobleDePedidos) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoPedidos)
	t.Setenv("SERVICE_API_KEY", llavePedidos)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteDePedidos{q: d}, reg),
		auth.NuevoVerificador([]byte(secretoPedidos)),
		func(context.Context) error { return nil },
	)

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{s.verif.Exigir, s.porteria.Exigir}
	admin := []httpx.Medio{s.verif.Exigir, auth.ExigirAdmin, s.porteria.Exigir}
	s.rutasPedidos(rt, sesion, admin)
	return rt.Handler()
}

func jwtDePedidos(t *testing.T, reclamos map[string]any) string {
	t.Helper()
	if _, hay := reclamos["exp"]; !hay {
		reclamos["exp"] = time.Now().Add(time.Hour).Unix()
	}
	cab := pedidosEnB64(t, map[string]any{"alg": "HS256", "typ": "JWT"})
	cuerpo := pedidosEnB64(t, reclamos)
	mac := hmac.New(sha256.New, []byte(secretoPedidos))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func pedidosEnB64(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func pedirPedidos(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo string, cabeceras map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	for k, v := range cabeceras {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func tokenDeSantiagoPedidos(t *testing.T) string {
	t.Helper()
	return jwtDePedidos(t, map[string]any{
		"sub": "p-stg", "email": "stg@procovar.cu", "role": "OPERADOR", "branchId": pedidosSucStg.String(),
	})
}

func leerDePedidos[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("respuesta ilegible (%d): %s", w.Code, w.Body.String())
	}
	return v
}

// --------------------------------------------------------------------------- alcance

// LA PRUEBA DE SEGURIDAD: un operador de Santiago no llega a los pedidos de Holguín ni
// pidiéndolo por cabecera, ni por id directo, que es por donde se prueba a mano.
func TestUnOperadorNoVeLosPedidosDeOtraSucursal(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	jwt := tokenDeSantiagoPedidos(t)

	w := pedirPedidos(t, h, http.MethodGet, "/api/orders", jwt, "",
		map[string]string{"X-Sucursal-Id": pedidosSucHol.String()})
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "Holguín") {
		t.Fatalf("Santiago vio pedidos de Holguín: %s", w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "Bar de Santiago") {
		t.Fatalf("Santiago no vio ni lo suyo: %s", w.Body.String())
	}

	w = pedirPedidos(t, h, http.MethodGet, "/api/orders/"+pedidosHolA.String(), jwt, "", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("el pedido de Holguín tenía que ser 404 para Santiago, y fue %d", w.Code)
	}
	// El literal del contrato para esta ruta es «Not found», en INGLÉS, y no el
	// «No encontrado» de sucursales. Están inventariados uno por uno.
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Not found"}` {
		t.Fatalf("mensaje %q", got)
	}
}

func TestPedidosSinTokenEs401(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	for _, ruta := range []string{"/api/orders", "/api/orders/available", "/api/orders/facetas"} {
		w := pedirPedidos(t, h, http.MethodGet, ruta, "", "", nil)
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("%s: código %d", ruta, w.Code)
		}
		if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Unauthorized"}` {
			t.Fatalf("%s: cuerpo %q", ruta, got)
		}
	}
}

// --------------------------------------------------------------------- disponibles

// LA TRAMPA DEL CONTRATO: `kmMax` y `costoMin` se aplican DESPUÉS de la consulta, y
// `total`/`truncated` se calculan ANTES que ellos. Si alguien los baja al SQL, estos dos
// números cambian y la pantalla dice «7» sobre una tabla de 1.
func TestDisponiblesElTotalYElTruncadoSonAnterioresAKmMaxYCostoMin(t *testing.T) {
	d := datosDePedidos()
	d.disponibles = []sqlc.ListarPedidosDisponiblesRow{
		{ID: pedidosStgA, CustomerName: "Cerca y caro", BranchID: pedidosPg(pedidosSucStg),
			DeliveryDistanceKm: pedidosPtr(5.0), PedidoCosto: pedidosPtr(100.0)},
		{ID: pedidosStgB, CustomerName: "Lejos", BranchID: pedidosPg(pedidosSucStg),
			DeliveryDistanceKm: pedidosPtr(80.0), PedidoCosto: pedidosPtr(100.0)},
		{ID: pedidosHolA, CustomerName: "Sin medir", BranchID: pedidosPg(pedidosSucStg),
			DeliveryDistanceKm: nil, PedidoCosto: nil},
	}
	// El contador ve más de lo que cabe en la lista: eso es lo que enciende `truncated`.
	d.totalDisponibles = 7

	h := servidorDePedidos(t, d)
	jwt := tokenDeSantiagoPedidos(t)

	w := pedirPedidos(t, h, http.MethodGet, "/api/orders/available?kmMax=10", jwt, "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	got := leerDePedidos[DisponiblesSalida](t, w)

	if got.Total != 7 {
		t.Fatalf("`total` tiene que ser el del WHERE, sin kmMax: salió %d y tenía que ser 7", got.Total)
	}
	if !got.Truncated {
		t.Fatal("`truncated` se calcula antes de kmMax: con 7 en el contador y 3 filas tiene que ser true")
	}
	if len(got.Orders) != 2 {
		t.Fatalf("kmMax=10 deja «Cerca y caro» y «Sin medir»: salieron %d", len(got.Orders))
	}
	// Un pedido SIN distancia medida NUNCA se descarta: no saber cuánto hay no es estar
	// lejos, y esconderlo quita de la vista justo el que hay que mirar a mano.
	if !strings.Contains(w.Body.String(), "Sin medir") {
		t.Fatalf("el pedido sin distancia se cayó por kmMax: %s", w.Body.String())
	}
}

func TestDisponiblesCostoMinCuentaElSinCotizarComoCero(t *testing.T) {
	d := datosDePedidos()
	d.disponibles = []sqlc.ListarPedidosDisponiblesRow{
		{ID: pedidosStgA, CustomerName: "Cotizado", BranchID: pedidosPg(pedidosSucStg), PedidoCosto: pedidosPtr(50.0)},
		{ID: pedidosStgB, CustomerName: "Sin cotizar", BranchID: pedidosPg(pedidosSucStg), PedidoCosto: nil},
	}
	d.totalDisponibles = 2

	w := pedirPedidos(t, servidorDePedidos(t, d), http.MethodGet,
		"/api/orders/available?costoMin=10", tokenDeSantiagoPedidos(t), "", nil)
	got := leerDePedidos[DisponiblesSalida](t, w)
	if len(got.Orders) != 1 || got.Orders[0].CustomerName != "Cotizado" {
		t.Fatalf("`pedidoCosto ?? 0 < costoMin` tenía que dejar sólo el cotizado: %s", w.Body.String())
	}
	if got.Truncated {
		t.Fatal("con 2 en el contador y 2 filas no hay recorte: `truncated` tiene que ser false")
	}
}

func TestDisponiblesUnKmMaxSinNumeroSeIgnora(t *testing.T) {
	d := datosDePedidos()
	d.disponibles = []sqlc.ListarPedidosDisponiblesRow{
		{ID: pedidosStgA, CustomerName: "Lejísimos", BranchID: pedidosPg(pedidosSucStg), DeliveryDistanceKm: pedidosPtr(900.0)},
	}
	d.totalDisponibles = 1
	// Con un tope mal escrito es mejor enseñar de más que esconder pedidos sin avisar.
	w := pedirPedidos(t, servidorDePedidos(t, d), http.MethodGet,
		"/api/orders/available?kmMax=&costoMin=abc", tokenDeSantiagoPedidos(t), "", nil)
	if got := leerDePedidos[DisponiblesSalida](t, w); len(got.Orders) != 1 {
		t.Fatalf("un filtro no numérico no puede esconder nada: %s", w.Body.String())
	}
}

// --------------------------------------------------------------------- catálogo

// La caja de búsqueda pregunta también por la MERCANCÍA. Antes eso era `productosTexto`,
// una copia a mano de los nombres; ahora es `order_items`.
func TestBuscarPorElNombreDeUnRenglonEncuentraElPedido(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	w := pedirPedidos(t, h, http.MethodGet, "/api/orders?q=malta", tokenDeSantiagoPedidos(t), "", nil)
	got := leerDePedidos[CatalogoSalida](t, w)
	if got.Total != 1 || len(got.Orders) != 1 || got.Orders[0].ID != pedidosStgA {
		t.Fatalf("«malta» tenía que encontrar el pedido por su renglón: %s", w.Body.String())
	}
	if len(got.Orders[0].Items) != 1 || got.Orders[0].Items[0].Description != "Malta Bucanero" {
		t.Fatalf("los renglones tienen que venir en `items`: %s", w.Body.String())
	}
}

func TestCatalogoPaginacionConSusTopes(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	jwt := tokenDeSantiagoPedidos(t)

	// `porPagina` pasado de rosca se recorta a 200; `pagina` por debajo de 1 sube a 1.
	w := pedirPedidos(t, h, http.MethodGet, "/api/orders?pagina=0&porPagina=9999", jwt, "", nil)
	got := leerDePedidos[CatalogoSalida](t, w)
	if got.Pagina != 1 || got.PorPagina != PorPaginaTope {
		t.Fatalf("topes mal: pagina=%d porPagina=%d", got.Pagina, got.PorPagina)
	}
	// Una tabla vacía sigue teniendo UNA página: un cero deja al paginador sin nada que
	// pintar.
	if got.Paginas != 1 {
		t.Fatalf("paginas=%d", got.Paginas)
	}

	// Segunda página de una en una: quedan dos pedidos de Santiago.
	w = pedirPedidos(t, h, http.MethodGet, "/api/orders?pagina=2&porPagina=1", jwt, "", nil)
	got = leerDePedidos[CatalogoSalida](t, w)
	if got.Total != 2 || got.Paginas != 2 || len(got.Orders) != 1 || got.Orders[0].ID != pedidosStgB {
		t.Fatalf("paginación: %s", w.Body.String())
	}
}

// Las tres caras de `resumen`, que son tres cosas distintas y no dos.
func TestResumenSeOmiteSaleNuloOSaleCalculado(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	jwt := tokenDeSantiagoPedidos(t)

	// 1. No se pidió: la clave NO está en el JSON.
	w := pedirPedidos(t, h, http.MethodGet, "/api/orders", jwt, "", nil)
	crudo := leerDePedidos[map[string]any](t, w)
	if _, hay := crudo["resumen"]; hay {
		t.Fatalf("sin pedirlo, `resumen` no puede salir: %s", w.Body.String())
	}
	if crudo["resumenTope"] != float64(TopeResumen) {
		t.Fatalf("`resumenTope` siempre sale: %s", w.Body.String())
	}

	// 2. Se pidió y se pudo: array, y `pesoTotal` es el de LO FILTRADO, no el de la
	//    página.
	w = pedirPedidos(t, h, http.MethodGet, "/api/orders?resumen=1&porPagina=1", jwt, "", nil)
	crudo = leerDePedidos[map[string]any](t, w)
	if crudo["resumen"] == nil {
		t.Fatalf("se pidió y cabía: tenía que salir el array: %s", w.Body.String())
	}
	got := leerDePedidos[CatalogoSalida](t, w)
	if len(got.Orders) != 1 {
		t.Fatalf("la página sigue siendo de uno: %s", w.Body.String())
	}
	if got.PesoTotal != 15 {
		t.Fatalf("`pesoTotal` es el de los dos pedidos filtrados (10+5): salió %v", got.PesoTotal)
	}
	if got.Resumen == nil || len(*got.Resumen) != 2 {
		t.Fatalf("el pre-despacho junta los renglones de los dos: %s", w.Body.String())
	}
	if (*got.Resumen)[0].PesoKg != 12.5 {
		t.Fatalf("el numeric de Postgres no se tradujo: %v", (*got.Resumen)[0].PesoKg)
	}
}

func TestResumenSaleNuloCuandoSePasaDelTope(t *testing.T) {
	d := datosDePedidos()
	// Más pedidos que el tope: releerlos todos es la petición que tumba el proceso, así
	// que se dice que no se pudo en vez de intentarlo.
	for i := 0; i < TopeResumen+1; i++ {
		d.pedidos = append(d.pedidos, sqlc.ListarPedidosRow{
			ID: uuid.New(), CustomerName: "relleno", BranchID: pedidosPg(pedidosSucStg),
			Status: sqlc.OrderStatusPending,
		})
	}
	w := pedirPedidos(t, servidorDePedidos(t, d), http.MethodGet,
		"/api/orders?resumen=1", tokenDeSantiagoPedidos(t), "", nil)
	crudo := leerDePedidos[map[string]any](t, w)
	valor, hay := crudo["resumen"]
	if !hay {
		t.Fatal("se pidió: la clave tiene que estar, aunque valga null")
	}
	if valor != nil {
		t.Fatalf("pasado el tope, `resumen` es null y no un array: %v", valor)
	}
	if got := leerDePedidos[CatalogoSalida](t, w); got.PesoTotal != 0 {
		t.Fatalf("sin resumen no hay `pesoTotal`: %v", got.PesoTotal)
	}
}

// --------------------------------------------------------------------- facetas

func TestFacetasComponenElNombreYDicenSinSucursal(t *testing.T) {
	d := datosDePedidos()
	d.municipio = []sqlc.FacetasMunicipiosRow{{Valor: pedidosPtr("Palma Soriano"), Pedidos: 3}}
	d.facetas = []sqlc.FacetasSucursalesRow{
		{Valor: pedidosPg(pedidosSucStg), SucursalNombre: pedidosPtr("Santiago"), SucursalCodigo: pedidosPtr("STG"), Pedidos: 2},
		// Una sucursal que ya no está en la tabla: se dice, no se esconde.
		{Valor: pedidosPg(pedidosSucHol), SucursalNombre: nil, SucursalCodigo: nil, Pedidos: 1},
	}
	w := pedirPedidos(t, servidorDePedidos(t, d), http.MethodGet, "/api/orders/facetas",
		tokenDeSantiagoPedidos(t), "", nil)
	got := leerDePedidos[FacetasSalida](t, w)

	if len(got.Municipios) != 1 || got.Municipios[0].Valor != "Palma Soriano" {
		t.Fatalf("municipios: %s", w.Body.String())
	}
	// Ordenadas por el nombre COMPUESTO, que es lo que se lee en el desplegable.
	if len(got.Sucursales) != 2 ||
		got.Sucursales[0].Nombre != "Santiago (STG)" ||
		got.Sucursales[1].Nombre != "Sin sucursal" {
		t.Fatalf("sucursales: %s", w.Body.String())
	}
	// Los vendedores salen `[]` y no `null`: la pantalla los recorre sin mirar.
	if got.Vendedores == nil {
		t.Fatalf("`vendedores` vacío tiene que ser [] y no null: %s", w.Body.String())
	}
}

// --------------------------------------------------------------------- PATCH

func TestPatchAplicaSoloLosCamposPresentes(t *testing.T) {
	d := datosDePedidos()
	h := servidorDePedidos(t, d)

	w := pedirPedidos(t, h, http.MethodPatch, "/api/orders/"+pedidosStgA.String(),
		tokenDeSantiagoPedidos(t), `{"customerName":"Bar del Parque"}`, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// Lo que no vino NO se toca: sin esto, un PATCH que sólo corregía el nombre borra
	// las coordenadas y el pedido desaparece del armador de rutas.
	if d.ultimoPatch.Address != nil || d.ultimoPatch.EndLat != nil || d.ultimoPatch.Weight != nil {
		t.Fatalf("un campo ausente llegó a la consulta: %+v", d.ultimoPatch)
	}
	if d.ultimoPatch.TocarRouteID {
		t.Fatal("`routeId` ausente no puede levantar el interruptor: bajaría el pedido del camión")
	}
	if got := leerDePedidos[PedidoDetalleSalida](t, w); got.CustomerName != "Bar del Parque" {
		t.Fatalf("la respuesta es la ficha releída: %s", w.Body.String())
	}
}

// `routeId: null` es como se baja un pedido de un camión a mano. Con `coalesce` esa mitad
// de la utilidad no se puede expresar, y por eso el SQL lleva interruptor.
func TestPatchConRouteIdNuloBajaElPedidoDelCamion(t *testing.T) {
	d := datosDePedidos()
	d.pedidos[0].RouteID = pedidosPg(uuid.New())
	h := servidorDePedidos(t, d)

	w := pedirPedidos(t, h, http.MethodPatch, "/api/orders/"+pedidosStgA.String(),
		tokenDeSantiagoPedidos(t), `{"routeId":null}`, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !d.ultimoPatch.TocarRouteID || d.ultimoPatch.RouteID.Valid {
		t.Fatalf("tenía que llegar el interruptor puesto y la ruta en NULL: %+v", d.ultimoPatch)
	}
}

func TestPatchConEstadoDesconocidoEs400YNo500(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	w := pedirPedidos(t, h, http.MethodPatch, "/api/orders/"+pedidosStgA.String(),
		tokenDeSantiagoPedidos(t), `{"status":"entregadisimo"}`, nil)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("un enum desconocido tiene que pararse aquí y no en Postgres: %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "entregadisimo") {
		t.Fatalf("el mensaje tiene que decir qué valor no vale: %s", w.Body.String())
	}
}

func TestPatchDeOtraSucursalEs404(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	w := pedirPedidos(t, h, http.MethodPatch, "/api/orders/"+pedidosHolA.String(),
		tokenDeSantiagoPedidos(t), `{"customerName":"mío ahora"}`, nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("código %d", w.Code)
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Not found"}` {
		t.Fatalf("mensaje %q", got)
	}
}

// --------------------------------------------------------------------- DELETE

func TestBorrarPedido(t *testing.T) {
	d := datosDePedidos()
	h := servidorDePedidos(t, d)
	jwt := tokenDeSantiagoPedidos(t)

	// El de otra sucursal, primero: tiene que ser 404 y NO tiene que borrarse.
	w := pedirPedidos(t, h, http.MethodDelete, "/api/orders/"+pedidosHolA.String(), jwt, "", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("borrar lo de Holguín desde Santiago tenía que ser 404, y fue %d", w.Code)
	}
	if len(d.pedidos) != 3 {
		t.Fatal("un 404 no puede haber borrado nada")
	}

	w = pedirPedidos(t, h, http.MethodDelete, "/api/orders/"+pedidosStgA.String(), jwt, "", nil)
	if w.Code != http.StatusOK || strings.TrimSpace(w.Body.String()) != `{"success":true}` {
		t.Fatalf("%d %s", w.Code, w.Body.String())
	}
	if len(d.pedidos) != 2 {
		t.Fatalf("quedaron %d pedidos", len(d.pedidos))
	}
}

// Un id que no es un uuid es el mismo caso que uno que no está: 404, no 400. Por fuera no
// hay diferencia, y contar cuál de las dos es sólo sirve para que alguien pruebe formatos.
func TestUnIdQueNoEsUuidEs404(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	w := pedirPedidos(t, h, http.MethodGet, "/api/orders/no-es-un-uuid", tokenDeSantiagoPedidos(t), "", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("código %d", w.Code)
	}
}

// --------------------------------------------------------------- recompute-weights

func TestRecalcularPesosExigeLaLlaveDeServicio(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())

	// Sin llave: 401. Y un token de persona NO vale: es otra puerta.
	w := pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", "", "", nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("sin llave: %d", w.Code)
	}
	w = pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", tokenDeSantiagoPedidos(t), "", nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("un token de persona no abre la puerta de servicio: %d", w.Code)
	}
	w = pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", "", "",
		map[string]string{"X-Api-Key": "la-que-no-es"})
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("llave equivocada: %d", w.Code)
	}
}

func TestRecalcularPesosEscribeYCuenta(t *testing.T) {
	d := datosDePedidos()
	d.pesos = []sqlc.PesosDelCatalogoPorFuenteRow{
		{ID: pedidosStgA, PesoGuardado: 10, PesoCatalogo: 12.5}, // cambia
		{ID: pedidosStgB, PesoGuardado: 5, PesoCatalogo: 5},     // igual
		{ID: pedidosHolA, PesoGuardado: 3, PesoCatalogo: 0},     // sin peso en el catálogo
	}
	d.sinPeso = []sqlc.RenglonesSinPesoPorFuenteRow{{Nombre: "Pomo raro", Veces: 4}}
	h := servidorDePedidos(t, d)
	cabecera := map[string]string{"X-Api-Key": llavePedidos}

	// En seco: cuenta lo que CAMBIARÍA y no escribe nada. Si no contara, el ensayo diría
	// siempre cero y no serviría para lo único para lo que existe.
	w := pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", "",
		`{"dryRun":true}`, cabecera)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	got := leerDePedidos[RecalculoSalida](t, w)
	if !got.DryRun || got.TotalOrders != 3 || got.Updated != 2 || got.Unchanged != 1 || got.OrdersSinPeso != 1 {
		t.Fatalf("cuentas del ensayo: %+v", got)
	}
	if len(d.pesosEscritos) != 0 {
		t.Fatalf("el ensayo escribió %d pesos", len(d.pesosEscritos))
	}
	if len(got.ProductosSinPeso) != 1 || got.ProductosSinPeso[0].Name != "Pomo raro" {
		t.Fatalf("falta la lista de lo que el catálogo no sabe pesar: %+v", got.ProductosSinPeso)
	}

	// De verdad: escribe sólo los que cambian.
	w = pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", "", "", cabecera)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if len(d.pesosEscritos) != 2 {
		t.Fatalf("se escribieron %d pesos y tenían que ser 2", len(d.pesosEscritos))
	}
	if d.pesosEscritos[0].ID != pedidosStgA || d.pesosEscritos[0].Weight != 12.5 {
		t.Fatalf("se escribió mal: %+v", d.pesosEscritos[0])
	}
}

func TestRecalcularPesosConProcedenciaRaraEs400(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	w := pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", "",
		`{"source":"inventada"}`, map[string]string{"X-Api-Key": llavePedidos})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------- alta retirada

// El alta manual se retiró el 03/09/2026. Al no registrar el POST, el 405 lo da el router
// y la cabecera `Allow` dice la verdad: sólo GET.
func TestElAltaManualDePedidosYaNoExiste(t *testing.T) {
	h := servidorDePedidos(t, datosDePedidos())
	w := pedirPedidos(t, h, http.MethodPost, "/api/orders", tokenDeSantiagoPedidos(t), `{}`, nil)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if allow := w.Header().Get("Allow"); strings.Contains(allow, "POST") {
		t.Fatalf("`Allow` no puede anunciar un alta que no existe: %q", allow)
	}
	if !strings.HasPrefix(w.Body.String(), `{"error"`) {
		t.Fatalf("el 405 también sale en JSON: %s", w.Body.String())
	}
}
