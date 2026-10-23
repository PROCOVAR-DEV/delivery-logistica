// EL CANAL DE SALIDA HACIA PEDIDO: contarle en qué punto del reparto va cada entrega.
//
// DESDE EL 22/10/2026 LA QUE MANDA ES LA FACTURA, no el pedido. Las entregas nacen de facturas de
// Ventra y su `external_id` no lo conoce PEDIDO, así que el aviso de una entrega de factura lleva
// `folio` (el pedido, para localizarlo) + `sucursal` + `factura` + `puntoDeVenta`, UNO por factura
// (un pedido con dos facturas manda dos). Una factura sin folio no tiene a quién avisar y no sale.
// El aviso de un pedido de PEDIDO sigue llevando `pedidoId`. Quién decide la forma es
// `alcance.AvisoDeLaEntrega`; este fichero sólo lo manda. Orden de despliegue: PEDIDO primero.
//
// POR QUÉ EXISTE: en PEDIDO el vendedor ve su pedido y nada más —no sabe si salió, si
// llegó o si volvió al almacén—. Lo sabe el reparto, porque es donde pasan esas cosas: se
// arma la ruta, sale el camión, se marca cada parada. A la APK de Entrega no se le puede
// avisar de nada (trabaja sin conexión), así que el sitio donde esto tiene que quedar
// escrito es PEDIDO, que siempre está en pie y del que la APK sincroniza cuando puede.
//
// Es la traducción del `avisarEstadoAPedido.ts` de delivery (reglas-negocio §13), con las
// tres cosas que aquél resuelve y que NO se pueden perder:
//
//  1. VA EN LOTE Y ES IDEMPOTENTE. El aviso dice en qué punto ESTÁ el pedido, no qué le
//     acaba de pasar: es una afirmación de estado, no un apunte que se suma. Por eso
//     repetirlo no cuenta nada dos veces, y por eso el reintento de un aparato que perdió
//     la señal a mitad de subida es barato y seguro.
//
//  2. MANDA LA HORA REAL DEL SUCESO (`at`), NO LA DE LA LLAMADA. Con el trabajo sin
//     conexión, un cierre marcado a las 16:04 puede subir a las 19:30: en PEDIDO tiene
//     que decir 16:04, porque el vendedor necesita saber cuándo recibió su cliente, no
//     cuándo pilló señal el teléfono. Ver `horaDelSuceso` en `rutas.go`.
//
//  3. ES «LO MEJOR QUE SE PUEDA». Si PEDIDO no contesta, aquí no se rompe nada: la ruta
//     sigue su curso y lo que no se pudo contar se cuenta la próxima vez que ese pedido
//     se mueva (cada aviso lleva el estado completo, ver 1). PERO NUNCA EN SILENCIO: todo
//     fallo queda en el registro Y en el parte que se le devuelve a quien llamó.
package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"procovar/reparto-api/internal/config"
)

// CanalAPedido es la firma del canal. Es un tipo y no una llamada directa para que la
// prueba lo sustituya sin levantar nada, y para que el día que PEDIDO cambie de puerta se
// toque un solo sitio.
type CanalAPedido func(ctx context.Context, avisos []AvisoDeParada) ParteAPedido

// RutaEstadoEnPedido: la puerta de PEDIDO. La misma que usa delivery hoy en producción.
const RutaEstadoEnPedido = "/integration/orders/status"

// TandaAPedido: de cuántos en cuántos se manda.
//
// PEDIDO acepta hasta 500, pero cada uno escribe y publica un aviso en vivo por pedido.
// Con tandas cortas, lo que se pierde si algo se cae es UNA tanda y no el lote entero.
const TandaAPedido = 200

// PlazoAPedido: ninguna petición sin plazo. Una llamada colgada contra la conexión de allá
// se queda esperando para siempre y se lleva con ella la goroutine que la disparó; en el
// cierre, que es síncrono, se llevaría además la petición de quien está cerrando la ruta.
const PlazoAPedido = 20 * time.Second

// ClienteDePedido es el http.Client del canal. Variable de paquete para que las pruebas
// puedan apuntarlo a un servidor de mentira.
var ClienteDePedido = &http.Client{Timeout: PlazoAPedido}

