// LAS RUTAS DE REPARTO. La pieza central: armar el camión, despacharlo y cerrarlo.
//
// El pliego es `docs/contratos-api.md` (sección routes) y `docs/reglas-negocio.md` §15.
// Lo que aquí se repite en comentarios es el PORQUÉ, que es lo que no se puede leer del
// código y lo que se rompe cuando alguien "simplifica".
//
// Las tres cosas que hay que tener delante todo el rato:
//
//  1. UNA RUTA SE ARMA CON PEDIDOS QUE YA EXISTEN y que están libres (`route_id` NULL).
//     Teclear paradas creaba pedidos sin folio de PEDIDO —sin factura que atarles y por
//     tanto imposibles de cobrar—; esa puerta se cerró el 03/09/2026.
//  2. `route_id` Y `ultima_ruta_id` SON DOS PREGUNTAS DISTINTAS. El primero es «va
//     cargado ahora»; el segundo, «en qué camión viajó». Al cerrar, un devuelto suelta el
//     primero y CONSERVA el segundo: soltar los dos lo borraba de la hoja de cierre.
//  3. EL CAMIÓN NO SE OCUPA AL ARMAR. Se ocupa al despachar (`in_progress`) y se libera
//     al completar o al borrar la ruta. Ocuparlo al armar impedía preparar la ruta de
//     mañana mientras el camión está fuera, que es justo cuando se prepara.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// Mensajes literales del pliego
// ---------------------------------------------------------------------------
//
// Van aquí y no en `httpx` porque son SÓLO de rutas; los de `httpx` son los que comparten
// varios recursos. Son visibles: salen en la pantalla del logístico. No se tocan.

const (
	msgFaltanCoordenadas = "Las coordenadas del punto de partida son requeridas"
	msgFaltaVehiculo     = "Se requiere un vehículo para crear la ruta"
	// El literal lleva las comillas invertidas alrededor de `orderIds`. Están en el
	// contrato y se ven en la pantalla: no son formato de Markdown.
	msgSinPedidos           = "Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`."
	msgPedidosNoDisponibles = "Los pedidos seleccionados ya no están disponibles"
	// Femenino y distinto del `No encontrado` de `/api/routes/[id]`: así viene del
	// contrato y así se queda.
	msgRutaNoEncontrada = "No encontrada"
	msgSinResultados    = "No vino ningún resultado"
	msgParadaAjena      = "ese pedido no va en esta ruta"
	// Sólo completar fija el histórico. Una marca de parada no cierra la ruta.
	msgRutaCompletada = "La ruta está completada y no se puede modificar ni eliminar: se conserva como histórico."
	// EL PUNTO DE PARTIDA TIENE QUE CAER EN EL PLANETA. Ver `puntoDelPlaneta`.
	msgOrigenImposible = "El punto de partida (%s, %s) no es un punto del mapa: " +
		"la latitud va de -90 a 90 y la longitud de -180 a 180. " +
		"Vuelve a elegir el almacén de salida."
)

// puntoDelPlaneta dice si una coordenada se puede medir.
//
// POR QUÉ EXISTE, con el caso concreto (24/09/2026, probando la API desde fuera). Armar
// una ruta con `originLat: 1e308` daba un `201` CON EL CUERPO VACÍO y dejaba la lista de
// rutas de esa sucursal contestando `200` con cero bytes para siempre. La cadena entera:
//
//	kmHaversine hace `(lat2 - lat1) * math.Pi / 180`. Con 1e308 esa resta se desborda a
//	±Inf, `math.Sin(±Inf)` es NaN, y `total_distance` se guardaba como NaN. `json.Encoder`
//	se niega a codificar un NaN, así que toda respuesta que llevara esa ruta dentro salía
//	cortada —y con el código de éxito ya escrito—.
//
// `httpx.JSON` ya no deja salir una respuesta rota con un 2xx (ahora es un 500), pero eso
// es la red de abajo: lo que no puede pasar es que el dato imposible ENTRE. Un almacén no
// está en la latitud 1e308 ni en la 91; si llega una, es el mapa que no terminó de cargar
// o un campo mal tecleado, y las dos cosas se arreglan volviendo a elegir el origen.
//
// El cero SIGUE VALIENDO, que es lo que dice el contrato: es una coordenada legítima —el
// golfo de Guinea— y es además lo que manda la pantalla mientras el mapa carga.
func puntoDelPlaneta(lat, lng float64) bool {
	if math.IsNaN(lat) || math.IsNaN(lng) || math.IsInf(lat, 0) || math.IsInf(lng, 0) {
		return false
	}
	return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}

// ---------------------------------------------------------------------------
// Geometría  (reglas-negocio §1.1 a §1.3)
// ---------------------------------------------------------------------------

// La distancia en línea recta es `kmHaversine`, en `clientes.go`: UNA sola en todo el
// paquete. Aquí había una tercera copia (`haversineKm`) escrita en paralelo con las otras
// dos; son la misma cuenta y ahora hay una.
//
// LO QUE NO SE PUEDE PERDER DE AQUÍ: se usa SIN REDONDEAR. El redondeo es cosa de quien lo
// enseña, y redondear antes de ordenar cambia el orden de visita cuando dos paradas caen
// casi a la misma distancia.

// paradaGeo es lo mínimo que hace falta para ordenar: dónde está cada pedido.
type paradaGeo struct {
	id  uuid.UUID
	lat float64
	lng float64
}

// distanciaKm es cómo se mide entre dos puntos. Se pasa por fuera **para dejar la puerta
// abierta al enrutador por calles** que se está escribiendo en el aparato
// (`app/lib/mapa/`): el día que la matriz salga de las calles en vez de la línea recta se
// cambia esta función y el orden de visita no se entera. Hoy el único valor que se usa es
// `kmHaversine` y nada de aquí depende de que ese enrutador exista.
type distanciaKm func(lat1, lng1, lat2, lng2 float64) float64

// mejoraMinimaKm es la mejora mínima, en km, para dar por bueno un movimiento.
//
// NUNCA SE COMPARA CON `> 0` A SECAS, y no es celo. Dos recorridos de la misma longitud no
// dan exactamente el mismo `float64`: el orden en que se suman los tramos cambia el último
// bit, así que A «mejora» a B por 1e-16 km y B «mejora» a A por otro tanto. Con `> 0` eso
// es un bucle que no termina, y —peor— no termina IGUAL aquí que en Dart, porque el
// `math.Sin` de Go y el de la VM de Dart redondean distinto en el último bit. 1e-9 km es un
// micrómetro: se traga ese ruido entero y no se traga ninguna mejora de verdad.
const mejoraMinimaKm = 1e-9

// topeDePasadasDeMejora: el tope de pasadas. Quien espera es la pantalla del logístico.
//
// Con 60 paradas una pasada son ~13.000 medidas (10 ms medidos, `orden_de_paradas_test.go`
// los imprime), y ni con 10, ni con 30, ni con 60 paradas hacen falta más de 3 pasadas.
// El tope está para que un caso patológico —o un `mejoraMinimaKm` que alguien
// baje— no cuelgue la petición: se devuelve el mejor orden encontrado hasta ahí, que
// siempre es mejor o igual que el del vecino más próximo.
const topeDePasadasDeMejora = 50

// ordenDeVisita devuelve los ids en el orden BUENO: vecino más próximo y después 2-opt y
// Or-opt sobre el circuito CERRADO, hasta que no mejore.
//
// POR QUÉ SE CAMBIÓ (21/09/2026). Jose, mirando una ruta planificada: «esa planificada está
// mal, no hace ruta lógica ni nada». Y tenía razón: el vecino más próximo a secas se come
// los caramelos cercanos y deja los lejanos sueltos, así que la ruta cruza sobre sí misma y
// el último tramo es un viaje entero de vuelta al almacén. No estaba rota: es lo que hace
// ese algoritmo.
//
// SOBRE EL CIRCUITO CERRADO, NO SOBRE LA IDA: el camión vuelve al almacén y esos km ya
// entran en `totalDistance`. Mejorar sólo la ida deja fuera justo el tramo que más duele.
//
// Los dos movimientos, y por qué hacen falta los dos:
//
//   - 2-opt invierte un trozo del recorrido. Es lo único que deshace un cruce: dos tramos
//     que se cortan siempre son más largos que los dos que salen de invertir lo de en medio.
//   - Or-opt mueve 1, 2 o 3 paradas seguidas a otro sitio SIN invertir nada. Es lo que
//     recoloca al cliente que se quedó solo en medio de la nada, y eso 2-opt no lo arregla
//     porque mover una sola parada no es invertir un trozo.
//
// DETERMINISMO, que es la parte que se rompe sin que salte nada: el mismo orden de entrada
// da el mismo orden de salida aquí y en `app/lib/pantallas/rutas/datos/geo.dart`
// (`ordenDeVisita`), porque las dos hacen las pasadas en el mismo orden, aplican la PRIMERA
// mejora que encuentran y comparan contra `mejoraMinimaKm`. Lo ata
// `docs/orden-de-paradas.casos.json`, que leen la prueba de aquí y la del aparato: si
// alguien toca un lado y no el otro, se pone rojo.
func ordenDeVisita(origenLat, origenLng float64, paradas []paradaGeo) []uuid.UUID {
	return ordenDeVisitaCon(origenLat, origenLng, paradas, kmHaversine)
}

// ordenDeVisitaCon es la de arriba con la regla de medir por fuera. Existe para el día del
// enrutador por calles y para que la prueba pueda medir con una distancia de mentira.
func ordenDeVisitaCon(origenLat, origenLng float64, paradas []paradaGeo, d distanciaKm) []uuid.UUID {
	c := &circuito{
		origenLat: origenLat,
		origenLng: origenLng,
		paradas:   vecinoMasProximo(origenLat, origenLng, paradas, d),
		distancia: d,
	}
	for pasadas := 0; pasadas < topeDePasadasDeMejora; pasadas++ {
		// Las dos pasadas SIEMPRE, sin cortocircuito: con `dosOpt() || orOpt()` el Or-opt
		// no correría en cuanto el 2-opt moviera algo, y el resultado dependería de cuál
		// encontró antes.
		movioDosOpt := c.pasadaDeDosOpt()
		movioOrOpt := c.pasadaDeOrOpt()
		if !movioDosOpt && !movioOrOpt {
			break
		}
	}
	if len(c.paradas) == 0 {
		return nil
	}
	orden := make([]uuid.UUID, 0, len(c.paradas))
	for _, p := range c.paradas {
		orden = append(orden, p.id)
	}
	return orden
}

// ordenVecinoMasProximo devuelve los ids por vecino más próximo, sin 2-opt ni nada después.
//
// Se queda tal cual, y no por nostalgia: es el punto de partida de `ordenDeVisita` y es LA
// VARA con la que se mide que la mejora mejora de verdad (`orden_de_paradas_test.go`).
// Quien arma una ruta llama a `ordenDeVisita`.
//
// DOS DETALLES QUE PARECEN MENUDENCIAS Y NO LO SON:
//
//   - El desempate lo gana el PRIMERO de la lista (comparación estricta `<`). Con dos
//     clientes en el mismo edificio —que los hay— un `<=` daría un orden distinto cada
//     vez que cambie el orden de lectura de la base.
//   - No se cierra el circuito: el regreso al almacén no es una parada. Los kilómetros
//     de la vuelta los suma quien calcula el total, no este orden.
func ordenVecinoMasProximo(origenLat, origenLng float64, paradas []paradaGeo) []uuid.UUID {
	ordenadas := vecinoMasProximo(origenLat, origenLng, paradas, kmHaversine)
	if len(ordenadas) == 0 {
		return nil
	}
	orden := make([]uuid.UUID, 0, len(ordenadas))
	for _, p := range ordenadas {
		orden = append(orden, p.id)
	}
	return orden
}

// ordenDelLogistico es el orden que vino en `orderIds`, tal cual, sin tocar una coma.
//
// No es «el algoritmo apagado»: es el otro orden posible, y el bueno cuando quien armó la
// ruta conoce las calles. Lo único que hace es quedarse con los que de verdad van en la
// ruta —los que tienen punto de entrega, que son los de `paradas`— y CONSERVAR la posición
// en que llegaron. Un id repetido en el cuerpo no se visita dos veces.
//
// Y lo que se guarda después es `optimized = false`. Ésa es la mitad que faltaba: sin ella
// la ruta salía firmada como calculada por la máquina y el orden de la persona quedaba
// indistinguible del del greedy.
func ordenDelLogistico(ids []uuid.UUID, paradas []paradaGeo) []uuid.UUID {
	if len(paradas) == 0 {
		return nil
	}
	tienePunto := make(map[uuid.UUID]bool, len(paradas))
	for _, p := range paradas {
		tienePunto[p.id] = true
	}
	orden := make([]uuid.UUID, 0, len(paradas))
	puesto := make(map[uuid.UUID]bool, len(paradas))
	for _, id := range ids {
		if tienePunto[id] && !puesto[id] {
			puesto[id] = true
			orden = append(orden, id)
		}
	}
	// Lo que estaba en `paradas` y no en la lista no se pierde: se va al final. No puede
	// pasar hoy —`paradas` sale de los mismos ids— pero descartar una parada en silencio
	// es un camión cargado con un bulto que no sale en la hoja.
	for _, p := range paradas {
		if !puesto[p.id] {
			puesto[p.id] = true
			orden = append(orden, p.id)
		}
	}
	return orden
}

// vecinoMasProximo es el greedy de siempre devolviendo las paradas en vez de sus ids:
// `ordenDeVisita` necesita las coordenadas para seguir midiendo. Es EL MISMO bucle que
// usaba `ordenVecinoMasProximo`, no una copia — dos greedy escritos en paralelo terminan
// desempatando distinto, que es justo lo que no puede pasar.
func vecinoMasProximo(origenLat, origenLng float64, paradas []paradaGeo, d distanciaKm) []paradaGeo {
	if len(paradas) == 0 {
		return nil
	}
	pendientes := append([]paradaGeo(nil), paradas...)
	orden := make([]paradaGeo, 0, len(pendientes))
	actualLat, actualLng := origenLat, origenLng
	for len(pendientes) > 0 {
		mejor := 0
		mejorKm := math.Inf(1)
		for i, p := range pendientes {
			km := d(actualLat, actualLng, p.lat, p.lng)
			if km < mejorKm {
				mejorKm = km
				mejor = i
			}
		}
		elegida := pendientes[mejor]
		orden = append(orden, elegida)
		actualLat, actualLng = elegida.lat, elegida.lng
		pendientes = append(pendientes[:mejor], pendientes[mejor+1:]...)
	}
	return orden
}

// circuito es el recorrido a medio mejorar. EL ALMACÉN NO ESTÁ EN LA LISTA: es el nodo -1 y
// el nodo n a la vez, que es lo que cierra el circuito sin meterlo como parada. Si
// estuviera dentro, 2-opt podría moverlo de sitio y la ruta dejaría de salir del almacén.
type circuito struct {
	origenLat, origenLng float64
	paradas              []paradaGeo
	distancia            distanciaKm
}

