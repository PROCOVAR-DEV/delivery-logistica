package api

// LOS CONDUCES CONTRA POSTGRES DE VERDAD (00029, `docs/conduces.md`): los tres endpoints, la visibilidad de los
// miembros en cada lista y su contador, el armado, el cierre con sus tres avisos y el espejo. Un doble reimplementa
// el SQL y no ve ninguna de estas reglas (`CLAUDE.md` §5): aquí se ejecutan las consultas reales dentro de una
// transacción que se revierte. Se salta sin REPARTO_MOTOR_REAL_DSN.

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

type entornoDeConduces struct {
	t        *testing.T
	ctx      context.Context
	tx       pgx.Tx
	h        http.Handler
	s        *Servidor
	stg, hol uuid.UUID
	jwt      string // LOGISTICO de Santiago
	jwtTodas string // SUPER ADMIN: ve las ocho
	avisados []AvisoDeParada
}

func nuevoEntornoDeConduces(t *testing.T) *entornoDeConduces {
	t.Helper()
	dsn := os.Getenv("REPARTO_MOTOR_REAL_DSN")
	if dsn == "" {
		t.Skip("requiere PostgreSQL aislado REPARTO_MOTOR_REAL_DSN")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
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
		t.Fatalf("la base %q no parece aislada: no se toca", base)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = tx.Rollback(context.Background()) })

	e := &entornoDeConduces{t: t, ctx: ctx, tx: tx}
	e.stg = e.id(`INSERT INTO branches (name, lat, lng, external_id, origin_configured)
	              VALUES ('Santiago', 19, -74, 'STG', true) RETURNING id`)
	e.hol = e.id(`INSERT INTO branches (name, lat, lng, external_id, origin_configured)
	              VALUES ('Holguín', 20.9, -76.2, 'HOL', true) RETURNING id`)

	conAccesos(t, &accesosFalso{sucursales: almacenesDeSantiagoDeAccesos()})
	contarAvisos(t)
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatal(err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDeMotorReal{q: sqlc.New(tx)}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	e.s = NuevoServidor(cfg, reg, porteria, verif, nil)
	// El canal hacia PEDIDO: se captura lo que saldría en vez de salir.
	e.s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		e.avisados = append(e.avisados, avisos...)
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}
	sesion := []httpx.Medio{verif.Exigir, porteria.Exigir}
	rt := httpx.NuevoRouter(httpx.ConRegistro(reg), httpx.SinCache)
	e.s.rutasPedidos(rt, sesion, nil)
	e.s.rutasConduces(rt, sesion)
	e.s.rutasDeReparto(rt, sesion, nil)
	e.s.rutasTablero(rt, sesion, nil)
	e.h = rt.Handler()
	e.jwt = tokenDeRutas(t, map[string]any{"sub": "p-conduce", "role": "LOGISTICO", "branchId": e.stg.String()})
	e.jwtTodas = tokenDeRutas(t, map[string]any{"sub": "p-admin", "role": "SUPER ADMIN"})
	return e
}

func (e *entornoDeConduces) id(sql string, args ...any) uuid.UUID {
	e.t.Helper()
	var u uuid.UUID
	if err := e.tx.QueryRow(e.ctx, sql, args...).Scan(&u); err != nil {
		e.t.Fatalf("siembra %q: %v", sql, err)
	}
	return u
}

func (e *entornoDeConduces) exec(sql string, args ...any) {
	e.t.Helper()
	if _, err := e.tx.Exec(e.ctx, sql, args...); err != nil {
		e.t.Fatalf("%q: %v", sql, err)
	}
}

// factura siembra una factura de Santiago lista para repartir: facturada, con punto, con folio de PEDIDO.
func (e *entornoDeConduces) factura(numero, cliente string, peso float64) uuid.UUID {
	return e.facturaDe(e.stg, "STG", numero, cliente, peso)
}

func (e *entornoDeConduces) facturaDe(suc uuid.UUID, codigo, numero, cliente string, peso float64) uuid.UUID {
	return e.id(`INSERT INTO orders (customer_name, operation_number, address, weight, branch_id, end_lat, end_lng, lat, lng,
	               source, external_id, factura_estado, factura_numero, folio, sucursal_codigo, factura_domicilio)
	             VALUES ($1, $2, 'calle', $3, $4, 20.1, -75.7, 20.1, -75.7,
	               'pedido', 'factura:'||$5::text||':1:'||$2::text||':20261020', 'igual', $2, 'FOLIO-'||$2::text, $5, 1)
	             RETURNING id`, cliente, numero, peso, suc, codigo)
}

func (e *entornoDeConduces) llamar(jwt, metodo, ruta, cuerpo string) (int, string) {
	e.t.Helper()
	w := llamarRutas(e.t, e.h, metodo, ruta, jwt, cuerpo)
	return w.Code, w.Body.String()
}

func (e *entornoDeConduces) crear(jwt string, principal uuid.UUID, ids ...uuid.UUID) (int, string) {
	textos := make([]string, 0, len(ids))
	for _, id := range ids {
		textos = append(textos, fmt.Sprintf("%q", id.String()))
	}
	return e.llamar(jwt, http.MethodPost, "/api/conduces",
		fmt.Sprintf(`{"principalId":%q,"ids":[%s]}`, principal.String(), strings.Join(textos, ",")))
}

func (e *entornoDeConduces) principalDe(id uuid.UUID) *uuid.UUID {
	e.t.Helper()
	var p *uuid.UUID
	if err := e.tx.QueryRow(e.ctx, `SELECT conduce_principal_id FROM orders WHERE id = $1`, id).Scan(&p); err != nil {
		e.t.Fatal(err)
	}
	return p
}

