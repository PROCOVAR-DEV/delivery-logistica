package sincro

// LA BANDEJA DE REVISIÓN CONTRA UN POSTGRES DE VERDAD.
//
// POR QUÉ EXISTE. Lo que más importa de la bandeja lo hace la BASE, no el Go: los triggers que impiden
// borrar y cambiar el original, el `CHECK` que exige motivo en un descarte, el `ON CONFLICT DO NOTHING` de la
// idempotencia, el alcance de sucursal DENTRO del SQL. Un doble de la base reimplementa el SQL y no ve nada de
// eso (la auditoría del 08/10/2026 lo midió en la API: de 14 guardas del SQL generado, sólo la prueba de motor
// real cazó las 14). Estas pruebas ejecutan las consultas que genera sqlc contra las migraciones de verdad.
//
// CÓMO SE EJECUTAN. Sólo con una base AISLADA, y sólo si se pide (docs/entorno-local.md):
//
//	docker exec -e PGPASSWORD=reparto reparto-postgres-1 psql -U reparto -d postgres -c 'CREATE DATABASE verif_sync OWNER verif'
//	goose -dir db/migrations postgres 'postgres://verif:verif@127.0.0.1:5433/verif_sync?sslmode=disable' up
//	SYNC_MOTOR_REAL_DSN='postgres://verif:verif@127.0.0.1:5433/verif_sync?sslmode=disable' go test -count=1 -run 'MotorReal|Revision|Entreg' ./internal/sincro/ -v
//
// Sin la variable se saltan (y `./comprobar.sh` lo dice a gritos: «SALTADO»). Nunca leen DATABASE_URL ni otra
// variable de producción, y se niegan a correr si la base no se llama `verif…`, `…test…` o `…prueba…`.
//
// CÓMO NO ENSUCIAN. Cada prueba abre UNA transacción y la revierte al terminar; `EnTransaccion` del servicio
// es un SAVEPOINT dentro de ella. La base queda como estaba, que aquí además es obligatorio: ni un DELETE
// puede limpiar lo que se escriba.

import (
	"context"
	"encoding/json"
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
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// datosEnTx: los datos de siempre sobre UNA transacción abierta. `EnTransaccion` es un savepoint, así que un
// error dentro (un CHECK, una unicidad) lo deshace sin matar la transacción de la prueba.
type datosEnTx struct {
	*sqlc.Queries
	tx pgx.Tx
}

var _ store.Datos = (*datosEnTx)(nil)

func (d *datosEnTx) EnTransaccion(ctx context.Context, fn func(sqlc.Querier) error) error {
	sp, err := d.tx.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = sp.Rollback(ctx) }()
	if err := fn(d.Queries.WithTx(sp)); err != nil {
		return err
	}
	return sp.Commit(ctx)
}

// motorReal abre la conexión y comprueba las tres cosas que la hacen segura: que se pidió, que la base es
// de pruebas y que está migrada hasta la bandeja.
func motorRealSync(t *testing.T) (context.Context, *pgxpool.Pool) {
	t.Helper()
	dsn := os.Getenv("SYNC_MOTOR_REAL_DSN")
	if dsn == "" {
		t.Skip("SALTADO: requiere PostgreSQL aislado en SYNC_MOTOR_REAL_DSN (docs/entorno-local.md)")
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
	var version int64
	if err := pool.QueryRow(ctx, "SELECT COALESCE(max(version_id), 0) FROM goose_db_version WHERE is_applied").Scan(&version); err != nil {
		t.Fatalf("la base %q no está migrada con goose: %v", base, err)
	}
	if version < 4 {
		t.Fatalf("la base %q está en la migración %d y el revisor pide la 00004: `goose -dir db/migrations postgres <dsn> up`", base, version)
	}
	return ctx, pool
}

func datosEnPostgresReal(t *testing.T) store.Datos {
	t.Helper()
	ctx, pool := motorRealSync(t)
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = tx.Rollback(context.Background()) })
	return &datosEnTx{Queries: sqlc.New(tx), tx: tx}
}

// ---------------------------------------------------------------------------
// Lo que la base impide aunque el Go se equivoque
// ---------------------------------------------------------------------------

