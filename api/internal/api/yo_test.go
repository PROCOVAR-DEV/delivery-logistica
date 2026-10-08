package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// El 401 de /api/me es `{"user":null}` y NO el {"error":...} de todas las demás. La web
// arranca preguntando aquí si tiene sesión: con el cuerpo de siempre no podría distinguir
// «no has entrado» de «se rompió algo», y las dos llevan a sitios distintos.
func TestYoSinSesionDevuelveUsuarioNulo(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	w := pedirDePanel(t, h, "/api/me", "")

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d, se esperaba 401", w.Code)
	}
	var cuerpo map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &cuerpo); err != nil {
		t.Fatalf("la respuesta no es JSON: %v", err)
	}
	if v, hay := cuerpo["user"]; !hay || v != nil {
		t.Errorf("el cuerpo es %s, se esperaba {\"user\":null}", w.Body.String())
	}
	if _, hay := cuerpo["error"]; hay {
		t.Errorf("el 401 de /api/me no lleva «error»: %s", w.Body.String())
	}
}

func TestYoDevuelveLaPersonaYElTokenDeLaCookie(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	jwt := tokenDePanel(t, map[string]any{
		"sub": "u-1", "email": "ana@procovar.cloud", "name": "Ana",
		"role": "operador", "branchId": holDePanel.String(),
	})

	r := httptest.NewRequest(http.MethodGet, "/api/me", nil)
	r.AddCookie(&http.Cookie{Name: "token", Value: jwt})
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	y := leerJSONDePanel[YoSalida](t, w)
	if y.User == nil {
		t.Fatal("no vino usuario")
	}
	if y.User.ID != "u-1" || y.User.Email != "ana@procovar.cloud" || y.User.Name != "Ana" || y.User.Role != "operador" {
		t.Errorf("la persona es %+v", *y.User)
	}
	if y.User.BranchID == nil || *y.User.BranchID != holDePanel.String() {
		t.Errorf("la sucursal es %v", y.User.BranchID)
	}
	// El token se devuelve para que la web, cuya cookie es httpOnly, pueda llamar con
	// `Authorization: Bearer`.
	if y.Token == nil || *y.Token != jwt {
		t.Error("no devolvió el token de la cookie")
	}
}

// Con Bearer y sin cookie, `token` es null: quien preguntó ya tiene el suyo, y devolverlo
// no añade nada.
func TestYoConBearerNoDevuelveToken(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	w := pedirDePanel(t, h, "/api/me", tokenDePanel(t, map[string]any{"sub": "super", "role": "SUPER ADMIN"}))

	y := leerJSONDePanel[YoSalida](t, w)
	if y.Token != nil {
		t.Errorf("devolvió un token que no salía de la cookie: %v", *y.Token)
	}
	// El Super Admin no pertenece a ninguna sucursal: null, no "". Una cadena vacía
	// acabaría viajando en `X-Sucursal-Id` como si fuera una sucursal elegida.
	if y.User == nil || y.User.BranchID != nil {
		t.Errorf("la sucursal del Super Admin tiene que ser null, es %v", y.User.BranchID)
	}
}

// «Accesos» sólo la ve el administrador GLOBAL: el que es admin y no pertenece a ninguna
// sucursal. Un administrador de sucursal manda en lo suyo, no en las cuentas de todos.
func TestAppsSoloEnseñaAccesosAlAdminGlobal(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})

	casos := []struct {
		nombre   string
		reclamos map[string]any
		accesos  bool
	}{
		{"admin global", map[string]any{"sub": "s", "role": "SUPER ADMIN"}, true},
		{"admin de sucursal", map[string]any{"sub": "a", "role": "ADMINISTRADOR", "branchId": holDePanel.String()}, false},
		{"logistico", map[string]any{"sub": "o", "role": "LOGISTICO", "branchId": holDePanel.String()}, false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			w := pedirDePanel(t, h, "/api/apps", tokenDePanel(t, c.reclamos))
			if w.Code != http.StatusOK {
				t.Fatalf("código %d: %s", w.Code, w.Body.String())
			}
			var cuerpo struct {
				Apps []AppSalida `json:"apps"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &cuerpo); err != nil {
				t.Fatal(err)
			}
			esperadas := 8
			if c.accesos {
				esperadas = 9
			}
			if len(cuerpo.Apps) != esperadas {
				t.Fatalf("salieron %d aplicaciones, se esperaban %d", len(cuerpo.Apps), esperadas)
			}
			hayAccesos := false
			for _, a := range cuerpo.Apps {
				if a.Title == "Accesos" {
					hayAccesos = true
				}
			}
			if hayAccesos != c.accesos {
				t.Errorf("Accesos presente = %v, se esperaba %v", hayAccesos, c.accesos)
			}
			// `soloAdmin` no se devuelve: decirle a quien no puede entrar que existe una
			// puerta y que es de administración ya es media pista.
			if bytes := w.Body.String(); contieneDeInforme(bytes, "soloAdmin") {
				t.Error("la respuesta filtra el campo soloAdmin")
			}
			// El orden y el contenido son los del contrato.
			if cuerpo.Apps[0].Title != "PEDIDO" || cuerpo.Apps[0].Href != "https://pedidos.procovar.cloud" {
				t.Errorf("la primera aplicación es %+v", cuerpo.Apps[0])
			}
			if cuerpo.Apps[0].Description != "Pedidos, clientes y vendedores." {
				t.Errorf("la descripción de PEDIDO es %q", cuerpo.Apps[0].Description)
			}
		})
	}
}

func TestAppsSinSesionEs401(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	w := pedirDePanel(t, h, "/api/apps", "")
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d, se esperaba 401", w.Code)
	}
}

// /api/apps no toca la base: ni una consulta, ni el alcance. Es la primera pantalla que se
// abre y no puede costar una ida y vuelta a Postgres para resolver una sucursal que nadie
// va a usar.
func TestAppsNoConsultaNada(t *testing.T) {
	q := &dobleDePanel{}
	h := montarDePanel(t, q)
	pedirDePanel(t, h, "/api/apps", tokenDePanel(t, map[string]any{"sub": "u1", "role": "LOGISTICO", "branchId": holDePanel.String()}))

	if len(q.sucursalVista) != 0 {
		t.Errorf("/api/apps hizo %d consultas acotadas: no tiene que hacer ninguna", len(q.sucursalVista))
	}
	if q.resoluciones != 0 {
		t.Errorf("/api/apps resolvió la sucursal %d veces: no monta el alcance, así que no debería", q.resoluciones)
	}
}
