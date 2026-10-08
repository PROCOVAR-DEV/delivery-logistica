package api_test

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/api"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
)

// SÓLO CUATRO ROLES ENTRAN A REPARTO — Jose, 08/10/2026:
//
//	«esos roles son los únicos que pueden entrar a Reparto; a los otros, que Reparto les
//	diga no tienes permiso y se dirijan a Accesos, a su inicio»
//
// SUPER ADMIN, DESARROLLADOR, ADMINISTRADOR y LOGISTICO. Estas pruebas van por HTTP, con token
// de verdad y por el router entero (`Rutas()`), porque el control está en el montaje
// (`Verificador.Exigir`) y es ahí donde se pierde: una prueba sobre `PuedeEntrarAReparto` sola
// sigue verde con la guarda quitada del router.

const (
	cuerpoSinPermiso = `{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}`

	// El servicio, el espejo y el webhook de PEDIDO NO son personas: entran con llave.
	llaveDeServicioDeReparto = "llave-de-servicio-del-control-de-reparto"
	claveDelWebhookDeReparto = "rp_clave_del_control_de_reparto"
	secretoDelWebhook        = "secreto-del-webhook-del-control-de-reparto"
)

// montarConRegistro: el montaje de `servidorCon`, con el registro en un búfer para poder leer
// qué se escribió, y con las tres llaves de servicio puestas.
func montarConRegistro(t *testing.T) (http.Handler, *bytes.Buffer) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secreto)
	t.Setenv("SERVICE_API_KEY", llaveDeServicioDeReparto)
	t.Setenv("PEDIDO_WEBHOOK_KEY", claveDelWebhookDeReparto)
	t.Setenv("PEDIDO_WEBHOOK_SECRET", secretoDelWebhook)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	q := &doble{}
	var registro bytes.Buffer
	reg := slog.New(slog.NewTextHandler(&registro, nil))
	return api.NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuente{q: q}, reg),
		auth.NuevoVerificador([]byte(secreto)),
		func(context.Context) error { return nil },
	).Rutas(), &registro
}

func conCookie(metodo, ruta, jwt string) *http.Request {
	r := httptest.NewRequest(metodo, ruta, nil)
	r.AddCookie(&http.Cookie{Name: "token", Value: jwt})
	return r
}

func conBearer(metodo, ruta, jwt string) *http.Request {
	r := httptest.NewRequest(metodo, ruta, nil)
	r.Header.Set("Authorization", "Bearer "+jwt)
	return r
}

func servir(h http.Handler, r *http.Request) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

// LOS CUATRO ENTRAN, y la otra mitad de la prueba de abajo: sin ella, «los demás no entran» se
// cumple con la puerta cerrada a todo el mundo.
func TestLosCuatroRolesDeRepartoEntran(t *testing.T) {
	h, _ := montarConRegistro(t)
	casos := []struct {
		rol      string
		sucursal any // nil = sin sucursal (los dos que ven las ocho)
	}{
		{"SUPER ADMIN", nil},
		{"DESARROLLADOR", nil},
		{"ADMINISTRADOR", stg.String()},
		{"LOGISTICO", stg.String()},
		// El `admin` de la web vieja sigue entrando (puente, ver `rolAdminHeredado`).
		{"admin", nil},
	}
	for _, c := range casos {
		t.Run(c.rol, func(t *testing.T) {
			jwt := token(t, map[string]any{"sub": "p-1", "role": c.rol, "branchId": c.sucursal})
			if w := servir(h, conBearer(http.MethodGet, "/api/vehicles", jwt)); w.Code != http.StatusOK {
				t.Fatalf("%s no entró a Reparto: %d %s", c.rol, w.Code, w.Body.String())
			}
		})
	}
}

