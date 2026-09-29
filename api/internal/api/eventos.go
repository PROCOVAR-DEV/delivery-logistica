// LOS EVENTOS EN VIVO  (GET /api/eventos) — SSE.
//
// Para qué sirve: que la pantalla del logístico se entere de que algo cambió sin estar
// preguntando cada pocos segundos. El aviso dice QUÉ cambió —`pedidos`, `catalogo`,
// `rutas` o `clientes`— y no «algo»: invalidarlo todo en cada cambio significa volver a
// bajar el catálogo entero cada vez que alguien cotiza un domicilio, por la conexión de
// allá (`../docs/reglas-negocio.md` §14).
//
// # El bus va EN MEMORIA DEL PROCESO, no en Redis
//
// En delivery esto se publicaba en Redis y `/api/eventos` repartía lo que llegaba por el
// canal. Aquí el bus es del proceso y se explica solo: quien avisa y quien reparte son el
// mismo servicio —los cambios los escriben estos mismos manejadores—, así que Redis sólo
// añadiría una pieza más que puede estar caída para llevar un mensaje de una gorutina a
// otra. Si algún día la API corre en dos réplicas hay que volver a un bus de verdad: lo
// único que cambia es `Difusor`, porque el manejador no sabe de dónde le llegan los
// cambios. Queda dicho aquí para que ese día se vea.
//
// # Lo que NO se puede tocar de este fichero sin romper algo que ya costó una vuelta
//
//  1. **El latido.** Una conexión callada la corta el proxy de delante al minuto o dos, y
//     desde el navegador eso se ve como «los avisos dejaron de llegar» sin ningún error.
//     Y desde el 29/09/2026 va como EVENTO CON NOMBRE (`event: latido`, con su `data:`) y
//     no como comentario: ver `NombreDelLatido`, que explica por qué las dos cosas —el
//     nombre y el `data:`— son obligatorias para que la web lo vea.
//  2. **`X-Accel-Buffering: no`.** Sin esa cabecera, nginx guarda los eventos en su propio
//     colchón y los suelta en bloque: la pantalla se entera de todo cuarenta segundos
//     tarde, o cuando se cierra la conexión.
//  3. **NUNCA `Connection: keep-alive`.** HTTP/2 y HTTP/3 lo prohíben, y con Cloudflare
//     por delante da `ERR_QUIC_PROTOCOL_ERROR`. No se pone: en HTTP/1.1 ya es lo implícito.
//  4. **El plazo de escritura.** El servidor va con `WriteTimeout` (30 s por defecto); sin
//     renovarlo en cada escritura, TODA conexión de eventos se muere a los treinta
//     segundos, pase lo que pase.
//  5. **El apagado.** Ver `registrarApagado`: una conexión abierta para siempre deja el
//     `Shutdown` esperándola hasta que se le acaba el plazo.
//  6. **El despertador de cada pendiente** (`despertarEn`). Lo que el freno retiene NO puede
//     depender del latido para salir: con el latido cada 20 s y el freno de 15, un pendiente
//     salía «15 redondeado al alza a múltiplo de 20» — medido en producción el 29/09/2026,
//     hasta 26,68 s. Quitarlo no rompe ninguna pantalla y no falla nada: sólo hace que lo
//     frenado tarde casi el doble de lo que dice `FrenoAvisos`.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"sync"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/httpx"
)

// Los cuatro tipos de cambio. Son los del contrato y los conoce la pantalla: uno nuevo que
// ella no espere se recibe y se ignora, así que añadir aquí no rompe nada, pero renombrar
// sí.
const (
	CambioPedidos  = "pedidos"
	CambioCatalogo = "catalogo"
	CambioRutas    = "rutas"
	CambioClientes = "clientes"
	// EL TABLERO. Es el que más falta hacía y el que no estaba: es la pantalla que dos
	// personas miran a la vez —una arma zonas en el teléfono y otra las ve desde el
	// navegador— y la única donde el trabajo de uno aparece encima del del otro.
	CambioTablero = "tablero"
)

// FrenoAvisos: cuánto espera un aviso DE LOS FRENADOS. Quince segundos.
//
// POR QUÉ EXISTE: el espejo importa por lotes de doscientos y avisaba por cada lote —
// veinte avisos seguidos y la pantalla recargándose veinte veces. Y en el aparato es peor
// que el parpadeo: **cada aviso dispara un ciclo de sincronización entero**, o sea veinte
// ciclos contra la conexión de allá.
//
// ## Y POR ESO HAY FLANCO DE BAJADA — 17/09/2026
//
// «Lo que pasa en ese rato viaja en el siguiente aviso» es cierto para el espejo, que
// siempre tiene un lote detrás. Lo que llega dentro del freno **se anota como pendiente** y
// sale solo al vencer (`SoltarPendientes`), así que el último cambio siempre llega.
//
// ## EL NÚMERO QUE LA GENTE SUFRE ERA OTRO: 15 REDONDEADO AL ALZA A MÚLTIPLO DE 20
//
// Queda escrito aquí, donde se lee la constante y donde alguien se va a creer el quince.
// Hasta el 29/09/2026 lo retenido **no salía solo**: lo soltaba el latido de cada conexión
// abierta (`SoltarPendientes` desde el `case <-tic.C`), que corre cada `latidoSSE` = 20 s. O
// sea que un pendiente no salía a los 15 s suyos, salía **en el siguiente tic de 20 s**.
//
// Diez muestras de producción de esa noche, comparando la hora del servidor que viaja dentro
// del aviso con la hora en que llega al navegador:
//
//   - sin freno: 70 · 67 · 95 · 69 · 70 ms;
//   - con freno: 6,77 · 17,89 · 20,41 · 20,76 · **26,68** s.
//
// Cuatro de cinco por encima de 17 s y el peor **casi el doble del freno nominal**. Las
// horas a las que salían los pendientes lo delataban —21:02:40.300 · 21:03:00.298 ·
// 21:03:20.319, veinte segundos clavados—, y el de 26,68 s se comió un tic entero de más: el
// cambio era de 21:02:13.622, el freno vencía sobre 21:02:25.4 y no salió hasta 21:02:40.3.
//
// **Ya no.** Cada pendiente se despierta solo cuando vence SU freno (ver `despertarEn`), así
// que el número de aquí es el de verdad: quince segundos, no «quince redondeados a veinte».
// El latido sigue llamando a `SoltarPendientes` como red de seguridad, no como mecanismo.
const FrenoAvisos = 15 * time.Second

