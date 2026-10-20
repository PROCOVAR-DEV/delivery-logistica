// EL ESPEJO DE PEDIDO: la pieza que trae los datos.
//
// Sin esto, la base del reparto no tiene ni un pedido. Aquí dentro no se da de alta nada a
// mano: los pedidos y los clientes son de PEDIDO, y este proceso los copia.
//
// Antes esto era una COLA (una tabla de trabajos) que procesaba los pedidos de uno en uno
// con una pausa entre cada uno. Esa lentitud era a propósito: alimentaba una pantalla de
// sincronización que enseñaba el progreso en vivo. Quitada la pantalla, la cola no servía a
// nadie — sólo hacía que traerse 600 pedidos tardara quince minutos en vez de unos segundos.
//
// EL COSTO DEL DOMICILIO NO SE TOCA. Lo pone la APK de Entrega directamente en PEDIDO, y
// este proceso NO le escribe nada a PEDIDO. Nunca. Eso está borrado y no detrás de un
// interruptor a propósito: mientras existiera la forma de reactivarlo, existía la forma de
// que dos sistemas escribieran el mismo campo y que el último en pasar pisara al otro sin
// que nadie se enterara.
package espejo

import (
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Opciones es todo lo que el espejo necesita saber. Sale del entorno UNA vez al arrancar,
// por lo mismo que `internal/config`: una variable que falta y se descubre a mitad de la
// primera pasada deja el espejo dando vueltas sin traer nada y con el proceso "sano".
type Opciones struct {
	// A quién se le piden los pedidos y a dónde se meten.
	PedidoURL   string
	DeliveryURL string
	// La llave de servicio. Es la MISMA en las dos puntas: con ella se firma la petición a
	// PEDIDO y con ella se entra a `/api/quote/batch`.
	Clave string
	// Si se pone, el espejo trae SÓLO esa sucursal. Vacío = las ocho.
	SucursalCodigo string

	// Cada cuánto se repasa.
	//
	// UN MINUTO, NO CINCO. El costo del domicilio lo pone el repartidor desde Entrega y
	// hasta que el espejo no pasa, aquí sigue diciendo «sin cotizar». Cinco minutos mirando
	// una pantalla que no cambia se leen como que está roto. El ciclo es barato —lo
	// incremental casi siempre trae cero filas—, y lo caro (el barrido del histórico) tiene
	// su propio freno en `BarridoCada`.
	Poll time.Duration
	// PollDelEntorno: `SYNC_POLL_MS` venía escrito. Ver `RitmoDelCiclo`.
	PollDelEntorno bool

	// TramoDias: cuántos días por petición al recorrer el histórico.
	TramoDias int
	// HistoricoDias: hasta dónde atrás llega el histórico.
	//
	// ERA 420 —un año y pico— Y NO SERVÍA PARA NADA. Medido el 26/09/2026 con el espejo
	// llevando meses corriendo: el reparto tiene **5.480 pedidos y el más viejo es de hace
	// 27 días**. Nada de lo que el barrido traía de los días 30 a 420 se quedaba, porque
	// PEDIDO filtra por repartible y la puerta de entrada rechaza lo que no tiene
	// geolocalización ni factura. **De 101.445 pedidos traídos en un día se quedaron 5.480:
	// el 95% del trabajo era para tirarlo.**
	//
	// Jose, viendo que PEDIDO tiene 67.971 pedidos en total y el espejo se trajo 101.445 en
	// un día: «cómo que anda buscando, si ya PEDIDO lo notifica… que chequee si están
	// iguales los espejos, sólo eso, no que ande buscando… no 200 pedidos nuevos». Y
	// después: «el espejo de sólo lo que necesita reparto, no todos».
	//
	// SESENTA DÍAS es el doble de lo que hoy sobrevive, que es el margen para que un cambio
	// en los filtros de allá no deje un hueco. Si alguna vez hace falta más histórico, se
	// sube ESTA variable y se dice por qué — pero traer un año «por si acaso» es cargar la
	// conexión de allá para no encontrar nada.
	HistoricoDias int
	// HistoricoPorCiclo: cuánto histórico se recupera POR CICLO.
	//
	// El histórico no se trae de una sentada: se va estirando hacia atrás un poco en cada
	// vuelta. Así lo reciente está disponible desde el primer ciclo —que es lo que hace
	// falta para trabajar hoy— y el año entero acaba de llenarse solo al cabo de un rato,
	// sin un proceso de una hora que si se corta hay que volver a empezar.
	HistoricoPorCiclo int
	// RepasoDias: y además, SIEMPRE, una repasada a los últimos días.
	//
	// `since` se fía de que PEDIDO toque `updatedAt` en cada cambio. Si alguna vez no lo
	// hace —una carga masiva, una corrección por SQL— ese pedido no vuelve a aparecer
	// nunca. Un repaso corto de los últimos días lo recoge igual. Cuesta poco y tapa el
	// único agujero que tiene el sincronizado incremental.
	RepasoDias int
	// BarridoCada: cada cuánto toca estirar el histórico. El barrido es lo caro y lo viejo
	// no se mueve, así que tiene su propio freno aparte del ritmo del ciclo.
	//
	// **CON AVISOS ENTRANDO SE USA [BarridoConAvisos], que es una vez al día.** Ver ahí el
	// porqué. Esta variable sigue mandando cuando nadie avisa, que es cuando el barrido
	// vuelve a ser lo único que caza lo que el `since` se pierde.
	BarridoCada time.Duration

	// SoloRepartibles: SÓLO LO QUE PUEDE SUBIR A UN CAMIÓN. Encendido por defecto.
	//
	// Antes el espejo traía el catálogo entero de PEDIDO —todos los estados, archivados
	// incluidos, de todo el año— y se filtraba en la pantalla. Los números: 54.077 pedidos
	// copiados, 49.590 archivados, y de todos ellos 1.277 que podían repartirse. Quien
	// abría el reparto veía el 100 % para trabajar con el 2 %, y se perdía entre filtros.
	//
	// Se apaga con `SYNC_TODOS=1` si alguna vez hace falta el catálogo entero. Los pedidos
	// que ya están copiados NO se borran: dejan de refrescarse y se quedan como historia.
	SoloRepartibles bool
	// SoloDomicilio: sólo los pedidos que LLEVAN domicilio. Apagado por defecto — los que
	// no llevan también valen: se ven en el mapa, cuentan para la capacidad del camión, y
	// un pedido puede pasar a llevarlo.
	SoloDomicilio bool
	// SoloCotizados: y de ésos, sólo los que YA tienen el costo puesto. También apagado, y
	// por un número: de los 1.243 pedidos con domicilio y geolocalización de los últimos
	// quince días, los que la APK ya cotizó eran SEIS. Con esto puesto, el reparto se queda
	// con seis pedidos y parece roto.
	SoloCotizados bool

	// CotizadosMin: la ventana de «los recién cotizados», en minutos. Es lo único que la
	// gente mira esperando a que cambie.
	CotizadosMin int

	// Lote: cuántos pedidos por POST a `/api/quote/batch`. 200 es un tamaño realista de
	// camión, y mandar miles en un solo POST es lo que reventó la memoria la vez anterior.
	Lote int
	// PaginaClientes: cuántos clientes por página. Traerlos todos de golpe eran 2,17 MB en
	// una sola respuesta; por páginas la memoria se mantiene plana y una respuesta cortada a
	// medias no deja el proceso con datos incompletos.
	PaginaClientes int

	// --- El canal de avisos de PEDIDO ---------------------------------------
	//
	// PEDIDO deja un aviso en un stream de Redis cada vez que un pedido pasa a importarle
	// al reparto, y el espejo lo lee BLOQUEADO: entra en cuanto lo sueltan, sin sondeo.
	// Ver `avisos_de_pedido.go`.
	//
	// SIN `REDIS_DIRECCION` NI CENTINELAS NO SE ENCHUFA NADA y el espejo sigue con su
	// ciclo de siempre. Es lo que hace que esto se pueda desplegar antes de tocar el
	// Redis, y que un Redis caído no impida arrancar: el ciclo es la red de debajo.
	RedisDireccion  string
	RedisCentinelas []string
	RedisMaestro    string
	RedisClave      string
	RedisBase       int
	Stream          string

	// EscuchaElStream: si se lee la cola de Redis.
	//
	// Existe para poder APAGAR la cola sin quitar `REDIS_URL`, que es lo que hacía falta el
	// día de la mudanza al webhook: mientras las dos puertas conviven, el mismo aviso entra
	// por las dos, y el orden acordado con la sesión de PEDIDO es apagar la cola SÓLO cuando
	// se ha visto entrar una tanda por HTTP. Sin este interruptor, apagarla obligaba a
	// quitarle el Redis al servicio entero.
	//
	// Por defecto true cuando hay Redis: quien no toque nada sigue como estaba.
	EscuchaElStream bool

	// TocanLaPuerta: si PEDIDO avisa por el webhook (`POST /api/webhooks/pedido`).
	//
	// EL ESPEJO NO RECIBE ESE POST —entra por la API—, pero SÍ le cambia el ritmo: es la
	// diferencia entre «soy el único que se entera de las cosas» y «soy la red de debajo».
	// Se deduce de la MISMA pareja key+secret que usa la API, así que ponerla en el servicio
	// ya lo dice y no hay una segunda variable que se pueda quedar a medias.
	TocanLaPuerta bool

	// --- La factura de Ventra como segunda fuente (issue 20, Fase A) --------
	//
	// Fuente: `SYNC_FUENTE` = `pedido` | `factura` | `ambas`. POR DEFECTO `pedido`: desplegar
	// esto no cambia NADA hasta que alguien escriba otra cosa. `ambas` es la convivencia
	// mientras dura el corte; `factura` es el espejo ya sin PEDIDO. El corte NO es parte de
	// esto: ni apaga el webhook de PEDIDO ni la cola, ni quita nada.
	Fuente string
	// Ventra: lo mismo que lee la API (`WAREHOUSE_API_URL`, `WAREHOUSE_API_TOKEN`,
	// `WAREHOUSE_TIMEOUT_MS`, `VENTRA_BASES`). Hacen falta SÓLO si la fuente incluye la factura.
	VentraURL   string
	VentraToken string
	VentraPlazo time.Duration
	VentraBases map[string]string
}

// LeePedido: ¿el espejo trae los pedidos de PEDIDO?
func (o Opciones) LeePedido() bool { return o.Fuente != FuenteDeFactura }

// LeeFactura: ¿el espejo trae las facturas con domicilio de Ventra?
func (o Opciones) LeeFactura() bool { return o.Fuente == FuenteDeFactura || o.Fuente == FuenteAmbas }

// PollConAvisos es cada cuánto da la vuelta el ciclo CUANDO a alguien le avisan.
//
// TRES HORAS — ocho vueltas al día. Jose, 26/09/2026: «el espejo sube el tiempo de la
// comprobación, 15 y 30 es muy poco tiempo, ponlo más alto, cada 3 o cada 5 horas; cada 3 lo
// veo, serían 8 veces en el día para comprobar si todo está correcto en el espejo».
//
// POR QUÉ SE PUEDE: el ciclo ya no es quien se entera de las cosas. Eso lo hace el aviso
// —por la cola o por el webhook—, que entra EN EL ACTO cuando PEDIDO suelta. Al ciclo le
// queda comprobar que nada se quedó por el camino: Redis caído, un aviso que se rindió a los
// tres intentos, o alguien corrigiendo la base por SQL sin tocar `updatedAt`.
//
// Y ESTE FICHERO YA SE EQUIVOCÓ UNA VEZ EN LO MISMO: decía «QUINCE Y NO TREINTA, es el
// tiempo que alguien tarda en llamar a la oficina preguntando por un pedido que no ve». Ese
// razonamiento era el del mundo anterior, cuando el ciclo ERA el que traía los cambios y
// quince minutos era lo que se tardaba en enterarse. Con avisos, quien pregunta por un pedido
// que no ve lo ve aparecer en segundos, y las otras 95 vueltas del día no encontraban nada:
// 96 barridos diarios de las ocho sucursales por la conexión de allá para no traer nada.
//
// LO QUE CUESTA, dicho claro: si el aviso se pierde Y el webhook se rinde, ese pedido puede
// tardar hasta tres horas en aparecer. Es el precio, y es el que Jose ha elegido sabiendo lo
// que hay. Lo que NO se pierde es nada: el ciclo lo encuentra igual, sólo más tarde.
const PollConAvisos = 3 * time.Hour

// BarridoConAvisos es cada cuánto se estira el histórico CUANDO a alguien le avisan.
//
// UNA VEZ AL DÍA, y antes era en cada ciclo. Con `HistoricoPorCiclo` a 30 días y
// `HistoricoDias` a 60, eso son **dos barridos para dar la vuelta entera**, o sea que el
// histórico se repasa completo cada dos días — que es lo que debe hacer una red de
// seguridad, no un trabajo continuo.
//
// LO QUE HABÍA: el barrido corría en cada ciclo y daba la vuelta al año cada dos días. Con
// el webhook trayendo los cambios en el acto —238 avisos el primer día—, eso era releer el
// año entero para no encontrar nada.
//
// ESTO SIGUE SIENDO UN PARCHE Y CONVIENE QUE ESTÉ ESCRITO: el barrido **trae para
// comparar**, que es justo lo que Jose no quiere. Lo que lo arregla de verdad es comparar
// sin traer, y para eso hacen falta dos rutas que PEDIDO no tiene todavía: un resumen por
// día (cuántos pedidos y cuál fue el último cambio) y la lista pelada de ids de un día.
// Con eso se comparan 60 filas en vez de bajarse 60 días. Pedidas a su sesión el
// 26/09/2026; cuando existan, esto se queda sólo como red de última hora.
const BarridoConAvisos = 24 * time.Hour

// HayRedis: si se puede hablar con la cola. No es lo mismo que leerla — ver EscuchaLosAvisos.
func (o Opciones) HayRedis() bool {
	return o.RedisDireccion != "" || len(o.RedisCentinelas) > 0
}

// EscuchaLosAvisos: ¿se va a leer la cola de avisos?
//
// Hacen falta LAS DOS COSAS: que haya Redis y que no se haya apagado a mano. El interruptor
// es lo que permite apagar la cola el día que el webhook quede como puerta buena, sin tener
// que quitarle el Redis al servicio.
func (o Opciones) EscuchaLosAvisos() bool {
	return o.HayRedis() && o.EscuchaElStream
}

// LeAvisan: ¿se entera alguien de los cambios SIN el ciclo?
//
// ES LA PREGUNTA QUE DECIDE EL RITMO, y son DOS puertas, no una. Estaba escrita mirando sólo
// la cola, y eso era una trampa puesta justo en el camino que íbamos a andar: **apagar la
// cola con el webhook funcionando habría devuelto el ciclo a UN MINUTO**, o sea 1.440 barridos
// al día de las ocho sucursales por la conexión de allá, en el momento exacto en que menos
// falta hacían. Sin un solo error, y nadie mirando el ritmo de una tarea de fondo.
func (o Opciones) LeAvisan() bool {
	return o.EscuchaLosAvisos() || o.TocanLaPuerta
}

// RitmoDelBarrido es cada cuánto se estira el histórico, ya decidido.
//
// Mismo criterio que [Opciones.RitmoDelCiclo] y por la misma razón: si a alguien le avisan,
// el barrido deja de ser quien se entera y pasa a ser quien comprueba. Si NO avisa nadie,
// vuelve a ser lo único que caza lo que el `since` se pierde y tiene que ir a su ritmo de
// siempre.
func (o Opciones) RitmoDelBarrido() time.Duration {
	if !o.LeAvisan() {
		return o.BarridoCada
	}
	return BarridoConAvisos
}

// RitmoDelCiclo es cada cuánto toca dar la vuelta, ya decidido.
//
// Si el entorno puso `SYNC_POLL_MS` a mano, manda ése: alguien que lo escribe sabe lo que
// quiere y no se le discute. Y si NADIE avisa, el ciclo vuelve a ser lo único que trae los
// cambios y tiene que ir deprisa: dejarlo en tres horas sería tener el reparto tres horas por
// detrás de PEDIDO sin que nada lo diga.
func (o Opciones) RitmoDelCiclo(loPusoElEntorno bool) time.Duration {
	// LA FACTURA NO TIENE AVISOS: Ventra no avisa de nada, así que el ciclo es lo ÚNICO que la
	// trae y no puede ir a tres horas. Lo de PEDIDO, en cambio, conserva su ritmo propio
	// (`RitmoDePedido`) aunque el ciclo gire más deprisa por la factura.
	if o.LeeFactura() {
		return o.Poll
	}
	return o.RitmoDePedido(loPusoElEntorno)
}

// RitmoDePedido es cada cuánto toca el trabajo de PEDIDO (incremental, recién cotizados,
// repaso y barrido): el de siempre, haya o no factura. Con `SYNC_FUENTE=ambas` el ciclo gira cada
// minuto por la factura y este ritmo evita que PEDIDO se lleve por eso 1.440 repasos al día.
func (o Opciones) RitmoDePedido(loPusoElEntorno bool) time.Duration {
	if loPusoElEntorno || !o.LeAvisan() {
		return o.Poll
	}
	return PollConAvisos
}

// PorDefecto son los valores con los que arranca si el entorno no dice otra cosa. Son los
// mismos números que llevaba el espejo de Node, y están medidos contra los datos de verdad.
func PorDefecto() Opciones {
	return Opciones{
		PedidoURL:         "http://localhost:8400",
		DeliveryURL:       "http://localhost:3002",
		Poll:              time.Minute,
		TramoDias:         3,
		HistoricoDias:     60,
		HistoricoPorCiclo: 30,
		RepasoDias:        3,
		BarridoCada:       10 * time.Minute,
		SoloRepartibles:   true,
		CotizadosMin:      30,
		Lote:              200,
		PaginaClientes:    1000,
		Stream:            StreamPorDefecto,
		Fuente:            FuenteDePedido,
		// Un barrido de 60 días de una sucursal grande son miles de facturas por la VPN: el
		// plazo de la API (30 s) se queda corto. Se cambia con `WAREHOUSE_TIMEOUT_MS`.
		VentraPlazo: 120 * time.Second,
		// SE LEE LA COLA SALVO QUE SE DIGA LO CONTRARIO: quien no toque nada sigue como
		// estaba. Apagarla es una decisión que se escribe, no un olvido.
		EscuchaElStream: true,
	}
}

// Cargar lee el entorno. `entorno` se pasa como función para que las pruebas no tengan que
// ensuciar el del proceso.
//
// Sólo la clave es obligatoria: sin ella no se puede ni preguntar ni escribir, y el proceso
// se pasaría el día dando vueltas contra un 401 que nadie mira.
func Cargar(entorno func(string) string) (Opciones, error) {
	o := PorDefecto()

	o.PedidoURL = urlOTal(entorno("PEDIDO_API_URL"), o.PedidoURL)
	o.DeliveryURL = urlOTal(entorno("DELIVERY_URL"), o.DeliveryURL)
	o.Clave = strings.TrimSpace(entorno("SERVICE_API_KEY"))
	o.SucursalCodigo = strings.TrimSpace(entorno("SUCURSAL_CODIGO"))

	var errs []string
	entero := func(nombre string, destino *int) {
		crudo := strings.TrimSpace(entorno(nombre))
		if crudo == "" {
			return
		}
		n, err := strconv.Atoi(crudo)
		if err != nil || n <= 0 {
			errs = append(errs, fmt.Sprintf("%s vale %q: hace falta un número entero mayor que cero", nombre, crudo))
			return
		}
		*destino = n
	}
	milis := func(nombre string, destino *time.Duration) {
		crudo := strings.TrimSpace(entorno(nombre))
		if crudo == "" {
			return
		}
		n, err := strconv.Atoi(crudo)
		if err != nil || n <= 0 {
			errs = append(errs, fmt.Sprintf("%s vale %q: hace falta un número de milisegundos mayor que cero", nombre, crudo))
			return
		}
		*destino = time.Duration(n) * time.Millisecond
	}

	// SE APUNTA SI LO PUSO EL ENTORNO. Sin esto no hay forma de distinguir «un minuto
	// porque nadie dijo nada» de «un minuto porque alguien lo escribió», y el ritmo
	// automático pisaría una decisión tomada a mano.
	o.PollDelEntorno = strings.TrimSpace(entorno("SYNC_POLL_MS")) != ""
	milis("SYNC_POLL_MS", &o.Poll)

	// EL INTERRUPTOR DE LA COLA. `ESPEJO_ESCUCHA_AVISOS=false` la apaga dejando el Redis
	// puesto — que es lo que hace falta el día de la mudanza al webhook, y en el orden
	// acordado: la cola se apaga SÓLO cuando se ha visto entrar una tanda por HTTP.
	//
	// SÓLO `false` Y `0` APAGAN. Cualquier otra cosa —vacía, `si`, una errata— deja la cola
	// encendida, que es el lado seguro: una variable mal escrita no puede dejar al reparto
	// sin enterarse de nada.
	if v := strings.ToLower(strings.TrimSpace(entorno("ESPEJO_ESCUCHA_AVISOS"))); v == "false" || v == "0" {
		o.EscuchaElStream = false
	}

	// ¿LE TOCAN LA PUERTA? Se deduce de la pareja del webhook, la MISMA que lee la API
	// (`PEDIDO_WEBHOOK_KEY` / `PEDIDO_WEBHOOK_SECRET`). El espejo no recibe ese POST, pero le
	// cambia el ritmo: ver `LeAvisan`. Hacen falta las dos, porque con una sola la API
	// contesta 503 y no entra ni un aviso.
	o.TocanLaPuerta = strings.TrimSpace(entorno("PEDIDO_WEBHOOK_KEY")) != "" &&
		strings.TrimSpace(entorno("PEDIDO_WEBHOOK_SECRET")) != ""

	// EL CANAL DE AVISOS. Los nombres son los del Redis de la casa: un solo motor, con
	// centinela (`procovar-sentinel`), y cada aplicación con su prefijo y sus bases.
	// `REDIS_URL` ES LA MISMA VARIABLE QUE USA PEDIDO, y se lee la primera a propósito.
	//
	// Los dos lados tienen que hablar con EL MISMO Redis o cada uno escribe en su cola y
	// no llega nunca nada — sin un solo error, que es el fallo que no se ve. Compartir el
	// nombre de la variable es lo que hace que copiarla de un servicio a otro no admita
	// equivocación.
	//
	// Formato: `redis://[:clave@]maquina:puerto[/base]`.
	if v := strings.TrimSpace(entorno("REDIS_URL")); v != "" {
		if u, err := url.Parse(v); err == nil {
			o.RedisDireccion = u.Host
			if pw, hay := u.User.Password(); hay {
				o.RedisClave = pw
			}
			if b := strings.TrimPrefix(u.Path, "/"); b != "" {
				if n, err := strconv.Atoi(b); err == nil {
					o.RedisBase = n
				}
			}
		}
	}
	if v := strings.TrimSpace(entorno("REDIS_DIRECCION")); v != "" {
		o.RedisDireccion = v
	}
	if v := strings.TrimSpace(entorno("REDIS_MAESTRO")); v != "" {
		o.RedisMaestro = v
	}
	if v := strings.TrimSpace(entorno("REDIS_CLAVE")); v != "" {
		o.RedisClave = v
	}
	// EL NOMBRE DEL STREAM TIENE QUE SER EL MISMO EN LOS DOS LADOS o cada uno habla solo:
	// PEDIDO escribiría en uno y el reparto leería de otro, sin un solo error y sin que
	// llegue nunca nada. Por eso el valor por defecto está escrito en las dos casas.
	if v := strings.TrimSpace(entorno("DELIVERY_STREAM")); v != "" {
		o.Stream = v
	}
	if v := strings.TrimSpace(entorno("REDIS_CENTINELAS")); v != "" {
		o.RedisCentinelas = nil
		for _, parte := range strings.Split(v, ",") {
			if p := strings.TrimSpace(parte); p != "" {
				o.RedisCentinelas = append(o.RedisCentinelas, p)
			}
		}
	}
	if v := strings.TrimSpace(entorno("REDIS_BASE")); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			o.RedisBase = n
		}
	}
	// LA FUENTE. Un valor que no se entiende es un ERROR y no «pedido»: `SYNC_FUENTE=facturas`
	// (con ese plural) leído como el valor por defecto dejaría al espejo trayendo PEDIDO cuando
	// alguien cree que ya trae las facturas, sin un solo aviso.
	switch f := strings.ToLower(strings.TrimSpace(entorno("SYNC_FUENTE"))); f {
	case "":
	case FuenteDePedido, FuenteDeFactura, FuenteAmbas:
		o.Fuente = f
	default:
		errs = append(errs, fmt.Sprintf("SYNC_FUENTE vale %q: tiene que ser pedido, factura o ambas", f))
	}
	o.VentraURL = urlOTal(entorno("WAREHOUSE_API_URL"), "")
	o.VentraToken = strings.TrimSpace(entorno("WAREHOUSE_API_TOKEN"))
	milis("WAREHOUSE_TIMEOUT_MS", &o.VentraPlazo)
	bases, errBases := paresDeBases(entorno("VENTRA_BASES"))
	if errBases != nil {
		errs = append(errs, errBases.Error())
	}
	o.VentraBases = bases
	if o.LeeFactura() {
		if o.VentraURL == "" || o.VentraToken == "" {
			errs = append(errs, "SYNC_FUENTE="+o.Fuente+" necesita WAREHOUSE_API_URL y WAREHOUSE_API_TOKEN: "+
				"sin ellas no hay de dónde traer las facturas y el espejo parecería sano sin traer nada")
		}
		if o.VentraURL != "" && !strings.HasPrefix(o.VentraURL, "http://") && !strings.HasPrefix(o.VentraURL, "https://") {
			errs = append(errs, fmt.Sprintf("WAREHOUSE_API_URL vale %q: tiene que empezar por http:// o https://", o.VentraURL))
		}
	}

	entero("SYNC_TRAMO_DIAS", &o.TramoDias)
	entero("SYNC_HISTORICO_DIAS", &o.HistoricoDias)
	entero("SYNC_HISTORICO_POR_CICLO", &o.HistoricoPorCiclo)
	entero("SYNC_REPASO_DIAS", &o.RepasoDias)
	milis("SYNC_BARRIDO_CADA_MS", &o.BarridoCada)
	entero("SYNC_COTIZADOS_MIN", &o.CotizadosMin)
	entero("SYNC_LOTE", &o.Lote)
	entero("SYNC_PAGINA_CLIENTES", &o.PaginaClientes)

	// Los tres interruptores comparan con "1" como el espejo de Node, y no con «cualquier
	// cosa que no sea vacío»: un `SYNC_TODOS=false` heredado de otro sitio no puede
	// encender el catálogo entero por leerse como verdadero.
	o.SoloDomicilio = entorno("SYNC_SOLO_DOMICILIO") == "1"
	o.SoloCotizados = entorno("SYNC_SOLO_COTIZADOS") == "1"
	o.SoloRepartibles = entorno("SYNC_TODOS") != "1"

	if o.Clave == "" {
		errs = append(errs, "falta SERVICE_API_KEY: sin ella PEDIDO contesta 401 y el espejo no trae nada")
	}
	// Un repaso más largo que el histórico deja al barrido sin nada que recorrer, y se
	// quedaría girando en el sitio marcando la posición una y otra vez.
	if o.RepasoDias >= o.HistoricoDias {
		errs = append(errs, fmt.Sprintf(
			"SYNC_REPASO_DIAS (%d) no puede llegar tan atrás como SYNC_HISTORICO_DIAS (%d): el barrido se quedaría sin recorrido",
			o.RepasoDias, o.HistoricoDias))
	}
	if len(errs) > 0 {
		return o, fmt.Errorf("configuración no válida:\n  - %s", strings.Join(errs, "\n  - "))
	}
	return o, nil
}

