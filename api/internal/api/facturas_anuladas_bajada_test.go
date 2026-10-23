package api

// LA FACTURA ANULADA LLEGA AL APARATO (00027, Jose y Amado, 23/10/2026).
//
// Cuando el espejo quita de su ruta una factura que Ventra ya no manda, la fila queda ARCHIVADA
// con `anulada_at`. Archivada, la bajada la manda en `quitados` (el aparato la borra de `orders`,
// donde ya no cuenta para nadie) y, además, en `facturasAnuladas`, para que la app diga «la factura
// 47412 se canceló y se quitó de la ruta Centro».
//
// Corren contra el doble de `espejo_test.go` (que repite el `WHERE` del SQL); que el SQL de verdad
// haga lo mismo lo ata `facturas_anuladas_motor_real_test.go`.

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

var (
	pedAnulada      = uuid.MustParse("7d000000-0000-0000-0000-0000000000a1")
	pedAnuladaVieja = uuid.MustParse("7d000000-0000-0000-0000-0000000000a2")
	pedAnuladaHol   = uuid.MustParse("7d000000-0000-0000-0000-0000000000a3")
	rutaDeLaAnulada = uuid.MustParse("7a000000-0000-0000-0000-0000000000a1")
)

func conAnuladas(q *espejoFalso) {
	ahora := time.Now().UTC()
	reciente, vieja := ahora.Add(-2*time.Hour), ahora.Add(-10*24*time.Hour)
	q.sync = append(q.sync,
		pedidoSync{id: pedAnulada, sucursal: sucStg, nombre: "Cliente de la 47412", archivado: true,
			marca: ahora.Add(-90 * time.Minute), facturaNumero: "47412", anuladaAt: &reciente, anuladaRuta: rutaDeLaAnulada},
		// Más vieja que la ventana de 7 días: sólo `quitados`.
		pedidoSync{id: pedAnuladaVieja, sucursal: sucStg, nombre: "Anulada hace diez días", archivado: true,
			marca: ahora.Add(-80 * time.Minute), anuladaAt: &vieja, anuladaRuta: rutaDeLaAnulada},
		// De OTRA sucursal: quien pregunta por Santiago no se entera.
		pedidoSync{id: pedAnuladaHol, sucursal: sucHol, nombre: "Anulada en Holguín", archivado: true,
			marca: ahora.Add(-70 * time.Minute), anuladaAt: &reciente, anuladaRuta: rutaDeLaAnulada},
	)
}

func puestosPorId(t *testing.T, m map[string]any, coleccion string) map[string]map[string]any {
	t.Helper()
	c, ok := m["cambios"].(map[string]any)[coleccion].(map[string]any)
	if !ok {
		t.Fatalf("la bajada no trae la colección %q", coleccion)
	}
	salida := map[string]map[string]any{}
	puestos, _ := c["puestos"].([]any)
	for _, p := range puestos {
		fila := p.(map[string]any)
		salida[fila["id"].(string)] = fila
	}
	return salida
}

func TestLaFacturaAnuladaBajaEnSuColeccionYSaleDeOrders(t *testing.T) {
	for nombre, cola := range map[string]string{
		"por diferencias": "?desde=" + time.Now().UTC().Add(-24*time.Hour).Format(time.RFC3339Nano),
		"carga inicial":   "",
	} {
		t.Run(nombre, func(t *testing.T) {
			q := nuevoEspejo()
			conAnuladas(q)
			m := bajadaDe(t, q, tokenTab(t, sucStg.String()), cola)

			anuladas := puestosPorId(t, m, "facturasAnuladas")
			fila, hay := anuladas[pedAnulada.String()]
			if !hay {
				t.Fatalf("la anulada de los últimos 7 días tiene que bajar en «facturasAnuladas»: %v", anuladas)
			}
			// LAS CLAVES, no los valores (como `la_bajada_no_pierde_campos_test.go`): lo que se rompe es
			// que una clave deje de escribirse.
			for _, k := range []string{"id", "operationNumber", "customerName", "facturaNumero", "branchId", "anuladaAt", "anuladaDeRutaId", "updatedAt"} {
				if _, ok := fila[k]; !ok {
					t.Errorf("facturasAnuladas: falta la clave %q", k)
				}
			}
			if fila["anuladaDeRutaId"] != rutaDeLaAnulada.String() || fila["facturaNumero"] != "47412" {
				t.Errorf("la ruta de la que salió y su número: %v", fila)
			}
			if _, hay := anuladas[pedAnuladaVieja.String()]; hay {
				t.Error("la anulada de hace diez días ya no baja como aviso")
			}
			if _, hay := anuladas[pedAnuladaHol.String()]; hay {
				t.Error("la anulada de OTRA sucursal no baja: el alcance es de quien pregunta")
			}
			// Y de `orders` sale: archivada, el aparato la borra (también en la carga completa: una copia
			// rebajada puede tener todavía la fila viva).
			if !bajasDe(t, m, "orders")[pedAnulada.String()] {
				t.Error("la anulada tiene que ir TAMBIÉN en «quitados» de orders: si no, el aparato la sigue contando")
			}
			for _, p := range m["cambios"].(map[string]any)["orders"].(map[string]any)["puestos"].([]any) {
				if p.(map[string]any)["id"] == pedAnulada.String() {
					t.Error("una fila archivada no se pone en orders")
				}
			}
		})
	}
}

// El aparato anterior a la 1.0.43 no conoce «facturasAnuladas»: sólo recorre las colecciones que
// conoce, y para él la anulada es una archivada más (en quitados). Esto fija que la colección
// nueva no cambia la forma de las demás.
func TestLaColeccionNuevaNoCambiaLasDemas(t *testing.T) {
	q := nuevoEspejo()
	conAnuladas(q)
	m := bajadaDe(t, q, tokenTab(t, sucStg.String()), "?desde="+time.Now().UTC().Add(-24*time.Hour).Format(time.RFC3339Nano))
	if bajasDe(t, m, "facturasAnuladas") == nil {
		t.Error("la colección nueva lleva su «quitados» como lista (no null), como todas")
	}
}