// tiposFrenados: LOS QUE ESPERAN. Todo lo que no esté nombrado aquí sale AL MOMENTO.
//
// # EL CASO QUE LO CAMBIÓ — 29/09/2026, medido en la ventana de Jose
//
// Jose, con el navegador en una mano y el teléfono en la otra, mueve dos tarjetas del
// tablero seguidas. Lo que salió por el cable:
//
//	20:59:22.622  mueve la primera tarjeta  ->  aviso 20:59:22.776    154 ms
//	20:59:24.052  mueve la segunda          ->  aviso 20:59:40.441    16 SEGUNDOS
//
// La primera al instante y la segunda dieciséis segundos después: los quince del freno más
// lo que tardó el latido en soltar el pendiente. Jose: «pero debe ser en tiempo real deben
// ocurrir por q se demoran 15segundos en ocurrir».
//
// # LA LÍNEA ES DE DÓNDE VIENE, ESCRITA POR TIPO
//
// El primer plan fue separar por origen —sesión de persona contra proceso de máquina, un
// campo que llevara cada aviso— y lo cerró Jose, que tenía razón y es más simple:
//
//	«pues cierralo para ahi nada mas para pedido y deja todo lo demas listo al momento,
//	 pedidos y clientes si pero lo otro no q se utiliza en reparto dejalo al momento»
//	«lo q viene al espejo q dispara tantas cosas ese si ponle el freno y a lo otro
//	 dejamelo listo»
//
// La regla en una frase: **lo que entra por el espejo y el webhook de PEDIDO se frena; lo
// que se usa para trabajar en el reparto sale al momento.** `canal` está frenado por eso y
// no por gusto de nadie —lo decidió Jose con esa segunda frase—: queda dicho para que dentro
// de dos meses nadie lo saque de aquí creyendo que se coló.
//
// # Y LA AVALANCHA NO ES TEÓRICA: PASÓ HOY
//
// Hasta la tarde del 29/09/2026 PEDIDO nos devolvía **2.000 pedidos por cada aviso de uno**
// —fallo suyo, arreglado y desplegado a las 20:02—. Con eso, una sola importación son
// muchos lotes seguidos, un aviso por lote y **un ciclo de sincronización entero por aviso**
// en cada aparato, contra la conexión de allá.
//
// Sí, `pedidos` también cambia por un gesto de persona (`PATCH /api/orders/{id}`), así que
// separar por tipo no es perfecto. Se acepta a propósito: por esa misma puerta entra el lote
// del espejo (`cotizacion.go`, doscientos pedidos por vuelta) y el webhook de PEDIDO. Un
// pedido corregido a mano que tarde medio minuto en verse es barato; veinte ciclos seguidos
// contra la conexión de Cuba, no.
//
// # LA LISTA ES DE LOS FRENADOS, NO DE LOS LIBRES, Y ESO ES LA MITAD DEL DISEÑO
//
// Escrita al revés —«éstos no se frenan»— un tipo nuevo que alguien añada mañana entraría
// **frenado sin querer**, su pantalla se quedaría hasta medio minuto vieja, y eso no falla,
// no sale en ningún registro y no lo nota nadie: el modo de fallo de esta casa. Así:
// nombrarse aquí es un acto, y el valor del mapa obliga a escribir por qué.
//
// Lo fija `TestSoloEstosTiposSeFrenan`, con los tres nombres a mano.
var tiposFrenados = map[string]string{
	CambioPedidos: "la manguera de PEDIDO: el lote del espejo son doscientos pedidos por " +
		"vuelta y avisa por cada uno, y el webhook manda un aviso por pedido movido",
	CambioClientes: "misma manguera: entra por el webhook de PEDIDO, un aviso por cliente " +
		"corregido, y una importación los corrige a montones",
	CambioCanal: "también viene del espejo: es la propia cola de PEDIDO —la entrada del " +
		"webhook y el drenaje del buzón—, o sea el tipo con más volumen de todos. Lo " +
		"decidió Jose el 29/09/2026 («lo q viene al espejo q dispara tantas cosas ese si " +
		"ponle el freno»), no se coló aquí. Y de paso su pantalla es de administración: " +
		"nadie arma una ruta mirándola",
}

// frenoDe: cuánto espera un aviso de este tipo. Cero para todo lo que no esté nombrado en
// [tiposFrenados], que es la mayoría y es lo que se usa para trabajar en el reparto.
func (d *Difusor) frenoDe(tipo string) time.Duration {
	if _, frenado := tiposFrenados[tipo]; !frenado {
		return 0
	}
	return d.freno
}

// NombreDelLatido es cómo se llama el evento del latido POR EL CABLE.
//
// # POR QUÉ ES UN EVENTO CON NOMBRE Y YA NO UN COMENTARIO — 29/09/2026
//
// Era `: latido`, un comentario SSE. Eso mantiene viva la conexión —el proxy ve tráfico— y
// a la APK le vale, porque lee el socket en crudo y marca el pulso con CUALQUIER byte
// (`app/lib/nucleo/red/eventos_io.dart`). **Pero `EventSource` descarta los comentarios por
// especificación y no hay forma de pedírselos**, así que en el navegador el latido era
// invisible: existía, pasaba por el socket y no lo veía nadie.
//
// Eso dejó de ser gratis en cuanto «el canal está vivo» pasó a decidirse por cualquier
// señal del canal —latido incluido— y con ello el reloj dejó de pedir nada. La APK late
// cada veinte segundos y se calla; **la web sólo tenía el `listo` de cada reconexión**, y
// el proxy corta cada 300 s contra un plazo de seis minutos: sesenta segundos de margen.
// Con la conexión de allá ese margen se rompe — medido, una reconexión de 61 s son nueve
// vueltas del reloj en una jornada en vez de cero.
//
// Con nombre, la web lo escucha igual que escucha `listo` y `cambio`, y el reloj se calla
// del todo.
//
// # Y LLEVA `data:` AUNQUE NO TENGA NADA QUE DECIR
//
// **Un evento sin `data:` el navegador no lo entrega**: el analizador de SSE descarta la
// trama cuando el búfer de datos está vacío. Un `event: latido` a secas sería exactamente
// el mismo agujero con otra forma — invisible en la web, y esta vez sin que se note que lo
// es. Por eso va `data: {}`, un objeto vacío: el latido no lleva información, y si algún
// día la lleva cabe ahí sin cambiar la forma.
//
// # LO QUE NO CAMBIA
//
//   - Sigue siendo tráfico por el socket cada veinte segundos, que es para lo que estaba:
//     lo que impide que un proxy corte una conexión callada. Son más bytes que un
//     comentario y siguen siendo menos de cuarenta.
//   - La APK no se entera de nada: su analizador ignora los eventos con un nombre que no
//     conoce (`default: break`) y el pulso ya lo marcaba con cualquier byte.
//
// Es el mismo nombre que espera `app/lib/nucleo/red/eventos_web.dart`. Son dos ficheros que
// no se ven, así que **renombrar un lado sin el otro deja a la web sin latido y sin que
// falle nada**, igual que pasa con los tipos de `Cambio…`.
const NombreDelLatido = "latido"

// bloqueDelLatido es el latido tal cual sale por el cable, armado UNA vez.
var bloqueDelLatido = "event: " + NombreDelLatido + "\ndata: {}\n\n"

// El latido, y el plazo de cada escritura. Son variables y no constantes para que las
// pruebas no tarden veinte segundos en comprobar que el latido sale.
var (
	latidoSSE   = 20 * time.Second
	plazoEnvio  = 10 * time.Second
	colaAbonado = 16 // avisos en vuelo que se le guardan a un abonado lento
)

// Cambio es lo que se publica. `Detalle` es libre —`{"pedidos": 42}`, `{"productos": 300}`—
// y lo pone quien avisa.
//
// # `Sucursal`: DE DÓNDE ES el cambio — 29/09/2026
//
// Vacío = **de todas**, y el aviso le llega a todo el mundo. Un uuid = sólo a quien mira
// esa sucursal. Jose: «el aviso por sucursales, ese evento debe de salir de su sucursal,
// no puede dar una bajada a las otras 7».
//
// **VACÍO NO ES «DE NINGUNA»**, y ésa es la única forma de equivocarse aquí que no falla,
// no sale en ningún registro y deja la pantalla vieja: el catálogo, los ajustes, la lista
// de sucursales y el canal con PEDIDO no son de nadie en concreto y TIENEN que seguir
// llegando a las ocho. Por eso el campo es un texto y el vacío se lee «no lo acota», no
// un puntero que alguien pueda comparar por igualdad con el de otro.
//
// Es un campo suyo y no una entrada del `Detalle` porque decide DOS cosas que el detalle
// no puede: a quién se le reparte (`repartir`) y con quién comparte freno (`clave`).
type Cambio struct {
	Tipo    string
	Cuando  time.Time
	Detalle map[string]any
	// Sucursal: el uuid de la sucursal del reparto a la que pertenece lo que cambió.
	// Vacío = de todas.
	Sucursal string
}