// Los motivos de «no se envió». Son texto para una persona: salen en la respuesta de la
// API y en el registro, y quien los lee tiene que saber qué variable poner.
const (
	msgSinCanalAPedido = "no hay canal a PEDIDO configurado en esta API: el aviso no se envió"
	msgSinClaveAPedido = "falta SERVICE_API_KEY: el aviso a PEDIDO no se envió"
)

// nuevoCanalAPedido devuelve el canal ya configurado, o uno que NO MIENTE cuando no hay a
// dónde mandar.
//
// Lo de no mentir es lo importante: mientras faltó la configuración, lo cómodo habría sido
// devolver `ok: true` y no molestar a nadie. Un aviso que nadie recibe y que además se
// declara enviado es peor que no avisar, porque nadie lo busca. Es exactamente lo que ya
// pasó con el canal de Entrega, que existía con clave y secreto y sin URL: no salía nada y
// no se veía en ningún registro.
func nuevoCanalAPedido(cfg *config.Config, reg *slog.Logger) CanalAPedido {
	switch {
	case cfg.PedidoAPIURL == "":
		return canalMudo(reg, msgSinCanalAPedido)
	case cfg.ServiceAPIKey == "":
		return canalMudo(reg, msgSinClaveAPedido)
	}

	destino := cfg.PedidoAPIURL + RutaEstadoEnPedido
	clave := cfg.ServiceAPIKey

	return func(ctx context.Context, avisos []AvisoDeParada) ParteAPedido {
		// Sin avisos no se llama a nada. Armar una ruta de pedidos tecleados a mano es un
		// caso normal y no tiene a quién avisar.
		if len(avisos) == 0 {
			return ParteAPedido{Ok: true}
		}
		avisos = sinRepetidos(avisos)

		parte := ParteAPedido{Enviados: len(avisos)}
		for i := 0; i < len(avisos); i += TandaAPedido {
			tanda := avisos[i:min(i+TandaAPedido, len(avisos))]

			aplicados, motivo, rechazo, codigo := mandarTanda(ctx, destino, clave, tanda)
			parte.Aplicados += aplicados
			// EL HTTP SE FIJA CON EL MOTIVO, EN EL MISMO SITIO. Si uno se quedara con el
			// primero y el otro con el último, la fila saldría con el motivo de una tanda
			// y el código de otra: se lee bien y es mentira.
			if parte.HTTP == 0 {
				parte.HTTP = codigo
			}
			if rechazo {
				parte.Rechazo = true
			}
			if motivo != "" {
				// SE GUARDA EL PRIMER MOTIVO Y SE SIGUE, no se aborta: las tandas que
				// vienen detrás son pedidos distintos y no tienen la culpa de que ésta
				// fallara. `aplicados` cuenta lo que sí entró.
				if parte.Error == "" {
					parte.Error = motivo
				}
				// Y QUEDA DICHO AQUÍ, tanda por tanda, aunque el parte sólo se lleve el
				// primer motivo. Sin esto, un lote de mil pedidos con ocho tandas rotas
				// por ocho razones distintas deja en el registro una sola.
				reg.Warn("PEDIDO no tomó una tanda de estados",
					"destino", destino, "avisos", len(tanda), "err", motivo)
			}
		}
		parte.Ok = parte.Error == ""
		return parte
	}
}

// canalMudo es el canal de cuando no hay a dónde mandar: no llama a nadie, lo dice en el
// parte y lo deja en el registro.
func canalMudo(reg *slog.Logger, motivo string) CanalAPedido {
	return func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		if len(avisos) > 0 {
			reg.Error("no se pudo avisar a PEDIDO", "avisos", len(avisos), "err", motivo)
		}
		return ParteAPedido{Ok: false, Enviados: len(avisos), Error: motivo}
	}
}