// nodo: el almacén por los dos extremos. Fuera del rango, el nodo es el origen.
func (c *circuito) nodo(i int) (float64, float64) {
	if i < 0 || i >= len(c.paradas) {
		return c.origenLat, c.origenLng
	}
	return c.paradas[i].lat, c.paradas[i].lng
}

func (c *circuito) paso(i, j int) float64 {
	aLat, aLng := c.nodo(i)
	bLat, bLng := c.nodo(j)
	return c.distancia(aLat, aLng, bLat, bLng)
}

// pasadaDeDosOpt invierte el trozo `[i..j]` y se queda con la inversión si acorta el
// circuito. Los dos tramos que cambian son el de entrada al trozo y el de salida; lo de
// dentro se recorre al revés y mide lo mismo.
//
// Se aplica la PRIMERA mejora que aparece (no la mejor de todas) y se sigue barriendo desde
// donde iba. Es lo mismo en Dart, línea por línea: quedarse con «la mejor» obligaría a
// desempatar entre dos mejoras iguales, y ahí es donde los dos lenguajes se separarían.
func (c *circuito) pasadaDeDosOpt() bool {
	movio := false
	for i := 0; i < len(c.paradas)-1; i++ {
		for j := i + 1; j < len(c.paradas); j++ {
			cambio := c.paso(i-1, j) + c.paso(i, j+1) - c.paso(i-1, i) - c.paso(j, j+1)
			if cambio < -mejoraMinimaKm {
				c.invertir(i, j)
				movio = true
			}
		}
	}
	return movio
}

func (c *circuito) invertir(desde, hasta int) {
	for a, b := desde, hasta; a < b; a, b = a+1, b-1 {
		c.paradas[a], c.paradas[b] = c.paradas[b], c.paradas[a]
	}
}

// pasadaDeOrOpt saca 1, 2 o 3 paradas seguidas y las vuelve a meter en otro sitio, en el
// mismo sentido.
//
// El hueco de inserción `p` se cuenta sobre la lista YA SIN el trozo, así que `p == inicio`
// es dejarlo donde estaba: se salta a propósito. Su cambio da cero exacto —son las mismas
// tres medidas restadas— pero saltarlo deja claro que no hay ningún movimiento nulo que
// pueda «mejorar» por redondeo.
func (c *circuito) pasadaDeOrOpt() bool {
	movio := false
	for largo := 1; largo <= 3; largo++ {
		for inicio := 0; inicio+largo <= len(c.paradas); inicio++ {
			trozo := append([]paradaGeo(nil), c.paradas[inicio:inicio+largo]...)
			resto := append([]paradaGeo(nil), c.paradas[:inicio]...)
			resto = append(resto, c.paradas[inicio+largo:]...)
			// Lo que se ahorra al sacar el trozo: los dos tramos que lo sujetaban menos
			// el que queda al juntar sus vecinos.
			antesLat, antesLng := c.nodo(inicio - 1)
			despuesLat, despuesLng := c.nodo(inicio + largo)
			ahorro := c.paso(inicio-1, inicio) +
				c.paso(inicio+largo-1, inicio+largo) -
				c.distancia(antesLat, antesLng, despuesLat, despuesLng)
			for p := 0; p <= len(resto); p++ {
				if p == inicio {
					continue
				}
				aLat, aLng := c.origenLat, c.origenLng
				if p > 0 {
					aLat, aLng = resto[p-1].lat, resto[p-1].lng
				}
				bLat, bLng := c.origenLat, c.origenLng
				if p < len(resto) {
					bLat, bLng = resto[p].lat, resto[p].lng
				}
				costo := c.distancia(aLat, aLng, trozo[0].lat, trozo[0].lng) +
					c.distancia(trozo[largo-1].lat, trozo[largo-1].lng, bLat, bLng) -
					c.distancia(aLat, aLng, bLat, bLng)
				if costo-ahorro < -mejoraMinimaKm {
					nuevo := make([]paradaGeo, 0, len(c.paradas))
					nuevo = append(nuevo, resto[:p]...)
					nuevo = append(nuevo, trozo...)
					nuevo = append(nuevo, resto[p:]...)
					c.paradas = nuevo
					movio = true
					break // el `resto` ya no vale: se rehace en la vuelta siguiente.
				}
			}
		}
	}
	return movio
}

// ---------------------------------------------------------------------------
// El aviso a PEDIDO y el aviso a las pantallas
// ---------------------------------------------------------------------------
//
// Son VARIABLES de paquete y no llamadas directas por dos razones: la prueba las sustituye
// sin levantar nada, y el día que exista el canal de verdad se cambia aquí y en un sitio.

// ParteAPedido es lo que se le contesta al cliente sobre el aviso: la forma la fija el
// contrato (`aPedido: {ok, enviados, aplicados, error?}`).
type ParteAPedido struct {
	Ok        bool   `json:"ok"`
	Enviados  int    `json:"enviados"`
	Aplicados int    `json:"aplicados"`
	Error     string `json:"error,omitempty"`

	// Rechazo: PEDIDO CONTESTÓ Y DIJO QUE NO. Es otra cosa que `Error`, y meterlos en el
	// mismo sitio era un fallo vivo del 26/09/2026.
	//
	// Los dos acaban en `Error` —ahí está el motivo para la persona que lo lea— pero el
	// que decide qué hacer con el aviso es ÉSTE. Un rechazo no se arregla esperando:
	// repetirlo da exactamente lo mismo. Un fallo de transporte sí.
	//
	// LO QUE PASABA SIN ESTO, y no es hipotético: `Ok = (Error == "")` mandaba los dos por
	// la rama de «no se pudo ni preguntar», así que `AvisoAPedidoRechazado` era **código
	// muerto** —`situacion='rechazado'` no se escribía jamás— y el aviso se reenviaba cada
	// minuto PARA SIEMPRE. Y como el buzón se drena por orden de llegada con
	// `LIMIT 200`, esa fila iba en todas las tandas y **paraba el canal entero**: nada de
	// lo que viniera detrás llegaba a marcarse enviado.
	//
	// Encima dejaba `pendienteMasViejo` clavado, así que la alarma del atasco sonaba a
	// diario diciendo «la salida está atascada» cuando la verdad era «PEDIDO rechazó un
	// pedido que allá no existe». Un aviso que sale siempre se silencia en una semana.
	Rechazo bool `json:"rechazo,omitempty"`

	// HTTP es el código que contestó PEDIDO, o 0 si no se llegó a hablar.
	//
	// La columna `envios_del_webhook.http` existe desde la 00011 y **nunca se rellenaba**,
	// porque `mandarTanda` se comía el `res.StatusCode` dentro de una cadena. Su propia
	// migración dice por qué hace falta: «un 200 con cero aceptados y un 502 no son lo
	// mismo, y guardar sólo “falló” los confunde». Estaban confundidos.
	HTTP int `json:"http,omitempty"`
}

// AvisoDeParada es un pedido y en qué punto del reparto quedó.
type AvisoDeParada struct {
	// PedidoID es el id EN PEDIDO, no el nuestro. Cada copia del espejo lo guarda en
	// `external_id`; un pedido sin él no tiene a quién avisarle y no entra en el lote.
	PedidoID string `json:"pedidoId"`
	Estado   string `json:"estado"`
	Nota     string `json:"nota,omitempty"`

	// At es LA HORA DEL SUCESO, no la de la llamada.
	//
	// Es la diferencia entre que en PEDIDO ponga las cuatro o las siete y media. Con el
	// trabajo sin conexión, el logístico marca el cierre a las 16:04 en un patio sin
	// señal y la cola sube a las 19:30: el vendedor tiene que ver cuándo recibió su
	// cliente, no cuándo pilló señal el teléfono (`docs/sincronizacion.md`, «La hora es
	// la del aparato»).
	//
	// `omitzero` y no `omitempty`: un `time.Time` vacío no es «vacío» para el JSON, se
	// serializaría como el año 1, y PEDIDO se creería esa fecha. Sin hora, el campo no
	// va y PEDIDO pone la suya, que es lo que dice el contrato (`at?`).
	At time.Time `json:"at,omitzero"`
}

// horaDelSuceso: CUÁNDO PASÓ, que no siempre es cuándo se está contando.
//
// El sincronizador reenvía cada apunte de la cola de un aparato con `X-Hecho-At`, la hora
// que marcó el aparato cuando la persona pulsó el botón (ver `sync/internal/reparto`). Si
// viene, es LA buena. Si no viene, quien llama tiene señal ahora mismo y la hora de la
// llamada ES la del suceso.
//
// POR QUÉ SE LEE DE LA CABECERA Y NO DEL CUERPO: el cuerpo es el contrato con la pantalla,
// que no sabe nada de colas ni de reintentos y manda lo mismo tenga o no señal. La hora
// del aparato es cosa del transporte, y ponerla en el cuerpo obligaría a que cada
// pantalla se acordara de rellenarla —y la que se olvidara mentiría sin que nada fallara.
func horaDelSuceso(r *http.Request) time.Time {
	if crudo := strings.TrimSpace(r.Header.Get("X-Hecho-At")); crudo != "" {
		if t, err := time.Parse(time.RFC3339Nano, crudo); err == nil {
			return t.UTC()
		}
		// Una cabecera ilegible NO tumba el aviso y NO se cuela: se cae a la hora de
		// ahora, que es peor dato pero es un dato honesto. Lo que no puede pasar es que
		// un reloj mal escrito ponga en PEDIDO una fecha del año 1970.
		httpx.Registro(r).Warn("X-Hecho-At no se entiende: se usa la hora de ahora", "valor", crudo)
	}
	return time.Now().UTC()
}

// Los cinco estados del contrato. `despachado` al armar, `en_transito` al salir y los
// tres del cierre.
const (
	estadoDespachado = "despachado"
	estadoEnTransito = "en_transito"
)

// EL CANAL YA NO ES UN GANCHO VACÍO: lo monta `NuevoServidor` a partir de la
// configuración y vive en `s.aPedido` (ver `canal_pedido.go`). Sigue siendo un campo y no
// una llamada directa por lo de siempre —la prueba lo sustituye sin levantar nada— pero
// cuando hay `PEDIDO_API_URL` y `SERVICE_API_KEY` sale de verdad a la red.
//
// Si NO las hay, el canal que se monta es el mudo: no llama a nadie, lo dice en el parte y
// lo deja en el registro. Nunca `ok: true` sin haber avisado.

// avisarCambio publica «algo cambió en rutas» para que las pantallas abiertas se enteren.
// Mientras no haya Redis no hace nada, y por eso NO devuelve error: una ruta no se deja de
// crear porque el aviso no salga.
//
// LA SUCURSAL SE LA PASA EL MANEJADOR, LEÍDA DE `routes.branch_id` — 01/10/2026. Antes la
// sacaba el bus del alcance de quien llamó, y para quien ve las ocho eso es «de todas»: una
// ruta de Santiago mandaba a las otras siete a bajarse su lista de rutas. El porqué entero,
// en `eventos.go` encima del `init()`.
//
// `routes.branch_id` admite nulo, así que se pasa con `deLaFilaPg`: una ruta sin sucursal
// —no debería haberlas— se avisa a las ocho, que es el lado seguro.
var avisarCambioDeRutas = func(_ context.Context, _ string) {}

// ---------------------------------------------------------------------------
// La forma de la respuesta
// ---------------------------------------------------------------------------

// RutaSalida es el contrato con el cliente. No se devuelve la fila de sqlc: la fila cambia
// en cuanto alguien toca una consulta y el cliente deja de encontrar un campo sin que nada
// falle al compilar.
type RutaSalida struct {
	ID            uuid.UUID `json:"id"`
	Name          *string   `json:"name"`
	RouteCode     *string   `json:"routeCode"`
	Status        string    `json:"status"`
	OriginAddress *string   `json:"originAddress"`
	OriginLat     *float64  `json:"originLat"`
	OriginLng     *float64  `json:"originLng"`
	TotalDistance float64   `json:"totalDistance"`
	TotalWeight   float64   `json:"totalWeight"`
	TotalPrice    float64   `json:"totalPrice"`
	// CUÁNTAS DE ESAS PARADAS NO ESTÁN COTIZADAS. Campo NUEVO, al lado del total y no en
	// lugar de él: `totalPrice` sigue siendo un número y una APK instalada lo lee igual.
	//
	// `totalPrice` suma sólo lo que SÍ está cotizado —la parada sin `pedidoCosto` entra
	// valiendo cero—, así que un 0 ahí no dice «no hay tarifa», dice que el reparto fue
	// gratis. Eso es lo que se vio el 22/09/2026 en RT-20260921-007: `$0.00` con sus dos
	// paradas sin cotizar y el camión a 1,50 USD/km. Dentro de la aplicación ya se
	// resolvió sumando de las paradas; esto es para quien lo lee por SQL o lo exporta.
	//
	// null = no consta (rutas anteriores a 00007, y las que arma el tablero hasta que
	// `tablero.go` lo mande); 0 = estaban todas cotizadas.
	ParadasSinCotizar *int32     `json:"paradasSinCotizar"`
	DeliveryDate      *time.Time `json:"deliveryDate"`
	VehicleID         *uuid.UUID `json:"vehicleId"`
	BranchID          *uuid.UUID `json:"branchId"`
	CreadoPor         *string    `json:"creadoPor"`
	StartedAt         *time.Time `json:"startedAt"`
	FinishedAt        *time.Time `json:"finishedAt"`
	Optimized         bool       `json:"optimized"`
	CreatedAt         *time.Time `json:"createdAt"`
	UpdatedAt         *time.Time `json:"updatedAt"`
	// `branch` no venía en delivery y tuvo que añadirse: el Super Admin veía las rutas de
	// las ocho sucursales en una lista sin nada que las distinguiera, y dos rutas del
	// mismo día con el mismo aspecto podían ser de Holguín y de La Habana.
	Branch  *SucursalDeRuta `json:"branch"`
	Vehicle *CamionDeRuta   `json:"vehicle"`
	Orders  []ParadaSalida  `json:"orders"`
}

type SucursalDeRuta struct {
	ID         uuid.UUID `json:"id"`
	Name       *string   `json:"name"`
	ExternalID *string   `json:"externalId"`
}

type CamionDeRuta struct {
	ID       uuid.UUID `json:"id"`
	Name     *string   `json:"name"`
	Type     *string   `json:"type"`
	Plate    *string   `json:"plate"`
	Capacity *float64  `json:"capacity"`
}