// clave: con quién comparte freno este cambio.
//
// **EL FRENO ES POR TIPO *Y* POR SUCURSAL, y esto no es un adorno.** Con el freno sólo por
// tipo, mover una tarjeta en Camagüey y otra en Holguín dentro de los mismos quince
// segundos dejaba UN pendiente —el último, porque `pendiente[tipo]` se pisa— y el otro no
// salía nunca. O sea: arreglando el ruido de las otras siete se habría abierto justo el
// fallo que este trabajo venía a evitar, un aviso que no le llega a quien sí lo
// necesitaba. Lo ata `TestElFrenoNoSeCruzaEntreSucursales`.
func clave(tipo, sucursal string) string { return tipo + "\x00" + sucursal }

// datos arma el `data:` del evento: `{tipo, ...detalle, cuando}`, tal cual el contrato.
//
// `tipo` y `cuando` se escriben DESPUÉS del detalle a propósito: si quien avisa mete un
// `tipo` en el detalle, el bueno es el del aviso y no el suyo. Un detalle que pueda pisar
// el tipo es un detalle que puede hacer que la pantalla invalide otra cosa.
func (c Cambio) datos() []byte {
	m := make(map[string]any, len(c.Detalle)+2)
	for k, v := range c.Detalle {
		m[k] = v
	}
	m["tipo"] = c.Tipo
	// LA SUCURSAL SÓLO SI LA HAY. Un `"sucursal": ""` en el cuerpo sería un texto que la
	// pantalla compararía con el suyo y nunca casaría: el aviso de todos se convertiría en
	// el aviso de nadie. Sin la clave, el cliente lee «no dice de dónde es» y lo deja
	// pasar, que es lo correcto.
	if c.Sucursal != "" {
		m["sucursal"] = c.Sucursal
	}
	// Con milisegundos y en UTC, que es lo que lee la pantalla (`2026-09-14T10:00:00.000Z`).
	m["cuando"] = c.Cuando.UTC().Format("2006-01-02T15:04:05.000Z07:00")
	b, err := json.Marshal(m)
	if err != nil {
		// Un detalle que no se puede codificar —una función, un canal— no puede tumbar el
		// flujo de todos los abonados. Se manda el aviso pelado: la pantalla refresca
		// igual, que es para lo único que sirve.
		return []byte(`{"tipo":"` + c.Tipo + `"}`)
	}
	return b
}

// Difusor reparte los cambios entre las conexiones abiertas.
//
// Hace tres cosas y las tres tienen que pasar sin bloquear a quien avisa: un aviso es un
// aviso, no el trabajo. Una importación de mil pedidos no puede quedarse esperando a que
// un navegador con la pestaña en segundo plano lea su canal.
type Difusor struct {
	mu sync.Mutex
	// abonados: el canal de cada conexión abierta -> LA SUCURSAL QUE MIRA, o vacío si
	// las ve todas (DESARROLLADOR y SUPER ADMIN sin sucursal elegida). Es lo que permite
	// que el reparto se haga aquí y no en el aparato: un aviso de Camagüey ni siquiera
	// sale por el cable de los otros siete. Ver `repartir`.
	abonados map[chan Cambio]string
	ultimo   map[string]time.Time // el freno, por tipo Y sucursal (ver `clave`)
	// pendiente: lo que llegó DENTRO del freno y todavía no ha salido. Es el flanco de
	// bajada; sin esto, lo que pasa en esos quince segundos no se dice nunca. La clave es
	// la misma que la del freno: tipo Y sucursal.
	pendiente map[string]Cambio
	// temporizadores: el despertador de cada pendiente, uno por clave y SÓLO mientras hay
	// algo que soltar. Ver `despertarEn`.
	temporizadores map[string]*time.Timer
	cerrado        bool
	// enganchados: los servidores HTTP a los que ya se les colgó el cierre. Ver
	// `registrarApagado`.
	enganchados map[*http.Server]struct{}

	freno time.Duration
	ahora func() time.Time // el reloj, por fuera, para poder probar el freno sin esperar
	// alVencer arma un despertador. Es `time.AfterFunc` y es un campo por lo mismo que
	// `ahora`: una prueba de reloj falso lo pone a nil y no deja temporizadores de verdad
	// colgando del proceso de pruebas.
	alVencer func(time.Duration, func()) *time.Timer
}

func NuevoDifusor() *Difusor {
	return &Difusor{
		abonados:       map[chan Cambio]string{},
		ultimo:         map[string]time.Time{},
		pendiente:      map[string]Cambio{},
		temporizadores: map[string]*time.Timer{},
		enganchados:    map[*http.Server]struct{}{},
		freno:          FrenoAvisos,
		ahora:          time.Now,
		alVencer:       time.AfterFunc,
	}
}

// busEventos es el bus del proceso. Vive en el paquete y no en el `Servidor` porque es de
// TODO el proceso —un solo servicio, un solo bus—, igual que lo era el canal de Redis.
var busEventos = NuevoDifusor()