// LOS DEMÁS NO: el mismo 403 con el mismo cuerpo, en minúscula y en mayúscula, con sucursal
// puesta (para que no pueda ser el alcance quien lo diga) y con rol que no conocemos.
func TestLosDemasRolesRecibenNoTienesPermiso(t *testing.T) {
	h, _ := montarConRegistro(t)
	roles := []string{
		"GERENTE", "SUPERVISOR", "GESTOR", "OPERADOR", "ECONOMICA", "ANALISTA",
		"DESCONOCIDO", "LOGISTICA", // la errata de LOGISTICO NO entra
		"SUPER_ADMIN", "ADMINISTRADORA", // ni «se parece» a uno que entra
		// El plegado Unicode de `strings.EqualFold` (auditoría, 08/10/2026): 'ſ' (U+017F) casa
		// con 's' y 'İ' (U+0130) se parece a 'I'. Son otro texto, no el rol.
		"ſUPER ADMIN", "ADMINIſTRADOR", "ADMİNİSTRADOR", "LOGİSTICO",
		"", // sin rol
	}
	for _, rol := range roles {
		t.Run("rol="+rol, func(t *testing.T) {
			jwt := token(t, map[string]any{"sub": "p-1", "role": rol, "branchId": stg.String()})
			w := servir(h, conBearer(http.MethodGet, "/api/vehicles", jwt))
			if w.Code != http.StatusForbidden {
				t.Fatalf("%q entró o se rechazó mal: %d %s", rol, w.Code, w.Body.String())
			}
			if got := strings.TrimSpace(w.Body.String()); got != cuerpoSinPermiso {
				t.Fatalf("cuerpo %q, se esperaba %q", got, cuerpoSinPermiso)
			}
			if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
				t.Errorf("Content-Type %q, se esperaba JSON", ct)
			}
		})
	}
}

// Un token con DOS roles entra si CUALQUIERA es de Reparto, esté en `role` o sólo en `roles`.
func TestUnTokenConDosRolesEntraSiUnoEsDeReparto(t *testing.T) {
	h, _ := montarConRegistro(t)
	casos := []struct {
		nombre  string
		rec     map[string]any
		entra   bool
		porQue  string
		sinRole bool
	}{
		{"sólo en roles (como firma Accesos a quien no trae role)",
			map[string]any{"roles": []string{"GERENTE", "LOGISTICO"}}, true, "LOGISTICO va en roles", true},
		{"role de reparto y roles de otra cosa",
			map[string]any{"role": "LOGISTICO", "roles": []string{"GERENTE"}}, true, "role vale", false},
		{"role de otra cosa y roles de reparto",
			map[string]any{"role": "GERENTE", "roles": []string{"GERENTE", "ADMINISTRADOR"}}, true, "ADMINISTRADOR va en roles", false},
		{"dos roles y ninguno de reparto",
			map[string]any{"role": "GERENTE", "roles": []string{"GERENTE", "OPERADOR"}}, false, "ninguno es de reparto", false},
		{"roles vacío y sin role",
			map[string]any{"roles": []string{}}, false, "no hay rol", true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			c.rec["sub"] = "p-1"
			c.rec["branchId"] = stg.String()
			w := servir(h, conBearer(http.MethodGet, "/api/vehicles", token(t, c.rec)))
			if c.entra && w.Code != http.StatusOK {
				t.Fatalf("tenía que entrar (%s): %d %s", c.porQue, w.Code, w.Body.String())
			}
			if !c.entra && (w.Code != http.StatusForbidden || strings.TrimSpace(w.Body.String()) != cuerpoSinPermiso) {
				t.Fatalf("tenía que rechazarse (%s): %d %s", c.porQue, w.Code, w.Body.String())
			}
		})
	}
}

// LAS TRES VÍAS CONTESTAN LO MISMO: la cabecera de la APK y el escritorio, la cookie de la web
// y el canal en vivo (que no pasa por `Exigir` y comprueba la sesión por su cuenta).
func TestLasTresViasDevuelvenElMismo403(t *testing.T) {
	h, _ := montarConRegistro(t)
	jwt := token(t, map[string]any{"sub": "p-1", "role": "GERENTE", "branchId": stg.String()})

	vias := map[string]*http.Request{
		"bearer (APK y escritorio)":              conBearer(http.MethodGet, "/api/vehicles", jwt),
		"cookie (web)":                           conCookie(http.MethodGet, "/api/vehicles", jwt),
		"SSE con bearer":                         conBearer(http.MethodGet, "/api/eventos", jwt),
		"SSE con cookie (EventSource de la web)": conCookie(http.MethodGet, "/api/eventos", jwt),
	}
	for nombre, r := range vias {
		t.Run(nombre, func(t *testing.T) {
			// Con plazo: si alguien quita el control del canal en vivo, la petición se
			// abre de verdad y sin esto la prueba se CUELGA en vez de fallar.
			ctx, cancelar := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancelar()
			w := servir(h, r.WithContext(ctx))
			if w.Code != http.StatusForbidden {
				t.Fatalf("código %d: %s", w.Code, w.Body.String())
			}
			if got := strings.TrimSpace(w.Body.String()); got != cuerpoSinPermiso {
				t.Fatalf("cuerpo %q, se esperaba %q", got, cuerpoSinPermiso)
			}
		})
	}
}

