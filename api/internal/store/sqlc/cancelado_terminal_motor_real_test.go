package sqlc

// UN CANCELADO ES TERMINAL, Y CADA GUARDA DE CANCELAR TIENE SU PRUEBA (issue 25 de Amado, auditoría del servidor).
//
// G1: la hoja de cierre (`MarcarResultadoDeParada` / `LimpiarResultadoDeParada`) reconoce las paradas ya soltadas con un
// resultado por `ultima_ruta_id` mientras la ruta no se complete, y un `cancelado` lo cumplía: reenviar «devuelto»,
// «entregado» o quitar la marca por `/results` reabría la factura en silencio.
// S2: `CancelarFacturaDevuelta` se llama AQUÍ directamente, con la fila en cada estado prohibido, saltándose el manejador
// (que lee antes y tapa el `WHERE`). M2: el Panel no cuenta lo cancelado en `peso_pendiente`.

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func (b *banco) cancelarDirecto(id uuid.UUID, suc uuid.UUID, nota *string) []uuid.UUID {
	b.t.Helper()
	ids, err := b.q.CancelarFacturaDevuelta(b.ctx, CancelarFacturaDevueltaParams{ID: id, Nota: nota, Sucursal: alcance(suc)})
	if err != nil {
		b.t.Fatal(err)
	}
	return ids
}

func TestMotorReal_UnCanceladoNoSeDeshaceDesdeLaHoja(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	ruta := b.ruta(suc, RouteStatusInProgress) // SIN completar: es donde se reabría
	c := b.devueltoDeAyer(suc, ruta, "cancelado")
	antes := b.fotoDelIntento(c)

	intactos := func(que string) {
		t.Helper()
		d := b.fotoDelIntento(c)
		if d.Resultado == nil || *d.Resultado != "cancelado" || d.Ruta != nil || d.Nota == nil || *d.Nota != *antes.Nota ||
			d.ResultadoAt == nil || !d.ResultadoAt.Equal(*antes.ResultadoAt) || d.EntregadoEn != nil {
			t.Fatalf("%s tocó una cancelada: %+v (antes %+v)", que, d, antes)
		}
	}
	for _, nuevo := range []StopResult{StopResultDevuelto, StopResultEntregado} {
		n, err := b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
			Resultado: nuevo, Nota: str("otra"), RutaID: alcance(ruta), PedidoID: c, Sucursal: alcance(suc)})
		if err != nil || n != 0 {
			t.Fatalf("marcar %s sobre una cancelada: n=%d err=%v (tenía que ser 0)", nuevo, n, err)
		}
		intactos("marcar " + string(nuevo))
	}
	n, err := b.q.LimpiarResultadoDeParada(b.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(ruta), PedidoID: c, Sucursal: alcance(suc)})
	if err != nil || n != 0 {
		t.Fatalf("quitar la marca de una cancelada: n=%d err=%v (tenía que ser 0)", n, err)
	}
	intactos("quitar la marca")

	// Sigue saliendo en la hoja de la ruta (como cancelada): no se pierde, solo no se deshace.
	filas, err := b.q.ListarParadasQueViajaronEnRuta(b.ctx, ListarParadasQueViajaronEnRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
	if err != nil || len(filas) != 1 || filas[0].ID != c || filas[0].Resultado == nil || *filas[0].Resultado != StopResultCancelado {
		t.Fatalf("la cancelada tiene que seguir en la hoja como cancelada: %+v err=%v", filas, err)
	}

	// Volver a marcar `cancelado` (una hoja que se reenvía entera) SÍ se admite.
	n, err = b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
		Resultado: StopResultCancelado, RutaID: alcance(ruta), PedidoID: c, Sucursal: alcance(suc)})
	if err != nil || n != 1 {
		t.Fatalf("repetir «cancelado»: n=%d err=%v (tenía que ser 1)", n, err)
	}

	// LA PAREJA: un DEVUELTO de la misma ruta, con la misma forma, sigue pudiéndose corregir y desmarcar.
	d := b.devueltoDeAyer(suc, ruta, "devuelto")
	if n, err := b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
		Resultado: StopResultEntregado, RutaID: alcance(ruta), PedidoID: d, Sucursal: alcance(suc)}); err != nil || n != 1 {
		t.Fatalf("corregir un devuelto: n=%d err=%v", n, err)
	}
	e := b.devueltoDeAyer(suc, ruta, "devuelto")
	if n, err := b.q.LimpiarResultadoDeParada(b.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(ruta), PedidoID: e, Sucursal: alcance(suc)}); err != nil || n != 1 {
		t.Fatalf("desmarcar un devuelto: n=%d err=%v", n, err)
	}
}

