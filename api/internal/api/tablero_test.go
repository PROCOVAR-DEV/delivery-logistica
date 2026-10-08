package api

// Las pruebas del tablero, POR HTTP y con un doble de la base.
//
// Van en el paquete `api` y no en `api_test` porque montan `rutasTablero`, que no se
// exporta: quien las llama de verdad es `Rutas()` en servidor.go, y aquí hace falta poder
// montarlas solas sin tocar ese fichero.
//
// El doble NO es un «devuelve lo que te pidan»: repite las reglas del SQL de verdad —la
// única de (columna, posición), el `route_id IS NULL`, la misma sucursal para el pedido y
// la columna, el RESTRICT de la columna con tarjetas dentro—. Un doble que contesta a todo
// es un doble que aprueba cualquier cosa, y justo lo que hay que comprobar aquí es que el
// manejador respeta lo que la base le impone.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

const secretoTab = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

var (
	sucStg = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	sucHol = uuid.MustParse("22222222-2222-2222-2222-222222222222")

	colCentro = uuid.MustParse("c0000000-0000-0000-0000-00000000000a")
	colVista  = uuid.MustParse("c0000000-0000-0000-0000-00000000000b")
	colVacia  = uuid.MustParse("c0000000-0000-0000-0000-00000000000c")

	ped1    = uuid.MustParse("0d000000-0000-0000-0000-000000000001")
	ped2    = uuid.MustParse("0d000000-0000-0000-0000-000000000002")
	ped3    = uuid.MustParse("0d000000-0000-0000-0000-000000000003")
	pedRuta = uuid.MustParse("0d000000-0000-0000-0000-000000000009")
	pedHol  = uuid.MustParse("0d000000-0000-0000-0000-00000000000f")

	rutaNueva = uuid.MustParse("4a000000-0000-0000-0000-000000000001")

	// Los camiones. En producción hay OCHO, uno por sucursal, los ocho con `branch_id`:
	// no hay camiones compartidos que disculpen un id ajeno.
	vehStgTab = uuid.MustParse("7e000000-0000-0000-0000-00000000000a")
	vehHolTab = uuid.MustParse("7e000000-0000-0000-0000-00000000000b")
)

// --------------------------------------------------------------------------- el doble

type pedidoFalso struct {
	id       uuid.UUID
	sucursal uuid.UUID
	nombre   string
	folio    string
	peso     float64
	ruta     *uuid.UUID
	// (0,0) es «SIN COORDENADAS», no el golfo de Guinea: es como el SQL de verdad ve un
	// `end_lat`/`end_lng` nulo. Pasa en producción — el upsert del espejo escribe
	// `end_lat = excluded.end_lat` sin `coalesce`, así que una bajada puede dejar sin
	// punto de entrega un pedido que ya estaba colocado.
	lat, lng float64
	factura  *sqlc.FacturaEstado
	// fecha es `order_date`, el segundo trozo del orden de la mitad izquierda y del
	// cursor. Nil es un pedido SIN fecha, que va al final (`DESC NULLS LAST`) y es donde
	// un cursor mal escrito se repite a sí mismo o se salta filas.
	fecha *time.Time
	// entregado es `delivered_at` + `resultado = 'entregado'`, las dos columnas que
	// `MarcarResultadoDeParada` escribe y limpia JUNTAS. Con `ruta` a nil es el caso que
	// da miedo y que en producción llega solo: la clave ajena de `orders.route_id` es
	// `ON DELETE SET NULL`, así que basta con que alguien borre la ruta de ayer para que
	// un pedido ya repartido aparezca suelto y sin una sola marca en el `WHERE` de
	// siempre. Ver `db/migrations/00001_init.sql:446`.
	entregado bool
	// `sinCobrar` deja `factura_domicilio` en NULL y `sinCotizar` deja `pedido_costo` en NULL:
	// las dos condiciones que Amado añadió el 07/10/2026. Al revés a propósito: el valor cero
	// es «cobrado y cotizado», que es lo que necesitan casi todas las pruebas.
	sinCobrar, sinCotizar bool
}

func tableroFloatPtr(v float64) *float64 { return &v }

// domicilioYCosto: lo que el SQL devuelve en `factura_domicilio` y `pedido_costo`.
func (p pedidoFalso) domicilioYCosto() (domicilio, costo *float64) {
	if !p.sinCobrar {
		domicilio = tableroFloatPtr(1)
	}
	if !p.sinCotizar {
		costo = tableroFloatPtr(10)
	}
	return domicilio, costo
}

// entregadoEn: lo que el SQL devuelve en `delivered_at`.
func (p pedidoFalso) entregadoEn() pgtype.Timestamptz {
	if !p.entregado {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: time.Now().Add(-3 * time.Hour), Valid: true}
}

// suResultado: lo que el SQL devuelve en `resultado`.
func (p pedidoFalso) suResultado() *sqlc.StopResult {
	if !p.entregado {
		return nil
	}
	e := sqlc.StopResultEntregado
	return &e
}

// tieneCoordenadas: lo que en la base es `end_lat IS NOT NULL AND end_lng IS NOT NULL`.
func (p pedidoFalso) tieneCoordenadas() bool { return p.lat != 0 || p.lng != 0 }

type colocacion struct {
	columna  uuid.UUID
	posicion int32
}

// vehiculoFalso: un camión con su sucursal. `sucursal` vacía es el COMPARTIDO, el que no
// es de nadie y por tanto es de todas.
type vehiculoFalso struct {
	id       uuid.UUID
	nombre   string
	sucursal uuid.UUID
	// `inactivo` es `is_active = false`; el cero es «activo».
	inactivo bool
}

type tableroFalso struct {
	sqlc.Querier

	origenes  []sqlc.ListarOrigenesRow
	vehiculos map[uuid.UUID]vehiculoFalso
	columnas  map[uuid.UUID]sqlc.BoardColumn
	pedidos   map[uuid.UUID]pedidoFalso
	colocadas map[uuid.UUID]colocacion
	creadas   []string

	// `true` para que `CrearColumna` choque por POSICIÓN en vez de por nombre. En
	// Postgres esa única es diferida y salta al CERRAR la transacción, cuando dos
	// aparatos suben a la vez y los dos calcularon el mismo `max(posicion)+1`.
	choquePosicion bool
	// El choque de la única de las TARJETAS, `(column_id, posicion)`. También es
	// `DEFERRABLE INITIALLY DEFERRED`, así que no salta al escribir: salta AL CERRAR la
	// transacción, y por eso el doble lo devuelve desde `EnTx` y no desde `ColocarPedido`.
	// Puesto en el sitio equivocado, la prueba aprobaría un manejador que sólo traduce lo
	// que le llega de la consulta.
	choqueAlCerrar bool
	// El pedido que OTRO se lleva entre la validación y el enganche. Es la carrera de
	// verdad, la única que sí se arregla reintentando.
	seLoLlevan  uuid.UUID
	borrarFalla bool
	capacidad   float64

	// Lo que se vio pasar al armar la ruta: es lo que se comprueba.
	rutaCreada  *sqlc.CrearRutaParams
	enganchados []uuid.UUID
	totales     *sqlc.FijarTotalesDeRutaParams
}

func nuevoTablero() *tableroFalso {
	igual := sqlc.FacturaEstadoIgual
	t := &tableroFalso{
		vehiculos: map[uuid.UUID]vehiculoFalso{
			vehStgTab: {id: vehStgTab, nombre: "Camión de Santiago", sucursal: sucStg},
			vehHolTab: {id: vehHolTab, nombre: "Camión de Holguín", sucursal: sucHol},
		},
		// CENTRO LLEVA SU CAMIÓN PREVISTO Y LAS OTRAS DOS NO, y es a propósito.
		//
		// Desde el 28/09/2026 `armarRutaDeColumna` se niega a armar una zona sin camión
		// (ver `msgZonaSinCamion`), así que la zona con la que se prueba TODO lo demás
		// —el orden de las paradas, los descartados, el día de la ruta— tiene que tener
		// uno o cada una de esas pruebas mediría el rechazo del camión en vez de lo suyo.
		// Y es además lo que hay en producción: 8 de las 9 rutas tenían vehículo.
		//
		// `colVista` y `colVacia` se quedan SIN camión a propósito: son las que prueban
		// que el «no» sale cuando toca. Ponerles uno dejaría el rechazo sin nadie que lo
		// ejercite.
		columnas: map[uuid.UUID]sqlc.BoardColumn{
			colCentro: {ID: colCentro, BranchID: sucStg, Nombre: "Centro", Posicion: 1,
				VehicleID: pgDe(vehStgTab)},
			colVista: {ID: colVista, BranchID: sucStg, Nombre: "Vista Alegre", Posicion: 2},
			colVacia: {ID: colVacia, BranchID: sucStg, Nombre: "Carretera", Posicion: 3},
		},
		pedidos: map[uuid.UUID]pedidoFalso{
			ped1:    {id: ped1, sucursal: sucStg, nombre: "Ana", peso: 30, lat: 20.02, lng: -75.82, factura: &igual},
			ped2:    {id: ped2, sucursal: sucStg, nombre: "Beto", peso: 40, lat: 20.05, lng: -75.80, factura: &igual},
			ped3:    {id: ped3, sucursal: sucStg, nombre: "Ana", peso: 10, lat: 20.03, lng: -75.83, factura: &igual},
			pedRuta: {id: pedRuta, sucursal: sucStg, nombre: "Ya salió", peso: 5, lat: 20.1, lng: -75.9, ruta: &colCentro, factura: &igual},
			pedHol:  {id: pedHol, sucursal: sucHol, nombre: "De Holguín", peso: 7, lat: 20.9, lng: -76.2, factura: &igual},
		},
		colocadas: map[uuid.UUID]colocacion{},
		// SIN `origenes`, y a propósito: los puntos de partida de esta base NO son los
		// almacenes. Sembrarlos aquí es lo que hacía pasar las pruebas mientras siete
		// sucursales de ocho se quedaban sin tablero. Desde dónde se mide lo dice
		// Accesos, y en las pruebas, `almacenesDelTablero`.
	}
	return t
}

