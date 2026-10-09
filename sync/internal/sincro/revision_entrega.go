package sincro

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// LA ENTREGA A REVISIÓN — `docs/bandeja-de-revision.md`, paquete S1.
//
//	POST /sync/revision/entrega   (token de ENTREGA)
//	GET  /sync/revision/mias      (token de entrega o el normal, de la misma persona del aparato)
//
// Quien perdió `delivery.entrar` conserva su cola en el aparato pero sin token no puede subirla. Con el
// token de entrega de Accesos (10 minutos, un ámbito) deja aquí cada apunte, TAL COMO VINO, y una persona
// lo aplicará o lo descartará (S2).
//
// # LA INVARIANTE CENTRAL: EL `Aplicador` NO SE LLAMA NUNCA AQUÍ
//
// Entregar no es aplicar. Ni pedidos, ni rutas, ni tablero: esta función sólo escribe en las tablas
// `revision_*`. Por eso `entregar` no toca `s.aplicador` y la prueba lo cuenta: el doble del reparto
// tiene que acabar con CERO llamadas, entregue lo que entregue. Si un día alguien «ayuda» aplicando lo que
// parece inofensivo, estará ejecutando el payload de alguien sin permiso con la autoridad de quien sea
// que esté detrás — que es exactamente lo que este diseño existe para impedir.
//
// # Lo que se comprueba, y en qué orden
//
//  1. Sólo el token de ENTREGA (`identidad.Ambito`): uno normal no entrega (403 sin_permiso_reparto).
//  2. Tasa: ≤ 60 peticiones por minuto por persona.
//  3. El aparato EXISTE (nunca se da de alta en modo entrega) y es de ESTA persona y de ESTA sucursal. La
//     subida normal no compara `aparato.Persona` con quien llama (otro de la misma sucursal con un aparato
//     conocido podría subir por él): aquí es obligatorio.
//  4. Cada apunte, ENTERO, antes de guardar ninguno: clave, método y ruta de la lista blanca, cuerpo JSON
//     de ≤ 128 KiB, hora plausible. Una entrega con un solo apunte malo no guarda ninguno.
//  5. Idempotencia por (aparato, clave): el mismo contenido → `repetido`; otro contenido → 409
//     `huella_distinta` y NO se sobrescribe nada.
//  6. Cupos de lo vivo (persona: 500 y 8 MiB; sucursal: 3.000), con la sucursal bloqueada para que contar y
//     escribir sean uno.

// Estados y códigos que la app lee. `EstadoEnRevision` es el estado NUEVO del protocolo: la APK que lo
// entiende tiene que estar antes de que `sync` pueda contestarlo (`ResultadoApunte.deJson` lanza ante un
// estado desconocido), y en la práctica sólo se lo contesta a la instalación que entregó.
const (
	EstadoEnRevision = "en_revision"

	CodigoHuellaDistinta    = "huella_distinta"
	CodigoEntregaNoAdmitida = "entrega_no_admitida"
	CodigoCupoDeRevision    = "cupo_de_revision"
	CodigoTasaDeRevision    = "tasa_de_revision"
	CodigoAparatoAjeno      = "aparato_ajeno"
)

type apunteDeEntrega struct {
	Clave string `json:"clave"`
	// La hora del APARATO.
	Hecho  time.Time `json:"hecho"`
	Metodo string    `json:"metodo"`
	Ruta   string    `json:"ruta"`
	// EL CUERPO TAL CUAL: `json.RawMessage` guarda los bytes del valor sin tocarlos. Se guarda y se hashea
	// EXACTAMENTE esto; re-serializarlo cambiaría el original y su huella.
	Cuerpo      json.RawMessage `json:"cuerpo,omitempty"`
	Provisional string          `json:"provisional,omitempty"`
	// Ayuda de lectura del aparato («Marcar parada»). No vale como dato.
	Resumen string `json:"resumen,omitempty"`
}

