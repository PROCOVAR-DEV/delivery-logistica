package api

// UN PEDIDO ENTREGADO NO SE PUEDE VOLVER A REPARTIR. NI OFRECER, NI COLOCAR, NI ARMAR.
//
// El agujero que cierran estas pruebas, y que estaba abierto de par en par el 18/09/2026:
//
//  1. Un entregado CONSERVA su `route_id` a propósito (`MarcarResultadoDeParada`), y ése
//     era el único motivo por el que no volvía a salir en ninguna lista: los seis `WHERE`
//     del reparto se apoyaban en `o.route_id IS NULL` y en NADA MÁS.
//  2. Pero la clave ajena de `orders.route_id` es `ON DELETE SET NULL`
//     (`db/migrations/00001_init.sql:446`), y borrar una ruta está permitido en CUALQUIER
//     estado: no hay ni una comprobación en `borrarRuta`. Además, el propio manejador
//     llama a `SoltarPedidosDeRuta`, cuyo `WHERE` es `route_id = $1` a secas — el
//     entregado entra de lleno.
//
// Junto: se borra la ruta de ayer y los pedidos que YA ESTÁN EN CASA DEL CLIENTE amanecen
// con `route_id` nulo. Vuelven a la mitad izquierda del tablero, vuelven a la lista del
// armador, se pueden colocar, y salen otra vez en el camión de mañana. Sin un solo error,
// sin una traza, y con una lista que se ve perfectamente normal — que es como se ven aquí
// los fallos caros.
//
// Palabras de Jose el 18/09/2026: «se hizo la ruta, se completó con esos pedidos que ya se
// entregaron, ahí se deberían de borrar esos pedidos de los tableros; creo que ahí diera
// un problema».
//
// Lo que se comprueba aquí son las CUATRO puertas por las que un pedido vuelve a un
// camión, cada una con su motivo escrito para quien lo lee:
//
//	la mitad izquierda del tablero · colocar una tarjeta · armar la ruta de una zona ·
//	armar una ruta por ids
//
// Lo que NO se puede comprobar en esta máquina: que el `WHERE` que se le añadió al SQL
// filtra de verdad en Postgres. Estas pruebas corren contra un doble que reimplementa las
// consultas, así que vigilan al MANEJADOR. Al texto de las consultas lo vigila
// `internal/store/guardas_del_reparto_test.go`, que es lo único que se puede hacer sin
// base de datos delante.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// pedEntregado es el pedido de Santiago que ya se repartió Y cuya ruta se borró: sin
// `route_id` y con `delivered_at`. Es exactamente la fila que deja en la base un
// `DELETE /api/routes/{id}` sobre la ruta de ayer.
var pedEntregado = uuid.MustParse("0d000000-0000-0000-0000-0000000000e1")

// conUnEntregadoSuelto deja el tablero de siempre más ese pedido.
func conUnEntregadoSuelto() *tableroFalso {
	q := nuevoTablero()
	igual := sqlc.FacturaEstadoIgual
	q.pedidos[pedEntregado] = pedidoFalso{
		id: pedEntregado, sucursal: sucStg, nombre: "Ya se entregó", folio: "X-3001",
		peso: 12, lat: 20.025, lng: -75.82, factura: &igual,
		ruta:      nil,  // la ruta se borró: `ON DELETE SET NULL`
		entregado: true, // pero esto no se borra nunca
	}
	return q
}

// ---------------------------------------------------------------------------
// 1. La mitad izquierda del tablero
// ---------------------------------------------------------------------------