// tresPuestasDeja Centro con tres tarjetas en las posiciones 1, 2 y 3.
func (q *tableroFalso) tresPuestas() {
	q.colocadas[ped1] = colocacion{colCentro, 1}
	q.colocadas[ped2] = colocacion{colCentro, 2}
	q.colocadas[ped3] = colocacion{colCentro, 3}
}

func (q *tableroFalso) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	switch id {
	case sucStg:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: sucStg, Name: "Santiago", ExternalID: &c}, nil
	case sucHol:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: sucHol, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

func (q *tableroFalso) ObtenerSucursal(_ context.Context, arg sqlc.ObtenerSucursalParams) (sqlc.Branch, error) {
	if arg.Sucursal.Valid && uuid.UUID(arg.Sucursal.Bytes) != arg.ID {
		return sqlc.Branch{}, pgx.ErrNoRows
	}
	// CON SU CÓDIGO PUESTO, que es lo que se le pregunta a Accesos para saber desde
	// dónde se mide. Sin él, el tablero de esa sucursal no existe — y ése era el fallo:
	// se resolvía por `saved_origins`, que no es donde viven los almacenes.
	stg, hol := "STG", "HOL"
	switch arg.ID {
	case sucStg:
		return sqlc.Branch{ID: sucStg, Name: "Santiago", ExternalID: &stg}, nil
	case sucHol:
		return sqlc.Branch{ID: sucHol, Name: "Holguín", ExternalID: &hol}, nil
	}
	return sqlc.Branch{}, pgx.ErrNoRows
}

// ListarOrigenes sigue aquí porque la interfaz de sqlc la exige, pero EL TABLERO YA NO LA
// USA: los orígenes son los puntos de partida de esta base y el almacén vive en Accesos.
func (q *tableroFalso) ListarOrigenes(_ context.Context, sucursal pgtype.UUID) ([]sqlc.ListarOrigenesRow, error) {
	var salida []sqlc.ListarOrigenesRow
	for _, o := range q.origenes {
		if sucursal.Valid && o.BranchID.Bytes != sucursal.Bytes {
			continue
		}
		salida = append(salida, o)
	}
	return salida, nil
}

func (q *tableroFalso) ListarColumnasDelTablero(_ context.Context, arg sqlc.ListarColumnasDelTableroParams) ([]sqlc.ListarColumnasDelTableroRow, error) {
	var salida []sqlc.ListarColumnasDelTableroRow
	for _, c := range q.columnas {
		if c.BranchID != arg.BranchID {
			continue
		}
		if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
			continue
		}
		fila := sqlc.ListarColumnasDelTableroRow{
			ID: c.ID, BranchID: c.BranchID, Nombre: c.Nombre, Posicion: c.Posicion,
		}
		for ped, col := range q.colocadas {
			if col.columna == c.ID {
				fila.Pedidos++
				fila.PesoKg += q.pedidos[ped].peso
			}
		}
		salida = append(salida, fila)
	}
	sort.Slice(salida, func(i, j int) bool { return salida[i].Posicion < salida[j].Posicion })
	return salida, nil
}

