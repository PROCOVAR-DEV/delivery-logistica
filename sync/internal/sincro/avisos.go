package sincro

import (
	"errors"
	"sync"
	"time"
)

// EL CONCENTRADOR DE AVISOS EN VIVO DE LA REVISIÓN — `docs/bandeja-de-revision.md`, punto 8.
//
// Quien entregó su cola se enteraba de qué decidió el administrador pulsando «Actualizar estados». Jose
// (09/10/2026): «nada de polling, para eso tenemos SSE». Este es el tablero de señales que hay detrás del
// canal `GET /sync/revision/eventos`: cada conexión abierta se apunta aquí con la PERSONA que la abrió, y
// cuando una decisión cambia el estado de un apunte de esa persona (`avisar`) le llega una señal.
//
// # UNA SEÑAL, NO UNA COLA
//
// El canal de cada suscripción tiene búfer 1 y el envío NO bloquea: si ya hay un aviso sin leer, el nuevo se
// pierde A PROPÓSITO. El aviso no lleva datos («algo cambió, vuelve a preguntar a `mias`»), así que dos avisos
// seguidos valen lo mismo que uno, y apilar no ganaría nada: «aplicar todo en orden» de 25 apuntes son 25
// llamadas a `avisar` y, para quien está mirando, una sola actualización. Lo que SÍ queda garantizado: tras
// cada escritura hay un aviso sin leer que se leerá DESPUÉS de ella (el suyo, o uno anterior que aún no se
// leyó), así que el `mias` que lo sigue ya la ve.
//
// # QUÉ NO ES
//
//   - No es una garantía de entrega: sin suscriptores, `avisar` no hace nada, y el aviso es un extra. Quien
//     no tenga el canal abierto (sin señal, app cerrada) lo sabe igual pulsando «Actualizar estados».
//   - No lleva nada de la entrega. El canal es de la PERSONA y aun así no lleva clave, estado, motivo ni
//     nombre: lo que sale por un flujo largo y sin cabeceras de caché no debe poder filtrar lo que la bandeja
//     decidió. El cliente pregunta a `mias`, que SÍ pasa por el alcance y la comprobación de aparato.
//
// # EL LÍMITE: MEMORIA DE UN SOLO PROCESO
//
// Esto vive en la memoria de `reparto-sync`, que hoy corre en UNA réplica. Con dos, el revisor que decide en la
// réplica A no avisaría a quien tiene el canal abierto en la B. El día que haya más de una hay que pasar el aviso
// por Redis (los `REDIS_*` ya existen en `sync`, los usa `internal/sesiones`): `avisar` publicaría la persona en
// un canal y cada réplica llamaría a su `avisar` local al recibirlo. Mientras tanto, el aviso en vivo es
// «mejor esfuerzo» y el botón «Actualizar estados» sigue siendo la fuente de verdad.
//
// # LOS TOPES
//
// Tres conexiones abiertas por persona (un teléfono, un escritorio y una reconexión que aún no cerró la
// anterior) y 500 en total. Cada una es una goroutine y un descriptor: sin tope, un cliente que reconecta en
// bucle —o alguien con un token de entrega, que lo puede pedir cualquiera que pierda el rol— se come el
// proceso que además aplica las colas de ocho horas. La 4.ª de una persona recibe 429 con `Retry-After: 30`.

const (
	topeDeAvisosPorPersona = 3
	topeDeAvisosEnTotal    = 500
	// Un comentario SSE (`: ka`) cada tanto, para que ni un proxy ni la red móvil den por muerta una conexión
	// que lleva rato callada. 25 s queda por debajo de los 30 s que suelen aguantar las pasarelas de los móviles.
	latidoDeLosAvisos = 25 * time.Second
	// Lo que dice el `Retry-After` del 429.
	esperaTrasElTopeDeAvisos = "30"
	// El plazo de CADA escritura al cliente (`revision_eventos.go`): el mismo que el `WriteTimeout` de `main`. Se
	// renueva antes de cada escritura, no se quita: un cliente cuyo socket murió sin RST (un móvil que perdió la
	// señal) deja de leer, la escritura se bloquea y, sin plazo, el canal y su hueco del tope quedarían retenidos
	// hasta el timeout de TCP, que son horas.
	plazoDeEscrituraDeLosAvisos = 60 * time.Second

	CodigoAvisosAlTope = "avisos_al_tope"
)

