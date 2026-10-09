package sincro

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// LA BANDEJA DEL REVISOR — `docs/bandeja-de-revision.md`, paquete S2 (B.2, B.3, B.4).
//
// Quien perdió `delivery.entrar` entregó su cola (S1); aquí una PERSONA la lee y decide. Cinco rutas, todas en
// el mux INTERNO de [Servicio.Rutas], o sea detrás del `Exigir` normal (la fuente de la casa): el token de
// entrega a revisión no entra por aquí. Lo que deciden `GET /sync/revision/mias` y `POST /sync/revision/entrega`
// (la persona que entregó) vive en `revision_entrega.go` y NO se mezcla.
//
//	GET  /sync/revision[?sucursal=]                      la bandeja: una fila por entrega con algo esperando
//	GET  /sync/revision/{entrega}                        la entrega con sus apuntes, el original EXACTO
//	POST /sync/revision/{aparato}/{clave}/aplicar        aplicar uno         (`revision_aplicar.go`)
//	POST /sync/revision/{entrega}/aplicar                aplicar en orden    (`revision_aplicar.go`)
//	POST /sync/revision/{aparato}/{clave}/descartar      {"motivo": "…"}
//
// # QUIÉN REVISA, y qué lo garantiza
//
//  1. El ROL, por nombre (`Identidad.RolDeRevisor`): ADMINISTRADOR, SUPER ADMIN o DESARROLLADOR, y con token.
//     LOGISTICO entra a Reparto pero no revisa. Es lo único que se decide en Go.
//  2. Lo demás lo decide el SQL, en la MISMA sentencia que escribe (`persona <> revisor`, el alcance de
//     sucursal, `estado IN (…)`): comprobar en Go y luego escribir deja una ventana, y un `if` que se olvida
//     no lo ve ninguna consulta. Cuando el SQL dice «ninguna fila», [Servicio.porQueNo] mira de nuevo SIN
//     alcance para poner la frase (404, 403 o 409); esa segunda lectura nunca concede nada.
//
// Respuestas de error (formato de la casa `{"error", "codigo"}`): 403 `no_revisa` · 403 `es_lo_tuyo` · 403
// `sucursal_ajena` · 404 `no_encontrado` · 409 `ya_se_esta_aplicando` · 409 `ya_decidido` · 422
// `motivo_obligatorio`.

const (
	CodigoNoRevisa          = "no_revisa"
	CodigoEsLoTuyo          = "es_lo_tuyo"
	CodigoSucursalAjena     = "sucursal_ajena"
	CodigoNoEncontrado      = "no_encontrado"
	CodigoYaSeEstaAplicando = "ya_se_esta_aplicando"
	CodigoYaDecidido        = "ya_decidido"
	CodigoMotivoObligatorio = "motivo_obligatorio"
	CodigoRepartoNoContesta = "reparto_no_disponible"
	CodigoNoSePudoAnotar    = "no_se_pudo_anotar"
	CodigoSigueEnCurso      = "sigue_en_curso"

	// Un descarte lleva un motivo escrito de verdad: la base lo exige también (CHECK ≥ 5 letras).
	minimoDelMotivo = 5
	// Tope de entregas en la bandeja. Se comprueba si se alcanzó (CLAUDE.md §3) y se dice en `truncado`.
	topeEntregasEnLaBandeja = 500
	// Una fila en `aplicando` más vieja que esto es de un proceso que murió: el revisor puede reintentarla
	// CONFIRMANDO que comprobó a mano que la ruta no se aplicó (la API no lee `X-Apunte`: no hay otra red).
	esperaParaDarPorInterrumpido = 10 * time.Minute
)

// RutasDelRevisor monta las cinco rutas del revisor. Las llama [Servicio.Rutas], así que van detrás del
// `Exigir` normal de `main` (el que RECHAZA el token de entrega); no hay que cablear nada más.
func (s *Servicio) RutasDelRevisor(mux *http.ServeMux) {
	mux.HandleFunc("GET /sync/revision", s.listarRevision)
	mux.HandleFunc("GET /sync/revision/{entrega}", s.detalleDeRevision)
	mux.HandleFunc("POST /sync/revision/{entrega}/aplicar", s.aplicarEntrega)
	mux.HandleFunc("POST /sync/revision/{aparato}/{clave}/aplicar", s.aplicarApunte)
	mux.HandleFunc("POST /sync/revision/{aparato}/{clave}/descartar", s.descartarApunte)
}

