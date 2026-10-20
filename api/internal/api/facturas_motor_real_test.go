package api

// LA FACTURA COMO SEGUNDA FUENTE, CONTRA POSTGRES DE VERDAD (issue 20, Fase A).
//
// Lo que se prueba aquí no lo ve ningún doble: la ADOPCIÓN (el `external_id` de la fila de
// PEDIDO cambia y conserva `id`, ruta y punto a mano), la CONVIVENCIA (un pedido de PEDIDO que
// llega después de adoptado no crea otra fila), la CARRERA (dos ciclos a la vez no duplican: el
// candado del folio), el REPASO IDÉNTICO (no reescribe) y la RETIRADA con sus guardas (con
// ruta no se borra, con respuesta vacía no se borra, fuera de la ventana no se borra).
//
// ES EL RECORRIDO ENTERO, no un trozo: el ciclo del espejo (`CicloDeFacturas`) → el mapeo →
// `ArmarLote` → `POST /api/quote/batch` (la puerta de verdad) → `EspejoGuardarPedido` → Postgres.
// Lo único de mentira es Ventra.
//
// SE SALTA SIN `REPARTO_MOTOR_REAL_DSN` y se niega a correr si la base no es de pruebas. A
// diferencia de las otras de motor real, ESTA CONFIRMA lo que escribe (la carrera necesita
// transacciones de verdad en conexiones distintas), así que cada prueba trabaja con su propia
// sucursal de nombre único y limpia lo suyo al terminar:
//
//	REPARTO_MOTOR_REAL_DSN='postgres://verif:verif@127.0.0.1:5433/verif_reparto_facturas?sslmode=disable' \
//	  go test -count=1 -run MotorReal_Factura ./internal/api/

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store"
)

// --------------------------------------------------------------------------- Ventra de mentira

type ventraEnMemoria struct {
	mu       sync.Mutex
	bases    map[string]string
	facturas []espejo.FacturaDeVentra
	fallo    error
	pedidas  []string
	// filtra: contesta SOLO las facturas cuyo día cae en [desde, hasta], como el Ventra de verdad.
	// Por defecto contesta todas, que es lo que suponían las pruebas de la retirada.
	filtra bool
}

func (v *ventraEnMemoria) Bases(context.Context) (map[string]string, error) {
	return v.bases, nil
}

func (v *ventraEnMemoria) FacturasConDomicilio(_ context.Context, base string, desde, hasta time.Time, _ []string) ([]espejo.FacturaDeVentra, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.pedidas = append(v.pedidas, base+" "+desde.Format(time.DateOnly)+".."+hasta.Format(time.DateOnly))
	if v.fallo != nil {
		return nil, v.fallo
	}
	if !v.filtra {
		return append([]espejo.FacturaDeVentra(nil), v.facturas...), nil
	}
	var dentro []espejo.FacturaDeVentra
	for _, f := range v.facturas {
		if f.Fecha >= desde.Format(time.DateOnly) && f.Fecha <= hasta.Format(time.DateOnly) {
			dentro = append(dentro, f)
		}
	}
	return dentro, nil
}

func (v *ventraEnMemoria) poner(fs ...espejo.FacturaDeVentra) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.facturas, v.fallo = fs, nil
}

// facturaDeMentira: UNA línea de cerveza (15 B) y su domicilio. Todo inventado.
func facturaDeMentira(numero, fecha, pedido string) espejo.FacturaDeVentra {
	return espejo.FacturaDeVentra{
		Numero: numero, Fecha: fecha,
		Punto: espejo.PuntoDeVenta{Codigo: "2", Nombre: "ALMACEN UNO"},
		Cliente: espejo.ClienteDeFactura{Nombre: "Cliente Inventado " + numero, Direccion: "Calle Falsa 1",
			Ciudad: "Santiago de Cuba", Telefono: "50000001"},
		Vendedor: "VENDEDOR INVENTADO", Pedido: pedido, ReferenciaDelCliente: "COD-" + numero,
		Lineas: []espejo.LineaDeFactura{
			{Codigo: "PARR0002", Nombre: "CERVEZA PARRANDA 500 ML BLISTER 6U", Unidad: "B", Cantidad: 15, Importe: 59.4},
			{Codigo: "50", Nombre: "ENTREGA A DOMICILIO", Unidad: "U", Cantidad: 0.29, Importe: 0.29, EsDomicilio: true},
		},
	}
}

// --------------------------------------------------------------------------- el entorno

// destinoPorLaPuerta hace de `ClienteDelivery` sin red: manda el MISMO cuerpo a la puerta de
// verdad. Es lo que garantiza que lo probado es lo que entra en producción.
type destinoPorLaPuerta struct{ h http.Handler }

func (d destinoPorLaPuerta) Cotizar(_ context.Context, pedidos []espejo.PedidoDeFuera) (espejo.RespuestaDelLote, error) {
	cuerpo, err := json.Marshal(espejo.ArmarLote(pedidos))
	if err != nil {
		return espejo.RespuestaDelLote{}, err
	}
	r := httptest.NewRequest(http.MethodPost, "/api/quote/batch", bytes.NewReader(cuerpo))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
	w := httptest.NewRecorder()
	d.h.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		return espejo.RespuestaDelLote{}, fmt.Errorf("la puerta contestó %d: %s", w.Code, w.Body.String())
	}
	var resp espejo.RespuestaDelLote
	return resp, json.Unmarshal(w.Body.Bytes(), &resp)
}

func (destinoPorLaPuerta) SincronizarCatalogo(context.Context) (*espejo.RespuestaDelCatalogo, error) {
	return nil, nil
}

type entornoReal struct {
	t        *testing.T
	ctx      context.Context
	pool     *pgxpool.Pool
	codigo   string // la sucursal de ESTA prueba
	branch   uuid.UUID
	ventra   *ventraEnMemoria
	destino  destinoPorLaPuerta
	e        *espejo.Espejo
	registro *bytes.Buffer
	ahora    time.Time
}