type entregaEntrada struct {
	Aparato    string            `json:"aparato"`
	VersionApp string            `json:"version_app,omitempty"`
	Apuntes    []apunteDeEntrega `json:"apuntes"`
}

type resultadoDeEntrega struct {
	Clave string `json:"clave"`
	// `en_revision` (lo acabo de guardar) o `repetido` (ya lo tenía).
	Estado string `json:"estado"`
	// En qué está AHORA: en_revision, aplicando, aplicado, rechazado, descartado (los de la bandeja) o
	// aplicado/rechazado (si lo resolvió antes la subida normal).
	EstadoActual string     `json:"estadoActual"`
	Revision     *uuid.UUID `json:"revision,omitempty"`
	Motivo       string     `json:"motivo,omitempty"`

	// LO QUE LA APP NECESITA DE UN `repetido` PARA NO QUEDARSE CON UN HUÉRFANO (aditivo).
	//
	// `id` es el id de lo que creó el apunte ya aplicado —por la subida normal (libro `apuntes`) o por la
	// revisión—, igual que el `repetido` de `/sync/subida`: sin él la app no puede sustituir su `local-…` por el
	// de verdad y el apunte queda con el aviso de huérfano. `descartados` es quién se cayó aquella vez.
	ID          *uuid.UUID      `json:"id,omitempty"`
	Descartados json.RawMessage `json:"descartados,omitempty"`
	// Quién decidió y cuándo, por separado, cuando lo decidió una persona (aplicado o descartado). `motivo`
	// sigue llevando la frase ya montada («Descartado en la revisión por X: …») y NO se toca; el texto que
	// escribió quien descartó va solo en `motivoDelDescarte`.
	DecididoPorNombre string     `json:"decididoPorNombre,omitempty"`
	DecididoAt        *time.Time `json:"decididoAt,omitempty"`
	MotivoDelDescarte string     `json:"motivoDelDescarte,omitempty"`
}

type entregaSalida struct {
	Resultados []resultadoDeEntrega `json:"resultados"`
}

// falloDeEntrega es un «no» con su código HTTP y su literal. Sale de la transacción como error, que es lo
// que la deshace entera.
type falloDeEntrega struct {
	estado  int
	mensaje string
	codigo  string
}

func (f *falloDeEntrega) Error() string { return f.mensaje }

func noAdmitida(formato string, a ...any) *falloDeEntrega {
	return &falloDeEntrega{http.StatusUnprocessableEntity, fmt.Sprintf(formato, a...), CodigoEntregaNoAdmitida}
}

