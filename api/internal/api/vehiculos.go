package api

import (
	"context"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// avisarCambioDeVehiculos publica «algo cambió en la flota» para que las pantallas
// abiertas se enteren sin esperar al temporizador.
//
// Vacío por defecto y lo engancha el fichero del bus (`eventos.go`), igual que el de rutas
// y el del tablero. **No devuelve error y no se mira lo que conteste**: un camión no se
// deja de dar de alta porque el aviso no salga.
//
// LO USAN DOS FICHEROS, éste y `tipos_vehiculo.go`, y es a propósito: la pantalla de
// Vehículos enseña las dos cosas —la flota y el desplegable de tipos— en la misma vista, y
// un tipo nuevo que no aparece en el desplegable se ve igual de roto que un camión que no
// aparece en la lista.
//
// Y esta pantalla es de las que MÁS falta le hacía: no vive de la base local, pide
// `GET /api/vehicles` a la red. El ciclo de sincronización no la repinta, así que sin este
// aviso lo único que la actualizaba era volver a entrar.
var avisarCambioDeVehiculos = func(_ context.Context) {}

// TipoPorDefecto: el contrato dice `type || 'truck'`. El nombre se traduce al id del
// catálogo `vehicle_types`, que es la tabla que antes no existía.
const TipoPorDefecto = "truck"

// CapacidadPorDefecto y EstadoPorDefecto: el `capacity ?? 1000` y el
// `status || 'available'` del contrato.
const CapacidadPorDefecto = 1000.0

var EstadoPorDefecto = sqlc.VehicleStatusAvailable

// ---------------------------------------------------------------------------
// Los dos números de un camión, y por qué se comprueban
// ---------------------------------------------------------------------------
//
// El contrato de delivery no los valida: `capacity ?? 1000` y `costoKmUsd` tal cual. Nos
// separamos de él a propósito (CLAUDE.md §2, «el patrón se sigue SALVO donde se
// equivoca») porque los dos son números que se usan para decidir y para cobrar, y un
// número creíble y equivocado es el fallo que más caro sale en este proyecto.
//
//   - CAPACIDAD. Es el único freno que tiene el armador contra un camión sobrecargado
//     (`pesoTotal > vehiculo.Capacity`). Con capacidad `0` o negativa ese freno deja de
//     medir nada: rechaza TODAS las rutas, incluso la de un solo bulto, y con un mensaje
//     —«Peso total (0.0 kg) supera la capacidad del vehículo (-5 kg)»— que no se puede
//     entender ni arreglar desde la pantalla donde sale. Un camión que no lleva nada no
//     existe: si la capacidad no es positiva, es un campo mal escrito.
//   - COSTO POR KM. Un negativo se lee igual de bien que un positivo y significa que el
//     kilómetro PAGA. Es el mismo caso que el cero que el CLAUDE.md ya manda dejar
//     vacío, un escalón peor. El vacío sigue valiendo y sigue significando «usa el del
//     tipo»; lo que no vale es un número que no se puede cobrar.
//
// Los dos rechazan además NaN e ±Infinity. Por JSON no entran como literales, pero sí como
// `1e308 * algo` en cuanto alguien haga una cuenta con ellos, y un no-finito guardado
// revienta la codificación de TODA respuesta que lo lleve dentro (ver `httpx.JSON`).

const (
	msgCapacidadImposible = "La capacidad del camión tiene que ser un número de kilos mayor que cero, y llegó '%s'"
	msgCostoKmImposible   = "El costo por kilómetro no puede ser negativo, y llegó '%s'. " +
		"Déjalo vacío si todavía no se sabe: un hueco se ve y se rellena."
)

// capacidadValida comprueba los kilos que admite el camión.
func capacidadValida(w http.ResponseWriter, r *http.Request, v httpx.Opcional[float64]) bool {
	if v.Valor == nil { // ausente o null: se usa el de la casa
		return true
	}
	if *v.Valor > 0 && !math.IsInf(*v.Valor, 0) {
		return true
	}
	httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(msgCapacidadImposible,
		strconv.FormatFloat(*v.Valor, 'g', -1, 64)))
	return false
}

