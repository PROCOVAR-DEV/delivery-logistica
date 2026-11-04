package alcance_test

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// El doble del Querier. Para esto sqlc genera la interfaz: las pruebas del alcance no
// necesitan base de datos, y por tanto se corren en cada compilación y no «cuando haya
// un Postgres a mano».
//
// Se EMBEBE `sqlc.Querier` sin implementarlo. Así el doble satisface la interfaz entera
// —ciento y pico consultas— escribiendo sólo las que interesan, y si una prueba llama a
// cualquier otra revienta con un puntero nil en vez de devolver un cero que parezca
// bueno. Un doble que contesta a todo es un doble que aprueba cualquier cosa.
type querierFalso struct {
	sqlc.Querier

	// Lo que "hay en la base".
	sucursales map[uuid.UUID]sqlc.ResolverSucursalRow
	vehiculos  []sqlc.ListarVehiculosRow

	// Fallo que devuelve ResolverSucursal, para la prueba de «la base no contesta».
	falloAlResolver error
	// Lo mismo para la búsqueda POR CÓDIGO, que es el camino por el que entra un token
	// de Accesos de verdad. Va aparte porque son dos consultas distintas y la de arriba
	// no la toca: con una sola variable, la prueba del fallo por código habría pasado
	// sin ejecutar nada nuevo.
	falloAlBuscarPorCodigo error

	// Lo que se vio pasar. Es lo que se comprueba: qué sucursal llegó a cada consulta.
	sucursalPedida    []pgtype.UUID
	personaPedida     []pgtype.UUID
	sucursalCreadaPor *string
}

func (q *querierFalso) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	if q.falloAlResolver != nil {
		return sqlc.ResolverSucursalRow{}, q.falloAlResolver
	}
	fila, ok := q.sucursales[id]
	if !ok {
		return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
	}
	return fila, nil
}

// BuscarSucursalPorCodigo es la sucursal por su `external_id` (CAM, HOL, STG...), que es
// lo que Accesos firma dentro del token. Repite el WHERE del SQL de verdad
// (`db/queries/branches.sql`): comparación exacta, sin `ilike` y sin recortes.
func (q *querierFalso) BuscarSucursalPorCodigo(_ context.Context, codigo *string) (sqlc.BuscarSucursalPorCodigoRow, error) {
	if q.falloAlBuscarPorCodigo != nil {
		return sqlc.BuscarSucursalPorCodigoRow{}, q.falloAlBuscarPorCodigo
	}
	if codigo == nil {
		return sqlc.BuscarSucursalPorCodigoRow{}, pgx.ErrNoRows
	}
	for id, s := range q.sucursales {
		if s.ExternalID != nil && *s.ExternalID == *codigo {
			return sqlc.BuscarSucursalPorCodigoRow{ID: id, Name: s.Name, ExternalID: s.ExternalID}, nil
		}
	}
	return sqlc.BuscarSucursalPorCodigoRow{}, pgx.ErrNoRows
}

// ListarVehiculos repite el WHERE del SQL de verdad (`db/queries/vehicles.sql`): sin
// alcance salen todos; con alcance, los de esa sucursal MÁS los que no tienen ninguna,
// que son los compartidos.
func (q *querierFalso) ListarVehiculos(_ context.Context, arg sqlc.ListarVehiculosParams) ([]sqlc.ListarVehiculosRow, error) {
	sucursal := arg.Sucursal
	q.sucursalPedida = append(q.sucursalPedida, sucursal)
	var salida []sqlc.ListarVehiculosRow
	for _, v := range q.vehiculos {
		if !sucursal.Valid || !v.BranchID.Valid || v.BranchID.Bytes == sucursal.Bytes {
			salida = append(salida, v)
		}
	}
	return salida, nil
}

func (q *querierFalso) ListarSucursales(_ context.Context, persona pgtype.UUID) ([]sqlc.ListarSucursalesRow, error) {
	q.personaPedida = append(q.personaPedida, persona)
	var salida []sqlc.ListarSucursalesRow
	for id, s := range q.sucursales {
		if persona.Valid && persona.Bytes != [16]byte(id) {
			continue
		}
		salida = append(salida, sqlc.ListarSucursalesRow{ID: id, Name: s.Name, ExternalID: s.ExternalID})
	}
	return salida, nil
}

func (q *querierFalso) ObtenerVehiculo(_ context.Context, arg sqlc.ObtenerVehiculoParams) (sqlc.ObtenerVehiculoRow, error) {
	q.sucursalPedida = append(q.sucursalPedida, arg.Sucursal)
	for _, v := range q.vehiculos {
		if v.ID != arg.ID {
			continue
		}
		if !arg.Sucursal.Valid || !v.BranchID.Valid || v.BranchID.Bytes == arg.Sucursal.Bytes {
			return sqlc.ObtenerVehiculoRow{ID: v.ID, Name: v.Name, BranchID: v.BranchID, TipoNombre: v.TipoNombre}, nil
		}
	}
	return sqlc.ObtenerVehiculoRow{}, pgx.ErrNoRows
}

func (q *querierFalso) CrearSucursal(_ context.Context, arg sqlc.CrearSucursalParams) (sqlc.Branch, error) {
	q.sucursalCreadaPor = arg.CreadoPor
	return sqlc.Branch{ID: uuid.New(), Name: arg.Name, CreadoPor: arg.CreadoPor}, nil
}

// fuenteFalsa es lo que `alcance` pide para poder consultar.
type fuenteFalsa struct{ q *querierFalso }

func (f fuenteFalsa) Consultas() sqlc.Querier { return f.q }

// EnTx corre la función tal cual: el doble no tiene transacciones. Lo que se prueba aquí
// es el alcance, no el aislamiento de Postgres.
func (f fuenteFalsa) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

var errBaseCaida = errors.New("la base no contesta")
