package api

// ACCESOS INVALIDA LA SESIÓN DE LA WEB, Y SE REFLEJA EN TODAS LAS PUERTAS (08/10/2026).
//
// Jose: «si cierro sesión o me cambian un permiso en Accesos se refleja en todas. Nada de
// polling: para eso tenemos SSE y Sentinel». Antes la cookie de la web valía siete días sin
// volver a preguntar a nadie.
//
// Estas pruebas van de PUNTA A PUNTA donde se puede: la cookie la emite el `Canjear` de verdad
// (contra un Accesos de mentira), el mensaje entra por `Registro.Aplicar` —el mismo camino que
// uno del canal de Redis— y lo que se mira es lo que ve el navegador: el código de cada puerta,
// la cabecera que borra la cookie y el evento SSE. El mapa y el bucle de Redis se prueban en
// `internal/sesiones`.

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/sesiones"
)

// bufferDeLog: el registro lo escriben las gorutinas del servidor y lo lee la prueba.
type bufferDeLog struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *bufferDeLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *bufferDeLog) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

type bancoDeSesiones struct {
	h    http.Handler
	inv  *sesiones.Registro
	bus  *Difusor
	logs *bufferDeLog
	s    *Servidor
}

// montarConAccesos monta las puertas con cookie (`/api/me`, `/api/apps` por `Exigir`,
// `/api/eventos`), la vuelta de Accesos y una ruta de servicio, con el empuje de Accesos enganchado
// a un registro SIN Redis: los mensajes se le dan con `Aplicar`.
func montarConAccesos(t *testing.T) *bancoDeSesiones {
	t.Helper()
	t.Setenv("PROCOVAR_PUBLIC_URL", "")
	accesos := levantarAccesos(t, func(_ string, cuerpo map[string]any) (int, any) {
		quien, _ := cuerpo["code"].(string) // el código de la prueba ES el id de la persona
		return http.StatusOK, map[string]any{
			"user":     map[string]any{"id": quien, "email": quien + "@procovar.cu", "name": quien},
			"role":     "SUPER ADMIN",
			"roles":    []any{"SUPER ADMIN"},
			"entradas": []any{auth.LlaveEntrarReparto},
			"returnTo": "http://reparto.test/",
		}
	})

	logs := &bufferDeLog{}
	reg := slog.New(slog.NewTextHandler(logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	cfg := &config.Config{
		JWTSecret:      []byte(secretoDePanel),
		AuthURL:        accesos.URL,
		AuthClientID:   "reparto",
		AuthSigningKey: llaveDeFirma,
		ServiceAPIKey:  "llave-de-servicio-de-prueba",
	}
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteDePanel{q: &dobleDePanel{}}, reg),
		auth.NuevoVerificador([]byte(secretoDePanel)), nil)

	inv := sesiones.Nuevo(nil, reg)
	s.PonerSesiones(inv)
	bus := NuevoDifusor()
	inv.AlEvento = bus.SesionInvalidada // el bus de la prueba, no el del proceso

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.SinCache)
	s.rutasAuthWeb(rt, nil, nil)
	rt.ManejarFunc(http.MethodGet, "/api/me", s.yo)
	rt.ManejarFunc(http.MethodGet, "/api/apps", s.apps, s.verif.Exigir)
	rt.ManejarFunc(http.MethodGet, "/api/eventos", func(w http.ResponseWriter, r *http.Request) {
		s.servirEventos(w, r, bus)
	})
	rt.ManejarFunc(http.MethodGet, "/api/de-servicio", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}, s.servicioOSesion)
	return &bancoDeSesiones{h: rt.Handler(), inv: inv, bus: bus, logs: logs, s: s}
}

