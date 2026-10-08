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
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
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
// Y esta pantalla es de las que MÁS falta le hacía: no vive de la base local, pide
// `GET /api/vehicles` a la red. El ciclo de sincronización no la repinta, así que sin este
// aviso lo único que la actualizaba era volver a entrar.
//
// # ÉSTE VA ACOTADO A SU SUCURSAL, y el de los TIPOS no — 29/09/2026
//
// Hasta hoy los dos ficheros compartían este gancho y el gancho era GLOBAL, así que dar de
// alta un camión en Camagüey mandaba a las otras SIETE pantallas de Vehículos a pedir otra
// vez `GET /api/vehicles` **y** `GET /api/settings`, por la conexión de allá, para pintar
// exactamente lo mismo. Jose: «el aviso por sucursales, ese evento debe de salir de su
// sucursal, no puede dar una bajada a las otras 7».
//
// `vehicles` TIENE `branch_id` y todos los manejadores de este fichero pasan por
// `acotado()`, así que el alcance de quien escribe es el techo de lo que pudo cambiar: un
// camión tocado desde Camagüey no puede ser de Holguín. Por eso este gancho se acota.
//
// `vehicle_types` **no tiene columna de sucursal ninguna** —es un catálogo de toda la
// empresa—, así que `tipos_vehiculo.go` tiene el SUYO, `avisarCambioDeTiposDeVehiculo`, y
// ése sigue siendo de las ocho. Publican el MISMO tipo de aviso (`vehiculos`), porque la
// pantalla es la misma y enseña las dos cosas; lo que cambia es a quién le llega.
//
// # Y DESDE EL 01/10/2026 LA SUCURSAL SALE DE LA FILA, NO DEL ALCANCE
//
// «El alcance de quien escribe es el techo de lo que pudo cambiar» es verdad y **no bastaba**:
// el techo de un SUPER ADMIN son las ocho, así que su alta de un camión seguía saliendo
// pelada y las otras siete seguían bajándose la flota. Ahora la pasa el manejador leída de
// `vehicles.branch_id`, que vale llegue o no la cabecera de sucursal. El porqué entero, en
// `eventos.go` encima del `init()`.
//
// Se pasa con `deLaFilaPg` porque `vehicles.branch_id` admite nulo: un camión sin sucursal es
// un camión COMPARTIDO y su aviso tiene que llegar a las ocho.
var avisarCambioDeVehiculos = func(_ context.Context, _ string) {}

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
	IsActive          bool       `json:"isActive"`
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
			Status: string(f.Status), IsActive: f.IsActive, Notes: f.Notes, BranchID: idOpcional(f.BranchID),
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
		Status: string(f.Status), IsActive: f.IsActive, Notes: f.Notes, BranchID: idOpcional(f.BranchID),
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
	IsActive          httpx.Opcional[bool]    `json:"isActive"`
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
			IsActive:          c.IsActive.Con(true),
			Status:            estado,
			Notes:             aTexto(c.Notes.Con("")),
		})
		return err
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	rastroDeQuien(r, "vehículo creado", "vehiculo", creado.ID, "sucursal", idParaElRegistro(creado.BranchID))
	avisarCambioDeVehiculos(r.Context(), deLaFilaPg(creado.BranchID))
	httpx.JSON(w, r, http.StatusCreated, deVehiculo(creado, c.Type.Con(TipoPorDefecto)))
}

// msgVehiculoCompartido es el 403 de modificar, dar de baja o borrar un camión COMPARTIDO
// (`branch_id` NULL) sin ser de los roles que ven todas las sucursales.
const msgVehiculoCompartido = "Este vehículo es compartido por todas las sucursales: " +
	"sólo un SUPER ADMIN o un DESARROLLADOR puede modificarlo, darlo de baja o eliminarlo."