// NO SE OFRECE, NI EN LA LISTA NI EN EL NÚMERO DE ENCIMA.
//
// Los dos a la vez y en la misma prueba: el 17/09/2026 se separaron —a la lista le
// pusieron `AND NOT o.archivado` y al contador no— y el tablero de La Habana dijo «Sin
// colocar (722)» encima de una lista de 293 durante tres días.
func TestUnPedidoEntregadoNoVuelveALaMitadIzquierdaDelTablero(t *testing.T) {
	q := conUnEntregadoSuelto()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet, "/api/board/unplaced", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var izq MitadIzquierda
	if err := json.Unmarshal(w.Body.Bytes(), &izq); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}

	for _, p := range izq.Pedidos {
		if p.ID == pedEntregado {
			t.Fatalf("un pedido YA ENTREGADO se le está ofreciendo al logístico para "+
				"colocarlo en una zona: lo prepararía otra vez y saldría en el camión de "+
				"mañana con mercancía que ya está en casa del cliente.\n"+
				"Llega aquí solo: borrar la ruta en la que viajó le pone `route_id` a NULL "+
				"(ON DELETE SET NULL, db/migrations/00001_init.sql:446), y `route_id IS "+
				"NULL` era todo lo que miraba este WHERE.\nLista: %s", w.Body.String())
		}
	}
	// Y el número de encima cuenta lo mismo que la lista.
	if int(izq.Total) != len(izq.Pedidos) {
		t.Fatalf("el contador dice %d encima de una lista de %d: uno de los dos se dejó "+
			"fuera al entregado. Es el «Sin colocar (722) encima de una lista de 293» "+
			"otra vez.", izq.Total, len(izq.Pedidos))
	}
}

// ---------------------------------------------------------------------------
// 2. Colocar la tarjeta
// ---------------------------------------------------------------------------

// COLOCAR UN ENTREGADO ES UN 409 CON SU MOTIVO, y no el 409 del de al lado.
//
// Las dos mitades importan. El código —409 y no 404 ni 500— porque el tablero sube en
// LOTES que se reintentan: un 500 corta el lote entero y un 404 dice que el pedido no
// existe, que es mentira. Y el texto, porque en la web «lo que el servidor rechaza se dice
// con su motivo literal» (§3-quinquies del CLAUDE.md): «ya está en una ruta» se arregla
// solo cuando esa ruta se cierre, «ya se entregó» no se arregla nunca.
func TestColocarUnPedidoYaEntregadoEs409ConSuMotivo(t *testing.T) {
	q := conUnEntregadoSuelto()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+pedEntregado.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colCentro.String()+`","posicion":1}`)

	if w.Code == http.StatusOK {
		t.Fatalf("SE COLOCÓ UN PEDIDO QUE YA SE ENTREGÓ. Esa tarjeta arma la ruta de "+
			"mañana y el pedido se reparte dos veces: %s", w.Body.String())
	}
	if w.Code == http.StatusInternalServerError {
		t.Fatalf("un 500 corta el lote entero del aparato que sube lo que hizo sin red: %s",
			w.Body.String())
	}
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	if got := leerTab(t, w)["error"]; got != msgYaSeEntrego {
		t.Fatalf("el motivo es %q y tenía que ser %q. Con %q quien lo lee se queda "+
			"esperando a que se cierre una ruta que puede que ni exista.",
			got, msgYaSeEntrego, msgYaVaEnUnaRuta)
	}
	if _, puesto := q.colocadas[pedEntregado]; puesto {
		t.Fatal("se contestó 409 pero la tarjeta quedó puesta igual")
	}
}

// ---------------------------------------------------------------------------
// 3. Armar la ruta de una zona
// ---------------------------------------------------------------------------