// El armador de rutas dejó preparado un gancho vacío (`avisarCambioDeRutas`, en `rutas.go`)
// para cuando hubiera un bus. Ya lo hay, así que se engancha aquí —desde el fichero del
// bus— y no allí: quien escribe rutas no tiene por qué saber cómo se reparten los avisos, y
// así el día que esto vuelva a ser Redis no hay que tocar el armador.
//
// El detalle va vacío a propósito: el aviso dice QUÉ cambió, no cuánto. La pantalla vuelve a
// pedir la lista, y esa sí va acotada a su sucursal.
// ## El tablero no avisaba, y es la pantalla que más falta hacía — 17/09/2026
//
// Publicaban dos: `CambioRutas` desde el armador y `CambioPedidos` desde el lote del espejo.
// Del tablero, nada — y es justamente la pantalla que dos personas miran a la vez: una arma
// zonas en el teléfono y otra las ve desde el navegador.
//
// Lo que se notaba: una zona creada en el móvil no aparecía en la web hasta que pasaba el
// temporizador —dos minutos— o alguien refrescaba a mano. Jose, 16/09/2026: «hice un tablero
// en el móvil, moví cosas, y en la web no salió en tiempo real, ¿por qué razón si eso debe
// pasar?».
//
// ## AQUÍ HABÍA UN COMENTARIO QUE MENTÍA — corregido el 17/09/2026
//
// Decía que `CambioCatalogo` y `CambioClientes` podían quedarse sin publicar porque «ésos
// cambian cuando el espejo importa, que ya avisa por `CambioPedidos`». **Ya no es verdad**,
// y la parte de catálogo no lo fue nunca: el catálogo se toca a mano desde Productos
// (`PATCH`/`DELETE /api/products`) y se trae aparte con `POST /api/products/sync`, sin que
// eso escriba un solo pedido. Un aviso de `pedidos` no invalida el catálogo de nadie.
//
// Jose, 17/09/2026: «¿y por qué probamos con tableros solamente? Son todas, porque todos
// deben ser en tiempo real como el tablero cuando las cosas tienen conexión».
//
// Así que ahora avisan TODAS las puertas que escriben algo que una pantalla enseña:
// pedidos, catálogo, vehículos (con sus tipos), almacenes, sucursales y ajustes, cada una
// con SU tipo. El tipo importa: quien lo recibe vuelve a pedir lo suyo, y mandar
// `pedidos` por un cambio de camión es hacer que ocho navegadores se bajen la lista de
// pedidos entera por nada, con la conexión de allá.
//
// ## `CambioClientes` ESTABA DECLARADO Y SIN PUBLICAR, Y EL MOTIVO ERA FALSO — 29/09/2026
//
// Aquí decía, en negrita y para que nadie lo tocara, que «no es un olvido: en esta API NO
// HAY ninguna puerta que escriba `customers`». La hay: `POST /api/webhooks/pedido` con el
// motivo `cliente` (`webhook_de_pedido.go`, `base.GuardarCliente`), que es el aviso de que
// en PEDIDO corrigieron la coordenada de un cliente. Y es de los peores que se pueden
// perder, porque **el reparto ordena las paradas por esa coordenada**: sin enterarse, la
// ruta se arma hacia el sitio de antes, con números y todo y sin un solo error.
//
// Un comentario no falla, y éste llevaba desde el 17/09/2026 tapando el hueco que decía
// explicar. Ya lo publica `avisarCambioDeClientes` (`clientes.go`).
//
// Lo que sigue sin poder publicar es el proceso del espejo (`cmd/espejo`,
// `internal/espejo/ciclo.go`, `clientes()`), que va contra Postgres directamente y **corre
// en otro proceso** — y este bus vive en la memoria de éste (ver arriba). Desde allí no hay
// forma de publicar sin volver a un bus de verdad o sin abrirle una puerta al espejo.
//
// Se enganchan aquí, en el fichero del bus, y no en cada manejador: quien escribe una zona
// —o un camión— no tiene por qué saber cómo se reparten los avisos, y el día que esto
// vuelva a ser Redis no hay que tocar ni el tablero ni los demás.
//
// ## Y DE QUÉ SUCURSAL ES CADA UNO — 29/09/2026
//
// Jose: «el aviso por sucursales, ese evento debe de salir de su sucursal, no puede dar
// una bajada a las otras 7». Mover una tarjeta en Camagüey mandaba a los ocho navegadores
// de la oficina —más los teléfonos, por la conexión de allá— a bajarse su tablero entero,
// y siete de los ocho no tenían nada que bajar. Desde el 29/09 era peor todavía, porque
// también se refresca al reconectar el canal.
//
// El modelo es el de PEDIDO (`api/src/lib/events.ts`, `api/src/routes/events.ts`), que ya
// lo tenía resuelto: el evento lleva `sucursalId`, **nulo = global**, y el corte se hace
// en el SERVIDOR al repartir, contra la sucursal que resolvió la sesión de quien escucha.
// Se copia entero, incluido lo que más importa: lo que no dice de qué sucursal es llega a
// todos.
//
// **Qué lleva sucursal y qué no**, con el porqué de cada uno. La regla es una: el aviso se
// acota sólo cuando lo que cambió SÓLO puede ser de esa sucursal. En la duda va sin acotar,
// porque un aviso de más cuesta una petición y uno de menos deja una pantalla vieja y
// callada, que es el fallo caro de esta casa.
//
//   - `tablero`, `rutas`, `pedidos`, `almacenes` -> DE SU SUCURSAL. Las cuatro cosas
//     cuelgan de `branch_id` y sus manejadores pasan todos por `acotado()`, así que el
//     alcance de quien escribe es el techo de lo que pudo cambiar: un usuario de Camagüey
//     no puede tocar nada de Holguín, por definición.
//   - `catalogo` -> GLOBAL. `products` sí tiene `sucursal_codigo`, pero las dos puertas que
//     lo tocan son de las ocho: `POST /api/products/sync` (`espejo.go`) trae el catálogo de
//     VARIAS sucursales en una sola vuelta y avisa una sola vez, y corregir un producto es
//     **sólo del SUPER ADMIN** (`esSuperAdmin` en `productos.go`), o sea que su alcance ya
//     es «todas» y acotarlo no cambiaría nada salvo esconder por qué.
//   - `vehiculos` -> DOS GANCHOS, y aquí está la diferencia que costó la fuga hasta el
//     29/09/2026. `avisarCambioDeVehiculos` (`vehiculos.go`) va ACOTADO: `vehicles` tiene
//     `branch_id` y sus tres manejadores pasan por `acotado()`, así que dar de alta un
//     camión en Camagüey ya no manda a las otras siete a pedir `/api/vehicles` **y**
//     `/api/settings` para pintar lo mismo. `avisarCambioDeTiposDeVehiculo`
//     (`tipos_vehiculo.go`) sigue GLOBAL: `vehicle_types` **no tiene columna de sucursal
//     ninguna** (es un catálogo de toda la empresa), y acotarlo dejaría a las otras siete
//     pantallas de Vehículos sin enterarse de un tipo nuevo —y esa pantalla NO vive de la
//     base local, así que el ciclo tampoco la repinta: se queda clavada hasta salir y
//     volver a entrar. Los dos publican el MISMO tipo, porque la pantalla es la misma.
//   - `clientes` -> DE SU SUCURSAL, y desde el 29/09/2026 **sí lo publica alguien**: el
//     aviso `cliente` de `POST /api/webhooks/pedido`, que es cuando en PEDIDO corrigen la
//     coordenada de un cliente. Aquí decía que no había ninguna puerta que escribiera
//     `customers` y era falso. Por esa puerta entra el servicio, sin sucursal, así que en
//     la práctica sale global; el gancho se acota igual por si algún día lo llama otro.
//     Lo que sigue sin publicar es el proceso del espejo (`cmd/espejo`), que corre fuera.
//   - `sucursales`, `ajustes` -> GLOBAL. La lista de sucursales es de todos, y los ajustes
//     lo dicen en su propio fichero: «GLOBALES: no llevan alcance por sucursal y no es un
//     olvido». Con la moneda y la tasa se convierte TODO importe que se pinta.
//   - `ajustes` TIENE ADEMÁS UN SEGUNDO EMISOR, Y ÉSE SÍ VA ACOTADO: el refresco de tasas
//     (`avisarTasaDeSucursal`, `refresco_de_tasas.go`). La tasa es POR SUCURSAL, y la de
//     Granma no le mueve ni un importe a Camagüey. Que el mismo tipo salga unas veces
//     global y otras acotado no es una incoherencia: el tipo dice QUÉ volver a pedir, la
//     sucursal dice A QUIÉN le cambió.
//   - `canal` -> GLOBAL. Lo publican el webhook de PEDIDO, la puerta del lote
//     (`buzon_a_pedido.go`), el cierre de ruta cuando encola avisos y el drenaje del buzón.
//     Los dos primeros no tienen sesión de persona y por tanto no tienen alcance —aquí
//     `sucursalDelAlcance` devolvería vacío de todos modos—, y el cierre sí la tiene pero
//     **la pantalla del canal es de administración y mira la cola entera**: acotarla
//     dejaría a quien la vigila sin ver justo lo que va a atascarla.
//
// Lo ata `el_aviso_sale_de_su_sucursal_test.go`, que fija esta tabla: un gancho que cambie
// de lado tiene que cambiarla a mano, y entonces se lee este comentario.
func init() {
	avisarCambioDeRutas = func(ctx context.Context) {
		busEventos.AvisarDe(CambioRutas, sucursalDelAlcance(ctx), nil)
	}
	avisarCambioDelTablero = func(ctx context.Context) {
		busEventos.AvisarDe(CambioTablero, sucursalDelAlcance(ctx), nil)
	}
	avisarCambioDePedidos = func(ctx context.Context) {
		busEventos.AvisarDe(CambioPedidos, sucursalDelAlcance(ctx), nil)
	}
	avisarCambioDeAlmacenes = func(ctx context.Context) {
		busEventos.AvisarDe(CambioAlmacenes, sucursalDelAlcance(ctx), nil)
	}
	avisarCambioDeVehiculos = func(ctx context.Context) {
		busEventos.AvisarDe(CambioVehiculos, sucursalDelAlcance(ctx), nil)
	}
	avisarCambioDeClientes = func(ctx context.Context) {
		busEventos.AvisarDe(CambioClientes, sucursalDelAlcance(ctx), nil)
	}

	// LOS DE TODAS. Van por `Avisar` —sin sucursal— a propósito; el porqué de cada uno,
	// en la tabla de arriba. No se les pone `sucursalDelAlcance` aunque quien los toque
	// tenga sucursal: lo que cambian lo ven las ocho.
	avisarCambioDelCatalogo = func(_ context.Context) { busEventos.Avisar(CambioCatalogo, nil) }
	avisarCambioDeTiposDeVehiculo = func(_ context.Context) { busEventos.Avisar(CambioVehiculos, nil) }
	avisarCambioDeSucursales = func(_ context.Context) { busEventos.Avisar(CambioSucursales, nil) }
	avisarCambioDeAjustes = func(_ context.Context) { busEventos.Avisar(CambioAjustes, nil) }
	avisarCambioEnElCanal = func(_ context.Context) { busEventos.Avisar(CambioCanal, nil) }

	// LA TASA, QUE NO SALE DE NINGÚN ALCANCE. El refresco de tasas corre de fondo, sin
	// petición y sin persona, así que la sucursal viene de la fila que acaba de escribir.
	// Ver `avisarTasaDeSucursal` en `refresco_de_tasas.go`.
	avisarTasaDeSucursal = func(_ context.Context, sucursal string) {
		busEventos.AvisarDe(CambioAjustes, sucursal, nil)
	}
}

