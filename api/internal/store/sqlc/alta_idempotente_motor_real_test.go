package sqlc

// MOTOR REAL: EL ALTA CON EL ID DEL APARATO (04/11/2026). El camión, el tipo de vehículo y el distribuidor nacen en el aparato con su
// UUIDv7 y el servidor lo respeta; y si el aparato manda dos veces el mismo alta (no supo si llegó la primera) se le devuelve lo que ya
// estaba, sin crear un segundo ni fallar. Esto solo lo ve la base: el `ON CONFLICT (id) DO NOTHING` y la rama que devuelve lo existente.

import (
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func TestMotorReal_AltaConElIdDelAparato(t *testing.T) {
	pool := motorReal(t)

	t.Run("tipo_de_vehiculo_respeta_el_id_y_el_reintento_devuelve_el_mismo", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := pgtype.UUID{Bytes: b.sucursal(), Valid: true}
		propio, _ := uuid.NewV7()
		arg := CrearTipoDeVehiculoParams{ID: pgtype.UUID{Bytes: propio, Valid: true}, Nombre: "Furgón", Activo: true, BranchID: suc}
		a, err := b.q.CrearTipoDeVehiculo(b.ctx, arg)
		if err != nil || a.ID != propio {
			t.Fatalf("id=%v err=%v: el id del aparato manda", a.ID, err)
		}
		otra, err := b.q.CrearTipoDeVehiculo(b.ctx, arg)
		if err != nil || otra.ID != propio {
			t.Fatalf("el reintento tiene que devolver el que ya estaba: id=%v err=%v", otra.ID, err)
		}
		if n := b.entero(`SELECT count(*) FROM vehicle_types WHERE id = $1`, propio); n != 1 {
			t.Fatalf("hay %d filas con ese id", n)
		}
		// otro sin id: lo pone la base, v7
		sin, err := b.q.CrearTipoDeVehiculo(b.ctx, CrearTipoDeVehiculoParams{Nombre: "Camión", Activo: true, BranchID: suc})
		if err != nil || sin.ID.Version() != 7 {
			t.Fatalf("sin id la base pone un v7: %v %v", sin.ID, err)
		}
	})

	t.Run("el_id_de_otra_sucursal_no_se_devuelve", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		mia := pgtype.UUID{Bytes: b.sucursal(), Valid: true}
		ajena := pgtype.UUID{Bytes: b.sucursal(), Valid: true}
		propio, _ := uuid.NewV7()
		if _, err := b.q.CrearDistribuidor(b.ctx, CrearDistribuidorParams{ID: pgtype.UUID{Bytes: propio, Valid: true}, BranchID: uuid.UUID(ajena.Bytes), Nombre: "Pedro", Activo: true}); err != nil {
			t.Fatal(err)
		}
		// mi sucursal manda ese mismo id: ni se crea (el id existe) ni se devuelve lo ajeno
		_, err := b.q.CrearDistribuidor(b.ctx, CrearDistribuidorParams{ID: pgtype.UUID{Bytes: propio, Valid: true}, BranchID: uuid.UUID(mia.Bytes), Nombre: "Pedro", Activo: true})
		if err == nil {
			t.Fatalf("con el id de un distribuidor de OTRA sucursal no podía devolver nada (sin filas)")
		}
	})

	t.Run("distribuidor_respeta_el_id_y_el_reintento_no_crea_dos", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		propio, _ := uuid.NewV7()
		arg := CrearDistribuidorParams{ID: pgtype.UUID{Bytes: propio, Valid: true}, BranchID: suc, Nombre: "Juan", Activo: true}
		a, err := b.q.CrearDistribuidor(b.ctx, arg)
		if err != nil || a.ID != propio {
			t.Fatalf("id=%v err=%v", a.ID, err)
		}
		if otra, err := b.q.CrearDistribuidor(b.ctx, arg); err != nil || otra.ID != propio {
			t.Fatalf("reintento: id=%v err=%v", otra.ID, err)
		}
		if n := b.entero(`SELECT count(*) FROM distribuidores WHERE branch_id = $1`, suc); n != 1 {
			t.Fatalf("hay %d distribuidores", n)
		}
	})

	t.Run("vehiculo_respeta_el_id_y_el_reintento_no_crea_dos", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := pgtype.UUID{Bytes: b.sucursal(), Valid: true}
		tipo := b.id(`INSERT INTO vehicle_types (nombre, branch_id) VALUES ('truck', $1) RETURNING id`, suc.Bytes)
		propio, _ := uuid.NewV7()
		arg := CrearVehiculoParams{ID: pgtype.UUID{Bytes: propio, Valid: true}, Name: "Camión 1", VehicleTypeID: tipo, Capacity: 1000, Status: VehicleStatusAvailable, IsActive: true, BranchID: suc}
		a, err := b.q.CrearVehiculo(b.ctx, arg)
		if err != nil || a.ID != propio {
			t.Fatalf("id=%v err=%v", a.ID, err)
		}
		if otra, err := b.q.CrearVehiculo(b.ctx, arg); err != nil || otra.ID != propio {
			t.Fatalf("reintento: id=%v err=%v", otra.ID, err)
		}
		if n := b.entero(`SELECT count(*) FROM vehicles WHERE branch_id = $1`, suc.Bytes); n != 1 {
			t.Fatalf("hay %d camiones", n)
		}
	})
}