// revisor es la puerta común: hay identidad y su rol puede revisar. Si no, ya contestó.
func (s *Servicio) revisor(w http.ResponseWriter, r *http.Request) (identidad.Identidad, string, bool) {
	quien, hay := identidad.De(r.Context())
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return identidad.Identidad{}, "", false
	}
	rol, ok := quien.RolDeRevisor()
	if !ok {
		httpx.FalloConCodigo(w, http.StatusForbidden,
			"No tienes permiso para revisar. Revisan el administrador de la sucursal, el super administrador y el desarrollador.",
			CodigoNoRevisa)
		return identidad.Identidad{}, "", false
	}
	return quien, rol, true
}

func (f *falloDeEntrega) contesta(w http.ResponseWriter) {
	httpx.FalloConCodigo(w, f.estado, f.mensaje, f.codigo)
}

func fallo(estado int, codigo, formato string, a ...any) *falloDeEntrega {
	return &falloDeEntrega{estado, fmt.Sprintf(formato, a...), codigo}
}

// ---------------------------------------------------------------------------
// Lo que se enseña
// ---------------------------------------------------------------------------

type entregaDelRevisor struct {
	ID            uuid.UUID  `json:"id"`
	Aparato       uuid.UUID  `json:"aparato"`
	AparatoNombre *string    `json:"aparatoNombre"`
	Persona       string     `json:"persona"`
	PersonaNombre *string    `json:"personaNombre"`
	Sucursal      uuid.UUID  `json:"sucursal"`
	EntregadaAt   *time.Time `json:"entregadaAt"`
	VersionApp    *string    `json:"versionApp"`
	// Cuántos apuntes hay en cada estado. «Por decidir» = enRevision + rechazados (+ aplicando, que alguien
	// está resolviendo o se interrumpió).
	EnRevision  int64 `json:"enRevision"`
	Aplicando   int64 `json:"aplicando"`
	Rechazados  int64 `json:"rechazados"`
	Aplicados   int64 `json:"aplicados"`
	Descartados int64 `json:"descartados"`
}

type apunteDelRevisor struct {
	Aparato uuid.UUID `json:"aparato"`
	Clave   string    `json:"clave"`
	Orden   int32     `json:"orden"`
	Metodo  string    `json:"metodo"`
	Ruta    string    `json:"ruta"`
	// EL ORIGINAL, byte a byte: lo que el revisor mira es lo que se reenvía (salvo los `local-…`, que se
	// traducen al aplicar). Un texto, no un objeto: re-serializarlo cambiaría el orden y los espacios.
	Cuerpo      *string `json:"cuerpo"`
	Provisional *string `json:"provisional,omitempty"`
	// La hora del APARATO.
	HechoAt *time.Time `json:"hechoAt"`
	Estado  string     `json:"estado"`
	// Rechazado: el LITERAL del reparto. Descartado: el motivo de quien decidió.
	Motivo            *string         `json:"motivo"`
	DecididoPorNombre *string         `json:"decididoPorNombre"`
	DecididoAt        *time.Time      `json:"decididoAt"`
	Intentos          int32           `json:"intentos"`
	IDCreado          *uuid.UUID      `json:"idCreado"`
	Descartados       json.RawMessage `json:"descartados,omitempty"`
	Resumen           *string         `json:"resumenDelAparato,omitempty"`
	// Un `aplicando` de hace más de [esperaParaDarPorInterrumpido]: el proceso murió. Se puede reintentar
	// confirmando (`{"reintentarInterrumpido": true}`) tras comprobar a mano la ruta.
	Interrumpido bool `json:"interrumpido,omitempty"`
}

func interrumpido(estado sqlc.RevisionEstado, desde pgtype.Timestamptz, ahora time.Time) bool {
	return estado == sqlc.RevisionEstadoAplicando && desde.Valid && ahora.Sub(desde.Time) >= esperaParaDarPorInterrumpido
}

// ---------------------------------------------------------------------------
// GET /sync/revision
// ---------------------------------------------------------------------------

type bandejaSalida struct {
	Entregas []entregaDelRevisor `json:"entregas"`
	// Hay más de las que caben: primero van las más antiguas (FIFO), así que se queda fuera lo más nuevo.
	Truncado bool `json:"truncado"`
}

