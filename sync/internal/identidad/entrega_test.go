package identidad

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// EL TOKEN DE ENTREGA A REVISIÓN (`docs/bandeja-de-revision.md`, B.1, paquete V).
//
// Dos cosas que no pueden separarse sin que salte algo:
//
//  1. Las rutas NORMALES rechazan todo token con `ambito`, lleve lo que lleve en `entradas`.
//  2. `DeTokenDeEntrega` acepta SÓLO el token de entrega, tal como lo firma Accesos.
//
// La tabla de casos es `docs/ambito-de-entrega.casos.json`, la misma que lee `api/internal/auth`.

var sucursalDeStg = uuid.MustParse("5a5a5a5a-0000-4000-8000-000000000001")

func resolutorDePrueba(_ context.Context, codigo string) (uuid.UUID, error) {
	if codigo == "STG" {
		return sucursalDeStg, nil
	}
	return uuid.Nil, ErrSinSesion
}

// elTokenDeEntrega: los claims de B.1.
func elTokenDeEntrega() map[string]any {
	return map[string]any{
		"sub": "p-yasmani", "name": "Yasmani", "email": "yasmani@procovar.cu", "sid": "ses-1",
		"sucursal": "STG", "branch_id": "STG", "purpose": PropositoEntrega, "ambito": AmbitoEntrega,
		"entradas": []string{}, "roles": []string{}, "role": "",
		"jti": "j-entrega-1", "iss": "https://auth.procovar.cloud",
		"iat": time.Now().Unix(), "iatms": time.Now().UnixMilli(), "exp": time.Now().Add(10 * time.Minute).Unix(),
	}
}

func con(base map[string]any, clave string, valor any) map[string]any {
	salida := map[string]any{}
	for k, v := range base {
		salida[k] = v
	}
	salida[clave] = valor
	return salida
}

func sin(base map[string]any, claves ...string) map[string]any {
	salida := map[string]any{}
	for k, v := range base {
		salida[k] = v
	}
	for _, c := range claves {
		delete(salida, c)
	}
	return salida
}

// tokenRoto: ni siquiera es un token de alguien con sesión (sin `sub`, sin `exp` o caducado).
func tokenRoto(claims map[string]any) bool {
	exp, hayExp := claims["exp"].(int64)
	sub, _ := claims["sub"].(string)
	return sub == "" || !hayExp || exp < time.Now().Unix()
}

func peticion(token string) *http.Request {
	r := httptest.NewRequest(http.MethodPost, "/sync/revision/entrega", nil)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	return r
}

func deEntrega(t *testing.T, claims map[string]any) (Identidad, error) {
	t.Helper()
	return DeTokenDeEntrega([]byte(secreto), resolutorDePrueba, nil)(peticion(firmar(t, claims, "HS256")))
}

func normal(t *testing.T, claims map[string]any) (Identidad, error) {
	t.Helper()
	return DeToken([]byte(secreto), resolutorDePrueba)(peticion(firmar(t, claims, "HS256")))
}