func (d *datosEnTx) debeFallar(t *testing.T, etiqueta, sqlstate, sentencia string, args ...any) {
	t.Helper()
	ctx := context.Background()
	sp, err := d.tx.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	_, err = sp.Exec(ctx, sentencia, args...)
	_ = sp.Rollback(ctx)
	var pg *pgconn.PgError
	switch {
	case err == nil:
		t.Errorf("%s: LA BASE LO DEJÓ PASAR (%s)", etiqueta, sentencia)
	case !errors.As(err, &pg):
		t.Errorf("%s: falló, pero no con un error de Postgres: %v", etiqueta, err)
	case pg.Code != sqlstate:
		t.Errorf("%s: falló con %s (%s) y se esperaba %s", etiqueta, pg.Code, pg.Message, sqlstate)
	}
}

func (d *datosEnTx) debePasar(t *testing.T, etiqueta, sentencia string, args ...any) {
	t.Helper()
	ctx := context.Background()
	sp, err := d.tx.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = sp.Rollback(ctx) }()
	if _, err := sp.Exec(ctx, sentencia, args...); err != nil {
		t.Errorf("%s: tenía que pasar y falló: %v", etiqueta, err)
	}
}

const (
	restrictViolation = "23001" // los triggers: ni borrar ni reescribir
	checkViolation    = "23514"
	foreignKey        = "23503"
)

// siembraDeUnaEntrega: un aparato, una entrega y los apuntes que se pidan, en `en_revision`.
func siembraDeUnaEntrega(t *testing.T, d *datosEnTx, claves ...string) (aparato sqlc.Aparato, entrega sqlc.RevisionEntrega) {
	t.Helper()
	ctx := context.Background()
	aparato, err := d.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: "autor-" + uuid.NewString(), BranchID: uuid.New()})
	if err != nil {
		t.Fatal(err)
	}
	entrega, err = d.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{
		AparatoID: aparato.ID, Persona: aparato.Persona, BranchID: aparato.BranchID, TokenJti: "jti-" + uuid.NewString()})
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range claves {
		cuerpo := `{"a": 1}`
		if _, err := d.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{
			AparatoID: aparato.ID, Clave: c, EntregaID: entrega.ID, Metodo: "POST", Ruta: "/routes", Cuerpo: &cuerpo,
			HechoAt: marca(time.Now()), Huella: strings.Repeat("a", 64)}); err != nil {
			t.Fatal(err)
		}
	}
	return aparato, entrega
}