func (s *Servicio) listarRevision(w http.ResponseWriter, r *http.Request) {
	quien, _, ok := s.revisor(w, r)
	if !ok {
		return
	}
	// EL ALCANCE SALE DE QUIÉN PREGUNTA (CLAUDE.md §4), igual que `/sync/estado`: el parámetro sólo ESTRECHA, y
	// sólo a quien ve todas. Para el resto se ignora: el ADMINISTRADOR de CAM no ve HOL cambiando la dirección.
	sucursal := quien.Alcance()
	if quien.EsSuperAdmin {
		if v := r.URL.Query().Get("sucursal"); v != "" {
			pedida, err := uuid.Parse(v)
			if err != nil {
				httpx.Fallo(w, http.StatusBadRequest, "La sucursal no es un identificador válido")
				return
			}
			sucursal = &pedida
		}
	}
	filas, err := s.datos.ListarEntregasParaRevisor(r.Context(), sqlc.ListarEntregasParaRevisorParams{
		Sucursal: alcance(sucursal), Limite: topeEntregasEnLaBandeja + 1,
	})
	if err != nil {
		s.log.Error("no se pudo leer la bandeja de revisión", "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer la bandeja de revisión")
		return
	}
	salida := bandejaSalida{Entregas: make([]entregaDelRevisor, 0, len(filas))}
	if len(filas) > topeEntregasEnLaBandeja {
		salida.Truncado, filas = true, filas[:topeEntregasEnLaBandeja]
	}
	for _, f := range filas {
		salida.Entregas = append(salida.Entregas, entregaDelRevisor{
			ID: f.ID, Aparato: f.AparatoID, AparatoNombre: textoOpcional(f.AparatoNombre, topeNombreEnLaBandeja), Persona: f.Persona,
			PersonaNombre: f.PersonaNombre, Sucursal: f.BranchID, EntregadaAt: hora(f.EntregadaAt), VersionApp: f.VersionApp,
			EnRevision: f.EnRevision, Aplicando: f.Aplicando, Rechazados: f.Rechazados,
			Aplicados: f.Aplicados, Descartados: f.Descartados,
		})
	}
	httpx.JSON(w, http.StatusOK, salida)
}

// ---------------------------------------------------------------------------
// GET /sync/revision/{entrega}
// ---------------------------------------------------------------------------

type detalleSalida struct {
	Entrega entregaDelRevisor  `json:"entrega"`
	Apuntes []apunteDelRevisor `json:"apuntes"`
}