// mandarTanda hace UNA llamada. Devuelve cuántos aplicó PEDIDO y, si algo salió mal, el
// motivo en texto. No devuelve `error` a propósito: aquí ningún fallo se propaga hacia
// arriba, se cuenta.
// mandarTanda devuelve cuántos aplicó PEDIDO, el motivo, **si fue un rechazo suyo** y el
// código HTTP.
//
// El tercer valor es el que separa «PEDIDO dijo que no» de «no se pudo ni preguntar». Ver
// `ParteAPedido.Rechazo`: sin él, un rechazo se reintentaba cada minuto para siempre y
// paraba el buzón entero.
func mandarTanda(ctx context.Context, destino, clave string, tanda []AvisoDeParada) (int, string, bool, int) {
	cuerpo, err := json.Marshal(map[string]any{"pedidos": tanda})
	if err != nil {
		return 0, fmt.Sprintf("no se pudo armar el aviso: %s", err), false, 0
	}

	// Plazo PROPIO por tanda, además del que trae el cliente: el contexto que llega puede
	// ser el de una petición que ya va por su último segundo, y entonces la tanda saldría
	// muerta sin que el motivo diga por qué.
	ctx, cancelar := context.WithTimeout(ctx, PlazoAPedido)
	defer cancelar()

	pet, err := http.NewRequestWithContext(ctx, http.MethodPost, destino, bytes.NewReader(cuerpo))
	if err != nil {
		return 0, err.Error(), false, 0
	}
	pet.Header.Set("Content-Type", "application/json")
	pet.Header.Set("Accept", "application/json")
	// La misma clave de servicio con la que PEDIDO entra aquí. No se abre una segunda
	// puerta para el sentido contrario.
	pet.Header.Set("x-api-key", clave)

	res, err := ClienteDePedido.Do(pet)
	if err != nil {
		// NO SE LLEGÓ A HABLAR: no es rechazo, y el HTTP es 0 porque no hubo ninguno.
		return 0, err.Error(), false, 0
	}
	defer res.Body.Close()

	// Se lee y se cierra SIEMPRE, también cuando el código es de error: un cuerpo sin
	// vaciar no devuelve la conexión al pool, y con un PEDIDO que contesta 500 en bucle
	// eso son mil conexiones abiertas en una tarde.
	crudo, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		// UN CÓDIGO DE ERROR NO ES UN RECHAZO. Un 502 de un proxy o un 500 mientras PEDIDO
		// arranca se arreglan solos esperando; un rechazo suyo no. Se reintenta.
		return 0, fmt.Sprintf("PEDIDO contestó %d", res.StatusCode), false, res.StatusCode
	}

	var r struct {
		Aplicados  []json.RawMessage `json:"aplicados"`
		Rechazados []struct {
			Motivo string `json:"motivo"`
		} `json:"rechazados"`
	}
	if err := json.Unmarshal(crudo, &r); err != nil {
		// 200 con un cuerpo que no se entiende NO se cuenta como aplicado. Contarlo sería
		// dar por contado lo que no consta en ningún sitio.
		// 200 CON UN CUERPO QUE NO SE ENTIENDE tampoco es un rechazo: no sabemos qué dijo.
		// Y si no es suyo —Traefik, un proxy— reintentar es lo correcto.
		return 0, fmt.Sprintf("PEDIDO contestó algo que no se entiende: %s", err), false, res.StatusCode
	}
	if len(r.Rechazados) > 0 {
		// El PRIMER motivo, no todos: es lo que cabe en una pantalla y lo que hace falta
		// para saber qué mirar. Los demás están en el registro de PEDIDO.
		// AQUÍ SÍ: contestó, miró los pedidos uno a uno y dijo que no. Repetirlo da lo mismo.
		return len(r.Aplicados), r.Rechazados[0].Motivo, true, res.StatusCode
	}
	return len(r.Aplicados), "", false, res.StatusCode
}

// sinRepetidos quita los avisos idénticos de un mismo lote.
//
// No es cosmética: el lote se arma recorriendo las paradas, y una corrección sobre la
// misma parada puede meter dos veces el mismo hecho. Mandarlo dos veces no rompe nada
// —el aviso es una afirmación de estado, ver la cabecera— pero cada uno le cuesta a PEDIDO
// una escritura y un aviso en vivo por pedido, que es lo caro de esta llamada.
//
// SE QUITA EL IDÉNTICO, no «el mismo pedido»: dos avisos del mismo pedido con estados u
// horas distintas son dos hechos distintos y los dos tienen que llegar, en su orden.
func sinRepetidos(avisos []AvisoDeParada) []AvisoDeParada {
	vistos := make(map[AvisoDeParada]struct{}, len(avisos))
	salida := make([]AvisoDeParada, 0, len(avisos))
	for _, a := range avisos {
		if _, repetido := vistos[a]; repetido {
			continue
		}
		vistos[a] = struct{}{}
		salida = append(salida, a)
	}
	return salida
}