func (e *entornoDeConduces) numeroDeMiembros() int {
	e.t.Helper()
	var n int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM orders WHERE conduce_principal_id IS NOT NULL`).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n
}

func decodificar[T any](t *testing.T, cuerpo string) T {
	t.Helper()
	var v T
	if err := json.Unmarshal([]byte(cuerpo), &v); err != nil {
		t.Fatalf("la respuesta no es JSON: %v\n%s", err, cuerpo)
	}
	return v
}

type errorJSON struct {
	Error string `json:"error"`
}

// ---------------------------------------------------------------------------
// Crear, ampliar, sacar un miembro y deshacer — y lo que ven las listas
// ---------------------------------------------------------------------------

func TestMotorReal_Conduces_CrearAmpliarSacarYDeshacer(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47313", "Hector Luis Pérez", 10)
	b := e.factura("47314", "  hector   LUIS pérez ", 5) // el mismo cliente, escrito distinto
	c := e.factura("47315", "Hector Luis Pérez", 2)
	otra := e.factura("50000", "Otro Cliente", 1)

	// --- Crear: 201 con la principal y sus miembros --------------------------------------------
	code, cuerpo := e.crear(e.jwt, a, b)
	if code != http.StatusCreated {
		t.Fatalf("crear contestó %d: %s", code, cuerpo)
	}
	creado := decodificar[ConduceCreado](t, cuerpo)
	if creado.PrincipalID != a || len(creado.Miembros) != 1 || creado.Miembros[0] != b {
		t.Fatalf("respuesta = %+v", creado)
	}
	if p := e.principalDe(b); p == nil || *p != a {
		t.Fatalf("b tenía que quedar como miembro de a: %v", p)
	}
	if e.principalDe(a) != nil {
		t.Fatal("la principal no puede ser miembro")
	}

	// --- Los miembros NO salen como filas propias, y la principal lleva su conduce -------------
	// GET /api/orders: la lista y su contador dicen LO MISMO (CLAUDE.md §3-bis).
	code, cuerpo = e.llamar(e.jwt, http.MethodGet, "/api/orders", "")
	if code != http.StatusOK {
		t.Fatalf("GET /api/orders: %d %s", code, cuerpo)
	}
	lista := decodificar[struct {
		Orders []struct {
			ID                 uuid.UUID      `json:"id"`
			ConducePrincipalID *uuid.UUID     `json:"conducePrincipalId"`
			Conduce            *ConduceSalida `json:"conduce"`
		} `json:"orders"`
		Total int64 `json:"total"`
	}](t, cuerpo)
	vistos := map[uuid.UUID]bool{}
	for _, o := range lista.Orders {
		vistos[o.ID] = true
		if o.ID == a {
			if o.Conduce == nil || o.Conduce.Miembros != 1 || len(o.Conduce.Facturas) != 2 ||
				o.Conduce.Facturas[0] != "47313" || o.Conduce.Facturas[1] != "47314" {
				t.Fatalf("la principal tenía que traer conduce {47313, 47314}: %+v", o.Conduce)
			}
		} else if o.Conduce != nil {
			t.Fatalf("%s trae conduce y no es una principal", o.ID)
		}
	}
	if vistos[b] || !vistos[a] || !vistos[c] || !vistos[otra] {
		t.Fatalf("GET /api/orders: %v (b es miembro y no sale; a, c y otra sí)", vistos)
	}
	if lista.Total != int64(len(lista.Orders)) {
		t.Fatalf("el contador dice %d y la lista trae %d", lista.Total, len(lista.Orders))
	}

	// /available y su contador.
	code, cuerpo = e.llamar(e.jwt, http.MethodGet, "/api/orders/available", "")
	if code != http.StatusOK {
		t.Fatalf("available: %d %s", code, cuerpo)
	}
	disp := decodificar[struct {
		Orders []struct {
			ID      uuid.UUID      `json:"id"`
			Conduce *ConduceSalida `json:"conduce"`
		} `json:"orders"`
		Total int64 `json:"total"`
	}](t, cuerpo)
	conConduce := false
	for _, o := range disp.Orders {
		if o.ID == b {
			t.Fatal("un miembro salió en los disponibles")
		}
		if o.ID == a && o.Conduce != nil && o.Conduce.Miembros == 1 {
			conConduce = true
		}
	}
	if !conConduce || disp.Total != int64(len(disp.Orders)) || disp.Total != 3 {
		t.Fatalf("disponibles: total %d, %d filas, conduce visible %v (esperaba 3: a, c y otra)", disp.Total, len(disp.Orders), conConduce)
	}

	// «Sin colocar» y su contador.
	code, cuerpo = e.llamar(e.jwt, http.MethodGet, "/api/board/unplaced?branchId="+e.stg.String(), "")
	if code != http.StatusOK {
		t.Fatalf("unplaced: %d %s", code, cuerpo)
	}
	sin := decodificar[struct {
		Orders []struct {
			ID uuid.UUID `json:"id"`
		} `json:"pedidos"`
		Total int64 `json:"total"`
	}](t, cuerpo)
	for _, o := range sin.Orders {
		if o.ID == b {
			t.Fatal("un miembro salió en «Sin colocar»")
		}
	}
	if sin.Total != int64(len(sin.Orders)) || sin.Total != 3 {
		t.Fatalf("sin colocar: total %d y %d filas (esperaba 3)", sin.Total, len(sin.Orders))
	}

	// El panel cuenta filas propias (3) pero pesa las cuatro facturas... las tres sin ruta: 10+5+2+1 = 18.
	var filas int64
	var peso float64
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FILTER (WHERE conduce_principal_id IS NULL), coalesce(sum(weight),0)
	                                FROM orders WHERE branch_id = $1`, e.stg).Scan(&filas, &peso); err != nil {
		t.Fatal(err)
	}
	if filas != 3 || peso != 18 {
		t.Fatalf("siembra rara: %d filas propias, %v kg", filas, peso)
	}

	// --- La ficha de un miembro dice su principal ---------------------------------------------
	code, cuerpo = e.llamar(e.jwt, http.MethodGet, "/api/orders/"+b.String(), "")
	if code != http.StatusOK {
		t.Fatalf("ficha del miembro: %d %s", code, cuerpo)
	}
	if ficha := decodificar[struct {
		ConducePrincipalID *uuid.UUID `json:"conducePrincipalId"`
	}](t, cuerpo); ficha.ConducePrincipalID == nil || *ficha.ConducePrincipalID != a {
		t.Fatalf("la ficha del miembro tenía que traer conducePrincipalId = %s: %s", a, cuerpo)
	}

	// --- Ampliar un conduce que ya existe: la principal SÍ puede ser ya principal --------------
	code, cuerpo = e.crear(e.jwt, a, c)
	if code != http.StatusCreated {
		t.Fatalf("ampliar contestó %d: %s", code, cuerpo)
	}
	if m := decodificar[ConduceCreado](t, cuerpo).Miembros; len(m) != 2 || m[0] != b || m[1] != c {
		t.Fatalf("tras ampliar, los miembros tienen que ser [b, c] por número de factura: %v", m)
	}

	// --- Sacar un miembro ---------------------------------------------------------------------
	code, cuerpo = e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+a.String()+"/miembros/"+b.String(), "")
	if code != http.StatusOK {
		t.Fatalf("sacar contestó %d: %s", code, cuerpo)
	}
	if e.principalDe(b) != nil || e.principalDe(c) == nil {
		t.Fatal("sacar b tenía que soltar sólo a b")
	}
	// Sacar a quien no es de ese conduce.
	code, cuerpo = e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+a.String()+"/miembros/"+b.String(), "")
	if code != http.StatusNotFound || decodificar[errorJSON](t, cuerpo).Error != "La factura 47314 no es miembro de ese conduce" {
		t.Fatalf("sacar a quien ya no es miembro: %d %s", code, cuerpo)
	}

	// --- Deshacer ----------------------------------------------------------------------------
	code, cuerpo = e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+a.String(), "")
	if code != http.StatusOK {
		t.Fatalf("deshacer contestó %d: %s", code, cuerpo)
	}
	if d := decodificar[ConduceDeshecho](t, cuerpo); d.PrincipalID != a || len(d.Liberados) != 1 || d.Liberados[0] != c {
		t.Fatalf("deshacer = %+v", d)
	}
	if e.numeroDeMiembros() != 0 {
		t.Fatal("deshacer dejó miembros")
	}
	code, cuerpo = e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+a.String(), "")
	if code != http.StatusNotFound || decodificar[errorJSON](t, cuerpo).Error != "La factura 47313 no encabeza ningún conduce" {
		t.Fatalf("deshacer lo que no es un conduce: %d %s", code, cuerpo)
	}
}

// Un miembro que tenía tarjeta en una zona la pierde: va dentro de su principal y ya no se coloca.
func TestMotorReal_Conduces_UnMiembroPierdeSuTarjetaDeLaZona(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("1", "Cliente", 1)
	b := e.factura("2", "Cliente", 1)
	zona := e.id(`INSERT INTO board_columns (branch_id, nombre, posicion) VALUES ($1, 'Centro', 1) RETURNING id`, e.stg)
	e.exec(`INSERT INTO board_placements (order_id, column_id, posicion) VALUES ($1, $3, 1), ($2, $3, 2)`, a, b, zona)
	if code, cuerpo := e.crear(e.jwt, a, b); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}
	var n int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM board_placements WHERE order_id = $1`, b).Scan(&n); err != nil || n != 0 {
		t.Fatalf("el miembro conserva su tarjeta (%d, %v)", n, err)
	}
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM board_placements WHERE order_id = $1`, a).Scan(&n); err != nil || n != 1 {
		t.Fatalf("la principal perdió la suya (%d, %v)", n, err)
	}
}

