// Package sincro es el protocolo de `docs/sincronizacion.md`, y nada más.
//
// Los datos del reparto —los pedidos, las rutas, los clientes— NO son de aquí. Este
// servicio reparte diferencias y recibe lotes; quien los guarda es `reparto-api`. Lo único
// que vive en la base de este servicio es la contabilidad de la sincronización: quién bajó,
// quién subió, qué se le aplicó y qué se le rechazó.
//
// Por eso el dueño de los datos entra por dos interfaces, `Origen` y `Aplicador`: son la
// frontera con el reparto, y son lo que permite probar aquí las seis cosas que no pueden
// salir mal sin levantar medio sistema.
package sincro

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/store"
)

// Los ocho conjuntos de la bajada, en el orden del protocolo. Se contestan SIEMPRE los
// ocho, aunque vengan vacíos: así la aplicación recorre lo que llega sin preguntarse si
// una clave que falta quiere decir «no cambió nada» o «el servidor es más viejo».
var Colecciones = []string{
	"orders", "routes", "customers", "products",
	"vehicles", "branches", "warehouses", "settings",
}

// Conjunto es lo que cambió en una colección.
//
// `quitados` hace falta de verdad: sin él, un pedido archivado o una ruta borrada se quedan
// en el aparato para siempre y la lista local sólo crece.
type Conjunto struct {
	Puestos  []json.RawMessage `json:"puestos"`
	Quitados []string          `json:"quitados"`
}

type Cambios map[string]Conjunto

// Ventana es lo que se le pide al reparto: qué sucursal y qué trozo de tiempo.
//
// `Hasta` va SIEMPRE puesto y lo pone este servicio con su propio reloj. No es un detalle
// de implementación: es la regla 5 del protocolo.
type Ventana struct {
	Sucursal uuid.UUID
	Desde    *time.Time
	Hasta    time.Time
	Tope     int32
	// Continuar es POR DÓNDE SEGUIR, tal cual lo mandó el reparto en la tanda anterior.
	// Vacío = primera tanda. **No se mira por dentro**: es del reparto y lo que lleva
	// dentro es cosa suya (`api/internal/api/espejo.go`).
	Continuar string
}

// Bajada es lo que contesta el reparto a una ventana.
//
// `Hasta` VIENE DEL REPARTO Y NO SE INVENTA AQUÍ, y ésa es toda la razón de que esto sea
// una estructura y no dos valores sueltos. Hasta el 21/09/2026 este servicio decodificaba
// sólo `cambios` y `truncado` y anotaba como marca el `hasta` que él mismo había mandado,
// saliera la tanda truncada o no. Con `truncado`, eso es trabajo perdido: el reparto sirve
// hasta donde le cabe y devuelve la marca de la última fila servida; anotando el reloj, lo
// que no cupo queda POR DEBAJO del próximo `desde` y no lo vuelve a pedir nadie nunca más.
// Es el §3 del `CLAUDE.md` —los 2.000 clientes de 8.034— visto desde este lado.
type Bajada struct {
	Cambios  Cambios
	Hasta    time.Time
	Truncado bool
	// Continuar es el cursor de la tanda siguiente, si el reparto mandó uno. Se devuelve
	// al aparato tal cual y el aparato lo vuelve a mandar tal cual.
	Continuar string
}

// Origen es el dueño de los datos, del lado de la lectura.
type Origen interface {
	// Diferencias devuelve lo que cambió en esa ventana, hasta dónde se sirvió de verdad
	// y si quedó cortado por el tope.
	Diferencias(ctx context.Context, v Ventana) (Bajada, error)
}

// Peticion es un apunte del aparato ya traducido y listo para mandárselo al reparto.
type Peticion struct {
	Metodo string
	Ruta   string
	Cuerpo json.RawMessage
	// La hora del APARATO. Lo que se marcó a las cuatro llega como las cuatro aunque suba
	// a las siete: en PEDIDO el vendedor tiene que ver cuándo recibió su cliente, no
	// cuándo pilló señal el teléfono.
	Hecho    time.Time
	Sucursal uuid.UUID
	Persona  string
	Clave    string

	// EL TOKEN DE LA PERSONA, para firmar la llamada al reparto con SU nombre. Ver
	// `identidad.Identidad.Token`: sin esto las rutas del aparato contestan 401 y el
	// apunte se queda en la cola para siempre.
	Token string
}