// entrar hace la vuelta de Accesos como `persona` y devuelve la cookie que deja la API.
func (b *bancoDeSesiones) entrar(t *testing.T, persona string) *http.Cookie {
	t.Helper()
	rec := httptest.NewRecorder()
	b.h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "http://reparto.test/api/auth/callback?code="+persona, nil))
	if rec.Code != http.StatusFound {
		t.Fatalf("la vuelta de Accesos dio %d: %s", rec.Code, rec.Body.String())
	}
	return laCookie(t, rec)
}

// pide hace una petición con la cookie y/o el Bearer que se le digan.
//
// **Con plazo**: `/api/eventos` con una sesión que vale se queda abierto para siempre, y una prueba
// que lo espera SE CUELGA en vez de fallar (CLAUDE.md §5). A los 400 ms se corta como lo haría el
// navegador, y el 200 que sale se lee como lo que es: una sesión que no se cortó.
func (b *bancoDeSesiones) pide(ruta string, cookie *http.Cookie, bearer string) *httptest.ResponseRecorder {
	ctx, cortar := context.WithTimeout(context.Background(), 400*time.Millisecond)
	defer cortar()
	r := httptest.NewRequest(http.MethodGet, "http://reparto.test"+ruta, nil).WithContext(ctx)
	if cookie != nil {
		r.AddCookie(&http.Cookie{Name: cookie.Name, Value: cookie.Value})
	}
	if bearer != "" {
		r.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	b.h.ServeHTTP(rec, r)
	return rec
}

// marca publica un mensaje de Accesos tal como llegaría por el canal.
func (b *bancoDeSesiones) marca(alcance, tipo string, tms int64, personas ...string) {
	ids, _ := json.Marshal(personas)
	b.inv.Aplicar(`{"v":1,"tipo":"` + tipo + `","alcance":"` + alcance + `","userIds":` + string(ids) +
		`,"tms":` + itoaMs(tms) + `,"motivo":"prueba"}`)
}

func itoaMs(n int64) string { return strconv.FormatInt(n, 10) }

func ahoraMs() int64 { return time.Now().UnixMilli() }

// laCookieBorrada dice si la respuesta borra la cookie de la web, con los MISMOS atributos con los
// que se puso (con uno distinto el navegador la trata como otra y deja la buena donde estaba).
func laCookieBorrada(t *testing.T, rec *httptest.ResponseRecorder, original *http.Cookie) bool {
	t.Helper()
	for _, c := range rec.Result().Cookies() {
		if c.Name != nombreDeLaCookie {
			continue
		}
		if c.Value != "" || c.MaxAge >= 0 {
			t.Errorf("la cookie que vuelve no es un borrado: valor=%q max-age=%d", c.Value, c.MaxAge)
			return false
		}
		if original != nil && (c.Path != original.Path || c.HttpOnly != original.HttpOnly ||
			c.SameSite != original.SameSite || c.Secure != original.Secure) {
			t.Errorf("el borrado no lleva los atributos de la cookie original (path %q/%q, httponly %v/%v, "+
				"samesite %v/%v, secure %v/%v)", c.Path, original.Path, c.HttpOnly, original.HttpOnly,
				c.SameSite, original.SameSite, c.Secure, original.Secure)
		}
		return true
	}
	return false
}

// iatmsDe lee el claim `iatms` de un token SIN comprobar nada (es una prueba).
func iatmsDe(t *testing.T, token string) (float64, bool) {
	t.Helper()
	partes := strings.Split(token, ".")
	crudo, err := base64.RawURLEncoding.DecodeString(partes[1])
	if err != nil {
		t.Fatal(err)
	}
	var c map[string]any
	if err := json.Unmarshal(crudo, &c); err != nil {
		t.Fatal(err)
	}
	v, hay := c["iatms"].(float64)
	return v, hay
}

// ---------------------------------------------------------------------------

// LA COOKIE LLEVA SU `iatms`, en milisegundos y junto al `iat` de siempre. Sin él no hay contra
// qué comparar la marca de Accesos, que va en milisegundos.
func TestLaCookieDeLaWebLlevaSuIatEnMilisegundos(t *testing.T) {
	b := montarConAccesos(t)
	antes := ahoraMs()
	galleta := b.entrar(t, "u-ana")
	despues := ahoraMs()

	// Y la MARCA `web`: Accesos también firma `iatms` en el token de la APK, así que es esto lo que
	// dice «esta credencial es una sesión de la web».
	partes := strings.Split(galleta.Value, ".")
	crudo, _ := base64.RawURLEncoding.DecodeString(partes[1])
	var claims map[string]any
	_ = json.Unmarshal(crudo, &claims)
	if claims["web"] != true {
		t.Error("la cookie no lleva `web: true`: sin la marca, un token de la APK con iatms y una cookie web serían indistinguibles")
	}

	ms, hay := iatmsDe(t, galleta.Value)
	if !hay {
		t.Fatal("la cookie no lleva `iatms`: sin él una marca de Accesos no se puede comparar")
	}
	if int64(ms) < antes || int64(ms) > despues {
		t.Errorf("iatms %d fuera de [%d, %d]: no es el instante de emisión en milisegundos", int64(ms), antes, despues)
	}
}

// LAS TRES PUERTAS CON COOKIE contestan lo suyo y borran la cookie. Cada una con SU forma de 401:
// `Exigir` el JSON de siempre, `/api/me` el `{"user":null}` y el canal el texto plano.
func TestLaCookieEmitidaAntesDeLaMarcaDa401EnLasTresPuertasYSeBorra(t *testing.T) {
	puertas := []struct {
		ruta   string
		cuerpo func(string) bool
	}{
		{"/api/apps", func(c string) bool { return strings.Contains(c, `"error":"Unauthorized"`) }},
		{"/api/me", func(c string) bool { return strings.Contains(c, `"user":null`) }},
		{"/api/eventos", func(c string) bool { return c == "Unauthorized" }},
	}
	for _, p := range puertas {
		t.Run(p.ruta, func(t *testing.T) {
			b := montarConAccesos(t)
			galleta := b.entrar(t, "u-ana")
			// (El canal NO se prueba antes de la marca: sin marca contesta 200 y se queda abierto
			// para siempre; que abre con la cookie buena lo prueba `TestElAvisoDeAccesosCierra…`.)
			if p.ruta != "/api/eventos" {
				if rec := b.pide(p.ruta, galleta, ""); rec.Code == http.StatusUnauthorized {
					t.Fatalf("la cookie recién emitida ya da 401 en %s sin ninguna marca", p.ruta)
				}
			}

			b.marca("web", sesiones.TipoSesionCerrada, ahoraMs()+1, "u-ana")
			rec := b.pide(p.ruta, galleta, "")

			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("%s con la cookie anterior a la marca dio %d, se esperaba 401", p.ruta, rec.Code)
			}
			if !p.cuerpo(strings.TrimSpace(rec.Body.String())) {
				t.Errorf("%s: el 401 no tiene la forma de esa puerta: %q", p.ruta, rec.Body.String())
			}
			if !laCookieBorrada(t, rec, galleta) {
				t.Errorf("%s: el 401 no borra la cookie: el navegador seguiría mandándola", p.ruta)
			}
			if !strings.Contains(b.logs.String(), "sesión web invalidada desde Accesos") {
				t.Error("no quedó escrito en el registro que Accesos invalidó la sesión")
			}
			// EL REGISTRO NO LLEVA EL TOKEN: un registro acaba pegado en un correo y en un chat.
			for _, parte := range strings.Split(galleta.Value, ".") {
				if strings.Contains(b.logs.String(), parte) {
					t.Fatalf("el registro filtra una parte del token: %q…", parte[:12])
				}
			}
		})
	}
}

