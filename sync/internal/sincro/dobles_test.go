package sincro

import (
	"context"
	"encoding/json"
	"log/slog"
	"maps"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// Los dobles. Son del Querier GENERADO, no de una interfaz inventada para las pruebas: lo
// que se prueba aquí es lo que hace este servicio con las mismas consultas que corren en
// producción, y si mañana cambia una firma de sqlc esto deja de compilar, que es justo lo
// que tiene que pasar.

const (
	// La hora del SERVIDOR en las pruebas. Fija, porque media prueba consiste en
	// distinguirla de la del aparato.
	ahoraServidor = "2026-09-14T11:02:31.481Z"
)

func enPunto(t *testing.T, texto string) time.Time {
	t.Helper()
	v, err := time.Parse(time.RFC3339Nano, texto)
	if err != nil {
		t.Fatalf("fecha de prueba mal escrita %q: %v", texto, err)
	}
	return v.UTC()
}

// ---------------------------------------------------------------------------
// La base, en memoria
// ---------------------------------------------------------------------------

type baseFalsa struct {
	// Lo que no esté implementado abajo no se usa en este servicio. Si alguna prueba lo
	// llama, revienta con el método a la vista en vez de devolver un cero en silencio.
	sqlc.Querier

	aparatos      map[uuid.UUID]sqlc.Aparato
	estados       map[uuid.UUID]sqlc.AparatoEstado
	apuntes       map[string]sqlc.Apunte
	rechazos      map[string]sqlc.ApuntesRechazado
	provisionales map[string]uuid.UUID

	// Espías: lo que hay que poder mirar desde las pruebas.
	bajadas        []sqlc.AnotarBajadaParams
	subidas        []sqlc.AnotarSubidaParams
	filtrosDePanel []pgtype.UUID
	tocado         int

	// Para probar que el rechazo y su motivo entran juntos o no entra ninguno.
	fallaElMotivo bool
}

var _ store.Datos = (*baseFalsa)(nil)

func nuevaBase() *baseFalsa {
	return &baseFalsa{
		aparatos:      map[uuid.UUID]sqlc.Aparato{},
		estados:       map[uuid.UUID]sqlc.AparatoEstado{},
		apuntes:       map[string]sqlc.Apunte{},
		rechazos:      map[string]sqlc.ApuntesRechazado{},
		provisionales: map[string]uuid.UUID{},
	}
}

func llave(aparato uuid.UUID, clave string) string { return aparato.String() + "|" + clave }

// EnTransaccion con foto y vuelta atrás. Un doble que se limitara a llamar a la función no
// probaría nada de lo que importa: que si el motivo no entra, el apunte NO se queda marcado
// como rechazado. Eso es un rechazo en silencio, que es lo que todo esto viene a impedir.
func (b *baseFalsa) EnTransaccion(ctx context.Context, fn func(sqlc.Querier) error) error {
	foto := struct {
		apuntes  map[string]sqlc.Apunte
		rechazos map[string]sqlc.ApuntesRechazado
		provis   map[string]uuid.UUID
	}{
		apuntes:  maps.Clone(b.apuntes),
		rechazos: maps.Clone(b.rechazos),
		provis:   maps.Clone(b.provisionales),
	}
	if err := fn(b); err != nil {
		b.apuntes, b.rechazos, b.provisionales = foto.apuntes, foto.rechazos, foto.provis
		return err
	}
	return nil
}

func (b *baseFalsa) AltaAparato(ctx context.Context, arg sqlc.AltaAparatoParams) (sqlc.Aparato, error) {
	a := sqlc.Aparato{
		ID:       uuid.New(),
		Persona:  arg.Persona,
		BranchID: arg.BranchID,
		Nombre:   arg.Nombre,
	}
	b.aparatos[a.ID] = a
	return a, nil
}

func (b *baseFalsa) AparatoPorId(ctx context.Context, id uuid.UUID) (sqlc.Aparato, error) {
	a, hay := b.aparatos[id]
	if !hay {
		return sqlc.Aparato{}, pgx.ErrNoRows
	}
	return a, nil
}

func (b *baseFalsa) TocarAparato(ctx context.Context, id uuid.UUID) error {
	b.tocado++
	return nil
}

func (b *baseFalsa) AbrirEstado(ctx context.Context, aparato uuid.UUID) error {
	if _, hay := b.estados[aparato]; !hay {
		b.estados[aparato] = sqlc.AparatoEstado{AparatoID: aparato}
	}
	return nil
}

func (b *baseFalsa) EstadoDeAparato(ctx context.Context, id uuid.UUID) (sqlc.EstadoDeAparatoRow, error) {
	a, hay := b.aparatos[id]
	e, hayEstado := b.estados[id]
	if !hay || !hayEstado {
		return sqlc.EstadoDeAparatoRow{}, pgx.ErrNoRows
	}
	return sqlc.EstadoDeAparatoRow{
		ID: a.ID, Persona: a.Persona, BranchID: a.BranchID, Nombre: a.Nombre,
		VistoAt: a.VistoAt, AltaAt: a.CreatedAt,
		BajadaAt: e.BajadaAt, BajadaHasta: e.BajadaHasta, SubidaAt: e.SubidaAt,
		Pendientes: e.Pendientes, Rechazados: e.Rechazados,
	}, nil
}

func (b *baseFalsa) AnotarBajada(ctx context.Context, arg sqlc.AnotarBajadaParams) error {
	b.bajadas = append(b.bajadas, arg)
	e := b.estados[arg.AparatoID]
	e.AparatoID = arg.AparatoID
	e.BajadaHasta = arg.BajadaHasta
	e.BajadaAt = arg.BajadaHasta
	b.estados[arg.AparatoID] = e
	return nil
}

func (b *baseFalsa) AnotarSubida(ctx context.Context, arg sqlc.AnotarSubidaParams) error {
	b.subidas = append(b.subidas, arg)
	e := b.estados[arg.AparatoID]
	e.AparatoID = arg.AparatoID
	e.Pendientes = arg.Pendientes
	e.Rechazados += arg.RechazadosDelLote
	e.SubidaAt = marca(enPuntoFijo())
	b.estados[arg.AparatoID] = e
	return nil
}

func enPuntoFijo() time.Time {
	v, _ := time.Parse(time.RFC3339Nano, ahoraServidor)
	return v.UTC()
}

func (b *baseFalsa) BuscarApunte(ctx context.Context, arg sqlc.BuscarApunteParams) (sqlc.BuscarApunteRow, error) {
	p, hay := b.apuntes[llave(arg.AparatoID, arg.Clave)]
	if !hay {
		return sqlc.BuscarApunteRow{}, pgx.ErrNoRows
	}
	fila := sqlc.BuscarApunteRow{
		AparatoID: p.AparatoID, Clave: p.Clave, Metodo: p.Metodo, Ruta: p.Ruta,
		Estado: p.Estado, IDCreado: p.IDCreado, HechoAt: p.HechoAt, CreatedAt: p.CreatedAt,
		// Lo que se cayó aquella vez. Va en la propia fila —no en un JOIN— porque a
		// diferencia del motivo, esto es del apunte y no de la bandeja.
		Descartados: p.Descartados,
	}
	// El LEFT JOIN con la bandeja: el motivo vive ahí y sólo ahí.
	if r, hayRechazo := b.rechazos[llave(arg.AparatoID, arg.Clave)]; hayRechazo {
		motivo := r.Motivo
		fila.Motivo = &motivo
	}
	return fila, nil
}

func (b *baseFalsa) AnotarApunteAplicado(ctx context.Context, arg sqlc.AnotarApunteAplicadoParams) (sqlc.Apunte, error) {
	return b.guardarApunte(sqlc.Apunte{
		AparatoID: arg.AparatoID, Clave: arg.Clave, Metodo: arg.Metodo, Ruta: arg.Ruta,
		Estado: sqlc.ApunteEstadoAplicado, IDCreado: arg.IDCreado, HechoAt: arg.HechoAt,
		Descartados: arg.Descartados,
	})
}

func (b *baseFalsa) AnotarApunteRechazado(ctx context.Context, arg sqlc.AnotarApunteRechazadoParams) (sqlc.Apunte, error) {
	return b.guardarApunte(sqlc.Apunte{
		AparatoID: arg.AparatoID, Clave: arg.Clave, Metodo: arg.Metodo, Ruta: arg.Ruta,
		Estado: sqlc.ApunteEstadoRechazado, HechoAt: arg.HechoAt,
	})
}

func (b *baseFalsa) guardarApunte(p sqlc.Apunte) (sqlc.Apunte, error) {
	k := llave(p.AparatoID, p.Clave)
	if _, hay := b.apuntes[k]; hay {
		// La primaria es (aparato_id, clave): esto en Postgres sería una violación de
		// unicidad, y que aquí también lo sea es lo que deja ver un doble aplicado.
		return sqlc.Apunte{}, errUnicidad
	}
	p.CreatedAt = marca(enPuntoFijo())
	b.apuntes[k] = p
	return p, nil
}

func (b *baseFalsa) AnotarRechazo(ctx context.Context, arg sqlc.AnotarRechazoParams) (sqlc.ApuntesRechazado, error) {
	if b.fallaElMotivo {
		return sqlc.ApuntesRechazado{}, errMotivo
	}
	k := llave(arg.AparatoID, arg.Clave)
	if _, hay := b.rechazos[k]; hay {
		return sqlc.ApuntesRechazado{}, errUnicidad
	}
	r := sqlc.ApuntesRechazado{
		ID: uuid.New(), AparatoID: arg.AparatoID, Clave: arg.Clave,
		Motivo: arg.Motivo, Cuerpo: arg.Cuerpo, RechazadoAt: marca(enPuntoFijo()),
	}
	b.rechazos[k] = r
	return r, nil
}

func (b *baseFalsa) AnotarProvisional(ctx context.Context, arg sqlc.AnotarProvisionalParams) (sqlc.IdsProvisionale, error) {
	k := llave(arg.AparatoID, arg.Provisional)
	// ON CONFLICT DO UPDATE SET id_real = el que ya había: la traducción buena es la
	// primera.
	if id, hay := b.provisionales[k]; hay {
		return sqlc.IdsProvisionale{AparatoID: arg.AparatoID, Provisional: arg.Provisional, IDReal: id}, nil
	}
	b.provisionales[k] = arg.IDReal
	return sqlc.IdsProvisionale{AparatoID: arg.AparatoID, Provisional: arg.Provisional, IDReal: arg.IDReal}, nil
}

func (b *baseFalsa) ResolverProvisional(ctx context.Context, arg sqlc.ResolverProvisionalParams) (uuid.UUID, error) {
	id, hay := b.provisionales[llave(arg.AparatoID, arg.Provisional)]
	if !hay {
		return uuid.Nil, pgx.ErrNoRows
	}
	return id, nil
}

func (b *baseFalsa) PanelDeEstado(ctx context.Context, sucursal pgtype.UUID) ([]sqlc.PanelDeEstadoRow, error) {
	b.filtrosDePanel = append(b.filtrosDePanel, sucursal)
	var filas []sqlc.PanelDeEstadoRow
	for id, a := range b.aparatos {
		if !cuadraSucursal(sucursal, a.BranchID) {
			continue
		}
		e := b.estados[id]
		filas = append(filas, sqlc.PanelDeEstadoRow{
			ID: a.ID, Persona: a.Persona, BranchID: a.BranchID, Nombre: a.Nombre,
			VistoAt: a.VistoAt, AltaAt: a.CreatedAt,
			BajadaAt: e.BajadaAt, BajadaHasta: e.BajadaHasta, SubidaAt: e.SubidaAt,
			Pendientes: e.Pendientes, Rechazados: e.Rechazados,
		})
	}
	// ORDER BY subida_at ASC NULLS FIRST: el que nunca subió, arriba.
	sort.Slice(filas, func(i, j int) bool {
		a, b := filas[i].SubidaAt, filas[j].SubidaAt
		if a.Valid != b.Valid {
			return !a.Valid
		}
		return a.Time.Before(b.Time)
	})
	return filas, nil
}

func (b *baseFalsa) RechazosSinAtender(ctx context.Context, sucursal pgtype.UUID) ([]sqlc.RechazosSinAtenderRow, error) {
	var filas []sqlc.RechazosSinAtenderRow
	for k, r := range b.rechazos {
		if r.AtendidoAt.Valid {
			continue
		}
		a := b.aparatos[r.AparatoID]
		if !cuadraSucursal(sucursal, a.BranchID) {
			continue
		}
		p := b.apuntes[k]
		filas = append(filas, sqlc.RechazosSinAtenderRow{
			ID: r.ID, AparatoID: r.AparatoID, Clave: r.Clave, Motivo: r.Motivo,
			RechazadoAt: r.RechazadoAt, Cuerpo: r.Cuerpo,
			Persona: a.Persona, BranchID: a.BranchID, Nombre: a.Nombre,
			Metodo: p.Metodo, Ruta: p.Ruta, HechoAt: p.HechoAt,
		})
	}
	sort.Slice(filas, func(i, j int) bool { return filas[i].Clave < filas[j].Clave })
	return filas, nil
}

func (b *baseFalsa) RechazosSinAtenderPorSucursal(ctx context.Context, sucursal pgtype.UUID) ([]sqlc.RechazosSinAtenderPorSucursalRow, error) {
	cuenta := map[uuid.UUID]int64{}
	for _, r := range b.rechazos {
		if r.AtendidoAt.Valid {
			continue
		}
		a := b.aparatos[r.AparatoID]
		if !cuadraSucursal(sucursal, a.BranchID) {
			continue
		}
		cuenta[a.BranchID]++
	}
	var filas []sqlc.RechazosSinAtenderPorSucursalRow
	for id, n := range cuenta {
		filas = append(filas, sqlc.RechazosSinAtenderPorSucursalRow{BranchID: id, SinAtender: n})
	}
	return filas, nil
}

// cuadraSucursal es el `(narg IS NULL OR branch_id = narg)` de las consultas: NULL quiere
// decir todas, o sea el Super Admin.
func cuadraSucursal(filtro pgtype.UUID, sucursal uuid.UUID) bool {
	if !filtro.Valid {
		return true
	}
	return uuid.UUID(filtro.Bytes) == sucursal
}

type errorFalso string

func (e errorFalso) Error() string { return string(e) }

const (
	errUnicidad = errorFalso("clave duplicada (aparato_id, clave)")
	errMotivo   = errorFalso("no se pudo guardar el motivo")
	errCaida    = errorFalso("el reparto no contesta")
)

// ---------------------------------------------------------------------------
// El reparto, falso
// ---------------------------------------------------------------------------

// aplicadorFalso hace de `reparto-api`: apunta lo que le llega, en el orden en que le
// llega, y guarda el último valor de cada cosa. Ese «último valor» es lo que deja probar
// que una corrección no se la come la marca anterior.
type aplicadorFalso struct {
	llamadas []Peticion
	// Qué contesta. Si es nil, aplica todo y devuelve un id nuevo cuando el apunte
	// declaraba un provisional.
	responde func(p Peticion) (*uuid.UUID, error)
	// Lo que el reparto deja FUERA aunque el apunte entre, en crudo. Nil casi siempre:
	// un armado normal no descarta a nadie.
	descarta func(p Peticion) json.RawMessage
	// El estado del reparto: ruta -> último cuerpo aplicado.
	estado map[string]string
}

func nuevoAplicador() *aplicadorFalso {
	return &aplicadorFalso{estado: map[string]string{}}
}

func (a *aplicadorFalso) Aplicar(ctx context.Context, p Peticion) (Aplicado, error) {
	a.llamadas = append(a.llamadas, p)
	var fuera json.RawMessage
	if a.descarta != nil {
		fuera = a.descarta(p)
	}
	if a.responde != nil {
		id, err := a.responde(p)
		if err != nil {
			return Aplicado{}, err
		}
		a.estado[p.Ruta] = string(p.Cuerpo)
		return Aplicado{ID: id, Descartados: fuera}, nil
	}
	a.estado[p.Ruta] = string(p.Cuerpo)
	if p.Clave != "" && strings.HasPrefix(p.Metodo, "POST") {
		id := uuid.New()
		return Aplicado{ID: &id, Descartados: fuera}, nil
	}
	return Aplicado{Descartados: fuera}, nil
}

func (a *aplicadorFalso) rutas() []string {
	var r []string
	for _, l := range a.llamadas {
		r = append(r, l.Ruta)
	}
	return r
}

type origenFalso struct {
	ventanas []Ventana
	cambios  Cambios
	truncado bool
	// hasta es lo que el reparto dice haber servido DE VERDAD. Cero = un reparto que no la
	// manda, y entonces vale la del propio servicio.
	hasta     time.Time
	continuar string
	err       error
	// responder, si está, manda sobre todo lo demás: sirve para encadenar tandas de
	// verdad, que es la única forma de ver un truncamiento que pierde filas.
	responder func(v Ventana) Bajada
}

func (o *origenFalso) Diferencias(_ context.Context, v Ventana) (Bajada, error) {
	o.ventanas = append(o.ventanas, v)
	if o.err != nil {
		return Bajada{}, o.err
	}
	if o.responder != nil {
		return o.responder(v), nil
	}
	return Bajada{
		Cambios:   o.cambios,
		Hasta:     o.hasta,
		Truncado:  o.truncado,
		Continuar: o.continuar,
	}, nil
}

// ---------------------------------------------------------------------------
// El montaje
// ---------------------------------------------------------------------------

type banco struct {
	t         *testing.T
	servicio  *Servicio
	mux       *http.ServeMux
	base      *baseFalsa
	aplicador *aplicadorFalso
	origen    *origenFalso
	sucursal  uuid.UUID
	aparato   sqlc.Aparato
	quien     identidad.Identidad
}

func montar(t *testing.T) *banco {
	t.Helper()
	base := nuevaBase()
	aplicador := nuevoAplicador()
	origen := &origenFalso{}

	s := Nuevo(Opciones{
		Datos:     base,
		Origen:    origen,
		Aplicador: aplicador,
		Ahora:     func() time.Time { return enPuntoFijo() },
		Log:       slog.New(slog.NewTextHandler(discard{}, &slog.HandlerOptions{Level: slog.LevelError})),
	})
	mux := http.NewServeMux()
	s.Rutas(mux)

	sucursal := uuid.New()
	aparato, _ := base.AltaAparato(context.Background(), sqlc.AltaAparatoParams{
		Persona: "persona-de-palma", BranchID: sucursal,
	})
	_ = base.AbrirEstado(context.Background(), aparato.ID)

	return &banco{
		t: t, servicio: s, mux: mux, base: base, aplicador: aplicador, origen: origen,
		sucursal: sucursal, aparato: aparato,
		quien: identidad.Identidad{Persona: "persona-de-palma", Sucursal: sucursal},
	}
}

type discard struct{}

func (discard) Write(p []byte) (int, error) { return len(p), nil }

func (b *banco) pedir(metodo, ruta string, cuerpo any, quien identidad.Identidad) *httptest.ResponseRecorder {
	b.t.Helper()
	var lector *strings.Reader
	if cuerpo != nil {
		datos, err := json.Marshal(cuerpo)
		if err != nil {
			b.t.Fatalf("no se pudo componer el cuerpo: %v", err)
		}
		lector = strings.NewReader(string(datos))
	} else {
		lector = strings.NewReader("")
	}
	req := httptest.NewRequest(metodo, ruta, lector)
	req = req.WithContext(identidad.Con(req.Context(), quien))
	w := httptest.NewRecorder()
	b.mux.ServeHTTP(w, req)
	return w
}

// subir manda un lote y devuelve los resultados apunte por apunte.
func (b *banco) subir(apuntes []apunteEntrada, quien identidad.Identidad) (*httptest.ResponseRecorder, []resultado) {
	b.t.Helper()
	w := b.pedir(http.MethodPost, "/sync/subida", loteEntrada{
		Aparato: b.aparato.ID.String(),
		Apuntes: apuntes,
	}, quien)
	if w.Code != http.StatusOK {
		return w, nil
	}
	var salida subidaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		b.t.Fatalf("la respuesta de la subida no se entiende: %v (%s)", err, w.Body.String())
	}
	return w, salida.Resultados
}

func (b *banco) errorDe(w *httptest.ResponseRecorder) string {
	b.t.Helper()
	var sobre struct {
		Error string `json:"error"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &sobre)
	return sobre.Error
}
