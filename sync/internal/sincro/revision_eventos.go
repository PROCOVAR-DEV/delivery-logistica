package sincro

import (
	"fmt"
	"io"
	"net/http"
	"time"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
)

// GET /sync/revision/eventos?aparato=<uuid> — EL AVISO EN VIVO PARA QUIEN ENTREGÓ (`avisos.go` cuenta el porqué).
//
// Un SSE (`text/event-stream; charset=utf-8`) que se abre con el token de ENTREGA (10 minutos, un ámbito) y manda:
//
//	: abierto\n\n                         nada más entrar, para que el cliente sepa que ya está dentro
//	event: revision\ndata: {"v":1}\n\n    cuando una decisión cambia el estado de un apunte de ESTA persona
//	: ka\n\n                              un latido cada 25 s
//
// El aviso NO lleva datos: ni clave, ni estado, ni motivo. El cliente, al recibirlo, consulta
// `GET /sync/revision/mias` (que sí pasa por el alcance y la comprobación del aparato). Por este canal no se
// puede filtrar nada, y lo que no se manda no hay que proteger.
//
// El flujo se cierra solo cuando: caduca el token (el cliente reconecta con otro), el cliente se va, o el servicio
// se apaga ([Servicio.CerrarAvisos]).
//
// # POR QUÉ ESTA RUTA ES DE LA PERSONA Y NO DEL REVISOR
//
// Acepta SÓLO el token de entrega (`identidad.FuentesDeEntrega`, la fuente `entrega`; el token normal de la APK
// recibe el 403 de siempre). Y aun con él, el aparato tiene que ser de la persona del token y de su alcance:
// las mismas comprobaciones y los MISMOS códigos que `mias` (400 · 404 `aparato_no_registrado` · 403
// `aparato_ajeno`), para que no haya un oráculo nuevo. Un revisor, aunque tenga rol de revisor y vea la sucursal,
// no abre el canal de otro: para él existe su bandeja (`GET /sync/revision`).
//
// # LO QUE NO SE APLICA AQUÍ
//
// El limitador de tasa de `mias` (60 por minuto) es para peticiones cortas; en un flujo largo cuenta mal (una
// sola petición dura diez minutos). Su lugar lo ocupa el tope de concurrencia de [avisos].
//
// El `WriteTimeout` del servidor (60 s) es un plazo ABSOLUTO desde que se leyó la petición: MATARÍA el flujo a
// los 60 s. Aquí, y sólo aquí, se sustituye por uno que se RENUEVA antes de CADA escritura (`: abierto`, latidos y
// avisos) con `http.ResponseController`: el flujo vive lo que dure el token, y un cliente que dejó de leer sin
// cerrar (el socket murió sin RST) tumba la escritura a los 60 s en vez de retener el canal y su hueco del tope
// hasta el timeout de TCP. Quitar el plazo del todo habría dejado ese agujero. Go lo vuelve a poner para la
// siguiente petición de la misma conexión, así que el resto de rutas conserva su `WriteTimeout`. Si el escritor no
// deja tocarlo (un envoltorio sin `Unwrap`), el canal se niega con un 500 que se ve, en vez de abrirse y morir a
// los 60 s sin decir nada.
//
// LAS CABECERAS, las mismas cautelas que `api/internal/api/eventos.go`: `charset=utf-8`; `no-transform`, para que un
// proxy que comprime al vuelo no junte los bloques (ese fichero cuenta por qué); `X-Accel-Buffering: no`; y NUNCA
// `Connection: keep-alive` (HTTP/2 y HTTP/3 lo prohíben: tras Cloudflare da `ERR_QUIC_PROTOCOL_ERROR`). Esto último
// lo ata una prueba con el socket en crudo, porque `http.Client` normaliza las cabeceras y no lo vería.
//
// El registro de peticiones (`httpx.Registro`) escribe UNA línea al terminar, no al abrir: su `ms` es lo que duró
// el canal, y su hora es la del final.
func (s *Servicio) eventos(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	quien, hay := identidad.De(ctx)
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}
	// SÓLO EL TOKEN DE ENTREGA, también aquí dentro (como `entregar`): la fuente de `main` ya lo exige, pero un
	// manejador que no depende de cómo le monten la puerta es el que no se abre por un cableado torcido.
	if quien.Ambito != identidad.AmbitoEntrega || quien.EsSuperAdmin || quien.Token != "" {
		httpx.FalloConCodigo(w, http.StatusForbidden, identidad.MsgSinPermisoReparto, identidad.CodigoSinPermisoReparto)
		return
	}
	// Sin saber cuándo caduca no hay con qué cerrar el flujo, y uno sin final es una sesión que no muere: no se abre.
	if quien.Caduca.IsZero() {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}
	aparato, ok := s.aparatoDeLaEntrega(w, r, quien, r.URL.Query().Get("aparato"))
	if !ok {
		return
	}
	if aparato.Persona != quien.Persona || !quien.Ve(aparato.BranchID) {
		httpx.FalloConCodigo(w, http.StatusForbidden, "Ese aparato no es tuyo.", CodigoAparatoAjeno)
		return
	}

	rc := http.NewResponseController(w)
	plazo := s.avisos.plazo()
	if err := rc.SetWriteDeadline(time.Now().Add(plazo)); err != nil {
		s.log.Error("avisos en vivo: no se pudo tocar el plazo de escritura (¿un envoltorio sin Unwrap?)", "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "Este servidor no puede mantener el canal de avisos abierto.")
		return
	}

	// El tope, DESPUÉS de las comprobaciones de arriba: quien no es de ese aparato no gasta un hueco ni sabe cómo
	// anda el cupo de otra persona.
	sus, err := s.avisos.suscribir(quien.Persona)
	if err != nil {
		s.log.Warn("avisos en vivo: canal rechazado por el tope", "persona", quien.Persona, "motivo", err)
		w.Header().Set("Retry-After", esperaTrasElTopeDeAvisos)
		mensaje := fmt.Sprintf("Ya tienes abiertos los canales de avisos que se permiten (%d). Cierra alguno o vuelve a intentarlo en 30 segundos. "+
			"Tus entregas no dependen de esto: «Actualizar estados» te dice siempre cómo van.", s.avisos.topePorPersona)
		if err == errServicioAlTopeDeAvisos {
			mensaje = "Ahora mismo hay demasiados canales de avisos abiertos. Vuelve a intentarlo en 30 segundos. " +
				"Tus entregas no dependen de esto: «Actualizar estados» te dice siempre cómo van."
		}
		httpx.FalloConCodigo(w, http.StatusTooManyRequests, mensaje, CodigoAvisosAlTope)
		return
	}
	defer s.avisos.baja(sus)

	cabecera := w.Header()
	cabecera.Set("Content-Type", "text/event-stream; charset=utf-8")
	cabecera.Set("Cache-Control", "no-cache, no-transform")
	cabecera.Set("X-Accel-Buffering", "no") // que un nginx de por medio no lo retenga
	w.WriteHeader(http.StatusOK)
	// Cada escritura, con SU plazo: renovado justo antes, no heredado de la anterior.
	enviar := func(texto string) bool {
		if rc.SetWriteDeadline(time.Now().Add(plazo)) != nil {
			return false
		}
		if _, err := io.WriteString(w, texto); err != nil {
			return false
		}
		return rc.Flush() == nil
	}
	if !enviar(": abierto\n\n") {
		return
	}

	// La caducidad se calcula UNA vez, contra el reloj de verdad —el mismo contra el que el verificador comprobó el
	// `exp`: `identidad.DeTokenDeEntrega` usa `time.Until`, no el reloj inyectable del servicio, que es el de las
	// marcas de la bajada— y se espera con un temporizador, que no se entera de un salto del reloj de la máquina.
	caduca := time.NewTimer(time.Until(quien.Caduca))
	defer caduca.Stop()
	latido := time.NewTicker(s.avisos.latido)
	defer latido.Stop()
	for {
		select {
		case <-sus.c:
			if !enviar("event: revision\ndata: {\"v\":1}\n\n") {
				return
			}
		case <-latido.C:
			if !enviar(": ka\n\n") {
				return
			}
		case <-caduca.C: // el token murió: el cliente pide otro y reconecta
			return
		case <-ctx.Done(): // el cliente se fue
			return
		case <-s.avisos.cerrado: // el servicio se apaga
			return
		}
	}
}
