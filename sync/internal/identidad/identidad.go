// Package identidad dice QUIÉN está llamando: su persona, su sucursal y si es Super Admin.
//
// Quien manda en personas, roles y sucursales es auth (`auth.procovar.cloud`), y aquí no
// hay ni va a haber una copia de esa lista: una segunda lista de personas es una segunda
// lista que mantener al día y un segundo sitio donde dar de baja a alguien.
//
// De dónde sale, hoy: de las cabeceras que pone el proxy que verifica el token delante de
// este servicio. Es provisional —lo bueno es verificar aquí el token de auth, que ya lleva
// dentro el `sub`, la sucursal y los roles (ver `docs/identidad.md`)— y por eso hay que
// pedirlo a mano con `SYNC_IDENTIDAD=cabeceras`: confiar en una cabecera es seguro
// exactamente mientras nadie más pueda llegar a este puerto, y eso es una decisión de
// despliegue que alguien tiene que tomar mirándola.
//
// El resto del servicio no se entera de nada de esto: pide la Identidad del contexto.
package identidad

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
)

type Identidad struct {
	// El id de la persona EN AUTH. Texto, porque viene de un sistema ajeno.
	Persona string
	// Su sucursal. El alcance por sucursal es la regla de seguridad de todo el reparto.
	Sucursal uuid.UUID
	// El Super Admin ve las diez. Es la única excepción al alcance, y la única fuente de
	// conflictos de verdad (ver `docs/sincronizacion.md`).
	EsSuperAdmin bool

	// EL TOKEN TAL CUAL VINO, para poder REENVIARLO al reparto.
	//
	// Este servicio no es el dueño de los datos: traduce los apuntes del aparato y se los
	// manda a `reparto-api`, que es quien escribe. Esa segunda llamada también tiene que
	// ir firmada por alguien, y ese alguien es **la misma persona**, no este servicio.
	//
	// Antes iba con la clave de servicio (`x-api-key`) más `X-Persona` y `X-Sucursal`, y
	// ahí había dos agujeros. El primero, que **`reparto-api` no lee esas dos cabeceras**:
	// las ponía este servicio y no las miraba nadie. El segundo, que las rutas del aparato
	// —`/api/board/columns` y las demás— exigen sesión de persona, así que la clave de
	// servicio no las abre: contestaban **401 «no viene token»** y el apunte se quedaba en
	// la cola para siempre. Es lo que dejó la zona «Vista» dentro de un teléfono, con sus
	// cinco pedidos colocados, sin que la viera nadie más.
	//
	// Reenviar el token de la persona arregla las dos cosas a la vez y, sobre todo, deja
	// el alcance donde tiene que estar: el reparto ve **al que hizo el trabajo**, con su
	// rol y su sucursal. La alternativa —abrir esas rutas a la clave de servicio— habría
	// significado colgarle un Super Admin a cada apunte que pasa por aquí, que es
	// exactamente lo que no puede pasar: «los super administradores pueden tocar en todos
	// lados», pero un gestor de Camagüey no se convierte en uno al subir su cola.
	//
	// Vacío cuando la identidad no salió de un token (`DeCabeceras`, el modo viejo).
	Token string

	// El claim `name` del token VERIFICADO (nunca del cuerpo de la petición), para que la bandeja
	// de revisión diga «Yasmani» y no un uuid. Vacío si el token no lo trae.
	Nombre string
	// El `jti` del token: qué token entregó o decidió. Vale como constancia, nunca como secreto.
	Jti string
	// Los roles del token VERIFICADO, por nombre (`role`, `rol` y `roles`, sin vacíos). Sólo los lee
	// [Identidad.RolDeRevisor]: Reparto no decide quién ENTRA por el rol (eso es `entradas`), pero quién REVISA
	// la bandeja sí se decide por nombre (docs/bandeja-de-revision.md B.3). Vacío con `SYNC_IDENTIDAD=cabeceras`.
	Roles []string
	// Ámbito del token. Vacío en todo token normal; [AmbitoEntrega] sólo lo pone
	// [DeTokenDeEntrega]. Es lo que deja a un manejador exigir «esto sólo con token de entrega»
	// aunque alguien le monte mal la fuente.
	Ambito string
}

