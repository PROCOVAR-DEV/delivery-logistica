package api

import (
	"context"
	"strings"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// EL TRABAJADOR QUE DRENA EL BUZÓN hacia PEDIDO.
//
// El cierre de ruta intenta mandar el aviso en el acto —el vendedor tiene que verlo ya—,
// pero si PEDIDO no contesta el aviso se queda `pendiente` en `avisos_a_pedido`. Esto es
// quien vuelve a por él. Sin este trabajador el buzón sería una lista de cosas perdidas
// mejor apuntada, que no es el arreglo.
//
// LO QUE NO HACE, y es la mitad del diseño:
//
//   - **No reintenta lo rechazado.** Un rechazo es PEDIDO diciendo que no con conocimiento
//     de causa —ese pedido no existe allá—: repetirlo da lo mismo y sólo gasta la conexión.
//     Se queda a la vista hasta que una persona decida (`CLAUDE.md` §4).
//   - **No borra nada.** Un `DELETE` al fallar deja el número cuadrado y la verdad perdida.
//
// Y APUNTA CADA TANDA en `envios_del_webhook`, que es otra pregunta que la de cada aviso:
// un aviso sin enviar puede ser «PEDIDO está caído» —la llamada no llegó— o «PEDIDO lo
// rechazó» —llegó perfectamente y dijo que no—. Desde fuera las dos se ven igual: «hay
// avisos sin enviar». Con la tanda apuntada, no.

// CadaCuantoSeDrena: cada cuánto vuelve el trabajador.
//
// Un minuto no es un número redondo elegido al azar: es lo que tarda alguien en mirar
// PEDIDO después de cerrar una ruta. Más corto castiga la conexión de allá sin que nadie
// lo note; más largo y el vendedor llama a la oficina antes de que llegue el aviso.
const CadaCuantoSeDrena = time.Minute

// DrenadorDelBuzon es la tarea de fondo. Una por proceso.
//
// Se monta igual que el refresco de tasas y por lo mismo: una gorutina que muere con el
// contexto, y un método suelto —[DrenarElBuzon]— para poder probarlo sin esperar a un tic.
type DrenadorDelBuzon struct {
	srv   *Servidor
	abrir func(ctx context.Context) (*alcance.Acotado, error)
	cada  time.Duration

	// vigia es quien avisa POR NOTIFY cuando el canal falla de verdad (ver
	// `vigia_del_canal.go`). Va aquí y no en su propia gorutina a propósito: ya hay un
	// trabajador que da una vuelta cada minuto con el alcance abierto, y montar un segundo
	// temporizador para mirar lo mismo sería otra conexión, otro `Resolver` y dos relojes
	// que se desincronizan.
	vigia *VigiaDelCanal
}

// NuevoDrenadorDelBuzon lo arma. `cada <= 0` usa [CadaCuantoSeDrena].
func NuevoDrenadorDelBuzon(
	srv *Servidor,
	abrir func(ctx context.Context) (*alcance.Acotado, error),
	cada time.Duration,
) *DrenadorDelBuzon {
	if cada <= 0 {
		cada = CadaCuantoSeDrena
	}
	return &DrenadorDelBuzon{srv: srv, abrir: abrir, cada: cada, vigia: NuevoVigiaDelCanal(srv, nil)}
}

// Correr da una vuelta AL ARRANCAR y luego una cada `cada`.
//
// La primera va al arrancar a propósito: si el proceso se reinició **mientras** había
// avisos sin mandar —que es justo uno de los casos que el buzón viene a tapar—, esperar al
// primer plazo son otros sesenta segundos de un pedido entregado que en PEDIDO sigue «en
// proceso».
func (d *DrenadorDelBuzon) Correr(ctx context.Context) {
	d.UnaVuelta(ctx)

	reloj := time.NewTicker(d.cada)
	defer reloj.Stop()
	for {
		select {
		case <-ctx.Done():
			d.srv.reg.Info("drenaje del buzón hacia PEDIDO parado")
			return
		case <-reloj.C:
			d.UnaVuelta(ctx)
		}
	}
}

// UnaVuelta abre el alcance y drena. Separada para poder probarla sin esperar a un tic.
func (d *DrenadorDelBuzon) UnaVuelta(ctx context.Context) {
	a, err := d.abrir(ctx)
	if err != nil {
		d.srv.reg.Error("no se pudo abrir el alcance para drenar el buzón", "err", err)
		return
	}
	enviados, quedan := d.srv.DrenarElBuzon(ctx, a)
	if enviados > 0 || quedan > 0 {
		d.srv.reg.Info("buzón hacia PEDIDO drenado", "enviados", enviados, "quedan", quedan)
	}

	// Y SE MIRA CÓMO VA EL CANAL, DESPUÉS DE DRENAR Y NO ANTES.
	//
	// El orden es la mitad de la guarda: drenar puede haber arreglado justo el atasco por el
	// que se iba a avisar, y un correo que dice «atascado» sobre un canal que acaba de
	// vaciarse es un aviso falso — y los avisos falsos son los que enseñan a no leer los
	// verdaderos. El vigía no devuelve error a propósito: si notify está caído, lo que no
	// puede pasar es que se caiga con él el drenaje, que es lo que de verdad importa.
	d.vigia.Mirar(ctx, a)
}

// DrenarElBuzon manda lo que quedó pendiente. Devuelve cuántos se mandaron y cuántos
// quedaron.
//
// No devuelve error a propósito: lo llama un temporizador, no una persona, y lo único
// razonable que puede hacer con un fallo es volver a intentarlo dentro de un minuto. Lo
// que sí hace es dejarlo escrito donde se puede mirar.
func (s *Servidor) DrenarElBuzon(ctx context.Context, a *alcance.Acotado) (enviados, pendientes int) {
	pend, err := a.AvisosAPedidoPendientes(ctx, TopeDelDrenaje)
	if err != nil {
		s.reg.Error("no se pudo leer el buzón hacia PEDIDO", "err", err)
		return 0, 0
	}
	if len(pend) == 0 {
		return 0, 0
	}

	avisos := make([]AvisoDeParada, 0, len(pend))
	for _, p := range pend {
		av := AvisoDeParada{PedidoID: p.PedidoID, Estado: p.Estado}
		if p.Factura != nil {
			// Aviso por factura: lo que se manda es lo que se guardó, y `pedido_id` (la clave de
			// lectura de la tabla) NO va, o PEDIDO buscaría un pedido que no existe.
			av = AvisoDeParada{
				Folio: derefONada(p.Folio), Sucursal: derefONada(p.Sucursal),
				Factura: *p.Factura, PuntoDeVenta: derefONada(p.PuntoDeVenta), Estado: p.Estado,
			}
		}
		if p.Nota != nil {
			av.Nota = *p.Nota
		}
		if p.OcurrioAt.Valid {
			av.At = p.OcurrioAt.Time
		}
		avisos = append(avisos, av)
	}

	arranque := time.Now()
	parte := s.aPedido(ctx, avisos)
	tardo := int32(time.Since(arranque).Milliseconds())

	// LA TANDA, apuntada pase lo que pase. Es lo que deja ver si el webhook respira.
	motivo := parte.Error
	var http32 *int32
	if parte.HTTP > 0 {
		c := int32(parte.HTTP)
		http32 = &c
	}
	if err := a.ApuntarEnvioDelWebhook(ctx, sqlc.ApuntarEnvioDelWebhookParams{
		Destino:    "pedido",
		Mandados:   int32(len(avisos)),
		Aceptados:  int32(parte.Aplicados),
		Rechazados: int32(len(avisos) - parte.Aplicados),
		Motivo:     textoONil(motivo),
		// EL CÓDIGO HTTP, que hasta el 26/09/2026 se quedaba NULL SIEMPRE. La 00011 creó
		// esa columna diciendo «un 200 con cero aceptados y un 502 no son lo mismo, y
		// guardar sólo “falló” los confunde» — y estaban confundidos, porque nadie la
		// rellenaba. `nil` cuando no se llegó a hablar, que tampoco es lo mismo que un 0.
		Http:       http32,
		DuracionMs: tardo,
	}); err != nil {
		s.reg.Error("no se pudo apuntar el envío del webhook", "err", err)
	}

	// NO SE PUDO NI PREGUNTAR: todos siguen pendientes, y eso no es un rechazo.
	//
	// `parte.Rechazo` es lo que separa las dos cosas, y antes no existía: `Ok` salía de
	// `Error == ""`, así que **un rechazo de PEDIDO entraba por aquí**. Consecuencia, viva
	// hasta hoy: el aviso se quedaba `pendiente` y se reenviaba cada minuto para siempre,
	// `AvisoAPedidoRechazado` era código muerto, y como el buzón se drena por orden de
	// llegada esa fila iba en TODAS las tandas y **paraba el canal entero**.
	if !parte.Ok && !parte.Rechazo {
		for _, p := range pend {
			if err := a.AvisoAPedidoSeReintenta(ctx, p.ID, motivo); err != nil {
				s.reg.Error("no se pudo anotar el reintento", "aviso", p.ID, "err", err)
			}
		}
		s.reg.Warn("PEDIDO no contestó: el buzón se queda lleno y se reintenta",
			"pendientes", len(pend), "motivo", motivo)
		// SE AVISA TAMBIÉN DE ESTO, y es la mitad que más importa de las dos: la pantalla
		// del canal existe para contestar «¿está saliendo algo?», y un PEDIDO caído es
		// justo la respuesta que hay que ver al instante y no en la vuelta siguiente.
		avisarCambioEnElCanal(ctx)
		return 0, len(pend)
	}

	// PEDIDO CONTESTÓ. Lo que aplicó va a `enviado`; lo que no, a `rechazado` con el
	// motivo que él mismo dio. **Un rechazo NO se reintenta**: repetirlo da exactamente lo
	// mismo y se queda a la vista hasta que una persona decida (`CLAUDE.md` §4).
	//
	// Se reparte por ORDEN y no por id. **Su respuesta SÍ trae los ids** —se comprobó el
	// 26/09/2026 contra la respuesta de verdad: `aplicados: [{pedidoId, folio, estado}]`—
	// así que esto se puede y se debe atar por id, y entonces desaparece el riesgo de
	// marcar enviado uno que no lo fue. **No está hecho**, y mientras no lo esté hay dos
	// cosas que pueden salir mal y conviene que estén dichas:
	//
	//   - `aplicados` es un subconjunto COMPACTADO: cada rechazo hace `continue` y no deja
	//     hueco, así que `aplicados[i]` deja de corresponder con `tanda[i]` en cuanto hay
	//     un rechazo delante. No es el caso raro: es cualquier tanda mixta.
	//   - `sinRepetidos` encoge la tanda DENTRO del canal, y aquí se recorre `pend` entera,
	//     así que los repetidos del final se marcan rechazados con un motivo que es mentira.
	//     Y un rechazado no se reintenta nunca.
	for i, p := range pend {
		if i < parte.Aplicados {
			if err := a.AvisoAPedidoEnviado(ctx, p.ID); err != nil {
				s.reg.Error("no se pudo marcar el aviso como enviado", "aviso", p.ID, "err", err)
				continue
			}
			enviados++
			continue
		}
		porQue := motivo
		if strings.TrimSpace(porQue) == "" {
			porQue = "PEDIDO no lo aplicó y no dijo por qué"
		}
		if err := a.AvisoAPedidoRechazado(ctx, p.ID, porQue); err != nil {
			s.reg.Error("no se pudo marcar el aviso como rechazado", "aviso", p.ID, "err", err)
		}
	}
	// LA TANDA SALIÓ: que se repinte la pantalla del canal. Ver `CambioCanal`.
	avisarCambioEnElCanal(ctx)
	return enviados, len(pend) - enviados
}

// textoONil: una cadena vacía se guarda como NULL. «» y «no hubo motivo» se leen igual en
// una pantalla, pero en la columna uno es un dato y el otro es su ausencia.
func textoONil(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}
