package sqlc

// Pruebas de MOTOR REAL de las consultas reescritas de rutas, flota y tablero.
//
// POR QUÉ EXISTEN. Las pruebas de Go de `internal/api` usan dobles: comprueban que el
// manejador llama a la consulta, no que la consulta haga en Postgres lo que su comentario
// dice. Estas ejecutan `New(tx)` — el `Queries` real que genera sqlc — contra un Postgres
// de verdad con TODAS las migraciones aplicadas.
//
// CÓMO SE EJECUTAN. Sólo con una base AISLADA, y sólo si se pide:
//
//	REPARTO_MOTOR_REAL_DSN='postgres://verif:verif@127.0.0.1:5433/verif_reparto?sslmode=disable' \
//	  go test -count=1 -run MotorReal ./internal/store/sqlc/ -v
//
// Sin la variable se saltan. Nunca leen DATABASE_URL ni ninguna otra variable de
// producción, y se niegan a correr si la base no se llama `verif…`, `…test…` o `…prueba…`.
//
// CÓMO NO ENSUCIAN. Cada subprueba abre SU transacción, siembra con SQL directo y la
// revierte al terminar: la base queda como estaba.
//
// LA TRAMPA DE ESTE ESQUEMA, y la razón de `restricciones()`. `board_placements` y
// `board_columns` tienen su UNIQUE de posición `DEFERRABLE INITIALLY DEFERRED`: Postgres lo
// comprueba al CONFIRMAR, no al ejecutar la sentencia. Una prueba que revierte nunca
// confirma, así que un choque de posiciones pasaría en verde sin que nadie lo viera.
// Después de cada consulta bajo prueba se fuerza esa comprobación con
// `SET CONSTRAINTS ALL IMMEDIATE`, que es exactamente lo que haría el COMMIT.

import (
	"context"
	"errors"
	"fmt"
	"os"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ---------------------------------------------------------------------------
// Conexión y transacción por subprueba
// ---------------------------------------------------------------------------

func motorReal(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("REPARTO_MOTOR_REAL_DSN")
	if dsn == "" {
		t.Skip("requiere PostgreSQL aislado REPARTO_MOTOR_REAL_DSN")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
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
	return pool
}

// banco es una transacción abierta con sus ayudantes de siembra y de lectura.
type banco struct {
	t   *testing.T
	ctx context.Context
	tx  pgx.Tx
	q   *Queries
}

func nuevoBanco(t *testing.T, pool *pgxpool.Pool) *banco {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	// Se registra DESPUÉS que el cancel: los Cleanup corren al revés, así que la
	// reversión sale primero y con un contexto que ya no depende del temporizador.
	t.Cleanup(func() { _ = tx.Rollback(context.Background()) })
	return &banco{t: t, ctx: ctx, tx: tx, q: New(tx)}
}

func (b *banco) exec(sql string, args ...any) {
	b.t.Helper()
	if _, err := b.tx.Exec(b.ctx, sql, args...); err != nil {
		b.t.Fatalf("siembra %q: %v", sql, err)
	}
}

func (b *banco) id(sql string, args ...any) uuid.UUID {
	b.t.Helper()
	var u uuid.UUID
	if err := b.tx.QueryRow(b.ctx, sql, args...).Scan(&u); err != nil {
		b.t.Fatalf("siembra %q: %v", sql, err)
	}
	return u
}

func (b *banco) entero(sql string, args ...any) int {
	b.t.Helper()
	var n int
	if err := b.tx.QueryRow(b.ctx, sql, args...).Scan(&n); err != nil {
		b.t.Fatalf("lectura %q: %v", sql, err)
	}
	return n
}

// restricciones hace lo que haría el COMMIT con las restricciones diferidas: si la base
// rechazaría confirmar este estado, la prueba falla AQUÍ y dice cuál.
func (b *banco) restricciones(tras string) {
	b.t.Helper()
	if _, err := b.tx.Exec(b.ctx, "SET CONSTRAINTS ALL IMMEDIATE"); err != nil {
		b.t.Fatalf("tras %s la base rechazaría el COMMIT (restricción diferida): %v", tras, err)
	}
	b.exec("SET CONSTRAINTS ALL DEFERRED")
}

func alcance(sucursal uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: sucursal, Valid: true} }

var sinAlcance = pgtype.UUID{}

func f64(v float64) *float64 { return &v }
func i32(v int32) *int32     { return &v }
func str(v string) *string   { return &v }

// ---------------------------------------------------------------------------
// Siembra
// ---------------------------------------------------------------------------

func (b *banco) sucursal() uuid.UUID {
	b.t.Helper()
	return b.id(`INSERT INTO branches (name, lat, lng) VALUES ($1, 0, 0) RETURNING id`, "suc-"+uuid.NewString())
}

func (b *banco) columna(sucursal uuid.UUID, nombre string, posicion int) uuid.UUID {
	b.t.Helper()
	return b.id(`INSERT INTO board_columns (branch_id, nombre, posicion) VALUES ($1, $2, $3) RETURNING id`,
		sucursal, nombre, posicion)
}

func (b *banco) ruta(sucursal uuid.UUID, estado RouteStatus) uuid.UUID {
	b.t.Helper()
	return b.id(`INSERT INTO routes (branch_id, status, name) VALUES ($1, $2::text::route_status, 'ruta') RETURNING id`,
		sucursal, string(estado))
}

func (b *banco) vehiculo(sucursal pgtype.UUID) uuid.UUID {
	b.t.Helper()
	tipo := b.id(`INSERT INTO vehicle_types (nombre) VALUES ($1) RETURNING id`, "tipo-"+uuid.NewString())
	return b.id(`INSERT INTO vehicles (name, vehicle_type_id, branch_id) VALUES ($1, $2, $3) RETURNING id`,
		"camion-"+uuid.NewString()[:8], tipo, sucursal)
}

// semilla describe un pedido. `listo()` da uno que cumple TODO lo que pide el tablero.
type semilla struct {
	Nombre      string
	Sucursal    uuid.UUID
	Source      *string
	Ruta        pgtype.UUID
	UltimaRuta  pgtype.UUID
	StopOrder   *int32
	SegmentKm   *float64
	TripLeg     string
	Entregado   bool
	Resultado   *string
	Factura     *string
	Domicilio   *float64
	Costo       *float64
	Requiere    bool
	Coordenadas bool
	Peso        *float64 // nil = 1, el de siempre
	Archivado   bool
}

func listo(nombre string, sucursal uuid.UUID) semilla {
	return semilla{
		Nombre: nombre, Sucursal: sucursal, Source: str("pedido"), TripLeg: "outbound",
		Factura: str("igual"), Domicilio: f64(5), Costo: f64(10), Requiere: true, Coordenadas: true,
	}
}

func (b *banco) pedido(s semilla) uuid.UUID {
	b.t.Helper()
	var lat, lng *float64
	if s.Coordenadas {
		lat, lng = f64(21.5), f64(-77.9)
	}
	return b.id(`
INSERT INTO orders (
    customer_name, address, weight, branch_id, source, external_id,
    end_lat, end_lng, requiere_domicilio, factura_estado, factura_domicilio, pedido_costo,
    route_id, ultima_ruta_id, stop_order, segment_km, trip_leg, status, delivered_at, resultado,
    archivado
) VALUES (
    $1, 'calle 1', COALESCE($18::double precision, 1), $2, $3::text::procedencia, $4,
    $5, $6, $7, $8::text::factura_estado, $9, $10,
    $11, $12, $13, $14, $15::text::trip_leg,
    (CASE WHEN $16::boolean THEN 'delivered' ELSE 'pending' END)::order_status,
    (CASE WHEN $16::boolean THEN now() END), $17::text::stop_result,
    $19::boolean
) RETURNING id`,
		s.Nombre, s.Sucursal, s.Source, "ext-"+uuid.NewString(),
		lat, lng, s.Requiere, s.Factura, s.Domicilio, s.Costo,
		s.Ruta, s.UltimaRuta, s.StopOrder, s.SegmentKm, s.TripLeg,
		s.Entregado, s.Resultado, s.Peso, s.Archivado)
}

// ficha: un pedido ya colocado en una columna del tablero.
func (b *banco) ficha(sucursal, columna uuid.UUID, nombre string, posicion int) uuid.UUID {
	b.t.Helper()
	p := b.pedido(listo(nombre, sucursal))
	b.exec(`INSERT INTO board_placements (order_id, column_id, posicion, colocado_por) VALUES ($1, $2, $3, 'jose')`,
		p, columna, posicion)
	return p
}

// parada: un pedido que nació del tablero y ya viaja en la ruta, con su origen guardado.
// Lleva trip_leg 'return', segment_km y stop_order para ver que al soltarlo se limpian.
func (b *banco) parada(sucursal, ruta, columna uuid.UUID, nombre string, posicion int, orden int32) uuid.UUID {
	b.t.Helper()
	s := listo(nombre, sucursal)
	s.Ruta = alcance(ruta)
	s.StopOrder = i32(orden)
	s.SegmentKm = f64(3.5)
	s.TripLeg = "return"
	p := b.pedido(s)
	b.exec(`INSERT INTO board_route_origins (route_id, order_id, column_id, posicion, colocado_por) VALUES ($1, $2, $3, $4, 'jose')`,
		ruta, p, columna, posicion)
	return p
}

// ---------------------------------------------------------------------------
// Lectura
// ---------------------------------------------------------------------------

// fichas devuelve la columna como "nombre@posicion", en orden de posición.
func (b *banco) fichas(columna uuid.UUID) []string {
	b.t.Helper()
	filas, err := b.tx.Query(b.ctx, `
SELECT o.customer_name, p.posicion FROM board_placements p JOIN orders o ON o.id = p.order_id
WHERE p.column_id = $1 ORDER BY p.posicion, o.customer_name`, columna)
	if err != nil {
		b.t.Fatal(err)
	}
	defer filas.Close()
	var salida []string
	for filas.Next() {
		var nombre string
		var pos int32
		if err := filas.Scan(&nombre, &pos); err != nil {
			b.t.Fatal(err)
		}
		salida = append(salida, fmt.Sprintf("%s@%d", nombre, pos))
	}
	if err := filas.Err(); err != nil {
		b.t.Fatal(err)
	}
	return salida
}

// orden devuelve sólo los nombres, en orden de posición, y comprueba que las posiciones
// no se repiten.
func (b *banco) orden(columna uuid.UUID) []string {
	b.t.Helper()
	if n := b.entero(`SELECT count(*) - count(DISTINCT posicion) FROM board_placements WHERE column_id = $1`, columna); n != 0 {
		b.t.Fatalf("posiciones repetidas en la columna: %v", b.fichas(columna))
	}
	var nombres []string
	for _, f := range b.fichas(columna) {
		nombres = append(nombres, f[:strings.LastIndex(f, "@")])
	}
	return nombres
}

type estadoPedido struct {
	Ruta, UltimaRuta pgtype.UUID
	StopOrder        *int32
	SegmentKm        *float64
	TripLeg          string
	Status           string
	Entregado        bool
	Resultado        *string
	ResultadoAt      bool
	Nota             *string
}

// String desreferencia los punteros: sin esto %+v imprime direcciones de memoria y dos
// fotos idénticas parecen distintas.
func (e estadoPedido) String() string {
	nulo := func(p any) string {
		switch v := p.(type) {
		case *int32:
			if v != nil {
				return fmt.Sprint(*v)
			}
		case *float64:
			if v != nil {
				return fmt.Sprint(*v)
			}
		case *string:
			if v != nil {
				return *v
			}
		}
		return "NULL"
	}
	ruta, ultima := "NULL", "NULL"
	if e.Ruta.Valid {
		ruta = uuid.UUID(e.Ruta.Bytes).String()[:8]
	}
	if e.UltimaRuta.Valid {
		ultima = uuid.UUID(e.UltimaRuta.Bytes).String()[:8]
	}
	return fmt.Sprintf("{route=%s ultima=%s stop=%s km=%s leg=%s status=%s entregado=%t resultado=%s resultado_at=%t nota=%s}",
		ruta, ultima, nulo(e.StopOrder), nulo(e.SegmentKm), e.TripLeg, e.Status, e.Entregado, nulo(e.Resultado), e.ResultadoAt, nulo(e.Nota))
}

func (b *banco) leer(pedido uuid.UUID) estadoPedido {
	b.t.Helper()
	var e estadoPedido
	var entregadoAt, resultadoAt pgtype.Timestamptz
	err := b.tx.QueryRow(b.ctx, `
SELECT route_id, ultima_ruta_id, stop_order, segment_km, trip_leg::text, status::text,
       delivered_at, resultado::text, resultado_at, resultado_nota
FROM orders WHERE id = $1`, pedido).Scan(&e.Ruta, &e.UltimaRuta, &e.StopOrder, &e.SegmentKm,
		&e.TripLeg, &e.Status, &entregadoAt, &e.Resultado, &resultadoAt, &e.Nota)
	if err != nil {
		b.t.Fatal(err)
	}
	e.Entregado = entregadoAt.Valid
	e.ResultadoAt = resultadoAt.Valid
	return e
}

func (b *banco) origenes(ruta uuid.UUID) int {
	b.t.Helper()
	return b.entero(`SELECT count(*) FROM board_route_origins WHERE route_id = $1`, ruta)
}

func (b *banco) tieneOrigen(pedido uuid.UUID) bool {
	b.t.Helper()
	return b.entero(`SELECT count(*) FROM board_route_origins WHERE order_id = $1`, pedido) == 1
}

func (b *banco) colocaciones() int {
	b.t.Helper()
	return b.entero(`SELECT count(*) FROM board_placements`)
}

func igualesTxt(t *testing.T, que string, real, esperado []string) {
	t.Helper()
	if !reflect.DeepEqual(real, esperado) {
		t.Fatalf("%s:\n  real     %v\n  esperado %v", que, real, esperado)
	}
}

func sinFilas(t *testing.T, que string, err error) {
	t.Helper()
	if !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("%s: esperaba pgx.ErrNoRows y llegó %v", que, err)
	}
}

