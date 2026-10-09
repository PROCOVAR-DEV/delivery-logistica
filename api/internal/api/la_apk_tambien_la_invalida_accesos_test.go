package api

// LA APK Y EL ESCRITORIO TAMBIÉN, PERO SÓLO CON UN CORTE `todo` (08/10/2026, segunda fase).
//
// Jose: «la web es la web y las APK son la APK». Un cierre de sesión en el navegador (alcance
// `web`) no echa al teléfono; una revocación, una baja, un cambio de rol o de llaves (alcance
// `todo`) sí: un token de acceso de 15 minutos emitido ANTES de la marca da 401 en el acto, y
// la app renueva contra Accesos, que decide si la sesión murió o sólo falta un permiso. Sin esto,
// un corte de seguridad dejaba al teléfono sirviendo hasta quince minutos más.
//
// La regla pura (`todo >= iat*1000`, con el `iat` en SEGUNDOS y comparación por arriba) se ata en
// `internal/sesiones`; aquí se ata lo que ve el cliente, con el Bearer por cabecera y sin cookie.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/sesiones"
)

// tokenDeLaAPK: el de acceso que firma Accesos —sin `iatms`, con su `iat` en segundos—.
func tokenDeLaAPK(t *testing.T, persona string, iatSeg int64) string {
	t.Helper()
	return tokenDePanel(t, map[string]any{
		"sub": persona, "role": "SUPER ADMIN", "iat": iatSeg,
		"entradas": []string{"delivery.entrar"},
	})
}

// tokenDeLaAPKConMs es el de Accesos desde el 08/10/2026: además del `iat` en segundos lleva `iatms`.
func tokenDeLaAPKConMs(t *testing.T, persona string, iatMs int64) string {
	t.Helper()
	return tokenDePanel(t, map[string]any{
		"sub": persona, "role": "SUPER ADMIN", "iat": iatMs / 1000, "iatms": iatMs,
		"entradas": []string{"delivery.entrar"},
	})
}

func TestUnCierreWebNoTocaAlBearerDeLaAPK(t *testing.T) {
	b := montarConAccesos(t)
	apk := tokenDeLaAPK(t, "u-ana", time.Now().Unix())
	b.marca("web", sesiones.TipoSesionCerrada, ahoraMs()+10_000, "u-ana")

	for _, ruta := range []string{"/api/apps", "/api/me"} {
		if rec := b.pide(ruta, nil, apk); rec.Code != http.StatusOK {
			t.Errorf("un cierre de sesión WEB echó al bearer de la APK en %s: %d", ruta, rec.Code)
		}
	}
}

func TestUnCorteTodoDa401AlBearerDeLaAPKEnLasTresPuertasSinTocarCookies(t *testing.T) {
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
			apk := tokenDeLaAPK(t, "u-ana", time.Now().Unix())
			b.marca("todo", sesiones.TipoPermisosCambiados, ahoraMs()+1000, "u-ana")

			rec := b.pide(p.ruta, nil, apk)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("%s con un bearer anterior al corte `todo` dio %d, se esperaba 401 "+
					"(y NO 403: la app lo trata como sesión caducada y renueva)", p.ruta, rec.Code)
			}
			if !p.cuerpo(strings.TrimSpace(rec.Body.String())) {
				t.Errorf("%s: el 401 no tiene la forma de esa puerta: %q", p.ruta, rec.Body.String())
			}
			if len(rec.Result().Cookies()) != 0 {
				t.Errorf("%s: el 401 de la APK toca cookies: %v", p.ruta, rec.Result().Cookies())
			}
			if !strings.Contains(b.logs.String(), "sesión de la APK o el escritorio invalidada desde Accesos") {
				t.Error("no quedó escrito en el registro")
			}
			if strings.Contains(b.logs.String(), strings.Split(apk, ".")[2]) {
				t.Fatal("el registro filtra la firma del token")
			}
		})
	}
}

