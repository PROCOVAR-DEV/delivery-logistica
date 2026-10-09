// Package sesiones: ACCESOS CORTA LAS SESIONES DE LA APK Y EL ESCRITORIO, y el sincronizador lo
// sabe sin preguntar. Es la gemela recortada de `api/internal/sesiones` (otro módulo de Go, así que
// no se puede importar): mismo canal, mismas marcas, mismos nombres de variable `REDIS_*`.
//
// # El hecho que lo trajo — 08/10/2026
//
// `reparto-sync` verifica el token de acceso por su cuenta (`identidad.DeToken`, sin estado): tras un
// corte de seguridad en Accesos —una revocación, una baja, un cambio de rol o de llaves— un token de
// 15 minutos seguiría sirviendo la bajada y la SUBIDA del día hasta caducar. Jose aprobó extender el
// corte a la APK y al escritorio («la web es la web y las APK son la APK»).
//
// # El contrato con Accesos (fijo)
//
//   - Canal [Canal]; mensaje JSON {"v":1,"tipo":"sesion-cerrada"|"permisos-cambiados",
//     "alcance":"web"|"todo","userIds":[...],"tms":<ms>,"motivo":"..."}.
//   - Marcas en la DB [BaseDeLasMarcas]: `procovar:auth:invalida:web:<userId>` y
//     `procovar:auth:invalida:todo:<userId>` (valor `<tms>`, TTL 8 días). Accesos las escribe ANTES
//     de publicar.
//   - La regla del bearer: ya no vale si `todo[persona] >= emitido` ([invalidaAlBearer]), donde
//     `emitido` es el claim `iatms` (milisegundos, que Accesos firma en el token de acceso) y, si
//     falta, `iat*1000` (segundos: se compara por arriba, conservador). Sin `iatms`, un token pedido
//     250 ms DESPUÉS del evento se rechazaba en ~75 % de los casos. **Un evento `web` no le llega**:
//     por eso aquí ni se carga la familia `web`.
//
// # Redis caído o sin configurar NO TUMBA NADA
//
// Se sirve sin el empuje y se dice (WARN al arrancar y en cada caída, INFO al volver, una línea de
// estado cada hora). Al reconectar se vuelven a cargar las marcas con SCAN. El corte responde 401,
// como un token inválido, NO 403: la app lo trata como sesión caducada y renueva, y es Accesos quien
// decide si la sesión murió o sólo falta un permiso.
package sesiones

import (
	"context"
	"encoding/json"
	"log/slog"
	"sort"
	"sync"
	"sync/atomic"
	"time"
)

const (
	// Canal es el pub/sub donde Accesos publica. Literal del contrato.
	Canal = "procovar:auth:eventos"
	// PrefijoDeMarcaTodo precede al id de la persona en la marca de alcance `todo`. Literal del contrato.
	PrefijoDeMarcaTodo = "procovar:auth:invalida:todo:"
	// BaseDeLasMarcas: la DB 6 de Redis, la de las sesiones de Accesos. FIJA por contrato.
	BaseDeLasMarcas = 6
	// VidaDeUnaMarca: el TTL que les pone Accesos.
	VidaDeUnaMarca = 8 * 24 * time.Hour

	AlcanceWeb  = "web"
	AlcanceTodo = "todo"

	tipoSesionCerrada     = "sesion-cerrada"
	tipoPermisosCambiados = "permisos-cambiados"
	versionConocida       = 1

	// LOS TOPES (auditoría de seguridad, 08/10/2026). El canal y las marcas viven en un Redis que
	// comparte toda la casa con una clave común: lo que llegue por ahí NO es de fiar. Sin topes, un
	// `tms` en el futuro (4102444800000, o un salto de reloj de Accesos) dejaba a una persona
	// bloqueada para siempre —cada token nuevo sigue siendo "anterior" a la marca— y el mapa no se
	// rebajaba hasta reiniciar; y un mensaje con un millón de ids, o un millón de mensajes, llenaba
	// la memoria. (Lo correcto es una ACL de Redis: sólo Accesos puede publicar en el canal y
	// escribir `procovar:auth:invalida:*`. Eso es infraestructura; esto es la defensa de este lado.)
	//
	// margenDelFuturo: cuánto se admite un `tms` por delante de nuestro reloj.
	margenDelFuturo = 60 * time.Second
	// maxIdsPorMensaje: de un mensaje se leen como mucho tantos ids (el resto se descarta con un WARN).
	maxIdsPorMensaje = 1000
)

