// Package httpx es la forma de contestar, y sobre todo la forma de contestar MAL.
//
// El formato del error es el de `delivery` y el de `reparto-api`: `{"error": "..."}` con el
// texto en español y entero. No es un código que traducir en el cliente — es la frase que
// va a leer la persona que tiene el teléfono en la mano, y por eso se conserva literal
// (ver `docs/contratos-api.md`).
package httpx

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"
)

// Tope del cuerpo de una petición. La subida manda la cola entera de un día, así que no
// puede ser pequeño; pero sin tope, un cuerpo inventado se come la memoria del servicio.
const TopeCuerpo = 32 << 20 // 32 MiB

type sobreError struct {
	Error string `json:"error"`
	// Una marca que una MÁQUINA puede leer, para los pocos fallos donde el cliente tiene
	// que hacer algo distinto según cuál sea. Va vacía en el resto: el formato de la casa
	// sigue siendo la frase en español, y esto no la sustituye.
	Codigo string `json:"codigo,omitempty"`
}

// CodigoAparatoNoRegistrado: el único 404 de `/sync/subida` y `/sync/bajada` que significa
// «este aparato ya no está en el registro, date de alta otra vez».
//
// EXISTE PORQUE UN NÚMERO NO BASTA. Hasta el 21/09/2026 el teléfono trataba **cualquier**
// 404 como éste y tiraba su identificador. Un 404 de Traefik durante un redespliegue —que
// no es nuestro y ni siquiera es JSON— le hacía darse de alta otra vez, y cada alta deja
// una fila más en el panel marcada en rojo como «lleva días sin subir».
//
// Se vio en producción: **12 aparatos para un solo teléfono**, once de ellos fantasmas,
// dos creados de madrugada sin nadie delante. Con diez repartidores esa lista es inútil en
// una semana, y es justo la lista que existe para ver quién está atascado.
//
// Es la misma trampa que ya está resuelta en el otro sentido, en
// `internal/reparto/reparto.go`: «UN 404 QUE NO VIENE DEL REPARTO ES NUESTRO, NO UN
// RECHAZO».
const CodigoAparatoNoRegistrado = "aparato_no_registrado"

// Fallo contesta con el formato de la casa.
func Fallo(w http.ResponseWriter, estado int, motivo string) {
	JSON(w, estado, sobreError{Error: motivo})
}

// FalloConCodigo es igual, más la marca legible por una máquina. Ver
// [CodigoAparatoNoRegistrado].
func FalloConCodigo(w http.ResponseWriter, estado int, motivo, codigo string) {
	JSON(w, estado, sobreError{Error: motivo, Codigo: codigo})
}

// JSON escribe la respuesta. Si el codificado falla a media escritura ya no se puede
// cambiar el código de estado —la cabecera salió—, así que sólo queda dejar constancia.
func JSON(w http.ResponseWriter, estado int, cuerpo any) {
	datos, err := json.Marshal(cuerpo)
	if err != nil {
		slog.Error("no se pudo codificar la respuesta", "err", err)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"No se pudo componer la respuesta"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(estado)
	_, _ = w.Write(datos)
}

// Leer descodifica el cuerpo y, si no se puede, YA contesta el 400. Devuelve false para
// que quien llama sólo tenga que volverse.
//
// Sin `DisallowUnknownFields` a propósito: la APK de un logístico que no actualizó puede
// mandar un campo de más, y tirarle la subida entera del día por eso sería perder trabajo
// por una diferencia de versión.
func Leer(w http.ResponseWriter, r *http.Request, destino any) bool {
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, TopeCuerpo))
	if err := dec.Decode(destino); err != nil {
		var grande *http.MaxBytesError
		if errors.As(err, &grande) {
			Fallo(w, http.StatusRequestEntityTooLarge, "El envío es demasiado grande. Sube la cola por tandas.")
			return false
		}
		Fallo(w, http.StatusBadRequest, "El cuerpo de la petición no es JSON válido")
		return false
	}
	return true
}

// Recuperar evita que un fallo en un apunte tire el servicio entero. Un pánico aquí deja
// sin sincronizar a las diez sucursales, no sólo a la que lo provocó.
func Recuperar(log *slog.Logger, siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if p := recover(); p != nil {
				log.Error("pánico atendiendo la petición", "ruta", r.URL.Path, "panico", p)
				Fallo(w, http.StatusInternalServerError, "Error interno")
			}
		}()
		siguiente.ServeHTTP(w, r)
	})
}

// Registro deja una línea por petición. En este servicio el registro no es un adorno: es
// de donde sale «Palma subió a las 19:40 y se cortó a mitad».
func Registro(log *slog.Logger, siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		inicio := time.Now()
		espia := &espiaEstado{ResponseWriter: w, estado: http.StatusOK}
		siguiente.ServeHTTP(espia, r)
		log.Info("petición",
			"metodo", r.Method,
			"ruta", r.URL.Path,
			"estado", espia.estado,
			"ms", time.Since(inicio).Milliseconds())
	})
}

type espiaEstado struct {
	http.ResponseWriter
	estado int
}

func (e *espiaEstado) WriteHeader(estado int) {
	e.estado = estado
	e.ResponseWriter.WriteHeader(estado)
}

// Unwrap deja a `http.NewResponseController` llegar al escritor de verdad. SIN ESTO el espía lo esconde:
// `Flush` y `SetWriteDeadline` contestarían `ErrNotSupported` y el canal de avisos en vivo
// (`GET /sync/revision/eventos`, un SSE) no podría ni vaciar el búfer ni quitarse el `WriteTimeout` de 60 s, que
// lo mataría en silencio. Ningún otro manejador lo usa: es la puerta, no un cambio de comportamiento.
func (e *espiaEstado) Unwrap() http.ResponseWriter { return e.ResponseWriter }
