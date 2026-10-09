package api

// EL TOKEN DE ENTREGA NO ENTRA POR `/api/*` — bandeja de revisión, paquete V
// (`docs/bandeja-de-revision.md`, B.1). La guarda vive en `auth.Verificador.Verificar`
// (`internal/auth/ambito_test.go` la prueba token a token); aquí se prueba con el ROUTER ENTERO,
// que es por donde se entra de verdad: `Exigir` (rutas normales), `/api/me` (que no da 403 y
// contesta quién es) y `/api/eventos` (que comprueba la sesión por su cuenta).

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func tokenDeEntregaParaLaAPI(t *testing.T, entradas []string) string {
	t.Helper()
	return tokenDeDatos(t, map[string]any{
		"sub": "p-stg", "name": "Yasmani", "email": "stg@procovar.cu", "sid": "ses-1",
		"sucursal": "STG", "branchId": avSucStg.String(), "purpose": "apk:entrega",
		"ambito": "reparto.entrega", "entradas": entradas, "roles": []string{}, "role": "",
		"jti": "j-1", "iat": time.Now().Unix(), "exp": time.Now().Add(10 * time.Minute).Unix(),
	})
}

func TestElTokenDeEntregaNoEntraPorLaApi(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	rutas := []struct{ metodo, ruta string }{
		{http.MethodGet, "/api/vehicles"},
		{http.MethodPost, "/api/vehicles"},
		{http.MethodGet, "/api/apps"},
		{http.MethodGet, "/api/eventos"},
		{http.MethodGet, "/api/me"},
	}
	tokens := map[string]string{
		"sin la llave": tokenDeEntregaParaLaAPI(t, []string{}),
		// LA PAREJA que importa: con `delivery.entrar` metida en `entradas` TAMBIÉN se rechaza.
		"CON delivery.entrar": tokenDeEntregaParaLaAPI(t, []string{"delivery.entrar"}),
	}
	for nombre, jwt := range tokens {
		for _, c := range rutas {
			// `/api/eventos` es un chorro que no termina: si el token ENTRARA, la prueba se colgaría
			// en vez de fallar. Con el contexto cortado a los 300 ms entra, se corta y el 200 canta.
			ctx, corta := context.WithTimeout(context.Background(), 300*time.Millisecond)
			r := httptest.NewRequest(c.metodo, c.ruta, nil).WithContext(ctx)
			r.Header.Set("Authorization", "Bearer "+jwt)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			corta()
			if w.Code != http.StatusUnauthorized {
				t.Errorf("%s %s con un token de entrega %s: código %d, tenía que ser 401: %s",
					c.metodo, c.ruta, nombre, w.Code, w.Body.String())
			}
			if c.ruta == "/api/me" && strings.Contains(w.Body.String(), jwt) {
				t.Errorf("/api/me devolvió el token de entrega")
			}
		}
	}

	// LA PAREJA DEL OTRO LADO: el token normal de la misma persona (sin `ambito`, con la llave) entra
	// por las mismas puertas. Una guarda que cierra de más es otra avería.
	normal := tokenDeDatos(t, map[string]any{"sub": "p-stg", "email": "stg@procovar.cu",
		"role": "LOGISTICO", "branchId": avSucStg.String(), "entradas": []string{"delivery.entrar"}})
	for _, ruta := range []string{"/api/me", "/api/apps"} {
		if w := pedirAv(t, h, http.MethodGet, ruta, normal, ""); w.Code != http.StatusOK {
			t.Errorf("GET %s con el token normal: código %d, tenía que ser 200: %s", ruta, w.Code, w.Body.String())
		}
	}
}
