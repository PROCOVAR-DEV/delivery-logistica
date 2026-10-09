package sincro

import (
	"context"
	"maps"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// LOS DOBLES DE LA BANDEJA DE REVISIÓN. Mismo criterio que `dobles_test.go`: son del `Querier` GENERADO, y
// cada método hace lo que hace su SQL en `db/queries/revision.sql` (el alcance de sucursal, `persona <>
// revisor`, `WHERE estado IN (…)`, `ON CONFLICT DO NOTHING`). Que el doble no se invente nada lo comprueba
// `revision_motor_real_test.go`, que corre el mismo guion contra Postgres de verdad.
//
// Hay DOS piezas, y no es capricho: `dobles_test.go` es de otro paquete de trabajo y no se toca, y un campo
// nuevo en `baseFalsa` obligaría a tocarlo.
//
//   - Los métodos de `baseFalsa` de aquí abajo son los MÍNIMOS para que la subida normal y el panel
//     (que ahora preguntan por la bandeja) sigan funcionando con la base de siempre: no hay nada entregado.
//   - `baseRevisionFalsa` envuelve a la base de siempre y le añade una bandeja de verdad, con su
//     transacción (foto y vuelta atrás) y sus espías. Es lo que montan las pruebas de la revisión.

// -- lo mínimo, en la base de siempre -----------------------------------------------------------

func (b *baseFalsa) EstadoDeRevisionDeApunte(context.Context, sqlc.EstadoDeRevisionDeApunteParams) (sqlc.EstadoDeRevisionDeApunteRow, error) {
	return sqlc.EstadoDeRevisionDeApunteRow{}, pgx.ErrNoRows
}

func (b *baseFalsa) RevisionSinDecidirPorSucursal(context.Context, pgtype.UUID) ([]sqlc.RevisionSinDecidirPorSucursalRow, error) {
	return nil, nil
}

// -- la bandeja ------------------------------------------------------------------------------

type memoriaDeRevision struct {
	entregas   map[uuid.UUID]sqlc.RevisionEntrega
	apuntes    map[string]sqlc.RevisionApunte
	decisiones []sqlc.RevisionDecisione
	reloj      int // cada escritura avanza un segundo: `updated_at` distingue lo primero de lo último

	// Espías.
	bloqueos []uuid.UUID
	// alInsertar se llama justo ANTES de resolver el `ON CONFLICT` de un `InsertarRevisionApunte`: deja a una
	// prueba colar «otra petición que llegó entre mirar y escribir».
	alInsertar func(sqlc.InsertarRevisionApunteParams)
	// fallaAlInsertar hace que el insert de la clave dicha devuelva este error (la transacción se deshace).
	fallaAlInsertar map[string]error
}

func (m *memoriaDeRevision) foto() *memoriaDeRevision {
	return &memoriaDeRevision{
		entregas: maps.Clone(m.entregas), apuntes: maps.Clone(m.apuntes),
		decisiones: append([]sqlc.RevisionDecisione(nil), m.decisiones...), reloj: m.reloj,
	}
}

func (m *memoriaDeRevision) restaurar(f *memoriaDeRevision) {
	m.entregas, m.apuntes, m.decisiones, m.reloj = f.entregas, f.apuntes, f.decisiones, f.reloj
}

// ahora: el reloj de la base. Cada llamada es un segundo más tarde que la anterior.
func (m *memoriaDeRevision) ahora() pgtype.Timestamptz {
	m.reloj++
	return marca(enPuntoFijo().Add(time.Duration(m.reloj) * time.Second))
}

type baseRevisionFalsa struct {
	*baseFalsa
	m *memoriaDeRevision
}

var _ store.Datos = (*baseRevisionFalsa)(nil)

func nuevaBaseConRevision(b *baseFalsa) *baseRevisionFalsa {
	return &baseRevisionFalsa{baseFalsa: b, m: &memoriaDeRevision{
		entregas: map[uuid.UUID]sqlc.RevisionEntrega{}, apuntes: map[string]sqlc.RevisionApunte{},
		fallaAlInsertar: map[string]error{},
	}}
}

// EnTransaccion con foto y vuelta atrás de la bandeja ADEMÁS de lo de siempre: una entrega que no cabe en
// el cupo, o con una huella distinta a mitad, no deja NADA guardado.
func (b *baseRevisionFalsa) EnTransaccion(ctx context.Context, fn func(sqlc.Querier) error) error {
	foto := b.m.foto()
	err := b.baseFalsa.EnTransaccion(ctx, func(sqlc.Querier) error { return fn(b) })
	if err != nil {
		b.m.restaurar(foto)
	}
	return err
}

func esVivo(e sqlc.RevisionEstado) bool {
	return e == sqlc.RevisionEstadoEnRevision || e == sqlc.RevisionEstadoAplicando || e == sqlc.RevisionEstadoRechazado
}

// dentroDelAlcance es el `(narg IS NULL OR e.branch_id = narg)` de las consultas.
func (b *baseRevisionFalsa) dentroDelAlcance(sucursal pgtype.UUID, entrega uuid.UUID) bool {
	return cuadraSucursal(sucursal, b.m.entregas[entrega].BranchID)
}

func (b *baseRevisionFalsa) AltaRevisionEntrega(_ context.Context, arg sqlc.AltaRevisionEntregaParams) (sqlc.RevisionEntrega, error) {
	for _, e := range b.m.entregas {
		if e.AparatoID == arg.AparatoID && e.TokenJti == arg.TokenJti { // ON CONFLICT (aparato_id, token_jti)
			return e, nil
		}
	}
	e := sqlc.RevisionEntrega{
		ID: uuid.New(), AparatoID: arg.AparatoID, Persona: arg.Persona, PersonaNombre: arg.PersonaNombre,
		BranchID: arg.BranchID, TokenJti: arg.TokenJti, DesdeIp: arg.DesdeIp, Agente: arg.Agente,
		VersionApp: arg.VersionApp, EntregadaAt: b.m.ahora(),
	}
	b.m.entregas[e.ID] = e
	return e, nil
}

func (b *baseRevisionFalsa) BloquearRevisionDeSucursal(_ context.Context, sucursal uuid.UUID) error {
	b.m.bloqueos = append(b.m.bloqueos, sucursal)
	return nil
}

func (b *baseRevisionFalsa) EstadoDeRevisionDeApunte(_ context.Context, arg sqlc.EstadoDeRevisionDeApunteParams) (sqlc.EstadoDeRevisionDeApunteRow, error) {
	a, hay := b.m.apuntes[llave(arg.AparatoID, arg.Clave)]
	if !hay {
		return sqlc.EstadoDeRevisionDeApunteRow{}, pgx.ErrNoRows
	}
	return sqlc.EstadoDeRevisionDeApunteRow{
		AparatoID: a.AparatoID, Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
		Huella: a.Huella, Motivo: a.Motivo, IDCreado: a.IDCreado, Descartados: a.Descartados,
		DecididoPorNombre: a.DecididoPorNombre, DecididoAt: a.DecididoAt,
	}, nil
}

func (b *baseRevisionFalsa) InsertarRevisionApunte(_ context.Context, arg sqlc.InsertarRevisionApunteParams) (sqlc.RevisionApunte, error) {
	if b.m.alInsertar != nil {
		b.m.alInsertar(arg)
	}
	if err := b.m.fallaAlInsertar[arg.Clave]; err != nil {
		return sqlc.RevisionApunte{}, err
	}
	k := llave(arg.AparatoID, arg.Clave)
	if _, hay := b.m.apuntes[k]; hay { // ON CONFLICT (aparato_id, clave) DO NOTHING RETURNING → ninguna fila
		return sqlc.RevisionApunte{}, pgx.ErrNoRows
	}
	orden := int32(0)
	for _, a := range b.m.apuntes {
		if a.AparatoID == arg.AparatoID && a.Orden >= orden {
			orden = a.Orden + 1
		}
	}
	ahora := b.m.ahora()
	a := sqlc.RevisionApunte{
		AparatoID: arg.AparatoID, Clave: arg.Clave, EntregaID: arg.EntregaID, Orden: orden,
		Metodo: arg.Metodo, Ruta: arg.Ruta, Cuerpo: arg.Cuerpo, Provisional: arg.Provisional,
		HechoAt: arg.HechoAt, Huella: arg.Huella, ResumenDelAparato: arg.ResumenDelAparato,
		Estado: sqlc.RevisionEstadoEnRevision, CreatedAt: ahora, UpdatedAt: ahora,
	}
	b.m.apuntes[k] = a
	return a, nil
}

func (b *baseRevisionFalsa) CupoDeRevision(_ context.Context, arg sqlc.CupoDeRevisionParams) (sqlc.CupoDeRevisionRow, error) {
	var c sqlc.CupoDeRevisionRow
	for _, a := range b.m.apuntes {
		e := b.m.entregas[a.EntregaID]
		if !esVivo(a.Estado) || (e.Persona != arg.Persona && e.BranchID != arg.Sucursal) {
			continue
		}
		if e.Persona == arg.Persona {
			c.DeLaPersona++
			if a.Cuerpo != nil {
				c.BytesDeLaPersona += int64(len(*a.Cuerpo)) // octet_length: bytes
			}
		}
		if e.BranchID == arg.Sucursal {
			c.DeLaSucursal++
		}
	}
	return c, nil
}

func (b *baseRevisionFalsa) RevisionDeAparato(_ context.Context, arg sqlc.RevisionDeAparatoParams) ([]sqlc.RevisionDeAparatoRow, error) {
	var filas []sqlc.RevisionApunte
	for _, a := range b.m.apuntes {
		if a.AparatoID == arg.AparatoID {
			filas = append(filas, a)
		}
	}
	sort.Slice(filas, func(i, j int) bool { // lo vivo primero, lo más reciente, y la clave
		if esVivo(filas[i].Estado) != esVivo(filas[j].Estado) {
			return esVivo(filas[i].Estado)
		}
		if !filas[i].UpdatedAt.Time.Equal(filas[j].UpdatedAt.Time) {
			return filas[i].UpdatedAt.Time.After(filas[j].UpdatedAt.Time)
		}
		return filas[i].Clave < filas[j].Clave
	})
	if int32(len(filas)) > arg.Limite {
		filas = filas[:arg.Limite]
	}
	salida := make([]sqlc.RevisionDeAparatoRow, 0, len(filas))
	for _, a := range filas {
		salida = append(salida, sqlc.RevisionDeAparatoRow{
			Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
			DecididoPorNombre: a.DecididoPorNombre, DecididoAt: a.DecididoAt, Motivo: a.Motivo,
			IDCreado: a.IDCreado, Descartados: a.Descartados, UpdatedAt: a.UpdatedAt,
		})
	}
	return salida, nil
}

func (b *baseRevisionFalsa) RevisionSinDecidirPorSucursal(_ context.Context, sucursal pgtype.UUID) ([]sqlc.RevisionSinDecidirPorSucursalRow, error) {
	cuenta := map[uuid.UUID]int64{}
	for _, a := range b.m.apuntes {
		e := b.m.entregas[a.EntregaID]
		if esVivo(a.Estado) && cuadraSucursal(sucursal, e.BranchID) {
			cuenta[e.BranchID]++
		}
	}
	var filas []sqlc.RevisionSinDecidirPorSucursalRow
	for id, n := range cuenta {
		filas = append(filas, sqlc.RevisionSinDecidirPorSucursalRow{BranchID: id, EnRevision: n})
	}
	sort.Slice(filas, func(i, j int) bool { return filas[i].EnRevision > filas[j].EnRevision })
	return filas, nil
}

// -- el revisor (S2) -------------------------------------------------------------------------

func (b *baseRevisionFalsa) ListarRevisionParaRevisor(_ context.Context, arg sqlc.ListarRevisionParaRevisorParams) ([]sqlc.ListarRevisionParaRevisorRow, error) {
	var filas []sqlc.ListarRevisionParaRevisorRow
	for _, a := range b.m.apuntes {
		e := b.m.entregas[a.EntregaID]
		if !cuadraSucursal(arg.Sucursal, e.BranchID) || (arg.SoloVivos && !esVivo(a.Estado)) ||
			(arg.Estado != nil && a.Estado != *arg.Estado) {
			continue
		}
		filas = append(filas, sqlc.ListarRevisionParaRevisorRow{
			AparatoID: a.AparatoID, Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
			Metodo: a.Metodo, Ruta: a.Ruta, HechoAt: a.HechoAt, ResumenDelAparato: a.ResumenDelAparato,
			DecididoPor: a.DecididoPor, DecididoPorNombre: a.DecididoPorNombre, DecididoAt: a.DecididoAt,
			Motivo: a.Motivo, IDCreado: a.IDCreado, Intentos: a.Intentos, UpdatedAt: a.UpdatedAt,
			Persona: e.Persona, PersonaNombre: e.PersonaNombre, BranchID: e.BranchID, EntregadaAt: e.EntregadaAt,
			AparatoNombre: nombreEnLaBandeja(b.baseFalsa.aparatos[a.AparatoID].Nombre),
		})
	}
	sort.Slice(filas, func(i, j int) bool { // ORDER BY e.entregada_at, a.orden, a.clave
		if !filas[i].EntregadaAt.Time.Equal(filas[j].EntregadaAt.Time) {
			return filas[i].EntregadaAt.Time.Before(filas[j].EntregadaAt.Time)
		}
		if filas[i].Orden != filas[j].Orden {
			return filas[i].Orden < filas[j].Orden
		}
		return filas[i].Clave < filas[j].Clave
	})
	if int32(len(filas)) > arg.Limite {
		filas = filas[:arg.Limite]
	}
	return filas, nil
}

func (b *baseRevisionFalsa) RevisionApunteDeRevisor(_ context.Context, arg sqlc.RevisionApunteDeRevisorParams) (sqlc.RevisionApunteDeRevisorRow, error) {
	a, hay := b.m.apuntes[llave(arg.AparatoID, arg.Clave)]
	if !hay || !b.dentroDelAlcance(arg.Sucursal, a.EntregaID) {
		return sqlc.RevisionApunteDeRevisorRow{}, pgx.ErrNoRows
	}
	e := b.m.entregas[a.EntregaID]
	return sqlc.RevisionApunteDeRevisorRow{
		AparatoID: a.AparatoID, Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
		Metodo: a.Metodo, Ruta: a.Ruta, Cuerpo: a.Cuerpo, Provisional: a.Provisional, HechoAt: a.HechoAt,
		Huella: a.Huella, ResumenDelAparato: a.ResumenDelAparato, DecididoPor: a.DecididoPor,
		DecididoPorNombre: a.DecididoPorNombre, DecididoAt: a.DecididoAt, Motivo: a.Motivo, IDCreado: a.IDCreado,
		Descartados: a.Descartados, Intentos: a.Intentos, CreatedAt: a.CreatedAt, UpdatedAt: a.UpdatedAt,
		Persona: e.Persona, PersonaNombre: e.PersonaNombre, BranchID: e.BranchID, EntregadaAt: e.EntregadaAt,
		TokenJti: e.TokenJti, DesdeIp: e.DesdeIp, Agente: e.Agente, VersionApp: e.VersionApp,
		AparatoNombre: nombreEnLaBandeja(b.baseFalsa.aparatos[a.AparatoID].Nombre),
	}, nil
}

func (b *baseRevisionFalsa) RevisionDeEntrega(_ context.Context, arg sqlc.RevisionDeEntregaParams) ([]sqlc.RevisionDeEntregaRow, error) {
	var filas []sqlc.RevisionDeEntregaRow
	for _, a := range b.m.apuntes {
		if a.EntregaID != arg.EntregaID || !b.dentroDelAlcance(arg.Sucursal, a.EntregaID) {
			continue
		}
		e := b.m.entregas[a.EntregaID]
		filas = append(filas, sqlc.RevisionDeEntregaRow{
			AparatoID: a.AparatoID, Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
			Metodo: a.Metodo, Ruta: a.Ruta, Cuerpo: a.Cuerpo, Provisional: a.Provisional, HechoAt: a.HechoAt,
			Huella: a.Huella, ResumenDelAparato: a.ResumenDelAparato, DecididoPor: a.DecididoPor,
			DecididoPorNombre: a.DecididoPorNombre, DecididoAt: a.DecididoAt, Motivo: a.Motivo,
			IDCreado: a.IDCreado, Descartados: a.Descartados, Intentos: a.Intentos,
			Persona: e.Persona, PersonaNombre: e.PersonaNombre, BranchID: e.BranchID, EntregadaAt: e.EntregadaAt,
		})
	}
	sort.Slice(filas, func(i, j int) bool {
		if filas[i].Orden != filas[j].Orden {
			return filas[i].Orden < filas[j].Orden
		}
		return filas[i].Clave < filas[j].Clave
	})
	return filas, nil
}

// reclamar es el UPDATE común de `ReclamarRevisionApunte` y `ReclamarRevisionInterrumpida`.
func (b *baseRevisionFalsa) reclamar(aparato uuid.UUID, clave, revisor string, nombre *string, sucursal pgtype.UUID,
	permite func(sqlc.RevisionApunte) bool) (sqlc.RevisionApunte, error) {
	k := llave(aparato, clave)
	a, hay := b.m.apuntes[k]
	if !hay || !permite(a) || b.m.entregas[a.EntregaID].Persona == revisor || !b.dentroDelAlcance(sucursal, a.EntregaID) {
		return sqlc.RevisionApunte{}, pgx.ErrNoRows
	}
	a.Estado = sqlc.RevisionEstadoAplicando
	a.DecididoPor, a.DecididoPorNombre, a.DecididoAt = &revisor, nombre, b.m.ahora()
	a.UpdatedAt = b.m.ahora()
	b.m.apuntes[k] = a
	return a, nil
}

func (b *baseRevisionFalsa) ReclamarRevisionApunte(_ context.Context, arg sqlc.ReclamarRevisionApunteParams) (sqlc.ReclamarRevisionApunteRow, error) {
	a, err := b.reclamar(arg.AparatoID, arg.Clave, arg.Revisor, arg.RevisorNombre, arg.Sucursal, func(a sqlc.RevisionApunte) bool {
		return a.Estado == sqlc.RevisionEstadoEnRevision || a.Estado == sqlc.RevisionEstadoRechazado
	})
	if err != nil {
		return sqlc.ReclamarRevisionApunteRow{}, err
	}
	return sqlc.ReclamarRevisionApunteRow{
		AparatoID: a.AparatoID, Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
		Metodo: a.Metodo, Ruta: a.Ruta, Cuerpo: a.Cuerpo, Provisional: a.Provisional, HechoAt: a.HechoAt,
		Huella: a.Huella, DecididoPor: a.DecididoPor, DecididoPorNombre: a.DecididoPorNombre,
		DecididoAt: a.DecididoAt, Intentos: a.Intentos,
	}, nil
}

func (b *baseRevisionFalsa) ReclamarRevisionInterrumpida(_ context.Context, arg sqlc.ReclamarRevisionInterrumpidaParams) (sqlc.ReclamarRevisionInterrumpidaRow, error) {
	a, err := b.reclamar(arg.AparatoID, arg.Clave, arg.Revisor, arg.RevisorNombre, arg.Sucursal, func(a sqlc.RevisionApunte) bool {
		// `updated_at < now() - antigüedad`: el reloj de la base es el de las pruebas.
		return a.Estado == sqlc.RevisionEstadoAplicando &&
			a.UpdatedAt.Time.Before(enPuntoFijo().Add(time.Duration(b.m.reloj)*time.Second-time.Duration(arg.AntiguedadSegundos)*time.Second))
	})
	if err != nil {
		return sqlc.ReclamarRevisionInterrumpidaRow{}, err
	}
	return sqlc.ReclamarRevisionInterrumpidaRow{
		AparatoID: a.AparatoID, Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
		Metodo: a.Metodo, Ruta: a.Ruta, Cuerpo: a.Cuerpo, Provisional: a.Provisional, HechoAt: a.HechoAt,
		Huella: a.Huella, DecididoPor: a.DecididoPor, DecididoPorNombre: a.DecididoPorNombre,
		DecididoAt: a.DecididoAt, Intentos: a.Intentos,
	}, nil
}

// cerrar es el UPDATE común de los tres cierres: SÓLO desde `aplicando` y SÓLO por quien lo reclamó.
func (b *baseRevisionFalsa) cerrar(aparato uuid.UUID, clave, revisor string, cambia func(*sqlc.RevisionApunte)) (sqlc.RevisionApunte, error) {
	k := llave(aparato, clave)
	a, hay := b.m.apuntes[k]
	if !hay || a.Estado != sqlc.RevisionEstadoAplicando || a.DecididoPor == nil || *a.DecididoPor != revisor {
		return sqlc.RevisionApunte{}, pgx.ErrNoRows
	}
	cambia(&a)
	a.UpdatedAt = b.m.ahora()
	b.m.apuntes[k] = a
	return a, nil
}

func (b *baseRevisionFalsa) CerrarRevisionComoAplicado(_ context.Context, arg sqlc.CerrarRevisionComoAplicadoParams) (sqlc.RevisionApunte, error) {
	return b.cerrar(arg.AparatoID, arg.Clave, arg.Revisor, func(a *sqlc.RevisionApunte) {
		a.Estado, a.Motivo, a.Intentos = sqlc.RevisionEstadoAplicado, nil, a.Intentos+1
		a.IDCreado, a.Descartados = arg.IDCreado, arg.Descartados
	})
}

func (b *baseRevisionFalsa) CerrarRevisionComoRechazado(_ context.Context, arg sqlc.CerrarRevisionComoRechazadoParams) (sqlc.RevisionApunte, error) {
	return b.cerrar(arg.AparatoID, arg.Clave, arg.Revisor, func(a *sqlc.RevisionApunte) {
		motivo := arg.Motivo
		a.Estado, a.Motivo, a.Intentos = sqlc.RevisionEstadoRechazado, &motivo, a.Intentos+1
	})
}

func (b *baseRevisionFalsa) DevolverRevisionAEnRevision(_ context.Context, arg sqlc.DevolverRevisionAEnRevisionParams) (sqlc.RevisionApunte, error) {
	return b.cerrar(arg.AparatoID, arg.Clave, arg.Revisor, func(a *sqlc.RevisionApunte) {
		a.Estado, a.Intentos = sqlc.RevisionEstadoEnRevision, a.Intentos+1
		a.DecididoPor, a.DecididoPorNombre, a.DecididoAt = nil, nil, pgtype.Timestamptz{}
	})
}

func (b *baseRevisionFalsa) DescartarRevisionApunte(_ context.Context, arg sqlc.DescartarRevisionApunteParams) (sqlc.DescartarRevisionApunteRow, error) {
	k := llave(arg.AparatoID, arg.Clave)
	a, hay := b.m.apuntes[k]
	if !hay || (a.Estado != sqlc.RevisionEstadoEnRevision && a.Estado != sqlc.RevisionEstadoRechazado) ||
		b.m.entregas[a.EntregaID].Persona == arg.Revisor || !b.dentroDelAlcance(arg.Sucursal, a.EntregaID) {
		return sqlc.DescartarRevisionApunteRow{}, pgx.ErrNoRows
	}
	// El CHECK de la base: un descarte sin motivo escrito (≥ 5 letras, sin contar los espacios de los lados) no existe.
	if len(trimEspacios(arg.Motivo)) < 5 {
		return sqlc.DescartarRevisionApunteRow{}, errCheckDelDescarte
	}
	motivo := arg.Motivo
	a.Estado, a.Motivo = sqlc.RevisionEstadoDescartado, &motivo
	a.DecididoPor, a.DecididoPorNombre, a.DecididoAt = &arg.Revisor, arg.RevisorNombre, b.m.ahora()
	a.UpdatedAt = b.m.ahora()
	b.m.apuntes[k] = a
	return sqlc.DescartarRevisionApunteRow{
		AparatoID: a.AparatoID, Clave: a.Clave, EntregaID: a.EntregaID, Orden: a.Orden, Estado: a.Estado,
		DecididoPor: a.DecididoPor, DecididoPorNombre: a.DecididoPorNombre, DecididoAt: a.DecididoAt, Motivo: a.Motivo,
	}, nil
}

const errCheckDelDescarte = errorFalso(`new row for relation "revision_apuntes" violates check constraint "revision_descarte_con_motivo"`)

func trimEspacios(s string) string {
	i, j := 0, len(s)
	for i < j && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r') {
		i++
	}
	for j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r') {
		j--
	}
	return s[i:j]
}

