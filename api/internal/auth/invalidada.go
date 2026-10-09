package auth

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
)

// ErrSesionInvalidada: la credencial es válida de firma y de fecha, pero Accesos cerró esa
// sesión o cambió los permisos de la persona DESPUÉS de emitirla (`internal/sesiones`). Es un
// 401 como cualquier otro hacia fuera; el motivo sólo va al registro.
//
// Es el género: [errWebInvalidada] (la cookie de la web) y [errAparatoInvalidado] (el token de la
// APK o el escritorio) cuelgan de él, y sólo la primera borra la cookie.
var ErrSesionInvalidada = errors.New("Accesos invalidó la sesión")

var (
	errWebInvalidada     = fmt.Errorf("%w: es una sesión web", ErrSesionInvalidada)
	errAparatoInvalidado = fmt.Errorf("%w: es un token de la APK o del escritorio", ErrSesionInvalidada)
)

// Invalidaciones es lo que el verificador pregunta para saber si una credencial ya no vale. La
// implementa `sesiones.Registro` y TIENE QUE CONTESTAR SIN RED: se pregunta en cada petición.
type Invalidaciones interface {
	// LaCookieNoVale: la sesión web emitida en `iatMs` (milisegundos). Cuentan los dos alcances.
	LaCookieNoVale(persona string, iatMs int64) bool
	// ElBearerNoVale: el token de la APK o el escritorio emitido en `iatMs` (milisegundos; 0 si no lo
	// trae) o, si no, en `iatSeg` (SEGUNDOS). Cuenta SÓLO el alcance `todo`: cerrar la sesión del
	// navegador no echa al teléfono.
	ElBearerNoVale(persona string, iatSeg, iatMs int64) bool
}

// ConInvalidaciones engancha el empuje de Accesos. `borrarCookie` escribe la cabecera que borra la
// cookie de la web (con SUS atributos: nombre, camino, Secure y SameSite tienen que ser los de
// cuando se puso o el navegador la deja donde estaba; por eso lo hace `internal/api`, que sabe
// el origen). Se llama UNA vez, antes de servir: no hay candado.
func (v *Verificador) ConInvalidaciones(inv Invalidaciones, borrarCookie func(http.ResponseWriter, *http.Request)) {
	v.inv, v.borrarCookie = inv, borrarCookie
}

// sesionInvalidada es EL ayudante: lo usan las tres puertas con sesión —`Exigir`, `/api/me` y el
// canal `/api/eventos`— porque las tres eligen la credencial por [Verificador.delaPeticion].
//
// # Dos clases de credencial, dos reglas
//
//   - SESIÓN WEB (cookie `token` o `iatms` en el token): ya no vale si hay marca `web` o `todo`
//     de esa persona posterior a su `iatms`.
//   - TOKEN DE LA APK Y EL ESCRITORIO (cualquier otro): ya no vale si hay marca `todo` posterior a
//     su `iatms` o, si no lo trae, a su `iat*1000` (conservador). Una marca `web` no le llega. Aprobado por
//     Jose el 08/10/2026 («la web es la web y las APK son la APK»): sin esto, un corte de seguridad
//     dejaba al teléfono sirviendo hasta 15 minutos más.
//
// # A quién se le llama «web», que no es sólo "quien llegó por cookie"
//
// La web NO manda sólo la cookie: su interceptor (`app/lib/nucleo/red/interceptor_sesion.dart`)
// pone además `Authorization: Bearer <el token de /api/me>`, que es EL MISMO token de la cookie. Si
// ese Bearer se tratara como el de la APK, la web quedaría fuera de la regla `web`. Por eso es web
// toda credencial que viaje en una cookie `token` (aunque se repita en el Bearer) o lleve la marca
// `web` (sólo la firma `auth_web.go`; sigue siendo web si la app la manda sola, p. ej. tras borrarse la
// cookie). **NO se distingue por `iatms`**: Accesos lo firma también en el token de la APK, y con eso
// un cierre de sesión `web` echaría al teléfono.
//
// # Cookies SIN `iatms` — 08/10/2026
//
// Las emitidas antes de este cambio no lo traen. Se tratan como emitidas en el instante 0: cualquier
// marca de esa persona las invalida, pero NO se rechazan por no tener el claim (al desplegar no se
// echa a nadie). Desaparecen solas con la última cookie vieja (15/10/2026, siete días). Su
// límite: un token viejo de la web que se mande SOLO como Bearer (sin cookie) se toma por uno de la
// APK, y sólo lo invalida una marca `todo`; sólo ocurre esa semana.
func (v *Verificador) sesionInvalidada(u *Usuario) bool {
	if v.inv == nil {
		return false
	}
	if u.SesionWeb {
		return v.inv.LaCookieNoVale(u.ID, u.IatMs)
	}
	return v.inv.ElBearerNoVale(u.ID, u.Iat, u.IatMs)
}

// BorrarCookieSiInvalidada: si el rechazo fue el de una SESIÓN WEB invalidada, deja puesta la
// cabecera que borra la cookie. La llaman los tres sitios que contestan el 401, ANTES de escribir
// la respuesta (después ya no se pueden añadir cabeceras). Al token de la APK no se le toca nada:
// no tiene cookie.
func (v *Verificador) BorrarCookieSiInvalidada(w http.ResponseWriter, r *http.Request, err error) {
	if v.borrarCookie != nil && errors.Is(err, errWebInvalidada) {
		v.borrarCookie(w, r)
	}
}

// valoresDeLaCookie son los valores de las cookies `token` (recortados, como en [Credenciales]).
func valoresDeLaCookie(r *http.Request) map[string]bool {
	salida := map[string]bool{}
	for _, c := range r.CookiesNamed(NombreDeLaCookie) {
		if t := strings.TrimSpace(c.Value); t != "" {
			salida[t] = true
		}
	}
	return salida
}
