package api

// PUT y DELETE /api/orders/{id}/punto — EL PUNTO DE ENTREGA PUESTO A MANO (issue 19 de Amado,
// 20/10/2026). Sobre el doble de `rutas_test.go`, que repite el WHERE de las consultas y deshace
// la transacción si el manejador falla; lo que el SQL de verdad hace (los CASE del espejo, las
// guardas del UPDATE) lo ata `punto_de_entrega_motor_real_test.go` contra Postgres.
//
// Van en pareja, como manda el CLAUDE.md: lo que pasa y lo que NO pasa (cada 400/404/409 y el
// 502 con Accesos caído dejan la fila EXACTAMENTE como estaba y no avisan).

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// puntoDelDoble es lo que el doble de rutas guarda de más para esta puerta.
type puntoDelDoble struct {
	almacen    *string  // almacen_salida_codigo
	direccion  *string  // end_address
	km         *float64 // delivery_distance_km
	manual     bool
	por        *string
	at         *time.Time
	clienteLat *float64
	clienteLng *float64
	clienteDir *string
	// escrituras cuenta las veces que una consulta del punto llegó a escribir.
	escrituras int
}

// sucursalesSinPuntoDeSalida pone `origin_configured = false` a las del doble.
var sucursalesSinPuntoDeSalida bool

func (d *dobleDeRutas) ListarSucursales(_ context.Context, persona pgtype.UUID) ([]sqlc.ListarSucursalesRow, error) {
	stg, hol := "STG", "HOL"
	// El punto de la SUCURSAL, LEJOS de los dos almacenes de Santiago: si una prueba acabara
	// midiendo desde aquí, el número canta.
	todas := []sqlc.ListarSucursalesRow{
		{ID: stgDeRutas, Name: "Santiago", ExternalID: &stg, Lat: 19.0, Lng: -74.0, OriginConfigured: !sucursalesSinPuntoDeSalida},
		{ID: holDeRutas, Name: "Holguín", ExternalID: &hol, Lat: 20.9, Lng: -76.2, OriginConfigured: !sucursalesSinPuntoDeSalida},
	}
	var salida []sqlc.ListarSucursalesRow
	for _, s := range todas {
		if !persona.Valid || persona.Bytes == [16]byte(s.ID) {
			salida = append(salida, s)
		}
	}
	return salida, nil
}

func (d *dobleDeRutas) LeerPedidoParaElPunto(_ context.Context, arg sqlc.LeerPedidoParaElPuntoParams) (sqlc.LeerPedidoParaElPuntoRow, error) {
	p := d.pedidos[arg.ID]
	if p == nil || !alcanza(arg.Sucursal, &p.sucursal) {
		return sqlc.LeerPedidoParaElPuntoRow{}, pgx.ErrNoRows
	}
	return sqlc.LeerPedidoParaElPuntoRow{
		ID: p.id, BranchID: pgDeRutas(p.sucursal), AlmacenSalidaCodigo: p.punto.almacen,
		RouteID: pgOpcionalDeRutas(p.rutaID), Resultado: p.resultado,
		DeliveredAt: horaOpcionalDeRutas(p.entregadoEn), PuntoManual: p.punto.manual,
		PuntoClienteLat: p.punto.clienteLat, PuntoClienteLng: p.punto.clienteLng,
	}, nil
}

func mismoTexto(a, b *string) bool {
	return (a == nil && b == nil) || (a != nil && b != nil && *a == *b)
}

// puedeCambiarElPunto repite el WHERE común de las dos escrituras: la misma ruta, el mismo
// almacén, sin entregar y de la sucursal del alcance.
func (d *dobleDeRutas) puedeCambiarElPunto(p *pedidoDeRutas, ruta pgtype.UUID, almacen *string, sucursal pgtype.UUID) bool {
	mismaRuta := (!ruta.Valid && p.rutaID == nil) || (ruta.Valid && p.rutaID != nil && ruta.Bytes == [16]byte(*p.rutaID))
	entregado := p.entregadoEn != nil || (p.resultado != nil && *p.resultado == sqlc.StopResultEntregado)
	return mismaRuta && mismoTexto(almacen, p.punto.almacen) && !entregado && alcanza(sucursal, &p.sucursal)
}

func (d *dobleDeRutas) filaDelPunto(p *pedidoDeRutas) (id uuid.UUID, suc pgtype.UUID, at pgtype.Timestamptz) {
	return p.id, pgDeRutas(p.sucursal), horaOpcionalDeRutas(p.punto.at)
}