// ParadaSalida es un pedido visto como parada del camión.
//
// `segmentKm` ENGAÑA y se conserva el nombre a propósito: NO es el tramo anterior→actual
// sino la distancia RADIAL del almacén a ese cliente, que es la medida con la que se cobra
// un domicilio. Cambiarle el sentido cambiaría el precio de todos los domicilios.
type ParadaSalida struct {
	ID              uuid.UUID         `json:"id"`
	OperationNumber *string           `json:"operationNumber"`
	CustomerName    string            `json:"customerName"`
	CustomerPhone   *string           `json:"customerPhone"`
	Address         string            `json:"address"`
	EndAddress      *string           `json:"endAddress"`
	EndLat          *float64          `json:"endLat"`
	EndLng          *float64          `json:"endLng"`
	Lat             *float64          `json:"lat"`
	Lng             *float64          `json:"lng"`
	Status          string            `json:"status"`
	Weight          float64           `json:"weight"`
	Price           *float64          `json:"price"`
	PedidoCosto     *float64          `json:"pedidoCosto"`
	SegmentKm       *float64          `json:"segmentKm"`
	StopOrder       *int32            `json:"stopOrder"`
	TripLeg         string            `json:"tripLeg"`
	Municipio       *string           `json:"municipio"`
	ExternalID      *string           `json:"externalId"`
	Resultado       *string           `json:"resultado"`
	ResultadoAt     *time.Time        `json:"resultadoAt"`
	ResultadoNota   *string           `json:"resultadoNota"`
	DeliveredAt     *time.Time        `json:"deliveredAt"`
	Items           []RenglonDeParada `json:"items"`
}

// RenglonDeParada es una línea de la hoja de carga. En delivery `items` era una columna
// JSON; aquí son filas de `order_items`, con su número de línea.
type RenglonDeParada struct {
	Linea       int32      `json:"linea"`
	Description string     `json:"description"`
	Quantity    float64    `json:"quantity"`
	Packs       *float64   `json:"packs"`
	ProductID   *uuid.UUID `json:"productId"`
}

// ---------------------------------------------------------------------------
// El montaje
// ---------------------------------------------------------------------------

// rutasDeReparto cuelga las seis rutas del recurso.
//
// TODAS van con sesión y alcance, NINGUNA con `admin`: el contrato dice «Auth: usuario»
// en las seis. Armar y cerrar rutas es el trabajo diario del logístico, no una tarea de
// administración; exigir admin aquí dejaría a la sucursal sin poder despachar. El
// parámetro `admin` se recibe igual para que el montaje se lea idéntico al de los demás
// recursos y para no tener que cambiar la firma el día que alguna lo pida.
func (s *Servidor) rutasDeReparto(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	rt.ManejarFunc(http.MethodGet, "/api/routes", s.listarRutas, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/routes", s.crearRuta, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/routes/{id}", s.obtenerRuta, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/routes/{id}", s.actualizarRuta, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/routes/{id}", s.borrarRuta, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/routes/{id}/stops/{orderId}", s.quitarParadaPlanificada, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/routes/{id}/results", s.cerrarRuta, sesion...)
}

// ---------------------------------------------------------------------------
// GET /api/routes
// ---------------------------------------------------------------------------

func (s *Servidor) listarRutas(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	filas, err := a.ListarRutas(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	ids := make([]uuid.UUID, 0, len(filas))
	for _, f := range filas {
		ids = append(ids, f.ID)
	}
	// TRES consultas fijas y no una por ruta: el tablero sale sin filtro de fecha y con
	// un año de trabajo son cientos de rutas.
	porRuta, err := s.paradasPorRuta(r, a, ids)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]RutaSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, deFilaDeLista(f, porRuta[f.ID]))
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// paradasPorRuta trae las paradas de varias rutas con sus renglones, ya agrupadas.
func (s *Servidor) paradasPorRuta(r *http.Request, a *alcance.Acotado, rutas []uuid.UUID) (map[uuid.UUID][]ParadaSalida, error) {
	porRuta := map[uuid.UUID][]ParadaSalida{}
	if len(rutas) == 0 {
		return porRuta, nil
	}
	paradas, err := a.ParadasDeRutas(r.Context(), rutas)
	if err != nil {
		return nil, err
	}
	renglones, err := a.RenglonesDeRutas(r.Context(), rutas)
	if err != nil {
		return nil, err
	}
	porPedido := map[uuid.UUID][]RenglonDeParada{}
	for _, g := range renglones {
		porPedido[g.OrderID] = append(porPedido[g.OrderID], RenglonDeParada{
			Linea: g.Linea, Description: g.Description, Quantity: g.Quantity,
			Packs: g.Packs, ProductID: idOpcional(g.ProductID),
		})
	}
	for _, p := range paradas {
		if !p.RouteID.Valid {
			continue // no puede pasar (el WHERE va por route_id), pero no se supone
		}
		ruta := uuid.UUID(p.RouteID.Bytes)
		porRuta[ruta] = append(porRuta[ruta], ParadaSalida{
			ID: p.ID, OperationNumber: p.OperationNumber, CustomerName: p.CustomerName,
			CustomerPhone: p.CustomerPhone, Address: p.Address, EndAddress: p.EndAddress,
			EndLat: p.EndLat, EndLng: p.EndLng, Lat: p.Lat, Lng: p.Lng,
			Status: string(p.Status), Weight: p.Weight, Price: p.Price,
			PedidoCosto: p.PedidoCosto, SegmentKm: p.SegmentKm, StopOrder: p.StopOrder,
			TripLeg: string(p.TripLeg), Municipio: p.Municipio, ExternalID: p.ExternalID,
			Resultado: textoDeResultado(p.Resultado), ResultadoAt: hora(p.ResultadoAt),
			ResultadoNota: p.ResultadoNota, DeliveredAt: hora(p.DeliveredAt),
			// Siempre una lista, nunca null: un `orders[].items` que a veces es null
			// obliga a comprobarlo en cada pantalla, y donde se olvide revienta.
			Items: append([]RenglonDeParada{}, porPedido[p.ID]...),
		})
	}
	return porRuta, nil
}

// ---------------------------------------------------------------------------
// POST /api/routes — EL ARMADO
// ---------------------------------------------------------------------------

type cuerpoRuta struct {
	Name          httpx.Opcional[string]  `json:"name"`
	VehicleID     httpx.Opcional[string]  `json:"vehicleId"`
	OriginAddress httpx.Opcional[string]  `json:"originAddress"`
	OriginLat     httpx.Opcional[float64] `json:"originLat"`
	OriginLng     httpx.Opcional[float64] `json:"originLng"`
	DeliveryDate  httpx.Opcional[string]  `json:"deliveryDate"`
	BranchID      httpx.Opcional[string]  `json:"branchId"`
	// Crudo a propósito: el contrato dice que lo que NO sea un array de ids se trata
	// como «no vinieron pedidos» y sale por su mensaje, no por «cuerpo no válido».
	OrderIds json.RawMessage `json:"orderIds"`

	// Optimizar dice QUIÉN ORDENA LAS PARADAS, y de ahí sale `optimized` tal cual.
	//
	// Por defecto `true`, que es lo que este armador hacía desde siempre y lo que dice
	// el contrato (§15.1): se manda una lista de pedidos y la máquina calcula el orden
	// de visita. Con `false` se respeta el orden en que vienen en `orderIds` —el que
	// puso la persona— y la ruta se guarda diciendo la verdad: que no la ordenó nadie
	// automático. Es el mismo campo y el mismo nombre que ya usa el tablero
	// (`cuerpoArmar.Optimizar`), para no tener dos idiomas para la misma pregunta.
	//
	// El valor por defecto es `true` y NO `false` a propósito: las APK ya instaladas no
	// mandan este campo, y su lista SÍ viene ordenada por la máquina del aparato.
	// Tomarlas por «orden a mano» marcaría en falso, que es el mismo fallo al revés.
	Optimizar httpx.Opcional[bool] `json:"optimizar"`
}

// errPedidosEscapados corta la transacción del armado cuando un pedido dejó de estar libre
// ENTRE el SELECT que lo dio por bueno y el UPDATE que lo engancha. Va como error —y no
// como una cuenta que se ignora— porque la ruta tiene que salir entera o no salir: media
// ruta creada es un camión cargado con la mitad de lo que dice la hoja.
var errPedidosEscapados = errors.New("un pedido se enganchó a otra ruta mientras se armaba ésta")

