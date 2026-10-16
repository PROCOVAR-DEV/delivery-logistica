package sqlc

// MOTOR REAL de LOS TIPOS DE VEHÍCULO EN LA BAJADA (issue 14 de Amado, migración 00021).
//
// Los dobles de `internal/api` reimplementan el SQL en Go y NO ven el disparador ni los filtros: aquí
// corre el `Queries` que genera sqlc contra Postgres de verdad (`REPARTO_MOTOR_REAL_DSN` hacia una base
// `verif…` migrada hasta la 00021; mismo molde que `distribuidores_motor_real_test.go`: cada subprueba
// abre SU transacción y la revierte).
//
// Lo que sólo ve la base: la lápida que pone `trg_vehicle_types_baja` (con su sucursal, y NULA para un
// tipo «de todas»), que retirar o un borrado que no se hizo NO dejan lápida, el alcance de la propia
// lápida (`BajasDeLaBajada` con y sin `sin_sucursal_tambien`), la lista que se sirve (activos y retirados,
// el filtro `IS NOT DISTINCT FROM`), y la migración (Up/Down).

import (
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func (b *banco) lapidasDeTipos(alcanceDe pgtype.UUID, sinSucursalTambien bool) map[string]BajasDeLaBajadaRow {
	b.t.Helper()
	filas, err := b.q.BajasDeLaBajada(b.ctx, BajasDeLaBajadaParams{
		Coleccion: ColeccionDeLaBajadaVehicleTypes, Sucursal: alcanceDe,
		SinSucursalTambien: sinSucursalTambien, Tope: 100,
	})
	if err != nil {
		b.t.Fatal(err)
	}
	m := map[string]BajasDeLaBajadaRow{}
	for _, f := range filas {
		m[f.Clave] = f
	}
	return m
}

func TestMotorReal_TiposDeVehiculoEnLaBajada(t *testing.T) {
	pool := motorReal(t)

	t.Run("borrar_un_tipo_de_sucursal_deja_su_lapida_para_esa_sucursal_y_no_para_otra", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		stg, hol := b.sucursal(), b.sucursal()
		tipo := b.tipoDe(alcance(stg), "borrable-"+uuid.NewString()[:8])
		// Por la consulta de la API, no a mano: lo que dispara la lápida es el DELETE de verdad.
		if _, err := b.q.BorrarTipoDeVehiculoSinUso(b.ctx, BorrarTipoDeVehiculoSinUsoParams{ID: tipo, Sucursal: alcance(stg)}); err != nil {
			t.Fatal(err)
		}
		l, hay := b.lapidasDeTipos(alcance(stg), false)[tipo.String()]
		if !hay || l.Motivo != MotivoDeBajaBorrado || l.BranchID != alcance(stg) {
			t.Fatalf("Santiago tenía que recibir la baja del tipo, con su sucursal y 'borrado': %+v", l)
		}
		if _, hay := b.lapidasDeTipos(alcance(hol), false)[tipo.String()]; hay {
			t.Fatal("a Holguín le llegó la baja de un tipo de Santiago")
		}
		// Quien ve «todas» (alcance nulo) la recibe: es un borrado.
		if _, hay := b.lapidasDeTipos(sinAlcance, false)[tipo.String()]; !hay {
			t.Fatal("quien ve «todas» no recibió la baja")
		}
	})

	t.Run("un_tipo_de_todas_deja_lapida_con_sucursal_nula_que_solo_recibe_quien_ve_todas", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		stg := b.sucursal()
		deTodas := b.tipoDe(sinAlcance, "de-todas-"+uuid.NewString()[:8])
		b.exec(`DELETE FROM vehicle_types WHERE id = $1`, deTodas)
		// La lápida existe, con la sucursal NULA (el disparador trata el nulo: `NULL::uuid`).
		if got := b.entero(`SELECT count(*) FROM bajas_de_la_bajada WHERE coleccion::text = 'vehicle_types' AND clave = $1::text AND branch_id IS NULL AND motivo = 'borrado'`, deTodas); got != 1 {
			t.Fatalf("el DELETE de un tipo «de todas» tenía que dejar UNA lápida con sucursal nula: %d", got)
		}
		// `sinSucursalTambien = false` es lo que usa la bajada para esta colección: a Santiago NO.
		if _, hay := b.lapidasDeTipos(alcance(stg), false)[deTodas.String()]; hay {
			t.Fatal("a Santiago le llegó la baja de un tipo «de todas», que su lista nunca incluyó")
		}
		// Y la pareja: quien ve «todas» (su lista SON los «de todas») sí.
		if _, hay := b.lapidasDeTipos(sinAlcance, false)[deTodas.String()]; !hay {
			t.Fatal("quien ve «todas» no recibió la baja del tipo «de todas»")
		}
	})

	t.Run("retirar_o_no_poder_borrar_no_dejan_lapida", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		stg := b.sucursal()
		usado := b.tipoDe(alcance(stg), "usado-"+uuid.NewString()[:8])
		b.camionConTipo(alcance(stg), usado)
		// Lo usa un camión: la sentencia no borra nada (cero filas) y NO hay lápida.
		if _, err := b.q.BorrarTipoDeVehiculoSinUso(b.ctx, BorrarTipoDeVehiculoSinUsoParams{ID: usado, Sucursal: alcance(stg)}); err != pgx.ErrNoRows {
			t.Fatalf("un tipo en uso no se borra: %v", err)
		}
		// Retirarlo es un UPDATE, no un borrado.
		b.exec(`UPDATE vehicle_types SET activo = false WHERE id = $1`, usado)
		if _, hay := b.lapidasDeTipos(alcance(stg), false)[usado.String()]; hay {
			t.Fatal("retirar un tipo dejó una lápida: el aparato lo borraría en vez de esconderlo")
		}
		if !b.tipoExiste(usado) {
			t.Fatal("el tipo desapareció")
		}
	})

	t.Run("la_lista_que_se_sirve_son_activos_y_retirados_de_su_alcance", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		stg, hol := b.sucursal(), b.sucursal()
		activo := b.tipoDe(alcance(stg), "activo-"+uuid.NewString()[:8])
		retirado := b.id(`INSERT INTO vehicle_types (nombre, costo_km_usd, activo, branch_id) VALUES ($1, NULL, false, $2) RETURNING id`,
			"retirado-"+uuid.NewString()[:8], stg)
		ajeno := b.tipoDe(alcance(hol), "ajeno-"+uuid.NewString()[:8])
		deTodas := b.tipoDe(sinAlcance, "todas-"+uuid.NewString()[:8])

		ids := func(p ListarTiposDeVehiculoParams) map[uuid.UUID]ListarTiposDeVehiculoRow {
			filas, err := b.q.ListarTiposDeVehiculo(b.ctx, p)
			if err != nil {
				t.Fatal(err)
			}
			m := map[uuid.UUID]ListarTiposDeVehiculoRow{}
			for _, f := range filas {
				m[f.ID] = f
			}
			return m
		}
		suyos := ids(ListarTiposDeVehiculoParams{Sucursal: alcance(stg)})
		if len(suyos) != 2 || suyos[activo].ID == uuid.Nil || suyos[retirado].ID == uuid.Nil {
			t.Fatalf("Santiago tenía que ver sus dos (el retirado también) y ni el de Holguín ni el «de todas»: %d", len(suyos))
		}
		if r := suyos[retirado]; r.Activo || r.CostoKmUsd != nil || r.BranchID != alcance(stg) {
			t.Fatalf("el retirado sin costo tiene que salir con activo=false, costo NULL y su sucursal: %+v", r)
		}
		todas := ids(ListarTiposDeVehiculoParams{})
		if todas[deTodas].ID == uuid.Nil || todas[activo].ID != uuid.Nil || todas[ajeno].ID != uuid.Nil {
			t.Fatalf("en modo «todas» salen SÓLO los «de todas»: %v", todas)
		}
	})
}

