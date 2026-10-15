package api

import (
	"context"
	"errors"
	"fmt"
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

// El nomenclador de DISTRIBUIDORES, POR SUCURSAL (issue 7 de Amado, 14/10/2026).
//
// El distribuidor es la persona responsable de la entrega y de devolver las facturas entregadas:
// el chofer mismo si va en triciclo, un empleado de Procovar si el vehículo es rentado. Se asocia
// a la ruta AL CREARLA (`distribuidorId` en `POST /api/routes` y en el armado desde el tablero).
// Aquí está el catálogo; la ruta lo valida en `distribuidorDeLaRuta` (rutas.go).
//
// NO es una persona de Accesos: Reparto no guarda personas (CLAUDE.md §4). Es un nombre que la
// sucursal mantiene en su lista, y por eso la pueden mantener todas las sesiones de Reparto,
// también LOGISTICO («la APK es completa para el logístico», Jose): igual que los tipos de vehículo.
//
// EL ALCANCE es el de las rutas: quien tiene sucursal ve y toca sólo los suyos —los de otra son un
// 404, no un 403— y quien está en modo «todas» ve las listas de todas, cada fila con su sucursal
// (en una ruta se elige la sucursal en el primer paso, y ahí el selector tiene que poder ofrecer
// los de ESA). Lo que NO puede hacer el modo «todas» es CREAR: un distribuidor nace en una sucursal
// y sin elegirla no tendría dueño, así que el POST contesta 400.
//
// SE RETIRA EN VEZ DE BORRAR si alguna ruta lo usa: borrarlo dejaría la ruta sin quién la repartió
// (la clave ajena lo impide, y no lleva CASCADE a propósito).

// avisarCambioDeDistribuidores publica «cambió el nomenclador» A LA SUCURSAL DEL DISTRIBUIDOR.
//
// Publica el MISMO tipo de aviso que la flota (`vehiculos`), por lo mismo que los tipos de vehículo:
// la pantalla donde se mantiene vive en Vehículos, que no vive de la base local y necesita el aviso
// para repintarse; y el vigía del aparato dispara con CUALQUIER aviso un ciclo, que es el que baja
// la colección `distribuidores` para el selector sin conexión. Inventar un tipo nuevo obligaría a
// cambiar la lista de la app (`CambioEnVivo`) por nada.
//
// Lleva la sucursal DE LA FILA que se escribió (`branch_id`, que devuelven las propias consultas),
// no la del alcance de quien llama: un distribuidor de Santiago no le importa a Holguín, y quien ve
// las ocho (alcance «todas») no es motivo para avisar a las ocho (ver `eventos.go`, «DE DÓNDE SALE
// LA SUCURSAL»).
var avisarCambioDeDistribuidores = func(_ context.Context, _ string) {}

// rutasDeDistribuidores cuelga las cuatro del recurso. Las cuatro son de SESIÓN, no de admin (como
// los tipos de vehículo, Jose 14/10/2026): la APK es completa para el logístico, y cada sesión toca
// sólo los de su sucursal. Si hubiera que cerrarlas, es cambiar `sesion...` por `admin...` aquí y
// la prueba `un_logistico_gestiona_distribuidores`.
func (s *Servidor) rutasDeDistribuidores(rt *httpx.Router, sesion []httpx.Medio) {
	rt.ManejarFunc(http.MethodGet, "/api/distribuidores", s.listarDistribuidores, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/distribuidores", s.crearDistribuidor, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/distribuidores/{id}", s.actualizarDistribuidor, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/distribuidores/{id}", s.borrarDistribuidor, sesion...)
}

// DistribuidorSalida es el contrato con el cliente.
type DistribuidorSalida struct {
	ID         uuid.UUID `json:"id"`
	Nombre     string    `json:"nombre"`
	Activo     bool      `json:"activo"`
	SucursalID uuid.UUID `json:"sucursalId"`
	// Sucursal es el nombre de la sucursal: quien ve las ocho listas (modo «todas») distingue así
	// a dos «Juan» de sucursales distintas.
	Sucursal *string `json:"sucursal"`
	// Rutas: cuántas rutas lo usan. Mayor que cero quiere decir que borrarlo lo RETIRA.
	Rutas     int64      `json:"rutas"`
	CreatedAt *time.Time `json:"createdAt"`
	UpdatedAt *time.Time `json:"updatedAt"`
}

// GET /api/distribuidores?activos=1
//
// Por defecto salen TODOS, activos y retirados: la pantalla de mantenimiento tiene que ver lo
// retirado para volver a activarlo. Con `activos=1` salen sólo los que se pueden elegir en una ruta
// nueva. Salen los de SU sucursal; en modo «todas», los de todas.
func (s *Servidor) listarDistribuidores(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var soloActivos *bool
	if v := r.URL.Query().Get("activos"); v == "1" || v == "true" {
		t := true
		soloActivos = &t
	}
	filas, err := a.ListarDistribuidores(r.Context(), soloActivos)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]DistribuidorSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, DistribuidorSalida{
			ID: f.ID, Nombre: f.Nombre, Activo: f.Activo, SucursalID: f.BranchID,
			Sucursal: &f.SucursalNombre, Rutas: f.Rutas,
			CreatedAt: hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

type cuerpoDistribuidor struct {
	Nombre httpx.Opcional[string] `json:"nombre"`
	Activo httpx.Opcional[bool]   `json:"activo"`
}

// msgDistribuidorSinSucursal es el 400 de crear un distribuidor en modo «todas».
const msgDistribuidorSinSucursal = "Elige una sucursal arriba para crear el distribuidor: los distribuidores son de cada sucursal."

// msgDistribuidorRepetido es el 409 de un nombre que la sucursal ya tiene (también el de un RETIRADO,
// que el cajón enseña aparte: se vuelve a activar, no se crea otro).
const msgDistribuidorRepetido = "Ya existe un distribuidor con ese nombre en esta sucursal"

// nombreDeDistribuidor limpia lo que escribió la persona: sin espacios en los bordes y con un solo
// espacio entre palabras. «Juan  Pérez» y «Juan Pérez» son el mismo nombre, y el índice único de
// la base sólo sabe de los bordes (`lower(btrim(nombre))`). El segundo valor es false si queda vacío.
func nombreDeDistribuidor(crudo string) (string, bool) {
	limpio := strings.Join(strings.Fields(crudo), " ")
	return limpio, limpio != ""
}

// POST /api/distribuidores   (cualquier sesión de Reparto, también LOGISTICO)
func (s *Servidor) crearDistribuidor(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// Sin sucursal elegida (modo «todas») no se crea nada: no tendría dueño.
	if !a.SucursalDeAlta().Valid {
		httpx.Error(w, r, http.StatusBadRequest, msgDistribuidorSinSucursal)
		return
	}
	var c cuerpoDistribuidor
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	nombre, hay := nombreDeDistribuidor(c.Nombre.Con(""))
	if !hay {
		httpx.Error(w, r, http.StatusBadRequest, "El nombre del distribuidor es obligatorio")
		return
	}
	d, err := a.CrearDistribuidor(r.Context(), sqlc.CrearDistribuidorParams{
		Nombre: nombre,
		Activo: c.Activo.Con(true),
	})
	if err != nil {
		// Un choque aquí es que el distribuidor ya está, no un fallo del servidor: con un 500 la
		// pantalla diría «error» y nadie sabría que basta con elegir el que ya existe.
		if esClaveRepetida(err) {
			httpx.Error(w, r, http.StatusConflict, msgDistribuidorRepetido)
			return
		}
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeDistribuidores(r.Context(), deLaFila(d.BranchID))
	httpx.JSON(w, r, http.StatusCreated, deDistribuidor(d, nombreDeLaSucursal(r, a, pgDe(d.BranchID))))
}

// PATCH /api/distribuidores/{id}   (cualquier sesión de Reparto, también LOGISTICO)
func (s *Servidor) actualizarDistribuidor(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c cuerpoDistribuidor
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	// El nombre, limpio y no vacío: sin esto un PATCH con `"nombre":"  "` dejaba a alguien que no
	// se puede leer en la lista (el POST ya lo rechaza, y la base tiene el CHECK).
	nombre := c.Nombre.Puntero()
	if nombre != nil {
		limpio, hay := nombreDeDistribuidor(*nombre)
		if !hay {
			httpx.Error(w, r, http.StatusBadRequest, "El nombre del distribuidor es obligatorio")
			return
		}
		nombre = &limpio
	}
	d, err := a.ActualizarDistribuidor(r.Context(), sqlc.ActualizarDistribuidorParams{
		ID: id, Nombre: nombre, Activo: c.Activo.Puntero(),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		// Renombrar a un nombre que ya existe en la sucursal (también el de un retirado) choca con
		// la única: el mismo 409 que el POST. Con un 500 la app lo toma por un fallo de red.
		if esClaveRepetida(err) {
			httpx.Error(w, r, http.StatusConflict, msgDistribuidorRepetido)
			return
		}
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeDistribuidores(r.Context(), deLaFila(d.BranchID))
	httpx.JSON(w, r, http.StatusOK, deDistribuidor(d, nombreDeLaSucursal(r, a, pgDe(d.BranchID))))
}

// DELETE /api/distribuidores/{id}   (cualquier sesión de Reparto, también LOGISTICO)
//
//	sin rutas -> se borra de verdad
//	con rutas -> se RETIRA (activo = false): deja de ofrecerse y las rutas siguen diciendo quién las repartió.
//
// La respuesta dice cuál de las dos pasó, porque no son lo mismo y la pantalla tiene que poder decirlo.
func (s *Servidor) borrarDistribuidor(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	// El borrado comprueba el uso EN LA MISMA SENTENCIA, no con un conteo antes: entre el conteo y
	// el borrado cabe una ruta nueva. Sin filas es «no existe / no es de tu sucursal» O «lo usa una
	// ruta»: el retiro de abajo, que también va acotado, separa los dos casos.
	sucursal, err := a.BorrarDistribuidorSinUso(r.Context(), id)
	if err == nil {
		avisarCambioDeDistribuidores(r.Context(), deLaFila(sucursal))
		httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "retirado": false})
		return
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		httpx.ErrorInterno(w, r, err)
		return
	}
	sucursal, err = a.RetirarDistribuidor(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// Un retirado también sale del selector, así que la pantalla cambia igual que si se hubiera
	// borrado. Avisar sólo en la rama del borrado dejaría la mitad de los casos sin decir nada.
	avisarCambioDeDistribuidores(r.Context(), deLaFila(sucursal))
	httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "retirado": true})
}

func deDistribuidor(d sqlc.Distribuidore, sucursal *string) DistribuidorSalida {
	return DistribuidorSalida{
		ID: d.ID, Nombre: d.Nombre, Activo: d.Activo, SucursalID: d.BranchID,
		Sucursal: sucursal, CreatedAt: hora(d.CreatedAt), UpdatedAt: hora(d.UpdatedAt),
	}
}

// msgDistribuidorRetirado es el 400 de asignar a una ruta a quien ya no está en activo. El aparato lo
// dice antes, con las mismas palabras, para que no llegue horas después a la bandeja de rechazados
// (igual que `msgVehiculoInactivo`).
const msgDistribuidorRetirado = "El distribuidor está retirado y no se puede asignar a una ruta."

// distribuidorDeLaRuta valida el `distribuidorId` que viene en el cuerpo de una ruta —`POST /api/routes`,
// `PATCH /api/routes/{id}` y el armado desde el tablero— y devuelve el id listo para escribir.
//
// Vacío o null NO es un error: es «sin distribuidor» (u, en un PATCH, quitarlo) y devuelve un uuid
// inválido. Con valor, TRES cosas, EN ESTE ORDEN:
//
//  1. que exista y sea ALCANZABLE: la consulta va acotada, así que el de otra sucursal contesta lo
//     mismo que uno que no existe (`No existe el distribuidor '…'`); decir «es de otra» sería contar
//     algo de él. Un id mal escrito es lo mismo: 400 con un mensaje que se entiende, y no el 500 de
//     la clave ajena con la jerga de Postgres dentro;
//  2. que sea de LA SUCURSAL DE LA RUTA. El alcance no basta: quien ve las ocho (SUPER ADMIN,
//     DESARROLLADOR sin sucursal elegida) alcanza el de Holguín aunque la ruta sea de Santiago, y la
//     clave ajena sola no sabe de sucursales. Aquí sólo llega ese caso, así que se puede nombrar;
//  3. que siga en activo: uno retirado no se asigna a una ruta nueva (las que ya lo llevan lo siguen
//     diciendo).
//
// `sucursalDeLaRuta` es la de la ruta, ya resuelta por quien llama (la elegida, la del primer pedido
// o la de la columna del tablero).
func distribuidorDeLaRuta(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, crudo string,
	sucursalDeLaRuta pgtype.UUID) (pgtype.UUID, bool) {
	pedido := strings.TrimSpace(crudo)
	if pedido == "" {
		return pgtype.UUID{}, true
	}
	noExiste := func() (pgtype.UUID, bool) {
		httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf("No existe el distribuidor '%s'", pedido))
		return pgtype.UUID{}, false
	}
	id, err := uuid.Parse(pedido)
	if err != nil {
		return noExiste()
	}
	d, err := a.ObtenerDistribuidor(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return noExiste()
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return pgtype.UUID{}, false
	}
	if !sucursalDeLaRuta.Valid || pgDe(d.BranchID) != sucursalDeLaRuta {
		httpx.Error(w, r, http.StatusBadRequest,
			fmt.Sprintf("El distribuidor '%s' no es de la sucursal de esta ruta", pedido))
		return pgtype.UUID{}, false
	}
	if !d.Activo {
		httpx.Error(w, r, http.StatusBadRequest, msgDistribuidorRetirado)
		return pgtype.UUID{}, false
	}
	return pgDe(d.ID), true
}
