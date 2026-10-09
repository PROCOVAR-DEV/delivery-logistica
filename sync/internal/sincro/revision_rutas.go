package sincro

import (
	"net/http"
	"time"

	"procovar/reparto-sync/internal/identidad"
)

// RutasDeRevision monta las DOS rutas de la entrega a revisión, cada una detrás de SU fuente de identidad:
//
//	POST /sync/revision/entrega   → `entrega`: sólo el token de ENTREGA (identidad.FuentesDeEntrega)
//	GET  /sync/revision/mias      → `mias`: el de entrega o el normal, de la misma persona del aparato
//
// Van en el mux PÚBLICO de `main`, no en el de `Rutas`: aquel está detrás del `Exigir` normal, que
// rechaza el token de entrega. `ServeMux` elige el patrón más específico, así que estos dos ganan a
// `/sync/` solo para estos dos métodos y estas dos rutas; todo lo demás (subida, bajada, estado, alta,
// y la bandeja del revisor de S2) sigue detrás del `Exigir` normal. Lo ata `fuente_de_la_casa_test.go`.
//
// El limitador de tasa (60 peticiones por minuto por persona) se crea AQUÍ y lo comparten las dos rutas.
func (s *Servicio) RutasDeRevision(mux *http.ServeMux, entrega, mias identidad.Fuente) {
	lim := nuevoLimitador(topePeticionesPorMinuto, time.Minute, s.ahora)
	mux.Handle("POST /sync/revision/entrega", identidad.Exigir(entrega,
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { s.entregar(w, r, lim) })))
	mux.Handle("GET /sync/revision/mias", identidad.Exigir(mias,
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { s.mias(w, r, lim) })))
}
