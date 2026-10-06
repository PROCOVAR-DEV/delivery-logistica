package sqlc

import (
	"context"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"os"
	"testing"
	"time"
)

// Test opcional de motor real. Se ejecuta en una base AISLADA: crea y borra
// su propio esquema. Nunca obtiene DSN de DATABASE_URL/producción.
func TestBloqueoRealDeRutaSerializaCompletarConResultados(t *testing.T) {
	dsn := os.Getenv("REPARTO_RUTAS_TEST_DSN")
	if dsn == "" {
		t.Skip("requiere PostgreSQL aislado REPARTO_RUTAS_TEST_DSN")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	a, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close(ctx)
	b, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close(ctx)
	schema := "auditoria_" + uuid.New().String()[:8]
	_, err = a.Exec(ctx, "CREATE SCHEMA "+schema+"; SET search_path TO "+schema+"; CREATE TABLE routes(id uuid PRIMARY KEY,status text NOT NULL,branch_id uuid)")
	if err != nil {
		t.Fatal(err)
	}
	defer a.Exec(context.Background(), "DROP SCHEMA "+schema+" CASCADE")
	if _, err = b.Exec(ctx, "SET search_path TO "+schema); err != nil {
		t.Fatal(err)
	}
	id := uuid.New()
	branch := uuid.New()
	if _, err = a.Exec(ctx, "INSERT INTO routes VALUES($1,'in_progress',$2)", id, branch); err != nil {
		t.Fatal(err)
	}
	param := BloquearRutaParams{ID: id, Sucursal: pgtype.UUID{Bytes: branch, Valid: true}}
	for _, completaPrimero := range []bool{false, true} {
		label := "marcar_antes_de_completar"
		if completaPrimero {
			label = "completar_antes_de_marcar"
		}
		t.Run(label, func(t *testing.T) {
			if _, err := a.Exec(ctx, "UPDATE routes SET status='in_progress'"); err != nil {
				t.Fatal(err)
			}
			primero, err := a.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer primero.Rollback(ctx)
			status, err := New(primero).BloquearRuta(ctx, param)
			if err != nil || status != RouteStatusInProgress {
				t.Fatalf("lock inicial %s %v", status, err)
			}
			if completaPrimero {
				if _, err := primero.Exec(ctx, "UPDATE routes SET status='completed'"); err != nil {
					t.Fatal(err)
				}
			}
			segundo, err := b.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer segundo.Rollback(ctx)
			type salida struct {
				status RouteStatus
				err    error
			}
			done := make(chan salida, 1)
			go func() { s, e := New(segundo).BloquearRuta(ctx, param); done <- salida{s, e} }()
			deadline := time.Now().Add(time.Second)
			blocked := false
			for time.Now().Before(deadline) {
				select {
				case s := <-done:
					t.Fatalf("la segunda operación entró antes de liberar la fila: %s %v; puede modificar el histórico", s.status, s.err)
				default:
				}
				var wait *string
				if err := a.QueryRow(ctx, "SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1", b.PgConn().PID()).Scan(&wait); err != nil {
					t.Fatal(err)
				}
				if wait != nil && *wait == "Lock" {
					blocked = true
					break
				}
				time.Sleep(5 * time.Millisecond)
			}
			if !blocked {
				t.Fatal("no se observó bloqueo real del segundo escritor")
			}
			if err := primero.Commit(ctx); err != nil {
				t.Fatal(err)
			}
			s := <-done
			if s.err != nil {
				t.Fatal(s.err)
			}
			expected := RouteStatusInProgress
			if completaPrimero {
				expected = RouteStatusCompleted
			}
			if s.status != expected {
				t.Fatalf("foto antigua después del bloqueo: %s, esperado%s", s.status, expected)
			}
			if _, err := New(segundo).BloquearRuta(ctx, BloquearRutaParams{ID: id, Sucursal: pgtype.UUID{Bytes: uuid.New(), Valid: true}}); err != pgx.ErrNoRows {
				t.Fatalf("el bloqueo amplió alcance: %v", err)
			}
		})
	}
}
