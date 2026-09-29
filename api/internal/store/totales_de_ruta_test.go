package store

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// LOS TOTALES DE UNA RUTA NO PUEDEN VOLVER A CONGELARSE.
//
// `routes.total_weight` y `routes.total_price` se escribían UNA vez, al armar, y nadie las
// recalculaba. Mordió dos veces, y las dos con un número que se lee bien:
//
//   - 22/09/2026 — `RT-20260921-007` decía `$0.00` con sus dos paradas marcadas «sin
//     cotizar» y el camión a 1,50 USD/km. Un cero no dice «no hay tarifa».
//   - 28/09/2026 — la cabecera de `RT-20260928-003` decía **420 kg** encima de dos paradas
//     de 419,7 y 96,8. Y la capacidad del camión se medía contra esa columna.
//
// Desde el 29/09/2026 esas tres columnas —las dos y su `paradas_sin_cotizar`— son un
// espejo que mantiene la base en cada cambio de paradas
// (`db/migrations/00014_los_totales_de_la_ruta_no_se_congelan.sql`). Estas pruebas vigilan
// las dos formas que tiene esa decisión de deshacerse sola, que son las dos que ya se han
// visto en este proyecto: que alguien vuelva a escribirlas a mano desde una consulta, y
// que la cuenta y su disparador se separen sin que salte nada (`CLAUDE.md` §3-bis).

// ---------------------------------------------------------------------------
// 1. Nadie más escribe esas tres columnas
// ---------------------------------------------------------------------------

// Un `SET total_weight = …` en cualquier consulta devuelve el problema entero: esa consulta
// corre cuando corre —al armar, casi siempre— y a partir de ahí la columna se queda con el
// número de aquel día mientras sus paradas siguen moviéndose. Y encima serían DOS
// aritméticas para el mismo número, que es como se separan (`CLAUDE.md` §3-sexies: «la
// regla vive en UN sitio, no en tres»).
//
// Leer y devolverlas sí se puede, y por eso se mira el `SET` y no el fichero entero: las
// consultas las devuelven en su `RETURNING` y en sus `SELECT`.
func TestNingunaConsultaEscribeLosTotalesDeLaRuta(t *testing.T) {
	ficheros, err := filepath.Glob(filepath.Join("..", "..", "db", "queries", "*.sql"))
	if err != nil || len(ficheros) == 0 {
		t.Fatalf("no se pudieron listar las consultas: %v", err)
	}
	sort.Strings(ficheros)

	// `columna =` dentro de una lista de asignaciones. El `RETURNING` y los `SELECT` no
	// asignan, así que no caen aquí.
	asigna := regexp.MustCompile(`(?i)(^|[\s,(])(total_weight|total_price|paradas_sin_cotizar)\s*=`)

	for _, f := range ficheros {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("%s: %v", f, err)
		}
		texto := sinComentarios(string(b))
		for _, trozo := range asigna.FindAllStringSubmatch(texto, -1) {
			t.Errorf("%s asigna `%s` en una consulta.\n"+
				"Esas tres columnas son la suma de las paradas de la ruta y las mantiene la "+
				"base en cada cambio de paradas (00014). Una consulta las escribe cuando "+
				"corre y nunca más: es el `$0.00` del 22/09 y los «420 kg» sobre 516,5 del "+
				"28/09, otra vez. Si de verdad hace falta escribirlas desde SQL, hazlo con "+
				"`fijar_espejo_de_totales_de_ruta(ruta)`, que es quien sabe la cuenta.",
				filepath.Base(f), strings.TrimSpace(trozo[2]))
		}
	}
}

// ---------------------------------------------------------------------------
// 2. La cuenta y su disparador miran lo MISMO
// ---------------------------------------------------------------------------

