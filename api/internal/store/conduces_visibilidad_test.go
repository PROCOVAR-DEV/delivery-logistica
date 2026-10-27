package store

import (
	"strings"
	"testing"
)

// QUÉ CONSULTA VE A LOS MIEMBROS DE UN CONDUCE Y CUÁL NO — decidido una por una (00029, `docs/conduces.md` regla 3).
//
// Un miembro de conduce es una fila (`orders.conduce_principal_id` no nulo) que NO es una fila propia de ninguna
// lista: se ve dentro de su principal. Si una lista lo olvida aparece DOS veces (la principal y el miembro); si lo
// olvida su contador, el número miente (el «Sin colocar (722)» del 17/09/2026, `CLAUDE.md` §3-bis). Esta tabla es el
// registro de la decisión y falla si alguien quita (o pone) el filtro sin cambiar también la decisión.
//
// Lo que NO hace, y hay que saberlo: comprueba que la línea está escrita, no que Postgres la aplique; eso lo hace
// `internal/api/conduces_motor_real_test.go` (la lista y su contador sobre filas reales).
func TestCadaConsultaDeConducesDecideSiVeALosMiembros(t *testing.T) {
	const filtro = "conduce_principal_id IS NULL"
	casos := []struct {
		fichero, consulta string
		excluye           bool
		porQue            string
	}{
		// --- LISTAS Y CONTADORES: excluyen. Cada pareja lleva LA MISMA línea (ata también `contador_y_lista_test.go`).
		{"orders.sql", "ListarPedidos", true, "Facturas: el miembro va dentro de su principal"},
		{"orders.sql", "ContarPedidos", true, "el contador de Facturas"},
		{"orders.sql", "ListarPedidosDisponibles", true, "los disponibles del asistente de rutas"},
		{"orders.sql", "ContarPedidosDisponibles", true, "su contador"},
		{"tablero.sql", "ListarPedidosSinColocar", true, "«Sin colocar»"},
		{"tablero.sql", "ContarPedidosSinColocar", true, "su contador"},
		{"orders.sql", "FacetasMunicipios", true, "el desplegable cuenta las filas de la lista"},
		{"orders.sql", "FacetasVendedores", true, "idem"},
		{"orders.sql", "FacetasSucursales", true, "idem"},
		{"orders.sql", "PanelResumen", true, "los CONTEOS son de filas propias (las sumas de peso llevan todas)"},
		{"orders.sql", "PanelPorSucursal", true, "idem"},
		// --- TABLERO: sólo se colocan principales.
		{"tablero.sql", "ListarPedidosColocados", true, "las tarjetas de las zonas"},
		{"tablero.sql", "AvisosDelTablero", true, "los conteos de arriba del tablero"},
		{"tablero.sql", "ListarColumnasDelTablero", true, "el conteo por zona (el peso suma el conduce con conduce_peso)"},
		{"tablero.sql", "ColocarPedido", true, "un miembro no se coloca: se coloca su principal"},
		{"tablero.sql", "PedidosDeColumnaParaArmarRuta", true, "armar una zona arma principales; los miembros van con ellas"},
		// --- RUTAS: una parada por conduce.
		{"routes.sql", "ListarRutas", true, "«n paradas»"},
		{"routes.sql", "ListarParadasDeRuta", true, "las paradas de una ruta"},
		{"routes.sql", "ListarParadasDeRutas", true, "las paradas de varias rutas"},
		{"routes.sql", "ListarParadasQueViajaronEnRuta", true, "la hoja de cierre: la parada es el conduce"},
		{"routes.sql", "FijarOrdenDeParada", true, "un miembro no tiene posición"},
		{"routes.sql", "SoltarParadaPlanificada", true, "un miembro no se quita solo de la ruta"},
		{"routes.sql", "MarcarResultadoDeParada", true, "el resultado se marca en la principal y se cascada a los miembros"},
		{"routes.sql", "LimpiarResultadoDeParada", true, "idem al desmarcar"},
		{"routes.sql", "EngancharPedidoARuta", true, "un miembro no se arma solo: entra con su principal"},

		// --- NO EXCLUYEN, y por qué:
		{"orders.sql", "DiferenciasDePedidos", false, "REGLA 9: los miembros BAJAN al aparato (con conducePrincipalId) para trabajar sin conexión"},
		{"warehouses.sql", "ResumenDeCotejo", false, "cuenta FACTURAS por estado de cotejo (contra Next/Ventra), no filas visibles: un miembro es una factura cotejada"},
		{"products.sql", "UsoDeProductos", false, "cuenta unidades de producto de los últimos N pedidos: el miembro lleva mercancía real"},
		{"orders.sql", "ListarPedidosParaInforme", false, "cada FACTURA es una fila del informe (peso e ingreso suman bien); la ruta y el camión salen de la fila"},
		{"orders.sql", "EntregasDeFacturaEnVentana", false, "el espejo tiene que ver TODAS sus filas para retirar las que ya no vienen"},
		{"routes.sql", "ListarRenglonesDeRuta", false, "regla 6: la hoja de carga lleva los renglones de TODAS las filas del conduce"},
		{"routes.sql", "ListarRenglonesDeRutas", false, "idem; cuelgan de la parada de su principal"},
		{"orders.sql", "ResumenPreDespacho", false, "regla 6: se pide por la principal y salen los renglones del conduce entero (OR conduce_principal_id = ANY)"},
		{"orders.sql", "ObtenerPedido", false, "por id: la ficha de un miembro existe y dice su principal"},
		{"orders.sql", "ListarRenglonesDePedido", false, "por id"},
		{"orders.sql", "ListarRenglonesDePedidos", false, "por id"},
		{"routes.sql", "PorQueNoSePuedeArmar", false, "es la explicación del 409: tiene que poder hablar de un miembro"},
		{"routes.sql", "SoltarPedidosDeRuta", false, "borrar/soltar una ruta suelta TODAS sus filas con route_id, miembros incluidos"},
		{"avisos_a_pedido.sql", "EntregasParaAvisar", false, "por id: cada factura avisa"},
	}
	for _, k := range casos {
		sql := leerFichero(t, k.fichero)
		cuerpo := espacios.ReplaceAllString(cuerpoDe(t, sql, k.consulta), " ")
		if got := strings.Contains(cuerpo, filtro); got != k.excluye {
			t.Errorf("%s (%s): excluye miembros = %v y la decisión es %v (%s).\n"+
				"Si la decisión cambia, cámbiala aquí a la vez y en docs/conduces.md.", k.consulta, k.fichero, got, k.excluye, k.porQue)
		}
	}
}

