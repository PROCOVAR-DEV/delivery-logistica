package api

// LA FECHA DE LA FACTURA DE «SIN COLOCAR», POR HTTP, CON LOS CASOS DEL FICHERO COMPARTIDO —
// issue 16 de Amado, 16/10/2026.
//
// `docs/fecha-de-la-factura.casos.json` lo leen tres pruebas: el SQL contra Postgres
// (`TestMotorReal_LaFechaDeLaFacturaEsElDiaDeCuba`), el aparato contra su base local, y ésta,
// que pide cada caso al manejador de `GET /api/board/unplaced` y de `GET /api/board` con los
// tres modos de decir el rango (`diaDesde`/`diaHasta`, `dia` cuando es uno solo) y comprueba
// lista y contador. El doble repite el `WHERE`, así que esto NO prueba el SQL: prueba que el
// parámetro llega a la consulta como DÍA y que la lista y el total salen de la misma cuenta.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

const rutaDeLosCasosDeLaFechaDeLaFactura = "../../../docs/fecha-de-la-factura.casos.json"

type casosDeLaFechaDeLaFactura struct {
	Pedidos []struct {
		Nombre    string     `json:"nombre"`
		FacturaAt *time.Time `json:"facturaAt"`
		OrderDate *time.Time `json:"orderDate"`
		CreatedAt *time.Time `json:"createdAt"`
	} `json:"pedidos"`
	Casos []struct {
		Nombre   string   `json:"nombre"`
		Desde    *string  `json:"desde"`
		Hasta    *string  `json:"hasta"`
		Esperado []string `json:"esperado"`
	} `json:"casos"`
	Instantes []struct {
		Instante time.Time `json:"instante"`
		Dia      string    `json:"dia"`
	} `json:"instantes"`
}

func leerCasosDeLaFechaDeLaFactura(t *testing.T) casosDeLaFechaDeLaFactura {
	t.Helper()
	b, err := os.ReadFile(rutaDeLosCasosDeLaFechaDeLaFactura)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v\nEs lo que ata el filtro de fechas del servidor con el del "+
			"aparato; sin él esta prueba no comprueba nada.", rutaDeLosCasosDeLaFechaDeLaFactura, err)
	}
	var f casosDeLaFechaDeLaFactura
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDeLaFechaDeLaFactura, err)
	}
	if len(f.Pedidos) == 0 || len(f.Casos) == 0 || len(f.Instantes) == 0 {
		t.Fatalf("%s sin pedidos, casos o instantes: una prueba sobre nada sale verde", rutaDeLosCasosDeLaFechaDeLaFactura)
	}
	return f
}

// Antes de fiarse del doble hay que fiarse de lo que le sirve de patrón: el día de Cuba de
// cada instante del fichero es el que calcula `diaDeCuba` (la base de husos de Go). Si esto
// falla, falla el fichero o el doble, no el servidor.
func TestElFicheroDeLaFechaDeLaFacturaDiceElDiaDeCuba(t *testing.T) {
	for _, c := range leerCasosDeLaFechaDeLaFactura(t).Instantes {
		if got := diaDeCuba(c.Instante).Format("2006-01-02"); got != c.Dia {
			t.Errorf("%s es el %s en Cuba y el fichero dice %s", c.Instante.Format(time.RFC3339), got, c.Dia)
		}
	}
}

func TestSinColocarPorLaFechaDeLaFacturaEsLaDelFichero(t *testing.T) {
	f := leerCasosDeLaFechaDeLaFactura(t)
	q := nuevoTablero()
	for id, p := range q.pedidos {
		if p.sucursal == sucStg {
			delete(q.pedidos, id)
		}
	}
	for i, p := range f.Pedidos {
		id := uuid.MustParse(fmt.Sprintf("5f000000-0000-0000-0000-%012d", i+1))
		q.pedidos[id] = pedidoFalso{
			id: id, sucursal: sucStg, nombre: p.Nombre, peso: 1, lat: 20.0247, lng: -75.8219,
			facturaAt: p.FacturaAt, fecha: p.OrderDate, creado: p.CreatedAt,
		}
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	for _, c := range f.Casos {
		consultas := []string{}
		var rango []string
		if c.Desde != nil {
			rango = append(rango, "diaDesde="+*c.Desde)
		}
		if c.Hasta != nil {
			rango = append(rango, "diaHasta="+*c.Hasta)
		}
		consultas = append(consultas, strings.Join(rango, "&"))
		// `dia` (un solo día) es lo mismo que desde = hasta: se sigue aceptando por compatibilidad
		// y tiene que filtrar por la fecha NUEVA.
		if c.Desde != nil && c.Hasta != nil && *c.Desde == *c.Hasta {
			consultas = append(consultas, "dia="+*c.Desde)
		}
		esperado := append([]string{}, c.Esperado...)
		sort.Strings(esperado)
		for _, query := range consultas {
			t.Run(c.Nombre+"?"+query, func(t *testing.T) {
				for _, ruta := range []string{"/api/board/unplaced?", "/api/board?branchId=" + sucStg.String() + "&"} {
					w := pedirTab(t, h, http.MethodGet, ruta+query, jwt, "")
					if w.Code != http.StatusOK {
						t.Fatalf("%s: código %d — %s", ruta, w.Code, w.Body.String())
					}
					m := leerTab(t, w)
					if izq, ok := m["sinColocar"].(map[string]any); ok {
						m = izq // `/api/board` la trae dentro
					}
					var salen []string
					for _, p := range m["pedidos"].([]any) {
						salen = append(salen, p.(map[string]any)["customerName"].(string))
					}
					sort.Strings(salen)
					if strings.Join(salen, ",") != strings.Join(esperado, ",") {
						t.Errorf("%s%s:\n  salen      %v\n  esperados  %v", ruta, query, salen, esperado)
					}
					if total, _ := m["total"].(float64); int(total) != len(esperado) {
						t.Errorf("%s%s: el total dice %v encima de una lista de %d", ruta, query, total, len(esperado))
					}
				}
			})
		}
	}
}
