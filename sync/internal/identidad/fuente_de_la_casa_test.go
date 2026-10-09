package identidad

// EL CABLEADO DE `cmd/sync`, PROBADO (09/10/2026).
//
// Quitar el registro de sesiones del verificador en `main` dejaba toda la suite en verde: las pruebas
// de `accesos_corta_la_sesion_test.go` se lo pasan a mano a `DeTokenConInvalidaciones`, y `cmd/sync`
// no tiene pruebas. Aquí se construye con [FuenteDeLaCasa] —lo único que llama `main`— y se alimenta
// al suscriptor desde memoria, como si el mensaje llegase del canal de Redis, de punta a punta por
// `Exigir`: lo que se mira es el código HTTP que ve la APK.

import (
	"context"
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"procovar/reparto-sync/internal/sesiones"
)

type fuenteEnMemoria struct{ msgs chan string }

func (f *fuenteEnMemoria) Suscribir(context.Context) (sesiones.Suscripcion, error) {
	return suscripcionEnMemoria{f.msgs}, nil
}
func (f *fuenteEnMemoria) Marcas(context.Context) (map[string]int64, error) { return nil, nil }
func (f *fuenteEnMemoria) Cerrar() error                                    { return nil }

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

// laCasa construye la fuente como `main` y hace correr el suscriptor como `main`.
func laCasa(t *testing.T, modo string) (h http.Handler, publicar func(alcance string, tms int64, persona string), inv *sesiones.Registro) {
	t.Helper()
	msgs := make(chan string, 16)
	fuente, inv := FuenteDeLaCasa(modo, []byte(secreto), nil, &fuenteEnMemoria{msgs},
		slog.New(slog.NewTextHandler(&strings.Builder{}, nil)))
	ctx, parar := context.WithCancel(context.Background())
	hecho := make(chan struct{})
	go func() { defer close(hecho); inv.Correr(ctx) }()
	t.Cleanup(func() { parar(); <-hecho })
	espera := time.Now().Add(2 * time.Second)
	for !inv.Activo() {
		if time.Now().After(espera) {
			t.Fatal("el suscriptor no llegó a estar activo")
		}
		time.Sleep(2 * time.Millisecond)
	}
	h = Exigir(fuente, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) }))
	publicar = func(alcance string, tms int64, persona string) {
		msgs <- `{"v":1,"tipo":"sesion-cerrada","alcance":"` + alcance + `","userIds":["` + persona +
			`"],"tms":` + strconv.FormatInt(tms, 10) + `}`
	}
	return h, publicar, inv
}

func codigoCon(h http.Handler, token string) int {
	r := httptest.NewRequest(http.MethodPost, "/sync/subida", nil)
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w.Code
}

// UN CORTE `todo` DE ACCESOS ECHA AL TOKEN ANTERIOR: con la fuente como la arma `main`, el verificador
// tiene al suscriptor. Un cierre `web` no toca a la APK. Sin el registro pasado al verificador, el
// token cortado seguiría entrando (y en `sync` entra la SUBIDA de la cola de ocho horas).
func TestLaFuenteComoLaArmaMainRechazaElTokenCortadoPorAccesos(t *testing.T) {
	h, publicar, inv := laCasa(t, "token")
	token := tokenDe(t, "u-ana", time.Now().Unix())
	if c := codigoCon(h, token); c != http.StatusOK {
		t.Fatalf("el token da %d antes de cualquier mensaje", c)
	}

	// (`sync` sólo guarda las marcas `todo`: el cierre `web` de Ana no deja marca; el de otra persona,
	// publicado DESPUÉS, sirve de testigo de que el primero ya se aplicó.)
	publicar("web", time.Now().UnixMilli()+10_000, "u-ana")
	publicar("todo", time.Now().UnixMilli()+10_000, "u-otra")
	esperarMarcas(t, inv, 1)
	if c := codigoCon(h, token); c != http.StatusOK {
		t.Errorf("un cierre WEB echó al token de la APK: %d", c)
	}

	publicar("todo", time.Now().UnixMilli()+10_000, "u-ana")
	espera := time.Now().Add(2 * time.Second)
	for codigoCon(h, token) != http.StatusUnauthorized {
		if time.Now().After(espera) {
			t.Fatal("el token sigue entrando tras un corte `todo` de Accesos: el verificador no tiene al suscriptor")
		}
		time.Sleep(2 * time.Millisecond)
	}
	if c := codigoCon(h, tokenDe(t, "u-beto", time.Now().Unix())); c != http.StatusOK {
		t.Errorf("el corte de Ana echó a Beto: %d", c)
	}
}