// sucursalDelAlcance: de qué sucursal es lo que acaba de cambiar.
//
// Sale del alcance de la petición que lo escribió, que es la única fuente honesta: el
// alcance lo resuelve la portería a partir de QUIÉN pide —nunca de lo que mande el
// cliente—, y acota las consultas, así que lo que un manejador pudo escribir no puede
// salirse de él. Un usuario de Camagüey no puede haber cambiado nada de Holguín.
//
// Devuelve vacío —o sea, «de todas»— en los dos casos en los que no se sabe:
//
//   - quien lo tocó ve las ocho (DESARROLLADOR, SUPER ADMIN sin sucursal elegida): pudo
//     cambiar cualquiera, así que el aviso tiene que llegarle a cualquiera;
//   - no hay alcance en el contexto (una ruta sin el middleware, un proceso de fondo, una
//     prueba): «no se sabe» **no es «de ninguna»**. Tratarlo como «de ninguna» sería el
//     aviso que no le llega a nadie, que no falla y no se ve.
func sucursalDelAlcance(ctx context.Context) string {
	a := alcance.DelContexto(ctx)
	if a == nil || a.Todas() {
		return ""
	}
	if id := a.Sucursal(); id != nil {
		return id.String()
	}
	return ""
}

// Avisar publica un cambio QUE ES DE TODAS LAS SUCURSALES. Devuelve si salió o si lo paró
// el freno; nunca bloquea y nunca entra en pánico.
//
// Es el caso seguro y por eso es el que tiene el nombre corto: un aviso de más cuesta una
// petición, y uno de menos deja una pantalla vieja sin que falle nada.
func (d *Difusor) Avisar(tipo string, detalle map[string]any) bool {
	return d.AvisarDe(tipo, "", detalle)
}

// AvisarDe publica un cambio DE UNA SUCURSAL. Con `sucursal` vacío es igual que [Avisar].
func (d *Difusor) AvisarDe(tipo, sucursal string, detalle map[string]any) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado {
		return false
	}
	ahora := d.ahora()
	c := Cambio{Tipo: tipo, Cuando: ahora, Detalle: detalle, Sucursal: sucursal}
	k := clave(tipo, sucursal)

	// EL FRENO ES DE UNOS POCOS TIPOS, Y SALE DE LA LISTA. Para todo lo demás `frenoDe`
	// devuelve cero y el aviso sale en el acto — que es lo que Jose pidió el 29/09/2026
	// después de ver su segunda tarjeta tardar dieciséis segundos. Ver `tiposFrenados`.
	if freno := d.frenoDe(tipo); freno > 0 {
		if visto, hay := d.ultimo[k]; hay && ahora.Sub(visto) < freno {
			// DENTRO DEL FRENO: no sale ahora, pero **se guarda**. Sale solo al vencer, con
			// `SoltarPendientes`. Antes se descartaba, y de doce avisos seguidos llegaba uno
			// —el primero— y once se perdían para siempre.
			//
			// Se queda el ÚLTIMO: es el que describe cómo está la cosa ahora, y quien lo
			// reciba va a pedir la lista entera de todos modos.
			d.pendiente[k] = c
			d.despertarEn(k, freno-ahora.Sub(visto))
			return false
		}
	}
	d.ultimo[k] = ahora
	delete(d.pendiente, k)
	d.olvidarDespertador(k)

	d.repartir(c)
	return true
}

// despertarEn deja programada la suelta de un pendiente. Con el candado ya cogido.
//
// # POR QUÉ HAY UN TEMPORIZADOR AQUÍ, SI ARRIBA DECÍA QUE NO HACÍA FALTA — 29/09/2026
//
// En `SoltarPendientes` ponía que colgarlo del latido bastaba, «para algo que ya tiene quien
// lo despierte cada veinte segundos». Medido en producción, no bastaba: el latido va cada
// 20 s y el freno es de 15, así que un pendiente salía **en el siguiente tic**, o sea 15
// redondeados al alza a múltiplo de 20. La peor muestra de esa noche fue de **26,68 s** —un
// tic entero de más— contra los 15 que dice la constante. El detalle, en `FrenoAvisos`.
//
// Lo que cuesta: un `time.AfterFunc` por clave CON PENDIENTE, y sólo mientras lo haya. No es
// un hilo por conexión ni un temporizador siempre vivo; en reposo no hay ninguno.
//
// # UNO POR CLAVE Y NO SE REPROGRAMA
//
// Si ya hay despertador puesto para esta clave, salta a la vez o antes que el que pondríamos
// ahora —se armó por el mismo freno y desde un `ultimo` que no se ha movido—, así que el
// pendiente que acaba de pisar al anterior sale con él. Reprogramarlo sólo lo retrasaría, y
// retrasar es justo lo que se vino a arreglar.
//
// Y no hace falta rearmarlo si salta en falso: entre que se arma y que salta, `ultimo[k]`
// sólo puede moverlo una salida de esa misma clave, y las dos —la de `AvisarDe` y la de
// `SoltarPendientes`— borran el pendiente y el despertador. O sea que cuando salta, o hay
// pendiente y el freno ya venció, o no hay nada que soltar.
func (d *Difusor) despertarEn(k string, dentroDe time.Duration) {
	if d.alVencer == nil {
		return
	}
	if _, ya := d.temporizadores[k]; ya {
		return
	}
	if dentroDe < 0 {
		dentroDe = 0
	}
	d.temporizadores[k] = d.alVencer(dentroDe, func() {
		// Se quita a sí mismo ANTES de soltar: `SoltarPendientes` coge el mismo candado.
		d.mu.Lock()
		delete(d.temporizadores, k)
		d.mu.Unlock()
		d.SoltarPendientes()
	})
}