func (d *dobleDeRutas) PonerPuntoDeEntregaAMano(_ context.Context, arg sqlc.PonerPuntoDeEntregaAManoParams) (sqlc.PonerPuntoDeEntregaAManoRow, error) {
	p := d.pedidos[arg.ID]
	if p == nil || !d.puedeCambiarElPunto(p, arg.RutaID, arg.AlmacenSalidaCodigo, arg.Sucursal) {
		return sqlc.PonerPuntoDeEntregaAManoRow{}, pgx.ErrNoRows
	}
	if !p.punto.manual { // la PRIMERA vez guarda el del cliente; las siguientes no lo pisan
		p.punto.clienteLat, p.punto.clienteLng, p.punto.clienteDir = p.endLat, p.endLng, p.punto.direccion
	}
	p.endLat, p.endLng = arg.Lat, arg.Lng
	if arg.Direccion != nil {
		p.punto.direccion = arg.Direccion
	}
	ahora := time.Now()
	p.punto.manual, p.punto.por, p.punto.at = true, arg.Por, &ahora
	p.punto.km = arg.DeliveryDistanceKm
	if arg.SegmentKm != nil {
		p.segmentKm = arg.SegmentKm
	}
	p.punto.escrituras++
	return d.respuestaDelPunto(p), nil
}

func (d *dobleDeRutas) DevolverPuntoDeEntregaAlCliente(_ context.Context, arg sqlc.DevolverPuntoDeEntregaAlClienteParams) (sqlc.DevolverPuntoDeEntregaAlClienteRow, error) {
	p := d.pedidos[arg.ID]
	if p == nil || !p.punto.manual || !d.puedeCambiarElPunto(p, arg.RutaID, arg.AlmacenSalidaCodigo, arg.Sucursal) ||
		p.punto.clienteLat == nil || arg.Lat == nil || *p.punto.clienteLat != *arg.Lat ||
		p.punto.clienteLng == nil || arg.Lng == nil || *p.punto.clienteLng != *arg.Lng {
		return sqlc.DevolverPuntoDeEntregaAlClienteRow{}, pgx.ErrNoRows
	}
	p.endLat, p.endLng, p.punto.direccion = p.punto.clienteLat, p.punto.clienteLng, p.punto.clienteDir
	p.punto.manual, p.punto.por, p.punto.at = false, nil, nil
	p.punto.clienteLat, p.punto.clienteLng, p.punto.clienteDir = nil, nil, nil
	p.punto.km = arg.DeliveryDistanceKm
	if arg.SegmentKm != nil {
		p.segmentKm = arg.SegmentKm
	}
	p.punto.escrituras++
	f := d.respuestaDelPunto(p)
	return sqlc.DevolverPuntoDeEntregaAlClienteRow(f), nil
}

func (d *dobleDeRutas) respuestaDelPunto(p *pedidoDeRutas) sqlc.PonerPuntoDeEntregaAManoRow {
	id, suc, at := d.filaDelPunto(p)
	return sqlc.PonerPuntoDeEntregaAManoRow{
		ID: id, BranchID: suc, EndLat: p.endLat, EndLng: p.endLng, EndAddress: p.punto.direccion,
		PuntoManual: p.punto.manual, PuntoManualPor: p.punto.por, PuntoManualAt: at,
		DeliveryDistanceKm: p.punto.km, SegmentKm: p.segmentKm,
	}
}

// --------------------------------------------------------------------------- el montaje

// Los dos almacenes de Santiago (`desde_que_almacen_se_mide_test.go`): PV-STGO "1" principal y
// AURORA "2". El punto nuevo cae cerca de AURORA a propósito: medido desde el principal sale
// otro número, y esa diferencia es lo que prueba que se midió desde el almacén del PEDIDO.
const (
	latNuevo, lngNuevo = 20.10, -75.90
)

type montajeDelPunto struct {
	t      *testing.T
	h      http.Handler
	hp     http.Handler
	d      *dobleDeRutas
	ids    [3]uuid.UUID // lejos, cerca, medio
	ajeno  uuid.UUID    // el de Holguín
	avisos *contadorDeAvisos
}

func puntoMontado(t *testing.T) *montajeDelPunto {
	t.Helper()
	conAccesos(t, &accesosFalso{sucursales: almacenesDeSantiagoDeAccesos()})
	d, ids, ajeno := datosDeReparto()
	// El cliente de «cerca» sale de AURORA (código "2") y tiene su dirección de siempre.
	aurora, calle := "2", "Calle del cliente"
	d.pedidos[ids[1]].punto = puntoDelDoble{almacen: &aurora, direccion: &calle}
	return &montajeDelPunto{t: t, h: montarRutas(t, d), d: d, ids: ids, ajeno: ajeno, avisos: contarAvisos(t)}
}

