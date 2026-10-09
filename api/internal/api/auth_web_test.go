package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
)

// LAS CUATRO RUTAS DE LA PUERTA DE LA WEB.
//
// Se prueban contra un Accesos de mentira levantado con `httptest`, no contra un
// doble del cliente: así se ejercita la firma HMAC de verdad, el cuerpo que se
// manda de verdad y lo que se hace con lo que contesta. Un doble probaría el
// manejador contra nuestra idea de Accesos, que es justo donde se esconden estos
// fallos.
//
// Y ninguna sale a internet: `httptest` escucha en el bucle local. La regla dura
// de `CLAUDE.md` —nada de peticiones a un dominio de Procovar desde este PC— se
// cumple porque `AUTH_URL` apunta al servidor de mentira.

const (
	secretoDePrueba = "0123456789012345678901234567890123456789"
	llaveDeFirma    = "6465616462656566" // hexadecimal, como la de verdad
)

// accesosDeMentira es el Accesos de las pruebas: apunta lo que le llega y
// contesta lo que se le diga.
type accesosDeMentira struct {
	*httptest.Server
	vistas []peticionVista
	// responder decide qué contesta cada ruta.
	responder func(ruta string, cuerpo map[string]any) (int, any)
}

type peticionVista struct {
	ruta      string
	cabeceras http.Header
	cuerpo    map[string]any
}

func levantarAccesos(t *testing.T, responder func(ruta string, cuerpo map[string]any) (int, any)) *accesosDeMentira {
	t.Helper()
	a := &accesosDeMentira{responder: responder}
	a.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		crudo, _ := io.ReadAll(r.Body)
		var cuerpo map[string]any
		_ = json.Unmarshal(crudo, &cuerpo)
		a.vistas = append(a.vistas, peticionVista{ruta: r.URL.Path, cabeceras: r.Header.Clone(), cuerpo: cuerpo})

		codigo, salida := a.responder(r.URL.Path, cuerpo)
		w.Header().Set("content-type", "application/json")
		w.WriteHeader(codigo)
		_ = json.NewEncoder(w).Encode(salida)
	}))
	t.Cleanup(a.Close)
	return a
}

func (a *accesosDeMentira) ultima(ruta string) *peticionVista {
	for i := len(a.vistas) - 1; i >= 0; i-- {
		if a.vistas[i].ruta == ruta {
			return &a.vistas[i]
		}
	}
	return nil
}

// puertaDePrueba monta SÓLO las rutas de la puerta y `/api/me`, que es la que
// tiene que reconocer la cookie que se acaba de escribir.
func puertaDePrueba(t *testing.T, accesos string, llave string) http.Handler {
	t.Helper()
	// Sin dirección pública declarada: se deduce de la petición, que es lo que
	// pasa en desarrollo. Las pruebas que la necesitan la ponen ellas.
	t.Setenv("PROCOVAR_PUBLIC_URL", "")

	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	cfg := &config.Config{
		JWTSecret:      []byte(secretoDePrueba),
		AuthURL:        accesos,
		AuthClientID:   "reparto",
		AuthSigningKey: llave,
	}
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(nil, reg),
		auth.NuevoVerificador([]byte(secretoDePrueba)),
		nil,
	)
	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg))
	s.rutasAuthWeb(rt, nil, nil)
	rt.ManejarFunc(http.MethodGet, "/api/me", s.yo)
	// `/api/apps` pasa por `Exigir` como cualquier ruta de Reparto: es la que prueba si la
	// cookie recién escrita ENTRA o recibe el 403 de «no tienes permiso».
	rt.ManejarFunc(http.MethodGet, "/api/apps", s.apps, s.verif.Exigir)
	return rt.Handler()
}

func pedir(h http.Handler, ruta string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "http://reparto.test"+ruta, nil))
	return rec
}