// La propia migración 00021: el Down quita el disparador y las lápidas; el Up lo vuelve a poner.
func TestMotorReal_Migracion00021TiposEnLaBajada(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	up, down := seccionesDeLaMigracion(t, "00021_tipos_de_vehiculo_en_la_bajada.sql")
	stg := b.sucursal()

	// Con la migración puesta, un borrado deja su lápida.
	uno := b.tipoDe(alcance(stg), "uno-"+uuid.NewString()[:8])
	b.exec(`DELETE FROM vehicle_types WHERE id = $1`, uno)
	if got := b.entero(`SELECT count(*) FROM bajas_de_la_bajada WHERE coleccion::text = 'vehicle_types' AND clave = $1::text`, uno); got != 1 {
		t.Fatalf("con la 00021 el borrado tenía que dejar su lápida: %d", got)
	}

	b.exec(down)
	if got := b.entero(`SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_vehicle_types_baja'`); got != 0 {
		t.Fatal("el Down dejó el disparador")
	}
	if got := b.entero(`SELECT count(*) FROM bajas_de_la_bajada WHERE coleccion::text = 'vehicle_types'`); got != 0 {
		t.Fatal("el Down dejó lápidas de una colección que ya no se sirve")
	}
	// Sin la migración, borrar un tipo no apunta nada.
	dos := b.tipoDe(alcance(stg), "dos-"+uuid.NewString()[:8])
	b.exec(`DELETE FROM vehicle_types WHERE id = $1`, dos)
	if got := b.entero(`SELECT count(*) FROM bajas_de_la_bajada WHERE clave = $1::text`, dos); got != 0 {
		t.Fatalf("sin el disparador no tenía que haber lápida: %d", got)
	}

	// `ADD VALUE IF NOT EXISTS`: el valor del enum SE QUEDÓ y subir otra vez no falla.
	b.exec(up)
	tres := b.tipoDe(alcance(stg), "tres-"+uuid.NewString()[:8])
	b.exec(`DELETE FROM vehicle_types WHERE id = $1`, tres)
	// Con su SUCURSAL (el tercer argumento del disparador): sin ella la lápida nace nula y la reciben los
	// aparatos de todas, no el de la sucursal que lo perdió.
	if got := b.entero(`SELECT count(*) FROM bajas_de_la_bajada WHERE coleccion::text = 'vehicle_types' AND clave = $1::text AND branch_id = $2 AND motivo = 'borrado'`, tres, stg); got != 1 {
		t.Fatalf("la segunda subida no volvió a poner el disparador con la sucursal del tipo: %d", got)
	}
}
