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

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// avisarCambioDeSucursales publica «cambió la lista de sucursales» para que las pantallas
// abiertas se enteren sin esperar al temporizador.
//
// Vacío por defecto y lo engancha el fichero del bus (`eventos.go`), igual que el de rutas
// y el del tablero. **No devuelve error y no se mira lo que conteste**: una sucursal no se
// deja de crear porque el aviso no salga.
//
// Aunque esto sólo lo toca un administrador y de higos a brevas, la lista de sucursales la
// enseñan el selector de la barra —en TODAS las pantallas— y el de Rutas. Una sucursal
// nueva que no aparece en el selector se lee como «la aplicación no la guardó».
var avisarCambioDeSucursales = func(_ context.Context) {}

// SucursalSalida es la forma con la que sale una sucursal.
//
// Se declara aquí y no se devuelve la fila de sqlc tal cual: la fila cambia en cuanto
// alguien toca una consulta, y entonces el cliente deja de encontrar un campo sin que
// nada falle al compilar.
//
// `creadoPor` era `creatorId` en delivery, y apuntaba a su tabla `User`. Aquí no hay
// tabla de personas —las personas viven en auth— así que es el id de auth, en texto y
// sin clave ajena. Por lo mismo, `_count` ya NO trae `members`: contar miembros exigiría
// preguntarle a auth en cada listado.
type SucursalSalida struct {
	ID               uuid.UUID  `json:"id"`
	Name             string     `json:"name"`
	Address          *string    `json:"address"`
	Lat              float64    `json:"lat"`
	Lng              float64    `json:"lng"`
	AreaKm2          float64    `json:"areaKm2"`
	ExternalID       *string    `json:"externalId"`
	OriginConfigured bool       `json:"originConfigured"`
	CreadoPor        *string    `json:"creadoPor"`
	CreatedAt        *time.Time `json:"createdAt"`
	UpdatedAt        *time.Time `json:"updatedAt"`
	Count            conteo     `json:"_count"`
}

type conteo struct {
	Origins int64 `json:"origins"`
}

func deBranch(b sqlc.Branch, origenes int64) SucursalSalida {
	return SucursalSalida{
		ID: b.ID, Name: b.Name, Address: b.Address, Lat: b.Lat, Lng: b.Lng,
		AreaKm2: b.AreaKm2, ExternalID: b.ExternalID, OriginConfigured: b.OriginConfigured,
		CreadoPor: b.CreadoPor, CreatedAt: hora(b.CreatedAt), UpdatedAt: hora(b.UpdatedAt),
		Count: conteo{Origins: origenes},
	}
}