func (q *tableroFalso) ObtenerColumna(_ context.Context, arg sqlc.ObtenerColumnaParams) (sqlc.BoardColumn, error) {
	c, ok := q.columnas[arg.ID]
	if !ok {
		return sqlc.BoardColumn{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.BoardColumn{}, pgx.ErrNoRows
	}
	return c, nil
}

// CrearColumna repite las DOS ramas del SQL, y la segunda es la que importa.
//
// El aparato puede mandar el id —un UUIDv7 que genera él, aunque esté sin señal— y
// entonces la creación es IDEMPOTENTE: `ON CONFLICT (id) DO NOTHING` más el `SELECT` de
// la que ya estaba. Es lo que hace que un reintento, cuando la red se cayó justo después
// de escribir y nadie sabe si llegó, entre una sola vez.
//
// Un doble que sólo insertara no vería esa rama, y con ella se cae la razón entera del
// cambio.
func (q *tableroFalso) CrearColumna(_ context.Context, arg sqlc.CrearColumnaParams) (sqlc.CrearColumnaRow, error) {
	// El choque de la ÚNICA DE POSICIÓN, que en Postgres es diferida y salta al cerrar la
	// transacción cuando dos aparatos suben a la vez.
	if q.choquePosicion {
		return sqlc.CrearColumnaRow{}, &pgconn.PgError{
			Code: "23505", ConstraintName: "board_columns_posicion_unica",
		}
	}
	// RAMA 2: ese id ya está. Se devuelve la que hay, acotada por sucursal — sin el
	// `branch_id`, mandar el id de la zona de otra sucursal la devolvería.
	if arg.ID.Valid {
		if c, hay := q.columnas[uuid.UUID(arg.ID.Bytes)]; hay {
			if c.BranchID != arg.BranchID {
				return sqlc.CrearColumnaRow{}, pgx.ErrNoRows
			}
			return filaDeColumna(c), nil
		}
	}
	for _, c := range q.columnas {
		// El índice único es `(branch_id, lower(nombre))`: «centro» y «Centro» son la
		// misma zona para quien las escribe.
		if c.BranchID == arg.BranchID && strings.EqualFold(c.Nombre, arg.Nombre) {
			// CON EL NOMBRE DE LA RESTRICCIÓN, como lo manda Postgres. La tabla tiene
			// DOS únicas —ésta y la de la posición, que es diferida y salta al cerrar la
			// transacción cuando dos aparatos suben a la vez—, y el manejador las
			// distingue para no contestar «ya hay una columna X» a un choque que no va
			// del nombre.
			return sqlc.CrearColumnaRow{}, &pgconn.PgError{
				Code: "23505", ConstraintName: "board_columns_nombre_idx",
			}
		}
	}
	pos := int32(1)
	for _, c := range q.columnas {
		if c.BranchID == arg.BranchID && c.Posicion >= pos {
			pos = c.Posicion + 1
		}
	}
	// El id del aparato si lo trae; si no, lo pone la base.
	id := uuid.New()
	if arg.ID.Valid {
		id = uuid.UUID(arg.ID.Bytes)
	}
	nueva := sqlc.BoardColumn{ID: id, BranchID: arg.BranchID, Nombre: arg.Nombre, Posicion: pos}
	q.columnas[nueva.ID] = nueva
	q.creadas = append(q.creadas, arg.Nombre)
	return filaDeColumna(nueva), nil
}

func filaDeColumna(c sqlc.BoardColumn) sqlc.CrearColumnaRow {
	return sqlc.CrearColumnaRow{
		ID: c.ID, BranchID: c.BranchID, Nombre: c.Nombre, Posicion: c.Posicion,
		VehicleID: c.VehicleID, CreadoPor: c.CreadoPor,
		CreatedAt: c.CreatedAt, UpdatedAt: c.UpdatedAt,
	}
}

// ActualizarColumna: renombrar y elegir camión. **No estaba**, así que esa ruta no la
// ejercitaba nadie: el `sqlc.Querier` embebido es nil y cualquier PATCH daba 500 dentro de
// las pruebas. Se descubrió el 17/09/2026 escribiendo la prueba de que cada escritura del
// tablero avisa a las pantallas abiertas.
//
// Repite lo que hace el SQL: acota por sucursal, respeta `tocar_vehiculo` —«no me lo
// toques» y «quítamelo» son dos órdenes distintas y las dos llegan con el campo vacío— y
// choca con el índice único del nombre.
func (q *tableroFalso) ActualizarColumna(_ context.Context, arg sqlc.ActualizarColumnaParams) (sqlc.BoardColumn, error) {
	c, hay := q.columnas[arg.ID]
	if !hay {
		return sqlc.BoardColumn{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.BoardColumn{}, pgx.ErrNoRows
	}
	if arg.Nombre != nil {
		for otra, o := range q.columnas {
			if otra != arg.ID && o.BranchID == c.BranchID &&
				strings.EqualFold(o.Nombre, *arg.Nombre) {
				return sqlc.BoardColumn{}, &pgconn.PgError{
					Code: "23505", ConstraintName: "board_columns_nombre_idx",
				}
			}
		}
		c.Nombre = *arg.Nombre
	}
	if arg.TocarVehiculo {
		c.VehicleID = arg.VehicleID
	}
	q.columnas[arg.ID] = c
	return c, nil
}

// ReordenarColumnas repite el `array_position`: la posición de cada una es su sitio en la
// lista, y las que no vengan no se tocan.
func (q *tableroFalso) ReordenarColumnas(_ context.Context, arg sqlc.ReordenarColumnasParams) (int64, error) {
	var n int64
	for i, id := range arg.Ids {
		c, ok := q.columnas[id]
		if !ok || c.BranchID != arg.BranchID {
			continue
		}
		if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
			continue
		}
		c.Posicion = int32(i + 1)
		q.columnas[id] = c
		n++
	}
	return n, nil
}

// enAlcance repite lo que hacen TODAS las consultas del tablero:
// `(sucursal IS NULL OR c.branch_id = sucursal)`, con la columna por delante — casi todas
// llegan a `board_placements` pasando por `board_columns`, así que una columna que no
// existe es tan «fuera» como una de otra sucursal.
//
// NO ESTABA, y ése era el agujero. El 18/09/2026 el auditor sustituyó las 24 apariciones
// de `Sucursal: a.sucursalPg()` por «todas las sucursales» y la suite entera siguió verde:
// el doble no miraba `arg.Sucursal`, así que el parámetro podía llegar vacío sin que se
// notara en ninguna respuesta. Un doble que no mira el alcance no puede cazar una fuga de
// alcance, y estas pruebas van por los cinco endpoints que NO reciben `branchId` ni pasan
// por `tableroDe`: para ellos ese narg es la única defensa que hay.
func (q *tableroFalso) enAlcance(columna uuid.UUID, sucursal pgtype.UUID) bool {
	c, hay := q.columnas[columna]
	if !hay {
		return false
	}
	return !sucursal.Valid || c.BranchID == uuid.UUID(sucursal.Bytes)
}

// deLaSucursal es lo mismo para las consultas que salen de `orders` y no de una columna.
func deLaSucursal(suya uuid.UUID, sucursal pgtype.UUID) bool {
	return !sucursal.Valid || suya == uuid.UUID(sucursal.Bytes)
}

func (q *tableroFalso) ContarPedidosEnColumna(_ context.Context, arg sqlc.ContarPedidosEnColumnaParams) (int64, error) {
	if !q.enAlcance(arg.ColumnaID, arg.Sucursal) {
		return 0, nil
	}
	var n int64
	for _, c := range q.colocadas {
		if c.columna == arg.ColumnaID {
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) VaciarColumna(_ context.Context, arg sqlc.VaciarColumnaParams) (int64, error) {
	if !q.enAlcance(arg.ColumnaID, arg.Sucursal) {
		return 0, nil
	}
	var n int64
	for ped, c := range q.colocadas {
		if c.columna == arg.ColumnaID {
			delete(q.colocadas, ped)
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) MoverPedidosDeColumna(_ context.Context, arg sqlc.MoverPedidosDeColumnaParams) (int64, error) {
	origen, ok1 := q.columnas[arg.ColumnaOrigen]
	destino, ok2 := q.columnas[arg.ColumnaDestino]
	if !ok1 || !ok2 || origen.BranchID != destino.BranchID {
		return 0, nil
	}
	if !deLaSucursal(origen.BranchID, arg.Sucursal) {
		return 0, nil
	}
	tope := int32(0)
	for _, c := range q.colocadas {
		if c.columna == destino.ID && c.posicion > tope {
			tope = c.posicion
		}
	}
	var n int64
	for ped, c := range q.colocadas {
		if c.columna != origen.ID {
			continue
		}
		q.colocadas[ped] = colocacion{destino.ID, tope + c.posicion}
		n++
	}
	return n, nil
}

// BorrarColumna repite el `ON DELETE RESTRICT`: con tarjetas dentro, la base se niega con
// un 23503. Es la mitad de la prueba que importa — sin esto, el 409 se podría estar
// dando sólo por el contador y el 500 seguiría ahí esperando a una carrera.
func (q *tableroFalso) BorrarColumna(_ context.Context, arg sqlc.BorrarColumnaParams) (int64, error) {
	c, ok := q.columnas[arg.ID]
	if !ok {
		return 0, nil
	}
	if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
		return 0, nil
	}
	if q.borrarFalla {
		return 0, &pgconn.PgError{Code: "23503", ConstraintName: "board_placements_column_id_fkey"}
	}
	for _, col := range q.colocadas {
		if col.columna == arg.ID {
			return 0, &pgconn.PgError{Code: "23503", ConstraintName: "board_placements_column_id_fkey"}
		}
	}
	delete(q.columnas, arg.ID)
	return 1, nil
}

// Y DEVUELVE `BranchID`, el de la COLUMNA, igual que el `JOIN` del CTE de verdad. Sin él
// este doble no podría cazar un aviso que saliera pelado: la sucursal del aviso de colocar
// una tarjeta sale de aquí, y un cero se leería como «de todas» y pasaría por bueno.
func (q *tableroFalso) ColocarPedido(_ context.Context, arg sqlc.ColocarPedidoParams) (sqlc.ColocarPedidoRow, error) {
	p, ok := q.pedidos[arg.PedidoID]
	c, ok2 := q.columnas[arg.ColumnaID]
	// Las condiciones del `WHERE` del INSERT de verdad. La de `delivered_at` es la que
	// `route_id IS NULL` no cubre: un entregado cuya ruta se borró está suelto.
	if !ok || !ok2 || p.sucursal != c.BranchID || p.ruta != nil || p.entregado {
		return sqlc.ColocarPedidoRow{}, pgx.ErrNoRows
	}
	// LAS DOS DE AMADO (`factura_domicilio > 0` y `pedido_costo IS NOT NULL`). `factura_estado`
	// NO está en el `WHERE` de `ColocarPedido` y no puede estar aquí.
	if p.sinCobrar || p.sinCotizar {
		return sqlc.ColocarPedidoRow{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.ColocarPedidoRow{}, pgx.ErrNoRows
	}
	// La única de (columna, posición): si ya hay OTRA tarjeta en ese sitio, la base
	// revienta. Es lo que prueba que el manejador abre hueco antes de soltar.
	for ped, col := range q.colocadas {
		if ped != arg.PedidoID && col.columna == arg.ColumnaID && col.posicion == arg.Posicion {
			return sqlc.ColocarPedidoRow{}, &pgconn.PgError{Code: "23505", ConstraintName: "board_placements_posicion_unica"}
		}
	}
	q.colocadas[arg.PedidoID] = colocacion{arg.ColumnaID, arg.Posicion}
	return sqlc.ColocarPedidoRow{
		OrderID: arg.PedidoID, ColumnID: arg.ColumnaID, Posicion: arg.Posicion,
		ColocadoPor: arg.ColocadoPor,
		ColocadoAt:  pgtype.Timestamptz{Time: time.Now(), Valid: true},
		BranchID:    c.BranchID,
	}, nil
}

func (q *tableroFalso) AbrirHuecoEnColumna(_ context.Context, arg sqlc.AbrirHuecoEnColumnaParams) (int64, error) {
	if !q.enAlcance(arg.ColumnaID, arg.Sucursal) {
		return 0, nil
	}
	var n int64
	for ped, c := range q.colocadas {
		if c.columna == arg.ColumnaID && c.posicion >= arg.DesdePosicion {
			q.colocadas[ped] = colocacion{c.columna, c.posicion + 1}
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) CerrarHuecoEnColumna(_ context.Context, arg sqlc.CerrarHuecoEnColumnaParams) (int64, error) {
	if !q.enAlcance(arg.ColumnaID, arg.Sucursal) {
		return 0, nil
	}
	var n int64
	for ped, c := range q.colocadas {
		if c.columna == arg.ColumnaID && c.posicion > arg.DesdePosicion {
			q.colocadas[ped] = colocacion{c.columna, c.posicion - 1}
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) QuitarPedidoDelTablero(_ context.Context, arg sqlc.QuitarPedidoDelTableroParams) (sqlc.QuitarPedidoDelTableroRow, error) {
	c, ok := q.colocadas[arg.PedidoID]
	if !ok {
		return sqlc.QuitarPedidoDelTableroRow{}, pgx.ErrNoRows
	}
	// El `USING board_columns c` del DELETE de verdad: la tarjeta se saca por su COLUMNA,
	// y la columna es la que lleva la sucursal.
	if !q.enAlcance(c.columna, arg.Sucursal) {
		return sqlc.QuitarPedidoDelTableroRow{}, pgx.ErrNoRows
	}
	delete(q.colocadas, arg.PedidoID)
	// `BranchID` sale de la COLUMNA, como el `JOIN` de la consulta de verdad: es la sucursal
	// con la que se publica el aviso de que la tarjeta se quitó.
	return sqlc.QuitarPedidoDelTableroRow{
		OrderID: arg.PedidoID, ColumnID: c.columna, Posicion: c.posicion,
		BranchID: q.columnas[c.columna].BranchID,
	}, nil
}

// ObtenerVehiculo repite el `WHERE` de `vehicles.sql`: con alcance salen los de esa
// sucursal MÁS los que no tienen ninguna (los compartidos). Es por donde pasa ahora el
// `vehiculoId` del cuerpo, que hasta el 18/09/2026 sólo se comprobaba que fuese un uuid.
func (q *tableroFalso) ObtenerVehiculo(_ context.Context, arg sqlc.ObtenerVehiculoParams) (sqlc.ObtenerVehiculoRow, error) {
	v, hay := q.vehiculos[arg.ID]
	if !hay {
		return sqlc.ObtenerVehiculoRow{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && v.sucursal != uuid.Nil && v.sucursal != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.ObtenerVehiculoRow{}, pgx.ErrNoRows
	}
	fila := sqlc.ObtenerVehiculoRow{ID: v.id, Name: v.nombre, IsActive: !v.inactivo}
	if v.sucursal != uuid.Nil {
		fila.BranchID = pgtype.UUID{Bytes: [16]byte(v.sucursal), Valid: true}
	}
	return fila, nil
}

// ObtenerVehiculoParaCapacidad va SIN alcance —la consulta no lo admite— y por eso
// devuelve `branch_id`: es el manejador quien lo coteja contra la sucursal de la columna.
func (q *tableroFalso) ObtenerVehiculoParaCapacidad(_ context.Context, id uuid.UUID) (sqlc.ObtenerVehiculoParaCapacidadRow, error) {
	fila := sqlc.ObtenerVehiculoParaCapacidadRow{ID: id, Name: "F-350", Capacity: q.capacidad, IsActive: true}
	if v, hay := q.vehiculos[id]; hay {
		fila.IsActive = !v.inactivo
		if v.sucursal != uuid.Nil {
			fila.Name = v.nombre
			fila.BranchID = pgtype.UUID{Bytes: [16]byte(v.sucursal), Valid: true}
		}
	}
	return fila, nil
}

func (q *tableroFalso) ObtenerPedido(_ context.Context, arg sqlc.ObtenerPedidoParams) (sqlc.ObtenerPedidoRow, error) {
	p, ok := q.pedidos[arg.ID]
	if !ok {
		return sqlc.ObtenerPedidoRow{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && p.sucursal != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.ObtenerPedidoRow{}, pgx.ErrNoRows
	}
	domicilio, costo := p.domicilioYCosto()
	fila := sqlc.ObtenerPedidoRow{ID: p.id, CustomerName: p.nombre, Weight: p.peso,
		FacturaEstado: p.factura, FacturaDomicilio: domicilio, PedidoCosto: costo,
		DeliveredAt: p.entregadoEn(), Resultado: p.suResultado()}
	if p.ruta != nil {
		fila.RouteID = pgtype.UUID{Bytes: [16]byte(*p.ruta), Valid: true}
	}
	return fila, nil
}

func (q *tableroFalso) ListarPedidosColocados(_ context.Context, arg sqlc.ListarPedidosColocadosParams) ([]sqlc.ListarPedidosColocadosRow, error) {
	var salida []sqlc.ListarPedidosColocadosRow
	for ped, c := range q.colocadas {
		col := q.columnas[c.columna]
		if col.BranchID != arg.BranchID {
			continue
		}
		if !deLaSucursal(col.BranchID, arg.Sucursal) {
			continue
		}
		p := q.pedidos[ped]
		fila := sqlc.ListarPedidosColocadosRow{
			OrderID: ped, ColumnID: c.columna, Posicion: c.posicion,
			ColumnaNombre: col.Nombre, CustomerName: p.nombre, Weight: p.peso,
			FacturaEstado: p.factura, Resultado: p.suResultado(),
			KmAlAlmacen: kmHaversine(arg.OrigenLat, arg.OrigenLng, p.lat, p.lng),
		}
		// LO QUE **NO** LLEVA EL `WHERE` DE ESTA CONSULTA: aquí sale TODO lo puesto, se
		// pueda repartir o no, y por eso se devuelven crudos `route_id`, las coordenadas y
		// `source`. Es con lo que el armador nombra cada tarjeta que se cae y por qué.
		if p.tieneCoordenadas() {
			lat, lng := p.lat, p.lng
			fila.EndLat, fila.EndLng = &lat, &lng
		}
		if p.ruta != nil {
			fila.RouteID = pgtype.UUID{Bytes: [16]byte(*p.ruta), Valid: true}
		}
		if p.folio != "" {
			folio := p.folio
			fila.OperationNumber = &folio
		}
		origen := sqlc.ProcedenciaPedido
		fila.Source = &origen
		salida = append(salida, fila)
	}
	sort.Slice(salida, func(i, j int) bool { return salida[i].Posicion < salida[j].Posicion })
	return salida, nil
}

func (q *tableroFalso) AvisosDelTablero(_ context.Context, arg sqlc.AvisosDelTableroParams) (sqlc.AvisosDelTableroRow, error) {
	var fila sqlc.AvisosDelTableroRow
	for ped, c := range q.colocadas {
		if q.columnas[c.columna].BranchID != arg.BranchID {
			continue
		}
		if !deLaSucursal(q.columnas[c.columna].BranchID, arg.Sucursal) {
			continue
		}
		fila.Colocados++
		if q.pedidos[ped].ruta != nil {
			fila.EnOtraRuta++
		}
	}
	return fila, nil
}

func (q *tableroFalso) ListarPedidosSinColocar(_ context.Context, arg sqlc.ListarPedidosSinColocarParams) ([]sqlc.ListarPedidosSinColocarRow, error) {
	var salida []sqlc.ListarPedidosSinColocarRow
	for _, p := range q.pedidos {
		if p.sucursal != arg.BranchID || p.ruta != nil || p.entregado || p.sinCobrar || p.sinCotizar {
			continue
		}
		if !deLaSucursal(p.sucursal, arg.Sucursal) {
			continue
		}
		if _, puesto := q.colocadas[p.id]; puesto {
			continue
		}
		fila := sqlc.ListarPedidosSinColocarRow{
			ID: p.id, CustomerName: p.nombre, Weight: p.peso,
			KmAlAlmacen: kmHaversine(arg.OrigenLat, arg.OrigenLng, p.lat, p.lng),
		}
		if p.fecha != nil {
			fila.OrderDate = pgtype.Timestamptz{Time: *p.fecha, Valid: true}
		}
		salida = append(salida, fila)
	}
	// El encargo: el más cerca del almacén primero, y el desempate del SQL de verdad
	// —`km ASC, order_date DESC NULLS LAST, id ASC`—. Sin el desempate, dos clientes del
	// mismo edificio salen en un orden distinto en cada llamada y un cursor sobre eso no
	// puede funcionar: no es que pagine mal, es que no hay por dónde cortar.
	sort.Slice(salida, func(i, j int) bool { return vaAntes(salida[i], salida[j]) })
	// El corte del cursor: se dejan fuera las filas que NO van después de la terna.
	var tanda []sqlc.ListarPedidosSinColocarRow
	for _, f := range salida {
		if !despuesDelCursor(f, arg) {
			continue
		}
		tanda = append(tanda, f)
	}
	if int32(len(tanda)) > arg.Limite {
		tanda = tanda[:arg.Limite]
	}
	return tanda, nil
}

// vaAntes repite `ORDER BY km_al_almacen ASC, o.order_date DESC NULLS LAST, o.id ASC`.
func vaAntes(a, b sqlc.ListarPedidosSinColocarRow) bool {
	if a.KmAlAlmacen != b.KmAlAlmacen {
		return a.KmAlAlmacen < b.KmAlAlmacen
	}
	if a.OrderDate.Valid != b.OrderDate.Valid {
		return a.OrderDate.Valid // las que no tienen fecha van al final
	}
	if a.OrderDate.Valid && !a.OrderDate.Time.Equal(b.OrderDate.Time) {
		return a.OrderDate.Time.After(b.OrderDate.Time) // la más reciente primero
	}
	return a.ID.String() < b.ID.String()
}

// despuesDelCursor repite el `AND (...)` del cursor, condición por condición. Si esto se
// escribiera «más fácil» que el SQL, la prueba aprobaría una paginación que en Postgres se
// salta filas — que es justo lo que se está arreglando.
func despuesDelCursor(f sqlc.ListarPedidosSinColocarRow, arg sqlc.ListarPedidosSinColocarParams) bool {
	if !arg.DesdeID.Valid {
		return true // desde el principio
	}
	if arg.DesdeKm == nil {
		// Los tres van juntos. En la base esto deja la comparación en NULL y no sale
		// ninguna fila; aquí se hace lo mismo para que nadie se fíe de un cursor a medias.
		return false
	}
	if f.KmAlAlmacen > *arg.DesdeKm {
		return true
	}
	if f.KmAlAlmacen != *arg.DesdeKm {
		return false
	}
	switch {
	case arg.DesdeFecha.Valid && !f.OrderDate.Valid:
		return true
	case arg.DesdeFecha.Valid && f.OrderDate.Valid && f.OrderDate.Time.Before(arg.DesdeFecha.Time):
		return true
	case f.OrderDate.Valid == arg.DesdeFecha.Valid &&
		(!f.OrderDate.Valid || f.OrderDate.Time.Equal(arg.DesdeFecha.Time)):
		return f.ID.String() > uuid.UUID(arg.DesdeID.Bytes).String()
	}
	return false
}

func (q *tableroFalso) ContarPedidosSinColocar(_ context.Context, arg sqlc.ContarPedidosSinColocarParams) (int64, error) {
	var n int64
	for _, p := range q.pedidos {
		// EL MISMO FILTRO QUE LA LISTA, entregados incluidos: si aquí se olvidara,
		// el doble reproduciría el «Sin colocar (722) encima de una lista de 293».
		if p.sucursal != arg.BranchID || p.ruta != nil || p.entregado || p.sinCobrar || p.sinCotizar {
			continue
		}
		if !deLaSucursal(p.sucursal, arg.Sucursal) {
			continue
		}
		if _, puesto := q.colocadas[p.id]; puesto {
			continue
		}
		n++
	}
	return n, nil
}

// --------------------------------------------------------------------------- montaje

type fuenteTab struct{ q sqlc.Querier }

func (f fuenteTab) Consultas() sqlc.Querier { return f.q }

// EnTx corre la función y, si falla, DESHACE LAS TARJETAS COLOCADAS, que es lo único del
// doble que una transacción de verdad revierte y que importa a una prueba: colocar una
// tarjeta saca primero la que estaba y, si `ColocarPedido` no coloca nada, Postgres deja el
// pedido en la columna de la que venía. Sin esto, la prueba de que un rechazo no mueve la
// tarjeta se pasaría sólo porque el manejador comprobaba ANTES, y no por lo que hace la base.
// El aislamiento de Postgres sigue sin probarse aquí: lo que se prueba es el manejador.
func (f fuenteTab) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	var antes map[uuid.UUID]colocacion
	if t, ok := f.q.(*tableroFalso); ok {
		antes = make(map[uuid.UUID]colocacion, len(t.colocadas))
		for k, v := range t.colocadas {
			antes[k] = v
		}
	}
	if err := fn(f.q); err != nil {
		if t, ok := f.q.(*tableroFalso); ok {
			t.colocadas = antes
		}
		return err
	}
	// EL COMMIT. Las dos únicas diferidas del tablero saltan aquí y no antes, y lo que las
	// traduce tiene que estar mirando el error de `EnTx`, no el de la consulta.
	if t, ok := f.q.(*tableroFalso); ok && t.choqueAlCerrar {
		return &pgconn.PgError{Code: "23505", ConstraintName: "board_placements_posicion_unica"}
	}
	return nil
}

func montarTab(t *testing.T, q sqlc.Querier) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoTab)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	// EL ALMACÉN SALE DE ACCESOS, así que sin Accesos no hay tablero. Se pone uno de
	// mentira por defecto —con las coordenadas de Santiago de verdad, para que los
	// kilómetros de las pruebas se puedan comparar con un mapa— y se respeta el que la
	// prueba haya puesto antes con `conAccesos`.
	if _, esElDeVerdad := Accesos.(*accesosHTTP); esElDeVerdad {
		conAccesos(t, almacenesDelTablero())
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteTab{q: q}, reg),
		auth.NuevoVerificador([]byte(secretoTab)),
		nil)
	// El lector de Ventra es un campo del servidor, así que se lo pone el montador con lo
	// que haya dejado `conVentra`. Sin doble queda nil, que es el caso de «no configurado»
	// y contesta 502.
	s.PonerLectorDeVentra(ventraDePrueba)

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{s.verif.Exigir, s.porteria.Exigir}
	admin := []httpx.Medio{s.verif.Exigir, auth.ExigirAdmin, s.porteria.Exigir}
	s.rutasTablero(rt, sesion, admin)
	s.rutasEspejo(rt, sesion, admin)
	return rt.Handler()
}

// almacenesDelTablero es lo que Accesos contesta en las pruebas del tablero: Santiago con
// su almacén principal y Holguín con el suyo. LAS DOS SUCURSALES, siempre: con una sola
// sembrada, un filtro que mira la tabla equivocada sale verde igual, que es exactamente
// como el fallo del 22/09/2026 llegó a producción.
func almacenesDelTablero() *accesosFalso {
	return &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: "STG", Nombre: "Santiago", Almacenes: []Almacen{
			{Nombre: "Almacén principal", Principal: true, Activo: true,
				Latitud: flotante(20.0247), Longitud: flotante(-75.8219)},
		}},
		{Codigo: "HOL", Nombre: "Holguín", Almacenes: []Almacen{
			{Nombre: "Nave de Holguín", Principal: true, Activo: true,
				Latitud: flotante(20.8872), Longitud: flotante(-76.2631)},
		}},
	}}
}

func tokenTab(t *testing.T, sucursal string) string {
	t.Helper()
	reclamos := map[string]any{
		"sub": "p-logistico", "role": "OPERADOR",
		"exp": time.Now().Add(time.Hour).Unix(),
	}
	if sucursal != "" {
		reclamos["branchId"] = sucursal
	} else {
		reclamos["role"] = "SUPER ADMIN"
	}
	cab := b64Tab(t, map[string]any{"alg": "HS256", "typ": "JWT"})
	cuerpo := b64Tab(t, reclamos)
	mac := hmac.New(sha256.New, []byte(secretoTab))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func b64Tab(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func pedirTab(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	if cuerpo != "" {
		r.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func leerTab(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &m); err != nil {
		t.Fatalf("respuesta ilegible (%d): %s", w.Code, w.Body.String())
	}
	return m
}

// --------------------------------------------------------------------------- pruebas

// LA PRUEBA DE LA REAPLICABILIDAD.
//
// El tablero se usa sin red y sus órdenes suben en lotes que se reintentan. Colocar dos
// veces el mismo pedido en el mismo sitio tiene que dejar EL MISMO TABLERO: ni dos
// tarjetas, ni un error, ni los vecinos corridos una posición en cada reintento.
func TestColocarDosVecesElMismoPedidoEnElMismoSitioNoFalla(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas() // Centro: ped1=1, ped2=2, ped3=3
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	cuerpo := `{"columnaId":"` + colCentro.String() + `","posicion":2}`
	for intento := 1; intento <= 3; intento++ {
		w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped2.String(), jwt, cuerpo)
		if w.Code != http.StatusOK {
			t.Fatalf("intento %d: código %d, cuerpo %s", intento, w.Code, w.Body.String())
		}
	}

	// Una sola tarjeta por pedido: lo sostiene la clave primaria, y el manejador no la
	// puede haber esquivado.
	if len(q.colocadas) != 3 {
		t.Fatalf("hay %d colocaciones y tenían que ser 3: %+v", len(q.colocadas), q.colocadas)
	}
	// Y el tablero está EXACTAMENTE como estaba: reaplicar no corre a nadie de sitio.
	esperado := map[uuid.UUID]colocacion{
		ped1: {colCentro, 1}, ped2: {colCentro, 2}, ped3: {colCentro, 3},
	}
	for ped, quiero := range esperado {
		if q.colocadas[ped] != quiero {
			t.Fatalf("tras tres reintentos, %s quedó en %+v y tenía que estar en %+v",
				ped, q.colocadas[ped], quiero)
		}
	}
}

// Mover de verdad sí cambia el tablero, y cierra el hueco que deja atrás.
func TestMoverUnaTarjetaDeColumnaCierraElHueco(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(), jwt,
		`{"columnaId":"`+colVista.String()+`","posicion":1}`)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if q.colocadas[ped1] != (colocacion{colVista, 1}) {
		t.Fatalf("ped1 quedó en %+v", q.colocadas[ped1])
	}
	// Los que quedaban detrás en Centro suben: sin esto las posiciones se van separando
	// hasta que alguien lee «la parada 47» de una columna de nueve.
	if q.colocadas[ped2] != (colocacion{colCentro, 1}) || q.colocadas[ped3] != (colocacion{colCentro, 2}) {
		t.Fatalf("no se cerró el hueco: ped2=%+v ped3=%+v", q.colocadas[ped2], q.colocadas[ped3])
	}
}

// LA OTRA PRUEBA QUE IMPORTA: la base se niega y la persona recibe algo que entiende.
func TestBorrarColumnaConPedidosDaElErrorClaroYNoUn500(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colCentro.String(), jwt, "")
	if w.Code != http.StatusConflict {
		t.Fatalf("tenía que ser 409 y fue %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if m["error"] != "«Centro» tiene 3 pedidos puestos" {
		t.Fatalf("mensaje %q", m["error"])
	}
	if n, _ := m["pedidos"].(float64); n != 3 {
		t.Fatalf("sin el número, la persona no sabe si vaciar dos o mover ochenta: %v", m["pedidos"])
	}
	if _, sigue := q.columnas[colCentro]; !sigue {
		t.Fatal("la columna se borró igual")
	}
	if len(q.colocadas) != 3 {
		t.Fatal("las tarjetas se perdieron por el camino")
	}
}

// Y si la base se niega DESPUÉS de haber contado cero —alguien colocó una tarjeta entre
// la cuenta y el borrado—, tampoco puede salir un 500 con la jerga de Postgres dentro.
func TestSiLaBaseSeNiegaEnElUltimoMomentoTampocoEs500(t *testing.T) {
	q := nuevoTablero()
	q.borrarFalla = true // 23503 aunque el contador diga cero
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colVacia.String(), jwt, "")
	if w.Code != http.StatusConflict {
		t.Fatalf("tenía que ser 409 y fue %d: %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "23503") || strings.Contains(w.Body.String(), "Error interno") {
		t.Fatalf("salió la jerga del motor: %s", w.Body.String())
	}
}

func TestBorrarColumnaConVaciarDevuelveLasTarjetasASinColocar(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colCentro.String()+"?vaciar=1", jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if len(q.colocadas) != 0 {
		t.Fatalf("quedaron tarjetas puestas: %+v", q.colocadas)
	}
	if _, sigue := q.columnas[colCentro]; sigue {
		t.Fatal("la columna no se borró")
	}
}

func TestBorrarColumnaConDestinoMueveLasTarjetasDetras(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.colocadas[pedRuta] = colocacion{colVista, 1} // ya había una en la de destino
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete,
		"/api/board/columns/"+colCentro.String()+"?destino="+colVista.String(), jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// Detrás de lo que ya había y en su mismo orden relativo.
	if q.colocadas[ped1] != (colocacion{colVista, 2}) ||
		q.colocadas[ped2] != (colocacion{colVista, 3}) ||
		q.colocadas[ped3] != (colocacion{colVista, 4}) {
		t.Fatalf("el orden relativo se perdió: %+v", q.colocadas)
	}
}

// Sin sucursal elegida NO se enseña «todo», que es lo que parecería razonable y sería lo
// peor: ordenaría los pedidos de Holguín por su distancia al almacén de Santiago.
func TestSuperAdminSinSucursalNoVeElTableroDeTodas(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, ""), "")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != msgElijeSucursal {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// Sin almacén con coordenadas NO HAY TABLERO: no se ordena por un punto inventado.
//
// «Sin almacén» es lo que diga ACCESOS, que es donde viven. Antes se miraba `saved_origins`
// y por eso este 409 salía en siete sucursales de ocho teniendo el almacén puesto.
func TestSinAlmacenConCoordenadasEs409(t *testing.T) {
	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: "STG", Nombre: "Santiago", Almacenes: []Almacen{
			// Dado de alta, sin punto. Es un estado normal y no sirve para medir.
			{Nombre: "Central", Principal: true, Activo: true},
		}},
	}})
	h := montarTab(t, nuevoTablero())

	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != "Santiago no tiene ningún almacén con coordenadas" {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// EL FALLO DEL 22/09/2026, CON DOS SUCURSALES SEMBRADAS.
//
// Cada sucursal mide desde SU almacén, el de Accesos, el mismo que enseña la pantalla de
// Almacenes y el mismo que cuenta el Panel. Con una sola sucursal sembrada esto sale verde
// aunque el origen salga de la tabla equivocada — que es como llegó a producción: La
// Habana, la única con un `saved_origins`, tenía tablero, y las otras siete recibían «no
// tiene ningún almacén con coordenadas» con el almacén puesto y con su punto.
func TestCadaSucursalMideDesdeSuAlmacenDeAccesos(t *testing.T) {
	h := montarTab(t, nuevoTablero())

	for _, c := range []struct {
		sucursal uuid.UUID
		almacen  string
		lat      float64
	}{
		{sucStg, "Almacén principal", 20.0247},
		{sucHol, "Nave de Holguín", 20.8872},
	} {
		w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, c.sucursal.String()), "")
		if w.Code != http.StatusOK {
			t.Fatalf("sucursal %s: código %d — %s", c.almacen, w.Code, w.Body.String())
		}
		alm, _ := leerTab(t, w)["almacen"].(map[string]any)
		if alm["nombre"] != c.almacen || alm["lat"] != c.lat {
			t.Fatalf("el tablero midió desde %v y tenía que medir desde %q (%v)",
				alm, c.almacen, c.lat)
		}
	}
}

// LA REGLA ES LA MISMA FUNCIÓN QUE LA DE LA COTIZACIÓN, no una copia.
//
// `cotizar.ElegirAlmacen` es quien decide desde dónde se mide el domicilio que se le cobra
// al cliente. Si el tablero eligiera otro, ordenaría por una distancia y se cobraría por
// otra, y ninguna pantalla lo desmentiría: sale una lista con sus kilómetros y todo.
//
// El principal va EL ÚLTIMO de la lista a propósito: quien coja «el primero» pasa las otras
// pruebas y falla ésta.
func TestElTableroYLaCotizacionEligenElMismoAlmacen(t *testing.T) {
	deAccesos := []Almacen{
		{Nombre: "Patio", Activo: true, Latitud: flotante(20.1), Longitud: flotante(-75.9)},
		{Nombre: "Central", Principal: true, Activo: true,
			Latitud: flotante(20.0247), Longitud: flotante(-75.8219)},
	}
	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: "STG", Nombre: "Santiago", Almacenes: deAccesos},
	}})
	h := montarTab(t, nuevoTablero())

	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	esperado := cotizar.ElegirAlmacen(almacenesConPunto(deAccesos))
	alm, _ := leerTab(t, w)["almacen"].(map[string]any)
	if alm["nombre"] != esperado.Nombre || alm["lat"] != *esperado.Latitud {
		t.Fatalf("el tablero mide desde %v y la cotización desde %q (%v): son el mismo dato",
			alm, esperado.Nombre, *esperado.Latitud)
	}
}