// EL TOKEN NO SALE: ni en el cuerpo, ni en el registro, ni sus tres trozos. El registro dice
// QUIÉN (rol, sucursal, persona) y DÓNDE (ruta), que es lo que hace falta para contestar «¿por
// qué no entra Pedro?» — y nada de la credencial: un registro acaba pegado en un chat.
func TestElTokenNoSaleNiEnElCuerpoNiEnElRegistro(t *testing.T) {
	h, registro := montarConRegistro(t)
	jwt := token(t, map[string]any{
		"sub": "p-gerente", "email": "gerente@procovar.cu", "role": "GERENTE",
		"roles": []string{"GERENTE", "OPERADOR"}, "branchId": stg.String(),
	})
	w := servir(h, conBearer(http.MethodGet, "/api/vehicles", jwt))
	if w.Code != http.StatusForbidden {
		t.Fatalf("código %d", w.Code)
	}

	linea := ""
	for _, l := range strings.Split(registro.String(), "\n") {
		if strings.Contains(l, "sin permiso de reparto") {
			linea = l
		}
	}
	if linea == "" {
		t.Fatalf("no hay renglón «sin permiso de reparto» en el registro:\n%s", registro.String())
	}
	if !strings.Contains(linea, "level=WARN") {
		t.Errorf("tiene que ser WARN: %s", linea)
	}
	for _, quiero := range []string{"rol=GERENTE", "OPERADOR", "sucursal=" + stg.String(),
		"ruta=/api/vehicles", "gerente@procovar.cu"} {
		if !strings.Contains(linea, quiero) {
			t.Errorf("al renglón le falta %q: %s", quiero, linea)
		}
	}

	for _, trozo := range append(strings.Split(jwt, "."), jwt) {
		if strings.Contains(registro.String(), trozo) {
			t.Errorf("el registro lleva un trozo del token (%.12s…)", trozo)
		}
		if strings.Contains(w.Body.String(), trozo) {
			t.Errorf("el cuerpo lleva un trozo del token (%.12s…)", trozo)
		}
	}
}

// ES DISTINTO DEL 403 DEL ALCANCE: «te falta la sucursal» se arregla en la oficina y NO lleva
// `codigo`; «tu rol no entra» no se arregla y sí. La app distingue uno de otro por ahí.
func TestElSinPermisoNoSeConfundeConElDeLaSucursal(t *testing.T) {
	h, _ := montarConRegistro(t)
	casos := map[string]map[string]any{
		"LOGISTICO sin sucursal":                 {"sub": "p-1", "role": "LOGISTICO"},
		"LOGISTICO con una sucursal sin alta":    {"sub": "p-2", "role": "LOGISTICO", "branchId": "MOA"},
		"ADMINISTRADOR con una que no existe":    {"sub": "p-3", "role": "ADMINISTRADOR", "branchId": fantasma.String()},
		"ADMINISTRADOR sin sucursal ni cabecera": {"sub": "p-4", "role": "ADMINISTRADOR"},
	}
	for nombre, rec := range casos {
		t.Run(nombre, func(t *testing.T) {
			w := servir(h, conBearer(http.MethodGet, "/api/vehicles", token(t, rec)))
			if w.Code != http.StatusForbidden {
				t.Fatalf("código %d: %s", w.Code, w.Body.String())
			}
			var cuerpo map[string]any
			if err := json.Unmarshal(w.Body.Bytes(), &cuerpo); err != nil {
				t.Fatal(err)
			}
			if _, hay := cuerpo["codigo"]; hay {
				t.Errorf("el 403 de la sucursal NO lleva `codigo`: %s", w.Body.String())
			}
			if strings.Contains(w.Body.String(), "No tienes permiso para entrar a Reparto") {
				t.Errorf("es un rol de Reparto: lo que falta es la sucursal, no el permiso: %s", w.Body.String())
			}
		})
	}
}

