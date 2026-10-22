package sqlc

// LA FACTURA DE CADA RENGLÓN CONTRA POSTGRES DE VERDAD (00026, issue 22 de Maikel): lo que se
// escribe con `CrearRenglonDePedido` es lo que leen `ListarRenglonesDePedido(s)` (la API y la
// bajada) y `RenglonesDePedidoParaComparar` (la guarda de «no reescribir lo igual»). Un renglón sin
// factura queda NULL.

import (
	"testing"

	"github.com/google/uuid"
)

func TestMotorReal_LaFacturaDelRenglonSeEscribeYSeLee(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)

	pedido := b.id(`INSERT INTO orders (customer_name, address, weight, operation_number, source, external_id, sucursal_codigo)
	    VALUES ('cliente', 'calle', 1, '47359, 47360', 'pedido'::procedencia, 'factura:STG:PXX-1', 'STG') RETURNING id`)
	f1, f2 := "47359", "47360"
	for i, f := range []*string{&f1, &f2, nil} {
		if _, err := b.q.CrearRenglonDePedido(b.ctx, CrearRenglonDePedidoParams{
			PedidoID: pedido, Linea: int32(i + 1), Description: "CERVEZA", Quantity: 1, FacturaNumero: f,
		}); err != nil {
			t.Fatal(err)
		}
	}
	quiere := []string{"47359", "47360", ""}

	leidos, err := b.q.ListarRenglonesDePedido(b.ctx, ListarRenglonesDePedidoParams{PedidoID: pedido})
	if err != nil {
		t.Fatal(err)
	}
	varios, err := b.q.ListarRenglonesDePedidos(b.ctx, ListarRenglonesDePedidosParams{PedidoIds: []uuid.UUID{pedido}})
	if err != nil {
		t.Fatal(err)
	}
	comparados, err := b.q.RenglonesDePedidoParaComparar(b.ctx, pedido)
	if err != nil {
		t.Fatal(err)
	}
	if len(leidos) != 3 || len(varios) != 3 || len(comparados) != 3 {
		t.Fatalf("tres renglones en las tres lecturas; salieron %d, %d y %d", len(leidos), len(varios), len(comparados))
	}
	for i, q := range quiere {
		for nombre, got := range map[string]*string{
			"ListarRenglonesDePedido": leidos[i].FacturaNumero, "ListarRenglonesDePedidos": varios[i].FacturaNumero,
			"RenglonesDePedidoParaComparar": comparados[i].FacturaNumero,
		} {
			if (q == "") != (got == nil) || (got != nil && *got != q) {
				t.Errorf("%s, renglón %d: factura %v, se esperaba %q (vacío = NULL)", nombre, i+1, got, q)
			}
		}
	}
}
