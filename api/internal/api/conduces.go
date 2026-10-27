// CONDUCES (super factura): `POST /api/conduces`, `DELETE /api/conduces/{principalId}` y
// `DELETE /api/conduces/{principalId}/miembros/{id}`. Especificación: `docs/conduces.md`; contrato y motivos
// literales: `docs/contratos-api.md`, «Conduces».
//
// Un conduce junta varias facturas del MISMO cliente en UNA parada. La primera que se marca es la PRINCIPAL y las
// demás son MIEMBROS (`orders.conduce_principal_id`, 00029). Cada factura sigue siendo una fila; el espejo no sabe
// nada de esto. Lo escribe SOLO una persona, por aquí.
//
// # LO QUE CONTESTAN LOS ERRORES
//
// `{ "error": "<motivo literal en español>" }`, y el motivo NOMBRA LA FACTURA que lo impide (su número de factura;
// el de operación si no hay otro; el id sólo como último recurso). 409 es un conflicto de ESTADO (ya va en una
// ruta, ya está entregada, ya es miembro…): se arregla cambiando el estado. 422 son DATOS que no valen (sin ids,
// repetidos, otro cliente, otra sucursal): no se arreglan reintentando. 404 es el alcance: una factura que no
// existe o no es de tu sucursal contesta lo mismo.
//
// # POR QUÉ SE LEE ANTES DE ESCRIBIR
//
// Para poder NOMBRAR. La escritura (`CrearConduce`, `DeshacerConduce`…) repite todas las guardas en su WHERE y
// además hay un trigger en la base; la lectura con candado (`FOR UPDATE`) sólo existe para que el motivo diga
// «la factura 47314 ya va en la ruta RT-…» y no «alguien se la llevó». Si entre las dos cosas algo cambia, la
// escritura devuelve de menos y se contesta 409 `msgConduceCambio`; no se guarda nada.
package api

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// Los literales, en constantes para que la app los diga igual y las pruebas los comparen sin copiarlos.
const (
	msgConduceSinIds     = "Marca al menos una factura, además de la principal, para el conduce"
	msgConduceIdMalo     = "principalId e ids tienen que ser ids de facturas"
	msgConduceCambio     = "Una factura del conduce cambió mientras se guardaba: vuelve a intentarlo"
	fmtConduceRepetida   = "La factura %s está repetida"
	fmtConducePrincipal  = "La factura %s es la principal: no va también entre las demás"
	fmtConduceSucursal   = "La factura %s es de otra sucursal: un conduce no mezcla sucursales"
	fmtConduceCliente    = "La factura %s es de otro cliente (%s): un conduce junta facturas de un solo cliente"
	fmtConduceAnulada    = "La factura %s está anulada"
	fmtConduceArchivada  = "La factura %s está archivada"
	fmtConduceEnRuta     = "La factura %s ya va en la ruta %s"
	fmtConduceEntregada  = "La factura %s ya está entregada"
	fmtConduceResultado  = "La factura %s ya tiene resultado (%s)"
	fmtConduceMiembro    = "La factura %s ya es miembro del conduce %s"
	fmtConduceMiembroPpl = "La factura %s es miembro del conduce %s: no puede ser la principal"
	fmtConducePrincipalA = "La factura %s ya es la principal de otro conduce"
	fmtConduceNoEs       = "La factura %s no encabeza ningún conduce"
	fmtConduceNoMiembro  = "La factura %s no es miembro de ese conduce"
	fmtConduceDeshacer   = "La factura %s es miembro del conduce %s: deshaz ese"

	// El que sale cuando se elige un MIEMBRO suelto al armar, colocar o marcar el cierre. Literal de Jose.
	fmtMiembroSuelto = "Esa factura va dentro del conduce %s: arma el conduce entero"
)

// ConduceSalida es lo que cuelga de una PRINCIPAL en `GET /api/orders` y en `/available`: sus facturas, la
// principal primero, y cuántos miembros lleva. `null` en las demás.
type ConduceSalida struct {
	Facturas []string `json:"facturas"`
	Miembros int      `json:"miembros"`
}

// numeroDeLaFila: el número con el que se nombra una factura en un motivo. El de factura; si falta, el de
// operación; el id sólo como último recurso (nadie lo reconoce, pero es mejor que un hueco).
func numeroDeLaFila(factura, operacion *string, id uuid.UUID) string {
	for _, t := range []*string{factura, operacion} {
		if t != nil {
			if n := strings.TrimSpace(*t); n != "" {
				return n
			}
		}
	}
	return id.String()
}

