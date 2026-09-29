package store

// LAS GUARDAS DE SQL DE 00007, QUE NO SE PUEDEN PROBAR EJECUTANDO.
//
// Aquí no hay Postgres, así que lo que se vigila es lo que un `go test` sí puede ver: que
// el texto de las consultas siga diciendo lo que la migración da por hecho. Son tres cosas
// que, si se rompen, **no fallan**: dan un número creíble y equivocado, que es el fallo
// que más caro sale en este proyecto.
//
// Los comentarios se quitan ANTES de mirar, y eso no es cosmético: el 17/09/2026 un «;»
// dentro de un comentario dejó dormida la prueba que ataba el contador a su lista, y el
// «722 encima de una lista de 293» habría vuelto a pasar en verde. Aquí el peligro es el
// gemelo: los comentarios de este proyecto NOMBRAN las columnas que vigilan, así que una
// consulta que hubiera dejado de leer `peso_respaldado` seguiría «conteniéndolo» en su
// propio comentario y la prueba pasaría sin que la columna se lea.

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// sinComentarios deja el SQL de verdad: fuera todo lo que va detrás de un `--`.
func sinComentarios(sql string) string {
	var b strings.Builder
	for _, linea := range strings.Split(sql, "\n") {
		if i := strings.Index(linea, "--"); i >= 0 {
			linea = linea[:i]
		}
		b.WriteString(linea)
		b.WriteString("\n")
	}
	return b.String()
}

// consulta devuelve el cuerpo de una consulta con nombre, ya sin comentarios.
func consulta(t *testing.T, sql, nombre string) string {
	t.Helper()
	marca := "-- name: " + nombre + " "
	i := strings.Index(sql, marca)
	if i < 0 {
		t.Fatalf("no está la consulta %q", nombre)
	}
	limpio := sinComentarios(sql[i:])
	j := strings.Index(limpio, ";")
	if j < 0 {
		t.Fatalf("la consulta %q no se cierra", nombre)
	}
	return limpio[:j]
}

// ---------------------------------------------------------------------------
// 1. La duda del peso se lee de UN sitio, y las tres pantallas leen el mismo
// ---------------------------------------------------------------------------

// LAS TRES CONSULTAS CONTESTAN LA MISMA PREGUNTA, así que van atadas con una prueba y no
// con un comentario: un comentario no falla (`CLAUDE.md` §3-bis).
//
// La pregunta es «¿ese `weight` sale de algo?» y la contestan el catálogo, la lista del
// armador —la que alimenta la barra de capacidad del camión— y el detalle. Si una dejara
// de leerla, esa pantalla volvería a enseñar el kilo inventado como si fuera un kilo, y
// las otras dos seguirían en verde.
func TestLasTresConsultasLeenLaMismaDuda(t *testing.T) {
	sql := leerFichero(t, "orders.sql")

	for _, nombre := range []string{"ListarPedidosDisponibles", "ListarPedidos", "ObtenerPedido"} {
		cuerpo := consulta(t, sql, nombre)
		if !strings.Contains(cuerpo, "pp.peso_respaldado") {
			t.Errorf("%s ya no lee `pp.peso_respaldado`.\n"+
				"Sin ese campo, un pedido con el peso inventado sale igual que uno con el "+
				"peso de verdad: `weight` es NOT NULL y no sabe decir «no se sabe».", nombre)
		}
		if !strings.Contains(cuerpo, "peso_de_los_pedidos pp ON pp.id = o.id") {
			t.Errorf("%s no se une a `peso_de_los_pedidos`.\n"+
				"La respuesta tiene que salir de la vista, que es donde está escrita UNA vez: "+
				"tres copias de la misma regla acaban contestando tres cosas distintas.", nombre)
		}
	}
}