// ÉSTE ES EL §3-bis DE ESTA MIGRACIÓN, y el fallo que vigila es silencioso de verdad.
//
// `totales_de_ruta` lee tres columnas de `orders` —de cuál es la ruta, cuánto pesa y
// cuánto cuesta— y el trigger `trg_orders_totales_de_ruta` sólo se dispara sobre las
// columnas que nombra su `UPDATE OF`. Si la cuenta empieza a mirar una cuarta y esa cuarta
// no se añade al disparador, la ruta deja de enterarse de ese sumando: el total se congela
// **sólo para él**, sin un error, sin una fila de más ni de menos, con toda la suite en
// verde. Es exactamente lo que le pasó al contador del tablero el 17/09/2026, que se quedó
// sin un `AND NOT o.archivado` y estuvo tres días diciendo 722 sobre una lista de 293.
//
// Al revés también se mira: un `UPDATE OF` que nombre una columna que la cuenta ya no lee
// es trabajo por nada en la tabla que más se escribe de todas —el espejo repasa 5.452
// pedidos cada minuto—, y además señal de que uno de los dos se quedó a medio cambiar.
func TestElTriggerVigilaLasColumnasQueLaCuentaLee(t *testing.T) {
	sql := migracionDeLosTotales(t)

	lee := columnasQueLeeLaCuenta(t, sql)
	vigila := columnasDelUpdateOf(t, sql)

	if faltan := loQueFaltaEn(vigila, lee); len(faltan) > 0 {
		t.Errorf("`trg_orders_totales_de_ruta` no se dispara con %v, y `totales_de_ruta` las lee.\n"+
			"El total de la ruta dejaría de enterarse de ese sumando y se quedaría con el "+
			"número del día del armado, sin un solo error en ningún sitio. Añádelas al "+
			"`UPDATE OF` del trigger.", faltan)
	}
	if sobran := loQueFaltaEn(lee, vigila); len(sobran) > 0 {
		t.Errorf("`trg_orders_totales_de_ruta` se dispara con %v y `totales_de_ruta` ya no las lee.\n"+
			"Eso es recalcular el espejo de una ruta entera por un cambio que no le afecta, "+
			"en la tabla que más se escribe del reparto. O uno de los dos se quedó a medio "+
			"cambiar.", sobran)
	}
}

// Y LOS TRES MOMENTOS EN QUE UNA RUTA PUEDE CAMBIAR DE PARADAS.
//
// Sin `DELETE`, borrar un pedido deja a su ruta contando un peso que ya no lleva. Sin
// `INSERT`, un pedido que naciera ya enganchado no se sumaría. Sin `UPDATE`, que es el
// camino de todos los días —el espejo pisando `weight` y `pedido_costo` cada minuto, y
// `EngancharPedidoARuta` poniendo `ultima_ruta_id`—, no queda nada en pie.
func TestElTriggerSeDisparaEnLosTresMomentos(t *testing.T) {
	sql := migracionDeLosTotales(t)

	cabecera := entre(t, sql, "CREATE TRIGGER trg_orders_totales_de_ruta", " ON orders")
	for _, momento := range []string{"INSERT", "DELETE", "UPDATE"} {
		if !strings.Contains(cabecera, momento) {
			t.Errorf("`trg_orders_totales_de_ruta` ya no se dispara con %s.\n"+
				"Los totales de la ruta se quedarían congelados justo en ese camino y en "+
				"ningún otro, que es la forma de fallar más cara de este proyecto.\n"+
				"Ahora mismo: %s", momento, strings.TrimSpace(cabecera))
		}
	}
}

// LAS PARADAS DE UNA RUTA SON LAS DE `ultima_ruta_id`, Y NO LAS DE `route_id`.
//
// Es la misma respuesta que ya dan la aplicación (`pesoPorRuta` e `importePorRuta`) y el
// post-despacho, y tiene que serlo o vuelven a ser dos preguntas con dos respuestas sobre
// la misma ruta. Un pedido que NO se entrega suelta su `route_id` al cerrarse la ruta, para
// poder repartirse mañana; `ultima_ruta_id` es la hoja de lo que subió al camión y no se
// suelta nunca. Con `route_id`, una ruta cerrada se iría quedando sin peso según se marcan
// los devueltos — y encima bajando, que es peor que quedarse quieto.
func TestLaCuentaAgrupaPorLaRutaEnQueViajo(t *testing.T) {
	cuerpo := cuerpoDeLaCuenta(t, migracionDeLosTotales(t))
	if !strings.Contains(cuerpo, "ultima_ruta_id") {
		t.Fatalf("`totales_de_ruta` ya no mira `ultima_ruta_id`:\n%s", cuerpo)
	}
	if regexp.MustCompile(`(^|[^_])\broute_id\b`).MatchString(cuerpo) {
		t.Errorf("`totales_de_ruta` mira `route_id`.\n"+
			"Un devuelto suelta su `route_id` al cerrar la ruta, así que el peso de una "+
			"ruta cerrada iría bajando según se marcan los devueltos y dejaría de cuadrar "+
			"con «Ver paradas», que agrupa por `ultima_ruta_id`.\n%s", cuerpo)
	}
}