// ---------------------------------------------------------------------------
// 1. SoltarParadaPlanificada
// ---------------------------------------------------------------------------

// escenaSoltar: columna "Centro" con a@0, b@2, c@4 puestas, y una ruta planificada cuyas
// dos paradas nacieron de esa misma columna: p1 (estaba en la 1) y p2 (estaba en la 3).
// Es lo que deja `QuitarDelTableroLosDeRuta`: las posiciones NO se cierran, así que el
// hueco de cada parada sigue siendo suyo.
type escenaSoltar struct {
	*banco
	suc, col, ruta uuid.UUID
	p1, p2         uuid.UUID
}

func nuevaEscenaSoltar(t *testing.T, pool *pgxpool.Pool, estado RouteStatus) *escenaSoltar {
	e := &escenaSoltar{banco: nuevoBanco(t, pool)}
	e.suc = e.sucursal()
	e.col = e.columna(e.suc, "Centro", 0)
	e.ruta = e.ruta_(estado)
	e.ficha(e.suc, e.col, "a", 0)
	e.ficha(e.suc, e.col, "b", 2)
	e.ficha(e.suc, e.col, "c", 4)
	e.p1 = e.parada(e.suc, e.ruta, e.col, "p1", 1, 1)
	e.p2 = e.parada(e.suc, e.ruta, e.col, "p2", 3, 2)
	return e
}

func (e *escenaSoltar) ruta_(estado RouteStatus) uuid.UUID { return e.banco.ruta(e.suc, estado) }

// foto resume todo lo que SoltarParadaPlanificada podría tocar, para comprobar «nada
// cambió» en los casos negativos.
func (e *escenaSoltar) foto() string {
	return fmt.Sprintf("%v | origenes=%d | p1=%+v | p2=%+v", e.fichas(e.col), e.origenes(e.ruta), e.leer(e.p1), e.leer(e.p2))
}

func TestMotorReal_SoltarParadaPlanificada(t *testing.T) {
	pool := motorReal(t)

	for _, caso := range []struct {
		nombre string
		scope  func(*escenaSoltar) pgtype.UUID
	}{
		{"con_alcance_de_su_sucursal", func(e *escenaSoltar) pgtype.UUID { return alcance(e.suc) }},
		{"sin_alcance_todas_las_sucursales", func(*escenaSoltar) pgtype.UUID { return sinAlcance }},
	} {
		t.Run("restaura_en_su_columna_y_posicion/"+caso.nombre, func(t *testing.T) {
			e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
			igualesTxt(t, "tablero antes", e.fichas(e.col), []string{"a@0", "b@2", "c@4"})

			id, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
				PedidoID: e.p1, RutaID: e.ruta, Sucursal: caso.scope(e)})
			if err != nil {
				t.Fatal(err)
			}
			// (d) devuelve el id del pedido
			if id != e.p1 {
				t.Fatalf("devolvió %s, esperaba el pedido %s", id, e.p1)
			}
			e.restricciones("SoltarParadaPlanificada")

			// (a) route_id, stop_order y segment_km a NULL; trip_leg vuelve a outbound
			p := e.leer(e.p1)
			if p.Ruta.Valid || p.StopOrder != nil || p.SegmentKm != nil || p.TripLeg != "outbound" {
				t.Fatalf("la parada soltada no quedó limpia: %+v", p)
			}
			// (b) su origen se borra
			if e.tieneOrigen(e.p1) {
				t.Fatal("el origen de la parada soltada sigue en board_route_origins")
			}
			// (c) su colocación vuelve a su columna y posición, y lo que estaba en >= 1 se
			// corre uno: a@0 no se mueve; b@2 -> 3; c@4 -> 5.
			igualesTxt(t, "tablero tras soltar p1", e.fichas(e.col), []string{"a@0", "p1@1", "b@3", "c@5"})

			// la otra parada de la ruta no se toca
			p2 := e.leer(e.p2)
			if !p2.Ruta.Valid || p2.Ruta.Bytes != e.ruta || p2.StopOrder == nil || *p2.StopOrder != 2 {
				t.Fatalf("soltar p1 tocó a p2: %+v", p2)
			}
			if !e.tieneOrigen(e.p2) {
				t.Fatal("soltar p1 se llevó el origen de p2")
			}
		})
	}

	t.Run("soltar_las_dos_paradas_una_tras_otra_no_choca", func(t *testing.T) {
		e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
		for _, p := range []uuid.UUID{e.p1, e.p2} {
			if _, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
				PedidoID: p, RutaID: e.ruta, Sucursal: alcance(e.suc)}); err != nil {
				t.Fatal(err)
			}
		}
		e.restricciones("soltar las dos paradas")
		nombres := e.orden(e.col)
		// OBSERVACIÓN, no aserción: el orden original era a, p1, b, p2, c. Al soltar p1 las
		// fichas de abajo se corren (b pasa de 2 a 3), pero el origen de p2 sigue diciendo
		// 3, así que p2 cae ANTES de b. Las posiciones del origen son una foto de cuando se
		// armó la ruta y no se actualizan con el tablero. Se deja escrito para que no
		// sorprenda; no se da por error porque ColocarPedido/AbrirHueco/CerrarHueco las
		// dejan igual de obsoletas.
		t.Logf("orden tras soltar p1 y luego p2: %v (original: [a p1 b p2 c])", nombres)
		if len(nombres) != 5 {
			t.Fatalf("faltan fichas: %v", e.fichas(e.col))
		}
	})

	negativos := []struct {
		nombre string
		monta  func(t *testing.T) *escenaSoltar
		llama  func(e *escenaSoltar) (uuid.UUID, error)
	}{
		{"ruta_en_curso_no_se_suelta", func(t *testing.T) *escenaSoltar { return nuevaEscenaSoltar(t, pool, RouteStatusInProgress) }, nil},
		{"ruta_completada_no_se_suelta", func(t *testing.T) *escenaSoltar { return nuevaEscenaSoltar(t, pool, RouteStatusCompleted) }, nil},
		{"ruta_cancelada_no_se_suelta", func(t *testing.T) *escenaSoltar { return nuevaEscenaSoltar(t, pool, RouteStatusCancelled) }, nil},
	}
	for _, caso := range negativos {
		t.Run(caso.nombre, func(t *testing.T) {
			e := caso.monta(t)
			antes := e.foto()
			_, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
				PedidoID: e.p1, RutaID: e.ruta, Sucursal: alcance(e.suc)})
			sinFilas(t, "ruta no planned", err)
			if despues := e.foto(); despues != antes {
				t.Fatalf("la consulta no devolvió filas PERO cambió datos:\n  antes   %s\n  después %s", antes, despues)
			}
		})
	}

	t.Run("pedido_entregado_por_delivered_at", func(t *testing.T) {
		e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
		e.exec(`UPDATE orders SET delivered_at = now() WHERE id = $1`, e.p1)
		antes := e.foto()
		_, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
			PedidoID: e.p1, RutaID: e.ruta, Sucursal: alcance(e.suc)})
		sinFilas(t, "pedido con delivered_at", err)
		if despues := e.foto(); despues != antes {
			t.Fatalf("cambió datos:\n  antes   %s\n  después %s", antes, despues)
		}
	})

	for _, res := range []string{"entregado", "devuelto", "cancelado"} {
		t.Run("pedido_con_resultado_"+res, func(t *testing.T) {
			e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
			e.exec(`UPDATE orders SET resultado = $2::text::stop_result WHERE id = $1`, e.p1, res)
			antes := e.foto()
			_, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
				PedidoID: e.p1, RutaID: e.ruta, Sucursal: alcance(e.suc)})
			sinFilas(t, "pedido con resultado "+res, err)
			if despues := e.foto(); despues != antes {
				t.Fatalf("cambió datos:\n  antes   %s\n  después %s", antes, despues)
			}
		})
	}

	t.Run("pedido_de_otra_ruta", func(t *testing.T) {
		e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
		otra := e.banco.ruta(e.suc, RouteStatusPlanned)
		colOtra := e.columna(e.suc, "Otra", 1)
		ajeno := e.parada(e.suc, otra, colOtra, "ajeno", 0, 1)
		antes := e.foto()
		antesOtra := e.fichas(colOtra)

		// p1 es de `ruta`, se pide con `otra`
		_, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
			PedidoID: e.p1, RutaID: otra, Sucursal: alcance(e.suc)})
		sinFilas(t, "p1 pedido con la ruta ajena", err)
		// `ajeno` es de `otra`, se pide con `ruta`
		_, err = e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
			PedidoID: ajeno, RutaID: e.ruta, Sucursal: alcance(e.suc)})
		sinFilas(t, "ajeno pedido con la ruta de p1", err)

		if despues := e.foto(); despues != antes {
			t.Fatalf("cambió datos:\n  antes   %s\n  después %s", antes, despues)
		}
		igualesTxt(t, "la otra columna", e.fichas(colOtra), antesOtra)
		if r := e.leer(ajeno); !r.Ruta.Valid || r.Ruta.Bytes != otra || !e.tieneOrigen(ajeno) {
			t.Fatalf("la parada ajena perdió su ruta o su origen: %+v", r)
		}
	})

	t.Run("pedido_de_otra_sucursal_no_existe_para_quien_llama", func(t *testing.T) {
		e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
		antes := e.foto()
		_, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
			PedidoID: e.p1, RutaID: e.ruta, Sucursal: alcance(e.sucursal())})
		sinFilas(t, "alcance de otra sucursal", err)
		if despues := e.foto(); despues != antes {
			t.Fatalf("cambió datos:\n  antes   %s\n  después %s", antes, despues)
		}
	})

	t.Run("pedido_inexistente", func(t *testing.T) {
		e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
		_, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
			PedidoID: uuid.New(), RutaID: e.ruta, Sucursal: alcance(e.suc)})
		sinFilas(t, "pedido inexistente", err)
	})

	t.Run("parada_sin_origen_se_suelta_y_no_inventa_colocacion", func(t *testing.T) {
		e := nuevaEscenaSoltar(t, pool, RouteStatusPlanned)
		// una parada armada a mano (asistente de rutas), que nunca estuvo en el tablero
		s := listo("manual", e.suc)
		s.Ruta = alcance(e.ruta)
		s.StopOrder = i32(3)
		manual := e.pedido(s)
		antes := e.fichas(e.col)
		id, err := e.q.SoltarParadaPlanificada(e.ctx, SoltarParadaPlanificadaParams{
			PedidoID: manual, RutaID: e.ruta, Sucursal: alcance(e.suc)})
		if err != nil || id != manual {
			t.Fatalf("id=%s err=%v", id, err)
		}
		e.restricciones("soltar una parada sin origen")
		if p := e.leer(manual); p.Ruta.Valid || p.StopOrder != nil {
			t.Fatalf("no quedó suelta: %+v", p)
		}
		igualesTxt(t, "el tablero no debe cambiar", e.fichas(e.col), antes)
	})
}

