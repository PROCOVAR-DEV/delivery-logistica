package identidad

import (
	"log/slog"
	"net/http"
	"strings"

	"procovar/reparto-sync/internal/httpx"
)

// EL DISTRIBUIDOR SOLO SUBE SU COLA (04/11/2026). Gemela de `reparto-api/internal/auth/distribuidor.go`: la llave `delivery.entrar` no
// distingue roles, así que este servicio también cierra por lista blanca. A un `DISTRIBUIDOR` solo se le deja dar de alta su aparato y subir
// su cola; el panel de aparatos (`/sync/estado`), la bandeja de revisión y la bajada por sucursal son de la oficina.
const rolDistribuidor = "DISTRIBUIDOR"

const (
	MsgNoEsParaElDistribuidor    = "Esta opción no está disponible para tu rol."
	CodigoNoEsParaElDistribuidor = "no_es_para_el_distribuidor"
)

// EsDistribuidor: lleva el rol DISTRIBUIDOR. Si además lleva otro de oficina, queda restringido (falla cerrado).
func (i Identidad) EsDistribuidor() bool {
	for _, r := range i.Roles {
		if mismoRol(r, rolDistribuidor) {
			return true
		}
	}
	return false
}

// PermitidoAlDistribuidor: lista blanca por método y ruta.
//
//	POST /sync/aparato   dar de alta su aparato
//	POST /sync/subida    subir su cola (el reparto la vuelve a acotar a sus rutas)
func PermitidoAlDistribuidor(metodo, ruta string) bool {
	ruta = strings.TrimSuffix(ruta, "/")
	return metodo == http.MethodPost && (ruta == "/sync/aparato" || ruta == "/sync/subida")
}

func permitirAlDistribuidor(w http.ResponseWriter, r *http.Request, id Identidad) bool {
	if !id.EsDistribuidor() || PermitidoAlDistribuidor(r.Method, r.URL.Path) {
		return true
	}
	slog.Warn("un distribuidor pidió algo que no es suyo", "persona", id.Persona, "metodo", r.Method, "ruta", r.URL.Path)
	httpx.FalloConCodigo(w, http.StatusForbidden, MsgNoEsParaElDistribuidor, CodigoNoEsParaElDistribuidor)
	return false
}
