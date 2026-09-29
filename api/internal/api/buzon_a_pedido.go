package api

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// EL BUZÓN DE SALIDA HACIA PEDIDO: que un aviso no se pierda porque el otro lado no estaba.
//
// El reparto le cuenta a PEDIDO en qué punto va cada pedido —entregado, devuelto,
// cancelado— por `POST /integration/orders/status`, y hasta el 26/09/2026 lo hacía **de una
// sola vez o nunca**: la llamada salía al cerrar la ruta y, si PEDIDO estaba caído o la red
// iba mal, el aviso desaparecía. El pedido quedaba entregado aquí y eterno «en proceso»
// allá, sin un error en ninguna pantalla y sin nadie a quien reclamarle. Jose, 26/09/2026:
// «el de enviar el estado de los pedidos de delivery, para que PEDIDO se entere de eso».
//
// LAS TRES SITUACIONES DE UN AVISO, y son tres y no dos:
//
//   - **enviado** — PEDIDO lo recibió y lo aplicó.
//   - **rechazado** — PEDIDO contestó perfectamente y dijo que NO: ese pedido no existe
//     allá, o el estado no lo conoce. Se queda a la vista con su motivo literal hasta que
//     una persona decida. No se reintenta: repetir lo mismo da lo mismo.
//   - **pendiente** — no se pudo ni preguntar. Eso NO es un rechazo, y confundirlos daría
//     por perdido lo que sólo estaba esperando. Lo vuelve a intentar el trabajador.
//
// El aviso se apunta ANTES de llamar, así que el peor caso es mandarlo dos veces —PEDIDO
// aplica el mismo estado dos veces y queda igual— y nunca ninguna.

// TopeDelDrenaje: cuántos avisos se drenan por vuelta.
//
// Corto a propósito: cada tanda es una llamada por la conexión de allá, y lo que se pierde
// si algo se cae es una tanda, no el buzón entero. Es el mismo número que [TandaAPedido] y
// por la misma razón.
const TopeDelDrenaje = TandaAPedido

// encolarAvisos apunta los avisos del cierre en el buzón, uno por uno.
//
// Devuelve cuántos se apuntaron. **Un fallo aquí no tumba el cierre**: el resultado de la
// parada ya está guardado y es lo que importa; lo que se pierde es el aviso, y eso se dice
// en el registro en vez de devolverle un error a quien acaba de cerrar la ruta con el
// camión en la puerta.
func (s *Servidor) encolarAvisos(
	ctx context.Context, a *alcance.Acotado, ruta any, avisos []AvisoDeParada,
) int {
	puestos := 0
	for _, av := range avisos {
		cuando := av.At
		if cuando.IsZero() {
			cuando = time.Now().UTC()
		}
		var nota *string
		if av.Nota != "" {
			n := av.Nota
			nota = &n
		}
		err := a.EncolarAvisoAPedido(ctx, sqlc.EncolarAvisoAPedidoParams{
			PedidoID: av.PedidoID,
			Estado:   av.Estado,
			Nota:     nota,
			// La hora del SUCESO, no la de la llamada: con el trabajo sin conexión
			// pueden ser tres horas distintas, y la que vale para el vendedor es
			// cuándo recibió su cliente. Ver `AvisoDeParada.At`.
			OcurrioAt: pgtype.Timestamptz{Time: cuando, Valid: true},
		})
		if err != nil {
			s.reg.Error("no se pudo apuntar el aviso a PEDIDO en el buzón",
				"ruta", ruta, "pedido", av.PedidoID, "err", err)
			continue
		}
		puestos++
	}
	return puestos
}

// apuntarLaRecepcion deja constancia de una tanda que entró por el webhook.
//
// NO SE GUARDA EL CUERPO. Son tandas de cientos de pedidos con nombres, teléfonos y
// direcciones: copiarlas aquí es tener el mismo dato personal en dos sitios y una tabla que
// crece sin techo. Se guardan los NÚMEROS, que es lo que se mira.
//
// Un fallo al apuntar **no tumba la recepción**: los pedidos ya están escritos y eso es lo
// que importa; lo que se pierde es la línea del registro, y eso se dice en el log.
func (s *Servidor) apuntarLaRecepcion(
	r *http.Request, a *alcance.Acotado, salida loteSalida, tardo time.Duration,
) {
	// QUIEN YA APUNTÓ SU FILA NO LLEVA OTRA. Lo pone este mismo proceso cuando un aviso del
	// webhook pasa por aquí de camino a guardarse: el aviso ya tiene su constancia, y una
	// segunda fila haría que `escritosHoy` contara ese pedido dos veces.
	if r.Header.Get(CabeceraDeConstancia) == YaApuntada {
		return
	}

	// `Skipped` son los que llegaron y NO se escribieron —sin coordenadas, sin
	// referencia—. No es un error de la tanda: es lo que hay que poder contar.
	motivos := ""
	if salida.Skipped > 0 {
		motivos = fmt.Sprintf("%d sin escribir (ver `results` de la respuesta)", salida.Skipped)
	}
	if err := a.ApuntarRecepcionDelWebhook(r.Context(), sqlc.ApuntarRecepcionDelWebhookParams{
		Origen:     OrigenDelLote,
		Traidos:    int32(salida.Total),
		Escritos:   int32(salida.Persisted),
		Rechazados: int32(salida.Skipped),
		Motivos:    textoONil(motivos),
		DuracionMs: int32(tardo.Milliseconds()),
	}); err != nil {
		s.reg.Error("no se pudo apuntar la recepción del webhook", "err", err)
	}

	// Y SE AVISA AL CANAL — 29/09/2026.
	//
	// Ésta es LA puerta por la que entran los pedidos de verdad: el lote del espejo de
	// PEDIDO, en tandas de doscientos. La pantalla del canal existe para contestar «¿está
	// entrando algo?», y hasta hoy esa pregunta sólo se le contestaba con lo que entraba de
	// uno en uno por el webhook — la tanda grande escribía su fila y no la enseñaba nadie
	// hasta que alguien recargara. La fila acaba de escribirse: que se vea aparecer.
	//
	// Va DESPUÉS del apunte y fuera del `if err`: aunque el apunte falle, la tanda entró y
	// `escritosHoy` cambió igual. Un aviso de más cuesta una petición de una pantalla que
	// mira un administrador; uno de menos deja esa pantalla mintiendo.
	avisarCambioEnElCanal(r.Context())
}