func (m *montajeDelPunto) pedir(metodo string, id uuid.UUID, jwt, cuerpo string) *httptest.ResponseRecorder {
	m.t.Helper()
	return llamarRutas(m.t, m.hPedidos(), metodo, "/api/orders/"+id.String()+"/punto", jwt, cuerpo)
}

func (m *montajeDelPunto) hPedidos() http.Handler {
	m.t.Helper()
	if m.hp == nil {
		m.hp = montarPedidosSobreRutas(m.t, m.d)
	}
	return m.hp
}

// montarPedidosSobreRutas monta las rutas de PEDIDOS (el PUT y el DELETE viven allí) sobre el
// doble de rutas, que es el que tiene las rutas, las paradas y el rollback de la transacción.
func montarPedidosSobreRutas(t *testing.T, q *dobleDeRutas) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDeRutas{q: q}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	s := NuevoServidor(cfg, reg, porteria, verif, func(context.Context) error { return nil })
	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	s.rutasPedidos(rt, []httpx.Medio{verif.Exigir, porteria.Exigir}, nil)
	return rt.Handler()
}

func cuerpoDelPunto(lat, lng float64, direccion string) string {
	c := map[string]any{"lat": lat, "lng": lng}
	if direccion != "" {
		c["direccion"] = direccion
	}
	b, _ := json.Marshal(c)
	return string(b)
}

func leerElPuntoSalida(t *testing.T, w *httptest.ResponseRecorder) PuntoSalida {
	t.Helper()
	var s PuntoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
		t.Fatalf("respuesta ilegible (%d): %s", w.Code, w.Body.String())
	}
	return s
}

func casiIgual(a *float64, b float64) bool { return a != nil && math.Abs(*a-b) < 1e-6 }

// --------------------------------------------------------------------------- PUT: lo que pasa

func TestPonerElPuntoALaManoMideDesdeElAlmacenDelPedido(t *testing.T) {
	m := puntoMontado(t)
	cerca := m.ids[1]
	w := m.pedir(http.MethodPut, cerca, deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, "  Calle 5, entre 6 y 7  "))
	if w.Code != http.StatusOK {
		t.Fatalf("PUT /punto contestó %d: %s", w.Code, w.Body.String())
	}
	got := leerElPuntoSalida(t, w)
	if got.ID != cerca || !casiIgual(got.EndLat, latNuevo) || !casiIgual(got.EndLng, lngNuevo) ||
		got.EndAddress == nil || *got.EndAddress != "Calle 5, entre 6 y 7" {
		t.Fatalf("el punto no es el que se pidió (la dirección va recortada): %+v", got)
	}
	if !got.PuntoManual || got.PuntoManualPor == nil || *got.PuntoManualPor != "p-stg" || got.PuntoManualAt == nil {
		t.Fatalf("faltan la marca, quién o cuándo: %+v", got)
	}

	// LOS KM SON LOS DE AURORA, no los del principal ni los del punto de la sucursal. La cuenta
	// es la de la cotización: si alguien midiera desde PV-STGO este número saldría ~4 km más.
	deAurora := cotizar.DistanciaHaversineKm(latAURORA, lngAURORA, latNuevo, lngNuevo)
	dePrincipal := cotizar.DistanciaHaversineKm(latPVSTGO, lngPVSTGO, latNuevo, lngNuevo)
	if !casiIgual(got.DeliveryDistanceKm, deAurora) {
		t.Fatalf("deliveryDistanceKm = %v; desde AURORA son %.4f (desde PV-STGO serían %.4f)",
			got.DeliveryDistanceKm, deAurora, dePrincipal)
	}
	if math.Abs(deAurora-dePrincipal) < 2 {
		t.Fatalf("la prueba no distingue los dos almacenes (%.2f contra %.2f): cambia el punto", deAurora, dePrincipal)
	}

	// Y lo guardado: el punto del cliente, para volver a él.
	p := m.d.pedidos[cerca]
	if !casiIgual(p.punto.clienteLat, 0) || !casiIgual(p.punto.clienteLng, 0.05) ||
		p.punto.clienteDir == nil || *p.punto.clienteDir != "Calle del cliente" {
		t.Fatalf("no se guardó el punto del cliente: %+v", p.punto)
	}
	// Sin ruta: nada de segmentKm, y los avisos son los de un pedido suelto.
	if got.SegmentKm != nil {
		t.Fatalf("un pedido sin ruta no tiene segmentKm: %v", *got.SegmentKm)
	}
	m.avisos.exige(t, "poner el punto a mano a un pedido sin ruta", CambioPedidos, CambioTablero)
}

