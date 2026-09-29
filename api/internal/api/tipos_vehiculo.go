package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

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
// GLOBAL, sin alcance por sucursal: un «camión» es un camión en las ocho, y la tabla no
// tiene columna de sucursal que filtrar.

// avisarCambioDeTiposDeVehiculo publica «cambió el catálogo de tipos» A LAS OCHO.
//
// Publica el MISMO tipo de aviso que `avisarCambioDeVehiculos` (`vehiculos`), porque la
// pantalla es la misma: Vehículos enseña la flota y el desplegable de tipos en la misma
// vista, y un tipo nuevo que no aparece en el desplegable se ve igual de roto que un camión
// que no aparece en la lista.
//
// LO QUE CAMBIA ES A QUIÉN LE LLEGA, y por eso son dos ganchos y no uno — 29/09/2026:
//
//   - un camión es de UNA sucursal (`vehicles.branch_id`), así que su aviso se acota;
//   - un TIPO no es de ninguna: `vehicle_types` no tiene columna de sucursal. Acotarlo al
//     alcance de quien lo creó dejaría a las otras siete pantallas de Vehículos sin
//     enterarse de un tipo nuevo, y esa pantalla NO vive de la base local, así que el ciclo
//     tampoco la repinta: se queda clavada hasta salir y volver a entrar.
//
// Compartir un solo gancho obligaba a elegir, y lo elegido era global: un camión de
// Camagüey costaba dos peticiones en las otras siete. Ahora no hay que elegir.
var avisarCambioDeTiposDeVehiculo = func(_ context.Context) {}

type TipoVehiculoSalida struct {
	ID         uuid.UUID  `json:"id"`
	Nombre     string     `json:"nombre"`
	CostoKmUsd *float64   `json:"costoKmUsd"`
	Activo     bool       `json:"activo"`
	Vehiculos  int64      `json:"vehiculos"`
	CreatedAt  *time.Time `json:"createdAt"`
	UpdatedAt  *time.Time `json:"updatedAt"`
}

// GET /api/vehicle-types?activos=1
//
// Por defecto salen TODOS, activos y retirados: esta ruta la usa la pantalla de
// administración, que tiene que poder ver lo retirado para volver a activarlo. Con
// `activos=1` salen sólo los que se pueden elegir, que es lo que pide el desplegable del
// alta de un camión.
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
			Vehiculos: f.Vehiculos, CreatedAt: hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

type cuerpoTipoVehiculo struct {
	Nombre     httpx.Opcional[string]  `json:"nombre"`
	CostoKmUsd httpx.Opcional[float64] `json:"costoKmUsd"`
	Activo     httpx.Opcional[bool]    `json:"activo"`
}

// POST /api/vehicle-types   (admin)
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
		// `nombre` es UNIQUE. Un choque aquí es que el tipo ya está, no un fallo del
		// servidor: con un 500 la pantalla diría "error" y nadie sabría que basta con
		// elegir el que ya existe.
		if esClaveRepetida(err) {
			httpx.Error(w, r, http.StatusConflict, "Ya existe un tipo de vehículo con ese nombre")
			return
		}
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeTiposDeVehiculo(r.Context())
	httpx.JSON(w, r, http.StatusCreated, deTipo(t, 0))
}

// PATCH /api/vehicle-types/{id}   (admin)
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
	t, err := a.ActualizarTipoDeVehiculo(r.Context(), sqlc.ActualizarTipoDeVehiculoParams{
		ID:         id,
		Nombre:     c.Nombre.Puntero(),
		TocarCosto: c.CostoKmUsd.Presente,
		CostoKmUsd: c.CostoKmUsd.Valor,
		Activo:     c.Activo.Puntero(),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeTiposDeVehiculo(r.Context())
	httpx.JSON(w, r, http.StatusOK, deTipo(t, 0))
}

// DELETE /api/vehicle-types/{id}   (admin)
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
	// el conteo y el borrado cabe un alta.
	filas, err := a.BorrarTipoDeVehiculoSinUso(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if filas > 0 {
		avisarCambioDeTiposDeVehiculo(r.Context())
		httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "retirado": false})
		return
	}
	retiradas, err := a.RetirarTipoDeVehiculo(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if retiradas == 0 {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	// Un tipo RETIRADO también sale del desplegable, así que la pantalla cambia igual que
	// si se hubiera borrado. Avisar sólo en la rama del borrado dejaría la mitad de los
	// casos sin decir nada.
	avisarCambioDeTiposDeVehiculo(r.Context())
	httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "retirado": true})
}

func deTipo(t sqlc.VehicleType, vehiculos int64) TipoVehiculoSalida {
	return TipoVehiculoSalida{
		ID: t.ID, Nombre: t.Nombre, CostoKmUsd: t.CostoKmUsd, Activo: t.Activo,
		Vehiculos: vehiculos, CreatedAt: hora(t.CreatedAt), UpdatedAt: hora(t.UpdatedAt),
	}
}
