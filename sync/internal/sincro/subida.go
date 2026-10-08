package sincro

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// POST /sync/subida — la cola del aparato, EN ORDEN.

const (
	EstadoAplicado  = "aplicado"
	EstadoRepetido  = "repetido"
	EstadoRechazado = "rechazado"
)

type apunteEntrada struct {
	// La pone el aparato, una por apunte (un ULID). Es lo único que deja reconocer un
	// reenvío: sin ella, una subida a medias duplica lo que ya se había guardado.
	Clave string `json:"clave"`
	// La hora del APARATO, no la de la subida.
	Hecho  time.Time       `json:"hecho"`
	Metodo string          `json:"metodo"`
	Ruta   string          `json:"ruta"`
	Cuerpo json.RawMessage `json:"cuerpo,omitempty"`
	// Si este apunte CREA algo, el id inventado.
	Provisional string `json:"provisional,omitempty"`
}

type loteEntrada struct {
	Aparato string `json:"aparato"`
	// Cuántos apuntes le quedan al aparato DESPUÉS de este envío. Lo dice él: la cola vive
	// en el teléfono y lo que no ha subido no existe aquí.
	Pendientes *int32          `json:"pendientes"`
	Apuntes    []apunteEntrada `json:"apuntes"`
}

type resultado struct {
	Clave  string     `json:"clave"`
	Estado string     `json:"estado"`
	ID     *uuid.UUID `json:"id,omitempty"`
	Motivo string     `json:"motivo,omitempty"`

	// QUIÉN SE CAYÓ AUNQUE EL APUNTE ENTRARA — 28/09/2026.
	//
	// No es un rechazo y por eso no cabe en `Motivo`: el apunte se aplicó de verdad. Es
	// lo otro que el reparto contesta al armar una zona —el pedido nombrado, su motivo y
	// qué hacer— y que hasta hoy se quedaba en este servicio. Sin esto, la ruta salía con
	// menos pedidos de los que el logístico puso y el teléfono no tenía cómo saberlo.
	//
	// `omitempty` no es cosmética: lo normal es que no haya ninguno, y un `"descartados":
	// []` en cada apunte del lote es peso en una conexión que se paga.
	Descartados json.RawMessage `json:"descartados,omitempty"`
}

type subidaSalida struct {
	Resultados []resultado `json:"resultados"`
}

func (s *Servicio) subida(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	quien, hay := identidad.De(ctx)
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var lote loteEntrada
	if !httpx.Leer(w, r, &lote) {
		return
	}

	aparato, ok := s.aparatoDeLaPeticion(w, r, quien, lote.Aparato)
	if !ok {
		return
	}

	// Un apunte sin clave o sin ruta no es un rechazo de negocio: es un fallo de la
	// aplicación, y se contesta 400 con el lote entero sin tocar. Guardarlo en la bandeja
	// llenaría de basura técnica la lista que tiene que mirar una persona.
	for i, a := range lote.Apuntes {
		if err := valido(a); err != nil {
			httpx.Fallo(w, http.StatusBadRequest, fmt.Sprintf("El apunte %d del lote %s", i, err))
			return
		}
	}

	if err := s.datos.TocarAparato(ctx, aparato.ID); err != nil {
		s.log.Warn("no se pudo tocar el aparato", "aparato", aparato.ID, "err", err)
	}

	resultados, procesados, rechazadosDelLote, sinPermiso := s.aplicarLote(ctx, aparato, quien, lote.Apuntes)
	if sinPermiso != nil {
		// El reparto dijo «tu rol no entra a Reparto». Se contesta 403 con el MISMO cuerpo que
		// `identidad.Exigir`, y NO se anota nada: ni rechazo, ni la cuenta de la subida. Los
		// apuntes que quedaron sin procesar siguen en la cola del aparato, intactos, y suben
		// solos el día que se le dé el rol en Accesos.
		s.log.Warn("subida con un rol que no entra a Reparto: la cola se queda como estaba",
			"aparato", aparato.ID, "persona", quien.Persona, "motivo", sinPermiso.Motivo)
		httpx.FalloConCodigo(w, http.StatusForbidden,
			identidad.MsgSinPermisoReparto, identidad.CodigoSinPermisoReparto)
		return
	}

	// Lo que quedó sin procesar sigue en la cola del teléfono, así que cuenta como
	// pendiente. Si no se sumara, el panel enseñaría a Palma en verde justo el día en que
	// se le cortó la subida a la mitad.
	pendientes := int32(0)
	if lote.Pendientes != nil && *lote.Pendientes > 0 {
		pendientes = *lote.Pendientes
	}
	pendientes += int32(len(lote.Apuntes) - procesados)

	if err := s.datos.AnotarSubida(ctx, sqlc.AnotarSubidaParams{
		AparatoID:         aparato.ID,
		Pendientes:        pendientes,
		RechazadosDelLote: rechazadosDelLote,
	}); err != nil {
		// No se le tira la respuesta al aparato por esto: el trabajo YA está aplicado en
		// el reparto y lo que falló es la contabilidad del panel. Dejar que el aparato
		// creyera que no subió le haría reintentarlo todo (lo cual es inofensivo, pero
		// innecesario) y, peor, perdería los ids que van en esta respuesta.
		s.log.Error("no se pudo anotar la subida", "aparato", aparato.ID, "err", err)
	}

	httpx.JSON(w, http.StatusOK, subidaSalida{Resultados: resultados})
}

