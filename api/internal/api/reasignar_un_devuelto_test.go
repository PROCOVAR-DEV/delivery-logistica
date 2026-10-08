package api

// REASIGNAR UN DEVUELTO ES UN INTENTO NUEVO — 08/10/2026 (auditoría de la 1.0.28, I-2).
//
// Un pedido devuelto o cancelado suelta su `route_id` pero conserva `resultado`,
// `resultado_at` y `resultado_nota` (la hoja de lo que bajó del camión). Al meterlo en otra
// ruta esas columnas se quedaban pegadas, y entonces «Quitar de ruta» contestaba un 409
// engañoso (la guarda mira `resultado IS NULL`) y al borrar la ruta el pedido no volvía a su
// zona. `EngancharPedidoARuta` lo deja limpio; aquí se prueba por la puerta HTTP con el doble
// que repite la consulta, y contra Postgres de verdad en `consultas_motor_real_test.go`.
//
// EN PAREJA: el devuelto y el cancelado salen limpios; el ENTREGADO no se reasigna y su
// entrega no se borra.

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

func TestReasignarUnDevueltoOCanceladoLoDejaLimpioYSePuedeQuitar(t *testing.T) {
	for _, resultado := range []sqlc.StopResult{sqlc.StopResultDevuelto, sqlc.StopResultCancelado} {
		t.Run(string(resultado), func(t *testing.T) {
			d, stg, _ := datosDeReparto()
			rutaVieja := uuid.New()
			ayer := time.Now().Add(-24 * time.Hour)
			nota := "el cliente no estaba"
			p := d.pedidos[stg[1]]
			// Tal como lo deja `MarcarResultadoDeParada` con un devuelto: sin route_id,
			// con la hoja (`ultima_ruta_id`) y con su resultado, su hora y su nota.
			p.rutaID, p.ultimaRuta = nil, &rutaVieja
			p.resultado, p.resultadoAt, p.nota = &resultado, &ayer, &nota
			h := montarRutas(t, d)
			jwt := deSantiagoEnRutas(t)

			id := armarRutaDePrueba(t, h, jwt, stg[1])
			if p.resultado != nil || p.resultadoAt != nil || p.nota != nil || p.entregadoEn != nil {
				t.Fatalf("el pedido reasignado conserva lo del intento anterior: resultado=%v at=%v nota=%v entregado=%v",
					p.resultado, p.resultadoAt, p.nota, p.entregadoEn)
			}
			if p.rutaID == nil || *p.rutaID != id || p.ultimaRuta == nil || *p.ultimaRuta != id {
				t.Fatalf("tenía que quedar en la ruta nueva: route=%v ultima=%v", p.rutaID, p.ultimaRuta)
			}

			// Y la consecuencia que se veía: «Quitar de ruta» ya no es el 409 engañoso.
			w := llamarRutas(t, h, http.MethodDelete,
				fmt.Sprintf("/api/routes/%s/stops/%s", id, stg[1]), jwt, "")
			if w.Code != http.StatusOK {
				t.Fatalf("quitar la parada de la ruta nueva: %d %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestUnEntregadoNoSeReasignaNiSeLeBorraLaEntrega(t *testing.T) {
	d, stg, _ := datosDeReparto()
	rutaVieja := uuid.New()
	entregado := sqlc.StopResultEntregado
	hace := time.Now().Add(-2 * time.Hour)
	p := d.pedidos[stg[1]]
	// Un entregado cuya ruta se borró: `route_id` NULL por el ON DELETE SET NULL.
	p.rutaID, p.ultimaRuta = nil, &rutaVieja
	p.resultado, p.entregadoEn, p.resultadoAt = &entregado, &hace, &hace
	h := montarRutas(t, d)

	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), stg[1]))
	if w.Code != http.StatusConflict {
		t.Fatalf("un entregado no vuelve a un camión: %d %s", w.Code, w.Body.String())
	}
	if p.resultado == nil || *p.resultado != sqlc.StopResultEntregado || p.entregadoEn == nil {
		t.Fatalf("la entrega se borró: resultado=%v entregado=%v", p.resultado, p.entregadoEn)
	}
	if len(d.rutas) != 0 {
		t.Fatal("se armó una ruta con un pedido ya entregado")
	}
}