// Cualquiera de los dos alcances invalida la cookie web, y también `permisos-cambiados`.
func TestLosDosAlcancesInvalidanLaCookieWeb(t *testing.T) {
	for _, alcance := range []string{"web", "todo"} {
		for _, tipo := range []string{sesiones.TipoSesionCerrada, sesiones.TipoPermisosCambiados} {
			b := montarConAccesos(t)
			galleta := b.entrar(t, "u-ana")
			b.marca(alcance, tipo, ahoraMs()+1, "u-ana")
			if rec := b.pide("/api/apps", galleta, ""); rec.Code != http.StatusUnauthorized {
				t.Errorf("alcance %s, tipo %s: dio %d, se esperaba 401", alcance, tipo, rec.Code)
			}
		}
	}
}

// CERRAR SESIÓN EN ACCESOS Y VOLVER A ENTRAR: la cookie de antes ya no vale; la nueva, sí.
func TestVolverAEntrarDespuesDeLaMarcaDejaPasarConLaCookieNueva(t *testing.T) {
	b := montarConAccesos(t)
	vieja := b.entrar(t, "u-ana")
	b.marca("web", sesiones.TipoSesionCerrada, ahoraMs(), "u-ana")
	time.Sleep(5 * time.Millisecond) // la nueva se emite DESPUÉS de la marca, en otro milisegundo
	nueva := b.entrar(t, "u-ana")

	if rec := b.pide("/api/apps", vieja, ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("la cookie vieja dio %d, se esperaba 401", rec.Code)
	}
	if rec := b.pide("/api/apps", nueva, ""); rec.Code != http.StatusOK {
		t.Errorf("la cookie emitida DESPUÉS de la marca dio %d, se esperaba 200: un bucle de entrada", rec.Code)
	}
}