func (s *Servicio) entregar(w http.ResponseWriter, r *http.Request, lim *limitador) {
	ctx := r.Context()
	quien, hay := identidad.De(ctx)
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}
	// 1 · SÓLO EL TOKEN DE ENTREGA, también aquí dentro: la fuente de `main` ya lo exige, pero que un
	// manejador no dependa de cómo le monten la puerta es lo que lo deja a salvo de un cableado torcido.
	// `Token` lleno es un token que se podría reenviar al reparto (de persona con llave): jamás.
	if quien.Ambito != identidad.AmbitoEntrega || quien.EsSuperAdmin || quien.Token != "" {
		httpx.FalloConCodigo(w, http.StatusForbidden, identidad.MsgSinPermisoReparto, identidad.CodigoSinPermisoReparto)
		return
	}
	// 2 · Tasa.
	if !s.dentroDeLaTasa(w, lim, quien.Persona) {
		return
	}

	var entrada entregaEntrada
	r.Body = http.MaxBytesReader(w, r.Body, topePeticionDeEntrega)
	if !leerEntrega(w, r, &entrada) {
		return
	}

	// 3 · El aparato, y que sea de ESTA persona y de ESTA sucursal.
	aparato, ok := s.aparatoDeLaEntrega(w, r, quien, entrada.Aparato)
	if !ok {
		return
	}
	if aparato.Persona != quien.Persona || aparato.BranchID != quien.Sucursal {
		httpx.FalloConCodigo(w, http.StatusForbidden, "Ese aparato no es tuyo.", CodigoAparatoAjeno)
		return
	}

	// 4 · Cada apunte, entero, antes de guardar ninguno.
	ahora := s.ahora()
	if f := validarEntrega(entrada.Apuntes, ahora); f != nil {
		httpx.FalloConCodigo(w, f.estado, f.mensaje, f.codigo)
		return
	}
	huellas := make([]string, len(entrada.Apuntes))
	var bytesNuevos int64
	for i, a := range entrada.Apuntes {
		huellas[i] = huellaDeApunte(aparato.ID, a)
		bytesNuevos += int64(len(a.Cuerpo))
	}

	if err := s.datos.TocarAparato(ctx, aparato.ID); err != nil {
		s.log.Warn("no se pudo tocar el aparato", "aparato", aparato.ID, "err", err)
	}

	var resultados []resultadoDeEntrega
	var entregaID uuid.UUID
	var nuevos int
	err := s.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		var f error
		resultados, entregaID, nuevos, f = s.guardarEntrega(ctx, q, aparato, quien, entrada, huellas, bytesNuevos, r)
		return f
	})
	var fallo *falloDeEntrega
	switch {
	case errors.As(err, &fallo):
		if fallo.codigo == CodigoHuellaDistinta {
			// «Queda en el registro»: o es un fallo de la app o es alguien manipulando.
			s.log.Warn("entrega con la misma clave y otro contenido: no se guarda nada",
				"persona", quien.Persona, "aparato", aparato.ID, "sucursal", aparato.BranchID, "motivo", fallo.mensaje)
		}
		httpx.FalloConCodigo(w, fallo.estado, fallo.mensaje, fallo.codigo)
		return
	case err != nil:
		s.log.Error("no se pudo guardar la entrega a revisión", "persona", quien.Persona, "aparato", aparato.ID, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo guardar la entrega. Tu trabajo sigue en el aparato: vuelve a intentarlo.")
		return
	}

	// Una línea por entrega, SIN token (misma regla que `rastro_de_quien.go`).
	s.log.Info("entrega a revisión", "persona", quien.Persona, "aparato", aparato.ID, "sucursal", aparato.BranchID,
		"apuntes", len(entrada.Apuntes), "nuevos", nuevos, "entrega", entregaID)
	httpx.JSON(w, http.StatusOK, entregaSalida{Resultados: resultados})
}

