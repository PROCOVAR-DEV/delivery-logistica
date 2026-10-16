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
	"testing"

	"github.com/google/uuid"
)

// armarYLeer arma la ruta con los tres pedidos de Santiago y devuelve lo guardado y lo
// devuelto, que tienen que decir lo mismo.
func armarYLeer(t *testing.T, d *dobleDeRutas, h http.Handler, ids ...uuid.UUID) (*rutaDeRutas, RutaSalida) {
	t.Helper()
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), ids...))
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// El armado contesta la ruta pelada: desde el 07/10/2026 ya no hay `{ruta, avisos}`.
	var ruta RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	guardada, hay := d.rutas[ruta.ID]
	if !hay {
		t.Fatal("la ruta no quedó guardada")
	}
	return guardada, ruta
}

// 1. SIN COTIZACIÓN SÍ SE ARMA RUTA si la factura cobró el domicilio (Amado, 16/10/2026), y la
// parada vale LO COBRADO: ya no cuenta en `paradas_sin_cotizar` ni deja el importe en cero.
// Antes era un 409 «no tienen cotizado el domicilio en Entrega».
func TestLaRutaAceptaParadasSinCotizarYLasValoraPorLoCobrado(t *testing.T) {
	d, stg, _ := datosDeReparto()
	d.pedidos[stg[0]].costo = nil
	d.pedidos[stg[1]].costo = nil
	h := montarRutas(t, d)
	guardada, ruta := armarYLeer(t, d, h, stg[0], stg[1], stg[2])
	if guardada.sinCotizar == nil || *guardada.sinCotizar != 0 {
		t.Fatalf("las dos están cobradas en la factura: no faltaba ninguna y se guardó %v", guardada.sinCotizar)
	}
	if ruta.ParadasSinCotizar == nil || *ruta.ParadasSinCotizar != 0 {
		t.Fatalf("la respuesta tiene que llevar paradasSinCotizar=0 y llevó %v", ruta.ParadasSinCotizar)
	}
	// 1 + 1 cobrados en la factura (el doble cobra 1) y 10 cotizados en Entrega.
	if guardada.precio != 12 {
		t.Fatalf("total_price tenía que ser 12 (1+1 cobrados + 10 cotizado) y fue %v", guardada.precio)
	}
	if p := d.pedidos[stg[0]].precio; p == nil || *p != 1 {
		t.Fatalf("el `price` de la parada sin cotizar tenía que ser lo cobrado (1) y fue %v", p)
	}
	if p := d.pedidos[stg[2]].precio; p == nil || *p != 10 {
		t.Fatalf("el `price` de la parada cotizada manda el cotizado (10) y fue %v", p)
	}
}

// 2. CON TODAS COTIZADAS: **0, no nulo**. Es la otra mitad de la pareja.
func TestUnaRutaConTodoCotizadoGuardaCeroYNoUnNulo(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d) // los tres traen costo 10

	guardada, ruta := armarYLeer(t, d, h, stg[0], stg[1], stg[2])

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

// 3. Ninguna cotizada pero TODAS cobradas: la ruta sale y vale lo cobrado, sin «—».
func TestUnaRutaSinNingunaCotizacionPeroCobradaSale(t *testing.T) {
	d, stg, _ := datosDeReparto()
	d.pedidos[stg[0]].costo = nil
	d.pedidos[stg[1]].costo = nil
	d.pedidos[stg[2]].costo = nil
	h := montarRutas(t, d)
	guardada, _ := armarYLeer(t, d, h, stg[0], stg[1], stg[2])
	if guardada.precio != 3 || guardada.sinCotizar == nil || *guardada.sinCotizar != 0 {
		t.Fatalf("tres cobradas de 1 sin cotizar: total 3 y 0 sin cotizar; salió %v y %v", guardada.precio, guardada.sinCotizar)
	}
}
