package api

// UNA RUTA SIEMPRE TIENE DÍA, y hasta el 28/09/2026 ninguna lo tenía.
//
// Leído del servidor ese día: las NUEVE rutas de producción con `delivery_date` nulo, las
// nueve. Jose, mirando la ficha y la lista: «mira todos los — que hay en la ruta y esos
// datos debemos de tenerlo por q no se estan poniendo».
//
// Eran dos agujeros distintos que daban el mismo hueco:
//
//  1. el asistente de Rutas tenía el campo como «Fecha de entrega (opcional)» y nacía en
//     blanco, así que nadie lo rellenaba nunca;
//  2. y ESTE camino —armar desde una zona del tablero, que es por donde se arma de
//     verdad— ni lo mandaba ni lo guardaba. El aparato SÍ escribía el día en su base
//     local, de modo que la ruta nacía con fecha en el teléfono y **la perdía al subir**,
//     cuando la bajada la pisaba con el nulo del servidor. En la prueba del móvil sin
//     señal se vio literal: «Planificada · 3 paradas · 1.7 km · 28/9/2026» antes de
//     sincronizar y «En curso · 3 paradas · 1.7 km · —» después.
//
// Las dos cosas que se atan aquí, y las dos hacen falta:
//
//   - si el aparato manda su día, MANDA EL SUYO. Un apunte hecho sin señal llega horas
//     después: la ruta se armó el día que la armó el logístico, no el día en que el
//     servidor se enteró. Es la misma razón por la que viajan los `pedidoIds`.
//   - si NO lo manda —las APK ya instaladas no lo hacen— se pone la de hoy, nunca nulo.
//     Con las viejas se acerca, y acercarse es infinitamente mejor que la raya.

import (
	"net/http"
	"testing"
	"time"
)

// EL DÍA DEL APARATO GANA. Es el caso del apunte que subió tarde.
func TestLaZonaArmadaConSuDiaGuardaEseDiaYNoElDeHoy(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()),
		`{"nombre":"Centro","optimizar":false,"deliveryDate":"2026-09-25"}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if q.rutaCreada == nil {
		t.Fatal("no se creó ninguna ruta")
	}
	dia := q.rutaCreada.DeliveryDate
	if !dia.Valid {
		t.Fatal("la ruta se guardó SIN día teniendo uno en el cuerpo: es el hueco que " +
			"deja la raya en la ficha y en la lista de rutas")
	}
	if dia.Time.Format("2006-01-02") != "2026-09-25" {
		t.Fatalf("día %s, se esperaba 2026-09-25: se puso el del servidor en vez del del "+
			"aparato, y una ruta armada sin señal el jueves aparecería como del sábado",
			dia.Time.Format("2006-01-02"))
	}
}

// SIN DÍA EN EL CUERPO, EL DE HOY — y NUNCA nulo. Es lo que mandan las APK instaladas.
func TestLaZonaSinDiaEnElCuerpoSeGuardaConElDeHoyYNoNula(t *testing.T) {
	antes := time.Now()

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
	if q.rutaCreada == nil {
		t.Fatal("no se creó ninguna ruta")
	}
	dia := q.rutaCreada.DeliveryDate
	if !dia.Valid {
		t.Fatal("la ruta nació con `delivery_date` NULO: es exactamente el estado en que " +
			"estaban las nueve rutas de producción el 28/09/2026, y lo que pinta el `—` " +
			"que vio Jose en la ficha y en la lista")
	}
	// La de hoy, con holgura para que no dependa del reloj ni del huso.
	if dia.Time.Before(antes.Add(-time.Minute)) || dia.Time.After(time.Now().Add(time.Minute)) {
		t.Fatalf("día %s, se esperaba el de ahora mismo", dia.Time)
	}
}

// Y LA FECHA QUE NO SE ENTIENDE SE DICE, no se traga en silencio (§4: nada se descarta
// sin decirlo). Un 400 con su motivo es lo único que le sirve a quien mandó la petición.
func TestUnaFechaQueNoSeEntiendeNoSeTragaEnSilencio(t *testing.T) {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()),
		`{"nombre":"Centro","optimizar":false,"deliveryDate":"el jueves"}`)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: una fecha ilegible se guardó o se ignoró — %s",
			w.Code, w.Body.String())
	}
	if q.rutaCreada != nil {
		t.Fatal("se armó la ruta igual, con el día perdido por el camino")
	}
}
