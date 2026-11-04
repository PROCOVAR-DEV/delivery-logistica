package api

// EL GPS DEL DISTRIBUIDOR (04/11/2026, Jose: «poder checkear en cada ruta su gps del móvil para tenerlo localizado y saber qué hizo y qué
// movimientos hizo en toda la ruta… eso no lo pueden ver ellos»).
//
//	POST /api/track                    SOLO un distribuidor: su ubicación, por lotes de hasta 200, idempotente por `id`.
//	GET  /api/routes/{id}/track        la oficina: el recorrido de UNA ruta con la hora real de cada parada y el cobro.
//	GET  /api/vehicles/{id}/historial  la oficina: la vida de un vehículo (sus rutas, de la más reciente a la más antigua).
//	GET  /api/tracking/ahora           la oficina: dónde está cada distribuidor que tiene una ruta en curso.
//
// Los tres GET NO están en la lista blanca del distribuidor (`auth.PermitidoAlDistribuidor`): él nunca ve nada de esto. La oficina son los
// roles que entran a Reparto —logístico, administrador, super administrador y desarrollador— acotados, como siempre, a su sucursal.

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
)

const (
	// TopeDePuntosPorLote: cuántos puntos caben en una petición. El aparato manda lotes de hasta 200.
	TopeDePuntosPorLote = 200
	// topeDePuntosDeUnaRuta: cuántos puntos se leen para dibujar una ruta (8 h a un punto cada 30 s son unos 1.000).
	topeDePuntosDeUnaRuta = 20000

	msgSoloDistribuidorMandaGps = "Solo los distribuidores mandan su ubicación."
)

type puntoGpsEntrada struct {
	ID        string   `json:"id"`
	RutaIDs   []string `json:"rutaIds"`
	Lat       *float64 `json:"lat"`
	Lng       *float64 `json:"lng"`
	Precision *float64 `json:"precision"`
	Velocidad *float64 `json:"velocidad"`
	Rumbo     *float64 `json:"rumbo"`
	Hora      string   `json:"hora"`
	Evento    *string  `json:"evento"`
	PedidoID  *string  `json:"pedidoId"`
}

type puntoGpsRechazado struct {
	ID     string `json:"id"`
	Motivo string `json:"motivo"`
}

func (s *Servidor) rutasDeGps(rt *httpx.Router, sesion []httpx.Medio) {
	rt.ManejarFunc(http.MethodPost, "/api/track", s.recibirPuntosGps, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/routes/{id}/track", s.recorridoDeUnaRuta, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/vehicles/{id}/historial", s.historialDeUnVehiculo, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/tracking/ahora", s.dondeEstanAhora, sesion...)
}

func f32(v *float64) *float32 {
	if v == nil {
		return nil
	}
	x := float32(*v)
	return &x
}

// validarPuntoGps devuelve el punto listo para guardar, o el motivo por el que se rechaza. El `id` tiene que ser un UUIDv7 (lo pone el aparato).
func validarPuntoGps(e puntoGpsEntrada, ahora time.Time, mias map[uuid.UUID]bool) (alcance.PuntoGps, string) {
	var p alcance.PuntoGps
	id, err := uuid.Parse(strings.TrimSpace(e.ID))
	if err != nil || id.Version() != 7 {
		return p, "el id tiene que ser un UUID v7"
	}
	p.ID = id
	if e.Lat == nil || e.Lng == nil || *e.Lat < -90 || *e.Lat > 90 || *e.Lng < -180 || *e.Lng > 180 {
		return p, "coordenadas fuera de rango"
	}
	p.Lat, p.Lng = *e.Lat, *e.Lng
	t, err := time.Parse(time.RFC3339, strings.TrimSpace(e.Hora))
	if err != nil {
		return p, "la hora tiene que ser ISO-8601"
	}
	if t.After(ahora.Add(10 * time.Minute)) {
		return p, "la hora está en el futuro"
	}
	p.Hora = t.UTC()
	for _, c := range e.RutaIDs {
		if r, err := uuid.Parse(strings.TrimSpace(c)); err == nil && mias[r] {
			p.RutaIDs = append(p.RutaIDs, r)
		}
	}
	if len(p.RutaIDs) == 0 {
		return p, "ninguna de sus rutas es tuya"
	}
	if e.Evento != nil && *e.Evento != "" {
		switch *e.Evento {
		case "inicio", "parada", "fin":
			ev := *e.Evento
			p.Evento = &ev
		default:
			return p, "evento desconocido"
		}
	}
	if e.PedidoID != nil && strings.TrimSpace(*e.PedidoID) != "" {
		pid, err := uuid.Parse(strings.TrimSpace(*e.PedidoID))
		if err != nil {
			return p, "pedidoId no es un uuid"
		}
		p.PedidoID = pgtype.UUID{Bytes: pid, Valid: true}
	}
	p.Precision, p.Velocidad, p.Rumbo = f32(e.Precision), f32(e.Velocidad), f32(e.Rumbo)
	return p, ""
}

// POST /api/track — solo un distribuidor. Los puntos mal formados NO tumban el lote: salen en `rechazados` con su motivo, y el aparato los da
// por enviados (reintentarlos no los arreglaría).
func (s *Servidor) recibirPuntosGps(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	if !a.EsDelDistribuidor() {
		httpx.Error(w, r, http.StatusForbidden, msgSoloDistribuidorMandaGps)
		return
	}
	var c struct {
		Puntos []puntoGpsEntrada `json:"puntos"`
	}
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	if len(c.Puntos) == 0 || len(c.Puntos) > TopeDePuntosPorLote {
		httpx.Error(w, r, http.StatusBadRequest, "Manda entre 1 y 200 puntos por petición.")
		return
	}
	// LAS RUTAS QUE DICEN LOS PUNTOS, comprobadas de una vez contra el distribuidor de la sesión.
	pedidas := map[uuid.UUID]bool{}
	for _, e := range c.Puntos {
		for _, x := range e.RutaIDs {
			if u, err := uuid.Parse(strings.TrimSpace(x)); err == nil {
				pedidas[u] = true
			}
		}
	}
	ids := make([]uuid.UUID, 0, len(pedidas))
	for u := range pedidas {
		ids = append(ids, u)
	}
	suyas, err := a.RutasDeEsteDistribuidor(r.Context(), ids)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	mias := map[uuid.UUID]bool{}
	for _, u := range suyas {
		mias[u] = true
	}

	ahora := time.Now().UTC()
	recibidos, nuevos := 0, 0
	rechazados := []puntoGpsRechazado{}
	for _, e := range c.Puntos {
		p, motivo := validarPuntoGps(e, ahora, mias)
		if motivo != "" {
			rechazados = append(rechazados, puntoGpsRechazado{ID: e.ID, Motivo: motivo})
			continue
		}
		nuevo, err := a.GuardarPuntoGps(r.Context(), p)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		recibidos++
		if nuevo {
			nuevos++
		}
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"recibidos": recibidos, "nuevos": nuevos, "rechazados": rechazados})
}