func TestElSegundoPutNoPisaElPuntoDelCliente(t *testing.T) {
	m := puntoMontado(t)
	cerca := m.ids[1]
	m.pedir(http.MethodPut, cerca, deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, "Primera"))
	w := m.pedir(http.MethodPut, cerca, deSantiagoEnRutas(t), cuerpoDelPunto(20.2, -75.7, ""))
	if w.Code != http.StatusOK {
		t.Fatalf("el segundo PUT contestó %d: %s", w.Code, w.Body.String())
	}
	p := m.d.pedidos[cerca]
	if !casiIgual(p.punto.clienteLat, 0) || p.punto.clienteDir == nil || *p.punto.clienteDir != "Calle del cliente" {
		t.Fatalf("el segundo PUT pisó el punto del CLIENTE con el manual anterior: %+v", p.punto)
	}
	// Sin `direccion` se deja la que tenía (la del primer PUT), no se borra.
	if p.punto.direccion == nil || *p.punto.direccion != "Primera" {
		t.Fatalf("sin direccion la anterior se queda: %v", p.punto.direccion)
	}
}

// El aviso sale con la sucursal DE LA FILA. Lo hace un SUPER ADMIN, que tiene alcance «todas»:
// con un aviso sacado del alcance saldría pelado y se bajarían la lista las ocho sucursales.
func TestElAvisoDelPuntoSaleConLaSucursalDeLaFila(t *testing.T) {
	m := puntoMontado(t)
	w := m.pedir(http.MethodPut, m.ids[1], superAdminEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusOK {
		t.Fatalf("%d: %s", w.Code, w.Body.String())
	}
	for _, tipo := range []string{CambioPedidos, CambioTablero} {
		if suc, hay := m.avisos.sucursalDe(tipo); !hay || suc != stgDeRutas.String() {
			t.Errorf("el aviso de %s salió con la sucursal %q y tenía que ser %s, la del pedido", tipo, suc, stgDeRutas)
		}
	}
}

// --------------------------------------------------------------------------- PUT: lo que NO pasa

func TestPutDelPuntoConUnCuerpoMalo(t *testing.T) {
	casos := []struct{ nombre, cuerpo, mensaje string }{
		{"vacío", ``, "Se espera { lat, lng }"},
		{"no es JSON", `lat=1`, "Se espera { lat, lng }"},
		{"sin lng", `{"lat":20}`, "Se espera { lat, lng }"},
		{"sin lat", `{"lng":-75}`, "Se espera { lat, lng }"},
		{"lat texto", `{"lat":"veinte","lng":-75}`, "Se espera { lat, lng }"},
		{"lat nula", `{"lat":null,"lng":-75}`, "Se espera { lat, lng }"},
		{"direccion que no es texto", `{"lat":20,"lng":-75,"direccion":5}`, "Se espera { lat, lng }"},
		{"latitud fuera de rango", `{"lat":91,"lng":-75}`, "lat y lng tienen que ser un punto del planeta"},
		{"longitud fuera de rango", `{"lat":20,"lng":-181}`, "lat y lng tienen que ser un punto del planeta"},
		{"desbordado", `{"lat":1e308,"lng":-75}`, "lat y lng tienen que ser un punto del planeta"},
		{"el golfo de Guinea", `{"lat":0,"lng":0}`, "lat y lng tienen que ser un punto del planeta"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			m := puntoMontado(t)
			antes := *m.d.pedidos[m.ids[1]]
			w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), c.cuerpo)
			if w.Code != http.StatusBadRequest || errorDeRutas(t, w) != c.mensaje {
				t.Fatalf("contestó %d %q; tenía que ser 400 %q", w.Code, errorDeRutas(t, w), c.mensaje)
			}
			noSeTocoNiSeAviso(t, m, m.ids[1], antes)
		})
	}
}

func noSeTocoNiSeAviso(t *testing.T, m *montajeDelPunto, id uuid.UUID, antes pedidoDeRutas) {
	t.Helper()
	despues := *m.d.pedidos[id]
	if despues.punto.escrituras != 0 || despues.punto.manual || !mismoFloat(despues.endLat, antes.endLat) ||
		!mismoFloat(despues.endLng, antes.endLng) || !mismoTexto(despues.punto.direccion, antes.punto.direccion) ||
		!mismoFloat(despues.segmentKm, antes.segmentKm) || !mismoFloat(despues.punto.km, antes.punto.km) {
		t.Fatalf("un rechazo dejó rastro en la fila:\n antes   %+v\n después %+v", antes, despues)
	}
	m.avisos.exigeSilencio(t, "un rechazo")
}

func mismoFloat(a, b *float64) bool {
	return (a == nil && b == nil) || (a != nil && b != nil && *a == *b)
}