// (0,0) ES EL GOLFO DE GUINEA, no Santiago. Un almacén así no tiene coordenadas: las tiene
// sin poner, y medir desde ahí pone el pedido más lejano el primero sin que nada falle.
func TestUnAlmacenEnCeroCeroNoEsUnPunto(t *testing.T) {
	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: "STG", Nombre: "Santiago", Almacenes: []Almacen{
			{Nombre: "Central", Principal: true, Activo: true,
				Latitud: flotante(0), Longitud: flotante(0)},
		}},
	}})
	h := montarTab(t, nuevoTablero())

	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// ACCESOS CAÍDO NO ES «NO TIENES ALMACÉN».
//
// Decirle al logístico que su sucursal no tiene almacén cuando lo que pasa es que Accesos
// no contesta le manda a arreglar algo que no está roto, y el mensaje que vería es
// creíble. Se dice quién no contestó.
func TestSiAccesosNoContestaElTableroNoAcusaALaSucursal(t *testing.T) {
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})
	h := montarTab(t, nuevoTablero())

	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusBadGateway {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if msg, _ := leerTab(t, w)["error"].(string); !strings.Contains(msg, "Accesos") {
		t.Fatalf("mensaje %q: tiene que decir quién no contestó", msg)
	}
}

// Un pedido que ya va en un camión no se coloca, y se dice POR QUÉ: es un 409 que la
// persona puede arreglar, no un 404 que no explica nada.
func TestColocarUnPedidoQueYaVaEnUnaRutaEs409(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+pedRuta.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colCentro.String()+`","posicion":1}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != msgYaVaEnUnaRuta {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// Un pedido de otra sucursal es 404 y NO se dice que existe: decirlo ya es contar algo.
func TestColocarUnPedidoDeOtraSucursalEs404(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+pedHol.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colCentro.String()+`","posicion":1}`)
	if w.Code != http.StatusNotFound {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "Holguín") {
		t.Fatalf("la respuesta cuenta de más: %s", w.Body.String())
	}
}