// puedeTocarElCamion: un camión propio lo toca quien lo ve (el alcance ya lo filtró); uno
// COMPARTIDO sólo quien ve todas las sucursales (`VeTodasLasSucursales`).
//
// POR QUÉ — 08/10/2026 (auditoría de la 1.0.28). El alcance deja VER los compartidos a
// todas las sucursales (para eso están: ofrecerlos al armar una ruta), y eso mismo los hacía
// ESCRIBIBLES por todas: el operador de Camagüey podía darle de baja, cambiarle la capacidad
// o borrar el camión que usan las otras siete, y a ellas les desaparecía de la lista sin un
// error. Ver y usar es de todos; cambiarlo o quitarlo es de quien administra todas.
//
// Se pregunta por el ROL (`VeTodasLasSucursales`) y no por `a.Todas()`: un SUPER ADMIN que
// está mirando una sola sucursal con el selector tiene alcance acotado y sigue siendo quien
// administra los compartidos.
func puedeTocarElCamion(r *http.Request, sucursalDelCamion pgtype.UUID) bool {
	if sucursalDelCamion.Valid {
		return true
	}
	u := auth.De(r)
	return u != nil && alcance.VeTodasLasSucursales(u)
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
	if !puedeTocarElCamion(r, antes.BranchID) {
		httpx.Error(w, r, http.StatusForbidden, msgVehiculoCompartido)
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
		IsActive:   c.IsActive.Puntero(),
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
			// La ruta que se cerró es de este camión, así que es de su misma sucursal: un
			// camión de Camagüey no puede estar en una ruta de Holguín (lo cierra
			// `CompletarRutasDeVehiculo`, que va acotado).
			avisarCambioDeRutas(r.Context(), deLaFilaPg(actualizado.BranchID))
		}
	}
	rastroDeQuien(r, "vehículo editado", "vehiculo", id, "sucursal", idParaElRegistro(actualizado.BranchID),
		"activo", actualizado.IsActive, "estado", string(actualizado.Status))
	avisarCambioDeVehiculos(r.Context(), deLaFilaPg(actualizado.BranchID))
	httpx.JSON(w, r, http.StatusOK, deVehiculo(actualizado, nombreTipo))
}

// errNoEstaba corta la transacción del borrado cuando el vehículo no es de esta sucursal
// o no existe. Va como error y no como bandera porque tiene que DESHACER lo ya
// desasociado: si no, un intento contra un id ajeno dejaría rutas y pedidos sueltos.
var errNoEstaba = errors.New("vehículo no encontrado en el alcance")
var errVehiculoConRutas = errors.New("vehículo con rutas históricas")

