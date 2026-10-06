package api

// EL CIERRE SE APLICA DOS VECES Y TIENE QUE DAR LO MISMO.
//
// No es un caso raro: es el caso NORMAL. Una hoja de cierre se marca en el patio, sin
// señal, y sube cuando la hay. Si el servidor guardó y la conexión se cortó antes de
// contestar, el aparato no sabe si llegó y la vuelve a mandar — eso está escrito en
// `docs/sincronizacion.md` («Una subida a medias reintenta»), y el sincronizador sólo
// puede reconocer el repetido cuando el apunte lleva su `clave`. Todo lo que entre por
// `/api` sin pasar por `/sync` —la web, un reintento a mano, una hoja cerrada desde el
// navegador— llega aquí tal cual, dos veces.
//
// Lo que no puede pasar, en palabras de lo que se juega:
//
//   - que la segunda vez CONTESTE QUE NO. El aparato marcaría el apunte como `rechazado`,
//     que por contrato «no se reintenta y no se borra», y el cierre de esa ruta se quedaría
//     a la vista de una persona para siempre pidiendo una decisión que no existe.
//   - que la segunda vez REVIENTE EL LOTE. Un 500 corta la subida entera, y detrás de esa
//     hoja va el resto del día.
//   - que cuente DOS ENTREGAS. Dos paradas donde hubo una, dos avisos contados como dos
//     repartos, un pedido que baja dos veces del camión.
//
// LO QUE ESTAS PRUEBAS NO TAPAN, y va en el informe del 18/09/2026: `MarcarResultadoDeParada`
// escribe `delivered_at = now()`, la hora del SERVIDOR. La hora del aparato llega en
// `X-Hecho-At`, `horaDelSuceso` la lee y viaja al aviso de PEDIDO, pero a la columna de la
// base no llega. Consecuencia doble: lo entregado a las cuatro y subido a las siete queda
// grabado a las siete, y un lote reaplicado MUEVE la hora de entrega a la del reintento.
// El arreglo es pasarle `hecho_at` a la consulta; se deja fuera a propósito porque cambia
// la firma de la consulta más delicada del reparto y eso no se hace con el servidor en uso.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"strings"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// cerrarDosVeces manda la misma hoja dos veces y devuelve las dos respuestas.
func cerrarDosVeces(t *testing.T, h http.Handler, jwt string, ruta uuid.UUID, cuerpo string) (salidaDeCierre, salidaDeCierre) {
	t.Helper()
	leer := func() salidaDeCierre {
		w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+ruta.String()+"/results", jwt, cuerpo)
		if w.Code != http.StatusOK {
			t.Fatalf("el cierre contestó %d: un lote que se reintenta no puede empezar a "+
				"fallar, y un rechazo aquí se queda pegado en el aparato para siempre — %s",
				w.Code, w.Body.String())
		}
		var s salidaDeCierre
		if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
			t.Fatalf("respuesta ilegible: %v", err)
		}
		return s
	}
	return leer(), leer()
}

