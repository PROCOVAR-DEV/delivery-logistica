package store

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// EL CONTADOR Y LA LISTA TIENEN QUE FILTRAR LO MISMO.
//
// `ListarPedidosSinColocar` llena la mitad izquierda del tablero y
// `ContarPedidosSinColocar` pone el número que va encima. Si los dos `WHERE` se
// separan, el número miente — y miente de la peor manera, porque sale solo y no
// hay nada al lado con qué compararlo: «722» se lee igual de bien que «293».
//
// Pasó. A la lista se le añadió `AND NOT o.archivado` el 15/09/2026 (PEDIDO
// archiva de baja y son la inmensa mayoría del histórico) y al contador no. Con
// los datos de La Habana del 17/09/2026 —728 pedidos, 429 archivados, 6
// colocados— el tablero decía «Sin colocar (722)» encima de una lista de 293.
// Tres días así, sin un solo error en ningún registro.
//
// Esto no sustituye a probarlo contra Postgres; lo que hace es vigilar el
// contrato que de verdad se rompió, que es textual: **el mismo WHERE**. Y corre
// en cualquier sitio, que es justo lo que hace falta en una máquina sin base.
func TestElContadorFiltraLoMismoQueLaLista(t *testing.T) {
	sql := leerConsultas(t)

	lista := filtrosDe(t, sql, "ListarPedidosSinColocar")
	contador := filtrosDe(t, sql, "ContarPedidosSinColocar")

	faltan := loQueFaltaEn(contador, lista)
	if len(faltan) > 0 {
		t.Errorf(
			"ContarPedidosSinColocar no filtra lo que sí filtra ListarPedidosSinColocar: %v\n"+
				"El número saldría por encima de lo que hay en la lista. Añádeselo, o si de "+
				"verdad tiene que ser distinto, explícalo en el SQL y cambia esta prueba.",
			faltan,
		)
	}

	sobran := loQueFaltaEn(lista, contador)
	if len(sobran) > 0 {
		t.Errorf(
			"ContarPedidosSinColocar filtra de más, cosas que la lista no filtra: %v\n"+
				"El número saldría por debajo de lo que hay en la lista.",
			sobran,
		)
	}
}

// Y TAMBIÉN TIENEN QUE MIRAR LAS MISMAS TABLAS.
//
// La comprobación de arriba sólo lee el `WHERE`, y con eso sola se puede romper
// el contrato sin que se entere. El auditor lo hizo el 17/09/2026: le puso a la
// lista un `JOIN branches b ON b.id = o.branch_id AND b.origin_configured` y la
// prueba siguió en verde — mismo fallo de siempre, el número por encima de la
// lista, y nadie avisando.
//
// Un `JOIN` filtra igual que un `WHERE`; que se escriba en otra línea es cosa de
// SQL, no del contrato. Así que se comparan los dos.
func TestElContadorMiraLasMismasTablasQueLaLista(t *testing.T) {
	sql := leerConsultas(t)

	lista := desdeDe(t, sql, "ListarPedidosSinColocar")
	contador := desdeDe(t, sql, "ContarPedidosSinColocar")

	if lista != contador {
		t.Errorf(
			"ListarPedidosSinColocar y ContarPedidosSinColocar no leen de lo mismo.\n"+
				"  lista:    %s\n"+
				"  contador: %s\n"+
				"Un JOIN filtra igual que un WHERE: si sólo lo lleva uno de los dos, el "+
				"número no cuadra con la lista que hay debajo.",
			lista, contador,
		)
	}
}

// El `FROM` con sus `JOIN`, normalizado: desde `FROM` hasta el `WHERE`.
func desdeDe(t *testing.T, sql, nombre string) string {
	t.Helper()
	cuerpo := cuerpoDe(t, sql, nombre)

	i := strings.Index(cuerpo, "\nFROM")
	if i < 0 {
		t.Fatalf("la consulta %q no tiene FROM", nombre)
	}
	cuerpo = cuerpo[i+1:]
	if j := strings.Index(cuerpo, "\nWHERE"); j >= 0 {
		cuerpo = cuerpo[:j]
	}

	var limpio []string
	for _, linea := range strings.Split(cuerpo, "\n") {
		if soloComentario.MatchString(linea) {
			continue
		}
		limpio = append(limpio, linea)
	}
	return espacios.ReplaceAllString(strings.TrimSpace(strings.Join(limpio, " ")), " ")
}

func leerConsultas(t *testing.T) string {
	t.Helper()
	ruta := filepath.Join("..", "..", "db", "queries", "tablero.sql")
	b, err := os.ReadFile(ruta)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", ruta, err)
	}
	return string(b)
}