// Renovar (un token NUEVO, emitido después del corte) vuelve a dejar pasar: el 401 se arregla solo.
func TestElBearerRenovadoDespuesDelCorteVale(t *testing.T) {
	b := montarConAccesos(t)
	viejo := tokenDeLaAPK(t, "u-ana", time.Now().Unix())
	b.marca("todo", sesiones.TipoSesionCerrada, ahoraMs(), "u-ana")
	nuevo := tokenDeLaAPK(t, "u-ana", time.Now().Unix()+5) // la renovación llega más tarde, en otro segundo

	if rec := b.pide("/api/apps", nil, viejo); rec.Code != http.StatusUnauthorized {
		t.Errorf("el token viejo dio %d", rec.Code)
	}
	if rec := b.pide("/api/apps", nil, nuevo); rec.Code != http.StatusOK {
		t.Errorf("el token renovado después del corte dio %d: la app no podría volver a entrar", rec.Code)
	}
	// Y el corte es de ESA persona.
	if rec := b.pide("/api/apps", nil, tokenDeLaAPK(t, "u-beto", time.Now().Unix())); rec.Code != http.StatusOK {
		t.Errorf("el corte de Ana echó a Beto: %d", rec.Code)
	}
}

// Sin `iatms` el `iat` va en SEGUNDOS: lo emitido en el mismo segundo que la marca se invalida
// (conservador); en el siguiente, ya no.
func TestSinIatMsLaComparacionDelBearerEsConservadoraPorSegundos(t *testing.T) {
	b := montarConAccesos(t)
	iat := time.Now().Unix() - 10
	b.marca("todo", sesiones.TipoSesionCerrada, iat*1000+500, "u-ana")

	if rec := b.pide("/api/apps", nil, tokenDeLaAPK(t, "u-ana", iat)); rec.Code != http.StatusUnauthorized {
		t.Errorf("emitido en el mismo segundo que la marca: %d, se esperaba 401", rec.Code)
	}
	if rec := b.pide("/api/apps", nil, tokenDeLaAPK(t, "u-ana", iat+1)); rec.Code != http.StatusOK {
		t.Errorf("emitido el segundo siguiente: %d, se esperaba 200", rec.Code)
	}
}

// EL REBOTE (auditoría, 08/10/2026): la APK renueva en cuanto le llega el aviso, y con `iat*1000` un
// token pedido 250 ms DESPUÉS del evento se rechazaba en ~75 % de los casos. Con `iatms` manda el
// milisegundo exacto: 250 ms después vale, antes no, y sin él se cae a `iat*1000`.
func TestUnTokenPedido250MsDespuesDelCorteNoRebota(t *testing.T) {
	b := montarConAccesos(t)
	// Un milisegundo a mitad de segundo: `iat*1000` quedaría ANTES de la marca y lo invalidaría.
	marca := (time.Now().Unix()-30)*1000 + 100
	b.marca("todo", sesiones.TipoPermisosCambiados, marca, "u-ana")

	if rec := b.pide("/api/apps", nil, tokenDeLaAPKConMs(t, "u-ana", marca+250)); rec.Code != http.StatusOK {
		t.Errorf("el token renovado 250 ms después del corte dio %d: rebota", rec.Code)
	}
	if rec := b.pide("/api/apps", nil, tokenDeLaAPKConMs(t, "u-ana", marca-50)); rec.Code != http.StatusUnauthorized {
		t.Errorf("el token emitido 50 ms ANTES del corte dio %d, se esperaba 401", rec.Code)
	}
	// Sin `iatms` (un token de Accesos anterior a ese cambio) cae a iat*1000, que es conservador.
	if rec := b.pide("/api/apps", nil, tokenDeLaAPK(t, "u-ana", (marca+250)/1000)); rec.Code != http.StatusUnauthorized {
		t.Errorf("sin iatms, en el mismo segundo que la marca dio %d, se esperaba 401 (conservador)", rec.Code)
	}
}

// ACCESOS FIRMA `iatms` TAMBIÉN EN EL TOKEN DE LA APK, así que `iatms` ya no dice «esto es la web»:
// un token de la APK con `iatms` NO es una sesión web, y un cierre de sesión `web` no lo toca.
func TestUnTokenDeLaAPKConIatMsNoEsUnaSesionWeb(t *testing.T) {
	b := montarConAccesos(t)
	emitido := ahoraMs() - 5000
	b.marca("web", sesiones.TipoSesionCerrada, ahoraMs()+1000, "u-ana")

	for _, ruta := range []string{"/api/apps", "/api/me"} {
		if rec := b.pide(ruta, nil, tokenDeLaAPKConMs(t, "u-ana", emitido)); rec.Code != http.StatusOK {
			t.Errorf("un cierre WEB echó a un token de la APK que lleva iatms (%s): %d", ruta, rec.Code)
		}
	}
	b.marca("todo", sesiones.TipoSesionCerrada, ahoraMs()+1000, "u-ana")
	if rec := b.pide("/api/apps", nil, tokenDeLaAPKConMs(t, "u-ana", emitido)); rec.Code != http.StatusUnauthorized {
		t.Errorf("un corte todo no echó al token de la APK con iatms: %d", rec.Code)
	}
}