func TestPutDelPuntoDeOtraSucursalOQueNoExisteEs404(t *testing.T) {
	m := puntoMontado(t)
	for nombre, id := range map[string]uuid.UUID{
		"un pedido de Holguín, con el token de Santiago": m.ajeno,
		"un pedido que no existe":                        uuid.New(),
	} {
		w := m.pedir(http.MethodPut, id, deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
		if w.Code != http.StatusNotFound || errorDeRutas(t, w) != "No encontrado" {
			t.Errorf("%s: contestó %d %q", nombre, w.Code, errorDeRutas(t, w))
		}
	}
	// Un id que ni es uuid.
	w := llamarRutas(t, m.hPedidos(), http.MethodPut, "/api/orders/no-es-un-uuid/punto", deSantiagoEnRutas(t),
		cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusNotFound {
		t.Errorf("un id que no es uuid contestó %d y tenía que ser 404", w.Code)
	}
	if o := m.d.pedidos[m.ajeno]; o.punto.escrituras != 0 || o.punto.manual {
		t.Fatalf("el pedido de Holguín se tocó desde Santiago: %+v", o.punto)
	}
	m.avisos.exigeSilencio(t, "un 404")
}

func TestPutDelPuntoDeUnPedidoYaEntregadoEs409(t *testing.T) {
	// Las dos columnas que `MarcarResultadoDeParada` escribe y limpia juntas: cualquiera basta.
	entregado := sqlc.StopResultEntregado
	ahora := time.Now()
	for nombre, poner := range map[string]func(*pedidoDeRutas){
		"con resultado entregado": func(p *pedidoDeRutas) { p.resultado = &entregado },
		"con hora de entrega":     func(p *pedidoDeRutas) { p.entregadoEn = &ahora },
	} {
		m := puntoMontado(t)
		poner(m.d.pedidos[m.ids[1]])
		antes := *m.d.pedidos[m.ids[1]]
		w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
		if w.Code != http.StatusConflict || errorDeRutas(t, w) != "El pedido ya está entregado: no se le puede cambiar el punto" {
			t.Fatalf("%s: contestó %d %q", nombre, w.Code, errorDeRutas(t, w))
		}
		noSeTocoNiSeAviso(t, m, m.ids[1], antes)
	}
}

func TestPutDelPuntoEnUnaRutaCompletadaEs409(t *testing.T) {
	m := puntoMontado(t)
	ruta := metaEnUnaRuta(m, sqlc.RouteStatusCompleted, false)
	antes := *m.d.pedidos[m.ids[1]]
	w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusConflict ||
		errorDeRutas(t, w) != "La ruta ya está completada: no se le puede cambiar el punto a sus paradas" {
		t.Fatalf("contestó %d %q", w.Code, errorDeRutas(t, w))
	}
	noSeTocoNiSeAviso(t, m, m.ids[1], antes)
	if m.d.rutas[ruta].km != 1 {
		t.Fatalf("una ruta completada es histórico y su total se movió: %v", m.d.rutas[ruta].km)
	}
}

// ACCESOS CAÍDO = 502 Y NO SE ESCRIBE NADA. La cotización tolera el fallo y mide desde el punto
// de la sucursal; aquí eso sería guardar un punto nuevo con un kilometraje que no es el del
// almacén del pedido, o sea un número del cobro creíble y equivocado.
func TestPutDelPuntoConAccesosCaidoEs502YNoEscribeNada(t *testing.T) {
	m := puntoMontado(t)
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})
	ruta := metaEnUnaRuta(m, sqlc.RouteStatusPlanned, false)
	antes := *m.d.pedidos[m.ids[1]]
	kmAntes := m.d.rutas[ruta].km

	w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, "Otra calle"))
	if w.Code != http.StatusBadGateway {
		t.Fatalf("con Accesos caído contestó %d y tenía que ser 502: %s", w.Code, w.Body.String())
	}
	noSeTocoNiSeAviso(t, m, m.ids[1], antes)
	if m.d.rutas[ruta].km != kmAntes {
		t.Fatalf("el total de la ruta se movió con Accesos caído: %v -> %v", kmAntes, m.d.rutas[ruta].km)
	}
}

func TestPutDelPuntoSinAlmacenMideDesdeElPuntoDeLaSucursal(t *testing.T) {
	m := puntoMontado(t)
	conAccesos(t, &accesosFalso{}) // Accesos contesta, pero no hay ni un almacén
	w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusOK {
		t.Fatalf("sin almacenes pero con punto de partida tiene que medir desde la sucursal: %d %s", w.Code, w.Body.String())
	}
	esperado := cotizar.DistanciaHaversineKm(19.0, -74.0, latNuevo, lngNuevo)
	if got := leerElPuntoSalida(t, w); !casiIgual(got.DeliveryDistanceKm, esperado) {
		t.Fatalf("sin almacén se mide desde el punto de la sucursal (%.4f): %v", esperado, got.DeliveryDistanceKm)
	}
}