// personaDeMentira es lo que contesta el canje de Accesos.
func personaDeMentira(volverA string) map[string]any {
	return map[string]any{
		"user": map[string]any{
			"id":            "u-777",
			"email":         "yasmani@procovar.cu",
			"name":          "Yasmani",
			"isSystemAdmin": false,
		},
		"memberships": []any{
			map[string]any{
				"organization": map[string]any{"slug": "hab", "name": "La Habana"},
				"roles":        []any{"SUPERVISOR"},
			},
		},
		"returnTo": volverA,
	}
}

// ---------------------------------------------------------------------------
// 1 · ENTRAR
// ---------------------------------------------------------------------------

func TestEntrarMandaAAccesosConLaFirmaPuesta(t *testing.T) {
	accesos := levantarAccesos(t, func(ruta string, _ map[string]any) (int, any) {
		return http.StatusOK, map[string]any{"redirectUrl": "REEMPLAZAR"}
	})
	// El destino tiene que ser del propio Accesos: se arma con su URL ya
	// levantada.
	accesos.responder = func(ruta string, _ map[string]any) (int, any) {
		return http.StatusOK, map[string]any{"redirectUrl": accesos.URL + "/sign-in?ticket=abc"}
	}
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/entrar")

	if rec.Code != http.StatusFound {
		t.Fatalf("esperaba 302, dio %d", rec.Code)
	}
	if destino := rec.Header().Get("Location"); destino != accesos.URL+"/sign-in?ticket=abc" {
		t.Fatalf("no manda a donde dijo Accesos: %q", destino)
	}

	vista := accesos.ultima(rutaPedirRedireccion)
	if vista == nil {
		t.Fatal("no se le pidió la redirección a Accesos")
	}
	// LA FIRMA. Sin ella Accesos contesta 401 y nadie entra nunca.
	for _, cab := range []string{"X-Client-Id", "X-Timestamp", "X-Nonce", "X-Signature"} {
		if vista.cabeceras.Get(cab) == "" {
			t.Errorf("falta la cabecera %s de la firma", cab)
		}
	}
	// LA DIRECCIÓN DE VUELTA SE CALCULA DESDE LA PETICIÓN. Si saliera de una
	// constante, en local mandaría a producción.
	if vista.cuerpo["callbackUrl"] != "http://reparto.test/api/auth/callback" {
		t.Errorf("callbackUrl mal armada: %v", vista.cuerpo["callbackUrl"])
	}
	if vista.cuerpo["returnTo"] != "http://reparto.test/" {
		t.Errorf("returnTo por defecto mal: %v", vista.cuerpo["returnTo"])
	}
}

func TestEntrarSeAcuerdaDeADondeIba(t *testing.T) {
	accesos := levantarAccesos(t, nil)
	accesos.responder = func(string, map[string]any) (int, any) {
		return http.StatusOK, map[string]any{"redirectUrl": accesos.URL + "/sign-in"}
	}
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	pedir(h, "/api/auth/entrar?volverA="+url.QueryEscape("/orders?municipio=Centro"))

	vista := accesos.ultima(rutaPedirRedireccion)
	if vista.cuerpo["returnTo"] != "http://reparto.test/orders?municipio=Centro" {
		t.Fatalf("se perdió a dónde iba: %v", vista.cuerpo["returnTo"])
	}
}

func TestElDestinoNoPuedeSalirDeCasa(t *testing.T) {
	accesos := levantarAccesos(t, nil)
	accesos.responder = func(string, map[string]any) (int, any) {
		return http.StatusOK, map[string]any{"redirectUrl": accesos.URL + "/sign-in"}
	}
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	// Los tres que un navegador lee como «otro dominio»: absoluta, `//host` y
	// la contrabarra.
	for _, malo := range []string{"https://sitio-falso.example/robar", "//sitio-falso.example", "/\\sitio-falso.example"} {
		pedir(h, "/api/auth/entrar?volverA="+url.QueryEscape(malo))
		vista := accesos.ultima(rutaPedirRedireccion)
		if vista.cuerpo["returnTo"] != "http://reparto.test/" {
			t.Errorf("con volverA=%q se aceptó salir de casa: %v", malo, vista.cuerpo["returnTo"])
		}
	}
}