// Quitar dos veces lo que ya no está no es un error: un lote que se reintenta no puede
// empezar a fallar por eso.
func TestQuitarDosVecesNoFalla(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	for i := 0; i < 2; i++ {
		w := pedirTab(t, h, http.MethodDelete, "/api/board/placements/"+ped2.String(), jwt, "")
		if w.Code != http.StatusOK {
			t.Fatalf("vuelta %d: código %d (%s)", i, w.Code, w.Body.String())
		}
	}
	if _, sigue := q.colocadas[ped2]; sigue {
		t.Fatal("ped2 sigue puesto")
	}
	if q.colocadas[ped3] != (colocacion{colCentro, 2}) {
		t.Fatalf("el hueco se cerró dos veces: ped3=%+v", q.colocadas[ped3])
	}
}

// La mitad izquierda sale ordenada por cercanía al almacén, que es el encargo entero.
func TestLosSinColocarSalenPorCercania(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board/unplaced", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	lista, _ := m["pedidos"].([]any)
	if len(lista) < 3 {
		t.Fatalf("faltan pedidos: %s", w.Body.String())
	}
	anterior := -1.0
	for _, cruda := range lista {
		p := cruda.(map[string]any)
		km := p["kmAlAlmacen"].(float64)
		if km < anterior {
			t.Fatalf("la lista no va del más cerca al más lejos: %s", w.Body.String())
		}
		anterior = km
	}
	// El pedido que ya va en una ruta no está: el listón es el mismo del armador.
	if strings.Contains(w.Body.String(), "Ya salió") {
		t.Fatalf("salió un pedido que ya va en un camión: %s", w.Body.String())
	}
	// Y dos pedidos del mismo cliente son DOS tarjetas, marcadas, no una fundida.
	for _, cruda := range lista {
		p := cruda.(map[string]any)
		if p["customerName"] == "Ana" {
			if n, _ := p["mismoCliente"].(float64); n != 2 {
				t.Fatalf("no se marcó «2 pedidos de este cliente hoy»: %v", p["mismoCliente"])
			}
		}
	}
}