// guardarEntrega es el cuerpo de la transacción. Devuelve los resultados EN EL ORDEN DE LA PETICIÓN.
func (s *Servicio) guardarEntrega(ctx context.Context, q sqlc.Querier, aparato sqlc.Aparato, quien identidad.Identidad,
	entrada entregaEntrada, huellas []string, bytesNuevos int64, r *http.Request) ([]resultadoDeEntrega, uuid.UUID, int, error) {
	// Contar el cupo y escribir son UNA cosa: sin este candado, N peticiones en paralelo pasarían todas por
	// debajo del tope a la vez. Dura hasta el final de la transacción.
	if err := q.BloquearRevisionDeSucursal(ctx, aparato.BranchID); err != nil {
		return nil, uuid.Nil, 0, err
	}

	resultados := make([]resultadoDeEntrega, len(entrada.Apuntes))
	var porGuardar []int
	for i, a := range entrada.Apuntes {
		// 5 · ¿La tengo ya, en la bandeja?
		previo, err := q.EstadoDeRevisionDeApunte(ctx, sqlc.EstadoDeRevisionDeApunteParams{AparatoID: aparato.ID, Clave: a.Clave})
		switch {
		case err == nil:
			if previo.Huella != huellas[i] {
				return nil, uuid.Nil, 0, huellaDistinta(a.Clave)
			}
			resultados[i] = repetidoDeRevision(a.Clave, previo)
			continue
		case !store.SinFilas(err):
			return nil, uuid.Nil, 0, err
		}
		// ¿Y en el libro de la subida normal? Si ya la aplicó (o la rechazó) allí, entregarla a revisión
		// sería dejar que un revisor la aplicara OTRA VEZ.
		ya, err := q.BuscarApunte(ctx, sqlc.BuscarApunteParams{AparatoID: aparato.ID, Clave: a.Clave})
		switch {
		case err == nil:
			res := resultadoDeEntrega{Clave: a.Clave, Estado: EstadoRepetido, EstadoActual: string(ya.Estado),
				ID: deIdentificador(ya.IDCreado)}
			if len(ya.Descartados) > 0 { // las filas anteriores a la 00002 la tienen nula: no se inventa una lista vacía
				res.Descartados = ya.Descartados
			}
			if ya.Estado == sqlc.ApunteEstadoRechazado && ya.Motivo != nil {
				res.Motivo = *ya.Motivo
			}
			resultados[i] = res
			continue
		case !store.SinFilas(err):
			return nil, uuid.Nil, 0, err
		}
		porGuardar = append(porGuardar, i)
	}
	if len(porGuardar) == 0 {
		return resultados, uuid.Nil, 0, nil
	}

	// 6 · Cupos, sólo de lo que de verdad se va a guardar.
	cupo, err := q.CupoDeRevision(ctx, sqlc.CupoDeRevisionParams{Persona: quien.Persona, Sucursal: aparato.BranchID})
	if err != nil {
		return nil, uuid.Nil, 0, err
	}
	var bytesPorGuardar int64
	for _, i := range porGuardar {
		bytesPorGuardar += int64(len(entrada.Apuntes[i].Cuerpo))
	}
	if msg := cupoExcedido(cupo, len(porGuardar), bytesPorGuardar); msg != "" {
		return nil, uuid.Nil, 0, &falloDeEntrega{http.StatusTooManyRequests, msg, CodigoCupoDeRevision}
	}

	entrega, err := q.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{
		AparatoID: aparato.ID, Persona: quien.Persona, PersonaNombre: textoOpcional(quien.Nombre, topeTextoDeAuditoria),
		BranchID: aparato.BranchID, TokenJti: quien.Jti,
		DesdeIp: textoOpcional(ipDe(r), 64), Agente: textoOpcional(r.UserAgent(), topeTextoDeAuditoria),
		VersionApp: textoOpcional(entrada.VersionApp, 60),
	})
	if err != nil {
		return nil, uuid.Nil, 0, err
	}

	guardados := 0
	for _, i := range porGuardar {
		a := entrada.Apuntes[i]
		var cuerpo *string
		if len(a.Cuerpo) > 0 {
			v := string(a.Cuerpo) // TAL CUAL
			cuerpo = &v
		}
		fila, err := q.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{
			AparatoID: aparato.ID, Clave: a.Clave, EntregaID: entrega.ID,
			Metodo: a.Metodo, Ruta: a.Ruta, Cuerpo: cuerpo, Provisional: textoOpcional(a.Provisional, 100),
			HechoAt: marca(hechoDe(a)), Huella: huellas[i], ResumenDelAparato: textoOpcional(a.Resumen, topeResumenDelAparato),
		})
		if store.SinFilas(err) {
			// Otra petición la guardó entre mirar y escribir: la idempotencia (ON CONFLICT DO NOTHING) la dejó
			// intacta. Se mira lo que quedó y se contesta como si hubiera llegado después.
			previo, err := q.EstadoDeRevisionDeApunte(ctx, sqlc.EstadoDeRevisionDeApunteParams{AparatoID: aparato.ID, Clave: a.Clave})
			if err != nil {
				return nil, uuid.Nil, 0, err
			}
			if previo.Huella != huellas[i] {
				return nil, uuid.Nil, 0, huellaDistinta(a.Clave)
			}
			resultados[i] = repetidoDeRevision(a.Clave, previo)
			continue
		}
		if err != nil {
			return nil, uuid.Nil, 0, err
		}
		guardados++
		resultados[i] = resultadoDeEntrega{
			Clave: a.Clave, Estado: EstadoEnRevision, EstadoActual: string(fila.Estado), Revision: &entrega.ID,
		}
	}
	return resultados, entrega.ID, guardados, nil
}