func valido(a apunteEntrada) error {
	switch {
	case a.Clave == "":
		return errors.New("no trae `clave`, y sin ella no hay idempotencia posible")
	case a.Metodo == "":
		return errors.New("no trae `metodo`")
	case a.Ruta == "":
		return errors.New("no trae `ruta`")
	case a.Hecho.IsZero():
		return errors.New("no trae `hecho`, la hora del aparato")
	}
	return nil
}

// aplicarLote recorre los apuntes UNO DETRÁS DE OTRO, en el orden en que vinieron.
//
// REGLA 2: marcar una parada y corregirla después son dos apuntes sobre el mismo pedido.
// Aplicarlos en paralelo, o reordenarlos por la hora del aparato —que es la de un reloj que
// se mueve—, deja puesta la primera marca y borra la corrección. La cola es FIFO y el orden
// lo pone la base local del teléfono, no el reloj.
//
// Devuelve además cuántos se llegaron a procesar: si el reparto se cae a mitad del lote se
// corta ahí y el resto se queda en la cola del aparato, que lo reintentará. Contestar lo
// que sí se hizo es lo que permite que el reintento sea barato: esas claves ya están en el
// libro y volverán como `repetido`.
func (s *Servicio) aplicarLote(ctx context.Context, aparato sqlc.Aparato, quien identidad.Identidad, apuntes []apunteEntrada) ([]resultado, int, int32, *SinPermiso) {
	resultados := make([]resultado, 0, len(apuntes))
	traduce := nuevoTraductor(s.datos, aparato.ID)
	// Una misma clave repetida DENTRO del mismo lote: el aparato reenvió su cola sin
	// limpiarla. La segunda tiene que contestar lo mismo que la primera, igual que si
	// hubiera llegado en otro envío.
	yaEnEsteLote := map[string]int{}
	var rechazados int32

	for i, a := range apuntes {
		if antes, ok := yaEnEsteLote[a.Clave]; ok {
			r := resultados[antes]
			r.Estado = EstadoRepetido
			resultados = append(resultados, r)
			continue
		}

		r, err := s.unApunte(ctx, aparato, quien, a, traduce)
		var sinPermiso *SinPermiso
		if errors.As(err, &sinPermiso) {
			return resultados, i, rechazados, sinPermiso
		}
		if err != nil {
			// Caída, no rechazo. Se corta el lote aquí: seguir con los siguientes
			// rompería el orden, que es lo único que no se puede romper.
			s.log.Error("se corta el lote", "aparato", aparato.ID, "clave", a.Clave, "posicion", i, "err", err)
			return resultados, i, rechazados, nil
		}
		if r.Estado == EstadoRechazado {
			rechazados++
		}
		yaEnEsteLote[a.Clave] = len(resultados)
		resultados = append(resultados, r)
	}
	return resultados, len(apuntes), rechazados, nil
}