var (
	errPersonaAlTopeDeAvisos  = errors.New("la persona ya tiene el máximo de canales de avisos abiertos")
	errServicioAlTopeDeAvisos = errors.New("el servicio ya tiene el máximo de canales de avisos abiertos")
)

// suscripcion es UN canal abierto. `c` no se cierra nunca: quien baja la suscripción la quita del mapa y deja
// que el recolector se la lleve. Cerrarlo haría pánico a cualquier `avisar` que lo tuviera ya en la mano.
type suscripcion struct {
	persona string
	c       chan struct{}
}

type avisos struct {
	mu         sync.Mutex
	porPersona map[string]map[*suscripcion]struct{}
	total      int

	// Los topes y el latido son campos y no constantes a secas para poder probarlos sin abrir 500 conexiones
	// ni esperar 25 segundos.
	topePorPersona, topeEnTotal int
	latido                      time.Duration
	plazoDeEscritura            time.Duration

	// `cerrado` lo cierra el apagado del servidor ([Servicio.CerrarAvisos]): un SSE nunca queda inactivo, así
	// que `http.Server.Shutdown` esperaría a los 30 s de `main` a una conexión que no va a terminar sola.
	cerrado chan struct{}
	cierre  sync.Once
}

func nuevosAvisos() *avisos {
	return &avisos{
		porPersona:     map[string]map[*suscripcion]struct{}{},
		topePorPersona: topeDeAvisosPorPersona, topeEnTotal: topeDeAvisosEnTotal,
		latido: latidoDeLosAvisos, plazoDeEscritura: plazoDeEscrituraDeLosAvisos,
		cerrado: make(chan struct{}),
	}
}

// suscribir apunta un canal nuevo para `persona`. Si no cabe, dice cuál de los dos topes lo impidió. Quien
// llama TIENE que llamar a [avisos.baja] cuando el cliente se vaya.
func (a *avisos) suscribir(persona string) (*suscripcion, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if len(a.porPersona[persona]) >= a.topePorPersona {
		return nil, errPersonaAlTopeDeAvisos
	}
	if a.total >= a.topeEnTotal {
		return nil, errServicioAlTopeDeAvisos
	}
	s := &suscripcion{persona: persona, c: make(chan struct{}, 1)}
	if a.porPersona[persona] == nil {
		a.porPersona[persona] = map[*suscripcion]struct{}{}
	}
	a.porPersona[persona][s] = struct{}{}
	a.total++
	return s, nil
}

// baja quita el canal. Idempotente: una segunda baja no descuenta dos veces del total.
func (a *avisos) baja(s *suscripcion) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if _, hay := a.porPersona[s.persona][s]; !hay {
		return
	}
	delete(a.porPersona[s.persona], s)
	if len(a.porPersona[s.persona]) == 0 {
		delete(a.porPersona, s.persona)
	}
	a.total--
}

// avisar deja una señal pendiente en cada canal de ESA persona, y sólo en los suyos. Nunca bloquea y nunca falla.
func (a *avisos) avisar(persona string) {
	if persona == "" {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	for s := range a.porPersona[persona] {
		select {
		case s.c <- struct{}{}:
		default: // ya hay una sin leer: vale por esta
		}
	}
}

// plazo es el de cada escritura. Con el cerrojo: las pruebas lo acortan (`ajustar`) mientras hay manejadores vivos.
func (a *avisos) plazo() time.Duration {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.plazoDeEscritura
}

func (a *avisos) cerrar() { a.cierre.Do(func() { close(a.cerrado) }) }

// CerrarAvisos cierra todos los canales de avisos abiertos (y los que lleguen después salen al instante). Lo
// llama el apagado del servidor: `servidor.RegisterOnShutdown(servicio.CerrarAvisos)` en `cmd/sync/main.go`. Sin
// eso, un SSE abierto retiene el cierre ordenado hasta que se acaba el plazo, y es el plazo en el que se les da
// tiempo a terminar a las colas de ocho horas que se están aplicando.
func (s *Servicio) CerrarAvisos() { s.avisos.cerrar() }