func nuevoEntornoReal(t *testing.T) *entornoReal {
	t.Helper()
	dsn := os.Getenv("REPARTO_MOTOR_REAL_DSN")
	if dsn == "" {
		t.Skip("requiere PostgreSQL aislado REPARTO_MOTOR_REAL_DSN")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	t.Cleanup(cancel)
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	var base string
	if err := pool.QueryRow(ctx, "SELECT current_database()").Scan(&base); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(base, "verif") && !strings.Contains(base, "test") && !strings.Contains(base, "prueba") {
		t.Fatalf("la base %q no parece aislada (debe llamarse verif…, …test… o …prueba…): no se toca", base)
	}
	var migrada int
	if err := pool.QueryRow(ctx, "SELECT max(version_id) FROM goose_db_version").Scan(&migrada); err != nil || migrada < 25 {
		t.Fatalf("la base tiene que estar migrada hasta la 00025 (está en %d): %v", migrada, err)
	}

	env := &entornoReal{t: t, ctx: ctx, pool: pool, registro: &bytes.Buffer{},
		codigo: "Z" + strings.ToUpper(uuid.NewString()[:5]),
		ahora:  time.Date(2026, 10, 20, 15, 0, 0, 0, time.UTC), // 10:00 en Cuba, 20/10/2026
		ventra: &ventraEnMemoria{}}
	env.ventra.bases = map[string]string{env.codigo: "slug-" + strings.ToLower(env.codigo)}

	// La sucursal de la prueba, con su punto de partida, y sus datos de Ventra y de PEDIDO.
	if err := pool.QueryRow(ctx, `INSERT INTO branches (name, lat, lng, external_id, origin_configured)
	    VALUES ($1, 20.0, -75.8, $2, true) RETURNING id`, "Sucursal "+env.codigo, env.codigo).Scan(&env.branch); err != nil {
		t.Fatal(err)
	}
	env.exec(`INSERT INTO products (name, weight, units_per_package, sku, sucursal_codigo)
	          VALUES ('CERVEZA PARRANDA 500 ML BLISTER 6U', 2.4, 6, 'PARR0002', $1)`, env.codigo)
	env.exec(`INSERT INTO customers (source, external_id, name, codigo, lat, lng, sucursal_codigo)
	          VALUES ('pedido', $1, 'Cliente en PEDIDO', 'COD-100', 20.05, -75.75, $2)`, "cli-"+env.codigo, env.codigo)
	t.Cleanup(func() {
		bg := context.Background()
		for _, q := range []string{
			`DELETE FROM orders WHERE sucursal_codigo = $1`,
			`DELETE FROM routes WHERE branch_id = (SELECT id FROM branches WHERE external_id = $1)`,
			`DELETE FROM customers WHERE sucursal_codigo = $1`,
			`DELETE FROM products WHERE sucursal_codigo = $1`,
		} {
			_, _ = pool.Exec(bg, q, env.codigo)
		}
	})

	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{{
		Codigo: env.codigo, Nombre: "Sucursal " + env.codigo,
		Almacenes: almacenesDeSantiagoDeAccesos()[0].Almacenes,
	}}})

	// El servidor y el espejo, con la base de verdad (un pool de verdad: la carrera lo necesita).
	t.Setenv("DATABASE_URL", dsn)
	t.Setenv("JWT_SECRET", secretoTab)
	t.Setenv("SERVICE_API_KEY", claveDeServicioDePrueba)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatal(err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	almacen, err := store.Abrir(ctx, &config.Config{DatabaseURL: dsn, PoolMaxConns: 16, PoolMinConns: 1, PoolMaxIdleTime: time.Minute})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(almacen.Cerrar)
	porteria := alcance.NuevaPorteria(almacen, reg)
	s := NuevoServidor(cfg, reg, porteria, auth.NuevoVerificador([]byte(secretoTab)), nil)
	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	s.rutasCotizacion(rt, []httpx.Medio{s.verif.Exigir, s.porteria.Exigir}, []httpx.Medio{s.verif.Exigir, auth.ExigirAdmin, s.porteria.Exigir})
	env.destino = destinoPorLaPuerta{h: rt.Handler()}

	acotado, err := porteria.Resolver(ctx, &auth.Usuario{ID: "servicio:espejo", Nombre: "espejo", Rol: "SUPER ADMIN"}, "")
	if err != nil {
		t.Fatal(err)
	}
	base2 := espejo.BaseDelReparto{Acotado: acotado}
	o := espejo.PorDefecto()
	o.Clave, o.Fuente = "k", espejo.FuenteDeFactura
	env.e = &espejo.Espejo{
		Opciones: o, Reparto: env.destino, Base: base2, BaseF: base2, Facturas: env.ventra,
		Reg:   slog.New(slog.NewTextHandler(env.registro, nil)),
		Ahora: func() time.Time { return env.ahora },
	}
	return env
}

func (env *entornoReal) exec(sql string, args ...any) {
	env.t.Helper()
	if _, err := env.pool.Exec(env.ctx, sql, args...); err != nil {
		env.t.Fatalf("%q: %v", sql, err)
	}
}

func (env *entornoReal) entero(sql string, args ...any) int {
	env.t.Helper()
	var n int
	if err := env.pool.QueryRow(env.ctx, sql, args...).Scan(&n); err != nil {
		env.t.Fatalf("%q: %v", sql, err)
	}
	return n
}

func (env *entornoReal) ciclo() int { return env.e.CicloDeFacturas(env.ctx) }

func (env *entornoReal) filasDelFolio(folio string) int {
	// Por el folio NORMALIZADO: la fila adoptada guarda el folio de la factura tal cual lo escribieron.
	return env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1 AND folio_normalizado(folio) = folio_normalizado($2::text)`, env.codigo, folio)
}

// ex es el external_id de la entrega de factura de un folio: `factura:<SUC>:<folio normalizado>`.
func (env *entornoReal) ex(folio string) string {
	return alcance.PrefijoDeFactura + env.codigo + ":" + alcance.FolioNormalizado(folio)
}

func (env *entornoReal) hay(externalID string) bool {
	return env.entero(`SELECT count(*) FROM orders WHERE source = 'pedido' AND external_id = $1`, externalID) == 1
}

func (env *entornoReal) idDe(externalID string) uuid.UUID {
	env.t.Helper()
	var id uuid.UUID
	if err := env.pool.QueryRow(env.ctx, `SELECT id FROM orders WHERE source = 'pedido' AND external_id = $1`, externalID).Scan(&id); err != nil {
		env.t.Fatalf("no hay fila con external_id %q: %v", externalID, err)
	}
	return id
}

// pedidoDePedido es un pedido tal como lo da PEDIDO, con su cliente geolocalizado.
func (env *entornoReal) pedidoDePedido(id, folio string) espejo.PedidoDeFuera {
	lat, lng := 20.05, -75.75
	uds, packs, peso := 90.0, 15.0, 2.4
	return espejo.PedidoDeFuera{
		ID: id, Folio: folio, Fecha: "2026-10-19T14:00:00Z", UpdatedAt: "2026-10-19T14:00:00Z",
		SucursalCodigo: env.codigo,
		Cliente:        &espejo.ClienteDelPedido{Nombre: "Cliente de PEDIDO", Latitud: &lat, Longitud: &lng},
		Items:          []espejo.RenglonDeFuera{{Codigo: "PARR0002", Producto: "CERVEZA", Descripcion: "CERVEZA", Unidades: &uds, Packs: &packs, PesoKg: &peso}},
		FacturaEstado:  "igual", FacturaNumero: "9999", RequiereDomicilio: true,
	}
}

// guardarPedidos manda pedidos por la puerta y devuelve, por id, su resultado.
func (env *entornoReal) guardarPedidos(ps ...espejo.PedidoDeFuera) map[string]espejo.ResultadoDelPedido {
	env.t.Helper()
	r, err := env.destino.Cotizar(env.ctx, ps)
	if err != nil {
		env.t.Fatalf("la puerta falló: %v", err)
	}
	salida := map[string]espejo.ResultadoDelPedido{}
	for _, res := range r.Results {
		if res.Ref != nil {
			salida[*res.Ref] = res
		}
	}
	return salida
}

// enRuta mete una fila en una ruta, como lo hace el armador.
func (env *entornoReal) enRuta(pedido uuid.UUID, orden int) uuid.UUID {
	env.t.Helper()
	var ruta uuid.UUID
	if err := env.pool.QueryRow(env.ctx, `INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng, total_distance, optimized)
	    VALUES ($1, 'planned', 'ruta de prueba', 20.0, -75.8, 1, false) RETURNING id`, env.branch).Scan(&ruta); err != nil {
		env.t.Fatal(err)
	}
	env.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = $3 WHERE id = $1`, pedido, ruta, orden)
	return ruta
}

// --------------------------------------------------------------------------- la adopción