// El armado, el cierre y el cierre de la espejo no pueden dejar de llevar a los miembros con su principal.
func TestLoQueMueveALaPrincipalMueveASusMiembros(t *testing.T) {
	routes := leerFichero(t, "routes.sql")
	for consulta, trozo := range map[string]string{
		"EngancharPedidoARuta":     "m.conduce_principal_id IN (SELECT parada.id FROM parada)",
		"MarcarResultadoDeParada":  "m.conduce_principal_id IN (SELECT parada.id FROM parada)",
		"LimpiarResultadoDeParada": "m.conduce_principal_id IN (SELECT parada.id FROM parada)",
		"SoltarParadaPlanificada":  "m.conduce_principal_id = l.id",
	} {
		if !strings.Contains(espacios.ReplaceAllString(cuerpoDe(t, routes, consulta), " "), trozo) {
			t.Errorf("%s ya no mueve a los miembros de la principal («%s»): el conduce se partiría entre dos rutas", consulta, trozo)
		}
	}
	orders := leerFichero(t, "orders.sql")
	if !strings.Contains(espacios.ReplaceAllString(cuerpoDe(t, orders, "AnularEntregasDeFacturaEnRuta"), " "), "WHERE m.conduce_principal_id = q.id") {
		t.Error("AnularEntregasDeFacturaEnRuta ya no suelta a los miembros de una principal cancelada")
	}
	// Y el upsert del espejo NO nombra la columna: sólo una persona escribe un conduce.
	if strings.Contains(cuerpoDe(t, orders, "GuardarPedidoDelEspejo"), "conduce_principal_id") {
		t.Error("GuardarPedidoDelEspejo escribe conduce_principal_id: el espejo pisaría un conduce hecho a mano")
	}
}