// Y NADIE SE ESCRIBE SU PROPIA VERSIÓN. Es la otra mitad: que las tres lean la vista no
// sirve de nada si mañana una cuarta se calcula el suyo con un `bool_or` a mano, porque
// entonces hay dos definiciones y la que se quede vieja no falla, miente.
func TestNadieSeCalculaLaDudaPorSuCuenta(t *testing.T) {
	for _, fichero := range []string{"orders.sql", "routes.sql", "tablero.sql"} {
		limpio := sinComentarios(leerFichero(t, fichero))
		if strings.Contains(limpio, "bool_or(") {
			t.Errorf("%s se calcula un `bool_or` por su cuenta.\n"+
				"La regla de «¿este peso sale de algo?» vive en la vista "+
				"`peso_de_los_pedidos` (00007_lo_que_no_se_sabe.sql) y sólo ahí. Dos "+
				"definiciones de lo mismo acaban discrepando y ninguna falla.", fichero)
		}
	}
}

// LA VISTA SE DEFINE UNA VEZ Y ESTÁ EN LAS MIGRACIONES. Si desapareciera, las tres
// consultas de arriba dejarían de compilar en Postgres — pero eso se descubre en el
// despliegue, no aquí.
func TestLaVistaDelPesoEstaDefinidaUnaVez(t *testing.T) {
	migraciones, err := filepath.Glob(filepath.Join("..", "..", "db", "migrations", "*.sql"))
	if err != nil || len(migraciones) == 0 {
		t.Fatalf("no se pudieron listar las migraciones: %v", err)
	}
	crea := regexp.MustCompile(`(?i)create\s+(or\s+replace\s+)?view\s+peso_de_los_pedidos`)
	n := 0
	for _, m := range migraciones {
		b, err := os.ReadFile(m)
		if err != nil {
			t.Fatalf("%s: %v", m, err)
		}
		n += len(crea.FindAllString(sinComentarios(string(b)), -1))
	}
	if n != 1 {
		t.Fatalf("la vista `peso_de_los_pedidos` se crea %d veces en las migraciones y tiene que ser 1", n)
	}
}

// ---------------------------------------------------------------------------
// 2. Ningún alta de pedido puede callarse el peso
// ---------------------------------------------------------------------------

// EL `DEFAULT 1` SE QUITÓ EN 00007, y esta prueba es la que evita que vuelva por la puerta
// de al lado.
//
// Mientras la columna tenía valor por defecto, un INSERT que se olvidara de `weight`
// escribía **1 kg** sin decir nada: un número perfectamente creíble para un paquete, que
// luego se suma en la tarjeta «Peso Total», en el Excel que alguien abre para cobrar y en
// la barra de capacidad del camión. Sin el DEFAULT ese olvido revienta contra el NOT NULL
// y se ve en el minuto uno.
//
// Aquí se vigila lo mismo un paso antes: que ningún alta de pedido deje de nombrar la
// columna. Es la única forma de que el fallo se vea escribiendo la consulta y no
// desplegando.
func TestTodaAltaDePedidoNombraElPeso(t *testing.T) {
	sql := sinComentarios(leerFichero(t, "orders.sql"))

	altas := regexp.MustCompile(`(?is)INSERT\s+INTO\s+orders\s*\(([^)]*)\)`).FindAllStringSubmatch(sql, -1)
	if len(altas) == 0 {
		t.Fatal("no se encontró ningún `INSERT INTO orders`: ¿cambió el nombre de la tabla?")
	}
	for _, a := range altas {
		columnas := a[1]
		if !regexp.MustCompile(`(?i)(^|[\s,])weight([\s,]|$)`).MatchString(columnas) {
			t.Errorf("hay un `INSERT INTO orders` que no nombra `weight`.\n"+
				"La columna es NOT NULL y ya NO tiene valor por defecto (00007): ese alta "+
				"revienta en Postgres. Y si alguien «lo arregla» devolviendo el DEFAULT, "+
				"vuelve el kilo inventado.\nColumnas: %s", strings.TrimSpace(columnas))
		}
	}
}

// ---------------------------------------------------------------------------
// 3. El total de la ruta no viaja solo
// ---------------------------------------------------------------------------

