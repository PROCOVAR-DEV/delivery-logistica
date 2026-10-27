package api

// PUT /api/routes/{id}/stops — REORDENAR LAS PARADAS (issue 11 de Amado, 15/10/2026).
//
// Van en pareja, como manda el CLAUDE.md: lo que pasa y lo que no pasa. Los literales y la
// cuenta de cercanía los ata además `docs/reordenar-paradas.casos.json` con la app; aquí se
// prueba el manejador montado con sus middlewares, sobre el doble de `rutas_test.go`.

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// FijarOrdenDeParada repite el WHERE del SQL: el pedido, cargado AHORA en esa ruta
// (`route_id`) y de la sucursal del alcance. Sólo toca el orden y el `segment_km`.
func (d *dobleDeRutas) FijarOrdenDeParada(_ context.Context, arg sqlc.FijarOrdenDeParadaParams) (int64, error) {
	p, hay := d.pedidos[arg.PedidoID]
	if hay && arg.PedidoID == seVaAlEscribir {
		p.rutaID = nil // la carrera: otro cierre la soltó entre la lectura y esta escritura
	}
	if !hay || p.rutaID == nil || [16]byte(*p.rutaID) != arg.RutaID.Bytes || !alcanza(arg.Sucursal, &p.sucursal) {
		return 0, nil
	}
	p.stopOrder, p.segmentKm = arg.StopOrder, arg.SegmentKm
	return 1, nil
}

// seVaAlEscribir: la parada que otra petición suelta justo antes de escribir su orden.
var seVaAlEscribir uuid.UUID

var rutaQueSeOrdena = uuid.MustParse("eeeeeeee-0000-0000-0000-000000000001")

// rutaParaOrdenar: una ruta de Santiago con origen en (0,0) y las tres paradas de
// `datosDeReparto` cargadas en el orden lejos(0,0.30), cerca(0,0.05), medio(0,0.15).
func rutaParaOrdenar(estado sqlc.RouteStatus) (*dobleDeRutas, [3]uuid.UUID) {
	d, ids, _ := datosDeReparto()
	cero := 0.0
	d.rutas[rutaQueSeOrdena] = &rutaDeRutas{
		id: rutaQueSeOrdena, codigo: "RT-ORD-001", estado: estado, sucursal: &stgDeRutas,
		origenLat: &cero, origenLng: &cero, km: 1, optimized: true, creada: time.Now(),
	}
	for i, id := range ids {
		n := int32(i + 1)
		ruta := rutaQueSeOrdena
		d.pedidos[id].rutaID, d.pedidos[id].ultimaRuta, d.pedidos[id].stopOrder = &ruta, &ruta, &n
	}
	return d, ids
}

func cuerpoDeOrden(ids ...uuid.UUID) string {
	b, _ := json.Marshal(map[string]any{"orden": ids})
	return string(b)
}

// ordenEnElDoble: los ids de las paradas por su `stop_order`.
func ordenEnElDoble(d *dobleDeRutas, ids [3]uuid.UUID) [3]uuid.UUID {
	var salida [3]uuid.UUID
	for _, id := range ids {
		if n := d.pedidos[id].stopOrder; n != nil && *n >= 1 && *n <= 3 {
			salida[*n-1] = id
		}
	}
	return salida
}

const rutaDeOrdenar = "/api/routes/eeeeeeee-0000-0000-0000-000000000001/stops"