// ---------------------------------------------------------------------------
// 2. SoltarPedidosDeRuta
// ---------------------------------------------------------------------------

// ruta con tres paradas nacidas de la misma columna, en 0, 1 y 2, y fichas ajenas.
func escenaMasiva(t *testing.T, pool *pgxpool.Pool, estado RouteStatus, posOtras map[string]int) (*banco, uuid.UUID, uuid.UUID, uuid.UUID, [3]uuid.UUID) {
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	col := b.columna(suc, "Centro", 0)
	ruta := b.ruta(suc, estado)
	for nombre, pos := range posOtras {
		b.ficha(suc, col, nombre, pos)
	}
	var s [3]uuid.UUID
	for i := range s {
		s[i] = b.parada(suc, ruta, col, fmt.Sprintf("s%d", i), i, int32(i+1))
	}
	return b, suc, col, ruta, s
}

func TestMotorReal_SoltarPedidosDeRuta(t *testing.T) {
	pool := motorReal(t)

	t.Run("tres_paradas_vuelven_aunque_las_fichas_ocupen_sus_posiciones", func(t *testing.T) {
		// Fichas que se pusieron DESPUÉS de armar la ruta y ocupan 0 y 1 (y una en 5):
		// exactamente el choque que rompería el UNIQUE.
		b, suc, col, ruta, _ := escenaMasiva(t, pool, RouteStatusPlanned, map[string]int{"x": 0, "y": 1, "z": 5})
		filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
		if err != nil {
			t.Fatal(err)
		}
		if filas != 3 {
			t.Fatalf("filas soltadas = %d, esperaba 3", filas)
		}
		b.restricciones("SoltarPedidosDeRuta")
		// cada parada vuelve ANTES de las fichas que estaban en una posición >= la suya
		igualesTxt(t, "orden final", b.orden(col), []string{"s0", "x", "s1", "y", "s2", "z"})
		t.Logf("posiciones finales: %v", b.fichas(col))
		if n := b.colocaciones(); n != 6 {
			t.Fatalf("hay %d colocaciones, esperaba 6", n)
		}
	})

	t.Run("tres_paradas_vuelven_antes_de_las_fichas_que_iban_detras", func(t *testing.T) {
		b, suc, col, ruta, _ := escenaMasiva(t, pool, RouteStatusPlanned, map[string]int{"x": 3, "y": 4})
		if _, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)}); err != nil {
			t.Fatal(err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		igualesTxt(t, "orden final", b.orden(col), []string{"s0", "s1", "s2", "x", "y"})
		t.Logf("posiciones finales: %v", b.fichas(col))
	})

	t.Run("paradas_y_fichas_intercaladas", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		ruta := b.ruta(suc, RouteStatusPlanned)
		// original: s0@0 x@1 s1@2 y@3 s2@4 z@5 -> las paradas dejaron los huecos 0, 2 y 4
		b.ficha(suc, col, "x", 1)
		b.ficha(suc, col, "y", 3)
		b.ficha(suc, col, "z", 5)
		b.parada(suc, ruta, col, "s0", 0, 1)
		b.parada(suc, ruta, col, "s1", 2, 2)
		b.parada(suc, ruta, col, "s2", 4, 3)
		if _, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: sinAlcance}); err != nil {
			t.Fatal(err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		igualesTxt(t, "orden final", b.orden(col), []string{"s0", "x", "s1", "y", "s2", "z"})
		t.Logf("posiciones finales: %v", b.fichas(col))
	})

	t.Run("columna_vacia", func(t *testing.T) {
		b, suc, col, ruta, _ := escenaMasiva(t, pool, RouteStatusPlanned, nil)
		if _, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)}); err != nil {
			t.Fatal(err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		// El orden manda, no el hueco: la fórmula suma a cada parada las que iban delante
		// aunque no haya nadie a quien dejar sitio, así que salen 0, 2 y 4. Es único y
		// ordenado; se deja a la vista por si alguien esperaba 0, 1, 2.
		igualesTxt(t, "orden final", b.orden(col), []string{"s0", "s1", "s2"})
		t.Logf("posiciones finales en columna vacía: %v", b.fichas(col))
	})

	t.Run("ida_y_vuelta_con_QuitarDelTableroLosDeRuta", func(t *testing.T) {
		// Sin sembrar los orígenes a mano: los escribe la consulta real que arma la ruta.
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		ruta := b.ruta(suc, RouteStatusPlanned)
		b.ficha(suc, col, "a", 0)
		p1 := b.ficha(suc, col, "p1", 1)
		b.ficha(suc, col, "b", 2)
		p2 := b.ficha(suc, col, "p2", 3)
		b.ficha(suc, col, "c", 4)
		b.exec(`UPDATE orders SET route_id = $1, stop_order = 1 WHERE id = $2`, ruta, p1)
		b.exec(`UPDATE orders SET route_id = $1, stop_order = 2 WHERE id = $2`, ruta, p2)

		n, err := b.q.QuitarDelTableroLosDeRuta(b.ctx, QuitarDelTableroLosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
		if err != nil || n != 2 {
			t.Fatalf("QuitarDelTableroLosDeRuta: n=%d err=%v", n, err)
		}
		b.restricciones("QuitarDelTableroLosDeRuta")
		if got := b.origenes(ruta); got != 2 {
			t.Fatalf("orígenes guardados = %d, esperaba 2", got)
		}
		igualesTxt(t, "tablero con la ruta armada", b.fichas(col), []string{"a@0", "b@2", "c@4"})

		filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
		if err != nil || filas != 2 {
			t.Fatalf("SoltarPedidosDeRuta: filas=%d err=%v", filas, err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		igualesTxt(t, "orden tras deshacer la ruta", b.orden(col), []string{"a", "p1", "b", "p2", "c"})
		t.Logf("posiciones finales: %v", b.fichas(col))
	})

	t.Run("entregada_y_devuelta_no_se_restauran", func(t *testing.T) {
		b, suc, col, ruta, s := escenaMasiva(t, pool, RouteStatusInProgress, map[string]int{"x": 5})
		// s0 ya se entregó (conserva route_id, como lo deja MarcarResultadoDeParada)
		b.exec(`UPDATE orders SET delivered_at = now(), status = 'delivered', resultado = 'entregado', ultima_ruta_id = $2 WHERE id = $1`, s[0], ruta)
		// s1 se devolvió: soltó su route_id y quedó con ultima_ruta_id
		b.exec(`UPDATE orders SET route_id = NULL, resultado = 'devuelto', ultima_ruta_id = $2 WHERE id = $1`, s[1], ruta)

		filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
		if err != nil {
			t.Fatal(err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		// sólo s0 (entregada, aún con route_id) y s2 (pendiente) están en la ruta
		if filas != 2 {
			t.Fatalf("filas soltadas = %d, esperaba 2 (s0 y s2; s1 ya no tenía route_id)", filas)
		}
		igualesTxt(t, "al tablero sólo vuelve la pendiente", b.orden(col), []string{"s2", "x"})

		// lo entregado SIGUE entregado: «el resultado del pedido sigue valiendo y evita
		// repartirlo dos veces»
		e := b.leer(s[0])
		if !e.Entregado || e.Status != "delivered" || e.Resultado == nil || *e.Resultado != "entregado" {
			t.Fatalf("la entregada perdió su resultado: %+v", e)
		}
		d := b.leer(s[1])
		if d.Resultado == nil || *d.Resultado != "devuelto" {
			t.Fatalf("la devuelta perdió su resultado: %+v", d)
		}

		// y el borrado real de la ruta: sus orígenes se van por cascada
		n, err := b.q.BorrarRuta(b.ctx, BorrarRutaParams{ID: ruta, Sucursal: alcance(suc)})
		if err != nil || n != 1 {
			t.Fatalf("BorrarRuta: n=%d err=%v", n, err)
		}
		b.restricciones("BorrarRuta")
		if got := b.origenes(ruta); got != 0 {
			t.Fatalf("quedaron %d orígenes huérfanos", got)
		}
		igualesTxt(t, "el tablero tras borrar la ruta", b.orden(col), []string{"s2", "x"})
		if e := b.leer(s[0]); !e.Entregado || e.Resultado == nil || *e.Resultado != "entregado" || e.Ruta.Valid {
			t.Fatalf("la entregada tras BorrarRuta: %+v", e)
		}
	})

	t.Run("cada_guarda_de_restauracion_cuenta_por_separado", func(t *testing.T) {
		// En el subtest anterior cada pedido cae bajo DOS guardas a la vez (la entregada
		// tiene delivered_at Y resultado; la devuelta no tiene route_id Y tiene resultado),
		// así que quitar cualquiera de las tres no ponía nada en rojo: lo vio la mutación.
		// Aquí cada pedido solo incumple UNA.
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		ruta := b.ruta(suc, RouteStatusInProgress)
		b.ficha(suc, col, "x", 5)
		b.parada(suc, ruta, col, "normal", 0, 1)
		so := b.parada(suc, ruta, col, "solo_delivered_at", 1, 2)
		sr := b.parada(suc, ruta, col, "solo_resultado", 2, 3)
		sn := b.parada(suc, ruta, col, "ya_no_viaja", 3, 4)
		b.exec(`UPDATE orders SET delivered_at = now() WHERE id = $1`, so)
		b.exec(`UPDATE orders SET resultado = 'devuelto' WHERE id = $1`, sr)
		b.exec(`UPDATE orders SET route_id = NULL, stop_order = NULL WHERE id = $1`, sn)

		if _, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)}); err != nil {
			t.Fatal(err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		igualesTxt(t, "sólo vuelve la que sigue pendiente y en la ruta", b.orden(col), []string{"normal", "x"})
	})

	t.Run("ruta_completada_no_restaura", func(t *testing.T) {
		// Una completada ya no debería tener orígenes (ActualizarEstadoDeRuta los borra al
		// completar), pero la consulta se defiende de los viejos: SEMBRADOS a mano.
		b, suc, col, ruta, _ := escenaMasiva(t, pool, RouteStatusCompleted, map[string]int{"x": 5})
		if _, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)}); err != nil {
			t.Fatal(err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		igualesTxt(t, "el tablero no debe cambiar", b.fichas(col), []string{"x@5"})
		if got := b.origenes(ruta); got != 3 {
			t.Fatalf("la completada perdió orígenes: %d", got)
		}
	})

	t.Run("ruta_completada_no_toca_las_paradas_del_historico", func(t *testing.T) {
		// Sólo `completed` es histórico (CLAUDE.md §1): «impide modificar o borrar». La
		// consulta ya filtra `r.status <> 'completed'` para NO restaurar en el tablero,
		// pero su UPDATE final de `orders` no mira el estado de la ruta.
		b, suc, _, ruta, s := escenaMasiva(t, pool, RouteStatusCompleted, nil)
		filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
		if err != nil {
			t.Fatal(err)
		}
		if filas != 0 {
			t.Errorf("sobre una ruta COMPLETADA devolvió %d filas: desenganchó sus paradas del histórico", filas)
		}
		for i, p := range s {
			if e := b.leer(p); !e.Ruta.Valid || e.StopOrder == nil || e.SegmentKm == nil {
				t.Errorf("la parada s%d de la ruta completada quedó %+v", i, e)
			}
		}
	})

	t.Run("alcance_ajeno_no_hace_nada", func(t *testing.T) {
		b, _, col, ruta, s := escenaMasiva(t, pool, RouteStatusPlanned, map[string]int{"x": 5})
		filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(b.sucursal())})
		if err != nil || filas != 0 {
			t.Fatalf("filas=%d err=%v", filas, err)
		}
		b.restricciones("SoltarPedidosDeRuta")
		igualesTxt(t, "tablero", b.fichas(col), []string{"x@5"})
		if e := b.leer(s[0]); !e.Ruta.Valid {
			t.Fatalf("soltó una parada de otra sucursal: %+v", e)
		}
	})
}