// El tablero entero en UNA ida y vuelta, y con la hora de la bajada dentro.
func TestElTableroTraeTodoDeUnaVez(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	for _, clave := range []string{"sucursal", "almacen", "columnas", "colocados", "avisos", "sinColocar", "vistoAt"} {
		if _, hay := m[clave]; !hay {
			t.Fatalf("falta «%s» en el tablero: %s", clave, w.Body.String())
		}
	}
	if len(m["columnas"].([]any)) != 3 {
		t.Fatalf("columnas: %s", w.Body.String())
	}
	if len(m["colocados"].([]any)) != 3 {
		t.Fatalf("colocados: %s", w.Body.String())
	}
}

// Dos columnas con el mismo nombre en el mismo tablero son dos camiones al mismo barrio.
func TestDosColumnasConElMismoNombreEs409(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt, `{"nombre":"centro"}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != "Ya hay una columna «centro» en este tablero" {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

func TestCrearColumnaVaAlFinal(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)
	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", tokenTab(t, sucStg.String()),
		`{"nombre":"Reparto Norte"}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if n, _ := leerTab(t, w)["posicion"].(float64); n != 4 {
		t.Fatalf("la columna nueva no fue al final: %s", w.Body.String())
	}
}

// Sin token no se llega al tablero de nadie.
func TestElTableroExigeSesion(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board", "", "")
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d", w.Code)
	}
	if strings.TrimSpace(w.Body.String()) != `{"error":"Unauthorized"}` {
		t.Fatalf("cuerpo %q", w.Body.String())
	}
}

