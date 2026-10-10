package sincro

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// APLICAR LO QUE OTRO ENTREGÓ — `docs/bandeja-de-revision.md`, B.2 «Aplicar: lo que pasa y lo que NO puede
// pasar» y B.4. Es el sitio donde el payload de una persona SIN permiso se ejecuta con la autoridad de otra, y
// por eso cada paso tiene su porqué y su prueba (el riesgo 1 del diseño, «autoridad prestada»):
//
//  1. EL CANDADO. `UPDATE … WHERE estado IN ('en_revision','rechazado') AND persona <> revisor AND <alcance>`
//     a `aplicando`: dos revisores o un doble clic, un solo ganador; el otro recibe 409. Nadie aplica lo suyo y
//     nadie aplica lo de una sucursal que no ve: lo dice el SQL, en la misma sentencia.
//  2. SE VUELVE A VALIDAR lo que `valido` pide a la subida normal y, además, la LISTA BLANCA de método y ruta
//     (la que ya pasó al entregar): entre entregar y aplicar pueden pasar días y la lista puede haberse
//     endurecido. Lo que no pasa NO llega al reparto: se rechaza aquí, con su frase.
//  3. LA MISMA TUBERÍA que la subida normal ([Servicio.reenviar]: mismo traductor de `local-…`, mismo
//     `Aplicador`), con el TOKEN DEL REVISOR —la persona del apunte ya no tiene permiso— y tres cabeceras más:
//     `X-Sucursal-Id` FORZADA a la sucursal del apunte (acota a un SUPER ADMIN a UNA sucursal), `X-Autor` y
//     `X-Revision` (sólo para el registro del reparto, que no autoriza nada con ellas).
//  4. EL RESULTADO, sin inventar ninguno:
//     2xx   → `aplicado`, y se escribe TAMBIÉN en el libro `apuntes` (+ los provisionales) en la misma
//     transacción: si la persona recupera el rol y reenvía, la subida normal contesta `repetido`.
//     4xx   → `rechazado` con el motivo LITERAL del reparto. Sigue vivo, a la vista, esperando decisión.
//     NO se reintenta solo: Reintentar es otro Aplicar, de una persona.
//     403 sin_permiso_reparto → el que no tiene permiso es el REVISOR: el apunte no es culpable, vuelve a
//     `en_revision` (marcarlo rechazado sería destruirlo por algo que se arregla en Accesos).
//     5xx o red → una CAÍDA, no un rechazo: vuelve a `en_revision` con un intento más y el revisor lo
//     reintenta a mano. Marcarlo `rechazado` llenaría la bandeja de rechazos falsos el día que el
//     reparto se reinicie.
//  5. Si el proceso muere con la fila en `aplicando`, se queda así —el revisor la ve como `interrumpido`
//     pasados 10 minutos— y reintentar exige CONFIRMARLO tras comprobar a mano la ruta: la API no lee
//     `X-Apunte`, no hay otra red. Por eso todo lo posterior al candado va con `context.WithoutCancel`:
//     que el revisor cierre la pestaña a mitad no puede dejar una petición cortada con el reparto a medias.

type resultadoDeRevision struct {
	Clave  string `json:"clave"`
	Estado string `json:"estado"`
	// Rechazado: el LITERAL del reparto. Descartado: el motivo escrito.
	Motivo      string          `json:"motivo,omitempty"`
	ID          *uuid.UUID      `json:"id,omitempty"`
	Descartados json.RawMessage `json:"descartados,omitempty"`

	DecididoPorNombre *string    `json:"decididoPorNombre,omitempty"`
	DecididoAt        *time.Time `json:"decididoAt,omitempty"`
}

type resultadosSalida struct {
	Resultados []resultadoDeRevision `json:"resultados"`

	// SÓLO «Aplicar todo en orden»: se DETIENE en el primer apunte que no queda `aplicado` (o que no se pudo
	// tomar), porque lo de detrás puede depender de él y el orden FIFO es lo único que no se rompe. Dice cuál,
	// por qué y cuántos quedaron sin tocar.
	Detenido       bool   `json:"detenido,omitempty"`
	DetenidoEn     string `json:"detenidoEn,omitempty"`
	DetenidoPorque string `json:"detenidoPorque,omitempty"`
	SinProcesar    int    `json:"sinProcesar,omitempty"`
}