func huellaDistinta(clave string) *falloDeEntrega {
	return &falloDeEntrega{http.StatusConflict,
		fmt.Sprintf("El apunte %s ya se entregó con otro contenido. No se ha guardado nada: avisa a quien mantiene la aplicación.", clave),
		CodigoHuellaDistinta}
}

// repetidoDeRevision: la respuesta a una clave que la bandeja ya tenía, con su estado de ahora.
func repetidoDeRevision(clave string, fila sqlc.EstadoDeRevisionDeApunteRow) resultadoDeEntrega {
	rev := fila.EntregaID
	res := resultadoDeEntrega{
		Clave: clave, Estado: EstadoRepetido, EstadoActual: string(fila.Estado), Revision: &rev,
		Motivo: textoDeDecision(fila.Estado, fila.DecididoPorNombre, fila.Motivo),
	}
	if fila.Estado == sqlc.RevisionEstadoAplicado {
		res.ID = deIdentificador(fila.IDCreado)
		if len(fila.Descartados) > 0 {
			res.Descartados = fila.Descartados
		}
	}
	if fila.Estado == sqlc.RevisionEstadoAplicado || fila.Estado == sqlc.RevisionEstadoDescartado {
		if fila.DecididoPorNombre != nil {
			res.DecididoPorNombre = *fila.DecididoPorNombre
		}
		res.DecididoAt = hora(fila.DecididoAt)
	}
	if fila.Estado == sqlc.RevisionEstadoDescartado && fila.Motivo != nil {
		res.MotivoDelDescarte = *fila.Motivo
	}
	return res
}

// textoDeDecision es lo que una persona lee de cómo acabó un apunte entregado: el LITERAL del reparto si lo
// rechazó al aplicar, o quién lo descartó y por qué. Vacío si sigue esperando o se aplicó.
func textoDeDecision(estado sqlc.RevisionEstado, por, motivo *string) string {
	if motivo == nil {
		return ""
	}
	switch estado {
	case sqlc.RevisionEstadoRechazado:
		return *motivo
	case sqlc.RevisionEstadoDescartado:
		if por != nil && *por != "" {
			return "Descartado en la revisión por " + *por + ": " + *motivo
		}
		return "Descartado en la revisión: " + *motivo
	}
	return ""
}