func TestMotorReal_FacturaAdoptaAlPedidoDePedidoYConservaSuRutaYSuPunto(t *testing.T) {
	env := nuevoEntornoReal(t)
	folio := "PXX26-261019-0100"
	suc := env.codigo

	// 1. El pedido entra por PEDIDO, va en una ruta y el logístico le puso el punto a mano.
	if r := env.guardarPedidos(env.pedidoDePedido("ped-100", folio)); !r["ped-100"].Entro() {
		t.Fatalf("el pedido de PEDIDO no entró: %+v", r)
	}
	if got := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1 AND folio = $2 AND operation_number = $2`, suc, folio); got != 1 {
		t.Fatalf("la fila de PEDIDO guarda folio = operation_number: %d", got)
	}
	id := env.idDe("ped-100")
	ruta := env.enRuta(id, 2)
	env.exec(`UPDATE orders SET punto_manual = true, end_lat = 20.5, end_lng = -75.5, end_address = 'a mano' WHERE id = $1`, id)

	// 2. Llega la factura del mismo pedido.
	env.ventra.poner(facturaDeMentira("100", "2026-10-19", folio))
	if got := env.ciclo(); got != 1 {
		t.Fatalf("el ciclo tenía que guardar 1 entrega; guardó %d\n%s", got, env.registro.String())
	}

	// 3. UNA sola fila, LA MISMA: id, ruta y orden conservados, ahora con el external_id de factura.
	if got := env.filasDelFolio(folio); got != 1 {
		t.Fatalf("hay %d filas con ese folio y tiene que haber 1: se duplicó", got)
	}
	if got := env.idDe(env.ex(folio)); got != id {
		t.Fatalf("la adopción tiene que conservar el id: era %s y ahora es %s", id, got)
	}
	if env.hay("ped-100") {
		t.Error("el external_id viejo de PEDIDO ya no existe: la fila lo cambió")
	}
	var rutaDespues *uuid.UUID
	var orden *int32
	var manual bool
	var endLat *float64
	if err := env.pool.QueryRow(env.ctx, `SELECT route_id, stop_order, punto_manual, end_lat FROM orders WHERE id = $1`, id).
		Scan(&rutaDespues, &orden, &manual, &endLat); err != nil {
		t.Fatal(err)
	}
	if rutaDespues == nil || *rutaDespues != ruta || orden == nil || *orden != 2 {
		t.Errorf("la ruta y el orden son del reparto y la adopción no los toca: %v %v", rutaDespues, orden)
	}
	if !manual || endLat == nil || *endLat != 20.5 {
		t.Errorf("el punto puesto a mano se conserva también al adoptar: %v %v", manual, endLat)
	}

	// 4. Y los campos del mapeo se pusieron encima.
	var conduce, facturaNum, estadoF, origen, almacen, nombre string
	var domicilio float64
	var requiere, archivado bool
	var estado, costo, comprometida any
	if err := env.pool.QueryRow(env.ctx, `SELECT operation_number, factura_numero, factura_estado::text, items_origen, almacen_salida_codigo,
	       customer_name, factura_domicilio, requiere_domicilio, archivado, estado, pedido_costo, fecha_comprometida
	       FROM orders WHERE id = $1`, id).Scan(&conduce, &facturaNum, &estadoF, &origen, &almacen, &nombre, &domicilio,
		&requiere, &archivado, &estado, &costo, &comprometida); err != nil {
		t.Fatal(err)
	}
	if conduce != "100" || facturaNum != "100" || estadoF != "igual" || origen != "factura" || almacen != "2" ||
		nombre != "Cliente Inventado 100" || domicilio != 0.29 || !requiere || archivado ||
		estado != nil || costo != nil || comprometida != nil {
		t.Errorf("el mapeo no se aplicó entero: %q %q %q %q %q %q %v %v %v %v %v %v",
			conduce, facturaNum, estadoF, origen, almacen, nombre, domicilio, requiere, archivado, estado, costo, comprometida)
	}
	// Los renglones: 15 B = 15 empaques y 90 unidades, con el peso de `products` (2,4 × 15 = 36).
	var packs, qty, pesoLinea float64
	var origenPeso string
	if err := env.pool.QueryRow(env.ctx, `SELECT packs, quantity, peso_linea_kg, origen_peso FROM order_items WHERE order_id = $1`, id).
		Scan(&packs, &qty, &pesoLinea, &origenPeso); err != nil {
		t.Fatalf("renglones: %v", err)
	}
	if packs != 15 || qty != 90 || math.Abs(pesoLinea-36) > 1e-9 || origenPeso != "pedido" {
		t.Errorf("15 B × 6 = 90 uds, 36 kg: salió packs=%v uds=%v kg=%v (%s)", packs, qty, pesoLinea, origenPeso)
	}
	var peso float64
	_ = env.pool.QueryRow(env.ctx, `SELECT weight FROM orders WHERE id = $1`, id).Scan(&peso)
	if math.Abs(peso-36) > 1e-9 {
		t.Errorf("el peso del pedido es el de la cascada: 36; salió %v", peso)
	}
}

func TestMotorReal_UnPedidoDePedidoQueLlegaDespuesDeAdoptadoNoCreaOtraFila(t *testing.T) {
	env := nuevoEntornoReal(t)
	folio := "PXX26-261019-0200"
	env.ventra.poner(facturaDeMentira("200", "2026-10-19", folio))
	env.ciclo()
	if !env.hay(env.ex(folio)) {
		t.Fatalf("la entrega de factura no se creó\n%s", env.registro.String())
	}

	// PEDIDO manda el mismo pedido (repaso, aviso, lo que sea).
	r := env.guardarPedidos(env.pedidoDePedido("ped-200", folio))["ped-200"]
	if r.Entro() {
		t.Fatalf("el pedido de PEDIDO NO se guarda: ya es una entrega de factura")
	}
	if r.Reason != espejo.MotivoYaAdoptado {
		t.Errorf("y se dice con su motivo, que no es un fallo: %q", r.Reason)
	}
	if got := env.filasDelFolio(folio); got != 1 {
		t.Fatalf("hay %d filas con ese folio: se duplicó", got)
	}
	if env.hay("ped-200") {
		t.Error("no puede haber fila con el external_id de PEDIDO")
	}
}

func TestMotorReal_UnPedidoDePedidoSinFacturaSigueEntrandoComoSiempre(t *testing.T) {
	// La otra mitad: lo de PEDIDO no se rompe cuando no hay factura de por medio.
	env := nuevoEntornoReal(t)
	r := env.guardarPedidos(env.pedidoDePedido("ped-300", "PXX-300"))["ped-300"]
	if !r.Entro() || !env.hay("ped-300") {
		t.Fatalf("un pedido sin factura entra normal: %+v", r)
	}
	// Y el mismo pedido otra vez es una actualización, no un duplicado ni un "ya adoptado".
	if r := env.guardarPedidos(env.pedidoDePedido("ped-300", "PXX-300"))["ped-300"]; r.Reason == espejo.MotivoYaAdoptado {
		t.Errorf("repetir un pedido de PEDIDO no es 'ya adoptado': %+v", r)
	}
	if got := env.filasDelFolio("PXX-300"); got != 1 {
		t.Fatalf("hay %d filas", got)
	}
}

func TestMotorReal_DosFoliosDeSucursalesDistintasNoSeAdoptanEntreSi(t *testing.T) {
	// Un folio es único DENTRO de su sucursal, no en la casa: la adopción mira (sucursal, folio).
	env := nuevoEntornoReal(t)
	otra := "Y" + env.codigo[1:]
	env.exec(`INSERT INTO branches (name, lat, lng, external_id, origin_configured) VALUES ($1, 20.0, -75.8, $2, true)`, "Otra "+otra, otra)
	t.Cleanup(func() {
		_, _ = env.pool.Exec(context.Background(), `DELETE FROM orders WHERE sucursal_codigo = $1`, otra)
	})
	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: env.codigo, Almacenes: almacenesDeSantiagoDeAccesos()[0].Almacenes},
		{Codigo: otra, Almacenes: almacenesDeSantiagoDeAccesos()[0].Almacenes},
	}})
	delOtra := env.pedidoDePedido("ped-otra", "MISMO-FOLIO")
	delOtra.SucursalCodigo = otra
	env.guardarPedidos(delOtra)

	env.ventra.poner(facturaDeMentira("1", "2026-10-19", "MISMO-FOLIO"))
	env.ciclo()
	if !env.hay("ped-otra") {
		t.Error("el pedido de la OTRA sucursal con el mismo folio no se toca")
	}
	if !env.hay(env.ex("MISMO-FOLIO")) {
		t.Errorf("y la factura de esta crea su propia fila\n%s", env.registro.String())
	}
}

// --------------------------------------------------------------------------- la carrera

func TestMotorReal_DosCiclosAlaVezNoDuplican(t *testing.T) {
	env := nuevoEntornoReal(t)
	const folios = 40
	var inicio sync.WaitGroup
	var fin sync.WaitGroup
	salida := make(chan error, folios*4)
	arranque := make(chan struct{})

	for i := 0; i < folios; i++ {
		folio := fmt.Sprintf("CARRERA-%03d", i)
		desdePedido := env.pedidoDePedido("ped-"+folio, folio)
		var desdeFactura espejo.PedidoDeFuera
		{
			// La entrega de factura TAL COMO la arma el mapeo del espejo.
			// Con el folio escrito en MINÚSCULAS: el candado también es del folio normalizado, y si la
			// factura y el pedido tomaran candados distintos la carrera los duplicaría.
			f := facturaDeMentira(fmt.Sprintf("%d", 5000+i), "2026-10-19", strings.ToLower(folio))
			en := espejo.AgruparPorFolio(env.codigo, []espejo.FacturaDeVentra{f})[0]
			desdeFactura, _ = en.APedido(espejo.ContextoDeMapeo{})
		}
		for _, p := range []espejo.PedidoDeFuera{desdePedido, desdeFactura, desdePedido, desdeFactura} {
			inicio.Add(1)
			fin.Add(1)
			go func() {
				defer fin.Done()
				inicio.Done()
				<-arranque // todos a la vez
				_, err := env.destino.Cotizar(env.ctx, []espejo.PedidoDeFuera{p})
				salida <- err
			}()
		}
	}
	inicio.Wait()
	close(arranque)
	fin.Wait()
	close(salida)
	for err := range salida {
		if err != nil {
			t.Fatalf("una de las peticiones falló: %v", err)
		}
	}

	for i := 0; i < folios; i++ {
		folio := fmt.Sprintf("CARRERA-%03d", i)
		if got := env.filasDelFolio(folio); got != 1 {
			t.Errorf("el folio %s tiene %d filas: la carrera lo duplicó (tiene que haber 1)", folio, got)
		}
	}
	if got := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, env.codigo); got != folios {
		t.Errorf("tenía que haber %d filas y hay %d", folios, got)
	}
}

// --------------------------------------------------------------------------- el repaso idéntico

func TestMotorReal_UnRepasoIdenticoNoReescribeNada(t *testing.T) {
	env := nuevoEntornoReal(t)
	env.ventra.poner(facturaDeMentira("400", "2026-10-19", "PXX-400"), facturaDeMentira("401", "2026-10-19", ""))
	env.ciclo()

	foto := func() string {
		var s string
		if err := env.pool.QueryRow(env.ctx, `SELECT string_agg(external_id || ':' || xmin::text || ':' || updated_at::text, '|' ORDER BY external_id)
		   FROM orders WHERE sucursal_codigo = $1`, env.codigo).Scan(&s); err != nil {
			t.Fatal(err)
		}
		return s
	}
	items := func() string {
		var s string
		if err := env.pool.QueryRow(env.ctx, `SELECT string_agg(i.id::text, '|' ORDER BY i.id) FROM order_items i
		   JOIN orders o ON o.id = i.order_id WHERE o.sucursal_codigo = $1`, env.codigo).Scan(&s); err != nil {
			t.Fatal(err)
		}
		return s
	}
	antes, itemsAntes := foto(), items()
	if antes == "" || strings.Count(antes, "|") != 1 {
		t.Fatalf("tenían que ser dos filas: %q", antes)
	}
	time.Sleep(20 * time.Millisecond) // para que un updated_at reescrito se note
	env.ciclo()
	env.ciclo()
	if despues := foto(); despues != antes {
		t.Errorf("un repaso idéntico NO reescribe las filas (xmin y updated_at cambian si se tocan):\n antes: %s\n ahora: %s", antes, despues)
	}
	if despues := items(); despues != itemsAntes {
		t.Errorf("ni los renglones: se borran y se reinsertan si no se comparan\n antes: %s\n ahora: %s", itemsAntes, despues)
	}

	// Y si de verdad cambia algo (el conduce gana otra factura), SÍ se actualiza.
	env.ventra.poner(facturaDeMentira("400", "2026-10-19", "PXX-400"), facturaDeMentira("402", "2026-10-19", "PXX-400"),
		facturaDeMentira("401", "2026-10-19", ""))
	env.ciclo()
	var conduce string
	_ = env.pool.QueryRow(env.ctx, `SELECT operation_number FROM orders WHERE external_id = $1`, env.ex("PXX-400")).Scan(&conduce)
	if conduce != "400, 402" {
		t.Errorf("la entrega ganó una segunda factura y el conduce tiene que decirlo: %q", conduce)
	}
	if got := env.filasDelFolio("PXX-400"); got != 1 {
		t.Errorf("sigue siendo UNA entrega: %d filas", got)
	}
}

func TestMotorReal_SinCoordenadasLaEntregaSeGuardaYConCoordenadasLasLleva(t *testing.T) {
	env := nuevoEntornoReal(t)
	conPunto := facturaDeMentira("500", "2026-10-19", "PXX-500")
	conPunto.ReferenciaDelCliente = "cod-100" // el código del cliente sembrado, en minúsculas
	sinPunto := facturaDeMentira("501", "2026-10-19", "PXX-501")
	sinPunto.ReferenciaDelCliente = "NADIE"
	env.ventra.poner(conPunto, sinPunto)
	env.ciclo()

	var lat, lng, km *float64
	if err := env.pool.QueryRow(env.ctx, `SELECT lat, lng, delivery_distance_km FROM orders WHERE external_id = $1`, env.ex("PXX-500")).
		Scan(&lat, &lng, &km); err != nil {
		t.Fatal(err)
	}
	if lat == nil || *lat != 20.05 || lng == nil || km == nil || *km <= 0 {
		t.Errorf("con cliente en el espejo, las coordenadas y la distancia salen de él: %v %v %v", lat, lng, km)
	}
	if err := env.pool.QueryRow(env.ctx, `SELECT lat, lng, delivery_distance_km FROM orders WHERE external_id = $1`, env.ex("PXX-501")).
		Scan(&lat, &lng, &km); err != nil {
		t.Fatalf("la entrega sin punto SE GUARDA: %v\n%s", err, env.registro.String())
	}
	if lat != nil || lng != nil || km != nil {
		t.Errorf("sin cliente en el espejo: sin coordenadas y sin distancia: %v %v %v", lat, lng, km)
	}
	if !strings.Contains(env.registro.String(), "SIN coordenadas") {
		t.Errorf("y el ciclo lo DICE:\n%s", env.registro.String())
	}
	// Una entrega sin punto es visible en la lista de Pedidos (que es donde se ubica a mano).
	if got := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1 AND end_lat IS NULL`, env.codigo); got != 1 {
		t.Errorf("tiene que haber una entrega sin punto visible: %d", got)
	}
}

