package api

// EL CABLEADO DE `main`, PROBADO (09/10/2026).
//
// El 08/10/2026 una auditoría quitó `inv.AlEvento = busEventos.SesionInvalidada` y toda la suite
// siguió en verde: las pruebas de `la_sesion_web_la_invalida_accesos_test.go` montan el servidor a
// mano y se enganchan SU PROPIO bus, y `cmd/api` no tiene pruebas, así que lo que de verdad se cose
// al arrancar no lo pisaba nada. Estas pruebas construyen el servidor con
// [NuevoServidorConSesiones] —la función que llama `cmd/api/main.go`, y nada más— y alimentan al
// suscriptor desde memoria, como si el mensaje llegase del canal de Redis: lo que se mira es lo que
// ve el navegador y la APK, con las rutas de verdad (`Rutas()`) y el bus del proceso.
//
// Si una se pone roja, el empuje de Accesos no llega a la API tal como se arranca en producción.

import (
	"context"
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/sesiones"
)

// fuenteEnMemoria hace de Redis: lo que se mete en `msgs` es lo que "publica Accesos".
type fuenteEnMemoria struct{ msgs chan string }

func (f *fuenteEnMemoria) Suscribir(context.Context) (sesiones.Suscripcion, error) {
	return suscripcionEnMemoria{f.msgs}, nil
}
func (f *fuenteEnMemoria) Marcas(context.Context) (sesiones.Marcas, error) {
	return sesiones.Marcas{}, nil
}
func (f *fuenteEnMemoria) Cerrar() error { return nil }

type suscripcionEnMemoria struct{ msgs <-chan string }

func (s suscripcionEnMemoria) Siguiente(ctx context.Context) (string, error) {
	select {
	case m := <-s.msgs:
		return m, nil
	case <-ctx.Done():
		return "", ctx.Err()
	}
}
func (suscripcionEnMemoria) Cerrar() error { return nil }

// comoMain monta el servidor como `cmd/api` y lo hace correr como `cmd/api` (`inv.Correr` en su
// gorutina). `publicar` mete un mensaje de Accesos por el "canal".
type comoMain struct {
	h        http.Handler
	srv      *httptest.Server
	inv      *sesiones.Registro
	publicar func(alcance, tipo string, tms int64, personas ...string)
}

func montarComoMain(t *testing.T) *comoMain {
	t.Helper()
	t.Setenv("PROCOVAR_PUBLIC_URL", "")
	// El bus del PROCESO, que es el que engancha `NuevoServidorConSesiones`; limpio para esta prueba.
	anterior := busEventos
	t.Cleanup(func() { busEventos = anterior })
	busEventos = NuevoDifusor()

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
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	cfg := &config.Config{
		JWTSecret:      []byte(secretoDePanel),
		AuthURL:        accesos.URL,
		AuthClientID:   "reparto",
		AuthSigningKey: llaveDeFirma,
		ServiceAPIKey:  "llave-de-servicio-de-prueba",
	}
	msgs := make(chan string, 16)
	s, inv := NuevoServidorConSesiones(cfg, reg,
		alcance.NuevaPorteria(fuenteDePanel{q: &dobleDePanel{}}, reg),
		auth.NuevoVerificador([]byte(secretoDePanel)), nil, &fuenteEnMemoria{msgs})

	ctx, parar := context.WithCancel(context.Background())
	hecho := make(chan struct{})
	go func() { defer close(hecho); inv.Correr(ctx) }()
	t.Cleanup(func() { parar(); <-hecho })
	esperarA(t, 2*time.Second, inv.Activo, "el suscriptor no llegó a estar activo")

	h := s.Rutas()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return &comoMain{h: h, srv: srv, inv: inv, publicar: func(alc, tipo string, tms int64, personas ...string) {
		ids, _ := json.Marshal(personas)
		msgs <- `{"v":1,"tipo":"` + tipo + `","alcance":"` + alc + `","userIds":` + string(ids) +
			`,"tms":` + itoaMs(tms) + `,"motivo":"prueba"}`
	}}
}