func TestSinMarcaOConMarcaDeOtraPersonaNadaSeInvalida(t *testing.T) {
	b := montarConAccesos(t)
	galleta := b.entrar(t, "u-ana")
	for _, ruta := range []string{"/api/apps", "/api/me"} {
		if rec := b.pide(ruta, galleta, ""); rec.Code != http.StatusOK {
			t.Errorf("sin marca, %s dio %d", ruta, rec.Code)
		}
	}
	b.marca("todo", sesiones.TipoSesionCerrada, ahoraMs()+1000, "u-beto")
	if rec := b.pide("/api/apps", galleta, ""); rec.Code != http.StatusOK {
		t.Errorf("con la marca de OTRA persona, la cookie de Ana dio %d: se invalidó a quien no tocaba", rec.Code)
	}
}

// COOKIES SIN `iatms` (emitidas antes de este cambio, 08/10/2026): con marca de esa persona se
// invalidan —valen como emitidas en el instante 0—, pero sin marca NO se rechazan por faltarles
// el claim: al desplegar no se echa a nadie.
func TestUnaCookieSinIatMsSoloSeInvalidaSiHayMarca(t *testing.T) {
	b := montarConAccesos(t)
	vieja := &http.Cookie{Name: nombreDeLaCookie, Value: tokenDePanel(t, map[string]any{
		"sub": "u-ana", "role": "SUPER ADMIN", "iat": time.Now().Unix(),
	})}
	if _, hay := iatmsDe(t, vieja.Value); hay {
		t.Fatal("la cookie de la prueba tenía que ser SIN iatms")
	}

	for _, ruta := range []string{"/api/apps", "/api/me"} {
		if rec := b.pide(ruta, vieja, ""); rec.Code != http.StatusOK {
			t.Fatalf("sin marca, la cookie sin iatms dio %d en %s: se echaría a todos al desplegar", rec.Code, ruta)
		}
	}
	b.marca("web", sesiones.TipoSesionCerrada, 1, "u-ana") // una marca ANTIGUA vale: iatms ausente = instante 0
	for _, ruta := range []string{"/api/apps", "/api/me"} {
		if rec := b.pide(ruta, vieja, ""); rec.Code != http.StatusUnauthorized {
			t.Errorf("con marca, la cookie sin iatms dio %d en %s, se esperaba 401", rec.Code, ruta)
		}
	}
}