// costoKmValido comprueba el costo por km. Vacío SÍ vale: es «usa el del tipo».
func costoKmValido(w http.ResponseWriter, r *http.Request, v httpx.Opcional[float64]) bool {
	if v.Valor == nil {
		return true
	}
	if *v.Valor >= 0 && !math.IsInf(*v.Valor, 0) && !math.IsNaN(*v.Valor) {
		return true
	}
	httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(msgCostoKmImposible,
		strconv.FormatFloat(*v.Valor, 'g', -1, 64)))
	return false
}

type VehiculoSalida struct {
	ID                uuid.UUID  `json:"id"`
	Name              string     `json:"name"`
	Type              string     `json:"type"` // el NOMBRE del tipo, que es lo que el cliente manda y enseña
	VehicleTypeID     uuid.UUID  `json:"vehicleTypeId"`
	Plate             *string    `json:"plate"`
	Capacity          float64    `json:"capacity"`
	CostoKmUsd        *float64   `json:"costoKmUsd"`
	TipoCostoKmUsd    *float64   `json:"tipoCostoKmUsd"`
	UsarParaDomicilio bool       `json:"usarParaDomicilio"`
	Status            string     `json:"status"`
	Notes             *string    `json:"notes"`
	BranchID          *uuid.UUID `json:"branchId"`
	SucursalNombre    *string    `json:"sucursalNombre,omitempty"`
	CreatedAt         *time.Time `json:"createdAt"`
	UpdatedAt         *time.Time `json:"updatedAt"`
	Count             conteoVeh  `json:"_count"`

	// EN QUÉ ANDA ESTE CAMIÓN. Cero o una ruta, la que lo tiene cogido ahora.
	//
	// Jose, 28/09/2026: «si la idea es q salga el vehiculo y ese vehiculo se ponga su
	// estado para q saber como anda ese vehiculo y saber de la flota».
	//
	// Va como LISTA y no como objeto porque es la forma que el aparato ya lee desde el
	// principio (`app/lib/pantallas/vehiculos/datos/vehiculo_api.dart`:
	// `rutas.first`, para la caja azul «Ruta activa»). Esa caja llevaba desde siempre
	// sin salir NUNCA, y no era cosa del aparato: este campo no existía, así que
	// `j['routes']` era siempre nulo. Se sirve con el nombre que él ya espera en vez de
	// inventar otro y tener dos.
	//
	// Y NO SALE DE `vehicles.status`: sale de las rutas abiertas del camión
	// (`RutasAbiertasDeLaFlota`). El porqué está escrito en `db/queries/vehicles.sql`,
	// y es el mismo que ya llevaba `ContarVehiculosEnRuta`: un campo que alguien pone a
	// mano y nadie quita miente a los dos días.
	Routes []RutaDeVehiculoSalida `json:"routes"`
}

// RutaDeVehiculoSalida: la ruta abierta de un camión, lo justo para decir en qué anda.
//
// `status` viaja aunque la caja azul de hoy no lo pinte: `planned` y `in_progress` son dos
// respuestas distintas a «¿está libre?» —una ruta planificada es un camión comprometido
// para mañana, una en curso es un camión que no está— y quien decide eso es la pantalla,
// no esta capa.
type RutaDeVehiculoSalida struct {
	ID           uuid.UUID  `json:"id"`
	RouteCode    *string    `json:"routeCode"`
	Name         *string    `json:"name"`
	Status       string     `json:"status"`
	DeliveryDate *time.Time `json:"deliveryDate"`
}

