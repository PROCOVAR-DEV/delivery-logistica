package api

// Las pruebas del panel, y el montaje que comparten el panel, el informe y la sesión.
//
// Van en el paquete `api` y no en `api_test` a propósito: lo que hay que probar aquí son
// las cuatro funciones `rutas…` que monta `servidor.go`, y montarlas una a una es lo que
// permite comprobar CADA RUTA CON SUS MIDDLEWARES —que `/api/me` no lleva el de sesión y
// `/api/dashboard` sí— en vez de darlo por hecho porque el router entero compila.

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

const secretoDePanel = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

var (
	stgDePanel = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	holDePanel = uuid.MustParse("22222222-2222-2222-2222-222222222222")
)

// --------------------------------------------------------------------------- el doble

// dobleDePanel embebe `sqlc.Querier` sin implementarlo: así satisface la interfaz entera
// escribiendo sólo las consultas que interesan, y si el manejador llama a cualquier otra
// revienta con un nil en vez de devolver un cero que parezca bueno.
type dobleDePanel struct {
	sqlc.Querier

	resumen     sqlc.PanelResumenRow
	porSucursal []sqlc.PanelPorSucursalRow
	rutas       int64
	vehiculos   int64
	enRuta      int64
	informe     []sqlc.ListarPedidosParaInformeRow

	// Lo que se vio pasar. ES LO QUE SE COMPRUEBA: qué sucursal llegó a cada consulta.
	sucursalVista []pgtype.UUID
	// Cuántas veces se resolvió una sucursal, que es la consulta que hace el alcance al
	// montarse. Sirve para comprobar que la ruta que NO lleva alcance no la paga.
	resoluciones int
	hoyVisto     pgtype.Timestamptz
	argInforme   sqlc.ListarPedidosParaInformeParams
}

func (d *dobleDePanel) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	d.resoluciones++
	switch id {
	case stgDePanel:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: stgDePanel, Name: "Santiago", ExternalID: &c}, nil
	case holDePanel:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: holDePanel, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

func (d *dobleDePanel) PanelResumen(_ context.Context, arg sqlc.PanelResumenParams) (sqlc.PanelResumenRow, error) {
	d.sucursalVista = append(d.sucursalVista, arg.Sucursal)
	d.hoyVisto = arg.Hoy
	return d.resumen, nil
}

func (d *dobleDePanel) PanelPorSucursal(_ context.Context, sucursal pgtype.UUID) ([]sqlc.PanelPorSucursalRow, error) {
	d.sucursalVista = append(d.sucursalVista, sucursal)
	return d.porSucursal, nil
}

func (d *dobleDePanel) ContarRutasActivas(_ context.Context, sucursal pgtype.UUID) (int64, error) {
	d.sucursalVista = append(d.sucursalVista, sucursal)
	return d.rutas, nil
}

func (d *dobleDePanel) ContarVehiculos(_ context.Context, sucursal pgtype.UUID) (int64, error) {
	d.sucursalVista = append(d.sucursalVista, sucursal)
	return d.vehiculos, nil
}

func (d *dobleDePanel) ContarVehiculosEnRuta(_ context.Context, sucursal pgtype.UUID) (int64, error) {
	d.sucursalVista = append(d.sucursalVista, sucursal)
	return d.enRuta, nil
}

func (d *dobleDePanel) ListarPedidosParaInforme(_ context.Context, arg sqlc.ListarPedidosParaInformeParams) ([]sqlc.ListarPedidosParaInformeRow, error) {
	d.sucursalVista = append(d.sucursalVista, arg.Sucursal)
	d.argInforme = arg
	return d.informe, nil
}

type fuenteDePanel struct{ q *dobleDePanel }

func (f fuenteDePanel) Consultas() sqlc.Querier { return f.q }
func (f fuenteDePanel) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// --------------------------------------------------------------------------- montaje

// montarDePanel levanta el servidor con las rutas del panel, el informe y la sesión, cada
// una con los middlewares que le tocan — los mismos que les pasa `servidor.go`.
func montarDePanel(t *testing.T, q *dobleDePanel) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDePanel)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDePanel{q: q}, reg)
	s := NuevoServidor(cfg, reg, porteria, auth.NuevoVerificador([]byte(secretoDePanel)), nil)

	rt := httpx.NuevoRouter(httpx.ConRegistro(reg), httpx.SinCache)
	sesion := []httpx.Medio{s.verif.Exigir, porteria.Exigir}
	admin := []httpx.Medio{s.verif.Exigir, auth.ExigirAdmin, porteria.Exigir}
	s.rutasPanel(rt, sesion, admin)
	s.rutasInformes(rt, sesion, admin)
	s.rutasYo(rt, sesion, admin)
	return rt.Handler()
}

