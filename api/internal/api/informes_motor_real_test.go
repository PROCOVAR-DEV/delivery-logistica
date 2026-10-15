package api

// GET /api/reports CONTRA UN POSTGRES DE VERDAD — la columna de facturas (issue 9 de Amado).
//
// Los dobles de `internal/api` reimplementan el SQL y NO lo ven (`CLAUDE.md` §5): que
// `ListarPedidosParaInforme` saque de verdad `operation_number` y `factura_numero` de las
// columnas, en el orden del más nuevo al más viejo, lo dice sólo la base. Esta prueba
// siembra EL MISMO informe que `docs/numero-de-factura.casos.json` (el que también siembra
// la prueba de Dart en la base local del aparato) y exige lo mismo que el doble y que el
// aparato.
//
// SÓLO SI SE PIDE, y sólo en una base aislada:
//
//	REPARTO_MOTOR_REAL_DSN='postgres://verif:verif@127.0.0.1:5433/verif_inf?sslmode=disable' \
//	  go test -count=1 -run MotorReal ./internal/api/ -v
//
// Sin la variable se salta (y `./comprobar.sh` lo dice a gritos). Se niega a correr si la
// base no se llama `verif…`, `…test…` o `…prueba…`, y nunca lee `DATABASE_URL`. Todo va
// dentro de UNA transacción que se revierte: la base queda como estaba.

import (
	"context"
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

// fuenteDeMotorReal da a la portería las consultas REALES de una transacción.
type fuenteDeMotorReal struct{ q sqlc.Querier }

func (f fuenteDeMotorReal) Consultas() sqlc.Querier { return f.q }
func (f fuenteDeMotorReal) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

func TestMotorReal_InformeLlevaLasFacturasDelFicheroCompartido(t *testing.T) {
	dsn := os.Getenv("REPARTO_MOTOR_REAL_DSN")
	if dsn == "" {
		t.Skip("requiere PostgreSQL aislado REPARTO_MOTOR_REAL_DSN")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	var base string
	if err := pool.QueryRow(ctx, "SELECT current_database()").Scan(&base); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(base, "verif") && !strings.Contains(base, "test") && !strings.Contains(base, "prueba") {
		t.Fatalf("la base %q no parece aislada (debe llamarse verif…, …test… o …prueba…): no se toca", base)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(context.Background()) }()

	caso := leerCasosDeFactura(t).Informe

	// La siembra: una sucursal, un camión, una ruta con ese camión y los pedidos del caso,
	// con `created_at` descendente (el primero del fichero es el más nuevo).
	id := func(sql string, args ...any) uuid.UUID {
		t.Helper()
		var u uuid.UUID
		if err := tx.QueryRow(ctx, sql, args...).Scan(&u); err != nil {
			t.Fatalf("siembra %q: %v", sql, err)
		}
		return u
	}
	sucursal := id(`INSERT INTO branches (name, lat, lng) VALUES ($1, 0, 0) RETURNING id`, "suc-"+uuid.NewString())
	tipo := id(`INSERT INTO vehicle_types (nombre) VALUES ($1) RETURNING id`, "tipo-"+uuid.NewString())
	camion := id(`INSERT INTO vehicles (name, vehicle_type_id, branch_id) VALUES ($1, $2, $3) RETURNING id`,
		caso.Camion, tipo, sucursal)
	ruta := id(`INSERT INTO routes (branch_id, status, name, vehicle_id) VALUES ($1, 'planned'::text::route_status, 'ruta', $2) RETURNING id`,
		sucursal, camion)
	ahora := time.Date(2026, 9, 13, 12, 0, 0, 0, time.UTC)
	for i, p := range caso.Pedidos {
		if _, err := tx.Exec(ctx, `
INSERT INTO orders (customer_name, address, weight, branch_id, route_id, price, pedido_costo,
                    operation_number, factura_numero, created_at)
VALUES ($1, 'calle 1', 10, $2, $3, $4, $4, $5, $6, $7)`,
			p.Cliente, sucursal, ruta, p.Ingreso, p.OperationNumber, p.FacturaNumero,
			ahora.Add(-time.Duration(i)*time.Hour)); err != nil {
			t.Fatalf("siembra del pedido %s: %v", p.Cliente, err)
		}
	}

	// El servidor, con las consultas REALES de la transacción. SUPER ADMIN ve todas las
	// sucursales; la sembrada es la única que hay en la base de pruebas.
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDePanel)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDeMotorReal{q: sqlc.New(tx)}, reg)
	s := NuevoServidor(cfg, reg, porteria, auth.NuevoVerificador([]byte(secretoDePanel)), nil)
	rt := httpx.NuevoRouter(httpx.ConRegistro(reg), httpx.SinCache)
	s.rutasInformes(rt, []httpx.Medio{s.verif.Exigir, porteria.Exigir}, nil)

	w := pedirDePanel(t, rt.Handler(), "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	compararInformeConElDeCaso(t, leerJSONDePanel[InformeSalida](t, w), caso)

	// Y la consulta, sola, saca las dos columnas CRUDAS: lo que se decide con ellas es cosa de
	// `numeroDeFactura`, no del SQL (la regla está escrita dos veces y no tres).
	filas, err := sqlc.New(tx).ListarPedidosParaInforme(ctx, sqlc.ListarPedidosParaInformeParams{})
	if err != nil && err != pgx.ErrNoRows {
		t.Fatal(err)
	}
	crudas := map[string][2]string{}
	for _, f := range filas {
		var op, fac string
		if f.OperationNumber != nil {
			op = *f.OperationNumber
		}
		if f.FacturaNumero != nil {
			fac = *f.FacturaNumero
		}
		crudas[f.CustomerName] = [2]string{op, fac}
	}
	if got := crudas["Cliente a"]; got != [2]string{"PTB25-261005-1479", "1024237"} {
		t.Errorf("la consulta tiene que sacar operation_number Y factura_numero tal cual; "+
			"del pedido a salió %q", got)
	}
	// Con la comilla de Excel puesta: limpiarla es cosa de `numeroDeFactura`, no del SQL. Si la
	// consulta la limpiara, la regla estaría escrita tres veces.
	if got := crudas["Cliente b"]; got[1] != "'1024240" {
		t.Errorf("la consulta tiene que sacar factura_numero tal cual, con su comilla; del pedido b "+
			"salió %q", got[1])
	}
}
