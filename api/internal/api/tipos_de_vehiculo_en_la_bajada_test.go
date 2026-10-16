package api

// LOS TIPOS DE VEHÍCULO Y LOS CAMIONES COMPLETOS BAJAN AL APARATO — issue 14 de Amado, 16/10/2026.
//
// La APK y el escritorio listan y CREAN tipos, camiones y distribuidores sin conexión, así que
// `GET /api/sync/cambios` tiene que llevar: la colección `vehicle_types` (la MISMA lista y el MISMO
// alcance que `GET /api/vehicle-types`), y en `vehicles` lo que hace falta para editar un camión
// (`vehicleTypeId`, `costoKmUsd` DEL CAMIÓN, `usarParaDomicilio`, `notes`, `createdAt`).
//
// Y como la marca `desde` es única para todas las colecciones, un aparato que ya había sincronizado
// bajó `vehicles` sin esos campos y nunca bajó `vehicle_types`: `?completas=` los entrega enteros.
// Todo en PAREJA: el caso sano y el que reproduce el fallo.

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

var (
	tipoStgTruck     = uuid.MustParse("7e000000-0000-0000-0000-000000000001")
	tipoStgRetira    = uuid.MustParse("7e000000-0000-0000-0000-000000000002")
	tipoHolTruck     = uuid.MustParse("7e000000-0000-0000-0000-000000000003")
	tipoDeTodas      = uuid.MustParse("7e000000-0000-0000-0000-000000000004")
	tipoStgViejo     = uuid.MustParse("7e000000-0000-0000-0000-000000000005")
	tipoBorrado      = uuid.MustParse("7e000000-0000-0000-0000-0000000000a1")
	tipoBorradoHol   = uuid.MustParse("7e000000-0000-0000-0000-0000000000a2")
	tipoBorradoTodas = uuid.MustParse("7e000000-0000-0000-0000-0000000000a3")
)

