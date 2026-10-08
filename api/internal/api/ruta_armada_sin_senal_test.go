package api

// LA RUTA QUE SE ARMÓ SIN SEÑAL Y SUBE HORAS DESPUÉS.
//
// EL MECANISMO ENTERO, que es el fallo más caro que se ha encontrado en esta puerta:
//
//	 9:10  el aparato, sin señal, arma la ruta de «Centro» con las tres tarjetas que ve.
//	 9:40  la web mueve una de esas tarjetas a otra zona. El servidor no sabe nada del
//	       camión que ya salió.
//	11:20  vuelve la señal y sube el apunte: `POST /api/board/columns/{id}/route`.
//
// El cuerpo que encola el aparato (`app/lib/pantallas/tablero/datos/repositorio.dart`,
// `armarRuta`) lleva sólo `{nombre, vehiculoId, optimizar}`. Sin la lista de pedidos, el
// servidor arma la ruta con LO QUE ÉL TENGA PUESTO EN ESA ZONA A LAS 11:20, y entonces:
//
//  1. la ruta nace SIN el pedido que el repartidor lleva entregado desde las diez;
//  2. el resultado de esa parada llega a `/routes/{id}/results`, no está en la ruta y se
//     rechaza — y hasta el 18/09/2026 eso salía con un 200, que el sincronizador anota
//     como `aplicado`: la entrega desaparecía sin dejar rastro en ninguna bandeja;
//  3. el pedido se queda suelto en el tablero del servidor, la web lo mete en otra ruta y
//     sale un SEGUNDO camión con el mismo bulto.
//
// Lo único que lo frenaba estaba en el aparato (la tarjeta vuelve marcada «ya va en otra
// ruta» y su `armarRuta` se niega). Del lado del servidor no había nada.
//
// Se cierra por los dos lados:
//
//   - el cuerpo ACEPTA `pedidoIds`/`orderIds`, y cuando viene, la ruta lleva exactamente
//     lo que el aparato decidió y la respuesta DICE LA DIFERENCIA con lo que hay ahora;
//   - el cierre con paradas rechazadas contesta 409 con motivo, que es lo único que llega
//     a la bandeja del aparato.
//
// EL CONTRATO SIGUE SIENDO COMPATIBLE: sin la lista, todo se comporta igual que antes. Las
// APK instaladas hoy no la mandan, y si dejaran de poder armar rutas el arreglo sería peor
// que el fallo.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// ---------------------------------------------------------------------------
// 1. El cierre de una parada que no va en la ruta llega a la bandeja
// ---------------------------------------------------------------------------

// UNA ENTREGA DE VERDAD NO PUEDE DESAPARECER CON UN 200.
//
// El sincronizador marca `aplicado` TODO lo que venga con un 2xx y no mira el cuerpo
// (`sync/internal/reparto/reparto.go`, el `case res.StatusCode >= 200 && < 300`), así que
// el apunte se borra de la cola del aparato. Con un 4xx lo anota como `rechazado` CON SU
// MOTIVO, y por contrato «no se reintenta y no se borra»: queda a la vista con su hora
// hasta que una persona decida.
func TestElCierreDeUnaParadaQueNoVaEnLaRutaNoSaleConUn200(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	// La ruta que el servidor acabó armando: sin el pedido que el repartidor entregó.
	id := armarRutaDePrueba(t, h, jwt, stg[1])
	seLoEntregoIgual := stg[0]

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, seLoEntregoIgual)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)

	if w.Code == http.StatusOK {
		t.Fatalf("UNA ENTREGA DE VERDAD SE PERDIÓ CON UN 200. El sincronizador marca "+
			"`aplicado` cualquier 2xx sin mirar el cuerpo, así que ese rechazo no llega a "+
			"ninguna bandeja: el apunte se borra de la cola y nadie se entera nunca de que "+
			"ese pedido se entregó — %s", w.Body.String())
	}
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}

	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	// El `error` es el campo del que el sincronizador saca el motivo para la bandeja.
	if salida.Error == "" {
		t.Fatal("el 409 no lleva `error`: el aparato anotaría «El reparto no dijo por qué», " +
			"que es un descarte en silencio con otro nombre")
	}
	// SE NOMBRA POR SU NÚMERO DE OPERACIÓN (el conduce), no por el UUID: con el UUID nadie
	// sabía de qué pedido hablaba el 409 (Amado, 07/10/2026). El del doble es «X-Lejos».
	if !strings.Contains(salida.Error, "X-Lejos") || strings.Contains(salida.Error, seLoEntregoIgual.String()) {
		t.Errorf("el motivo tiene que nombrar el pedido que se quedó fuera por su número de "+
			"operación (X-Lejos) y no por el UUID, que es el dato con el que alguien puede ir "+
			"a buscarlo: %q", salida.Error)
	}
	if len(salida.Rechazados) == 1 && (salida.Rechazados[0].NumeroOperacion != "X-Lejos" ||
		salida.Rechazados[0].OrderID != seLoEntregoIgual.String()) {
		t.Errorf("el detalle tiene que llevar numeroOperacion y conservar el orderId: %+v", salida.Rechazados)
	}
	if !strings.Contains(salida.Error, msgParadaAjena) {
		t.Errorf("el motivo no dice POR QUÉ no entró: %q", salida.Error)
	}
	if len(salida.Rechazados) != 1 || salida.Rechazados[0].Motivo != msgParadaAjena {
		t.Fatalf("el detalle por parada se perdió: %+v", salida.Rechazados)
	}
}