// maxMarcas es el tope de entradas del mapa. Variable para que las pruebas no necesiten cien mil. Al
// pasarse se descartan las MÁS VIEJAS, nunca las recientes.
var maxMarcas = 100_000

// Evento es el mensaje del canal.
type Evento struct {
	V       int      `json:"v"`
	Tipo    string   `json:"tipo"`
	Alcance string   `json:"alcance"`
	UserIDs []string `json:"userIds"`
	Tms     int64    `json:"tms"` // milisegundos Unix
	Motivo  string   `json:"motivo"`
}

// Fuente es lo que hace falta de Redis, y nada más. Una interfaz para que las pruebas corran sin él.
type Fuente interface {
	// Suscribir abre la suscripción y VUELVE cuando Redis ya la confirmó (las marcas se cargan DESPUÉS).
	Suscribir(ctx context.Context) (Suscripcion, error)
	// Marcas hace el SCAN de las marcas `todo`: persona -> tms.
	Marcas(ctx context.Context) (map[string]int64, error)
	Cerrar() error
}

// Suscripcion es una suscripción abierta.
type Suscripcion interface {
	// Siguiente bloquea hasta el próximo mensaje. Un error es "esta conexión murió". Tiene que volver
	// si ctx se cancela.
	Siguiente(ctx context.Context) (string, error)
	Cerrar() error
}

// Registro es el mapa en memoria de las marcas `todo` y el bucle que lo mantiene.
type Registro struct {
	fuente Fuente
	log    *slog.Logger

	mu   sync.RWMutex
	todo map[string]int64

	activo atomic.Bool

	ahora       func() time.Time
	esperaMin   time.Duration
	esperaMax   time.Duration
	cadaLimpiar time.Duration
}

// Nuevo monta el registro. `fuente == nil` es "Redis sin configurar": [Registro.Correr] lo dice y
// vuelve, y [Registro.ElBearerNoVale] contesta siempre que no.
func Nuevo(fuente Fuente, log *slog.Logger) *Registro {
	if log == nil {
		log = slog.Default()
	}
	return &Registro{
		fuente:      fuente,
		log:         log,
		todo:        map[string]int64{},
		ahora:       time.Now,
		esperaMin:   time.Second,
		esperaMax:   30 * time.Second,
		cadaLimpiar: time.Hour,
	}
}

// invalidaAlBearer es la regla: sólo cuenta la marca `todo`, contra el instante en que se emitió el
// token:
//
//   - `iatMs` (el claim `iatms` que firma Accesos, en milisegundos) si viene. Es el exacto, y evita el
//     REBOTE: la APK renueva en cuanto le llega el aviso, y un token pedido 250 ms después del
//     evento no puede salir rechazado.
//   - si no viene, `iat*1000`: el `iat` va en SEGUNDOS y eso es, como mucho, el instante real, así que
//     un token emitido en el mismo segundo que la marca cae del lado de invalidarlo (conservador).
//
// Todo ausente (0) es el instante 0: cualquier marca lo invalida.
//
// GEMELA de `sesiones.invalidaAlBearer` en `reparto-api`: se cambian JUNTAS (las dos tablas de
// pruebas llevan los mismos casos).
func invalidaAlBearer(todo, iatSeg, iatMs int64) bool {
	emitido := iatMs
	if emitido <= 0 {
		emitido = iatSeg * 1000
	}
	return todo > 0 && todo >= emitido
}

// ElBearerNoVale dice si el token de acceso de esta persona, emitido en `iatMs` (milisegundos; 0 si no
// lo trae) o, si no, en `iatSeg` (segundos), ya no vale porque Accesos cortó SUS sesiones (`todo`)
// después. SIN RED: un candado de lectura y un mapa.
func (r *Registro) ElBearerNoVale(persona string, iatSeg, iatMs int64) bool {
	if r == nil {
		return false
	}
	r.mu.RLock()
	todo := r.todo[persona]
	r.mu.RUnlock()
	return invalidaAlBearer(todo, iatSeg, iatMs)
}

// Activo: hay una suscripción viva. Falso = el sincronizador sirve, pero sin el empuje.
func (r *Registro) Activo() bool { return r != nil && r.activo.Load() }

// NumMarcas: cuántas marcas hay en memoria.
func (r *Registro) NumMarcas() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.todo)
}

