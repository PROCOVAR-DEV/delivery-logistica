package sincro

import (
	"net/http"
	"time"

	"procovar/reparto-sync/internal/identidad"
)

// RutasDeRevision monta las TRES rutas de la persona que entregó, cada una detrás de SU fuente de identidad:
//
//	POST /sync/revision/entrega   → `entrega`: sólo el token de ENTREGA (identidad.FuentesDeEntrega)
//	GET  /sync/revision/mias      → `mias`: el de entrega o el normal, de la misma persona del aparato
//	GET  /sync/revision/eventos   → `entrega`: sólo el token de ENTREGA; el aviso en vivo (SSE) de `mias`
//
// Van en el mux PÚBLICO de `main`, no en el de `Rutas`: aquel está detrás del `Exigir` normal, que
// rechaza el token de entrega. `ServeMux` elige el patrón más específico, así que estos tres ganan a
// `/sync/` solo para estos métodos y estas rutas; todo lo demás (subida, bajada, estado, alta,
// y la bandeja del revisor de S2) sigue detrás del `Exigir` normal. Lo ata `fuente_de_la_casa_test.go`.
//
// `eventos` lleva la fuente `entrega` y NO la de `mias` a propósito: `mias` es una consulta y la puede hacer la
// persona ya con su token normal, pero el canal en vivo se ofrece sólo a quien está entregando. Con la de `mias`,
// el token normal de la APK abriría un flujo de diez minutos que ni lo necesita ni lo pidió.
//
// El limitador de tasa (60 peticiones por minuto por persona) se crea AQUÍ y lo comparten `entrega` y `mias`.
// `eventos` no lo usa: es un flujo largo, y su freno es el tope de canales abiertos por persona (`avisos.go`).
func (s *Servicio) RutasDeRevision(mux *http.ServeMux, entrega, mias identidad.Fuente) {
	lim := nuevoLimitador(topePeticionesPorMinuto, time.Minute, s.ahora)
	mux.Handle("POST /sync/revision/entrega", identidad.Exigir(entrega,
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { s.entregar(w, r, lim) })))
	mux.Handle("GET /sync/revision/mias", identidad.Exigir(mias,
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { s.mias(w, r, lim) })))
	mux.Handle("GET /sync/revision/eventos", identidad.Exigir(entrega, http.HandlerFunc(s.eventos)))
}