// --------------------------------------------------------------------------- la retirada

// sembrarEntregas deja guardadas, por el recorrido de verdad, las entregas que pide el caso.
func (env *entornoReal) sembrarEntregas(fs ...espejo.FacturaDeVentra) {
	env.t.Helper()
	env.ventra.poner(fs...)
	env.ciclo()
	for _, f := range fs {
		if f.Pedido != "" && !env.hay(env.ex(f.Pedido)) {
			env.t.Fatalf("no se guardó la entrega %s\n%s", f.Pedido, env.registro.String())
		}
	}
}

func TestMotorReal_LaRetiradaRespetaSusGuardas(t *testing.T) {
	env := nuevoEntornoReal(t)
	suc := env.codigo
	ex := env.ex

	// Hoy es el 20/10 (Cuba). El repaso normal son los 17-20/10 y el barrido, del 21/08 al 20/10; pero
	// el repaso se ENSANCHA hasta la entrega abierta más antigua (con tope en el histórico, G2), y
	// aquí C (01/06) está abierta: el repaso llega hasta el tope, 21/08.
	//   A  19/10  en el repaso, sin ruta         -> SE RETIRA cuando ya no viene
	//   R  19/10  en el repaso, EN UNA RUTA      -> se deja y se dice
	//   D  19/10  en el repaso, con RESULTADO    -> se deja
	//   B  05/10  abierta: el repaso ensanchado la alcanza -> SE RETIRA también
	//   C  01/06  fuera del tope: de TODA ventana -> nunca se toca
	env.sembrarEntregas(
		facturaDeMentira("1", "2026-10-19", "FA"), facturaDeMentira("2", "2026-10-19", "FR"),
		facturaDeMentira("3", "2026-10-19", "FD"), facturaDeMentira("4", "2026-10-05", "FB"),
		facturaDeMentira("5", "2026-06-01", "FC"))
	env.enRuta(env.idDe(ex("FR")), 1)
	env.exec(`UPDATE orders SET resultado = 'entregado', delivered_at = now() WHERE id = $1`, env.idDe(ex("FD")))
	todas := func() int { return env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, suc) }
	if todas() != 5 {
		t.Fatalf("la siembra dejó %d filas y tenían que ser 5", todas())
	}

	// GUARDA: Ventra falla. Un fallo no es una anulación.
	env.ventra.mu.Lock()
	env.ventra.fallo = fmt.Errorf("Ventra 500")
	env.ventra.mu.Unlock()
	env.ciclo()
	if todas() != 5 {
		t.Fatalf("con Ventra caído NO se retira nada: quedan %d de 5", todas())
	}

	// GUARDA: Ventra contesta VACÍO (una base caída contesta así, sin error) y hay entregas en la
	// ventana. Es un error, no una anulación de todo.
	env.ventra.poner()
	env.registro.Reset()
	env.ciclo()
	if todas() != 5 {
		t.Fatalf("con la respuesta vacía NO se retira nada: quedan %d de 5\n%s", todas(), env.registro.String())
	}
	if !strings.Contains(env.registro.String(), "se toma por un ERROR") {
		t.Errorf("y se dice:\n%s", env.registro.String())
	}

	// AHORA SÍ: Ventra contesta con otra factura y ya no trae A, R, D, B ni C. Es un REPASO
	// (el barrido de hoy ya se hizo), ensanchado por C hasta el tope: 21/08..20/10.
	env.ventra.poner(facturaDeMentira("6", "2026-10-19", "FE"))
	env.registro.Reset()
	env.ciclo()
	if env.hay(ex("FA")) {
		t.Error("A estaba en la ventana, sin ruta y ya no viene: se retira")
	}
	if !env.hay(ex("FR")) {
		t.Error("R va en una ruta: NO se borra lo que ya está en el camión")
	}
	if !env.hay(ex("FD")) {
		t.Error("D tiene resultado: no se borra")
	}
	if env.hay(ex("FB")) {
		t.Error("B (05/10) cae dentro de la ventana ensanchada del repaso, sin ruta y ya no viene: se retira")
	}
	if !env.hay(ex("FC")) {
		t.Error("C (01/06) cae FUERA de la ventana consultada (más allá del tope): no se puede juzgar y no se toca")
	}
	if !env.hay(ex("FE")) {
		t.Error("y la nueva entra")
	}
	// R (ruta) y D (resultado) son las dos que se dejan.
	if !strings.Contains(env.registro.String(), "anuladasConRuta=2") || !strings.Contains(env.registro.String(), "ANULADAS que ya van en una ruta") {
		t.Errorf("la anulada con ruta se cuenta y se dice:\n%s", env.registro.String())
	}
	if !strings.Contains(env.registro.String(), "retiradas=2") {
		t.Errorf("y las retiradas se cuentan:\n%s", env.registro.String())
	}

	// Pasadas 24 horas toca el BARRIDO: ventana 22/08..21/10. C (01/06) sigue fuera de toda
	// ventana. R y D se siguen dejando.
	env.ahora = env.ahora.Add(25 * time.Hour)
	env.ciclo()
	if !env.hay(ex("FC")) {
		t.Error("C está fuera de TODA ventana: no se toca jamás")
	}
	if !env.hay(ex("FR")) || !env.hay(ex("FD")) {
		t.Error("R y D se siguen dejando")
	}

	// Lo retirado deja su lápida para que los aparatos lo quiten.
	if got := env.entero(`SELECT count(*) FROM orders_fuera_de_alcance WHERE branch_id = $1 AND motivo = 'borrado'`, env.branch); got != 2 {
		t.Errorf("A y B retiradas dejan 2 lápidas; hay %d", got)
	}
}

