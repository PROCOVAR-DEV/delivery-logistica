// QUÉ CREDENCIAL LLEGÓ, para cuando la respuesta es 401 y nadie lo ve.
//
// # EL CASO QUE LO TRAJO — 29/09/2026, 21:30:50 UTC, `GET /api/eventos` 401
//
// Del registro de `reparto-api` en el VPS esa noche (las horas son UTC, la línea se
// escribe AL TERMINAR la petición y `ms` es lo que duró, así que hay que restar):
//
//	21:30:45  GET /api/eventos  200  299999ms   -> empezó 21:25:45, la cortó el proxy
//	21:30:47  GET /api/eventos  200  300000ms   -> empezó 21:25:47, ídem
//	21:30:50.169  GET /api/eventos  401  0ms    <- ÉSTE
//	21:35:49.849  GET /api/eventos  200  299999ms -> empezó 21:30:49.850
//
// O sea: dos canales abiertos a la vez, los dos cortados por el proxy a los 300 s, y **dos
// reconexiones con 319 ms de diferencia — una aceptada y la otra rechazada**.
//
// Y ahí se acabó la investigación, porque lo único que ese 401 dejó escrito fue:
//
//	eventos sin sesión  motivo=<uno de los cinco de auth.Err*>
//
// **No dice de quién.** Y ésa era la única pregunta: si el rechazado fue el navegador o el
// teléfono. Son dos averías con arreglos que no se parecen, porque las dos puertas de esta
// casa tienen vidas distintas —`internal/api/auth_web.go`, `duracionDeLaSesionWeb` = 7
// días; el de la APK, 15 minutos— y por el registro no hay forma de saber cuál cayó.
//
// Ni siquiera el `motivo` estaba a mano al investigarlo: el extracto que llegó eran las
// cuatro líneas de `peticion`, sin la línea de `eventos sin sesión` que va justo antes con
// el mismo `peticion` id. Así que la causa quedó SIN CONCLUIR, y ése es el punto: un
// renglón que obliga a volver al servidor a por el siguiente dato ya perdió la carrera.
//
// # LO QUE SE ANOTA, Y POR QUÉ CADA COSA
//
//   - `via` — por dónde vino. `cabecera` es la APK y el escritorio (`Authorization:
//     Bearer`); `cookie` es la web, que no puede mandar cabeceras porque `EventSource` no
//     sabe (`app/lib/nucleo/red/eventos_web.dart`). Responde la pregunta de arriba sola.
//   - `cookies_token` — CUÁNTAS cookies llamadas `token` traía. Si alguna vez es 2, el
//     rechazo no es de la sesión: es que hay otra cookie `token` tapando a la buena, y eso
//     no se adivina desde fuera ni en dos horas. Ver [Credenciales].
//   - `vida` — `exp - iat`, la vida ENTERA que le dieron al token. Es lo que separa las
//     dos puertas sin tener que mirar nada más: `168h0m0s` es la web, `15m0s` es la APK.
//     No hace falta que el token valga para leerlo, y por eso se lee aquí y no en
//     [Verificador.Verificar].
//   - `caduco_hace` — cuánto hacía que había vencido. Dos segundos es un reloj desfasado;
//     tres horas es una sesión que nadie renovó. No es la misma avería.
//   - `agente` — recortado. Un `Dart/3.x (dart:io)` y un `Mozilla/5.0…` se distinguen de
//     un vistazo, que es la confirmación independiente de `via`.
//
// # LO QUE NO SE ANOTA NUNCA
//
// **El token no sale aquí ni recortado.** Un registro se copia a un correo, a un chat y a
// un ticket; un token de siete días pegado en un chat es una sesión regalada. De la firma
// no se anota nada, ni su longitud. Del cuerpo sólo salen tiempos y el `alg`, que son
// números, no llaves. Y tampoco sale el `sub`: para saber quién es ya está el 200, y en el
// 401 el que pregunta todavía no ha demostrado ser nadie.
package auth

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

// NombreDeLaCookie es la cookie donde la web deja su sesión. Está escrita aquí, que es
// donde se lee, y `internal/api/auth_web.go` la usa para escribirla: dos literales
// distintos serían una sesión guardada en un sitio donde nadie la busca — se entraría bien
// y la siguiente petición sería 401.
const NombreDeLaCookie = "token"

// Credenciales devuelve, EN ORDEN, todos los tokens que trae la petición, por dónde
// vinieron y cuántas cookies `token` había.
//
// # POR QUÉ DEVUELVE VARIAS Y NO UNA — 29/09/2026
//
// Aquí se hacía `r.Cookie("token")`, que devuelve **la primera** y calla las demás. Un
// navegador puede tener dos cookies con el mismo nombre a la vez sin que sea culpa de
// nadie: basta que otra aplicación de la casa deje una `token` con `Domain=.procovar.cloud`
// —que se manda a TODOS los subdominios— para que viaje por delante de la nuestra, que es
// de host y de `Path=/`. El orden lo decide el navegador (RFC 6265: camino más largo
// primero y, a igualdad, la más vieja), o sea que no lo decidimos nosotros.
//
// Con `r.Cookie` eso es un 401 permanente e inexplicable: la sesión de aquí está puesta, es
// válida y no se mira nunca. Probándolas todas, la buena entra; y si ninguna vale, el
// motivo que se devuelve sigue siendo el de la primera, para no cambiar lo que se registra
// en el caso normal de una sola.
//
// No hay pérdida de seguridad: TODAS tienen que pasar por la misma firma. Lo único que
// cambia es que una cookie de más deje de tapar a la buena.
func Credenciales(r *http.Request) (tokens []string, via string, cookiesToken int) {
	if r == nil {
		return nil, "ninguna", 0
	}
	deCabecera := false
	if cab := r.Header.Get("Authorization"); cab != "" {
		if partes := strings.Fields(cab); len(partes) == 2 && strings.EqualFold(partes[0], "Bearer") {
			if t := strings.TrimSpace(partes[1]); t != "" {
				tokens = append(tokens, t)
				deCabecera = true
			}
		}
	}
	deCookie := false
	for _, c := range r.CookiesNamed(NombreDeLaCookie) {
		cookiesToken++
		if t := strings.TrimSpace(c.Value); t != "" {
			tokens = append(tokens, t)
			deCookie = true
		}
	}
	switch {
	case deCabecera && deCookie:
		via = "cabecera+cookie"
	case deCabecera:
		via = "cabecera"
	case deCookie:
		via = "cookie"
	default:
		via = "ninguna"
	}
	return tokens, via, cookiesToken
}

