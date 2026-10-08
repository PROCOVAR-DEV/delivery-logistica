package api

// Las pruebas de clientes, productos, orígenes y almacenes, POR HTTP y con el router
// montado: así se comprueba que el alcance no se pierde en el montaje, que es donde se
// escapan estas cosas.
//
// Van en el paquete `api` y no en `api_test` porque las funciones que montan las rutas
// (`rutasClientes`, `rutasProductos`, `rutasAlmacenes`) no son exportadas: se llaman desde
// `servidor.go`, no desde fuera.
//
// EL MONTAJE COMÚN VIVE AQUÍ y lo usan los tres ficheros. El doble del Querier repite el
// WHERE del SQL de verdad —no devuelve lo que le pidas— porque lo que se está probando es
// justo qué sucursal llega a cada consulta.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
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

const secretoDeDatos = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

var (
	datSucStg = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	datSucHol = uuid.MustParse("22222222-2222-2222-2222-222222222222")

	datCliStg    = uuid.MustParse("c1111111-0000-0000-0000-000000000001")
	datCliHol    = uuid.MustParse("c2222222-0000-0000-0000-000000000002")
	datCliManual = uuid.MustParse("c3333333-0000-0000-0000-000000000003")
	datCliLejos  = uuid.MustParse("c4444444-0000-0000-0000-000000000004")

	datProdStg = uuid.MustParse("d1111111-0000-0000-0000-000000000001")
	datProdHol = uuid.MustParse("d2222222-0000-0000-0000-000000000002")

	datOrigStg = uuid.MustParse("e1111111-0000-0000-0000-000000000001")
	datOrigHol = uuid.MustParse("e2222222-0000-0000-0000-000000000002")
)

// --------------------------------------------------------------------------- el doble

// dobleDatos es el Querier de mentira. Embebe `sqlc.Querier` sin implementarlo: así
// satisface la interfaz entera escribiendo sólo las consultas que interesan, y si una
// prueba llama a cualquier otra revienta con un puntero nil en vez de devolver un cero que
// parezca bueno. Un doble que contesta a todo es un doble que aprueba cualquier cosa.
type dobleDatos struct {
	sqlc.Querier

	clientes  []sqlc.ListarClientesRow
	productos []sqlc.Product
	origenes  []sqlc.ListarOrigenesRow

	// Lo que se vio pasar: es lo que se comprueba de verdad.
	codigoPedidoAClientes  []*string
	codigoPedidoAProductos []*string
}

func (d *dobleDatos) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	switch id {
	case datSucStg:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: datSucStg, Name: "Santiago", ExternalID: &c}, nil
	case datSucHol:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: datSucHol, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

func (d *dobleDatos) ObtenerSucursal(_ context.Context, arg sqlc.ObtenerSucursalParams) (sqlc.Branch, error) {
	fila, err := d.ResolverSucursal(context.Background(), arg.ID)
	if err != nil {
		return sqlc.Branch{}, err
	}
	if arg.Sucursal.Valid && arg.Sucursal.Bytes != [16]byte(arg.ID) {
		return sqlc.Branch{}, pgx.ErrNoRows
	}
	return sqlc.Branch{ID: fila.ID, Name: fila.Name, ExternalID: fila.ExternalID}, nil
}

func (d *dobleDatos) CodigosDeSucursalesVisibles(_ context.Context, sucursal pgtype.UUID) ([]sqlc.CodigosDeSucursalesVisiblesRow, error) {
	stg, hol := "STG", "HOL"
	todas := []sqlc.CodigosDeSucursalesVisiblesRow{
		{ID: datSucHol, Name: "Holguín", ExternalID: &hol},
		{ID: datSucStg, Name: "Santiago", ExternalID: &stg},
	}
	if !sucursal.Valid {
		return todas, nil
	}
	var salida []sqlc.CodigosDeSucursalesVisiblesRow
	for _, v := range todas {
		if [16]byte(v.ID) == sucursal.Bytes {
			salida = append(salida, v)
		}
	}
	return salida, nil
}