// LO QUE NO PASA POR `Exigir` SIGUE IGUAL: salud, versión, mapa y la puerta de la web; y
// `/api/me`, que contesta QUIÉN ERES a cualquier sesión válida — es lo que la app lee para
// poder enseñar «no tienes permiso» con el nombre y el rol de la persona.
func TestLoQueNoPasaPorExigirSigueIgual(t *testing.T) {
	h, _ := montarConRegistro(t)
	for _, ruta := range []string{"/health", "/version", "/api/version"} {
		if w := servir(h, httptest.NewRequest(http.MethodGet, ruta, nil)); w.Code != http.StatusOK {
			t.Errorf("%s sin sesión: %d %s", ruta, w.Code, w.Body.String())
		}
	}
	// La vuelta de salir no necesita sesión: redirige.
	if w := servir(h, httptest.NewRequest(http.MethodGet, "/api/auth/logout/done", nil)); w.Code != http.StatusFound {
		t.Errorf("/api/auth/logout/done: %d, se esperaba la redirección", w.Code)
	}

	jwt := token(t, map[string]any{"sub": "p-1", "email": "g@procovar.cu", "role": "GERENTE", "branchId": stg.String()})
	w := servir(h, conBearer(http.MethodGet, "/api/me", jwt))
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"role":"GERENTE"`) {
		t.Errorf("/api/me de un GERENTE tiene que seguir diciendo quién es: %d %s", w.Code, w.Body.String())
	}
	// Y /api/apps SÍ es de Reparto (pasa por Exigir, como siempre).
	if w := servir(h, conBearer(http.MethodGet, "/api/apps", jwt)); w.Code != http.StatusForbidden {
		t.Errorf("/api/apps de un GERENTE: %d %s", w.Code, w.Body.String())
	}
}

// LAS CUENTAS DE SERVICIO NO SE QUEDAN FUERA: una prueba por cada puerta que entra con llave y
// no con persona —el espejo, el sincronizador de productos, el repaso de pesos, el lote y el
// domicilio de PEDIDO, el alta de sucursal por código y el webhook de PEDIDO—, por el router
// ENTERO. Si alguien las envolviera con `Exigir`, o si la persona sintética perdiera su rol,
// aquí daría 401/403 y en producción sería el lote de PEDIDO sin entrar (ya pasó con 84 rechazos).
func TestLasPuertasDeServicioNoPasanPorElControlDeReparto(t *testing.T) {
	h, _ := montarConRegistro(t)

	cuerpoWebhook := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`
	mac := hmac.New(sha256.New, []byte(secretoDelWebhook))
	mac.Write([]byte(cuerpoWebhook))
	firma := "sha256=" + hex.EncodeToString(mac.Sum(nil))

	puertas := []struct {
		nombre, metodo, ruta, cuerpo string
		cabeceras                    map[string]string
	}{
		{"sucursal por código (sync)", http.MethodGet, "/api/service/sucursal?codigo=STG", "",
			map[string]string{"X-Api-Key": llaveDeServicioDeReparto}},
		{"repaso de pesos", http.MethodPost, "/api/orders/recompute-weights", `{}`,
			map[string]string{"X-Api-Key": llaveDeServicioDeReparto}},
		{"lote de cotización (PEDIDO)", http.MethodPost, "/api/quote/batch", `{}`,
			map[string]string{"X-Api-Key": llaveDeServicioDeReparto}},
		{"domicilio (PEDIDO)", http.MethodPost, "/api/quote/home-delivery", `{}`,
			map[string]string{"X-Api-Key": llaveDeServicioDeReparto}},
		{"sincronizar productos (espejo/n8n)", http.MethodPost, "/api/products/sync", `{}`,
			map[string]string{"X-Api-Key": llaveDeServicioDeReparto}},
		{"webhook de PEDIDO", http.MethodPost, "/api/webhooks/pedido", cuerpoWebhook,
			map[string]string{api.CabeceraClaveDelWebhook: claveDelWebhookDeReparto, api.CabeceraFirmaDelWebhook: firma}},
	}
	for _, p := range puertas {
		t.Run(p.nombre, func(t *testing.T) {
			r := httptest.NewRequest(p.metodo, p.ruta, io.NopCloser(strings.NewReader(p.cuerpo)))
			r.Header.Set("Content-Type", "application/json")
			for k, v := range p.cabeceras {
				r.Header.Set(k, v)
			}
			w := servir(h, r)
			if w.Code == http.StatusUnauthorized || w.Code == http.StatusForbidden {
				t.Fatalf("la puerta de servicio %q se quedó fuera: %d %s", p.nombre, w.Code, w.Body.String())
			}
			if strings.Contains(w.Body.String(), "sin_permiso_reparto") {
				t.Fatalf("la puerta de servicio %q recibió el control de Reparto: %s", p.nombre, w.Body.String())
			}
		})
	}

	// El alta de sucursal por código, que sí devuelve algo comprobable.
	r := httptest.NewRequest(http.MethodGet, "/api/service/sucursal?codigo=STG", nil)
	r.Header.Set("X-Api-Key", llaveDeServicioDeReparto)
	if w := servir(h, r); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), stg.String()) {
		t.Errorf("la traducción STG -> id para el sincronizador: %d %s", w.Code, w.Body.String())
	}

	// Y la llave de servicio en una ruta de PERSONA sigue sin valer: el control no abrió nada.
	r = httptest.NewRequest(http.MethodGet, "/api/vehicles", nil)
	r.Header.Set("X-Api-Key", llaveDeServicioDeReparto)
	if w := servir(h, r); w.Code != http.StatusUnauthorized {
		t.Errorf("la llave de servicio no es una sesión: %d %s", w.Code, w.Body.String())
	}
}