// paraAplicar es lo que hace falta de un apunte, venga de la lectura por id o de la de la entrega.
type paraAplicar struct {
	Aparato     uuid.UUID
	Clave       string
	Entrega     uuid.UUID
	Persona     string // QUIÉN LO HIZO (X-Autor)
	Sucursal    uuid.UUID
	Estado      sqlc.RevisionEstado
	Metodo      string
	Ruta        string
	Cuerpo      *string
	Provisional *string
	Hecho       pgtype.Timestamptz
}

func deApunteDeRevisor(f sqlc.RevisionApunteDeRevisorRow) paraAplicar {
	return paraAplicar{Aparato: f.AparatoID, Clave: f.Clave, Entrega: f.EntregaID, Persona: f.Persona, Sucursal: f.BranchID,
		Estado: f.Estado, Metodo: f.Metodo, Ruta: f.Ruta, Cuerpo: f.Cuerpo, Provisional: f.Provisional, Hecho: f.HechoAt}
}

func deFilaDeEntrega(f sqlc.RevisionDeEntregaRow) paraAplicar {
	return paraAplicar{Aparato: f.AparatoID, Clave: f.Clave, Entrega: f.EntregaID, Persona: f.Persona, Sucursal: f.BranchID,
		Estado: f.Estado, Metodo: f.Metodo, Ruta: f.Ruta, Cuerpo: f.Cuerpo, Provisional: f.Provisional, Hecho: f.HechoAt}
}

type aplicarEntrada struct {
	// Confirma que se comprobó a mano que la ruta de un `aplicando` interrumpido NO se aplicó.
	ReintentarInterrumpido bool `json:"reintentarInterrumpido"`
}