// LA WEB MANDA LA COOKIE *Y* EL MISMO TOKEN COMO BEARER (su interceptor, `interceptor_sesion.dart`,
// pone `Authorization: Bearer <token de /api/me>` en toda llamada). Si "el Bearer no se mira", casi
// ninguna llamada de la web se comprobaría nunca. Esta prueba es la que lo ata.
func TestLaWebQueMandaLaCookieYElMismoBearerTambienSeInvalida(t *testing.T) {
	b := montarConAccesos(t)
	galleta := b.entrar(t, "u-ana")
	if rec := b.pide("/api/apps", galleta, galleta.Value); rec.Code != http.StatusOK {
		t.Fatalf("cookie + bearer iguales dio %d antes de la marca", rec.Code)
	}
	b.marca("web", sesiones.TipoSesionCerrada, ahoraMs()+1, "u-ana")
	rec := b.pide("/api/apps", galleta, galleta.Value)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("cookie + bearer iguales dio %d tras la marca: la web seguiría dentro con cada llamada", rec.Code)
	}
	if !laCookieBorrada(t, rec, galleta) {
		t.Error("no se borró la cookie")
	}
}

// Un token de la WEB (lleva `iatms`) que llega SOLO como Bearer —la app lo guarda en memoria y la
// cookie ya se borró— sigue siendo una sesión web, y se mira.
func TestUnTokenDeLaWebQueLlegaSoloComoBearerTambienSeMira(t *testing.T) {
	b := montarConAccesos(t)
	galleta := b.entrar(t, "u-ana")
	b.marca("web", sesiones.TipoSesionCerrada, ahoraMs()+1, "u-ana")
	if rec := b.pide("/api/apps", nil, galleta.Value); rec.Code != http.StatusUnauthorized {
		t.Fatalf("el token de la web, sin cookie y como Bearer, dio %d: tras borrarse la cookie seguiría "+
			"valiendo siete días", rec.Code)
	}
}

// UN BEARER VIEJO DELANTE DE UNA COOKIE NUEVA no echa a quien ya volvió a entrar: la credencial
// invalidada cuenta como un fallo más y gana la buena. Y NO se le borra la cookie buena.
func TestUnBearerViejoNoEchaALaCookieRecienEmitida(t *testing.T) {
	b := montarConAccesos(t)
	vieja := b.entrar(t, "u-ana")
	b.marca("web", sesiones.TipoSesionCerrada, ahoraMs(), "u-ana")
	time.Sleep(5 * time.Millisecond)
	nueva := b.entrar(t, "u-ana")

	rec := b.pide("/api/apps", nueva, vieja.Value) // lo que la pestaña vieja todavía lleva en memoria
	if rec.Code != http.StatusOK {
		t.Fatalf("dio %d: el Bearer viejo tapó a la cookie nueva", rec.Code)
	}
	if laCookieBorrada(t, rec, nueva) {
		t.Error("se borró la cookie buena por culpa del Bearer viejo")
	}
}

// LAS CUENTAS DE SERVICIO NO PREGUNTAN POR SESIONES: la llave entra por su puerta y el verificador
// ni se toca.
func TestLaClaveDeServicioNoPreguntaPorSesiones(t *testing.T) {
	b := montarConAccesos(t)
	var preguntas atomic.Int32
	b.s.verif.ConInvalidaciones(contadorDeInvalidaciones{&preguntas}, nil)

	r := httptest.NewRequest(http.MethodGet, "http://reparto.test/api/de-servicio", nil)
	r.Header.Set("X-Api-Key", "llave-de-servicio-de-prueba")
	rec := httptest.NewRecorder()
	b.h.ServeHTTP(rec, r)

	if rec.Code != http.StatusOK {
		t.Fatalf("la clave de servicio dio %d", rec.Code)
	}
	if n := preguntas.Load(); n != 0 {
		t.Errorf("una cuenta de servicio provocó %d consultas de sesión", n)
	}
}

type contadorDeInvalidaciones struct{ n *atomic.Int32 }