// ---------------------------------------------------------------------------
// Los rechazos: motivo literal, estado y NADA escrito
// ---------------------------------------------------------------------------

func TestMotorReal_Conduces_LosRechazos(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47313", "Hector Luis", 1)
	b := e.factura("47314", "Hector Luis", 1)
	c := e.factura("47315", "Hector Luis", 1)
	otroCliente := e.factura("47400", "Maria Perez", 1)
	deHolguin := e.facturaDe(e.hol, "HOL", "47500", "Hector Luis", 1)
	ruta := e.id(`INSERT INTO routes (branch_id, status, name, route_code, origin_lat, origin_lng, total_distance, optimized)
	              VALUES ($1, 'planned', 'r', 'RT-20261027-001', 20, -75.8, 1, false) RETURNING id`, e.stg)
	enRuta := e.factura("47600", "Hector Luis", 1)
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 1 WHERE id = $1`, enRuta, ruta)
	entregada := e.factura("47601", "Hector Luis", 1)
	e.exec(`UPDATE orders SET resultado = 'entregado', delivered_at = now() WHERE id = $1`, entregada)
	devuelta := e.factura("47602", "Hector Luis", 1)
	e.exec(`UPDATE orders SET resultado = 'devuelto' WHERE id = $1`, devuelta)
	archivada := e.factura("47603", "Hector Luis", 1)
	e.exec(`UPDATE orders SET archivado = true WHERE id = $1`, archivada)
	// Un conduce que ya existe: x principal, y miembro.
	x := e.factura("47700", "Hector Luis", 1)
	y := e.factura("47701", "Hector Luis", 1)
	if code, cuerpo := e.crear(e.jwt, x, y); code != http.StatusCreated {
		t.Fatalf("siembra del conduce: %d %s", code, cuerpo)
	}
	base := e.numeroDeMiembros()

	raro := uuid.New()
	casos := []struct {
		nombre string
		jwt    string
		cuerpo string
		code   int
		motivo string // literal, o "" si sólo se mira el código
	}{
		{"sin ids", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[]}`, a), 422, msgConduceSinIds},
		{"sin el campo ids", e.jwt, fmt.Sprintf(`{"principalId":%q}`, a), 422, msgConduceSinIds},
		{"principalId que no es un id", e.jwt, `{"principalId":"no","ids":["x"]}`, 422, msgConduceIdMalo},
		{"ids repetidos", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q,%q]}`, a, b, b), 422, "La factura 47314 está repetida"},
		{"la principal entre las demás", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, a), 422, "La factura 47313 es la principal: no va también entre las demás"},
		{"otro cliente", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q,%q]}`, a, b, otroCliente), 422,
			"La factura 47400 es de otro cliente (Maria Perez): un conduce junta facturas de un solo cliente"},
		{"otra sucursal (quien ve todas)", e.jwtTodas, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, deHolguin), 422,
			"La factura 47500 es de otra sucursal: un conduce no mezcla sucursales"},
		{"otra sucursal (quien sólo ve la suya: 404)", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, deHolguin), 404, httpx.MsgNoEncontrado},
		{"una factura que no existe", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, raro), 404, httpx.MsgNoEncontrado},
		{"ya va en una ruta", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, enRuta), 409, "La factura 47600 ya va en la ruta RT-20261027-001"},
		{"la principal ya va en una ruta", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, enRuta, a), 409, "La factura 47600 ya va en la ruta RT-20261027-001"},
		{"ya está entregada", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, entregada), 409, "La factura 47601 ya está entregada"},
		{"ya tiene resultado", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, devuelta), 409, "La factura 47602 ya tiene resultado (devuelto)"},
		{"archivada", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, archivada), 409, "La factura 47603 está archivada"},
		{"ya es miembro de otro conduce", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, y), 409, "La factura 47701 ya es miembro del conduce 47700"},
		{"la principal es miembro de otro", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, y, a), 409, "La factura 47701 es miembro del conduce 47700: no puede ser la principal"},
		{"una de las demás ya es principal de otro conduce", e.jwt, fmt.Sprintf(`{"principalId":%q,"ids":[%q]}`, a, x), 409, "La factura 47700 ya es la principal de otro conduce"},
	}
	for _, k := range casos {
		code, cuerpo := e.llamar(k.jwt, http.MethodPost, "/api/conduces", k.cuerpo)
		if code != k.code {
			t.Errorf("%s: contestó %d y tenía que ser %d: %s", k.nombre, code, k.code, cuerpo)
			continue
		}
		if got := decodificar[errorJSON](t, cuerpo).Error; got != k.motivo {
			t.Errorf("%s: el motivo era %q y tenía que ser %q", k.nombre, got, k.motivo)
		}
		if n := e.numeroDeMiembros(); n != base {
			t.Errorf("%s: el rechazo escribió algo (%d miembros, había %d)", k.nombre, n, base)
		}
	}
	_ = c

	// --- Deshacer y sacar también se niegan si algo del conduce va en una ruta o tiene resultado --
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 2 WHERE id = $1`, y, ruta)
	if code, cuerpo := e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+x.String(), ""); code != 409 ||
		decodificar[errorJSON](t, cuerpo).Error != "La factura 47701 ya va en la ruta RT-20261027-001" {
		t.Errorf("deshacer con un miembro en ruta: %d %s", code, cuerpo)
	}
	if code, cuerpo := e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+x.String()+"/miembros/"+y.String(), ""); code != 409 ||
		decodificar[errorJSON](t, cuerpo).Error != "La factura 47701 ya va en la ruta RT-20261027-001" {
		t.Errorf("sacar con el miembro en ruta: %d %s", code, cuerpo)
	}
	if e.numeroDeMiembros() != base {
		t.Error("el rechazo de deshacer/sacar escribió algo")
	}
	// Deshacer un miembro (no una principal): su motivo manda a deshacer el conduce.
	e.exec(`UPDATE orders SET route_id = NULL, ultima_ruta_id = NULL, stop_order = NULL WHERE id = $1`, y)
	if code, cuerpo := e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+y.String(), ""); code != 409 ||
		decodificar[errorJSON](t, cuerpo).Error != "La factura 47701 es miembro del conduce 47700: deshaz ese" {
		t.Errorf("deshacer desde un miembro: %d %s", code, cuerpo)
	}
	// Un conduce con resultado en la principal (historial) tampoco se deshace.
	e.exec(`UPDATE orders SET resultado = 'devuelto' WHERE id = $1`, x)
	if code, cuerpo := e.llamar(e.jwt, http.MethodDelete, "/api/conduces/"+x.String(), ""); code != 409 ||
		decodificar[errorJSON](t, cuerpo).Error != "La factura 47700 ya tiene resultado (devuelto)" {
		t.Errorf("deshacer con resultado: %d %s", code, cuerpo)
	}
	// Y sin sesión, 401.
	if code, _ := e.llamar("", http.MethodPost, "/api/conduces", `{}`); code != http.StatusUnauthorized {
		t.Errorf("sin sesión contestó %d", code)
	}
}

// LA ESCRITURA REPITE LAS GUARDAS. El manejador lee antes para NOMBRAR la factura que lo impide, pero entre la
// lectura y la escritura puede cambiar cualquier cosa: `CrearConduce` no puede fiarse de esa lectura. Aquí se le
// llama DIRECTAMENTE, sin pasar por el manejador, con cada caso que el manejador ya habría rechazado.
func TestMotorReal_Conduces_LaEscrituraRepiteLasGuardas(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	q := sqlc.New(e.tx)
	principal := e.factura("1", "Cliente", 1)
	ruta := e.id(`INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng, total_distance, optimized)
	              VALUES ($1, 'planned', 'r', 20, -75.8, 1, false) RETURNING id`, e.stg)
	enRuta := e.factura("2", "Cliente", 1)
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 1 WHERE id = $1`, enRuta, ruta)
	conResultado := e.factura("3", "Cliente", 1)
	e.exec(`UPDATE orders SET resultado = 'devuelto' WHERE id = $1`, conResultado)
	entregada := e.factura("4", "Cliente", 1)
	e.exec(`UPDATE orders SET delivered_at = now() WHERE id = $1`, entregada)
	archivada := e.factura("5", "Cliente", 1)
	e.exec(`UPDATE orders SET archivado = true WHERE id = $1`, archivada)
	deHolguin := e.facturaDe(e.hol, "HOL", "6", "Cliente", 1)
	ya := e.factura("7", "Cliente", 1)
	otraPrincipal := e.factura("8", "Cliente", 1)
	e.exec(`UPDATE orders SET conduce_principal_id = $2 WHERE id = $1`, ya, otraPrincipal)

	for nombre, ids := range map[string][]uuid.UUID{
		"en una ruta": {enRuta}, "con resultado": {conResultado}, "entregada": {entregada}, "archivada": {archivada},
		"de otra sucursal": {deHolguin}, "ya miembro": {ya}, "principal de otro": {otraPrincipal}, "ella misma": {principal},
	} {
		hechos, err := q.CrearConduce(e.ctx, sqlc.CrearConduceParams{PrincipalID: principal, Ids: ids})
		if err != nil || len(hechos) != 0 {
			t.Errorf("%s: CrearConduce juntó %v (err %v) y tenía que juntar nada", nombre, hechos, err)
		}
	}
	// Con una principal que no sirve (en una ruta), tampoco junta a nadie.
	libre := e.factura("9", "Cliente", 1)
	if hechos, err := q.CrearConduce(e.ctx, sqlc.CrearConduceParams{PrincipalID: enRuta, Ids: []uuid.UUID{libre}}); err != nil || len(hechos) != 0 {
		t.Errorf("principal en una ruta: juntó %v (err %v)", hechos, err)
	}
	// Con el alcance de otra sucursal no junta lo de Santiago.
	stg := pgDe(e.stg)
	hol := pgDe(e.hol)
	_ = stg
	if hechos, err := q.CrearConduce(e.ctx, sqlc.CrearConduceParams{PrincipalID: principal, Ids: []uuid.UUID{libre}, Sucursal: hol}); err != nil || len(hechos) != 0 {
		t.Errorf("con el alcance de Holguín juntó %v (err %v)", hechos, err)
	}
	// Y la buena sí.
	if hechos, err := q.CrearConduce(e.ctx, sqlc.CrearConduceParams{PrincipalID: principal, Ids: []uuid.UUID{libre}}); err != nil || len(hechos) != 1 {
		t.Errorf("el caso bueno juntó %v (err %v) y tenía que juntar 1", hechos, err)
	}
	// Deshacer y sacar también repiten la guarda de ruta/resultado.
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2 WHERE id = $1`, libre, ruta)
	if ids, err := q.DeshacerConduce(e.ctx, sqlc.DeshacerConduceParams{PrincipalID: principal}); err != nil || len(ids) != 0 {
		t.Errorf("deshacer con un miembro en ruta liberó %v (err %v)", ids, err)
	}
	if n, err := q.SacarMiembroDeConduce(e.ctx, sqlc.SacarMiembroDeConduceParams{ID: libre, PrincipalID: principal}); err != nil || n != 0 {
		t.Errorf("sacar con el miembro en ruta sacó %d (err %v)", n, err)
	}
}

// ---------------------------------------------------------------------------
// Armar, colocar, totales y una parada por conduce
// ---------------------------------------------------------------------------

func TestMotorReal_Conduces_ArmarMueveElConduceEnteroYCuentaUnaParada(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47313", "Hector Luis", 10)
	b := e.factura("47314", "Hector Luis", 5)
	d := e.factura("47315", "Otro", 2)
	// a cuesta 1 (factura_domicilio), b y d también (la siembra les da factura_domicilio = 1): el importe de la ruta
	// es la suma de las TRES facturas y el peso, 17.
	if code, cuerpo := e.crear(e.jwt, a, b); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}

	// Un MIEMBRO suelto no se arma: motivo literal.
	body := func(ids ...uuid.UUID) string {
		textos := make([]string, 0, len(ids))
		for _, id := range ids {
			textos = append(textos, fmt.Sprintf("%q", id.String()))
		}
		return fmt.Sprintf(`{"vehicleId":"sin-camion","originLat":20.0,"originLng":-75.8,"orderIds":[%s]}`, strings.Join(textos, ","))
	}
	code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/routes", body(b, d))
	if code != http.StatusConflict || decodificar[errorJSON](t, cuerpo).Error != "Esa factura va dentro del conduce 47313: arma el conduce entero" {
		t.Fatalf("armar un miembro suelto: %d %s", code, cuerpo)
	}
	var enRuta int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM orders WHERE route_id IS NOT NULL`).Scan(&enRuta); err != nil || enRuta != 0 {
		t.Fatalf("el rechazo armó algo (%d, %v)", enRuta, err)
	}
	// Colocar un miembro en una zona: lo mismo.
	zona := e.id(`INSERT INTO board_columns (branch_id, nombre, posicion) VALUES ($1, 'Centro', 1) RETURNING id`, e.stg)
	code, cuerpo = e.llamar(e.jwt, http.MethodPut, "/api/board/placements/"+b.String(), fmt.Sprintf(`{"columnaId":%q}`, zona))
	if code != http.StatusConflict || decodificar[errorJSON](t, cuerpo).Error != "Esa factura va dentro del conduce 47313: arma el conduce entero" {
		t.Fatalf("colocar un miembro suelto: %d %s", code, cuerpo)
	}

	// La capacidad del camión se mide contra el conduce ENTERO (15 kg), no contra la principal sola (10).
	tipo := e.id(`INSERT INTO vehicle_types (nombre) VALUES ('Camión de prueba') RETURNING id`)
	chico := e.id(`INSERT INTO vehicles (name, vehicle_type_id, capacity, branch_id) VALUES ('Chico', $1, 12, $2) RETURNING id`, tipo, e.stg)
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes",
		fmt.Sprintf(`{"vehicleId":%q,"originLat":20.0,"originLng":-75.8,"orderIds":[%q]}`, chico, a))
	if code != http.StatusBadRequest || !strings.Contains(cuerpo, "supera la capacidad") {
		t.Fatalf("un conduce de 15 kg en un camión de 12 tenía que rechazarse por capacidad: %d %s", code, cuerpo)
	}

	// Armar la principal (con otra suelta): el conduce entra entero.
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes", body(a, d))
	if code != http.StatusCreated {
		t.Fatalf("armar: %d %s", code, cuerpo)
	}
	ruta := decodificar[struct {
		ID     uuid.UUID `json:"id"`
		Orders []struct {
			ID          uuid.UUID `json:"id"`
			Weight      float64   `json:"weight"`
			PedidoCosto *float64  `json:"pedidoCosto"`
		} `json:"orders"`
		TotalWeight float64 `json:"totalWeight"`
		TotalPrice  float64 `json:"totalPrice"`
	}](t, cuerpo)
	var rb struct {
		ruta, ultima *uuid.UUID
		orden        *int32
		resultado    *string
	}
	if err := e.tx.QueryRow(e.ctx, `SELECT route_id, ultima_ruta_id, stop_order, resultado::text FROM orders WHERE id = $1`, b).
		Scan(&rb.ruta, &rb.ultima, &rb.orden, &rb.resultado); err != nil {
		t.Fatal(err)
	}
	if rb.ruta == nil || *rb.ruta != ruta.ID || rb.ultima == nil || *rb.ultima != ruta.ID || rb.orden != nil {
		t.Fatalf("el miembro tenía que entrar a la ruta SIN stop_order: %+v", rb)
	}
	// UNA PARADA POR CONDUCE: la ruta enseña 2 paradas (a+b, d), no 3, y la del conduce pesa y cuesta las dos.
	if len(ruta.Orders) != 2 {
		t.Fatalf("la ruta enseña %d paradas y tenían que ser 2 (el conduce y la suelta): %+v", len(ruta.Orders), ruta.Orders)
	}
	for _, p := range ruta.Orders {
		if p.ID == b {
			t.Fatal("el miembro salió como parada")
		}
		if p.ID == a && (p.Weight != 15 || p.PedidoCosto == nil || *p.PedidoCosto != 2) {
			t.Fatalf("la parada del conduce tenía que pesar 15 y costar 2: %+v", p)
		}
	}
	// Los totales de la ruta suman TODAS las filas.
	if ruta.TotalWeight != 17 || ruta.TotalPrice != 3 {
		t.Fatalf("totales de la ruta: %v kg y %v (esperaba 17 y 3)", ruta.TotalWeight, ruta.TotalPrice)
	}
	var sinCotizar int
	if err := e.tx.QueryRow(e.ctx, `SELECT paradas_sin_cotizar FROM routes WHERE id = $1`, ruta.ID).Scan(&sinCotizar); err != nil || sinCotizar != 0 {
		t.Fatalf("paradas_sin_cotizar = %d (%v) y tenía que ser 0", sinCotizar, err)
	}
	// «n paradas» del listado de rutas.
	code, cuerpo = e.llamar(e.jwt, http.MethodGet, "/api/routes", "")
	if code != http.StatusOK {
		t.Fatalf("GET /api/routes: %d %s", code, cuerpo)
	}
	if l := decodificar[[]struct {
		ID     uuid.UUID      `json:"id"`
		Orders []ParadaSalida `json:"orders"`
	}](t, cuerpo); len(l) != 1 || len(l[0].Orders) != 2 {
		t.Fatalf("el listado dice %+v y tenía que enseñar 2 paradas", l)
	}
	// Y el «n paradas» que baja al aparato (`ListarRutas.paradas`) cuenta UNA por conduce.
	rutas, err := sqlc.New(e.tx).ListarRutas(e.ctx, sqlc.ListarRutasParams{})
	if err != nil || len(rutas) != 1 || rutas[0].Paradas != 2 {
		t.Fatalf("ListarRutas.paradas = %+v (%v) y tenía que ser 2", rutas, err)
	}

	// Quitar un MIEMBRO de la ruta no se puede: la parada es el conduce.
	code, cuerpo = e.llamar(e.jwt, http.MethodDelete, "/api/routes/"+ruta.ID.String()+"/stops/"+b.String(), "")
	if code != http.StatusConflict || decodificar[errorJSON](t, cuerpo).Error != "Esa factura va dentro del conduce 47313: arma el conduce entero" {
		t.Fatalf("quitar un miembro de la ruta: %d %s", code, cuerpo)
	}
	// Quitar la PRINCIPAL suelta a los miembros con ella; siguen en su conduce.
	code, cuerpo = e.llamar(e.jwt, http.MethodDelete, "/api/routes/"+ruta.ID.String()+"/stops/"+a.String(), "")
	if code != http.StatusOK {
		t.Fatalf("quitar la principal: %d %s", code, cuerpo)
	}
	if err := e.tx.QueryRow(e.ctx, `SELECT route_id, ultima_ruta_id, stop_order, resultado::text FROM orders WHERE id = $1`, b).
		Scan(&rb.ruta, &rb.ultima, &rb.orden, &rb.resultado); err != nil {
		t.Fatal(err)
	}
	if rb.ruta != nil || rb.ultima != nil {
		t.Fatalf("el miembro siguió en la ruta al quitar a su principal: %+v", rb)
	}
	if p := e.principalDe(b); p == nil || *p != a {
		t.Fatal("quitar de la ruta no puede deshacer el conduce")
	}
	var pesoDeLaRuta float64
	if err := e.tx.QueryRow(e.ctx, `SELECT total_weight FROM routes WHERE id = $1`, ruta.ID).Scan(&pesoDeLaRuta); err != nil || pesoDeLaRuta != 2 {
		t.Fatalf("total_weight tras quitar el conduce = %v (%v); sólo queda la suelta de 2", pesoDeLaRuta, err)
	}

	// Volver a armar el mismo conduce es un intento nuevo y entra entero; y BORRAR esa ruta los suelta a los tres.
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes", body(a))
	if code != http.StatusCreated {
		t.Fatalf("rearmar el conduce: %d %s", code, cuerpo)
	}
	otra := decodificar[struct {
		ID uuid.UUID `json:"id"`
	}](t, cuerpo).ID
	if err := e.tx.QueryRow(e.ctx, `SELECT route_id FROM orders WHERE id = $1`, b).Scan(&rb.ruta); err != nil || rb.ruta == nil || *rb.ruta != otra {
		t.Fatalf("al rearmar, el miembro tenía que volver a entrar con su principal: %v %v", rb.ruta, err)
	}
	if code, cuerpo = e.llamar(e.jwt, http.MethodDelete, "/api/routes/"+otra.String(), ""); code != http.StatusOK {
		t.Fatalf("borrar la ruta: %d %s", code, cuerpo)
	}
	var enAlguna int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM orders WHERE id IN ($1, $2) AND route_id IS NOT NULL`, a, b).Scan(&enAlguna); err != nil || enAlguna != 0 {
		t.Fatalf("borrar la ruta dejó %d del conduce en ella (%v)", enAlguna, err)
	}
	if p := e.principalDe(b); p == nil || *p != a {
		t.Fatal("borrar la ruta no puede deshacer el conduce")
	}
}

// «Paradas sin cotizar» cuenta PARADAS: un conduce está sin cotizar sólo si NINGUNA de sus facturas trae costo, y un
// miembro sin costo no suma una parada más (00029, `totales_de_ruta`).
func TestMotorReal_Conduces_ParadasSinCotizarCuentaConduces(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	sinCosto := func(numero, cliente string) uuid.UUID {
		id := e.factura(numero, cliente, 1)
		e.exec(`UPDATE orders SET factura_domicilio = NULL WHERE id = $1`, id)
		return id
	}
	// Conduce 1: la principal y un miembro sin costo, otro miembro CON costo -> cotizado (0 sin cotizar).
	p1, m1a := sinCosto("1", "Uno"), sinCosto("2", "Uno")
	m1b := e.factura("3", "Uno", 1)
	// Conduce 2: nadie trae costo -> UNA parada sin cotizar (no dos).
	p2, m2a := sinCosto("4", "Dos"), sinCosto("5", "Dos")
	// Y una suelta sin costo -> otra.
	suelta := sinCosto("6", "Tres")
	for _, par := range [][]uuid.UUID{{p1, m1a, m1b}, {p2, m2a}} {
		if code, cuerpo := e.crear(e.jwt, par[0], par[1:]...); code != http.StatusCreated {
			t.Fatalf("crear: %d %s", code, cuerpo)
		}
	}
	code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/routes",
		fmt.Sprintf(`{"vehicleId":"sin-camion","originLat":20.0,"originLng":-75.8,"orderIds":[%q,%q,%q]}`, p1, p2, suelta))
	if code != http.StatusCreated {
		t.Fatalf("armar: %d %s", code, cuerpo)
	}
	ruta := decodificar[struct {
		ID uuid.UUID `json:"id"`
	}](t, cuerpo).ID
	var sin int
	if err := e.tx.QueryRow(e.ctx, `SELECT paradas_sin_cotizar FROM routes WHERE id = $1`, ruta).Scan(&sin); err != nil || sin != 2 {
		t.Fatalf("paradas_sin_cotizar = %d (%v) y tenía que ser 2: el conduce 2 y la suelta (el conduce 1 tiene un miembro cotizado)", sin, err)
	}
}

// El armado desde una ZONA del tablero mueve también los miembros, y la zona pesa el conduce entero.
func TestMotorReal_Conduces_ArmarDesdeUnaZonaDelTablero(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47313", "Hector Luis", 10)
	b := e.factura("47314", "Hector Luis", 5)
	if code, cuerpo := e.crear(e.jwt, a, b); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}
	tipo := e.id(`INSERT INTO vehicle_types (nombre) VALUES ('Camión de prueba') RETURNING id`)
	camion := e.id(`INSERT INTO vehicles (name, vehicle_type_id, capacity, branch_id) VALUES ('C1', $1, 1000, $2) RETURNING id`, tipo, e.stg)
	zona := e.id(`INSERT INTO board_columns (branch_id, nombre, posicion, vehicle_id) VALUES ($1, 'Centro', 1, $2) RETURNING id`, e.stg, camion)
	if code, cuerpo := e.llamar(e.jwt, http.MethodPut, "/api/board/placements/"+a.String(), fmt.Sprintf(`{"columnaId":%q}`, zona)); code != http.StatusOK {
		t.Fatalf("colocar la principal: %d %s", code, cuerpo)
	}
	// La tarjeta de la zona pesa el conduce entero: 15, no 10.
	code, cuerpo := e.llamar(e.jwt, http.MethodGet, "/api/board?branchId="+e.stg.String(), "")
	if code != http.StatusOK {
		t.Fatalf("GET /api/board: %d %s", code, cuerpo)
	}
	if !strings.Contains(cuerpo, `"pesoKg":15`) {
		t.Fatalf("la zona tenía que pesar 15 kg (el conduce entero): %s", cuerpo)
	}
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/board/columns/"+zona.String()+"/route", `{"nombre":"r"}`)
	if code != http.StatusCreated && code != http.StatusOK {
		t.Fatalf("armar la zona: %d %s", code, cuerpo)
	}
	var rutaA, rutaB *uuid.UUID
	var ordenB *int32
	if err := e.tx.QueryRow(e.ctx, `SELECT route_id FROM orders WHERE id = $1`, a).Scan(&rutaA); err != nil {
		t.Fatal(err)
	}
	if err := e.tx.QueryRow(e.ctx, `SELECT route_id, stop_order FROM orders WHERE id = $1`, b).Scan(&rutaB, &ordenB); err != nil {
		t.Fatal(err)
	}
	if rutaA == nil || rutaB == nil || *rutaA != *rutaB || ordenB != nil {
		t.Fatalf("la zona tenía que llevarse a los dos a la misma ruta, el miembro sin stop_order: a=%v b=%v orden=%v", rutaA, rutaB, ordenB)
	}
}

// ---------------------------------------------------------------------------
// El cierre: el resultado de la principal se aplica a los miembros y CADA factura avisa
// ---------------------------------------------------------------------------

func TestMotorReal_Conduces_ElCierreAplicaAMiembrosYAvisaPorCadaFactura(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47313", "Hector Luis", 10)
	b := e.factura("47314", "Hector Luis", 5)
	c := e.factura("47315", "Hector Luis", 2)
	d := e.factura("47400", "Otro", 1)
	if code, cuerpo := e.crear(e.jwt, a, b, c); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}
	code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/routes",
		fmt.Sprintf(`{"vehicleId":"sin-camion","originLat":20.0,"originLng":-75.8,"orderIds":[%q,%q]}`, a, d))
	if code != http.StatusCreated {
		t.Fatalf("armar: %d %s", code, cuerpo)
	}
	ruta := decodificar[struct {
		ID uuid.UUID `json:"id"`
	}](t, cuerpo).ID
	e.avisados = nil // lo del armado (despachado) no es lo que se prueba aquí

	// Un MIEMBRO marcado solo se rechaza con su motivo, y no toca nada.
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes/"+ruta.String()+"/results",
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, b))
	if code != http.StatusConflict {
		t.Fatalf("marcar un miembro solo: %d %s", code, cuerpo)
	}
	if rz := decodificar[struct {
		Rechazados []struct {
			Motivo string `json:"motivo"`
		} `json:"rechazados"`
	}](t, cuerpo).Rechazados; len(rz) != 1 || rz[0].Motivo != "Esa factura va dentro del conduce 47313: arma el conduce entero" {
		t.Fatalf("el rechazo del miembro: %s", cuerpo)
	}
	if len(e.avisados) != 0 {
		t.Fatalf("un rechazo avisó a PEDIDO: %+v", e.avisados)
	}

	// Marcar la principal: 200, y el resultado vale para las tres filas.
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes/"+ruta.String()+"/results",
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado","nota":"lo recibió la hija"}]}`, a))
	if code != http.StatusOK {
		t.Fatalf("cerrar: %d %s", code, cuerpo)
	}
	sal := decodificar[struct {
		Aplicados []struct {
			OrderID  string   `json:"orderId"`
			Miembros []string `json:"miembros"`
		} `json:"aplicados"`
		Rechazados []any `json:"rechazados"`
	}](t, cuerpo)
	if len(sal.Aplicados) != 1 || sal.Aplicados[0].OrderID != a.String() || len(sal.Aplicados[0].Miembros) != 2 || len(sal.Rechazados) != 0 {
		t.Fatalf("aplicados/rechazados hablan de PARADAS (la principal), con sus miembros dentro: %s", cuerpo)
	}
	for _, id := range []uuid.UUID{a, b, c} {
		var res, nota *string
		var entregada bool
		var rid *uuid.UUID
		if err := e.tx.QueryRow(e.ctx, `SELECT resultado::text, resultado_nota, delivered_at IS NOT NULL, route_id FROM orders WHERE id = $1`, id).
			Scan(&res, &nota, &entregada, &rid); err != nil {
			t.Fatal(err)
		}
		if res == nil || *res != "entregado" || nota == nil || *nota != "lo recibió la hija" || !entregada || rid == nil {
			t.Fatalf("%s: resultado=%v nota=%v entregada=%v ruta=%v", id, res, nota, entregada, rid)
		}
	}
	var dRes *string
	if err := e.tx.QueryRow(e.ctx, `SELECT resultado::text FROM orders WHERE id = $1`, d).Scan(&dRes); err != nil || dRes != nil {
		t.Fatalf("la otra parada se marcó sin que nadie la marcara: %v %v", dRes, err)
	}

	// TRES AVISOS: uno por factura, todos entregado, con su número de factura.
	facturas := map[string]bool{}
	for _, av := range e.avisados {
		if av.Estado != "entregado" {
			t.Fatalf("aviso con estado %q", av.Estado)
		}
		facturas[av.Factura] = true
	}
	if len(e.avisados) != 3 || !facturas["47313"] || !facturas["47314"] || !facturas["47315"] {
		t.Fatalf("un conduce de 3 facturas son 3 avisos distintos: %+v", e.avisados)
	}
	var enBuzon int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM avisos_a_pedido WHERE sucursal = 'STG' AND estado = 'entregado'`).Scan(&enBuzon); err != nil || enBuzon != 3 {
		t.Fatalf("en el buzón hay %d avisos (%v) y tenían que ser 3", enBuzon, err)
	}

	// Una DEVOLUCIÓN suelta la ruta de las tres y conserva su nota; desmarcar lo deshace en las tres.
	e2a := e.factura("48000", "Maria", 1)
	e2b := e.factura("48001", "Maria", 1)
	if code, cuerpo := e.crear(e.jwt, e2a, e2b); code != http.StatusCreated {
		t.Fatalf("crear el segundo conduce: %d %s", code, cuerpo)
	}
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes",
		fmt.Sprintf(`{"vehicleId":"sin-camion","originLat":20.0,"originLng":-75.8,"orderIds":[%q]}`, e2a))
	if code != http.StatusCreated {
		t.Fatalf("armar el segundo: %d %s", code, cuerpo)
	}
	ruta2 := decodificar[struct {
		ID uuid.UUID `json:"id"`
	}](t, cuerpo).ID
	if code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes/"+ruta2.String()+"/results",
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"devuelto","nota":"no estaba"}]}`, e2a)); code != http.StatusOK {
		t.Fatalf("devolver: %d %s", code, cuerpo)
	}
	var rid *uuid.UUID
	var res, nota *string
	if err := e.tx.QueryRow(e.ctx, `SELECT route_id, resultado::text, resultado_nota FROM orders WHERE id = $1`, e2b).Scan(&rid, &res, &nota); err != nil {
		t.Fatal(err)
	}
	if rid != nil || res == nil || *res != "devuelto" || nota == nil || *nota != "no estaba" {
		t.Fatalf("el miembro de la devolución: ruta=%v resultado=%v nota=%v", rid, res, nota)
	}
	if code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes/"+ruta2.String()+"/results",
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":null}]}`, e2a)); code != http.StatusOK {
		t.Fatalf("desmarcar: %d %s", code, cuerpo)
	}
	if err := e.tx.QueryRow(e.ctx, `SELECT route_id, resultado::text FROM orders WHERE id = $1`, e2b).Scan(&rid, &res); err != nil {
		t.Fatal(err)
	}
	if rid == nil || *rid != ruta2 || res != nil {
		t.Fatalf("desmarcar la principal tenía que devolver al miembro a su ruta sin resultado: ruta=%v resultado=%v", rid, res)
	}
}