// validarEntrega mira los apuntes ANTES de guardar ninguno.
func validarEntrega(apuntes []apunteDeEntrega, ahora time.Time) *falloDeEntrega {
	if len(apuntes) == 0 {
		return noAdmitida("La entrega no trae ningún apunte.")
	}
	if len(apuntes) > topeApuntesPorEntrega {
		return noAdmitida("La entrega trae %d apuntes y el máximo son %d por envío. Entrégalos por tandas.",
			len(apuntes), topeApuntesPorEntrega)
	}
	vistas := map[string]bool{}
	for i, a := range apuntes {
		donde := fmt.Sprintf("El apunte %d de la entrega ", i)
		switch {
		case !reClaveDeRevision.MatchString(a.Clave):
			return noAdmitida("%sno trae una `clave` válida (letras, números y `_.:-`, hasta 100).", donde)
		case vistas[a.Clave]:
			return noAdmitida("%srepite la clave %s dentro del mismo envío.", donde, a.Clave)
		case !metodoAdmitidoEnRevision(a.Metodo):
			return noAdmitida("%s%s: el método %q no se puede entregar a revisión.", donde, a.Clave, a.Metodo)
		case !rutaAdmitidaEnRevision(a.Ruta):
			return noAdmitida("%s%s: la ruta %q no se puede entregar a revisión (sólo /routes… y /board…).", donde, a.Clave, a.Ruta)
		case a.Provisional != "" && !reProvisionalDeRevision.MatchString(a.Provisional):
			return noAdmitida("%s%s: el identificador provisional no es válido (letras, números y `_.:-`, hasta 100).", donde, a.Clave)
		case a.Hecho.IsZero():
			return noAdmitida("%s%s: no trae `hecho`, la hora del aparato.", donde, a.Clave)
		case a.Hecho.After(ahora.Add(hechoMaximoEnElFuturo)):
			return noAdmitida("%s%s: la hora del aparato está más de 24 horas en el futuro: revisa el reloj.", donde, a.Clave)
		case a.Hecho.Before(ahora.Add(-hechoMaximoEnElPasado)):
			return noAdmitida("%s%s: la hora del aparato tiene más de 60 días.", donde, a.Clave)
		case len(a.Cuerpo) > topeCuerpoDeApunte:
			return noAdmitida("%s%s: el cuerpo pesa %d KiB y el máximo son %d KiB.", donde, a.Clave, len(a.Cuerpo)>>10, topeCuerpoDeApunte>>10)
		case len(a.Cuerpo) > 0 && (!json.Valid(a.Cuerpo) || !utf8.Valid(a.Cuerpo)):
			return noAdmitida("%s%s: el cuerpo no es un JSON válido.", donde, a.Clave)
		}
		vistas[a.Clave] = true
	}
	return nil
}

// hechoDe: la hora del aparato a la precisión de Postgres (microsegundos) y en UTC, para que lo que se
// guarda, lo que se hashea y lo que se vuelve a leer sean el mismo instante.
func hechoDe(a apunteDeEntrega) time.Time { return a.Hecho.UTC().Truncate(time.Microsecond) }

// huellaDeApunte: sha256 del apunte ENTERO tal como vino (aparato, clave, método, ruta, cuerpo, provisional
// y hora del aparato). Campos separados por NUL, que no puede aparecer en ninguno (la clave, el método y la
// ruta pasan listas blancas y el cuerpo es JSON válido), así que dos apuntes distintos no comparten huella
// por concatenación.
func huellaDeApunte(aparato uuid.UUID, a apunteDeEntrega) string {
	h := sha256.New()
	for _, campo := range []string{
		aparato.String(), a.Clave, a.Metodo, a.Ruta, string(a.Cuerpo), a.Provisional,
		hechoDe(a).Format("2006-01-02T15:04:05.000000Z"),
	} {
		h.Write([]byte(campo))
		h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil))
}

// aparatoDeLaEntrega busca el aparato y NADA MÁS: que sea de esta persona y de esta sucursal lo comprueba
// quien llama, explícitamente, en un solo sitio. No usa `aparatoDeLaPeticion` (que mira `quien.Ve`) para que
// cada una de las dos comparaciones sea una guarda propia y se pueda probar quitándola.
func (s *Servicio) aparatoDeLaEntrega(w http.ResponseWriter, r *http.Request, quien identidad.Identidad, crudo string) (sqlc.Aparato, bool) {
	if crudo == "" {
		httpx.Fallo(w, http.StatusBadRequest, "Falta el aparato")
		return sqlc.Aparato{}, false
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		httpx.Fallo(w, http.StatusBadRequest, "El aparato no es un identificador válido")
		return sqlc.Aparato{}, false
	}
	aparato, err := s.datos.AparatoPorId(r.Context(), id)
	if err != nil {
		if store.SinFilas(err) {
			// CON LA MARCA de siempre. En modo entrega NO se da de alta otra vez: no hay token para eso, y la
			// app dice «Este aparato no estaba registrado. Pide a un administrador que te devuelva el acceso.»
			httpx.FalloConCodigo(w, http.StatusNotFound,
				"Ese aparato no está registrado. Vuelve a darlo de alta.", httpx.CodigoAparatoNoRegistrado)
			return sqlc.Aparato{}, false
		}
		s.log.Error("no se pudo leer el aparato", "aparato", id, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el aparato")
		return sqlc.Aparato{}, false
	}
	return aparato, true
}

// dentroDeLaTasa cuenta la petición y, si se pasó, contesta el 429 con el tiempo que falta.
func (s *Servicio) dentroDeLaTasa(w http.ResponseWriter, lim *limitador, persona string) bool {
	if ok, espera := lim.permitir(persona); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(espera.Seconds())+1))
		httpx.FalloConCodigo(w, http.StatusTooManyRequests,
			"Demasiadas peticiones seguidas. Espera un minuto y vuelve a intentarlo: tu trabajo sigue en el aparato.",
			CodigoTasaDeRevision)
		return false
	}
	return true
}