// El alcance por HTTP: Santiago no ve el tablero de Holguín ni pidiéndolo por `branchId`.
func TestSantiagoNoLlegaAlTableroDeHolguin(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board?branchId="+sucHol.String(),
		tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusNotFound {
		t.Fatalf("tenía que ser 404 y fue %d: %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------------- armar ruta

func (q *tableroFalso) PedidosDeColumnaParaArmarRuta(_ context.Context, arg sqlc.PedidosDeColumnaParaArmarRutaParams) ([]sqlc.PedidosDeColumnaParaArmarRutaRow, error) {
	if !q.enAlcance(arg.ColumnaID, arg.Sucursal) {
		return nil, nil
	}
	var salida []sqlc.PedidosDeColumnaParaArmarRutaRow
	for ped, c := range q.colocadas {
		if c.columna != arg.ColumnaID {
			continue
		}
		p := q.pedidos[ped]
		// Las condiciones del SQL: sin ruta y con coordenadas. `factura_estado` NO corta
		// aquí, corta el manejador, para poder nombrar cuál falla y por qué.
		if p.ruta != nil || !p.tieneCoordenadas() {
			continue
		}
		lat, lng := p.lat, p.lng
		domicilio, costo := p.domicilioYCosto()
		fila := sqlc.PedidosDeColumnaParaArmarRutaRow{
			ID: p.id, CustomerName: p.nombre, Weight: p.peso,
			EndLat: &lat, EndLng: &lng, FacturaEstado: p.factura, Posicion: c.posicion,
			FacturaDomicilio: domicilio, PedidoCosto: costo,
			// Como en el SQL: `delivered_at` y `resultado` salen como DATO y no
			// filtran aquí. Quien corta y nombra la tarjeta es `armarRutaDeColumna`.
			DeliveredAt: p.entregadoEn(), Resultado: p.suResultado(),
		}
		if p.folio != "" {
			folio := p.folio
			fila.OperationNumber = &folio
		}
		salida = append(salida, fila)
	}
	sort.Slice(salida, func(i, j int) bool { return salida[i].Posicion < salida[j].Posicion })
	return salida, nil
}

func (q *tableroFalso) ContarRutasDelDia(context.Context, string) (int64, error) { return 4, nil }

func (q *tableroFalso) CrearRuta(_ context.Context, arg sqlc.CrearRutaParams) (sqlc.CrearRutaRow, error) {
	q.rutaCreada = &arg
	return sqlc.CrearRutaRow{
		ID: rutaNueva, Name: arg.Name, RouteCode: arg.RouteCode,
		Status: sqlc.RouteStatusPlanned, BranchID: arg.BranchID, VehicleID: arg.VehicleID,
	}, nil
}

func (q *tableroFalso) EngancharPedidoARuta(_ context.Context, arg sqlc.EngancharPedidoARutaParams) (int64, error) {
	p, ok := q.pedidos[arg.PedidoID]
	if !ok || p.ruta != nil || arg.PedidoID == q.seLoLlevan {
		return 0, nil // se lo llevaron entre medias
	}
	ruta := uuid.UUID(arg.RutaID.Bytes)
	p.ruta = &ruta
	q.pedidos[arg.PedidoID] = p
	q.enganchados = append(q.enganchados, arg.PedidoID)
	return 1, nil
}

func (q *tableroFalso) FijarTotalesDeRuta(_ context.Context, arg sqlc.FijarTotalesDeRutaParams) (sqlc.FijarTotalesDeRutaRow, error) {
	q.totales = &arg
	return sqlc.FijarTotalesDeRutaRow{ID: arg.ID}, nil
}

func (q *tableroFalso) QuitarDelTableroLosDeRuta(_ context.Context, arg sqlc.QuitarDelTableroLosDeRutaParams) (int64, error) {
	var n int64
	for ped, c := range q.colocadas {
		if !q.enAlcance(c.columna, arg.Sucursal) {
			continue
		}
		if p := q.pedidos[ped]; p.ruta != nil && [16]byte(*p.ruta) == arg.RutaID.Bytes {
			delete(q.colocadas, ped)
			n++
		}
	}
	return n, nil
}

// De una columna sale una ruta, la columna se queda vacía y la columna SIGUE EXISTIENDO:
// el distrito sigue ahí mañana; lo que se vacía es lo que llevaba dentro hoy.
func TestArmarLaRutaDeUnaColumnaVaciaSusTarjetasYDejaLaColumna(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["paradas"].(float64); n != 3 {
		t.Fatalf("paradas %v: %s", m["paradas"], w.Body.String())
	}
	if peso, _ := m["totalWeight"].(float64); peso != 80 {
		t.Fatalf("peso %v", m["totalWeight"])
	}
	if len(q.colocadas) != 0 {
		t.Fatalf("las tarjetas siguen puestas: %+v", q.colocadas)
	}
	if _, sigue := q.columnas[colCentro]; !sigue {
		t.Fatal("se borró la columna: el distrito sigue existiendo mañana")
	}
	// Se RESPETA el orden del logístico: él conoce las calles de su distrito.
	if len(q.enganchados) != 3 || q.enganchados[0] != ped1 || q.enganchados[2] != ped3 {
		t.Fatalf("no se respetó el orden puesto: %v", q.enganchados)
	}
	// Y la distancia es el CIRCUITO CERRADO: el camión vuelve.
	if q.totales == nil || q.totales.TotalDistance <= 0 {
		t.Fatalf("totales: %+v", q.totales)
	}
	if *q.rutaCreada.RouteCode != "RT-"+time.Now().Format("20060102")+"-005" {
		t.Fatalf("código de ruta %q", *q.rutaCreada.RouteCode)
	}
}

// Los que no cuadran con la factura se descartan NOMBRÁNDOLOS. Una columna de tres que
// produce una ruta de dos sin explicación es la manera más rápida de que el logístico
// deje de fiarse del tablero.
func TestLosQueNoCuadranConLaFacturaSeCaenConNombreYMotivo(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	// A ped2 nadie lo ha cotejado: NULL no es «cuadra». Con un NULL colado se armó una
	// ruta sin facturar el 2/09.
	p := q.pedidos[ped2]
	p.factura = nil
	q.pedidos[ped2] = p
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	desc := m["descartados"].([]any)
	if len(desc) != 1 {
		t.Fatalf("descartados: %s", w.Body.String())
	}
	if d := desc[0].(map[string]any); d["motivo"] != "sin cotejar" || d["customerName"] != "Beto" {
		t.Fatalf("no se dice quién falla ni por qué: %v", d)
	}
}

// Si no queda ninguno repartible NO se crea una ruta vacía, y se dice por qué se cayó
// cada uno.
func TestArmarUnaColumnaSinNadaRepartibleEs409(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	for _, id := range []uuid.UUID{ped1, ped2, ped3} {
		p := q.pedidos[id]
		sin := sqlc.FacturaEstadoSinFactura
		p.factura = &sin
		q.pedidos[id] = p
	}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if m["error"] != msgColumnaSinNada {
		t.Fatalf("mensaje %q", m["error"])
	}
	if len(m["descartados"].([]any)) != 3 {
		t.Fatalf("faltan los motivos: %s", w.Body.String())
	}
	if q.rutaCreada != nil {
		t.Fatal("se creó una ruta vacía")
	}
}

// El exceso de peso AVISA en el tablero pero al ARMAR ya no: lo que no cabe, no sube.
func TestAlArmarSeComprubaLaCapacidadDelCamion(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 50 // los tres pesan 80
	c := q.columnas[colCentro]
	c.VehicleID = pgtype.UUID{Bytes: [16]byte(uuid.New()), Valid: true}
	q.columnas[colCentro] = c
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "supera la capacidad del vehículo") {
		t.Fatalf("mensaje %q", w.Body.String())
	}
	if len(q.colocadas) != 3 {
		t.Fatal("se vació la columna igual")
	}
}

// Reordenar el tablero entero: llega la lista de ids en el orden nuevo.
func TestReordenarElTableroEntero(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)
	cuerpo := `{"ids":["` + colVacia.String() + `","` + colCentro.String() + `","` + colVista.String() + `"]}`

	w := pedirTab(t, h, http.MethodPut, "/api/board/columns/orden", tokenTab(t, sucStg.String()), cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if n, _ := leerTab(t, w)["reordenadas"].(float64); n != 3 {
		t.Fatalf("reordenadas %v: %s", n, w.Body.String())
	}
	if q.columnas[colVacia].Posicion != 1 || q.columnas[colVista].Posicion != 3 {
		t.Fatalf("no se reordenó: %+v", q.columnas)
	}
}

// Y por PUT a una columna suelta no se hace nada: renombrar es PATCH.
func TestPutAUnaColumnaSueltaEs405(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodPut, "/api/board/columns/"+colCentro.String(),
		tokenTab(t, sucStg.String()), `{"nombre":"Otro"}`)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// SUBIR DOS VECES LA MISMA ZONA NO CREA DOS. El aparato pone el id.
//
// Es lo que convierte «¿llegó o no llegó?» —la pregunta que no tiene respuesta cuando la
// red se cae justo después de que el servidor escriba— en una pregunta que no hace falta
// hacer. El teléfono genera un UUIDv7 al crear la zona, aunque esté sin señal, y lo manda;
// si no le llega la respuesta, reintenta con el mismo id y entra una sola vez.
//
// Jose, 16/09/2026: «así no tendríamos problema nunca poniéndonos offline y online, los id
// nunca chocarían».
func TestSubirDosVecesLaMismaZonaNoCreaDos(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	// El id que pone el aparato. v7: la versión va en el tercer grupo.
	id := "018f2c7e-0000-7000-8000-000000000001"
	cuerpo := `{"id":"` + id + `","nombre":"Reparto Norte"}`

	primera := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt, cuerpo)
	if primera.Code != http.StatusCreated {
		t.Fatalf("la primera vez: código %d — %s", primera.Code, primera.Body.String())
	}

	// La segunda es el REINTENTO: la misma petición, palabra por palabra.
	segunda := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt, cuerpo)
	if segunda.Code == http.StatusConflict {
		t.Fatalf("el reintento chocó consigo mismo (409): el aparato no puede saber si "+
			"la primera llegó, así que reintentar TIENE que ser seguro — %s",
			segunda.Body.String())
	}
	if segunda.Code >= 400 {
		t.Fatalf("el reintento falló con %d: %s", segunda.Code, segunda.Body.String())
	}

	if len(q.creadas) != 1 {
		t.Errorf("se crearon %d zonas y tenía que ser UNA: %v", len(q.creadas), q.creadas)
	}
	// Y devuelve la misma, no otra: las colocaciones que van detrás nombran ese id.
	var a, b ColumnaSalida
	if err := json.Unmarshal(primera.Body.Bytes(), &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(segunda.Body.Bytes(), &b); err != nil {
		t.Fatal(err)
	}
	if a.ID.String() != id || b.ID != a.ID {
		t.Errorf("los ids no cuadran: pedido %s, primera %s, segunda %s", id, a.ID, b.ID)
	}
}

// Y un id que NO es un uuid se rechaza, en vez de entrar a ciegas.
//
// Un `local-…` de una versión anterior del aparato acabaría metiendo en la base un id que
// ningún otro aparato podría volver a nombrar.
func TestUnIdQueNoEsUuidSeRechaza(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt,
		`{"id":"local-abc123","nombre":"Vista"}`)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
	}
}

