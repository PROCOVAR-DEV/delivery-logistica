package store

import (
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// EL ORDEN DE LA LISTA Y SU CURSOR TIENEN QUE SER LA MISMA PAREJA.
//
// Desde el 14/10/2026 la mitad izquierda del tablero va del más viejo al más reciente por la
// fecha de la factura (issue 6 de Amado, punto 2): `ORDER BY fecha_cronologica ASC NULLS
// LAST, o.id ASC`, con `fecha_cronologica = coalesce(o.factura_at, o.order_date)`. Antes era
// `km ASC, order_date DESC NULLS LAST, id ASC` y el cursor llevaba esa terna.
//
// Un cursor que no es la pareja del `ORDER BY` es el fallo que más caro sale en esta casa
// (CLAUDE.md §3: pedir un tope y no poder seguir): la tanda siguiente repite una fila o se
// salta otra, y la pantalla se queda perfectamente normal. Por eso esto es una prueba y no
// un comentario (§3-bis).
//
// Lo que ata ESTA prueba es textual y corre en cualquier sitio: que el `ORDER BY` sea el
// esperado, que la fecha del cursor sea la MISMA expresión que la de la columna por la que
// se ordena, y que ni los km ni el viejo `desde_km` hayan vuelto. Que la lista REALMENTE
// salga en ese orden y que pagine entera sin repetir ni saltar lo ata, contra Postgres de
// verdad, `TestMotorReal_SinColocarCronologico` (`internal/store/sqlc`).
//
// Está en una función aparte (`problemasDeOrdenYCursor`) para poder probarla EN PAREJA: una
// SQL sana no da problemas y la misma SQL rota de varias maneras los da. Una guarda que no
// se ha visto fallar no es una guarda.

var (
	columnaDeOrden = regexp.MustCompile(`(?m)^\s*(coalesce\([^)]*\))::timestamptz AS fecha_cronologica`)
	clausulaOrden  = regexp.MustCompile(`(?m)^ORDER BY (.+)$`)
)

const ordenEsperado = "fecha_cronologica ASC NULLS LAST, o.id ASC"

// problemasDeOrdenYCursor devuelve lo que está mal en el SQL de la lista, o nada.
func problemasDeOrdenYCursor(sql string) []string {
	var problemas []string

	orden := clausulaOrden.FindStringSubmatch(sql)
	if orden == nil {
		return []string{"la lista no tiene ORDER BY"}
	}
	if strings.TrimSpace(orden[1]) != ordenEsperado {
		problemas = append(problemas, "el ORDER BY es «"+strings.TrimSpace(orden[1])+
			"» y tendría que ser «"+ordenEsperado+"»")
	}
	if strings.Contains(orden[1], "km") {
		problemas = append(problemas, "los kilómetros han vuelto al ORDER BY: Amado pidió cronológico")
	}

	col := columnaDeOrden.FindStringSubmatch(sql)
	if col == nil {
		return append(problemas, "la lista no define `fecha_cronologica` como coalesce(...)::timestamptz")
	}
	expresion := col[1]

	// El cursor es la condición que empieza en `desde_id IS NULL` y llega hasta el ORDER BY.
	i := strings.Index(sql, "sqlc.narg('desde_id')::uuid IS NULL")
	if i < 0 {
		return append(problemas, "la lista no lleva el cursor `desde_id`")
	}
	cursor := sql[i:]
	if j := strings.Index(cursor, "ORDER BY"); j >= 0 {
		cursor = cursor[:j]
	}
	if strings.Contains(cursor, "desde_km") || strings.Contains(cursor, "km_haversine") {
		problemas = append(problemas, "el cursor todavía compara kilómetros: ya no son parte del orden")
	}
	// La fecha del cursor es la misma expresión que la de la columna: se compara con ella,
	// se pregunta si es nula y se pregunta `IS NOT DISTINCT FROM`. Tres usos.
	if n := strings.Count(cursor, expresion); n < 3 {
		problemas = append(problemas, "el cursor usa la fecha por la que se ordena `"+expresion+
			"` solo "+strconv.Itoa(n)+" veces y hacen falta 3 (mayor, nula y empate)")
	}
	if !strings.Contains(cursor, "> sqlc.narg('desde_fecha')::timestamptz") {
		problemas = append(problemas, "el cursor no pasa a los de fecha MÁS RECIENTE (`>`): el orden es ascendente")
	}
	if !strings.Contains(cursor, "IS NOT DISTINCT FROM sqlc.narg('desde_fecha')::timestamptz") {
		problemas = append(problemas, "el cursor no compara la fecha con IS NOT DISTINCT FROM: "+
			"un cursor sobre un pedido sin fecha repetiría o saltaría filas")
	}
	if !strings.Contains(cursor, "o.id > sqlc.narg('desde_id')::uuid") {
		problemas = append(problemas, "el cursor no desempata por `o.id >`")
	}
	return problemas
}

func TestElOrdenDeLaListaYSuCursorSonLaMismaPareja(t *testing.T) {
	lista := cuerpoDe(t, leerConsultas(t), "ListarPedidosSinColocar")
	if problemas := problemasDeOrdenYCursor(lista); len(problemas) > 0 {
		t.Errorf("ListarPedidosSinColocar: el orden y su cursor no coinciden:\n  - %s\n"+
			"El cursor tiene que ser la pareja del ORDER BY o la tanda siguiente repite "+
			"o salta pedidos (CLAUDE.md §3).", strings.Join(problemas, "\n  - "))
	}
}

// LA PAREJA DE LA PRUEBA DE ARRIBA: la misma SQL, rota de cinco maneras, TIENE que dar
// problemas. Sin esto, una guarda que siempre dice «bien» pasaría por buena.
func TestLaGuardaDelOrdenYCursorSabeFallar(t *testing.T) {
	sana := cuerpoDe(t, leerConsultas(t), "ListarPedidosSinColocar")
	if p := problemasDeOrdenYCursor(sana); len(p) > 0 {
		t.Fatalf("la SQL real ya da problemas, la pareja no se puede leer: %v", p)
	}

	roturas := map[string]string{
		"vuelven los km al ORDER BY": strings.Replace(sana,
			"ORDER BY fecha_cronologica ASC NULLS LAST, o.id ASC",
			"ORDER BY km_al_almacen ASC, fecha_cronologica ASC NULLS LAST, o.id ASC", 1),
		"se ordena descendente": strings.Replace(sana,
			"ORDER BY fecha_cronologica ASC NULLS LAST, o.id ASC",
			"ORDER BY fecha_cronologica DESC NULLS LAST, o.id ASC", 1),
		"el cursor ordena por otra fecha": strings.Replace(sana,
			"coalesce(o.factura_at, o.order_date) > sqlc.narg('desde_fecha')",
			"o.order_date > sqlc.narg('desde_fecha')", 1),
		"el cursor pierde el empate por id": strings.Replace(sana,
			"AND o.id > sqlc.narg('desde_id')::uuid", "AND o.id >= sqlc.narg('desde_id')::uuid", 1),
		"el cursor compara con = y no con IS NOT DISTINCT FROM": strings.Replace(sana,
			"IS NOT DISTINCT FROM sqlc.narg('desde_fecha')", "= sqlc.narg('desde_fecha')", 1),
	}
	for nombre, rota := range roturas {
		if rota == sana {
			t.Fatalf("%s: la rotura no cambió nada, la prueba no prueba", nombre)
		}
		if len(problemasDeOrdenYCursor(rota)) == 0 {
			t.Errorf("%s: la guarda NO lo vio", nombre)
		}
	}
}