type puntoGpsSalida struct {
	ID        uuid.UUID  `json:"id"`
	Lat       float64    `json:"lat"`
	Lng       float64    `json:"lng"`
	Precision *float32   `json:"precision"`
	Velocidad *float32   `json:"velocidad"`
	Rumbo     *float32   `json:"rumbo"`
	Hora      time.Time  `json:"hora"`
	Evento    *string    `json:"evento"`
	PedidoID  *uuid.UUID `json:"pedidoId"`
}

func idDe(p pgtype.UUID) *uuid.UUID {
	if !p.Valid {
		return nil
	}
	u := uuid.UUID(p.Bytes)
	return &u
}

// GET /api/routes/{id}/track — el recorrido real de una ruta.
func (s *Servidor) recorridoDeUnaRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	ruta, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	puntos, err := a.PuntosDeUnaRuta(r.Context(), id, topeDePuntosDeUnaRuta+1)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	truncado := len(puntos) > topeDePuntosDeUnaRuta
	if truncado {
		puntos = puntos[:topeDePuntosDeUnaRuta]
	}
	salida := make([]puntoGpsSalida, 0, len(puntos))
	for _, p := range puntos {
		salida = append(salida, puntoGpsSalida{
			ID: p.ID, Lat: p.Lat, Lng: p.Lng, Precision: p.PrecisionM, Velocidad: p.VelocidadMs, Rumbo: p.Rumbo,
			Hora: p.Hora.Time, Evento: p.Evento, PedidoID: idDe(p.PedidoID),
		})
	}
	paradas, err := a.ParadasConSuHoraDeUnaRuta(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	filas := make([]map[string]any, 0, len(paradas))
	for _, p := range paradas {
		filas = append(filas, map[string]any{
			"pedidoId": p.ID, "factura": p.FacturaNumero, "cliente": p.CustomerName,
			"lat": p.EndLat, "lng": p.EndLng, "orden": p.StopOrder,
			"resultado": textoDeResultado(p.Resultado), "resultadoAt": hora(p.ResultadoAt), "nota": p.ResultadoNota,
			"cobroEntrega": p.CobroEntrega, "cobroEntregaAt": hora(p.CobroEntregaAt),
		})
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"ruta": map[string]any{
			"id": ruta.ID, "codigo": ruta.RouteCode, "nombre": ruta.Name, "estado": string(ruta.Status),
			"inicio": hora(ruta.StartedAt), "fin": hora(ruta.FinishedAt),
			"distribuidorId": idOpcional(ruta.DistribuidorID), "distribuidor": ruta.DistribuidorNombre,
			"vehiculoId": idOpcional(ruta.VehicleID), "vehiculo": ruta.VehiculoNombre,
		},
		"puntos": salida, "paradas": filas, "truncado": truncado,
	})
}

// GET /api/vehicles/{id}/historial — la vida de un vehículo.
func (s *Servidor) historialDeUnVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	if _, err := a.ObtenerVehiculo(r.Context(), id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
			return
		}
		httpx.ErrorInterno(w, r, err)
		return
	}
	filas, err := a.HistorialDeUnVehiculo(r.Context(), id, 200)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]map[string]any, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, map[string]any{
			"id": f.ID, "codigo": f.RouteCode, "nombre": f.Name, "estado": string(f.Status),
			"fecha": hora(f.DeliveryDate), "inicio": hora(f.StartedAt), "fin": hora(f.FinishedAt),
			"km": f.TotalDistance, "distribuidorId": idOpcional(f.DistribuidorID), "distribuidor": f.DistribuidorNombre,
			"paradas": f.Paradas, "entregadas": f.Entregadas, "devueltas": f.Devueltas, "cobradas": f.Cobradas, "puntos": f.Puntos,
		})
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"vehiculoId": id, "rutas": salida})
}

// GET /api/tracking/ahora — dónde está cada distribuidor con una ruta en curso.
func (s *Servidor) dondeEstanAhora(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	filas, err := a.UltimoPuntoDeCadaDistribuidor(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]map[string]any, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, map[string]any{
			"distribuidorId": f.DistribuidorID, "distribuidor": f.DistribuidorNombre,
			"lat": f.Lat, "lng": f.Lng, "hora": hora(f.Hora), "recibidoAt": hora(f.RecibidoAt),
			"velocidad": f.VelocidadMs, "rutaIds": f.RutaIds,
		})
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"distribuidores": salida})
}