// Y la pareja: ni almacén ni punto de partida. El punto de la sucursal sería (0,0) y los km
// saldrían del golfo de Guinea, con sus decimales: 409 y nada guardado.
func TestPutDelPuntoSinAlmacenNiPuntoDeSalidaEs409(t *testing.T) {
	m := puntoMontado(t)
	conAccesos(t, &accesosFalso{})
	sucursalesSinPuntoDeSalida = true
	t.Cleanup(func() { sucursalesSinPuntoDeSalida = false })
	antes := *m.d.pedidos[m.ids[1]]
	w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusConflict || errorDeRutas(t, w) != "Santiago no tiene ningún almacén con coordenadas" {
		t.Fatalf("contestó %d %q", w.Code, errorDeRutas(t, w))
	}
	noSeTocoNiSeAviso(t, m, m.ids[1], antes)
}

// --------------------------------------------------------------------------- PUT en una ruta

// metaEnUnaRuta mete «cerca» (y los otros dos) en una ruta de Santiago con origen en (20.0,-75.8),
// en el orden lejos=1, cerca=2, medio=3. `optimized` arranca en false A PROPÓSITO: el
// `FijarTotalesDeRuta` de `nil` lo pone en true, y una firma que cambia sola es una ruta que
// dice haber sido optimizada por la máquina sin que nadie la haya optimizado.
func metaEnUnaRuta(m *montajeDelPunto, estado sqlc.RouteStatus, optimizada bool) uuid.UUID {
	id := uuid.MustParse("eeeeeeee-0000-0000-0000-0000000000aa")
	lat, lng := 20.0, -75.8
	m.d.rutas[id] = &rutaDeRutas{
		id: id, codigo: "RT-PUNTO-001", estado: estado, sucursal: &stgDeRutas,
		origenLat: &lat, origenLng: &lng, km: 1, optimized: optimizada, creada: time.Now(),
	}
	coordenadas := [3][2]float64{{20.20, -75.60}, {20.05, -75.75}, {20.10, -75.70}}
	for i, pid := range m.ids {
		n := int32(i + 1)
		ruta := id
		p := m.d.pedidos[pid]
		p.rutaID, p.ultimaRuta, p.stopOrder = &ruta, &ruta, &n
		p.endLat, p.endLng = &coordenadas[i][0], &coordenadas[i][1]
		km := 99.0 // un segment_km viejo y reconocible
		p.segmentKm = &km
	}
	return id
}

