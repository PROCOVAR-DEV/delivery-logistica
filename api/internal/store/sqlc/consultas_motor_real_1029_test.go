package sqlc

// Pruebas de MOTOR REAL de la entrega 1.0.29 (auditoría de la 1.0.28, 08/10/2026).
// Misma regla que `consultas_motor_real_test.go`: sólo con `REPARTO_MOTOR_REAL_DSN` a una base
// aislada, cada subprueba en su transacción y revertida.
//
//   - T6: `EngancharPedidoARuta` deja LIMPIO el intento anterior de un devuelto/cancelado, y
//     un entregado no se reasigna (ni se le borra la entrega).
//   - T2: `ActualizarPedido` ya no escribe la ruta, el estado, el precio, el peso, el orden de
//     parada ni la hora de entrega.

import (
	"reflect"
	"testing"
	"time"

	"github.com/google/uuid"
)

// fotoDelIntento lee, directamente de la tabla, todo lo que un intento anterior deja pegado.
type fotoDelIntento struct {
	Ruta, Ultima             *uuid.UUID
	Resultado                *string
	ResultadoAt, EntregadoEn *time.Time
	Nota                     *string
	Estado                   string
	Precio, Peso             *float64
	Orden                    *int32
}

func (b *banco) fotoDelIntento(p uuid.UUID) fotoDelIntento {
	b.t.Helper()
	var f fotoDelIntento
	err := b.tx.QueryRow(b.ctx, `
SELECT route_id, ultima_ruta_id, resultado::text, resultado_at, delivered_at, resultado_nota,
       status::text, price, weight, stop_order
FROM orders WHERE id = $1`, p).Scan(&f.Ruta, &f.Ultima, &f.Resultado, &f.ResultadoAt,
		&f.EntregadoEn, &f.Nota, &f.Estado, &f.Precio, &f.Peso, &f.Orden)
	if err != nil {
		b.t.Fatalf("lectura del pedido %s: %v", p, err)
	}
	return f
}

// devueltoDeAyer siembra un pedido tal como lo deja `MarcarResultadoDeParada` con un
// devuelto/cancelado: sin `route_id`, con la hoja (`ultima_ruta_id`) y con su resultado, su
// hora y su nota. Si `entregado`, además con la hora de entrega y el estado `delivered`.
func (b *banco) devueltoDeAyer(suc, rutaVieja uuid.UUID, resultado string) uuid.UUID {
	b.t.Helper()
	s := listo("p-"+resultado, suc)
	s.UltimaRuta = alcance(rutaVieja)
	s.Resultado = str(resultado)
	s.Entregado = resultado == "entregado"
	p := b.pedido(s)
	b.exec(`UPDATE orders SET resultado_at = now() - interval '1 day', resultado_nota = 'el cliente no estaba' WHERE id = $1`, p)
	return p
}

