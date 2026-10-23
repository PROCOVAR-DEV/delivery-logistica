package api

// EL AVISO POR FACTURA CONTRA POSTGRES DE VERDAD (00028): la consulta que lee folio/factura, el
// INSERT del buzón con las columnas nuevas y el SELECT del drenaje. Un doble no ve que una columna
// falte o que el SELECT no la traiga. Comparte entorno con `facturas_motor_real_test.go`.

import (
	"context"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestMotorReal_LaFacturaCanceladaSeEncolaYElDrenajeLaMandaIgual(t *testing.T) {
	env := nuevoEntornoReal(t)
	t.Cleanup(func() {
		_, _ = env.pool.Exec(context.Background(), `DELETE FROM avisos_a_pedido WHERE sucursal = $1 OR pedido_id LIKE 'factura:'||$1||':%'`, env.codigo)
	})
	env.sembrarEntregas(facturaDeMentira("1", "2026-10-19", "FA"), facturaDeMentira("2", "2026-10-19", ""))
	con, sin := env.idDe(env.exF("1", "2026-10-19")), env.idDe(env.exF("2", "2026-10-19"))
	cuando := time.Date(2026, 10, 23, 9, 0, 0, 0, time.UTC)

	n, err := env.acotado.AvisarFacturasCanceladas(env.ctx, []uuid.UUID{con, sin}, cuando)
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v; se esperaba 1 (la que tiene folio) y sin error", n, err)
	}

	var enviados []AvisoDeParada
	s := &Servidor{reg: slog.New(slog.DiscardHandler), aPedido: func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		for _, a := range avisos {
			if a.Sucursal == env.codigo {
				enviados = append(enviados, a)
			}
		}
		return ParteAPedido{Ok: false, Error: "PEDIDO caído"} // se reintenta: sigue pendiente
	}}
	s.DrenarElBuzon(env.ctx, env.acotado)
	s.DrenarElBuzon(env.ctx, env.acotado) // y el segundo intento lleva lo mismo

	if len(enviados) != 2 || enviados[0] != enviados[1] {
		t.Fatalf("el reintento tiene que ser idéntico al primer intento: %+v", enviados)
	}
	a := enviados[0]
	if a.Folio != "FA" || a.Sucursal != env.codigo || a.Factura != "1" || a.PuntoDeVenta != "2" ||
		a.Estado != "cancelado" || a.PedidoID != "" || !a.At.Equal(cuando) {
		t.Fatalf("aviso reenviado mal armado: %+v", a)
	}
}