// Aplicar procesa un mensaje del canal tal cual llegó. Los que no se entienden se IGNORAN con un
// WARN: un mensaje malo no puede parar el bucle. Los de alcance `web` se ignoran sin ruido: no
// tocan al bearer. Un mensaje sin alcance se lee como `todo` (fallar cerrado).
func (r *Registro) Aplicar(crudo string) {
	var ev Evento
	if err := json.Unmarshal([]byte(crudo), &ev); err != nil {
		r.log.Warn("sesiones: mensaje de Accesos que no es JSON válido; se ignora",
			"err", err, "largo", len(crudo), "inicio", recortar(crudo, 80))
		return
	}
	switch {
	case ev.V != versionConocida:
		r.log.Warn("sesiones: mensaje de Accesos con una versión que no conozco; se ignora",
			"v", ev.V, "conozco", versionConocida)
		return
	case ev.Tipo != tipoSesionCerrada && ev.Tipo != tipoPermisosCambiados:
		r.log.Warn("sesiones: mensaje de Accesos con un tipo que no conozco; se ignora",
			"tipo", recortar(ev.Tipo, 40))
		return
	case ev.Alcance != "" && ev.Alcance != AlcanceWeb && ev.Alcance != AlcanceTodo:
		r.log.Warn("sesiones: mensaje de Accesos con un alcance que no conozco; se ignora",
			"alcance", recortar(ev.Alcance, 40))
		return
	case ev.Tms <= 0:
		r.log.Warn("sesiones: mensaje de Accesos sin tms; se ignora", "tipo", ev.Tipo)
		return
	case r.enElFuturo(ev.Tms):
		// Bloquearía a esa persona hasta ese día: cada token nuevo seguiría siendo "anterior".
		r.log.Warn("sesiones: mensaje de Accesos con un tms en el futuro; se ignora",
			"tipo", ev.Tipo, "tms", ev.Tms, "ahora_ms", r.ahora().UnixMilli())
		return
	}
	if ev.Alcance == AlcanceWeb {
		return // un cierre de sesión del navegador no echa a la APK
	}
	if n := len(ev.UserIDs); n > maxIdsPorMensaje {
		r.log.Warn("sesiones: mensaje de Accesos con demasiadas personas; sólo se leen las primeras",
			"tipo", ev.Tipo, "personas", n, "tope", maxIdsPorMensaje)
		ev.UserIDs = ev.UserIDs[:maxIdsPorMensaje]
	}

	personas := 0
	r.mu.Lock()
	for _, id := range ev.UserIDs {
		if id == "" {
			continue
		}
		personas++
		// El tms MAYOR: un mensaje atrasado no puede rebajar una marca más nueva.
		if r.todo[id] < ev.Tms {
			r.todo[id] = ev.Tms
		}
	}
	acotar(r.todo)
	r.mu.Unlock()
	if personas == 0 {
		r.log.Warn("sesiones: mensaje de Accesos sin personas; se ignora", "tipo", ev.Tipo)
		return
	}
	r.log.Info("sesiones: Accesos cortó sesiones", "tipo", ev.Tipo, "personas", personas,
		"motivo", recortar(ev.Motivo, 80))
}

// enElFuturo dice si un `tms` va más allá de lo que se admite: [margenDelFuturo] por delante de
// nuestro reloj.
func (r *Registro) enElFuturo(tms int64) bool {
	return tms > r.ahora().Add(margenDelFuturo).UnixMilli()
}

// fusionar mete las marcas leídas con SCAN, quedándose con el tms mayor de cada persona. Las que
// están en el futuro se ignoran (y se cuentan en el registro), igual que en [Registro.Aplicar], y el
// mapa queda acotado a [maxMarcas].
func (r *Registro) fusionar(marcas map[string]int64) {
	r.mu.Lock()
	defer r.mu.Unlock()
	futuras := 0
	for id, tms := range marcas {
		if r.enElFuturo(tms) {
			futuras++
			continue
		}
		if r.todo[id] < tms {
			r.todo[id] = tms
		}
	}
	acotar(r.todo)
	if futuras > 0 {
		r.log.Warn("sesiones: marcas de Accesos con un tms en el futuro; se ignoran", "marcas", futuras)
	}
}

