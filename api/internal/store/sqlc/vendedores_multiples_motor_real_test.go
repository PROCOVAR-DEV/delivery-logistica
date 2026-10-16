package sqlc

// EL FILTRO DE VENDEDOR ES DE UNO O VARIOS (issue 18 de Amado, 16/10/2026): «porque
// pueden haber pocos domicilios y se combinan los de ambos». Con VARIOS salen los pedidos
// de CUALQUIERA de ellos (unión, `= ANY`), con ninguno salen todos, y con uno que no tiene
// pedidos sale la lista vacía. Lo ejecuta Postgres de verdad (REPARTO_MOTOR_REAL_DSN) en
// las seis consultas que lo llevan —las dos del tablero y las cuatro de Pedidos y de los
// disponibles—, y la lista y su contador tienen que dar lo mismo en cada caso.

import (
	"sort"
	"testing"
)

func TestMotorReal_VendedoresMultiples(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	for nombre, vendedor := range map[string]*string{
		"ana1": str("Ana"), "ana2": str("Ana"), "luis1": str("Luis"),
		"marta1": str("Marta"), "sin_vendedor": nil,
	} {
		b.exec(`UPDATE orders SET vendedor = $1 WHERE id = $2`, vendedor, b.pedido(listo(nombre, suc)))
	}

	casos := []struct {
		nombre     string
		vendedores []string
		esperados  []string
	}{
		{"ninguno = todos", nil, []string{"ana1", "ana2", "luis1", "marta1", "sin_vendedor"}},
		{"uno", []string{"Ana"}, []string{"ana1", "ana2"}},
		{"dos = la unión", []string{"Ana", "Luis"}, []string{"ana1", "ana2", "luis1"}},
		{"uno repetido no duplica", []string{"Luis", "Luis"}, []string{"luis1"}},
		{"uno sin pedidos", []string{"Nadie"}, nil},
		{"uno con pedidos y otro sin", []string{"Marta", "Nadie"}, []string{"marta1"}},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			espera := append([]string(nil), c.esperados...)
			sort.Strings(espera)
			compara := func(consulta string, nombres []string, contador int64) {
				t.Helper()
				sort.Strings(nombres)
				igualesTxt(t, consulta, nombres, espera)
				if int(contador) != len(espera) {
					t.Errorf("%s: el contador dice %d y debería decir %d", consulta, contador, len(espera))
				}
			}

			sin, err := b.q.ListarPedidosSinColocar(b.ctx, ListarPedidosSinColocarParams{
				BranchID: suc, Sucursal: sinAlcance, Vendedores: c.vendedores, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			nSin, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{
				BranchID: suc, Sucursal: sinAlcance, Vendedores: c.vendedores})
			if err != nil {
				t.Fatal(err)
			}
			var ns []string
			for _, f := range sin {
				ns = append(ns, f.CustomerName)
			}
			compara("ListarPedidosSinColocar/ContarPedidosSinColocar", ns, nSin)

			disp, err := b.q.ListarPedidosDisponibles(b.ctx, ListarPedidosDisponiblesParams{
				BranchID: alcance(suc), Vendedores: c.vendedores, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			nDisp, err := b.q.ContarPedidosDisponibles(b.ctx, ContarPedidosDisponiblesParams{
				BranchID: alcance(suc), Vendedores: c.vendedores})
			if err != nil {
				t.Fatal(err)
			}
			var nd []string
			for _, f := range disp {
				nd = append(nd, f.CustomerName)
			}
			compara("ListarPedidosDisponibles/ContarPedidosDisponibles", nd, nDisp)

			cat, err := b.q.ListarPedidos(b.ctx, ListarPedidosParams{
				BranchID: alcance(suc), Vendedores: c.vendedores, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			nCat, err := b.q.ContarPedidos(b.ctx, ContarPedidosParams{
				BranchID: alcance(suc), Vendedores: c.vendedores})
			if err != nil {
				t.Fatal(err)
			}
			var nc []string
			for _, f := range cat {
				nc = append(nc, f.CustomerName)
			}
			compara("ListarPedidos/ContarPedidos", nc, nCat)
		})
	}
}
