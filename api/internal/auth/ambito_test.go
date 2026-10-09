package auth_test

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"procovar/reparto-api/internal/auth"
)

// UN TOKEN DE ENTREGA NO ENTRA POR `/api/*` — bandeja de revisión, paquete V
// (`docs/bandeja-de-revision.md`, B.1).
//
// Accesos firma, con el mismo `JWT_SECRET`, un token restringido para quien perdió
// `delivery.entrar` y tiene cola que entregar: `ambito:"reparto.entrega"`, `entradas:[]`, sin
// roles. Solo abre las dos rutas de entrega de `sync`. Aquí, `Verificar` rechaza TODO token que
// traiga `ambito`, y lo rechaza AUNQUE alguien le hubiera metido `delivery.entrar` en `entradas`.
// Sin esta guarda, esa llave lo convertiría en una sesión normal que aplicaría gestos con la
// autoridad de la persona, saltándose la revisión.

// elTokenDeEntrega: los claims de B.1, tal como los firma Accesos.
func elTokenDeEntrega() map[string]any {
	return map[string]any{
		"sub": "p-yasmani", "name": "Yasmani", "email": "yasmani@procovar.cu", "sid": "ses-1",
		"sucursal": "STG", "branch_id": "STG", "purpose": "apk:entrega",
		"ambito": "reparto.entrega", "entradas": []string{}, "roles": []string{}, "role": "",
		"jti": "j-1", "iat": time.Now().Unix(), "exp": time.Now().Add(10 * time.Minute).Unix(),
	}
}

func conCampo(base map[string]any, clave string, valor any) map[string]any {
	salida := map[string]any{}
	for k, v := range base {
		salida[k] = v
	}
	salida[clave] = valor
	return salida
}

func TestUnTokenConAmbitoNoEntra(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	casos := []struct {
		nombre string
		claims map[string]any
	}{
		{"el token de entrega tal cual", elTokenDeEntrega()},
		// LA PAREJA que importa: con la llave puesta TAMBIÉN se rechaza.
		{"el de entrega con delivery.entrar en entradas", conCampo(elTokenDeEntrega(), "entradas", []string{"delivery.entrar"})},
		{"el de entrega con la llave y un rol que entra",
			conCampo(conCampo(elTokenDeEntrega(), "entradas", []string{"delivery.entrar"}), "role", "SUPER ADMIN")},
		{"con la llave y roles que entran", conCampo(conCampo(elTokenDeEntrega(), "entradas", []string{"pedido.entrar", "delivery.entrar"}),
			"roles", []string{"ADMINISTRADOR", "LOGISTICO"})},
		{"sin entradas y con un rol que entra (la caída por roles)", func() map[string]any {
			c := conCampo(elTokenDeEntrega(), "role", "LOGISTICO")
			delete(c, "entradas")
			return c
		}()},
		// Basta con que el campo VENGA, sea lo que sea.
		{"ambito vacío", conCampo(elTokenDeEntrega(), "ambito", "")},
		{"ambito null", conCampo(elTokenDeEntrega(), "ambito", nil)},
		{"ambito otro texto", conCampo(elTokenDeEntrega(), "ambito", "reparto.otra-cosa")},
		{"ambito un array", conCampo(elTokenDeEntrega(), "ambito", []string{})},
		{"ambito un número", conCampo(elTokenDeEntrega(), "ambito", 0)},
		{"ambito false", conCampo(elTokenDeEntrega(), "ambito", false)},
		{"ambito un objeto", conCampo(elTokenDeEntrega(), "ambito", map[string]any{})},
		// El decodificador de Go casa las claves sin distinguir mayúsculas; el token no puede
		// colarse escribiendo «Ambito».
		{"Ambito con mayúscula", func() map[string]any {
			c := elTokenDeEntrega()
			delete(c, "ambito")
			c["Ambito"] = "reparto.entrega"
			return c
		}()},
		// Un campo suelto con otro tipo manda el decodificador por su camino de reintento: el
		// ámbito no se pierde por ahí.
		{"camino de reintento (name numérico)", conCampo(elTokenDeEntrega(), "name", 7)},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			u, err := v.Verificar(firmar(t, "HS256", c.claims))
			if err == nil {
				t.Fatalf("un token con ambito ENTRÓ como %+v", u)
			}
			if !errors.Is(err, auth.ErrAmbito) {
				t.Fatalf("se rechazó, pero por otra razón (no ErrAmbito): %v", err)
			}
		})
	}
}