func TestMotorRealLaBaseImpideBorrarYCambiarElOriginal(t *testing.T) {
	d := datosEnPostgresReal(t).(*datosEnTx)
	ctx := context.Background()
	aparato, entrega := siembraDeUnaEntrega(t, d, "c1", "c2")
	if _, err := d.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{
		AparatoID: aparato.ID, Clave: "c1", Accion: "aplicar", Por: "revisor", Resultado: "caida"}); err != nil {
		t.Fatal(err)
	}

	// NI UN DELETE, en ninguna de las tres tablas.
	d.debeFallar(t, "DELETE de un apunte", restrictViolation, `DELETE FROM revision_apuntes WHERE aparato_id = $1`, aparato.ID)
	d.debeFallar(t, "DELETE de una entrega", restrictViolation, `DELETE FROM revision_entregas WHERE id = $1`, entrega.ID)
	d.debeFallar(t, "DELETE del libro", restrictViolation, `DELETE FROM revision_decisiones WHERE aparato_id = $1`, aparato.ID)
	d.debeFallar(t, "DELETE sin WHERE", restrictViolation, `DELETE FROM revision_apuntes`)
	// Ni un TRUNCATE, ni en cascada desde arriba.
	d.debeFallar(t, "TRUNCATE del libro", restrictViolation, `TRUNCATE revision_decisiones`)
	d.debeFallar(t, "TRUNCATE de los apuntes y el libro", restrictViolation, `TRUNCATE revision_apuntes, revision_decisiones`)
	d.debeFallar(t, "TRUNCATE de las entregas en cascada", restrictViolation, `TRUNCATE revision_entregas CASCADE`)
	d.debeFallar(t, "TRUNCATE de los aparatos en cascada", restrictViolation, `TRUNCATE aparatos CASCADE`)
	// Y CADA tabla tiene el suyo: se apagan los de las otras dos (dentro de la transacción de la prueba, que se
	// revierte) y se vacían las tres a la vez; si el de ESA falta, el TRUNCATE pasa y esto se pone rojo.
	tablas := []string{"revision_entregas", "revision_apuntes", "revision_decisiones"}
	for _, quedaEncendido := range tablas {
		var apaga []string
		for _, otra := range tablas {
			if otra != quedaEncendido {
				apaga = append(apaga, fmt.Sprintf(`ALTER TABLE %s DISABLE TRIGGER trg_%s_no_truncate;`, otra, otra))
			}
		}
		d.debeFallar(t, "TRUNCATE con sólo el trigger de "+quedaEncendido, restrictViolation,
			strings.Join(apaga, " ")+` TRUNCATE revision_entregas, revision_apuntes, revision_decisiones`)
	}
	// Ni borrar el aparato del que cuelgan (RESTRICT).
	d.debeFallar(t, "DELETE del aparato con apuntes en revisión", foreignKey, `DELETE FROM aparatos WHERE id = $1`, aparato.ID)

	// EL ORIGINAL NO SE CAMBIA, columna por columna.
	for col, valor := range map[string]string{
		"cuerpo": `'otro'`, "metodo": `'PUT'`, "ruta": `'/routes/otra'`, "hecho_at": `now() - interval '1 day'`,
		"huella": `'` + strings.Repeat("b", 64) + `'`, "entrega_id": `gen_random_uuid()`, "orden": `99`,
		"clave": `'otra'`, "provisional": `'local-x'`, "resumen_del_aparato": `'otro'`, "created_at": `now() - interval '1 day'`,
		"aparato_id": `gen_random_uuid()`,
	} {
		d.debeFallar(t, "UPDATE de "+col, restrictViolation,
			fmt.Sprintf(`UPDATE revision_apuntes SET %s = %s WHERE aparato_id = $1 AND clave = 'c1'`, col, valor), aparato.ID)
	}
	// Quién entregó y con qué token tampoco.
	for col, valor := range map[string]string{"persona": `'otro'`, "token_jti": `'otro'`, "branch_id": `gen_random_uuid()`, "persona_nombre": `'Otro'`} {
		d.debeFallar(t, "UPDATE de la entrega: "+col, restrictViolation,
			fmt.Sprintf(`UPDATE revision_entregas SET %s = %s WHERE id = $1`, col, valor), entrega.ID)
	}
	// El libro sólo se añade.
	d.debeFallar(t, "UPDATE del libro", restrictViolation, `UPDATE revision_decisiones SET motivo = 'x'`)

	// Y LO QUE SÍ SE MUEVE, se mueve: sin esto las guardas de arriba podrían estar rechazándolo todo.
	d.debePasar(t, "la decisión de un apunte", `UPDATE revision_apuntes SET intentos = 3, motivo = NULL, updated_at = now() WHERE aparato_id = $1 AND clave = 'c1'`, aparato.ID)
	d.debePasar(t, "tocar la entrega (el ON CONFLICT de la entrega)", `UPDATE revision_entregas SET updated_at = now() WHERE id = $1`, entrega.ID)
	d.debePasar(t, "añadir al libro", `INSERT INTO revision_decisiones (aparato_id, clave, accion, por, resultado) VALUES ($1, 'c2', 'descartar', 'x', 'descartado')`, aparato.ID)

	// LO DECIDIDO NO SE REESCRIBE.
	if _, err := d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r1", AparatoID: aparato.ID, Clave: "c1"}); err != nil {
		t.Fatal(err)
	}
	if _, err := d.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{AparatoID: aparato.ID, Clave: "c1", Revisor: "r1"}); err != nil {
		t.Fatal(err)
	}
	if _, err := d.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", Motivo: "no era para hoy", AparatoID: aparato.ID, Clave: "c2"}); err != nil {
		t.Fatal(err)
	}
	for _, clave := range []string{"c1", "c2"} {
		for etiqueta, set := range map[string]string{
			"volver a en_revision": `estado = 'en_revision'`, "cambiar de decisión": `estado = 'rechazado', motivo = 'x'`,
			"cambiar quién decidió": `decidido_por = 'otro'`, "cambiar cuándo": `decidido_at = now() - interval '1 day'`,
			"cambiar el motivo": `motivo = 'otro motivo'`, "cambiar lo que creó": `id_creado = gen_random_uuid()`,
			"cambiar los intentos": `intentos = 9`,
		} {
			d.debeFallar(t, clave+": "+etiqueta, restrictViolation,
				fmt.Sprintf(`UPDATE revision_apuntes SET %s WHERE aparato_id = $1 AND clave = '%s'`, set, clave), aparato.ID)
		}
	}
}