// urlOTal quita la barra final. Con ella, las rutas salen con `//` en medio y hay quien
// contesta 404 a eso sin decir por qué.
func urlOTal(v, porDefecto string) string {
	v = strings.TrimRight(strings.TrimSpace(v), "/")
	if v == "" {
		return porDefecto
	}
	return v
}

// paresDeBases lee `VENTRA_BASES` (`STG=santiago,HOL=holguinmoa`) igual que `config`: las claves
// en mayúsculas, y un par mal escrito es un error y no se ignora, porque ignorarlo deja a una
// sucursal entera sin facturas.
func paresDeBases(crudo string) (map[string]string, error) {
	salida := map[string]string{}
	for _, p := range strings.Split(strings.TrimSpace(crudo), ",") {
		if p = strings.TrimSpace(p); p == "" {
			continue
		}
		clave, valor, hay := strings.Cut(p, "=")
		clave, valor = strings.TrimSpace(clave), strings.TrimSpace(valor)
		if !hay || clave == "" || valor == "" {
			return nil, fmt.Errorf("VENTRA_BASES tiene %q, que no es un par CLAVE=valor: se escribe como STG=santiago,HOL=holguinmoa", p)
		}
		salida[strings.ToUpper(clave)] = valor
	}
	return salida, nil
}