// LA TABLA COMPARTIDA, caso a caso.
func TestElAmbitoDeEntregaEsElDeLosCasosCompartidos(t *testing.T) {
	crudo, err := os.ReadFile("../../../docs/ambito-de-entrega.casos.json")
	if err != nil {
		t.Fatalf("no se pudo leer docs/ambito-de-entrega.casos.json: %v. En una imagen es que "+
			"deploy/Dockerfile.sync no lo copia", err)
	}
	var f struct {
		Constantes struct{ Ambito, Proposito, Llave string } `json:"constantes"`
		Base       map[string]map[string]any                 `json:"base"`
		Casos      []struct {
			Nombre  string         `json:"nombre"`
			Base    string         `json:"base"`
			Con     map[string]any `json:"con"`
			Sin     []string       `json:"sin"`
			Normal  string         `json:"normal"`
			Entrega string         `json:"entrega"`
		} `json:"casos"`
	}
	if err := json.Unmarshal(crudo, &f); err != nil || len(f.Casos) < 30 {
		t.Fatalf("el fichero de casos no se entiende o está casi vacío (%d): %v", len(f.Casos), err)
	}
	// Las constantes del fichero SON las del código: renombrar una sin la otra no pasa en silencio.
	if f.Constantes.Ambito != AmbitoEntrega || f.Constantes.Proposito != PropositoEntrega ||
		f.Constantes.Llave != llaveEntrarReparto {
		t.Fatalf("las constantes del fichero (%+v) no son las del código (%s, %s, %s)",
			f.Constantes, AmbitoEntrega, PropositoEntrega, llaveEntrarReparto)
	}

	entra, rechaza, acepta, rechazaEntrega := 0, 0, 0, 0
	for _, c := range f.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			base, hay := f.Base[c.Base]
			if !hay {
				t.Fatalf("el caso pide una base que no existe: %q", c.Base)
			}
			ahora := time.Now()
			claims := map[string]any{}
			for k, v := range base {
				claims[k] = v
			}
			claims["iat"] = ahora.Unix()
			claims["iatms"] = ahora.Unix() * 1000
			claims["exp"] = ahora.Add(10 * time.Minute).Unix()
			for k, v := range c.Con {
				if k == "exp" && v == "$caducado" {
					v = ahora.Add(-2 * time.Hour).Unix()
				} else if k == "exp" && v == "$doce_minutos" {
					v = ahora.Add(12 * time.Minute).Unix()
				} else if k == "exp" && v == "$larga" {
					v = ahora.Add(time.Hour).Unix()
				}
				claims[k] = v
			}
			for _, k := range c.Sin {
				delete(claims, k)
			}

			switch c.Normal {
			case "entra":
				if _, err := normal(t, claims); err != nil {
					t.Errorf("RUTAS NORMALES: los casos compartidos dicen que ENTRA y el sincronizador lo rechaza: %v", err)
				}
				entra++
			case "rechaza":
				_, err := normal(t, claims)
				if err == nil {
					t.Errorf("RUTAS NORMALES: los casos compartidos dicen que NO entra y el sincronizador lo deja pasar")
				} else if _, tieneAmbito := claims["ambito"]; tieneAmbito && !tokenRoto(claims) &&
					!errors.Is(err, ErrSinPermisoDeReparto) {
					// Con `ambito` el rechazo es el 403 de «sin permiso», no un 401 que mataría la sesión.
					// (Un token roto —sin sub, sin exp, caducado— es antes que nada un 401.)
					t.Errorf("con `ambito` se esperaba ErrSinPermisoDeReparto (403) y salió %v", err)
				}
				rechaza++
			case "":
			default:
				t.Fatalf("`normal` desconocido: %q", c.Normal)
			}

			switch c.Entrega {
			case "acepta":
				id, err := deEntrega(t, claims)
				if err != nil {
					t.Errorf("DeTokenDeEntrega: los casos compartidos dicen que ACEPTA y lo rechaza: %v", err)
				} else if id.Ambito != AmbitoEntrega || id.EsSuperAdmin || id.Token != "" {
					t.Errorf("DeTokenDeEntrega aceptó pero la identidad no es la de una entrega: %+v", id)
				}
				acepta++
			case "rechaza":
				if id, err := deEntrega(t, claims); err == nil {
					t.Errorf("DeTokenDeEntrega: los casos compartidos dicen que RECHAZA y lo acepta: %+v", id)
				}
				rechazaEntrega++
			case "":
			default:
				t.Fatalf("`entrega` desconocido: %q", c.Entrega)
			}
		})
	}
	// El fichero no se puede vaciar de un lado sin que se note.
	if entra < 2 || rechaza < 20 || acepta < 4 || rechazaEntrega < 20 {
		t.Errorf("la tabla compartida se quedó corta: entra=%d rechaza=%d acepta=%d rechazaEntrega=%d",
			entra, rechaza, acepta, rechazaEntrega)
	}

	// La imagen de `sync` tiene que copiar el fichero (no viaja dentro de ella, así que el chequeo sólo corre
	// donde está `deploy/`): sin él esta prueba hace Fatalf en la imagen y Dokploy deja corriendo el viejo.
	if d, err := os.ReadFile("../../../deploy/Dockerfile.sync"); err == nil &&
		!strings.Contains(string(d), "COPY docs/ambito-de-entrega.casos.json") {
		t.Errorf("deploy/Dockerfile.sync no copia docs/ambito-de-entrega.casos.json: la imagen no construiría")
	}
}

// LO QUE DEVUELVE: persona, nombre del TOKEN, sucursal traducida y jti. Nunca roles, nunca el token.
func TestElTokenDeEntregaDaLaIdentidadMinima(t *testing.T) {
	id, err := deEntrega(t, elTokenDeEntrega())
	if err != nil {
		t.Fatalf("el token de entrega legítimo no entró: %v", err)
	}
	if id.Persona != "p-yasmani" || id.Nombre != "Yasmani" || id.Jti != "j-entrega-1" ||
		id.Sucursal != sucursalDeStg || id.Ambito != AmbitoEntrega {
		t.Errorf("identidad inesperada: %+v", id)
	}
	if id.EsSuperAdmin {
		t.Error("un token de entrega JAMÁS es Super Admin")
	}
	if id.Token != "" {
		t.Error("el token de entrega NO se guarda en Identidad.Token: es lo que se reenvía al reparto, y éste no vale allí")
	}
}

