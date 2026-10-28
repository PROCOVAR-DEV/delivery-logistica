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

	ids := func(sucursal pgtype.UUID, tope int32) map[uuid.UUID]bool {
		t.Helper()
		filas, err := b.q.IdsDePedidosParaElCuadre(b.ctx, IdsDePedidosParaElCuadreParams{
			Sucursal: sucursal, Tope: tope,
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
	if !santiago[viva] {
		t.Fatalf("falta la viva: %v", santiago)
	}
	if santiago[archivadaID] || santiago[anulada] || santiago[vieja] || santiago[ajena] {
		t.Fatalf("sobran la archivada, las anuladas (bajan como aviso, no como fila) o la de otra sucursal: %v", santiago)
	}
	if !ids(sinAlcance, 100)[ajena] {
		t.Fatal("quien ve «todas» tenía que ver también la de Holguín")
	}
	if n := len(ids(alcance(stg), 1)); n != 1 {
		t.Fatalf("el tope no se respeta: %d", n)
	}
}

// EL CURSOR (hora, clave) DE LAS LÁPIDAS contra Postgres de verdad: un grupo con la MISMA hora se reparte en lotes sin
// perder ni repetir ninguna (28/10/2026). Lo que sólo ve la base: la comparación de tupla `(salio_at, clave) > (…)`.
func TestMotorReal_LasBajasPorLotesConCursor(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	misma := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	claves := map[string]bool{}
	for range 7 {
		c := uuid.NewString()
		claves[c] = true
		b.exec(`INSERT INTO bajas_de_la_bajada (coleccion, clave, branch_id, motivo, salio_at)
		        VALUES ('routes', $1, $2, 'borrado', $3)`, c, suc, misma)
	}
	visto := map[string]int{}
	var marca *pgtype.Timestamptz
	var clave *string
	for vuelta := 0; vuelta < 10; vuelta++ {
		p := BajasDeLaBajadaParams{
			Coleccion: ColeccionDeLaBajadaRoutes, Sucursal: alcance(suc),
			Desde: pgtype.Timestamptz{Time: misma.Add(-time.Hour), Valid: true}, Tope: 3,
		}
		if marca != nil {
			p.CursorMarca, p.CursorClave, p.Desde = *marca, clave, pgtype.Timestamptz{}
		}
		filas, err := b.q.BajasDeLaBajada(b.ctx, p)
		if err != nil {
			t.Fatal(err)
		}
		if len(filas) == 0 {
			break
		}
		for _, f := range filas {
			visto[f.Clave]++
		}
		ultima := filas[len(filas)-1]
		m, c := ultima.SalioAt, ultima.Clave
		marca, clave = &m, &c
	}
	if len(visto) != len(claves) {
		t.Fatalf("llegaron %d de %d: %v", len(visto), len(claves), visto)
	}
	for c := range claves {
		if visto[c] != 1 {
			t.Fatalf("la baja %s llegó %d veces", c, visto[c])
		}
	}
}
