package store

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// LA FECHA DE LOS SEIS FILTROS ES LA MISMA REGLA (issue 16 de Amado, 16/10/2026): el día de
// `coalesce(factura_at, order_date, created_at)` en `America/Havana`. Las parejas de
// `contador_y_lista_test.go` atan cada lista con su contador; ésta ata las TRES familias entre
// sí (Sin colocar, el catálogo de Pedidos y los disponibles): si una vuelve a la fecha del
// pedido o al día de UTC, el mismo rango daría otra lista según la pantalla. Es textual y corre
// sin base; el SQL de verdad lo prueba `TestMotorReal_LaFechaDeLaFacturaEsElDiaDeCuba`.
func TestLaFechaDeLosFiltrosEsLaDeLaFacturaEnCuba(t *testing.T) {
	regla := "(coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date"
	ordenes, err := os.ReadFile(filepath.Join("..", "..", "db", "queries", "orders.sql"))
	if err != nil {
		t.Fatal(err)
	}
	tablero := leerConsultas(t)
	for _, c := range []struct{ sql, nombre string }{
		{tablero, "ListarPedidosSinColocar"},
		{tablero, "ContarPedidosSinColocar"},
		{string(ordenes), "ListarPedidos"},
		{string(ordenes), "ContarPedidos"},
		{string(ordenes), "ListarPedidosDisponibles"},
		{string(ordenes), "ContarPedidosDisponibles"},
	} {
		cuerpo := espacios.ReplaceAllString(cuerpoDe(t, c.sql, c.nombre), " ")
		if n := strings.Count(cuerpo, regla); n != 2 {
			t.Errorf("%s usa la fecha de la factura en hora de Cuba %d veces y tienen que ser 2 (desde y hasta): %s",
				c.nombre, n, regla)
		}
	}
}
