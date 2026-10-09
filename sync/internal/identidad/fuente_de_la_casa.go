package identidad

import (
	"log/slog"

	"procovar/reparto-sync/internal/sesiones"
)

// FuenteDeLaCasa es de dónde saca `cmd/sync` quién llama, TAL COMO LO CABLEA `main`: con
// `SYNC_IDENTIDAD=token` el token de Accesos se verifica aquí [DeTokenConInvalidaciones] y el
// registro de sesiones de Accesos (`fuente`, que es el Redis en producción) se le pasa; en cualquier
// otro modo, las cabeceras de un proxy que ya verificó. Devuelve el registro para que `main` lo haga
// `Correr`. Existe para que una prueba construya EXACTAMENTE esto: el 08/10/2026 el cableado de `main`
// (verificador ↔ suscriptor) no lo pisaba ninguna, y quitar el `inv` dejaba toda la suite en verde.
// `fuente == nil` es «Redis sin configurar»: el sincronizador sirve igual, sin el empuje.
func FuenteDeLaCasa(modo string, secreto []byte, resolutor Resolutor, fuente sesiones.Fuente,
	log *slog.Logger) (Fuente, *sesiones.Registro) {
	inv := sesiones.Nuevo(fuente, log)
	if modo == "token" {
		return DeTokenConInvalidaciones(secreto, resolutor, inv), inv
	}
	return DeCabeceras, inv
}
