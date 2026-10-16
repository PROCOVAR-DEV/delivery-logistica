package api

// Pedidos y los disponibles (el paso de pedidos del asistente) aceptan el vendedor repetido o
// separado por comas, igual que «Sin colocar» (issue 18 de Amado, 16/10/2026), y se lo pasan
// IGUAL a la lista y a su contador: los parámetros se copian a mano en Go (§3-bis). El SQL de
// verdad lo ata `TestMotorReal_VendedoresMultiples`.

import (
	"net/http"
	"reflect"
	"testing"
)

func TestPedidosYDisponiblesPasanLosVendedoresALaListaYAlContador(t *testing.T) {
	d := datosDePedidos()
	h := servidorDePedidos(t, d)
	jwt := tokenDeSantiagoPedidos(t)

	for _, c := range []struct {
		nombre, query string
		quiero        []string
	}{
		{"ninguno", "", nil},
		{"uno, el de siempre", "vendedor=Ana", []string{"Ana"}},
		{"repetido", "vendedor=Ana&vendedor=Luis", []string{"Ana", "Luis"}},
		{"separado por comas", "vendedores=Ana,Luis", []string{"Ana", "Luis"}},
	} {
		t.Run(c.nombre, func(t *testing.T) {
			if w := pedirPedidos(t, h, http.MethodGet, "/api/orders?"+c.query, jwt, "", nil); w.Code != http.StatusOK {
				t.Fatalf("/api/orders: %d %s", w.Code, w.Body.String())
			}
			if !reflect.DeepEqual(d.vistoListar.Vendedores, c.quiero) || !reflect.DeepEqual(d.vistoContar.Vendedores, c.quiero) {
				t.Errorf("/api/orders: la lista recibió %#v y el contador %#v; tenía que ser %#v los dos",
					d.vistoListar.Vendedores, d.vistoContar.Vendedores, c.quiero)
			}
			if w := pedirPedidos(t, h, http.MethodGet, "/api/orders/available?"+c.query, jwt, "", nil); w.Code != http.StatusOK {
				t.Fatalf("/api/orders/available: %d %s", w.Code, w.Body.String())
			}
			if !reflect.DeepEqual(d.vistoDispLista.Vendedores, c.quiero) || !reflect.DeepEqual(d.vistoDispContar.Vendedores, c.quiero) {
				t.Errorf("/api/orders/available: la lista recibió %#v y el contador %#v; tenía que ser %#v los dos",
					d.vistoDispLista.Vendedores, d.vistoDispContar.Vendedores, c.quiero)
			}
		})
	}
}
