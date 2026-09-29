package auth_test

// LAS GUARDAS DEL RENGLÓN QUE EXPLICA UN 401.
//
// El caso entero está en `rastro.go`: el 29/09/2026 a las 21:30:50 UTC, `GET /api/eventos`
// contestó 401 y el registro decía `motivo="el token está caducado"` y nada más. Con eso no
// se puede saber si el rechazado fue el navegador o el teléfono, que es la única pregunta
// que había, y la investigación costó una noche en vez de un minuto.
//
// Estas cuatro pruebas fijan lo que ese renglón tiene que decir y lo que NUNCA puede decir.

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/auth"
)

// campo saca el valor de un par de los de `slog` (clave, valor, clave, valor…). Devuelve
// "" si la clave no está, que es lo que hay que poder distinguir.
func campo(campos []any, clave string) string {
	for i := 0; i+1 < len(campos); i += 2 {
		if c, _ := campos[i].(string); c == clave {
			return fmt.Sprintf("%v", campos[i+1])
		}
	}
	return ""
}

// LA PRUEBA QUE HABRÍA CONTESTADO LA PREGUNTA DE ESA NOCHE.
//
// Dos rechazos idénticos en `motivo` —los dos «caducado»— tienen que distinguirse en el
// registro sin preguntarle nada a nadie: la web entra por cookie con una sesión de SIETE
// DÍAS (`duracionDeLaSesionWeb`) y la APK por cabecera con una de QUINCE MINUTOS.
func TestElRastroSeparaLaWebDeLaAPK(t *testing.T) {
	ahora := time.Date(2026, 9, 29, 21, 30, 50, 0, time.UTC)

	// La web: cookie, siete días de vida, caducada hace un minuto.
	nacioWeb := ahora.Add(-7*24*time.Hour - time.Minute)
	web := httptest.NewRequest(http.MethodGet, "/api/eventos", nil)
	web.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36")
	web.AddCookie(&http.Cookie{Name: "token", Value: firmar(t, "HS256", map[string]any{
		"id":  "quien-sea",
		"iat": nacioWeb.Unix(),
		"exp": nacioWeb.Add(7 * 24 * time.Hour).Unix(),
	})})

	// La APK: cabecera, quince minutos de vida, caducada hace un minuto.
	nacioAPK := ahora.Add(-16 * time.Minute)
	apk := httptest.NewRequest(http.MethodGet, "/api/eventos", nil)
	apk.Header.Set("User-Agent", "Dart/3.9 (dart:io)")
	apk.Header.Set("Authorization", "Bearer "+firmar(t, "HS256", map[string]any{
		"sub": "quien-sea",
		"iat": nacioAPK.Unix(),
		"exp": nacioAPK.Add(15 * time.Minute).Unix(),
	}))

	deLaWeb := auth.RastroDe(web, ahora).Campos()
	deLaAPK := auth.RastroDe(apk, ahora).Campos()

	if v := campo(deLaWeb, "via"); v != "cookie" {
		t.Errorf("la web tiene que salir como `cookie`, salió %q — sin eso, el 401 del "+
			"29/09/2026 vuelve a no decir de quién era", v)
	}
	if v := campo(deLaAPK, "via"); v != "cabecera" {
		t.Errorf("la APK tiene que salir como `cabecera`, salió %q", v)
	}
	if v := campo(deLaWeb, "vida"); v != "168h0m0s" {
		t.Errorf("la vida de la sesión de la web tiene que salir entera (168h0m0s), salió "+
			"%q: es lo que la separa de los quince minutos de la APK", v)
	}
	if v := campo(deLaAPK, "vida"); v != "15m0s" {
		t.Errorf("la vida de la sesión de la APK tiene que ser 15m0s, salió %q", v)
	}
	if v := campo(deLaWeb, "caduco_hace"); v != "1m0s" {
		t.Errorf("hace falta saber si venció hace un minuto (reloj desfasado) o hace horas "+
			"(nadie la renovó); salió %q", v)
	}
	if v := campo(deLaAPK, "agente"); !strings.Contains(v, "Dart") {
		t.Errorf("el agente confirma por su cuenta quién mandó la petición; salió %q", v)
	}
}

