package api_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// EN QUÉ ANDA CADA CAMIÓN — 28/09/2026
// ---------------------------------------------------------------------------
//
// Jose: «si la idea es q salga el vehiculo y ese vehiculo se ponga su estado para q saber
// como anda ese vehiculo y saber de la flota».
//
// La pantalla de Vehículos ya tenía una caja azul «Ruta activa» —estaba escrita en
// `tarjeta_vehiculo.dart` desde el principio— y **no salía nunca**, porque este endpoint no
// servía el campo `routes` que ella lee. Así que un camión podía estar rodando y su tarjeta
// no lo decía por ningún sitio.
//
// LAS PRUEBAS VAN EN PAREJA, como todo aviso de esta casa: que el camión OCUPADO lo diga, y
// que el LIBRE **no** lo diga. Sin la segunda, servir siempre la misma ruta para todos
// dejaría esto en verde y la pantalla contando que los ocho camiones están fuera.

func rutaAbierta(camion uuid.UUID, codigo, estado string) sqlc.RutasAbiertasDeLaFlotaRow {
	return sqlc.RutasAbiertasDeLaFlotaRow{
		VehicleID: pgtype.UUID{Bytes: [16]byte(camion), Valid: true},
		ID:        uuid.New(),
		RouteCode: &codigo,
		Status:    sqlc.RouteStatus(estado),
	}
}

// deLaLista: el camión que se llama así, de `GET /api/vehicles`.
func deLaLista(t *testing.T, cuerpo []byte, nombre string) map[string]any {
	t.Helper()
	var lista []map[string]any
	if err := json.Unmarshal(cuerpo, &lista); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	for _, v := range lista {
		if v["name"] == nombre {
			return v
		}
	}
	t.Fatalf("no sale el camión %q: %s", nombre, cuerpo)
	return nil
}

// EL CAMIÓN QUE ESTÁ FUERA LO DICE, con su ruta y con el estado de esa ruta.
func TestElCamionConRutaAbiertaDiceEnQueAnda(t *testing.T) {
	h := servidorCon(t, []sqlc.RutasAbiertasDeLaFlotaRow{
		rutaAbierta(vehStg, "RT-20260928-001", "in_progress"),
	})
	jwt := token(t, map[string]any{"sub": "p-1", "role": "SUPER ADMIN"})

	w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	rutas, _ := deLaLista(t, w.Body.Bytes(), "Camión de Santiago")["routes"].([]any)
	if len(rutas) != 1 {
		t.Fatalf("el camión de Santiago está en `RT-20260928-001` y su tarjeta no lo dice: "+
			"%s", w.Body.String())
	}
	r, _ := rutas[0].(map[string]any)
	if r["routeCode"] != "RT-20260928-001" {
		t.Errorf("no viaja el código de la ruta: %v", r)
	}
	// EL ESTADO DE LA RUTA, que es lo que separa «está fuera» de «lo tiene cogido para
	// mañana». Sin él, la pantalla sólo puede decir «ocupado» y las dos cosas se ven
	// iguales.
	if r["status"] != "in_progress" {
		t.Errorf("no viaja el estado de la ruta, y `planned` e `in_progress` son dos "+
			"respuestas distintas a «¿está libre?»: %v", r)
	}
}

// Y EL QUE NO TIENE NINGUNA, TAMPOCO LO DICE. Ésta es la mitad que caza servir la misma
// ruta para todos.
func TestElCamionLibreNoSaleConRuta(t *testing.T) {
	h := servidorCon(t, []sqlc.RutasAbiertasDeLaFlotaRow{
		rutaAbierta(vehStg, "RT-20260928-001", "in_progress"),
	})
	jwt := token(t, map[string]any{"sub": "p-1", "role": "SUPER ADMIN"})

	w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, nil)
	libre := deLaLista(t, w.Body.Bytes(), "Camión de Holguín")

	rutas, esLista := libre["routes"].([]any)
	if !esLista {
		// `[]` Y NO `null`. Son dos formas del mismo vacío y obligan a cada cliente a
		// distinguirlas; el de Flutter lee `(j['routes'] as List?) ?? const []`, pero el
		// siguiente que llegue no tiene por qué.
		t.Fatalf("`routes` no vino como lista en un camión libre: %v", libre["routes"])
	}
	if len(rutas) != 0 {
		t.Fatalf("el camión de Holguín está libre y su tarjeta dice que anda en algo: %v",
			rutas)
	}
}

// LA FLOTA ENTERA SIN NINGUNA RUTA ABIERTA: los tres salen, y los tres libres.
//
// Un `INNER JOIN` en vez del `LEFT` habría escondido justo los camiones que se pueden usar,
// que es lo contrario de lo que pide «saber qué hay libre».
func TestSinRutasAbiertasLaFlotaSigueSaliendoEntera(t *testing.T) {
	h := servidorCon(t, nil)
	jwt := token(t, map[string]any{"sub": "p-1", "role": "SUPER ADMIN"})

	w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, nil)
	var lista []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &lista); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(lista) != 3 {
		t.Fatalf("la flota son 3 y salieron %d: %s", len(lista), w.Body.String())
	}
	for _, v := range lista {
		if rutas, _ := v["routes"].([]any); len(rutas) != 0 {
			t.Errorf("%v sale con ruta sin haber ninguna abierta: %v", v["name"], rutas)
		}
	}
}