// ListarSucursales: «A CUÁLES PUEDO LLEGAR», acotada por la sucursal **de la persona** y
// no por la de la cabecera. Es la que usa `/api/almacenes` desde el 26/09/2026 — ver
// `TestAlmacenesElSuperAdminMirandoUnaLasSigueViendoTodas`—, y repite aquí el `WHERE` de
// `branches.sql`: nulo = todas.
func (d *dobleDatos) ListarSucursales(_ context.Context, persona pgtype.UUID) ([]sqlc.ListarSucursalesRow, error) {
	stg, hol := "STG", "HOL"
	todas := []sqlc.ListarSucursalesRow{
		{ID: datSucHol, Name: "Holguín", ExternalID: &hol},
		{ID: datSucStg, Name: "Santiago", ExternalID: &stg},
	}
	if !persona.Valid {
		return todas, nil
	}
	var salida []sqlc.ListarSucursalesRow
	for _, v := range todas {
		if [16]byte(v.ID) == persona.Bytes {
			salida = append(salida, v)
		}
	}
	return salida, nil
}

// pasaElAlcanceDeClientes repite el WHERE de `customers.sql`: la sucursal del alcance, con
// los clientes SIN código dejándose ver siempre.
func pasaElAlcanceDeClientes(c sqlc.ListarClientesRow, alcanceCod *string) bool {
	if alcanceCod == nil {
		return true
	}
	return c.SucursalCodigo == nil || *c.SucursalCodigo == *alcanceCod
}

func (d *dobleDatos) filtrarClientes(arg sqlc.ListarClientesParams) []sqlc.ListarClientesRow {
	var salida []sqlc.ListarClientesRow
	for _, c := range d.clientes {
		if !pasaElAlcanceDeClientes(c, arg.SucursalDelAlcance) {
			continue
		}
		if arg.SucursalCodigo != nil && (c.SucursalCodigo == nil || *c.SucursalCodigo != *arg.SucursalCodigo) {
			continue
		}
		if arg.Q != nil && !strings.Contains(strings.ToLower(c.Name), strings.ToLower(*arg.Q)) {
			continue
		}
		if arg.LatMin != nil && c.Lat < *arg.LatMin {
			continue
		}
		if arg.LatMax != nil && c.Lat > *arg.LatMax {
			continue
		}
		if arg.LngMin != nil && c.Lng < *arg.LngMin {
			continue
		}
		if arg.LngMax != nil && c.Lng > *arg.LngMax {
			continue
		}
		salida = append(salida, c)
	}
	return salida
}

func (d *dobleDatos) ListarClientes(_ context.Context, arg sqlc.ListarClientesParams) ([]sqlc.ListarClientesRow, error) {
	d.codigoPedidoAClientes = append(d.codigoPedidoAClientes, arg.SucursalDelAlcance)
	return d.filtrarClientes(arg), nil
}

func (d *dobleDatos) ContarClientes(_ context.Context, arg sqlc.ContarClientesParams) (int64, error) {
	return int64(len(d.filtrarClientes(sqlc.ListarClientesParams{
		SucursalDelAlcance: arg.SucursalDelAlcance, SucursalCodigo: arg.SucursalCodigo, Q: arg.Q,
		LatMin: arg.LatMin, LatMax: arg.LatMax, LngMin: arg.LngMin, LngMax: arg.LngMax,
	}))), nil
}

func (d *dobleDatos) FacetasClientesMunicipios(_ context.Context, cod *string) ([]sqlc.FacetasClientesMunicipiosRow, error) {
	var salida []sqlc.FacetasClientesMunicipiosRow
	for _, c := range d.clientes {
		if pasaElAlcanceDeClientes(c, cod) && c.Municipio != nil {
			salida = append(salida, sqlc.FacetasClientesMunicipiosRow{Valor: c.Municipio, Clientes: 1})
		}
	}
	return salida, nil
}

func (d *dobleDatos) FacetasClientesZonas(_ context.Context, _ *string) ([]sqlc.FacetasClientesZonasRow, error) {
	return nil, nil
}

func (d *dobleDatos) FacetasClientesVendedores(_ context.Context, _ *string) ([]sqlc.FacetasClientesVendedoresRow, error) {
	return nil, nil
}