func (s *Servidor) crearRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoRuta
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	// --- Validaciones, EN ESTE ORDEN (contrato §15.1) -----------------------
	//
	// El orden importa: quien manda un cuerpo vacío tiene que enterarse primero de que le
	// faltan las coordenadas, que es el primer campo del asistente.

	// `== null` del contrato: el cero es una coordenada válida (Golfo de Guinea, sí, pero
	// también es lo que llega cuando el mapa no ha terminado de cargar). Lo que se
	// rechaza es la ausencia, no el valor.
	if c.OriginLat.Valor == nil || c.OriginLng.Valor == nil {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltanCoordenadas)
		return
	}
	origenLat, origenLng := *c.OriginLat.Valor, *c.OriginLng.Valor
	// Y TIENE QUE SER UN PUNTO DEL MAPA. Va justo detrás del `== null` y antes que nada
	// más: si la coordenada no se puede medir, todo lo que viene después —el orden de
	// visita, los km, el `segmentKm` con el que se cobra el domicilio— sale sin sentido.
	// Ver `puntoDelPlaneta` para el incidente que lo puso aquí.
	if !puntoDelPlaneta(origenLat, origenLng) {
		httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(msgOrigenImposible,
			strconv.FormatFloat(origenLat, 'g', -1, 64),
			strconv.FormatFloat(origenLng, 'g', -1, 64)))
		return
	}

	vehiculoPedido := strings.TrimSpace(c.VehicleID.Con(""))
	if vehiculoPedido == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaVehiculo)
		return
	}

	idsPedidos := leerIdsDePedidos(c.OrderIds)
	if len(idsPedidos) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, msgSinPedidos)
		return
	}

	entrega, ok := fechaDeEntrega(w, r, c.DeliveryDate.Con(""))
	if !ok {
		return
	}

	// --- La sucursal de la ruta --------------------------------------------
	//
	// El alcance MANDA: quien pertenece a una sucursal no puede pasar otra por el cuerpo.
	// Quien no tiene alcance (Super Admin) la dice en el primer paso del asistente; sin
	// eso, su ruta nacía sin sucursal o con la del primer pedido, por casualidad.
	ar := a.EnSucursal(sucursalDelCuerpo(r, c.BranchID.Con("")))

	// --- Los pedidos que TODAVÍA se pueden meter ---------------------------
	//
	// Esta consulta ES la validación, no una lectura previa a ella: pide por ids y
	// devuelve sólo los que siguen libres, facturados en el espejo y con coordenadas.
	pedidos, err := ar.PedidosParaArmarRuta(r.Context(), soloUuids(idsPedidos))
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// LOS QUE NO VOLVIERON, NOMBRADOS UNO A UNO Y CON SU MOTIVO DE VERDAD.
	//
	// Aquí había una RESTA —`len(idsPedidos) - len(pedidos)`— y la diferencia entera se le
	// atribuía a «ya están en otra ruta». Es el mismo fallo que ya se arregló en el tablero
	// (`tablero.go`, `porQueNoEsCandidato`) y en este camino seguía vivo, con tres
	// agravantes:
	//
	//   · EL MOTIVO PODÍA SER FALSO. `PedidosParaArmarRuta` descarta además los archivados
	//     en PEDIDO, los que se quedaron sin coordenadas de entrega —pasa: el upsert del
	//     espejo escribe `end_lat = excluded.end_lat` sin `coalesce`—, los que no vinieron
	//     de PEDIDO y los de otra sucursal. `TestArmarRutaNoCogePedidosDeOtraSucursal`
	//     llegó a dejar escrito que un pedido de Holguín contestaba «ya está en otra ruta».
	//   · NO DECÍA CUÁL. Con quince elegidos, «1 de los 15» obliga a adivinar.
	//   · «Vuelve a elegirlos» ERA UN REINTENTO IMPOSIBLE para casi todos ellos: un pedido
	//     archivado o sin coordenadas contesta lo mismo las veces que se pulse. Un rechazo
	//     permanente disfrazado de reintento es justo lo que prohíbe el `CLAUDE.md`.
	//
	// Y de paso se arregla el repetido: mandar dos veces el mismo id hacía `1 < 2` y
	// contestaba 409 sobre un pedido que estaba perfectamente libre. Lo que falta se
	// calcula sobre los ids DISTINTOS; la M del mensaje sigue siendo lo que la persona
	// eligió en la pantalla.
	faltan, noSonID := faltanDelArmado(idsPedidos, pedidos)
	if len(faltan) > 0 || len(noSonID) > 0 {
		detalle, err := s.motivosDelArmado(r.Context(), ar, faltan, noSonID)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		cuantos := len(faltan) + len(noSonID)
		if len(pedidos) == 0 {
			// Ninguno sirve. Se mantiene el literal del contrato como primera frase —es lo
			// que la pantalla lleva reconociendo desde delivery— y detrás va el porqué de
			// cada uno: sin eso, un 400 a secas es el descarte en silencio entero.
			httpx.Error(w, r, http.StatusBadRequest, msgPedidosNoDisponibles+": "+detalle)
			return
		}
		httpx.Error(w, r, http.StatusConflict, encabezadoDelArmado(cuantos, len(idsPedidos))+detalle)
		return
	}

	// --- Y LO QUE YA SE ENTREGÓ NO VUELVE A SUBIR --------------------------
	//
	// Va ANTES que el corte por factura porque es más grave y porque su arreglo es otro:
	// un pedido sin cotejar se cotea y vuelve, un pedido entregado no vuelve nunca.
	//
	// Por qué hace falta si `PedidosParaArmarRuta` ya exige `route_id IS NULL`: un
	// entregado CONSERVA su `route_id`, pero la clave ajena de `orders.route_id` es
	// `ON DELETE SET NULL` (`db/migrations/00001_init.sql:446`). El día que alguien
	// borre la ruta de ayer —y borrarla está permitido en cualquier estado—, los
	// pedidos que ya se repartieron amanecen con `route_id` nulo, vuelven a la lista de
	// disponibles y se pueden armar otra vez. Ahí el camión sale con mercancía que ya
	// está en casa del cliente.
	if mensaje := mensajeYaEntregados(pedidos); mensaje != "" {
		httpx.Error(w, r, http.StatusConflict, mensaje)
		return
	}

	// --- Sólo entra lo facturado y que cuadre ------------------------------
	//
	// Se comprueba aquí aunque la pantalla ya filtre: basta con que alguien mande los ids
	// a mano, o con que un pedido se coteje otra vez entre que se eligió y se armó la
	// ruta. Lo que se carga tiene que ser lo que se cobró.
	if mensaje := mensajeNoFacturados(pedidos); mensaje != "" {
		httpx.Error(w, r, http.StatusConflict, mensaje)
		return
	}
	if mensaje := mensajeDomicilioSinCobrar(pedidos); mensaje != "" {
		httpx.Error(w, r, http.StatusConflict, mensaje)
		return
	}

	// La factura puede estar pagada y aun así faltar la cotización propia de Entrega.
	// En ese caso no hay importe fiable que asignar a la parada: se rechaza y se identifica
	// por el número de operación que aparece también en la hoja de ruta.
	if mensaje := mensajeSinCalcular(pedidos); mensaje != "" {
		httpx.Error(w, r, http.StatusConflict, mensaje)
		return
	}

	// --- Capacidad por peso ------------------------------------------------
	//
	// Esto es UNA COMPROBACIÓN, no el total de la ruta. Aquí se sumaban también el importe
	// y las paradas sin cotizar para escribirlos en `routes`, y eso se fue el 29/09/2026:
	// los totales de una ruta son la suma de sus paradas y los mantiene la base en cada
	// cambio de paradas (`db/migrations/00014_los_totales_de_la_ruta_no_se_congelan.sql`).
	// Escribirlos también desde aquí era tener la misma aritmética en dos sitios, que es
	// como se separan (`CLAUDE.md` §3-sexies).
	//
	// El peso se queda porque hace falta AHORA, antes de crear nada: es lo que decide si
	// la ruta se arma o se contesta «supera la capacidad». Se suma de los pedidos que van
	// a entrar, que todavía no son paradas de ninguna ruta.
	var pesoTotal float64
	for _, p := range pedidos {
		pesoTotal += p.Weight // un peso sin resolver cuenta 0 kg, como en delivery
	}
	avisoSinCosto := ""
	sinCosto := 0
	// Si el id del camión no es un uuid o no existe, NO se valida capacidad y la ruta se
	// crea igual —así lo dice el contrato— pero se crea SIN camión: guardar un id que no
	// está en `vehicles` reventaría contra la clave ajena con un 500 sin explicación.
	var vehiculo *sqlc.ObtenerVehiculoParaCapacidadRow
	if id, err := uuid.Parse(vehiculoPedido); err == nil {
		v, err := ar.ObtenerVehiculoParaCapacidad(r.Context(), id)
		switch {
		case err == nil:
			vehiculo = &v
		case errors.Is(err, pgx.ErrNoRows):
			httpx.Registro(r).Warn("la ruta se arma sin camión: el vehículo pedido no existe",
				"vehiculo", vehiculoPedido)
		default:
			httpx.ErrorInterno(w, r, err)
			return
		}
	} else {
		httpx.Registro(r).Warn("la ruta se arma sin camión: el vehículo pedido no es un id",
			"vehiculo", vehiculoPedido)
	}
	// Estrictamente mayor: igualar la capacidad exacta SÍ pasa. El peso se enseña con un
	// decimal y la capacidad tal cual está guardada, como en delivery.
	if vehiculo != nil && !vehiculo.IsActive {
		httpx.Error(w, r, http.StatusBadRequest, "El vehículo está inactivo y no se puede asignar a una ruta.")
		return
	}
	if vehiculo != nil && pesoTotal > vehiculo.Capacity {
		httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(
			"Peso total (%.1f kg) supera la capacidad del vehículo (%s kg)",
			pesoTotal, strconv.FormatFloat(vehiculo.Capacity, 'f', -1, 64)))
		return
	}

	// --- El recorrido -------------------------------------------------------
	//
	// Se ordena por el DESTINO (`end_lat`/`end_lng`), no por `lat`/`lng`: el camión va a
	// donde se entrega, no a donde se facturó.
	geo := make([]paradaGeo, 0, len(pedidos))
	// LAS COORDENADAS IMPOSIBLES SE NOMBRAN, NO SE SALTAN. Una parada que se cae de la
	// lista en silencio es un pedido que se queda en el almacén con la ruta dada por
	// buena; y si se dejara entrar, su NaN se comería `total_distance` y con él la
	// respuesta entera (ver `puntoDelPlaneta`). Estas coordenadas no las teclea nadie:
	// vienen del espejo de PEDIDO, así que una fuera del planeta es un dato que alguien
	// tiene que arreglar allí y hay que poder decir cuál.
	var sinMapa []uuid.UUID
	for _, p := range pedidos {
		if p.EndLat == nil || p.EndLng == nil {
			continue // el SQL ya los excluye; aquí es sólo por no desreferenciar
		}
		if !puntoDelPlaneta(*p.EndLat, *p.EndLng) {
			sinMapa = append(sinMapa, p.ID)
			continue
		}
		geo = append(geo, paradaGeo{id: p.ID, lat: *p.EndLat, lng: *p.EndLng})
	}
	if len(sinMapa) > 0 {
		httpx.Error(w, r, http.StatusConflict, mensajeSinMapa(pedidos, sinMapa))
		return
	}
	// EL ORDEN BUENO, NO EL DEL GREEDY A SECAS — 21/09/2026. Aquí se llamaba a
	// `ordenVecinoMasProximo` y es lo que Jose estaba viendo en la pantalla: cruces y un
	// último tramo larguísimo de vuelta al almacén. `ordenDeVisita` arranca de ese mismo
	// greedy y le pasa 2-opt y Or-opt sobre el circuito cerrado. El aparato hace lo mismo.
	//
	// Y QUIEN ORDENA SE APUNTA. Con `optimizar:false` no se toca el orden que vino en
	// `orderIds`: lo puso una persona que conoce las calles, y la máquina no. Ese dato es
	// el que se guarda en `optimized` unas líneas más abajo — antes se guardaba `true`
	// siempre, también cuando el orden era el de la persona, y eso es una firma falsa:
	// quien lo lee da por calculado lo que nadie calculó.
	optimizar := c.Optimizar.Con(true)
	var orden []uuid.UUID
	if optimizar {
		orden = ordenDeVisita(origenLat, origenLng, geo)
	} else {
		orden = ordenDelLogistico(soloUuids(idsPedidos), geo)
	}
	porID := map[uuid.UUID]paradaGeo{}
	for _, g := range geo {
		porID[g.id] = g
	}

	// DOS MEDIDAS DISTINTAS Y NO SE PUEDEN CONFUNDIR:
	//  - `totalDistance` son los km REALES del camión: origen→p1→…→pn→origen, con la
	//    vuelta incluida. Sin la vuelta, las rutas largas salen a la mitad de lo que son.
	//  - `segmentKm` de cada pedido es la distancia RADIAL del origen a ese cliente, que
	//    es con lo que se cobra el domicilio. No es el tramo del recorrido.
	var distanciaTotal float64
	segmentos := map[uuid.UUID]float64{}
	anteriorLat, anteriorLng := origenLat, origenLng
	for _, id := range orden {
		p := porID[id]
		distanciaTotal += kmHaversine(anteriorLat, anteriorLng, p.lat, p.lng)
		segmentos[id] = kmHaversine(origenLat, origenLng, p.lat, p.lng)
		anteriorLat, anteriorLng = p.lat, p.lng
	}
	if len(orden) > 0 {
		distanciaTotal += kmHaversine(anteriorLat, anteriorLng, origenLat, origenLng)
	}

	// --- El código de ruta --------------------------------------------------
	//
	// `RT-YYYYMMDD-NNN` con la fecha de HOY EN UTC, y el NNN de contar las del día. Se
	// cuenta, no se lee el máximo: si se borra una ruta del día el siguiente código se
	// repite, y dos armados a la vez pueden chocar. Se hereda tal cual porque ese código
	// es lo que la gente se dice por teléfono; si empieza a chocar, la salida es una
	// secuencia por día, no un reintento.
	prefijo := "RT-" + time.Now().UTC().Format("20060102") + "-"
	delDia, err := ar.ContarRutasDelDia(r.Context(), prefijo)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	codigo := fmt.Sprintf("%s%03d", prefijo, delDia+1)

	// La ruta pertenece a la sucursal elegida o, si no hay ninguna, a la de sus pedidos.
	sucursalRuta := pedidos[0].BranchID
	if propia := ar.Sucursal(); propia != nil {
		sucursalRuta = pgDe(*propia)
	}

	// --- La escritura, ENTERA O NADA ---------------------------------------
	//
	// Delivery actualizaba los pedidos «una a una y sin transacción». Aquí va en una: si
	// falla a mitad, lo que queda es una ruta con la mitad de las paradas y la otra mitad
	// de los pedidos enganchados a una ruta que nadie va a mirar. La regla de la casa es
	// que a medias no vale.
	var creada sqlc.CrearRutaRow
	// QUIÉNES se escaparon, no cuántos: el 409 de la carrera nombra a los suyos igual que
	// el de arriba. Con un contador sólo se podía decir un número, y un número no le dice
	// a nadie qué tarjeta quitar de la selección.
	var escapados []uuid.UUID
	err = ar.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		creada, err = tx.CrearRuta(r.Context(), sqlc.CrearRutaParams{
			Name:          aTexto(strings.TrimSpace(c.Name.Con(""))),
			RouteCode:     &codigo,
			OriginAddress: aTexto(strings.TrimSpace(c.OriginAddress.Con(""))),
			OriginLat:     &origenLat,
			OriginLng:     &origenLng,
			DeliveryDate:  entrega,
			VehicleID:     idDelVehiculo(vehiculo),
			BranchID:      sucursalRuta,
			// `creado_por` lo pone el alcance: es constancia de quién armó la ruta y NO
			// filtra nada. Filtrar por el creador es lo que escondió los pedidos de
			// Holguín a los propios compañeros de Holguín.
		})
		if err != nil {
			return err
		}
		for i, id := range orden {
			parada := int32(i + 1) // el orden de visita empieza en 1, no en 0
			km := segmentos[id]
			filas, err := tx.EngancharPedidoARuta(r.Context(), sqlc.EngancharPedidoARutaParams{
				PedidoID:  id,
				RutaID:    pgDe(creada.ID),
				StopOrder: &parada,
				SegmentKm: &km,
				// `price` se COPIA de `pedidoCosto`, que es lo que puso el repartidor en
				// PEDIDO; un `null` se guarda como 0. Aquí no se calcula ningún precio:
				// eso lo hace la APK de Entrega y nadie más.
				Price: costoDelPedido(pedidos, id),
			})
			if err != nil {
				return err
			}
			if filas == 0 {
				escapados = append(escapados, id)
			}
		}
		if len(escapados) > 0 {
			return errPedidosEscapados
		}
		// EL PESO, EL IMPORTE Y LAS PARADAS SIN COTIZAR YA NO SE MANDAN DESDE AQUÍ.
		//
		// Los escribían los `EngancharPedidoARuta` de arriba, en esta misma transacción:
		// cada parada que entra dispara el recálculo del espejo de su ruta
		// (`db/migrations/00014_los_totales_de_la_ruta_no_se_congelan.sql`). Así los tres
		// números siguen siendo los de las paradas también dentro de un mes, cuando el
		// espejo de PEDIDO haya repasado el peso o el costo de alguna de ellas — que es lo
		// que no pasaba, y lo que puso «420 kg» sobre dos paradas de 516,5.
		//
		// Lo que se manda es lo que NO es una suma de las paradas: el recorrido y la firma.
		_, err = tx.FijarTotalesDeRuta(r.Context(), sqlc.FijarTotalesDeRutaParams{
			TotalDistance: distanciaTotal,
			// LA FIRMA DE QUIÉN ORDENÓ. Se manda SIEMPRE, también cuando vale `true`:
			// dejarlo a nil aquí lo devolvería al `optimized = true` de la consulta y el
			// dato volvería a mentir en cuanto alguien armara respetando el orden.
			Optimizado: &optimizar,
			ID:         creada.ID,
		})
		return err
	})
	if errors.Is(err, errPedidosEscapados) {
		// La transacción ya deshizo la ruta entera: a medias no vale. Lo que se contesta es
		// QUIÉNES se llevaron y a dónde, leído DESPUÉS del rollback —o sea el estado de
		// ahora mismo, que es el que la persona va a ver al volver a la pantalla.
		detalle, errM := s.motivosDelArmado(r.Context(), ar, escapados, nil)
		if errM != nil {
			httpx.ErrorInterno(w, r, errM)
			return
		}
		httpx.Error(w, r, http.StatusConflict,
			encabezadoDelArmado(len(escapados), len(idsPedidos))+detalle)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// El vendedor se entera AQUÍ de que su pedido se movió. Va de fondo: si PEDIDO no
	// contesta la ruta se crea igual — lo que no puede pasar es no poder armar una ruta
	// porque otra aplicación esté caída.
	// La hora se lee UNA vez y se reparte: todos estos pedidos se cargaron en el mismo
	// acto —armar la ruta— y tienen que constar con la misma hora, no con la de cada
	// vuelta del bucle.
	cuando := horaDelSuceso(r)
	var avisos []AvisoDeParada
	for _, p := range pedidos {
		if p.Source != nil && *p.Source == sqlc.ProcedenciaPedido && p.ExternalID != nil {
			avisos = append(avisos, AvisoDeParada{
				PedidoID: *p.ExternalID, Estado: estadoDespachado, At: cuando,
			})
		}
	}
	s.avisarDeFondo(r, avisos)
	// DE LA RUTA QUE SE ACABA DE CREAR, no del alcance de quien la creó.
	avisarCambioDeRutas(r.Context(), deLaFilaPg(creada.BranchID))

	// El aviso viaja CON la ruta creada, no en su lugar.
	//
	// Si hay pedidos con domicilio sin costear, la pantalla tiene que poder decirlo encima
	// del total: «no incluye N pedidos». Un total a secas parece completo y no lo es.
	if sinCosto > 0 {
		s.reg.WarnContext(r.Context(), "ruta armada con domicilios sin costear",
			"ruta", creada.ID, "sin_costo", sinCosto, "de", len(pedidos))
	}
	s.responderConLaRutaYAvisos(w, r, ar, creada.ID, http.StatusCreated, avisoSinCosto, sinCosto)
}

// ---------------------------------------------------------------------------
// GET /api/routes/{id}
// ---------------------------------------------------------------------------

func (s *Servidor) obtenerRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	s.responderConLaRuta(w, r, a, id, http.StatusOK)
}

// responderConLaRuta relee la ruta entera —cabecera, sucursal, camión y paradas— y la
// escribe. Se relee después de escribir a propósito: así el cliente ve lo que quedó
// guardado y no lo que creíamos haber guardado.
// responderConLaRutaYAvisos es responderConLaRuta más lo que hay que decir de ella.
//
// Se separa en vez de meterle dos parámetros a la de siempre porque la mayoría de las
// respuestas no tienen nada que avisar, y un `"", 0` repetido por todo el fichero se acaba
// copiando mal.
func (s *Servidor) responderConLaRutaYAvisos(w http.ResponseWriter, r *http.Request, ar *alcance.Acotado, id uuid.UUID, codigo int, aviso string, sinCosto int) {
	if aviso == "" {
		s.responderConLaRuta(w, r, ar, id, codigo)
		return
	}
	fila, err := ar.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porRuta, err := s.paradasPorRuta(r, ar, []uuid.UUID{id})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	cuerpo := map[string]any{
		"ruta": deFilaDeDetalle(fila, porRuta[id]),
		"avisos": map[string]any{
			"sinCosto":  sinCosto,
			"detalle":   aviso,
			"elTotalNo": "incluye los pedidos sin costo de domicilio",
		},
	}
	httpx.JSON(w, r, codigo, cuerpo)
}

func (s *Servidor) responderConLaRuta(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, id uuid.UUID, codigo int) {
	fila, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porRuta, err := s.paradasPorRuta(r, a, []uuid.UUID{id})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, codigo, deFilaDeDetalle(fila, porRuta[id]))
}

// ---------------------------------------------------------------------------
// PATCH /api/routes/{id}
// ---------------------------------------------------------------------------