// El cuerpo de una consulta, desde su `-- name:` hasta el `;` que la cierra.
func cuerpoDe(t *testing.T, sql, nombre string) string {
	t.Helper()
	marca := "-- name: " + nombre + " "
	i := strings.Index(sql, marca)
	if i < 0 {
		t.Fatalf("no está la consulta %q en tablero.sql", nombre)
	}
	resto := sql[i:]

	// EL «;» QUE CIERRA, NO EL PRIMERO QUE APAREZCA.
	//
	// Esto buscaba el primer «;» del texto, y un «;» dentro de un COMENTARIO
	// cortaba el cuerpo ahí: todo lo que viniera después dejaba de compararse, en
	// verde. Lo cazó un agente el 17/09/2026 escribiendo un comentario con un
	// «…del almacén; o», que dejó dormido justo al vigilante del «722 encima de
	// una lista de 293».
	//
	// Una prueba que se apaga sola según cómo alguien redacte un comentario no es
	// una prueba. Se quitan los comentarios primero y se corta después.
	var limpio strings.Builder
	for _, linea := range strings.Split(resto, "\n") {
		if j := strings.Index(linea, "--"); j >= 0 {
			linea = linea[:j]
		}
		limpio.WriteString(linea)
		limpio.WriteString("\n")
	}
	fin := strings.Index(limpio.String(), ";")
	if fin < 0 {
		t.Fatalf("la consulta %q no termina en «;»", nombre)
	}
	return limpio.String()[:fin]
}

var (
	soloComentario = regexp.MustCompile(`^\s*--`)
	espacios       = regexp.MustCompile(`\s+`)
)

// Las condiciones del WHERE, normalizadas y sin comentarios.
//
// Se parte por `AND` al principio de línea, que es como está escrito este
// fichero de punta a punta. Las condiciones de varias líneas (los `OR` de la
// caja de búsqueda, los rangos de fecha) se juntan en una sola, así que un
// cambio dentro de una de ellas también se nota.
func filtrosDe(t *testing.T, sql, nombre string) []string {
	t.Helper()
	cuerpo := cuerpoDe(t, sql, nombre)

	// EL `WHERE` PUEDE IR SANGRADO, y eso no es cosmético: desde el 01/10/2026 hay consultas
	// cuyo cuerpo va dentro de un CTE (`WITH puesta AS ( … )`), porque el `RETURNING` de un
	// `INSERT` no puede nombrar los `FROM` de su propio `SELECT` y hacía falta sacar el
	// `branch_id` de la columna para el aviso en vivo. Buscando `"\nWHERE"` a secas, esas
	// consultas contestaban «no tiene WHERE» y **el vigilante se apagaba entero**: no es que
	// fallara la comprobación, es que ya no comprobaba las guardas de dentro.
	m := inicioDelWhere.FindStringIndex(cuerpo)
	if m == nil {
		t.Fatalf("la consulta %q no tiene WHERE", nombre)
	}
	cuerpo = cuerpo[m[1]:]
	// Lo que va después del WHERE y no es filtro. También sangrados, por lo mismo de arriba, y
	// con los dos que cierran un `INSERT … RETURNING` dentro de un CTE: sin ellos, el
	// `ON CONFLICT` y el `RETURNING` se pegarían a la última condición y dejarían de casar.
	if j := finDelWhere.FindStringIndex(cuerpo); j != nil {
		cuerpo = cuerpo[:j[0]]
	}

	var condiciones []string
	var actual strings.Builder
	guardar := func() {
		texto := espacios.ReplaceAllString(strings.TrimSpace(actual.String()), " ")
		if texto != "" {
			condiciones = append(condiciones, texto)
		}
		actual.Reset()
	}
	for _, linea := range strings.Split(cuerpo, "\n") {
		if soloComentario.MatchString(linea) {
			continue
		}
		if strings.HasPrefix(strings.TrimSpace(linea), "AND ") {
			guardar()
			linea = strings.TrimSpace(linea)[len("AND "):]
		}
		actual.WriteString(" ")
		actual.WriteString(linea)
	}
	guardar()

	sort.Strings(condiciones)
	return condiciones
}

// inicioDelWhere y finDelWhere delimitan el `WHERE` DE UNA CONSULTA, con o sin sangría.
//
// `(?m)` para que `^` sea principio de línea y no de texto: así una condición que lleve la
// palabra `where` dentro de una cadena no abre un `WHERE` falso.
var (
	inicioDelWhere = regexp.MustCompile(`(?m)^[ \t]*WHERE`)
	finDelWhere    = regexp.MustCompile(`(?m)^[ \t]*(ORDER BY|GROUP BY|LIMIT|ON CONFLICT|RETURNING)`)
)

// Lo que está en `referencia` y no en `esto`.
func loQueFaltaEn(esto, referencia []string) []string {
	tiene := make(map[string]bool, len(esto))
	for _, c := range esto {
		tiene[c] = true
	}
	var faltan []string
	for _, c := range referencia {
		if !tiene[c] {
			faltan = append(faltan, c)
		}
	}
	return faltan
}