// POST /sync/revision/{aparato}/{clave}/aplicar
func (s *Servicio) aplicarApunte(w http.ResponseWriter, r *http.Request) {
	quien, rol, ok := s.revisor(w, r)
	if !ok {
		return
	}
	aparato, clave, ok := idDeApunte(w, r)
	if !ok {
		return
	}
	var entrada aplicarEntrada
	if !leerOpcional(w, r, &entrada) {
		return
	}
	ctx := r.Context()
	fila, err := s.datos.RevisionApunteDeRevisor(ctx, sqlc.RevisionApunteDeRevisorParams{
		AparatoID: aparato, Clave: clave, Sucursal: alcance(quien.Alcance())})
	switch {
	case store.SinFilas(err):
		s.porQueNo(ctx, quien, aparato, clave).contesta(w)
		return
	case err != nil:
		s.log.Error("no se pudo leer el apunte", "aparato", aparato, "clave", clave, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el apunte")
		return
	}
	res, f, err := s.aplicarDeRevision(ctx, quien, rol, deApunteDeRevisor(fila), nuevoTraductor(s.datos, aparato), entrada.ReintentarInterrumpido)
	switch {
	case err != nil:
		s.log.Error("no se pudo aplicar", "aparato", aparato, "clave", clave, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo aplicar. Actualiza la bandeja para ver cómo quedó antes de repetir.")
	case f != nil:
		f.contesta(w)
	default:
		httpx.JSON(w, http.StatusOK, resultadosSalida{Resultados: []resultadoDeRevision{res}})
	}
}

// POST /sync/revision/{entrega}/aplicar — «Aplicar todo en orden».
//
// FIFO y SE DETIENE en el primer fallo (B.4 decía «un rechazo no detiene al resto»; Jose pidió lo contrario:
// lo de detrás puede depender de lo que no entró, y un `local-…` que no llegó es justo el caso). Lo ya decidido
// (`aplicado`, `descartado`) se salta; un `rechazado` se vuelve a intentar —es un gesto explícito del revisor—
// pero UNA sola vez en esta llamada. No hay reintento automático de nada.
func (s *Servicio) aplicarEntrega(w http.ResponseWriter, r *http.Request) {
	quien, rol, ok := s.revisor(w, r)
	if !ok {
		return
	}
	id, ok := idDeEntrega(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	filas, err := s.datos.RevisionDeEntrega(ctx, sqlc.RevisionDeEntregaParams{EntregaID: id, Sucursal: alcance(quien.Alcance())})
	if err != nil {
		s.log.Error("no se pudo leer la entrega", "entrega", id, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer la entrega")
		return
	}
	if len(filas) == 0 {
		s.porQueNoHayEntrega(ctx, quien, id).contesta(w)
		return
	}

	traduce := nuevoTraductor(s.datos, filas[0].AparatoID)
	salida := resultadosSalida{Resultados: []resultadoDeRevision{}}
	for i, f := range filas {
		if f.Estado == sqlc.RevisionEstadoAplicado || f.Estado == sqlc.RevisionEstadoDescartado {
			continue
		}
		res, fa, err := s.aplicarDeRevision(ctx, quien, rol, deFilaDeEntrega(f), traduce, false)
		var motivoDelAlto string
		switch {
		case err != nil:
			s.log.Error("no se pudo aplicar", "entrega", id, "clave", f.Clave, "err", err)
			motivoDelAlto = "No se pudo aplicar este apunte (fallo interno). Actualiza la bandeja para ver cómo quedó antes de repetir."
		case fa != nil:
			motivoDelAlto = fa.mensaje
		default:
			salida.Resultados = append(salida.Resultados, res)
			if res.Estado == EstadoAplicado {
				continue
			}
			motivoDelAlto = res.Motivo
		}
		if len(salida.Resultados) == 0 && (err != nil || fa != nil) {
			// Ni el primero se pudo tomar: no es una parada a mitad, es un «no» de la petición entera.
			if fa != nil {
				fa.contesta(w)
			} else {
				httpx.Fallo(w, http.StatusInternalServerError, motivoDelAlto)
			}
			return
		}
		salida.Detenido, salida.DetenidoEn, salida.DetenidoPorque = true, f.Clave, motivoDelAlto
		for _, resto := range filas[i+1:] {
			if resto.Estado != sqlc.RevisionEstadoAplicado && resto.Estado != sqlc.RevisionEstadoDescartado {
				salida.SinProcesar++
			}
		}
		break
	}
	httpx.JSON(w, http.StatusOK, salida)
}

// aplicarDeRevision es «Aplicar» para UN apunte más el AVISO EN VIVO a quien lo entregó (`avisos.go`). Es el
// sitio central de los dos caminos (uno y «aplicar todo en orden»): un tercero que se añada no se olvida de avisar.
//
// SE AVISA SÓLO SI EL APUNTE QUEDÓ DECIDIDO Y ESCRITO: sin error ni fallo, el resultado es `aplicado` o `rechazado`
// y su transacción ya se confirmó (cada rama de [Servicio.aplicarYAnotar] vuelve de su `EnTransaccion` antes de
// llegar aquí; nada de esto corre dentro de una). Un fallo (no se pudo tomar, el reparto se cayó y el apunte vuelve
// a `en_revision`, no se pudo anotar) deja al apunte donde estaba para quien lo mira, así que no hay nada que contar.
// El aviso es un extra: `avisar` no bloquea ni falla, y sin suscriptores no hace nada.
//
// A QUIÉN: a la persona DUEÑA del apunte (`p.Persona`, sale de la fila de la entrega), jamás al revisor.
func (s *Servicio) aplicarDeRevision(ctx context.Context, quien identidad.Identidad, rol string, p paraAplicar,
	traduce *traductor, reintentarInterrumpido bool) (resultadoDeRevision, *falloDeEntrega, error) {
	res, f, err := s.aplicarYAnotar(ctx, quien, rol, p, traduce, reintentarInterrumpido)
	if err == nil && f == nil {
		s.avisos.avisar(p.Persona)
	}
	return res, f, err
}

// aplicarYAnotar es el cuerpo entero de «Aplicar» para UN apunte. Devuelve:
//   - el resultado, si el apunte quedó `aplicado` o `rechazado`;
//   - un [falloDeEntrega] si no hubo resultado que dar: no se pudo tomar (403/404/409), el reparto se cayó
//     (502, el apunte vuelve a `en_revision`) o el permiso del revisor no vale en Reparto (403);
//   - un `error` sólo si falló la base.
func (s *Servicio) aplicarYAnotar(ctx context.Context, quien identidad.Identidad, rol string, p paraAplicar,
	traduce *traductor, reintentarInterrumpido bool) (resultadoDeRevision, *falloDeEntrega, error) {
	nombre := textoOpcional(quien.Nombre, topeTextoDeAuditoria)
	filtro := alcance(quien.Alcance())

	// 1 · EL CANDADO.
	var err error
	if reintentarInterrumpido && p.Estado == sqlc.RevisionEstadoAplicando {
		err = s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
			if _, err := q.ReclamarRevisionInterrumpida(ctx, sqlc.ReclamarRevisionInterrumpidaParams{
				Revisor: quien.Persona, RevisorNombre: nombre, AparatoID: p.Aparato, Clave: p.Clave,
				AntiguedadSegundos: int32(esperaParaDarPorInterrumpido / time.Second), Sucursal: filtro,
			}); err != nil {
				return err
			}
			// El intento que murió no dejó rastro en el libro: lo deja quien lo recoge.
			motivo := "Reintento confirmado a mano: la ruta de un aplicando interrumpido no se había aplicado."
			_, err := q.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{
				AparatoID: p.Aparato, Clave: p.Clave, Accion: "aplicar", Por: quien.Persona, PorNombre: nombre,
				Rol: &rol, Resultado: "interrumpido", Motivo: &motivo,
			})
			return err
		})
	} else {
		_, err = s.datos.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{
			Revisor: quien.Persona, RevisorNombre: nombre, AparatoID: p.Aparato, Clave: p.Clave, Sucursal: filtro,
		})
	}
	if store.SinFilas(err) {
		return resultadoDeRevision{}, s.porQueNo(ctx, quien, p.Aparato, p.Clave), nil
	}
	if err != nil {
		return resultadoDeRevision{}, nil, err
	}

	// DESDE AQUÍ EL APUNTE ES NUESTRO (`aplicando`) y tiene que quedar en un estado honesto pase lo que pase.
	ctx = context.WithoutCancel(ctx)

	// 1-bis · ¿LA SUBIDA NORMAL YA LO RESOLVIÓ? (auditoría final, B6). `unApunte` mira la bandeja antes de aplicar,
	// pero un sync VIEJO (un rollback del despliegue) no la conoce y pudo aplicar por la subida normal una clave
	// que ya estaba aquí entregada. Reenviarla otra vez la aplicaría DOS VECES, con la autoridad del revisor. Si
	// el libro `apuntes` ya la tiene, se cierra con lo que dice el libro y NO se manda al reparto.
	ya, err := s.datos.BuscarApunte(ctx, sqlc.BuscarApunteParams{AparatoID: p.Aparato, Clave: p.Clave})
	switch {
	case err == nil:
		return s.cerrarComoYaResuelto(ctx, quien, rol, p, ya)
	case !store.SinFilas(err):
		// Sin poder mirarlo no se reenvía: el apunte vuelve a la cola de revisión, que es el fallo barato.
		return s.devolverAEnRevision(ctx, quien, rol, p, err)
	}

	// 2 · SE VUELVE A VALIDAR: lo de la subida normal y la lista blanca.
	a := apunteEntrada{Clave: p.Clave, Hecho: p.Hecho.Time, Metodo: p.Metodo, Ruta: p.Ruta}
	if p.Provisional != nil {
		a.Provisional = *p.Provisional
	}
	if p.Cuerpo != nil {
		a.Cuerpo = json.RawMessage(*p.Cuerpo)
	}
	if err := valido(a); err != nil {
		return s.cerrarRechazado(ctx, quien, rol, p, fmt.Sprintf("El apunte %s. No se ha mandado nada al reparto.", err))
	}
	if !metodoAdmitidoEnRevision(a.Metodo) || !rutaAdmitidaEnRevision(a.Ruta) {
		return s.cerrarRechazado(ctx, quien, rol, p, fmt.Sprintf(
			"No se aplica: %s %s no está entre lo que la cola del aparato emite (sólo POST, PUT, PATCH y DELETE sobre /routes… y /board…). "+
				"No se ha mandado nada al reparto.", a.Metodo, a.Ruta))
	}

	// 3 · LA MISMA TUBERÍA que la subida normal, con el token DEL REVISOR y la sucursal FORZADA.
	ruta, aplicado, rechazo, err := s.reenviar(ctx, sqlc.Aparato{ID: p.Aparato, BranchID: p.Sucursal}, quien, a, traduce,
		&origenDeRevision{Autor: p.Persona, Revision: p.Entrega.String(), SucursalPedida: p.Sucursal})
	switch {
	case rechazo != nil: // 4 · un 4xx (o un `local-…` que no llegó): rechazado, a la vista, con el LITERAL
		return s.cerrarRechazado(ctx, quien, rol, p, rechazo.Motivo)
	case err != nil: // una caída o el permiso del revisor: NO es culpa del apunte
		return s.devolverAEnRevision(ctx, quien, rol, p, err)
	}

	// 4 · el reparto dijo que sí: el cierre, el libro de lo aplicado, los provisionales y el libro de decisiones
	// van JUNTOS o no va ninguno.
	idCreado := aplicado.ID
	err = s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		bueno := aplicado.ID
		if p.Provisional != nil && *p.Provisional != "" && bueno != nil {
			// La traducción buena es la PRIMERA (si ese `local-…` ya estaba, no se pisa): ver `unApunte`.
			fila, err := q.AnotarProvisional(ctx, sqlc.AnotarProvisionalParams{
				AparatoID: p.Aparato, Provisional: *p.Provisional, IDReal: *bueno})
			if err != nil {
				return err
			}
			id := fila.IDReal
			bueno = &id
		}
		idCreado = bueno
		var creado pgtype.UUID
		if bueno != nil {
			creado = identificador(*bueno)
		}
		if _, err := q.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{
			IDCreado: creado, Descartados: aplicado.Descartados, AparatoID: p.Aparato, Clave: p.Clave, Revisor: quien.Persona,
		}); err != nil {
			return err
		}
		// EL LIBRO `apuntes`: sin esto la reentrega normal NO daría `repetido` pasados los 30 días de la bandeja.
		// `ON CONFLICT DO NOTHING`: si la clave ya estaba (la subida normal de un sync viejo se coló entre mirar
		// y escribir) la fila existente cuenta lo mismo y la transacción NO se cae (B6); se dice en el registro.
		escritas, err := q.CopiarApunteAplicadoAlLibro(ctx, sqlc.CopiarApunteAplicadoAlLibroParams{
			AparatoID: p.Aparato, Clave: p.Clave, Metodo: a.Metodo, Ruta: ruta, IDCreado: creado,
			HechoAt: p.Hecho, Descartados: aplicado.Descartados,
		})
		if err != nil {
			return err
		}
		if escritas == 0 {
			s.log.Warn("revisión: la clave ya estaba en el libro `apuntes` al anotar lo aplicado: se aplicó DOS VECES "+
				"(la subida normal de un sync viejo se coló); comprobar a mano",
				"aparato", p.Aparato, "clave", p.Clave, "entrega", p.Entrega)
		}
		_, err = q.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{
			AparatoID: p.Aparato, Clave: p.Clave, Accion: "aplicar", Por: quien.Persona, PorNombre: nombre,
			Rol: &rol, Resultado: "aplicado",
		})
		return err
	})
	if err != nil {
		// LO PEOR QUE PUEDE PASAR AQUÍ: el reparto lo aplicó y esta base no lo pudo anotar. Se queda en
		// `aplicando` (interrumpido) y se dice a gritos: reintentarlo sin mirar lo aplicaría dos veces.
		s.log.Error("SE APLICÓ EN EL REPARTO PERO NO SE PUDO ANOTAR: el apunte queda en `aplicando`",
			"revisor", quien.Persona, "aparato", p.Aparato, "clave", p.Clave, "entrega", p.Entrega, "ruta", ruta, "err", err)
		return resultadoDeRevision{}, fallo(http.StatusInternalServerError, CodigoNoSePudoAnotar,
			"Se aplicó en el reparto pero no se pudo anotar aquí. El apunte queda como «aplicando» (interrumpido): "+
				"comprueba a mano la ruta %s ANTES de reintentarlo, o se aplicará dos veces.", ruta), nil
	}
	if idCreado != nil {
		traduce.apuntar(a.Provisional, *idCreado)
	}
	s.log.Info("revisión: aplicado", "revisor", quien.Persona, "rol", rol, "autor", p.Persona, "aparato", p.Aparato,
		"clave", p.Clave, "entrega", p.Entrega, "sucursal", p.Sucursal)
	return resultadoDeRevision{Clave: p.Clave, Estado: EstadoAplicado, ID: idCreado, Descartados: aplicado.Descartados}, nil, nil
}

