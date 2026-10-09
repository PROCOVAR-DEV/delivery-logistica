package api

import (
	"context"
	"log/slog"
	"net/http"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/sesiones"
)

// NuevoServidorConSesiones es EL SERVIDOR TAL COMO LO CONSTRUYE `cmd/api`: [NuevoServidor] con el
// empuje de Accesos ya cosido ([Servidor.PonerSesiones]), y el registro para que `main` lo haga
// correr. `main` sólo llama a esto, y la prueba de `sesion_cableada_test.go` construye con lo mismo:
// el 08/10/2026 quitar la línea `inv.AlEvento = …` dejaba toda la suite en verde porque las pruebas
// se enganchaban su propio bus y `cmd/api` no tiene pruebas. `fuente == nil` es «Redis sin
// configurar» (la API sirve igual, sin el empuje).
func NuevoServidorConSesiones(cfg *config.Config, reg *slog.Logger, p *alcance.Porteria, v *auth.Verificador,
	salud func(ctx context.Context) error, fuente sesiones.Fuente) (*Servidor, *sesiones.Registro) {
	s := NuevoServidor(cfg, reg, p, v, salud)
	inv := sesiones.Nuevo(fuente, s.reg)
	s.PonerSesiones(inv)
	return s, inv
}

// PonerSesiones engancha el empuje de Accesos (`internal/sesiones`): la sesión web de Reparto la
// invalida ACCESOS por Redis —sin sondeo— y esto es el punto donde se cose con la API.
//
//  1. El verificador consulta el registro en cada petición (sólo memoria, cero red): una cookie
//     emitida antes de la marca de esa persona da 401 y se borra.
//  2. Cada mensaje del canal se reparte por el difusor del SSE: SÓLO las conexiones de esas
//     personas reciben `sesion-invalidada` y se cierran.
//
// Se llama una vez, antes de servir y antes de `inv.Correr`. Sin llamarla (Redis sin configurar) la
// API funciona exactamente como antes. Las pruebas pueden cambiar `inv.AlEvento` después para
// apuntarlo a su propio bus.
func (s *Servidor) PonerSesiones(inv *sesiones.Registro) {
	// Los atributos de la cookie de borrado son los de la que se puso (`cookieDeLaWeb`): con uno
	// distinto el navegador la trata como otra y deja la buena donde estaba.
	s.verif.ConInvalidaciones(inv, func(w http.ResponseWriter, r *http.Request) {
		http.SetCookie(w, cookieDeLaWeb(origenPublico(r), "", -1))
	})
	inv.AlEvento = busEventos.SesionInvalidada
}
