package identidad

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// EL DISTRIBUIDOR SOLO SUBE SU COLA (04/11/2026): gemela de `reparto-api/internal/auth/distribuidor_test.go`.
func TestElDistribuidorSoloDaDeAltaYSubeSuCola(t *testing.T) {
	llamadas := 0
	h := func(roles ...string) http.Handler {
		return Exigir(func(*http.Request) (Identidad, error) { return Identidad{Persona: "p-1", Roles: roles}, nil },
			http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { llamadas++; w.WriteHeader(http.StatusOK) }))
	}
	pedir := func(h http.Handler, metodo, ruta string) int {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(metodo, ruta, nil))
		return w.Code
	}
	dist := h("DISTRIBUIDOR")
	for _, c := range []struct{ metodo, ruta string }{{"POST", "/sync/aparato"}, {"POST", "/sync/subida"}} {
		if got := pedir(dist, c.metodo, c.ruta); got != http.StatusOK {
			t.Errorf("%s %s: %d, tenía que entrar", c.metodo, c.ruta, got)
		}
	}
	antes := llamadas
	for _, c := range []struct{ metodo, ruta string }{
		{"GET", "/sync/estado"}, {"GET", "/sync/bajada"}, {"GET", "/sync/revision"}, {"POST", "/sync/revision/entrega"},
		{"POST", "/sync/revision/x/y/aplicar"}, {"GET", "/sync/subida"},
	} {
		if got := pedir(dist, c.metodo, c.ruta); got != http.StatusForbidden {
			t.Errorf("%s %s: %d, tenía que ser 403", c.metodo, c.ruta, got)
		}
	}
	if llamadas != antes {
		t.Fatalf("algo prohibido llegó al manejador (%d veces)", llamadas-antes)
	}
	// la oficina sigue entrando a todo, y quien lleva los dos roles queda restringido
	if got := pedir(h("LOGISTICO"), "GET", "/sync/estado"); got != http.StatusOK {
		t.Errorf("el logístico en /sync/estado: %d", got)
	}
	if got := pedir(h("LOGISTICO", "DISTRIBUIDOR"), "GET", "/sync/estado"); got != http.StatusForbidden {
		t.Errorf("con los dos roles tenía que quedar restringido: %d", got)
	}
}