// LA PAREJA: el token de entrega no entra por ninguna ruta normal (ni subida, ni bajada, ni estado, ni
// alta), con la fuente tal como la arma `main`.
func TestElTokenDeEntregaNoEntraPorLasRutasNormales(t *testing.T) {
	h, _, _ := laCasa(t, "token")
	for _, ruta := range []string{"/sync/subida", "/sync/bajada", "/sync/estado", "/sync/aparato", "/sync/revision"} {
		for nombre, claims := range map[string]map[string]any{
			"tal cual":                          elTokenDeEntrega(),
			"con la llave en entradas":          con(elTokenDeEntrega(), "entradas", []string{llaveEntrarReparto}),
			"con la llave y un rol que ve todo": con(con(elTokenDeEntrega(), "entradas", []string{llaveEntrarReparto}), "role", "SUPER ADMIN"),
		} {
			// La sucursal como uuid: `laCasa` no tiene resolutor.
			claims = con(con(claims, "branch_id", uuid.NewString()), "sucursal", uuid.NewString())
			r := httptest.NewRequest(http.MethodPost, ruta, nil)
			r.Header.Set("Authorization", "Bearer "+firmar(t, claims, "HS256"))
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			if w.Code != http.StatusForbidden {
				t.Errorf("%s %s: dio %d, se esperaba el 403 sin_permiso_reparto", ruta, nombre, w.Code)
			}
			if !strings.Contains(w.Body.String(), CodigoSinPermisoReparto) {
				t.Errorf("%s %s: el cuerpo no lleva %q: %s", ruta, nombre, CodigoSinPermisoReparto, w.Body.String())
			}
		}
	}
}

// Y AL REVÉS: un token normal, con la llave, tampoco es un token de entrega: 403 sin_permiso_reparto
// (el contrato de S1), no un 401 que el cliente leería como «la sesión murió».
func TestUnTokenNormalNoEsDeEntrega(t *testing.T) {
	normalConLlave := map[string]any{
		"sub": "p-ana", "role": "LOGISTICO", "branchId": uuid.NewString(),
		"entradas": []string{llaveEntrarReparto}, "jti": "j-n", "iat": time.Now().Unix(),
		"exp": time.Now().Add(10 * time.Minute).Unix(),
	}
	_, err := deEntrega(t, normalConLlave)
	if !errors.Is(err, ErrNoEsDeEntrega) || !errors.Is(err, ErrSinPermisoDeReparto) {
		t.Fatalf("un token normal en DeTokenDeEntrega tenía que dar ErrNoEsDeEntrega (403): %v", err)
	}

	entrega, mias := FuentesDeEntrega("token", []byte(secreto), resolutorDePrueba, nil, DeToken([]byte(secreto), resolutorDePrueba))
	puerta := func(f Fuente, token string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		Exigir(f, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })).
			ServeHTTP(w, peticion(token))
		return w
	}
	normalToken := firmar(t, normalConLlave, "HS256")
	if w := puerta(entrega, normalToken); w.Code != http.StatusForbidden || !strings.Contains(w.Body.String(), CodigoSinPermisoReparto) {
		t.Errorf("entrega con token normal: %d %s", w.Code, w.Body.String())
	}
	// `mias` es la excepción: acepta el normal (y el de entrega).
	if w := puerta(mias, normalToken); w.Code != http.StatusOK {
		t.Errorf("mias con token normal: %d %s", w.Code, w.Body.String())
	}
	if w := puerta(mias, firmar(t, elTokenDeEntrega(), "HS256")); w.Code != http.StatusOK {
		t.Errorf("mias con token de entrega: %d %s", w.Code, w.Body.String())
	}
	// Pero `mias` no abre la puerta a lo que ninguna de las dos fuentes acepta.
	for nombre, token := range map[string]string{
		"sin token":           "",
		"firma rota":          firmar(t, elTokenDeEntrega(), "HS256")[:len(firmar(t, elTokenDeEntrega(), "HS256"))-2] + "AA",
		"caducado":            firmar(t, con(elTokenDeEntrega(), "exp", time.Now().Add(-time.Hour).Unix()), "HS256"),
		"normal sin la llave": firmar(t, con(normalConLlave, "entradas", []string{}), "HS256"),
	} {
		if w := puerta(mias, token); w.Code == http.StatusOK {
			t.Errorf("mias dejó pasar un token %s", nombre)
		}
	}
	// En un token de entrega ROTO la entrega contesta 401, no 403.
	if w := puerta(entrega, firmar(t, con(elTokenDeEntrega(), "exp", time.Now().Add(-time.Hour).Unix()), "HS256")); w.Code != http.StatusUnauthorized {
		t.Errorf("un token de entrega caducado dio %d, se esperaba 401", w.Code)
	}
}