func TestOrdenarAManoAplicaElOrdenYRecalculaLosKm(t *testing.T) {
	d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
	lejos, cerca, medio := ids[0], ids[1], ids[2]
	h := montarRutas(t, d)

	w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), cuerpoDeOrden(cerca, lejos, medio))
	if w.Code != http.StatusOK {
		t.Fatalf("reordenar a mano contestó %d: %s", w.Code, w.Body.String())
	}
	if got := ordenEnElDoble(d, ids); got != [3]uuid.UUID{cerca, lejos, medio} {
		t.Fatalf("el orden guardado es %v y se pidió cerca, lejos, medio", got)
	}
	// El circuito en ESE orden, con la vuelta: 0→0,05→0,30→0,15→0.
	esperado := kmHaversine(0, 0, 0, 0.05) + kmHaversine(0, 0.05, 0, 0.30) +
		kmHaversine(0, 0.30, 0, 0.15) + kmHaversine(0, 0.15, 0, 0)
	if math.Abs(d.rutas[rutaQueSeOrdena].km-esperado) > 1e-9 {
		t.Fatalf("total_distance = %.6f km y el circuito en el orden nuevo mide %.6f (con la vuelta)",
			d.rutas[rutaQueSeOrdena].km, esperado)
	}
	// `segment_km` es la RADIAL desde el origen: se recalcula, y no depende del orden.
	for _, id := range ids {
		p := d.pedidos[id]
		if p.segmentKm == nil || math.Abs(*p.segmentKm-kmHaversine(0, 0, *p.endLat, *p.endLng)) > 1e-9 {
			t.Fatalf("%s: segment_km = %v y tenía que ser la recta desde el origen", p.cliente, p.segmentKm)
		}
	}
	if d.rutas[rutaQueSeOrdena].optimized {
		t.Fatal("un orden puesto a mano quedó firmado `optimized = true`: diría que lo calculó la máquina")
	}
	// Y la respuesta es la ruta releída, con las paradas en el orden nuevo.
	var ruta RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil || len(ruta.Orders) != 3 || ruta.Orders[0].ID != cerca {
		t.Fatalf("la respuesta no trae la ruta en el orden nuevo: %s", w.Body.String())
	}
}

func TestOrdenarPorCercaniaUsaElOrigenDeLaRutaYFirmaLaMaquina(t *testing.T) {
	d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
	lejos, cerca, medio := ids[0], ids[1], ids[2]
	d.rutas[rutaQueSeOrdena].optimized = false
	h := montarRutas(t, d)

	w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), `{"porCercania":true}`)
	if w.Code != http.StatusOK {
		t.Fatalf("por cercanía contestó %d: %s", w.Code, w.Body.String())
	}
	if got := ordenEnElDoble(d, ids); got != [3]uuid.UUID{cerca, medio, lejos} {
		t.Fatalf("por cercanía desde (0,0) el orden es %v y tenía que ser cerca, medio, lejos", got)
	}
	ida := kmHaversine(0, 0, 0, 0.30)
	if math.Abs(d.rutas[rutaQueSeOrdena].km-2*ida) > 1e-9 {
		t.Fatalf("total_distance = %.6f y en línea recta ida y vuelta son %.6f", d.rutas[rutaQueSeOrdena].km, 2*ida)
	}
	if !d.rutas[rutaQueSeOrdena].optimized {
		t.Fatal("ordenado por la máquina y quedó firmado como orden a mano")
	}
}

// LA PAREJA DE LA FIRMA Y DE LOS KM: un orden peor a mano tiene que SUBIR el total. Si el
// manejador dejara el total viejo, la prueba de arriba no lo vería en una ruta ya óptima.
func TestReordenarCambiaLosKmDeLaCabecera(t *testing.T) {
	d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
	lejos, cerca, medio := ids[0], ids[1], ids[2]
	h := montarRutas(t, d)
	llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), `{"porCercania":true}`)
	bueno := d.rutas[rutaQueSeOrdena].km
	llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), cuerpoDeOrden(lejos, cerca, medio))
	if malo := d.rutas[rutaQueSeOrdena].km; malo <= bueno+1 {
		t.Fatalf("el orden en zigzag mide %.3f km y el bueno %.3f: el total no se recalculó", malo, bueno)
	}
}

