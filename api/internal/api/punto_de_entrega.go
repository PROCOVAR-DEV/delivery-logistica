// El punto de entrega puesto a MANO: `PUT` y `DELETE /api/orders/{id}/punto`.
//
// # EL CASO (issue 19 de Amado, «Geolocalización», Reparto 1.0.39; Jose, 20/10/2026)
//
// El cliente pide entregar en otro sitio y quien factura lo apunta en el ticket. Esa dirección
// no coincide con la geolocalización del cliente, que es la única que manda PEDIDO. El logístico,
// al armar la ruta, le pone a mano el punto de entrega a un pedido (lat, lng y dirección) y ese
// punto MANDA sobre el del cliente: el espejo no lo pisa (`GuardarPedidoDelEspejo`, `punto_manual`).
//
// NADA de webhooks ni de payloads de PEDIDO para esto: Reparto trabaja contra Ventra/facturas, el
// logístico lo pone aquí y su punto gana.
//
// # LO QUE SE RECALCULA, Y POR QUÉ NO SE PUEDE DEJAR PARA DESPUÉS
//
// Al mover el punto se quedaban viejos tres números, y dos son del cobro:
//
//   - `delivery_distance_km`: la distancia del domicilio, medida desde el almacén DEL PEDIDO con la
//     cuenta de la cotización (`cotizar.ElegirOrigenDelPedido`, `kmDesdeElOrigen`).
//   - `segment_km` de la parada: la recta desde el origen de la ruta, con la que se cobra.
//   - `total_distance` de la ruta: el circuito cerrado (`kmDelRecorrido`).
//
// El `stop_order` NO se toca: es lo que decidió el logístico (la ruta puede dejar de ser el
// «óptimo» que decía `optimized`, y es suyo juzgarlo; la marca se conserva tal cual).
//
// Si Accesos no contesta, 502 y NO SE GUARDA NADA: un punto nuevo con el kilometraje viejo es un
// número creíble y equivocado, y es justo lo que esta puerta existe para no dejar.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// Los literales, en una constante cada uno para que la app los diga igual y las pruebas los
// puedan comparar sin copiarlos.
const (
	msgPuntoSeEspera        = "Se espera { lat, lng }"
	msgPuntoImposible       = "lat y lng tienen que ser un punto del planeta"
	msgPuntoYaEntregado     = "La factura ya está entregada: no se le puede cambiar el punto"
	msgPuntoRutaCompletada  = "La ruta ya está completada: no se le puede cambiar el punto a sus paradas"
	msgPuntoNoEsManual      = "La factura no tiene un punto puesto a mano"
	msgPuntoSinPuntoCliente = "La factura no guardó el punto del cliente: no se puede volver a él"
	msgPuntoSinSucursal     = "La factura no tiene sucursal: no se pueden medir los kilómetros hasta el nuevo punto"
	msgPuntoCambio          = "La factura cambió mientras se guardaba el punto: vuelve a intentarlo"
)

// PuntoSalida es la respuesta de las dos puertas: lo que cambió y los números que se recalcularon.
type PuntoSalida struct {
	ID                 uuid.UUID  `json:"id"`
	EndLat             *float64   `json:"endLat"`
	EndLng             *float64   `json:"endLng"`
	EndAddress         *string    `json:"endAddress"`
	PuntoManual        bool       `json:"puntoManual"`
	PuntoManualPor     *string    `json:"puntoManualPor"`
	PuntoManualAt      *time.Time `json:"puntoManualAt"`
	DeliveryDistanceKm *float64   `json:"deliveryDistanceKm"`
	SegmentKm          *float64   `json:"segmentKm"`
}

// cuerpoPunto: `lat` y `lng` son obligatorios y son números; `direccion` es opcional.
type cuerpoPunto struct {
	Lat       *float64 `json:"lat"`
	Lng       *float64 `json:"lng"`
	Direccion *string  `json:"direccion"`
}

// errPuntoCambio es la carrera: entre la lectura y la escritura el pedido se entregó, cambió de
// ruta o de almacén. Es un 409 y no se guarda nada.
var errPuntoCambio = errors.New(msgPuntoCambio)

// ---------------------------------------------------------------------------
// PUT /api/orders/{id}/punto
// ---------------------------------------------------------------------------