// El CHECK del descarte sin motivo, y los demás: un descarte SIN motivo escrito no existe.
func TestMotorRealUnDescarteSinMotivoNoExiste(t *testing.T) {
	d := datosEnPostgresReal(t).(*datosEnTx)
	ctx := context.Background()
	aparato, _ := siembraDeUnaEntrega(t, d, "k1")

	descartar := func(set string) string {
		return fmt.Sprintf(`UPDATE revision_apuntes SET estado = 'descartado', %s WHERE aparato_id = $1 AND clave = 'k1'`, set)
	}
	const quien = `decidido_por = 'r1', decidido_at = now()`
	// El motivo: NULL (el que un CHECK sin `coalesce` dejaría pasar), vacío, de espacios y de menos de 5 letras.
	d.debeFallar(t, "descartar con motivo NULL", checkViolation, descartar(quien), aparato.ID)
	d.debeFallar(t, "descartar con motivo vacío", checkViolation, descartar(quien+`, motivo = ''`), aparato.ID)
	d.debeFallar(t, "descartar con motivo de espacios", checkViolation, descartar(quien+`, motivo = '        '`), aparato.ID)
	d.debeFallar(t, "descartar con 4 letras", checkViolation, descartar(quien+`, motivo = 'abcd'`), aparato.ID)
	d.debeFallar(t, "descartar con 4 letras y espacios", checkViolation, descartar(quien+`, motivo = '   abcd   '`), aparato.ID)
	// Sin quién ni cuándo, aunque haya motivo.
	d.debeFallar(t, "descartar sin quién", checkViolation, descartar(`decidido_at = now(), motivo = 'abcde'`), aparato.ID)
	d.debeFallar(t, "descartar sin cuándo", checkViolation, descartar(`decidido_por = 'r1', motivo = 'abcde'`), aparato.ID)
	d.debePasar(t, "descartar con 5 letras", descartar(quien+`, motivo = 'abcde'`), aparato.ID)

	// Por las consultas de verdad.
	for _, motivo := range []string{"abc", "     "} {
		// (en un savepoint: un CHECK que falla mata la transacción de la prueba si no)
		err := d.EnTransaccion(ctx, func(q sqlc.Querier) error {
			_, err := q.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", Motivo: motivo, AparatoID: aparato.ID, Clave: "k1"})
			return err
		})
		var pg *pgconn.PgError
		if !errors.As(err, &pg) || pg.Code != checkViolation {
			t.Errorf("DescartarRevisionApunte con el motivo %q tenía que fallar por el CHECK: %v", motivo, err)
		}
	}
	// Y que falló NO deja nada a medias: el apunte sigue esperando.
	if f, err := d.EstadoDeRevisionDeApunte(ctx, sqlc.EstadoDeRevisionDeApunteParams{AparatoID: aparato.ID, Clave: "k1"}); err != nil || f.Estado != sqlc.RevisionEstadoEnRevision {
		t.Errorf("tras los intentos fallidos el apunte tenía que seguir en revisión: %+v %v", f, err)
	}

	// Los otros CHECK de la tabla.
	d.debeFallar(t, "aplicado sin quién", checkViolation, `UPDATE revision_apuntes SET estado = 'aplicado' WHERE aparato_id = $1 AND clave = 'k1'`, aparato.ID)
	d.debeFallar(t, "aplicando sin dueño", checkViolation, `UPDATE revision_apuntes SET estado = 'aplicando' WHERE aparato_id = $1 AND clave = 'k1'`, aparato.ID)
	d.debeFallar(t, "rechazado sin motivo", checkViolation, `UPDATE revision_apuntes SET estado = 'rechazado' WHERE aparato_id = $1 AND clave = 'k1'`, aparato.ID)
	d.debeFallar(t, "rechazado con motivo vacío", checkViolation, `UPDATE revision_apuntes SET estado = 'rechazado', motivo = '  ' WHERE aparato_id = $1 AND clave = 'k1'`, aparato.ID)
	d.debeFallar(t, "huella que no es un sha256", checkViolation,
		`INSERT INTO revision_apuntes (aparato_id, clave, entrega_id, orden, metodo, ruta, hecho_at, huella)
		 SELECT aparato_id, 'huella-mala', entrega_id, 7, 'POST', '/routes', now(), 'XYZ' FROM revision_apuntes WHERE aparato_id = $1 AND clave = 'k1'`, aparato.ID)
	d.debeFallar(t, "un apunte de una entrega que no existe", foreignKey,
		`INSERT INTO revision_apuntes (aparato_id, clave, entrega_id, orden, metodo, ruta, hecho_at, huella)
		 VALUES ($1, 'huerfano', gen_random_uuid(), 0, 'POST', '/routes', now(), $2)`, aparato.ID, strings.Repeat("c", 64))
	d.debeFallar(t, "una decisión de un apunte que no existe", foreignKey,
		`INSERT INTO revision_decisiones (aparato_id, clave, accion, por, resultado) VALUES ($1, 'no-existe', 'aplicar', 'r', 'caida')`, aparato.ID)
	d.debeFallar(t, "una acción que no existe", checkViolation,
		`INSERT INTO revision_decisiones (aparato_id, clave, accion, por, resultado) VALUES ($1, 'k1', 'borrar', 'r', 'caida')`, aparato.ID)
}