// olvidarDespertador quita el despertador de una clave que ya no tiene nada pendiente. Con
// el candado ya cogido. Sin esto, un despertador viejo sigue en el mapa e impide poner el
// del pendiente siguiente — y ése sí volvería a esperar al latido.
func (d *Difusor) olvidarDespertador(k string) {
	if t, hay := d.temporizadores[k]; hay {
		t.Stop()
		delete(d.temporizadores, k)
	}
}

// repartir manda el cambio a los abonados A QUIEN LE TOCA. Con el candado ya cogido.
//
// # LA REGLA, y se lee en un renglón
//
// Se descarta SÓLO cuando las dos partes saben de qué sucursal hablan y no es la misma.
// Todo lo demás pasa:
//
//   - el cambio no dice de qué sucursal es (catálogo, ajustes, sucursales, canal) -> a TODOS;
//   - quien escucha ve las ocho (DESARROLLADOR, SUPER ADMIN) -> se lo lleva TODO;
//   - coinciden -> pasa.
//
// Escrito al revés —«se manda sólo si coinciden»— un aviso sin sucursal no le llegaría a
// nadie, y ése es el fallo caro: no falla, no hay error, no sale en ningún registro, y la
// pantalla se queda vieja sin que nadie sepa por qué.
//
// Y esto es además la mitad que NO se puede hacer en el aparato: saber que «cambió el
// tablero de Camagüey» ya es contar algo, así que el corte por persona va aquí, donde el
// alcance sale de quién pregunta y no de lo que mande el cliente.
func (d *Difusor) repartir(c Cambio) {
	for ch, suya := range d.abonados {
		if suya != "" && c.Sucursal != "" && suya != c.Sucursal {
			continue
		}
		select {
		case ch <- c:
		default:
			// Abonado lleno: se le pierde este aviso. Es lo correcto —el siguiente le
			// dirá lo mismo— y desde luego mejor que dejar la escritura de un pedido
			// esperando a que un navegador se despierte.
		}
	}
}

// SoltarPendientes manda lo que se quedó dentro del freno y ya venció.
//
// Lo llaman DOS, y el orden importa para entender el número:
//
//  1. **El despertador del propio pendiente** (`despertarEn`), que salta cuando vence SU
//     freno. Es el mecanismo, y es lo que hace que quince segundos sean quince.
//  2. **El latido de cada conexión abierta** (el `ticker` de `servirEventos`), cada 20 s.
//     Ya no es el mecanismo: es la red de seguridad, para un pendiente que se quedara sin
//     despertador —una prueba que puso `alVencer` a nil, un reloj falso que no avanza—.
//
// # AQUÍ PONÍA QUE EL LATIDO BASTABA, Y ERA FALSO — 29/09/2026
//
// Decía que montar un temporizador propio «sería un hilo más vivo para algo que ya tiene
// quien lo despierte cada veinte segundos». Con el latido solo, un pendiente de 15 s salía
// **en el siguiente tic de 20**: quince redondeados al alza a múltiplo de veinte. Medido esa
// noche en producción, cinco frenadas de 6,77 · 17,89 · 20,41 · 20,76 y **26,68** segundos,
// contra una constante que dice quince. Un comentario no falla, y éste tapaba once segundos.
// El detalle completo, en `FrenoAvisos`.
func (d *Difusor) SoltarPendientes() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado || len(d.pendiente) == 0 {
		return
	}
	ahora := d.ahora()
	for k, c := range d.pendiente {
		if visto, hay := d.ultimo[k]; hay && ahora.Sub(visto) < d.frenoDe(c.Tipo) {
			continue
		}
		d.ultimo[k] = ahora
		delete(d.pendiente, k)
		d.olvidarDespertador(k)
		d.repartir(c)
	}
}

// Suscribir abre un abono QUE SE LO LLEVA TODO. El tercer valor es false cuando el bus
// está cerrado —el proceso se está parando—, y entonces no hay canal que escuchar.
func (d *Difusor) Suscribir() (<-chan Cambio, func(), bool) { return d.SuscribirDe("") }

// SuscribirDe abre un abono acotado a UNA sucursal: sólo recibe lo suyo y lo que no es de
// ninguna. Con `sucursal` vacío es igual que [Suscribir] — que es lo que le toca a quien ve
// las ocho, y también el caso seguro si algún día no se puede averiguar cuál es la suya.
func (d *Difusor) SuscribirDe(sucursal string) (<-chan Cambio, func(), bool) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado {
		return nil, func() {}, false
	}
	ch := make(chan Cambio, colaAbonado)
	d.abonados[ch] = sucursal
	// El corte NO cierra el canal: sólo lo saca del reparto. Cerrarlo aquí y cerrarlo en
	// `Cerrar` es cerrarlo dos veces el día que las dos cosas pasen a la vez.
	return ch, func() {
		d.mu.Lock()
		delete(d.abonados, ch)
		d.mu.Unlock()
	}, true
}

// Cerrar echa a todos los abonados y deja el bus cerrado para siempre.
//
// ES LO QUE PERMITE QUE EL SERVIDOR SE PARE. `http.Server.Shutdown` espera a que terminen
// las peticiones en vuelo, y una conexión de eventos no termina nunca por su cuenta: sin
// esto, el apagado se queda esperando el plazo entero y luego corta a lo bruto, con el
// mensaje de «no dio tiempo a terminar las peticiones en vuelo» que hace pensar en un
// problema que no existe.
func (d *Difusor) Cerrar() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado {
		return
	}
	d.cerrado = true
	for ch := range d.abonados {
		close(ch)
		delete(d.abonados, ch)
	}
	// Y LOS DESPERTADORES. Un `time.AfterFunc` vivo es una gorutina esperando a saltar sobre
	// un bus ya cerrado; no rompe nada —`SoltarPendientes` sale a la primera si está
	// cerrado— pero es exactamente lo que este fichero no puede dejar detrás en un apagado.
	for k, t := range d.temporizadores {
		t.Stop()
		delete(d.temporizadores, k)
	}
}

// Abonados: cuántas conexiones hay abiertas. Para las pruebas y para el registro.
func (d *Difusor) Abonados() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return len(d.abonados)
}

// AvisarCambio es por donde avisan los demás manejadores: `s.AvisarCambio(CambioPedidos,
// map[string]any{"pedidos": n})` después de escribir. Se llama SIEMPRE fuera de la
// transacción y sin mirar lo que devuelve: un aviso perdido no puede tumbar una
// importación de mil pedidos.
func (s *Servidor) AvisarCambio(tipo string, detalle map[string]any) {
	busEventos.Avisar(tipo, detalle)
}

// CerrarEventos cierra a mano las conexiones en vivo. No hace falta llamarla en el arranque
// normal —`registrarApagado` la engancha sola al `Shutdown` del servidor—; está para quien
// pare el servicio de otra manera.
func (s *Servidor) CerrarEventos() { busEventos.Cerrar() }