// claveDeCliente: «el mismo cliente» es el mismo nombre sin mayúsculas ni espacios de más. Sin plegar tildes:
// «Pérez» y «Perez» son dos nombres, y juntar dos clientes por parecidos es peor que pedir que se corrija el dato.
func claveDeCliente(nombre string) string {
	return strings.ToLower(strings.Join(strings.Fields(nombre), " "))
}

// ---------------------------------------------------------------------------
// La validación, sin base de datos: se prueba con filas a mano.
// ---------------------------------------------------------------------------

type rechazoDeConduce struct {
	Estado int
	Motivo string
}

func numeroDe(f sqlc.LeerFilasParaConduceRow) string {
	return numeroDeLaFila(f.FacturaNumero, f.OperationNumber, f.ID)
}

func numeroDelPrincipalDe(f sqlc.LeerFilasParaConduceRow) string {
	return numeroDeLaFila(f.PrincipalNumero, nil, f.ID)
}

// libreDeRutaYResultado: ¿puede tocarse este conduce? Ni en una ruta ni con resultado ni entregada. Lo piden
// crear, deshacer y sacar. Devuelve el motivo (409) o "".
func estadoQueImpide(f sqlc.LeerFilasParaConduceRow) string {
	switch {
	case f.AnuladaAt.Valid:
		return fmt.Sprintf(fmtConduceAnulada, numeroDe(f))
	case f.Archivado:
		return fmt.Sprintf(fmtConduceArchivada, numeroDe(f))
	case f.RouteID.Valid:
		ruta := "otra ruta"
		if f.RutaCodigo != nil && *f.RutaCodigo != "" {
			ruta = *f.RutaCodigo
		}
		return fmt.Sprintf(fmtConduceEnRuta, numeroDe(f), ruta)
	case f.DeliveredAt.Valid || (f.Resultado != nil && *f.Resultado == sqlc.StopResultEntregado):
		return fmt.Sprintf(fmtConduceEntregada, numeroDe(f))
	case f.Resultado != nil:
		return fmt.Sprintf(fmtConduceResultado, numeroDe(f), string(*f.Resultado))
	}
	return ""
}

// validarCrearConduce aplica las reglas 1 de la especificación a las filas ya leídas. `principal` es la primera
// que se marcó; `miembros`, las demás, en el orden en que llegaron. Los DATOS (422: otra sucursal, otro cliente)
// van antes que los ESTADOS (409) porque no se arreglan reintentando.
func validarCrearConduce(principal sqlc.LeerFilasParaConduceRow, miembros []sqlc.LeerFilasParaConduceRow) *rechazoDeConduce {
	todas := append([]sqlc.LeerFilasParaConduceRow{principal}, miembros...)

	for _, f := range miembros {
		if f.BranchID != principal.BranchID {
			return &rechazoDeConduce{http.StatusUnprocessableEntity, fmt.Sprintf(fmtConduceSucursal, numeroDe(f))}
		}
	}
	cliente := claveDeCliente(principal.CustomerName)
	for _, f := range miembros {
		if claveDeCliente(f.CustomerName) != cliente {
			return &rechazoDeConduce{http.StatusUnprocessableEntity, fmt.Sprintf(fmtConduceCliente, numeroDe(f), f.CustomerName)}
		}
	}

	for i, f := range todas {
		if m := estadoQueImpide(f); m != "" {
			return &rechazoDeConduce{http.StatusConflict, m}
		}
		if f.ConducePrincipalID.Valid {
			if i == 0 {
				return &rechazoDeConduce{http.StatusConflict, fmt.Sprintf(fmtConduceMiembroPpl, numeroDe(f), numeroDelPrincipalDe(f))}
			}
			return &rechazoDeConduce{http.StatusConflict, fmt.Sprintf(fmtConduceMiembro, numeroDe(f), numeroDelPrincipalDe(f))}
		}
		// Sólo la PRINCIPAL puede tener ya miembros (añadir a un conduce existente).
		if i > 0 && f.TieneMiembros {
			return &rechazoDeConduce{http.StatusConflict, fmt.Sprintf(fmtConducePrincipalA, numeroDe(f))}
		}
	}
	return nil
}