// unApunte resuelve uno solo: ¿ya lo vi? ¿a qué se refiere ese `local-…`? ¿qué dice el
// reparto?
func (s *Servicio) unApunte(ctx context.Context, aparato sqlc.Aparato, quien identidad.Identidad, a apunteEntrada, traduce *traductor) (resultado, error) {
	// 1 · REGLA 1. ¿He visto ya esta clave DE ESTE APARATO?
	previo, err := s.datos.BuscarApunte(ctx, sqlc.BuscarApunteParams{
		AparatoID: aparato.ID,
		Clave:     a.Clave,
	})
	switch {
	case err == nil:
		return s.mismaRespuestaQueLaPrimeraVez(previo, a, traduce), nil
	case !store.SinFilas(err):
		return resultado{}, err
	}

	// 2 · REGLA 3. Los `local-…` que traiga se cambian por el id de verdad.
	ruta, falta, err := traduce.texto(ctx, a.Ruta, a.Provisional)
	if err != nil {
		return resultado{}, err
	}
	cuerpo := a.Cuerpo
	if falta == "" && len(cuerpo) > 0 {
		var traducido string
		traducido, falta, err = traduce.texto(ctx, string(cuerpo), a.Provisional)
		if err != nil {
			return resultado{}, err
		}
		cuerpo = json.RawMessage(traducido)
	}
	if falta != "" {
		// No se manda al reparto para que conteste 404 —eso sería perder el trabajo con
		// cara de error técnico—: se rechaza con un motivo que se entiende.
		motivo := fmt.Sprintf("El identificador provisional %s todavía no corresponde a nada: el apunte que lo crea no ha llegado.", falta)
		return s.rechazar(ctx, aparato, a, motivo)
	}

	// 3 · El reparto, que es el dueño de los datos.
	aplicado, err := s.aplicador.Aplicar(ctx, Peticion{
		Metodo:   a.Metodo,
		Ruta:     ruta,
		Cuerpo:   cuerpo,
		Hecho:    a.Hecho,
		Sucursal: aparato.BranchID,
		Persona:  quien.Persona,
		Clave:    a.Clave,
		Token:    quien.Token,
	})
	var rechazo *Rechazo
	switch {
	case errors.As(err, &rechazo):
		return s.rechazar(ctx, aparato, a, rechazo.Motivo)
	case err != nil:
		return resultado{}, err
	}
	idCreado := aplicado.ID

	// 4 · La traducción del provisional se anota ANTES que el apunte, y el id que manda es
	// el que devuelve esa consulta: si ese `local-…` ya estaba traducido, LA BUENA ES LA
	// PRIMERA. Sobrescribirla dejaría huérfana la ruta que ya existía, que es exactamente
	// cómo se duplica una ruta armada sin conexión.
	// UN APUNTE QUE CREA ALGO Y VUELVE SIN ID NO PUEDE PASAR EN SILENCIO.
	//
	// Esto se aplicaba y se daba por bueno, y el aparato se quedaba con su `local-…` para
	// siempre: la ruta existe arriba con sus paradas y abajo se ve vacía. El 21/09/2026
	// costó una tarde encontrarlo porque desde fuera todo estaba en verde — la ruta subió,
	// el servidor la guardó entera, y el único rastro era una tabla de equivalencias vacía
	// en el teléfono.
	//
	// Con un `Warn` basta y sobra para verlo: no se rechaza, porque el trabajo SÍ se hizo
	// arriba y rechazarlo sería tirar lo que ya está guardado. Lo que no puede es callarse.
	if a.Provisional != "" && idCreado == nil {
		s.log.Warn("el reparto aplicó un apunte que crea algo y NO devolvió id: "+
			"el aparato se quedará con su identificador provisional y lo que creó se le "+
			"verá vacío",
			"clave", a.Clave, "provisional", a.Provisional, "metodo", a.Metodo, "ruta", ruta)
	}
	if a.Provisional != "" && idCreado != nil {
		fila, err := s.datos.AnotarProvisional(ctx, sqlc.AnotarProvisionalParams{
			AparatoID:   aparato.ID,
			Provisional: a.Provisional,
			IDReal:      *idCreado,
		})
		if err != nil {
			return resultado{}, err
		}
		bueno := fila.IDReal
		idCreado = &bueno
		traduce.apuntar(a.Provisional, bueno)
	}

	// 5 · El apunte se anota DESPUÉS de aplicarlo. Al revés —anotar y luego aplicar— un
	// corte en medio dejaría la clave marcada como hecha con el trabajo sin hacer, y el
	// reintento contestaría `repetido` sobre algo que no existe.
	var creado pgtype.UUID
	if idCreado != nil {
		creado = identificador(*idCreado)
	}
	if _, err := s.datos.AnotarApunteAplicado(ctx, sqlc.AnotarApunteAplicadoParams{
		AparatoID: aparato.ID,
		Clave:     a.Clave,
		Metodo:    a.Metodo,
		Ruta:      ruta,
		IDCreado:  creado,
		HechoAt:   marca(a.Hecho),
		// Y QUIÉN SE CAYÓ, para poder repetirlo — 29/09/2026.
		//
		// Hasta hoy esto no se guardaba y el agujero estaba escrito abajo, en
		// `mismaRespuestaQueLaPrimeraVez`: un apunte que entró dejando pedidos fuera y
		// cuya respuesta se perdió por el camino volvía como `repetido` **sin el aviso**.
		// La ruta existía arriba con nueve de doce y en el teléfono parecía entera.
		Descartados: aplicado.Descartados,
	}); err != nil {
		return resultado{}, err
	}

	return resultado{
		Clave: a.Clave, Estado: EstadoAplicado, ID: idCreado,
		// Y lo que se quedó fuera, tal cual vino. Ver [resultado.Descartados].
		Descartados: aplicado.Descartados,
	}, nil
}