func (s *Servidor) ponerPuntoDeEntrega(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	c, ok := leerElPunto(w, r)
	if !ok {
		return
	}
	fila, ok := s.pedidoParaElPunto(w, r, a, id)
	if !ok {
		return
	}
	km, ok := kmDelPedidoAlPunto(w, r, a, fila, *c.Lat, *c.Lng)
	if !ok {
		return
	}

	salida, ok := cambiarElPunto(w, r, a, fila, *c.Lat, *c.Lng,
		func(tx *alcance.Acotado, segmento *float64) (PuntoSalida, error) {
			f, err := tx.PonerPuntoDeEntregaAMano(r.Context(), sqlc.PonerPuntoDeEntregaAManoParams{
				ID: id, Lat: c.Lat, Lng: c.Lng, Direccion: c.Direccion,
				DeliveryDistanceKm: &km, SegmentKm: segmento,
				RutaID: fila.RouteID, AlmacenSalidaCodigo: fila.AlmacenSalidaCodigo,
			})
			if err != nil {
				return PuntoSalida{}, err
			}
			return PuntoSalida{
				ID: f.ID, EndLat: f.EndLat, EndLng: f.EndLng, EndAddress: f.EndAddress,
				PuntoManual: f.PuntoManual, PuntoManualPor: f.PuntoManualPor,
				PuntoManualAt:      hora(f.PuntoManualAt),
				DeliveryDistanceKm: f.DeliveryDistanceKm, SegmentKm: f.SegmentKm,
			}, nil
		})
	if !ok {
		return
	}

	rastroDeQuien(r, "pedido: punto de entrega puesto a mano", "pedido", id)
	// LA SUCURSAL SE LEE DE LA FILA, no del alcance (pedidos.go): un SUPER ADMIN tiene alcance
	// «todas» y el aviso saldría pelado, a las ocho. El tablero también: el pedido cambia de km al
	// almacén y, con ellos, de orden en «Sin colocar». Y la ruta, si va en una.
	sucursal := deLaFilaPg(fila.BranchID)
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)
	if fila.RouteID.Valid {
		avisarCambioDeRutas(r.Context(), sucursal)
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// ---------------------------------------------------------------------------
// DELETE /api/orders/{id}/punto
// ---------------------------------------------------------------------------

func (s *Servidor) devolverPuntoDeEntregaAlCliente(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	fila, ok := s.pedidoParaElPunto(w, r, a, id)
	if !ok {
		return
	}
	if !fila.PuntoManual {
		httpx.Error(w, r, http.StatusConflict, msgPuntoNoEsManual)
		return
	}
	if fila.PuntoClienteLat == nil || fila.PuntoClienteLng == nil {
		httpx.Error(w, r, http.StatusConflict, msgPuntoSinPuntoCliente)
		return
	}
	lat, lng := *fila.PuntoClienteLat, *fila.PuntoClienteLng
	km, ok := kmDelPedidoAlPunto(w, r, a, fila, lat, lng)
	if !ok {
		return
	}

	salida, ok := cambiarElPunto(w, r, a, fila, lat, lng,
		func(tx *alcance.Acotado, segmento *float64) (PuntoSalida, error) {
			f, err := tx.DevolverPuntoDeEntregaAlCliente(r.Context(), sqlc.DevolverPuntoDeEntregaAlClienteParams{
				ID: id, Lat: &lat, Lng: &lng,
				DeliveryDistanceKm: &km, SegmentKm: segmento,
				RutaID: fila.RouteID, AlmacenSalidaCodigo: fila.AlmacenSalidaCodigo,
			})
			if err != nil {
				return PuntoSalida{}, err
			}
			return PuntoSalida{
				ID: f.ID, EndLat: f.EndLat, EndLng: f.EndLng, EndAddress: f.EndAddress,
				PuntoManual: f.PuntoManual, PuntoManualPor: f.PuntoManualPor,
				PuntoManualAt:      hora(f.PuntoManualAt),
				DeliveryDistanceKm: f.DeliveryDistanceKm, SegmentKm: f.SegmentKm,
			}, nil
		})
	if !ok {
		return
	}

	rastroDeQuien(r, "pedido: punto de entrega devuelto al del cliente", "pedido", id)
	sucursal := deLaFilaPg(fila.BranchID)
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)
	if fila.RouteID.Valid {
		avisarCambioDeRutas(r.Context(), sucursal)
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// ---------------------------------------------------------------------------
// Lo que comparten
// ---------------------------------------------------------------------------

// leerElPunto lee y valida el cuerpo. `Se espera { lat, lng }` es todo lo que no es un par de
// números; lo que SON números pero no un sitio —fuera de rango, NaN, o (0,0)— es otro 400, el
// de siempre (`puntoDelPlaneta`). (0,0) es el golfo de Guinea y lo que manda un mapa que no
// terminó de cargar: guardarlo mandaría un camión al océano con sus kilómetros y todo.
func leerElPunto(w http.ResponseWriter, r *http.Request) (cuerpoPunto, bool) {
	var c cuerpoPunto
	defer r.Body.Close()
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&c); err != nil ||
		c.Lat == nil || c.Lng == nil {
		httpx.Error(w, r, http.StatusBadRequest, msgPuntoSeEspera)
		return c, false
	}
	if !puntoDelPlaneta(*c.Lat, *c.Lng) || (*c.Lat == 0 && *c.Lng == 0) {
		httpx.Error(w, r, http.StatusBadRequest, msgPuntoImposible)
		return c, false
	}
	// Una dirección en blanco es «no la cambies», no «bórrala»: dejar un punto sin dirección
	// es dejar a quien reparte sin saber a qué puerta llamar.
	if c.Direccion != nil {
		if d := strings.TrimSpace(*c.Direccion); d == "" {
			c.Direccion = nil
		} else {
			c.Direccion = &d
		}
	}
	return c, true
}

// pedidoParaElPunto lee el pedido (404 si no existe o es de otra sucursal: lo mismo) y contesta
// los dos 409 que se ven antes de gastar una llamada a Accesos. La comprobación que vale es la
// del WHERE de la escritura y la del bloqueo de la ruta; ésta es para que el mensaje llegue sin
// esperar a nadie.
func (s *Servidor) pedidoParaElPunto(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, id uuid.UUID) (sqlc.LeerPedidoParaElPuntoRow, bool) {
	fila, err := a.LeerPedidoParaElPunto(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return fila, false
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return fila, false
	}
	// Las dos columnas, que `MarcarResultadoDeParada` escribe y limpia juntas (como `mensajeYaEntregados`).
	if fila.DeliveredAt.Valid || (fila.Resultado != nil && *fila.Resultado == sqlc.StopResultEntregado) {
		httpx.Error(w, r, http.StatusConflict, msgPuntoYaEntregado)
		return fila, false
	}
	if fila.RouteID.Valid {
		ruta, err := a.ObtenerRuta(r.Context(), uuid.UUID(fila.RouteID.Bytes))
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			httpx.ErrorInterno(w, r, err)
			return fila, false
		}
		if err == nil && ruta.Status == sqlc.RouteStatusCompleted {
			httpx.Error(w, r, http.StatusConflict, msgPuntoRutaCompletada)
			return fila, false
		}
	}
	return fila, true
}