// validarTocarConduce vale para deshacer y para sacar un miembro: ninguna fila del conduce, la principal ni los
// miembros, puede ir en una ruta ni tener resultado.
func validarTocarConduce(filas []sqlc.LeerFilasParaConduceRow) *rechazoDeConduce {
	for _, f := range filas {
		if m := estadoQueImpide(f); m != "" {
			return &rechazoDeConduce{http.StatusConflict, m}
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// POST /api/conduces
// ---------------------------------------------------------------------------

type cuerpoConduce struct {
	PrincipalID string   `json:"principalId"`
	Ids         []string `json:"ids"`
}

// ConduceCreado es la respuesta del POST: la principal y TODOS sus miembros después de crear (también los que ya
// tenía si se amplió un conduce existente), en el orden de lectura.
type ConduceCreado struct {
	PrincipalID uuid.UUID   `json:"principalId"`
	Miembros    []uuid.UUID `json:"miembros"`
}

// ConduceDeshecho es la respuesta del DELETE del conduce entero.
type ConduceDeshecho struct {
	PrincipalID uuid.UUID   `json:"principalId"`
	Liberados   []uuid.UUID `json:"liberados"`
}

// MiembroSacado es la respuesta del DELETE de un miembro.
type MiembroSacado struct {
	PrincipalID uuid.UUID `json:"principalId"`
	ID          uuid.UUID `json:"id"`
}

func (s *Servidor) rutasConduces(rt *httpx.Router, sesion []httpx.Medio) {
	rt.ManejarFunc(http.MethodPost, "/api/conduces", s.crearConduce, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/conduces/{principalId}", s.deshacerConduce, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/conduces/{principalId}/miembros/{id}", s.sacarMiembroDeConduce, sesion...)
}

var errConduceCambio = errors.New(msgConduceCambio)

// rechazo es un error que lleva su estado y su motivo; `EnTx` lo deshace todo y el manejador lo contesta.
type errDeConduce struct{ rechazoDeConduce }

func (e errDeConduce) Error() string { return e.Motivo }

func (s *Servidor) crearConduce(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoConduce
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	principal, err := uuid.Parse(strings.TrimSpace(c.PrincipalID))
	if err != nil {
		httpx.Error(w, r, http.StatusUnprocessableEntity, msgConduceIdMalo)
		return
	}
	ids := make([]uuid.UUID, 0, len(c.Ids))
	for _, t := range c.Ids {
		id, err := uuid.Parse(strings.TrimSpace(t))
		if err != nil {
			httpx.Error(w, r, http.StatusUnprocessableEntity, msgConduceIdMalo)
			return
		}
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		httpx.Error(w, r, http.StatusUnprocessableEntity, msgConduceSinIds)
		return
	}

	var sucursal string
	var miembrosFinales []uuid.UUID
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		filas, err := tx.FilasParaConduce(r.Context(), append([]uuid.UUID{principal}, ids...), nil)
		if err != nil {
			return err
		}
		por := make(map[uuid.UUID]sqlc.LeerFilasParaConduceRow, len(filas))
		for _, f := range filas {
			por[f.ID] = f
		}
		// Una que no existe o no es de tu sucursal: el mismo 404 (alcance).
		pf, hay := por[principal]
		if !hay {
			return pgx.ErrNoRows
		}
		miembros := make([]sqlc.LeerFilasParaConduceRow, 0, len(ids))
		vistos := map[uuid.UUID]bool{}
		for _, id := range ids {
			f, hay := por[id]
			if !hay {
				return pgx.ErrNoRows
			}
			switch {
			case id == principal:
				return errDeConduce{rechazoDeConduce{http.StatusUnprocessableEntity, fmt.Sprintf(fmtConducePrincipal, numeroDe(f))}}
			case vistos[id]:
				return errDeConduce{rechazoDeConduce{http.StatusUnprocessableEntity, fmt.Sprintf(fmtConduceRepetida, numeroDe(f))}}
			}
			vistos[id] = true
			miembros = append(miembros, f)
		}
		if rz := validarCrearConduce(pf, miembros); rz != nil {
			return errDeConduce{*rz}
		}
		hechos, err := tx.CrearConduce(r.Context(), principal, ids)
		if err != nil {
			return err
		}
		if len(hechos) != len(ids) {
			return errConduceCambio // alguien movió una entre la lectura y la escritura
		}
		todos, err := tx.MiembrosDeConduces(r.Context(), []uuid.UUID{principal})
		if err != nil {
			return err
		}
		for _, m := range todos {
			miembrosFinales = append(miembrosFinales, m.ID)
		}
		sucursal = deLaFilaPg(pf.BranchID)
		return nil
	})
	if !conduceContestado(w, r, err) {
		return
	}
	rastroDeQuien(r, "conduce creado", "principal", principal, "miembros", len(ids))
	// Los miembros desaparecen de las listas y del «Sin colocar»: las dos pantallas se enteran.
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)
	httpx.JSON(w, r, http.StatusCreated, ConduceCreado{PrincipalID: principal, Miembros: miembrosFinales})
}