func TestPutDelPuntoEnUnaRutaRecalculaLaParadaYElTotalSinTocarElOrden(t *testing.T) {
	m := puntoMontado(t)
	ruta := metaEnUnaRuta(m, sqlc.RouteStatusPlanned, false)
	cerca := m.ids[1]
	ordenAntes := map[uuid.UUID]int32{}
	for _, id := range m.ids {
		ordenAntes[id] = *m.d.pedidos[id].stopOrder
	}

	w := m.pedir(http.MethodPut, cerca, deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusOK {
		t.Fatalf("contestó %d: %s", w.Code, w.Body.String())
	}
	got := leerElPuntoSalida(t, w)

	// segment_km: la recta del ORIGEN DE LA RUTA al punto nuevo (radial, no el tramo).
	radial := kmHaversine(20.0, -75.8, latNuevo, lngNuevo)
	if !casiIgual(got.SegmentKm, radial) {
		t.Fatalf("segmentKm = %v; la recta del origen de la ruta al punto son %.4f", got.SegmentKm, radial)
	}
	// total_distance: el circuito cerrado con la parada en su sitio nuevo y el MISMO orden.
	p := [][2]float64{{20.20, -75.60}, {latNuevo, lngNuevo}, {20.10, -75.70}}
	esperado := kmHaversine(20.0, -75.8, p[0][0], p[0][1]) +
		kmHaversine(p[0][0], p[0][1], p[1][0], p[1][1]) +
		kmHaversine(p[1][0], p[1][1], p[2][0], p[2][1]) +
		kmHaversine(p[2][0], p[2][1], 20.0, -75.8)
	r := m.d.rutas[ruta]
	if math.Abs(r.km-esperado) > 1e-6 {
		t.Fatalf("total_distance = %.6f; el circuito con el punto nuevo son %.6f (antes valía 1)", r.km, esperado)
	}
	// LO QUE NO SE TOCA: el orden que decidió el logístico y la firma de quién lo ordenó.
	for _, id := range m.ids {
		if n := m.d.pedidos[id].stopOrder; n == nil || *n != ordenAntes[id] {
			t.Fatalf("el stop_order de %s cambió: %v -> %v", id, ordenAntes[id], n)
		}
	}
	if r.optimized {
		t.Fatal("la ruta no estaba optimizada y ahora dice que sí: `FijarTotalesDeRuta` se llamó con optimizado nil")
	}
	// Las otras paradas conservan su segment_km: sólo se mueve el de la que cambió.
	if km := m.d.pedidos[m.ids[0]].segmentKm; km == nil || *km != 99 {
		t.Fatalf("otra parada cambió su segment_km: %v", km)
	}
	m.avisos.exige(t, "poner el punto a mano a una parada de una ruta", CambioPedidos, CambioTablero, CambioRutas)
}

func TestLaRutaEnCursoTambienSeRecalcula(t *testing.T) {
	m := puntoMontado(t)
	metaEnUnaRuta(m, sqlc.RouteStatusInProgress, true)
	w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusOK {
		t.Fatalf("una ruta en curso se puede editar (sólo `completed` es histórico): %d %s", w.Code, w.Body.String())
	}
	if !m.d.rutas[uuid.MustParse("eeeeeeee-0000-0000-0000-0000000000aa")].optimized {
		t.Fatal("la firma `optimized` tenía que conservarse tal cual (true)")
	}
}

// --------------------------------------------------------------------------- DELETE

func TestDeleteDelPuntoVuelveAlDelCliente(t *testing.T) {
	m := puntoMontado(t)
	ruta := metaEnUnaRuta(m, sqlc.RouteStatusPlanned, false)
	cerca := m.ids[1]
	m.pedir(http.MethodPut, cerca, deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, "Otra calle"))
	// El espejo trajo entre medias un punto del cliente MÁS NUEVO: a ése se vuelve.
	nuevaLat, nuevaLng, nuevaDir := 20.07, -75.77, "Calle corregida por PEDIDO"
	p := m.d.pedidos[cerca]
	p.punto.clienteLat, p.punto.clienteLng, p.punto.clienteDir = &nuevaLat, &nuevaLng, &nuevaDir
	m.avisos.tipos, m.avisos.sucursales = nil, nil

	w := m.pedir(http.MethodDelete, cerca, deSantiagoEnRutas(t), "")
	if w.Code != http.StatusOK {
		t.Fatalf("DELETE /punto contestó %d: %s", w.Code, w.Body.String())
	}
	got := leerElPuntoSalida(t, w)
	if !casiIgual(got.EndLat, nuevaLat) || !casiIgual(got.EndLng, nuevaLng) ||
		got.EndAddress == nil || *got.EndAddress != nuevaDir {
		t.Fatalf("no volvió al punto MÁS RECIENTE del cliente: %+v", got)
	}
	if got.PuntoManual || got.PuntoManualPor != nil || got.PuntoManualAt != nil {
		t.Fatalf("la marca tenía que quedar limpia: %+v", got)
	}
	// Los km, desde AURORA otra vez, al punto del cliente; el segmento y el total, de la ruta.
	if want := cotizar.DistanciaHaversineKm(latAURORA, lngAURORA, nuevaLat, nuevaLng); !casiIgual(got.DeliveryDistanceKm, want) {
		t.Fatalf("deliveryDistanceKm = %v; desde AURORA al punto del cliente son %.4f", got.DeliveryDistanceKm, want)
	}
	if want := kmHaversine(20.0, -75.8, nuevaLat, nuevaLng); !casiIgual(got.SegmentKm, want) {
		t.Fatalf("segmentKm = %v; tenían que ser %.4f", got.SegmentKm, want)
	}
	if m.d.rutas[ruta].km == 1 {
		t.Fatal("el total de la ruta no se recalculó")
	}
	m.avisos.exige(t, "devolver el punto al del cliente", CambioPedidos, CambioTablero, CambioRutas)
}

func TestDeleteDelPuntoDeUnPedidoQueNoEsManualEs409(t *testing.T) {
	m := puntoMontado(t)
	antes := *m.d.pedidos[m.ids[1]]
	w := m.pedir(http.MethodDelete, m.ids[1], deSantiagoEnRutas(t), "")
	if w.Code != http.StatusConflict || errorDeRutas(t, w) != "El pedido no tiene un punto puesto a mano" {
		t.Fatalf("contestó %d %q", w.Code, errorDeRutas(t, w))
	}
	noSeTocoNiSeAviso(t, m, m.ids[1], antes)
}