// mismaRespuestaQueLaPrimeraVez es la regla 1 entera: un apunte se queda para siempre como
// se resolvió la primera vez.
//
// Con el id que se creó entonces —no uno nuevo—, y si aquella vez fue un rechazo, con aquel
// motivo, que se lee de la bandeja (el motivo vive ahí y sólo ahí; copiado en dos sitios
// acaba discrepando).
//
// Y CON LOS `descartados` DE AQUELLA VEZ, que hasta el 29/09/2026 se perdían y estaba
// escrito aquí como agujero conocido. El caso entero: se arma una zona sin señal con doce
// pedidos, el apunte sube, el reparto la crea con NUEVE y nombra a los tres que se cayeron,
// y la respuesta se pierde por el camino. El aparato reintenta, aquí se contestaba
// `repetido` sin el aviso dentro, y la ruta quedaba arriba con nueve mientras en el
// teléfono parecía que había ido entera. Se tapó con la columna `descartados`
// (`00002_los_descartados_del_repetido.sql`).
//
// Las filas anteriores a esa migración la tienen nula, y eso es literalmente lo que eran:
// no se sabía. No se inventa una lista vacía, que se leería como «no se cayó nadie».
func (s *Servicio) mismaRespuestaQueLaPrimeraVez(previo sqlc.BuscarApunteRow, a apunteEntrada, traduce *traductor) resultado {
	r := resultado{Clave: a.Clave, Estado: EstadoRepetido, Descartados: previo.Descartados}
	if id := deIdentificador(previo.IDCreado); id != nil {
		r.ID = id
		// Y el `local-…` de aquel apunte sigue valiendo: lo que venga detrás en ESTE lote
		// referido a él tiene que apuntar al id bueno igual que si se acabara de crear.
		// Sin esto, reintentar un lote entero traduce mal todo lo que iba detrás.
		traduce.apuntar(a.Provisional, *id)
	}
	if previo.Estado == sqlc.ApunteEstadoRechazado && previo.Motivo != nil {
		// Sigue siendo `repetido` —«ya lo había visto»— pero con el motivo de entonces:
		// el aparato no tiene que volver a mandarlo ni tratarlo como nuevo.
		r.Motivo = *previo.Motivo
	}
	return r
}

// rechazar guarda el «no» del servidor: el apunte con su estado y el motivo en la bandeja,
// EN LA MISMA TRANSACCIÓN. Un apunte marcado rechazado sin motivo en la bandeja es
// exactamente el descarte en silencio que esto viene a impedir.
//
// REGLA 4: no se borra y no se reintenta. Queda a la vista con su motivo y su hora hasta
// que una persona decida.
func (s *Servicio) rechazar(ctx context.Context, aparato sqlc.Aparato, a apunteEntrada, motivo string) (resultado, error) {
	var cuerpo *string
	if len(a.Cuerpo) > 0 {
		// El sobre, tal como vino: es lo que deja a una persona ver qué se intentó y
		// repetirlo a mano.
		v := string(a.Cuerpo)
		cuerpo = &v
	}

	err := s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		if _, err := q.AnotarApunteRechazado(ctx, sqlc.AnotarApunteRechazadoParams{
			AparatoID: aparato.ID,
			Clave:     a.Clave,
			Metodo:    a.Metodo,
			Ruta:      a.Ruta,
			HechoAt:   marca(a.Hecho),
		}); err != nil {
			return err
		}
		_, err := q.AnotarRechazo(ctx, sqlc.AnotarRechazoParams{
			AparatoID: aparato.ID,
			Clave:     a.Clave,
			Motivo:    motivo,
			Cuerpo:    cuerpo,
		})
		return err
	})
	if err != nil {
		return resultado{}, err
	}
	return resultado{Clave: a.Clave, Estado: EstadoRechazado, Motivo: motivo}, nil
}