// conduceContestado traduce el error de la transacción. Devuelve true si NO hubo error y hay que seguir.
func conduceContestado(w http.ResponseWriter, r *http.Request, err error) bool {
	var rz errDeConduce
	switch {
	case err == nil:
		return true
	case errors.As(err, &rz):
		httpx.Error(w, r, rz.Estado, rz.Motivo)
	case errors.Is(err, errConduceCambio):
		httpx.Error(w, r, http.StatusConflict, msgConduceCambio)
	case errors.Is(err, pgx.ErrNoRows):
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
	default:
		httpx.ErrorInterno(w, r, err)
	}
	return false
}

// ---------------------------------------------------------------------------
// DELETE /api/conduces/{principalId}
// ---------------------------------------------------------------------------

func (s *Servidor) deshacerConduce(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	principal, err := uuid.Parse(r.PathValue("principalId"))
	if err != nil {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	var sucursal string
	var liberados []uuid.UUID
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		filas, err := tx.FilasParaConduce(r.Context(), []uuid.UUID{principal}, &principal)
		if err != nil {
			return err
		}
		var pf *sqlc.LeerFilasParaConduceRow
		for i := range filas {
			if filas[i].ID == principal {
				pf = &filas[i]
			}
		}
		if pf == nil {
			return pgx.ErrNoRows
		}
		if pf.ConducePrincipalID.Valid {
			return errDeConduce{rechazoDeConduce{http.StatusConflict, fmt.Sprintf(fmtConduceDeshacer, numeroDe(*pf), numeroDelPrincipalDe(*pf))}}
		}
		if len(filas) < 2 {
			return errDeConduce{rechazoDeConduce{http.StatusNotFound, fmt.Sprintf(fmtConduceNoEs, numeroDe(*pf))}}
		}
		if rz := validarTocarConduce(filas); rz != nil {
			return errDeConduce{*rz}
		}
		liberados, err = tx.DeshacerConduce(r.Context(), principal)
		if err != nil {
			return err
		}
		if len(liberados) != len(filas)-1 {
			return errConduceCambio
		}
		sucursal = deLaFilaPg(pf.BranchID)
		return nil
	})
	if !conduceContestado(w, r, err) {
		return
	}
	rastroDeQuien(r, "conduce deshecho", "principal", principal, "liberados", len(liberados))
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)
	httpx.JSON(w, r, http.StatusOK, ConduceDeshecho{PrincipalID: principal, Liberados: liberados})
}

// ---------------------------------------------------------------------------
// DELETE /api/conduces/{principalId}/miembros/{id}
// ---------------------------------------------------------------------------

func (s *Servidor) sacarMiembroDeConduce(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	principal, err1 := uuid.Parse(r.PathValue("principalId"))
	id, err2 := uuid.Parse(r.PathValue("id"))
	if err1 != nil || err2 != nil {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	var sucursal string
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		filas, err := tx.FilasParaConduce(r.Context(), []uuid.UUID{principal, id}, &principal)
		if err != nil {
			return err
		}
		por := make(map[uuid.UUID]sqlc.LeerFilasParaConduceRow, len(filas))
		for _, f := range filas {
			por[f.ID] = f
		}
		pf, hay := por[principal]
		mf, hayM := por[id]
		if !hay || !hayM {
			return pgx.ErrNoRows
		}
		if !mf.ConducePrincipalID.Valid || uuid.UUID(mf.ConducePrincipalID.Bytes) != principal {
			return errDeConduce{rechazoDeConduce{http.StatusNotFound, fmt.Sprintf(fmtConduceNoMiembro, numeroDe(mf))}}
		}
		if rz := validarTocarConduce(filas); rz != nil {
			return errDeConduce{*rz}
		}
		n, err := tx.SacarMiembroDeConduce(r.Context(), principal, id)
		if err != nil {
			return err
		}
		if n != 1 {
			return errConduceCambio
		}
		sucursal = deLaFilaPg(pf.BranchID)
		return nil
	})
	if !conduceContestado(w, r, err) {
		return
	}
	rastroDeQuien(r, "miembro sacado de un conduce", "principal", principal, "factura", id)
	avisarCambioDePedidos(r.Context(), sucursal)
	avisarCambioDelTablero(r.Context(), sucursal)
	httpx.JSON(w, r, http.StatusOK, MiembroSacado{PrincipalID: principal, ID: id})
}

