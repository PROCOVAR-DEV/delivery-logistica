package sqlc

// MOTOR REAL del CUADRE de facturas del aparato (28/10/2026): `IdsDePedidosParaElCuadre` contra Postgres de verdad.
// Lo que sólo ve la base: el `NOT archivado OR anulada reciente`, el alcance (sucursal ajena fuera) y el tope.

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func TestMotorReal_ElCuadreDeFacturas(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	stg, hol := b.sucursal(), b.sucursal()

	viva := b.pedido(listo("viva", stg))
	archivada := listo("archivada", stg)
	archivada.Archivado = true
	archivadaID := b.pedido(archivada)
	anulada := b.pedido(func() semilla { s := listo("anulada", stg); s.Archivado = true; return s }())
	b.exec(`UPDATE orders SET anulada_at = now() - interval '1 day', anulada_de_ruta_id = NULL WHERE id = $1`, anulada)
	vieja := b.pedido(func() semilla { s := listo("anulada-vieja", stg); s.Archivado = true; return s }())
	b.exec(`UPDATE orders SET anulada_at = now() - interval '30 days' WHERE id = $1`, vieja)
	ajena := b.pedido(listo("ajena", hol))

	desde := time.Now().Add(-VentanaAnuladasParaLaPrueba)
	ids := func(sucursal pgtype.UUID, tope int32) map[uuid.UUID]bool {
		t.Helper()
		filas, err := b.q.IdsDePedidosParaElCuadre(b.ctx, IdsDePedidosParaElCuadreParams{
			Sucursal: sucursal, AnuladasDesde: pgtype.Timestamptz{Time: desde, Valid: true}, Tope: tope,
		})
		if err != nil {
			t.Fatal(err)
		}
		m := map[uuid.UUID]bool{}
		for _, id := range filas {
			m[id] = true
		}
		return m
	}

	santiago := ids(alcance(stg), 100)
	if !santiago[viva] || !santiago[anulada] {
		t.Fatalf("faltan la viva o la anulada de ayer: %v", santiago)
	}
	if santiago[archivadaID] || santiago[vieja] || santiago[ajena] {
		t.Fatalf("sobran la archivada, la anulada de hace un mes o la de otra sucursal: %v", santiago)
	}
	if !ids(sinAlcance, 100)[ajena] {
		t.Fatal("quien ve «todas» tenía que ver también la de Holguín")
	}
	if n := len(ids(alcance(stg), 1)); n != 1 {
		t.Fatalf("el tope no se respeta: %d", n)
	}
}

// VentanaAnuladasParaLaPrueba: los 7 días de `alcance.VentanaDeFacturasAnuladas` (no se importa: sqlc no depende de alcance).
const VentanaAnuladasParaLaPrueba = 7 * 24 * time.Hour