// ---------------------------------------------------------------------------
// El espejo: no pisa el conduce, y una cancelación saca la factura (o suelta a los miembros)
// ---------------------------------------------------------------------------

func TestMotorReal_Conduces_ElEspejoNoPisaElConduce(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47313", "Hector Luis", 10)
	b := e.factura("47314", "Hector Luis", 5)
	if code, cuerpo := e.crear(e.jwt, a, b); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}
	// El espejo reescribe la fila MIEMBRO con otro peso y otra dirección (el upsert de verdad).
	q := sqlc.New(e.tx)
	var ext string
	if err := e.tx.QueryRow(e.ctx, `SELECT external_id FROM orders WHERE id = $1`, b).Scan(&ext); err != nil {
		t.Fatal(err)
	}
	fuente := sqlc.ProcedenciaPedido
	suc := pgDe(e.stg)
	cod := "STG"
	facNum := "47314"
	fila, err := q.GuardarPedidoDelEspejo(e.ctx, sqlc.GuardarPedidoDelEspejoParams{
		CustomerName: "Hector Luis", Address: "OTRA calle", Weight: 99, BranchID: suc,
		Source: &fuente, ExternalID: &ext, SucursalCodigo: &cod, FacturaNumero: &facNum,
	})
	if err != nil {
		t.Fatal(err)
	}
	if fila.ID != b || fila.EsNuevo {
		t.Fatalf("el upsert tenía que actualizar la misma fila: %+v", fila)
	}
	var peso float64
	if err := e.tx.QueryRow(e.ctx, `SELECT weight FROM orders WHERE id = $1`, b).Scan(&peso); err != nil || peso != 99 {
		t.Fatalf("el espejo no reescribió (peso %v, %v): la prueba no prueba nada", peso, err)
	}
	if p := e.principalDe(b); p == nil || *p != a {
		t.Fatalf("el espejo pisó conduce_principal_id: %v", p)
	}
}