// cerrarComoYaResuelto: la clave YA estaba en el libro `apuntes` al ir a aplicarla (B6). Se cierra como el libro
// dice, SIN reenviar nada al reparto:
//   - `aplicado` → `aplicado` con el id (y lo que se cayó) del libro. Cuenta lo mismo que si lo hubiera aplicado
//     esta revisión, y el libro de decisiones deja la nota de que no se reenvió.
//   - `rechazado` → `rechazado` con el motivo LITERAL de entonces (sigue vivo y a la vista; Descartar lo cierra).
func (s *Servicio) cerrarComoYaResuelto(ctx context.Context, quien identidad.Identidad, rol string, p paraAplicar, ya sqlc.BuscarApunteRow) (resultadoDeRevision, *falloDeEntrega, error) {
	if ya.Estado != sqlc.ApunteEstadoAplicado {
		motivo := "La subida normal ya lo rechazó antes de la revisión."
		if ya.Motivo != nil && strings.TrimSpace(*ya.Motivo) != "" {
			motivo = *ya.Motivo
		}
		return s.cerrarRechazado(ctx, quien, rol, p, motivo)
	}
	nombre := textoOpcional(quien.Nombre, topeTextoDeAuditoria)
	nota := "Ya estaba aplicado por la subida normal (libro `apuntes`): no se reenvió al reparto."
	err := s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		if _, err := q.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{
			IDCreado: ya.IDCreado, Descartados: ya.Descartados, AparatoID: p.Aparato, Clave: p.Clave, Revisor: quien.Persona,
		}); err != nil {
			return err
		}
		_, err := q.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{
			AparatoID: p.Aparato, Clave: p.Clave, Accion: "aplicar", Por: quien.Persona, PorNombre: nombre,
			Rol: &rol, Resultado: "aplicado", Motivo: &nota,
		})
		return err
	})
	if err != nil {
		s.log.Error("no se pudo cerrar como ya aplicado: el apunte queda en `aplicando`", "aparato", p.Aparato, "clave", p.Clave, "err", err)
		return resultadoDeRevision{}, fallo(http.StatusInternalServerError, CodigoNoSePudoAnotar,
			"La subida normal ya lo había aplicado pero no se pudo anotar aquí. El apunte queda como «aplicando»: actualiza la bandeja."), nil
	}
	s.log.Warn("revisión: la clave ya estaba aplicada por la subida normal; no se reenvía", "revisor", quien.Persona,
		"aparato", p.Aparato, "clave", p.Clave, "entrega", p.Entrega)
	var descartados json.RawMessage
	if len(ya.Descartados) > 0 {
		descartados = ya.Descartados
	}
	return resultadoDeRevision{Clave: p.Clave, Estado: EstadoAplicado, ID: deIdentificador(ya.IDCreado), Descartados: descartados}, nil, nil
}

