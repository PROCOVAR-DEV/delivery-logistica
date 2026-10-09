package httpx

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"runtime/debug"
	"strings"
	"time"
)

type claveCtx int

const (
	claveRegistro claveCtx = iota
	clavePeticion
)

// Medio es un escalón de la cadena de middlewares.
type Medio func(http.Handler) http.Handler

// Encadenar aplica los middlewares en el orden en que se escriben: el primero de la
// lista es el más externo y por tanto el primero en ver la petición y el último en ver
// la respuesta. Escrito al revés, la recuperación de pánico quedaría DENTRO del registro
// y un pánico se llevaría por delante la línea del registro que lo explica.
func Encadenar(h http.Handler, medios ...Medio) http.Handler {
	for i := len(medios) - 1; i >= 0; i-- {
		h = medios[i](h)
	}
	return h
}

// IDDePeticion cuelga un identificador de cada petición y lo devuelve en la cabecera
// `X-Peticion-Id`.
//
// POR QUÉ: el logístico llama por teléfono y dice "me salió un error". Con este número
// en la pantalla, el registro del servidor se abre por esa línea. Sin él hay que
// adivinar entre diez sucursales a qué petición se refiere.
//
// Si el cliente ya trae uno se conserva: así una cadena de peticiones (APK -> API ->
// PEDIDO) se sigue entera con el mismo hilo.
func IDDePeticion(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimSpace(r.Header.Get("X-Peticion-Id"))
		if id == "" || len(id) > 64 {
			id = nuevoID()
		}
		w.Header().Set("X-Peticion-Id", id)
		ctx := context.WithValue(r.Context(), clavePeticion, id)
		siguiente.ServeHTTP(w, r.WithContext(ctx))
	})
}

// ConRegistro deja en el contexto un registro que ya lleva el id de la petición, para
// que ninguna línea escrita más abajo tenga que acordarse de ponerlo.
func ConRegistro(base *slog.Logger) Medio {
	return func(siguiente http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			reg := base
			if id, _ := r.Context().Value(clavePeticion).(string); id != "" {
				reg = base.With("peticion", id)
			}
			ctx := context.WithValue(r.Context(), claveRegistro, reg)
			siguiente.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// Registro saca el registro de la petición. Nunca devuelve nil: un manejador al que le
// llegue un contexto pelado —una prueba, por ejemplo— tiene que poder escribir igual.
func Registro(r *http.Request) *slog.Logger {
	if r != nil {
		if reg, _ := r.Context().Value(claveRegistro).(*slog.Logger); reg != nil {
			return reg
		}
	}
	return slog.Default()
}

// IDDeLaPeticion devuelve el identificador colgado por IDDePeticion, o "".
func IDDeLaPeticion(r *http.Request) string {
	id, _ := r.Context().Value(clavePeticion).(string)
	return id
}

// escritor guarda el código y los bytes para poder registrarlos después.
type escritor struct {
	http.ResponseWriter
	codigo int
	bytes  int
}

func (e *escritor) WriteHeader(codigo int) {
	if e.codigo == 0 {
		e.codigo = codigo
	}
	e.ResponseWriter.WriteHeader(codigo)
}

func (e *escritor) Write(b []byte) (int, error) {
	// Un Write sin WriteHeader previo es un 200 implícito; hay que anotarlo o el
	// registro diría "0" en las respuestas correctas.
	if e.codigo == 0 {
		e.codigo = http.StatusOK
	}
	n, err := e.ResponseWriter.Write(b)
	e.bytes += n
	return n, err
}

// Unwrap deja que http.ResponseController llegue al escritor de verdad (necesario para
// el vaciado de los eventos en vivo, que van por streaming).
func (e *escritor) Unwrap() http.ResponseWriter { return e.ResponseWriter }

// RegistrarPeticiones deja una línea por petición atendida, con lo que hace falta para
// entender un incidente: método, ruta, código, tamaño y cuánto tardó.
//
// El nivel sube con el código: un 500 tiene que verse en un registro filtrado a error,
// y un 401 no puede ensuciarlo (la APK reintenta y da 401 cada vez que caduca un token,
// que es constantemente).
func RegistrarPeticiones(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		inicio := time.Now()
		e := &escritor{ResponseWriter: w}
		siguiente.ServeHTTP(e, r)
		if e.codigo == 0 {
			e.codigo = http.StatusOK
		}

		nivel := slog.LevelInfo
		switch {
		case e.codigo >= 500:
			nivel = slog.LevelError
		case e.codigo >= 400 && e.codigo != http.StatusUnauthorized && e.codigo != http.StatusNotFound:
			nivel = slog.LevelWarn
		}
		campos := []any{
			"metodo", r.Method,
			"ruta", r.URL.Path,
			"codigo", e.codigo,
			"bytes", e.bytes,
			"ms", time.Since(inicio).Milliseconds(),
		}
		Registro(r).Log(r.Context(), nivel, "peticion", append(campos, autoriaDe(r)...)...)
	})
}