// Fuera del modo `token` no hay token de entrega posible, y no se abre nada por defecto.
func TestSinTokensNoHayEntrega(t *testing.T) {
	entrega, mias := FuentesDeEntrega("cabeceras", []byte(secreto), resolutorDePrueba, nil, DeCabeceras)
	if _, err := entrega(peticion(firmar(t, elTokenDeEntrega(), "HS256"))); !errors.Is(err, ErrSinSesion) {
		t.Errorf("en modo cabeceras la entrega aceptó un token: %v", err)
	}
	r := httptest.NewRequest(http.MethodGet, "/sync/revision/mias", nil)
	r.Header.Set("X-Persona", "p-1")
	r.Header.Set("X-Sucursal", uuid.NewString())
	if id, err := mias(r); err != nil || id.Persona != "p-1" {
		t.Errorf("en modo cabeceras `mias` cae a las cabeceras de siempre: %v %+v", err, id)
	}
}

// LA VIDA DEL TOKEN: Accesos firma 600 s. Más que el tope no es el diseño, y un `iat` en el futuro no
// puede alargarla.
func TestUnTokenDeEntregaNoVivePorEncimaDelTope(t *testing.T) {
	ahora := time.Now()
	for nombre, c := range map[string]map[string]any{
		"dura una hora": con(elTokenDeEntrega(), "exp", ahora.Add(time.Hour).Unix()),
		"iat en el futuro: la vida real se alarga": con(con(elTokenDeEntrega(), "iat", ahora.Add(2*time.Hour).Unix()), "exp", ahora.Add(2*time.Hour+10*time.Minute).Unix()),
	} {
		if id, err := deEntrega(t, c); err == nil {
			t.Errorf("%s: entró %+v", nombre, id)
		}
	}
	// Lo que dice VIVIR, no lo que le queda: nació hace una hora y le quedan 5 minutos. Accesos no firma eso.
	if id, err := deEntrega(t, con(con(elTokenDeEntrega(), "iat", ahora.Add(-time.Hour).Unix()), "exp", ahora.Add(5*time.Minute).Unix())); err == nil {
		t.Errorf("un token de entrega que vive 65 minutos entró: %+v", id)
	}
	// Los 10 minutos que firma Accesos y su holgura (hasta 10 min + 1) sí entran; 12 no.
	for _, minutos := range []time.Duration{10 * time.Minute, 10*time.Minute + 30*time.Second} {
		if _, err := deEntrega(t, con(elTokenDeEntrega(), "exp", ahora.Add(minutos).Unix())); err != nil {
			t.Errorf("%s de vida tendrían que entrar: %v", minutos, err)
		}
	}
	if id, err := deEntrega(t, con(elTokenDeEntrega(), "exp", ahora.Add(12*time.Minute).Unix())); err == nil {
		t.Errorf("12 minutos de vida entraron: %+v", id)
	}
}

// EL CORTE DE SESIONES DE ACCESOS TAMBIÉN MATA AL TOKEN DE ENTREGA: 401, no 403.
func TestUnCorteDeAccesosMataElTokenDeEntrega(t *testing.T) {
	inv := registroDePrueba()
	token := firmar(t, con(elTokenDeEntrega(), "iat", time.Now().Unix()), "HS256")
	f := DeTokenDeEntrega([]byte(secreto), resolutorDePrueba, inv)
	if _, err := f(peticion(token)); err != nil {
		t.Fatalf("antes del corte: %v", err)
	}
	corte(inv, "todo", time.Now().UnixMilli()+1000, "p-yasmani")
	_, err := f(peticion(token))
	if !errors.Is(err, ErrSesionInvalidada) || errors.Is(err, ErrSinPermisoDeReparto) {
		t.Errorf("tras el corte se esperaba ErrSesionInvalidada (401): %v", err)
	}
}

