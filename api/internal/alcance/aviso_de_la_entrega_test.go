package alcance

import (
	"testing"
	"time"

	"procovar/reparto-api/internal/store/sqlc"
)

func tx(s string) *string { return &s }

func TestAvisoDeLaEntregaDecideTodo(t *testing.T) {
	pedido := sqlc.ProcedenciaPedido
	ahora := time.Date(2026, 10, 23, 9, 0, 0, 0, time.UTC)
	casos := []struct {
		nombre string
		e      EntregaAAvisar
		hay    bool
		quiero AvisoDeParada
	}{
		{"factura con folio",
			EntregaAAvisar{Source: &pedido, ExternalID: tx("factura:STG:P01:1001:2026-10-22"), Folio: tx(" PSV26-1 "), FacturaNumero: tx("1001")},
			true, AvisoDeParada{Folio: "PSV26-1", Sucursal: "STG", Factura: "1001", PuntoDeVenta: "P01", Estado: "entregado", Nota: "n", At: ahora}},
		{"factura sin folio", EntregaAAvisar{Source: &pedido, ExternalID: tx("factura:STG:P01:1001:2026-10-22"), FacturaNumero: tx("1001")}, false, AvisoDeParada{}},
		{"factura con folio en blanco", EntregaAAvisar{Source: &pedido, ExternalID: tx("factura:STG:P01:1001:2026-10-22"), Folio: tx("  ")}, false, AvisoDeParada{}},
		{"factura sin número en ningún sitio", EntregaAAvisar{ExternalID: tx("factura:STG:folio"), Folio: tx("PSV26-1")}, false, AvisoDeParada{}},
		{"clave vieja por folio, número de la fila",
			EntregaAAvisar{ExternalID: tx("factura:STG:PSV26-1"), Folio: tx("PSV26-1"), FacturaNumero: tx("77")},
			true, AvisoDeParada{Folio: "PSV26-1", Sucursal: "STG", Factura: "77", Estado: "entregado", Nota: "n", At: ahora}},
		{"pedido de PEDIDO", EntregaAAvisar{Source: &pedido, ExternalID: tx("ped-9"), Folio: tx("X")},
			true, AvisoDeParada{PedidoID: "ped-9", Estado: "entregado", Nota: "n", At: ahora}},
		{"sin external_id", EntregaAAvisar{Source: &pedido}, false, AvisoDeParada{}},
		{"sin source y no es de factura", EntregaAAvisar{ExternalID: tx("ped-9")}, false, AvisoDeParada{}},
	}
	for _, c := range casos {
		got, hay := AvisoDeLaEntrega(c.e, "entregado", ahora, "n")
		if hay != c.hay || (hay && got != c.quiero) {
			t.Errorf("%s: hay=%v got=%+v; se esperaba hay=%v %+v", c.nombre, hay, got, c.hay, c.quiero)
		}
	}
}

func TestLaClaveDelAvisoEsLaFacturaNoElPedido(t *testing.T) {
	a := AvisoDeParada{Folio: "F", Sucursal: "STG", PuntoDeVenta: "P1", Factura: "1"}
	b := AvisoDeParada{Folio: "F", Sucursal: "STG", PuntoDeVenta: "P1", Factura: "2"}
	c := AvisoDeParada{Folio: "F", Sucursal: "STG", PuntoDeVenta: "P2", Factura: "1"}
	if a.Clave() == b.Clave() || a.Clave() == c.Clave() {
		t.Fatal("facturas distintas del mismo folio (o el mismo número en otro punto) no pueden compartir clave")
	}
	if (AvisoDeParada{PedidoID: "x"}).Clave() == (AvisoDeParada{PedidoID: "y"}).Clave() {
		t.Fatal("pedidos distintos con la misma clave")
	}
}