// cerrarRechazado: el «no» (del reparto o de aquí) se ESCRIBE —con su motivo literal— y el apunte sigue vivo.
func (s *Servicio) cerrarRechazado(ctx context.Context, quien identidad.Identidad, rol string, p paraAplicar, motivo string) (resultadoDeRevision, *falloDeEntrega, error) {
	if strings.TrimSpace(motivo) == "" {
		motivo = "El reparto dijo que no y no dijo por qué."
	}
	nombre := textoOpcional(quien.Nombre, topeTextoDeAuditoria)
	err := s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		if _, err := q.CerrarRevisionComoRechazado(ctx, sqlc.CerrarRevisionComoRechazadoParams{
			Motivo: motivo, AparatoID: p.Aparato, Clave: p.Clave, Revisor: quien.Persona}); err != nil {
			return err
		}
		_, err := q.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{
			AparatoID: p.Aparato, Clave: p.Clave, Accion: "aplicar", Por: quien.Persona, PorNombre: nombre,
			Rol: &rol, Resultado: "rechazado", Motivo: &motivo,
		})
		return err
	})
	if err != nil {
		s.log.Error("no se pudo anotar el rechazo: el apunte queda en `aplicando`", "aparato", p.Aparato, "clave", p.Clave, "err", err)
		return resultadoDeRevision{}, fallo(http.StatusInternalServerError, CodigoNoSePudoAnotar,
			"El reparto no lo aceptó (%s) pero no se pudo anotar aquí. El apunte queda como «aplicando»: actualiza la bandeja.", motivo), nil
	}
	s.log.Info("revisión: rechazado", "revisor", quien.Persona, "aparato", p.Aparato, "clave", p.Clave, "entrega", p.Entrega)
	return resultadoDeRevision{Clave: p.Clave, Estado: string(sqlc.RevisionEstadoRechazado), Motivo: motivo}, nil, nil
}

