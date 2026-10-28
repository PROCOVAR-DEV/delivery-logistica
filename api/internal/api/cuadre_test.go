package api

import (
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
)

// EL CUADRE DE LAS FACTURAS (28/10/2026): los ids de lo que una carga completa le bajaría al aparato, para que
// quite los fantasmas cuya lápida se perdió. Sin archivadas, sin las de otra sucursal, y siempre un array.
func TestElCuadreDaLosIdsDeLoQueElAparatoDebeTener(t *testing.T) {
	q := nuevoEspejo()
	ahora := time.Now().UTC()
	viva := pedidoSync{id: uuid.New(), sucursal: sucStg, nombre: "viva", marca: ahora}
	archivada := pedidoSync{id: uuid.New(), sucursal: sucStg, nombre: "archivada", archivado: true, marca: ahora}
	anulada := pedidoSync{id: uuid.New(), sucursal: sucStg, nombre: "anulada", archivado: true, marca: ahora,
		anuladaAt: &ahora}
	ajena := pedidoSync{id: uuid.New(), sucursal: sucHol, nombre: "ajena", marca: ahora}
	q.sync = append(q.sync, viva, archivada, anulada, ajena)

	h := montarTab(t, q)
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cuadre", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	hay := map[string]bool{}
	for _, id := range m["colecciones"].(map[string]any)["orders"].([]any) {
		hay[id.(string)] = true
	}
	if !hay[viva.id.String()] || !hay[anulada.id.String()] {
		t.Fatalf("faltan la viva o la anulada reciente: %v", hay)
	}
	if hay[archivada.id.String()] || hay[ajena.id.String()] {
		t.Fatalf("sobran la archivada o la de otra sucursal: %v", hay)
	}
	if tr, _ := m["truncado"].([]any); len(tr) != 0 {
		t.Fatalf("no se pasó del tope y dice truncado: %v", tr)
	}
	// TODAS las colecciones que guarda el aparato salen, cada una como array (nunca null).
	cols := m["colecciones"].(map[string]any)
	for _, c := range []string{"orders", "branches", "vehicles", "vehicle_types", "distribuidores", "routes", "products", "customers"} {
		if _, ok := cols[c].([]any); !ok {
			t.Errorf("falta la colección %q o no es un array: %#v", c, cols[c])
		}
	}
}

func TestElCuadreNuncaDaNullEnNingunaColeccion(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cuadre", tokenTab(t, sucStg.String()), "")
	m := leerTab(t, w)
	for nombre, v := range m["colecciones"].(map[string]any) {
		if _, ok := v.([]any); !ok {
			t.Fatalf("«%s» tenía que ser un array y fue %#v: el aparato no recorre un null", nombre, v)
		}
	}
}