// La idempotencia es del SQL (`ON CONFLICT DO NOTHING`): sin ella, entregar dos veces sería una violación de
// unicidad (un 500) o, peor, dos filas.
func TestMotorRealEntregarDosVecesEsUnaFilaYElOrdenEsElDeLlegada(t *testing.T) {
	d := datosEnPostgresReal(t).(*datosEnTx)
	ctx := context.Background()
	aparato, entrega := siembraDeUnaEntrega(t, d, "o1", "o2", "o3")
	cuerpo := `{"distinto": true}`
	_, err := d.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{
		AparatoID: aparato.ID, Clave: "o2", EntregaID: entrega.ID, Metodo: "PUT", Ruta: "/routes/otra", Cuerpo: &cuerpo,
		HechoAt: marca(time.Now()), Huella: strings.Repeat("f", 64)})
	if !store.SinFilas(err) {
		t.Fatalf("reinsertar la misma clave tenía que devolver «ninguna fila» (ON CONFLICT DO NOTHING) y devolvió %v", err)
	}
	f, _ := d.RevisionApunteDeRevisor(ctx, sqlc.RevisionApunteDeRevisorParams{AparatoID: aparato.ID, Clave: "o2"})
	if f.Metodo != "POST" || f.Huella != strings.Repeat("a", 64) || *f.Cuerpo != `{"a": 1}` {
		t.Errorf("el segundo insert SOBRESCRIBIÓ el original: %+v", f)
	}
	for i, c := range []string{"o1", "o2", "o3"} {
		if f, _ := d.EstadoDeRevisionDeApunte(ctx, sqlc.EstadoDeRevisionDeApunteParams{AparatoID: aparato.ID, Clave: c}); int(f.Orden) != i {
			t.Errorf("%s: orden %d, se esperaba %d", c, f.Orden, i)
		}
	}
	// La entrega de un mismo token es UNA: el ON CONFLICT de la entrega devuelve la que mandaba.
	otra, err := d.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{
		AparatoID: aparato.ID, Persona: aparato.Persona, BranchID: aparato.BranchID, TokenJti: entrega.TokenJti})
	if err != nil || otra.ID != entrega.ID {
		t.Errorf("el mismo token tenía que caer en la misma entrega: %v %v", otra.ID, err)
	}
}

// ---------------------------------------------------------------------------
// El doble y Postgres, el mismo guion
// ---------------------------------------------------------------------------