func pgSuc(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

func unTipoDeLaBajada(id uuid.UUID, nombre string, costo *float64, activo bool, sucursal pgtype.UUID, marca time.Time) sqlc.ListarTiposDeVehiculoRow {
	return sqlc.ListarTiposDeVehiculoRow{
		ID: id, Nombre: nombre, CostoKmUsd: costo, Activo: activo, BranchID: sucursal,
		CreatedAt: pgtype.Timestamptz{Time: marca.Add(-72 * time.Hour), Valid: true},
		UpdatedAt: pgtype.Timestamptz{Time: marca, Valid: true},
	}
}

func f64(v float64) *float64 { return &v }

func espejoConTipos(ahora time.Time) *espejoFalso {
	q := nuevoEspejo()
	q.tiposDelEspejo = []sqlc.ListarTiposDeVehiculoRow{
		unTipoDeLaBajada(tipoStgTruck, "truck", f64(0.45), true, pgSuc(sucStg), ahora),
		// Sin costo: VACÍO, no cero (CLAUDE.md §2). Tiene que viajar como null.
		unTipoDeLaBajada(tipoStgRetira, "van", nil, false, pgSuc(sucStg), ahora),
		unTipoDeLaBajada(tipoHolTruck, "truck", f64(0.5), true, pgSuc(sucHol), ahora),
		unTipoDeLaBajada(tipoDeTodas, "truck", f64(0.4), true, pgtype.UUID{}, ahora),
	}
	return q
}

// CADA APARATO RECIBE LOS TIPOS DE SU SUCURSAL, activos y retirados, con todos sus campos; el de
// otra sucursal y el «de todas» NO le llegan. Quien está en modo «todas» recibe SÓLO los «de todas»
// (la misma lista que `GET /api/vehicle-types`).
func TestLaBajadaLlevaLosTiposDeVehiculoDeSuAlcance(t *testing.T) {
	ahora := time.Now().UTC()
	q := espejoConTipos(ahora)

	t.Run("Santiago: los suyos, con el retirado, y ni el de Holguín ni el «de todas»", func(t *testing.T) {
		puestos := puestosDe(t, bajadaDe(t, q, tokenTab(t, sucStg.String()), ""), "vehicle_types")
		if len(puestos) != 2 || puestos[tipoStgTruck.String()] == nil || puestos[tipoStgRetira.String()] == nil {
			t.Fatalf("Santiago tenía que recibir sus dos (el retirado también) y recibió %v", puestos)
		}
		truck := puestos[tipoStgTruck.String()]
		if truck["nombre"] != "truck" || truck["costoKmUsd"] != 0.45 || truck["activo"] != true ||
			truck["branchId"] != sucStg.String() {
			t.Fatalf("la fila tiene que llevar nombre, costo, estado y sucursal: %v", truck)
		}
		if _, hay := truck["createdAt"].(string); !hay {
			t.Fatalf("falta createdAt: %v", truck)
		}
		if _, hay := truck["updatedAt"].(string); !hay {
			t.Fatalf("falta updatedAt: %v", truck)
		}
		van := puestos[tipoStgRetira.String()]
		// Un costo vacío viaja como null: un 0 se leería como «el kilómetro es gratis».
		if v, hay := van["costoKmUsd"]; !hay || v != nil {
			t.Fatalf("un tipo sin costo tiene que bajar con costoKmUsd null, no 0 ni ausente: %v", van)
		}
		if van["activo"] != false {
			t.Fatal("el retirado tiene que bajar como retirado: el selector lo esconde él")
		}
	})

	t.Run("Holguín: sólo el suyo", func(t *testing.T) {
		puestos := puestosDe(t, bajadaDe(t, q, tokenTab(t, sucHol.String()), ""), "vehicle_types")
		if len(puestos) != 1 || puestos[tipoHolTruck.String()] == nil {
			t.Fatalf("Holguín tenía que recibir sólo el suyo: %v", puestos)
		}
	})

	t.Run("modo «todas»: sólo los «de todas», con branchId null", func(t *testing.T) {
		puestos := puestosDe(t, bajadaDe(t, q, tokenTab(t, ""), ""), "vehicle_types")
		if len(puestos) != 1 || puestos[tipoDeTodas.String()] == nil {
			t.Fatalf("en modo «todas» tenía que recibir sólo el «de todas» (como GET /api/vehicle-types): %v", puestos)
		}
		if v, hay := puestos[tipoDeTodas.String()]["branchId"]; !hay || v != nil {
			t.Fatalf("el «de todas» baja con branchId null: %v", puestos[tipoDeTodas.String()])
		}
	})
}

// POR DIFERENCIAS Y `completas`. El aparato viejo trae una marca `desde` posterior a sus tipos: sin
// `completas` NO le llegan (el fallo), con `completas=vehicle_types` sí, y sin tocar las demás.
func TestCompletasTraeLosTiposAnterioresALaMarca(t *testing.T) {
	ahora := time.Now().UTC()
	marca := ahora.Add(-time.Hour)
	q := nuevoEspejo()
	q.tiposDelEspejo = []sqlc.ListarTiposDeVehiculoRow{
		unTipoDeLaBajada(tipoStgViejo, "car", f64(0.3), true, pgSuc(sucStg), ahora.Add(-48*time.Hour)),
		unTipoDeLaBajada(tipoStgTruck, "truck", f64(0.45), true, pgSuc(sucStg), ahora),
	}
	q.bajas = []bajaSync{
		// Posterior a la marca: con la lista ENTERA no hay nada que quitar.
		{sqlc.ColeccionDeLaBajadaVehicleTypes, tipoBorrado.String(), &sucStg, sqlc.MotivoDeBajaBorrado, ahora.Add(-30 * time.Minute)},
	}
	desde := "?desde=" + marca.Format(time.RFC3339Nano)
	santiago := tokenTab(t, sucStg.String())

	t.Run("por diferencias: sólo lo que cambió después de la marca", func(t *testing.T) {
		puestos := puestosDe(t, bajadaDe(t, q, santiago, desde), "vehicle_types")
		if len(puestos) != 1 || puestos[tipoStgTruck.String()] == nil {
			t.Fatalf("con «desde» sólo tenía que venir el que cambió: %v", puestos)
		}
	})

	t.Run("`completas=vehicle_types` los trae TODOS y sin lápidas; sin él, no", func(t *testing.T) {
		con := bajadaDe(t, q, santiago, desde+"&completas=vehicle_types")
		if got := puestosDe(t, con, "vehicle_types"); len(got) != 2 || got[tipoStgViejo.String()] == nil {
			t.Fatalf("`completas=vehicle_types` tenía que traer los dos, y trajo %v", got)
		}
		if quitados := bajasDe(t, con, "vehicle_types"); len(quitados) != 0 {
			t.Fatalf("pidiendo la lista entera no hay nada que quitar: %v", quitados)
		}
		// Las listas hermanas NO se ensanchan.
		if got := puestosDe(t, con, "distribuidores"); len(got) != 0 {
			t.Fatalf("`completas` ensanchó los distribuidores: %v", got)
		}
		// Y la misma petición SIN `completas` sí trae la lápida (la pareja).
		sin := bajadaDe(t, q, santiago, desde)
		if !bajasDe(t, sin, "vehicle_types")[tipoBorrado.String()] {
			t.Fatal("sin `completas` la lápida posterior a la marca tenía que salir")
		}
	})

	t.Run("un nombre ajeno en `completas` no ensancha los tipos", func(t *testing.T) {
		raro := bajadaDe(t, q, santiago, desde+"&completas=ruta%20inventada,distribuidores")
		if got := puestosDe(t, raro, "vehicle_types"); len(got) != 1 {
			t.Fatalf("un nombre ajeno ensanchó los tipos: %v", got)
		}
	})
}

// LA LÁPIDA DE UN TIPO BORRADO sale en «quitados» de SU sucursal y de ninguna otra; la de uno «de
// todas» (sucursal nula) NO le llega a quien tiene sucursal y SÍ a quien ve «todas»; la mentirosa
// (de uno que sigue vivo) se tacha; la anterior a la marca no sale.
func TestElBorradoDeUnTipoSaleEnQuitadosDeSuAlcance(t *testing.T) {
	ahora := time.Now().UTC()
	marca := ahora.Add(-12 * time.Hour)
	q := nuevoEspejo()
	q.tiposDelEspejo = []sqlc.ListarTiposDeVehiculoRow{
		unTipoDeLaBajada(tipoStgTruck, "truck", f64(0.45), true, pgSuc(sucStg), ahora.Add(-24*time.Hour)),
		unTipoDeLaBajada(tipoDeTodas, "truck", f64(0.4), true, pgtype.UUID{}, ahora.Add(-24*time.Hour)),
	}
	hace1h := ahora.Add(-time.Hour)
	q.bajas = []bajaSync{
		{sqlc.ColeccionDeLaBajadaVehicleTypes, tipoBorrado.String(), &sucStg, sqlc.MotivoDeBajaBorrado, hace1h},
		{sqlc.ColeccionDeLaBajadaVehicleTypes, tipoBorradoHol.String(), &sucHol, sqlc.MotivoDeBajaBorrado, hace1h},
		{sqlc.ColeccionDeLaBajadaVehicleTypes, tipoBorradoTodas.String(), nil, sqlc.MotivoDeBajaBorrado, hace1h},
		// LA LÁPIDA MENTIROSA: de uno que sigue vivo. Tiene que tacharse.
		{sqlc.ColeccionDeLaBajadaVehicleTypes, tipoStgTruck.String(), &sucStg, sqlc.MotivoDeBajaBorrado, hace1h},
		// Anterior a la marca: ya se la llevó en su día.
		{sqlc.ColeccionDeLaBajadaVehicleTypes, tipoStgViejo.String(), &sucStg, sqlc.MotivoDeBajaBorrado, ahora.Add(-24 * time.Hour)},
		// De otra colección con el mismo id: no es de ésta.
		{sqlc.ColeccionDeLaBajadaDistribuidores, "7e000000-0000-0000-0000-0000000000ff", &sucStg, sqlc.MotivoDeBajaBorrado, hace1h},
	}
	desde := "?desde=" + marca.Format(time.RFC3339Nano)

	t.Run("Santiago", func(t *testing.T) {
		quitados := bajasDe(t, bajadaDe(t, q, tokenTab(t, sucStg.String()), desde), "vehicle_types")
		if !quitados[tipoBorrado.String()] {
			t.Fatalf("el tipo borrado no salió en «quitados»: el aparato lo seguiría ofreciendo.\n%v", quitados)
		}
		if quitados[tipoBorradoHol.String()] {
			t.Fatal("a Santiago le llegó la baja de un tipo de Holguín")
		}
		if quitados[tipoBorradoTodas.String()] {
			t.Fatal("a Santiago le llegó la baja de un tipo «de todas», que su lista nunca incluyó")
		}
		if quitados[tipoStgTruck.String()] {
			t.Fatal("salió en «quitados» uno que sigue vivo: se lo llevaría el aparato por una lápida mal puesta")
		}
		if quitados[tipoStgViejo.String()] {
			t.Fatal("salió una baja anterior a la marca del aparato")
		}
		if quitados["7e000000-0000-0000-0000-0000000000ff"] {
			t.Fatal("se coló la lápida de otra colección")
		}
	})

	t.Run("modo «todas»: recibe la del «de todas» (su lista son ésos)", func(t *testing.T) {
		quitados := bajasDe(t, bajadaDe(t, q, tokenTab(t, ""), desde), "vehicle_types")
		if !quitados[tipoBorradoTodas.String()] {
			t.Fatalf("quien ve «todas» tenía que recibir la baja del «de todas»: %v", quitados)
		}
		if quitados[tipoDeTodas.String()] {
			t.Fatal("salió en «quitados» un «de todas» que sigue vivo")
		}
	})
}

// EL CAMIÓN BAJA CON LO QUE HACE FALTA PARA EDITARLO SIN CONEXIÓN, y el costo es el DEL CAMIÓN: un
// camión sin costo propio baja con null aunque su tipo tenga uno.
func TestLaBajadaDeVehiculosLlevaLosCamposParaEditarlos(t *testing.T) {
	ahora := time.Now().UTC()
	notas := "se le cambió el aceite"
	placa := "P123456"
	q := nuevoEspejo()
	q.vehiculosDelEspejo = []sqlc.ListarVehiculosRow{
		{ID: vehVivo, Name: "Camión 1", VehicleTypeID: tipoStgTruck, TipoNombre: "truck", Plate: &placa,
			Capacity: 1000, Status: sqlc.VehicleStatusAvailable, IsActive: true,
			CostoKmUsd: f64(0.7), TipoCostoKmUsd: f64(0.45), UsarParaDomicilio: true, Notes: &notas,
			BranchID:  pgSuc(sucStg),
			CreatedAt: pgtype.Timestamptz{Time: ahora.Add(-72 * time.Hour), Valid: true},
			UpdatedAt: pgtype.Timestamptz{Time: ahora, Valid: true}},
		{ID: vehBorrado, Name: "Camión 2", VehicleTypeID: tipoStgTruck, TipoNombre: "truck",
			TipoCostoKmUsd: f64(0.45), BranchID: pgSuc(sucStg),
			CreatedAt: pgtype.Timestamptz{Time: ahora.Add(-72 * time.Hour), Valid: true},
			UpdatedAt: pgtype.Timestamptz{Time: ahora, Valid: true}},
	}
	puestos := puestosDe(t, bajadaDe(t, q, tokenTab(t, sucStg.String()), ""), "vehicles")

	c1 := puestos[vehVivo.String()]
	if c1["vehicleTypeId"] != tipoStgTruck.String() || c1["costoKmUsd"] != 0.7 ||
		c1["usarParaDomicilio"] != true || c1["notes"] != notas {
		t.Fatalf("el camión tiene que bajar con vehicleTypeId, costoKmUsd (el SUYO), usarParaDomicilio y notes: %v", c1)
	}
	if _, hay := c1["createdAt"].(string); !hay {
		t.Fatalf("falta createdAt: %v", c1)
	}
	// Los que ya salían siguen saliendo.
	if c1["type"] != "truck" || c1["isActive"] != true || c1["branchId"] != sucStg.String() {
		t.Fatalf("se perdió algo de lo que ya bajaba: %v", c1)
	}

	c2 := puestos[vehBorrado.String()]
	if v, hay := c2["costoKmUsd"]; !hay || v != nil {
		t.Fatalf("un camión SIN costo propio baja con costoKmUsd null (no el del tipo, ni 0): %v", c2)
	}
	if v, hay := c2["notes"]; !hay || v != nil {
		t.Fatalf("las notas vacías bajan como null: %v", c2)
	}
	if c2["usarParaDomicilio"] != false {
		t.Fatalf("usarParaDomicilio falso baja como false: %v", c2)
	}
}

// `completas=vehicles`: el aparato que bajó los camiones SIN los campos nuevos los recibe enteros,
// aunque su marca los deje atrás. Sin `completas`, no (el fallo), y sin lápidas cuando es entera.
func TestCompletasTraeLosCamionesAnterioresALaMarca(t *testing.T) {
	ahora := time.Now().UTC()
	marca := ahora.Add(-time.Hour)
	q := nuevoEspejo()
	q.vehiculosDelEspejo = []sqlc.ListarVehiculosRow{
		{ID: vehVivo, VehicleTypeID: tipoStgTruck, BranchID: pgSuc(sucStg),
			UpdatedAt: pgtype.Timestamptz{Time: ahora.Add(-48 * time.Hour), Valid: true}},
	}
	q.bajas = []bajaSync{
		{sqlc.ColeccionDeLaBajadaVehicles, vehBorrado.String(), &sucStg, sqlc.MotivoDeBajaBorrado, ahora.Add(-30 * time.Minute)},
	}
	desde := "?desde=" + marca.Format(time.RFC3339Nano)
	santiago := tokenTab(t, sucStg.String())

	sin := bajadaDe(t, q, santiago, desde)
	if got := puestosDe(t, sin, "vehicles"); len(got) != 0 {
		t.Fatalf("la pareja está rota: sin `completas`, con un camión viejo, no podía venir nada: %v", got)
	}
	if !bajasDe(t, sin, "vehicles")[vehBorrado.String()] {
		t.Fatal("sin `completas` la lápida posterior a la marca tenía que salir")
	}

	con := bajadaDe(t, q, santiago, desde+"&completas=vehicles")
	got := puestosDe(t, con, "vehicles")
	if len(got) != 1 || got[vehVivo.String()]["vehicleTypeId"] != tipoStgTruck.String() {
		t.Fatalf("`completas=vehicles` tenía que traer el camión con sus campos nuevos: %v", got)
	}
	if quitados := bajasDe(t, con, "vehicles"); len(quitados) != 0 {
		t.Fatalf("pidiendo la lista entera no hay nada que quitar: %v", quitados)
	}
	if got := puestosDe(t, con, "vehicle_types"); len(got) != 0 {
		t.Fatalf("`completas=vehicles` ensanchó los tipos: %v", got)
	}
}