// kmDelPedidoAlPunto mide del almacén DEL PEDIDO al punto, con la cuenta de la cotización.
//
// ACCESOS CAÍDO ES 502 Y NO SE SIGUE. La cotización trata el fallo como «no hay almacenes» y mide
// desde el punto de la sucursal; aquí eso sería escribir un kilometraje que no es el del almacén
// del pedido junto a un punto nuevo, y nadie lo vería: es el número del cobro.
func kmDelPedidoAlPunto(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, fila sqlc.LeerPedidoParaElPuntoRow, lat, lng float64) (float64, bool) {
	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return 0, false
	}
	var suc *sqlc.ListarSucursalesRow
	for i := range sucursales {
		if fila.BranchID.Valid && sucursales[i].ID == uuid.UUID(fila.BranchID.Bytes) {
			suc = &sucursales[i]
			break
		}
	}
	if suc == nil {
		httpx.Error(w, r, http.StatusConflict, msgPuntoSinSucursal)
		return 0, false
	}

	var almacenes []cotizar.Almacen
	if suc.ExternalID != nil && strings.TrimSpace(*suc.ExternalID) != "" {
		almacenes, err = almacenesDeAccesos(r.Context(), strings.TrimSpace(*suc.ExternalID))
		if err != nil {
			httpx.Registro(r).Warn("Accesos no dio los almacenes: el punto de entrega no se guarda",
				"sucursal", *suc.ExternalID, "err", err)
			httpx.Error(w, r, http.StatusBadGateway,
				fmt.Sprintf("No se pudieron traer los almacenes de Accesos: %s", err))
			return 0, false
		}
	}
	codigo := ""
	if fila.AlmacenSalidaCodigo != nil {
		codigo = *fila.AlmacenSalidaCodigo
	}
	origen := cotizar.ElegirOrigenDelPedido(almacenes, codigo)
	// Sin almacén con punto el lote mide desde el punto de la sucursal; si tampoco tiene punto de
	// partida, ese punto es (0,0) y los kilómetros saldrían del golfo de Guinea.
	if origen.Almacen == nil && !suc.OriginConfigured {
		httpx.Error(w, r, http.StatusConflict, fmt.Sprintf(msgSinAlmacenF, suc.Name))
		return 0, false
	}
	return kmDesdeElOrigen(origen, suc.Lat, suc.Lng, lat, lng), true
}