func TestMotorReal_ReasignarUnDevueltoOCanceladoEsUnIntentoNuevo(t *testing.T) {
	pool := motorReal(t)

	for _, resultado := range []string{"devuelto", "cancelado"} {
		t.Run(resultado, func(t *testing.T) {
			b := nuevoBanco(t, pool)
			suc := b.sucursal()
			vieja, nueva := b.ruta(suc, RouteStatusCompleted), b.ruta(suc, RouteStatusPlanned)
			p := b.devueltoDeAyer(suc, vieja, resultado)

			antes := b.fotoDelIntento(p)
			if antes.Resultado == nil || antes.ResultadoAt == nil || antes.Nota == nil {
				t.Fatalf("la siembra no dejó lo del intento anterior: %+v", antes)
			}

			n, err := b.q.EngancharPedidoARuta(b.ctx, EngancharPedidoARutaParams{
				PedidoID: p, RutaID: alcance(nueva), StopOrder: i32(1), Sucursal: alcance(suc)})
			if err != nil || n != 1 {
				t.Fatalf("reasignar un %s: n=%d err=%v", resultado, n, err)
			}
			d := b.fotoDelIntento(p)
			if d.Resultado != nil || d.ResultadoAt != nil || d.Nota != nil || d.EntregadoEn != nil {
				t.Fatalf("el pedido reasignado conserva lo del intento anterior: %+v", d)
			}
			if d.Ruta == nil || *d.Ruta != nueva || d.Ultima == nil || *d.Ultima != nueva {
				t.Fatalf("tenía que quedar en la ruta nueva (route y ultima): %+v", d)
			}

			// LA CONSECUENCIA QUE SE VEÍA: «Quitar de ruta» ya no es un 409 engañoso. Con el
			// resultado pegado, `SoltarParadaPlanificada` (guarda `resultado IS NULL`) no
			// soltaba nada.
			id, err := b.q.SoltarParadaPlanificada(b.ctx, SoltarParadaPlanificadaParams{
				PedidoID: p, RutaID: nueva, Sucursal: alcance(suc)})
			if err != nil || id != p {
				t.Fatalf("quitar la parada de la ruta nueva: id=%v err=%v", id, err)
			}
			b.restricciones("SoltarParadaPlanificada tras reasignar")
		})
	}

	// LA PAREJA, en dos mitades.
	t.Run("un_pedido_limpio_se_engancha_igual_y_no_inventa_resultado", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		nueva := b.ruta(suc, RouteStatusPlanned)
		p := b.pedido(listo("limpio", suc))
		n, err := b.q.EngancharPedidoARuta(b.ctx, EngancharPedidoARutaParams{
			PedidoID: p, RutaID: alcance(nueva), StopOrder: i32(1), Sucursal: alcance(suc)})
		if err != nil || n != 1 {
			t.Fatalf("n=%d err=%v", n, err)
		}
		if d := b.fotoDelIntento(p); d.Resultado != nil || d.ResultadoAt != nil || d.Nota != nil || d.EntregadoEn != nil {
			t.Fatalf("%+v", d)
		}
	})

	t.Run("un_entregado_NO_se_reasigna_y_conserva_su_entrega", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		vieja, nueva := b.ruta(suc, RouteStatusCompleted), b.ruta(suc, RouteStatusPlanned)
		// Un entregado cuya ruta se borró: `route_id` NULL por el ON DELETE SET NULL.
		p := b.devueltoDeAyer(suc, vieja, "entregado")
		antes := b.fotoDelIntento(p)
		if antes.EntregadoEn == nil || antes.Estado != "delivered" {
			t.Fatalf("la siembra del entregado: %+v", antes)
		}
		n, err := b.q.EngancharPedidoARuta(b.ctx, EngancharPedidoARutaParams{
			PedidoID: p, RutaID: alcance(nueva), StopOrder: i32(1), Sucursal: alcance(suc)})
		if err != nil || n != 0 {
			t.Fatalf("un entregado no se reasigna: n=%d err=%v", n, err)
		}
		if d := b.fotoDelIntento(p); d.Resultado == nil || *d.Resultado != "entregado" ||
			d.EntregadoEn == nil || d.ResultadoAt == nil || d.Nota == nil || d.Ruta != nil {
			t.Fatalf("la entrega se tocó: antes=%+v después=%+v", antes, d)
		}
	})

	// Un pedido con la hora de entrega puesta pero SIN `resultado` (entregado por el PATCH viejo
	// de /api/orders/{id}, que fijaba `delivered_at` sin pasar por el cierre): también es un
	// entregado. El `WHERE` mira las dos columnas, igual que `mensajeYaEntregados`.
	t.Run("una_hora_de_entrega_sin_resultado_tambien_es_un_entregado", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		nueva := b.ruta(suc, RouteStatusPlanned)
		s := listo("viejo", suc)
		s.Entregado = true // status delivered + delivered_at, sin resultado
		p := b.pedido(s)
		n, err := b.q.EngancharPedidoARuta(b.ctx, EngancharPedidoARutaParams{
			PedidoID: p, RutaID: alcance(nueva), StopOrder: i32(1), Sucursal: alcance(suc)})
		if err != nil || n != 0 {
			t.Fatalf("n=%d err=%v", n, err)
		}
		if d := b.fotoDelIntento(p); d.EntregadoEn == nil || d.Ruta != nil {
			t.Fatalf("se tocó un entregado: %+v", d)
		}
	})
}

func TestMotorReal_ActualizarPedidoSoloTocaLoQueSeCorrigeAMano(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()
	ruta := b.ruta(suc, RouteStatusPlanned)
	s := listo("en ruta", suc)
	s.Ruta, s.UltimaRuta, s.StopOrder = alcance(ruta), alcance(ruta), i32(4)
	s.Peso = f64(37.5)
	p := b.pedido(s)
	b.exec(`UPDATE orders SET price = 12.5 WHERE id = $1`, p)
	antes := b.fotoDelIntento(p)

	fila, err := b.q.ActualizarPedido(b.ctx, ActualizarPedidoParams{
		ID: p, Sucursal: alcance(suc),
		OperationNumber: str("PTB25-1"), CustomerName: str("Bar del Parque"), Address: str("Calle 9"),
		EndAddress: str("Calle 10"), EndLat: f64(20.1), EndLng: f64(-75.8), Lat: f64(20.2), Lng: f64(-75.9),
		Notes: str("tocar timbre"),
	})
	if err != nil {
		t.Fatal(err)
	}
	if fila.CustomerName != "Bar del Parque" {
		t.Fatalf("no cambió lo que sí se corrige: %+v", fila)
	}
	despues := b.fotoDelIntento(p)
	// LO QUE EL PATCH YA NO PUEDE TOCAR: ruta, estado, precio, peso, orden de parada y la
	// hora de entrega. Mutar la consulta para que vuelva a escribirlos pone esto en rojo.
	if !reflect.DeepEqual(despues, antes) {
		t.Fatalf("ActualizarPedido tocó lo que ya no puede:\n antes   %+v\n después %+v", antes, despues)
	}
	if despues.Ruta == nil || *despues.Ruta != ruta || despues.Orden == nil || *despues.Orden != 4 ||
		despues.Precio == nil || *despues.Precio != 12.5 || despues.Peso == nil || *despues.Peso != 37.5 {
		t.Fatalf("la parada ya no es la que era: %+v", despues)
	}

	// El alcance sigue mandando: de otra sucursal, ErrNoRows (el 404).
	otra := b.sucursal()
	if _, err := b.q.ActualizarPedido(b.ctx, ActualizarPedidoParams{
		ID: p, Sucursal: alcance(otra), CustomerName: str("mío ahora")}); err == nil {
		t.Fatal("un pedido de otra sucursal se actualizó")
	}
}
