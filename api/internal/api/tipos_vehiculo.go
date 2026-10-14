package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// El catálogo de tipos de vehículo. RECURSO NUEVO, no está en las 35 rutas de delivery.
//
// Allí la pantalla mandaba los tipos dentro de `PUT /api/settings` con la clave
// `tiposVehiculo`, y ese campo NUNCA EXISTIÓ en el esquema: se creaban tipos, se
// guardaban y se perdían sin un solo error. Por eso `Vehicle.type` era un conjunto
// abierto que nadie podía cerrar. Ahora es una tabla, así que tiene sus rutas.
//
// POR SUCURSAL desde la 00018 (Jose, 14/10/2026). Hasta entonces el catálogo era de toda la
// empresa y el costo por km de un tipo —que es el que cotiza el domicilio— se movía en las ocho
// a la vez: el logístico de Santiago editaba «truck» y cambiaba el precio en Holguín. Ahora cada
// sucursal tiene SUS tipos y quien trabaja en una ve y toca sólo los suyos (los de otra
// sucursal y los «de todas» son un 404, igual que un id que no existe). `branch_id` NULO es el
// tipo «de todas»: los cinco de fábrica, que sólo usan los camiones compartidos. Sólo quien no
// tiene sucursal (SUPER ADMIN y DESARROLLADOR en modo «todas») ve todos, y lo que cree allí
// nace «de todas»: para dar de alta un tipo de una sucursal hay que mirar esa sucursal con el
// selector de arriba.
//
// EL NOMBRE SE REPITE ENTRE SUCURSALES y es único DENTRO de cada una (dos índices únicos parciales,
// 00018). Que coincida con el de uno «de todas» NO es un choque: quien tiene sucursal no ve ni puede
// usar los «de todas» —los camiones de su sucursal sólo aceptan tipos de su sucursal—, así que
// negarle el nombre sería esconderle algo por un motivo que no puede ver.

// avisarCambioDeTiposDeVehiculo publica «cambió el catálogo de tipos» A LA SUCURSAL DEL TIPO.
//
// Publica el MISMO tipo de aviso que `avisarCambioDeVehiculos` (`vehiculos`), porque la
// pantalla es la misma: Vehículos enseña la flota y el desplegable de tipos en la misma
// vista, y un tipo nuevo que no aparece en el desplegable se ve igual de roto que un camión
// que no aparece en la lista.
//
// ERA GLOBAL Y YA NO LO ES — 14/10/2026. Con un catálogo único, acotar el aviso al alcance de
// quien lo creó dejaba a las otras siete pantallas de Vehículos sin enterarse de un tipo nuevo, y
// esa pantalla NO vive de la base local, así que el ciclo tampoco la repinta. Con tipos por sucursal
// la cuenta es la contraria: un tipo de Santiago no sale en el desplegable de Holguín, y
// avisarla sería mandarle a pedir `GET /api/vehicles` y `GET /api/vehicle-types` para pintar
// exactamente lo mismo. Por eso el gancho recibe la sucursal DE LA FILA que se escribió
// (`vehicle_types.branch_id`, que la devuelven las propias consultas), igual que el de los camiones.
// Un tipo «de todas» sale con la sucursal vacía y llega a las ocho.
var avisarCambioDeTiposDeVehiculo = func(_ context.Context, _ string) {}

type TipoVehiculoSalida struct {
	ID         uuid.UUID `json:"id"`
	Nombre     string    `json:"nombre"`
	CostoKmUsd *float64  `json:"costoKmUsd"`
	Activo     bool      `json:"activo"`
	Vehiculos  int64     `json:"vehiculos"`
	// SucursalID y Sucursal dicen de quién es el tipo; AMBOS NULOS son «de todas». Quien tiene
	// sucursal sólo recibe la suya; quien ve todas recibe el mismo nombre varias veces y esto
	// es lo único que distingue un «truck» de otro.
	SucursalID *uuid.UUID `json:"sucursalId"`
	Sucursal   *string    `json:"sucursal"`
	CreatedAt  *time.Time `json:"createdAt"`
	UpdatedAt  *time.Time `json:"updatedAt"`
}