// Rastro es lo que se sabe de la credencial que llegó SIN haberla creído.
//
// Todo lo de dentro se lee del token sin comprobar la firma, a propósito: cuando esto se
// escribe es porque el token NO valía, así que exigir que valga para poder describirlo es
// no describir nunca lo único que interesa.
type Rastro struct {
	// Via: `cabecera` (APK y escritorio), `cookie` (web), `cabecera+cookie` o `ninguna`.
	Via string
	// CookiesToken: cuántas cookies llamadas `token` traía. Más de una es una avería.
	CookiesToken int
	// Alg es el `alg` de la cabecera del JWT, tal cual venía. Un `none` o un `RS256` aquí
	// no es un despiste: es alguien probando.
	Alg string
	// Vida es `exp - iat`: la vida entera que le dieron. Cero si falta alguno de los dos.
	Vida time.Duration
	// CaducoHace es cuánto llevaba vencido cuando llegó. Cero si no había caducado o si no
	// se pudo leer el `exp`.
	CaducoHace time.Duration
	// Legible dice si se pudo leer el cuerpo del token. Falso es un token roto o cortado,
	// que es otra avería distinta de una sesión vencida.
	Legible bool
	// Agente es el `User-Agent` recortado.
	Agente string
}

// largoDelAgente: lo que se guarda del `User-Agent`. Ochenta caracteres llegan de sobra
// para distinguir un `Dart/3.x (dart:io)` de un `Mozilla/5.0 (X11; Linux…)`, y evitan que
// una cadena de mil caracteres inventada por quien llama se lleve el renglón entero del
// registro.
const largoDelAgente = 80

// RastroDe hace la radiografía de la petición. Nunca devuelve nada que no se pueda pegar
// en un chat.
func RastroDe(r *http.Request, ahora time.Time) Rastro {
	tokens, via, cookies := Credenciales(r)
	ras := Rastro{Via: via, CookiesToken: cookies}
	if r != nil {
		ras.Agente = recortar(r.UserAgent(), largoDelAgente)
	}
	if len(tokens) == 0 {
		return ras
	}
	ras.leerSinCreer(tokens[0], ahora)
	return ras
}

// leerSinCreer saca del token lo que se puede contar. NO comprueba la firma y no debe
// hacerlo: ver el comentario de [Rastro].
func (ras *Rastro) leerSinCreer(token string, ahora time.Time) {
	partes := strings.Split(token, ".")
	if len(partes) != 3 {
		return
	}
	if cab, err := decodificar(partes[0]); err == nil {
		var c struct {
			Alg string `json:"alg"`
		}
		if json.Unmarshal(cab, &c) == nil {
			ras.Alg = recortar(c.Alg, 16)
		}
	}
	cuerpo, err := decodificar(partes[1])
	if err != nil {
		return
	}
	var c reclamos
	if json.Unmarshal(cuerpo, &c) != nil {
		return
	}
	ras.Legible = true
	if c.Exp == nil {
		return
	}
	exp := time.Unix(int64(*c.Exp), 0)
	if c.Iat != nil {
		ras.Vida = exp.Sub(time.Unix(int64(*c.Iat), 0)).Round(time.Second)
	}
	if ahora.After(exp) {
		ras.CaducoHace = ahora.Sub(exp).Round(time.Second)
	}
}

// Campos son los pares que se le pasan a `slog`. Se omite lo que no se sabe: un renglón
// con seis campos vacíos se lee peor que uno con dos llenos.
//
// `via` y `cookies_token` van SIEMPRE, incluso cuando no vino nada: «no traía credencial
// ninguna» es un dato, y es justo el que faltaba la noche del 29/09/2026.
func (ras Rastro) Campos() []any {
	campos := []any{"via", ras.Via, "cookies_token", ras.CookiesToken}
	if ras.Alg != "" {
		campos = append(campos, "alg", ras.Alg)
	}
	if ras.Vida > 0 {
		campos = append(campos, "vida", ras.Vida.String())
	}
	if ras.CaducoHace > 0 {
		campos = append(campos, "caduco_hace", ras.CaducoHace.String())
	}
	if ras.Via != "ninguna" && !ras.Legible {
		// Vino algo y no se pudo ni leer: no es una sesión vencida, es un token cortado,
		// pegado a medias o de otro sistema. Se dice, porque el arreglo no se parece.
		campos = append(campos, "ilegible", true)
	}
	if ras.Agente != "" {
		campos = append(campos, "agente", ras.Agente)
	}
	return campos
}

func recortar(s string, largo int) string {
	s = strings.TrimSpace(s)
	if len(s) <= largo {
		return s
	}
	return s[:largo] + "…"
}