func TestMotorReal_Conduces_UnaCancelacionSacaLaFacturaOSueltaALosMiembros(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	q := sqlc.New(e.tx)
	armar := func(numeros ...string) (principal uuid.UUID, miembros []uuid.UUID, ruta uuid.UUID) {
		principal = e.factura(numeros[0], "Cliente "+numeros[0], 1)
		for _, n := range numeros[1:] {
			m := e.factura(n, "Cliente "+numeros[0], 1)
			e.exec(`UPDATE orders SET customer_name = 'Cliente '||$2::text WHERE id = $1`, m, numeros[0])
			miembros = append(miembros, m)
		}
		e.exec(`UPDATE orders SET customer_name = 'Cliente '||$2::text WHERE id = $1`, principal, numeros[0])
		if code, cuerpo := e.crear(e.jwt, principal, miembros...); code != http.StatusCreated {
			t.Fatalf("crear: %d %s", code, cuerpo)
		}
		ruta = e.id(`INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng, total_distance, optimized)
		             VALUES ($1, 'planned', 'r', 20, -75.8, 1, false) RETURNING id`, e.stg)
		e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 1 WHERE id = $1`, principal, ruta)
		for _, m := range miembros {
			e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2 WHERE id = $1`, m, ruta)
		}
		return
	}
	estado := func(id uuid.UUID) (conduce, ruta *uuid.UUID, archivada bool, anulada bool) {
		t.Helper()
		if err := e.tx.QueryRow(e.ctx, `SELECT conduce_principal_id, route_id, archivado, anulada_at IS NOT NULL FROM orders WHERE id = $1`, id).
			Scan(&conduce, &ruta, &archivada, &anulada); err != nil {
			t.Fatal(err)
		}
		return
	}

	// (1) SE CANCELA UN MIEMBRO que iba en la ruta: sale del conduce y de la ruta, archivada; el conduce sigue.
	p, ms, ruta := armar("100", "101", "102")
	if hechas, err := q.AnularEntregasDeFacturaEnRuta(e.ctx, []uuid.UUID{ms[0]}); err != nil || len(hechas) != 1 {
		t.Fatalf("anular el miembro: %v %v", hechas, err)
	}
	if c, r, arch, an := estado(ms[0]); c != nil || r != nil || !arch || !an {
		t.Fatalf("el miembro cancelado: conduce=%v ruta=%v archivada=%v anulada=%v", c, r, arch, an)
	}
	if c, r, _, _ := estado(ms[1]); c == nil || *c != p || r == nil || *r != ruta {
		t.Fatalf("el otro miembro tenía que seguir en el conduce y en la ruta: %v %v", c, r)
	}
	if _, r, _, _ := estado(p); r == nil {
		t.Fatal("la principal salió de la ruta por cancelar un miembro")
	}

	// (2) SE CANCELA LA PRINCIPAL en una ruta no completada: los miembros salen de la ruta y del conduce, vivos.
	p, ms, _ = armar("200", "201", "202")
	if hechas, err := q.AnularEntregasDeFacturaEnRuta(e.ctx, []uuid.UUID{p}); err != nil || len(hechas) != 1 {
		t.Fatalf("anular la principal: %v %v", hechas, err)
	}
	for _, m := range ms {
		if c, r, arch, an := estado(m); c != nil || r != nil || arch || an {
			t.Fatalf("un miembro de la principal cancelada: conduce=%v ruta=%v archivado=%v anulada=%v (tenía que quedar suelto, sin ruta y vivo)", c, r, arch, an)
		}
	}
	var ultima *uuid.UUID
	if err := e.tx.QueryRow(e.ctx, `SELECT ultima_ruta_id FROM orders WHERE id = $1`, ms[0]).Scan(&ultima); err != nil || ultima != nil {
		t.Fatalf("el miembro liberado conserva ultima_ruta_id (%v, %v): seguiría contando en los totales de la ruta", ultima, err)
	}

	// (3) SE CANCELAN LA PRINCIPAL Y UN MIEMBRO EN LA MISMA TANDA: sin error, el otro miembro queda suelto.
	p, ms, _ = armar("300", "301", "302")
	if hechas, err := q.AnularEntregasDeFacturaEnRuta(e.ctx, []uuid.UUID{ms[0], p}); err != nil || len(hechas) != 2 {
		t.Fatalf("anular la principal y un miembro a la vez: %v %v", hechas, err)
	}
	if c, r, arch, _ := estado(ms[1]); c != nil || r != nil || arch {
		t.Fatalf("el miembro que sobrevive: conduce=%v ruta=%v archivado=%v", c, r, arch)
	}
	if c, _, arch, an := estado(ms[0]); c != nil || !arch || !an {
		t.Fatalf("el miembro cancelado en la misma tanda: conduce=%v archivado=%v anulada=%v", c, arch, an)
	}

	// (4) SE RETIRA UNA PRINCIPAL SIN RUTA (el espejo la borra): los miembros quedan sueltos, NO se destruyen.
	pa := e.factura("400", "Cliente 400", 1)
	pb := e.factura("401", "Cliente 400", 1)
	if code, cuerpo := e.crear(e.jwt, pa, pb); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}
	if n, err := q.RetirarEntregasDeFactura(e.ctx, []uuid.UUID{pa}); err != nil || n != 1 {
		t.Fatalf("retirar la principal: %d %v", n, err)
	}
	if c, _, arch, _ := estado(pb); c != nil || arch {
		t.Fatalf("el miembro de una principal borrada tenía que sobrevivir suelto: conduce=%v archivado=%v", c, arch)
	}

	// (5) PEDIDO ARCHIVA una principal (upsert con archivado = true): sus miembros se sueltan. Y un MIEMBRO archivado sale del conduce.
	x := e.factura("500", "Cliente 500", 1)
	y := e.factura("501", "Cliente 500", 1)
	z := e.factura("502", "Cliente 500", 1)
	if code, cuerpo := e.crear(e.jwt, x, y, z); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}
	e.exec(`UPDATE orders SET archivado = true WHERE id = $1`, z)
	if c, _, arch, _ := estado(z); c != nil || !arch {
		t.Fatalf("un miembro archivado tenía que salir del conduce: %v %v", c, arch)
	}
	e.exec(`UPDATE orders SET archivado = true WHERE id = $1`, x)
	if c, _, _, _ := estado(y); c != nil {
		t.Fatal("al archivar la principal, su miembro tenía que quedar suelto")
	}
}

