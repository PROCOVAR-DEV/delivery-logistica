// Package sesiones: ACCESOS MANDA SOBRE LA SESIÓN DE LA WEB, y avisa EMPUJANDO.
//
// # El hecho que lo trajo — 08/10/2026
//
// Jose cerró sesión en Accesos y siguió dentro de Reparto: la web emite SU cookie
// (`auth_web.go`, siete días) y nunca más pregunta a Accesos. Cambiar los permisos de alguien
// tardaba hasta siete días en notarse. Lo pidió así: «Accesos debe afectar a las otras sesiones;
// si inicio en una estoy logueado en las otras, y si cierro sesión o me cambian un permiso en
// Accesos se refleja en todas. Nada de polling: para eso tenemos SSE y Sentinel».
//
// # El contrato con Accesos (fijo; lo implementa Accesos, no se cambia desde aquí)
//
//   - Canal pub/sub [Canal]; mensaje JSON [Evento]:
//     {"v":1,"tipo":"sesion-cerrada"|"permisos-cambiados","alcance":"web"|"todo",
//     "userIds":[...],"tms":<ms>,"motivo":"..."}.
//   - El ALCANCE (contrato ampliado el 08/10/2026): `web` es un cierre de sesión (`logout`) y sólo
//     toca a la cookie de la web; `todo` es una revocación explícita, una baja, un cambio de rol,
//     de llaves, de admin, de membresía o un borrado, y toca TAMBIÉN a la APK y al escritorio.
//   - Las marcas de recuperación: DOS claves por persona en la DB [BaseDeLasMarcas],
//     `procovar:auth:invalida:web:<userId>` y `procovar:auth:invalida:todo:<userId>`, con valor
//     `<tms>` y TTL de [VidaDeUnaMarca]. Accesos las escribe ANTES de publicar.
//   - La regla de la COOKIE web (esto es lo que se aplica hoy): ya no vale si
//     `max(web[persona], todo[persona]) >= iatms` ([invalidaALaCookie]).
//   - La regla del BEARER de la APK y el escritorio (aprobada por Jose el 08/10/2026: «la web es la
//     web y las APK son la APK»): ya no vale si `todo[persona] >= emitido` ([invalidaAlBearer]),
//     donde `emitido` es el claim `iatms` (milisegundos, que Accesos firma en el token de acceso) y,
//     si falta, `iat*1000` (el `iat` va en segundos: se compara por arriba, o sea de forma
//     conservadora). Sin el `iatms`, un token pedido 250 ms DESPUÉS del evento —la APK renueva en
//     cuanto le llega el aviso— se rechazaba en ~75 % de los casos. Un evento `web` NUNCA le llega:
//     cerrar sesión en el navegador no echa al teléfono. La aplican `auth.Verificador` (esta API) y, con una copia de este paquete,
//     el sincronizador (`sync/internal/sesiones`): el corte responde 401 como un token inválido,
//     NO 403, para que la app lo trate como sesión caducada, renueve, y sea Accesos quien decida
//     si la sesión murió o sólo falta un permiso.
//
// # Qué hace este paquete
//
// Al arrancar carga las marcas con SCAN (las dos familias), se suscribe al canal y mantiene DOS mapas
// EN MEMORIA `persona -> tms`, uno por alcance. [Registro.LaCookieNoVale] los consulta sin tocar la red: la comprobación de cada
// petición cuesta un candado de lectura y un mapa, no un viaje a Redis. Cada mensaje, además,
// avisa a quien se haya enganchado en [Registro.AlEvento] (el difusor del SSE, para cerrarle la
// conexión a esa persona en el acto).
//
// # Redis caído o sin configurar NO TUMBA NADA
//
// La API arranca y sirve igual, sin el empuje, y lo DICE (WARN al arrancar, WARN en cada caída,
// INFO al volver, y una línea de estado cada hora). Al reconectar vuelve a cargar las marcas con
// SCAN, por si se perdió un mensaje mientras no se oía. Lo que no se puede perder es lo que
// ocurre MIENTRAS está caído: la marca se queda en Redis ocho días, y el SCAN de la reconexión
// la recoge; pero una cookie vive siete, así que una caída larga no abre ninguna ventana que el
// SCAN no cierre (ver [VidaDeUnaMarca]).
//
// LÍMITE CONOCIDO: las conexiones SSE ya abiertas de quien se invalidó MIENTRAS no se oía no
// reciben el aviso (sólo se recargan las marcas, que no dicen si fue cierre de sesión o cambio de
// permisos). Se cierran solas cuando el proxy corta el canal (cada ~5 min) y la reconexión recibe
// 401 por la marca.
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
	// Los dos prefijos de las marcas, uno por alcance; el id de la persona va detrás. Literales del contrato.
	PrefijoDeMarcaWeb  = "procovar:auth:invalida:web:"
	PrefijoDeMarcaTodo = "procovar:auth:invalida:todo:"
	// BaseDeLasMarcas: la DB 6 de Redis, la de las sesiones de Accesos. FIJA por contrato:
	// no sale de `REDIS_BASE` (esa es la de la cola de PEDIDO del espejo).
	BaseDeLasMarcas = 6

	// VidaDeUnaMarca es el TTL que les pone Accesos: ocho días, uno más que la cookie de la web
	// (siete). Por eso se puede olvidar una entrada del mapa a los ocho: ninguna cookie anterior
	// a ella puede seguir viva.
	VidaDeUnaMarca = 8 * 24 * time.Hour

	TipoSesionCerrada     = "sesion-cerrada"
	TipoPermisosCambiados = "permisos-cambiados"

	// AlcanceWeb: sólo la cookie de la web. AlcanceTodo: la web y también la APK y el escritorio.
	AlcanceWeb  = "web"
	AlcanceTodo = "todo"

	// versionConocida: la `v` del mensaje que sabemos leer. Otra se ignora con un WARN.
	versionConocida = 1

	// LOS TOPES (auditoría de seguridad, 08/10/2026). El canal y las marcas viven en un Redis que
	// comparte toda la casa con una clave común: lo que llegue por ahí NO es de fiar. Sin topes, un
	// `tms` en el futuro (4102444800000, o un salto de reloj de Accesos) dejaba a una persona
	// bloqueada para siempre —cada cookie nueva sigue siendo "anterior" a la marca— y el mapa no
	// se rebajaba hasta reiniciar; y un mensaje con un millón de ids, o un millón de mensajes,
	// llenaba la memoria. (Lo correcto es una ACL de Redis: sólo Accesos puede publicar en el canal y
	// escribir `procovar:auth:invalida:*`. Eso es infraestructura; esto es la defensa de este lado.)
	//
	// margenDelFuturo: cuánto se admite un `tms` por delante de nuestro reloj. Un minuto cubre un
	// desfase de relojes entre contenedores; más es un fallo o un ataque.
	margenDelFuturo = 60 * time.Second
	// maxIdsPorMensaje: de un mensaje se leen como mucho tantos ids (el resto se descarta con un WARN).
	maxIdsPorMensaje = 1000
)