// `iatms` (extra de A1 respecto a B.1): el corte `todo` lo compara con ESE valor, como en el token normal
// (`todo >= iatms` ⇒ 401), y sin él cae a iat*1000.
func TestElCorteTodoUsaElIatMsDelTokenDeEntrega(t *testing.T) {
	ahoraMs := time.Now().UnixMilli()
	casos := []struct {
		nombre string
		claims map[string]any
		marca  int64
		pasa   bool
	}{
		{"emitido ANTES de la marca (iatms)", con(elTokenDeEntrega(), "iatms", ahoraMs-500), ahoraMs, false},
		{"emitido DESPUÉS de la marca (iatms)", con(elTokenDeEntrega(), "iatms", ahoraMs+500), ahoraMs, true},
		{"en el mismo milisegundo (todo >= iatms: 401)", con(elTokenDeEntrega(), "iatms", ahoraMs), ahoraMs, false},
		// El segundo entero del iat NO manda cuando hay iatms: iat dice que es posterior, iatms que no.
		{"iatms manda sobre iat", con(con(elTokenDeEntrega(), "iat", ahoraMs/1000+100), "iatms", ahoraMs-500), ahoraMs, false},
		{"sin iatms, cae a iat*1000", con(sin(elTokenDeEntrega(), "iatms"), "iat", ahoraMs/1000-5), ahoraMs, false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			inv := registroDePrueba()
			corte(inv, "todo", c.marca, "p-yasmani")
			// `exp` relativo al ahora real, sea cual sea el iat que se pidió.
			cl := con(c.claims, "exp", time.Now().Add(9*time.Minute).Unix())
			_, err := DeTokenDeEntrega([]byte(secreto), resolutorDePrueba, inv)(peticion(firmar(t, cl, "HS256")))
			if c.pasa && err != nil {
				t.Errorf("tenía que pasar: %v", err)
			}
			if !c.pasa && !errors.Is(err, ErrSesionInvalidada) {
				t.Errorf("tenía que dar ErrSesionInvalidada (401) y dio %v", err)
			}
		})
	}
}

// SI EL REPARTO NO CONTESTA (traduciendo el código de la sucursal), NO SE MATA LA SESIÓN: 503.
func TestSiElRepartoNoContestaLaEntregaDa503(t *testing.T) {
	f := DeTokenDeEntrega([]byte(secreto), func(context.Context, string) (uuid.UUID, error) {
		return uuid.Nil, ErrNoSePudoComprobar
	}, nil)
	w := httptest.NewRecorder()
	Exigir(f, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("llegó al manejador") })).
		ServeHTTP(w, peticion(firmar(t, elTokenDeEntrega(), "HS256")))
	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("dio %d, se esperaba 503", w.Code)
	}
}

// El nombre sale del TOKEN, recortado; un `name` raro no revienta.
func TestElNombreSaleDelToken(t *testing.T) {
	id, err := deEntrega(t, con(elTokenDeEntrega(), "name", "  Yasmani Pérez  "))
	if err != nil || id.Nombre != "Yasmani Pérez" {
		t.Errorf("nombre = %q (%v)", id.Nombre, err)
	}
	id, err = deEntrega(t, con(elTokenDeEntrega(), "name", 7))
	if err != nil || id.Nombre != "" {
		t.Errorf("un name que no es texto: %q (%v)", id.Nombre, err)
	}
	// Y en el token normal también se lee (el revisor firma con él).
	id, err = normal(t, map[string]any{
		"sub": "r-1", "name": "Marta Pérez", "role": "ADMINISTRADOR", "branch_id": "STG",
		"entradas": []string{llaveEntrarReparto}, "jti": "j-r", "exp": time.Now().Add(time.Hour).Unix(),
	})
	if err != nil || id.Nombre != "Marta Pérez" || id.Jti != "j-r" || id.Ambito != "" {
		t.Errorf("el normal: %+v (%v)", id, err)
	}
}