// ---------------------------------------------------------------------------
// La base misma: sin cadenas, y el pre-despacho
// ---------------------------------------------------------------------------

func TestMotorReal_Conduces_LaBaseNoDejaCadenas(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("1", "C", 1)
	b := e.factura("2", "C", 1)
	c := e.factura("3", "C", 1)
	e.exec(`UPDATE orders SET conduce_principal_id = $2 WHERE id = $1`, b, a)
	for nombre, sql := range map[string]string{
		"un miembro como principal de otro":    `UPDATE orders SET conduce_principal_id = ` + fmt.Sprintf("'%s'", b) + ` WHERE id = ` + fmt.Sprintf("'%s'", c),
		"una principal que pasa a ser miembro": `UPDATE orders SET conduce_principal_id = ` + fmt.Sprintf("'%s'", c) + ` WHERE id = ` + fmt.Sprintf("'%s'", a),
		"de sí misma":                          `UPDATE orders SET conduce_principal_id = ` + fmt.Sprintf("'%s'", c) + ` WHERE id = ` + fmt.Sprintf("'%s'", c),
	} {
		e.exec(`SAVEPOINT s`)
		if _, err := e.tx.Exec(e.ctx, sql); err == nil {
			t.Errorf("%s: la base lo dejó escribir", nombre)
		}
		e.exec(`ROLLBACK TO SAVEPOINT s`)
	}
	// Y de otra sucursal tampoco.
	h := e.facturaDe(e.hol, "HOL", "9", "C", 1)
	e.exec(`SAVEPOINT s`)
	if _, err := e.tx.Exec(e.ctx, `UPDATE orders SET conduce_principal_id = $2 WHERE id = $1`, h, a); err == nil {
		t.Error("la base dejó juntar dos sucursales")
	}
	e.exec(`ROLLBACK TO SAVEPOINT s`)
}

