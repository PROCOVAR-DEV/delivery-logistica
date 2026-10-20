package api

// PUT y DELETE /api/orders/{id}/punto CONTRA POSTGRES DE VERDAD: el manejador entero —alcance,
// bloqueo de la ruta, `PonerPuntoDeEntregaAMano`, `FijarTotalesDeRuta` y la relectura— sobre las
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
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

func TestMotorReal_ElPuntoDeEntregaAMano(t *testing.T) {
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
	suc := id(`INSERT INTO branches (name, lat, lng, external_id, origin_configured)
	           VALUES ('Santiago', 19, -74, 'STG', true) RETURNING id`)
	otra := id(`INSERT INTO branches (name, lat, lng, external_id, origin_configured)
	            VALUES ('Holguín', 20.9, -76.2, 'HOL', true) RETURNING id`)
	rutaEn := func(estado string) uuid.UUID {
		return id(`INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng, total_distance, optimized)
		           VALUES ($1, $2::text::route_status, 'ruta', 20.0, -75.8, 1, false) RETURNING id`, suc, estado)
	}
	parada := func(ruta uuid.UUID, nombre string, lat, lng float64, orden int, almacen string) uuid.UUID {
		return id(`INSERT INTO orders (customer_name, operation_number, address, weight, branch_id,
		             end_lat, end_lng, lat, lng, route_id, ultima_ruta_id, stop_order, segment_km,
		             delivery_distance_km, almacen_salida_codigo, end_address)
		           VALUES ($1, $2, 'calle', 1, $3, $4, $5, $4, $5, $6, $6, $7, 99, 77, $8, 'Calle del cliente')
		           RETURNING id`, nombre, "OP-"+nombre, suc, lat, lng, ruta, orden, almacen)
	}
	ruta := rutaEn("planned")
	uno := parada(ruta, "Uno", 20.20, -75.60, 1, "2")
	dos := parada(ruta, "Dos", 20.05, -75.75, 2, "2")
	tres := parada(ruta, "Tres", 20.10, -75.70, 3, "2")
	completada := rutaEn("completed")
	historica := parada(completada, "Historica", 20.30, -75.50, 1, "2")
	suelto := id(`INSERT INTO orders (customer_name, address, weight, branch_id, end_lat, end_lng, lat, lng, almacen_salida_codigo)
	              VALUES ('Suelto', 'calle', 1, $1, 20.02, -75.82, 20.02, -75.82, '1') RETURNING id`, suc)
	ajeno := id(`INSERT INTO orders (customer_name, address, weight, branch_id, end_lat, end_lng)
	             VALUES ('Ajeno', 'calle', 1, $1, 20.5, -76.0) RETURNING id`, otra)

	conAccesos(t, &accesosFalso{sucursales: almacenesDeSantiagoDeAccesos()})
	avisos := contarAvisos(t)

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
	s.rutasPedidos(rt, []httpx.Medio{verif.Exigir, porteria.Exigir}, nil)
	h := rt.Handler()
	jwt := tokenDeRutas(t, map[string]any{"sub": "p-mr", "role": "LOGISTICO", "branchId": suc.String()})
	llamar := func(metodo string, pedido uuid.UUID, cuerpo string) *struct {
		code int
		body string
	} {
		w := llamarRutas(t, h, metodo, "/api/orders/"+pedido.String()+"/punto", jwt, cuerpo)
		return &struct {
			code int
			body string
		}{w.Code, w.Body.String()}
	}

	type foto struct {
		endLat, endLng float64
		segmentoV, kmV float64
		segmento, km   *float64
		orden          int32
		manual         bool
	}
	leer := func(pedido uuid.UUID) (f foto) {
		t.Helper()
		if err := tx.QueryRow(ctx, `SELECT end_lat, end_lng, segment_km, delivery_distance_km, coalesce(stop_order, 0), punto_manual
		                            FROM orders WHERE id = $1`, pedido).Scan(&f.endLat, &f.endLng, &f.segmento, &f.km, &f.orden, &f.manual); err != nil {
			t.Fatal(err)
		}
		if f.segmento != nil {
			f.segmentoV = *f.segmento
		}
		if f.km != nil {
			f.kmV = *f.km
		}
		f.segmento, f.km = nil, nil // lo comparable es el valor, no el puntero
		return
	}
	total := func(r uuid.UUID) (km float64, optimizada bool) {
		t.Helper()
		if err := tx.QueryRow(ctx, `SELECT total_distance, optimized FROM routes WHERE id = $1`, r).Scan(&km, &optimizada); err != nil {
			t.Fatal(err)
		}
		return
	}

	// --- PUT en una parada de una ruta planificada -----------------------------------------
	if r := llamar(http.MethodPut, dos, cuerpoDelPunto(latNuevo, lngNuevo, "Calle del logístico")); r.code != http.StatusOK {
		t.Fatalf("PUT contestó %d: %s", r.code, r.body)
	}
	f := leer(dos)
	if !f.manual || f.endLat != latNuevo || f.endLng != lngNuevo {
		t.Fatalf("el punto no quedó: %+v", f)
	}
	if want := kmHaversine(20.0, -75.8, latNuevo, lngNuevo); math.Abs(f.segmentoV-want) > 1e-9 {
		t.Fatalf("segment_km = %v; la recta del origen al punto son %v (antes valía 99)", f.segmentoV, want)
	}
	if want := cotizar.DistanciaHaversineKm(latAURORA, lngAURORA, latNuevo, lngNuevo); math.Abs(f.kmV-want) > 1e-9 {
		t.Fatalf("delivery_distance_km = %v; desde AURORA, el almacén del pedido, son %v (antes 77)", f.kmV, want)
	}
	p := [][2]float64{{20.20, -75.60}, {latNuevo, lngNuevo}, {20.10, -75.70}}
	esperado := kmHaversine(20.0, -75.8, p[0][0], p[0][1]) + kmHaversine(p[0][0], p[0][1], p[1][0], p[1][1]) +
		kmHaversine(p[1][0], p[1][1], p[2][0], p[2][1]) + kmHaversine(p[2][0], p[2][1], 20.0, -75.8)
	if km, opt := total(ruta); math.Abs(km-esperado) > 1e-6 || opt {
		t.Fatalf("total_distance = %.6f (esperado %.6f), optimized = %v (esperado false)", km, esperado, opt)
	}
	for pedido, orden := range map[uuid.UUID]int32{uno: 1, dos: 2, tres: 3} {
		if got := leer(pedido).orden; got != orden {
			t.Fatalf("el stop_order de la parada %d pasó a %d: no se toca", orden, got)
		}
	}
	if k := leer(uno).segmentoV; k != 99 {
		t.Fatalf("otra parada cambió su segment_km: %v", k)
	}
	avisos.exige(t, "el PUT en una ruta", CambioPedidos, CambioTablero, CambioRutas)

	// --- Lo que se rechaza, con la fila intacta ------------------------------------------
	antes := leer(historica)
	kmAntes, _ := total(completada)
	if r := llamar(http.MethodPut, historica, cuerpoDelPunto(latNuevo, lngNuevo, "")); r.code != http.StatusConflict {
		t.Fatalf("una ruta completada contestó %d (%s) y tenía que ser 409", r.code, r.body)
	}
	if d := leer(historica); d != antes {
		t.Fatalf("el 409 de la ruta completada tocó la fila: %+v -> %+v", antes, d)
	}
	if k, _ := total(completada); k != kmAntes {
		t.Fatal("el 409 de la ruta completada tocó su total")
	}
	if r := llamar(http.MethodPut, ajeno, cuerpoDelPunto(latNuevo, lngNuevo, "")); r.code != http.StatusNotFound {
		t.Fatalf("un pedido de otra sucursal contestó %d y tenía que ser 404", r.code)
	}
	if leer(ajeno).manual {
		t.Fatal("el pedido de otra sucursal se marcó")
	}
	tx.Exec(ctx, `UPDATE orders SET delivered_at = now(), resultado = 'entregado' WHERE id = $1`, tres)
	if r := llamar(http.MethodPut, tres, cuerpoDelPunto(latNuevo, lngNuevo, "")); r.code != http.StatusConflict ||
		!strings.Contains(r.body, "ya está entregado") {
		t.Fatalf("un entregado contestó %d %s", r.code, r.body)
	}
	if leer(tres).manual {
		t.Fatal("un entregado se marcó")
	}
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})
	antesSuelto := leer(suelto)
	if r := llamar(http.MethodPut, suelto, cuerpoDelPunto(latNuevo, lngNuevo, "x")); r.code != http.StatusBadGateway {
		t.Fatalf("con Accesos caído contestó %d y tenía que ser 502", r.code)
	}
	if leer(suelto) != antesSuelto {
		t.Fatal("con Accesos caído SE ESCRIBIÓ algo")
	}
	conAccesos(t, &accesosFalso{sucursales: almacenesDeSantiagoDeAccesos()})

	// --- Un pedido suelto se mide desde SU almacén ("1", el principal) y no tiene segmento ------
	if r := llamar(http.MethodPut, suelto, cuerpoDelPunto(latNuevo, lngNuevo, "")); r.code != http.StatusOK {
		t.Fatalf("PUT del suelto: %d %s", r.code, r.body)
	}
	if want := cotizar.DistanciaHaversineKm(latPVSTGO, lngPVSTGO, latNuevo, lngNuevo); math.Abs(leer(suelto).kmV-want) > 1e-9 {
		t.Fatalf("el suelto es del almacén 1 (PV-STGO): %v, esperado %v", leer(suelto).kmV, want)
	}
	if leer(suelto).segmentoV != 0 {
		t.Fatal("un pedido suelto no tiene segment_km")
	}

	// --- DELETE: vuelve al del cliente y la ruta se recalcula otra vez ---------------------
	if r := llamar(http.MethodDelete, dos, ""); r.code != http.StatusOK {
		t.Fatalf("DELETE contestó %d: %s", r.code, r.body)
	}
	f = leer(dos)
	if f.manual || f.endLat != 20.05 || f.endLng != -75.75 {
		t.Fatalf("no volvió al punto del cliente: %+v", f)
	}
	p[1] = [2]float64{20.05, -75.75}
	esperado = kmHaversine(20.0, -75.8, p[0][0], p[0][1]) + kmHaversine(p[0][0], p[0][1], p[1][0], p[1][1]) +
		kmHaversine(p[1][0], p[1][1], p[2][0], p[2][1]) + kmHaversine(p[2][0], p[2][1], 20.0, -75.8)
	if km, _ := total(ruta); math.Abs(km-esperado) > 1e-6 {
		t.Fatalf("tras el DELETE total_distance = %.6f, esperado %.6f", km, esperado)
	}
	if r := llamar(http.MethodDelete, dos, ""); r.code != http.StatusConflict {
		t.Fatalf("devolver dos veces: el segundo contestó %d y tenía que ser 409", r.code)
	}
}