// acotar deja el mapa en [maxMarcas] como mucho, descartando las MÁS VIEJAS y nunca las recientes.
// Con el candado cogido. Cuando se pasa, recorta de golpe hasta el 90 %, para no ordenar en cada alta.
func acotar(m map[string]int64) {
	if len(m) <= maxMarcas {
		return
	}
	type marca struct {
		id  string
		tms int64
	}
	todas := make([]marca, 0, len(m))
	for id, tms := range m {
		todas = append(todas, marca{id, tms})
	}
	sort.Slice(todas, func(i, j int) bool { return todas[i].tms < todas[j].tms })
	for _, v := range todas[:len(todas)-maxMarcas*9/10] {
		delete(m, v.id)
	}
}

// limpiar olvida las marcas de hace más de [VidaDeUnaMarca] y REBAJA las que quedaron por delante de
// nuestro reloj (una que se coló con el reloj atrasado, o un salto de reloj): las deja en "ahora",
// que sigue cortando los tokens anteriores y no bloquea los nuevos. Devuelve cuántas quitó.
func (r *Registro) limpiar() int {
	ahora := r.ahora()
	corte := ahora.Add(-VidaDeUnaMarca).UnixMilli()
	techo := ahora.Add(margenDelFuturo).UnixMilli()
	r.mu.Lock()
	defer r.mu.Unlock()
	quitadas := 0
	for id, tms := range r.todo {
		switch {
		case tms < corte:
			delete(r.todo, id)
			quitadas++
		case tms > techo:
			r.todo[id] = ahora.UnixMilli()
		}
	}
	return quitadas
}

// Correr es el bucle: suscribe, carga las marcas, lee; si algo falla, espera (con retroceso) y vuelve
// a empezar —recargando las marcas—. Bloquea hasta que ctx se cancela y no deja nada vivo detrás. Sin
// [Fuente] avisa y vuelve en el acto.
func (r *Registro) Correr(ctx context.Context) {
	if r.fuente == nil {
		r.log.Warn("sesiones: sin Redis configurado (REDIS_CENTINELAS / REDIS_DIRECCION / REDIS_URL): " +
			"el sincronizador sirve igual, pero un corte de sesiones en Accesos NO se notará aquí " +
			"hasta que caduque el token de acceso (15 minutos)")
		return
	}
	defer r.fuente.Cerrar()

	var hilos sync.WaitGroup
	hilos.Add(1)
	go func() {
		defer hilos.Done()
		r.limpiarCada(ctx)
	}()
	defer hilos.Wait()

	espera := r.esperaMin
	for ctx.Err() == nil {
		err := r.unaConexion(ctx, func() { espera = r.esperaMin })
		r.activo.Store(false)
		if ctx.Err() != nil {
			return
		}
		r.log.Warn("sesiones: se perdió el empuje de Accesos; el sincronizador sigue sirviendo sin él y reintento",
			"err", err, "reintento_en", espera.String())
		t := time.NewTimer(espera)
		select {
		case <-ctx.Done():
			t.Stop()
			return
		case <-t.C:
		}
		if espera *= 2; espera > r.esperaMax {
			espera = r.esperaMax
		}
	}
}

// unaConexion: una vida entera de la suscripción. Siempre vuelve con error.
func (r *Registro) unaConexion(ctx context.Context, conectada func()) error {
	sus, err := r.fuente.Suscribir(ctx)
	if err != nil {
		return err
	}
	defer sus.Cerrar()

	// PRIMERO SUSCRITOS Y DESPUÉS EL SCAN: lo que se publique durante el SCAN espera en la
	// suscripción y se aplica después; al revés, se perdería en el hueco.
	marcas, err := r.fuente.Marcas(ctx)
	if err != nil {
		r.log.Warn("sesiones: no pude cargar las marcas de Accesos; sigo con el canal "+
			"(las marcas de antes de este momento no se conocerán hasta la próxima reconexión)", "err", err)
	} else {
		r.fusionar(marcas)
	}
	r.activo.Store(true)
	conectada()
	r.log.Info("sesiones: empuje de Accesos activo", "marcas", r.NumMarcas())

	for {
		crudo, err := sus.Siguiente(ctx)
		if err != nil {
			return err
		}
		r.Aplicar(crudo)
	}
}

// limpiarCada olvida las marcas viejas y deja la línea de estado.
func (r *Registro) limpiarCada(ctx context.Context) {
	t := time.NewTicker(r.cadaLimpiar)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			quitadas := r.limpiar()
			r.log.Info("sesiones: estado", "empuje_activo", r.Activo(), "marcas", r.NumMarcas(), "olvidadas", quitadas)
		}
	}
}

func recortar(s string, largo int) string {
	if len(s) <= largo {
		return s
	}
	return s[:largo] + "…"
}