func TestMotorReal_Conduces_ElPreDespachoLlevaLosRenglonesDeTodoElConduce(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47313", "Hector Luis", 10)
	b := e.factura("47314", "Hector Luis", 5)
	e.exec(`INSERT INTO order_items (order_id, linea, description, quantity, factura_numero) VALUES
	        ($1, 1, 'Malta', 4, '47313'), ($2, 1, 'Malta', 6, '47314')`, a, b)
	if code, cuerpo := e.crear(e.jwt, a, b); code != http.StatusCreated {
		t.Fatalf("crear: %d %s", code, cuerpo)
	}
	// El pre-despacho de la lista (sólo sale la principal) lleva las DOS facturas: 10 unidades y 15 kg.
	code, cuerpo := e.llamar(e.jwt, http.MethodGet, "/api/orders?resumen=1", "")
	if code != http.StatusOK {
		t.Fatalf("GET /api/orders?resumen=1: %d %s", code, cuerpo)
	}
	r := decodificar[struct {
		Resumen []struct {
			Producto string  `json:"producto"`
			Unidades float64 `json:"unidades"`
		} `json:"resumen"`
		PesoTotal float64 `json:"pesoTotal"`
	}](t, cuerpo)
	if len(r.Resumen) != 1 || r.Resumen[0].Unidades != 10 || r.PesoTotal != 15 {
		t.Fatalf("el pre-despacho tenía que sumar los renglones y el peso de las dos facturas: %s", cuerpo)
	}
}

var _ = time.Now