// -- el libro ----------------------------------------------------------------------------------

func (b *baseRevisionFalsa) AnotarRevisionDecision(_ context.Context, arg sqlc.AnotarRevisionDecisionParams) (sqlc.RevisionDecisione, error) {
	if _, hay := b.m.apuntes[llave(arg.AparatoID, arg.Clave)]; !hay { // la clave ajena
		return sqlc.RevisionDecisione{}, errorFalso("violates foreign key constraint")
	}
	d := sqlc.RevisionDecisione{
		ID: uuid.New(), AparatoID: arg.AparatoID, Clave: arg.Clave, Accion: arg.Accion, Por: arg.Por,
		PorNombre: arg.PorNombre, Rol: arg.Rol, Resultado: arg.Resultado, HttpEstado: arg.HttpEstado,
		Motivo: arg.Motivo, Cuando: b.m.ahora(),
	}
	b.m.decisiones = append(b.m.decisiones, d)
	return d, nil
}

func (b *baseRevisionFalsa) RevisionDecisionesDeApunte(_ context.Context, arg sqlc.RevisionDecisionesDeApunteParams) ([]sqlc.RevisionDecisione, error) {
	var salida []sqlc.RevisionDecisione
	for _, d := range b.m.decisiones {
		if d.AparatoID == arg.AparatoID && d.Clave == arg.Clave {
			salida = append(salida, d)
		}
	}
	return salida, nil
}