// ---------------------------------------------------------------------------
// 3. ActualizarEstadoDeRuta
// ---------------------------------------------------------------------------

func TestMotorReal_ActualizarEstadoDeRuta(t *testing.T) {
	pool := motorReal(t)

	montar := func(t *testing.T) (*banco, uuid.UUID, uuid.UUID, uuid.UUID, uuid.UUID) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		ruta := b.ruta(suc, RouteStatusInProgress)
		otra := b.ruta(suc, RouteStatusPlanned)
		b.parada(suc, ruta, col, "r1", 0, 1)
		b.parada(suc, ruta, col, "r2", 1, 2)
		b.parada(suc, otra, col, "o1", 2, 1)
		return b, suc, col, ruta, otra
	}
	estado := func(s RouteStatus) *RouteStatus { return &s }

	t.Run("completar_borra_los_origenes_de_esa_ruta_y_devuelve_la_ruta", func(t *testing.T) {
		b, suc, _, ruta, otra := montar(t)
		fila, err := b.q.ActualizarEstadoDeRuta(b.ctx, ActualizarEstadoDeRutaParams{
			ID: ruta, Status: estado(RouteStatusCompleted), Sucursal: alcance(suc)})
		if err != nil {
			t.Fatal(err)
		}
		if fila.ID != ruta || fila.Status != RouteStatusCompleted || !fila.FinishedAt.Valid {
			t.Fatalf("la fila devuelta no es la ruta completada: %+v", fila)
		}
		if got := b.origenes(ruta); got != 0 {
			t.Fatalf("quedaron %d orígenes de la ruta completada", got)
		}
		if got := b.origenes(otra); got != 1 {
			t.Fatalf("completar una ruta tocó los orígenes de otra: %d", got)
		}
		// el histórico: las paradas siguen en su ruta, y NO vuelven al tablero
		if e := b.leer(b.id(`SELECT id FROM orders WHERE customer_name = 'r1'`)); !e.Ruta.Valid || e.Ruta.Bytes != ruta {
			t.Fatalf("la parada dejó de pertenecer a la ruta completada: %+v", e)
		}
		if n := b.colocaciones(); n != 0 {
			t.Fatalf("completar no debe devolver nada al tablero, hay %d colocaciones", n)
		}
	})

	t.Run("completar_sin_alcance_tambien", func(t *testing.T) {
		b, _, _, ruta, _ := montar(t)
		if _, err := b.q.ActualizarEstadoDeRuta(b.ctx, ActualizarEstadoDeRutaParams{
			ID: ruta, Status: estado(RouteStatusCompleted), Sucursal: sinAlcance}); err != nil {
			t.Fatal(err)
		}
		if got := b.origenes(ruta); got != 0 {
			t.Fatalf("quedaron %d orígenes", got)
		}
	})

	for _, otro := range []RouteStatus{RouteStatusPlanned, RouteStatusInProgress, RouteStatusCancelled} {
		t.Run("con_estado_"+string(otro)+"_no_borra_nada", func(t *testing.T) {
			b, suc, _, ruta, otra := montar(t)
			fila, err := b.q.ActualizarEstadoDeRuta(b.ctx, ActualizarEstadoDeRutaParams{
				ID: ruta, Status: estado(otro), Sucursal: alcance(suc)})
			if err != nil {
				t.Fatal(err)
			}
			if fila.Status != otro {
				t.Fatalf("estado devuelto %s, esperaba %s", fila.Status, otro)
			}
			if b.origenes(ruta) != 2 || b.origenes(otra) != 1 {
				t.Fatalf("borró orígenes con estado %s: %d y %d", otro, b.origenes(ruta), b.origenes(otra))
			}
		})
	}

	t.Run("solo_renombrar_no_borra_nada", func(t *testing.T) {
		b, suc, _, ruta, _ := montar(t)
		fila, err := b.q.ActualizarEstadoDeRuta(b.ctx, ActualizarEstadoDeRutaParams{
			ID: ruta, Name: str("nueva"), Sucursal: alcance(suc)})
		if err != nil {
			t.Fatal(err)
		}
		if fila.Name == nil || *fila.Name != "nueva" || fila.Status != RouteStatusInProgress {
			t.Fatalf("fila: %+v", fila)
		}
		if got := b.origenes(ruta); got != 2 {
			t.Fatalf("renombrar borró orígenes: quedan %d", got)
		}
	})

	t.Run("completar_con_alcance_ajeno_no_borra_ni_cambia", func(t *testing.T) {
		b, _, _, ruta, _ := montar(t)
		_, err := b.q.ActualizarEstadoDeRuta(b.ctx, ActualizarEstadoDeRutaParams{
			ID: ruta, Status: estado(RouteStatusCompleted), Sucursal: alcance(b.sucursal())})
		sinFilas(t, "completar con otra sucursal", err)
		if got := b.origenes(ruta); got != 2 {
			t.Fatalf("borró orígenes de una ruta ajena: quedan %d", got)
		}
		if st := b.id(`SELECT id FROM routes WHERE id = $1 AND status = 'in_progress'`, ruta); st != ruta {
			t.Fatal("la ruta ajena cambió de estado")
		}
	})
}

// ---------------------------------------------------------------------------
// 4. BorrarVehiculo
// ---------------------------------------------------------------------------

func TestMotorReal_BorrarVehiculo(t *testing.T) {
	pool := motorReal(t)

	existe := func(b *banco, v uuid.UUID) bool {
		return b.entero(`SELECT count(*) FROM vehicles WHERE id = $1`, v) == 1
	}

	t.Run("sin_rutas_se_borra_y_devuelve_la_sucursal", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		v := b.vehiculo(alcance(suc))
		branch, err := b.q.BorrarVehiculo(b.ctx, BorrarVehiculoParams{ID: v, Sucursal: alcance(suc)})
		if err != nil {
			t.Fatal(err)
		}
		if !branch.Valid || branch.Bytes != suc {
			t.Fatalf("devolvió branch_id %+v, esperaba %s", branch, suc)
		}
		if existe(b, v) {
			t.Fatal("el vehículo sigue en la base")
		}
	})

	t.Run("sin_rutas_sin_alcance", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		v := b.vehiculo(alcance(suc))
		branch, err := b.q.BorrarVehiculo(b.ctx, BorrarVehiculoParams{ID: v, Sucursal: sinAlcance})
		if err != nil || !branch.Valid || branch.Bytes != suc {
			t.Fatalf("branch=%+v err=%v", branch, err)
		}
	})

	t.Run("compartido_branch_null_lo_borra_cualquier_sucursal_y_devuelve_null", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		v := b.vehiculo(sinAlcance)
		branch, err := b.q.BorrarVehiculo(b.ctx, BorrarVehiculoParams{ID: v, Sucursal: alcance(b.sucursal())})
		if err != nil {
			t.Fatal(err)
		}
		if branch.Valid {
			t.Fatalf("un camión compartido debe devolver branch_id NULL y devolvió %+v", branch)
		}
		if existe(b, v) {
			t.Fatal("el vehículo sigue en la base")
		}
	})

	for _, estado := range []RouteStatus{RouteStatusCompleted, RouteStatusPlanned, RouteStatusInProgress, RouteStatusCancelled} {
		t.Run("con_una_ruta_"+string(estado)+"_no_se_borra", func(t *testing.T) {
			b := nuevoBanco(t, pool)
			suc := b.sucursal()
			v := b.vehiculo(alcance(suc))
			ruta := b.ruta(suc, estado)
			b.exec(`UPDATE routes SET vehicle_id = $1 WHERE id = $2`, v, ruta)
			_, err := b.q.BorrarVehiculo(b.ctx, BorrarVehiculoParams{ID: v, Sucursal: alcance(suc)})
			// ErrNoRows y NO una violación de clave ajena (23503): la guarda NOT EXISTS tiene
			// que cortar ANTES de que routes_vehicle_id_fkey salte.
			sinFilas(t, "vehículo con ruta "+string(estado), err)
			if !existe(b, v) {
				t.Fatal("el vehículo con ruta desapareció")
			}
			if got := b.entero(`SELECT count(*) FROM routes WHERE id = $1 AND vehicle_id = $2`, ruta, v); got != 1 {
				t.Fatal("la ruta perdió su vehículo")
			}
		})
	}

	t.Run("de_otra_sucursal_no_existe_para_quien_llama", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		v := b.vehiculo(alcance(b.sucursal()))
		_, err := b.q.BorrarVehiculo(b.ctx, BorrarVehiculoParams{ID: v, Sucursal: alcance(b.sucursal())})
		sinFilas(t, "alcance de otra sucursal", err)
		if !existe(b, v) {
			t.Fatal("borró un camión de otra sucursal")
		}
	})

	t.Run("inexistente", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		_, err := b.q.BorrarVehiculo(b.ctx, BorrarVehiculoParams{ID: uuid.New(), Sucursal: sinAlcance})
		sinFilas(t, "vehículo inexistente", err)
	})
}

// ---------------------------------------------------------------------------
// 5. ListarParadasQueViajaronEnRuta / MarcarResultadoDeParada / LimpiarResultadoDeParada
// ---------------------------------------------------------------------------