func TestSinLlaveLoDiceEnVezDeIntentarlo(t *testing.T) {
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, map[string]any{}
	})
	h := puertaDePrueba(t, accesos.URL, "") // ← la llave que falta

	rec := pedir(h, "/api/auth/entrar")

	if rec.Code != http.StatusFound {
		t.Fatalf("esperaba 302, dio %d", rec.Code)
	}
	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/acceso?sso=nodisponible" {
		t.Fatalf("no vuelve a la puerta diciendo el motivo: %q", destino)
	}
	if len(accesos.vistas) != 0 {
		t.Error("se salió a la red sin llave: eso es un 401 de Accesos que nadie sabe explicar")
	}
}

func TestAccesosQueNoContestaVuelveALaPuertaDiciendolo(t *testing.T) {
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusInternalServerError, map[string]any{"error": "boom"}
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/entrar")

	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/acceso?sso=error" {
		t.Fatalf("esperaba la puerta con el motivo, dio %q", destino)
	}
}

func TestNoSeMandaANadieFueraDeAccesos(t *testing.T) {
	// Un redirector abierto con nuestro dominio delante: la persona se
	// identifica de verdad y acaba en una copia del login.
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, map[string]any{"redirectUrl": "https://sitio-falso.example/login"}
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/entrar")

	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/acceso?sso=error" {
		t.Fatalf("se mandó a alguien a un sitio que no es Accesos: %q", destino)
	}
}

// ---------------------------------------------------------------------------
// 2 · LA VUELTA
// ---------------------------------------------------------------------------

func TestLaVueltaDejaLaCookieYEsLaQueLeeApiMe(t *testing.T) {
	accesos := levantarAccesos(t, func(ruta string, _ map[string]any) (int, any) {
		return http.StatusOK, personaDeMentira("http://reparto.test/orders")
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/callback?code=abc123")

	if rec.Code != http.StatusFound {
		t.Fatalf("esperaba 302, dio %d", rec.Code)
	}
	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/orders" {
		t.Fatalf("no vuelve a donde iba: %q", destino)
	}

	galleta := laCookie(t, rec)
	if !galleta.HttpOnly {
		t.Error("la cookie NO es httpOnly: un script de la página se lleva la sesión")
	}
	if galleta.Path != "/" {
		t.Errorf("camino %q: si no es `/` no llega a `/api`", galleta.Path)
	}
	if galleta.SameSite != http.SameSiteLaxMode {
		t.Errorf("SameSite %v: con Strict el navegador no la manda al volver de Accesos", galleta.SameSite)
	}
	if galleta.MaxAge <= 0 {
		t.Errorf("Max-Age %d: una cookie que nace borrada no deja entrar a nadie", galleta.MaxAge)
	}

	// EL TOKEN ES EL NUESTRO: firmado con el mismo secreto que comprueba la API.
	u, err := auth.NuevoVerificador([]byte(secretoDePrueba)).Verificar(galleta.Value)
	if err != nil {
		t.Fatalf("el token de la cookie no lo acepta la propia API: %v", err)
	}
	if u.ID != "u-777" || u.Email != "yasmani@procovar.cu" {
		t.Errorf("la persona del token no es la que dijo Accesos: %+v", u)
	}
	if u.Sucursal != "HAB" {
		t.Errorf("sucursal %q: sale del slug de la organización en mayúsculas", u.Sucursal)
	}
	if u.Rol != "SUPERVISOR" {
		t.Errorf("rol %q: se copia tal cual lo escribe Procovar", u.Rol)
	}

	// Y DE PUNTA A PUNTA: con esa cookie, `/api/me` ya sabe quién es. Esta es la
	// que ata las dos mitades — la puerta escribe y el armazón pregunta.
	rec2 := httptest.NewRecorder()
	pet := httptest.NewRequest(http.MethodGet, "http://reparto.test/api/me", nil)
	pet.AddCookie(&http.Cookie{Name: galleta.Name, Value: galleta.Value})
	h.ServeHTTP(rec2, pet)

	if rec2.Code != http.StatusOK {
		t.Fatalf("/api/me no reconoce la cookie recién escrita: %d %s", rec2.Code, rec2.Body.String())
	}
	var yo YoSalida
	if err := json.Unmarshal(rec2.Body.Bytes(), &yo); err != nil {
		t.Fatalf("/api/me contestó algo ilegible: %v", err)
	}
	if yo.User == nil || yo.User.ID != "u-777" {
		t.Fatalf("/api/me no devuelve a la persona: %s", rec2.Body.String())
	}
	if yo.Token == nil || *yo.Token != galleta.Value {
		t.Fatal("/api/me no devuelve el token de la cookie, que es lo que la web usa para hablar con la API")
	}
}

func TestUnCodigoInvalidoDiceElMotivoYNoDejaSesion(t *testing.T) {
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusBadRequest, map[string]any{"error": "codigo_invalido", "message": "el código ya se usó"}
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/callback?code=yaquemado")

	// NI PANTALLA EN BLANCO NI 500: vuelve a la puerta con el motivo puesto en
	// la dirección, que es lo único que la puerta sabe leer sin sesión.
	if rec.Code != http.StatusFound {
		t.Fatalf("esperaba 302 a la puerta, dio %d con %q", rec.Code, rec.Body.String())
	}
	destino := rec.Header().Get("Location")
	if destino != "http://reparto.test/acceso?sso=error" {
		t.Fatalf("no dice el motivo: %q", destino)
	}
	if len(rec.Result().Cookies()) != 0 {
		t.Fatal("un canje fallido dejó sesión escrita")
	}
}

func TestLaVueltaSinCodigoLoDice(t *testing.T) {
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, personaDeMentira("")
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/callback")

	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/acceso?sso=sincodigo" {
		t.Fatalf("esperaba `sincodigo`, dio %q", destino)
	}
	if len(accesos.vistas) != 0 {
		t.Error("se fue a canjear un código que no había")
	}
}