// ---------------------------------------------------------------------------
// Piezas sueltas
// ---------------------------------------------------------------------------

func migracionDeLosTotales(t *testing.T) string {
	t.Helper()
	ruta := filepath.Join("..", "..", "db", "migrations",
		"00014_los_totales_de_la_ruta_no_se_congelan.sql")
	b, err := os.ReadFile(ruta)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", ruta, err)
	}
	texto := string(b)
	// Sólo el `Up`: el `Down` nombra las mismas funciones para tirarlas.
	if i := strings.Index(texto, "+goose Down"); i >= 0 {
		texto = texto[:i]
	}
	return texto
}

// El cuerpo de `totales_de_ruta`, sin comentarios: desde su `CREATE` hasta el `$$;`.
func cuerpoDeLaCuenta(t *testing.T, sql string) string {
	t.Helper()
	return entre(t, sql, "CREATE OR REPLACE FUNCTION totales_de_ruta(", "$$;")
}

// Las columnas de `orders` que lee la cuenta, ordenadas y sin repetir.
func columnasQueLeeLaCuenta(t *testing.T, sql string) []string {
	t.Helper()
	cuerpo := cuerpoDeLaCuenta(t, sql)
	if !strings.Contains(cuerpo, "FROM orders") {
		t.Fatalf("`totales_de_ruta` ya no lee de `orders`: esta prueba se quedó mirando otra cosa\n%s", cuerpo)
	}
	// El alias de la tabla en la cuenta es `o`. Si alguien lo cambia, el `Fatal` de arriba
	// no salta pero éste sí: sin columnas no hay nada que comparar.
	var vistas []string
	for _, m := range regexp.MustCompile(`\bo\.(\w+)`).FindAllStringSubmatch(cuerpo, -1) {
		vistas = append(vistas, m[1])
	}
	if len(vistas) == 0 {
		t.Fatalf("no se le encontró ni una columna `o.<algo>` a `totales_de_ruta`; "+
			"¿cambió el alias de `orders`?\n%s", cuerpo)
	}
	return unicasOrdenadas(vistas)
}

// Las columnas del `UPDATE OF …` del trigger, ordenadas y sin repetir.
func columnasDelUpdateOf(t *testing.T, sql string) []string {
	t.Helper()
	cabecera := entre(t, sql, "CREATE TRIGGER trg_orders_totales_de_ruta", " ON orders")
	i := strings.Index(cabecera, "UPDATE OF ")
	if i < 0 {
		t.Fatalf("`trg_orders_totales_de_ruta` ya no tiene `UPDATE OF`.\n"+
			"Sin él se dispara con CUALQUIER cambio de un pedido, y son 7,1 millones de "+
			"actualizaciones sobre `orders`, casi todas para dejar la fila igual.\n%s",
			strings.TrimSpace(cabecera))
	}
	lista := cabecera[i+len("UPDATE OF "):]
	var columnas []string
	for _, c := range strings.Split(lista, ",") {
		if c = strings.TrimSpace(c); c != "" {
			columnas = append(columnas, c)
		}
	}
	return unicasOrdenadas(columnas)
}

// entre devuelve lo que hay entre `desde` y el primer `hasta` que venga detrás, sin
// comentarios. Falla nombrando la marca que no encontró: una prueba que se queda mirando
// una cadena vacía es una prueba verde que no prueba.
func entre(t *testing.T, sql, desde, hasta string) string {
	t.Helper()
	limpio := sinComentarios(sql)
	i := strings.Index(limpio, desde)
	if i < 0 {
		t.Fatalf("no está %q en 00014: ¿se renombró o se quitó?", desde)
	}
	resto := limpio[i+len(desde):]
	j := strings.Index(resto, hasta)
	if j < 0 {
		t.Fatalf("%q no se cierra con %q en 00014", desde, hasta)
	}
	return resto[:j]
}

func unicasOrdenadas(v []string) []string {
	visto := map[string]bool{}
	var salida []string
	for _, x := range v {
		if !visto[x] {
			visto[x] = true
			salida = append(salida, x)
		}
	}
	sort.Strings(salida)
	return salida
}
