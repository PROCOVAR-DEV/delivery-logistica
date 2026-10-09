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

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sesiones"
)

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

	// (El cierre `web` de Ana deja su marca `web`, que NO toca al token de la APK; el `todo` de otra persona,
	// publicado DESPUÉS, sirve de testigo de que el primero ya se aplicó.)
	publicar("web", time.Now().UnixMilli()+10_000, "u-ana")
	publicar("todo", time.Now().UnixMilli()+10_000, "u-otra")
	esperarMarcas(t, inv, 2)
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
	var entrega, mias string    // y los de lo que devuelve FuentesDeEntrega (la entrega a revisión)
	var argsDeEntrega []string
	conRedisReal := false
	ast.Inspect(f, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.CallExpr:
			llamadas = append(llamadas, x)
		case *ast.SelectorExpr:
			// Ni llamada ni referencia: `identidad.Exigir(identidad.DeCabeceras, mux)` también se la salta.
			if id, ok := x.X.(*ast.Ident); ok && id.Name == "identidad" {
				switch x.Sel.Name {
				case "DeToken", "DeTokenConInvalidaciones", "DeCabeceras", "DeTokenDeEntrega":
					t.Errorf("cmd/sync/main.go usa identidad.%s directamente: se salta el cableado de FuenteDeLaCasa", x.Sel.Name)
				}
			}
		case *ast.AssignStmt:
			if len(x.Lhs) != 2 || len(x.Rhs) != 1 {
				break
			}
			c, ok := x.Rhs[0].(*ast.CallExpr)
			if ok && types.ExprString(c.Fun) == "identidad.FuentesDeEntrega" {
				if id, ok := x.Lhs[0].(*ast.Ident); ok {
					entrega = id.Name
				}
				if id, ok := x.Lhs[1].(*ast.Ident); ok {
					mias = id.Name
				}
				for _, a := range c.Args {
					argsDeEntrega = append(argsDeEntrega, types.ExprString(a))
				}
				break
			}
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

	correBucle, exigeLaFuente, montaLaRevision := false, false, false
	for _, c := range llamadas {
		nombre := types.ExprString(c.Fun)
		// EL MISMO MURO PARA TODA RUTA NORMAL: ningún `identidad.Exigir` de `main` puede recibir otra fuente que
		// la de FuenteDeLaCasa (la fuente de la entrega a revisión se monta DENTRO de `RutasDeRevision`, nunca
		// aquí a pelo: ahí es donde se colaría un token de entrega por una ruta de datos).
		if nombre == "identidad.Exigir" && len(c.Args) > 0 && types.ExprString(c.Args[0]) != fuente {
			t.Errorf("cmd/sync/main.go llama a identidad.Exigir(%s, …): sólo puede recibir la fuente de FuenteDeLaCasa (%q)",
				types.ExprString(c.Args[0]), fuente)
		}
		// Las dos rutas de la entrega, con LAS DOS fuentes que salieron de FuentesDeEntrega y EN ESE ORDEN:
		// cambiadas, `POST /sync/revision/entrega` aceptaría un token normal y `mias` sólo el de entrega.
		if strings.HasSuffix(nombre, ".RutasDeRevision") && len(c.Args) == 3 && entrega != "" && mias != "" &&
			types.ExprString(c.Args[1]) == entrega && types.ExprString(c.Args[2]) == mias {
			montaLaRevision = true
		}
		// LA BANDEJA DEL REVISOR SE MONTA DENTRO DE `Servicio.Rutas` (detrás del `Exigir` normal, que rechaza el
		// token de entrega), nunca desde `main` a pelo: montada en el mux público quedaría sin esa puerta.
		if strings.HasSuffix(nombre, ".RutasDelRevisor") {
			t.Errorf("cmd/sync/main.go llama a %s: la bandeja del revisor la monta Servicio.Rutas, detrás del Exigir normal", nombre)
		}
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
	if entrega == "" || mias == "" {
		t.Error("cmd/sync/main.go ya no asigna el resultado de identidad.FuentesDeEntrega(...): la entrega a revisión " +
			"no tendría puerta propia")
	}
	// Con lo que de verdad hace falta: el modo, el secreto, el registro de sesiones de FuenteDeLaCasa (un corte de
	// Accesos mata también al token de entrega) y LA fuente normal (de donde sale `mias`).
	if len(argsDeEntrega) != 5 || argsDeEntrega[0] != "cfg.Identidad" || argsDeEntrega[3] != registro ||
		argsDeEntrega[4] != fuente {
		t.Errorf("identidad.FuentesDeEntrega(%s) tiene que recibir (cfg.Identidad, secreto, resolutor, %s, %s)",
			strings.Join(argsDeEntrega, ", "), registro, fuente)
	}
	if !montaLaRevision {
		t.Errorf("cmd/sync/main.go no llama a <servicio>.RutasDeRevision(mux, %s, %s) con las fuentes de FuentesDeEntrega, "+
			"en ese orden: las rutas de entrega a revisión quedarían sin montar o con la puerta cambiada", entrega, mias)
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

// LA BANDEJA WEB (SERIO 2, 09/10/2026): la web llama a `sync` con el token de `/api/me` (el de la cookie, siete
// días, con `web:true`) como Bearer. Con la fuente como la arma `main`, un cierre de sesión SOLO-web de esa
// persona le cierra la puerta (401, antes 200 hasta los siete días), y el token de la APK de la misma persona
// sigue entrando. Un token web pedido DESPUÉS del cierre entra.
func TestLaFuenteComoLaArmaMainCierraLaPuertaAlTokenWebTrasUnCierreSoloWeb(t *testing.T) {
	h, publicar, inv := laCasa(t, "token")
	ahora := time.Now()
	web := func(persona string, emitido time.Time) string {
		return firmar(t, map[string]any{
			"sub": persona, "role": "ADMINISTRADOR", "branchId": uuid.New().String(), "web": true,
			"iat": emitido.Unix(), "iatms": emitido.UnixMilli(), "exp": ahora.Add(time.Hour).Unix(),
			"entradas": []string{llaveEntrarReparto},
		}, "HS256")
	}
	viejo := web("u-ana", ahora)
	apk := tokenDe(t, "u-ana", ahora.Unix())
	if codigoCon(h, viejo) != http.StatusOK || codigoCon(h, apk) != http.StatusOK {
		t.Fatal("sin marcas los dos tokens tenían que entrar")
	}

	publicar("web", ahora.UnixMilli()+1000, "u-ana") // cierra sesión en el navegador
	espera := time.Now().Add(2 * time.Second)
	for codigoCon(h, viejo) != http.StatusUnauthorized {
		if time.Now().After(espera) {
			t.Fatal("EL TOKEN WEB SIGUE ENTRANDO TRAS UN CIERRE DE SESIÓN SOLO-WEB: la bandeja del revisor queda abierta siete días")
		}
		time.Sleep(2 * time.Millisecond)
	}
	if c := codigoCon(h, apk); c != http.StatusOK {
		t.Errorf("el cierre solo-web echó al token de la APK de la misma persona: %d", c)
	}
	if c := codigoCon(h, web("u-ana", ahora.Add(5*time.Second))); c != http.StatusOK {
		t.Errorf("el token web pedido DESPUÉS del cierre no entra: %d", c)
	}
	if c := codigoCon(h, web("u-beto", ahora)); c != http.StatusOK {
		t.Errorf("el cierre de Ana echó a Beto: %d", c)
	}
	_ = inv
}

// `cmd/sync/main.go` SE NIEGA A ARRANCAR con la base atrasada (auditoría final, mutación 1.32: quitar la línea
// dejaba toda la suite en verde). Sin esto, un despliegue con la migración sin aplicar —la 00003 de la bandeja
// o la 00004 del tope del nombre— sirve tan tranquilo y falla más tarde, en la primera bandeja o el primer alta.
// Se ata por AST (un comentario no cuenta): tiene que ser `if err := <base>.ExigirMigraciones(ctx); err != nil {
// return … }` y venir ANTES de que el servidor escuche.
func TestMainSeNiegaAArrancarConLaBaseAtrasada(t *testing.T) {
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "../../cmd/sync/main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	var exige, escucha token.Pos
	devuelve := false
	ast.Inspect(f, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.IfStmt:
			a, ok := x.Init.(*ast.AssignStmt)
			if !ok || len(a.Lhs) != 1 || len(a.Rhs) != 1 {
				break
			}
			c, ok := a.Rhs[0].(*ast.CallExpr)
			if !ok || !strings.HasSuffix(types.ExprString(c.Fun), ".ExigirMigraciones") {
				break
			}
			exige = c.Pos()
			if types.ExprString(x.Cond) == types.ExprString(a.Lhs[0])+" != nil" {
				for _, st := range x.Body.List {
					if _, ok := st.(*ast.ReturnStmt); ok {
						devuelve = true
					}
				}
			}
		case *ast.CallExpr:
			if strings.HasSuffix(types.ExprString(x.Fun), ".ListenAndServe") && escucha == 0 {
				escucha = x.Pos()
			}
		}
		return true
	})
	switch {
	case exige == 0:
		t.Error("cmd/sync/main.go ya no hace `if err := <base>.ExigirMigraciones(ctx); err != nil { return … }`: " +
			"arrancaría con la base atrasada")
	case !devuelve:
		t.Error("main llama a ExigirMigraciones pero NO devuelve el error: seguiría arrancando con la base atrasada")
	case escucha == 0:
		t.Error("main ya no llama a ListenAndServe: la prueba no sabe en qué orden va")
	case exige > escucha:
		t.Error("ExigirMigraciones va DESPUÉS de ListenAndServe: el servidor ya estaría sirviendo")
	}
}