func TestLaVueltaCompruebaOtraVezADondeVa(t *testing.T) {
	// `returnTo` fue y vino por fuera: lo que se comprueba tiene que ser lo que
	// se usa.
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, personaDeMentira("https://sitio-falso.example/")
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/callback?code=abc")

	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/" {
		t.Fatalf("se aceptó un destino de fuera: %q", destino)
	}
}

func TestElAdministradorGlobalNoEntraSinSerlo(t *testing.T) {
	// `isSystemAdmin` sin rol en la lista: sin traducirlo, entra y ve la
	// aplicación medio vacía sin un solo error.
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, map[string]any{
			"user":        map[string]any{"id": "u-1", "email": "jefe@procovar.cu", "name": "Jefa", "isSystemAdmin": true},
			"memberships": []any{},
		}
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/callback?code=abc")
	galleta := laCookie(t, rec)

	u, err := auth.NuevoVerificador([]byte(secretoDePrueba)).Verificar(galleta.Value)
	if err != nil {
		t.Fatalf("token no válido: %v", err)
	}
	if !u.EsSuperAdmin() {
		t.Fatalf("el administrador global de Accesos entró sin serlo: rol %q, roles %v", u.Rol, u.Roles)
	}
	if u.Sucursal != "" {
		t.Errorf("sin membresías la sucursal tiene que ir vacía, no %q", u.Sucursal)
	}
}

// ---------------------------------------------------------------------------
// 3 · SALIR
// ---------------------------------------------------------------------------