// DOS COOKIES `token` DE LA MISMA PERSONA, con roles distintos (auditoría, 08/10/2026).
//
// Es el caso de las cookies duplicadas del 29/09 con un rol de por medio: una cookie vieja
// (GERENTE) delante de la buena (LOGISTICO). Ganaba la primera válida y la persona recibía un
// 403 `sin_permiso_reparto` teniendo permiso. Ahora, entre las válidas, `Exigir` y el canal en
// vivo prefieren la que entra; si ninguna entra, se contesta con la primera.
func TestDosCookiesTokenGanaLaQueEntraAReparto(t *testing.T) {
	h, _ := montarConRegistro(t)
	gerente := token(t, map[string]any{"sub": "p-1", "role": "GERENTE", "branchId": stg.String()})
	logistico := token(t, map[string]any{"sub": "p-1", "role": "LOGISTICO", "branchId": stg.String()})
	rota := logistico[:len(logistico)-3] + "xxx"

	dos := func(ruta string, valores ...string) *http.Request {
		r := httptest.NewRequest(http.MethodGet, ruta, nil)
		for _, v := range valores {
			r.AddCookie(&http.Cookie{Name: "token", Value: v})
		}
		return r
	}

	casos := []struct {
		nombre string
		req    *http.Request
		entra  bool
	}{
		{"GERENTE y luego LOGISTICO: entra", dos("/api/vehicles", gerente, logistico), true},
		{"LOGISTICO y luego GERENTE: entra", dos("/api/vehicles", logistico, gerente), true},
		{"una rota y luego LOGISTICO: entra", dos("/api/vehicles", rota, logistico), true},
		{"las dos GERENTE: 403 (ninguna entra)", dos("/api/vehicles", gerente, gerente), false},
		{"cabecera GERENTE y cookie LOGISTICO: entra",
			func() *http.Request {
				r := dos("/api/vehicles", logistico)
				r.Header.Set("Authorization", "Bearer "+gerente)
				return r
			}(), true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			w := servir(h, c.req)
			if c.entra && w.Code != http.StatusOK {
				t.Fatalf("tenía que entrar: %d %s", w.Code, w.Body.String())
			}
			if !c.entra && (w.Code != http.StatusForbidden || strings.TrimSpace(w.Body.String()) != cuerpoSinPermiso) {
				t.Fatalf("tenía que dar el 403 de rol: %d %s", w.Code, w.Body.String())
			}
		})
	}

	// El canal en vivo, que no pasa por Exigir, igual. Con plazo: si entra, el canal se abre.
	for nombre, c := range map[string]struct {
		cookies []string
		entra   bool
	}{
		"SSE GERENTE y luego LOGISTICO": {[]string{gerente, logistico}, true},
		"SSE las dos GERENTE":           {[]string{gerente, gerente}, false},
	} {
		t.Run(nombre, func(t *testing.T) {
			ctx, cancelar := context.WithTimeout(context.Background(), 300*time.Millisecond)
			defer cancelar()
			w := servir(h, dos("/api/eventos", c.cookies...).WithContext(ctx))
			if c.entra && (w.Code != http.StatusOK || !strings.HasPrefix(w.Header().Get("Content-Type"), "text/event-stream")) {
				t.Fatalf("el canal tenía que abrirse: %d %s", w.Code, w.Body.String())
			}
			if !c.entra && (w.Code != http.StatusForbidden || strings.TrimSpace(w.Body.String()) != cuerpoSinPermiso) {
				t.Fatalf("el canal tenía que dar el 403 de rol: %d %s", w.Code, w.Body.String())
			}
		})
	}
}

