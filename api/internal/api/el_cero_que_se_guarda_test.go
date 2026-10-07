package api

// EL CERO QUE SE GUARDA EN `routes.total_price`, QUE ES EL QUE NO DESMIENTE NADIE.
//
// El 22/09/2026 se tapó el `$0.00` de la tarjeta de una ruta en el aparato: el importe ya
// no se lee de `routes.total_price` sino que se suma de las paradas, que sí saben decir
// que no lo saben (`app/lib/pantallas/rutas/datos/importe_de_la_ruta.dart`). Pero la
// columna del servidor sigue siendo `double precision NOT NULL DEFAULT 0`, así que **quien
// la consulte por SQL o la exporte sigue viendo un cero indistinguible de un cero de
// verdad**. La ruta RT-20260921-007 decía `$0.00` con sus dos paradas sin cotizar y el
// camión a 1,50 USD/km.
//
// La decisión (00007_lo_que_no_se_sabe.sql) no fue anular la columna —eso rompería a todo
// el que ya la lee, empezando por las APK instaladas— sino guardar A SU LADO cuántas
// paradas entraron sin cotizar. Un total con ese número al lado ya no puede mentir.
//
// LAS PRUEBAS VAN EN PAREJA, y ésa es la mitad del valor: una guarda que sólo se prueba
// por el lado que falla no distingue entre «avisa cuando toca» y «avisa siempre»
// (`CLAUDE.md` §3-quinquies). Así que se comprueba que sale 2 cuando faltan dos Y que sale
// **0, no nulo**, cuando no falta ninguna: si en ese caso se dejara el nulo, una ruta
// entera bien cotizada diría «no consta» y el número dejaría de servir para nada.

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// armarYLeer arma la ruta con los tres pedidos de Santiago y devuelve lo guardado y lo
// devuelto, que tienen que decir lo mismo.
func armarYLeer(t *testing.T, d *dobleDeRutas, h http.Handler, ids ...uuid.UUID) (*rutaDeRutas, RutaSalida, int) {
	t.Helper()
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), ids...))
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// El armado contesta de DOS formas: la ruta pelada, o `{ruta, avisos}` cuando hay
	// domicilios sin costear. Las dos llevan la misma ruta dentro.
	var conAvisos struct {
		Ruta   *RutaSalida `json:"ruta"`
		Avisos struct {
			SinCosto int `json:"sinCosto"`
		} `json:"avisos"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &conAvisos); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	var ruta RutaSalida
	if conAvisos.Ruta != nil {
		ruta = *conAvisos.Ruta
	} else if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	guardada, hay := d.rutas[ruta.ID]
	if !hay {
		t.Fatal("la ruta no quedó guardada")
	}
	return guardada, ruta, conAvisos.Avisos.SinCosto
}

// 1. SIN COTIZACIÓN NO SE ARMA RUTA: ya no se permite guardar paradas con importe cero.
func TestLaRutaNoAceptaParadasSinCotizar(t *testing.T) {
	d, stg, _ := datosDeReparto()
	d.pedidos[stg[0]].costo = nil
	d.pedidos[stg[1]].costo = nil
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), stg[0], stg[1], stg[2]))
	if w.Code != http.StatusConflict || !strings.Contains(w.Body.String(), "no tienen cotizado el domicilio") {
		t.Fatalf("la ruta debe bloquear los pedidos sin cotización: %d %s", w.Code, w.Body.String())
	}
	if len(d.rutas) != 0 {
		t.Fatal("se guardó una ruta con pedidos sin cotización")
	}
}

// 2. CON TODAS COTIZADAS: **0, no nulo**. Es la otra mitad de la pareja.
func TestUnaRutaConTodoCotizadoGuardaCeroYNoUnNulo(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d) // los tres traen costo 10

	guardada, ruta, _ := armarYLeer(t, d, h, stg[0], stg[1], stg[2])

	if guardada.sinCotizar == nil {
		t.Fatal("con las tres paradas cotizadas se guardó NULL: «no consta» y «ninguna» no " +
			"son lo mismo, y dejarlo en nulo hace inservible el número en el caso bueno")
	}
	if *guardada.sinCotizar != 0 {
		t.Fatalf("no faltaba ninguna y se guardó %d", *guardada.sinCotizar)
	}
	if guardada.precio != 30 {
		t.Fatalf("total_price tenía que ser 30 y fue %v", guardada.precio)
	}
	if ruta.ParadasSinCotizar == nil || *ruta.ParadasSinCotizar != 0 {
		t.Fatalf("la respuesta tiene que llevar paradasSinCotizar=0 y llevó %v", ruta.ParadasSinCotizar)
	}
}

// 3. La misma guarda se aplica cuando no hay cotización de domicilio en ninguno.
func TestNoSeCreaUnaRutaSiNingunPedidoTieneCotizacion(t *testing.T) {
	d, stg, _ := datosDeReparto()
	d.pedidos[stg[0]].costo = nil
	d.pedidos[stg[1]].costo = nil
	d.pedidos[stg[2]].costo = nil
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), stg[0], stg[1], stg[2]))
	if w.Code != http.StatusConflict || len(d.rutas) != 0 {
		t.Fatalf("no debió crearse la ruta sin ninguna cotización: %d %s", w.Code, w.Body.String())
	}
}