func TestSalirVaPrimeroAAccesos(t *testing.T) {
	accesos := levantarAccesos(t, nil)
	accesos.responder = func(string, map[string]any) (int, any) { return http.StatusOK, map[string]any{} }
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	rec := pedir(h, "/api/auth/logout")

	destino := rec.Header().Get("Location")
	if !strings.HasPrefix(destino, accesos.URL+"/logout?") {
		t.Fatalf("salir no pasa por Accesos: %q", destino)
	}
	q, err := url.Parse(destino)
	if err != nil {
		t.Fatal(err)
	}
	if q.Query().Get("returnTo") != "http://reparto.test/api/auth/logout/done" {
		t.Errorf("returnTo mal: %q", q.Query().Get("returnTo"))
	}
	// CANCELAR NO PUEDE DEJAR A NADIE A MEDIAS: si dice que no en el cartel de
	// Accesos, vuelve a la aplicación con su sesión intacta.
	if q.Query().Get("cancelUrl") != "http://reparto.test/" {
		t.Errorf("cancelUrl mal: %q", q.Query().Get("cancelUrl"))
	}
	if len(rec.Result().Cookies()) != 0 {
		t.Fatal("se borró la cookie ANTES de ir a Accesos: decir que no ahí deja a la persona fuera de la aplicación sin haber querido salir")
	}
}

func TestLaVueltaDeSalirBorraLaCookieDeVerdad(t *testing.T) {
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, personaDeMentira("")
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	// La que se puso al entrar, para comparar atributo a atributo.
	puesta := laCookie(t, pedir(h, "/api/auth/callback?code=abc"))

	rec := pedir(h, "/api/auth/logout/done")

	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/" {
		t.Fatalf("no deja a la persona en la aplicación: %q", destino)
	}
	borrada := laCookie(t, rec)
	if borrada.Value != "" || borrada.MaxAge >= 0 {
		t.Fatalf("la cookie NO se borra: valor %q, Max-Age %d — quien pulsó «cerrar sesión» sigue dentro", borrada.Value, borrada.MaxAge)
	}
	// LOS ATRIBUTOS TIENEN QUE SER LOS MISMOS. Con uno distinto el navegador la
	// trata como otra cookie y deja la buena donde estaba: se cierra la sesión
	// de Accesos, se vuelve, y se sigue dentro como si nada.
	if borrada.Name != puesta.Name || borrada.Path != puesta.Path ||
		borrada.Secure != puesta.Secure || borrada.SameSite != puesta.SameSite || !borrada.HttpOnly {
		t.Fatalf("el borrado no cuadra con lo que se puso:\n  puesta:  %+v\n  borrada: %+v", puesta, borrada)
	}
}

func TestSalirCierraAunqueAccesosNoEsteConfigurado(t *testing.T) {
	h := puertaDePrueba(t, "", llaveDeFirma)

	rec := pedir(h, "/api/auth/logout")

	if destino := rec.Header().Get("Location"); destino != "http://reparto.test/api/auth/logout/done" {
		t.Fatalf("sin AUTH_URL no se cierra nada: %q", destino)
	}
}

// ---------------------------------------------------------------------------
// 4 · DÓNDE ESTAMOS
// ---------------------------------------------------------------------------

func TestLaDireccionPublicaMandaSobreLaCabecera(t *testing.T) {
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, personaDeMentira("")
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)
	// Detrás del proxy `r.Host` es `0.0.0.0:8080` y la vuelta no llevaría a
	// ninguna parte. Y con HTTPS la cookie tiene que salir `Secure`.
	t.Setenv("PROCOVAR_PUBLIC_URL", "https://reparto.procovar.cloud/")

	rec := pedir(h, "/api/auth/callback?code=abc")

	if destino := rec.Header().Get("Location"); destino != "https://reparto.procovar.cloud/" {
		t.Fatalf("no usa la dirección pública: %q", destino)
	}
	if galleta := laCookie(t, rec); !galleta.Secure {
		t.Fatal("por HTTPS la cookie tiene que ser Secure")
	}
}