type cuerpoActualizarRuta struct {
	VehicleID httpx.Opcional[string] `json:"vehicleId"`
	Name      httpx.Opcional[string] `json:"name"`
	Status    httpx.Opcional[string] `json:"status"`
}

// La comprobación previa mejora el error, pero sólo esta lectura bloqueada
// impide que otra petición complete entre la lectura y la escritura.
var errRutaCompletada = errors.New(msgRutaCompletada)

func rutaEditableEnTx(ctx context.Context, tx *alcance.Acotado, id uuid.UUID) (sqlc.ObtenerRutaRow, error) {
	estado, err := tx.BloquearRuta(ctx, id)
	if err != nil {
		return sqlc.ObtenerRutaRow{}, err
	}
	if estado == sqlc.RouteStatusCompleted {
		return sqlc.ObtenerRutaRow{}, errRutaCompletada
	}
	return tx.ObtenerRuta(ctx, id)
}

func (s *Servidor) actualizarRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c cuerpoActualizarRuta
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	// Se lee ANTES por dos cosas: el 404 con el alcance puesto y el camión ANTERIOR, que
	// hay que liberar si la ruta cambia de vehículo o se cierra.
	antes, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if antes.Status == sqlc.RouteStatusCompleted {
		httpx.Error(w, r, http.StatusConflict, msgRutaCompletada)
		return
	}

	nombre := c.Name.Puntero()
	var estado *sqlc.RouteStatus
	if c.Status.Presente && c.Status.Valor != nil {
		e, ok := estadoDeRutaValido(w, r, *c.Status.Valor)
		if !ok {
			return
		}
		estado = &e
	}

	// CAMINO A: cambiar el camión. Tiene prioridad y retorna antes, tal como el contrato;
	// aquí no se tocan `startedAt`/`finishedAt` ni se avisa a PEDIDO.
	if c.VehicleID.Presente {
		s.cambiarCamionDeRuta(w, r, a, antes, c, nombre, estado)
		return
	}

	// CAMINO B: el estado. Las horas de salida y regreso las pone el SQL —`started_at`
	// sólo la primera vez— para que dos peticiones simultáneas no se pisen la hora.
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		antes, err = rutaEditableEnTx(r.Context(), tx, antes.ID)
		if err != nil {
			return err
		}
		if _, err := tx.ActualizarEstadoDeRuta(r.Context(), sqlc.ActualizarEstadoDeRutaParams{
			ID: id, Name: nombre, Status: estado,
		}); err != nil {
			return err
		}
		if estado == nil || !antes.VehicleID.Valid {
			return nil
		}
		vehiculo := uuid.UUID(antes.VehicleID.Bytes)
		switch {
		// Despachar OCUPA el camión: es ahora cuando sale, no cuando se armó la ruta.
		case *estado == sqlc.RouteStatusInProgress:
			_, err := tx.CambiarEstadoDeVehiculo(r.Context(), vehiculo, sqlc.VehicleStatusInUse)
			return err
		// Completar lo LIBERA. Si ya estaba disponible no se toca: alguien pudo haberlo
		// liberado a mano y volver a escribirlo sólo mueve `updated_at`.
		case *estado == sqlc.RouteStatusCompleted &&
			antes.VehiculoEstado != nil && *antes.VehiculoEstado == sqlc.VehicleStatusInUse:
			_, err := tx.CambiarEstadoDeVehiculo(r.Context(), vehiculo, sqlc.VehicleStatusAvailable)
			return err
		}
		return nil
	})
	if errors.Is(err, errRutaCompletada) {
		httpx.Error(w, r, http.StatusConflict, msgRutaCompletada)
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Al SALIR se avisa a PEDIDO; al completar NO, porque cada pedido ya tiene su propio
	// resultado y un «entregado» genérico pisaría a los devueltos.
	if estado != nil && *estado == sqlc.RouteStatusInProgress {
		s.avisarDeFondo(r, s.avisosDeLasParadas(r, a, id, estadoEnTransito))
	}
	// `antes` es la ruta leída al entrar, y la sucursal de una ruta no se cambia nunca: ni
	// el estado ni el camión la mueven, así que es la misma antes y después.
	avisarCambioDeRutas(r.Context(), deLaFilaPg(antes.BranchID))
	s.responderConLaRuta(w, r, a, id, http.StatusOK)
}

// cambiarCamionDeRuta es el camino A del PATCH: soltar el camión viejo y ocupar el nuevo.
func (s *Servidor) cambiarCamionDeRuta(w http.ResponseWriter, r *http.Request, a *alcance.Acotado,
	antes sqlc.ObtenerRutaRow, c cuerpoActualizarRuta, nombre *string, estado *sqlc.RouteStatus) {

	// Un `vehicleId` vacío o null desengancha el camión. Uno con valor tiene que EXISTIR y
	// ser alcanzable: si no, la clave ajena daría un 500 con la jerga de Postgres dentro.
	var nuevo *uuid.UUID
	if pedido := strings.TrimSpace(c.VehicleID.Con("")); pedido != "" {
		id, err := uuid.Parse(pedido)
		if err != nil {
			// Un id mal escrito es lo mismo que uno que no está: 400 con un mensaje que
			// se entiende, y no el 500 de la clave ajena con la jerga de Postgres dentro.
			httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf("No existe el vehículo '%s'", pedido))
			return
		}
		// Se comprueba CON ALCANCE: el camión de Holguín no se engancha a una ruta de
		// Santiago ni sabiendo su id. Los compartidos (`branch_id` NULL) sí pasan, que
		// para eso están.
		_, err = a.ObtenerVehiculo(r.Context(), id)
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf("No existe el vehículo '%s'", pedido))
			return
		}
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		nuevo = &id
	}

	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		antes, err = rutaEditableEnTx(r.Context(), tx, antes.ID)
		if err != nil {
			return err
		}
		// El camión viejo se libera SÓLO si estaba ocupado y de verdad cambia: una ruta
		// que se reasigna al mismo camión no tiene por qué dejarlo libre.
		if antes.VehicleID.Valid {
			viejo := uuid.UUID(antes.VehicleID.Bytes)
			cambia := nuevo == nil || *nuevo != viejo
			ocupado := antes.VehiculoEstado != nil && *antes.VehiculoEstado == sqlc.VehicleStatusInUse
			if cambia && ocupado {
				if _, err := tx.CambiarEstadoDeVehiculo(r.Context(), viejo, sqlc.VehicleStatusAvailable); err != nil {
					return err
				}
			}
		}
		if nuevo != nil {
			if _, err := tx.CambiarEstadoDeVehiculo(r.Context(), *nuevo, sqlc.VehicleStatusInUse); err != nil {
				return err
			}
		}
		_, err = tx.CambiarVehiculoDeRuta(r.Context(), sqlc.CambiarVehiculoDeRutaParams{
			ID: antes.ID, VehicleID: aPgOpcional(nuevo), Name: nombre, Status: estado,
		})
		return err
	})
	if errors.Is(err, errRutaCompletada) {
		httpx.Error(w, r, http.StatusConflict, msgRutaCompletada)
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeRutas(r.Context(), deLaFilaPg(antes.BranchID))
	s.responderConLaRuta(w, r, a, antes.ID, http.StatusOK)
}

// ---------------------------------------------------------------------------
// DELETE /api/routes/{id}
// ---------------------------------------------------------------------------

// errRutaNoEstaba corta la transacción del borrado cuando la ruta no es de esta sucursal o
// ya no existe. Va como error para DESHACER lo ya soltado: si no, un intento contra un id
// ajeno dejaría los pedidos de otra sucursal sin ruta.
var errRutaNoEstaba = errors.New("ruta no encontrada en el alcance")
var errParadaNoPertenece = errors.New("parada no pertenece a una ruta planificada")

// DELETE /api/routes/{id}/stops/{orderId}
// Retira sólo una parada de una ruta todavía planificada. Si la ruta nació del tablero,
// la consulta la devuelve además a su columna y posición de origen.
func (s *Servidor) quitarParadaPlanificada(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	rutaID, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	pedidoID, err := uuid.Parse(strings.TrimSpace(r.PathValue("orderId")))
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "Identificador de pedido no válido")
		return
	}
	antes, err := a.ObtenerRuta(r.Context(), rutaID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if antes.Status != sqlc.RouteStatusPlanned {
		httpx.Error(w, r, http.StatusConflict, "Sólo se pueden retirar paradas de una ruta planificada")
		return
	}
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		actual, err := rutaEditableEnTx(r.Context(), tx, rutaID)
		if err != nil {
			return err
		}
		if actual.Status != sqlc.RouteStatusPlanned {
			return errParadaNoPertenece
		}
		_, err = tx.SoltarParadaPlanificada(r.Context(), rutaID, pedidoID)
		if errors.Is(err, pgx.ErrNoRows) {
			return errParadaNoPertenece
		}
		return err
	})
	if errors.Is(err, errRutaCompletada) {
		httpx.Error(w, r, http.StatusConflict, msgRutaCompletada)
		return
	}
	if errors.Is(err, errParadaNoPertenece) {
		httpx.Error(w, r, http.StatusConflict, "El pedido no pertenece a una ruta planificada o ya fue retirado")
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	sucursal := deLaFilaPg(antes.BranchID)
	avisarCambioDeRutas(r.Context(), sucursal)
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

func (s *Servidor) borrarRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	antes, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Jose, 06/10/2026: planificada o en curso se puede borrar incluso con
	// resultados provisionales. El histórico se protege bajo el bloqueo de fila de la transacción.

	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		antes, err = rutaEditableEnTx(r.Context(), tx, antes.ID)
		if err != nil {
			return err
		}
		// Borrar la ruta LIBERA el camión: si no, queda ocupado por una ruta que ya no
		// existe y no hay pantalla donde soltarlo.
		if antes.VehicleID.Valid && antes.VehiculoEstado != nil && *antes.VehiculoEstado == sqlc.VehicleStatusInUse {
			if _, err := tx.CambiarEstadoDeVehiculo(r.Context(), uuid.UUID(antes.VehicleID.Bytes), sqlc.VehicleStatusAvailable); err != nil {
				return err
			}
		}
		// Los pedidos NO se borran: se sueltan y vuelven a la lista de disponibles.
		// El resultado del pedido se conserva. Al borrar la ruta, la clave ajena
		// ON DELETE SET NULL suelta también ultima_ruta_id; sólo completed
		// conserva esa ruta como histórico y nunca llega a este borrado.
		if _, err := tx.SoltarPedidosDeRuta(r.Context(), id); err != nil {
			return err
		}
		filas, err := tx.BorrarRuta(r.Context(), id)
		if err != nil {
			return err
		}
		if filas == 0 {
			return errRutaNoEstaba
		}
		return nil
	})
	if errors.Is(err, errRutaCompletada) {
		httpx.Error(w, r, http.StatusConflict, msgRutaCompletada)
		return
	}
	if errors.Is(err, errRutaNoEstaba) || errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// DE LA RUTA QUE SE FUE. `antes` se leyó al entrar —hace falta para saber si su camión
	// estaba ocupado—, así que la sucursal está en la mano cuando la fila ya no existe.
	sucursal := deLaFilaPg(antes.BranchID)
	avisarCambioDeRutas(r.Context(), sucursal)
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

// ---------------------------------------------------------------------------
// POST /api/routes/{id}/results — EL CIERRE
// ---------------------------------------------------------------------------

type cuerpoCierre struct {
	Resultados []entradaDeCierre `json:"resultados"`
}

type entradaDeCierre struct {
	OrderID string `json:"orderId"`
	// TRI-ESTADO, y los tres significan cosas distintas — 28/09/2026:
	//
	//   · NO VINO el campo        → cuerpo mal formado. Se rechaza con `undefined`, que es
	//     lo que ve quien mira el JSON que mandó.
	//   · vino `"entregado"`…     → se marca.
	//   · vino `null` EXPLÍCITO   → se QUITA la marca. Es lo que manda el aparato cuando
	//     alguien pulsa dos veces el mismo botón en la hoja de cierre para corregir un
	//     dedazo.
	//
	// Con un `*string` a secas los dos primeros casos son indistinguibles —`null` y
	// «ausente» decodifican los dos a `nil`— y por eso desmarcar no tenía forma de llegar
	// hasta aquí. `httpx.Opcional` es la pieza de la casa para exactamente esto.
	//
	// Las APK ya instaladas NO mandan `null`: mandan sólo las paradas con resultado, así
	// que para ellas nada cambia.
	Resultado httpx.Opcional[string] `json:"resultado"`
	Nota      *string                `json:"nota"`
}

type aplicadoDeCierre struct {
	OrderID string `json:"orderId"`
	// `null` cuando lo que se aplicó fue QUITAR la marca. Es el acuse de lo que se hizo, y
	// «se quitó» no es un resultado: escribir `""` ahí obligaría a quien lo lea a
	// distinguir dos formas del mismo vacío.
	Resultado *string `json:"resultado"`
}

type rechazadoDeCierre struct {
	OrderID string `json:"orderId"`
	Motivo  string `json:"motivo"`
}

type salidaDeCierre struct {
	// Error sólo viaja cuando hubo algún rechazo, y entonces la respuesta NO es 200.
	//
	// Es el campo que lee el sincronizador (`sync/internal/reparto/reparto.go`,
	// `motivoDe`): de él saca el motivo que guarda en la bandeja del aparato. Sin él, un
	// rechazo dentro de un 200 no llega a ninguna parte — ver `cerrarRuta`.
	Error      string              `json:"error,omitempty"`
	Aplicados  []aplicadoDeCierre  `json:"aplicados"`
	Rechazados []rechazadoDeCierre `json:"rechazados"`
	APedido    ParteAPedido        `json:"aPedido"`
}