// LO QUE ESTE RENGLÓN NO PUEDE LLEVAR NUNCA.
//
// Un registro acaba pegado en un correo, en un chat y en un ticket. Un token de siete días
// pegado en un chat es una sesión regalada, así que no sale: ni entero, ni recortado, ni su
// firma, ni el `sub` de quien todavía no ha demostrado ser nadie.
func TestElRastroNoEnsenaElToken(t *testing.T) {
	token := firmar(t, "HS256", map[string]any{"id": "persona-secreta", "sub": "persona-secreta"})
	r := httptest.NewRequest(http.MethodGet, "/api/eventos", nil)
	r.AddCookie(&http.Cookie{Name: "token", Value: token})

	var todo string
	for _, v := range auth.RastroDe(r, time.Now()).Campos() {
		if s, ok := v.(string); ok {
			todo += s + "\u0000"
		}
	}
	partes := strings.Split(token, ".")
	for _, prohibido := range []string{token, partes[1], partes[2], "persona-secreta"} {
		if strings.Contains(todo, prohibido) {
			t.Fatalf("el rastro no puede llevar la credencial ni a quién dice ser; llevaba %q",
				prohibido)
		}
	}
}

// DOS COOKIES `token` A LA VEZ: LA BUENA TIENE QUE ENTRAR, Y HAY QUE ENTERARSE.
//
// Pasa sin que sea culpa de nadie: otra aplicación de la casa que deje una `token` con
// `Domain=.procovar.cloud` la manda a todos los subdominios, y el navegador decide el orden
// (RFC 6265), no nosotros. Con `r.Cookie("token")` —que devuelve la primera— eso es un 401
// permanente sobre una sesión válida que nadie mira.
func TestDosCookiesTokenYLaBuenaEsLaSegunda(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))

	r := httptest.NewRequest(http.MethodGet, "/api/eventos", nil)
	// La de la otra aplicación va primera, como la mandaría el navegador.
	r.AddCookie(&http.Cookie{Name: "token", Value: "esto-no-es-un-jwt"})
	r.AddCookie(&http.Cookie{Name: "token", Value: firmar(t, "HS256", map[string]any{"id": "la-buena"})})

	u, err := v.DelaPeticion(r)
	if err != nil || u == nil || u.ID != "la-buena" {
		t.Fatalf("con dos cookies `token`, la válida tiene que entrar; salió %v %+v\n"+
			"Si esto falla, `DelaPeticion` volvió a quedarse con la primera cookie y hay "+
			"un 401 permanente que no se puede explicar desde fuera.", err, u)
	}

	if c := campo(auth.RastroDe(r, time.Now()).Campos(), "cookies_token"); c != "2" {
		t.Errorf("el registro tiene que decir que venían DOS cookies `token`: es la única "+
			"forma de ver esa avería desde el servidor. Salió %q", c)
	}
}

// SIN CREDENCIAL NINGUNA TAMBIÉN SE DICE.
//
// «No traía nada» y «traía algo que ya no vale» llevan a sitios distintos: uno es la puerta
// y el otro una renovación. Si el campo se omitiera cuando está vacío, el renglón del
// primer caso volvería a ser el de aquella noche.
func TestElRastroDiceCuandoNoVinoNada(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/api/eventos", nil)
	campos := auth.RastroDe(r, time.Now()).Campos()
	if v := campo(campos, "via"); v != "ninguna" {
		t.Fatalf("sin credencial el rastro tiene que decir `ninguna`, dijo %q", v)
	}
	if v := campo(campos, "cookies_token"); v != "0" {
		t.Fatalf("`cookies_token` tiene que ir siempre, también en cero; salió %q", v)
	}
}