// leerEntrega descodifica el cuerpo con su propio tope (512 KiB, no los 32 MiB de la subida). Un envío más
// grande es una entrega no admitida; un JSON roto, un 400 como en el resto.
func leerEntrega(w http.ResponseWriter, r *http.Request, destino any) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(destino); err != nil {
		var grande *http.MaxBytesError
		if errors.As(err, &grande) {
			f := noAdmitida("La entrega pesa más de %d KiB. Entrégala por tandas.", topePeticionDeEntrega>>10)
			httpx.FalloConCodigo(w, f.estado, f.mensaje, f.codigo)
			return false
		}
		httpx.Fallo(w, http.StatusBadRequest, "El cuerpo de la petición no es JSON válido")
		return false
	}
	return true
}

func textoOpcional(s string, max int) *string {
	s = limpio(s, max)
	if s == "" {
		return nil
	}
	return &s
}

// ipDe: de dónde vino la entrega, como constancia de auditoría. Detrás de Traefik el cliente es lo último
// que añade `X-Forwarded-For`; sin él, la dirección de la conexión. NO es un dato de seguridad.
func ipDe(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		partes := strings.Split(xff, ",")
		return strings.TrimSpace(partes[len(partes)-1])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// ---------------------------------------------------------------------------
// GET /sync/revision/mias?aparato=<uuid>
// ---------------------------------------------------------------------------

type miaDeRevision struct {
	Clave             string          `json:"clave"`
	Estado            string          `json:"estado"`
	Revision          uuid.UUID       `json:"revision"`
	DecididoPorNombre *string         `json:"decididoPorNombre"`
	DecididoAt        *time.Time      `json:"decididoAt"`
	Motivo            *string         `json:"motivo"`
	IDCreado          *uuid.UUID      `json:"idCreado"`
	Descartados       json.RawMessage `json:"descartados,omitempty"`
}

type miasSalida struct {
	Entregas []miaDeRevision `json:"entregas"`
	// Hay más de las que caben (§3 del CLAUDE.md: si pides un tope, comprueba si lo alcanzaste). Primero van
	// las vivas, así que lo que se queda fuera es lo más viejo ya decidido.
	Truncado bool `json:"truncado"`
}

// mias contesta qué ha pasado con lo que este aparato entregó. Sin sondeo automático en la app: la consulta
// la dispara la persona. Acepta el token de entrega o el normal, SIEMPRE de la misma persona del aparato.
func (s *Servicio) mias(w http.ResponseWriter, r *http.Request, lim *limitador) {
	ctx := r.Context()
	quien, hay := identidad.De(ctx)
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}
	if !s.dentroDeLaTasa(w, lim, quien.Persona) {
		return
	}
	aparato, ok := s.aparatoDeLaEntrega(w, r, quien, r.URL.Query().Get("aparato"))
	if !ok {
		return
	}
	// De la misma persona Y de su alcance: ni un Super Admin lee lo de otra persona por aquí (para eso está
	// la bandeja del revisor, con su propio control).
	if aparato.Persona != quien.Persona || !quien.Ve(aparato.BranchID) {
		httpx.FalloConCodigo(w, http.StatusForbidden, "Ese aparato no es tuyo.", CodigoAparatoAjeno)
		return
	}
	if err := s.datos.TocarAparato(ctx, aparato.ID); err != nil {
		s.log.Warn("no se pudo tocar el aparato", "aparato", aparato.ID, "err", err)
	}

	filas, err := s.datos.RevisionDeAparato(ctx, sqlc.RevisionDeAparatoParams{AparatoID: aparato.ID, Limite: topeDeFilasEnMias + 1})
	if err != nil {
		s.log.Error("no se pudo leer la revisión del aparato", "aparato", aparato.ID, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el estado de tus entregas")
		return
	}
	salida := miasSalida{Entregas: make([]miaDeRevision, 0, len(filas))}
	if len(filas) > topeDeFilasEnMias {
		salida.Truncado = true
		filas = filas[:topeDeFilasEnMias]
	}
	for _, f := range filas {
		m := miaDeRevision{
			Clave: f.Clave, Estado: string(f.Estado), Revision: f.EntregaID,
			DecididoPorNombre: f.DecididoPorNombre, DecididoAt: hora(f.DecididoAt),
			Motivo: f.Motivo, IDCreado: deIdentificador(f.IDCreado),
		}
		if len(f.Descartados) > 0 {
			m.Descartados = f.Descartados
		}
		salida.Entregas = append(salida.Entregas, m)
	}
	httpx.JSON(w, http.StatusOK, salida)
}

// ---------------------------------------------------------------------------
// El paso 0 de la subida normal
// ---------------------------------------------------------------------------

// respuestaDeRevision es el paso 0 de `unApunte`: si la clave está en la bandeja, la subida normal contesta lo
// que corresponde y NO LA APLICA. Es la otra mitad de la idempotencia: una persona que entregó su cola, recupera
// el rol y reenvía el mismo apunte no lo duplica.
//
//   - en_revision, aplicando → `en_revision` (todavía no está aplicado)
//   - aplicado               → `repetido`, con el id que se creó (el libro `apuntes` ya lo tiene también)
//   - rechazado, descartado  → `repetido` CON MOTIVO (la app ya lo lee como «no subió»)
func (s *Servicio) respuestaDeRevision(ctx context.Context, aparato sqlc.Aparato, a apunteEntrada, traduce *traductor) (resultado, bool, error) {
	fila, err := s.datos.EstadoDeRevisionDeApunte(ctx, sqlc.EstadoDeRevisionDeApunteParams{AparatoID: aparato.ID, Clave: a.Clave})
	if store.SinFilas(err) {
		return resultado{}, false, nil
	}
	if err != nil {
		return resultado{}, false, err
	}
	r := resultado{Clave: a.Clave}
	switch fila.Estado {
	case sqlc.RevisionEstadoAplicado:
		r.Estado, r.Descartados = EstadoRepetido, fila.Descartados
		if id := deIdentificador(fila.IDCreado); id != nil {
			r.ID = id
			traduce.apuntar(a.Provisional, *id)
		}
	case sqlc.RevisionEstadoRechazado, sqlc.RevisionEstadoDescartado:
		r.Estado = EstadoRepetido
		r.Motivo = textoDeDecision(fila.Estado, fila.DecididoPorNombre, fila.Motivo)
		if fila.Estado == sqlc.RevisionEstadoDescartado { // aditivo: lo mismo por separado, sin quitar la frase
			if fila.DecididoPorNombre != nil {
				r.DecididoPorNombre = *fila.DecididoPorNombre
			}
			if fila.Motivo != nil {
				r.MotivoDelDescarte = *fila.Motivo
			}
		}
	default: // en_revision, aplicando
		r.Estado = EstadoEnRevision
	}
	return r, true, nil
}