func TestPorHttpLaCookieNoEsSecure(t *testing.T) {
	// En el `localhost` de desarrollo una cookie `Secure` la descarta el
	// navegador y no se entra nunca.
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) {
		return http.StatusOK, personaDeMentira("")
	})
	h := puertaDePrueba(t, accesos.URL, llaveDeFirma)

	if galleta := laCookie(t, pedir(h, "/api/auth/callback?code=abc")); galleta.Secure {
		t.Fatal("por HTTP la cookie no puede ser Secure: el navegador la descarta y nadie entra")
	}
}

// laCookie saca la cookie de la sesión de la respuesta, o falla diciéndolo.
func laCookie(t *testing.T, rec *httptest.ResponseRecorder) *http.Cookie {
	t.Helper()
	for _, c := range rec.Result().Cookies() {
		if c.Name == nombreDeLaCookie {
			return c
		}
	}
	t.Fatalf("no hay cookie %q en la respuesta (%d): %v", nombreDeLaCookie, rec.Code, rec.Header())
	return nil
}

// ---------------------------------------------------------------------------
// 2-bis · EL CÓDIGO DE SUCURSAL DE LA WEB (`organization.codigo`, no el `slug`)
// ---------------------------------------------------------------------------

// La APK y el escritorio llevan `organization.codigo` en el token; la web lo sacaba del `slug` en
// mayúsculas. En Accesos son columnas distintas y difieren en `PLS` (slug `palma-soriano`): la web de
// Palma Soriano pedía «PALMA-SORIANO» y su APK «PLS». Ahora manda `codigo` y, si falta, el `slug`
// (Accesos y Reparto se pueden desplegar en cualquier orden).
func TestLaSucursalDeLaWebSaleDelCodigoYSiFaltaDelSlug(t *testing.T) {
	casos := []struct {
		nombre string
		org    map[string]any
		quiero string
	}{
		{"el codigo manda sobre el slug (PLS)", map[string]any{"slug": "palma-soriano", "codigo": "PLS"}, "PLS"},
		{"el codigo manda aunque el slug sea otra sucursal", map[string]any{"slug": "hab", "codigo": "STG"}, "STG"},
		{"el codigo en minúsculas y con espacios se normaliza", map[string]any{"slug": "palma-soriano", "codigo": " pls "}, "PLS"},
		// La pareja: sin `codigo` (un Accesos anterior al cambio) se cae al slug de siempre.
		{"sin codigo: el slug en mayúsculas", map[string]any{"slug": "hab"}, "HAB"},
		{"codigo vacío: el slug", map[string]any{"slug": "hab", "codigo": ""}, "HAB"},
		{"codigo en blanco: el slug", map[string]any{"slug": "hab", "codigo": "   "}, "HAB"},
		{"codigo null: el slug", map[string]any{"slug": "hab", "codigo": nil}, "HAB"},
		// Un tipo raro NO tumba el login de toda la web: se ignora y se cae al slug.
		{"codigo numérico: el slug, y el login sigue", map[string]any{"slug": "hab", "codigo": 7}, "HAB"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			accesos := levantarAccesos(t, func(ruta string, _ map[string]any) (int, any) {
				p := personaDeMentira("http://reparto.test/orders")
				p["memberships"] = []any{map[string]any{"organization": c.org, "roles": []any{"SUPERVISOR"}}}
				return http.StatusOK, p
			})
			h := puertaDePrueba(t, accesos.URL, llaveDeFirma)
			rec := pedir(h, "/api/auth/callback?code=abc123")
			if rec.Code != http.StatusFound {
				t.Fatalf("esperaba 302, dio %d", rec.Code)
			}
			u, err := auth.NuevoVerificador([]byte(secretoDePrueba)).Verificar(laCookie(t, rec).Value)
			if err != nil {
				t.Fatalf("el token de la cookie no lo acepta la propia API: %v", err)
			}
			if u.Sucursal != c.quiero {
				t.Fatalf("sucursal %q, se esperaba %q (org %v)", u.Sucursal, c.quiero, c.org)
			}
		})
	}
}