// Alcance devuelve la sucursal por la que hay que filtrar, o nil para «todas». Es lo que
// espera el parámetro anulable de las consultas: el filtro vive en el SQL, nunca en Go.
func (i Identidad) Alcance() *uuid.UUID {
	if i.EsSuperAdmin {
		return nil
	}
	s := i.Sucursal
	return &s
}

// Ve dice si esta identidad puede ver las cosas de esa sucursal.
func (i Identidad) Ve(sucursal uuid.UUID) bool {
	return i.EsSuperAdmin || i.Sucursal == sucursal
}

var ErrSinSesion = errors.New("sin sesión")

// El 403 de «tu rol no entra a Reparto»: literales idénticos a los de `reparto-api`
// (`auth.MsgSinPermisoReparto`, `auth.CodigoSinPermisoReparto`).
const (
	MsgSinPermisoReparto    = "No tienes permiso para entrar a Reparto."
	CodigoSinPermisoReparto = "sin_permiso_reparto"
)

// Fuente saca la identidad de una petición. Se cambia entera el día que el token se
// verifique aquí, sin tocar ningún handler.
type Fuente func(*http.Request) (Identidad, error)

// DeCabeceras lee lo que puso el verificador de delante.
func DeCabeceras(r *http.Request) (Identidad, error) {
	persona := strings.TrimSpace(r.Header.Get("X-Persona"))
	if persona == "" {
		return Identidad{}, ErrSinSesion
	}
	var id Identidad
	id.Persona = persona
	id.EsSuperAdmin = esCierto(r.Header.Get("X-Super-Admin"))

	if v := strings.TrimSpace(r.Header.Get("X-Sucursal")); v != "" {
		s, err := uuid.Parse(v)
		if err != nil {
			return Identidad{}, ErrSinSesion
		}
		id.Sucursal = s
	} else if !id.EsSuperAdmin {
		// Sin sucursal y sin ser Super Admin no hay alcance que aplicar, y «sin alcance»
		// no puede querer decir «todas»: eso es justo cómo se ve lo que no es de uno.
		return Identidad{}, ErrSinSesion
	}
	return id, nil
}

func esCierto(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "si", "sí":
		return true
	}
	return false
}

type llave struct{}

// Con mete la identidad en el contexto. Lo usa el middleware, y las pruebas.
func Con(ctx context.Context, id Identidad) context.Context {
	return context.WithValue(ctx, llave{}, id)
}

// De la saca. El segundo valor es false cuando no pasó por el middleware.
func De(ctx context.Context) (Identidad, bool) {
	id, ok := ctx.Value(llave{}).(Identidad)
	return id, ok
}

// Exigir corta la petición si no hay sesión. El mensaje es el literal de `delivery`.
//
// «NO HAY SESIÓN» Y «NO PUDE COMPROBARLO» NO SE CONTESTAN IGUAL, y la diferencia es el
// día de trabajo de alguien. El cliente trata un 401 que sobrevive a renovar como «la
// sesión murió» y se va a la pantalla de acceso; un 5xx conserva los tokens y reintenta
// luego (`docs/identidad.md`, regla 3). Así que un tropiezo del reparto al traducir el
// código de la sucursal sale como **503**, no como 401: quien está en el patio de un
// almacén con la cola llena vuelve a intentarlo, no se queda fuera.
func Exigir(fuente Fuente, siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, err := fuente(r)
		if errors.Is(err, ErrNoSePudoComprobar) {
			httpx.Fallo(w, http.StatusServiceUnavailable,
				"No se pudo comprobar tu sucursal ahora mismo. Tu sesión sigue valiendo: se reintenta solo.")
			return
		}
		if errors.Is(err, ErrSinPermisoDeReparto) {
			// El MISMO 403 y el mismo cuerpo que `reparto-api` (`auth.PermitirReparto`). El
			// registro lleva rol(es), sucursal y ruta —viene en el error— y nunca el token.
			slog.Warn("sin permiso de reparto", "motivo", err, "ruta", r.URL.Path)
			httpx.FalloConCodigo(w, http.StatusForbidden, MsgSinPermisoReparto, CodigoSinPermisoReparto)
			return
		}
		if err != nil {
			httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
			return
		}
		siguiente.ServeHTTP(w, r.WithContext(Con(r.Context(), id)))
	})
}