func TestMotorReal_ParadasQueViajaronYSuResultado(t *testing.T) {
	pool := motorReal(t)

	type escena struct {
		*banco
		suc, ruta, otra        uuid.UUID
		o1, o2, o3, o4, o5, o6 uuid.UUID
	}
	montar := func(t *testing.T) *escena {
		e := &escena{banco: nuevoBanco(t, pool)}
		e.suc = e.sucursal()
		e.ruta = e.banco.ruta(e.suc, RouteStatusInProgress)
		e.otra = e.banco.ruta(e.suc, RouteStatusInProgress)
		en := func(nombre string, ruta, ultima pgtype.UUID, ord int32) uuid.UUID {
			s := listo(nombre, e.suc)
			s.Ruta, s.UltimaRuta, s.StopOrder = ruta, ultima, i32(ord)
			return e.pedido(s)
		}
		// así llegan del tablero: route_id = ruta y ultima_ruta_id NULL
		e.o1 = en("o1", alcance(e.ruta), sinAlcance, 1)
		e.o2 = en("o2", alcance(e.ruta), sinAlcance, 2)
		// pertenece a OTRA ruta pero su historia dice que viajó en ésta
		e.o3 = en("o3", alcance(e.otra), alcance(e.ruta), 3)
		// suelto y sin historia
		e.o4 = en("o4", sinAlcance, sinAlcance, 4)
		// un devuelto de esta ruta, ya con route_id soltado
		e.o5 = en("o5", sinAlcance, alcance(e.ruta), 5)
		e.exec(`UPDATE orders SET resultado = 'devuelto', resultado_at = now() WHERE id = $1`, e.o5)
		// de otra sucursal, pero con route_id de esta ruta (dato corrupto)
		e.o6 = e.pedido(func() semilla {
			s := listo("o6", e.sucursal())
			s.Ruta = alcance(e.ruta)
			return s
		}())
		return e
	}
	nombresDe := func(filas []ListarParadasQueViajaronEnRutaRow) []string {
		var n []string
		for _, f := range filas {
			n = append(n, f.CustomerName)
		}
		return n
	}
	listar := func(t *testing.T, e *escena, ruta uuid.UUID, scope pgtype.UUID) []string {
		t.Helper()
		filas, err := e.q.ListarParadasQueViajaronEnRuta(e.ctx, ListarParadasQueViajaronEnRutaParams{RutaID: alcance(ruta), Sucursal: scope})
		if err != nil {
			t.Fatal(err)
		}
		n := nombresDe(filas)
		sort.Strings(n) // orden estable para comparar
		return n
	}

	t.Run("lista_las_que_viajaron_y_no_las_de_otra_ruta", func(t *testing.T) {
		e := montar(t)
		// o1 y o2 (route_id = ruta, ultima NULL) y o5 (devuelto: route_id NULL, ultima = ruta).
		// o3 tiene route_id de otra ruta: NO es de ésta aunque su ultima_ruta_id lo diga.
		// (o6 es un dato corrupto de OTRA sucursal con route_id de esta ruta: sólo se ve sin
		// alcance, y lo cubre el último subtest)
		igualesTxt(t, "con alcance", listar(t, e, e.ruta, alcance(e.suc)), []string{"o1", "o2", "o5"})
		igualesTxt(t, "la otra ruta", listar(t, e, e.otra, sinAlcance), []string{"o3"})
	})

	t.Run("marcar_entregado_un_pedido_que_vino_del_tablero", func(t *testing.T) {
		e := montar(t)
		n, err := e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(e.ruta), PedidoID: e.o1, Sucursal: alcance(e.suc)})
		if err != nil || n != 1 {
			t.Fatalf("n=%d err=%v", n, err)
		}
		p := e.leer(e.o1)
		if p.Resultado == nil || *p.Resultado != "entregado" || !p.Entregado || p.Status != "delivered" || !p.ResultadoAt {
			t.Fatalf("no quedó entregado: %+v", p)
		}
		// un entregado CONSERVA su ruta y queda anotada como la última
		if !p.Ruta.Valid || p.Ruta.Bytes != e.ruta || !p.UltimaRuta.Valid || p.UltimaRuta.Bytes != e.ruta {
			t.Fatalf("route_id/ultima_ruta_id: %+v", p)
		}
	})

	t.Run("marcar_devuelto_suelta_la_ruta_y_sigue_en_la_lista_y_se_puede_limpiar", func(t *testing.T) {
		e := montar(t)
		n, err := e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultDevuelto, RutaID: alcance(e.ruta), Nota: str("no estaba"), PedidoID: e.o2, Sucursal: sinAlcance})
		if err != nil || n != 1 {
			t.Fatalf("n=%d err=%v", n, err)
		}
		p := e.leer(e.o2)
		if p.Resultado == nil || *p.Resultado != "devuelto" || p.Entregado || p.Status != "pending" ||
			p.Ruta.Valid || !p.UltimaRuta.Valid || p.UltimaRuta.Bytes != e.ruta ||
			p.Nota == nil || *p.Nota != "no estaba" || p.StopOrder == nil || *p.StopOrder != 2 {
			t.Fatalf("devuelto mal escrito: %+v", p)
		}
		igualesTxt(t, "lista tras devolver", listar(t, e, e.ruta, alcance(e.suc)), []string{"o1", "o2", "o5"})

		// marcarlo OTRA VEZ ya con route_id NULL (corregir un devuelto): sigue valiendo
		n, err = e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultCancelado, RutaID: alcance(e.ruta), PedidoID: e.o2, Sucursal: sinAlcance})
		if err != nil || n != 1 {
			t.Fatalf("re-marcar un devuelto: n=%d err=%v", n, err)
		}

		// LimpiarResultadoDeParada deshace TODO y devuelve el pedido a su ruta
		n, err = e.q.LimpiarResultadoDeParada(e.ctx, LimpiarResultadoDeParadaParams{
			RutaID: alcance(e.ruta), PedidoID: e.o2, Sucursal: alcance(e.suc)})
		if err != nil || n != 1 {
			t.Fatalf("limpiar: n=%d err=%v", n, err)
		}
		p = e.leer(e.o2)
		if p.Resultado != nil || p.ResultadoAt || p.Nota != nil || p.Entregado || p.Status != "pending" ||
			!p.Ruta.Valid || p.Ruta.Bytes != e.ruta {
			t.Fatalf("limpiar no deshizo la marca: %+v", p)
		}
	})

	t.Run("limpiar_un_entregado_borra_la_hora_de_entrega", func(t *testing.T) {
		e := montar(t)
		if _, err := e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(e.ruta), PedidoID: e.o1, Sucursal: sinAlcance}); err != nil {
			t.Fatal(err)
		}
		n, err := e.q.LimpiarResultadoDeParada(e.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(e.ruta), PedidoID: e.o1, Sucursal: sinAlcance})
		if err != nil || n != 1 {
			t.Fatalf("n=%d err=%v", n, err)
		}
		if p := e.leer(e.o1); p.Entregado || p.Status != "pending" || p.Resultado != nil {
			t.Fatalf("quedó entregado: %+v", p)
		}
	})

	t.Run("un_devuelto_que_ya_solto_su_ruta_se_corrige_a_entregado", func(t *testing.T) {
		e := montar(t) // o5: route_id NULL, ultima = ruta, devuelto
		n, err := e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(e.ruta), PedidoID: e.o5, Sucursal: sinAlcance})
		if err != nil || n != 1 {
			t.Fatalf("n=%d err=%v", n, err)
		}
		if p := e.leer(e.o5); !p.Ruta.Valid || p.Ruta.Bytes != e.ruta || !p.Entregado {
			t.Fatalf("corregir devuelto->entregado: %+v", p)
		}
	})

	t.Run("no_se_roba_un_pedido_de_otra_ruta", func(t *testing.T) {
		e := montar(t) // o3: route_id = otra, ultima_ruta_id = ruta
		antes := e.leer(e.o3)
		n, err := e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(e.ruta), PedidoID: e.o3, Sucursal: sinAlcance})
		if err != nil || n != 0 {
			t.Fatalf("MarcarResultadoDeParada sobre pedido de otra ruta: n=%d err=%v (esperaba 0 filas)", n, err)
		}
		n, err = e.q.LimpiarResultadoDeParada(e.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(e.ruta), PedidoID: e.o3, Sucursal: sinAlcance})
		if err != nil || n != 0 {
			t.Fatalf("LimpiarResultadoDeParada sobre pedido de otra ruta: n=%d err=%v (esperaba 0 filas)", n, err)
		}
		if despues := e.leer(e.o3); !reflect.DeepEqual(antes, despues) {
			t.Fatalf("se robó el pedido:\n  antes   %+v\n  después %+v", antes, despues)
		}
		// y desde SU ruta sí se puede
		n, err = e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(e.otra), PedidoID: e.o3, Sucursal: sinAlcance})
		if err != nil || n != 1 {
			t.Fatalf("desde su ruta: n=%d err=%v", n, err)
		}
	})

	t.Run("pedido_suelto_y_sin_historia_no_se_puede_marcar", func(t *testing.T) {
		e := montar(t) // o4
		antes := e.leer(e.o4)
		n, err := e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(e.ruta), PedidoID: e.o4, Sucursal: sinAlcance})
		if err != nil || n != 0 {
			t.Fatalf("n=%d err=%v", n, err)
		}
		n, err = e.q.LimpiarResultadoDeParada(e.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(e.ruta), PedidoID: e.o4, Sucursal: sinAlcance})
		if err != nil || n != 0 {
			t.Fatalf("limpiar: n=%d err=%v", n, err)
		}
		if despues := e.leer(e.o4); !reflect.DeepEqual(antes, despues) {
			t.Fatalf("cambió:\n  antes   %+v\n  después %+v", antes, despues)
		}
	})

	t.Run("alcance_de_otra_sucursal_no_marca_ni_lista", func(t *testing.T) {
		e := montar(t)
		otraSuc := alcance(e.sucursal())
		n, err := e.q.MarcarResultadoDeParada(e.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(e.ruta), PedidoID: e.o1, Sucursal: otraSuc})
		if err != nil || n != 0 {
			t.Fatalf("marcar: n=%d err=%v", n, err)
		}
		n, err = e.q.LimpiarResultadoDeParada(e.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(e.ruta), PedidoID: e.o1, Sucursal: otraSuc})
		if err != nil || n != 0 {
			t.Fatalf("limpiar: n=%d err=%v", n, err)
		}
		igualesTxt(t, "lista con alcance ajeno", listar(t, e, e.ruta, otraSuc), nil)
		if p := e.leer(e.o1); p.Resultado != nil {
			t.Fatalf("marcó con alcance ajeno: %+v", p)
		}
		// el dato corrupto o6 (otra sucursal, route_id de esta ruta) sólo sale sin alcance
		igualesTxt(t, "sin alcance ve el corrupto", listar(t, e, e.ruta, sinAlcance), []string{"o1", "o2", "o5", "o6"})
	})
}

// ---------------------------------------------------------------------------
// 6. ColocarPedido (el filtro de factura del tablero) y PedidosDeColumnaParaArmarRuta
// ---------------------------------------------------------------------------