// rutasEventos monta el flujo. VA SIN `sesion` Y SIN `admin`, y no es un olvido:
//
//   - la sesión se comprueba DENTRO porque el 401 de esta ruta es `Unauthorized` en TEXTO
//     PLANO y no el `{"error":...}` de todas las demás. Es lo que espera el `EventSource`
//     del navegador, que no lee JSON;
//   - el middleware de alcance no se monta porque aquí no se consulta nada. **El alcance sí
//     se resuelve**, a mano y dentro (`sucursalDeQuienEscucha`), desde el 29/09/2026: el
//     aviso ya dice de qué sucursal es, así que hay que cortar por persona. Se hace con la
//     MISMA portería que todo lo demás —`s.porteria.Resolver`—, y no con una comparación
//     propia, porque dos copias de una regla de permisos acaban diciendo cosas distintas y
//     la que se olvide de actualizar es por donde se cuela alguien.
func (s *Servidor) rutasEventos(rt *httpx.Router, sesion, admin []httpx.Medio) {
	rt.ManejarFunc(http.MethodGet, "/api/eventos", s.eventos)
}

// GET /api/eventos
func (s *Servidor) eventos(w http.ResponseWriter, r *http.Request) {
	s.servirEventos(w, r, busEventos)
}

// servirEventos es el manejador de verdad, con el bus por parámetro para poder probarlo
// sin tocar el del proceso.
//
// NO ABRE NI UNA GORUTINA. Todo pasa en la de la petición: el `select` espera a la vez al
// corte del cliente, al siguiente cambio y al latido. Una gorutina aparte por conexión es
// lo que se queda viva cuando el navegador cierra la pestaña sin avisar, y con doscientas
// pestañas al día eso es un proceso que crece hasta que alguien lo reinicia.
func (s *Servidor) servirEventos(w http.ResponseWriter, r *http.Request, bus *Difusor) {
	u, err := s.verif.DelaPeticion(r)
	if err != nil {
		httpx.Registro(r).Warn("eventos sin sesión", "motivo", err)
		// TEXTO PLANO, no JSON: es lo que dice el contrato y lo que sabe leer el cliente.
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = io.WriteString(w, "Unauthorized")
		return
	}

	// Se engancha ANTES de abrir nada: si el servidor se para justo ahora, esta conexión
	// tiene que poder cerrarse sola.
	registrarApagado(r, bus)

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	// Pisa el `no-store, must-revalidate` que pone `httpx.SinCache`. `no-transform` es la
	// parte que importa aquí: sin ella, un proxy que comprime al vuelo puede juntar los
	// bloques y la pantalla no recibe nada hasta que hay bastante que comprimir.
	w.Header().Set("Cache-Control", "no-store, no-transform")
	w.Header().Set("X-Accel-Buffering", "no")

	rc := http.NewResponseController(w)

	// DE QUIÉN ES ESTA CONEXIÓN. Se resuelve antes de abrir nada: si la cuenta no puede
	// ver ninguna sucursal, no hay canal que darle y se dice por qué.
	suya, puede := s.sucursalDeQuienEscucha(w, r, u)
	if !puede {
		return
	}

	canal, cortar, vivo := bus.SuscribirDe(suya)
	if !vivo {
		// El bus está cerrado: el proceso se está parando. Se contesta y se cierra, que es
		// mejor que dejar al navegador con una conexión que no le va a traer nada. La
		// pantalla lo entiende y pasa a refrescar sola cada treinta segundos.
		enviarSSE(w, r, rc, "event: sin-vivo\ndata: {}\n\n")
		return
	}
	defer cortar()

	// El `listo` va SIEMPRE el primero. Además de decir que hay avisos en vivo, obliga a
	// vaciar el colchón: hasta que no sale el primer byte, el navegador no da la conexión
	// por abierta y algunos proxys ni siquiera mandan las cabeceras.
	if !enviarSSE(w, r, rc, "event: listo\ndata: {\"vivo\":true}\n\n") {
		return
	}

	tic := time.NewTicker(latidoSSE)
	defer tic.Stop()

	for {
		select {
		case <-r.Context().Done():
			// El navegador cerró, o se acabó el plazo. No hay nada que limpiar salvo lo
			// que ya está en los `defer`.
			return

		case c, abierto := <-canal:
			if !abierto {
				// El bus se cerró: el servidor se está parando. Se sale para que el
				// `Shutdown` pueda terminar.
				return
			}
			if !enviarSSE(w, r, rc, "event: cambio\ndata: "+string(c.datos())+"\n\n") {
				return
			}

		case <-tic.C:
			// LO QUE SE QUEDÓ DENTRO DEL FRENO y ya venció. Va aquí y no en un
			// temporizador propio: este latido ya corre por cada conexión abierta, y
			// montar otro hilo para algo que ya tiene quien lo despierte es hilo de más.
			//
			// Sin esto, doce gestos en doce segundos mandaban UNO —el primero— y los once
			// siguientes no se decían nunca: la otra pantalla se quedaba once tarjetas
			// atrás hasta el temporizador.
			bus.SoltarPendientes()

			// EL LATIDO, CON NOMBRE Y CON `data:`. Ver `bloqueDelLatido`.
			if !enviarSSE(w, r, rc, bloqueDelLatido) {
				return
			}
		}
	}
}

// sucursalDeQuienEscucha: a qué sucursal está acotado el que abre el canal. Vacío = ve las
// ocho, y entonces se lleva todo.
//
// ES LA MITAD QUE NO SE PUEDE HACER EN EL APARATO. Filtrar en el cliente ahorra peticiones,
// pero el aviso ya habría salido por el cable: saber que «cambió el tablero de Camagüey» ya
// es contar algo, y el alcance sale de quién pregunta, nunca de lo que mande el cliente
// (`../../CLAUDE.md` §4; en delivery un operador de Santiago llegó a ver los precios de La
// Habana). Por eso el corte va aquí.
//
// Se resuelve UNA vez, al abrir, y no en cada aviso: la portería toca la base, y hacerlo por
// evento serían cientos de consultas por minuto para contestar siempre lo mismo. El precio
// es que cambiar de sucursal en la barra no se nota hasta que el canal se vuelve a abrir —y
// eso pasa solo cada cinco minutos, porque el proxy lo corta—; mientras tanto lo tapa el
// filtro del aparato, que sí mira la sucursal en el momento de cada aviso.
//
// La cabecera `X-Sucursal-Id` se pasa tal cual porque la portería ya sabe qué hacer con
// ella: **la sucursal DE LA PERSONA manda sobre la cabecera**, así que sólo puede estrechar
// dentro de lo que esa persona ya podía ver, nunca abrir. En la web no llega nunca
// —`EventSource` no sabe mandar cabeceras— y ahí el corte fino lo hace el aparato.
//
// Si la portería falla —la base caída medio segundo— se devuelve vacío y se deja
// constancia: quien escucha se lleva de más, que es exactamente lo que tenía antes de este
// cambio. Al revés —«no pude resolverlo, pues no le mando nada»— sería una pantalla que se
// queda vieja sin un error, sin un registro y sin nadie mirando.
func (s *Servidor) sucursalDeQuienEscucha(w http.ResponseWriter, r *http.Request, u *auth.Usuario) (string, bool) {
	if s.porteria == nil || u == nil {
		return "", true
	}
	a, err := s.porteria.Resolver(r.Context(), u, r.Header.Get(alcance.CabeceraSucursal))
	switch {
	case errors.Is(err, alcance.ErrSinAlcance):
		// NO SE ABRE EL CANAL, y no es por tacañería: esta cuenta no está dada de alta en
		// ninguna sucursal, así que TODAS las demás rutas le contestan 403 y sus pantallas
		// están vacías. Un canal abierto para ella sería mandarle los uuid de las ocho
		// sucursales para refrescar lo que no ve.
		//
		// Texto plano y el literal de siempre, por lo mismo que el 401 de arriba: el
		// `EventSource` del navegador no lee JSON. Un 403 lo cierra para siempre, que es lo
		// correcto — esto no se arregla reintentando, se arregla en la oficina.
		httpx.Registro(r).Warn("eventos: cuenta sin alcance", "persona", u.ID)
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusForbidden)
		_, _ = io.WriteString(w, alcance.ErrSinAlcance.Error())
		return "", false
	case err != nil:
		// CUALQUIER OTRO FALLO ABRE A TODAS, y deja constancia. Aquí es al revés que en
		// las consultas —donde «no pude comprobarlo» tiene que ser un 500, porque abrir
		// enseñaría datos de otra sucursal—: por el canal no viaja ningún dato, sólo «algo
		// cambió». Un Postgres que tose medio segundo no puede dejar a una oficina entera
		// con las pantallas quietas y sin un error que lo diga.
		httpx.Registro(r).Warn("eventos: no se pudo resolver el alcance; se le mandan todos",
			"motivo", err)
		return "", true
	}
	// `Todas()` es DESARROLLADOR o SUPER ADMIN (o uno de ellos sin sucursal elegida). No se
	// pregunta aquí por el rol a mano: lo decide la portería con la misma regla que el
	// resto de la api, que compara el nombre del rol EXACTO. `ADMINISTRADOR` es de UNA
	// sucursal, y un «¿contiene admin?» escrito aquí le daría las ocho — que es justo la
	// fuga que este cambio no puede abrir.
	if a.Todas() {
		return "", true
	}
	if id := a.Sucursal(); id != nil {
		return id.String(), true
	}
	return "", true
}

