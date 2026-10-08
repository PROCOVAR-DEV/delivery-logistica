package store

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// LAS GUARDAS QUE IMPIDEN REPARTIR DOS VECES EL MISMO PEDIDO, VIGILADAS EN EL SQL.
//
// POR QUÉ HACE FALTA ESTA PRUEBA Y NO BASTA CON LAS DE `internal/api`.
//
// Las pruebas de los manejadores corren contra DOBLES escritos a mano que reimplementan
// cada consulta en Go. Eso está bien y hay que seguir haciéndolo —es lo que deja probar el
// manejador sin una base delante—, pero tiene un agujero que se midió el 18/09/2026,
// borrando guardas de verdad del SQL y ejecutando `go build && go vet && go test ./...`:
//
//	db/queries/tablero.sql  ColocarPedido                 quitado `AND o.route_id IS NULL`   → TODO VERDE
//	db/queries/tablero.sql  PedidosDeColumnaParaArmarRuta quitado `AND o.route_id IS NULL`   → TODO VERDE
//	db/queries/routes.sql   EngancharPedidoARuta          quitado `AND route_id IS NULL`     → TODO VERDE
//	db/queries/routes.sql   MarcarResultadoDeParada       `route_id = NULL` siempre          → TODO VERDE
//
// Las cuatro son la diferencia entre que un pedido cargado en un camión se pueda meter en
// otro y que no. Con las cuatro borradas, la suite entera pasaba y el 409 de «ese pedido ya
// está en una ruta» seguía saliendo en las pruebas... porque lo daba el doble. En
// producción, ese mismo pedido se habría colocado con un 200.
//
// Un doble que reimplementa el SQL sólo puede comprobar al manejador. A la consulta hay que
// vigilarla por su TEXTO, que es lo único que se puede hacer sin Postgres en esta máquina,
// y es exactamente el mismo oficio que hace `contador_y_lista_test.go`.
//
// LO QUE ESTA PRUEBA NO PUEDE HACER, y hay que saberlo antes de fiarse de ella: no ejecuta
// nada. Comprueba que la condición está escrita, no que Postgres la aplique como se espera.
// Una condición presente pero mal puesta —dentro de un `OR`, o en un `LEFT JOIN` donde no
// filtra— pasaría por aquí. Eso sólo lo caza una base de verdad.
func TestLasGuardasSiguenEnElSQL(t *testing.T) {
	for _, g := range guardasDelReparto {
		t.Run(g.consulta, func(t *testing.T) {
			sql := leerFichero(t, g.fichero)
			cuerpo := cuerpoDe(t, sql, g.consulta)
			condiciones := filtrosDe(t, sql, g.consulta)

			for _, quiere := range g.enElWhere {
				if !contiene(condiciones, quiere) {
					t.Errorf(
						"%s (%s) ya no filtra por «%s».\n\n%s\n\n"+
							"Si de verdad tiene que quitarse, explica en el SQL por qué y "+
							"cambia esta prueba a la vez: lo que no puede es desaparecer sin "+
							"que nadie se entere, que es lo que pasaba hasta el 18/09/2026.\n"+
							"Condiciones leídas: %v",
						g.consulta, g.fichero, quiere, g.porQue, condiciones)
				}
			}
			for _, quiere := range g.enElCuerpo {
				if !strings.Contains(espacios.ReplaceAllString(cuerpo, " "), quiere) {
					t.Errorf(
						"%s (%s) ya no lleva «%s».\n\n%s",
						g.consulta, g.fichero, quiere, g.porQue)
				}
			}
			for _, noQuiere := range g.noEnElCuerpo {
				if strings.Contains(espacios.ReplaceAllString(cuerpo, " "), noQuiere) {
					t.Errorf(
						"%s (%s) lleva «%s», que NO tiene que llevar.\n\n%s",
						g.consulta, g.fichero, noQuiere, g.porQue)
				}
			}
		})
	}
}