func (d *dobleDatos) FacetasClientesSucursales(_ context.Context, cod *string) ([]sqlc.FacetasClientesSucursalesRow, error) {
	var salida []sqlc.FacetasClientesSucursalesRow
	for _, c := range d.clientes {
		if pasaElAlcanceDeClientes(c, cod) && c.SucursalCodigo != nil {
			salida = append(salida, sqlc.FacetasClientesSucursalesRow{Valor: c.SucursalCodigo, Clientes: 1})
		}
	}
	return salida, nil
}

func (d *dobleDatos) ContarClientesSinTelefono(_ context.Context, _ *string) (int64, error) {
	return 0, nil
}

// --------------------------------------------------------------------------- montaje

type fuenteDeDatos struct{ q sqlc.Querier }

func (f fuenteDeDatos) Consultas() sqlc.Querier { return f.q }

// EnTx corre la función tal cual: el doble no tiene transacciones. Lo que se prueba aquí
// es el alcance, no el aislamiento de Postgres.
func (f fuenteDeDatos) EnTx(_ context.Context, fn func(sqlc.Querier) error) error { return fn(f.q) }

// datosDePrueba es la base de mentira: dos sucursales con lo suyo y un cliente manual.
func datosDePrueba() *dobleDatos {
	stg, hol := "STG", "HOL"
	sant, holg := "Santiago", "Holguín"
	pedido := sqlc.ProcedenciaPedido
	return &dobleDatos{
		clientes: []sqlc.ListarClientesRow{
			{ID: datCliStg, Name: "Bodega de Santiago", SucursalCodigo: &stg, Municipio: &sant,
				Source: &pedido, Lat: 20.01, Lng: -75.80},
			{ID: datCliHol, Name: "Bodega de Holguín", SucursalCodigo: &hol, Municipio: &holg,
				Source: &pedido, Lat: 20.88, Lng: -76.26},
			// Sin código: el alta a mano vieja. Se ve desde cualquier sucursal.
			{ID: datCliManual, Name: "Cliente manual", Lat: 20.00, Lng: -75.80},
			{ID: datCliLejos, Name: "Bodega lejana de Santiago", SucursalCodigo: &stg,
				Source: &pedido, Lat: 21.00, Lng: -75.80},
		},
		productos: []sqlc.Product{
			{ID: datProdStg, Name: "Arroz", Weight: 1, SucursalCodigo: &stg, Price: flotante(100)},
			{ID: datProdHol, Name: "Arroz", Weight: 1, SucursalCodigo: &hol, Price: flotante(250)},
		},
		origenes: []sqlc.ListarOrigenesRow{
			{ID: datOrigStg, Name: "Almacén de Santiago", Address: "x", BranchID: pgDeDatos(datSucStg), SucursalNombre: &sant},
			{ID: datOrigHol, Name: "Almacén de Holguín", Address: "y", BranchID: pgDeDatos(datSucHol), SucursalNombre: &holg},
		},
	}
}

func pgDeDatos(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

// montar levanta el servidor con las tres rutas de este trabajo puestas.
func montarDeDatos(t *testing.T, q sqlc.Querier) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeDatos)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDeDatos{q: q}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeDatos))
	s := NuevoServidor(cfg, reg, porteria, verif, func(context.Context) error { return nil })

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{verif.Exigir, porteria.Exigir}
	admin := []httpx.Medio{verif.Exigir, auth.ExigirAdmin, porteria.Exigir}
	s.rutasClientes(rt, sesion, admin)
	s.rutasProductos(rt, sesion, admin)
	s.rutasAlmacenes(rt, sesion, admin)
	return rt.Handler()
}