// rutasPorCamion indexa las rutas abiertas por el id del camión que las lleva.
//
// Una consulta para toda la flota y no una por camión: con ocho camiones la diferencia no
// se nota, pero una consulta por fila dentro de un bucle es cómo se llega a las 200
// consultas por pantalla sin que nadie lo vea venir.
func rutasPorCamion(filas []sqlc.RutasAbiertasDeLaFlotaRow) map[uuid.UUID]RutaDeVehiculoSalida {
	m := make(map[uuid.UUID]RutaDeVehiculoSalida, len(filas))
	for _, f := range filas {
		if !f.VehicleID.Valid {
			continue
		}
		m[uuid.UUID(f.VehicleID.Bytes)] = RutaDeVehiculoSalida{
			ID: f.ID, RouteCode: f.RouteCode, Name: f.Name,
			Status: string(f.Status), DeliveryDate: hora(f.DeliveryDate),
		}
	}
	return m
}

// laSuya: la ruta abierta de este camión, como lista de cero o uno. Nunca `nil`, que en
// JSON sale como `null` y obliga a cada cliente a distinguir dos formas del mismo vacío.
func laSuya(porCamion map[uuid.UUID]RutaDeVehiculoSalida, id uuid.UUID) []RutaDeVehiculoSalida {
	if ruta, hay := porCamion[id]; hay {
		return []RutaDeVehiculoSalida{ruta}
	}
	return []RutaDeVehiculoSalida{}
}

type conteoVeh struct {
	Routes           int64 `json:"routes"`
	Orders           int64 `json:"orders"`
	OrderAssignments int64 `json:"orderAssignments"`
}