// LA MISMA HOJA DOS VECES: las dos veces se aplica y el pedido queda igual.
func TestLaMismaHojaDeCierreDosVecesNoCuentaDosEntregas(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	entregado, devuelto := stg[1], stg[2]
	id := armarRutaDePrueba(t, h, jwt, entregado, devuelto)

	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":%q,"resultado":"devuelto","nota":"el cliente no estaba"}
	]}`, entregado, devuelto)
	primera, segunda := cerrarDosVeces(t, h, jwt, id, cuerpo)

	// LAS DOS SE APLICAN. La segunda NO se rechaza: un `rechazado` no se reintenta y no se
	// borra, así que el cierre de esa ruta se quedaría clavado en la pantalla del aparato
	// pidiendo que alguien decida algo sobre un trabajo que ya está hecho.
	if len(primera.Aplicados) != 2 || len(primera.Rechazados) != 0 {
		t.Fatalf("la primera vuelta ya no cuadra: %+v", primera)
	}
	if len(segunda.Rechazados) != 0 {
		t.Fatalf("la segunda vuelta RECHAZA lo que ya había aplicado: %+v.\n"+
			"Un lote que se reintenta es lo normal cuando vuelve la señal, y un rechazo "+
			"aquí no se reintenta ni se borra: se queda a la vista de una persona para "+
			"siempre.", segunda.Rechazados)
	}
	if len(segunda.Aplicados) != 2 {
		t.Fatalf("la segunda vuelta aplicó %d de 2: %+v", len(segunda.Aplicados), segunda)
	}

	// Y EL PEDIDO QUEDA IGUAL QUE DESPUÉS DE LA PRIMERA. Una entrega, no dos.
	e := d.pedidos[entregado]
	if e.resultado == nil || *e.resultado != sqlc.StopResultEntregado {
		t.Fatalf("el entregado quedó con resultado %v", e.resultado)
	}
	if e.estado != sqlc.OrderStatusDelivered {
		t.Fatalf("el entregado quedó en estado %q", e.estado)
	}
	if e.rutaID == nil || *e.rutaID != id {
		t.Fatal("la segunda vuelta bajó del camión al entregado: volvería a la lista de " +
			"disponibles y se repartiría otra vez")
	}
	if e.stopOrder == nil || *e.stopOrder != 1 {
		t.Fatalf("la parada se movió de sitio al reaplicar: %v", e.stopOrder)
	}

	// El devuelto, que es el que SÍ suelta el camión, tampoco se duplica ni pierde su hoja.
	v := d.pedidos[devuelto]
	if v.rutaID != nil {
		t.Fatal("el devuelto volvió a subirse al camión en la segunda vuelta")
	}
	if v.ultimaRuta == nil || *v.ultimaRuta != id {
		t.Fatal("el devuelto perdió su ultimaRutaId al reaplicar: desaparece de la hoja")
	}
	if v.entregadoEn != nil {
		t.Fatal("el devuelto acabó con hora de entrega: se pintaría «entregado»")
	}
	// La ruta no se mueve sola: el estado lo cambia el PATCH, no el cierre.
	if d.rutas[id].estado != sqlc.RouteStatusPlanned {
		t.Fatalf("el cierre repetido movió el estado de la ruta a %q", d.rutas[id].estado)
	}
}

// Y EL PARTE A PEDIDO SE VUELVE A MANDAR, que es lo correcto y conviene tenerlo escrito.
//
// La segunda vuelta no se calla: manda otra vez los avisos de lo que aplicó. Tiene que ser
// así — el motivo por el que el aparato reintenta es que NO SABE si la primera llegó, y
// callarse aquí dejaría al vendedor sin enterarse de que su pedido se entregó. Quien no
// puede contar dos veces la misma entrega es PEDIDO, y para eso el aviso lleva el id del
// pedido y su estado final, no un incremento.
func TestElCierreRepetidoVuelveAAvisarAPedido(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h, s := montarRutasCon(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	var tandas [][]AvisoDeParada
	s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		tandas = append(tandas, avisos)
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	cerrarDosVeces(t, h, jwt, id, cuerpo)

	if len(tandas) != 2 {
		t.Fatalf("se avisó %d veces y tenían que ser 2: el aparato reintenta porque NO "+
			"SABE si la primera llegó; callarse la segunda deja al vendedor sin enterarse "+
			"de que su pedido se entregó", len(tandas))
	}
	for i, tanda := range tandas {
		if len(tanda) != 1 {
			t.Fatalf("la tanda %d llevaba %d avisos: %+v", i+1, len(tanda), tanda)
		}
		if tanda[0].Estado != "entregado" {
			t.Fatalf("la tanda %d avisa de %q", i+1, tanda[0].Estado)
		}
		// El aviso dice CÓMO QUEDÓ el pedido, no «una entrega más». Es lo que deja que
		// PEDIDO lo aplique dos veces sin contar dos.
		if tanda[0].PedidoID == "" {
			t.Fatalf("la tanda %d no nombra el pedido: %+v", i+1, tanda[0])
		}
	}
}

// Jose, 06/10/2026: completar fija el histórico, incluso ante una hoja tardía.
// La subida nativa debe enviar resultados ANTES de completar; un rechazo conserva
// su motivo en la bandeja y nunca se descarta en silencio.
func TestUnResultadoNuevoConLaRutaYaCompletadaNoReescribeElHistorico(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1], stg[2])
	for _, estado := range []string{"in_progress", "completed"} {
		w := llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, fmt.Sprintf(`{"status":%q}`, estado))
		if w.Code != 200 {
			t.Fatalf("preparar ruta %s: %s", estado, w.Body.String())
		}
	}
	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != 409 || errorDeRutas(t, w) != msgRutaCompletada {
		t.Fatalf("completada exige409 sin cambios: %d %s", w.Code, w.Body.String())
	}
	if d.pedidos[stg[1]].resultado != nil {
		t.Fatal("se reescribió una parada del histórico")
	}
	if d.rutas[id].estado != sqlc.RouteStatusCompleted {
		t.Fatal("se reabrió el histórico")
	}
}

// UNA PARADA MALA NO SE LLEVA POR DELANTE A LAS BUENAS.
//
// El cierre ACUMULA y no aborta: cada parada es un hecho independiente —el camión volvió y
// ese pedido se entregó—, así que tumbar las buenas porque una venga mal borraría
// información real que nadie va a volver a teclear. Lo malo se nombra en `rechazados` con
// su motivo, que es la otra mitad: «nada se descarta en silencio».
func TestUnaParadaMalaNoTumbaElRestoDelLote(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[0], stg[1], stg[2])

	// La mala es una parada DE ESTA RUTA con un resultado que no existe. Es la forma que
	// importa: con un id ajeno se rechaza por otro camino y la rama del resultado
	// desconocido —la que puede tumbar el lote si alguien la convierte en un 400— no se
	// llega a pisar.
	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":%q,"resultado":"se_perdio"},
		{"orderId":%q,"resultado":"devuelto"}
	]}`, stg[0], stg[1], stg[2])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)

	// 409, NO 200 Y NO 500. Las dos mitades:
	//
	//   · No 200, porque un 2xx se lo traga el sincronizador como `aplicado` sin mirar el
	//     cuerpo, y entonces la parada rechazada desaparece de la cola del aparato sin
	//     que nadie se entere. Ver `cerrarRuta`.
	//   · No 500, porque eso corta la subida entera y detrás de esta hoja va el resto del
	//     día — y porque las dos buenas SÍ se guardaron: decir «error interno» sobre un
	//     trabajo que se hizo es mentir en la otra dirección.
	if w.Code == http.StatusOK {
		t.Fatalf("una parada rechazada salió con un 200: el sincronizador marca `aplicado` "+
			"todo lo que venga con un 2xx y no mira el cuerpo, así que ese rechazo no llega "+
			"a ninguna bandeja y la parada se pierde en silencio — %s", w.Body.String())
	}
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(salida.Aplicados) != 2 {
		t.Fatalf("se aplicaron %d de las 2 paradas buenas: %s", len(salida.Aplicados), w.Body.String())
	}
	if len(salida.Rechazados) != 1 {
		t.Fatalf("rechazados %d: %s", len(salida.Rechazados), w.Body.String())
	}
	if salida.Rechazados[0].Motivo == "" {
		t.Fatal("se rechazó sin motivo: nada se descarta en silencio")
	}
	if !strings.Contains(salida.Rechazados[0].Motivo, "se_perdio") {
		t.Fatalf("el motivo no dice QUÉ vino mal, y el valor tal cual es lo único que "+
			"deja arreglarlo en el aparato: %q", salida.Rechazados[0].Motivo)
	}
	if d.pedidos[stg[0]].resultado == nil || d.pedidos[stg[2]].resultado == nil {
		t.Fatal("las dos paradas buenas no se guardaron")
	}
	if d.pedidos[stg[1]].resultado != nil {
		t.Fatal("la parada mala se guardó igual")
	}
	// Y EL MOTIVO VIAJA EN `error`, que es de donde lo saca el sincronizador para
	// guardarlo en la bandeja (`sync/internal/reparto/reparto.go`, `motivoDe`). Sin ese
	// campo el aparato anota «El reparto no dijo por qué».
	if salida.Error == "" {
		t.Fatal("el 409 no lleva `error`: el aparato lo anotaría sin motivo, y un rechazo " +
			"sin motivo es el descarte en silencio otra vez")
	}
	if !strings.Contains(salida.Error, "Se guardaron 2 de las 3") {
		t.Errorf("el motivo no dice cuántas SÍ entraron, y quien lo lee tres horas después "+
			"va a creer que se perdió la hoja entera: %q", salida.Error)
	}
}
