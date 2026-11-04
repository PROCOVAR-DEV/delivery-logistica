package auth

import (
	"net/http"
	"strings"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/httpx"
)

// EL DISTRIBUIDOR (04/11/2026): el repartidor que va en el vehículo y usa su propia aplicación («Reparto Distribuidor»). Entra a
// Reparto con la llave `delivery.entrar` como cualquiera —eso lo decide Accesos—, pero **no es un logístico**: solo ve y completa SUS
// rutas. Como la llave no distingue roles, lo distingue esto, y **falla cerrado**: lo que no esté en [PermitidoAlDistribuidor] es un 403.
//
// Quien lleva el rol `DISTRIBUIDOR` queda restringido aunque además tenga otro rol de oficina: una persona con los dos roles es un
// error de alta, y el error se paga con menos permiso, no con más.
const rolDistribuidor = "DISTRIBUIDOR"

// CodigoSoloDistribuidor es la marca del 403 de «esto no es para tu rol»: la app del distribuidor no lo manda a Accesos, es una pantalla
// que no le toca.
const (
	MsgNoEsParaElDistribuidor    = "Esta opción no está disponible para tu rol."
	CodigoNoEsParaElDistribuidor = "no_es_para_el_distribuidor"
)

// EsDistribuidor: lleva el rol DISTRIBUIDOR.
func (u *Usuario) EsDistribuidor() bool { return u.tieneAlguno(rolDistribuidor) }

// PermitidoAlDistribuidor dice si un distribuidor puede hacer esta petición. **Lista blanca**: método + ruta.
//
//	GET   /api/sync/cambios · /api/sync/cuadre · /api/almacenes   la bajada de lo suyo (acotada por distribuidor en el SQL)
//	GET   /api/routes · /api/routes/{id}                            sus rutas
//	POST  /api/routes/{id}/results                                  marcar sus paradas
//	PATCH /api/routes/{id}                                          iniciar / completar (el manejador solo le deja `status`)
//	POST  /api/track                                                su ubicación
//
// Todo lo demás —tablero, pedidos, clientes, vehículos, ajustes, informes, conduces, armar y borrar rutas— es un 403. Que una ruta nueva
// de la API no esté aquí es justo lo correcto: nace cerrada para el distribuidor.
func PermitidoAlDistribuidor(metodo, ruta string) bool {
	ruta = strings.TrimSuffix(ruta, "/")
	partes := strings.Split(strings.TrimPrefix(ruta, "/"), "/")
	if len(partes) < 2 || partes[0] != "api" {
		return false
	}
	switch metodo {
	case http.MethodGet:
		switch ruta {
		case "/api/sync/cambios", "/api/sync/cuadre", "/api/almacenes", "/api/routes":
			return true
		}
		return len(partes) == 3 && partes[1] == "routes" && esUUID(partes[2])
	case http.MethodPost:
		if ruta == "/api/track" {
			return true
		}
		return len(partes) == 4 && partes[1] == "routes" && esUUID(partes[2]) && partes[3] == "results"
	case http.MethodPatch:
		return len(partes) == 3 && partes[1] == "routes" && esUUID(partes[2])
	}
	return false
}

func esUUID(s string) bool {
	_, err := uuid.Parse(s)
	return err == nil
}

// permitirAlDistribuidor es el cierre de [Verificador.Exigir]: si la persona es distribuidor y la petición no está en la lista
// blanca, 403. Devuelve false si ya contestó.
func permitirAlDistribuidor(w http.ResponseWriter, r *http.Request, u *Usuario) bool {
	if !u.EsDistribuidor() || PermitidoAlDistribuidor(r.Method, r.URL.Path) {
		return true
	}
	httpx.Registro(r).Warn("un distribuidor pidió algo que no es suyo",
		"persona", u.ID, "metodo", r.Method, "ruta", r.URL.Path)
	httpx.ErrorConCodigo(w, r, http.StatusForbidden, MsgNoEsParaElDistribuidor, CodigoNoEsParaElDistribuidor)
	return false
}

// CerrarAlDistribuidor es para los manejadores que NO pasan por [Verificador.Exigir] (el canal de avisos en vivo): si la persona es un
// distribuidor, 403 y devuelve false. El canal no está en su lista blanca: con él vería la actividad de los demás teléfonos de su sucursal.
func CerrarAlDistribuidor(w http.ResponseWriter, r *http.Request, u *Usuario) bool {
	return permitirAlDistribuidor(w, r, u)
}
