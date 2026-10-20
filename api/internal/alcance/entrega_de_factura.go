package alcance

import (
	"context"
	"errors"
	"strings"

	"procovar/reparto-api/internal/store/sqlc"
)

// LA CONVENCIÓN DE LA ENTREGA QUE NACE DE UNA FACTURA (issue 20, «Sustitución de Pedido por
// Factura», Fase A; Jose, 20/10/2026).
//
// Una entrega de factura se guarda con `source = 'pedido'` —el único valor del enum
// `procedencia`— y con `external_id = 'factura:' + clave`. NO hay un valor nuevo del enum a
// propósito: así NINGÚN filtro `source = 'pedido'` (SQL, Go ni Dart) se rompe, y la fila entra
// por la misma puerta, con el mismo upsert y las mismas guardas que cualquier pedido.
//
// El nombre `source = 'pedido'` es LEGADO y se renombra o se quita en la fase de LIMPIEZA del
// issue 20 (tras el corte, cuando PEDIDO ya no alimente nada). Hasta entonces, «es de factura»
// se pregunta SOLO con [EsDeFactura] (y su gemela SQL, `starts_with(external_id, 'factura:')`
// en `orders.sql`), nunca con un `strings.HasPrefix` suelto: una convención escrita en tres
// sitios se separa en cuanto uno se olvida.

// PrefijoDeFactura es lo que lleva delante el `external_id` de una entrega de factura.
const PrefijoDeFactura = "factura:"

// EsDeFactura dice si un `external_id` es el de una entrega que nació de una factura de Ventra
// (y no de un pedido de PEDIDO).
func EsDeFactura(externalID string) bool {
	return strings.HasPrefix(externalID, PrefijoDeFactura)
}

// FolioNormalizado es el folio como se COMPARA: en mayúsculas y sin nada que no sea letra o dígito
// ASCII (`'PXX-900`, `pxx-900` y `PXX - 900` son `PXX900`). Es la gemela en Go de la función SQL
// `folio_normalizado` (00025) y las ata `TestMotorReal_FolioNormalizadoGoYSqlDicenLoMismo`: la usan
// la adopción, el «ya adoptado» y la clave `external_id` de la entrega. La columna `folio` guarda el
// valor tal cual; lo que se normaliza es la comparación.
func FolioNormalizado(folio string) string {
	var b strings.Builder
	for _, r := range folio {
		switch {
		case r >= 'a' && r <= 'z':
			b.WriteRune(r - 'a' + 'A')
		case r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ErrYaAdoptadoPorFactura: el pedido de PEDIDO que se quería guardar ya tiene una entrega de
// factura con su mismo folio en esa sucursal, y NO se crea otra fila. No es un fallo: es la
// convivencia de las dos fuentes (`SYNC_FUENTE=ambas`), y quien llama lo cuenta aparte.
var ErrYaAdoptadoPorFactura = errors.New("ya lo adoptó una entrega de factura con el mismo folio")

// alFolio hace, DENTRO de la transacción de [Acotado.EspejoGuardarPedido], lo que une las dos
// fuentes. Va antes del upsert y sólo si el pedido trae folio y sucursal.
//
//   - Toma el candado del (sucursal, folio): sin él, un ciclo de PEDIDO y uno de factura con el
//     mismo folio a la vez, sin fila previa de ninguno, insertan cada uno la suya y el pedido
//     sale DOS veces (external_id distinto: nada choca).
//   - Si la fila que se guarda es de FACTURA: ADOPTA a la de PEDIDO del mismo folio, cambiándole
//     sólo el `external_id`; el upsert que viene detrás le pone el mapeo. Conserva el `id`, la
//     ruta, el orden, el resultado y el punto a mano.
//   - Si es de PEDIDO y ya hay una de factura con ese folio: devuelve [ErrYaAdoptadoPorFactura].
func (a *Acotado) alFolio(ctx context.Context, p sqlc.GuardarPedidoDelEspejoParams) error {
	// Un folio que se queda vacío al normalizarlo (`---`) no es un folio: con él se adoptarían entre
	// sí todas las entregas sin folio de verdad.
	if p.Folio == nil || FolioNormalizado(*p.Folio) == "" ||
		p.SucursalCodigo == nil || strings.TrimSpace(*p.SucursalCodigo) == "" ||
		p.ExternalID == nil {
		return nil
	}
	if err := a.q.BloquearFolioDePedido(ctx, sqlc.BloquearFolioDePedidoParams{
		SucursalCodigo: *p.SucursalCodigo, Folio: *p.Folio,
	}); err != nil {
		return err
	}
	if EsDeFactura(*p.ExternalID) {
		_, err := a.q.AdoptarPedidoPorFolio(ctx, sqlc.AdoptarPedidoPorFolioParams{
			ExternalID: *p.ExternalID, SucursalCodigo: *p.SucursalCodigo, Folio: *p.Folio,
		})
		return err
	}
	ya, err := a.q.ExisteEntregaDeFacturaDelFolio(ctx, sqlc.ExisteEntregaDeFacturaDelFolioParams{
		SucursalCodigo: *p.SucursalCodigo, Folio: *p.Folio,
	})
	if err != nil {
		return err
	}
	if ya {
		return ErrYaAdoptadoPorFactura
	}
	return nil
}