// Aplicado es lo que el reparto contestó de un apunte que SÍ entró.
//
// Era un `*uuid.UUID` a secas y por eso se perdía lo segundo: **un apunte puede aplicarse
// y aun así dejar gente fuera**. Armar una zona de doce devuelve 201 con la ruta creada y,
// en el mismo cuerpo, quién se cayó y por qué. Leyendo sólo el id, la ruta salía con nueve
// paradas y en el teléfono no había ni un aviso — el §4 del reparto al revés.
type Aplicado struct {
	// El id de lo que se creó, o nil si el apunte no creaba nada (marcar una parada,
	// corregirla).
	ID *uuid.UUID

	// QUIÉN SE CAYÓ, tal y como lo escribió el reparto: una lista JSON con el pedido
	// nombrado, su motivo y qué hacer (`api/internal/api/tablero.go`,
	// `DescartadoSalida`). Se reenvía sin tocar dentro del resultado del apunte.
	//
	// Casi siempre vacío, y así tiene que ser: un aviso que sale en cada armado deja de
	// leerse, y entonces tampoco se lee el día que importa.
	Descartados json.RawMessage
}

// Aplicador es el dueño de los datos, del lado de la escritura.
//
// Devuelve [Aplicado] —con el id de lo que se creó, si creó algo—. Un `*Rechazo` significa
// que el reparto dijo que no por una razón de negocio y que NO hay que reintentarlo;
// cualquier otro error es una caída y el apunte se queda en la cola.
type Aplicador interface {
	Aplicar(ctx context.Context, p Peticion) (Aplicado, error)
}

// Rechazo es el «no» del servidor, con la frase que va a leer una persona.
//
// Es un tipo de error aparte justamente para no confundirlo con una caída: un rechazo se
// guarda con su motivo y sale en el panel; una caída se reintenta. Tratar el segundo como
// el primero llenaría la bandeja de rechazos falsos el día que el reparto se reinicie.
type Rechazo struct {
	Motivo string
}

func (r *Rechazo) Error() string { return r.Motivo }

// SinPermiso: el reparto contestó 403 con `codigo: "sin_permiso_reparto"`: el ROL de la
// persona no entra a Reparto. NO ES UN RECHAZO Y NO SE ANOTA COMO TAL.
//
// Un [Rechazo] marca el apunte `rechazado` en la bandeja y lo retiene hasta que una persona
// decida. Aquí no hay nada que decidir sobre el apunte: es la PERSONA la que no tiene permiso,
// y marcarle rechazado todo lo que tenía en la cola sería destruirle el trabajo pendiente por
// algo que se arregla en Accesos (dándole el rol). El apunte se queda como estaba, sin
// anotar, y `/sync/subida` contesta 403 con el mismo cuerpo que el resto de Reparto.
//
// Distinto del 403 del alcance de sucursal (sin `codigo`), que sigue siendo un [Rechazo].
type SinPermiso struct {
	// Lo que dijo el reparto, para el registro. Al cliente no se le reenvía: el cuerpo del 403
	// es siempre el mismo literal (`identidad.MsgSinPermisoReparto`).
	Motivo string
}

func (e *SinPermiso) Error() string { return "sin permiso de reparto: " + e.Motivo }

type Opciones struct {
	Datos     store.Datos
	Origen    Origen
	Aplicador Aplicador
	// El reloj del SERVIDOR. Es un campo y no `time.Now` a secas porque la regla 5 —la
	// marca de la bajada la pone el servidor— hay que poder probarla.
	Ahora      func() time.Time
	TopeBajada int32
	Log        *slog.Logger
}

type Servicio struct {
	datos     store.Datos
	origen    Origen
	aplicador Aplicador
	ahora     func() time.Time
	tope      int32
	log       *slog.Logger
}

func Nuevo(o Opciones) *Servicio {
	s := &Servicio{
		datos:     o.Datos,
		origen:    o.Origen,
		aplicador: o.Aplicador,
		ahora:     o.Ahora,
		tope:      o.TopeBajada,
		log:       o.Log,
	}
	if s.ahora == nil {
		s.ahora = func() time.Time { return time.Now().UTC() }
	}
	if s.tope <= 0 {
		s.tope = 500
	}
	if s.log == nil {
		s.log = slog.Default()
	}
	return s
}

// Rutas son las cuatro del protocolo. Los patrones con método son de `net/http`: no hace
// falta un enrutador de fuera para cuatro rutas sin parámetros en el camino.
func (s *Servicio) Rutas(mux *http.ServeMux) {
	mux.HandleFunc("POST /sync/aparato", s.alta)
	mux.HandleFunc("GET /sync/bajada", s.bajada)
	mux.HandleFunc("POST /sync/subida", s.subida)
	mux.HandleFunc("GET /sync/estado", s.estado)
}