// ---------------------------------------------------------------------------
// 2. Armar la zona con la lista que decidió el aparato
// ---------------------------------------------------------------------------

// cuerpoConPedidos arma el JSON del apunte del aparato.
func cuerpoConPedidos(clave string, ids ...uuid.UUID) string {
	txt := make([]string, 0, len(ids))
	for _, id := range ids {
		txt = append(txt, `"`+id.String()+`"`)
	}
	return fmt.Sprintf(`{%q:[%s]}`, clave, strings.Join(txt, ","))
}

// LA RUTA LLEVA LO QUE EL APARATO DECIDIÓ, Y LO QUE FALTA SE DICE.
//
// La zona tiene ahora tres tarjetas; el aparato armó con dos, porque la tercera llegó
// después. Y una de las que él eligió ya no está. La ruta tiene que salir con UNA —la que
// estaba en las dos listas— y la respuesta tiene que nombrar las otras dos diferencias.
func TestArmarLaZonaRespetaLaListaDelAparatoYDiceLaDiferencia(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	// Lo que hay AHORA en Centro: ped1 y ped2 (ped3 no está: se lo llevaron).
	q.colocadas[ped1] = colocacion{colCentro, 1}
	q.colocadas[ped2] = colocacion{colCentro, 2}
	h := montarTab(t, q)

	// Lo que el aparato eligió a las 9:10: ped1 y ped3.
	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), cuerpoConPedidos("pedidoIds", ped1, ped3))

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d, se esperaba 201: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["paradas"].(float64); n != 1 {
		t.Fatalf("paradas %v, se esperaba 1: la ruta tiene que llevar lo que el aparato "+
			"decidió y que todavía se puede, ni más ni menos — %s", m["paradas"], w.Body.String())
	}
	if len(q.enganchados) != 1 || q.enganchados[0] != ped1 {
		t.Fatalf("se engancharon %v: ped2 no lo eligió nadie en ese camión", q.enganchados)
	}
	// ped2 sigue en la zona: no subió, así que su tarjeta no se quita.
	if _, sigue := q.colocadas[ped2]; !sigue {
		t.Fatal("se quitó del tablero una tarjeta que no subió a ninguna ruta: " +
			"desaparece de la pantalla sin haber salido en ningún camión")
	}

	// LAS DOS DIFERENCIAS, NOMBRADAS.
	desc, _ := m["descartados"].([]any)
	porID := map[string]map[string]any{}
	for _, cruda := range desc {
		d, _ := cruda.(map[string]any)
		if d != nil {
			porID[fmt.Sprint(d["pedidoId"])] = d
		}
	}
	falta := porID[ped3.String()]
	if falta == nil {
		t.Fatalf("el pedido que el aparato eligió y ya no estaba NO SE NOMBRA. Es justo el "+
			"que su repartidor puede llevar entregado: %v", m["descartados"])
	}
	if !strings.Contains(fmt.Sprint(falta["motivo"]), "ya no estaba en esa zona") {
		t.Errorf("motivo %q", falta["motivo"])
	}
	if !strings.Contains(fmt.Sprint(falta["queHacer"]), "otra ruta") {
		t.Errorf("no se avisa de lo que hay que mirar —que no salga otra vez— : %q",
			falta["queHacer"])
	}

	sobra := porID[ped2.String()]
	if sobra == nil {
		t.Fatalf("la tarjeta que llegó a la zona después NO SE NOMBRA: se queda puesta y "+
			"nadie sabe por qué no salió — %v", m["descartados"])
	}
	if !strings.Contains(fmt.Sprint(sobra["motivo"]), "después de que armaras") {
		t.Errorf("motivo %q", sobra["motivo"])
	}
}

