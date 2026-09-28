package api

// QUITAR LA MARCA DE UNA PARADA — 28/09/2026.
//
// Jose: «desmarco el estado de cierre y no se guarda cuando salgo por q razon».
//
// En la hoja de cierre, pulsar dos veces el mismo botón DESMARCA: es como se corrige un
// dedazo, y estaba puesto desde el principio. Lo que no existía era el camino de vuelta —
// el aparato sólo mandaba las paradas CON resultado, así que quitar la marca no producía
// ningún apunte, y en este lado un `"resultado": null` era indistinguible de «no vino el
// campo» porque el cuerpo lo leía como `*string`.
//
// LAS PRUEBAS VAN EN PAREJA, y aquí la pareja es la que separa los DOS nulos:
//
//   · `"resultado": null` EXPLÍCITO → se quita la marca;
//   · el campo AUSENTE              → sigue siendo un cuerpo mal formado y se rechaza.
//
// Sin la segunda, leer «ausente» como «bórralo» convertiría cualquier entrada mal escrita
// en un borrado silencioso de trabajo real, que es el fallo contrario y más caro.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

func cerrarUnaVez(t *testing.T, h http.Handler, jwt string, ruta uuid.UUID, cuerpo string) (int, salidaDeCierre) {
	t.Helper()
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+ruta.String()+"/results", jwt, cuerpo)
	var s salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
		t.Fatalf("respuesta ilegible (%d): %s", w.Code, w.Body.String())
	}
	return w.Code, s
}

// UN ENTREGADO SE DESMARCA Y VUELVE A ESTAR SIN MARCAR.
func TestDesmarcarUnEntregadoLoDejaSinMarcar(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	pedido := stg[1]
	id := armarRutaDePrueba(t, h, jwt, pedido)

	// Se marca...
	if codigo, _ := cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, pedido)); codigo != http.StatusOK {
		t.Fatalf("la marca no entró: %d", codigo)
	}
	if p := d.pedidos[pedido]; p.resultado == nil {
		t.Fatal("la marca no se guardó: esta prueba no probaría nada")
	}

	// ...y se quita.
	codigo, salida := cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":null}]}`, pedido))
	if codigo != http.StatusOK {
		t.Fatalf("código %d al desmarcar: %+v", codigo, salida)
	}
	if len(salida.Aplicados) != 1 || len(salida.Rechazados) != 0 {
		t.Fatalf("el desmarcado no se aplicó: %+v", salida)
	}
	// EN EL ACUSE VA CON `resultado: null`: lo que se hizo fue dejarla sin marcar, y eso
	// no es un resultado.
	if salida.Aplicados[0].Resultado != nil {
		t.Errorf("el acuse dice que se aplicó el resultado %q sobre un desmarcado",
			*salida.Aplicados[0].Resultado)
	}

	p := d.pedidos[pedido]
	if p.resultado != nil {
		t.Errorf("la marca sigue puesta: %v — es justo lo que veía Jose al volver a abrir "+
			"la hoja de cierre", *p.resultado)
	}
	if p.resultadoAt != nil || p.nota != nil {
		t.Errorf("quedó la hora o la nota de una marca que ya no existe: %v / %v",
			p.resultadoAt, p.nota)
	}
	// LA HORA DE ENTREGA SE VA CON ELLA. Si no, la parada se queda sin resultado pero con
	// `delivered_at`, y la lista la pinta «entregada»: la contradicción del 2 de
	// septiembre, al revés.
	if p.entregadoEn != nil {
		t.Error("quedó la hora de entrega sobre una parada sin marcar: se pintaría «entregada»")
	}
	if p.estado != sqlc.OrderStatusPending {
		t.Errorf("el estado quedó en %q y tenía que volver a pendiente", p.estado)
	}
}