// guionDeLasConsultas corre una secuencia de las consultas del revisor y devuelve, paso a paso, lo que un
// llamador observa. EL MISMO guion se ejecuta contra el doble y contra Postgres, y tienen que contar lo
// mismo: es lo que mantiene honestos a los dobles de `dobles_revision_test.go`.
func guionDeLasConsultas(t *testing.T, d store.Datos) []string {
	t.Helper()
	ctx := context.Background()
	var s []string
	anota := func(formato string, a ...any) { s = append(s, fmt.Sprintf(formato, a...)) }
	cuerpo := func(f *string) string {
		if f == nil {
			return "-"
		}
		return *f
	}
	pers := func(f *string) string { return cuerpo(f) }
	sinFilas := func(err error) string {
		switch {
		case err == nil:
			return "ok"
		case store.SinFilas(err):
			return "sin filas"
		default:
			return "error"
		}
	}
	// Una consulta que puede fallar por un CHECK va en su propio savepoint.
	enSavepoint := func(fn func(q sqlc.Querier) error) error { return d.EnTransaccion(ctx, fn) }

	s1, s2 := uuid.New(), uuid.New()
	a1, _ := d.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: "autor", BranchID: s1})
	a2, _ := d.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: "otro-autor", BranchID: s2})
	nombre := "Marta"
	nuevo := func(a sqlc.Aparato, claves ...string) {
		e, err := d.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{AparatoID: a.ID, Persona: a.Persona, BranchID: a.BranchID, TokenJti: "j-" + a.Persona})
		if err != nil {
			t.Fatal(err)
		}
		for _, c := range claves {
			cu := `{"k":1}`
			if _, err := d.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{AparatoID: a.ID, Clave: c, EntregaID: e.ID,
				Metodo: "POST", Ruta: "/routes", Cuerpo: &cu, HechoAt: marca(time.Now()), Huella: strings.Repeat("a", 64)}); err != nil {
				t.Fatal(err)
			}
		}
	}
	nuevo(a1, "c1", "c2", "c3")
	nuevo(a2, "d1")
	vsuc := func(u uuid.UUID) pgtype.UUID { return identificador(u) }
	claves := func(filas []string) string { return strings.Join(filas, ",") }

	// RECLAMAR: el autor no, otra sucursal no, un revisor del alcance sí, y el segundo se queda sin él.
	_, err := d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "autor", AparatoID: a1.ID, Clave: "c1"})
	anota("reclamar siendo el autor: %s", sinFilas(err))
	_, err = d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r1", AparatoID: a1.ID, Clave: "c1", Sucursal: vsuc(s2)})
	anota("reclamar con el alcance de otra sucursal: %s", sinFilas(err))
	r, err := d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r1", RevisorNombre: &nombre, AparatoID: a1.ID, Clave: "c1", Sucursal: vsuc(s1)})
	anota("reclamar bien: %s %s por=%s nombre=%s decidido=%v cuerpo=%s", sinFilas(err), r.Estado, pers(r.DecididoPor), pers(r.DecididoPorNombre), r.DecididoAt.Valid, cuerpo(r.Cuerpo))
	_, err = d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r2", AparatoID: a1.ID, Clave: "c1"})
	anota("reclamar lo que ya se está aplicando: %s", sinFilas(err))
	_, err = d.ReclamarRevisionInterrumpida(ctx, sqlc.ReclamarRevisionInterrumpidaParams{Revisor: "r2", AparatoID: a1.ID, Clave: "c1", AntiguedadSegundos: 600})
	anota("reclamar como interrumpida lo que se acaba de reclamar: %s", sinFilas(err))

	// CERRAR: sólo quien lo reclamó.
	_, err = d.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{AparatoID: a1.ID, Clave: "c1", Revisor: "r2"})
	anota("cerrar sin ser el dueño: %s", sinFilas(err))
	_, err = d.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{AparatoID: a1.ID, Clave: "c3", Revisor: "r1"})
	anota("cerrar sin haber reclamado: %s", sinFilas(err))
	rr, err := d.CerrarRevisionComoRechazado(ctx, sqlc.CerrarRevisionComoRechazadoParams{AparatoID: a1.ID, Clave: "c1", Revisor: "r1", Motivo: "Ese pedido ya va en otra ruta."})
	anota("rechazar: %s %s motivo=%s intentos=%d", sinFilas(err), rr.Estado, cuerpo(rr.Motivo), rr.Intentos)
	r, err = d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r2", AparatoID: a1.ID, Clave: "c1"})
	anota("reintentar un rechazado: %s %s por=%s", sinFilas(err), r.Estado, pers(r.DecididoPor))
	rr, err = d.DevolverRevisionAEnRevision(ctx, sqlc.DevolverRevisionAEnRevisionParams{AparatoID: a1.ID, Clave: "c1", Revisor: "r2"})
	anota("devolver tras una caída: %s %s por=%s intentos=%d motivo=%s", sinFilas(err), rr.Estado, pers(rr.DecididoPor), rr.Intentos, cuerpo(rr.Motivo))

	// DESCARTAR: alcance, motivo (el CHECK) y una sola vez.
	_, err = d.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", Motivo: "no hacía falta", AparatoID: a1.ID, Clave: "c2", Sucursal: vsuc(s2)})
	anota("descartar con el alcance de otra sucursal: %s", sinFilas(err))
	_, err = d.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "autor", Motivo: "no hacía falta", AparatoID: a1.ID, Clave: "c2"})
	anota("descartar lo propio: %s", sinFilas(err))
	err = enSavepoint(func(q sqlc.Querier) error {
		_, err := q.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", Motivo: "abc", AparatoID: a1.ID, Clave: "c2"})
		return err
	})
	anota("descartar con 3 letras: %s", sinFilas(err))
	dd, err := d.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", RevisorNombre: &nombre, Motivo: "no hacía falta", AparatoID: a1.ID, Clave: "c2", Sucursal: vsuc(s1)})
	anota("descartar bien: %s %s por=%s motivo=%s", sinFilas(err), dd.Estado, pers(dd.DecididoPorNombre), cuerpo(dd.Motivo))
	_, err = d.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", Motivo: "no hacía falta", AparatoID: a1.ID, Clave: "c2"})
	anota("descartar lo ya descartado: %s", sinFilas(err))
	_, err = d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r1", AparatoID: a1.ID, Clave: "c2"})
	anota("reclamar lo descartado: %s", sinFilas(err))

	// APLICAR c3 de punta a punta.
	creada := uuid.MustParse("11111111-2222-4333-8444-555555555555")
	_, _ = d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r1", AparatoID: a1.ID, Clave: "c3"})
	ap, err := d.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{AparatoID: a1.ID, Clave: "c3", Revisor: "r1",
		IDCreado: identificador(creada), Descartados: json.RawMessage(`[1]`)})
	anota("aplicar: %s %s id=%v descartados=%s motivo=%s intentos=%d", sinFilas(err), ap.Estado, deIdentificador(ap.IDCreado), strings.ReplaceAll(string(ap.Descartados), " ", ""), cuerpo(ap.Motivo), ap.Intentos)

	// LECTURAS, con alcance.
	l, _ := d.ListarRevisionParaRevisor(ctx, sqlc.ListarRevisionParaRevisorParams{Sucursal: vsuc(s1), SoloVivos: true, Limite: 100})
	var ls []string
	for _, f := range l {
		ls = append(ls, f.Clave+":"+string(f.Estado))
	}
	anota("lista de S1, vivos: %s", claves(ls))
	l, _ = d.ListarRevisionParaRevisor(ctx, sqlc.ListarRevisionParaRevisorParams{SoloVivos: true, Limite: 100})
	ls = nil
	for _, f := range l {
		ls = append(ls, f.Clave)
	}
	anota("lista de todas, vivos: %s", claves(ls))
	l, _ = d.ListarRevisionParaRevisor(ctx, sqlc.ListarRevisionParaRevisorParams{Sucursal: vsuc(s1), Limite: 100})
	ls = nil
	for _, f := range l {
		ls = append(ls, f.Clave+":"+string(f.Estado))
	}
	anota("lista de S1, todo: %s", claves(ls))
	est := sqlc.RevisionEstadoDescartado
	l, _ = d.ListarRevisionParaRevisor(ctx, sqlc.ListarRevisionParaRevisorParams{Sucursal: vsuc(s1), Estado: &est, Limite: 100})
	ls = nil
	for _, f := range l {
		ls = append(ls, f.Clave)
	}
	anota("lista de S1, sólo descartados: %s", claves(ls))
	l, _ = d.ListarRevisionParaRevisor(ctx, sqlc.ListarRevisionParaRevisorParams{Limite: 2})
	anota("lista con tope 2: %d", len(l))

	_, err = d.RevisionApunteDeRevisor(ctx, sqlc.RevisionApunteDeRevisorParams{AparatoID: a1.ID, Clave: "c1", Sucursal: vsuc(s2)})
	anota("un apunte por id con el alcance de otra sucursal: %s", sinFilas(err))
	det, err := d.RevisionApunteDeRevisor(ctx, sqlc.RevisionApunteDeRevisorParams{AparatoID: a1.ID, Clave: "c1", Sucursal: vsuc(s1)})
	anota("un apunte por id: %s persona=%s suc=%v cuerpo=%s", sinFilas(err), det.Persona, det.BranchID == s1, cuerpo(det.Cuerpo))
	ent, _ := d.EstadoDeRevisionDeApunte(ctx, sqlc.EstadoDeRevisionDeApunteParams{AparatoID: a1.ID, Clave: "c1"})
	de, _ := d.RevisionDeEntrega(ctx, sqlc.RevisionDeEntregaParams{EntregaID: ent.EntregaID, Sucursal: vsuc(s1)})
	ls = nil
	for _, f := range de {
		ls = append(ls, f.Clave)
	}
	anota("la entrega, con su alcance: %s", claves(ls))
	de, _ = d.RevisionDeEntrega(ctx, sqlc.RevisionDeEntregaParams{EntregaID: ent.EntregaID, Sucursal: vsuc(s2)})
	anota("la entrega, con el alcance de otra: %d", len(de))

	cuenta, _ := d.RevisionSinDecidirPorSucursal(ctx, pgtype.UUID{})
	porSuc := map[uuid.UUID]int64{}
	for _, c := range cuenta {
		porSuc[c.BranchID] = c.EnRevision
	}
	anota("sin decidir: S1=%d S2=%d", porSuc[s1], porSuc[s2])
	cuenta, _ = d.RevisionSinDecidirPorSucursal(ctx, vsuc(s2))
	anota("sin decidir con el alcance de S2: %d filas", len(cuenta))
	cupo, _ := d.CupoDeRevision(ctx, sqlc.CupoDeRevisionParams{Persona: "autor", Sucursal: s1})
	anota("cupo: persona=%d bytes=%d sucursal=%d", cupo.DeLaPersona, cupo.BytesDeLaPersona, cupo.DeLaSucursal)
	mias, _ := d.RevisionDeAparato(ctx, sqlc.RevisionDeAparatoParams{AparatoID: a1.ID, Limite: 100})
	// Dentro de UNA transacción `now()` es siempre el mismo y `updated_at` empata; el doble sí avanza. Se compara
	// lo que no depende de eso: lo vivo va ANTES que lo decidido, y dentro de cada grupo por clave.
	var vivas, decididas []string
	for _, f := range mias {
		if f.Estado == sqlc.RevisionEstadoEnRevision || f.Estado == sqlc.RevisionEstadoAplicando || f.Estado == sqlc.RevisionEstadoRechazado {
			vivas = append(vivas, f.Clave+":"+string(f.Estado))
		} else {
			decididas = append(decididas, f.Clave+":"+string(f.Estado))
		}
	}
	sort.Strings(vivas)
	sort.Strings(decididas)
	anota("lo mío (vivo primero): %s | %s", claves(vivas), claves(decididas))
	primeraDecidida := -1
	for i, f := range mias {
		if f.Estado == sqlc.RevisionEstadoAplicado || f.Estado == sqlc.RevisionEstadoDescartado {
			primeraDecidida = i
			break
		}
	}
	for i, f := range mias {
		if i > primeraDecidida && primeraDecidida >= 0 && (f.Estado == sqlc.RevisionEstadoEnRevision || f.Estado == sqlc.RevisionEstadoAplicando || f.Estado == sqlc.RevisionEstadoRechazado) {
			t.Errorf("lo vivo tiene que ir ANTES que lo decidido: %v", mias)
		}
	}
	mias, _ = d.RevisionDeAparato(ctx, sqlc.RevisionDeAparatoParams{AparatoID: a1.ID, Limite: 1})
	anota("lo mío con tope 1: %d", len(mias))

	// EL LIBRO.
	_, err = d.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{AparatoID: a1.ID, Clave: "c1", Accion: "aplicar", Por: "r1", Resultado: "rechazado", Motivo: &nombre})
	anota("anotar una decisión: %s", sinFilas(err))
	_, _ = d.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{AparatoID: a1.ID, Clave: "c1", Accion: "aplicar", Por: "r2", Resultado: "caida"})
	libro, _ := d.RevisionDecisionesDeApunte(ctx, sqlc.RevisionDecisionesDeApunteParams{AparatoID: a1.ID, Clave: "c1"})
	ls = nil
	for _, f := range libro {
		ls = append(ls, f.Por+":"+f.Resultado)
	}
	anota("el libro, en orden: %s", claves(ls))
	return s
}

func TestMotorRealElDobleHaceLoMismoQuePostgres(t *testing.T) {
	real := guionDeLasConsultas(t, datosEnPostgresReal(t))
	doble := guionDeLasConsultas(t, nuevaBaseConRevision(nuevaBase()))
	if len(real) != len(doble) {
		t.Fatalf("el guion dio %d líneas en Postgres y %d en el doble", len(real), len(doble))
	}
	for i := range real {
		if real[i] != doble[i] {
			t.Errorf("EL DOBLE MIENTE en el paso %d:\n  Postgres: %s\n  doble:    %s", i, real[i], doble[i])
		}
	}
	if !reflect.DeepEqual(real, doble) {
		t.Log("las listas difieren")
	}
	if t.Failed() {
		t.Logf("todo el guion de Postgres:\n%s", strings.Join(real, "\n"))
	}
}
