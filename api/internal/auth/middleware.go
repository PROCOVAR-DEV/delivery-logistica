package auth

import (
	"context"
	"crypto/subtle"
	"net/http"
	"time"

	"procovar/reparto-api/internal/httpx"
)

type claveCtx int

const claveUsuario claveCtx = iota

// Exigir deja pasar sólo a quien trae un token válido y cuelga la persona del contexto.
//
// El 401 es siempre el mismo cuerpo, {"error":"Unauthorized"}, SIN decir por qué. El
// motivo va al registro. Contarle a quien prueba si el fallo fue "no hay token", "la
// firma no cuadra" o "está caducado" es regalarle el mapa.
func (v *Verificador) Exigir(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, err := v.DelaPeticion(r)
		if err != nil {
			// EL MOTIVO SOLO NO BASTA, y costó una noche averiguarlo: ver `rastro.go`.
			// «el token está caducado» no dice si el rechazado es el navegador o el
			// teléfono, y las dos sesiones duran cosas distintas (7 días contra 15
			// minutos), así que el arreglo no es el mismo. Al cliente se le sigue
			// contestando lo de siempre, sin decirle nada.
			httpx.Registro(r).Warn("sesión rechazada",
				append([]any{"motivo", err, "ruta", r.URL.Path},
					RastroDe(r, time.Now()).Campos()...)...)
			httpx.NoAutorizado(w, r)
			return
		}
		ctx := context.WithValue(r.Context(), claveUsuario, u)
		siguiente.ServeHTTP(w, r.WithContext(ctx))
	})
}

// ExigirAdmin se pone DESPUÉS de Exigir. Es el `403 {"error":"Admin access required"}`
// de `/api/branches`.
func ExigirAdmin(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u := De(r)
		if u == nil {
			// No debería poder pasar: significa que se montó ExigirAdmin sin Exigir
			// delante. Se responde 401 y se deja constancia, porque es un fallo de
			// montaje que si no nadie ve.
			httpx.Registro(r).Error("ExigirAdmin sin Exigir delante", "ruta", r.URL.Path)
			httpx.NoAutorizado(w, r)
			return
		}
		if !u.EsAdmin() {
			httpx.Error(w, r, http.StatusForbidden, httpx.MsgAdminRequerido)
			return
		}
		siguiente.ServeHTTP(w, r)
	})
}

// De saca la persona del contexto. nil si no la hay.
func De(r *http.Request) *Usuario {
	u, _ := r.Context().Value(claveUsuario).(*Usuario)
	return u
}

// ConUsuario mete una persona en el contexto. Para las PRUEBAS y para las rutas de
// servicio, que no traen persona pero sí tienen que pasar por el alcance.
func ConUsuario(ctx context.Context, u *Usuario) context.Context {
	return context.WithValue(ctx, claveUsuario, u)
}

// LlaveDeServicio es la puerta del espejo de PEDIDO y de las tareas de fondo: cabecera
// `x-api-key`.
//
// Si la llave NO está configurada en el servidor, esto es SIEMPRE falso — nunca "pasa
// todo el mundo". Un servicio al que se le olvidó la variable tiene que quedarse cerrado,
// no abierto de par en par.
func LlaveDeServicio(esperada string) httpx.Medio {
	return func(siguiente http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			traida := r.Header.Get("X-Api-Key")
			if esperada == "" || subtle.ConstantTimeCompare([]byte(traida), []byte(esperada)) != 1 {
				if esperada == "" {
					httpx.Registro(r).Error("SERVICE_API_KEY no configurada: la puerta de servicio queda cerrada", "ruta", r.URL.Path)
				}
				httpx.NoAutorizado(w, r)
				return
			}
			siguiente.ServeHTTP(w, r)
		})
	}
}

// ExigirQuienMiraElCanal: pasan el DESARROLLADOR y el SUPER ADMIN, y nadie más.
//
// Es el listón más alto y se usa donde lo que hay detrás no es administrar la empresa sino
// mirar el estado de las tuberías: colas, reintentos, códigos HTTP y motivos de error de
// otro sistema. Quién entra exactamente está en `Usuario.PuedeMirarElCanal`, con el porqué
// de que sean dos y no uno.
//
// Contesta 403 y NO 404. Esconder que la ruta existe suena más seguro y no lo es: quien
// llega aquí ya tiene sesión, y un 404 le haría pensar que la aplicación está rota. Lo que
// no se dice es qué hay dentro.
func ExigirQuienMiraElCanal(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u := De(r)
		if u == nil {
			httpx.Registro(r).Error("ExigirQuienMiraElCanal sin Exigir delante", "ruta", r.URL.Path)
			httpx.NoAutorizado(w, r)
			return
		}
		if !u.PuedeMirarElCanal() {
			httpx.Error(w, r, http.StatusForbidden, MsgSoloElCanal)
			return
		}
		siguiente.ServeHTTP(w, r)
	})
}

// MsgSoloElCanal: el literal que lee quien llega sin poder. Dice QUÉ falta, no «no
// autorizado»: así quien lo vea sabe que no es un fallo de la aplicación.
const MsgSoloElCanal = "Esta pantalla es del desarrollador: mira cómo van las " +
	"tuberías con PEDIDO y no es de administrar el reparto."
