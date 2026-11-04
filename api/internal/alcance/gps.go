package alcance

// EL GPS DEL DISTRIBUIDOR (04/11/2026): la puerta a `db/queries/gps.sql`. Lo escrito (los puntos) lo rellena el alcance —quién, de qué
// sucursal— y lo leído (el recorrido, el historial, «dónde están ahora») sale acotado a la sucursal de quien pregunta.

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// PuntoGps es un punto ya validado por el manejador.
type PuntoGps struct {
	ID        uuid.UUID
	RutaIDs   []uuid.UUID
	Lat, Lng  float64
	Precision *float32
	Velocidad *float32
	Rumbo     *float32
	Hora      time.Time
	Evento    *string
	PedidoID  pgtype.UUID
}

// RutasDeEsteDistribuidor: de esas rutas, las que SON suyas (completadas incluidas).
func (a *Acotado) RutasDeEsteDistribuidor(ctx context.Context, ids []uuid.UUID) ([]uuid.UUID, error) {
	if a.distribuidor == nil || len(ids) == 0 {
		return nil, nil
	}
	return a.q.RutasDelDistribuidorEntre(ctx, sqlc.RutasDelDistribuidorEntreParams{RutaIds: ids, Distribuidor: pgtype.UUID{Bytes: *a.distribuidor, Valid: true}})
}

// GuardarPuntoGps guarda UN punto de la persona de la sesión (solo un distribuidor): su persona y su sucursal las pone el alcance. Devuelve
// si era nuevo (un punto repetido no es un error: es la idempotencia del reintento).
func (a *Acotado) GuardarPuntoGps(ctx context.Context, p PuntoGps) (bool, error) {
	if a.distribuidor == nil || a.sucursal == nil {
		return false, ErrSinDistribuidor
	}
	n, err := a.q.GuardarPuntoGps(ctx, sqlc.GuardarPuntoGpsParams{
		ID: p.ID, Distribuidor: *a.distribuidor, Persona: a.actor, Sucursal: *a.sucursal,
		RutaIds: p.RutaIDs, Lat: p.Lat, Lng: p.Lng,
		PrecisionM: p.Precision, VelocidadMs: p.Velocidad, Rumbo: p.Rumbo,
		Hora: pgtype.Timestamptz{Time: p.Hora, Valid: true}, Evento: p.Evento, PedidoID: p.PedidoID,
	})
	return n > 0, err
}

func (a *Acotado) PuntosDeUnaRuta(ctx context.Context, ruta uuid.UUID, tope int32) ([]sqlc.PuntosDeUnaRutaRow, error) {
	return a.q.PuntosDeUnaRuta(ctx, sqlc.PuntosDeUnaRutaParams{Ruta: ruta, Sucursal: a.sucursalPg(), Tope: tope})
}

func (a *Acotado) HistorialDeUnVehiculo(ctx context.Context, vehiculo uuid.UUID, tope int32) ([]sqlc.HistorialDeUnVehiculoRow, error) {
	return a.q.HistorialDeUnVehiculo(ctx, sqlc.HistorialDeUnVehiculoParams{Vehiculo: pgtype.UUID{Bytes: vehiculo, Valid: true}, Sucursal: a.sucursalPg(), Tope: tope})
}

func (a *Acotado) UltimoPuntoDeCadaDistribuidor(ctx context.Context) ([]sqlc.UltimoPuntoDeCadaDistribuidorRow, error) {
	return a.q.UltimoPuntoDeCadaDistribuidor(ctx, a.sucursalPg())
}

func (a *Acotado) ParadasConSuHoraDeUnaRuta(ctx context.Context, ruta uuid.UUID) ([]sqlc.ParadasConSuHoraDeUnaRutaRow, error) {
	return a.q.ParadasConSuHoraDeUnaRuta(ctx, pgtype.UUID{Bytes: ruta, Valid: true})
}