func TestDeleteDelPuntoOtrasSucursalYOtrosRechazos(t *testing.T) {
	m := puntoMontado(t)
	m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	m.avisos.tipos, m.avisos.sucursales = nil, nil

	// Otra sucursal: 404, y el punto manual sigue.
	holguin := tokenDeRutas(t, map[string]any{"sub": "p-hol", "role": "LOGISTICO", "branchId": holDeRutas.String()})
	if w := m.pedir(http.MethodDelete, m.ids[1], holguin, ""); w.Code != http.StatusNotFound {
		t.Fatalf("desde Holguín contestó %d y tenía que ser 404", w.Code)
	}
	// Accesos caído: 502 y sigue siendo manual.
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})
	if w := m.pedir(http.MethodDelete, m.ids[1], deSantiagoEnRutas(t), ""); w.Code != http.StatusBadGateway {
		t.Fatalf("con Accesos caído contestó %d y tenía que ser 502", w.Code)
	}
	// Ruta completada y pedido entregado: 409 cada uno.
	conAccesos(t, &accesosFalso{sucursales: almacenesDeSantiagoDeAccesos()})
	ahora := time.Now()
	m.d.pedidos[m.ids[1]].entregadoEn = &ahora
	if w := m.pedir(http.MethodDelete, m.ids[1], deSantiagoEnRutas(t), ""); w.Code != http.StatusConflict ||
		errorDeRutas(t, w) != "El pedido ya está entregado: no se le puede cambiar el punto" {
		t.Fatalf("un entregado contestó %d %q", w.Code, errorDeRutas(t, w))
	}
	m.d.pedidos[m.ids[1]].entregadoEn = nil
	metaEnUnaRuta(m, sqlc.RouteStatusCompleted, false)
	if w := m.pedir(http.MethodDelete, m.ids[1], deSantiagoEnRutas(t), ""); w.Code != http.StatusConflict ||
		errorDeRutas(t, w) != "La ruta ya está completada: no se le puede cambiar el punto a sus paradas" {
		t.Fatalf("una ruta completada contestó %d %q", w.Code, errorDeRutas(t, w))
	}
	if !m.d.pedidos[m.ids[1]].punto.manual {
		t.Fatal("un rechazo dejó de ser manual el punto")
	}
	m.avisos.exigeSilencio(t, "un DELETE rechazado")
}

// LA CARRERA. La lectura previa dice «planificada» y «sin entregar»; entre ella y la escritura la
// ruta se completa, o el pedido se entrega. Lo único que lo sujeta es el bloqueo de la ruta dentro
// de la transacción y el WHERE de la escritura, y las pruebas secuenciales de arriba no lo ven:
// la lectura previa ya contesta el mismo 409 por su cuenta.
func TestSiLaRutaSeCompletaMientrasSeGuardaNoSeGuardaNada(t *testing.T) {
	m := puntoMontado(t)
	ruta := metaEnUnaRuta(m, sqlc.RouteStatusPlanned, false)
	antes := *m.d.pedidos[m.ids[1]]
	kmAntes := m.d.rutas[ruta].km
	m.d.alBloquear = func() { m.d.rutas[ruta].estado = sqlc.RouteStatusCompleted }

	w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusConflict ||
		errorDeRutas(t, w) != "La ruta ya está completada: no se le puede cambiar el punto a sus paradas" {
		t.Fatalf("contestó %d %q", w.Code, errorDeRutas(t, w))
	}
	noSeTocoNiSeAviso(t, m, m.ids[1], antes)
	if m.d.rutas[ruta].km != kmAntes {
		t.Fatalf("la ruta completada cambió su total: %v", m.d.rutas[ruta].km)
	}
}

func TestSiElPedidoSeEntregaMientrasSeGuardaNoSeGuardaNada(t *testing.T) {
	m := puntoMontado(t)
	metaEnUnaRuta(m, sqlc.RouteStatusPlanned, false)
	antes := *m.d.pedidos[m.ids[1]]
	m.d.alBloquear = func() { ahora := time.Now(); m.d.pedidos[m.ids[1]].entregadoEn = &ahora }

	w := m.pedir(http.MethodPut, m.ids[1], deSantiagoEnRutas(t), cuerpoDelPunto(latNuevo, lngNuevo, ""))
	if w.Code != http.StatusConflict ||
		errorDeRutas(t, w) != "El pedido cambió mientras se guardaba el punto: vuelve a intentarlo" {
		t.Fatalf("contestó %d %q", w.Code, errorDeRutas(t, w))
	}
	despues := *m.d.pedidos[m.ids[1]]
	if despues.punto.escrituras != 0 || despues.punto.manual || !mismoFloat(despues.endLat, antes.endLat) {
		t.Fatalf("se escribió con el pedido ya entregado: %+v", despues.punto)
	}
	m.avisos.exigeSilencio(t, "una carrera perdida")
}