func TestMotorReal_LaRetiradaNoTocaLoQueNoEsDeFactura(t *testing.T) {
	// Un pedido de PEDIDO (external_id sin prefijo) dentro de la ventana, sin ruta y que "no viene
	// en Ventra" no se retira: no es de factura y Ventra no tiene por qué traerlo.
	env := nuevoEntornoReal(t)
	env.guardarPedidos(env.pedidoDePedido("ped-600", "PXX-600"))
	env.sembrarEntregas(facturaDeMentira("7", "2026-10-19", "FF"))
	env.ventra.poner(facturaDeMentira("8", "2026-10-19", "FG"))
	env.ciclo()
	if !env.hay("ped-600") {
		t.Fatal("lo que no es de factura no se retira por una respuesta de Ventra")
	}
	if env.hay(env.ex("FF")) {
		t.Error("y la de factura que ya no viene, sí")
	}
}

func TestMotorReal_ElBorradoTieneSuPropiaGuarda(t *testing.T) {
	// Entre que se LEE la lista de las que ya no vienen y se BORRA, una ruta puede haber recogido
	// una (el logístico no espera a nadie). La guarda de quien llama no lo ve: tiene que estar en
	// el propio DELETE. Aquí se le pide borrar, directamente, lo que NO se puede borrar.
	env := nuevoEntornoReal(t)
	ex := env.ex
	env.sembrarEntregas(facturaDeMentira("1", "2026-10-19", "GA"), facturaDeMentira("2", "2026-10-19", "GB"),
		facturaDeMentira("3", "2026-10-19", "GC"), facturaDeMentira("4", "2026-10-19", "GD"))
	env.guardarPedidos(env.pedidoDePedido("ped-700", "PXX-700"))
	env.enRuta(env.idDe(ex("GA")), 1)
	env.exec(`UPDATE orders SET resultado = 'devuelto' WHERE id = $1`, env.idDe(ex("GB")))
	env.exec(`UPDATE orders SET delivered_at = now() WHERE id = $1`, env.idDe(ex("GC")))

	ids := []uuid.UUID{env.idDe(ex("GA")), env.idDe(ex("GB")), env.idDe(ex("GC")), env.idDe(ex("GD")), env.idDe("ped-700")}
	n, err := env.e.BaseF.RetirarEntregasDeFactura(env.ctx, ids)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 || env.hay(ex("GD")) {
		t.Errorf("SOLO la libre (GD) se borra; borró %d y GD sigue: %v", n, env.hay(ex("GD")))
	}
	for _, e := range []string{ex("GA"), ex("GB"), ex("GC"), "ped-700"} {
		if !env.hay(e) {
			t.Errorf("%s no se podía borrar (ruta, resultado, entrega o no es de factura) y se borró", e)
		}
	}
}