// LA TARJETA ENTREGADA NO SUBE AL CAMIÓN, Y SE NOMBRA.
//
// No bloquea la zona —«los avisos del armador son aviso, no bloqueo»—: la ruta sale con
// las demás y la tarjeta entregada aparece en `descartados` con su motivo y con lo que hay
// que hacer con ella. Un 409 entero aquí dejaría al logístico sin poder armar nada y sin
// saber cuál de las doce tarjetas es la que sobra.
func TestUnaTarjetaEntregadaNoSubeAOtroCamionYSeNombra(t *testing.T) {
	q := conUnEntregadoSuelto()
	q.tresPuestas()
	q.capacidad = 1000
	q.colocadas[pedEntregado] = colocacion{colCentro, 4}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d, se esperaba 201: una tarjeta entregada no puede dejar la zona "+
			"entera sin poder salir — %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["paradas"].(float64); n != 3 {
		t.Fatalf("paradas %v, se esperaban 3: si son 4, el pedido YA ENTREGADO se subió "+
			"otra vez al camión — %s", m["paradas"], w.Body.String())
	}
	for _, id := range q.enganchados {
		if id == pedEntregado {
			t.Fatalf("el pedido ya entregado se enganchó a la ruta nueva: %v", q.enganchados)
		}
	}

	d := descartadoPorNombre(t, m, "Ya se entregó")
	if d["motivo"] != "ya se entregó" {
		t.Errorf("el motivo es %q y tenía que decir que ya se entregó. Con «ya va en otra "+
			"ruta» el logístico va a buscar un camión que no existe: esa ruta se borró, "+
			"que es justo por lo que el pedido volvió a aparecer aquí.", d["motivo"])
	}
	que, _ := d["queHacer"].(string)
	if !strings.Contains(que, "dos veces") {
		t.Errorf("no se dice qué pasa si se vuelve a subir, que es lo único que importa "+
			"de este descarte: %q", que)
	}
	if d["operationNumber"] != "X-3001" {
		t.Errorf("no se nombra el folio de la tarjeta y hay que poder encontrarla: %v", d)
	}
}

// ---------------------------------------------------------------------------
// 4. Armar una ruta por ids  (POST /api/routes)
// ---------------------------------------------------------------------------

// POR IDS TAMPOCO, Y CON EL MOTIVO DE VERDAD.
//
// Ésta es la puerta del armador de siempre, la que no pasa por el tablero. El mensaje NO
// puede ser el «N de los M pedidos ya están en otra ruta» de al lado: sería falso —no
// están en ninguna ruta, se entregaron— y «vuelve a elegirlos» es un rechazo permanente
// disfrazado de reintento, exactamente el fallo que se arregló el 18/09/2026 en el tablero.
func TestArmarUnaRutaConUnPedidoYaEntregadoEs409QueLoNombra(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)

	// El pedido ENTREGADO Y SUELTO, que es la fila de la que va todo esto: `resultado` y
	// `delivered_at` puestos, `route_id` a nil.
	//
	// Se siembra en vez de llegar aquí borrando la ruta, porque desde el 18/09/2026 eso ya
	// no se puede —`borrarRuta` se niega con un 409 en cuanto hay una parada cerrada, ver
	// `TestNoSeBorraUnaRutaQueYaTieneResultados`—. Pero la fila SIGUE SIENDO ALCANZABLE: la
	// dejan así las rutas que se borraron antes de que existiera aquella guarda, y la
	// dejaría cualquier camino nuevo que toque `route_id`. Que la puerta de delante esté
	// cerrada no es motivo para dejar de mirar quién entra.
	entregado := d.pedidos[stg[0]]
	ahora := time.Now().Add(-20 * time.Hour)
	resultado := sqlc.StopResultEntregado
	entregado.resultado = &resultado
	entregado.entregadoEn = &ahora
	entregado.estado = sqlc.OrderStatusDelivered
	entregado.rutaID = nil
	entregado.ultimaRuta = nil // la clave ajena es ON DELETE SET NULL: se lo llevó también

	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmado(camionStg.String(), stg[0], stg[2]))

	if w.Code == http.StatusCreated {
		t.Fatalf("SE ARMÓ UNA RUTA CON UN PEDIDO YA ENTREGADO. El camión sale con "+
			"mercancía que está en casa del cliente desde ayer: %s", w.Body.String())
	}
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	motivo := errorDeRutas(t, w)
	// «YA SE ENTREGÓ» porque aquí se cae UNO solo; con dos o más dice «YA SE ENTREGARON».
	// Se mira el trozo común para no atar esta prueba a la concordancia, que ya tiene la
	// suya en `armado_rechazado_casos_compartidos_test.go`; lo que se comprueba aquí es que
	// el motivo que se da es ÉSE y no «ya va en otra ruta».
	if !strings.Contains(motivo, "YA SE ENTREG") {
		t.Errorf("el rechazo no dice que ya se entregó: %q", motivo)
	}
	if !strings.Contains(motivo, "X-Lejos") {
		t.Errorf("no se nombra CUÁL de los dos pedidos es: %q", motivo)
	}
	if strings.Contains(motivo, "ya están en otra ruta") || strings.Contains(motivo, "Vuelve a elegirlos") {
		t.Errorf("se le echa la culpa a «otra ruta» y se manda reintentar algo que no "+
			"tiene arreglo. Ese pedido no está en ninguna ruta: se entregó. %q", motivo)
	}
	// Y no se creó nada a medias.
	if len(d.rutas) != 0 {
		t.Fatalf("se rechazó pero quedó una ruta creada: %+v", d.rutas)
	}
	if p := d.pedidos[stg[2]]; p.rutaID != nil {
		t.Fatalf("%s se enganchó a una ruta que no llegó a existir", p.cliente)
	}
}