// EL MOTIVO DE LO QUE EL APARATO NO ELIGIÓ TIENE QUE SER EL VERDADERO — 08/10/2026.
// El aparato manda `pedidoIds` con las buenas solamente, así que una tarjeta de la zona que
// no se puede cargar (aquí, sin cotizar) tampoco viene en su lista. El servidor le decía
// «lo pusieron en la zona después de que armaras», que es FALSO: lleva ahí desde antes y lo
// que le falta es la cotización. En PAREJA: la que sí sería buena y llegó después conserva su
// motivo de siempre; la mala dice el suyo, y el literal es el del bucle que arma.
func TestLoQueElAparatoNoEligioDiceSuMotivoDeVerdad(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas() // ped1, ped2 y ped3 en Centro
	p2 := q.pedidos[ped2]
	p2.sinCotizar = true // mala: sin cotizar. Tampoco la eligió el aparato (que filtra igual).
	q.pedidos[ped2] = p2
	// ped3 es buena y NO la eligió el aparato: llegó después.
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), cuerpoConPedidos("pedidoIds", ped1))
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	porID := map[string]map[string]any{}
	desc, _ := m["descartados"].([]any)
	for _, cruda := range desc {
		if d, _ := cruda.(map[string]any); d != nil {
			porID[fmt.Sprint(d["pedidoId"])] = d
		}
	}
	if mala := porID[ped2.String()]; mala == nil || mala["motivo"] != "domicilio sin cotizar" {
		t.Errorf("la tarjeta sin cotizar tenía que decir su motivo de verdad (domicilio sin cotizar), y dice: %v", mala)
	}
	if buena := porID[ped3.String()]; buena == nil ||
		!strings.Contains(fmt.Sprint(buena["motivo"]), "después de que armaras") {
		t.Errorf("la buena que llegó después conserva «lo pusieron en la zona después de que armaras»: %v", buena)
	}
}

// EL MISMO CUERPO CON `orderIds`, que es el nombre que usa `POST /api/routes`.
func TestLaListaTambienSeAceptaComoOrderIds(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), cuerpoConPedidos("orderIds", ped1))

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if n, _ := leerTab(t, w)["paradas"].(float64); n != 1 {
		t.Fatalf("paradas %v, se esperaba 1: no se hizo caso a `orderIds` y la ruta salió "+
			"con lo que había en la zona — %s", leerTab(t, w)["paradas"], w.Body.String())
	}
}

// SIN LA LISTA, TODO SIGUE IGUAL QUE ANTES. Es la mitad que no se puede romper: las APK
// instaladas hoy mandan `{nombre, vehiculoId, optimizar}` y nada más, y si dejaran de
// poder armar rutas el arreglo sería peor que el fallo.
func TestSinListaLaZonaSeArmaConLoQueHayComoSiempre(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{"nombre":"Centro","optimizar":false}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: una APK instalada acaba de quedarse sin poder armar rutas — %s",
			w.Code, w.Body.String())
	}
	if n, _ := leerTab(t, w)["paradas"].(float64); n != 3 {
		t.Fatalf("paradas %v, se esperaban 3: %s", leerTab(t, w)["paradas"], w.Body.String())
	}
	if desc, _ := leerTab(t, w)["descartados"].([]any); len(desc) != 0 {
		t.Fatalf("sin lista no hay nada que comparar y no puede haber descartes: %v", desc)
	}
}

// UNA LISTA VACÍA NO ES «ARMA CON TODO». Es un cuerpo mal formado, y armar con lo que haya
// es exactamente el fallo que la lista viene a tapar.
func TestUnaListaDePedidosVaciaEsUn400YNoArmaConTodo(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{"pedidoIds":[]}`)

	if w.Code == http.StatusCreated {
		t.Fatalf("una lista vacía armó la ruta con lo que había en la zona: %s", w.Body.String())
	}
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != msgListaVacia {
		t.Fatalf("mensaje %q", w.Body.String())
	}
	if len(q.enganchados) != 0 {
		t.Fatalf("se enganchó algo igual: %v", q.enganchados)
	}
}

// Y LA LISTA NO AMPLÍA NADA: un id de otra sucursal o de un pedido que ya va en otra ruta
// no entra por venir escrito en el cuerpo. La lista sólo puede QUITAR de lo que la zona ya
// ofrecía, nunca añadir — si no, sería una puerta para subir al camión lo que sea.
func TestLaListaDelAparatoNoPuedeMeterLoQueNoEstaEnLaZona(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), cuerpoConPedidos("pedidoIds", ped1, pedHol, pedRuta))

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	for _, id := range q.enganchados {
		if id == pedHol {
			t.Fatal("un pedido de Holguín subió al camión de Santiago porque venía en la " +
				"lista del cuerpo: el alcance no puede salir de lo que manda el cliente")
		}
		if id == pedRuta {
			t.Fatal("un pedido que ya va en otra ruta subió a ésta por venir en la lista")
		}
	}
	if len(q.enganchados) != 1 || q.enganchados[0] != ped1 {
		t.Fatalf("se engancharon %v, se esperaba sólo ped1", q.enganchados)
	}
}
