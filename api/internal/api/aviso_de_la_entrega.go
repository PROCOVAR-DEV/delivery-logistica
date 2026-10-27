package api

import (
	"net/http"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
)

// avisosDeLasEntregas arma el lote de avisos a PEDIDO de unas entregas, todos con el mismo
// estado y la misma hora. Quién se avisa y con qué campos lo decide [alcance.AvisoDeLaEntrega]
// —una factura sin folio no sale, sin ruido—; esto sólo lee las filas y junta el lote.
//
// Un fallo al leer se dice en el registro y devuelve un lote vacío: armar o despachar una ruta
// no puede caerse porque no se pudo avisar a otra aplicación.
func (s *Servidor) avisosDeLasEntregas(
	r *http.Request, a *alcance.Acotado, ids []uuid.UUID, estado string, cuando time.Time,
) []AvisoDeParada {
	// UN CONDUCE AVISA POR CADA FACTURA (00029, regla 5): a PEDIDO no le importa que viajen juntas.
	ids, err := conSusMiembros(r, a, ids)
	if err != nil {
		httpx.Registro(r).Error("no se pudieron leer los miembros de los conduces para avisar a PEDIDO", "err", err)
		return nil
	}
	filas, err := a.EntregasParaAvisar(r.Context(), ids)
	if err != nil {
		httpx.Registro(r).Error("no se pudieron leer las entregas para avisar a PEDIDO", "err", err)
		return nil
	}
	var avisos []AvisoDeParada
	for _, id := range ids {
		if av, hay := alcance.AvisoDeLaEntrega(filas[id], estado, cuando, ""); hay {
			avisos = append(avisos, av)
		}
	}
	return avisos
}

func derefONada(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