// jwt firma un token HS256 como el que emite auth.
func tokenDeDatos(t *testing.T, reclamos map[string]any) string {
	t.Helper()
	if _, hay := reclamos["exp"]; !hay {
		reclamos["exp"] = time.Now().Add(time.Hour).Unix()
	}
	cab := b64DeDatos(t, map[string]any{"alg": "HS256", "typ": "JWT"})
	cuerpo := b64DeDatos(t, reclamos)
	mac := hmac.New(sha256.New, []byte(secretoDeDatos))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func b64DeDatos(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// deSantiago: un operador que pertenece a Santiago. Es quien no puede ver Holguín ni
// pidiéndolo.
func logisticoDeSantiago(t *testing.T) string {
	return tokenDeDatos(t, map[string]any{"sub": "p-stg", "email": "stg@procovar.cu",
		"role": "LOGISTICO", "branchId": datSucStg.String()})
}

// superAdmin: administrador SIN sucursal. Es el único que ve las ocho y el único que toca
// el catálogo.
func superAdminDeDatos(t *testing.T) string {
	return tokenDeDatos(t, map[string]any{"sub": "p-super", "role": "SUPER ADMIN"})
}

func pedirDeDatos(t *testing.T, h http.Handler, metodo, ruta, token, cuerpo string, cabeceras map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	for k, v := range cabeceras {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func leerJSONDeDatos(t *testing.T, w *httptest.ResponseRecorder, destino any) {
	t.Helper()
	if err := json.Unmarshal(w.Body.Bytes(), destino); err != nil {
		t.Fatalf("respuesta ilegible (%d): %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------------- clientes

// LA PRUEBA DEL ALCANCE, y aquí no es sólo de permisos: los clientes de Holguín son los de
// Holguín. Verlos desde Santiago es meter en la ruta de hoy a alguien que está a 200 km.
func TestClientesNoSeVenLosDeOtraSucursalNiPidiendolaPorCabecera(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers", logisticoDeSantiago(t), "",
		map[string]string{alcance.CabeceraSucursal: datSucHol.String()})
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida ClientesSalida
	leerJSONDeDatos(t, w, &salida)

	for _, c := range salida.Customers {
		if c.ID == datCliHol {
			t.Fatalf("Santiago vio un cliente de Holguín: %s", w.Body.String())
		}
	}
	if len(salida.Customers) != 3 {
		t.Fatalf("tenía que ver los dos suyos y el manual, y vio %d: %s", len(salida.Customers), w.Body.String())
	}
	// Las facetas también van acotadas: si no, el desplegable de sucursales ofrece HOL y
	// al elegirlo salen cero clientes, que parece un fallo de datos.
	for _, f := range salida.Sucursales {
		if f.Valor == "HOL" {
			t.Fatalf("el desplegable ofrecía Holguín: %s", w.Body.String())
		}
	}
}

// El cliente MANUAL no tiene código de sucursal y tiene que verse desde cualquiera:
// esconderlo haría desaparecer clientes que sí se atienden, sin decir nada.
func TestClientesElManualSinCodigoSeVeSiempre(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers", logisticoDeSantiago(t), "", nil)

	var salida ClientesSalida
	leerJSONDeDatos(t, w, &salida)
	hay := false
	for _, c := range salida.Customers {
		if c.ID == datCliManual {
			hay = true
		}
	}
	if !hay {
		t.Fatalf("el cliente manual no salió: %s", w.Body.String())
	}
}

// El filtro de la query ESTRECHA dentro del alcance, nunca lo amplía: pedir el código de
// otra sucursal deja la lista vacía, no enseña la de otra.
func TestClientesElFiltroDeLaQueryNoAmpliaElAlcance(t *testing.T) {
	d := datosDePrueba()
	h := montarDeDatos(t, d)

	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers?sucursalCodigo=HOL", logisticoDeSantiago(t), "", nil)
	var salida ClientesSalida
	leerJSONDeDatos(t, w, &salida)
	if len(salida.Customers) != 0 {
		t.Fatalf("pidiendo HOL desde Santiago salió algo: %s", w.Body.String())
	}
	// Y lo que llegó a la consulta fue el código del ALCANCE, no el de la query.
	if n := len(d.codigoPedidoAClientes); n == 0 || d.codigoPedidoAClientes[n-1] == nil ||
		*d.codigoPedidoAClientes[n-1] != "STG" {
		t.Fatalf("a la consulta no le llegó el código del alcance: %v", d.codigoPedidoAClientes)
	}
}

// El Super Admin sí elige sucursal por la cabecera: es el caso normal de quien administra.
func TestClientesElSuperAdminEligeSucursalPorCabecera(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers", superAdminDeDatos(t), "",
		map[string]string{alcance.CabeceraSucursal: datSucHol.String()})

	var salida ClientesSalida
	leerJSONDeDatos(t, w, &salida)
	for _, c := range salida.Customers {
		if c.ID == datCliStg {
			t.Fatalf("eligió Holguín y le salió Santiago: %s", w.Body.String())
		}
	}
}

// La forma de la respuesta es la del contrato, y la página son 50 FIJOS.
func TestClientesLaFormaDeLaRespuestaEsLaDelContrato(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers", superAdminDeDatos(t), "", nil)

	var crudo map[string]any
	leerJSONDeDatos(t, w, &crudo)
	for _, campo := range []string{"count", "total", "pagina", "porPagina", "paginas", "truncated",
		"customers", "almacenDeReferencia", "municipios", "sucursales", "zonas", "vendedores", "sinTelefono"} {
		if _, hay := crudo[campo]; !hay {
			t.Fatalf("falta el campo %q del contrato: %s", campo, w.Body.String())
		}
	}
	if crudo["porPagina"].(float64) != 50 {
		t.Fatalf("la página es de 50, fija: %v", crudo["porPagina"])
	}
	// Sin almacén no se mide: `almacenDeReferencia` es null y no hay `kmDelAlmacen`.
	if crudo["almacenDeReferencia"] != nil {
		t.Fatalf("sin kmMax no se mide nada: %v", crudo["almacenDeReferencia"])
	}
	if strings.Contains(w.Body.String(), "kmDelAlmacen") {
		t.Fatalf("salió kmDelAlmacen sin haber medido: %s", w.Body.String())
	}
}

// El filtro por kilómetros: la caja primero y la distancia exacta después, sobre la
// página. Y se dice desde qué almacén se midió — «a 10 km» de un almacén y de otro no es
// lo mismo.
func TestClientesElFiltroPorKilometrosMideDesdeElAlmacen(t *testing.T) {
	anterior := Accesos
	t.Cleanup(func() { Accesos = anterior })
	// `Activo: true` NO estaba aquí hasta el 24/09/2026, y no era un olvido: era la señal
	// de que esta pantalla tenía su propia copia de la regla y no miraba `activo`. Hoy
	// elige con `cotizar.ElegirAlmacen`, como el tablero y la cotización, y un almacén sin
	// `activo` es un almacén de baja.
	Accesos = &accesosFalso{sucursales: []SucursalConAlmacenes{{
		Codigo: "STG", Nombre: "Santiago",
		Almacenes: []Almacen{
			{Nombre: "Patio viejo", Activo: true, Latitud: flotante(21.5), Longitud: flotante(-75.8)},
			{Nombre: "Principal", Principal: true, Activo: true, Latitud: flotante(20.0), Longitud: flotante(-75.8)},
		},
	}}}

	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers?kmMax=5", logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida ClientesSalida
	leerJSONDeDatos(t, w, &salida)

	if salida.AlmacenDeReferencia == nil || salida.AlmacenDeReferencia.Latitud != 20.0 {
		t.Fatalf("tenía que medir desde el PRINCIPAL con coordenadas: %+v", salida.AlmacenDeReferencia)
	}
	for _, c := range salida.Customers {
		if c.ID == datCliLejos {
			t.Fatalf("un cliente a ~111 km pasó un filtro de 5 km: %s", w.Body.String())
		}
		if c.KmDelAlmacen == nil {
			t.Fatalf("se midió pero no se dice cuánto: %s", w.Body.String())
		}
	}
	if len(salida.Customers) != 2 {
		t.Fatalf("tenían que quedar los dos de cerca, y quedaron %d: %s", len(salida.Customers), w.Body.String())
	}
	// `total` se cuenta ANTES del filtro de distancia exacto, así que puede ser mayor que
	// `count`: la caja deja pasar las esquinas del cuadrado.
	if salida.Count > int(salida.Total) {
		t.Fatalf("count (%d) no puede ser mayor que total (%d)", salida.Count, salida.Total)
	}
}

// CLIENTES MIDE DESDE EL MISMO ALMACÉN QUE TODOS LOS DEMÁS — 24/09/2026.
//
// Esta pantalla tenía su propia copia de la regla: un bucle a mano que sólo miraba las
// coordenadas, sin `activo` y sin descartar el (0,0). Con ella, la columna de km y el
// filtro «Hasta N km» de la WEB medían desde un almacén dado de baja mientras la ficha de
// Clientes de la APK medía desde el activo — el mismo cliente, dos distancias, y de ahí
// sale el domicilio que se cobra. Hoy elige con `cotizar.ElegirAlmacen`.
//
// EL DE BAJA ES EL PRINCIPAL Y VA EL PRIMERO a propósito: quien vuelva a coger «el primer
// principal con coordenadas» pasa las demás pruebas y falla ésta.
func TestClientesNoMideDesdeUnAlmacenDeBaja(t *testing.T) {
	anterior := Accesos
	t.Cleanup(func() { Accesos = anterior })
	Accesos = &accesosFalso{sucursales: []SucursalConAlmacenes{{
		Codigo: "STG", Nombre: "Santiago",
		Almacenes: []Almacen{
			{Nombre: "Almacén viejo", Principal: true, Activo: false,
				Latitud: flotante(21.5), Longitud: flotante(-75.8)},
			{Nombre: "Zona franca", Activo: true,
				Latitud: flotante(20.0), Longitud: flotante(-75.8)},
		},
	}}}

	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers?kmMax=5", logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida ClientesSalida
	leerJSONDeDatos(t, w, &salida)

	if salida.AlmacenDeReferencia == nil || salida.AlmacenDeReferencia.Latitud != 20.0 {
		t.Fatalf("midió desde el almacén dado de baja: %+v. La APK mide desde el activo, "+
			"así que el mismo cliente sale a dos distancias y el domicilio se cobra por "+
			"la que toque pulsar", salida.AlmacenDeReferencia)
	}
}

// Si Accesos no contesta, la lista de clientes SALE IGUAL, sin medir. Que el buscador que
// se usa todo el día dependa de un servicio ajeno sería cambiar lo importante por lo raro.
func TestClientesSiAccesosNoContestaSeListaSinMedir(t *testing.T) {
	anterior := Accesos
	t.Cleanup(func() { Accesos = anterior })
	Accesos = &accesosFalso{fallo: errAccesosCaido}

	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/customers?kmMax=5", logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("Accesos caído no puede tumbar la lista de clientes: %d %s", w.Code, w.Body.String())
	}
	var salida ClientesSalida
	leerJSONDeDatos(t, w, &salida)
	if salida.AlmacenDeReferencia != nil {
		t.Fatalf("no había almacén que usar: %+v", salida.AlmacenDeReferencia)
	}
	if len(salida.Customers) != 3 {
		t.Fatalf("tenían que salir los tres del alcance: %s", w.Body.String())
	}
}

func TestClientesSinTokenEs401ConElLiteralDelContrato(t *testing.T) {
	w := pedirDeDatos(t, montarDeDatos(t, datosDePrueba()), http.MethodGet, "/api/customers", "", "", nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d", w.Code)
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Unauthorized"}` {
		t.Fatalf("cuerpo %q", got)
	}
}

// El alta a mano se retiró el 03/09/2026: no hay POST montado y tiene que verse como
// método no permitido, con JSON y con la cabecera Allow.
func TestClientesNoHayAltaManual(t *testing.T) {
	w := pedirDeDatos(t, montarDeDatos(t, datosDePrueba()), http.MethodPost, "/api/customers", superAdminDeDatos(t), `{}`, nil)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("el alta de clientes ya no existe: %d %s", w.Code, w.Body.String())
	}
	if !strings.HasPrefix(w.Body.String(), `{"error"`) {
		t.Fatalf("hasta el 405 sale en JSON: %s", w.Body.String())
	}
}