func TestMotorReal_ColocarPedidoFactura(t *testing.T) {
	pool := motorReal(t)

	// LO QUE DECIDE COLOCAR ES EL DOMICILIO COBRADO Y COTIZADO (Amado, 07/10/2026) Y NO LA
	// FACTURA. `factura_estado` no está en el `WHERE` de `ColocarPedido`: un pedido `cambiado`
	// o sin cotejar se puede preparar en una zona, y el corte a `igual` lo hace el armador con
	// su motivo. Se llegó a añadir el mismo día y se quitó (D1): estos casos son los que lo
	// vigilan, además del texto en `guardas_del_reparto_test.go`.
	casos := []struct {
		nombre    string
		factura   *string
		domicilio *float64
		costo     *float64
		pasa      bool
	}{
		{"cambiado_con_domicilio_y_costo", str("cambiado"), f64(5), f64(10), true},
		{"igual_con_domicilio_y_costo", str("igual"), f64(5), f64(10), true},
		{"cambiado_con_domicilio_pequeno", str("cambiado"), f64(0.01), f64(0), true}, // costo 0 NO es NULL
		{"sin_factura_pero_cobrado_y_cotizado", str("sin_factura"), f64(5), f64(10), true},
		{"factura_estado_null_pero_cobrado_y_cotizado", nil, f64(5), f64(10), true},
		{"igual_con_domicilio_null", str("igual"), nil, f64(10), false},
		{"igual_con_domicilio_cero", str("igual"), f64(0), f64(10), false},
		{"cambiado_con_domicilio_null", str("cambiado"), nil, f64(10), false},
		{"cambiado_con_domicilio_cero", str("cambiado"), f64(0), f64(10), false},
		{"cambiado_con_domicilio_negativo", str("cambiado"), f64(-1), f64(10), false},
		{"cambiado_sin_costo", str("cambiado"), f64(5), nil, false},
		{"igual_sin_costo", str("igual"), f64(5), nil, false},
		{"sin_factura_y_sin_cobrar", str("sin_factura"), nil, f64(10), false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			b := nuevoBanco(t, pool)
			suc := b.sucursal()
			col := b.columna(suc, "Centro", 0)
			s := listo("p", suc)
			s.Factura, s.Domicilio, s.Costo = c.factura, c.domicilio, c.costo
			p := b.pedido(s)

			fila, err := b.q.ColocarPedido(b.ctx, ColocarPedidoParams{
				Posicion: 0, ColocadoPor: str("jose"), PedidoID: p, ColumnaID: col, Sucursal: alcance(suc)})
			if c.pasa {
				if err != nil {
					t.Fatalf("debía dejarlo pasar y devolvió %v", err)
				}
				if fila.OrderID != p || fila.ColumnID != col || fila.BranchID != suc || fila.Posicion != 0 {
					t.Fatalf("fila: %+v", fila)
				}
				igualesTxt(t, "tablero", b.fichas(col), []string{"p@0"})
				return
			}
			sinFilas(t, "debía rechazarlo", err)
			if n := b.colocaciones(); n != 0 {
				t.Fatalf("lo rechazó pero dejó %d colocaciones", n)
			}
		})
	}

	// El resto de condiciones de ColocarPedido, para que la tabla de arriba no se lea como
	// «sólo importa la factura».
	otras := []struct {
		nombre string
		ajusta func(b *banco, s *semilla, suc uuid.UUID)
		pasa   bool
	}{
		{"ya_va_en_una_ruta", func(b *banco, s *semilla, suc uuid.UUID) { s.Ruta = alcance(b.ruta(suc, RouteStatusPlanned)) }, false},
		{"ya_entregado_delivered_at", func(_ *banco, s *semilla, _ uuid.UUID) { s.Entregado = true }, false},
		{"resultado_entregado", func(_ *banco, s *semilla, _ uuid.UUID) { s.Resultado = str("entregado") }, false},
		{"resultado_devuelto_si_se_puede", func(_ *banco, s *semilla, _ uuid.UUID) { s.Resultado = str("devuelto") }, true},
		{"pedido_de_otra_sucursal", func(b *banco, s *semilla, _ uuid.UUID) { s.Sucursal = b.sucursal() }, false},
	}
	for _, c := range otras {
		t.Run("otras_condiciones/"+c.nombre, func(t *testing.T) {
			b := nuevoBanco(t, pool)
			suc := b.sucursal()
			col := b.columna(suc, "Centro", 0)
			s := listo("p", suc)
			c.ajusta(b, &s, suc)
			p := b.pedido(s)
			_, err := b.q.ColocarPedido(b.ctx, ColocarPedidoParams{Posicion: 0, PedidoID: p, ColumnaID: col, Sucursal: alcance(suc)})
			if c.pasa && err != nil {
				t.Fatalf("debía dejarlo pasar: %v", err)
			}
			if !c.pasa {
				sinFilas(t, "debía rechazarlo", err)
			}
		})
	}

	t.Run("alcance_ajeno_no_coloca", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		p := b.pedido(listo("p", suc))
		_, err := b.q.ColocarPedido(b.ctx, ColocarPedidoParams{PedidoID: p, ColumnaID: col, Sucursal: alcance(b.sucursal())})
		sinFilas(t, "alcance ajeno", err)
	})

	t.Run("recolocar_mueve_de_columna_sin_duplicar", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		c1 := b.columna(suc, "Centro", 0)
		c2 := b.columna(suc, "Norte", 1)
		p := b.pedido(listo("p", suc))
		for _, col := range []uuid.UUID{c1, c2} {
			if _, err := b.q.ColocarPedido(b.ctx, ColocarPedidoParams{PedidoID: p, ColumnaID: col, Sucursal: alcance(suc)}); err != nil {
				t.Fatal(err)
			}
		}
		b.restricciones("ColocarPedido")
		igualesTxt(t, "columna origen", b.fichas(c1), nil)
		igualesTxt(t, "columna destino", b.fichas(c2), []string{"p@0"})
	})
}

func TestMotorReal_PedidosDeColumnaParaArmarRuta(t *testing.T) {
	pool := motorReal(t)

	t.Run("entrega_el_dato_de_factura_sin_filtrar_por_el", func(t *testing.T) {
		// El SQL lo dice: «SE ENTREGA EL DATO, NO SE FILTRA AQUÍ». El filtro de factura es de
		// ColocarPedido; esta consulta tiene que devolver también lo que no pasaría el
		// filtro (puesto a mano) para que el manejador lo NOMBRE entre los descartados.
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		colOtra := b.columna(suc, "Otra", 1)

		pon := func(nombre string, pos int, ajusta func(*semilla)) uuid.UUID {
			s := listo(nombre, suc)
			if ajusta != nil {
				ajusta(&s)
			}
			p := b.pedido(s)
			b.exec(`INSERT INTO board_placements (order_id, column_id, posicion) VALUES ($1, $2, $3)`, p, col, pos)
			return p
		}
		pon("bueno", 0, nil)
		pon("cambiado", 1, func(s *semilla) { s.Factura = str("cambiado") })
		pon("igual_sin_domicilio", 2, func(s *semilla) { s.Domicilio = nil })
		pon("sin_costo", 3, func(s *semilla) { s.Costo = nil })
		pon("sin_factura", 4, func(s *semilla) { s.Factura = str("sin_factura") })
		// los que SÍ descarta el WHERE
		pon("ya_en_ruta", 5, func(s *semilla) { s.Ruta = alcance(b.ruta(suc, RouteStatusPlanned)) })
		pon("sin_coordenadas", 6, func(s *semilla) { s.Coordenadas = false })
		pon("otro_origen", 7, func(s *semilla) { s.Source = nil })
		// una ficha de otra columna
		b.ficha(suc, colOtra, "de_otra_columna", 0)

		filas, err := b.q.PedidosDeColumnaParaArmarRuta(b.ctx, PedidosDeColumnaParaArmarRutaParams{ColumnaID: col, Sucursal: alcance(suc)})
		if err != nil {
			t.Fatal(err)
		}
		var nombres []string
		porNombre := map[string]PedidosDeColumnaParaArmarRutaRow{}
		for _, f := range filas {
			nombres = append(nombres, f.CustomerName)
			porNombre[f.CustomerName] = f
		}
		igualesTxt(t, "pedidos de la columna, en el orden del logístico", nombres,
			[]string{"bueno", "cambiado", "igual_sin_domicilio", "sin_costo", "sin_factura"})

		// y con el dato de factura SIN tocar, que es lo que le hace falta al manejador
		if f := porNombre["cambiado"]; f.FacturaEstado == nil || *f.FacturaEstado != FacturaEstadoCambiado {
			t.Fatalf("cambiado: %+v", f.FacturaEstado)
		}
		if f := porNombre["igual_sin_domicilio"]; f.FacturaDomicilio != nil {
			t.Fatalf("igual_sin_domicilio: factura_domicilio = %v, esperaba NULL", *f.FacturaDomicilio)
		}
		if f := porNombre["sin_costo"]; f.PedidoCosto != nil {
			t.Fatalf("sin_costo: pedido_costo = %v, esperaba NULL", *f.PedidoCosto)
		}
		if f := porNombre["sin_factura"]; f.FacturaEstado == nil || *f.FacturaEstado != FacturaEstadoSinFactura {
			t.Fatalf("sin_factura: %+v", f.FacturaEstado)
		}
		if f := porNombre["bueno"]; f.Posicion != 0 || f.Source == nil || *f.Source != ProcedenciaPedido || f.BranchID.Bytes != suc {
			t.Fatalf("bueno: %+v", f)
		}

		// alcance de otra sucursal: ni una fila
		ajenas, err := b.q.PedidosDeColumnaParaArmarRuta(b.ctx, PedidosDeColumnaParaArmarRutaParams{ColumnaID: col, Sucursal: alcance(b.sucursal())})
		if err != nil || len(ajenas) != 0 {
			t.Fatalf("alcance ajeno: %d filas, err=%v", len(ajenas), err)
		}
	})
}

// Las tres puertas del tablero tienen que decir lo mismo. El SQL de ListarPedidosSinColocar
// afirma que sus condiciones son «LAS MISMAS CINCO de ListarPedidosDisponibles» y que si el
// tablero ofreciera algo que luego se rechaza, el logístico prepararía una columna entera
// para nada. Aquí se comprueba contra la base: lo que la mitad izquierda OFRECE tiene que
// poder COLOCARSE.
func TestMotorReal_ListasDelTableroYColocarDicenLoMismo(t *testing.T) {
	pool := motorReal(t)

	montar := func(t *testing.T) (*banco, uuid.UUID, uuid.UUID, map[string]uuid.UUID) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		ids := map[string]uuid.UUID{}
		for _, c := range []struct {
			nombre    string
			factura   string
			domicilio *float64
			costo     *float64
		}{
			{"a_igual_completo", "igual", f64(5), f64(10)},
			{"b_igual_sin_domicilio", "igual", nil, f64(10)},
			{"c_igual_domicilio_cero", "igual", f64(0), f64(10)},
			{"d_cambiado_sin_costo", "cambiado", f64(5), nil},
			{"e_cambiado_completo", "cambiado", f64(5), f64(10)},
			{"f_sin_factura", "sin_factura", f64(5), f64(10)},
		} {
			s := listo(c.nombre, suc)
			s.Factura, s.Domicilio, s.Costo = str(c.factura), c.domicilio, c.costo
			ids[c.nombre] = b.pedido(s)
		}
		return b, suc, col, ids
	}

	t.Run("disponibles_exige_domicilio_y_costo", func(t *testing.T) {
		b, suc, _, _ := montar(t)
		filas, err := b.q.ListarPedidosDisponibles(b.ctx, ListarPedidosDisponiblesParams{
			BranchID: alcance(suc), Limite: 100})
		if err != nil {
			t.Fatal(err)
		}
		var nombres []string
		for _, f := range filas {
			nombres = append(nombres, f.CustomerName)
		}
		sort.Strings(nombres)
		igualesTxt(t, "ListarPedidosDisponibles", nombres, []string{"a_igual_completo", "e_cambiado_completo"})
	})

	t.Run("sin_colocar_solo_ofrece_lo_que_ColocarPedido_acepta", func(t *testing.T) {
		b, suc, col, _ := montar(t)
		filas, err := b.q.ListarPedidosSinColocar(b.ctx, ListarPedidosSinColocarParams{
			BranchID: suc, Sucursal: sinAlcance, Limite: 100})
		if err != nil {
			t.Fatal(err)
		}
		total, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{BranchID: suc, Sucursal: sinAlcance})
		if err != nil {
			t.Fatal(err)
		}
		if int(total) != len(filas) {
			t.Errorf("ContarPedidosSinColocar = %d y la lista trae %d", total, len(filas))
		}

		var ofrecidos, rechazados []string
		for _, f := range filas {
			ofrecidos = append(ofrecidos, f.CustomerName)
			_, err := b.q.ColocarPedido(b.ctx, ColocarPedidoParams{
				Posicion: int32(len(ofrecidos)), PedidoID: f.ID, ColumnaID: col, Sucursal: alcance(suc)})
			if errors.Is(err, pgx.ErrNoRows) {
				rechazados = append(rechazados, f.CustomerName)
			} else if err != nil {
				t.Fatal(err)
			}
		}
		sort.Strings(ofrecidos)
		sort.Strings(rechazados)
		t.Logf("ListarPedidosSinColocar ofrece: %v", ofrecidos)
		if len(rechazados) > 0 {
			t.Errorf("la mitad izquierda del tablero ofrece %v y ColocarPedido los rechaza (409): "+
				"ListarPedidosSinColocar/ContarPedidosSinColocar sólo exigen factura_estado IN ('igual','cambiado') "+
				"y le faltan `factura_domicilio > 0` y `pedido_costo IS NOT NULL`, que ColocarPedido y "+
				"ListarPedidosDisponibles sí exigen", rechazados)
		}
	})
}

// ---------------------------------------------------------------------------
// 7. LA PARADA FANTASMA (D3): quitar una parada la saca de verdad de la ruta
// ---------------------------------------------------------------------------