// GET /api/vehicle-types?activos=1
//
// Por defecto salen TODOS, activos y retirados: esta ruta la usa la pantalla de
// administración, que tiene que poder ver lo retirado para volver a activarlo. Con
// `activos=1` salen sólo los que se pueden elegir, que es lo que pide el desplegable del
// alta de un camión. Salen los de SU sucursal; quien ve todas, los de todas.
func (s *Servidor) listarTiposDeVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var soloActivos *bool
	if v := r.URL.Query().Get("activos"); v == "1" || v == "true" {
		t := true
		soloActivos = &t
	}
	filas, err := a.ListarTiposDeVehiculo(r.Context(), soloActivos)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]TipoVehiculoSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, TipoVehiculoSalida{
			ID: f.ID, Nombre: f.Nombre, CostoKmUsd: f.CostoKmUsd, Activo: f.Activo,
			Vehiculos: f.Vehiculos, SucursalID: idOpcional(f.BranchID), Sucursal: f.SucursalNombre,
			CreatedAt: hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

type cuerpoTipoVehiculo struct {
	Nombre     httpx.Opcional[string]  `json:"nombre"`
	CostoKmUsd httpx.Opcional[float64] `json:"costoKmUsd"`
	Activo     httpx.Opcional[bool]    `json:"activo"`
}

// POST /api/vehicle-types   (cualquier sesión de Reparto, también LOGISTICO)
func (s *Servidor) crearTipoDeVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoTipoVehiculo
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	nombre := strings.TrimSpace(c.Nombre.Con(""))
	if nombre == "" {
		httpx.Error(w, r, http.StatusBadRequest, "El nombre del tipo es obligatorio")
		return
	}
	// El costo por km del TIPO es el valor por defecto de todos los camiones que lo usen,
	// así que un número imposible aquí se reparte por toda la flota. Misma guarda que en
	// `vehiculos.go`, y a propósito la misma función: dos copias de esta regla acabarían
	// admitiendo cosas distintas por las dos puertas de la misma pantalla.
	if !costoKmValido(w, r, c.CostoKmUsd) {
		return
	}
	// `costo_km_usd` se deja vacío a propósito si no lo mandan: es un valor por defecto
	// para los camiones de ese tipo, y ponerle un número inventado es peor que no
	// tenerlo, porque se cobra igual y nadie lo revisa.
	t, err := a.CrearTipoDeVehiculo(r.Context(), sqlc.CrearTipoDeVehiculoParams{
		Nombre:     nombre,
		CostoKmUsd: c.CostoKmUsd.Valor,
		Activo:     c.Activo.Con(true),
	})
	if err != nil {
		// `nombre` es único DENTRO de la sucursal. Un choque aquí es que el tipo ya está, no un
		// fallo del servidor: con un 500 la pantalla diría "error" y nadie sabría que basta con
		// elegir el que ya existe.
		if esClaveRepetida(err) {
			httpx.Error(w, r, http.StatusConflict, "Ya existe un tipo de vehículo con ese nombre")
			return
		}
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeTiposDeVehiculo(r.Context(), deLaFilaPg(t.BranchID))
	httpx.JSON(w, r, http.StatusCreated, deTipo(t, 0, nombreDeLaSucursal(r, a, t.BranchID)))
}

// PATCH /api/vehicle-types/{id}   (cualquier sesión de Reparto, también LOGISTICO)
func (s *Servidor) actualizarTipoDeVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c cuerpoTipoVehiculo
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	if !costoKmValido(w, r, c.CostoKmUsd) {
		return
	}
	// El nombre, recortado y no vacío: sin esto un PATCH con `"nombre":"  "` dejaba un tipo
	// que no se puede elegir (el POST ya lo rechaza).
	nombre := c.Nombre.Puntero()
	if nombre != nil {
		recortado := strings.TrimSpace(*nombre)
		if recortado == "" {
			httpx.Error(w, r, http.StatusBadRequest, "El nombre del tipo es obligatorio")
			return
		}
		nombre = &recortado
	}
	t, err := a.ActualizarTipoDeVehiculo(r.Context(), sqlc.ActualizarTipoDeVehiculoParams{
		ID:         id,
		Nombre:     nombre,
		TocarCosto: c.CostoKmUsd.Presente,
		CostoKmUsd: c.CostoKmUsd.Valor,
		Activo:     c.Activo.Puntero(),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		// Renombrar a un nombre que ya existe en la sucursal (también el de un RETIRADO, que el
		// cajón ni enseña) choca con la única de `nombre`. Con un 500 la app lo toma por un fallo de
		// red, reintenta 15 s y dice «no se guardó nada»: el mismo choque que el POST ya
		// traducía a 409 y el PATCH no.
		if esClaveRepetida(err) {
			httpx.Error(w, r, http.StatusConflict, "Ya existe un tipo de vehículo con ese nombre")
			return
		}
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeTiposDeVehiculo(r.Context(), deLaFilaPg(t.BranchID))
	httpx.JSON(w, r, http.StatusOK, deTipo(t, 0, nombreDeLaSucursal(r, a, t.BranchID)))
}

// DELETE /api/vehicle-types/{id}   (cualquier sesión de Reparto, también LOGISTICO)
//
// Borrar un tipo que usa algún camión dejaría la clave ajena colgando, y a la fuerza
// dejaría camiones sin tipo: un camión sin tipo es un camión sin costo por km y por tanto
// sin fórmula del domicilio. Así que:
//
//	sin vehículos -> se borra de verdad
//	con vehículos -> se RETIRA (activo = false): deja de ofrecerse y los que ya lo tienen
//	                 siguen funcionando.
//
// La respuesta dice cuál de las dos pasó, porque no son lo mismo y la pantalla tiene que
// poder decirlo.
func (s *Servidor) borrarTipoDeVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	// El borrado comprueba el uso EN LA MISMA SENTENCIA, no con un conteo antes: entre
	// el conteo y el borrado cabe un alta. Sin filas es «no existe / no es de tu sucursal» O
	// «lo usa un camión»: el retiro de abajo, que también va acotado, separa los dos casos.
	sucursal, err := a.BorrarTipoDeVehiculoSinUso(r.Context(), id)
	if err == nil {
		avisarCambioDeTiposDeVehiculo(r.Context(), deLaFilaPg(sucursal))
		httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "retirado": false})
		return
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		httpx.ErrorInterno(w, r, err)
		return
	}
	sucursal, err = a.RetirarTipoDeVehiculo(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// Un tipo RETIRADO también sale del desplegable, así que la pantalla cambia igual que
	// si se hubiera borrado. Avisar sólo en la rama del borrado dejaría la mitad de los
	// casos sin decir nada.
	avisarCambioDeTiposDeVehiculo(r.Context(), deLaFilaPg(sucursal))
	httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "retirado": true})
}

