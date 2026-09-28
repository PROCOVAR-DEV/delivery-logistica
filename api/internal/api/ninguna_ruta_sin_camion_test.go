package api

import (
	"net/http"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// NINGUNA RUTA SIN CAMIÓN — 28/09/2026
// ---------------------------------------------------------------------------
//
// Jose, viendo `RT-20260928-001` en producción, «En curso · 3 paradas · Sin vehículo»:
// «por q se creo una ruta sin vehiculo eso no se puede mi broder».
//
// Los otros dos caminos que crean rutas se niegan desde siempre —`POST /api/routes` con
// `msgFaltaVehiculo`, y el asistente del aparato con su `RechazoLocal`—; el que faltaba era
// éste, `POST /api/board/columns/{id}/route`, que es **el principal**: así se arma el día,
// por zonas. Aquí decía literalmente «puede no haber ninguno; la ruta se arma igual y el
// camión se elige después», y de ahí salió esa ruta.
//
// LAS PRUEBAS VAN EN PAREJA, que es la regla de la casa para todo lo que avisa: una que el
// «no» salga cuando toca, y otra que **NO salga** cuando la zona sí tiene camión. Sin la
// segunda, un `if false` en la guarda deja la suite entera en verde.
//
// Y hay una tercera que no es cosmética: el motivo tiene que decir DÓNDE se arregla. Este
// 400 lo lee una persona dos veces —en la pantalla al armar con conexión, y en la bandeja
// de rechazos cuando el apunte de una APK sin señal sube horas después
// (`sync/internal/reparto/reparto.go`: un 4xx es rechazo de negocio, no se reintenta y se
// queda a la vista con su motivo)—. Un rechazo que no dice dónde se arregla es un rechazo
// permanente, y de ésos ya hubo uno el 18/09/2026 («Vuelve a elegirlos»).

// EL «NO» SALE CUANDO TOCA: zona sin camión previsto, 400 y nada creado.
func TestUnaZonaSinCamionNoPareUnaRuta(t *testing.T) {
	q := nuevoTablero()
	// `colVista` es la que nace SIN camión en el doble. Se le ponen dos tarjetas buenas
	// para que el «no» sea por el camión y no por «no hay nada repartible»: si la zona
	// estuviera vacía, esta prueba pasaría aunque la guarda no existiera.
	q.colocadas[ped1] = colocacion{colVista, 1}
	q.colocadas[ped2] = colocacion{colVista, 2}
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colVista.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: una zona sin camión previsto no puede parir "+
			"una ruta — así nació `RT-20260928-001`, «En curso · 3 paradas · Sin "+
			"vehículo» — %s", w.Code, w.Body.String())
	}
	motivo, _ := leerTab(t, w)["error"].(string)
	if motivo != msgZonaSinCamion {
		t.Fatalf("el motivo es %q y tenía que ser el de `msgZonaSinCamion`", motivo)
	}
	// QUE DIGA DÓNDE. El camión de una zona no se elige en el asistente: se pone en
	// «Camión previsto», en las opciones de la zona. Sin eso, quien lea el rechazo —en la
	// pantalla o en la bandeja— no tiene por dónde empezar.
	if !strings.Contains(motivo, "Camión previsto") {
		t.Errorf("el motivo no dice dónde se arregla: %q", motivo)
	}
	// Y NADA SE CREÓ. Un 400 que deja media ruta escrita es peor que no tener guarda.
	if len(q.creadas) != 0 {
		t.Errorf("se creó algo pese al 400: %v", q.creadas)
	}
	// Las tarjetas se quedan puestas: el trabajo de nadie desaparece por un rechazo.
	if len(q.colocadas) != 2 {
		t.Errorf("las tarjetas se movieron: quedan %d de 2", len(q.colocadas))
	}
}