type totalesDeRuta struct {
	peso, precio float64
	sinCotizar   *int32
}

func (b *banco) totales(ruta uuid.UUID) totalesDeRuta {
	b.t.Helper()
	var t totalesDeRuta
	if err := b.tx.QueryRow(b.ctx, `SELECT total_weight, total_price, paradas_sin_cotizar FROM routes WHERE id = $1`,
		ruta).Scan(&t.peso, &t.precio, &t.sinCotizar); err != nil {
		b.t.Fatal(err)
	}
	return t
}

func (t totalesDeRuta) String() string {
	n := "NULL"
	if t.sinCotizar != nil {
		n = fmt.Sprint(*t.sinCotizar)
	}
	return fmt.Sprintf("{peso=%v precio=%v sin_cotizar=%s}", t.peso, t.precio, n)
}

// viajera: una parada tal y como la deja `EngancharPedidoARuta`, con `route_id` Y
// `ultima_ruta_id`, y con peso y costo para que se vean los totales.
func (b *banco) viajera(sucursal, ruta uuid.UUID, nombre string, orden int32, peso float64, costo *float64) uuid.UUID {
	b.t.Helper()
	s := listo(nombre, sucursal)
	s.Ruta, s.UltimaRuta = alcance(ruta), alcance(ruta)
	s.StopOrder, s.Peso, s.Costo = i32(orden), f64(peso), costo
	p := b.pedido(s)
	b.exec(`INSERT INTO order_items (order_id, linea, description, quantity) VALUES ($1, 1, $2, 1)`, p, "renglon de "+nombre)
	return p
}

func (b *banco) hoja(ruta uuid.UUID, scope pgtype.UUID) []string {
	b.t.Helper()
	filas, err := b.q.ListarParadasQueViajaronEnRuta(b.ctx, ListarParadasQueViajaronEnRutaParams{RutaID: alcance(ruta), Sucursal: scope})
	if err != nil {
		b.t.Fatal(err)
	}
	var n []string
	for _, f := range filas {
		n = append(n, f.CustomerName)
	}
	sort.Strings(n)
	return n
}

func (b *banco) renglonesDe(ruta uuid.UUID) []string {
	b.t.Helper()
	filas, err := b.q.ListarRenglonesDeRuta(b.ctx, ListarRenglonesDeRutaParams{RutaID: alcance(ruta), Sucursal: sinAlcance})
	if err != nil {
		b.t.Fatal(err)
	}
	var n []string
	for _, f := range filas {
		n = append(n, f.CustomerName)
	}
	sort.Strings(n)
	return n
}

func TestMotorReal_ParadaFantasma(t *testing.T) {
	pool := motorReal(t)

	montar := func(t *testing.T) (*banco, uuid.UUID, uuid.UUID, [3]uuid.UUID) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		ruta := b.ruta(suc, RouteStatusPlanned)
		var p [3]uuid.UUID
		p[0] = b.viajera(suc, ruta, "p1", 1, 10, f64(5))
		p[1] = b.viajera(suc, ruta, "p2", 2, 20, f64(2))
		p[2] = b.viajera(suc, ruta, "p3", 3, 30, f64(7))
		return b, suc, ruta, p
	}
	quitar := func(b *banco, suc, ruta, pedido uuid.UUID) {
		b.t.Helper()
		if _, err := b.q.SoltarParadaPlanificada(b.ctx, SoltarParadaPlanificadaParams{
			PedidoID: pedido, RutaID: ruta, Sucursal: alcance(suc)}); err != nil {
			b.t.Fatal(err)
		}
	}

	t.Run("quitar_una_parada_baja_los_totales_de_la_ruta", func(t *testing.T) {
		b, suc, ruta, p := montar(t)
		if got := b.totales(ruta).String(); got != "{peso=60 precio=14 sin_cotizar=0}" {
			t.Fatalf("antes de quitar: %s", got)
		}
		quitar(b, suc, ruta, p[1])
		// El trigger de 00014 suma por `ultima_ruta_id`: si el quitado la conservara, seguiría
		// contando aquí (60 kg y 14 de importe) sobre una ruta que ya no lo lleva.
		if got := b.totales(ruta).String(); got != "{peso=40 precio=12 sin_cotizar=0}" {
			t.Fatalf("tras quitar p2 la ruta debería pesar 40 y valer 12: %s", got)
		}
		quitar(b, suc, ruta, p[0])
		if got := b.totales(ruta).String(); got != "{peso=30 precio=7 sin_cotizar=0}" {
			t.Fatalf("tras quitar también p1: %s", got)
		}
	})

	t.Run("quitar_una_parada_sin_cotizar_baja_tambien_el_contador", func(t *testing.T) {
		b, suc, ruta, _ := montar(t)
		sin := b.viajera(suc, ruta, "sin_costo", 4, 5, nil)
		if got := b.totales(ruta).String(); got != "{peso=65 precio=14 sin_cotizar=1}" {
			t.Fatalf("antes: %s", got)
		}
		quitar(b, suc, ruta, sin)
		if got := b.totales(ruta).String(); got != "{peso=60 precio=14 sin_cotizar=0}" {
			t.Fatalf("quitar la que no tenía costo tiene que bajar `paradas_sin_cotizar`: %s", got)
		}
	})

	t.Run("el_quitado_queda_suelto_y_sin_historia_de_esa_ruta", func(t *testing.T) {
		b, suc, ruta, p := montar(t)
		quitar(b, suc, ruta, p[1])
		e := b.leer(p[1])
		if e.Ruta.Valid || e.UltimaRuta.Valid || e.StopOrder != nil || e.SegmentKm != nil {
			t.Fatalf("el quitado conserva rastro de la ruta: %+v", e)
		}
		// Los `stop_order` de las demás NO se renumeran (queda un hueco), y `total_distance`
		// tampoco se toca: está documentado en la consulta.
		if o := b.leer(p[2]); o.StopOrder == nil || *o.StopOrder != 3 {
			t.Fatalf("p3 cambió de orden: %+v", o)
		}
	})

	t.Run("el_quitado_no_sale_en_la_hoja_ni_en_los_renglones_de_la_ruta", func(t *testing.T) {
		b, suc, ruta, p := montar(t)
		igualesTxt(t, "hoja antes", b.hoja(ruta, alcance(suc)), []string{"p1", "p2", "p3"})
		quitar(b, suc, ruta, p[1])
		igualesTxt(t, "hoja tras quitar p2", b.hoja(ruta, alcance(suc)), []string{"p1", "p3"})
		igualesTxt(t, "renglones tras quitar p2", b.renglonesDe(ruta), []string{"p1", "p3"})
	})

	t.Run("el_quitado_no_se_puede_marcar_ni_desmarcar_desde_esa_ruta", func(t *testing.T) {
		b, suc, ruta, p := montar(t)
		quitar(b, suc, ruta, p[1])
		antes := b.leer(p[1])
		n, err := b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(ruta), PedidoID: p[1], Sucursal: alcance(suc)})
		if err != nil || n != 0 {
			t.Fatalf("marcar un pedido quitado: n=%d err=%v (esperaba 0 filas)", n, err)
		}
		n, err = b.q.LimpiarResultadoDeParada(b.ctx, LimpiarResultadoDeParadaParams{
			RutaID: alcance(ruta), PedidoID: p[1], Sucursal: alcance(suc)})
		if err != nil || n != 0 {
			t.Fatalf("desmarcar un pedido quitado: n=%d err=%v (esperaba 0 filas)", n, err)
		}
		if despues := b.leer(p[1]); !reflect.DeepEqual(antes, despues) {
			t.Fatalf("el cierre tocó un pedido que ya no va en la ruta:\n  antes   %v\n  después %v", antes, despues)
		}
	})

	// LA SEGUNDA LLAVE, sin pasar por SoltarParadaPlanificada: una fila que viene de antes (o
	// que dejó otro camino) con `route_id` nulo, `ultima_ruta_id` = la ruta y SIN resultado.
	// Es justo lo que `resultado IS NOT NULL` en la rama del NULL deja fuera.
	t.Run("una_fila_fantasma_de_antes_tampoco_cuenta", func(t *testing.T) {
		b, suc, ruta, _ := montar(t)
		s := listo("fantasma", suc)
		s.UltimaRuta, s.StopOrder = alcance(ruta), i32(9)
		f := b.pedido(s)
		b.exec(`INSERT INTO order_items (order_id, linea, description, quantity) VALUES ($1, 1, 'x', 1)`, f)
		igualesTxt(t, "hoja", b.hoja(ruta, sinAlcance), []string{"p1", "p2", "p3"})
		igualesTxt(t, "renglones", b.renglonesDe(ruta), []string{"p1", "p2", "p3"})
		n, err := b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(ruta), PedidoID: f, Sucursal: sinAlcance})
		if err != nil || n != 0 {
			t.Fatalf("marcar la fantasma: n=%d err=%v", n, err)
		}
		n, err = b.q.LimpiarResultadoDeParada(b.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(ruta), PedidoID: f, Sucursal: sinAlcance})
		if err != nil || n != 0 {
			t.Fatalf("desmarcar la fantasma: n=%d err=%v", n, err)
		}
	})

	// LA PAREJA: lo que SÍ viajó se sigue viendo. Un devuelto suelta su `route_id` pero tiene
	// resultado, y tiene que seguir en la hoja, en los renglones y poder corregirse.
	t.Run("el_devuelto_sigue_en_la_hoja_y_se_puede_corregir", func(t *testing.T) {
		b, _, ruta, p := montar(t)
		n, err := b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultDevuelto, RutaID: alcance(ruta), PedidoID: p[0], Sucursal: sinAlcance})
		if err != nil || n != 1 {
			t.Fatalf("devolver: n=%d err=%v", n, err)
		}
		if e := b.leer(p[0]); e.Ruta.Valid || !e.UltimaRuta.Valid {
			t.Fatalf("un devuelto suelta route_id y conserva ultima_ruta_id: %+v", e)
		}
		igualesTxt(t, "hoja con un devuelto", b.hoja(ruta, sinAlcance), []string{"p1", "p2", "p3"})
		igualesTxt(t, "renglones con un devuelto", b.renglonesDe(ruta), []string{"p1", "p2", "p3"})
		n, err = b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
			Resultado: StopResultEntregado, RutaID: alcance(ruta), PedidoID: p[0], Sucursal: sinAlcance})
		if err != nil || n != 1 {
			t.Fatalf("corregir el devuelto a entregado: n=%d err=%v", n, err)
		}
	})
}

// ---------------------------------------------------------------------------
// 8. board_route_origins (D5): borrar una zona vacía con ruta planificada, y orígenes viejos
// ---------------------------------------------------------------------------

