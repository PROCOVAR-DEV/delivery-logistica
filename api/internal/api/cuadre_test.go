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
	for _, id := range m["ids"].([]any) {
		hay[id.(string)] = true
	}
	if !hay[viva.id.String()] || !hay[anulada.id.String()] {
		t.Fatalf("faltan la viva o la anulada reciente: %v", hay)
	}
	if hay[archivada.id.String()] || hay[ajena.id.String()] {
		t.Fatalf("sobran la archivada o la de otra sucursal: %v", hay)
	}
	if tr, _ := m["truncado"].(bool); tr {
		t.Fatal("no se pasó del tope y dice truncado")
	}
}

func TestElCuadreSinNadaDaUnArrayVacioNoNull(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cuadre", tokenTab(t, sucStg.String()), "")
	m := leerTab(t, w)
	if ids, ok := m["ids"].([]any); !ok || len(ids) != 0 {
		t.Fatalf("«ids» tenía que ser [] y fue %#v: el aparato no recorre un null", m["ids"])
	}
}