func (s *Servidor) cerrarRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// Femenino: «No encontrada». Distinto del de `/api/routes/[id]` y así está
	// inventariado; hay clientes que comparan el texto.
	id, ok := idDeRuta(w, r, msgRutaNoEncontrada)
	if !ok {
		return
	}
	ruta, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgRutaNoEncontrada)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if ruta.Status == sqlc.RouteStatusCompleted {
		httpx.Error(w, r, http.StatusConflict, msgRutaCompletada)
		return
	}

	// Un cuerpo ilegible se trata como `{}` y sale por «No vino ningún resultado», no por
	// «Cuerpo de la petición no válido»: lo dice el contrato y además es lo útil — quien
	// cierra una ruta desde el móvil con mala cobertura ve el mismo mensaje que si no
	// hubiera marcado nada, que es lo que le pasó.
	var c cuerpoCierre
	_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, topeCuerpoCierre)).Decode(&c)
	defer r.Body.Close()
	if len(c.Resultados) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, msgSinResultados)
		return
	}

	salida := salidaDeCierre{Aplicados: []aplicadoDeCierre{}, Rechazados: []rechazadoDeCierre{}}
	var avisos []AvisoDeParada
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		ruta, err = rutaEditableEnTx(r.Context(), tx, id)
		if err != nil {
			return err
		}
		// EL UNIVERSO SON LOS QUE VIAJARON EN ESTA RUTA, por `ultima_ruta_id` y no por
		// `route_id`: así se puede corregir el resultado de un devuelto, que ya soltó su
		// `route_id` al cerrarse. Con `route_id` media hoja de cierre sería incorregible.
		viajaron, err := tx.ParadasQueViajaronEnRuta(r.Context(), ruta.ID)
		if err != nil {
			return err
		}
		universo := map[uuid.UUID]sqlc.ListarParadasQueViajaronEnRutaRow{}
		for _, p := range viajaron {
			universo[p.ID] = p
		}

		// LA HORA DEL CIERRE, que es el caso por el que existe todo esto. Una hoja de cierre
		// se marca en el patio, sin señal, y sube cuando la hay: el apunte llega con
		// `X-Hecho-At` puesto por el sincronizador y ésa es la hora que va a PEDIDO. Toda la
		// hoja comparte una sola hora porque un apunte es un acto: si algún día hiciera falta
		// la hora parada por parada, tendría que venir en el cuerpo y eso es cambiar el
		// contrato con la pantalla.
		cuando := horaDelSuceso(r)

		// NO ABORTA: acumula. Cada parada es un hecho independiente —el camión volvió y ese
		// pedido se entregó—, así que tumbar las nueve buenas porque la décima venga mal
		// borraría información real que ya nadie va a volver a teclear. Los rechazos
		// individuales no abortan la transacción: se guardan todas las marcas válidas.
		// El bloqueo sólo serializa con completar/borrar; ante un error de base no se
		// acusa un cierre parcial como guardado y el aparato conserva el apunte.
		for _, e := range c.Resultados {
			pedidoID, err := uuid.Parse(strings.TrimSpace(e.OrderID))
			if err != nil {
				salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{OrderID: e.OrderID, Motivo: msgParadaAjena})
				continue
			}
			parada, iba := universo[pedidoID]
			if !iba {
				salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{OrderID: e.OrderID, Motivo: msgParadaAjena})
				continue
			}
			// QUITAR LA MARCA — 28/09/2026. Jose: «desmarco el estado de cierre y no se
			// guarda cuando salgo por q razon».
			//
			// Un `"resultado": null` EXPLÍCITO es «esta parada vuelve a estar sin marcar», y
			// se ejecuta aquí y se acaba la vuelta: no hay resultado que validar, no hay nota
			// que guardar —se va con la marca— y **no sale aviso a PEDIDO**, porque en su
			// contrato no existe «des-entregado» e inventarle un estado es peor que no
			// decirle nada. Eso queda dicho aquí y es un hueco conocido: si la parada ya le
			// había llegado a PEDIDO como entregada, allí sigue entregada hasta que se
			// vuelva a marcar con otro resultado.
			//
			// Lo que SÍ deshace, entero, está en `LimpiarResultadoDeParada`; lo delicado es
			// que le devuelve el `route_id`, o un devuelto desmarcado se queda fuera de su
			// propia ruta y sale en dos camiones.
			if e.Resultado.Presente && e.Resultado.Valor == nil {
				filas, err := tx.LimpiarResultadoDeParada(r.Context(), ruta.ID, pedidoID)
				if err != nil {
					return err
				}
				if filas == 0 {
					salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{OrderID: e.OrderID, Motivo: msgParadaAjena})
					continue
				}
				// En `aplicados` va con su `resultado: null`: el acuse dice lo que se hizo, y
				// lo que se hizo fue dejarla sin marcar.
				salida.Aplicados = append(salida.Aplicados, aplicadoDeCierre{OrderID: pedidoID.String()})
				continue
			}

			resultado, ok := resultadoValido(e.Resultado.Valor)
			if !ok {
				salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{
					OrderID: e.OrderID,
					Motivo:  fmt.Sprintf("resultado '%s' desconocido", valorTalCual(e.Resultado)),
				})
				continue
			}

			nota := notaDeCierre(e.Nota)
			// Aquí está TODO lo delicado del cierre, y va en una sola sentencia SQL:
			//   - un entregado fija `delivered_at` y conserva su `route_id`;
			//   - un devuelto o un cancelado SUELTAN `route_id` —vuelven a la lista de
			//     disponibles para mañana— pero NO `ultima_ruta_id` ni `stop_order`, que son
			//     la hoja de lo que bajó del camión;
			//   - `delivered_at` se limpia cuando no se entregó, o un devuelto con la hora de
			//     un intento anterior se pinta «entregado» en la lista;
			//   - ni devuelto ni cancelado tocan INVENTARIO: el reintegro lo hace Ventra.
			filas, err := tx.MarcarResultadoDeParada(r.Context(), ruta.ID, pedidoID, resultado, nota)
			if err != nil {
				return err
			}
			if filas == 0 {
				// El WHERE lleva `ultima_ruta_id` y el alcance: cero filas es el mismo
				// rechazo, comprobado contra la base y no contra una lectura ya vieja.
				salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{OrderID: e.OrderID, Motivo: msgParadaAjena})
				continue
			}
			aplicado := string(resultado)
			salida.Aplicados = append(salida.Aplicados, aplicadoDeCierre{OrderID: pedidoID.String(), Resultado: &aplicado})
			if parada.Source != nil && *parada.Source == sqlc.ProcedenciaPedido && parada.ExternalID != nil {
				aviso := AvisoDeParada{PedidoID: *parada.ExternalID, Estado: string(resultado), At: cuando}
				if nota != nil {
					aviso.Nota = *nota
				}
				// UN AVISO POR PEDIDO, EL ÚLTIMO — y es el que la base acaba teniendo.
				//
				// Una hoja de cierre puede traer el mismo `orderId` dos veces: la cola del
				// aparato junta apuntes cuando vuelve la señal, y una corrección —«entregado»
				// y luego «devuelto»— es justo el caso S3 del guion de QA. En la base no hay
				// duda: son dos UPDATE seguidos y manda el segundo. En PEDIDO sí la había,
				// porque se le mandaban LOS DOS en el mismo lote y cuál gana depende de en qué
				// orden los aplique él. Ahí es donde el vendedor ve «entregado» sobre un pedido
				// que volvió en el camión: un estado creíble y equivocado, y las dos
				// aplicaciones diciendo cosas distintas del mismo pedido.
				//
				// `aplicados` NO se toca: sigue llevando una entrada por cada cosa que se
				// procesó, que es el acuse que el aparato compara con lo que mandó.
				if donde, repetido := dondeEstaElAviso(avisos, aviso.PedidoID); repetido {
					httpx.Registro(r).Warn("la hoja de cierre trae el mismo pedido dos veces: a PEDIDO va el último",
						"ruta", ruta.ID, "pedido", aviso.PedidoID,
						"antes", avisos[donde].Estado, "ahora", aviso.Estado)
					avisos[donde] = aviso
				} else {
					avisos = append(avisos, aviso)
				}
			}
		}

		return nil
	})
	if errors.Is(err, errRutaCompletada) {
		httpx.Error(w, r, http.StatusConflict, msgRutaCompletada)
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgRutaNoEncontrada)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// AL BUZÓN PRIMERO, Y DESPUÉS SE INTENTA MANDAR.
	//
	// El envío del cierre es síncrono a propósito —el vendedor tiene que poder ver en
	// PEDIDO lo que pasó con su pedido—, pero síncrono no puede querer decir «de una sola
	// vez o nunca». Hasta el 26/09/2026 era eso: si PEDIDO estaba caído, la red iba mal o
	// el proceso se reiniciaba, el aviso se perdía y quedaba **entregado aquí y eterno «en
	// proceso» allá**, sin error en ninguna pantalla y sin nadie a quien reclamarle.
	//
	// Ahora se apunta ANTES de llamar. Si la llamada sale bien, el aviso se marca enviado
	// en el acto; si PEDIDO dice que no, se queda con su motivo literal; y si no se pudo
	// ni preguntar, se queda pendiente y lo drena el trabajador. Un rechazo y un «no se
	// pudo hablar» NO son lo mismo y por eso no comparten estado.
	encolados := s.encolarAvisos(r.Context(), a, ruta.ID, avisos)

	salida.APedido = s.aPedido(r.Context(), avisos)
	if !salida.APedido.Ok && len(avisos) > 0 {
		httpx.Registro(r).Error("el cierre se guardó pero PEDIDO no se enteró; queda en el buzón",
			"ruta", ruta.ID, "avisos", len(avisos), "encolados", encolados,
			"err", salida.APedido.Error)
	}
	avisarCambioDeRutas(r.Context(), deLaFilaPg(ruta.BranchID))
	if encolados > 0 {
		// Y EL CANAL, porque el cierre acaba de meter filas en el buzón de salida
		// (`encolarAvisos`) — 29/09/2026. Es la otra mitad de la pregunta que contesta esa
		// pantalla: `drenaje_del_buzon.go` avisa cuando la tanda SALE, pero nadie avisaba
		// cuando ENTRA en el buzón. Con PEDIDO caído eso es justo lo que hay que ver: la
		// cola llenándose. Sólo si se apuntó algo: un cierre sin avisos no mueve el buzón.
		avisarCambioEnElCanal(r.Context())
	}

	// UN RECHAZO DENTRO DE UN 200 NO LLEGA A NINGUNA PARTE, Y ASÍ SE PIERDE UNA ENTREGA
	// DE VERDAD. Esto es lo que se arregló el 18/09/2026.
	//
	// El mecanismo entero, que no es hipotético:
	//
	//  1. El aparato arma la ruta de una zona sin señal. `POST /board/columns/{id}/route`
	//     no llevaba los pedidos dentro, así que el servidor la armaba HORAS DESPUÉS con
	//     lo que él tuviera puesto en esa zona en ese instante — que puede ser otra cosa,
	//     porque la web siguió moviendo tarjetas mientras tanto.
	//  2. La ruta del servidor nace SIN un pedido que el repartidor ya entregó. Su
	//     resultado llega aquí, no está en el universo, y se va a `rechazados`.
	//  3. Y aquí estaba el agujero: la respuesta era 200. El sincronizador marca
	//     `aplicado` TODO lo que venga con un 2xx —no mira el cuerpo, ver `motivoDe`—, así
	//     que el apunte se borra de la cola del aparato. Una entrega de verdad desaparece
	//     con un 200 y sin dejar rechazo en ninguna bandeja.
	//
	// Con un 4xx, el sincronizador lo anota como `rechazado` CON SU MOTIVO y, por
	// contrato, «no se reintenta y no se borra»: se queda a la vista con su hora hasta que
	// una persona decida. Que es la regla de la casa: nada se descarta en silencio.
	//
	// LO QUE SÍ SE APLICÓ, SE QUEDA APLICADO. El cierre sigue sin abortar: las paradas
	// buenas ya están guardadas y sus avisos ya salieron hacia PEDIDO. El 409 no las
	// deshace —por eso la respuesta sigue llevando `aplicados` entero—, dice que esta hoja
	// no se cerró como el aparato creía y nombra qué falta.
	if len(salida.Rechazados) > 0 {
		salida.Error = motivoDelCierreIncompleto(salida)
		httpx.Registro(r).Error("un cierre llegó con paradas que no van en esa ruta",
			"ruta", ruta.ID, "aplicados", len(salida.Aplicados),
			"rechazados", len(salida.Rechazados), "motivo", salida.Error)
		httpx.JSON(w, r, http.StatusConflict, salida)
		return
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// dondeEstaElAviso busca un aviso ya puesto para ese pedido de PEDIDO.
//
// Es una búsqueda lineal y está bien que lo sea: una hoja de cierre son las paradas de UN
// camión —decenas, no miles— y un mapa aquí obligaría a mantener dos estructuras a la vez
// con el mismo contenido, que es como se separan. Ver el porqué en `cerrarRuta`.
func dondeEstaElAviso(avisos []AvisoDeParada, pedidoID string) (int, bool) {
	for i, a := range avisos {
		if a.PedidoID == pedidoID {
			return i, true
		}
	}
	return 0, false
}

// motivoDelCierreIncompleto arma el texto que va a acabar en la bandeja del aparato.
//
// Lleva las tres cosas que necesita quien lo lee tres horas después: CUÁNTAS entraron
// —para que no crea que se perdió la hoja entera—, cuáles no y por qué. Se nombran las
// cinco primeras y se cuenta el resto, como en los demás rechazos de este fichero.
func motivoDelCierreIncompleto(s salidaDeCierre) string {
	detalle := make([]string, 0, 5)
	for _, r := range s.Rechazados {
		if len(detalle) == 5 {
			break
		}
		detalle = append(detalle, fmt.Sprintf("%s (%s)", r.OrderID, r.Motivo))
	}
	mensaje := fmt.Sprintf("Se guardaron %d de las %d paradas de esta hoja. %d no se "+
		"pudieron guardar: %s", len(s.Aplicados), len(s.Aplicados)+len(s.Rechazados),
		len(s.Rechazados), strings.Join(detalle, ", "))
	if len(s.Rechazados) > 5 {
		return mensaje + fmt.Sprintf(" y %d más.", len(s.Rechazados)-5)
	}
	return mensaje + "."
}

// topeCuerpoCierre: una hoja de cierre son decenas de paradas con su nota; 1 MiB sobra. Lo
// que no cabe es el intento de tumbar el proceso a base de memoria.
const topeCuerpoCierre = 1 << 20

// ---------------------------------------------------------------------------
// Piezas sueltas
// ---------------------------------------------------------------------------

// leerIdsDePedidos saca los ids TAL Y COMO VINIERON, sin quitar repetidos ni los que no
// son uuid. Se cuentan todos porque el mensaje del 409 dice «N de los M», y esa M es lo
// que la persona eligió en la pantalla.
func leerIdsDePedidos(crudo json.RawMessage) []string {
	if len(crudo) == 0 {
		return nil
	}
	var ids []string
	if err := json.Unmarshal(crudo, &ids); err != nil {
		// Lo que no sea un array de textos es «no vinieron pedidos», que es el caso del
		// contrato. No es un cuerpo inválido: es un armado sin elegir nada.
		return nil
	}
	limpios := make([]string, 0, len(ids))
	for _, id := range ids {
		if id = strings.TrimSpace(id); id != "" {
			limpios = append(limpios, id)
		}
	}
	return limpios
}

// soloUuids es lo que se le pasa a la consulta. Un id que no es uuid no puede estar en la
// base, así que no se busca; sigue contando para la M del mensaje.
//
// Y SIN REPETIDOS, que es lo que hace la base: `WHERE id = ANY('{a,a,b}')` devuelve la
// fila de `a` UNA vez. Sin quitarlos aquí, los repetidos se colaban por otra puerta — el
// peso de la ruta se sumaba dos veces y un camión al límite contestaba «supera la
// capacidad» por un pedido que iba una sola vez. El orden en que los mandó la persona se
// respeta, que es el que se usa con `optimizar:false`.
func soloUuids(ids []string) []uuid.UUID {
	salida := make([]uuid.UUID, 0, len(ids))
	visto := make(map[uuid.UUID]bool, len(ids))
	for _, texto := range ids {
		id, err := uuid.Parse(texto)
		if err != nil || visto[id] {
			continue
		}
		visto[id] = true
		salida = append(salida, id)
	}
	return salida
}

// encabezadoDelArmado es la cabecera del 409, con sus dos números.
//
// Aquí decía «ya están en otra ruta. Vuelve a elegirlos.» y ése era el literal heredado de
// delivery. Se cambia a propósito (CLAUDE.md §2, «el patrón se sigue SALVO donde se
// equivoca») porque afirmaba una causa que muchas veces no era la de verdad: el mismo
// mensaje salía para un pedido archivado, para uno sin coordenadas y para uno de otra
// sucursal. La cabecera ahora dice lo único que es cierto siempre —cuántos de los que
// elegiste no pueden ir— y el motivo de cada uno va detrás, nombrándolo.
//
// La M sigue siendo `len(orderIds)`, lo que la persona marcó en la pantalla, y no el número
// de ids distintos: es lo que tiene delante mientras lee el aviso.
//
// # EL SINGULAR — 29/09/2026
//
// Decía «1 de los 1 pedidos elegidos no pueden ir en esta ruta». Tres faltas en siete
// palabras, y salía en el caso más común de todos: elegir UN pedido y que no entre.
//
// Los dos números son la misma cuenta contada de dos maneras, así que el arreglo son dos
// concordancias distintas:
//
//   - el VERBO va con `faltan`, que es el sujeto: «1 … no PUEDE ir», «3 … no PUEDEN ir»;
//   - el SUSTANTIVO va con `pedidos`, los que la persona marcó.
//
// Y con un solo pedido elegido los dos números son el mismo, así que decirlos no informa de
// nada: se dice la frase entera sin ellos. El patrón de plural es el de la casa —`n == 1 ?
// singular : plural`, como `EnlaceDeLaRuta.cuantasParadas`—, con el cero cayendo en plural.
//
// **SE ESCRIBE IGUAL EN EL APARATO**, en `app/lib/pantallas/rutas/datos/acciones_rutas.dart`
// (`_mensajeNoPuedenIr`), porque sin señal el rechazo lo redacta él: dos redacciones del
// mismo rechazo son peor que el «1 pedidos». Lo que ata las dos es
// `docs/armado-rechazado.casos.json`, que leen esta prueba y la del aparato — no un
// comentario (`CLAUDE.md` §3-bis).
func encabezadoDelArmado(faltan, pedidos int) string {
	verbo := "no pueden ir"
	if faltan == 1 {
		verbo = "no puede ir"
	}
	if pedidos == 1 {
		return "El pedido elegido " + verbo + " en esta ruta: "
	}
	return fmt.Sprintf("%d de los %d pedidos elegidos %s en esta ruta: ", faltan, pedidos, verbo)
}

// faltanDelArmado separa lo que se pidió de lo que volvió.
//
// Devuelve los ids DISTINTOS que la consulta no trajo, en el orden en que los mandó la
// persona —un mapa en Go se recorre al azar y un mensaje que cambia de orden entre dos
// llamadas iguales no se puede comparar en una prueba ni leer en un registro—, y aparte los
// textos que ni siquiera son un identificador.
//
// Los repetidos NO cuentan como faltantes: mandar dos veces el mismo id es una lista mal
// hecha, no un conflicto, y contestarlo con un 409 mandaba a la persona a buscar una ruta
// que no existe.
func faltanDelArmado(ids []string, volvieron []sqlc.PedidosParaArmarRutaRow) ([]uuid.UUID, []string) {
	llego := make(map[uuid.UUID]bool, len(volvieron))
	for _, p := range volvieron {
		llego[p.ID] = true
	}
	var faltan []uuid.UUID
	var noSonID []string
	visto := make(map[string]bool, len(ids))
	for _, texto := range ids {
		if visto[texto] {
			continue
		}
		visto[texto] = true
		id, err := uuid.Parse(texto)
		if err != nil {
			noSonID = append(noSonID, texto)
			continue
		}
		if !llego[id] {
			faltan = append(faltan, id)
		}
	}
	return faltan, noSonID
}

// motivosDelArmado escribe POR QUÉ no entra cada uno, con su nombre y su ruta.
//
// Se nombran los cinco primeros y se cuenta el resto, igual que los otros mensajes del
// armado: quince líneas en un aviso no las lee nadie, y un número sin nombres no sirve
// para nada.
func (s *Servidor) motivosDelArmado(ctx context.Context, ar *alcance.Acotado, faltan []uuid.UUID, noSonID []string) (string, error) {
	porID := map[uuid.UUID]sqlc.PorQueNoSePuedeArmarRow{}
	if len(faltan) > 0 {
		filas, err := ar.PorQueNoSePuedeArmar(ctx, faltan)
		if err != nil {
			return "", err
		}
		for _, f := range filas {
			porID[f.ID] = f
		}
	}

	total := len(faltan) + len(noSonID)
	detalle := make([]string, 0, 5)
	apuntar := func(texto string) {
		if len(detalle) < 5 {
			detalle = append(detalle, texto)
		}
	}
	for _, id := range faltan {
		fila, hay := porID[id]
		if !hay {
			// NO EXISTE Y NO ES TUYO SON LO MISMO desde fuera, igual que en `ObtenerRuta`.
			// Decir «existe pero es de Holguín» ya es contar algo de Holguín.
			apuntar(fmt.Sprintf("%s (no existe o no es de tu sucursal)", id))
			continue
		}
		apuntar(fmt.Sprintf("%s (%s)", quienEs(fila.OperationNumber, fila.CustomerName), porQueNoSeArma(fila)))
	}
	for _, texto := range noSonID {
		apuntar(fmt.Sprintf("%s (no es un identificador de pedido)", texto))
	}

	mensaje := strings.Join(detalle, ", ")
	if total > len(detalle) {
		return mensaje + fmt.Sprintf(" y %d más.", total-len(detalle)), nil
	}
	return mensaje + ".", nil
}

// porQueNoSeArma traduce cada condición del `WHERE` de `PedidosParaArmarRuta` a algo que
// una persona pueda leer y hacer. Es la gemela de `porQueNoEsCandidato` del tablero, y se
// mantienen las dos porque las consultas son dos; lo que NO puede pasar es que una de las
// dos vuelva a meter cinco motivos en un número.
//
// EL ORDEN IMPORTA Y ES EL MISMO QUE ALLÍ:
//
//   - el entregado va PRIMERO porque conserva su `route_id`: mirando la ruta antes se le
//     contaría al logístico que «otro lo subió a un camión» cuando ese pedido ya está en
//     casa del cliente, y lo que hay que hacer es distinto.
//   - la ruta va antes que lo demás porque un pedido que ya salió puede además haberse
//     quedado sin coordenadas, y lo que importa es que el camión ya se lo llevó.
//
// Y SE NOMBRA LA RUTA. «Ya va en la ruta RT-20260922-003» dice dónde mirar; «ya va en otra
// ruta» deja quince rutas que abrir. Sin código —no debería pasar, `route_code` es NOT
// NULL— se cae a la frase de siempre en vez de enseñar un hueco.
func porQueNoSeArma(f sqlc.PorQueNoSePuedeArmarRow) string {
	switch {
	case f.DeliveredAt.Valid || (f.Resultado != nil && *f.Resultado == sqlc.StopResultEntregado):
		return "ya se entregó y no puede volver a un camión"
	case f.RouteID.Valid:
		if f.RutaCodigo != nil && *f.RutaCodigo != "" {
			return "ya va en la ruta " + *f.RutaCodigo
		}
		return "ya va en otra ruta"
	case f.Archivado:
		// El borrado blando de PEDIDO, y son la inmensa mayoría del histórico. Volver a
		// elegirlo no lo arregla: hay que desarchivarlo allí.
		return "PEDIDO lo archivó"
	case f.EndLat == nil || f.EndLng == nil:
		return "sin coordenadas de entrega"
	case f.Source == nil || *f.Source != sqlc.ProcedenciaPedido:
		return "no vino de PEDIDO"
	}
	// No debería llegar aquí: las de arriba son todas las condiciones de la consulta. Si
	// llega, se dice que no se sabe en vez de inventar un motivo — un motivo equivocado es
	// peor que ninguno, que es exactamente lo que pasó con «ya están en otra ruta».
	return "cambió mientras se armaba"
}

// quienEs es cómo se nombra un pedido en un aviso: su número de operación, que es lo que la
// persona tiene delante en la pantalla, y el cliente sólo si aquél falta.
func quienEs(operacion *string, cliente string) string {
	if operacion != nil && *operacion != "" {
		return *operacion
	}
	return cliente
}

// mensajeYaEntregados arma el 409 de los que ya se repartieron, o "" si ninguno.
//
// SE NOMBRAN UNO A UNO, como los de la factura. El «N de los M pedidos ya están en otra
// ruta» de aquí al lado NO sirve para esto y sería mentira: no están en ninguna ruta —la
// que los llevó puede haberse borrado— y «vuelve a elegirlos» es un rechazo permanente
// disfrazado de reintento, que es justo lo que el CLAUDE.md prohíbe.
func mensajeYaEntregados(pedidos []sqlc.PedidosParaArmarRutaRow) string {
	var malos []sqlc.PedidosParaArmarRutaRow
	for _, p := range pedidos {
		// Las dos columnas, que `MarcarResultadoDeParada` escribe y limpia juntas.
		if p.DeliveredAt.Valid || (p.Resultado != nil && *p.Resultado == sqlc.StopResultEntregado) {
			malos = append(malos, p)
		}
	}
	if len(malos) == 0 {
		return ""
	}
	detalle := make([]string, 0, 5)
	for _, p := range malos {
		if len(detalle) == 5 {
			break
		}
		quien := p.CustomerName
		if p.OperationNumber != nil && *p.OperationNumber != "" {
			quien = *p.OperationNumber
		}
		detalle = append(detalle, quien)
	}
	// El singular, por lo mismo que el encabezado del armado: con un pedido elegido y
	// entregado salía «1 de los pedidos elegidos YA SE ENTREGARON y no pueden volver».
	entregaron, pueden := "YA SE ENTREGARON", "no pueden"
	if len(malos) == 1 {
		entregaron, pueden = "YA SE ENTREGÓ", "no puede"
	}
	mensaje := fmt.Sprintf("%d de los pedidos elegidos %s y %s volver "+
		"a un camión: %s", len(malos), entregaron, pueden, strings.Join(detalle, ", "))
	if len(malos) > 5 {
		return mensaje + fmt.Sprintf(" y %d más.", len(malos)-5)
	}
	return mensaje + "."
}

// mensajeSinMapa arma el 409 de los pedidos cuyo destino no cae en el planeta.
//
// SE NOMBRAN, como todos los rechazos de este fichero: el logístico tiene delante una
// selección de quince tarjetas y un «no se pudo» le obliga a quitarlas de una en una para
// averiguar cuál sobra. Y se dice DÓNDE se arregla, que no es aquí: estas coordenadas las
// escribe PEDIDO y las copia el espejo, así que reintentar no cambia nada —un rechazo
// permanente disfrazado de reintento es lo que prohíbe el CLAUDE.md—.
func mensajeSinMapa(pedidos []sqlc.PedidosParaArmarRutaRow, sinMapa []uuid.UUID) string {
	malo := make(map[uuid.UUID]bool, len(sinMapa))
	for _, id := range sinMapa {
		malo[id] = true
	}
	detalle := make([]string, 0, 5)
	for _, p := range pedidos {
		if !malo[p.ID] || len(detalle) == 5 {
			continue
		}
		detalle = append(detalle, fmt.Sprintf("%s (%s, %s)", quienEs(p.OperationNumber, p.CustomerName),
			strconv.FormatFloat(valorO(p.EndLat), 'g', -1, 64),
			strconv.FormatFloat(valorO(p.EndLng), 'g', -1, 64)))
	}
	// El singular, como en los otros dos rechazos de este fichero.
	tienen, les := "tienen", "les"
	if len(sinMapa) == 1 {
		tienen, les = "tiene", "le"
	}
	mensaje := fmt.Sprintf("%d de los pedidos elegidos %s el punto de entrega fuera del mapa "+
		"y no se %s puede calcular el recorrido: %s",
		len(sinMapa), tienen, les, strings.Join(detalle, ", "))
	if len(sinMapa) > 5 {
		mensaje += fmt.Sprintf(" y %d más", len(sinMapa)-5)
	}
	return mensaje + ". Hay que corregir la dirección en PEDIDO; desde aquí no se arregla."
}

// valorO saca el float de un puntero, o 0. Sólo para escribir el número en un mensaje:
// llegar aquí con nil ya lo descarta el bucle que llama.
func valorO(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}

// mensajeNoFacturados arma el 409 de facturación, o "" si todos cuadran.
//
// Se dice CUÁLES y por qué: un «no se pudo» a secas obliga a adivinar cuál de los quince
// pedidos es el que sobra. Se nombran los cinco primeros y se cuenta el resto.
func mensajeNoFacturados(pedidos []sqlc.PedidosParaArmarRutaRow) string {
	var malos []sqlc.PedidosParaArmarRutaRow
	for _, p := range pedidos {
		// `cambiado` también es una factura válida: las líneas facturadas pueden diferir
		// de lo pedido y el número de operación sigue identificando esa factura.
		if p.FacturaEstado == nil || (*p.FacturaEstado != sqlc.FacturaEstadoIgual && *p.FacturaEstado != sqlc.FacturaEstadoCambiado) {
			malos = append(malos, p)
		}
	}
	if len(malos) == 0 {
		return ""
	}
	detalle := make([]string, 0, 5)
	for _, p := range malos {
		if len(detalle) == 5 {
			break
		}
		quien := p.CustomerName
		if p.OperationNumber != nil && *p.OperationNumber != "" {
			quien = *p.OperationNumber
		}
		detalle = append(detalle, fmt.Sprintf("%s (%s)", quien, motivoDeFactura(p.FacturaEstado)))
	}
	mensaje := fmt.Sprintf("En una ruta sólo entra lo facturado. %d no cumplen: %s",
		len(malos), strings.Join(detalle, ", "))
	if len(malos) > 5 {
		return mensaje + fmt.Sprintf(" y %d más.", len(malos)-5)
	}
	return mensaje + "."
}

// llevaDomicilio dice si este pedido va a casa del cliente.
//
// Se miran las DOS señales. `requiere_domicilio` es la casilla que alguien marcó al tomar
// el pedido; `factura_domicilio` es lo que se cobró en el mostrador, que es más fiable
// porque ya pasó por caja. Con una sola se escapan casos por los dos lados.
func llevaDomicilio(p sqlc.PedidosParaArmarRutaRow) bool {
	if p.FacturaDomicilio != nil && *p.FacturaDomicilio > 0 {
		return true
	}
	return p.RequiereDomicilio != nil && *p.RequiereDomicilio
}

// mensajeDomicilioSinCobrar identifica pedidos cuya factura no registra un importe
// positivo de domicilio. La operación visible también permite localizar el caso llamado
// «conduce» en la factura, sin introducir un estado paralelo.
func mensajeDomicilioSinCobrar(pedidos []sqlc.PedidosParaArmarRutaRow) string {
	var malos []sqlc.PedidosParaArmarRutaRow
	for _, p := range pedidos {
		if p.FacturaDomicilio == nil || *p.FacturaDomicilio <= 0 {
			malos = append(malos, p)
		}
	}
	if len(malos) == 0 {
		return ""
	}
	detalle := make([]string, 0, 5)
	for _, p := range malos {
		if len(detalle) == 5 {
			break
		}
		quien := p.CustomerName
		if p.OperationNumber != nil && strings.TrimSpace(*p.OperationNumber) != "" {
			quien = strings.TrimSpace(*p.OperationNumber)
		}
		detalle = append(detalle, quien)
	}
	mensaje := fmt.Sprintf("En una ruta sólo entra lo facturado con domicilio cobrado. %d no cumplen: %s",
		len(malos), strings.Join(detalle, ", "))
	if len(malos) > 5 {
		return mensaje + fmt.Sprintf(" y %d más.", len(malos)-5)
	}
	return mensaje + "."
}

// cuantosSinCosto cuenta los que llevan domicilio y no traen su costo.
//
// Va aparte del mensaje porque el número viaja en la respuesta y el texto es para leerlo:
// la pantalla necesita poder decir «el total no incluye 12 pedidos» sin tener que parsear
// una frase.
func cuantosSinCosto(pedidos []sqlc.PedidosParaArmarRutaRow) int {
	n := 0
	for _, p := range pedidos {
		if llevaDomicilio(p) && p.PedidoCosto == nil {
			n++
		}
	}
	return n
}

// mensajeSinCalcular bloquea pedidos sin la cotización de domicilio de Entrega e
// identifica cada uno por su número de operación visible.
func mensajeSinCalcular(pedidos []sqlc.PedidosParaArmarRutaRow) string {
	var malos []sqlc.PedidosParaArmarRutaRow
	for _, p := range pedidos {
		if p.PedidoCosto == nil {
			malos = append(malos, p)
		}
	}
	if len(malos) == 0 {
		return ""
	}
	detalle := make([]string, 0, 5)
	for _, p := range malos {
		if len(detalle) == 5 {
			break
		}
		quien := p.CustomerName
		if p.OperationNumber != nil && *p.OperationNumber != "" {
			quien = *p.OperationNumber
		}
		detalle = append(detalle, quien)
	}
	mensaje := fmt.Sprintf("No se puede crear la ruta: %d pedidos no tienen cotizado el domicilio en Entrega: %s",
		len(malos), strings.Join(detalle, ", "))
	if len(malos) > 5 {
		return mensaje + fmt.Sprintf(" y %d más.", len(malos)-5)
	}
	return mensaje + "."
}

// motivoDeFactura traduce el estado a lo que se lee en la pantalla. Un estado NULL es
// «sin cotejar», igual que cualquier otro valor inesperado: lo que no se comprobó no se
// carga, y decir «sin factura» cuando en realidad nadie la ha mirado sería mentir.
func motivoDeFactura(e *sqlc.FacturaEstado) string {
	if e == nil {
		return "sin cotejar"
	}
	switch *e {
	case sqlc.FacturaEstadoCambiado:
		return "cambió en la factura"
	case sqlc.FacturaEstadoSinFactura:
		return "sin facturar"
	}
	return "sin cotejar"
}

// costoDelPedido devuelve el `pedidoCosto` de ese pedido, que es lo que se copia a `price`.
// NO se calcula aquí ningún precio: el del domicilio lo pone la APK de Entrega.
func costoDelPedido(pedidos []sqlc.PedidosParaArmarRutaRow, id uuid.UUID) *float64 {
	for _, p := range pedidos {
		if p.ID == id {
			return p.PedidoCosto
		}
	}
	return nil
}

func idDelVehiculo(v *sqlc.ObtenerVehiculoParaCapacidadRow) pgtype.UUID {
	if v == nil {
		return pgtype.UUID{}
	}
	return pgDe(v.ID)
}

func aPgOpcional(id *uuid.UUID) pgtype.UUID {
	if id == nil {
		return pgtype.UUID{}
	}
	return pgDe(*id)
}

// sucursalDelCuerpo lee el `branchId` que manda el asistente. Un id mal escrito NO acota:
// se avisa y se sigue, que es la misma regla del alcance para una sucursal que ya no
// existe — esconder el problema devolviendo cero pedidos es lo que nadie sabe diagnosticar.
func sucursalDelCuerpo(r *http.Request, crudo string) *uuid.UUID {
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return nil
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		httpx.Registro(r).Warn("[rutas] el branchId del cuerpo no es un id: se ignora", "branchId", crudo)
		return nil
	}
	return &id
}