// maxMarcas es el tope de entradas de CADA mapa. Variable para que las pruebas no necesiten cien mil.
// Al pasarse se descartan las MÁS VIEJAS, nunca las recientes: una marca vieja ya casi no puede
// afectar a ninguna cookie viva, una reciente sí.
var maxMarcas = 100_000

// Evento es el mensaje del canal.
type Evento struct {
	V    int    `json:"v"`
	Tipo string `json:"tipo"`
	// Alcance: [AlcanceWeb] o [AlcanceTodo]. Si NO VIENE se lee como `todo`: fallar cerrado,
	// porque ignorar un mensaje de invalidación deja una sesión viva que Accesos quiso matar.
	Alcance string   `json:"alcance"`
	UserIDs []string `json:"userIds"`
	Tms     int64    `json:"tms"` // milisegundos Unix
	Motivo  string   `json:"motivo"`
}

// Fuente es lo que hace falta de Redis, y nada más. Una interfaz para que las pruebas corran
// sin Redis (igual que `espejo.LectorDeAvisos`).
type Fuente interface {
	// Suscribir abre la suscripción al [Canal] y VUELVE cuando Redis ya la confirmó: lo que se
	// publique a partir de ahí no se pierde, y las marcas se cargan DESPUÉS.
	Suscribir(ctx context.Context) (Suscripcion, error)
	// Marcas hace el SCAN de las dos familias de marcas en la DB 6.
	Marcas(ctx context.Context) (Marcas, error)
	// Cerrar suelta el cliente. Lo llama [Registro.Correr] al terminar.
	Cerrar() error
}

