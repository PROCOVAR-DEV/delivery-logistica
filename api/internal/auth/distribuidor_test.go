package auth_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/auth"
)

// EL DISTRIBUIDOR SOLO HACE LO SUYO (04/11/2026). La llave `delivery.entrar` no distingue roles, así que la API lo distingue: lista blanca
// por método y ruta, y lo que no está es un 403. Estas pruebas son el cierre: una ruta nueva de la API NO aparece aquí y por tanto nace cerrada.

func TestListaBlancaDelDistribuidor(t *testing.T) {
	id := uuid.NewString()
	permitidas := []struct{ metodo, ruta string }{
		{"GET", "/api/sync/cambios"}, {"GET", "/api/sync/cuadre"}, {"GET", "/api/almacenes"},
		{"GET", "/api/routes"}, {"GET", "/api/routes/" + id},
		{"POST", "/api/routes/" + id + "/results"}, {"PATCH", "/api/routes/" + id}, {"POST", "/api/track"},
		{"GET", "/api/routes/"}, // la barra final no cambia nada
	}
	for _, p := range permitidas {
		if !auth.PermitidoAlDistribuidor(p.metodo, p.ruta) {
			t.Errorf("%s %s tenía que estar permitida", p.metodo, p.ruta)
		}
	}
	prohibidas := []struct{ metodo, ruta string }{
		{"POST", "/api/routes"},                 // armar rutas
		{"DELETE", "/api/routes/" + id},         // borrar
		{"PUT", "/api/routes/" + id + "/stops"}, // reordenar
		{"GET", "/api/orders"}, {"PATCH", "/api/orders/" + id}, {"DELETE", "/api/orders/" + id},
		{"GET", "/api/customers"}, {"GET", "/api/vehicles"}, {"POST", "/api/vehicles"}, {"GET", "/api/distribuidores"},
		{"PUT", "/api/settings"}, {"GET", "/api/settings"}, {"GET", "/api/board"}, {"POST", "/api/conduces"},
		{"GET", "/api/routes/" + id + "/track"}, // el seguimiento NO lo ve el distribuidor
		{"GET", "/api/track"}, {"GET", "/api/eventos"},
		{"GET", "/api/routes/no-es-un-uuid"}, // un id que no es uuid no pasa por «una ruta suya»
		{"POST", "/api/routes/" + id + "/results/x"},
		{"GET", "/health"}, {"GET", ""}, {"GET", "/"},
		{"GET", "/api/routes/" + id + "/../orders"},
	}
	for _, p := range prohibidas {
		if auth.PermitidoAlDistribuidor(p.metodo, p.ruta) {
			t.Errorf("%s %s NO tenía que estar permitida", p.metodo, p.ruta)
		}
	}
}

// El camino HTTP completo por `Exigir`: el distribuidor pasa en lo suyo, recibe el 403 con su marca en lo demás, y quien NO es distribuidor
// no se entera de la lista blanca.
func TestExigirCierraAlDistribuidor(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	llamadas := 0
	h := v.Exigir(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		llamadas++
		w.WriteHeader(http.StatusOK)
	}))
	pedir := func(jwt, metodo, ruta string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(metodo, ruta, nil)
		r.Header.Set("Authorization", "Bearer "+jwt)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	llave := []string{"delivery.entrar"}
	dist := firmar(t, "HS256", map[string]any{"sub": "p-dist", "role": "DISTRIBUIDOR", "branchId": "HAB", "entradas": llave})
	logi := firmar(t, "HS256", map[string]any{"sub": "p-logi", "role": "LOGISTICO", "branchId": "HAB", "entradas": llave})
	ambos := firmar(t, "HS256", map[string]any{"sub": "p-ambos", "role": "LOGISTICO", "roles": []string{"DISTRIBUIDOR"}, "branchId": "HAB", "entradas": llave})
	id := uuid.NewString()

	if w := pedir(dist, "GET", "/api/routes"); w.Code != http.StatusOK {
		t.Fatalf("el distribuidor en lo suyo: %d %s", w.Code, w.Body.String())
	}
	antes := llamadas
	for _, c := range []struct{ metodo, ruta string }{{"GET", "/api/orders"}, {"DELETE", "/api/routes/" + id}, {"GET", "/api/vehicles"}, {"POST", "/api/routes"}} {
		w := pedir(dist, c.metodo, c.ruta)
		if w.Code != http.StatusForbidden || !contiene(w.Body.String(), auth.CodigoNoEsParaElDistribuidor) {
			t.Errorf("%s %s: %d %s, tenía que ser 403 con su marca", c.metodo, c.ruta, w.Code, w.Body.String())
		}
	}
	if llamadas != antes {
		t.Fatalf("la ruta prohibida se ejecutó %d veces", llamadas-antes)
	}

	// el logístico sigue entrando a todo
	if w := pedir(logi, "GET", "/api/orders"); w.Code != http.StatusOK {
		t.Fatalf("el logístico en /api/orders: %d", w.Code)
	}
	// y quien lleva LOS DOS roles queda restringido (falla cerrado)
	if w := pedir(ambos, "GET", "/api/orders"); w.Code != http.StatusForbidden {
		t.Fatalf("con los dos roles tenía que quedar restringido: %d", w.Code)
	}
}

func contiene(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