// GET /api/vehicles
func (s *Servidor) listarVehiculos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	filas, err := a.ListarVehiculos(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// EN QUÉ ANDA CADA UNO. Si esta consulta falla se cae la lista entera y no se sirve
	// media flota sin estado: «disponible» dicho de un camión que está fuera es
	// exactamente el número creíble y equivocado que aquí sale caro.
	abiertas, err := a.RutasAbiertasDeLaFlota(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porCamion := rutasPorCamion(abiertas)
	salida := make([]VehiculoSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, VehiculoSalida{
			ID: f.ID, Name: f.Name, Type: f.TipoNombre, VehicleTypeID: f.VehicleTypeID,
			Plate: f.Plate, Capacity: f.Capacity, CostoKmUsd: f.CostoKmUsd,
			TipoCostoKmUsd: f.TipoCostoKmUsd, UsarParaDomicilio: f.UsarParaDomicilio,
			Status: string(f.Status), Notes: f.Notes, BranchID: idOpcional(f.BranchID),
			SucursalNombre: f.SucursalNombre,
			CreatedAt:      hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
			Count:  conteoVeh{Routes: f.Rutas, Orders: f.Pedidos, OrderAssignments: f.Asignaciones},
			Routes: laSuya(porCamion, f.ID),
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// GET /api/vehicles/{id}
func (s *Servidor) obtenerVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	f, err := a.ObtenerVehiculo(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	abiertas, err := a.RutasAbiertasDeLaFlota(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, VehiculoSalida{
		ID: f.ID, Name: f.Name, Type: f.TipoNombre, VehicleTypeID: f.VehicleTypeID,
		Plate: f.Plate, Capacity: f.Capacity, CostoKmUsd: f.CostoKmUsd,
		TipoCostoKmUsd: f.TipoCostoKmUsd, UsarParaDomicilio: f.UsarParaDomicilio,
		Status: string(f.Status), Notes: f.Notes, BranchID: idOpcional(f.BranchID),
		CreatedAt: hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
		Count:  conteoVeh{Routes: f.Rutas, Orders: f.Pedidos, OrderAssignments: f.Asignaciones},
		Routes: laSuya(rutasPorCamion(abiertas), f.ID),
	})
}

type cuerpoVehiculo struct {
	Name              httpx.Opcional[string]  `json:"name"`
	Type              httpx.Opcional[string]  `json:"type"`
	Plate             httpx.Opcional[string]  `json:"plate"`
	Capacity          httpx.Opcional[float64] `json:"capacity"`
	Status            httpx.Opcional[string]  `json:"status"`
	Notes             httpx.Opcional[string]  `json:"notes"`
	CostoKmUsd        httpx.Opcional[float64] `json:"costoKmUsd"`
	UsarParaDomicilio httpx.Opcional[bool]    `json:"usarParaDomicilio"`
}

// POST /api/vehicles
func (s *Servidor) crearVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoVehiculo
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	// Literal del contrato, en inglés, y así se queda: está inventariado.
	if c.Name.Con("") == "" {
		httpx.Error(w, r, http.StatusBadRequest, "Vehicle name is required")
		return
	}
	if !capacidadValida(w, r, c.Capacity) || !costoKmValido(w, r, c.CostoKmUsd) {
		return
	}
	tipo, ok := s.tipoPorNombre(w, r, a, c.Type.Con(TipoPorDefecto))
	if !ok {
		return
	}
	estado, ok := estadoValido(w, r, c.Status.Con(string(EstadoPorDefecto)))
	if !ok {
		return
	}
	// `=== true` estricto: un `usarParaDomicilio` ausente o null NO marca el camión de
	// referencia. Marcarlo por descuido cambia el precio de todos los domicilios de esa
	// sucursal, porque el CKK de la fórmula sale de ese vehículo.
	referencia := c.UsarParaDomicilio.Con(false)

	var creado sqlc.Vehicle
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		if referencia {
			// Se desmarca ANTES de insertar: el índice único parcial
			// `vehicles_una_referencia_por_sucursal` rechazaría el INSERT si ya hubiera
			// otro marcado. `uuid.Nil` como excepción porque el nuevo todavía no tiene
			// id — no hay ninguna fila con ese id, así que no excluye a nadie.
			if _, err := tx.DesmarcarReferenciaDeDomicilio(r.Context(), uuid.Nil); err != nil {
				return err
			}
		}
		var err error
		creado, err = tx.CrearVehiculo(r.Context(), sqlc.CrearVehiculoParams{
			Name:              *c.Name.Valor,
			VehicleTypeID:     tipo,
			Plate:             aTexto(c.Plate.Con("")),
			Capacity:          c.Capacity.Con(CapacidadPorDefecto),
			CostoKmUsd:        c.CostoKmUsd.Valor, // vacío = «usa el del tipo», NO cero
			UsarParaDomicilio: referencia,
			Status:            estado,
			Notes:             aTexto(c.Notes.Con("")),
		})
		return err
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeVehiculos(r.Context())
	httpx.JSON(w, r, http.StatusCreated, deVehiculo(creado, c.Type.Con(TipoPorDefecto)))
}

// PATCH /api/vehicles/{id}
func (s *Servidor) actualizarVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	var c cuerpoVehiculo
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	// Los mismos dos números que en el alta, y por lo mismo: un PATCH es la otra puerta a
	// la misma fila. Validar sólo el alta deja el agujero abierto a un botón de distancia.
	if !capacidadValida(w, r, c.Capacity) || !costoKmValido(w, r, c.CostoKmUsd) {
		return
	}

	// Se lee antes para dos cosas: el 404 con el alcance puesto, y el estado ANTERIOR,
	// que hace falta para saber si el camión se acaba de liberar.
	antes, err := a.ObtenerVehiculo(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	arg := sqlc.ActualizarVehiculoParams{
		ID:         id,
		Name:       c.Name.Puntero(),
		TocarPlate: c.Plate.Presente,
		Plate:      c.Plate.Valor,
		Capacity:   c.Capacity.Puntero(),
		TocarCosto: c.CostoKmUsd.Presente,
		CostoKmUsd: c.CostoKmUsd.Valor,
		TocarNotes: c.Notes.Presente,
		Notes:      c.Notes.Valor,
	}
	nombreTipo := antes.TipoNombre
	if c.Type.Presente && c.Type.Valor != nil {
		tipo, ok := s.tipoPorNombre(w, r, a, *c.Type.Valor)
		if !ok {
			return
		}
		arg.VehicleTypeID = pgDe(tipo)
		nombreTipo = *c.Type.Valor
	}
	if c.Status.Presente && c.Status.Valor != nil {
		estado, ok := estadoValido(w, r, *c.Status.Valor)
		if !ok {
			return
		}
		arg.Status = &estado
	}
	if c.UsarParaDomicilio.Presente {
		v := c.UsarParaDomicilio.Con(false) // `=== true` estricto, igual que en el alta
		arg.UsarParaDomicilio = &v
	}

	var actualizado sqlc.Vehicle
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		if arg.UsarParaDomicilio != nil && *arg.UsarParaDomicilio {
			if _, err := tx.DesmarcarReferenciaDeDomicilio(r.Context(), id); err != nil {
				return err
			}
		}
		var err error
		actualizado, err = tx.ActualizarVehiculo(r.Context(), arg)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// DESPUÉS de la transacción, no dentro: liberar el camión cierra su ruta abierta.
	// Es un efecto del cambio de estado, no parte de él — si fallara, el camión tiene
	// que quedar liberado igual, que es lo que pidieron.
	//
	// MANDAR UN CAMIÓN AL TALLER **NO** CIERRA SU RUTA, y es a propósito (28/09/2026).
	// Cerrarla sería dar por repartido lo que no se repartió: una ruta `completed` es la
	// que llegó a su destino, y el cierre es donde se cuadra qué bajó del camión
	// (`CLAUDE.md` §2). Un camión que se rompe a mitad de ruta deja un reparto a medias
	// que alguien tiene que repartirse, no un reparto terminado.
	//
	// Así que `maintenance` con una ruta abierta es una CONTRADICCIÓN que se queda en pie,
	// y la aplicación la dice en la tarjeta del camión con la ruta nombrada
	// (`VehiculoDeLaApi.enTallerConRutaAbierta`) en vez de resolverla por su cuenta. Es la
	// misma decisión que ya estaba tomada para `estadoGuardadoMiente`: lo que no se puede
	// saber desde aquí se enseña, no se adivina.
	if antes.Status == sqlc.VehicleStatusInUse && actualizado.Status == sqlc.VehicleStatusAvailable {
		if n, err := a.CompletarRutasDeVehiculo(r.Context(), id); err != nil {
			httpx.Registro(r).Error("el vehículo quedó libre pero su ruta sigue abierta",
				"vehiculo", id, "err", err)
		} else if n > 0 {
			httpx.Registro(r).Info("rutas cerradas al liberar el vehículo", "vehiculo", id, "rutas", n)
			// La ruta que se acaba de cerrar la está mirando otro en la pantalla de
			// Rutas. Se avisa de LAS DOS cosas porque cambiaron las dos, y cada pantalla
			// vuelve a pedir lo suyo: mandar sólo `vehiculos` dejaría la ruta abierta en
			// la pantalla de al lado hasta el temporizador.
			avisarCambioDeRutas(r.Context())
		}
	}
	avisarCambioDeVehiculos(r.Context())
	httpx.JSON(w, r, http.StatusOK, deVehiculo(actualizado, nombreTipo))
}

// errNoEstaba corta la transacción del borrado cuando el vehículo no es de esta sucursal
// o no existe. Va como error y no como bandera porque tiene que DESHACER lo ya
// desasociado: si no, un intento contra un id ajeno dejaría rutas y pedidos sueltos.
var errNoEstaba = errors.New("vehículo no encontrado en el alcance")

// DELETE /api/vehicles/{id}
func (s *Servidor) borrarVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		// Desasociar primero. El histórico de lo que se repartió NO se borra porque un
		// camión se dé de baja: las rutas y los pedidos se quedan, sin vehículo.
		if _, err := tx.DesvincularVehiculoDeRutas(r.Context(), id); err != nil {
			return err
		}
		if _, err := tx.DesvincularVehiculoDePedidos(r.Context(), id); err != nil {
			return err
		}
		if _, err := tx.BorrarAsignacionesDeVehiculo(r.Context(), id); err != nil {
			return err
		}
		filas, err := tx.BorrarVehiculo(r.Context(), id)
		if err != nil {
			return err
		}
		if filas == 0 {
			return errNoEstaba
		}
		return nil
	})
	if errors.Is(err, errNoEstaba) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// TRES AVISOS, y no es de más: este borrado desvincula el camión de sus rutas y de sus
	// pedidos antes de quitarlo. Las tres listas cambiaron de verdad, y quien tenga Rutas
	// delante vería el camión de una ruta que ya no lo tiene hasta el temporizador.
	avisarCambioDeVehiculos(r.Context())
	avisarCambioDeRutas(r.Context())
	avisarCambioDePedidos(r.Context())
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

func deVehiculo(v sqlc.Vehicle, nombreTipo string) VehiculoSalida {
	return VehiculoSalida{
		ID: v.ID, Name: v.Name, Type: nombreTipo, VehicleTypeID: v.VehicleTypeID,
		Plate: v.Plate, Capacity: v.Capacity, CostoKmUsd: v.CostoKmUsd,
		UsarParaDomicilio: v.UsarParaDomicilio, Status: string(v.Status), Notes: v.Notes,
		BranchID:  idOpcional(v.BranchID),
		CreatedAt: hora(v.CreatedAt), UpdatedAt: hora(v.UpdatedAt),
	}
}

// tipoPorNombre traduce el `type: "truck"` del cuerpo al id del catálogo.
//
// En delivery `type` era texto libre y su catálogo no existía en ninguna parte, así que
// cualquier cosa se guardaba. Ahora hay tabla y clave ajena: un tipo que no está es un
// 400, y eso es lo que hace que el desplegable de la pantalla signifique algo.
func (s *Servidor) tipoPorNombre(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, nombre string) (uuid.UUID, bool) {
	t, err := a.BuscarTipoDeVehiculoPorNombre(r.Context(), nombre)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusBadRequest,
			fmt.Sprintf("No existe el tipo de vehículo '%s'", nombre))
		return uuid.Nil, false
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return uuid.Nil, false
	}
	return t.ID, true
}

