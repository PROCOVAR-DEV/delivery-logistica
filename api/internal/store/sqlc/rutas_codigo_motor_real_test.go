package sqlc

// MOTOR REAL del ID Y EL CÓDIGO DE LAS RUTAS (migración 00031, 04/11/2026).
//
// Lo que sólo ve la base: el índice único que hace IMPOSIBLE repetir un código (el 03/11/2026 hubo tres `RT-20261103-004` en La Habana),
// que el valor por defecto de los ids nuevos sea UUIDv7, que `CrearRuta` respete el id que manda el aparato, y que `ExisteCodigoDeRuta`
// lea de verdad. Cada subprueba abre su transacción y la revierte (misma regla que las demás pruebas del motor real).

import (
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func (b *banco) rutaConCodigo(sucursal uuid.UUID, codigo string) error {
	_, err := b.tx.Exec(b.ctx, `INSERT INTO routes (branch_id, status, name, route_code) VALUES ($1, 'planned', 'r', $2)`, sucursal, codigo)
	return err
}

func TestMotorReal_CodigoDeRutaUnico(t *testing.T) {
	pool := motorReal(t)

	t.Run("dos_rutas_no_pueden_tener_el_mismo_codigo", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		if err := b.rutaConCodigo(suc, "7K2M9Q"); err != nil {
			t.Fatal(err)
		}
		// Un punto de guardado: el error de la base aborta la transacción, y aquí sólo se quiere ver QUÉ error es.
		b.exec(`SAVEPOINT antes`)
		err := b.rutaConCodigo(suc, "7K2M9Q")
		if err == nil || !strings.Contains(err.Error(), "routes_route_code_uniq") {
			t.Fatalf("la base tenía que rechazar el código repetido con su índice único, y dio: %v", err)
		}
		b.exec(`ROLLBACK TO SAVEPOINT antes`)
	})

	t.Run("rutas_sin_codigo_si_pueden_repetirse_y_las_sucursales_no_separan_el_codigo", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		a, c := b.sucursal(), b.sucursal()
		for i := 0; i < 2; i++ {
			b.exec(`INSERT INTO routes (branch_id, status, name) VALUES ($1, 'planned', 'sin codigo')`, a)
		}
		if err := b.rutaConCodigo(a, "AAAAAA"); err != nil {
			t.Fatal(err)
		}
		b.exec(`SAVEPOINT antes`)
		if err := b.rutaConCodigo(c, "AAAAAA"); err == nil {
			t.Fatalf("el código es único en TODA la casa, no por sucursal")
		}
		b.exec(`ROLLBACK TO SAVEPOINT antes`)
	})

	t.Run("el_id_por_defecto_de_una_ruta_es_un_uuid_v7", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		id := b.id(`INSERT INTO routes (branch_id, status, name, route_code) VALUES ($1, 'planned', 'r', 'V7V7V7') RETURNING id`, suc)
		if id.Version() != 7 {
			t.Fatalf("el id por defecto tiene que ser UUIDv7 y es v%d: %s", id.Version(), id)
		}
		// y las demás tablas con id propio (los ids nuevos son v7 en todas)
		for _, sql := range []string{
			`INSERT INTO customers (name, lat, lng) VALUES ('c', 0, 0) RETURNING id`,
			`INSERT INTO distribuidores (branch_id, nombre) VALUES ($1, 'd') RETURNING id`,
		} {
			args := []any{}
			if strings.Contains(sql, "$1") {
				args = append(args, suc)
			}
			if v := b.id(sql, args...); v.Version() != 7 {
				t.Fatalf("%q dio un id v%d", sql, v.Version())
			}
		}
	})

	t.Run("crear_ruta_respeta_el_id_del_aparato_y_sin_id_la_base_pone_uno_v7", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		propio, _ := uuid.NewV7()
		codigo := "AP4R4T"
		creada, err := b.q.CrearRuta(b.ctx, CrearRutaParams{
			ID: pgtype.UUID{Bytes: propio, Valid: true}, RouteCode: &codigo, OriginLat: f64(20), OriginLng: f64(-75),
			BranchID: pgtype.UUID{Bytes: suc, Valid: true},
		})
		if err != nil {
			t.Fatal(err)
		}
		if creada.ID != propio {
			t.Fatalf("el id que mandó el aparato manda: pidió %s y quedó %s", propio, creada.ID)
		}
		otro := "S1NID0"
		sinId, err := b.q.CrearRuta(b.ctx, CrearRutaParams{
			RouteCode: &otro, OriginLat: f64(20), OriginLng: f64(-75), BranchID: pgtype.UUID{Bytes: suc, Valid: true},
		})
		if err != nil {
			t.Fatal(err)
		}
		if sinId.ID.Version() != 7 {
			t.Fatalf("sin id del aparato, la base pone un UUIDv7 y puso v%d", sinId.ID.Version())
		}
	})

	t.Run("existe_codigo_de_ruta_lee_de_verdad", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		if err := b.rutaConCodigo(suc, "EX1ST4"); err != nil {
			t.Fatal(err)
		}
		if ya, err := b.q.ExisteCodigoDeRuta(b.ctx, "EX1ST4"); err != nil || !ya {
			t.Fatalf("existe y dijo %v (%v)", ya, err)
		}
		if ya, err := b.q.ExisteCodigoDeRuta(b.ctx, "N0EX1S"); err != nil || ya {
			t.Fatalf("no existe y dijo %v (%v)", ya, err)
		}
	})
}
