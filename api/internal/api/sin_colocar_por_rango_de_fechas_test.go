package api

// LOS DÍAS DE LA FACTURA LLEGAN A LA CONSULTA — issue 13 de Amado (15/10/2026, el rango) e
// issue 16 (16/10/2026, la fecha es la de la FACTURA y el día el de Cuba).
//
// «Sin colocar» lleva `diaDesde`/`diaHasta` (no `desde`, que aquí es el cursor) y `dia`;
// el catálogo de Pedidos y los disponibles del asistente llevan `desde`/`hasta`, y los
// disponibles además `fecha`. Los cuatro son DÍAS (`AAAA-MM-DD`), los dos extremos incluidos.
// Esto prueba el manejador: que cada parámetro se lee, se mezcla bien con los otros y llega
// IGUAL a la lista y a su contador. Que el SQL de verdad haga lo que dice el fichero de casos
// lo prueba `TestMotorReal_LaFechaDeLaFacturaEsElDiaDeCuba`; que el doble de «Sin colocar»
// y el aparato lo hagan, `fecha_de_la_factura_casos_compartidos_test.go`.

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func dia(s string) pgtype.Date {
	d, err := time.Parse("2006-01-02", s)
	if err != nil {
		panic(err)
	}
	return pgtype.Date{Time: d, Valid: true}
}

func TestRangoDelPedido(t *testing.T) {
	nada := pgtype.Date{}
	for _, c := range []struct {
		nombre, query string
		desde, hasta  pgtype.Date
	}{
		{"sin nada no acota", "", nada, nada},
		{"el día suelto de siempre: ese día entero", "dia=2026-10-03", dia("2026-10-03"), dia("2026-10-03")},
		{"el rango: los dos días incluidos", "diaDesde=2026-10-01&diaHasta=2026-10-03", dia("2026-10-01"), dia("2026-10-03")},
		{"sólo desde", "diaDesde=2026-10-01", dia("2026-10-01"), nada},
		{"sólo hasta", "diaHasta=2026-10-03", nada, dia("2026-10-03")},
		{"un día como rango es el día suelto", "diaDesde=2026-10-03&diaHasta=2026-10-03", dia("2026-10-03"), dia("2026-10-03")},
		{"dia y rango a la vez: el tramo común", "dia=2026-10-02&diaDesde=2026-10-01&diaHasta=2026-10-05", dia("2026-10-02"), dia("2026-10-02")},
		{"una fecha mal escrita no acota", "diaDesde=03-10-2026", nada, nada},
		{"un día que no existe no acota", "diaDesde=2026-02-30", nada, nada},
		{"el cursor `desde` NO es una fecha", "desde=2026-10-01T00:00:00Z|" + uuid.NewString(), nada, nada},
	} {
		t.Run(c.nombre, func(t *testing.T) {
			r, _ := http.NewRequest(http.MethodGet, "/x?"+strings.ReplaceAll(c.query, "|", "%7C"), nil)
			desde, hasta := rangoDelPedido(r.URL.Query())
			if desde != c.desde || hasta != c.hasta {
				t.Errorf("%q → [%v, %v] y tenía que ser [%v, %v]", c.query, desde, hasta, c.desde, c.hasta)
			}
		})
	}
}

// El catálogo de Pedidos y los disponibles pasan `desde`/`hasta` como DÍAS a la lista Y al
// contador: si uno de los dos se queda sin ellos, «Mostrando 1-50 de N» o el `total` del
// asistente cuentan otra cosa que la tabla (los parámetros se copian a mano, §3-bis).
func TestPedidosYDisponiblesPasanLosDiasALaListaYAlContador(t *testing.T) {
	d := datosDePedidos()
	h := servidorDePedidos(t, d)
	jwt := tokenDeSantiagoPedidos(t)

	if w := pedirPedidos(t, h, http.MethodGet,
		"/api/orders?desde=2026-10-15&hasta=2026-10-15", jwt, "", nil); w.Code != http.StatusOK {
		t.Fatalf("/api/orders: %d %s", w.Code, w.Body.String())
	}
	if d.vistoListar.Desde != dia("2026-10-15") || d.vistoListar.Hasta != dia("2026-10-15") {
		t.Errorf("ListarPedidos recibió [%v, %v] y tenía que ser el 15 entero", d.vistoListar.Desde, d.vistoListar.Hasta)
	}
	if d.vistoContar.Desde != d.vistoListar.Desde || d.vistoContar.Hasta != d.vistoListar.Hasta {
		t.Errorf("ContarPedidos recibió [%v, %v] y su lista [%v, %v]: el contador diría otra cosa",
			d.vistoContar.Desde, d.vistoContar.Hasta, d.vistoListar.Desde, d.vistoListar.Hasta)
	}

	for _, c := range []struct {
		nombre, query string
		desde, hasta  pgtype.Date
	}{
		{"el rango", "desde=2026-10-14&hasta=2026-10-15", dia("2026-10-14"), dia("2026-10-15")},
		{"sólo desde", "desde=2026-10-14", dia("2026-10-14"), pgtype.Date{}},
		{"`fecha` es un día: desde = hasta", "fecha=2026-10-15", dia("2026-10-15"), dia("2026-10-15")},
		{"`fecha` dentro del rango: el tramo común", "desde=2026-10-14&hasta=2026-10-16&fecha=2026-10-15", dia("2026-10-15"), dia("2026-10-15")},
		{"`fecha` fuera del rango no trae nada, no ensancha", "desde=2026-10-16&hasta=2026-10-17&fecha=2026-10-15", dia("2026-10-16"), dia("2026-10-15")},
		{"sin nada no acota", "", pgtype.Date{}, pgtype.Date{}},
	} {
		t.Run("disponibles: "+c.nombre, func(t *testing.T) {
			if w := pedirPedidos(t, h, http.MethodGet, "/api/orders/available?"+c.query, jwt, "", nil); w.Code != http.StatusOK {
				t.Fatalf("/api/orders/available: %d %s", w.Code, w.Body.String())
			}
			if d.vistoDispLista.Desde != c.desde || d.vistoDispLista.Hasta != c.hasta {
				t.Errorf("la lista recibió [%v, %v] y tenía que ser [%v, %v]",
					d.vistoDispLista.Desde, d.vistoDispLista.Hasta, c.desde, c.hasta)
			}
			if d.vistoDispContar.Desde != c.desde || d.vistoDispContar.Hasta != c.hasta {
				t.Errorf("el contador recibió [%v, %v] y tenía que ser [%v, %v]",
					d.vistoDispContar.Desde, d.vistoDispContar.Hasta, c.desde, c.hasta)
			}
		})
	}
}