// --------------------------------------------------------------------------- auditoría del 20/10/2026

// puntoYKm lee lo que el armador necesita de una fila.
type puntoYKm struct {
	lat, lng, endLat, endLng, km *float64
	dir                          *string
}

func (env *entornoReal) puntoYKm(id uuid.UUID) (p puntoYKm) {
	env.t.Helper()
	if err := env.pool.QueryRow(env.ctx, `SELECT lat, lng, end_lat, end_lng, delivery_distance_km, end_address FROM orders WHERE id = $1`, id).
		Scan(&p.lat, &p.lng, &p.endLat, &p.endLng, &p.km, &p.dir); err != nil {
		env.t.Fatal(err)
	}
	return
}

func (env *entornoReal) xmin(externalID string) string {
	env.t.Helper()
	var x string
	if err := env.pool.QueryRow(env.ctx, `SELECT xmin::text FROM orders WHERE source = 'pedido' AND external_id = $1`, externalID).Scan(&x); err != nil {
		env.t.Fatal(err)
	}
	return x
}

// G1: la adopción NO pierde las coordenadas ni el km aunque la factura no traiga punto.
func TestMotorReal_LaAdopcionNoPierdeElPuntoNiElKmSiLaFacturaNoTieneCliente(t *testing.T) {
	env := nuevoEntornoReal(t)
	folio := "PXX26-261019-0110"
	ped := env.pedidoDePedido("ped-110", folio)
	ped.Direccion = "Calle del cliente de PEDIDO"
	if r := env.guardarPedidos(ped); !r["ped-110"].Entro() {
		t.Fatalf("el pedido de PEDIDO no entró: %+v", r)
	}
	id := env.idDe("ped-110")
	antes := env.puntoYKm(id)
	if antes.endLat == nil || *antes.endLat != 20.05 || antes.km == nil || *antes.km <= 0 || antes.dir == nil {
		t.Fatalf("la siembra tenía que dejar punto, km y dirección: %+v", antes)
	}
	ruta := env.enRuta(id, 3)

	// Llega la factura del MISMO pedido; su cliente no está en `customers` ni por código ni por nombre.
	f := facturaDeMentira("110", "2026-10-19", folio)
	f.ReferenciaDelCliente = "CLIENTE-QUE-NO-EXISTE"
	env.ventra.poner(f)
	if got := env.ciclo(); got != 1 {
		t.Fatalf("el ciclo tenía que guardar 1; guardó %d\n%s", got, env.registro.String())
	}
	if got := env.idDe(env.ex(folio)); got != id {
		t.Fatalf("la adopción conserva el id: %s -> %s", id, got)
	}
	d := env.puntoYKm(id)
	if d.endLat == nil || d.endLng == nil || d.lat == nil || d.lng == nil ||
		*d.endLat != *antes.endLat || *d.endLng != *antes.endLng || *d.lat != *antes.lat || *d.lng != *antes.lng {
		t.Fatalf("la adopción BORRÓ el punto de una parada que va en una ruta: antes lat/lng=%v/%v, ahora %v/%v end=%v/%v",
			*antes.lat, *antes.lng, d.lat, d.lng, d.endLat, d.endLng)
	}
	if d.km == nil || *d.km != *antes.km || d.dir == nil || *d.dir != *antes.dir {
		t.Fatalf("y el km y la dirección del punto se conservan con él: km %v -> %v, dir %v -> %v", *antes.km, d.km, *antes.dir, d.dir)
	}
	if env.entero(`SELECT count(*) FROM orders WHERE id = $1 AND route_id = $2 AND end_lat IS NOT NULL`, id, ruta) != 1 {
		t.Fatal("la parada sigue en su ruta y el armador la sigue viendo (end_lat IS NOT NULL)")
	}
	// Lo demás sí lo puso la factura (la adopción no es un no-op).
	var cliente string
	_ = env.pool.QueryRow(env.ctx, `SELECT customer_name FROM orders WHERE id = $1`, id).Scan(&cliente)
	if cliente != "Cliente Inventado 110" {
		t.Errorf("el mapeo de la factura se aplicó igual: %q", cliente)
	}
	// Y los repasos siguientes no reescriben la fila (el WHERE usa los mismos valores efectivos).
	x := env.xmin(env.ex(folio))
	env.ciclo()
	env.ciclo()
	if env.xmin(env.ex(folio)) != x {
		t.Error("un repaso idéntico reescribió la fila: el WHERE del upsert compara contra NULL y no contra el punto conservado")
	}

	// Una entrega NUEVA de factura sin punto se guarda sin punto, y cuando el cliente aparece, lo gana.
	solo := facturaDeMentira("111", "2026-10-19", "PXX-SIN-PUNTO")
	solo.ReferenciaDelCliente = "NADIE"
	env.ventra.poner(f, solo)
	env.ciclo()
	if n := env.puntoYKm(env.idDe(env.ex("PXX-SIN-PUNTO"))); n.endLat != nil || n.lat != nil || n.km != nil {
		t.Errorf("una entrega nueva sin punto se guarda SIN punto: %+v", n)
	}
	solo.ReferenciaDelCliente = "COD-100"
	env.ventra.poner(f, solo)
	env.ciclo()
	if n := env.puntoYKm(env.idDe(env.ex("PXX-SIN-PUNTO"))); n.endLat == nil || *n.endLat != 20.05 || n.km == nil {
		t.Errorf("y cuando su cliente aparece en el espejo, el punto entra: %+v", n)
	}
}

// G3: el folio se compara normalizado.
func TestMotorReal_LaAdopcionReconoceElFolioAunqueSeEscribaDistinto(t *testing.T) {
	for _, escrito := range []string{"pxx-900", "'PXX-900", "PXX - 900", " PXX-900 ", "PXX-900 ", "Pxx_900"} {
		t.Run(escrito, func(t *testing.T) {
			env := nuevoEntornoReal(t)
			if r := env.guardarPedidos(env.pedidoDePedido("ped-900", "PXX-900")); !r["ped-900"].Entro() {
				t.Fatalf("el pedido de PEDIDO no entró: %+v", r)
			}
			id := env.idDe("ped-900")
			env.ventra.poner(facturaDeMentira("900", "2026-10-19", escrito))
			env.ciclo()
			if n := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, env.codigo); n != 1 {
				t.Fatalf("la factura con folio %q DUPLICÓ la fila de PEDIDO PXX-900: hay %d filas\n%s", escrito, n, env.registro.String())
			}
			if got := env.idDe(env.ex("PXX-900")); got != id {
				t.Fatalf("la factura %q tenía que adoptar la fila de PEDIDO (mismo id)", escrito)
			}
			if env.hay("ped-900") {
				t.Error("y la fila cambia su external_id")
			}
		})
	}
}