func esperarMarcas(t *testing.T, inv *sesiones.Registro, n int) {
	t.Helper()
	espera := time.Now().Add(2 * time.Second)
	for inv.NumMarcas() != n {
		if time.Now().After(espera) {
			t.Fatal("el suscriptor no aplicó el mensaje de Accesos")
		}
		time.Sleep(2 * time.Millisecond)
	}
}

// `cmd/sync/main.go` SÓLO puede sacar quién llama de [FuenteDeLaCasa], con la fuente real, hacer correr
// el registro y ponerle ESA fuente a `Exigir`: llamar a `DeToken` a secas, pasarle `nil` en vez de
// `sesiones.DeRedis(cfg.Redis)`, no llamar a `Correr`, quitar `identidad.Exigir(fuente, mux)` o
// dárselo con otra fuente que deje pasar a todos lo dejaría sin empuje (o sin puerta), y `cmd/sync` no
// tiene pruebas que lo noten.
//
// Esto ANALIZA `main.go` con go/parser (no lo lee como texto): un comentario no cuenta. La versión de
// texto aceptaba `_ = ctx // invalidaciones.Correr(ctx)` y `nil /* sesiones.DeRedis(cfg.Redis) */`
// (re-auditoría 09/10/2026, O2/O3), y `Exigir` no estaba atado (O7/O8).
func TestMainSacaQuienLlamaDeLaFuenteDeLaCasa(t *testing.T) {
	f, err := parser.ParseFile(token.NewFileSet(), "../../cmd/sync/main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	var llamadas []*ast.CallExpr
	var fuente, registro string // los nombres a los que main asigna lo que devuelve FuenteDeLaCasa
	conRedisReal := false
	ast.Inspect(f, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.CallExpr:
			llamadas = append(llamadas, x)
		case *ast.SelectorExpr:
			// Ni llamada ni referencia: `identidad.Exigir(identidad.DeCabeceras, mux)` también se la salta.
			if id, ok := x.X.(*ast.Ident); ok && id.Name == "identidad" {
				switch x.Sel.Name {
				case "DeToken", "DeTokenConInvalidaciones", "DeCabeceras":
					t.Errorf("cmd/sync/main.go usa identidad.%s directamente: se salta el cableado de FuenteDeLaCasa", x.Sel.Name)
				}
			}
		case *ast.AssignStmt:
			if len(x.Lhs) != 2 || len(x.Rhs) != 1 {
				break
			}
			c, ok := x.Rhs[0].(*ast.CallExpr)
			if !ok || types.ExprString(c.Fun) != "identidad.FuenteDeLaCasa" {
				break
			}
			if id, ok := x.Lhs[0].(*ast.Ident); ok {
				fuente = id.Name
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

	correBucle, exigeLaFuente := false, false
	for _, c := range llamadas {
		nombre := types.ExprString(c.Fun)
		if registro != "" && registro != "_" && nombre == registro+".Correr" {
			correBucle = true
		}
		// `Exigir` con EL identificador que salió de FuenteDeLaCasa, no con cualquier otra cosa.
		if nombre == "identidad.Exigir" && len(c.Args) > 0 && fuente != "" && fuente != "_" &&
			types.ExprString(c.Args[0]) == fuente {
			exigeLaFuente = true
		}
	}
	if fuente == "" {
		t.Error("cmd/sync/main.go ya no asigna el resultado de identidad.FuenteDeLaCasa(...): " +
			"arrancaría sin el empuje de Accesos")
	}
	if !conRedisReal {
		t.Error("cmd/sync/main.go no pasa sesiones.DeRedis(cfg.Redis) a FuenteDeLaCasa (¿nil, un comentario?): " +
			"arrancaría sin el empuje de Accesos")
	}
	if !correBucle {
		t.Errorf("cmd/sync/main.go no llama a %q.Correr(...) sobre el registro que devuelve FuenteDeLaCasa "+
			"(¿comentado?): el suscriptor nunca escucharía", registro)
	}
	if !exigeLaFuente {
		t.Errorf("cmd/sync/main.go no llama a identidad.Exigir(%s, …) con la fuente que devuelve FuenteDeLaCasa: "+
			"/sync/ quedaría sin puerta, o con una que deja pasar a todos", fuente)
	}
}

// En modo `cabeceras` no hay token que cortar: sigue siendo el de siempre.
func TestEnModoCabecerasLaFuenteNoMiraTokens(t *testing.T) {
	h, _, _ := laCasa(t, "cabeceras")
	r := httptest.NewRequest(http.MethodPost, "/sync/subida", nil)
	r.Header.Set("Authorization", "Bearer "+tokenDe(t, "u-ana", time.Now().Unix()))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized { // sin X-Persona no hay quién: DeCabeceras ignora el Bearer
		t.Errorf("en modo cabeceras, sin cabeceras de identidad, dio %d (se esperaba 401)", w.Code)
	}
}