// estadoValido comprueba el enum antes de que lo haga Postgres. Dejarlo caer hasta la
// base daría un 500 con la jerga del motor dentro; esto da un 400 que se puede leer.
//
// SON TRES, y `maintenance` entró el 28/09/2026 con la 00013. Hasta ese día el enum de la
// base sólo tenía dos valores y esta función contestaba 400 a cualquier otra cosa: la
// ficha del vehículo ofrecía «En mantenimiento» en un desplegable y **no guardaba nada
// nunca**, con un «no se pudo guardar» que no decía por qué.
//
// Y son tres y no más. `maintenance` es el ÚNICO estado que se guarda porque es el único
// que no se puede deducir —un camión en el taller no tiene ruta, exactamente igual que uno
// libre—; `libre`, `asignado` y `enRuta` salen de las rutas abiertas del camión y no de
// esta columna (`db/queries/vehicles.sql`, `RutasAbiertasDeLaFlota`). Un estado inventado
// sigue siendo un 400 **con su motivo dentro**: «no se pudo guardar» no le dice nada a
// nadie, y el que llega aquí llega por un cliente que manda lo que no debe.
//
// LOS TRES DE AQUÍ Y LOS DEL ENUM SON LA MISMA LISTA, y eso lo ata una prueba y no este
// comentario (`estado_del_camion_test.go`): un comentario no falla, y el CLAUDE.md §3-bis
// lo tiene escrito con el caso de «Sin colocar (722)» encima de una lista de 293. Si
// alguien añade un valor al tipo y se olvida de esta función, la api contesta 400 a algo
// que la base admite; al revés, contesta 500 con la jerga de Postgres dentro.
func estadoValido(w http.ResponseWriter, r *http.Request, v string) (sqlc.VehicleStatus, bool) {
	switch sqlc.VehicleStatus(v) {
	case sqlc.VehicleStatusAvailable, sqlc.VehicleStatusInUse, sqlc.VehicleStatusMaintenance:
		return sqlc.VehicleStatus(v), true
	}
	httpx.Error(w, r, http.StatusBadRequest,
		fmt.Sprintf("Estado de vehículo no válido: '%s'. Sólo 'available', 'in_use' o 'maintenance'", v))
	return "", false
}
