package store

import (
	"regexp"
	"testing"
)

// UNA FACTURA ANULADA NO LA CUENTA NINGUNA LISTA NI NINGÚN CONTADOR (00027, 23/10/2026).
//
// El espejo quita de su ruta la factura que Ventra ya no manda y la deja en la base ARCHIVADA, con
// `anulada_at`: sin ruta, con coordenadas y con `factura_estado = 'igual'`. Esa fila pasa todos los
// filtros de «lo repartible» MENOS `archivado`, así que la garantía de que nadie la cuenta es que
// cada consulta que arma una lista o un número de lo repartible lleve `NOT o.archivado`.
//
// El 23/10/2026, al comprobarlo, `PanelResumen`, `PanelPorSucursal`, `ResumenDeCotejo` y
// `UsoDeProductos` NO lo llevaban (contaban también los 50.000 archivados de PEDIDO). Este
// fichero ata la regla por su TEXTO — como `guardas_del_reparto_test.go`, que explica qué puede y
// qué no puede hacer una prueba así — y `facturas_anuladas_motor_real_test.go` (en `internal/api`) la ata
// ejecutando las consultas contra Postgres de verdad.
var consultasQueNoCuentanArchivadas = []struct{ fichero, consulta string }{
	{"orders.sql", "ListarPedidosDisponibles"},
	{"orders.sql", "ContarPedidosDisponibles"},
	{"orders.sql", "PanelResumen"},
	{"orders.sql", "PanelPorSucursal"},
	{"tablero.sql", "ListarPedidosSinColocar"},
	{"tablero.sql", "ContarPedidosSinColocar"},
	{"routes.sql", "PedidosParaArmarRuta"},
	{"warehouses.sql", "ResumenDeCotejo"},
	{"products.sql", "UsoDeProductos"},
}

var (
	noArchivado     = regexp.MustCompile(`(?i)\bNOT\s+o\.archivado\b`)
	comentarioDeSQL = regexp.MustCompile(`--[^\n]*`)
)

func TestLasListasYLosContadoresNoCuentanLoArchivado(t *testing.T) {
	for _, c := range consultasQueNoCuentanArchivadas {
		t.Run(c.consulta, func(t *testing.T) {
			// SIN LOS COMENTARIOS: varias de estas consultas CUENTAN en un comentario la historia de
			// `AND NOT o.archivado`, y una mutación que borrara la línea de verdad seguiría casando.
			cuerpo := comentarioDeSQL.ReplaceAllString(cuerpoDe(t, leerFichero(t, c.fichero), c.consulta), "")
			if !noArchivado.MatchString(cuerpo) {
				t.Errorf("%s (%s) ya no lleva `NOT o.archivado`: una factura anulada y quitada de su ruta "+
					"(archivada, sin ruta, con coordenadas) volvería a contar como repartible", c.consulta, c.fichero)
			}
		})
	}
}