func TestOrdenarUnaRutaEnCursoSiYUnaCompletadaNo(t *testing.T) {
	for _, c := range []struct {
		estado sqlc.RouteStatus
		codigo int
	}{
		{sqlc.RouteStatusPlanned, http.StatusOK},
		{sqlc.RouteStatusInProgress, http.StatusOK},
		{sqlc.RouteStatusCompleted, http.StatusConflict},
	} {
		d, ids := rutaParaOrdenar(c.estado)
		h := montarRutas(t, d)
		w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), cuerpoDeOrden(ids[2], ids[1], ids[0]))
		if w.Code != c.codigo {
			t.Fatalf("ruta %s: contestó %d y tenía que ser %d: %s", c.estado, w.Code, c.codigo, w.Body.String())
		}
		if c.codigo != http.StatusOK {
			if got := errorDeRutas(t, w); got != msgRutaCompletada {
				t.Fatalf("ruta completada: el motivo es %q y tenía que ser el literal %q", got, msgRutaCompletada)
			}
			if ordenEnElDoble(d, ids) != ids {
				t.Fatal("una ruta completada es histórico y su orden se movió")
			}
		}
	}
}

func TestOrdenarConUnaListaQueNoCuadraNoMueveNada(t *testing.T) {
	d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
	lejos, cerca, medio := ids[0], ids[1], ids[2]
	h := montarRutas(t, d)
	casos := []struct {
		nombre, cuerpo string
		codigo         int
		motivo         string
	}{
		{"falta una", cuerpoDeOrden(cerca, lejos), http.StatusConflict,
			"El nuevo orden no coincide con las paradas de la ruta (falta X-Medio). Vuelve a abrir la ruta y ordénala otra vez."},
		{"repetida", cuerpoDeOrden(cerca, cerca, lejos, medio), http.StatusBadRequest,
			"El nuevo orden repite la parada X-Cerca: cada parada va una sola vez."},
		{"sobra una de otra sucursal", cuerpoDeOrden(cerca, lejos, medio, uuid.MustParse("dddddddd-0000-0000-0000-000000000004")),
			http.StatusConflict,
			"El nuevo orden no coincide con las paradas de la ruta (sobra 1 factura que no va en ella). Vuelve a abrir la ruta y ordénala otra vez."},
		{"un id que no es un id", `{"orden":["no-es-un-uuid"]}`, http.StatusBadRequest, "Identificador de factura no válido"},
		{"ni orden ni porCercania", `{}`, http.StatusBadRequest, msgOrdenSinForma},
		{"las dos formas a la vez", `{"orden":[],"porCercania":true}`, http.StatusBadRequest, msgOrdenSinForma},
	}
	for _, c := range casos {
		w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), c.cuerpo)
		if w.Code != c.codigo || errorDeRutas(t, w) != c.motivo {
			t.Errorf("%s: contestó %d %q y tenía que ser %d %q", c.nombre, w.Code, errorDeRutas(t, w), c.codigo, c.motivo)
		}
		if ordenEnElDoble(d, ids) != ids || d.rutas[rutaQueSeOrdena].km != 1 {
			t.Fatalf("%s: un orden rechazado movió las paradas o los km: nada de reordenar a medias", c.nombre)
		}
	}
	// LA PAREJA: la misma lista entera, sí.
	if w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), cuerpoDeOrden(medio, cerca, lejos)); w.Code != http.StatusOK {
		t.Fatalf("la lista exacta contestó %d: %s", w.Code, w.Body.String())
	}
}

func TestOrdenarLaRutaDeOtraSucursalNoExisteParaTi(t *testing.T) {
	d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
	d.rutas[rutaQueSeOrdena].sucursal = &holDeRutas
	for _, id := range ids {
		d.pedidos[id].sucursal = holDeRutas
	}
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), cuerpoDeOrden(ids[2], ids[1], ids[0]))
	if w.Code != http.StatusNotFound {
		t.Fatalf("Santiago reordenó una ruta de Holguín: %d %s", w.Code, w.Body.String())
	}
	if ordenEnElDoble(d, ids) != ids {
		t.Fatal("el orden de la ruta de Holguín se movió desde Santiago")
	}
	// LA PAREJA: quien ve las ocho, sí.
	if w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, superAdminEnRutas(t), cuerpoDeOrden(ids[2], ids[1], ids[0])); w.Code != http.StatusOK {
		t.Fatalf("el SUPER ADMIN no pudo reordenar: %d %s", w.Code, w.Body.String())
	}
}