// tokenDePanel firma un JWT HS256 como el que emite auth.
func tokenDePanel(t *testing.T, reclamos map[string]any) string {
	t.Helper()
	if _, hay := reclamos["exp"]; !hay {
		reclamos["exp"] = time.Now().Add(time.Hour).Unix()
	}
	cab := b64DePanel(t, map[string]any{"alg": "HS256", "typ": "JWT"})
	cuerpo := b64DePanel(t, reclamos)
	mac := hmac.New(sha256.New, []byte(secretoDePanel))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func b64DePanel(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func pedirDePanel(t *testing.T, h http.Handler, ruta, jwt string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(http.MethodGet, ruta, nil)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func leerJSONDePanel[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("la respuesta no es JSON: %v\n%s", err, w.Body.String())
	}
	return v
}

func pgDePanel(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

// --------------------------------------------------------------------------- pruebas

func TestPanelDevuelveLosOchoNumerosDelContrato(t *testing.T) {
	hol := "Holguín"
	q := &dobleDePanel{
		resumen: sqlc.PanelResumenRow{
			TotalPedidos: 3528, SinRuta: 40, EntregadosHoy: 7,
			PesoPendiente: 1234.5, TotalDomicilios: 987.25,
		},
		rutas: 3, vehiculos: 9, enRuta: 2,
		porSucursal: []sqlc.PanelPorSucursalRow{
			{BranchID: pgDePanel(holDePanel), SucursalNombre: &hol, Pedidos: 30, PesoKg: 900},
			// Sin nombre: un pedido sin sucursal, o con una que ya no está. TIENE que
			// salir, o el desglose no suma lo que dice la tarjeta de arriba.
			{Pedidos: 10, PesoKg: 334.5},
		},
	}
	h := montarDePanel(t, q)

	w := pedirDePanel(t, h, "/api/dashboard", tokenDePanel(t, map[string]any{"sub": "u1", "role": "LOGISTICO", "branchId": holDePanel.String()}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	p := leerJSONDePanel[PanelSalida](t, w)

	if p.TotalOrders != 3528 || p.SinRuta != 40 || p.EntregadosHoy != 7 {
		t.Errorf("los números de pedidos no cuadran: %+v", p)
	}
	if p.RutasActivas != 3 || p.TotalVehicles != 9 || p.VehiculosEnRuta != 2 {
		t.Errorf("los números de rutas y flota no cuadran: %+v", p)
	}
	if p.PesoPendiente != 1234.5 || p.TotalDomicilios != 987.25 {
		t.Errorf("los pesos e importes no cuadran: %+v", p)
	}
	if len(p.PorSucursal) != 2 {
		t.Fatalf("el desglose trae %d filas, se esperaban 2", len(p.PorSucursal))
	}
	if p.PorSucursal[0].Sucursal != "Holguín" || p.PorSucursal[0].Pedidos != 30 {
		t.Errorf("la primera fila del desglose es %+v", p.PorSucursal[0])
	}
	// Literal del contrato: sale en la pantalla tal cual.
	if p.PorSucursal[1].Sucursal != "Sin sucursal" {
		t.Errorf("un pedido sin sucursal tiene que salir como «Sin sucursal», salió %q", p.PorSucursal[1].Sucursal)
	}
}

// LA PRUEBA QUE IMPORTA. El fallo de delivery era contar por la cuenta que mira: dos
// personas distintas de la MISMA sucursal tienen que ver exactamente lo mismo, y la
// sucursal tiene que llegar a las CINCO consultas del panel.
func TestPanelCuentaPorSucursalYNoPorCuenta(t *testing.T) {
	nuevo := func() *dobleDePanel {
		return &dobleDePanel{
			resumen: sqlc.PanelResumenRow{TotalPedidos: 12, SinRuta: 4},
			rutas:   1, vehiculos: 2, enRuta: 1,
		}
	}

	q1 := nuevo()
	h1 := montarDePanel(t, q1)
	w1 := pedirDePanel(t, h1, "/api/dashboard",
		tokenDePanel(t, map[string]any{"sub": "quien-importo-los-pedidos", "role": "LOGISTICO", "branchId": holDePanel.String()}))

	q2 := nuevo()
	h2 := montarDePanel(t, q2)
	w2 := pedirDePanel(t, h2, "/api/dashboard",
		tokenDePanel(t, map[string]any{"sub": "el-logistico-de-holguin", "role": "LOGISTICO", "branchId": holDePanel.String()}))

	if w1.Body.String() != w2.Body.String() {
		t.Errorf("dos cuentas de la misma sucursal ven cosas distintas:\n%s\n%s", w1.Body, w2.Body)
	}

	// Las cinco consultas del panel, todas con la sucursal puesta. Si alguna llegara sin
	// acotar, esa tarjeta enseñaría las ocho sucursales.
	if len(q2.sucursalVista) != 5 {
		t.Fatalf("el panel hizo %d consultas acotadas, se esperaban 5", len(q2.sucursalVista))
	}
	for i, s := range q2.sucursalVista {
		if !s.Valid || uuid.UUID(s.Bytes) != holDePanel {
			t.Errorf("la consulta %d llegó con la sucursal %v, se esperaba Holguín", i, s)
		}
	}
}

// El Super Admin no tiene sucursal: las consultas van con NULL, que es «todas». Que llegara
// acotado a algo sería peor que un error — vería ceros y se los creería.
func TestPanelDelSuperAdminVaSinAcotar(t *testing.T) {
	q := &dobleDePanel{}
	h := montarDePanel(t, q)

	w := pedirDePanel(t, h, "/api/dashboard", tokenDePanel(t, map[string]any{"sub": "super", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	for i, s := range q.sucursalVista {
		if s.Valid {
			t.Errorf("la consulta %d llegó acotada a %v; el Super Admin las ve todas", i, s)
		}
	}
	// Y la lista vacía sale como `[]`, no como `null`: la pantalla la recorre sin mirar.
	if p := leerJSONDePanel[PanelSalida](t, w); p.PorSucursal == nil {
		t.Error("porSucursal salió como null; tiene que ser una lista vacía")
	}
}

func TestPanelSinSesionEs401(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	w := pedirDePanel(t, h, "/api/dashboard", "")
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d, se esperaba 401", w.Code)
	}
	if e := leerJSONDePanel[httpx.CuerpoError](t, w); e.Error != httpx.MsgNoAutorizado {
		t.Errorf("el cuerpo del 401 es %q, se esperaba %q", e.Error, httpx.MsgNoAutorizado)
	}
}

// `hoy` es las 00:00 del día EN LA ZONA DEL SERVIDOR. Si se calculara en UTC, «entregados
// hoy» arrancaría a las siete de la tarde de ayer para quien está en Cuba.
func TestMedianocheDeHoyEsLaDelDiaLocal(t *testing.T) {
	zona := time.FixedZone("CUB", -5*60*60)
	tarde := time.Date(2026, 9, 14, 23, 30, 0, 0, zona)

	m := medianocheDeHoy(tarde)
	if !m.Valid {
		t.Fatal("la medianoche salió sin valor")
	}
	if m.Time.Year() != 2026 || m.Time.Month() != time.September || m.Time.Day() != 14 {
		t.Errorf("la medianoche es de otro día: %s", m.Time)
	}
	if h, mi, s := m.Time.Clock(); h != 0 || mi != 0 || s != 0 {
		t.Errorf("la medianoche no está a las 00:00: %s", m.Time)
	}
	if m.Time.Location() != zona {
		t.Errorf("la medianoche cambió de zona: %s", m.Time.Location())
	}
}

func TestPanelPasaLaMedianocheALaConsulta(t *testing.T) {
	q := &dobleDePanel{}
	h := montarDePanel(t, q)
	pedirDePanel(t, h, "/api/dashboard", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))

	if !q.hoyVisto.Valid {
		t.Fatal("la consulta del panel no recibió el «hoy»")
	}
	esperado := medianocheDeHoy(time.Now())
	if !q.hoyVisto.Time.Equal(esperado.Time) {
		t.Errorf("la consulta recibió %s, se esperaba %s", q.hoyVisto.Time, esperado.Time)
	}
}
