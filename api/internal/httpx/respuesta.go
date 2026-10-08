// El formato de respuesta que esperan los clientes.
//
// UN SOLO SITIO ESCRIBE ERRORES. Los mensajes de esta API son visibles —salen en la
// pantalla del logístico, en español, y están inventariados literalmente en
// `docs/contratos-api.md`—, así que no pueden depender de cómo le dé por escribir a cada
// manejador. Si mañana el envoltorio cambia, cambia aquí y en ningún otro sitio.
package httpx

import (
	"bytes"
	"encoding/json"
	"net/http"
)

// CuerpoError es el contrato: {"error": "..."}. La APK y la web leen ese campo y lo
// enseñan tal cual.
//
// `codigo` va SÓLO en los pocos errores donde el cliente tiene que hacer algo distinto según
// cuál sea (hoy: `sin_permiso_reparto`, ver [ErrorConCodigo]); en el resto se omite y el
// cuerpo sigue siendo `{"error":"..."}` byte por byte.
type CuerpoError struct {
	Error  string `json:"error"`
	Codigo string `json:"codigo,omitempty"`
}

// Mensajes literales del contrato. Van aquí como constantes y no sueltos por los
// manejadores porque son parte de la API: cambiarlos rompe a quien los compara.
const (
	MsgNoAutorizado   = "Unauthorized"          // todas las rutas con sesión
	MsgAdminRequerido = "Admin access required" // /api/branches POST y [id]
	MsgNoEncontrado   = "No encontrado"         // /api/branches/[id], /api/origins/[id]
	MsgNotFound       = "Not found"             // /api/vehicles/[id] — en inglés, y así se queda
	MsgCuerpoNoValido = "Cuerpo de la petición no válido"
	MsgErrorInterno   = "Error interno"
	MsgMetodoNoValido = "Método no permitido"
)

// respuesta500 es el cuerpo del 500 escrito A MANO, sin pasar por el codificador.
//
// Tiene que ser literal: se usa justo cuando codificar ha fallado, y volver a llamar a
// `Error` —que llama a `JSON`— sería intentar la misma operación que acaba de romperse.
var respuesta500 = []byte(`{"error":"` + MsgErrorInterno + `"}` + "\n")

// JSON escribe una respuesta con código y cuerpo.
//
// SE CODIFICA ANTES DE ESCRIBIR LA CABECERA, y eso no es una manía de estilo: es lo que
// impide que una respuesta rota salga con un código de éxito.
//
// Lo que pasaba antes, y pasó (24/09/2026, probándolo desde fuera): `json.Encoder` se
// niega a escribir un `float64` que no sea finito —`json: unsupported value: NaN`— y ese
// error llegaba con el `200` YA ENVIADO. Al cliente le quedaba un `200 OK` con el cuerpo
// **vacío**. Con `POST /api/routes` y `originLat: 1e308`, la resta de la haversine se
// desborda a −Inf, `math.Sin(-Inf)` es NaN y la ruta se guardaba con `total_distance = NaN`:
// el alta contestaba `201` sin cuerpo y, a partir de ahí, `GET /api/routes` contestaba
// `200` con cero bytes PARA SIEMPRE —la lista entera de la sucursal, no sólo esa ruta—.
// Ni un error, ni un 500, ni una línea de registro que un cliente pudiera enseñar: la
// pantalla se queda sin rutas y nadie sabe por qué. Es el §3 del CLAUDE.md en su peor
// forma: una lista que vuelve a medias con un 2xx.
//
// Ahora un cuerpo que no se puede codificar es un 500 con el mensaje de siempre. Se pierde
// la respuesta igual —no hay forma de inventarla— pero se pierde RUIDOSAMENTE: el cliente
// ve un error, el registro lleva la ruta y el porqué, y el 500 sube de nivel en el
// registro (`RegistrarPeticiones`).
//
// El coste es tener el cuerpo en memoria un instante. Ya se tenía: el objeto entero estaba
// montado antes de codificarlo, y la bajada más grande que sirve esta API son 2.000 filas
// por colección (`TopeDeBajada`).
func JSON(w http.ResponseWriter, r *http.Request, codigo int, cuerpo any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if cuerpo == nil {
		w.WriteHeader(codigo)
		return
	}

	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(cuerpo); err != nil {
		// `Registro` admite una petición nil; `r.URL.Path` no. Se saca con cuidado
		// porque este camino se recorre precisamente cuando algo ya ha ido mal.
		ruta, metodo := "", ""
		if r != nil {
			metodo = r.Method
			if r.URL != nil {
				ruta = r.URL.Path
			}
		}
		Registro(r).Error("la respuesta no se pudo codificar: sale un 500 en vez de un cuerpo cortado",
			"err", err, "ruta", ruta, "metodo", metodo, "codigo_que_iba", codigo)
		w.WriteHeader(http.StatusInternalServerError)
		if _, err := w.Write(respuesta500); err != nil {
			Registro(r).Error("no se pudo escribir la respuesta", "err", err)
		}
		return
	}

	w.WriteHeader(codigo)
	if _, err := w.Write(buf.Bytes()); err != nil {
		// Aquí la cabecera ya salió y el cuerpo iba entero: esto es el cliente que se
		// fue a mitad, no un cuerpo imposible. Sólo queda dejar constancia.
		Registro(r).Error("no se pudo escribir la respuesta", "err", err)
	}
}

// Error escribe {"error": mensaje} con el código dado.
func Error(w http.ResponseWriter, r *http.Request, codigo int, mensaje string) {
	JSON(w, r, codigo, CuerpoError{Error: mensaje})
}

// ErrorConCodigo es Error más la marca que lee una máquina: {"error": mensaje, "codigo": c}.
// El mensaje sigue siendo la frase en español que lee la persona; el código NO la sustituye.
func ErrorConCodigo(w http.ResponseWriter, r *http.Request, codigo int, mensaje, marca string) {
	JSON(w, r, codigo, CuerpoError{Error: mensaje, Codigo: marca})
}

// ErrorInterno es el 500. El detalle va al REGISTRO, nunca al cliente: los errores de
// pgx traen la consulta y a veces el dato que falló, y eso no sale de aquí.
func ErrorInterno(w http.ResponseWriter, r *http.Request, err error) {
	Registro(r).Error("error interno", "err", err, "ruta", r.URL.Path, "metodo", r.Method)
	Error(w, r, http.StatusInternalServerError, MsgErrorInterno)
}

// NoAutorizado, el 401 de siempre.
func NoAutorizado(w http.ResponseWriter, r *http.Request) {
	Error(w, r, http.StatusUnauthorized, MsgNoAutorizado)
}

// LeerJSON decodifica el cuerpo en destino. Devuelve false y ya ha respondido si el
// cuerpo no vale.
//
// `DisallowUnknownFields` NO se usa a propósito: los clientes mandan campos de más
// —`_count`, `createdAt` devueltos en un GET anterior— y rechazar la petición entera por
// eso convierte cada añadido del front en un fallo del back.
func LeerJSON(w http.ResponseWriter, r *http.Request, destino any) bool {
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxCuerpo))
	if err := dec.Decode(destino); err != nil {
		Registro(r).Warn("cuerpo no válido", "err", err)
		Error(w, r, http.StatusBadRequest, MsgCuerpoNoValido)
		return false
	}
	return true
}

// Tope del cuerpo. Un JSON de reparto grande (un lote del espejo) cabe de sobra; lo que
// no cabe es el intento de tumbar el proceso a base de memoria.
const maxCuerpo = 8 << 20 // 8 MiB
