package sqlc

// `FijarOrdenDeParada` (PUT /api/routes/{id}/stops, issue 11 de Amado) contra Postgres de
// verdad. El doble de `internal/api` repite su WHERE a mano; esto es lo que lo comprueba.
// Se salta sin REPARTO_MOTOR_REAL_DSN, como todas las de este fichero (ver
// `consultas_motor_real_test.go`), y revierte su transacción al terminar.

import (
	"testing"
)

func TestMotorReal_FijarOrdenDeParada(t *testing.T) {
	b := nuevoBanco(t, motorReal(t))
	suc, otra := b.sucursal(), b.sucursal()
	ruta := b.ruta(suc, RouteStatusInProgress)
	otraRuta := b.ruta(suc, RouteStatusPlanned)

	s := listo("cargada", suc)
	s.Ruta, s.UltimaRuta, s.StopOrder, s.SegmentKm = alcance(ruta), alcance(ruta), i32(1), f64(9)
	s.Resultado = str("devuelto") // una marca provisional de una ruta en curso: NO se toca
	cargada := b.pedido(s)
	ajena := listo("de otra ruta", suc)
	ajena.Ruta, ajena.StopOrder = alcance(otraRuta), i32(1)
	deOtraRuta := b.pedido(ajena)
	soltada := listo("soltada con resultado", suc)
	soltada.UltimaRuta, soltada.StopOrder, soltada.Resultado = alcance(ruta), i32(2), str("devuelto")
	devuelta := b.pedido(soltada)

	fijar := func(pedido, rutaID [16]byte, sucursal [16]byte, orden int32, km *float64) int64 {
		t.Helper()
		n, err := b.q.FijarOrdenDeParada(b.ctx, FijarOrdenDeParadaParams{
			StopOrder: i32(orden), SegmentKm: km, PedidoID: pedido, RutaID: alcance(rutaID), Sucursal: alcance(sucursal),
		})
		if err != nil {
			t.Fatalf("FijarOrdenDeParada: %v", err)
		}
		return n
	}
	leer := func(pedido [16]byte) (orden *int32, km *float64, resultado *string, precio *float64) {
		t.Helper()
		if err := b.tx.QueryRow(b.ctx,
			`SELECT stop_order, segment_km, resultado::text, price FROM orders WHERE id = $1`, pedido,
		).Scan(&orden, &km, &resultado, &precio); err != nil {
			t.Fatal(err)
		}
		return
	}

	_, _, _, precioAntes := leer(cargada)
	if n := fijar(cargada, ruta, suc, 3, f64(2.5)); n != 1 {
		t.Fatalf("la parada cargada en la ruta: %d filas, tenía que ser 1", n)
	}
	orden, km, resultado, precio := leer(cargada)
	if orden == nil || *orden != 3 || km == nil || *km != 2.5 {
		t.Fatalf("quedó stop_order=%v segment_km=%v; se pidió 3 y 2.5", orden, km)
	}
	if resultado == nil || *resultado != "devuelto" || (precio == nil) != (precioAntes == nil) {
		t.Fatalf("reordenar tocó lo que no es suyo: resultado=%v precio=%v (antes %v)", resultado, precio, precioAntes)
	}
	// Sin punto se escribe el HUECO: `narg` es NULL de verdad, no un cero.
	fijar(cargada, ruta, suc, 3, nil)
	if _, km, _, _ := leer(cargada); km != nil {
		t.Fatalf("segment_km nulo se escribió como %v y no como NULL", *km)
	}

	// Las tres que NO: otra ruta, otra sucursal y la que ya soltó su `route_id`.
	if n := fijar(deOtraRuta, ruta, suc, 1, f64(1)); n != 0 {
		t.Fatal("reordenó un pedido que va cargado en OTRA ruta")
	}
	if n := fijar(cargada, ruta, otra, 1, f64(1)); n != 0 {
		t.Fatal("reordenó con el alcance de otra sucursal")
	}
	if n := fijar(devuelta, ruta, suc, 1, f64(1)); n != 0 {
		t.Fatal("reordenó una parada que ya no va cargada (route_id NULL): el orden es de lo que lleva el camión")
	}
	if o, _, _, _ := leer(deOtraRuta); o == nil || *o != 1 {
		t.Fatalf("el pedido de otra ruta cambió de orden: %v", o)
	}
}