// guarda es una condición que, si desaparece, deja repartir dos veces el mismo pedido.
type guarda struct {
	fichero  string
	consulta string
	// enElWhere: condiciones del `WHERE`, tal y como las normaliza `filtrosDe` —una por
	// cada `AND` a principio de línea, con los espacios colapsados.
	enElWhere []string
	// enElCuerpo: trozos que tienen que estar en algún sitio de la consulta, para las que
	// no son un `AND` suelto (una columna del `SELECT`, un `CASE`).
	enElCuerpo []string
	// noEnElCuerpo: trozos que NO pueden estar. Una decisión de «esto no se filtra aquí» es
	// tan fácil de deshacer sin querer como una guarda de quitar, y hasta que existió esto no
	// la vigilaba nadie.
	noEnElCuerpo []string
	porQue       string
}

var guardasDelReparto = []guarda{
	{
		fichero:  "vehicles.sql",
		consulta: "ListarVehiculos",
		enElCuerpo: []string{
			"FROM orders o JOIN routes r ON r.id = o.route_id WHERE r.vehicle_id = v.id",
		},
		porQue: "LOS PEDIDOS QUE LLEVA ESTE CAMIÓN SALEN DE SUS RUTAS.\n" +
			"Antes de eliminarse `orders.vehicle_id`, aquí se contaba esa columna duplicada y el\n" +
			"tablero la escribía al colocar pedidos. Armar una ruta nunca la tocaba, porque el\n" +
			"camión de un pedido es el de la ruta en la que viaja. El 22/09/2026 la tarjeta decía\n" +
			"«Rutas 7» y «0 órdenes asignadas», con 125,3 kg cargados. Ahora la relación canónica\n" +
			"se consulta directamente en `routes.vehicle_id`.",
	},
	{
		fichero:  "vehicles.sql",
		consulta: "ObtenerVehiculo",
		enElCuerpo: []string{
			"FROM orders o JOIN routes r ON r.id = o.route_id WHERE r.vehicle_id = v.id",
		},
		porQue: "El detalle tiene que contar lo mismo que la lista. Ver ListarVehiculos.",
	},

	{
		fichero:   "tablero.sql",
		consulta:  "ColocarPedido",
		enElWhere: []string{"o.route_id IS NULL", "o.delivered_at IS NULL", "(o.resultado IS NULL OR o.resultado <> 'entregado')"},
		porQue: "Es el `WHERE` que impide soltar en una zona una tarjeta de un pedido que\n" +
			"ya va cargado en un camión o que ya se entregó. El cero filas de este INSERT es\n" +
			"lo que `porQueNoSePudoColocar` traduce al 409 con su motivo: sin la condición no\n" +
			"hay cero filas, no hay 409, y la tarjeta se coloca con un 200.",
	},
	{
		fichero:   "tablero.sql",
		consulta:  "ListarPedidosSinColocar",
		enElWhere: []string{"o.route_id IS NULL", "o.delivered_at IS NULL", "(o.resultado IS NULL OR o.resultado <> 'entregado')"},
		porQue: "La mitad izquierda del tablero. Sin esto se le ofrece al logístico un pedido\n" +
			"que ya va en un camión, o uno que YA SE ENTREGÓ y cuya ruta se borró — la clave\n" +
			"ajena es ON DELETE SET NULL (db/migrations/00001_init.sql:446), así que el\n" +
			"entregado aparece suelto y sin una sola marca en el WHERE de siempre.",
	},
	{
		fichero:   "tablero.sql",
		consulta:  "ContarPedidosSinColocar",
		enElWhere: []string{"o.route_id IS NULL", "o.delivered_at IS NULL", "(o.resultado IS NULL OR o.resultado <> 'entregado')"},
		porQue: "El número que va ENCIMA de esa lista, y tiene que filtrar lo mismo o dice\n" +
			"«Sin colocar (722)» sobre una lista de 293. Ver contador_y_lista_test.go.",
	},
	{
		fichero:    "tablero.sql",
		consulta:   "PedidosDeColumnaParaArmarRuta",
		enElWhere:  []string{"o.route_id IS NULL"},
		enElCuerpo: []string{"o.delivered_at, o.resultado"},
		porQue: "De una zona sale una ruta. `route_id IS NULL` es lo que impide que la tarjeta\n" +
			"de un pedido que otro ya subió a su camión se suba también al tuyo; y\n" +
			"`delivered_at`/`resultado` salen como DATO —no como filtro, a propósito— para\n" +
			"que `armarRutaDeColumna` pueda nombrar la tarjeta ya entregada en `descartados`\n" +
			"en vez de callársela. Sin esas dos columnas el manejador no puede distinguirla.",
	},
	{
		fichero:    "routes.sql",
		consulta:   "PedidosParaArmarRuta",
		enElWhere:  []string{"o.route_id IS NULL"},
		enElCuerpo: []string{"o.delivered_at, o.resultado"},
		porQue: "La validación del armador de siempre. Las dos columnas son las que\n" +
			"`mensajeYaEntregados` necesita para contestar «N de los pedidos elegidos YA SE\n" +
			"ENTREGARON» con sus nombres, en vez del «ya están en otra ruta» de al lado, que\n" +
			"para un entregado es falso: esa ruta puede que ni exista.",
	},
	{
		fichero:   "routes.sql",
		consulta:  "EngancharPedidoARuta",
		enElWhere: []string{"route_id IS NULL"},
		porQue: "LA ÚNICA GUARDA CONTRA LA CARRERA DE VERDAD. La validación de más arriba se\n" +
			"hizo hace unos milisegundos y con diez logísticos armando rutas a la vez eso es\n" +
			"una foto vieja. El cero filas de este UPDATE es lo que levanta `errSeLoLlevaron`\n" +
			"y deshace la ruta entera. Sin esto, dos rutas se llevan el mismo pedido y las\n" +
			"dos creen tenerlo.",
	},
	{
		fichero:    "routes.sql",
		consulta:   "MarcarResultadoDeParada",
		enElWhere:  []string{"(route_id = sqlc.arg('ruta_id')"},
		enElCuerpo: []string{"OR (route_id IS NULL AND ultima_ruta_id = sqlc.arg('ruta_id') AND resultado IS NOT NULL)", "WHEN sqlc.arg('resultado')::stop_result = 'entregado' THEN sqlc.arg('ruta_id')"},
		porQue: "Las dos mitades del cierre.\n" +
			"  · El `WHERE` acepta la parada que sigue en `route_id` y la ya soltada cuya\n" +
			"    `ultima_ruta_id` apunta a esta ruta; cualquier otra ruta queda excluida.\n" +
			"  · El `CASE` que fija `route_id` del entregado es lo que impide que un\n" +
			"    pedido ya repartido vuelva a la lista de disponibles esa misma tarde. Con\n" +
			"    `route_id = NULL` a secas, cerrar la ruta devuelve TODO al montón.",
	},
	// ---- LA PARADA FANTASMA (07/10/2026): las cuatro preguntas «¿viajó este pedido en esta
	// ruta?» tienen que contestar lo mismo, y un pedido quitado de la ruta no viajó. ----
	{
		fichero:    "routes.sql",
		consulta:   "ListarParadasQueViajaronEnRuta",
		enElCuerpo: []string{"OR (o.route_id IS NULL AND o.ultima_ruta_id = sqlc.arg('ruta_id') AND o.resultado IS NOT NULL)"},
		porQue: "LA HOJA DE CIERRE. Sin `resultado IS NOT NULL` en la rama de `route_id IS NULL`, un\n" +
			"pedido que se QUITÓ de una ruta planificada seguía saliendo como parada suya, se podía\n" +
			"marcar «entregado» desde ahí y esa marca le devolvía el `route_id` de una ruta que ya\n" +
			"no lo lleva. Un devuelto o un cancelado siempre tiene resultado, así que no se pierde.",
	},
	{
		fichero:    "routes.sql",
		consulta:   "ListarRenglonesDeRuta",
		enElCuerpo: []string{"OR (o.route_id IS NULL AND o.ultima_ruta_id = sqlc.arg('ruta_id') AND o.resultado IS NOT NULL)"},
		porQue:     "Los renglones de la hoja de carga tienen que ser los de las paradas de la hoja de cierre.",
	},
	{
		fichero:    "routes.sql",
		consulta:   "LimpiarResultadoDeParada",
		enElCuerpo: []string{"OR (route_id IS NULL AND ultima_ruta_id = sqlc.arg('ruta_id') AND resultado IS NOT NULL)"},
		porQue:     "Desmarcar una parada que no viajó le pondría `route_id` a un pedido quitado de la ruta.",
	},
	{
		fichero:    "routes.sql",
		consulta:   "SoltarParadaPlanificada",
		enElCuerpo: []string{"route_id = NULL, ultima_ruta_id = NULL, stop_order = NULL, segment_km = NULL"},
		porQue: "QUITAR UNA PARADA SUELTA TAMBIÉN `ultima_ruta_id`. Si se conserva, el pedido sigue\n" +
			"contando en los totales de la ruta (el trigger de 00014 suma por `ultima_ruta_id`): la\n" +
			"cabecera dice 516 kg sobre una ruta que ya sólo carga 420.",
	},
	{
		fichero:      "tablero.sql",
		consulta:     "QuitarDelTableroLosDeRuta",
		enElCuerpo:   []string{"ON CONFLICT (order_id) DO UPDATE SET route_id = excluded.route_id"},
		noEnElCuerpo: []string{"DO NOTHING"},
		porQue: "UN ORIGEN VIEJO NO PUEDE BLOQUEAR AL NUEVO. Con `DO NOTHING`, un devuelto que se\n" +
			"vuelve a colocar y a armar conserva el origen de la ruta de ayer, y al borrar la ruta de\n" +
			"hoy vuelve a una zona que no es la suya.",
	},

	// ---- LA REGLA DE AMADO (07/10/2026): domicilio cobrado Y cotizado. Las mismas dos
	// condiciones en TODOS los sitios que ofrecen o aceptan un pedido para una ruta. ----
	{
		fichero:   "orders.sql",
		consulta:  "ListarPedidosDisponibles",
		enElWhere: []string{"o.factura_domicilio > 0", "o.pedido_costo IS NOT NULL"},
		porQue:    "La lista del armador no puede ofrecer lo que el armador rechaza. Ver ColocarPedido.",
	},
	{
		fichero:   "orders.sql",
		consulta:  "ContarPedidosDisponibles",
		enElWhere: []string{"o.factura_domicilio > 0", "o.pedido_costo IS NOT NULL"},
		porQue:    "El total de arriba de la lista de disponibles, que tiene que ser el de la lista.",
	},
	{
		fichero:   "tablero.sql",
		consulta:  "ListarPedidosSinColocar",
		enElWhere: []string{"o.factura_domicilio > 0", "o.pedido_costo IS NOT NULL"},
		porQue: "LA MITAD IZQUIERDA DEL TABLERO. Se añadieron a `ColocarPedido` y no aquí, y ofrecía\n" +
			"tarjetas que el 409 devolvía: el logístico preparaba una zona para nada.",
	},
	{
		fichero:   "tablero.sql",
		consulta:  "ContarPedidosSinColocar",
		enElWhere: []string{"o.factura_domicilio > 0", "o.pedido_costo IS NOT NULL"},
		porQue:    "El número de encima de esa lista. Ver contador_y_lista_test.go.",
	},
	{
		fichero:      "tablero.sql",
		consulta:     "ColocarPedido",
		enElWhere:    []string{"o.factura_domicilio > 0", "o.pedido_costo IS NOT NULL"},
		noEnElCuerpo: []string{"factura_estado"},
		porQue: "Colocar exige el domicilio cobrado y cotizado y NO mira `factura_estado`: un pedido\n" +
			"`cambiado` se puede preparar en una zona, y lo corta el armador con su motivo. Se llegó a\n" +
			"añadir el 07/10/2026 y se quitó ese mismo día (D1).",
	},
	{
		fichero:      "routes.sql",
		consulta:     "EngancharPedidoARuta",
		enElWhere:    []string{"factura_domicilio > 0", "pedido_costo IS NOT NULL"},
		noEnElCuerpo: []string{"factura_estado"},
		porQue: "LA SEGUNDA LLAVE de la regla de Amado al enganchar. `factura_estado` NO está: el corte a\n" +
			"`igual` lo hacen `mensajeNoFacturados` y `armarRutaDeColumna`, para poder nombrar cuál falla.",
	},
	{
		fichero:   "orders.sql",
		consulta:  "PanelPorSucursal",
		enElWhere: []string{"o.factura_domicilio > 0", "o.pedido_costo IS NOT NULL"},
		porQue:    "El panel cuenta lo repartible con el mismo listón que el armador, o dice «40 por repartir» y el armador ofrece 12.",
	},
	{
		fichero:    "orders.sql",
		consulta:   "PanelResumen",
		enElCuerpo: []string{"AND o.factura_domicilio > 0 AND o.pedido_costo IS NOT NULL) AS sin_ruta"},
		porQue:     "`sin_ruta` del panel: mismo listón. `peso_pendiente` lo ata el motor real.",
	},
	{
		fichero:   "orders.sql",
		consulta:  "PedidosQueSalieronDelAlcance",
		enElWhere: []string{"f.salio_at >", "f.salio_at <=", "f.branch_id = sqlc.narg('sucursal')::uuid", "f.motivo = 'borrado'"},
		enElCuerpo: []string{
			"ORDER BY f.salio_at ASC, f.order_id ASC",
			"LIMIT sqlc.arg('tope')",
		},
		porQue: "LAS LÁPIDAS DE LOS PEDIDOS, que es lo que hace que un pedido borrado o mudado\n" +
			"de sucursal desaparezca del aparato. Las cuatro condiciones se rompen de forma\n" +
			"distinta y ninguna la caza el doble:\n" +
			"  · sin el `desde`/`hasta`, cada bajada le manda los borrados de los últimos dos\n" +
			"    años por la conexión de allá;\n" +
			"  · sin el alcance, al aparato de Santiago le llegan las bajas de Holguín;\n" +
			"  · sin `motivo = 'borrado'`, a quien ve las OCHO se le manda borrar un pedido que\n" +
			"    sólo se mudó de sucursal y que sigue en su lista — le borra trabajo del\n" +
			"    aparato, que es el peor fallo posible de esta consulta.\n" +
			"Y el orden por la marca con el `LIMIT` es lo que hace que un tope no pierda nada.",
	},
	{
		fichero:  "bajas.sql",
		consulta: "BajasDeLaBajada",
		enElWhere: []string{
			"b.coleccion = sqlc.arg('coleccion')",
			"b.salio_at > sqlc.narg('desde')",
			"b.salio_at <= sqlc.narg('hasta')",
			"b.branch_id = sqlc.narg('sucursal')::uuid",
			"sqlc.arg('sin_sucursal_tambien')::boolean",
			"b.branch_id = sqlc.narg('branch_id')::uuid",
			"b.motivo = 'borrado'",
		},
		enElCuerpo: []string{
			"ORDER BY b.salio_at ASC, b.clave ASC",
			"LIMIT sqlc.arg('tope')",
		},
		porQue: "LAS LÁPIDAS DE TODO LO DEMÁS (rutas, camiones, sucursales, catálogo, padrón y\n" +
			"las dos del tablero). Es la consulta que arregla lo que Jose vio el 17/09/2026: una\n" +
			"ruta borrada en el servidor que seguía en su teléfono. Cada condición, y lo que\n" +
			"pasa sin ella:\n" +
			"  · `b.coleccion`: sin esto, la baja de un producto llega como la baja de una ruta\n" +
			"    con el mismo uuid — o, peor, no llega ninguna y todo sale «en verde».\n" +
			"  · el `desde`/`hasta`: sin ellos, cada bajada arrastra el histórico entero.\n" +
			"  · `b.branch_id = sucursal`: el alcance. Sin él, a Santiago le llegan las bajas de\n" +
			"    Holguín.\n" +
			"  · `sin_sucursal_tambien`: copia el `OR v.branch_id IS NULL` que lleva\n" +
			"    `ListarVehiculos` y NO lleva `ListarRutas`. Quitado, un camión sin sucursal\n" +
			"    dado de baja se queda en los ocho teléfonos para siempre.\n" +
			"  · `b.branch_id = branch_id`: la sucursal PEDIDA, que es la que acota el tablero.\n" +
			"  · `b.motivo = 'borrado'`: a quien ve las ocho no se le borra lo que sólo se mudó.\n" +
			"El orden por la marca con el `LIMIT` es lo que hace que el tope no pierda una baja.",
	},
}

// contiene busca la condición exacta, ya normalizada por `filtrosDe`.
func contiene(condiciones []string, quiere string) bool {
	for _, c := range condiciones {
		if c == quiere || strings.Contains(c, quiere) {
			return true
		}
	}
	return false
}

func leerFichero(t *testing.T, nombre string) string {
	t.Helper()
	ruta := filepath.Join("..", "..", "db", "queries", nombre)
	b, err := os.ReadFile(ruta)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", ruta, err)
	}
	return string(b)
}
