package api

// EL 409 DEL CIERRE NOMBRA CADA PARADA POR SU NÚMERO DE OPERACIÓN — 08/10/2026 (I-3).
//
// El 07/10/2026 a Amado le llegó «… 1 no se pudieron guardar: 8cb90608-76da-4fae-879d-126ff9ab4c3c
// (ese pedido no va en esta ruta)». Un UUID no le dice a nadie de qué pedido se habla; el
// número de operación (el conduce) es el que tiene en la factura. Cada elemento de
// `rechazados[]` gana `numeroOperacion` (string SIEMPRE presente) y el texto de `error` lo usa,
// con el `orderId` como ÚLTIMO recurso.
//
// EN PAREJA: el pedido de la misma sucursal se nombra por su número; el de OTRA sucursal NO
// (se lee con alcance: no se cuenta el conduce de otra oficina por el mensaje de error) y
// cae al id que mandó el propio cliente.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
)

func TestElCierreNombraLasRechazadasPorSuConduce(t *testing.T) {
	d, stg, ajeno := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1]) // «Cerca» va en la ruta; «Lejos» y «Medio» no.

	cuerpo := fmt.Sprintf(`{"resultados":[`+
		`{"orderId":%q,"resultado":"entregado"},`+ // buena
		`{"orderId":%q,"resultado":"entregado"},`+ // de la misma sucursal, no va en la ruta
		`{"orderId":%q,"resultado":"entregado"},`+ // de OTRA sucursal
		`{"orderId":"no-es-un-id","resultado":"entregado"},`+ // basura
		`{"orderId":%q,"resultado":"volando"}`+ // va en la ruta pero el resultado no existe
		`]}`, stg[1], stg[0], ajeno, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatal(err)
	}
	if len(salida.Rechazados) != 4 {
		t.Fatalf("rechazados: %+v", salida.Rechazados)
	}
	esperado := []struct{ orderID, numero string }{
		{stg[0].String(), "X-Lejos"}, // de la misma sucursal: lee con alcance
		{ajeno.String(), ""},         // de otra: NO se cuenta su conduce
		{"no-es-un-id", ""},          // basura: no es un id
		{stg[1].String(), "X-Cerca"}, // en la hoja: sale de la propia transacción
	}
	// El orden de `rechazados` es el de la hoja que mandó el aparato.
	for i, e := range esperado {
		got := salida.Rechazados[i]
		if got.OrderID != e.orderID || got.NumeroOperacion != e.numero {
			t.Errorf("rechazados[%d] = %+v, se esperaba orderId=%q numeroOperacion=%q", i, got, e.orderID, e.numero)
		}
	}

	// EL TEXTO: conduce donde lo hay, el id que mandó el cliente donde no.
	for _, quiero := range []string{"X-Lejos (" + msgParadaAjena + ")", "X-Cerca (resultado 'volando' desconocido)",
		ajeno.String() + " (" + msgParadaAjena + ")", "no-es-un-id (" + msgParadaAjena + ")"} {
		if !strings.Contains(salida.Error, quiero) {
			t.Errorf("el error no dice %q: %q", quiero, salida.Error)
		}
	}
	if strings.Contains(salida.Error, stg[0].String()) {
		t.Errorf("el pedido con conduce se nombró por su UUID: %q", salida.Error)
	}
	// Y LA FUGA que no puede haber: el conduce del pedido de Holguín no sale por ningún lado.
	if strings.Contains(w.Body.String(), "X-Ajeno") {
		t.Fatalf("el número de operación de OTRA sucursal salió en la respuesta: %s", w.Body.String())
	}

	// La clave está SIEMPRE y es texto (no `null`), también cuando no hay número.
	var crudo struct {
		Rechazados []map[string]any `json:"rechazados"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &crudo)
	for i, rc := range crudo.Rechazados {
		if v, hay := rc["numeroOperacion"]; !hay {
			t.Errorf("rechazados[%d] no lleva `numeroOperacion`: %v", i, rc)
		} else if _, esTexto := v.(string); !esTexto {
			t.Errorf("rechazados[%d].numeroOperacion tiene que ser texto y es %T", i, v)
		}
	}
}

// Un pedido SIN número de operación se nombra por su id y la clave sale vacía; y un
// `orderId` kilométrico no vuelve entero en el texto.
func TestElCierreSinConduceCaeAlIdYRecortaLaBasura(t *testing.T) {
	d, stg, _ := datosDeReparto()
	d.pedidos[stg[0]].operacion = nil
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	kilometrico := strings.Repeat("x", 5000)
	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"},{"orderId":%q,"resultado":"entregado"}]}`,
		stg[0], kilometrico)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida salidaDeCierre
	_ = json.Unmarshal(w.Body.Bytes(), &salida)
	if !strings.Contains(salida.Error, stg[0].String()+" ("+msgParadaAjena+")") {
		t.Errorf("sin número, el último recurso es el id: %q", salida.Error)
	}
	if strings.Contains(salida.Error, strings.Repeat("x", 100)) || !strings.Contains(salida.Error, strings.Repeat("x", 64)+"…") {
		t.Errorf("el orderId crudo tiene que salir recortado a 64 caracteres: %.200q", salida.Error)
	}
	if len(salida.Error) > 600 {
		t.Errorf("el texto del error no puede crecer con la basura del cliente: %d bytes", len(salida.Error))
	}
	if !strings.Contains(w.Body.String(), `"numeroOperacion":""`) {
		t.Errorf("la clave tiene que salir vacía, no ausente ni null: %s", w.Body.String())
	}
}