// `/api/me` ELIGE COMO `Exigir` (auditoría del repo, 08/10/2026). Con dos cookies `token` de la
// misma persona [GERENTE, LOGISTICO], `/api/vehicles` entra como LOGISTICO; `/api/me` usaba la
// primera cookie válida y decía `role: GERENTE`, así que la app enseñaba «sin permiso» a quien
// sí entra. Y el `token` que devuelve tiene que ser el de ESA cookie, no el de la primera.
func TestApiMeDiceLoMismoQueExigirConDosCookies(t *testing.T) {
	h, _ := montarConRegistro(t)
	gerente := token(t, map[string]any{"sub": "p-1", "email": "p@procovar.cu", "role": "GERENTE", "branchId": stg.String()})
	logistico := token(t, map[string]any{"sub": "p-1", "email": "p@procovar.cu", "role": "LOGISTICO", "branchId": stg.String()})

	me := func(cookies ...string) (string, string) {
		r := httptest.NewRequest(http.MethodGet, "/api/me", nil)
		for _, c := range cookies {
			r.AddCookie(&http.Cookie{Name: "token", Value: c})
		}
		w := servir(h, r)
		var yo struct {
			User  *struct{ Role string } `json:"user"`
			Token *string                `json:"token"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &yo); err != nil || w.Code != http.StatusOK || yo.User == nil {
			t.Fatalf("/api/me: %d %s", w.Code, w.Body.String())
		}
		devuelto := ""
		if yo.Token != nil {
			devuelto = *yo.Token
		}
		return yo.User.Role, devuelto
	}

	for nombre, orden := range map[string][]string{
		"GERENTE y luego LOGISTICO": {gerente, logistico},
		"LOGISTICO y luego GERENTE": {logistico, gerente},
	} {
		t.Run(nombre, func(t *testing.T) {
			rol, devuelto := me(orden...)
			if rol != "LOGISTICO" || devuelto != logistico {
				t.Fatalf("/api/me dice rol %q y devuelve el token de otra cookie (%v): tenía que decir "+
					"LOGISTICO y devolver el de la cookie que entra", rol, devuelto == gerente)
			}
			// Y es coherente con lo que hace Exigir con esas mismas cookies.
			r := httptest.NewRequest(http.MethodGet, "/api/vehicles", nil)
			for _, c := range orden {
				r.AddCookie(&http.Cookie{Name: "token", Value: c})
			}
			if w := servir(h, r); w.Code != http.StatusOK {
				t.Fatalf("Exigir con las mismas cookies: %d", w.Code)
			}
		})
	}

	// LA PAREJA: si ninguna entra, la primera válida (la que explica el 403), con su token.
	if rol, devuelto := me(gerente, gerente); rol != "GERENTE" || devuelto != gerente {
		t.Fatalf("dos GERENTE: rol %q", rol)
	}
	// Y con una sola cookie, como siempre.
	if rol, devuelto := me(logistico); rol != "LOGISTICO" || devuelto != logistico {
		t.Fatalf("una cookie: rol %q", rol)
	}
}
