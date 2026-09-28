package api

// LA CABECERA DE LA RUTA TIENE QUE DECIR LO MISMO QUE SUS PARADAS — 28/09/2026.
//
// Medido en la APK 1.0.13 de un SM-A165M: `RT-20260928-003`, dos pedidos del MISMO cliente
// y la MISMA dirección, cabecera «420 kg» encima de dos paradas de 419,7 y 96,8 kg. 516,5
// contra 420: justo el peso de la primera.
//
// Y sólo fallaba el peso, porque el peso es el ÚNICO número de esa cabecera que sale de la
// columna guardada (`routes.total_weight`); el importe y la carga los suma la pantalla de
// las paradas. Un total guardado que nadie contrasta con su detalle es el §3-bis del
// `CLAUDE.md`, y se ata con una prueba, no con un comentario.
//
// Con clientes DISTINTOS salía bien, así que el acotamiento es la pista: lo que tienen dos
// pedidos del mismo cliente en la misma dirección es **el mismo punto de entrega**.

import (
	"net/http"
	"testing"

	"github.com/google/uuid"
)

// pedMismoA y pedMismoB son los dos pedidos del mismo cliente, en la misma dirección y por
// tanto en el MISMO punto: es lo único que los diferencia del caso que ya funcionaba.
var (
	pedMismoA = uuid.MustParse("0d000000-0000-0000-0000-0000000000a1")
	pedMismoB = uuid.MustParse("0d000000-0000-0000-0000-0000000000a2")
)

// dosDelMismoCliente deja en Centro dos pedidos del mismo cliente y el mismo punto.
func dosDelMismoCliente(q *tableroFalso) {
	igual := q.pedidos[ped1].factura
	q.pedidos[pedMismoA] = pedidoFalso{
		id: pedMismoA, sucursal: sucStg, nombre: "KIOSKO HABANA CLUB OMAR JIMENEZ MONTOYA L2",
		folio: "POR26-260927-3733", peso: 419.7, lat: 20.02, lng: -75.82, factura: igual,
	}
	q.pedidos[pedMismoB] = pedidoFalso{
		id: pedMismoB, sucursal: sucStg, nombre: "KIOSKO HABANA CLUB OMAR JIMENEZ MONTOYA L2",
		folio: "POR26-260925-3700", peso: 96.8, lat: 20.02, lng: -75.82, factura: igual,
	}
	q.colocadas[pedMismoA] = colocacion{colCentro, 1}
	q.colocadas[pedMismoB] = colocacion{colCentro, 2}
}

// pesoDeLoEnganchado suma el peso de los pedidos que de verdad subieron al camión. Es la
// cuenta de «Ver paradas», hecha sobre lo que el manejador enganchó.
func pesoDeLoEnganchado(q *tableroFalso) float64 {
	peso := 0.0
	for _, id := range q.enganchados {
		peso += q.pedidos[id].peso
	}
	return peso
}

// El peso guardado es el de TODAS las paradas, también cuando dos son del mismo cliente.
func TestElPesoDeLaRutaCuentaLosDosPedidosDelMismoCliente(t *testing.T) {
	q := nuevoTablero()
	dosDelMismoCliente(q)
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if len(q.enganchados) != 2 {
		t.Fatalf("no subieron los dos pedidos al camión: %v", q.enganchados)
	}
	if q.totales == nil {
		t.Fatal("no se fijaron los totales de la ruta")
	}
	// LA CABECERA CONTRA SUS PARADAS: son dos preguntas sobre lo mismo (§3-bis).
	if paradas := pesoDeLoEnganchado(q); q.totales.TotalWeight != paradas {
		t.Fatalf("la cabecera dice %.1f kg y sus paradas suman %.1f kg: "+
			"dos pedidos del mismo cliente cuentan como uno y el camión parece "+
			"más vacío de lo que sale", q.totales.TotalWeight, paradas)
	}
	if m := leerTab(t, w); m["totalWeight"] != 516.5 {
		t.Fatalf("la respuesta dice %v kg y tienen que ser 516.5", m["totalWeight"])
	}
}