func TestMotorReal_UnPedidoDePedidoYaAdoptadoSeReconoceConElFolioEscritoDistinto(t *testing.T) {
	// El «ya adoptado» del lado de PEDIDO (`ExisteEntregaDeFacturaDelFolio`) también normaliza.
	for _, escrito := range []string{"pxx-901", "'PXX-901", "PXX - 901"} {
		t.Run(escrito, func(t *testing.T) {
			env := nuevoEntornoReal(t)
			env.ventra.poner(facturaDeMentira("901", "2026-10-19", escrito))
			env.ciclo()
			r := env.guardarPedidos(env.pedidoDePedido("ped-901", "PXX-901"))["ped-901"]
			if r.Entro() || r.Reason != espejo.MotivoYaAdoptado {
				t.Errorf("el pedido de PEDIDO PXX-901 ya es la entrega de factura %q: %+v", escrito, r)
			}
			if n := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, env.codigo); n != 1 {
				t.Errorf("hay %d filas y tiene que haber 1", n)
			}
		})
	}
}

func TestMotorReal_UnPrefijoDistintoNoEsElMismoFolio(t *testing.T) {
	env := nuevoEntornoReal(t)
	env.guardarPedidos(env.pedidoDePedido("ped-902", "PXX-902"))
	env.ventra.poner(facturaDeMentira("902", "2026-10-19", "PXY-902"))
	env.ciclo()
	if n := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, env.codigo); n != 2 {
		t.Fatalf("PXX-902 y PXY-902 son dos pedidos y tiene que haber 2 filas; hay %d", n)
	}
	if !env.hay("ped-902") || !env.hay(env.ex("PXY-902")) {
		t.Error("cada uno conserva lo suyo")
	}
	// Un folio que normaliza a vacío no adopta a nadie (los dos «---» no son el mismo pedido). El mapeo
	// ya los separa (una factura con «---» no tiene folio), así que se manda por la puerta una entrega
	// de factura que SÍ lo trae, como la podría mandar cualquier otro cliente de la puerta.
	env.guardarPedidos(env.pedidoDePedido("ped-guiones", "---"))
	en := espejo.AgruparPorFolio(env.codigo, []espejo.FacturaDeVentra{facturaDeMentira("903", "2026-10-19", "")})[0]
	p, _ := en.APedido(espejo.ContextoDeMapeo{})
	p.FolioDelPedido = "---"
	env.guardarPedidos(p)
	if !env.hay("ped-guiones") {
		t.Error("«---» no es un folio: la entrega de factura no adopta la fila de PEDIDO que también lo lleva")
	}
	if env.hay(p.ID) == false {
		t.Error("y se guarda como entrega propia")
	}
	if r := env.guardarPedidos(env.pedidoDePedido("ped-guiones-2", "---"))["ped-guiones-2"]; !r.Entro() {
		t.Errorf("ni un pedido de PEDIDO con «---» es «ya adoptado» por la entrega de factura que lleva «---»: %+v", r)
	}
}

func TestMotorReal_FolioNormalizadoGoYSqlDicenLoMismo(t *testing.T) {
	// La función SQL (índice, adopción, «ya adoptado», candado) y su gemela de Go (clave external_id)
	// son DOS escrituras de la misma regla: las ata esta prueba, no un comentario.
	env := nuevoEntornoReal(t)
	entradas := []string{
		"", " ", "PXX-900", "pxx-900", "'PXX-900", "PXX - 900", " PXX-900 ", "PXX_900", "PXX/900", "pXx.900\t",
		"PXX\u00a0900", "ÁÉÍ-1", "ñandú-7", "ß-1", "ſ-1", "İ-1", "ı-1", "９００", "A\u200bB", "---", "0012", "'0012",
		"PJM26-261017-1925", "abc\nDEF", "日本語-12", "ǅ-1", "K-1", // K = signo Kelvin (U+212A)
	}
	for _, e := range entradas {
		var sql string
		if err := env.pool.QueryRow(env.ctx, `SELECT folio_normalizado($1::text)`, e).Scan(&sql); err != nil {
			t.Fatal(err)
		}
		if go_ := alcance.FolioNormalizado(e); go_ != sql {
			t.Errorf("%q: Go dice %q y SQL dice %q", e, go_, sql)
		}
	}
	var nulo *string
	if err := env.pool.QueryRow(env.ctx, `SELECT folio_normalizado(NULL::text)`).Scan(&nulo); err != nil || nulo != nil {
		t.Errorf("NULL se queda NULL (una fila sin folio no casa con nadie): %v %v", nulo, err)
	}
}

// a-adopt-sin-limit: PEDIDO puede repetir un folio; la adopción toma UNA fila (la más antigua).
func TestMotorReal_SiPedidoRepiteElFolioLaAdopcionTomaSoloLaMasAntigua(t *testing.T) {
	env := nuevoEntornoReal(t)
	env.guardarPedidos(env.pedidoDePedido("ped-a", "PXX-777"))
	time.Sleep(5 * time.Millisecond)
	env.guardarPedidos(env.pedidoDePedido("ped-b", "PXX-777"))
	idA := env.idDe("ped-a")

	env.ventra.poner(facturaDeMentira("777", "2026-10-19", "PXX-777"))
	if got := env.ciclo(); got != 1 {
		t.Fatalf("con dos filas de PEDIDO con el mismo folio la adopción tiene que seguir funcionando; guardó %d\n%s", got, env.registro.String())
	}
	if got := env.idDe(env.ex("PXX-777")); got != idA {
		t.Errorf("se adopta la MÁS ANTIGUA (%s) y se adoptó %s", idA, got)
	}
	if !env.hay("ped-b") || env.hay("ped-a") {
		t.Error("la otra fila de PEDIDO se queda como estaba (no se adoptan dos con el mismo external_id)")
	}
}

// --------------------------------------------------------------------------- G2

func (env *entornoReal) conducePesoPacks(externalID string) (conduce string, peso, packs float64) {
	env.t.Helper()
	if err := env.pool.QueryRow(env.ctx, `SELECT o.operation_number, o.weight, coalesce((SELECT sum(i.packs) FROM order_items i WHERE i.order_id = o.id), 0)
	    FROM orders o WHERE o.source = 'pedido' AND o.external_id = $1`, externalID).Scan(&conduce, &peso, &packs); err != nil {
		env.t.Fatalf("no hay entrega %q: %v", externalID, err)
	}
	return
}

func (env *entornoReal) pasa(d time.Duration) { env.ahora = env.ahora.Add(d) }