func (c contadorDeInvalidaciones) LaCookieNoVale(string, int64) bool        { c.n.Add(1); return true }
func (c contadorDeInvalidaciones) ElBearerNoVale(string, int64, int64) bool { c.n.Add(1); return true }

// SIN EL EMPUJE ENGANCHADO (Redis sin configurar) LA API ES LA DE SIEMPRE: la cookie vale.
func TestSinElEmpujeEnganchadoLaApiSirveComoAntes(t *testing.T) {
	b := montarConAccesos(t)
	b.s.verif.ConInvalidaciones(nil, nil)
	galleta := b.entrar(t, "u-ana")
	b.marca("todo", sesiones.TipoSesionCerrada, ahoraMs()+1000, "u-ana")
	if rec := b.pide("/api/apps", galleta, ""); rec.Code != http.StatusOK {
		t.Errorf("sin empuje enganchado dio %d", rec.Code)
	}
}

// ---------------------------------------------------------------------------
// El SSE: se avisa a ESA persona y se le cierra la conexión.
// ---------------------------------------------------------------------------

func abrirEventos(t *testing.T, srv *httptest.Server, galleta *http.Cookie) (<-chan string, func()) {
	t.Helper()
	r, err := http.NewRequest(http.MethodGet, srv.URL+"/api/eventos", nil)
	if err != nil {
		t.Fatal(err)
	}
	r.AddCookie(&http.Cookie{Name: galleta.Name, Value: galleta.Value})
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("el canal dio %d", resp.StatusCode)
	}
	lineas := lineasDeEventos(resp.Body)
	esperarLinea(t, lineas, "event: listo", time.Second)
	return lineas, func() { _ = resp.Body.Close() }
}

// El flujo ha terminado: el servidor cerró la conexión.
func seCerro(lineas <-chan string, plazo time.Duration) bool {
	limite := time.After(plazo)
	for {
		select {
		case _, abierto := <-lineas:
			if !abierto {
				return true
			}
		case <-limite:
			return false
		}
	}
}

func TestElAvisoDeAccesosCierraSoloLasConexionesDeEsaPersona(t *testing.T) {
	for _, c := range []struct{ alcance, tipo string }{
		{"web", sesiones.TipoSesionCerrada},
		{"todo", sesiones.TipoPermisosCambiados},
	} {
		t.Run(c.tipo, func(t *testing.T) {
			b := montarConAccesos(t)
			srv := httptest.NewServer(b.h)
			defer srv.Close()

			ana, beto := b.entrar(t, "u-ana"), b.entrar(t, "u-beto")
			anaUno, cerrarA1 := abrirEventos(t, srv, ana)
			defer cerrarA1()
			anaDos, cerrarA2 := abrirEventos(t, srv, ana) // la misma persona en otra pestaña
			defer cerrarA2()
			betoUno, cerrarB := abrirEventos(t, srv, beto)
			defer cerrarB()
			if b.bus.Abonados() != 3 {
				t.Fatalf("hay %d conexiones, se esperaban 3", b.bus.Abonados())
			}

			b.marca(c.alcance, c.tipo, ahoraMs()+1, "u-ana")

			for i, lineas := range []<-chan string{anaUno, anaDos} {
				if l := esperarLinea(t, lineas, "event: sesion-invalidada", time.Second); l == "" {
					t.Fatalf("pestaña %d de Ana sin evento", i+1)
				}
				dato := esperarLinea(t, lineas, "data:", time.Second)
				if dato != `data: {"tipo":"`+c.tipo+`"}` {
					t.Errorf("pestaña %d de Ana: el dato es %q", i+1, dato)
				}
				if !seCerro(lineas, time.Second) {
					t.Errorf("pestaña %d de Ana: la conexión sigue abierta tras el aviso: con una sesión muerta "+
						"seguiría recibiendo los avisos de su sucursal", i+1)
				}
			}
			// La de Beto, ni enterada: sigue abierta y sigue recibiendo lo suyo.
			if seCerro(betoUno, 200*time.Millisecond) {
				t.Fatal("se le cerró la conexión a OTRA persona: el aviso se repartió a todos")
			}
			b.bus.Avisar(CambioPedidos, nil)
			if l := esperarLinea(t, betoUno, "event: ", time.Second); strings.Contains(l, "sesion-invalidada") {
				t.Errorf("Beto recibió el aviso de la sesión de Ana: %q", l)
			}
			esperarA(t, time.Second, func() bool { return b.bus.Abonados() == 1 }, "quedan conexiones de Ana abiertas")

			// Y si Ana reconecta con la cookie vieja, se encuentra el 401 (y el borrado).
			rec := b.pide("/api/eventos", ana, "")
			if rec.Code != http.StatusUnauthorized || !laCookieBorrada(t, rec, ana) {
				t.Errorf("al reconectar con la cookie vieja: %d, borrada=%v", rec.Code, laCookieBorrada(t, rec, ana))
			}
		})
	}
}