// Marcas es lo que devuelve el SCAN: persona -> tms, una por alcance.
type Marcas struct{ Web, Todo map[string]int64 }

// Suscripcion es una suscripción abierta.
type Suscripcion interface {
	// Siguiente bloquea hasta el próximo mensaje (el JSON crudo). Un error es "esta conexión
	// murió": quien llama la cierra y vuelve a empezar. Tiene que volver si ctx se cancela.
	Siguiente(ctx context.Context) (string, error)
	Cerrar() error
}

// Registro es el mapa en memoria de las marcas y el bucle que lo mantiene.
type Registro struct {
	fuente Fuente
	log    *slog.Logger

	// AlEvento se llama con CADA mensaje válido, DESPUÉS de haber actualizado el mapa (para que
	// quien reciba el aviso y reconecte ya se encuentre la marca puesta). `alcance` es el EFECTIVO
	// ([AlcanceWeb] o [AlcanceTodo]; un mensaje sin alcance llega como `todo`). Se asigna antes de
	// [Registro.Correr]. Es el enganche del difusor del SSE (`api.Servidor.PonerSesiones`).
	AlEvento func(alcance, tipo string, userIDs []string)

	mu   sync.RWMutex
	web  map[string]int64 // persona -> tms del último cierre de sesión en Accesos
	todo map[string]int64 // persona -> tms de la última invalidación TOTAL

	activo atomic.Bool // hay suscripción viva ahora mismo

	// Por fuera para que las pruebas no esperen segundos ni días.
	ahora       func() time.Time
	esperaMin   time.Duration
	esperaMax   time.Duration
	cadaLimpiar time.Duration
}

// Nuevo monta el registro. `fuente == nil` es "Redis sin configurar": [Registro.Correr] lo dice
// y vuelve, y [Registro.Invalidada] contesta siempre que no.
func Nuevo(fuente Fuente, log *slog.Logger) *Registro {
	if log == nil {
		log = slog.Default()
	}
	return &Registro{
		fuente:      fuente,
		log:         log,
		web:         map[string]int64{},
		todo:        map[string]int64{},
		ahora:       time.Now,
		esperaMin:   time.Second,
		esperaMax:   30 * time.Second,
		cadaLimpiar: time.Hour,
	}
}

// invalidaALaCookie es la REGLA de la cookie de la web, pura: la cookie emitida en `iatMs`
// (milisegundos) no vale si hay marca `web` o `todo` de esa persona (>0 es "hay") y la mayor es
// de después o del mismo instante. `iatMs == 0` es una cookie sin `iatms` (anterior a este
// cambio): cuenta como emitida en el instante 0, o sea que cualquier marca la invalida.
func invalidaALaCookie(web, todo, iatMs int64) bool {
	m := max(web, todo)
	return m > 0 && m >= iatMs
}

// invalidaAlBearer es la regla del token de la APK y el escritorio (ver la cabecera del paquete):
// sólo cuenta la marca `todo` —un cierre de sesión `web` no le llega nunca—, contra el instante en
// que se emitió el token:
//
//   - `iatMs` (el claim `iatms` que firma Accesos, en milisegundos) si viene. Es el exacto, y es el
//     que evita el REBOTE: la APK renueva en cuanto le llega el aviso, y un token pedido 250 ms
//     después del evento no puede salir rechazado.
//   - si no viene, `iat*1000`: el `iat` va en SEGUNDOS y eso es, como mucho, el instante real, así que
//     un token emitido en el mismo segundo que la marca cae del lado de invalidarlo. Es la
//     comparación conservadora; sólo se usa con tokens que no traen `iatms`.
//
// Todo ausente (0) es el instante 0: cualquier marca lo invalida.
//
// GEMELA de `sesiones.invalidaAlBearer` en `reparto-sync`: se cambian JUNTAS (las dos tablas de
// pruebas llevan los mismos casos).
func invalidaAlBearer(todo, iatSeg, iatMs int64) bool {
	emitido := iatMs
	if emitido <= 0 {
		emitido = iatSeg * 1000
	}
	return todo > 0 && todo >= emitido
}

