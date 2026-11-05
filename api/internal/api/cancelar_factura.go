// POST /api/orders/{id}/cancelar: cancelar una factura DEVUELTA (issue 25 de Amado, «Facturas devueltas»).
//
// # El caso
//
// Una factura que volvió en el camión (`resultado = 'devuelto'`) acaba de dos formas: en otra ruta otro día, o
// CANCELADA porque el cliente se arrepintió. Jose, 05/11/2026: «la cancelada es el cancelado ese». No hay estado,
// columna ni migración nuevos: cancelar es dejar `resultado = 'cancelado'` (el valor que ya existía), con su hora
// (`resultado_at`) y su nota (`resultado_nota`). Lo que cambia es la regla: un `cancelado` sin ruta ya NO vuelve a
// disponibles, «Sin colocar», tablero, armado, panel ni `EngancharPedidoARuta`; sólo el `devuelto` se reasigna.
//
// # Contrato
//
//   - cuerpo opcional `{"nota": "..."}`, máximo 500 caracteres;
//   - sólo `resultado = 'devuelto'`, sin ruta ni entrega: si no, 409 con el motivo en español;
//   - 404 si no existe O no es de tu sucursal (el alcance falla cerrado: es lo mismo desde fuera);
//   - 200 con la ficha de la factura (la misma forma que `GET /api/orders/{id}`);
//   - REINTENTO: repetir la petición sobre una factura YA cancelada es un 409 «ya está cancelada» (`msgYaCancelada`).
//     La cola del aparato lo trata como ya hecho: el estado que quería es el que hay;
//   - el distribuidor no entra (lista blanca de `auth.PermitidoAlDistribuidor`: nace cerrada);
//   - quién la canceló NO se guarda en la fila (no hay columna): queda en el registro del servidor (`actor`).
//
// El aviso `cancelado` a PEDIDO (por factura, con la nota) se apunta en el buzón DENTRO de la misma transacción.
package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

const (
	// TopeDeLaNotaDeCancelacion: caracteres de la nota.
	TopeDeLaNotaDeCancelacion = 500

	msgYaCancelada = "La factura ya está cancelada"
	// CodigoYaCancelada marca el 409 del reintento: el sincronizador (`sync/internal/reparto`) lo lee y da el apunte
	// por hecho. Si lo cambias, cambia el mismo literal allí.
	CodigoYaCancelada = "ya_cancelada"

	msgCancelarVaEnRuta   = "La factura va en una ruta: sólo se puede cancelar una factura devuelta que ya no esté en ninguna"
	msgCancelarNoDevuelta = "La factura no está devuelta: sólo se puede cancelar una factura que volvió devuelta en el camión"
	msgCancelarMiembro    = "La factura va dentro de un conduce: cancela el conduce entero desde su factura principal"
	msgCancelarCambio     = "La factura cambió mientras se cancelaba: vuelve a intentarlo"
	msgNotaLarga          = "La nota no puede pasar de 500 caracteres"
	msgCancelarCuerpo     = "Se espera { nota? } con la nota como texto"
)

type cuerpoCancelar struct {
	Nota *string `json:"nota"`
}

func (s *Servidor) cancelarFacturaDevuelta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	nota, ok := leerLaNotaDeCancelar(w, r)
	if !ok {
		return
	}

	// Se lee ANTES sólo para dar el motivo: la guarda que vale es la del WHERE de la escritura.
	p, err := a.ObtenerPedido(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if motivo := porQueNoSePuedeCancelar(p); motivo != "" {
		if motivo == msgYaCancelada {
			httpx.ErrorConCodigo(w, r, http.StatusConflict, motivo, CodigoYaCancelada)
			return
		}
		httpx.Error(w, r, http.StatusConflict, motivo)
		return
	}

	cuando := time.Now().UTC()
	var avisos []AvisoDeParada
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		ids, hechos, err := tx.CancelarFacturaDevuelta(r.Context(), id, nota, cuando)
		if err != nil {
			return err
		}
		if len(ids) == 0 {
			return errCancelarCambio
		}
		avisos = hechos
		return nil
	})
	switch {
	case errors.Is(err, errCancelarCambio):
		httpx.Error(w, r, http.StatusConflict, msgCancelarCambio)
		return
	case err != nil:
		httpx.ErrorInterno(w, r, err)
		return
	}

	rastroDeQuien(r, "factura devuelta cancelada", "pedido", id, "avisos", len(avisos), "conNota", nota != nil)
	// El aviso ya está en el buzón; esto es el intento en el acto (síncrono, como el cierre) y un fallo se queda
	// pendiente para el trabajador, no se pierde.
	if len(avisos) > 0 {
		if parte := s.aPedido(r.Context(), avisos); !parte.Ok {
			httpx.Registro(r).Error("la cancelación se guardó pero PEDIDO no se enteró; queda en el buzón",
				"pedido", id, "err", parte.Error)
		}
	}
	sucursal := deLaFilaPg(p.BranchID)
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)

	salida, ok := s.detalleDePedido(w, r, a, id)
	if !ok {
		return
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

var errCancelarCambio = errors.New(msgCancelarCambio)

// porQueNoSePuedeCancelar dice por qué NO, o "" si puede. El orden importa: «ya está cancelada» antes que lo demás,
// porque es el reintento de la cola del aparato y tiene que poder reconocerse por su texto.
func porQueNoSePuedeCancelar(p sqlc.ObtenerPedidoRow) string {
	switch {
	case p.Resultado != nil && *p.Resultado == sqlc.StopResultCancelado:
		return msgYaCancelada
	case p.RouteID.Valid:
		return msgCancelarVaEnRuta
	case p.Resultado == nil || *p.Resultado != sqlc.StopResultDevuelto || p.DeliveredAt.Valid:
		return msgCancelarNoDevuelta
	case p.ConducePrincipalID.Valid:
		return msgCancelarMiembro
	}
	return ""
}

// leerLaNotaDeCancelar: el cuerpo es opcional (vacío = sin nota). La nota se recorta; en blanco es «sin nota».
func leerLaNotaDeCancelar(w http.ResponseWriter, r *http.Request) (*string, bool) {
	var c cuerpoCancelar
	defer r.Body.Close()
	err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&c)
	if err != nil && !errors.Is(err, io.EOF) {
		httpx.Error(w, r, http.StatusBadRequest, msgCancelarCuerpo)
		return nil, false
	}
	if c.Nota == nil {
		return nil, true
	}
	n := strings.TrimSpace(*c.Nota)
	if utf8.RuneCountInString(n) > TopeDeLaNotaDeCancelacion {
		httpx.Error(w, r, http.StatusBadRequest, msgNotaLarga)
		return nil, false
	}
	if n == "" {
		return nil, true
	}
	return &n, true
}