// fechaDeEntrega admite la fecha sola (`2026-09-14`) y la marca completa con zona. Una
// fecha que no se entiende se RECHAZA en vez de guardarse como nula: una ruta planificada
// para el día equivocado se descubre con el camión cargado.
func fechaDeEntrega(w http.ResponseWriter, r *http.Request, crudo string) (pgtype.Timestamptz, bool) {
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return pgtype.Timestamptz{}, true
	}
	for _, formato := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02T15:04:05", "2006-01-02"} {
		if t, err := time.Parse(formato, crudo); err == nil {
			return pgtype.Timestamptz{Time: t, Valid: true}, true
		}
	}
	httpx.Error(w, r, http.StatusBadRequest,
		fmt.Sprintf("La fecha de entrega '%s' no se entiende. Se espera AAAA-MM-DD", crudo))
	return pgtype.Timestamptz{}, false
}

// estadoDeRutaValido comprueba el enum antes de que lo haga Postgres: dejarlo caer hasta
// la base da un 500 con la jerga del motor dentro, y esto da un 400 que se puede leer.
func estadoDeRutaValido(w http.ResponseWriter, r *http.Request, v string) (sqlc.RouteStatus, bool) {
	switch sqlc.RouteStatus(v) {
	case sqlc.RouteStatusPlanned, sqlc.RouteStatusInProgress, sqlc.RouteStatusCompleted, sqlc.RouteStatusCancelled:
		return sqlc.RouteStatus(v), true
	}
	httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(
		"Estado de ruta no válido: '%s'. Sólo 'planned', 'in_progress', 'completed' o 'cancelled'", v))
	return "", false
}

