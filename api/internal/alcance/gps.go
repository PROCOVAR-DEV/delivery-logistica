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

// RutasDeEsteDispositivo: de esas rutas, las que están ASIGNADAS a su teléfono (completadas incluidas: el punto de «fin» llega después).
func (a *Acotado) RutasDeEsteDispositivo(ctx context.Context, ids []uuid.UUID) ([]sqlc.RutasDelDispositivoEntreRow, error) {
	if a.dispositivo == nil || len(ids) == 0 {
		return nil, nil
	}
	return a.q.RutasDelDispositivoEntre(ctx, sqlc.RutasDelDispositivoEntreParams{
		RutaIds: ids, Dispositivo: pgtype.UUID{Bytes: *a.dispositivo, Valid: true},
	})
}

// GuardarPuntoGps guarda UN punto del teléfono de la sesión: su dispositivo y su sucursal las pone el alcance. Devuelve si era nuevo (un punto
// repetido no es un error: es la idempotencia del reintento).
func (a *Acotado) GuardarPuntoGps(ctx context.Context, p PuntoGps, distribuidor pgtype.UUID) (bool, error) {
	if a.dispositivo == nil || a.sucursal == nil {
		return false, ErrSinDispositivo
	}
	n, err := a.q.GuardarPuntoGps(ctx, sqlc.GuardarPuntoGpsParams{
		ID: p.ID, Dispositivo: *a.dispositivo, Distribuidor: distribuidor, Sucursal: *a.sucursal,
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

// SinAlcance son las consultas SIN alcance de nadie, para lo que ocurre ANTES de que haya sesión: el teléfono que reclama un enlace todavía no
// tiene token (`api/dispositivos.go`). Es la única puerta así: todo lo demás pasa por [Acotado].
func (p *Porteria) SinAlcance() sqlc.Querier { return p.fuente.Consultas() }

// EnTxSinAlcance: lo mismo, dentro de una transacción (reclamar un enlace y asignar la ruta son dos escrituras que van juntas).
func (p *Porteria) EnTxSinAlcance(ctx context.Context, f func(sqlc.Querier) error) error {
	return p.fuente.EnTx(ctx, f)
}

// Los enlaces de ruta de la OFICINA (acotados a su sucursal). Ver `api/dispositivos.go`.

func (a *Acotado) EnlaceVivoDeUnaRuta(ctx context.Context, ruta uuid.UUID) (sqlc.EnlaceVivoDeUnaRutaRow, error) {
	return a.q.EnlaceVivoDeUnaRuta(ctx, sqlc.EnlaceVivoDeUnaRutaParams{Ruta: ruta, Sucursal: a.sucursalPg()})
}

func (a *Acotado) RevocarEnlacesDeUnaRuta(ctx context.Context, ruta uuid.UUID) error {
	return a.q.RevocarEnlacesDeUnaRuta(ctx, ruta)
}

func (a *Acotado) SoltarRutaDeSuDispositivo(ctx context.Context, ruta uuid.UUID) error {
	return a.q.SoltarRutaDeSuDispositivo(ctx, ruta)
}

func (a *Acotado) CrearEnlaceDeRuta(ctx context.Context, ruta uuid.UUID, token string, creadoPor *string) (sqlc.CrearEnlaceDeRutaRow, error) {
	return a.q.CrearEnlaceDeRuta(ctx, sqlc.CrearEnlaceDeRutaParams{Ruta: ruta, Token: token, CreadoPor: creadoPor})
}