// `total_price` SUMA SÓLO LO COTIZADO, así que el número que dice cuántas faltan tiene que
// ir con él a todas partes. Donde se lee el total se lee el contador: en cuanto uno de los
// dos se quede por el camino, vuelve el `$0.00` de RT-20260921-007 — un cero que se lee
// como «el reparto fue gratis».
//
// La parte de ESCRIBIRLOS ya no se mira aquí y no es un olvido: desde el 29/09/2026
// ninguna consulta escribe ni el total ni su contador. Los mantiene la base en cada cambio
// de paradas, y lo vigila `totales_de_ruta_test.go` —que además ata la cuenta con su
// disparador—. Lo que queda aquí es que los dos números salgan JUNTOS a donde sea que
// vayan.
func TestElTotalDeLaRutaViajaConSuContador(t *testing.T) {
	sql := leerFichero(t, "routes.sql")

	for _, nombre := range []string{"ListarRutas", "ObtenerRuta", "FijarTotalesDeRuta"} {
		cuerpo := consulta(t, sql, nombre)
		if !strings.Contains(cuerpo, "total_price") {
			t.Fatalf("%s ya no lee `total_price`: esta prueba se quedó mirando otra cosa", nombre)
		}
		if !strings.Contains(cuerpo, "paradas_sin_cotizar") {
			t.Errorf("%s devuelve `total_price` sin `paradas_sin_cotizar`.\n"+
				"Quien lo lea verá un total que parece completo y no lo es, y no tendrá "+
				"nada con qué desmentirlo.", nombre)
		}
	}
}

// Y EL `DEFAULT 1` NO PUEDE VOLVER.
//
// Es la línea más pequeña de 00007 y la que más sostiene: mientras la columna tuvo valor
// por defecto, olvidarse de `weight` en un INSERT escribía un kilo en silencio. Devolverlo
// «para que no falle el alta» es exactamente la forma que tendría la vuelta atrás, y no
// rompería ninguna prueba de las de arriba — el alta seguiría funcionando, sólo que
// mintiendo.
//
// Se mira SÓLO la sección `Up` de cada migración: la `Down` de 00007 devuelve el DEFAULT a
// propósito, que es lo que tiene que hacer una vuelta atrás.
func TestElPesoNoRecuperaSuValorPorDefecto(t *testing.T) {
	migraciones, err := filepath.Glob(filepath.Join("..", "..", "db", "migrations", "*.sql"))
	if err != nil || len(migraciones) == 0 {
		t.Fatalf("no se pudieron listar las migraciones: %v", err)
	}
	sort.Strings(migraciones) // 00001, 00002, … el orden en que se aplican

	pone := regexp.MustCompile(`(?is)alter\s+column\s+weight\s+set\s+default`)
	quita := regexp.MustCompile(`(?is)alter\s+column\s+weight\s+drop\s+default`)

	ultimo, dondeUltimo := "", ""
	for _, m := range migraciones {
		b, err := os.ReadFile(m)
		if err != nil {
			t.Fatalf("%s: %v", m, err)
		}
		texto := sinComentarios(string(b))
		if i := strings.Index(texto, "+goose Down"); i >= 0 {
			texto = texto[:i]
		}
		for _, sitio := range pone.FindAllStringIndex(texto, -1) {
			_ = sitio
			ultimo, dondeUltimo = "pone", filepath.Base(m)
		}
		for _, sitio := range quita.FindAllStringIndex(texto, -1) {
			_ = sitio
			ultimo, dondeUltimo = "quita", filepath.Base(m)
		}
	}
	if ultimo != "quita" {
		t.Fatalf("`orders.weight` vuelve a tener valor por defecto (lo último que lo toca es %q en %s).\n"+
			"Con DEFAULT, un INSERT que se olvide del peso escribe 1 kg sin decir nada, y "+
			"ese kilo se suma en «Peso Total», en el Excel que alguien abre para cobrar y "+
			"en la barra de capacidad del camión. Sin él, el olvido revienta y se ve.",
			ultimo, dondeUltimo)
	}
}
