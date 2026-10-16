package api

// EL FILTRO DE VENDEDOR DE «SIN COLOCAR» ES DE UNO O VARIOS (issue 18 de Amado, 16/10/2026).
//
// Tres maneras de pedirlo, que se UNEN: `vendedor=a&vendedor=b`, `vendedor=a` (el de siempre,
// que las APK instaladas siguen mandando) y `vendedores=a,b`. La lista y su contador (`total`)
// tienen que dar lo mismo en cada una: el `total` sale de `paramsDelContador`, que copia los
// parámetros a mano (§3-bis). El SQL de verdad lo ata
// `TestMotorReal_VendedoresMultiples`; aquí se ata lo que Go le pasa.

import (
	"net/http"
	"net/url"
	"reflect"
	"testing"

	"github.com/google/uuid"
)

func TestSinColocarFiltraPorUnoOVariosVendedores(t *testing.T) {
	q := nuevoTablero()
	for id, vendedor := range map[uuid.UUID]string{ped1: "Luis", ped2: "Marta", ped3: "Nadie Conocido"} {
		p := q.pedidos[id]
		p.vendedor = vendedor
		q.pedidos[id] = p
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	todos := []string{ped1.String(), ped2.String(), ped3.String()}
	casos := []struct {
		nombre   string
		consulta string
		quedan   []string // ids
	}{
		{"ninguno = todos", "", todos},
		{"uno, el parámetro de siempre", "vendedor=Luis", []string{ped1.String()}},
		{"dos repetidos = unión", "vendedor=Luis&vendedor=Marta", []string{ped1.String(), ped2.String()}},
		{"dos separados por comas = unión", "vendedores=Luis,Marta", []string{ped1.String(), ped2.String()}},
		{"el viejo y la lista se unen", "vendedor=Luis&vendedores=Nadie+Conocido", []string{ped1.String(), ped3.String()}},
		{"uno sin pedidos", "vendedor=Fantasma", nil},
		{"vacío no es «ninguno»: es todos", "vendedores=&vendedor=", todos},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			w := pedirTab(t, h, http.MethodGet, "/api/board/unplaced?"+c.consulta, jwt, "")
			if w.Code != http.StatusOK {
				t.Fatalf("código %d — %s", w.Code, w.Body.String())
			}
			m := leerTab(t, w)
			var ids []string
			for _, cruda := range m["pedidos"].([]any) {
				ids = append(ids, cruda.(map[string]any)["id"].(string))
			}
			// El orden no es lo que se prueba aquí.
			if !mismosElementos(ids, c.quedan) {
				t.Errorf("la lista trae %v y debería traer %v", ids, c.quedan)
			}
			if total, _ := m["total"].(float64); int(total) != len(c.quedan) {
				t.Errorf("el total dice %v y la lista debería tener %d: el contador no recibió el filtro "+
					"(§3-bis, paramsDelContador)", total, len(c.quedan))
			}
		})
	}
}

func mismosElementos(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	visto := map[string]int{}
	for _, x := range a {
		visto[x]++
	}
	for _, x := range b {
		visto[x]--
	}
	for _, n := range visto {
		if n != 0 {
			return false
		}
	}
	return true
}

// vendedoresDe devuelve NIL cuando no hay ninguno, NUNCA un vacío: `= ANY('{}')` no casa
// con nada, así que un `[]string{}` convertiría «todos» en «ninguno» sin un error.
func TestVendedoresDe(t *testing.T) {
	casos := []struct {
		consulta string
		quiero   []string
	}{
		{"", nil},
		{"vendedor=", nil},
		{"vendedores=,,", nil},
		{"vendedor=Ana", []string{"Ana"}},
		{"vendedor=Ana&vendedor=Luis", []string{"Ana", "Luis"}},
		{"vendedores=Ana,Luis", []string{"Ana", "Luis"}},
		{"vendedores=+Ana+,+Luis", []string{"Ana", "Luis"}},
		{"vendedor=Ana&vendedores=Ana,Luis", []string{"Ana", "Luis"}},
		// Un nombre CON coma, repetido, se conserva entero: sólo `vendedores` se parte.
		{"vendedor=" + url.QueryEscape("Pérez, Juan"), []string{"Pérez, Juan"}},
	}
	for _, c := range casos {
		q, err := url.ParseQuery(c.consulta)
		if err != nil {
			t.Fatal(err)
		}
		if got := vendedoresDe(q); !reflect.DeepEqual(got, c.quiero) {
			t.Errorf("%q: salió %#v y debía salir %#v", c.consulta, got, c.quiero)
		}
	}
}