// GET /api/branches
func (s *Servidor) listarSucursales(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// OJO: ListarSucursalesVisibles, no la lista acotada. Es «a cuáles puedo llegar» y
	// no «cuál estoy mirando»; si se acotara por la elegida, el selector devolvería una
	// sola sucursal y no habría forma de cambiar a otra.
	filas, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]SucursalSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, SucursalSalida{
			ID: f.ID, Name: f.Name, Address: f.Address, Lat: f.Lat, Lng: f.Lng,
			AreaKm2: f.AreaKm2, ExternalID: f.ExternalID, OriginConfigured: f.OriginConfigured,
			CreadoPor: f.CreadoPor, CreatedAt: hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
			Count: conteo{Origins: f.Origenes},
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// GET /api/branches/{id}
func (s *Servidor) obtenerSucursal(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	b, err := a.ObtenerSucursal(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	origenes, err := a.ContarOrigenesDeSucursal(r.Context(), b.ID)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, deBranch(b, origenes))
}

type cuerpoSucursal struct {
	Name       httpx.Opcional[string]  `json:"name"`
	Address    httpx.Opcional[string]  `json:"address"`
	Lat        httpx.Opcional[float64] `json:"lat"`
	Lng        httpx.Opcional[float64] `json:"lng"`
	AreaKm2    httpx.Opcional[float64] `json:"areaKm2"`
	ExternalID httpx.Opcional[string]  `json:"externalId"`
}

// POST /api/branches   (admin)
func (s *Servidor) crearSucursal(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoSucursal
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	// Literal del contrato. Las coordenadas son obligatorias porque sin ellas no hay
	// punto de partida, y sin punto de partida esa sucursal no puede armar una ruta.
	if c.Name.Con("") == "" || c.Lat.Valor == nil || c.Lng.Valor == nil {
		httpx.Error(w, r, http.StatusBadRequest, "Nombre y coordenadas son requeridos")
		return
	}

	var creada sqlc.Branch
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		creada, err = tx.CrearSucursal(r.Context(), sqlc.CrearSucursalParams{
			Name:       *c.Name.Valor,
			Address:    aTexto(c.Address.Con("")),
			Lat:        *c.Lat.Valor,
			Lng:        *c.Lng.Valor,
			AreaKm2:    c.AreaKm2.Con(1), // el `areaKm2 ?? 1` del contrato
			ExternalID: aTexto(c.ExternalID.Con("")),
		})
		if err != nil {
			return err
		}
		// El punto de partida por defecto se crea AQUÍ y en la misma transacción. Una
		// sucursal con coordenadas y sin origen no puede armar una ruta, y eso no lo
		// dice ninguna pantalla: se descubre el día que hace falta.
		_, err = tx.CrearOrigen(r.Context(), sqlc.CrearOrigenParams{
			Name:     creada.Name,
			Address:  direccionDeOrigen(creada),
			Lat:      creada.Lat,
			Lng:      creada.Lng,
			BranchID: pgDe(creada.ID),
		})
		if err != nil {
			return err
		}
		// Y sus tipos de vehículo: una COPIA de los «de todas», como la 00018 se los dio a las
		// que ya existían. Los tipos son por sucursal, y una que naciera sin ninguno no podría
		// dar de alta ni un camión (el `type` por defecto, «truck», daría 400).
		_, err = tx.SembrarTiposDeVehiculoEnSucursal(r.Context(), creada.ID)
		return err
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeSucursales(r.Context())
	httpx.JSON(w, r, http.StatusCreated, deBranch(creada, 1))
}

// PATCH /api/branches/{id}   (admin)
func (s *Servidor) actualizarSucursal(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c cuerpoSucursal
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	var b sqlc.Branch
	var origenes int64
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		b, err = tx.ActualizarSucursal(r.Context(), sqlc.ActualizarSucursalParams{
			ID:   id,
			Name: c.Name.Puntero(),
			// `tocar_*` es la diferencia entre «no me mandes esto» y «déjalo vacío».
			// Ver httpx.Opcional.
			TocarAddress:    c.Address.Presente,
			Address:         c.Address.Valor,
			Lat:             c.Lat.Puntero(),
			Lng:             c.Lng.Puntero(),
			AreaKm2:         c.AreaKm2.Puntero(),
			TocarExternalID: c.ExternalID.Presente,
			ExternalID:      c.ExternalID.Valor,
		})
		if err != nil {
			return err
		}
		// Relleno: si ahora tiene coordenadas y sigue sin ningún punto de partida, se le
		// crea el de por defecto. Es el mismo arreglo que el del alta, para las que se
		// dieron de alta antes de que existiera.
		origenes, err = tx.ContarOrigenesDeSucursal(r.Context(), b.ID)
		if err != nil {
			return err
		}
		if origenes == 0 {
			if _, err = tx.CrearOrigen(r.Context(), sqlc.CrearOrigenParams{
				Name:     b.Name,
				Address:  direccionDeOrigen(b),
				Lat:      b.Lat,
				Lng:      b.Lng,
				BranchID: pgDe(b.ID),
			}); err != nil {
				return err
			}
			origenes = 1
		}
		return nil
	})
	// Cero filas: o no existe, o es de otra sucursal. Las dos cosas son 404; decir cuál
	// sería contarle a quien prueba qué ids existen.
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeSucursales(r.Context())
	httpx.JSON(w, r, http.StatusOK, deBranch(b, origenes))
}

