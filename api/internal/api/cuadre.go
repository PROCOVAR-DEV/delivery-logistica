package api

import (
	"net/http"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
)

// TopeDelCuadre: cuántos ids se sirven. Una sucursal tiene cientos de facturas vivas y las ocho juntas unas 2.700;
// pasarse de aquí es un ERROR para el aparato (`truncado`), que NO borra nada con una lista a medias.
const TopeDelCuadre = 50000

// CuadreSalida es la respuesta de `GET /api/sync/cuadre`.
type CuadreSalida struct {
	// Ids de las facturas que una carga completa le bajaría al aparato (las no archivadas y las anuladas de los
	// últimos días). Siempre un array, nunca null.
	Ids []string `json:"ids"`
	// Truncado: no cupieron todos. El aparato NO aplica un cuadre truncado: quitaría facturas vivas.
	Truncado bool `json:"truncado"`
	// Hasta: la hora del servidor a la que se hizo la lista.
	Hasta time.Time `json:"hasta"`
}

// GET /api/sync/cuadre — la red de seguridad de la bajada (28/10/2026).
//
// La bajada por diferencias solo borra lo que le dicen en `quitados`; una lápida que no llega deja facturas
// FANTASMA en el aparato para siempre (el 21/10/2026 se perdieron 828 de Santiago). Este endpoint da los ids de
// TODO lo que el aparato debería tener y él quita lo que sobre. Mismo alcance y misma sucursal que la bajada.
func (s *Servidor) cuadreDeFacturas(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	v := alcance.VentanaDeBajada{
		Hasta:    time.Now().UTC(),
		Sucursal: sucursalDeLaBajada(r, a),
		Tope:     TopeDelCuadre + 1,
	}
	ids, err := a.EspejoIdsParaElCuadre(r.Context(), v)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := CuadreSalida{Ids: make([]string, 0, len(ids)), Hasta: v.Hasta}
	if len(ids) > TopeDelCuadre {
		salida.Truncado = true
		ids = ids[:TopeDelCuadre]
	}
	for _, id := range ids {
		salida.Ids = append(salida.Ids, id.String())
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}