// LaCookieNoVale dice si la cookie de esta persona, emitida en `iatMs` (milisegundos), ya no vale
// porque Accesos marcó su sesión DESPUÉS (o en el mismo instante), con cualquier alcance.
//
// SIN RED: un candado de lectura y dos mapas. Es lo que se llama en cada petición.
func (r *Registro) LaCookieNoVale(persona string, iatMs int64) bool {
	if r == nil {
		return false
	}
	r.mu.RLock()
	web, todo := r.web[persona], r.todo[persona]
	r.mu.RUnlock()
	return invalidaALaCookie(web, todo, iatMs)
}

// ElBearerNoVale es la pregunta equivalente para el token de la APK y el escritorio, con su `iat`
// (segundos) y su `iatms` (milisegundos; 0 si no lo trae). Ver [invalidaAlBearer].
func (r *Registro) ElBearerNoVale(persona string, iatSeg, iatMs int64) bool {
	if r == nil {
		return false
	}
	r.mu.RLock()
	todo := r.todo[persona]
	r.mu.RUnlock()
	return invalidaAlBearer(todo, iatSeg, iatMs)
}

// Activo: hay una suscripción viva. Falso = la API sirve, pero sin el empuje.
func (r *Registro) Activo() bool { return r != nil && r.activo.Load() }

// NumMarcas: cuántas marcas hay en memoria (las `web` más las `todo`).
func (r *Registro) NumMarcas() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.web) + len(r.todo)
}

// Aplicar procesa un mensaje del canal tal cual llegó. Los que no se entienden —JSON roto, una
// `v` que no conocemos, un tipo que no es de los dos— se IGNORAN con un WARN: un mensaje malo
// no puede parar el bucle ni dejar la API sin el empuje de los buenos.
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
	case ev.Tipo != TipoSesionCerrada && ev.Tipo != TipoPermisosCambiados:
		r.log.Warn("sesiones: mensaje de Accesos con un tipo que no conozco; se ignora",
			"tipo", recortar(ev.Tipo, 40))
		return
	case ev.Alcance != "" && ev.Alcance != AlcanceWeb && ev.Alcance != AlcanceTodo:
		r.log.Warn("sesiones: mensaje de Accesos con un alcance que no conozco; se ignora",
			"alcance", recortar(ev.Alcance, 40))
		return
	case ev.Tms <= 0:
		// Un cero marcaría como invalidada CUALQUIER cookie vieja (iatms 0): no es un mensaje, es un fallo.
		r.log.Warn("sesiones: mensaje de Accesos sin tms; se ignora", "tipo", ev.Tipo)
		return
	case r.enElFuturo(ev.Tms):
		// Bloquearía a esa persona hasta ese día: cada cookie nueva seguiría siendo "anterior".
		r.log.Warn("sesiones: mensaje de Accesos con un tms en el futuro; se ignora",
			"tipo", ev.Tipo, "tms", ev.Tms, "ahora_ms", r.ahora().UnixMilli())
		return
	}
	if n := len(ev.UserIDs); n > maxIdsPorMensaje {
		r.log.Warn("sesiones: mensaje de Accesos con demasiadas personas; sólo se leen las primeras",
			"tipo", ev.Tipo, "personas", n, "tope", maxIdsPorMensaje)
		ev.UserIDs = ev.UserIDs[:maxIdsPorMensaje]
	}

	destino := ev.Alcance
	if destino == "" {
		destino = AlcanceTodo
	}
	personas := make([]string, 0, len(ev.UserIDs))
	r.mu.Lock()
	mapa := r.todo
	if destino == AlcanceWeb {
		mapa = r.web
	}
	for _, id := range ev.UserIDs {
		if id == "" {
			continue
		}
		personas = append(personas, id)
		// El tms MAYOR: un mensaje atrasado no puede rebajar una marca más nueva.
		if mapa[id] < ev.Tms {
			mapa[id] = ev.Tms
		}
	}
	acotar(mapa)
	r.mu.Unlock()
	if len(personas) == 0 {
		r.log.Warn("sesiones: mensaje de Accesos sin personas; se ignora", "tipo", ev.Tipo)
		return
	}
	r.log.Info("sesiones: Accesos invalidó sesiones", "tipo", ev.Tipo, "alcance", destino, "personas", len(personas), "motivo", recortar(ev.Motivo, 80))
	if r.AlEvento != nil {
		r.AlEvento(destino, ev.Tipo, personas)
	}
}