// DELETE /api/branches/{id}   (admin)
//
// En delivery esto desasociaba antes a los miembros (`User.updateMany`). Aquí no hay
// tabla de personas: la pertenencia a una sucursal la guarda auth, y quien borre una
// sucursal tiene que moverlos ALLÍ. Queda dicho en el aviso del registro, que es el
// único sitio donde se puede decir sin inventarse una llamada a auth desde un DELETE.
func (s *Servidor) borrarSucursal(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	filas, err := a.BorrarSucursal(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if filas == 0 {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	httpx.Registro(r).Warn("sucursal borrada: las personas que la tenían asignada siguen asignadas EN AUTH",
		"sucursal", id, "actor", a.Actor())
	avisarCambioDeSucursales(r.Context())
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

// direccionDeOrigen es el `address || "<lat>, <lng>"` del contrato: el origen siempre
// tiene algo escrito, porque es lo que se enseña en el desplegable de puntos de partida y
// una fila en blanco no se puede elegir.
func direccionDeOrigen(b sqlc.Branch) string {
	if b.Address != nil && *b.Address != "" {
		return *b.Address
	}
	return fmt.Sprintf("%g, %g", b.Lat, b.Lng)
}

// ---------------------------------------------------------------------------
// GET /api/service/sucursal?codigo=CAM — traducir el código a NUESTRO id.
//
// # Por qué existe
//
// Accesos firma dentro del token el CÓDIGO de la sucursal (`CAM`, `HOL`, `STG`), que es
// la única clave que cruza los cinco sistemas: los identificadores internos de cada
// aplicación no se parecen en nada. Aquí, en cambio, todo cuelga de `branches.id`, que es
// un uuid nuestro.
//
// `reparto-api` puede traducirlo él solo porque la tabla es suya (`internal/alcance`).
// `reparto-sync` NO: tiene su propia base y ahí no hay sucursales. Y la necesita de
// verdad — `POST /sync/aparato` guarda `branch_id` — así que hacía `uuid.Parse("CAM")`,
// fallaba, y contestaba **401 a todo lo del protocolo**. Lo que eso provoca aguas arriba
// está escrito en `sync/internal/identidad/token.go` y ya pasó el 16/09/2026: el cliente
// trata un 401 que sobrevive a renovar como «la sesión murió», así que echa a la persona
// a la pantalla de acceso **justo cuando vuelve la señal**, con el día del almacén dentro
// del aparato y sin haber subido nada.
//
// # Por qué con clave de servicio y no con la sesión de quien pide
//
// Porque quien pregunta es el sincronizador **antes** de saber quién llama: es el paso
// que resuelve la identidad, así que no puede exigir una. La clave es la misma que ya
// comparten los dos servicios (`SERVICE_API_KEY`), y lo que se devuelve —el id de una
// sucursal y su nombre— no es dato de nadie.
//
// Devuelve 404 cuando el código no es de ninguna. Eso NO se trata como «todas» en el
// sincronizador: allí no hay nada que enseñar de más, sólo un aparato que no se puede dar
// de alta, y decirlo es lo correcto.

// SucursalPorCodigoSalida es lo justo: quien pregunta sólo necesita el id.
type SucursalPorCodigoSalida struct {
	ID         uuid.UUID `json:"id"`
	Name       string    `json:"name"`
	ExternalID *string   `json:"externalId"`
}

func (s *Servidor) sucursalPorCodigo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	codigo := strings.TrimSpace(r.URL.Query().Get("codigo"))
	if codigo == "" {
		httpx.Error(w, r, http.StatusBadRequest, "Falta el código de la sucursal")
		return
	}
	fila, err := a.BuscarSucursalPorCodigo(r.Context(), codigo)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	case err != nil:
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, SucursalPorCodigoSalida{
		ID: fila.ID, Name: fila.Name, ExternalID: fila.ExternalID,
	})
}