// resultadoValido: sólo los tres del contrato.
func resultadoValido(v *string) (sqlc.StopResult, bool) {
	if v == nil {
		return "", false
	}
	switch sqlc.StopResult(*v) {
	case sqlc.StopResultEntregado, sqlc.StopResultDevuelto, sqlc.StopResultCancelado:
		return sqlc.StopResult(*v), true
	}
	return "", false
}

// valorTalCual es lo que se interpola en «resultado '<v>' desconocido». Un resultado que
// no vino sale como `undefined`, calcado de delivery: el que lee el mensaje está mirando
// el JSON que mandó, y ahí el campo no está.
func valorTalCual(v httpx.Opcional[string]) string {
	if v.Valor == nil {
		return "undefined"
	}
	return *v.Valor
}

// notaDeCierre limpia la nota: vacía es NULL, y se corta a 500. El corte va por RUNAS y no
// por bytes — cortar por bytes parte una «ñ» por la mitad y lo que queda guardado no es
// texto válido.
func notaDeCierre(v *string) *string {
	if v == nil {
		return nil
	}
	nota := strings.TrimSpace(*v)
	if nota == "" {
		return nil
	}
	if runas := []rune(nota); len(runas) > 500 {
		nota = string(runas[:500])
	}
	return &nota
}

// textoDeResultado saca el enum a texto, o null. `resultado` y `resultadoNota` son cómo
// acabó la parada: de ahí sale el post-despacho.
func textoDeResultado(v *sqlc.StopResult) *string {
	if v == nil {
		return nil
	}
	s := string(*v)
	return &s
}

// avisosDeLasParadas arma el lote de avisos de los pedidos que van EN la ruta y vienen del
// espejo: los tecleados a mano no existen ya, pero un pedido sin `externalId` no tiene a
// quién avisarle.
func (s *Servidor) avisosDeLasParadas(r *http.Request, a *alcance.Acotado, ruta uuid.UUID, estado string) []AvisoDeParada {
	paradas, err := a.ParadasDeRutas(r.Context(), []uuid.UUID{ruta})
	if err != nil {
		httpx.Registro(r).Error("no se pudieron leer las paradas para avisar a PEDIDO", "ruta", ruta, "err", err)
		return nil
	}
	cuando := horaDelSuceso(r)
	var avisos []AvisoDeParada
	for _, p := range paradas {
		if p.Source != nil && *p.Source == sqlc.ProcedenciaPedido && p.ExternalID != nil {
			avisos = append(avisos, AvisoDeParada{PedidoID: *p.ExternalID, Estado: estado, At: cuando})
		}
	}
	return avisos
}

// avisarDeFondo dispara y olvida. Lo que NO puede pasar es que no se pueda armar o
// despachar una ruta porque otra aplicación esté caída; lo que sí tiene que pasar es que
// quede en el registro cuando no sale.
func (s *Servidor) avisarDeFondo(r *http.Request, avisos []AvisoDeParada) {
	if len(avisos) == 0 {
		return
	}
	reg := httpx.Registro(r)
	// El canal se lee AQUÍ y no dentro de la goroutine: así el disparo de fondo no toca
	// el campo del servidor desde otro hilo, que es una carrera de las que sólo se ven en
	// producción y un martes.
	enviar := s.aPedido
	// El contexto de la petición muere al contestar, así que el aviso se lleva uno propio.
	go func() {
		ctx, cancelar := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancelar()
		if parte := enviar(ctx, avisos); !parte.Ok {
			reg.Warn("PEDIDO no se enteró del cambio de estado", "avisos", len(avisos), "err", parte.Error)
		}
	}()
}

// ---------------------------------------------------------------------------
// De fila de sqlc a respuesta
// ---------------------------------------------------------------------------

func deFilaDeLista(f sqlc.ListarRutasRow, paradas []ParadaSalida) RutaSalida {
	return armarRuta(datosDeRuta{
		ID: f.ID, Name: f.Name, RouteCode: f.RouteCode, Status: string(f.Status),
		OriginAddress: f.OriginAddress, OriginLat: f.OriginLat, OriginLng: f.OriginLng,
		TotalDistance: f.TotalDistance, TotalWeight: f.TotalWeight, TotalPrice: f.TotalPrice,
		ParadasSinCotizar: f.ParadasSinCotizar,
		DeliveryDate:      f.DeliveryDate, VehicleID: f.VehicleID, BranchID: f.BranchID,
		CreadoPor: f.CreadoPor, StartedAt: f.StartedAt, FinishedAt: f.FinishedAt,
		Optimized: f.Optimized, CreatedAt: f.CreatedAt, UpdatedAt: f.UpdatedAt,
		SucursalNombre: f.SucursalNombre, SucursalCodigo: f.SucursalCodigo,
		VehiculoNombre: f.VehiculoNombre, VehiculoMatricula: f.VehiculoMatricula,
		VehiculoCapacidad: f.VehiculoCapacidad, VehiculoTipo: f.VehiculoTipo,
	}, paradas)
}

func deFilaDeDetalle(f sqlc.ObtenerRutaRow, paradas []ParadaSalida) RutaSalida {
	return armarRuta(datosDeRuta{
		ID: f.ID, Name: f.Name, RouteCode: f.RouteCode, Status: string(f.Status),
		OriginAddress: f.OriginAddress, OriginLat: f.OriginLat, OriginLng: f.OriginLng,
		TotalDistance: f.TotalDistance, TotalWeight: f.TotalWeight, TotalPrice: f.TotalPrice,
		ParadasSinCotizar: f.ParadasSinCotizar,
		DeliveryDate:      f.DeliveryDate, VehicleID: f.VehicleID, BranchID: f.BranchID,
		CreadoPor: f.CreadoPor, StartedAt: f.StartedAt, FinishedAt: f.FinishedAt,
		Optimized: f.Optimized, CreatedAt: f.CreatedAt, UpdatedAt: f.UpdatedAt,
		SucursalNombre: f.SucursalNombre, SucursalCodigo: f.SucursalCodigo,
		VehiculoNombre: f.VehiculoNombre, VehiculoMatricula: f.VehiculoMatricula,
		VehiculoCapacidad: f.VehiculoCapacidad, VehiculoTipo: f.VehiculoTipo,
	}, paradas)
}

// datosDeRuta es el intermedio entre las dos filas de sqlc —lista y detalle, que traen las
// mismas columnas con distinto tipo— y la salida. Existe para no escribir dos veces el
// mismo armado y que un día se cambie sólo uno.
type datosDeRuta struct {
	ID                uuid.UUID
	Name              *string
	RouteCode         *string
	Status            string
	OriginAddress     *string
	OriginLat         *float64
	OriginLng         *float64
	TotalDistance     float64
	TotalWeight       float64
	TotalPrice        float64
	ParadasSinCotizar *int32
	DeliveryDate      pgtype.Timestamptz
	VehicleID         pgtype.UUID
	BranchID          pgtype.UUID
	CreadoPor         *string
	StartedAt         pgtype.Timestamptz
	FinishedAt        pgtype.Timestamptz
	Optimized         bool
	CreatedAt         pgtype.Timestamptz
	UpdatedAt         pgtype.Timestamptz
	SucursalNombre    *string
	SucursalCodigo    *string
	VehiculoNombre    *string
	VehiculoMatricula *string
	VehiculoCapacidad *float64
	VehiculoTipo      *string
}

func armarRuta(d datosDeRuta, paradas []ParadaSalida) RutaSalida {
	salida := RutaSalida{
		ID: d.ID, Name: d.Name, RouteCode: d.RouteCode, Status: d.Status,
		OriginAddress: d.OriginAddress, OriginLat: d.OriginLat, OriginLng: d.OriginLng,
		TotalDistance: d.TotalDistance, TotalWeight: d.TotalWeight, TotalPrice: d.TotalPrice,
		ParadasSinCotizar: d.ParadasSinCotizar,
		DeliveryDate:      hora(d.DeliveryDate), VehicleID: idOpcional(d.VehicleID),
		BranchID: idOpcional(d.BranchID), CreadoPor: d.CreadoPor,
		StartedAt: hora(d.StartedAt), FinishedAt: hora(d.FinishedAt),
		Optimized: d.Optimized, CreatedAt: hora(d.CreatedAt), UpdatedAt: hora(d.UpdatedAt),
		// Siempre lista, nunca null: ver el comentario de `Items`.
		Orders: paradas,
	}
	if salida.Orders == nil {
		salida.Orders = []ParadaSalida{}
	}
	if d.BranchID.Valid {
		salida.Branch = &SucursalDeRuta{
			ID: uuid.UUID(d.BranchID.Bytes), Name: d.SucursalNombre, ExternalID: d.SucursalCodigo,
		}
	}
	if d.VehicleID.Valid {
		salida.Vehicle = &CamionDeRuta{
			ID: uuid.UUID(d.VehicleID.Bytes), Name: d.VehiculoNombre, Type: d.VehiculoTipo,
			Plate: d.VehiculoMatricula, Capacity: d.VehiculoCapacidad,
		}
	}
	return salida
}