func TestUnBearerSinIatSoloSeInvalidaSiHayMarcaTodo(t *testing.T) {
	b := montarConAccesos(t)
	sinIat := tokenDePanel(t, map[string]any{"sub": "u-ana", "role": "SUPER ADMIN"})

	if rec := b.pide("/api/apps", nil, sinIat); rec.Code != http.StatusOK {
		t.Fatalf("sin marca, un bearer sin iat dio %d: no se echa a nadie por faltarle el claim", rec.Code)
	}
	b.marca("web", sesiones.TipoSesionCerrada, 1, "u-ana")
	if rec := b.pide("/api/apps", nil, sinIat); rec.Code != http.StatusOK {
		t.Errorf("una marca web invalidó a un bearer: %d", rec.Code)
	}
	b.marca("todo", sesiones.TipoSesionCerrada, 1, "u-ana")
	if rec := b.pide("/api/apps", nil, sinIat); rec.Code != http.StatusUnauthorized {
		t.Errorf("con marca todo, un bearer sin iat (instante 0) dio %d, se esperaba 401", rec.Code)
	}
}

// ---------------------------------------------------------------------------
// El SSE nativo: las conexiones de la APK reciben SÓLO los cortes `todo`.
// ---------------------------------------------------------------------------

func abrirEventosConBearer(t *testing.T, srv *httptest.Server, bearer string) (<-chan string, func()) {
	t.Helper()
	r, err := http.NewRequest(http.MethodGet, srv.URL+"/api/eventos", nil)
	if err != nil {
		t.Fatal(err)
	}
	r.Header.Set("Authorization", "Bearer "+bearer)
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("el canal con bearer dio %d", resp.StatusCode)
	}
	lineas := lineasDeEventos(resp.Body)
	esperarLinea(t, lineas, "event: listo", time.Second)
	return lineas, func() { _ = resp.Body.Close() }
}

func TestElSSEDeLaAPKRecibeSoloLosCortesTodo(t *testing.T) {
	b := montarConAccesos(t)
	srv := httptest.NewServer(b.h)
	defer srv.Close()

	web := b.entrar(t, "u-ana")
	anaWeb, c1 := abrirEventos(t, srv, web)
	defer c1()
	anaApk, c2 := abrirEventosConBearer(t, srv, tokenDeLaAPK(t, "u-ana", time.Now().Unix()))
	defer c2()
	betoApk, c3 := abrirEventosConBearer(t, srv, tokenDeLaAPK(t, "u-beto", time.Now().Unix()))
	defer c3()

	// 1 · Un cierre de sesión WEB: la web de Ana se entera y se cierra; su teléfono, ni enterado.
	b.marca("web", sesiones.TipoSesionCerrada, ahoraMs()+1, "u-ana")
	esperarLinea(t, anaWeb, "event: sesion-invalidada", time.Second)
	if !seCerro(anaWeb, time.Second) {
		t.Fatal("la web de Ana no se cerró")
	}
	if seCerro(anaApk, 200*time.Millisecond) {
		t.Fatal("un cierre de sesión WEB cerró la conexión de la APK de Ana")
	}

	// 2 · Un corte `todo`: ahora sí, el teléfono de Ana, y sólo el suyo.
	b.marca("todo", sesiones.TipoPermisosCambiados, ahoraMs()+2, "u-ana")
	esperarLinea(t, anaApk, "event: sesion-invalidada", time.Second)
	if dato := esperarLinea(t, anaApk, "data:", time.Second); dato != `data: {"tipo":"permisos-cambiados"}` {
		t.Errorf("el dato para la APK es %q", dato)
	}
	if !seCerro(anaApk, time.Second) {
		t.Fatal("la conexión de la APK de Ana sigue abierta tras el corte `todo`")
	}
	if seCerro(betoApk, 200*time.Millisecond) {
		t.Fatal("el corte de Ana cerró la conexión de Beto")
	}

	// 3 · Y si el teléfono reconecta con el token viejo, se encuentra el 401.
	if rec := b.pide("/api/eventos", nil, tokenDeLaAPK(t, "u-ana", time.Now().Unix()-30)); rec.Code != http.StatusUnauthorized {
		t.Errorf("al reconectar con el token viejo: %d", rec.Code)
	}
}
