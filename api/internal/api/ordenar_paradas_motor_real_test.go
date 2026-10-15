package api

// PUT /api/routes/{id}/stops CONTRA POSTGRES DE VERDAD: el manejador entero —bloqueo de la
// fila, alcance, `FijarOrdenDeParada`, `FijarTotalesDeRuta` y la relectura— sobre las
// consultas reales, en una transacción que se revierte. Se salta sin REPARTO_MOTOR_REAL_DSN.

import (
	"context"
	"io"
	"log/slog"
	"math"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

func TestMotorReal_ReordenarLasParadasDeUnaRuta(t *testing.T) {
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
		t.Fatalf("la base %q no parece aislada: no se toca", base)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(context.Background()) }()

	id := func(sql string, args ...any) uuid.UUID {
		t.Helper()
		var u uuid.UUID
		if err := tx.QueryRow(ctx, sql, args...).Scan(&u); err != nil {
			t.Fatalf("siembra %q: %v", sql, err)
		}
		return u
	}
	suc := id(`INSERT INTO branches (name, lat, lng) VALUES ($1, 0, 0) RETURNING id`, "suc-"+uuid.NewString())
	otra := id(`INSERT INTO branches (name, lat, lng) VALUES ($1, 0, 0) RETURNING id`, "suc-"+uuid.NewString())
	rutaEn := func(sucursal uuid.UUID, estado string) uuid.UUID {
		return id(`INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng, total_distance)
		           VALUES ($1, $2::text::route_status, 'ruta', 0, 0, 1) RETURNING id`, sucursal, estado)
	}
	parada := func(sucursal, ruta uuid.UUID, nombre string, lng float64, orden int) uuid.UUID {
		return id(`INSERT INTO orders (customer_name, operation_number, address, weight, branch_id,
		             end_lat, end_lng, route_id, ultima_ruta_id, stop_order)
		           VALUES ($1, $2, 'calle', 1, $3, 0, $4, $5, $5, $6) RETURNING id`,
			nombre, "OP-"+nombre, sucursal, lng, ruta, orden)
	}
	ruta := rutaEn(suc, "in_progress")
	lejos := parada(suc, ruta, "Lejos", 0.30, 1)
	cerca := parada(suc, ruta, "Cerca", 0.05, 2)
	medio := parada(suc, ruta, "Medio", 0.15, 3)
	completada := rutaEn(suc, "completed")
	parada(suc, completada, "Histórica", 0.10, 1)
	ajena := rutaEn(otra, "planned")
	deOtra := parada(otra, ajena, "Ajena", 0.10, 1)

	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatal(err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDeMotorReal{q: sqlc.New(tx)}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	s := NuevoServidor(cfg, reg, porteria, verif, nil)
	rt := httpx.NuevoRouter(httpx.ConRegistro(reg), httpx.SinCache)
	s.rutasDeReparto(rt, []httpx.Medio{verif.Exigir, porteria.Exigir}, nil)
	h := rt.Handler()
	jwt := tokenDeRutas(t, map[string]any{"sub": "p-mr", "role": "LOGISTICO", "branchId": suc.String()})

	leer := func() (orden map[uuid.UUID]int32, km map[uuid.UUID]float64, total float64, optimizada bool) {
		t.Helper()
		orden, km = map[uuid.UUID]int32{}, map[uuid.UUID]float64{}
		filas, err := tx.Query(ctx, `SELECT id, stop_order, segment_km FROM orders WHERE route_id = $1`, ruta)
		if err != nil {
			t.Fatal(err)
		}
		for filas.Next() {
			var pid uuid.UUID
			var o int32
			var k *float64
			if err := filas.Scan(&pid, &o, &k); err != nil {
				t.Fatal(err)
			}
			orden[pid] = o
			if k != nil {
				km[pid] = *k
			}
		}
		if err := tx.QueryRow(ctx, `SELECT total_distance, optimized FROM routes WHERE id = $1`, ruta).Scan(&total, &optimizada); err != nil {
			t.Fatal(err)
		}
		return
	}
	pedir := func(rutaID uuid.UUID, cuerpo string) int {
		t.Helper()
		return llamarRutas(t, h, http.MethodPut, "/api/routes/"+rutaID.String()+"/stops", jwt, cuerpo).Code
	}

	// A MANO, en una ruta EN CURSO.
	if c := pedir(ruta, cuerpoDeOrden(cerca, lejos, medio)); c != http.StatusOK {
		t.Fatalf("reordenar a mano contestó %d", c)
	}
	orden, km, total, optimizada := leer()
	if orden[cerca] != 1 || orden[lejos] != 2 || orden[medio] != 3 {
		t.Fatalf("orden guardado %v; se pidió cerca, lejos, medio", orden)
	}
	esperado := kmHaversine(0, 0, 0, 0.05) + kmHaversine(0, 0.05, 0, 0.30) + kmHaversine(0, 0.30, 0, 0.15) + kmHaversine(0, 0.15, 0, 0)
	if math.Abs(total-esperado) > 1e-6 || optimizada {
		t.Fatalf("total_distance %.6f (esperado %.6f) y optimized %v (esperado false)", total, esperado, optimizada)
	}
	if math.Abs(km[lejos]-kmHaversine(0, 0, 0, 0.30)) > 1e-9 {
		t.Fatalf("segment_km de Lejos = %v, tenía que ser la recta desde el origen", km[lejos])
	}

	// POR CERCANÍA.
	if c := pedir(ruta, `{"porCercania":true}`); c != http.StatusOK {
		t.Fatalf("por cercanía contestó %d", c)
	}
	orden, _, total, optimizada = leer()
	if orden[cerca] != 1 || orden[medio] != 2 || orden[lejos] != 3 || !optimizada {
		t.Fatalf("por cercanía quedó %v, optimized %v", orden, optimizada)
	}
	if math.Abs(total-2*kmHaversine(0, 0, 0, 0.30)) > 1e-6 {
		t.Fatalf("por cercanía total_distance %.6f", total)
	}

	// LOS QUE NO: completada (409), otra sucursal (404), lista incompleta (409). Nada se mueve.
	if c := pedir(completada, `{"porCercania":true}`); c != http.StatusConflict {
		t.Fatalf("una ruta completada contestó %d y tenía que ser 409", c)
	}
	if c := pedir(ajena, cuerpoDeOrden(deOtra)); c != http.StatusNotFound {
		t.Fatalf("la ruta de otra sucursal contestó %d y tenía que ser 404", c)
	}
	if c := pedir(ruta, cuerpoDeOrden(lejos, cerca)); c != http.StatusConflict {
		t.Fatalf("una lista incompleta contestó %d y tenía que ser 409", c)
	}
	if o, _, _, _ := leer(); o[cerca] != 1 || o[medio] != 2 || o[lejos] != 3 {
		t.Fatalf("un rechazo movió el orden: %v", o)
	}
}