func deTipo(t sqlc.VehicleType, vehiculos int64, sucursal *string) TipoVehiculoSalida {
	return TipoVehiculoSalida{
		ID: t.ID, Nombre: t.Nombre, CostoKmUsd: t.CostoKmUsd, Activo: t.Activo,
		Vehiculos: vehiculos, SucursalID: idOpcional(t.BranchID), Sucursal: sucursal,
		CreatedAt: hora(t.CreatedAt), UpdatedAt: hora(t.UpdatedAt),
	}
}

// nombreDeLaSucursal es el nombre de la sucursal de un tipo que se acaba de escribir, para la
// respuesta del alta y del cambio (el listado lo trae en la propia consulta). Nulo si el tipo es
// «de todas». Si no se puede leer NO se falla: el tipo ya está escrito, y un 500 aquí haría que la
// app reintentara un alta que ya ocurrió y se llevara un 409. Queda en el registro.
func nombreDeLaSucursal(r *http.Request, a *alcance.Acotado, id pgtype.UUID) *string {
	if !id.Valid {
		return nil
	}
	b, err := a.ObtenerSucursal(r.Context(), uuid.UUID(id.Bytes))
	if err != nil {
		httpx.Registro(r).Warn("el tipo de vehículo se guardó pero no se pudo leer el nombre de su sucursal",
			"sucursal", idParaElRegistro(id), "err", err)
		return nil
	}
	return &b.Name
}