// enElFuturo dice si un `tms` va más allá de lo que se admite: [margenDelFuturo] por delante de
// nuestro reloj.
func (r *Registro) enElFuturo(tms int64) bool {
	return tms > r.ahora().Add(margenDelFuturo).UnixMilli()
}

// fusionar mete las marcas leídas con SCAN, quedándose con el tms mayor de cada persona. Las que
// están en el futuro se ignoran (y se cuentan en el registro), igual que en [Registro.Aplicar], y
// los mapas quedan acotados a [maxMarcas].
func (r *Registro) fusionar(m Marcas) {
	r.mu.Lock()
	defer r.mu.Unlock()
	futuras := fundir(r.web, m.Web, r.enElFuturo) + fundir(r.todo, m.Todo, r.enElFuturo)
	acotar(r.web)
	acotar(r.todo)
	if futuras > 0 {
		r.log.Warn("sesiones: marcas de Accesos con un tms en el futuro; se ignoran", "marcas", futuras)
	}
}

// fundir mete `origen` en `destino` (el tms mayor de cada id) sin las que cumplan `descartar`;
// devuelve cuántas descartó.
func fundir(destino, origen map[string]int64, descartar func(int64) bool) (descartadas int) {
	for id, tms := range origen {
		if descartar(tms) {
			descartadas++
			continue
		}
		if destino[id] < tms {
			destino[id] = tms
		}
	}
	return descartadas
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

// limpiar olvida las marcas de hace más de [VidaDeUnaMarca] y REBAJA las que quedaron por delante
// de nuestro reloj (una que se coló con el reloj atrasado, o un salto de reloj): las deja en
// "ahora", que sigue cortando las cookies anteriores y no bloquea las nuevas. Devuelve cuántas
// quitó.
func (r *Registro) limpiar() int {
	ahora := r.ahora()
	corte := ahora.Add(-VidaDeUnaMarca).UnixMilli()
	techo := ahora.Add(margenDelFuturo).UnixMilli()
	r.mu.Lock()
	defer r.mu.Unlock()
	quitadas := 0
	for _, mapa := range []map[string]int64{r.web, r.todo} {
		for id, tms := range mapa {
			switch {
			case tms < corte:
				delete(mapa, id)
				quitadas++
			case tms > techo:
				mapa[id] = ahora.UnixMilli()
			}
		}
	}
	return quitadas
}

// Correr es el bucle: suscribe, carga las marcas, lee; si algo falla, espera (con retroceso) y
// vuelve a empezar —recargando las marcas—. Bloquea hasta que ctx se cancela, y no deja nada
// vivo detrás. Sin [Fuente] avisa y vuelve en el acto.
func (r *Registro) Correr(ctx context.Context) {
	if r.fuente == nil {
		r.log.Warn("sesiones: sin Redis configurado (REDIS_CENTINELAS / REDIS_DIRECCION / REDIS_URL): " +
			"la API sirve igual, pero una sesión que Accesos cierre o cuyos permisos cambien NO se " +
			"notará en la web hasta que caduque su cookie (7 días)")
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
		r.log.Warn("sesiones: se perdió el empuje de Accesos; la API sigue sirviendo sin él y reintento",
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

// unaConexion: una vida entera de la suscripción. `conectada` se avisa cuando ya está viva (para
// que el retroceso vuelva a empezar). Siempre vuelve con error: o murió, o se canceló ctx.
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
		// No es motivo para no oír el canal: los mensajes nuevos siguen valiendo.
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

// limpiarCada olvida las marcas viejas y deja la línea de estado: sin ella, "el empuje está
// caído" sólo se sabría buscando el WARN de la caída.
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