// La misma guarda en la cláusula de los MIEMBROS de un conduce: un miembro cancelado no se reabre con su principal.
func TestMotorReal_UnMiembroCanceladoNoSeDeshaceConSuPrincipal(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	ruta := b.ruta(suc, RouteStatusInProgress)
	principal := b.devueltoDeAyer(suc, ruta, "devuelto")
	miembro := b.devueltoDeAyer(suc, ruta, "cancelado")
	b.exec(`UPDATE orders SET conduce_principal_id = $1 WHERE id = $2`, principal, miembro)

	if n, err := b.q.MarcarResultadoDeParada(b.ctx, MarcarResultadoDeParadaParams{
		Resultado: StopResultEntregado, RutaID: alcance(ruta), PedidoID: principal, Sucursal: alcance(suc)}); err != nil || n != 1 {
		t.Fatalf("marcar la principal: n=%d err=%v", n, err)
	}
	if d := b.fotoDelIntento(miembro); d.Resultado == nil || *d.Resultado != "cancelado" {
		t.Fatalf("marcar la principal reabrió a su miembro cancelado: %+v", d)
	}
	if n, err := b.q.LimpiarResultadoDeParada(b.ctx, LimpiarResultadoDeParadaParams{RutaID: alcance(ruta), PedidoID: principal, Sucursal: alcance(suc)}); err != nil || n != 1 {
		t.Fatalf("desmarcar la principal: n=%d err=%v", n, err)
	}
	if d := b.fotoDelIntento(miembro); d.Resultado == nil || *d.Resultado != "cancelado" {
		t.Fatalf("desmarcar la principal reabrió a su miembro cancelado: %+v", d)
	}
}

