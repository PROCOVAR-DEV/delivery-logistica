package api

// «SIN COLOCAR» SE ACOTA POR UN RANGO DE FECHAS DEL PEDIDO — issue 13 de Amado, 15/10/2026.
//
// «El filtro de pedidos necesita que tenga un rango de fecha desde/hasta, además de la del
// día que existe hoy.» La mitad izquierda del tablero sólo sabía de UN día (`dia`). Ahora
// lleva `diaDesde`/`diaHasta` (no `desde`, que aquí es el cursor), los dos días incluidos, y
// `dia` se sigue aceptando. Las pruebas van en pareja: lo que cae en el rango ENTRA, en los
// dos bordes, y lo de fuera NO entra; y el total dice lo mismo que la lista.
//
// Esto prueba el manejador contra el doble. Que el SQL de verdad haga lo mismo lo prueba
// `TestMotorReal_SinColocarPorRangoDeFechas`.

import (
	"fmt"
	"net/http"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func TestRangoDelPedido(t *testing.T) {
	dia := func(s string) pgtype.Timestamptz {
		d, err := time.Parse("2006-01-02", s)
		if err != nil {
			t.Fatal(err)
		}
		return pgtype.Timestamptz{Time: d, Valid: true}
	}
	nada := pgtype.Timestamptz{}
	for _, c := range []struct {
		nombre, query string
		desde, hasta  pgtype.Timestamptz
	}{
		{"sin nada no acota", "", nada, nada},
		{"el día suelto de siempre: ese día entero", "dia=2026-10-03", dia("2026-10-03"), dia("2026-10-04")},
		{"el rango: el hasta llega al día SIGUIENTE, o sea incluido", "diaDesde=2026-10-01&diaHasta=2026-10-03", dia("2026-10-01"), dia("2026-10-04")},
		{"sólo desde", "diaDesde=2026-10-01", dia("2026-10-01"), nada},
		{"sólo hasta", "diaHasta=2026-10-03", nada, dia("2026-10-04")},
		{"un día como rango es el día suelto", "diaDesde=2026-10-03&diaHasta=2026-10-03", dia("2026-10-03"), dia("2026-10-04")},
		{"dia y rango a la vez: el tramo común", "dia=2026-10-02&diaDesde=2026-10-01&diaHasta=2026-10-05", dia("2026-10-02"), dia("2026-10-03")},
		{"una fecha mal escrita no acota", "diaDesde=03-10-2026", nada, nada},
		{"el cursor `desde` NO es una fecha", "desde=2026-10-01T00:00:00Z|" + uuid.NewString(), nada, nada},
	} {
		t.Run(c.nombre, func(t *testing.T) {
			r, _ := http.NewRequest(http.MethodGet, "/x?"+strings.ReplaceAll(c.query, "|", "%7C"), nil)
			desde, hasta := rangoDelPedido(r.URL.Query())
			if desde != c.desde || hasta != c.hasta {
				t.Errorf("%q → [%v, %v) y tenía que ser [%v, %v)", c.query, desde, hasta, c.desde, c.hasta)
			}
		})
	}
}

func TestSinColocarPorRangoDeFechas(t *testing.T) {
	q := nuevoTablero()
	// Los del 3 a última hora y los del 1 a primera: son los bordes que un `<` o un `>`
	// de más se come. Los tres de base no tienen fecha y quedan fuera con cualquier rango.
	for i, cuando := range []time.Time{
		time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC),
		time.Date(2026, 10, 3, 23, 30, 0, 0, time.UTC),
		time.Date(2026, 10, 4, 0, 0, 0, 0, time.UTC),
	} {
		id := uuid.MustParse(fmt.Sprintf("5f000000-0000-0000-0000-%012d", i+1))
		f := cuando
		q.pedidos[id] = pedidoFalso{
			id: id, sucursal: sucStg, nombre: fmt.Sprintf("del %d", cuando.Day()),
			peso: 1, lat: 20.0247, lng: -75.8219, fecha: &f,
		}
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	for _, c := range []struct {
		query string
		salen []string
	}{
		{"diaDesde=2026-10-01&diaHasta=2026-10-03", []string{"del 1", "del 3"}},
		{"diaDesde=2026-10-04", []string{"del 4"}},
		{"diaHasta=2026-10-03", []string{"del 1", "del 3"}},
		{"diaDesde=2026-10-02&diaHasta=2026-10-02", nil},
		{"dia=2026-10-03", []string{"del 3"}},
	} {
		t.Run(c.query, func(t *testing.T) {
			for _, ruta := range []string{"/api/board/unplaced?", "/api/board?branchId=" + sucStg.String() + "&"} {
				w := pedirTab(t, h, http.MethodGet, ruta+c.query, jwt, "")
				if w.Code != http.StatusOK {
					t.Fatalf("%s: código %d — %s", ruta, w.Code, w.Body.String())
				}
				m := leerTab(t, w)
				if izq, ok := m["sinColocar"].(map[string]any); ok {
					m = izq // `/api/board` la trae dentro
				}
				var salen []string
				for _, p := range m["pedidos"].([]any) {
					salen = append(salen, p.(map[string]any)["customerName"].(string))
				}
				sort.Strings(salen)
				if strings.Join(salen, ",") != strings.Join(c.salen, ",") {
					t.Errorf("%s%s: salen %v y tenían que salir %v", ruta, c.query, salen, c.salen)
				}
				if total, _ := m["total"].(float64); int(total) != len(c.salen) {
					t.Errorf("%s%s: el total dice %v encima de una lista de %d", ruta, c.query, total, len(c.salen))
				}
			}
		})
	}
}
