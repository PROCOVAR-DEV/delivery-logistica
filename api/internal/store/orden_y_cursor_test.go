package store

import (
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// EL ORDEN DE LA LISTA Y SU CURSOR TIENEN QUE SER LA MISMA TERNA.
//
// Desde el 14/10/2026 la mitad izquierda del tablero va del más viejo al más reciente por la
// fecha de la factura (issue 6 de Amado, punto 2), con `fecha_cronologica =
// coalesce(o.factura_at, o.order_date)`. Y desde el 15/10/2026 (Jose), con un almacén elegido
// arriba, van PRIMERO los pedidos de ese almacén del más cercano al más lejano: la primera
// clave es `cercania_de_orden`, la distancia para los suyos e infinito para los demás. El
// `ORDER BY` es `cercania_de_orden ASC, fecha_cronologica ASC NULLS LAST, o.id ASC` y el
// cursor lleva esa terna.
//
// Un cursor que no es la terna del `ORDER BY` es el fallo que más caro sale en esta casa
// (CLAUDE.md §3: pedir un tope y no poder seguir): la tanda siguiente repite una fila o se
// salta otra, y la pantalla se queda perfectamente normal. Por eso esto es una prueba y no
// un comentario (§3-bis).
//
// Lo que ata ESTA prueba es textual y corre en cualquier sitio: que el `ORDER BY` sea el
// esperado, y que la cercanía y la fecha del cursor sean las MISMAS expresiones que las
// columnas por las que se ordena. Que la lista REALMENTE salga en ese orden y que pagine
// entera sin repetir ni saltar —también a través de la frontera entre los del almacén y los
// demás— lo atan, contra Postgres de verdad, `TestMotorReal_SinColocarCronologico` y
// `TestMotorReal_SinColocarConAlmacenElegido` (`internal/store/sqlc`).
//
// Está en una función aparte (`problemasDeOrdenYCursor`) para poder probarla EN PAREJA: una
// SQL sana no da problemas y la misma SQL rota de varias maneras los da. Una guarda que no
// se ha visto fallar no es una guarda.

var (
	columnaDeOrden    = regexp.MustCompile(`(?m)^\s*(coalesce\([^)]*\))::timestamptz AS fecha_cronologica`)
	columnaDeCercania = regexp.MustCompile(`(?m)^\s*(\(CASE .+ END\)::float8) AS cercania_de_orden`)
	clausulaOrden     = regexp.MustCompile(`(?m)^ORDER BY (.+)$`)
)

const ordenEsperado = "cercania_de_orden ASC, fecha_cronologica ASC NULLS LAST, o.id ASC"

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

	col := columnaDeOrden.FindStringSubmatch(sql)
	if col == nil {
		return append(problemas, "la lista no define `fecha_cronologica` como coalesce(...)::timestamptz")
	}
	expresion := col[1]

	cer := columnaDeCercania.FindStringSubmatch(sql)
	if cer == nil {
		return append(problemas, "la lista no define `cercania_de_orden` como (CASE ... END)::float8 en una línea")
	}
	cercania := cer[1]
	// Lo que hace la cercanía, pieza por pieza: los del código elegido miden desde el origen,
	// y los demás valen infinito, que es lo que los manda DETRÁS con la fecha como orden.
	for _, pieza := range []string{
		"upper(btrim(o.almacen_salida_codigo)) = upper(btrim(sqlc.narg('primero_codigo')::text))",
		"THEN km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng)",
		"ELSE 'Infinity'::float8 END",
	} {
		if !strings.Contains(cercania, pieza) {
			problemas = append(problemas, "la cercanía de orden no lleva «"+pieza+"»: "+
				"los del almacén elegido van primero por su distancia y los demás valen infinito")
		}
	}

	// El cursor es la condición que empieza en `desde_id IS NULL` y llega hasta el ORDER BY.
	i := strings.Index(sql, "sqlc.narg('desde_id')::uuid IS NULL")
	if i < 0 {
		return append(problemas, "la lista no lleva el cursor `desde_id`")
	}
	cursor := sql[i:]
	if j := strings.Index(cursor, "ORDER BY"); j >= 0 {
		cursor = cursor[:j]
	}
	// La cercanía del cursor es la misma expresión que la de la columna: «mayor» y «empate».
	if n := strings.Count(cursor, cercania); n < 2 {
		problemas = append(problemas, "el cursor usa la cercanía por la que se ordena solo "+
			strconv.Itoa(n)+" veces y hacen falta 2 (mayor y empate)")
	}
	if !strings.Contains(cursor, cercania+" > sqlc.narg('desde_cercania')::float8") {
		problemas = append(problemas, "el cursor no pasa a los de cercanía MAYOR (`>`): el orden es ascendente")
	}
	if !strings.Contains(cursor, cercania+" = sqlc.narg('desde_cercania')::float8") {
		problemas = append(problemas, "el cursor no mira la fecha y el id DENTRO de la misma cercanía (`=`)")
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
		"la cercanía sale del ORDER BY": strings.Replace(sana,
			"ORDER BY cercania_de_orden ASC, fecha_cronologica ASC NULLS LAST, o.id ASC",
			"ORDER BY fecha_cronologica ASC NULLS LAST, o.id ASC", 1),
		"se ordena por los km de todos y no por la cercanía de los del almacén": strings.Replace(sana,
			"ORDER BY cercania_de_orden ASC,", "ORDER BY km_al_almacen ASC,", 1),
		"la cercanía va descendente": strings.Replace(sana,
			"ORDER BY cercania_de_orden ASC,", "ORDER BY cercania_de_orden DESC,", 1),
		"se ordena descendente": strings.Replace(sana,
			"fecha_cronologica ASC NULLS LAST, o.id ASC",
			"fecha_cronologica DESC NULLS LAST, o.id ASC", 1),
		"los demás ya no van detrás (cero en vez de infinito)": strings.ReplaceAll(sana,
			"ELSE 'Infinity'::float8 END", "ELSE 0::float8 END"),
		"la cercanía del cursor se mide desde otro sitio": strings.Replace(sana,
			"THEN km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng')",
			"THEN km_haversine(sqlc.arg('origen_lng'), sqlc.arg('origen_lat')", 1),
		"el cursor repite la última fila de la cercanía (>=)": strings.Replace(sana,
			"> sqlc.narg('desde_cercania')", ">= sqlc.narg('desde_cercania')", 1),
		"el cursor no mira la fecha dentro de la misma cercanía": strings.Replace(sana,
			"= sqlc.narg('desde_cercania')::float8\n", "<> sqlc.narg('desde_cercania')::float8\n", 1),
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