// ---------------------------------------------------------------------------
// Lo que cuelga de una principal en las listas, y lo que necesitan el armado y el cierre
// ---------------------------------------------------------------------------

// facturaDeFila: lo mínimo para nombrar una principal en `conduce.facturas`.
type facturaDeFila struct {
	ID        uuid.UUID
	Factura   *string
	Operacion *string
}

func facturasDeLaPagina(filas []sqlc.ListarPedidosRow) []facturaDeFila {
	out := make([]facturaDeFila, 0, len(filas))
	for _, x := range filas {
		out = append(out, facturaDeFila{ID: x.ID})
	}
	return out
}

// conducesDe devuelve `conduce` de cada principal que tiene miembros. Una consulta para toda la página.
func (s *Servidor) conducesDe(r *http.Request, a *alcance.Acotado, filas []facturaDeFila) (map[uuid.UUID]*ConduceSalida, error) {
	out := map[uuid.UUID]*ConduceSalida{}
	if len(filas) == 0 {
		return out, nil
	}
	ids := make([]uuid.UUID, 0, len(filas))
	for _, f := range filas {
		ids = append(ids, f.ID)
	}
	miembros, err := a.MiembrosDeConduces(r.Context(), ids)
	if err != nil {
		return nil, err
	}
	for _, m := range miembros {
		if !m.PrincipalID.Valid {
			continue
		}
		p := uuid.UUID(m.PrincipalID.Bytes)
		c := out[p]
		if c == nil {
			c = &ConduceSalida{Facturas: []string{numeroDeLaFila(m.PrincipalFactura, m.PrincipalOperacion, p)}}
			out[p] = c
		}
		c.Facturas = append(c.Facturas, numeroDeLaFila(m.FacturaNumero, m.OperationNumber, m.ID))
		c.Miembros++
	}
	return out, nil
}

// miembrosDe: los ids de los miembros de cada principal, para el cierre y el armado.
func miembrosDe(filas []sqlc.MiembrosDeConducesRow) map[uuid.UUID][]sqlc.MiembrosDeConducesRow {
	out := map[uuid.UUID][]sqlc.MiembrosDeConducesRow{}
	for _, m := range filas {
		if m.PrincipalID.Valid {
			p := uuid.UUID(m.PrincipalID.Bytes)
			out[p] = append(out[p], m)
		}
	}
	return out
}

// conSusMiembros: los ids dados más los de los miembros de sus conduces. Lo que se avisa a PEDIDO al despachar
// tiene que llevar CADA factura, no sólo la principal.
func conSusMiembros(r *http.Request, a *alcance.Acotado, ids []uuid.UUID) ([]uuid.UUID, error) {
	miembros, err := a.MiembrosDeConduces(r.Context(), ids)
	if err != nil {
		return nil, err
	}
	todos := append([]uuid.UUID(nil), ids...)
	for _, m := range miembros {
		todos = append(todos, m.ID)
	}
	return todos, nil
}

// motivoDeMiembroSuelto dice, si esta factura es MIEMBRO de un conduce, que se arma/coloca/marca el conduce
// entero: «Esa factura va dentro del conduce 47313: arma el conduce entero». Con el alcance de quien llama: una
// factura que no puede leer contesta ("", false) y el manejador sigue con su motivo de siempre.
func motivoDeMiembroSuelto(r *http.Request, a *alcance.Acotado, pedido uuid.UUID) (string, bool) {
	p, err := a.TableroObtenerPedido(r.Context(), pedido)
	if err != nil || !p.ConducePrincipalID.Valid {
		return "", false
	}
	principal := uuid.UUID(p.ConducePrincipalID.Bytes)
	pr, err := a.TableroObtenerPedido(r.Context(), principal)
	if err != nil {
		return fmt.Sprintf(fmtMiembroSuelto, principal), true
	}
	return fmt.Sprintf(fmtMiembroSuelto, numeroDeLaFila(pr.FacturaNumero, pr.OperationNumber, principal)), true
}