// El id de la zona de OTRA sucursal no la devuelve: la rama del reintento va acotada.
//
// Sin el `branch_id` en esa rama, mandar un id ajeno sería una forma de leer lo que no es
// de uno — la regla 1 de la casa, por la puerta de atrás.
func TestElIdDeOtraSucursalNoDevuelveSuZona(t *testing.T) {
	q := nuevoTablero()
	ajena := uuid.New()
	q.columnas[ajena] = sqlc.BoardColumn{
		ID: ajena, BranchID: holDePanel, Nombre: "La de Holguín", Posicion: 1,
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt,
		`{"id":"`+ajena.String()+`","nombre":"Vista"}`)

	var salida ColumnaSalida
	if w.Code < 400 {
		if err := json.Unmarshal(w.Body.Bytes(), &salida); err == nil &&
			salida.Nombre == "La de Holguín" {
			t.Fatalf("devolvió la zona de otra sucursal: %s", w.Body.String())
		}
	}
	if salida.BranchID == holDePanel {
		t.Fatalf("la zona devuelta es de Holguín: %s", w.Body.String())
	}
}

// EL CHOQUE DE POSICIÓN NO SE CONTESTA COMO SI FUERA EL DEL NOMBRE.
//
// `board_columns` tiene DOS únicas. La del nombre dice algo que una persona puede
// arreglar: «ya hay una columna “Vista Alegre”». La de la posición
// —`board_columns_posicion_unica`, `DEFERRABLE INITIALLY DEFERRED`— salta al CERRAR la
// transacción cuando dos aparatos suben a la vez: los dos calcularon el mismo
// `max(posicion)+1`. Eso no va del nombre y no lo arregla nadie renombrando.
//
// Con un `23505` a secas, ese choque se contestaba «Ya hay una columna “X” en este
// tablero» —falso— y el apunte quedaba muerto en la bandeja de rechazos con un motivo que
// no explica nada. Se vuelve más probable según más se trabaje sin señal: las colas se
// vacían de golpe cuando vuelve la red.
func TestElChoqueDePosicionNoSeConfundeConElDelNombre(t *testing.T) {
	q := nuevoTablero()
	q.choquePosicion = true
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt,
		`{"nombre":"Reparto Norte"}`)

	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	cuerpo := w.Body.String()
	if contieneDeInforme(cuerpo, "Ya hay una columna") {
		t.Errorf("un choque de POSICIÓN se contestó como si fuera de nombre: %s\n"+
			"nadie lo arregla renombrando, y el apunte queda muerto en la bandeja "+
			"con un motivo que no explica nada", cuerpo)
	}
	if !contieneDeInforme(cuerpo, "Vuelve a intentarlo") {
		t.Errorf("no se dice que se reintente, que es lo único que hay que hacer: %s",
			cuerpo)
	}
}