// enviarSSE escribe un bloque y lo vacía. Devuelve false cuando ya no se puede escribir
// —el cliente se fue—, que es la señal de salir del bucle.
func enviarSSE(w http.ResponseWriter, r *http.Request, rc *http.ResponseController, bloque string) bool {
	// EL PLAZO SE RENUEVA EN CADA ESCRITURA. El servidor arranca con `WriteTimeout`
	// puesto —y tiene que estarlo, es lo que impide que un cliente lento se quede con una
	// conexión para siempre—, pero ese plazo cuenta desde que empezó la petición: sin
	// renovarlo, toda conexión de eventos se muere a los treinta segundos. Que el escritor
	// no lo admita (una prueba con `httptest.ResponseRecorder`) no es un fallo.
	_ = rc.SetWriteDeadline(time.Now().Add(plazoEnvio))
	if _, err := io.WriteString(w, bloque); err != nil {
		httpx.Registro(r).Debug("se cortó el flujo de eventos", "err", err)
		return false
	}
	// Sin el vaciado no sale nada hasta que se llena el colchón de Go, que para líneas de
	// veinte bytes es nunca.
	if err := rc.Flush(); err != nil {
		httpx.Registro(r).Debug("no se pudo vaciar el flujo de eventos", "err", err)
		return false
	}
	return true
}

// registrarApagado cuelga el cierre del bus del `Shutdown` del servidor HTTP.
//
// EL PORQUÉ: `Shutdown` deja de aceptar conexiones nuevas y ESPERA a que terminen las que
// hay. Una conexión de eventos no termina nunca —para eso está—, así que sin esto el
// apagado se come el plazo entero (8 s) y acaba cortando a lo bruto; por el camino se
// pierden de verdad las peticiones normales que sí estaban a medias, que es justo lo que el
// apagado ordenado venía a evitar.
//
// El servidor se saca del contexto de la petición (`http.ServerContextKey`) y no de una
// variable del arranque a propósito: así esto funciona sin que `cmd/api` tenga que acordarse
// de nada. Lo que no se ve en el montaje no se puede olvidar al cambiarlo.
func registrarApagado(r *http.Request, bus *Difusor) {
	srv, _ := r.Context().Value(http.ServerContextKey).(*http.Server)
	if srv == nil {
		// Una prueba con el manejador pelado, o un montaje que no es un http.Server. No
		// hay apagado del que colgarse.
		return
	}
	bus.mu.Lock()
	defer bus.mu.Unlock()
	if _, ya := bus.enganchados[srv]; ya {
		return
	}
	bus.enganchados[srv] = struct{}{}
	srv.RegisterOnShutdown(bus.Cerrar)
}

// ---------------------------------------------------------------------------
// Los tipos que faltaban — 17/09/2026
// ---------------------------------------------------------------------------
//
// Van al final del fichero y no en el bloque de arriba a propósito: ese bloque lo está
// leyendo más gente, y añadir aquí no mueve ni una línea de lo que ya hay. Añadir NO rompe
// nada —un tipo que la pantalla no espera se recibe y se ignora—; renombrar sí.
//
// Cada uno está porque hay UNA PANTALLA que lo enseña y que hoy no se entera de nada hasta
// que pasa el temporizador (dos minutos en la web, cinco en la APK):
//
//   - `vehiculos`  → la pantalla de Vehículos, que pide `GET /api/vehicles` y
//     `GET /api/vehicle-types` a la red y **no vive de la base**: el ciclo de
//     sincronización no la repinta, así que sin este aviso no hay nada que la repinte.
//   - `almacenes`  → la pantalla de Almacenes, igual: `GET /api/almacenes` a la red, y los
//     almacenes ni siquiera viajan en `GET /api/sync/cambios` (van en `faltan`).
//   - `sucursales` → el selector de sucursal de la barra y el de Rutas. Ésos sí salen de la
//     base, pero una sucursal recién creada no aparece hasta el siguiente ciclo.
//   - `ajustes`    → la tasa y la moneda. Con ellas se convierte TODO importe que se pinta;
//     una tasa vieja es un número creíble y equivocado, que es lo peor que le puede pasar a
//     algo que alguien va a cobrar.
//
// NO se añadió un tipo para los orígenes (`/api/origins`): ninguna pantalla de la
// aplicación los pide. Queda dicho para que nadie lo lea como un olvido.
const (
	CambioVehiculos  = "vehiculos"
	CambioAlmacenes  = "almacenes"
	CambioSucursales = "sucursales"
	CambioAjustes    = "ajustes"

	// CambioCanal: se movió algo en el canal con PEDIDO — entró un aviso, o salió una tanda.
	//
	// Jose, 26/09/2026: «SSE con todo esto igual, nada de polling». La pantalla del canal
	// nació pidiendo su estado UNA vez, con un botón de «volver a mirar» al lado, y eso es
	// medio sondeo con el dedo de una persona haciendo de temporizador: quien la mira quiere
	// ver el aviso APARECER, que es justo la pregunta que esa pantalla contesta —«¿está
	// entrando algo?»—, y con una foto de hace un rato no se contesta.
	//
	// SE PUBLICA TAMBIÉN CUANDO SE RECHAZA, y no sólo cuando entra: un PEDIDO que manda y un
	// reparto que rechaza todo son la situación que hay que ver cuanto antes, y es la que con
	// un aviso sólo-de-éxito se quedaría sin pintar.
	//
	// LOS DOS SENTIDOS LO PUBLICAN desde esta API —la entrada en `webhook_de_pedido.go`, la
	// salida en `drenaje_del_buzon.go`—, así que la pantalla se entera de las dos mitades.
	// Lo que NO puede publicar es el consumidor de la cola: corre en el proceso del espejo y
	// este bus vive en la memoria de éste, igual que le pasa a `CambioClientes`. Queda dicho
	// para que nadie lo lea como un olvido: mientras las dos puertas convivan, lo que entre
	// por la cola se verá en la siguiente vuelta y no al instante.
	CambioCanal = "canal"
)