// msgVehiculoConRutas es el 409 de borrar un camión con rutas, y sale por DOS caminos: la
// comprobación de antes de la transacción y la carrera de dentro. Es UN literal para que no
// puedan diverger. Dice «Márcalo como inactivo» y no «Ponlo en mantenimiento»: el
// mantenimiento es un estado pasajero (`status`) que no impide asignarlo a una ruta nueva,
// y lo que Amado pidió (incidencia 4) es el estado activo/inactivo (`isActive`).
const msgVehiculoConRutas = "No se puede eliminar este vehículo porque tiene rutas asociadas, incluso históricas. " +
	"Márcalo como inactivo para impedir que se use en nuevas rutas."

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
	// Las rutas históricas deben seguir apuntando al vehículo. Si tiene alguna, se
	// conserva y se deja de usar marcándolo INACTIVO (`isActive: false`); no se borran sus
	// referencias para poder eliminar la fila.
	actual, err := a.ObtenerVehiculo(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if !puedeTocarElCamion(r, actual.BranchID) {
		httpx.Error(w, r, http.StatusForbidden, msgVehiculoCompartido)
		return
	}
	if actual.Rutas > 0 {
		httpx.Error(w, r, http.StatusConflict,
			msgVehiculoConRutas)
		return
	}
	// LA SUCURSAL DEL CAMIÓN QUE SE VA, para los tres avisos. La pone el propio DELETE
	// (`BorrarVehiculo` devuelve `branch_id`): cuando se avisa, la fila ya no está, así que
	// o la trae el borrado o no la trae nadie. Un camión compartido viene con nulo y entonces
	// el aviso sale a las ocho, que es lo correcto.
	var sucursalDelCamion pgtype.UUID
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		// Repetir la guarda dentro de la transacción antes de borrar order_vehicles. Una ruta
		// pudo aparecer después de la comprobación exterior; si ya hay historial, salimos sin
		// tocar las asignaciones. BorrarVehiculo vuelve a comprobarlo en el propio DELETE.
		actual, err := tx.ObtenerVehiculo(r.Context(), id)
		if errors.Is(err, pgx.ErrNoRows) {
			return errNoEstaba
		}
		if err != nil {
			return err
		}
		if actual.Rutas > 0 {
			return errVehiculoConRutas
		}
		if _, err := tx.BorrarAsignacionesDeVehiculo(r.Context(), id); err != nil {
			return err
		}
		suc, err := tx.BorrarVehiculo(r.Context(), id)
		if errors.Is(err, pgx.ErrNoRows) {
			// Puede ser que una ruta se haya asociado después de la comprobación inicial.
			// Distinguirlo del 404 sin permitir que el borrado rompa su historial.
			actual, consultaErr := tx.ObtenerVehiculo(r.Context(), id)
			if consultaErr == nil && actual.Rutas > 0 {
				return errVehiculoConRutas
			}
			return errNoEstaba
		}
		if err != nil {
			return err
		}
		sucursalDelCamion = suc
		return nil
	})
	if errors.Is(err, errNoEstaba) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if errors.Is(err, errVehiculoConRutas) {
		httpx.Error(w, r, http.StatusConflict,
			msgVehiculoConRutas)
		return
	}
	// LA CARRERA QUE LAS DOS GUARDAS DE ARRIBA NO CIERRAN — 08/10/2026. Entre la comprobación
	// de `Rutas` y el DELETE otra petición puede crear una ruta con este camión: el `NOT
	// EXISTS` de `BorrarVehiculo` va en la misma sentencia, pero con dos transacciones a la vez
	// (READ COMMITTED) el INSERT de la ruta llega después de que el DELETE ya miró, y la clave
	// ajena `routes.vehicle_id` lo rechaza con un 23503. Eso es EXACTAMENTE «tiene rutas
	// asociadas», y no un 500 «Error interno» que no le dice a nadie qué hacer.
	if esClaveAjenaViolada(err) {
		httpx.Error(w, r, http.StatusConflict, msgVehiculoConRutas)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// TRES AVISOS: cambian las listas de flota, rutas y pedidos para quien tenga esas
	// pantallas abiertas mientras se quita el vehículo.
	//
	// Y LAS TRES CON LA SUCURSAL DEL CAMIÓN, no con el alcance de quien lo borró.
	rastroDeQuien(r, "vehículo borrado", "vehiculo", id, "sucursal", idParaElRegistro(sucursalDelCamion))
	avisarCambioDeVehiculos(r.Context(), deLaFilaPg(sucursalDelCamion))
	avisarCambioDeRutas(r.Context(), deLaFilaPg(sucursalDelCamion))
	avisarCambioDePedidos(r.Context(), deLaFilaPg(sucursalDelCamion))
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

func deVehiculo(v sqlc.Vehicle, nombreTipo string) VehiculoSalida {
	return VehiculoSalida{
		ID: v.ID, Name: v.Name, Type: nombreTipo, VehicleTypeID: v.VehicleTypeID,
		Plate: v.Plate, Capacity: v.Capacity, CostoKmUsd: v.CostoKmUsd,
		UsarParaDomicilio: v.UsarParaDomicilio, Status: string(v.Status), IsActive: v.IsActive, Notes: v.Notes,
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
