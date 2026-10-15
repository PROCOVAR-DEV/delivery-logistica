package sqlc

// MOTOR REAL de los DISTRIBUIDORES (issue 7 de Amado, migración 00019).
//
// Los dobles de `internal/api` reimplementan el SQL en Go y NO lo ven: aquí corre el `Queries` que genera
// sqlc contra Postgres de verdad. Misma regla que `consultas_motor_real_test.go` (que explica cómo se
// ejecuta: `REPARTO_MOTOR_REAL_DSN` hacia una base `verif…` migrada hasta la 00019) y mismo molde: cada
// subprueba abre SU transacción y la revierte.
//
// Lo que sólo ve la base, y que por eso va aquí: el filtro de sucursal DENTRO del SQL, el índice único
// sin distinguir mayúsculas ni espacios, el CHECK de nombre vacío, que borrar sin uso y retirar con uso
// sean UNA sentencia, la clave ajena SIN cascada, la lápida que pone el disparador, y la propia migración
// (Up sobre rutas que ya existían, Down que la deja como estaba).

import (
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func (b *banco) distribuidor(sucursal uuid.UUID, nombre string, activo bool) uuid.UUID {
	b.t.Helper()
	return b.id(`INSERT INTO distribuidores (branch_id, nombre, activo) VALUES ($1, $2, $3) RETURNING id`,
		sucursal, nombre, activo)
}

func (b *banco) rutaDe(sucursal, distribuidor uuid.UUID) uuid.UUID {
	b.t.Helper()
	return b.id(`INSERT INTO routes (branch_id, status, name, distribuidor_id) VALUES ($1, 'planned', 'ruta', $2) RETURNING id`,
		sucursal, distribuidor)
}

func idsDeLaLista(filas []ListarDistribuidoresRow) map[uuid.UUID]ListarDistribuidoresRow {
	m := map[uuid.UUID]ListarDistribuidoresRow{}
	for _, f := range filas {
		m[f.ID] = f
	}
	return m
}

func TestMotorReal_DistribuidoresPorSucursal(t *testing.T) {
	pool := motorReal(t)

	// escena: dos sucursales; «Juan» en las dos; Santiago tiene además a María (la usa una ruta) y a Pedro
	// (retirado).
	type escena struct {
		*banco
		stg, hol                       uuid.UUID
		juanStg, juanHol, maria, pedro uuid.UUID
		rutaDeMaria                    uuid.UUID
	}
	nueva := func(t *testing.T) *escena {
		b := nuevoBanco(t, pool)
		e := &escena{banco: b, stg: b.sucursal(), hol: b.sucursal()}
		e.juanStg = b.distribuidor(e.stg, "Juan Pérez", true)
		e.juanHol = b.distribuidor(e.hol, "Juan Pérez", true)
		e.maria = b.distribuidor(e.stg, "María López", true)
		e.pedro = b.distribuidor(e.stg, "Pedro Gil", false)
		e.rutaDeMaria = b.rutaDe(e.stg, e.maria)
		return e
	}

	t.Run("listar_acota_por_sucursal_y_el_modo_todas_ve_todas_las_listas", func(t *testing.T) {
		e := nueva(t)
		suyos := func(sucursal any) map[uuid.UUID]ListarDistribuidoresRow {
			var p ListarDistribuidoresParams
			switch s := sucursal.(type) {
			case uuid.UUID:
				p.Sucursal = alcance(s)
			}
			filas, err := e.q.ListarDistribuidores(e.ctx, p)
			if err != nil {
				t.Fatal(err)
			}
			return idsDeLaLista(filas)
		}
		stg := suyos(e.stg)
		if len(stg) != 3 || stg[e.juanHol].ID != uuid.Nil {
			t.Fatalf("Santiago tenía que ver sus tres y ninguno de Holguín: %d", len(stg))
		}
		if hol := suyos(e.hol); len(hol) != 1 || hol[e.juanHol].ID == uuid.Nil {
			t.Fatalf("Holguín tenía que ver sólo el suyo: %d", len(hol))
		}
		// «Todas» (sucursal nula): las listas de todas, incluidas las de estas dos sucursales de la prueba.
		todas := suyos(nil)
		for _, id := range []uuid.UUID{e.juanStg, e.juanHol, e.maria, e.pedro} {
			if todas[id].ID == uuid.Nil {
				t.Fatalf("en modo «todas» faltaba %s", id)
			}
		}
		if f := stg[e.juanStg]; f.SucursalNombre == "" || f.BranchID != e.stg {
			t.Fatalf("la fila tiene que decir su sucursal: %+v", f)
		}
	})

	t.Run("listar_solo_activos_y_cuenta_las_rutas_que_los_usan", func(t *testing.T) {
		e := nueva(t)
		si := true
		filas, err := e.q.ListarDistribuidores(e.ctx, ListarDistribuidoresParams{SoloActivos: &si, Sucursal: alcance(e.stg)})
		if err != nil {
			t.Fatal(err)
		}
		activos := idsDeLaLista(filas)
		if len(activos) != 2 || activos[e.pedro].ID != uuid.Nil {
			t.Fatalf("con solo_activos no puede salir el retirado: %d", len(activos))
		}
		if activos[e.maria].Rutas != 1 || activos[e.juanStg].Rutas != 0 {
			t.Fatalf("María la usa UNA ruta y Juan ninguna: %d y %d", activos[e.maria].Rutas, activos[e.juanStg].Rutas)
		}
		no := false
		filas, _ = e.q.ListarDistribuidores(e.ctx, ListarDistribuidoresParams{SoloActivos: &no, Sucursal: alcance(e.stg)})
		if len(filas) != 3 {
			t.Fatalf("con solo_activos=false salen todos: %d", len(filas))
		}
	})

	t.Run("obtener_acota_por_sucursal", func(t *testing.T) {
		e := nueva(t)
		if d, err := e.q.ObtenerDistribuidor(e.ctx, ObtenerDistribuidorParams{ID: e.juanStg, Sucursal: alcance(e.stg)}); err != nil || d.Nombre != "Juan Pérez" {
			t.Fatalf("el suyo tenía que salir: %+v %v", d, err)
		}
		_, err := e.q.ObtenerDistribuidor(e.ctx, ObtenerDistribuidorParams{ID: e.juanHol, Sucursal: alcance(e.stg)})
		sinFilas(t, "el de Holguín visto desde Santiago", err)
		if _, err := e.q.ObtenerDistribuidor(e.ctx, ObtenerDistribuidorParams{ID: e.juanHol, Sucursal: sinAlcance}); err != nil {
			t.Fatalf("en modo «todas» el de Holguín tenía que salir: %v", err)
		}
	})

	t.Run("el_nombre_es_unico_por_sucursal_sin_distinguir_mayusculas_ni_espacios", func(t *testing.T) {
		e := nueva(t)
		for _, nombre := range []string{"Juan Pérez", "juan pérez", "  JUAN PÉREZ  ", "pedro gil"} {
			err := e.intento(func() error {
				_, err := e.q.CrearDistribuidor(e.ctx, CrearDistribuidorParams{BranchID: e.stg, Nombre: nombre, Activo: true})
				return err
			})
			if !esClaveRepetida(err) {
				t.Fatalf("crear %q en Santiago tenía que dar 23505 (también contra un retirado) y dio %v", nombre, err)
			}
		}
		// La PAREJA: en otra sucursal el mismo nombre es válido, y uno distinto también.
		if _, err := e.q.CrearDistribuidor(e.ctx, CrearDistribuidorParams{BranchID: e.hol, Nombre: "María López", Activo: true}); err != nil {
			t.Fatalf("el mismo nombre en OTRA sucursal tenía que valer: %v", err)
		}
		if _, err := e.q.CrearDistribuidor(e.ctx, CrearDistribuidorParams{BranchID: e.stg, Nombre: "Ana Torres", Activo: true}); err != nil {
			t.Fatalf("un nombre libre tenía que valer: %v", err)
		}
	})

	t.Run("el_nombre_vacio_lo_rechaza_la_base", func(t *testing.T) {
		e := nueva(t)
		for _, nombre := range []string{"", "   "} {
			err := e.intento(func() error {
				_, err := e.q.CrearDistribuidor(e.ctx, CrearDistribuidorParams{BranchID: e.stg, Nombre: nombre, Activo: true})
				return err
			})
			if err == nil {
				t.Fatalf("la base dejó un distribuidor con nombre %q", nombre)
			}
		}
	})

	t.Run("actualizar_acota_por_sucursal_y_respeta_la_unica", func(t *testing.T) {
		e := nueva(t)
		nuevo := "Juan Carlos"
		if d, err := e.q.ActualizarDistribuidor(e.ctx, ActualizarDistribuidorParams{ID: e.juanStg, Nombre: &nuevo, Sucursal: alcance(e.stg)}); err != nil || d.Nombre != nuevo {
			t.Fatalf("renombrar el suyo tenía que valer: %+v %v", d, err)
		}
		_, err := e.q.ActualizarDistribuidor(e.ctx, ActualizarDistribuidorParams{ID: e.juanHol, Nombre: &nuevo, Sucursal: alcance(e.stg)})
		sinFilas(t, "renombrar el de Holguín desde Santiago", err)
		if got := e.entero(`SELECT count(*) FROM distribuidores WHERE id = $1 AND nombre = 'Juan Pérez'`, e.juanHol); got != 1 {
			t.Fatal("el 404 llegó DESPUÉS de escribir: el de Holguín se renombró")
		}
		repetido := "María López"
		err = e.intento(func() error {
			_, err := e.q.ActualizarDistribuidor(e.ctx, ActualizarDistribuidorParams{ID: e.juanStg, Nombre: &repetido, Sucursal: alcance(e.stg)})
			return err
		})
		if !esClaveRepetida(err) {
			t.Fatalf("renombrar a uno que ya existe tenía que dar 23505 y dio %v", err)
		}
		// Activar/retirar sin tocar el nombre (el coalesce).
		no := false
		d, err := e.q.ActualizarDistribuidor(e.ctx, ActualizarDistribuidorParams{ID: e.maria, Activo: &no, Sucursal: alcance(e.stg)})
		if err != nil || d.Activo || d.Nombre != "María López" {
			t.Fatalf("retirar con PATCH no puede tocar el nombre: %+v %v", d, err)
		}
	})

	t.Run("retirar_acota_y_devuelve_la_sucursal", func(t *testing.T) {
		e := nueva(t)
		sucursal, err := e.q.RetirarDistribuidor(e.ctx, RetirarDistribuidorParams{ID: e.maria, Sucursal: alcance(e.stg)})
		if err != nil || sucursal != e.stg {
			t.Fatalf("retirar el suyo: %v %v", sucursal, err)
		}
		if got := e.entero(`SELECT count(*) FROM distribuidores WHERE id = $1 AND NOT activo`, e.maria); got != 1 {
			t.Fatal("no quedó retirada")
		}
		_, err = e.q.RetirarDistribuidor(e.ctx, RetirarDistribuidorParams{ID: e.juanHol, Sucursal: alcance(e.stg)})
		sinFilas(t, "retirar el de Holguín desde Santiago", err)
		if got := e.entero(`SELECT count(*) FROM distribuidores WHERE id = $1 AND activo`, e.juanHol); got != 1 {
			t.Fatal("el 404 llegó DESPUÉS de retirar: el de Holguín quedó retirado")
		}
	})

	t.Run("borrar_sin_uso_borra_y_con_uso_no_borra_nada", func(t *testing.T) {
		e := nueva(t)
		// CON UNA RUTA: cero filas (el manejador lo retira), y sigue ahí.
		_, err := e.q.BorrarDistribuidorSinUso(e.ctx, BorrarDistribuidorSinUsoParams{ID: e.maria, Sucursal: alcance(e.stg)})
		sinFilas(t, "borrar al que usa una ruta", err)
		if got := e.entero(`SELECT count(*) FROM distribuidores WHERE id = $1`, e.maria); got != 1 {
			t.Fatal("se borró al que usa una ruta")
		}
		// DE OTRA SUCURSAL: cero filas aunque no lo use nadie.
		_, err = e.q.BorrarDistribuidorSinUso(e.ctx, BorrarDistribuidorSinUsoParams{ID: e.juanHol, Sucursal: alcance(e.stg)})
		sinFilas(t, "borrar el de Holguín desde Santiago", err)
		if got := e.entero(`SELECT count(*) FROM distribuidores WHERE id = $1`, e.juanHol); got != 1 {
			t.Fatal("se borró el de otra sucursal")
		}
		// SIN USO Y SUYO: se borra y devuelve su sucursal.
		sucursal, err := e.q.BorrarDistribuidorSinUso(e.ctx, BorrarDistribuidorSinUsoParams{ID: e.juanStg, Sucursal: alcance(e.stg)})
		if err != nil || sucursal != e.stg {
			t.Fatalf("borrar el suyo sin uso: %v %v", sucursal, err)
		}
		if got := e.entero(`SELECT count(*) FROM distribuidores WHERE id = $1`, e.juanStg); got != 0 {
			t.Fatal("dijo que lo borró y sigue ahí")
		}
	})

	t.Run("borrar_pone_su_lapida_para_el_aparato_de_su_sucursal", func(t *testing.T) {
		e := nueva(t)
		if _, err := e.q.BorrarDistribuidorSinUso(e.ctx, BorrarDistribuidorSinUsoParams{ID: e.juanStg, Sucursal: alcance(e.stg)}); err != nil {
			t.Fatal(err)
		}
		bajas := func(sucursal uuid.UUID) []BajasDeLaBajadaRow {
			filas, err := e.q.BajasDeLaBajada(e.ctx, BajasDeLaBajadaParams{
				Coleccion: ColeccionDeLaBajadaDistribuidores, Sucursal: alcance(sucursal), Tope: 100,
			})
			if err != nil {
				t.Fatal(err)
			}
			return filas
		}
		stg := bajas(e.stg)
		if len(stg) != 1 || stg[0].Clave != e.juanStg.String() || stg[0].Motivo != MotivoDeBajaBorrado || stg[0].BranchID != alcance(e.stg) {
			t.Fatalf("Santiago tenía que recibir UNA baja, la de Juan: %+v", stg)
		}
		if hol := bajas(e.hol); len(hol) != 0 {
			t.Fatalf("a Holguín le llegó la baja de un distribuidor de Santiago: %+v", hol)
		}
		// Retirar NO es borrar: no deja lápida.
		if _, err := e.q.RetirarDistribuidor(e.ctx, RetirarDistribuidorParams{ID: e.maria, Sucursal: alcance(e.stg)}); err != nil {
			t.Fatal(err)
		}
		if got := bajas(e.stg); len(got) != 1 {
			t.Fatalf("retirar dejó una lápida: %+v", got)
		}
	})

	t.Run("la_clave_ajena_no_borra_en_cascada", func(t *testing.T) {
		e := nueva(t)
		// Borrar a mano al que usa una ruta, o a una sucursal con distribuidores, FALLA en voz alta.
		err := e.intento(func() error {
			_, err := e.tx.Exec(e.ctx, `DELETE FROM distribuidores WHERE id = $1`, e.maria)
			return err
		})
		if err == nil {
			t.Fatal("se borró al distribuidor de una ruta: la ruta se queda sin quién la repartió")
		}
		err = e.intento(func() error {
			_, err := e.tx.Exec(e.ctx, `DELETE FROM branches WHERE id = $1`, e.hol)
			return err
		})
		if err == nil {
			t.Fatal("se borró una sucursal con distribuidores: ON DELETE CASCADE se llevaría su nomenclador")
		}
		if e.entero(`SELECT count(*) FROM routes WHERE id = $1 AND distribuidor_id = $2`, e.rutaDeMaria, e.maria) != 1 {
			t.Fatal("la ruta perdió su distribuidor")
		}
	})

	t.Run("la_ruta_guarda_y_lee_su_distribuidor_con_su_nombre", func(t *testing.T) {
		e := nueva(t)
		creada, err := e.q.CrearRuta(e.ctx, CrearRutaParams{
			RouteCode: str("RT-X-001"), OriginLat: f64(0), OriginLng: f64(0),
			BranchID: alcance(e.stg), DistribuidorID: alcance(e.juanStg),
		})
		if err != nil {
			t.Fatal(err)
		}
		det, err := e.q.ObtenerRuta(e.ctx, ObtenerRutaParams{ID: creada.ID, Sucursal: alcance(e.stg)})
		if err != nil || det.DistribuidorNombre == nil || *det.DistribuidorNombre != "Juan Pérez" || det.DistribuidorID != alcance(e.juanStg) {
			t.Fatalf("el detalle tenía que traer a Juan: %+v %v", det.DistribuidorNombre, err)
		}
		lista, err := e.q.ListarRutas(e.ctx, ListarRutasParams{Sucursal: alcance(e.stg)})
		if err != nil {
			t.Fatal(err)
		}
		visto := false
		for _, r := range lista {
			if r.ID == creada.ID {
				visto = r.DistribuidorNombre != nil && *r.DistribuidorNombre == "Juan Pérez"
			}
		}
		if !visto {
			t.Fatal("la lista de rutas no trajo el nombre del distribuidor")
		}
		// Sin distribuidor: nulo, no inventado.
		sin, _ := e.q.CrearRuta(e.ctx, CrearRutaParams{RouteCode: str("RT-X-002"), OriginLat: f64(0), OriginLng: f64(0), BranchID: alcance(e.stg)})
		d2, _ := e.q.ObtenerRuta(e.ctx, ObtenerRutaParams{ID: sin.ID, Sucursal: alcance(e.stg)})
		if d2.DistribuidorID.Valid || d2.DistribuidorNombre != nil {
			t.Fatalf("una ruta sin distribuidor salió con uno: %+v", d2.DistribuidorNombre)
		}
	})

	t.Run("actualizar_la_ruta_cambia_quita_y_no_toca_al_distribuidor", func(t *testing.T) {
		e := nueva(t)
		quien := func() pgtype.UUID {
			det, err := e.q.ObtenerRuta(e.ctx, ObtenerRutaParams{ID: e.rutaDeMaria, Sucursal: alcance(e.stg)})
			if err != nil {
				t.Fatal(err)
			}
			return det.DistribuidorID
		}
		nombre := "otra"
		// SIN tocar: el nombre cambia y el distribuidor se queda.
		if _, err := e.q.ActualizarEstadoDeRuta(e.ctx, ActualizarEstadoDeRutaParams{ID: e.rutaDeMaria, Name: &nombre, Sucursal: alcance(e.stg)}); err != nil {
			t.Fatal(err)
		}
		if quien() != alcance(e.maria) {
			t.Fatal("un cambio de nombre borró al distribuidor")
		}
		// TOCANDO con valor.
		if _, err := e.q.ActualizarEstadoDeRuta(e.ctx, ActualizarEstadoDeRutaParams{ID: e.rutaDeMaria, TocarDistribuidor: true, DistribuidorID: alcance(e.juanStg), Sucursal: alcance(e.stg)}); err != nil {
			t.Fatal(err)
		}
		if quien() != alcance(e.juanStg) {
			t.Fatal("no cambió de distribuidor")
		}
		// TOCANDO con nulo: lo quita. Por el otro camino (el del camión) también.
		if _, err := e.q.CambiarVehiculoDeRuta(e.ctx, CambiarVehiculoDeRutaParams{ID: e.rutaDeMaria, TocarDistribuidor: true, Sucursal: alcance(e.stg)}); err != nil {
			t.Fatal(err)
		}
		if quien().Valid {
			t.Fatal("no se quitó el distribuidor")
		}
		if _, err := e.q.CambiarVehiculoDeRuta(e.ctx, CambiarVehiculoDeRutaParams{ID: e.rutaDeMaria, Name: &nombre, Sucursal: alcance(e.stg)}); err != nil {
			t.Fatal(err)
		}
		// De otra sucursal: nada.
		_, err := e.q.ActualizarEstadoDeRuta(e.ctx, ActualizarEstadoDeRutaParams{ID: e.rutaDeMaria, TocarDistribuidor: true, DistribuidorID: alcance(e.juanHol), Sucursal: alcance(e.hol)})
		if err == nil || err != pgx.ErrNoRows {
			t.Fatalf("tocar la ruta de Santiago desde Holguín tenía que ser ErrNoRows: %v", err)
		}
	})
}

// ---------------------------------------------------------------------------
// La propia migración 00019: Up sobre rutas que ya existían, y Down que la deja como estaba
// ---------------------------------------------------------------------------

func TestMotorReal_Migracion00019Distribuidores(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	up, down := seccionesDeLaMigracion(t, "00019_distribuidores.sql")

	// La base ya está en la 00019. Dentro de ESTA transacción se deshace, se siembra el estado de ANTES con
	// rutas de verdad, se sube y se mira. Todo se revierte al terminar (los DDL de Postgres son
	// transaccionales; mientras dura, `routes` queda bloqueada: no se corre contra una base que use otro).
	b.exec(down)
	if got := b.entero(`SELECT count(*) FROM information_schema.columns WHERE table_name = 'routes' AND column_name = 'distribuidor_id'`); got != 0 {
		t.Fatal("el Down dejó la columna routes.distribuidor_id")
	}
	if got := b.entero(`SELECT count(*) FROM information_schema.tables WHERE table_name = 'distribuidores'`); got != 0 {
		t.Fatal("el Down dejó la tabla distribuidores")
	}

	a := b.sucursal()
	antes := []uuid.UUID{b.ruta(a, RouteStatusPlanned), b.ruta(a, RouteStatusInProgress), b.ruta(a, RouteStatusCompleted)}

	b.exec(up)

	t.Run("las_rutas_historicas_quedan_sin_distribuidor_y_no_se_pierde_ninguna", func(t *testing.T) {
		if got := b.entero(`SELECT count(*) FROM routes WHERE id = ANY($1)`, antes); got != len(antes) {
			t.Fatalf("la subida perdió rutas: quedan %d de %d", got, len(antes))
		}
		if got := b.entero(`SELECT count(*) FROM routes WHERE id = ANY($1) AND distribuidor_id IS NOT NULL`, antes); got != 0 {
			t.Fatal("la migración le inventó un distribuidor a una ruta histórica")
		}
	})

	t.Run("la_columna_es_opcional_y_la_clave_ajena_no_borra_en_cascada", func(t *testing.T) {
		if got := b.entero(`SELECT count(*) FROM information_schema.columns WHERE table_name = 'routes' AND column_name = 'distribuidor_id' AND is_nullable = 'YES'`); got != 1 {
			t.Fatal("routes.distribuidor_id tiene que existir y admitir nulo")
		}
		var accion string
		if err := b.tx.QueryRow(b.ctx, `SELECT confdeltype::text FROM pg_constraint WHERE conrelid = 'routes'::regclass AND contype = 'f' AND confrelid = 'distribuidores'::regclass`).Scan(&accion); err != nil {
			t.Fatal(err)
		}
		if accion != "a" {
			t.Fatalf("la clave ajena de routes.distribuidor_id es %q y tiene que ser 'a' (NO ACTION): sin ON DELETE CASCADE", accion)
		}
		if err := b.tx.QueryRow(b.ctx, `SELECT confdeltype::text FROM pg_constraint WHERE conrelid = 'distribuidores'::regclass AND contype = 'f' AND confrelid = 'branches'::regclass`).Scan(&accion); err != nil || accion != "a" {
			t.Fatalf("la clave ajena de distribuidores.branch_id es %q (%v) y tiene que ser 'a'", accion, err)
		}
	})

	// Sin sucursal no hay dueño: lo rechaza la BASE (NOT NULL de la 00019), no sólo la API. La
	// pareja: con sucursal, el mismo alta entra.
	t.Run("sin_sucursal_lo_rechaza_la_base", func(t *testing.T) {
		err := b.intento(func() error {
			_, err := b.tx.Exec(b.ctx, `INSERT INTO distribuidores (branch_id, nombre) VALUES (NULL, 'Sin dueño')`)
			return err
		})
		if err == nil || !strings.Contains(err.Error(), "23502") {
			t.Fatalf("un distribuidor sin sucursal tenía que dar 23502 (NOT NULL) y dio %v", err)
		}
		if err := b.intento(func() error {
			_, err := b.tx.Exec(b.ctx, `INSERT INTO distribuidores (branch_id, nombre) VALUES ($1, 'Sin dueño')`, a)
			return err
		}); err != nil {
			t.Fatalf("con sucursal el mismo alta tenía que entrar: %v", err)
		}
	})

	t.Run("el_nombre_es_unico_por_sucursal_sin_distinguir_mayusculas_ni_espacios", func(t *testing.T) {
		b.distribuidor(a, "Juan Pérez", true)
		err := b.intento(func() error {
			_, err := b.tx.Exec(b.ctx, `INSERT INTO distribuidores (branch_id, nombre) VALUES ($1, '  JUAN pérez ')`, a)
			return err
		})
		if !esClaveRepetida(err) {
			t.Fatalf("repetir el nombre con otras mayúsculas y espacios tenía que dar 23505 y dio %v", err)
		}
		if err := b.intento(func() error {
			_, err := b.tx.Exec(b.ctx, `INSERT INTO distribuidores (branch_id, nombre) VALUES ($1, 'Juan Pérez')`, b.sucursal())
			return err
		}); err != nil {
			t.Fatalf("el mismo nombre en otra sucursal tenía que valer: %v", err)
		}
	})

	t.Run("updated_at_se_mueve_con_el_disparador_de_la_casa", func(t *testing.T) {
		id := b.distribuidor(a, "Rosa", true)
		b.exec(`UPDATE distribuidores SET updated_at = now() - interval '1 day' WHERE id = $1`, id)
		// El disparador pisa a mano lo que se ponga: el UPDATE sigue dejando `now()`.
		if got := b.entero(`SELECT count(*) FROM distribuidores WHERE id = $1 AND updated_at > now() - interval '1 minute'`, id); got != 1 {
			t.Fatal("`updated_at` no lo mantiene `set_updated_at`: la bajada por diferencias no vería el cambio")
		}
	})

	t.Run("el_borrado_deja_su_lapida_con_el_disparador", func(t *testing.T) {
		id := b.distribuidor(a, "Borrable", true)
		b.exec(`DELETE FROM distribuidores WHERE id = $1`, id)
		if got := b.entero(`SELECT count(*) FROM bajas_de_la_bajada WHERE coleccion::text = 'distribuidores' AND clave = $1::text AND branch_id = $2 AND motivo = 'borrado'`, id, a); got != 1 {
			t.Fatalf("el DELETE no dejó su lápida: %d", got)
		}
	})

	// DESPUÉS de la subida se trabaja: una ruta con distribuidor.
	d := b.distribuidor(a, "Quien reparte", true)
	conDist := b.rutaDe(a, d)
	b.exec(down)

	t.Run("down_deja_la_base_como_estaba_y_no_pierde_rutas", func(t *testing.T) {
		if got := b.entero(`SELECT count(*) FROM information_schema.columns WHERE table_name = 'routes' AND column_name = 'distribuidor_id'`); got != 0 {
			t.Fatal("el Down dejó la columna")
		}
		if got := b.entero(`SELECT count(*) FROM information_schema.tables WHERE table_name = 'distribuidores'`); got != 0 {
			t.Fatal("el Down dejó la tabla")
		}
		if got := b.entero(`SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_distribuidores_baja'`); got != 0 {
			t.Fatal("el Down dejó el disparador de la lápida")
		}
		if got := b.entero(`SELECT count(*) FROM bajas_de_la_bajada WHERE coleccion::text = 'distribuidores'`); got != 0 {
			t.Fatal("el Down dejó lápidas de una colección que ya no existe")
		}
		// Pierde QUIÉN repartió, y sólo eso: las rutas siguen (también la que lo tenía).
		if got := b.entero(`SELECT count(*) FROM routes WHERE id = ANY($1)`, append(antes, conDist)); got != len(antes)+1 {
			t.Fatalf("el Down se llevó rutas: quedan %d de %d", got, len(antes)+1)
		}
	})

	t.Run("se_puede_volver_a_subir", func(t *testing.T) {
		// `ADD VALUE IF NOT EXISTS`: el valor del enum SE QUEDÓ (Postgres no sabe quitarlo) y subir otra vez no falla.
		b.exec(up)
		if got := b.entero(`SELECT count(*) FROM information_schema.tables WHERE table_name = 'distribuidores'`); got != 1 {
			t.Fatal("la segunda subida no recreó la tabla")
		}
	})
}