func (m *comoMain) entrar(t *testing.T, persona string) *http.Cookie {
	t.Helper()
	rec := httptest.NewRecorder()
	m.h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "http://reparto.test/api/auth/callback?code="+persona, nil))
	if rec.Code != http.StatusFound {
		t.Fatalf("la vuelta de Accesos dio %d: %s", rec.Code, rec.Body.String())
	}
	return laCookie(t, rec)
}

// codigoDe pide /api/me (sin base de datos) con la cookie y/o el Bearer, y devuelve el código.
func (m *comoMain) codigoDe(cookie *http.Cookie, bearer string) int {
	r := httptest.NewRequest(http.MethodGet, "http://reparto.test/api/me", nil)
	if cookie != nil {
		r.AddCookie(&http.Cookie{Name: cookie.Name, Value: cookie.Value})
	}
	if bearer != "" {
		r.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	m.h.ServeHTTP(rec, r)
	return rec.Code
}

func (m *comoMain) esperarMarcas(t *testing.T, n int) {
	t.Helper()
	esperarA(t, 2*time.Second, func() bool { return m.inv.NumMarcas() == n },
		"el suscriptor no aplicó el mensaje de Accesos")
}

// UN EVENTO DE ACCESOS LLEGA AL SSE DE ESA PERSONA, con el servidor como lo arma `main`: el
// difusor del proceso está enganchado al suscriptor. Quitar `inv.AlEvento = busEventos.…` deja a la
// web sin enterarse hasta que caduque su cookie (siete días) y sin que ninguna otra prueba lo vea.
func TestElServidorComoLoArmaMainLlevaUnEventoDeAccesosAlSSEDeEsaPersona(t *testing.T) {
	m := montarComoMain(t)
	ana, beto := m.entrar(t, "u-ana"), m.entrar(t, "u-beto")
	anaSSE, cerrarA := abrirEventos(t, m.srv, ana)
	defer cerrarA()
	betoSSE, cerrarB := abrirEventos(t, m.srv, beto)
	defer cerrarB()

	m.publicar("web", sesiones.TipoSesionCerrada, ahoraMs()+1, "u-ana")

	esperarLinea(t, anaSSE, "event: sesion-invalidada", 2*time.Second)
	if dato := esperarLinea(t, anaSSE, "data:", time.Second); dato != `data: {"tipo":"sesion-cerrada"}` {
		t.Errorf("el dato del aviso es %q", dato)
	}
	if !seCerro(anaSSE, time.Second) {
		t.Error("la conexión de Ana sigue abierta tras el aviso")
	}
	if seCerro(betoSSE, 200*time.Millisecond) {
		t.Fatal("se le cerró la conexión a OTRA persona: el aviso se repartió a todos")
	}
}

// Y EL VERIFICADOR TAMBIÉN ESTÁ ENGANCHADO: tras el mensaje, la cookie de la web y el Bearer de la
// APK dan 401 según su alcance. Sin pasarle el suscriptor al verificador, el SSE avisaría pero la
// API seguiría dejando pasar a la sesión muerta.
func TestElServidorComoLoArmaMainRechazaLaSesionInvalidadaPorAccesos(t *testing.T) {
	m := montarComoMain(t)
	ana := m.entrar(t, "u-ana")
	apk := tokenDeLaAPKConMs(t, "u-ana", ahoraMs())
	if c := m.codigoDe(ana, ""); c != http.StatusOK {
		t.Fatalf("la cookie recién emitida da %d antes de cualquier mensaje", c)
	}
	if c := m.codigoDe(nil, apk); c != http.StatusOK {
		t.Fatalf("el bearer de la APK da %d antes de cualquier mensaje", c)
	}

	// Un cierre de sesión WEB: echa a la cookie, no a la APK.
	m.publicar("web", sesiones.TipoSesionCerrada, ahoraMs()+10, "u-ana")
	m.esperarMarcas(t, 1)
	if c := m.codigoDe(ana, ""); c != http.StatusUnauthorized {
		t.Errorf("la cookie de Ana tras el cierre WEB da %d, se esperaba 401: el verificador no tiene al suscriptor", c)
	}
	if c := m.codigoDe(nil, apk); c != http.StatusOK {
		t.Errorf("el cierre WEB echó al bearer de la APK: %d", c)
	}

	// Un corte `todo`: echa también a la APK.
	m.publicar("todo", sesiones.TipoPermisosCambiados, ahoraMs()+10, "u-ana")
	esperarA(t, 2*time.Second, func() bool { return m.codigoDe(nil, apk) == http.StatusUnauthorized },
		"el bearer de la APK sigue valiendo tras un corte `todo`: el verificador no tiene al suscriptor")
}

// `main` SÓLO puede construir el servidor por la función de arriba, con la fuente real y haciéndola
// correr: llamar a `NuevoServidor` a secas, pasarle `nil` en lugar de `sesiones.DeRedis(cfg.Redis)` o
// no llamar a `inv.Correr(ctx)` lo dejaría sin empuje, y `cmd/api` no tiene pruebas que lo noten.
//
// Esto ANALIZA `main.go` con go/parser (no lo lee como texto): un comentario no cuenta. La versión
// de texto aceptaba `_ = ctx // inv.Correr(ctx)` y `nil /* sesiones.DeRedis(cfg.Redis) */`
// (re-auditoría 09/10/2026, N2/N3): la cadena seguía ahí y la llamada no. Es lo único que ata la última
// pieza sin arrancar una base de datos.
func TestMainConstruyeElServidorConElEmpujeDeAccesos(t *testing.T) {
	f, err := parser.ParseFile(token.NewFileSet(), "../../cmd/api/main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	var llamadas []*ast.CallExpr
	var registro string // el nombre al que main asigna el registro de sesiones
	conRedisReal := false
	ast.Inspect(f, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.CallExpr:
			llamadas = append(llamadas, x)
		case *ast.AssignStmt:
			if len(x.Lhs) != 2 || len(x.Rhs) != 1 {
				break
			}
			c, ok := x.Rhs[0].(*ast.CallExpr)
			if !ok || types.ExprString(c.Fun) != "api.NuevoServidorConSesiones" {
				break
			}
			if id, ok := x.Lhs[1].(*ast.Ident); ok {
				registro = id.Name
			}
			for _, a := range c.Args {
				// Una LLAMADA a DeRedis con la configuración de verdad: ni `nil`, ni una fuente de memoria.
				if k, ok := a.(*ast.CallExpr); ok && types.ExprString(k) == "sesiones.DeRedis(cfg.Redis)" {
					conRedisReal = true
				}
			}
		}
		return true
	})

	hayServidor, correBucle := false, false
	for _, c := range llamadas {
		nombre := types.ExprString(c.Fun)
		if nombre == "api.NuevoServidorConSesiones" {
			hayServidor = true
		}
		if registro != "" && registro != "_" && nombre == registro+".Correr" {
			correBucle = true
		}
		if s, ok := c.Fun.(*ast.SelectorExpr); ok && s.Sel.Name == "NuevoServidor" {
			t.Errorf("cmd/api/main.go llama a %s a secas: el servidor no llevaría el empuje de Accesos", nombre)
		}
	}
	if !hayServidor {
		t.Error("cmd/api/main.go ya no llama a api.NuevoServidorConSesiones: arrancaría sin el empuje de Accesos")
	}
	if !conRedisReal {
		t.Error("cmd/api/main.go no pasa sesiones.DeRedis(cfg.Redis) a NuevoServidorConSesiones (¿nil, un comentario?): " +
			"arrancaría sin el empuje de Accesos")
	}
	if !correBucle {
		t.Errorf("cmd/api/main.go no llama a %q.Correr(...) sobre el registro que devuelve NuevoServidorConSesiones "+
			"(¿comentado?): el suscriptor nunca escucharía", registro)
	}
}
