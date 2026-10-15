package sqlc

import (
	"testing"

	"github.com/google/uuid"
)

// LA CAJA DE BÚSQUEDA ENCUENTRA POR EL NÚMERO DE FACTURA (issue 10 de Amado, 15/10/2026).
//
// «Busca por el número de pedido entre otros, pero la factura no está incluida.» La factura es
// `factura_numero` (Ventra, `47061`), no `operation_number` (el folio). Un pedido cubierto por
// dos facturas las lleva juntas («47061, 47062») y buscar la segunda tiene que encontrarlo.
// Las seis consultas con caja de búsqueda —las tres listas y sus contadores— en pareja: la
// factura propia encuentra, la ajena no.
func TestMotorReal_LaBusquedaEncuentraPorFactura(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()

	conFactura := func(nombre, numero string) uuid.UUID {
		s := listo(nombre, suc)
		s.FacturaNumero = str(numero)
		return b.pedido(s)
	}
	dos := conFactura("dos_facturas", "47061, 47062")
	otra := conFactura("otra_factura", "50000")

	buscar := func(t *testing.T, q string) map[string][]uuid.UUID {
		t.Helper()
		encontrados := map[string][]uuid.UUID{}
		disp, err := b.q.ListarPedidosDisponibles(b.ctx, ListarPedidosDisponiblesParams{BranchID: alcance(suc), Q: &q, Limite: 100})
		if err != nil {
			t.Fatal(err)
		}
		for _, f := range disp {
			encontrados["ListarPedidosDisponibles"] = append(encontrados["ListarPedidosDisponibles"], f.ID)
		}
		todos, err := b.q.ListarPedidos(b.ctx, ListarPedidosParams{BranchID: alcance(suc), Q: &q, Limite: 100})
		if err != nil {
			t.Fatal(err)
		}
		for _, f := range todos {
			encontrados["ListarPedidos"] = append(encontrados["ListarPedidos"], f.ID)
		}
		sin, err := b.q.ListarPedidosSinColocar(b.ctx, ListarPedidosSinColocarParams{
			OrigenLat: 21.5, OrigenLng: -77.9, BranchID: suc, Sucursal: sinAlcance, Q: &q, Limite: 100,
		})
		if err != nil {
			t.Fatal(err)
		}
		for _, f := range sin {
			encontrados["ListarPedidosSinColocar"] = append(encontrados["ListarPedidosSinColocar"], f.ID)
		}
		return encontrados
	}
	contar := func(t *testing.T, q string) map[string]int64 {
		t.Helper()
		n1, err := b.q.ContarPedidosDisponibles(b.ctx, ContarPedidosDisponiblesParams{BranchID: alcance(suc), Q: &q})
		if err != nil {
			t.Fatal(err)
		}
		n2, err := b.q.ContarPedidos(b.ctx, ContarPedidosParams{BranchID: alcance(suc), Q: &q})
		if err != nil {
			t.Fatal(err)
		}
		n3, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{BranchID: suc, Sucursal: sinAlcance, Q: &q})
		if err != nil {
			t.Fatal(err)
		}
		return map[string]int64{"ContarPedidosDisponibles": n1, "ContarPedidos": n2, "ContarPedidosSinColocar": n3}
	}

	for _, c := range []struct {
		q        string
		esperado uuid.UUID
	}{
		{"47062", dos}, // la SEGUNDA de dos facturas
		{"47061", dos},
		{"50000", otra}, // la factura de otro pedido no trae a «dos_facturas»
	} {
		t.Run(c.q, func(t *testing.T) {
			for consulta, ids := range buscar(t, c.q) {
				if len(ids) != 1 || ids[0] != c.esperado {
					t.Errorf("%s con q=%q devolvió %v, esperaba sólo %v: la caja de búsqueda no mira factura_numero",
						consulta, c.q, ids, c.esperado)
				}
			}
			if n := len(buscar(t, c.q)); n != 3 {
				t.Errorf("q=%q: sólo %d de las 3 listas encontraron algo: la caja de búsqueda no mira factura_numero", c.q, n)
			}
			for consulta, n := range contar(t, c.q) {
				if n != 1 {
					t.Errorf("%s con q=%q cuenta %d, esperaba 1: el contador no busca lo mismo que su lista", consulta, c.q, n)
				}
			}
		})
	}

	t.Run("una_factura_que_no_es_de_nadie_no_encuentra_nada", func(t *testing.T) {
		if got := buscar(t, "47063"); len(got) != 0 {
			t.Errorf("q=47063 encontró %v: no es de ningún pedido", got)
		}
		for consulta, n := range contar(t, "47063") {
			if n != 0 {
				t.Errorf("%s con q=47063 cuenta %d, esperaba 0", consulta, n)
			}
		}
	})
}