func TestMotorReal_UnaEntregaConFacturasAAmbosLadosDelBordeNoOscila(t *testing.T) {
	// EL CASO MEDIDO EN LA AUDITORÍA: un folio con la factura 100 del 10/10 y la 101 del 19/10, hoy
	// 20/10. El repaso de 3 días sólo veía la 101 y reescribía la entrega con ella sola; el barrido
	// la dejaba bien y el repaso siguiente la rompía otra vez (conduce «100, 101» -> «101» ->
	// «100, 101»…, peso 72 -> 36).
	env := nuevoEntornoReal(t)
	env.ventra.filtra = true
	folio := "PXX-G2"
	ex := env.ex(folio)
	env.ventra.poner(facturaDeMentira("100", "2026-10-10", folio), facturaDeMentira("101", "2026-10-19", folio))

	env.ciclo() // el primero es barrido: ve las dos
	if c, peso, packs := env.conducePesoPacks(ex); c != "100, 101" || math.Abs(peso-72) > 1e-9 || packs != 30 {
		t.Fatalf("el barrido deja la entrega entera: conduce %q peso %v packs %v", c, peso, packs)
	}
	for i := 1; i <= 6; i++ {
		env.pasa(time.Minute)
		env.ciclo() // repasos
		if c, peso, packs := env.conducePesoPacks(ex); c != "100, 101" || math.Abs(peso-72) > 1e-9 || packs != 30 {
			t.Fatalf("repaso %d: la entrega OSCILA (conduce %q, peso %v, packs %v) y tiene que seguir en «100, 101», 72, 30\n%s",
				i, c, peso, packs, env.registro.String())
		}
	}
	// El repaso se ensanchó hasta la entrega abierta más antigua (10/10).
	ult := env.ventra.pedidas[len(env.ventra.pedidas)-1]
	if !strings.HasSuffix(ult, "2026-10-10..2026-10-20") {
		t.Errorf("el repaso tenía que pedir desde el 10/10 (la entrega abierta más antigua); pidió %q", ult)
	}

	// Y una factura NUEVA del mismo folio entra EN EL REPASO (con el repaso estrecho la entrega
	// quedaría «parcial» y esperaría al barrido de mañana).
	env.ventra.poner(facturaDeMentira("100", "2026-10-10", folio), facturaDeMentira("101", "2026-10-19", folio),
		facturaDeMentira("102", "2026-10-20", folio))
	env.pasa(time.Minute)
	env.ciclo()
	if c, peso, packs := env.conducePesoPacks(ex); c != "100, 101, 102" || math.Abs(peso-108) > 1e-9 || packs != 45 {
		t.Errorf("la factura 102 tenía que entrar en el repaso: conduce %q peso %v packs %v", c, peso, packs)
	}
	if strings.Contains(env.registro.String(), "entrega parcial") {
		t.Errorf("con el repaso ensanchado ninguna entrega abierta llega partida:\n%s", env.registro.String())
	}
}

func TestMotorReal_UnaEntregaCerradaNoSeEncogeEnUnRepasoYElBarridoSiLaRehace(t *testing.T) {
	// La red de seguridad (2): la entrega ya está ENTREGADA, así que el repaso no se ensancha por ella,
	// y aun así no puede reescribirla con la mitad. Sólo el barrido puede encoger o rehacer.
	env := nuevoEntornoReal(t)
	env.ventra.filtra = true
	folio := "PXX-G2B"
	ex := env.ex(folio)
	env.ventra.poner(facturaDeMentira("100", "2026-10-10", folio), facturaDeMentira("101", "2026-10-19", folio))
	env.ciclo() // barrido
	env.exec(`UPDATE orders SET resultado = 'entregado', delivered_at = now() WHERE id = $1`, env.idDe(ex))

	for i := 1; i <= 3; i++ {
		env.pasa(time.Minute)
		env.registro.Reset()
		env.ciclo()
		if c, peso, _ := env.conducePesoPacks(ex); c != "100, 101" || math.Abs(peso-72) > 1e-9 {
			t.Fatalf("repaso %d: el repaso ENCOGIÓ una entrega ya entregada: conduce %q peso %v\n%s", i, c, peso, env.registro.String())
		}
		if !strings.Contains(env.registro.String(), "entrega parcial: se espera al barrido") || !strings.Contains(env.registro.String(), "parciales=1") {
			t.Errorf("repaso %d: la entrega parcial se cuenta y se dice:\n%s", i, env.registro.String())
		}
	}
	if ult := env.ventra.pedidas[len(env.ventra.pedidas)-1]; !strings.HasSuffix(ult, "2026-10-17..2026-10-20") {
		t.Errorf("una entrega entregada no ensancha el repaso; pidió %q", ult)
	}

	// Pasado el día toca el BARRIDO, y Ventra ya sólo trae la 101 (la 100 se anuló): el barrido sí la rehace.
	env.ventra.poner(facturaDeMentira("101", "2026-10-19", folio))
	env.pasa(25 * time.Hour)
	env.ciclo()
	if c, peso, _ := env.conducePesoPacks(ex); c != "101" || math.Abs(peso-36) > 1e-9 {
		t.Errorf("el barrido es el que rehace: conduce %q peso %v", c, peso)
	}
}

func TestMotorReal_ElRepasoEnsanchadoNoPasaDelTopeDeSesentaDias(t *testing.T) {
	env := nuevoEntornoReal(t)
	env.ventra.filtra = true
	// Hoy 20/10: el tope (HistoricoDias = 60) es el 21/08. Una entrega abierta del 22/07 (90 días).
	env.ventra.poner(facturaDeMentira("1", "2026-07-22", "PXX-VIEJA"))
	env.ventra.filtra = false
	env.ciclo() // barrido: la guarda aunque Ventra la conteste fuera de ventana (es lo que da la fila)
	env.ventra.filtra = true
	if !env.hay(env.ex("PXX-VIEJA")) {
		t.Fatal("la siembra no dejó la entrega")
	}
	env.pasa(time.Minute)
	env.ciclo() // repaso
	if ult := env.ventra.pedidas[len(env.ventra.pedidas)-1]; !strings.HasSuffix(ult, "2026-08-21..2026-10-20") {
		t.Errorf("con una abierta de hace 90 días el repaso llega al tope, 21/08, y no más atrás; pidió %q", ult)
	}
	if !strings.Contains(env.registro.String(), "más antigua que el histórico") {
		t.Errorf("y se dice:\n%s", env.registro.String())
	}

	// Una abierta de hace 49 días (01/09) ensancha hasta SU día, no hasta el tope.
	env.exec(`DELETE FROM orders WHERE sucursal_codigo = $1`, env.codigo)
	env.ventra.filtra = false
	env.ventra.poner(facturaDeMentira("2", "2026-09-01", "PXX-MEDIA"))
	env.pasa(time.Minute)
	env.ciclo() // repaso: la guarda (fuera de ventana, pero la fake no filtra)
	env.ventra.filtra = true
	env.pasa(time.Minute)
	env.ciclo()
	if ult := env.ventra.pedidas[len(env.ventra.pedidas)-1]; !strings.HasSuffix(ult, "2026-09-01..2026-10-20") {
		t.Errorf("la abierta más antigua es del 01/09 y el repaso llega hasta ahí; pidió %q", ult)
	}
}

func TestMotorReal_UnaEntregaEnUnaRutaCompletadaNoEnsanchaElRepaso(t *testing.T) {
	// «Ni entregada NI CERRADA»: una entrega sin resultado pero en una ruta completada es histórico.
	env := nuevoEntornoReal(t)
	env.ventra.filtra = true
	folio := "PXX-CERRADA"
	env.ventra.poner(facturaDeMentira("100", "2026-10-10", folio))
	env.ventra.filtra = false
	env.ciclo() // barrido
	env.ventra.filtra = true
	ruta := env.enRuta(env.idDe(env.ex(folio)), 1)
	env.pasa(time.Minute)
	env.ciclo()
	if ult := env.ventra.pedidas[len(env.ventra.pedidas)-1]; !strings.HasSuffix(ult, "2026-10-10..2026-10-20") {
		t.Fatalf("la entrega abierta en una ruta planificada ensancha el repaso; pidió %q", ult)
	}
	env.exec(`UPDATE routes SET status = 'completed' WHERE id = $1`, ruta)
	env.pasa(time.Minute)
	env.ciclo()
	if ult := env.ventra.pedidas[len(env.ventra.pedidas)-1]; !strings.HasSuffix(ult, "2026-10-17..2026-10-20") {
		t.Errorf("en una ruta completada ya no es abierta y el repaso vuelve a ser el de 3 días; pidió %q", ult)
	}
}