// SIN `exp` NO HAY SESIÓN QUE MUERA NUNCA, ni siquiera para un token que por lo demás entraría: la prueba
// vieja (`TestUnTokenSinExpNoVale`) usaba un token sin rol, que se rechazaba POR EL ROL y no por la
// caducidad, así que quitar la exigencia de `exp` salía en verde.
func TestSinExpUnTokenQueEntraríaNoEntra(t *testing.T) {
	bueno := map[string]any{
		"sub": "p-1", "role": "LOGISTICO", "branchId": uuid.NewString(),
		"entradas": []string{llaveEntrarReparto}, "iat": time.Now().Unix(),
	}
	if _, err := conToken(t, firmar(t, con(bueno, "exp", time.Now().Add(time.Hour).Unix()), "HS256")); err != nil {
		t.Fatalf("el control (con exp) tenía que entrar: %v", err)
	}
	if id, err := conToken(t, firmar(t, bueno, "HS256")); !errors.Is(err, ErrSinSesion) {
		t.Errorf("sin exp tenía que ser un 401 (ErrSinSesion) y fue %v %+v", err, id)
	}
	entrega := sin(elTokenDeEntrega(), "exp")
	if _, err := deEntrega(t, entrega); !errors.Is(err, ErrSinSesion) {
		t.Errorf("un token de entrega sin exp tenía que ser ErrSinSesion: %v", err)
	}
}

// SIN SUCURSAL NO HAY ALCANCE, y «sin alcance» no es «todas» (auditoría final, mutación 1.22): un token de entrega
// sin sucursal, o con ella en blanco, se rechaza ANTES de preguntarle nada al resolutor. Con un resolutor que
// acepta cualquier cosa —incluido el texto vacío— quitar la guarda dejaba pasar una identidad con una sucursal
// inventada; sólo el 400 del reparto, más abajo, lo habría frenado.
func TestUnTokenDeEntregaSinSucursalSeRechazaAntesDelResolutor(t *testing.T) {
	llamadas := 0
	quienSea := func(context.Context, string) (uuid.UUID, error) { llamadas++; return uuid.New(), nil }
	casos := map[string]map[string]any{
		"sin ninguna":   sin(elTokenDeEntrega(), "sucursal", "branch_id"),
		"todas vacías":  con(con(elTokenDeEntrega(), "sucursal", ""), "branch_id", ""),
		"sólo espacios": con(con(elTokenDeEntrega(), "sucursal", "   "), "branch_id", " "),
		"nulas":         con(con(elTokenDeEntrega(), "sucursal", nil), "branch_id", nil),
	}
	for nombre, claims := range casos {
		_, err := DeTokenDeEntrega([]byte(secreto), quienSea, nil)(peticion(firmar(t, claims, "HS256")))
		if !errors.Is(err, ErrSinSesion) {
			t.Errorf("%s: dio %v, se esperaba ErrSinSesion (la sucursal es obligatoria)", nombre, err)
		}
	}
	if llamadas != 0 {
		t.Errorf("el resolutor se llamó %d veces con una sucursal vacía: se le preguntó por un texto que no es una sucursal", llamadas)
	}
	// La pareja: con sucursal, sí entra y sí se traduce.
	if id, err := DeTokenDeEntrega([]byte(secreto), quienSea, nil)(peticion(firmar(t, elTokenDeEntrega(), "HS256"))); err != nil || id.Sucursal == uuid.Nil || llamadas != 1 {
		t.Errorf("el token bueno: %+v %v (resolutor llamado %d veces)", id, err, llamadas)
	}
}

// EL `exp` DEL TOKEN DE ENTREGA LLEGA A LA IDENTIDAD. El canal de avisos en vivo (`GET /sync/revision/eventos`)
// es un flujo largo abierto con un token de diez minutos, y se cierra solo cuando ese token caduca: el manejador
// no ve el token, sólo la [Identidad], así que si `Caduca` no sale de aquí no hay con qué cerrarlo. Sin esta
// prueba, quitar la asignación dejaría el canal fallando cerrado en producción y verde aquí.
func TestElTokenDeEntregaLlevaSuCaducidadALaIdentidad(t *testing.T) {
	exp := time.Now().Add(7 * time.Minute).Unix()
	id, err := deEntrega(t, con(elTokenDeEntrega(), "exp", exp))
	if err != nil {
		t.Fatal(err)
	}
	if !id.Caduca.Equal(time.Unix(exp, 0)) {
		t.Errorf("Caduca = %s, tenía que ser el `exp` del token (%s)", id.Caduca, time.Unix(exp, 0))
	}
	// Y un token normal no la lleva: no es de nadie que abra el canal.
	n, err := normal(t, sin(con(elTokenDeEntrega(), "entradas", []string{llaveEntrarReparto}), "ambito", "purpose"))
	if err != nil {
		t.Fatal(err)
	}
	if !n.Caduca.IsZero() {
		t.Errorf("un token normal trae Caduca = %s", n.Caduca)
	}
}