func TestMotorReal_BorrarColumnaConRutaPlanificada(t *testing.T) {
	pool := motorReal(t)

	t.Run("una_zona_vacia_con_ruta_planificada_se_borra_y_su_origen_se_va", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		ruta := b.ruta(suc, RouteStatusPlanned)
		p := b.parada(suc, ruta, col, "p1", 1, 1)
		if b.colocaciones() != 0 {
			t.Fatal("la zona tenía que estar vacía de tarjetas")
		}
		n, err := b.q.BorrarColumna(b.ctx, BorrarColumnaParams{ID: col, Sucursal: alcance(suc)})
		if err != nil || n != 1 {
			// Con `ON DELETE RESTRICT` esto era un 23503 y el manejador contestaba el 409
			// falso «tiene 0 pedidos puestos».
			t.Fatalf("borrar la zona vacía: n=%d err=%v", n, err)
		}
		if b.tieneOrigen(p) {
			t.Fatal("el origen de la parada sobrevivió a su zona")
		}
		// La ruta y la parada no se tocan, y borrar la ruta después no restaura nada ni falla.
		if e := b.leer(p); !e.Ruta.Valid {
			t.Fatalf("la parada perdió su ruta: %+v", e)
		}
		filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
		if err != nil || filas != 1 {
			t.Fatalf("soltar la ruta tras borrar la zona: filas=%d err=%v", filas, err)
		}
		b.restricciones("SoltarPedidosDeRuta tras borrar la zona")
		if b.colocaciones() != 0 {
			t.Fatal("se restauró una tarjeta en una zona que ya no existe")
		}
		if e := b.leer(p); e.Ruta.Valid || e.StopOrder != nil {
			t.Fatalf("el pedido tenía que quedar suelto: %+v", e)
		}
	})

	// LA PAREJA: con tarjetas puestas la base SIGUE negándose. El `CASCADE` es sólo de los
	// orígenes; las colocaciones son trabajo de una persona y borrar eso no puede ser silencioso.
	t.Run("una_zona_con_tarjetas_puestas_sigue_sin_poder_borrarse", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		b.ficha(suc, col, "a", 0)
		// SAVEPOINT: el error de la restricción aborta la transacción entera del banco.
		b.exec(`SAVEPOINT antes_de_borrar`)
		_, err := b.q.BorrarColumna(b.ctx, BorrarColumnaParams{ID: col, Sucursal: alcance(suc)})
		if err == nil {
			t.Fatal("se borró una zona con tarjetas puestas")
		}
		var pgErr interface{ SQLState() string }
		if !errors.As(err, &pgErr) || pgErr.SQLState() != "23503" {
			t.Fatalf("esperaba la violación de clave ajena 23503 y llegó %v", err)
		}
		b.exec(`ROLLBACK TO SAVEPOINT antes_de_borrar`)
		igualesTxt(t, "la zona sigue con su tarjeta", b.fichas(col), []string{"a@0"})
	})
}

func TestMotorReal_UnOrigenViejoNoBloqueaAlNuevo(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	zonaVieja := b.columna(suc, "Vieja", 0)
	zonaNueva := b.columna(suc, "Nueva", 1)
	rutaVieja := b.ruta(suc, RouteStatusInProgress)
	rutaNueva := b.ruta(suc, RouteStatusPlanned)

	// Un devuelto de una ruta EN CURSO: soltó su route_id pero el origen de aquella ruta sigue
	// ahí (se borra al completar o al borrar la ruta).
	p := b.pedido(listo("devuelto", suc))
	b.exec(`INSERT INTO board_route_origins (route_id, order_id, column_id, posicion, colocado_por) VALUES ($1, $2, $3, 7, 'viejo')`,
		rutaVieja, p, zonaVieja)
	// Mañana lo colocan en OTRA zona y arman otra ruta.
	b.exec(`INSERT INTO board_placements (order_id, column_id, posicion, colocado_por) VALUES ($1, $2, 3, 'nuevo')`, p, zonaNueva)
	b.exec(`UPDATE orders SET route_id = $1, ultima_ruta_id = $1, stop_order = 1 WHERE id = $2`, rutaNueva, p)

	n, err := b.q.QuitarDelTableroLosDeRuta(b.ctx, QuitarDelTableroLosDeRutaParams{RutaID: alcance(rutaNueva), Sucursal: alcance(suc)})
	if err != nil || n != 1 {
		t.Fatalf("QuitarDelTableroLosDeRuta: n=%d err=%v", n, err)
	}
	var ruta, col uuid.UUID
	var pos int32
	if err := b.tx.QueryRow(b.ctx, `SELECT route_id, column_id, posicion FROM board_route_origins WHERE order_id = $1`, p).Scan(&ruta, &col, &pos); err != nil {
		t.Fatal(err)
	}
	if ruta != rutaNueva || col != zonaNueva || pos != 3 {
		t.Fatalf("el origen vigente tenía que ser el NUEVO (ruta nueva, zona nueva, posición 3) y es ruta=%s zona=%s posición=%d",
			ruta, col, pos)
	}
	if b.entero(`SELECT count(*) FROM board_route_origins WHERE order_id = $1`, p) != 1 {
		t.Fatal("tiene que haber UN origen por pedido")
	}

	// Y borrar la ruta nueva devuelve el pedido a la zona NUEVA, no a la de ayer.
	filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(rutaNueva), Sucursal: alcance(suc)})
	if err != nil || filas != 1 {
		t.Fatalf("SoltarPedidosDeRuta: filas=%d err=%v", filas, err)
	}
	b.restricciones("SoltarPedidosDeRuta")
	igualesTxt(t, "zona nueva", b.fichas(zonaNueva), []string{"devuelto@3"})
	igualesTxt(t, "zona vieja", b.fichas(zonaVieja), nil)
}

// ---------------------------------------------------------------------------
// 9. EngancharPedidoARuta: las dos de Amado, y `factura_estado` NO (D1)
// ---------------------------------------------------------------------------

func TestMotorReal_EngancharPedidoARuta(t *testing.T) {
	pool := motorReal(t)

	casos := []struct {
		nombre    string
		factura   *string
		domicilio *float64
		costo     *float64
		pasa      bool
	}{
		{"igual_cobrado_y_cotizado", str("igual"), f64(5), f64(10), true},
		// El SQL NO corta `cambiado`: lo corta el manejador, para poder nombrarlo. Este caso
		// documenta la mitad de la regla que vive en Go (`mensajeNoFacturados`).
		{"cambiado_pasa_el_sql_y_lo_corta_el_manejador", str("cambiado"), f64(5), f64(10), true},
		{"sin_cobrar", str("igual"), nil, f64(10), false},
		{"domicilio_en_cero", str("igual"), f64(0), f64(10), false},
		{"sin_cotizar", str("igual"), f64(5), nil, false},
		{"costo_cero_no_es_null", str("igual"), f64(5), f64(0), true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			b := nuevoBanco(t, pool)
			suc := b.sucursal()
			ruta := b.ruta(suc, RouteStatusPlanned)
			s := listo("p", suc)
			s.Factura, s.Domicilio, s.Costo = c.factura, c.domicilio, c.costo
			p := b.pedido(s)
			n, err := b.q.EngancharPedidoARuta(b.ctx, EngancharPedidoARutaParams{
				PedidoID: p, RutaID: alcance(ruta), StopOrder: i32(1), Sucursal: alcance(suc)})
			if err != nil {
				t.Fatal(err)
			}
			if (n == 1) != c.pasa {
				t.Fatalf("filas=%d, pasa esperado=%v", n, c.pasa)
			}
			if e := b.leer(p); e.Ruta.Valid != c.pasa {
				t.Fatalf("estado del pedido: %v", e)
			}
		})
	}

	t.Run("un_pedido_que_ya_va_en_otra_ruta_no_se_engancha", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		otra, ruta := b.ruta(suc, RouteStatusPlanned), b.ruta(suc, RouteStatusPlanned)
		s := listo("p", suc)
		s.Ruta = alcance(otra)
		p := b.pedido(s)
		n, err := b.q.EngancharPedidoARuta(b.ctx, EngancharPedidoARutaParams{
			PedidoID: p, RutaID: alcance(ruta), StopOrder: i32(1), Sucursal: alcance(suc)})
		if err != nil || n != 0 {
			t.Fatalf("n=%d err=%v", n, err)
		}
	})
}

// ---------------------------------------------------------------------------
// 10. Lo que se ofrece y lo que se cuenta dicen lo mismo (D2)
// ---------------------------------------------------------------------------

func TestMotorReal_DisponiblesPanelYSinColocarCuentanLoMismo(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	b.columna(suc, "Centro", 0)
	for _, c := range []struct {
		nombre    string
		factura   string
		domicilio *float64
		costo     *float64
		peso      float64
	}{
		{"a_ok", "igual", f64(5), f64(10), 10},
		{"b_cambiado_ok", "cambiado", f64(5), f64(10), 20},
		{"c_sin_cobrar", "igual", nil, f64(10), 40},
		{"d_domicilio_cero", "igual", f64(0), f64(10), 80},
		{"e_sin_cotizar", "cambiado", f64(5), nil, 160},
		{"f_sin_factura", "sin_factura", f64(5), f64(10), 320},
	} {
		s := listo(c.nombre, suc)
		s.Factura, s.Domicilio, s.Costo, s.Peso = str(c.factura), c.domicilio, c.costo, f64(c.peso)
		b.pedido(s)
	}

	disp, err := b.q.ContarPedidosDisponibles(b.ctx, ContarPedidosDisponiblesParams{BranchID: alcance(suc)})
	if err != nil {
		t.Fatal(err)
	}
	lista, err := b.q.ListarPedidosDisponibles(b.ctx, ListarPedidosDisponiblesParams{BranchID: alcance(suc), Limite: 100})
	if err != nil {
		t.Fatal(err)
	}
	if disp != 2 || len(lista) != 2 {
		t.Fatalf("disponibles: contador=%d lista=%d, esperaba 2 y 2 (a y b)", disp, len(lista))
	}

	sin, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{BranchID: suc, Sucursal: sinAlcance})
	if err != nil {
		t.Fatal(err)
	}
	if sin != disp {
		t.Fatalf("«Sin colocar» cuenta %d y los disponibles %d: el tablero ofrece algo que el armador no", sin, disp)
	}

	// El Panel: el mismo número y el mismo peso (10 + 20 = 30), por resumen y por sucursal.
	hoy := pgtype.Timestamptz{Time: time.Now().Add(-24 * time.Hour), Valid: true}
	resumen, err := b.q.PanelResumen(b.ctx, PanelResumenParams{Hoy: hoy, Sucursal: alcance(suc)})
	if err != nil {
		t.Fatal(err)
	}
	if int64(resumen.SinRuta) != disp || resumen.PesoPendiente != 30 {
		t.Fatalf("PanelResumen: sin_ruta=%d peso_pendiente=%v, esperaba %d y 30", resumen.SinRuta, resumen.PesoPendiente, disp)
	}
	porSucursal, err := b.q.PanelPorSucursal(b.ctx, alcance(suc))
	if err != nil {
		t.Fatal(err)
	}
	if len(porSucursal) != 1 || int64(porSucursal[0].Pedidos) != disp || porSucursal[0].PesoKg != 30 {
		t.Fatalf("PanelPorSucursal: %+v, esperaba %d pedidos y 30 kg", porSucursal, disp)
	}
}

// ---------------------------------------------------------------------------
// 11. Vehículos: is_active
// ---------------------------------------------------------------------------

func TestMotorReal_VehiculoInactivo(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	v := b.vehiculo(alcance(suc))

	fila, err := b.q.ObtenerVehiculoParaCapacidad(b.ctx, v)
	if err != nil || !fila.IsActive {
		t.Fatalf("un camión nuevo nace ACTIVO: %+v err=%v", fila, err)
	}
	// Sin tocar `isActive` (nil) NO cambia; con false se desactiva. Es el coalesce de la consulta.
	if _, err := b.q.ActualizarVehiculo(b.ctx, ActualizarVehiculoParams{ID: v, Sucursal: alcance(suc), Notes: nil}); err != nil {
		t.Fatal(err)
	}
	if fila, _ := b.q.ObtenerVehiculoParaCapacidad(b.ctx, v); !fila.IsActive {
		t.Fatal("actualizar sin `is_active` lo desactivó")
	}
	no := false
	if _, err := b.q.ActualizarVehiculo(b.ctx, ActualizarVehiculoParams{ID: v, Sucursal: alcance(suc), IsActive: &no}); err != nil {
		t.Fatal(err)
	}
	if fila, _ := b.q.ObtenerVehiculoParaCapacidad(b.ctx, v); fila.IsActive {
		t.Fatal("no se pudo marcar inactivo")
	}
	// Inactivo conserva su historial: sigue en la lista de la flota (la app lo filtra con `isActive`).
	lista, err := b.q.ListarVehiculos(b.ctx, alcance(suc))
	if err != nil || len(lista) != 1 || lista[0].IsActive {
		t.Fatalf("la lista tiene que traerlo con is_active=false: %+v err=%v", lista, err)
	}
}