func TestSinPuntoDeSalidaNoSeReordena(t *testing.T) {
	d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
	d.rutas[rutaQueSeOrdena].origenLat = nil
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), `{"porCercania":true}`)
	if w.Code != http.StatusConflict || errorDeRutas(t, w) != msgRutaSinOrigen {
		t.Fatalf("sin origen contestó %d %s", w.Code, w.Body.String())
	}
	if ordenEnElDoble(d, ids) != ids {
		t.Fatal("sin origen se movió el orden")
	}
}

// LA PARADA SIN COORDENADAS va al final por cercanía, se queda sin `segment_km` (un hueco,
// no un cero) y no entra en los km del circuito: (0,0) sería el golfo de Guinea.
// Y una coordenada FUERA DEL PLANETA cuenta igual que ninguna: su NaN se comería el total
// y la respuesta entera (`puntoDelPlaneta`).
func TestLaParadaSinPuntoVaAlFinalYSinKm(t *testing.T) {
	imposible := 1e308
	for nombre, lat := range map[string]*float64{"sin coordenadas": nil, "fuera del planeta": &imposible} {
		d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
		lejos, cerca, medio := ids[0], ids[1], ids[2]
		d.pedidos[lejos].endLat = lat
		viejo := 7.0
		d.pedidos[lejos].segmentKm = &viejo
		h := montarRutas(t, d)
		if w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), `{"porCercania":true}`); w.Code != http.StatusOK {
			t.Fatalf("%s: contestó %d: %s", nombre, w.Code, w.Body.String())
		}
		if got := ordenEnElDoble(d, ids); got != [3]uuid.UUID{cerca, medio, lejos} {
			t.Fatalf("%s: no quedó al final: %v", nombre, got)
		}
		if d.pedidos[lejos].segmentKm != nil {
			t.Fatalf("%s: quedó con segment_km = %v", nombre, *d.pedidos[lejos].segmentKm)
		}
		if esperado := 2 * kmHaversine(0, 0, 0, 0.15); math.Abs(d.rutas[rutaQueSeOrdena].km-esperado) > 1e-9 {
			t.Fatalf("%s: total = %.6f y sin ella son %.6f", nombre, d.rutas[rutaQueSeOrdena].km, esperado)
		}
	}
}

// LA CARRERA: una parada sale de la ruta entre la lectura y la escritura. Se deshace TODO
// (en la base, el rollback de la transacción; aquí, el del doble) y se dice con su motivo.
func TestSiUnaParadaSeVaMientrasSeOrdenaNoSeOrdenaANadie(t *testing.T) {
	d, ids := rutaParaOrdenar(sqlc.RouteStatusPlanned)
	seVaAlEscribir = ids[2]
	t.Cleanup(func() { seVaAlEscribir = uuid.Nil })
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPut, rutaDeOrdenar, deSantiagoEnRutas(t), cuerpoDeOrden(ids[1], ids[0], ids[2]))
	if w.Code != http.StatusConflict ||
		errorDeRutas(t, w) != "El nuevo orden no coincide con las paradas de la ruta (una parada dejó la ruta mientras se ordenaba). Vuelve a abrir la ruta y ordénala otra vez." {
		t.Fatalf("la carrera contestó %d %s", w.Code, w.Body.String())
	}
	if ordenEnElDoble(d, ids) != ids || d.rutas[rutaQueSeOrdena].km != 1 {
		t.Fatal("la carrera dejó la ruta reordenada a medias")
	}
}