// TopeDeLaAutoria: caracteres que se anotan de `X-Autor` y `X-Revision` (un uuid con guiones mide 36).
const TopeDeLaAutoria = 64

// autoriaDe: la AUTORÍA DE LA BANDEJA DE REVISIÓN (`docs/bandeja-de-revision.md`, paquete P).
//
// Cuando el revisor aplica lo que otra persona entregó, `sync` llama a esta API con el token del
// REVISOR y añade `X-Autor` (quién hizo el gesto: el `sub` del aparato) y `X-Revision` (el id de la
// revisión). Aquí se ESCRIBEN, como `autor` y `revision`, en la línea de la petición, que sale para
// TODA escritura (POST/PUT/PATCH/DELETE) y por eso cubre rutas que no llaman a `rastroDeQuien`
// (`/board/columns`...): el 09/10/2026 la prueba de punta a punta vio que aplicar el tablero por
// revisión no dejaba ni rastro de las dos personas. Es el ÚNICO sitio que las escribe.
//
// NO AUTORIZAN NADA, no tocan el `actor` (que sale del token verificado, en `rastroDeQuien`) y se
// recortan: son cabeceras de quien llama, o sea texto de fuera, y un renglón que se pega en un chat
// no puede crecer con ellas. Un GET no las anota; un valor vacío tampoco.
func autoriaDe(r *http.Request) []any {
	switch r.Method {
	case http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
	default:
		return nil
	}
	var campos []any
	for _, c := range [...]struct{ cabecera, clave string }{{"X-Autor", "autor"}, {"X-Revision", "revision"}} {
		if v := strings.TrimSpace(r.Header.Get(c.cabecera)); v != "" {
			if t := []rune(v); len(t) > TopeDeLaAutoria {
				v = string(t[:TopeDeLaAutoria]) + "…"
			}
			campos = append(campos, c.clave, v)
		}
	}
	return campos
}

// RecuperarPanico convierte un pánico en un 500 con el formato de siempre.
//
// POR QUÉ: sin esto, un índice fuera de rango en un manejador se lleva el PROCESO
// ENTERO, y con él las peticiones de las otras nueve sucursales que estaban en vuelo.
// La traza se guarda completa en el registro; al cliente no le va nada de eso.
func RecuperarPanico(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			p := recover()
			if p == nil {
				return
			}
			// http.ErrAbortHandler es la forma normal de cortar una respuesta (la usa
			// el propio net/http). Re-lanzarlo: no es un fallo nuestro.
			if p == http.ErrAbortHandler {
				panic(p)
			}
			Registro(r).Error("pánico atendiendo la petición",
				"panico", p,
				"metodo", r.Method,
				"ruta", r.URL.Path,
				"traza", string(debug.Stack()),
			)
			defer func() {
				// Si la cabecera ya había salido, este WriteHeader vuelve a entrar en
				// pánico. No hay nada que hacer salvo no morirse por segunda vez.
				_ = recover()
			}()
			Error(w, r, http.StatusInternalServerError, MsgErrorInterno)
		}()
		siguiente.ServeHTTP(w, r)
	})
}

// SinCache marca lo que no puede quedarse guardado en el navegador. Todas las rutas de
// datos lo son: en delivery iban con `dynamic = 'force-dynamic'`.
func SinCache(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store, must-revalidate")
		siguiente.ServeHTTP(w, r)
	})
}

// CORS deja entrar a la web de Flutter, que vive en otro dominio.
//
// La lista es CERRADA y sale de la configuración: con `*` no se pueden mandar cookies, y
// la sesión de la web es una cookie.
func CORS(origenes []string) Medio {
	permitido := make(map[string]bool, len(origenes))
	for _, o := range origenes {
		permitido[o] = true
	}
	return func(siguiente http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origen := r.Header.Get("Origin")
			if origen != "" && permitido[origen] {
				w.Header().Set("Access-Control-Allow-Origin", origen)
				w.Header().Set("Access-Control-Allow-Credentials", "true")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Sucursal-Id, X-Api-Key, X-Peticion-Id")
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
				w.Header().Set("Access-Control-Max-Age", "600")
				w.Header().Add("Vary", "Origin")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			siguiente.ServeHTTP(w, r)
		})
	}
}

func nuevoID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		// rand.Read no falla en la práctica; si fallara, un id repetido es mejor que
		// no atender la petición.
		return "sin-id"
	}
	return hex.EncodeToString(b[:])
}