// S2 · CADA GUARDA DEL `WHERE` DE CancelarFacturaDevuelta, con la fila en su estado prohibido y SIN el manejador delante.
func TestMotorReal_CancelarFacturaDevuelta_CadaGuardaDelWhere(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	vieja := b.ruta(suc, RouteStatusCompleted)

	casos := []struct {
		nombre  string
		siembra func() uuid.UUID
	}{
		{"sin resultado", func() uuid.UUID { return b.pedido(listo("sin-resultado", suc)) }},
		{"entregado", func() uuid.UUID { return b.devueltoDeAyer(suc, vieja, "entregado") }},
		{"ya cancelado", func() uuid.UUID { return b.devueltoDeAyer(suc, vieja, "cancelado") }},
		{"devuelto que va en una ruta", func() uuid.UUID {
			p := b.devueltoDeAyer(suc, vieja, "devuelto")
			b.exec(`UPDATE orders SET route_id = $2 WHERE id = $1`, p, b.ruta(suc, RouteStatusPlanned))
			return p
		}},
		{"devuelto con hora de entrega", func() uuid.UUID {
			p := b.devueltoDeAyer(suc, vieja, "devuelto")
			b.exec(`UPDATE orders SET delivered_at = now() WHERE id = $1`, p)
			return p
		}},
		{"devuelto que es miembro de un conduce", func() uuid.UUID {
			principal := b.devueltoDeAyer(suc, vieja, "devuelto")
			p := b.devueltoDeAyer(suc, vieja, "devuelto")
			b.exec(`UPDATE orders SET conduce_principal_id = $1 WHERE id = $2`, principal, p)
			return p
		}},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			p := c.siembra()
			antes := b.fotoDelIntento(p)
			if ids := b.cancelarDirecto(p, suc, str("x")); len(ids) != 0 {
				t.Fatalf("canceló una factura en estado «%s»: %v", c.nombre, ids)
			}
			despues := b.fotoDelIntento(p)
			if (antes.Resultado == nil) != (despues.Resultado == nil) || (antes.Resultado != nil && *antes.Resultado != *despues.Resultado) {
				t.Fatalf("«%s» cambió de resultado: %+v -> %+v", c.nombre, antes, despues)
			}
		})
	}

	t.Run("de otra sucursal", func(t *testing.T) {
		p := b.devueltoDeAyer(suc, vieja, "devuelto")
		if ids := b.cancelarDirecto(p, b.sucursal(), nil); len(ids) != 0 {
			t.Fatalf("canceló la factura de otra sucursal: %v", ids)
		}
	})

	// LA PAREJA: la devuelta normal, y su conduce entero con la guarda de los miembros.
	t.Run("la devuelta se cancela", func(t *testing.T) {
		p := b.devueltoDeAyer(suc, vieja, "devuelto")
		if ids := b.cancelarDirecto(p, suc, str("se arrepintió")); len(ids) != 1 || ids[0] != p {
			t.Fatalf("no canceló la devuelta: %v", ids)
		}
		if d := b.fotoDelIntento(p); *d.Resultado != "cancelado" || *d.Nota != "se arrepintió" {
			t.Fatalf("%+v", d)
		}
	})
	t.Run("los miembros: solo los devueltos y libres, con su principal", func(t *testing.T) {
		principal := b.devueltoDeAyer(suc, vieja, "devuelto")
		bueno := b.devueltoDeAyer(suc, vieja, "devuelto")
		enRuta := b.devueltoDeAyer(suc, vieja, "devuelto")
		conHora := b.devueltoDeAyer(suc, vieja, "devuelto")
		entregado := b.devueltoDeAyer(suc, vieja, "entregado")
		for _, m := range []uuid.UUID{bueno, enRuta, conHora, entregado} {
			b.exec(`UPDATE orders SET conduce_principal_id = $1 WHERE id = $2`, principal, m)
		}
		b.exec(`UPDATE orders SET route_id = $2 WHERE id = $1`, enRuta, b.ruta(suc, RouteStatusPlanned))
		b.exec(`UPDATE orders SET delivered_at = now() WHERE id = $1`, conHora)
		ids := b.cancelarDirecto(principal, suc, nil)
		if len(ids) != 2 {
			t.Fatalf("tenían que cancelarse la principal y el miembro bueno: %v", ids)
		}
		for _, m := range []uuid.UUID{enRuta, conHora, entregado} {
			if d := b.fotoDelIntento(m); *d.Resultado == "cancelado" {
				t.Fatalf("la guarda de los miembros dejó pasar a %s: %+v", m, d)
			}
		}
		if d := b.fotoDelIntento(bueno); *d.Resultado != "cancelado" {
			t.Fatalf("el miembro bueno no se canceló: %+v", d)
		}
	})
}

// M2 · `peso_pendiente` del Panel no cuenta lo cancelado (ni `sin_ruta`): los números con un devuelto y un cancelado, uno al lado del otro.
func TestMotorReal_ElPanelNoPesaLoCancelado(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	vieja := b.ruta(suc, RouteStatusCompleted)
	pesado := func(res string, kg float64) {
		s := listo("p-"+res, suc)
		s.Peso = f64(kg)
		p := b.pedido(s)
		b.exec(`UPDATE orders SET resultado = $2::text::stop_result, ultima_ruta_id = $3, resultado_at = now() WHERE id = $1`, p, res, vieja)
	}
	pesado("devuelto", 100)
	pesado("cancelado", 900)
	r, err := b.q.PanelResumen(b.ctx, PanelResumenParams{Hoy: pgtype.Timestamptz{Time: time.Now().Add(-24 * time.Hour), Valid: true}, Sucursal: alcance(suc)})
	if err != nil {
		t.Fatal(err)
	}
	if r.SinRuta != 1 || r.PesoPendiente != 100 {
		t.Fatalf("el panel cuenta lo cancelado: sin_ruta=%d peso_pendiente=%v (esperaba 1 y 100)", r.SinRuta, r.PesoPendiente)
	}
}