// Y NO SALE CUANDO NO TOCA: la misma zona con el camión previsto puesto arma su ruta.
//
// Ésta es la mitad que caza un bloqueo de más, que aquí es el riesgo de verdad: el
// CLAUDE.md §2 cuenta que los avisos del armador son aviso y no bloqueo porque los datos
// reales tenían 657 de 686 domicilios sin costo y bloquear habría dejado la aplicación
// inservible. Si esta prueba se pone roja, es que acabamos de hacer eso mismo con los
// camiones.
func TestLaMismaZonaConCamionPrevistoSiArma(t *testing.T) {
	q := nuevoTablero()
	q.colocadas[ped1] = colocacion{colVista, 1}
	q.colocadas[ped2] = colocacion{colVista, 2}
	q.capacidad = 1000
	// Lo único que cambia respecto a la prueba de arriba: la zona tiene su camión. El de
	// Santiago, que es la sucursal de la zona.
	col := q.columnas[colVista]
	col.VehicleID = pgDe(vehStgTab)
	q.columnas[colVista] = col
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colVista.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d, se esperaba 201: con camión previsto la ruta sale, y si esto "+
			"falla el tablero se quedó sin poder armar nada — %s", w.Code, w.Body.String())
	}
	if n, _ := leerTab(t, w)["paradas"].(float64); n != 2 {
		t.Errorf("paradas %v, se esperaban 2", leerTab(t, w)["paradas"])
	}
}

// EL CAMIÓN PUEDE VENIR EN EL CUERPO, y entonces la zona no hace falta que lo tenga.
//
// Es la diferencia entre mirar `vehiculo` y mirar `columna.VehicleID`, y no es teórica: una
// APK que armó con el camión ya elegido manda `vehiculoId` en el apunte
// (`app/lib/pantallas/tablero/datos/repositorio.dart`, `armarRuta`). Negarle la ruta porque
// su zona no lo tuviera guardado sería negar una ruta que SÍ tiene camión.
func TestElCamionDelCuerpoBastaAunqueLaZonaNoLoTenga(t *testing.T) {
	q := nuevoTablero()
	q.colocadas[ped1] = colocacion{colVista, 1}
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colVista.String()+"/route",
		tokenTab(t, sucStg.String()), `{"vehiculoId":"`+vehStgTab.String()+`"}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d, se esperaba 201: el camión venía en el cuerpo — %s",
			w.Code, w.Body.String())
	}
}

// UN `vehiculoId` VACÍO ES «SIN CAMIÓN», y también se niega.
//
// `vehiculoDelCuerpo` devuelve un uuid inválido para la cadena vacía —es como se
// DESENGANCHA el camión de una zona— y eso, presente en el cuerpo, PISA al previsto de la
// columna. Sin esta prueba, un cuerpo con `"vehiculoId":""` se colaba por el único camino
// que borra el camión bueno justo antes de armar.
func TestUnVehiculoVacioEnElCuerpoNoArmaLaRuta(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas() // en `colCentro`, que SÍ tiene camión previsto
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{"vehiculoId":""}`)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: un `vehiculoId` vacío en el cuerpo pisa al "+
			"previsto de la zona, así que la ruta saldría sin camión — %s",
			w.Code, w.Body.String())
	}
	if len(q.creadas) != 0 {
		t.Errorf("se creó algo pese al 400: %v", q.creadas)
	}
}

// EL ORDEN: primero «la zona no tiene nada repartible», después el camión.
//
// Es el mismo orden que el del aparato (`repositorio.dart`, `armarRuta`), y de eso depende
// que la persona lea el MISMO mensaje por los dos caminos cuando fallan los dos a la vez.
// Sin esta prueba, mover la guarda del camión tres líneas más arriba deja al aparato y al
// servidor diciendo cosas distintas del mismo gesto, y eso no lo caza nada.
func TestSiLaZonaNoTieneNadaRepartibleEsoSeDiceAntesQueElCamion(t *testing.T) {
	q := nuevoTablero()
	// `colVacia` no tiene camión Y no tiene tarjetas: fallan las dos cosas.
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colVacia.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: cuando fallan las dos cosas manda la zona "+
			"vacía, que es el orden que sigue el aparato — %s", w.Code, w.Body.String())
	}
	if m := leerTab(t, w); m["error"] != msgColumnaSinNada {
		t.Errorf("el motivo es %q y tenía que ser el de la zona sin nada repartible",
			m["error"])
	}
}