// devolverAEnRevision: una caída (5xx, red) o el 403 de rol del REVISOR. El apunte NO es culpable: vuelve a
// `en_revision` (+1 intento, sin dueño) y el revisor decide cuándo reintentar. Jamás `rechazado`.
func (s *Servicio) devolverAEnRevision(ctx context.Context, quien identidad.Identidad, rol string, p paraAplicar, causa error) (resultadoDeRevision, *falloDeEntrega, error) {
	f := fallo(http.StatusBadGateway, CodigoRepartoNoContesta,
		"El reparto no contestó. El apunte sigue en revisión: vuelve a intentarlo en un momento.")
	motivo := "El reparto no contestó"
	var sinPermiso *SinPermiso
	if errors.As(causa, &sinPermiso) {
		f = fallo(http.StatusForbidden, identidad.CodigoSinPermisoReparto, "%s", identidad.MsgSinPermisoReparto)
		motivo = "El reparto dijo que el revisor no tiene permiso en Reparto"
	}
	s.log.Warn("revisión: el apunte vuelve a en_revision (no es un rechazo)", "revisor", quien.Persona,
		"aparato", p.Aparato, "clave", p.Clave, "entrega", p.Entrega, "motivo", motivo, "err", causa)
	nombre := textoOpcional(quien.Nombre, topeTextoDeAuditoria)
	err := s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		if _, err := q.DevolverRevisionAEnRevision(ctx, sqlc.DevolverRevisionAEnRevisionParams{
			AparatoID: p.Aparato, Clave: p.Clave, Revisor: quien.Persona}); err != nil {
			return err
		}
		_, err := q.AnotarRevisionDecision(ctx, sqlc.AnotarRevisionDecisionParams{
			AparatoID: p.Aparato, Clave: p.Clave, Accion: "aplicar", Por: quien.Persona, PorNombre: nombre,
			Rol: &rol, Resultado: "caida", Motivo: &motivo,
		})
		return err
	})
	if err != nil {
		s.log.Error("no se pudo devolver el apunte a en_revision: queda en `aplicando`", "aparato", p.Aparato, "clave", p.Clave, "err", err)
		return resultadoDeRevision{}, fallo(http.StatusInternalServerError, CodigoNoSePudoAnotar,
			"El reparto no contestó y el apunte quedó como «aplicando». Actualiza la bandeja; si no lo ves en revisión, comprueba a mano la ruta antes de reintentar."), nil
	}
	return resultadoDeRevision{}, f, nil
}