func (s *Servicio) detalleDeRevision(w http.ResponseWriter, r *http.Request) {
	quien, _, ok := s.revisor(w, r)
	if !ok {
		return
	}
	id, ok := idDeEntrega(w, r)
	if !ok {
		return
	}
	filas, err := s.datos.RevisionDeEntrega(r.Context(), sqlc.RevisionDeEntregaParams{EntregaID: id, Sucursal: alcance(quien.Alcance())})
	if err != nil {
		s.log.Error("no se pudo leer la entrega", "entrega", id, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer la entrega")
		return
	}
	if len(filas) == 0 {
		s.porQueNoHayEntrega(r.Context(), quien, id).contesta(w)
		return
	}
	cabecera := entregaDelRevisor{
		ID: id, Aparato: filas[0].AparatoID, Persona: filas[0].Persona, PersonaNombre: filas[0].PersonaNombre,
		Sucursal: filas[0].BranchID, EntregadaAt: hora(filas[0].EntregadaAt),
	}
	if a, err := s.datos.AparatoPorId(r.Context(), filas[0].AparatoID); err == nil && a.Nombre != nil {
		// RECORTADO: el nombre lo manda el aparato y de antes del tope pudo quedar uno enorme (auditoría M3).
		cabecera.AparatoNombre = textoOpcional(*a.Nombre, topeNombreEnLaBandeja)
	}
	ahora := s.ahora()
	salida := detalleSalida{Apuntes: make([]apunteDelRevisor, 0, len(filas))}
	for _, f := range filas {
		switch f.Estado {
		case sqlc.RevisionEstadoEnRevision:
			cabecera.EnRevision++
		case sqlc.RevisionEstadoAplicando:
			cabecera.Aplicando++
		case sqlc.RevisionEstadoRechazado:
			cabecera.Rechazados++
		case sqlc.RevisionEstadoAplicado:
			cabecera.Aplicados++
		case sqlc.RevisionEstadoDescartado:
			cabecera.Descartados++
		}
		salida.Apuntes = append(salida.Apuntes, apunteDelRevisor{
			Aparato: f.AparatoID, Clave: f.Clave, Orden: f.Orden, Metodo: f.Metodo, Ruta: f.Ruta, Cuerpo: f.Cuerpo,
			Provisional: f.Provisional, HechoAt: hora(f.HechoAt), Estado: string(f.Estado), Motivo: f.Motivo,
			DecididoPorNombre: f.DecididoPorNombre, DecididoAt: hora(f.DecididoAt), Intentos: f.Intentos,
			IDCreado: deIdentificador(f.IDCreado), Descartados: f.Descartados, Resumen: f.ResumenDelAparato,
			Interrumpido: interrumpido(f.Estado, f.DecididoAt, ahora),
		})
	}
	salida.Entrega = cabecera
	httpx.JSON(w, http.StatusOK, salida)
}

func idDeEntrega(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	id, err := uuid.Parse(r.PathValue("entrega"))
	if err != nil {
		httpx.Fallo(w, http.StatusBadRequest, "La entrega no es un identificador válido")
		return uuid.Nil, false
	}
	return id, true
}

// idDeApunte lee `{aparato}/{clave}` de la ruta.
func idDeApunte(w http.ResponseWriter, r *http.Request) (uuid.UUID, string, bool) {
	aparato, err := uuid.Parse(r.PathValue("aparato"))
	if err != nil {
		httpx.Fallo(w, http.StatusBadRequest, "El aparato no es un identificador válido")
		return uuid.Nil, "", false
	}
	clave := r.PathValue("clave")
	if !reClaveDeRevision.MatchString(clave) {
		httpx.Fallo(w, http.StatusBadRequest, "La clave del apunte no es válida")
		return uuid.Nil, "", false
	}
	return aparato, clave, true
}

// ---------------------------------------------------------------------------
// Por qué NO: ponerle frase a un «ninguna fila»
// ---------------------------------------------------------------------------

// porQueNoHayEntrega: la consulta CON alcance no devolvió nada. Mirando SIN alcance (que no concede nada, sólo
// elige la frase): si la entrega no existe, 404; si existe en una sucursal que este revisor no ve, 403.
func (s *Servicio) porQueNoHayEntrega(ctx context.Context, quien identidad.Identidad, id uuid.UUID) *falloDeEntrega {
	e, err := s.datos.RevisionEntregaPorId(ctx, id)
	switch {
	case store.SinFilas(err):
		return fallo(http.StatusNotFound, CodigoNoEncontrado, "Esa entrega no existe.")
	case err != nil:
		return fallo(http.StatusInternalServerError, "", "No se pudo leer la entrega.")
	case !quien.Ve(e.BranchID):
		return fallo(http.StatusForbidden, CodigoSucursalAjena, "Esa entrega es de una sucursal que no ves.")
	}
	return fallo(http.StatusNotFound, CodigoNoEncontrado, "Esa entrega no existe.")
}

// porQueNo: el SQL con alcance no dejó escribir en este apunte (no se reclamó, no se descartó). Es SÓLO la
// frase: el «no» ya estaba dado. Orden de lo que se dice: no existe (404) · sucursal ajena (403) · es lo tuyo
// (403) · ya lo está aplicando o ya está decidido (409).
func (s *Servicio) porQueNo(ctx context.Context, quien identidad.Identidad, aparato uuid.UUID, clave string) *falloDeEntrega {
	a, err := s.datos.EstadoDeRevisionDeApunte(ctx, sqlc.EstadoDeRevisionDeApunteParams{AparatoID: aparato, Clave: clave})
	if store.SinFilas(err) {
		return fallo(http.StatusNotFound, CodigoNoEncontrado, "Ese apunte no existe.")
	}
	if err != nil {
		return fallo(http.StatusInternalServerError, "", "No se pudo leer el apunte.")
	}
	e, err := s.datos.RevisionEntregaPorId(ctx, a.EntregaID)
	if err != nil {
		return fallo(http.StatusInternalServerError, "", "No se pudo leer el apunte.")
	}
	switch {
	case !quien.Ve(e.BranchID):
		return fallo(http.StatusForbidden, CodigoSucursalAjena, "Ese apunte es de una sucursal que no ves.")
	case e.Persona == quien.Persona:
		return fallo(http.StatusForbidden, CodigoEsLoTuyo, "Lo entregaste tú. Nadie revisa lo suyo: tiene que decidirlo otra persona.")
	}
	quienLoTiene := "otra persona"
	if a.DecididoPorNombre != nil && *a.DecididoPorNombre != "" {
		quienLoTiene = *a.DecididoPorNombre
	}
	switch a.Estado {
	case sqlc.RevisionEstadoAplicando:
		return fallo(http.StatusConflict, CodigoYaSeEstaAplicando,
			"Ya lo está aplicando %s. Espera a que termine y actualiza la bandeja.", quienLoTiene)
	case sqlc.RevisionEstadoAplicado:
		return fallo(http.StatusConflict, CodigoYaDecidido, "Ya está aplicado (lo aplicó %s).", quienLoTiene)
	case sqlc.RevisionEstadoDescartado:
		return fallo(http.StatusConflict, CodigoYaDecidido, "Ya está descartado (lo descartó %s).", quienLoTiene)
	}
	// Esperando y a la vista, y aun así no se pudo tomar: otro revisor se adelantó entre mirar y escribir.
	return fallo(http.StatusConflict, CodigoYaSeEstaAplicando, "Otro revisor acaba de tomarlo. Actualiza la bandeja.")
}

// ---------------------------------------------------------------------------
// POST /sync/revision/{aparato}/{clave}/descartar
// ---------------------------------------------------------------------------

type descarteEntrada struct {
	Motivo string `json:"motivo"`
}

// descartarApunte NO BORRA: marca `descartado` con quién, cuándo y el motivo, y lo anota en el libro. Sin
// motivo escrito (≥ 5 letras) no hay descarte: 422 aquí y el CHECK de la base por debajo.
//
// «Una decisión de una persona se ESCRIBE, no se borra» (CLAUDE.md §4): borrar dejaría un hueco, y otra
// pieza lo rellenaría con lo que ella cree.
func (s *Servicio) descartarApunte(w http.ResponseWriter, r *http.Request) {
	quien, rol, ok := s.revisor(w, r)
	if !ok {
		return
	}
	aparato, clave, ok := idDeApunte(w, r)
	if !ok {
		return
	}
	var entrada descarteEntrada
	if !leerOpcional(w, r, &entrada) { // sin cuerpo = sin motivo = 422, no un 400
		return
	}
	motivo := strings.TrimSpace(entrada.Motivo)
	if utf8.RuneCountInString(motivo) < minimoDelMotivo {
		httpx.FalloConCodigo(w, http.StatusUnprocessableEntity,
			fmt.Sprintf("Descartar exige un motivo escrito de al menos %d caracteres: queda anotado con tu nombre y la hora.", minimoDelMotivo),
			CodigoMotivoObligatorio)
		return
	}
	ctx := r.Context()
	nombre := textoOpcional(quien.Nombre, topeTextoDeAuditoria)

	var descartado sqlc.DescartarRevisionApunteRow
	err := s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		var err error
		descartado, err = q.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{
			Revisor: quien.Persona, RevisorNombre: nombre, Motivo: motivo,
			AparatoID: aparato, Clave: clave, Sucursal: alcance(quien.Alcance()),
		})
		if err != nil {
			return err
		}
		_, err = q.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{
			AparatoID: aparato, Clave: clave, Accion: "descartar", Por: quien.Persona, PorNombre: nombre,
			Rol: &rol, Resultado: "descartado", Motivo: &motivo,
		})
		return err
	})
	switch {
	case store.SinFilas(err):
		s.porQueNo(ctx, quien, aparato, clave).contesta(w)
		return
	case err != nil:
		s.log.Error("no se pudo descartar", "aparato", aparato, "clave", clave, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo descartar. Nada cambió: vuelve a intentarlo.")
		return
	}
	s.log.Info("revisión: descartado", "revisor", quien.Persona, "rol", rol, "aparato", aparato, "clave", clave,
		"entrega", descartado.EntregaID)
	httpx.JSON(w, http.StatusOK, resultadosSalida{Resultados: []resultadoDeRevision{{
		Clave: clave, Estado: string(descartado.Estado), Motivo: motivo,
		DecididoPorNombre: descartado.DecididoPorNombre, DecididoAt: hora(descartado.DecididoAt),
	}}})
}

// leerOpcional descodifica un cuerpo PEQUEÑO que puede no venir: vacío vale (queda el valor cero); roto, 400.
func leerOpcional(w http.ResponseWriter, r *http.Request, destino any) bool {
	defer r.Body.Close()
	err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(destino)
	if err == nil || errors.Is(err, io.EOF) {
		return true
	}
	httpx.Fallo(w, http.StatusBadRequest, "El cuerpo de la petición no es JSON válido")
	return false
}