// EL CONTRATO CON LA APP, ATADO: el nombre del evento. Renombrar un lado sin el otro deja a la web
// sin enterarse de que su sesión murió, y no falla nada.
func TestElNombreDelEventoDeSesionInvalidadaNoSeRenombraSolo(t *testing.T) {
	if NombreDeSesionInvalidada != "sesion-invalidada" {
		t.Fatalf("el evento se llama %q y la app (`eventos_web.dart`) espera «sesion-invalidada»", NombreDeSesionInvalidada)
	}
}

// El aviso por el difusor, sin HTTP: una conexión SIN dueño conocido (`Suscribir()` a secas, como
// las de las pruebas viejas) no recibe nunca un aviso de persona, y una persona con la cola llena
// no bloquea a quien avisa.
func TestElAvisoDePersonaNoLlegaALasConexionesSinDuenoNiBloquea(t *testing.T) {
	d := NuevoDifusor()
	sinDueno, cortarS, _ := d.Suscribir()
	defer cortarS()
	ana, cortarA, _ := d.SuscribirComo("", "u-ana", true)
	defer cortarA()

	d.SesionInvalidada(sesiones.AlcanceTodo, sesiones.TipoSesionCerrada, []string{"", "u-ana"})
	select {
	case c := <-sinDueno:
		t.Errorf("una conexión sin dueño recibió %+v", c)
	default:
	}
	select {
	case c := <-ana:
		if c.Tipo != NombreDeSesionInvalidada {
			t.Errorf("Ana recibió %+v", c)
		}
	default:
		t.Error("Ana no recibió el aviso")
	}

	// Cola llena: no se bloquea y la conexión se cierra (al reconectar se encontrará el 401).
	lenta, cortarL, _ := d.SuscribirComo("", "u-lenta", true)
	defer cortarL()
	for i := 0; i < colaAbonado; i++ {
		d.Avisar(CambioRutas, nil) // CambioRutas no se frena: llena la cola de todos
	}
	hecho := make(chan struct{})
	go func() {
		d.SesionInvalidada(sesiones.AlcanceWeb, sesiones.TipoSesionCerrada, []string{"u-lenta"})
		close(hecho)
	}()
	select {
	case <-hecho:
	case <-time.After(time.Second):
		t.Fatal("avisar a un abonado con la cola llena bloqueó al que avisa")
	}
	cerrada := make(chan struct{})
	go func() {
		for range lenta { // vacía lo que traía; sólo termina si el canal se cerró
		}
		close(cerrada)
	}()
	select {
	case <-cerrada:
	case <-time.After(time.Second):
		t.Error("la conexión lenta no se cerró: se quedaría sin enterarse de que su sesión murió")
	}
	if d.Abonados() != 2 {
		t.Errorf("hay %d abonados, se esperaban 2 (la lenta ya no está)", d.Abonados())
	}
}