// cambiarElPunto es la transacción de las dos puertas: bloquea la ruta (si va en una), deja que
// `escribir` ponga el punto y recalcula el `segment_km` y el `total_distance`. Todo o nada.
//
// El `segment_km` se calcula ANTES de escribir porque va en la misma sentencia que el punto, con
// el origen de la ruta ya bloqueada. El total, DESPUÉS, sobre las paradas ya con el punto nuevo.
// Ha contestado ya si devuelve false.
func cambiarElPunto(
	w http.ResponseWriter, r *http.Request, a *alcance.Acotado,
	fila sqlc.LeerPedidoParaElPuntoRow, lat, lng float64,
	escribir func(tx *alcance.Acotado, segmento *float64) (PuntoSalida, error),
) (PuntoSalida, bool) {
	var salida PuntoSalida
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var segmento *float64
		var ruta sqlc.ObtenerRutaRow
		if fila.RouteID.Valid {
			var err error
			ruta, err = rutaEditableEnTx(r.Context(), tx, uuid.UUID(fila.RouteID.Bytes))
			if errors.Is(err, pgx.ErrNoRows) {
				return errPuntoCambio // la ruta se borró entre la lectura y el bloqueo
			}
			if err != nil {
				return err
			}
			if ruta.OriginLat == nil || ruta.OriginLng == nil {
				return rechazoDelOrden{http.StatusConflict, msgRutaSinOrigen}
			}
			km := kmHaversine(*ruta.OriginLat, *ruta.OriginLng, lat, lng)
			segmento = &km
		}
		var err error
		salida, err = escribir(tx, segmento)
		if errors.Is(err, pgx.ErrNoRows) {
			return errPuntoCambio
		}
		if err != nil {
			return err
		}
		if !fila.RouteID.Valid {
			return nil
		}
		return recalcularElTotalDeLaRuta(r.Context(), tx, ruta)
	})
	var rechazo rechazoDelOrden
	switch {
	case errors.Is(err, errRutaCompletada):
		httpx.Error(w, r, http.StatusConflict, msgPuntoRutaCompletada)
	case errors.Is(err, errPuntoCambio):
		httpx.Error(w, r, http.StatusConflict, msgPuntoCambio)
	case errors.As(err, &rechazo):
		httpx.Error(w, r, rechazo.codigo, rechazo.motivo)
	case err != nil:
		httpx.ErrorInterno(w, r, err)
	default:
		return salida, true
	}
	return PuntoSalida{}, false
}

// recalcularElTotalDeLaRuta vuelve a medir el circuito de la ruta con las paradas como están
// ahora y en el orden que tienen. La firma `optimized` se conserva: mover un punto no cambia
// quién ordenó las paradas.
func recalcularElTotalDeLaRuta(ctx context.Context, tx *alcance.Acotado, ruta sqlc.ObtenerRutaRow) error {
	filas, err := tx.ParadasDeRutas(ctx, []uuid.UUID{ruta.ID})
	if err != nil {
		return err
	}
	conPunto, _ := paradasConYSinPunto(filas)
	total, _ := kmDelRecorrido(*ruta.OriginLat, *ruta.OriginLng, conPunto)
	_, err = tx.FijarTotalesDeRuta(ctx, sqlc.FijarTotalesDeRutaParams{
		TotalDistance: total, Optimizado: &ruta.Optimized, ID: ruta.ID,
	})
	return err
}