// UN DEVUELTO DESMARCADO VUELVE AL CAMIÓN. Es la parte que no es obvia y la que más duele.
//
// Un devuelto SUELTA su `route_id` al marcarse —baja del camión y vuelve a la lista de
// disponibles para mañana—. Si al desmarcarlo no se le devuelve, el pedido se queda fuera
// de su propia ruta con la ruta todavía abierta: la zona lo vuelve a coger y sale un
// SEGUNDO camión con el mismo bulto.
func TestDesmarcarUnDevueltoLoDevuelveASuRuta(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	pedido := stg[1]
	id := armarRutaDePrueba(t, h, jwt, pedido)

	cerrarUnaVez(t, h, jwt, id, fmt.Sprintf(
		`{"resultados":[{"orderId":%q,"resultado":"devuelto","nota":"no estaba"}]}`, pedido))
	if d.pedidos[pedido].rutaID != nil {
		t.Fatal("un devuelto tiene que soltar su ruta: esta prueba no probaría nada")
	}

	codigo, salida := cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":null}]}`, pedido))
	if codigo != http.StatusOK || len(salida.Aplicados) != 1 {
		t.Fatalf("el desmarcado no se aplicó: %d %+v", codigo, salida)
	}

	p := d.pedidos[pedido]
	if p.rutaID == nil || *p.rutaID != id {
		t.Fatalf("el devuelto desmarcado se quedó FUERA de su ruta (%v): vuelve a la lista "+
			"de disponibles con la ruta abierta y sale en dos camiones", p.rutaID)
	}
	// Y la hoja de lo que subió al camión no se toca nunca.
	if p.ultimaRuta == nil || *p.ultimaRuta != id {
		t.Fatal("se perdió `ultima_ruta_id`: el pedido desaparece de la hoja de cierre")
	}
	if p.nota != nil {
		t.Error("quedó el motivo de una devolución que ya no consta")
	}
}

// Y LA OTRA MITAD: el campo AUSENTE sigue siendo un cuerpo mal formado.
//
// `null` y «no vino» decodifican los dos a `nil` con un `*string`, y confundirlos es
// convertir cualquier entrada mal escrita en un borrado silencioso. Por eso el cuerpo lo
// lee `httpx.Opcional`, que sí los distingue.
func TestSinCampoResultadoSigueSiendoUnRechazo(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	pedido := stg[1]
	id := armarRutaDePrueba(t, h, jwt, pedido)

	cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, pedido))

	_, salida := cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"nota":"sin resultado"}]}`, pedido))

	if len(salida.Rechazados) != 1 {
		t.Fatalf("una entrada sin `resultado` tiene que rechazarse, no borrar la marca: %+v",
			salida)
	}
	if salida.Rechazados[0].Motivo != "resultado 'undefined' desconocido" {
		t.Errorf("el motivo cambió: %q", salida.Rechazados[0].Motivo)
	}
	// Y LA MARCA SIGUE PUESTA. Ésta es la mitad que importa: un cuerpo mal escrito no
	// puede borrar trabajo de verdad.
	if p := d.pedidos[pedido]; p.resultado == nil {
		t.Fatal("un cuerpo sin `resultado` borró la marca: leer «ausente» como «bórralo» " +
			"es el fallo contrario y más caro")
	}
}

// UN RESULTADO DESCONOCIDO SIGUE SIENDO UN RECHAZO, no un desmarcado.
func TestUnResultadoRaroNoDesmarca(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	pedido := stg[1]
	id := armarRutaDePrueba(t, h, jwt, pedido)

	cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, pedido))
	_, salida := cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"quiensabe"}]}`, pedido))

	if len(salida.Rechazados) != 1 || salida.Rechazados[0].Motivo != "resultado 'quiensabe' desconocido" {
		t.Fatalf("un resultado desconocido tiene que rechazarse con su valor: %+v", salida)
	}
	if p := d.pedidos[pedido]; p.resultado == nil {
		t.Fatal("un resultado desconocido borró la marca")
	}
}

// DESMARCAR UNA PARADA QUE NO VA EN ESTA RUTA se rechaza igual que marcarla.
func TestDesmarcarUnaParadaAjenaSeRechaza(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	// `stg[2]` no viajó en esa ruta.
	_, salida := cerrarUnaVez(t, h, jwt, id,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":null}]}`, stg[2]))

	if len(salida.Rechazados) != 1 || len(salida.Aplicados) != 0 {
		t.Fatalf("una parada ajena tiene que rechazarse también al desmarcar: %+v", salida)
	}
}