// LA PAREJA: sin `ambito` los tokens de siempre siguen entrando, con y sin la llave. Una guarda
// que rechaza de más es otra avería: Accesos firma estos mismos claims para la APK y la web.
func TestUnTokenSinAmbitoSigueEntrando(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	normal := map[string]any{
		"sub": "p-1", "name": "Ana", "email": "ana@procovar.cu", "sid": "ses-1", "sucursal": "STG",
		"branch_id": "STG", "role": "LOGISTICO", "roles": []string{"LOGISTICO"},
		"entradas": []string{"delivery.entrar"}, "jti": "j-2",
		"iat": time.Now().Unix(), "exp": time.Now().Add(15 * time.Minute).Unix(),
	}
	casos := []struct {
		nombre string
		claims map[string]any
		entra  bool
	}{
		{"el normal de la APK, con la llave", normal, true},
		{"el normal sin la llave (entra el token, no a Reparto)", conCampo(normal, "entradas", []string{}), false},
		{"el de la web", map[string]any{"id": "web-1", "role": "SUPER ADMIN", "branchId": "", "web": true,
			"entradas": []string{"delivery.entrar"}, "iatms": time.Now().UnixMilli()}, true},
		{"el de siempre, sin `entradas` ni `ambito`", map[string]any{"sub": "p-3", "role": "GERENTE"}, false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			u, err := v.Verificar(firmar(t, "HS256", c.claims))
			if err != nil {
				t.Fatalf("un token SIN ambito se rechazó: %v", err)
			}
			if got := u.PuedeEntrarAReparto(); got != c.entra {
				t.Fatalf("PuedeEntrarAReparto() = %v, se esperaba %v", got, c.entra)
			}
		})
	}
}

// El camino HTTP completo: `Exigir` contesta el 401 de siempre —sin decir por qué— y la ruta no se
// ejecuta. (`sync` contesta 403 `sin_permiso_reparto` al mismo token; los casos compartidos solo
// atan que NO entra, no el código.)
func TestExigirNoDejaPasarUnTokenDeEntrega(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	llamadas := 0
	h := v.Exigir(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		llamadas++
		w.WriteHeader(http.StatusOK)
	}))
	pedir := func(jwt string, cookies ...string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodGet, "/api/orders", nil)
		if jwt != "" {
			r.Header.Set("Authorization", "Bearer "+jwt)
		}
		for _, c := range cookies {
			r.AddCookie(&http.Cookie{Name: auth.NombreDeLaCookie, Value: c})
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}

	entrega := firmar(t, "HS256", elTokenDeEntrega())
	conLlave := firmar(t, "HS256", conCampo(elTokenDeEntrega(), "entradas", []string{"delivery.entrar"}))
	for nombre, jwt := range map[string]string{"sin la llave": entrega, "CON la llave": conLlave} {
		for via, w := range map[string]*httptest.ResponseRecorder{"cabecera": pedir(jwt), "cookie": pedir("", jwt)} {
			if w.Code != http.StatusUnauthorized {
				t.Errorf("token de entrega %s por %s: %d %s, tenía que ser 401", nombre, via, w.Code, w.Body.String())
			}
		}
	}
	if llamadas != 0 {
		t.Fatalf("la ruta se ejecutó %d veces con un token de entrega", llamadas)
	}

	// LA PAREJA: una credencial buena en la misma petición SÍ entra (se prueban todas las
	// candidatas, ver `DelaPeticion`), así que el token de entrega no echa a quien ya tiene sesión.
	buena := firmar(t, "HS256", map[string]any{"sub": "p-1", "role": "LOGISTICO", "branchId": "s-1",
		"entradas": []string{"delivery.entrar"}})
	if w := pedir(conLlave, buena); w.Code != http.StatusOK {
		t.Errorf("cookie buena + Bearer de entrega: código %d, tenía que ser 200", w.Code)
	}
	if w := pedir(buena); w.Code != http.StatusOK {
		t.Errorf("el token normal: código %d, tenía que ser 200", w.Code)
	}
}