// ---------------------------------------------------------------------------
// 5. Y la puerta de delante: una ruta cerrada no se borra
// ---------------------------------------------------------------------------

// BORRAR UNA RUTA CON RESULTADOS ES UN 409, Y NO SE TOCA NADA.
//
// Es el camino por el que el entregado volvía al montón, y tiene dos daños, no uno:
//
//  1. `SoltarPedidosDeRuta` filtra por `route_id = $1` a secas y el entregado conserva el
//     suyo, así que baja del camión con los demás — y aunque no bajara, la clave ajena es
//     `ON DELETE SET NULL`.
//  2. Se pierde la HOJA de lo que bajó del camión: `ultima_ruta_id` también es `ON DELETE
//     SET NULL`, por mucho que el esquema prometa en su comentario que «esto no se libera
//     nunca». Con la fila de `routes` se van además el código de ruta, la fecha y el
//     camión. Y el cierre que suba el teléfono cuando vuelva la señal recibe un 404, que
//     el sincronizador anota como `rechazado` y por contrato no se reintenta.
//
// Una ruta ARMADA POR ERROR se sigue borrando igual: lo vigila
// `TestBorrarLaRutaSueltaLosPedidosPeroNoSuPasado`, que es el mismo camino sin resultados.
func TestNoSeBorraUnaRutaCompletadaConResultados(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[0], stg[1])
	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[0])
	if w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo); w.Code != http.StatusOK {
		t.Fatalf("no se pudo cerrar la parada: %s", w.Body.String())
	}

	d.rutas[id].estado = sqlc.RouteStatusCompleted
	d.camiones[camionStg].estado = sqlc.VehicleStatusInUse

	w := llamarRutas(t, h, http.MethodDelete, "/api/routes/"+id.String(), jwt, "")

	if w.Code == http.StatusOK {
		t.Fatalf("SE BORRÓ UNA RUTA CON UNA ENTREGA DENTRO. El pedido entregado vuelve a "+
			"la lista de disponibles, la hoja de lo que bajó del camión desaparece y el "+
			"cierre que falte por subir ya no tiene dónde ir: %s", w.Body.String())
	}
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	motivo := errorDeRutas(t, w)
	if motivo != msgRutaCompletada {
		t.Errorf("el rechazo no explica el histórico completado: %q", motivo)
	}

	// Y NO SE TOCÓ NADA. El 409 se contesta ANTES de la transacción, así que ni el camión
	// se liberó ni los pedidos bajaron: un portazo a medias sería peor que no ponerlo.
	if _, sigue := d.rutas[id]; !sigue {
		t.Fatal("se contestó 409 y la ruta se borró igual")
	}
	for _, i := range []int{0, 1} {
		p := d.pedidos[stg[i]]
		if p.rutaID == nil || *p.rutaID != id {
			t.Fatalf("%s bajó del camión aunque el borrado se rechazó", p.cliente)
		}
		if p.ultimaRuta == nil {
			t.Fatalf("%s perdió la hoja de en qué camión viajó", p.cliente)
		}
	}
	if d.camiones[camionStg].estado == sqlc.VehicleStatusAvailable && d.rutas[id].estado != sqlc.RouteStatusPlanned {
		t.Fatal("se liberó el camión de una ruta que no se llegó a borrar")
	}
}
