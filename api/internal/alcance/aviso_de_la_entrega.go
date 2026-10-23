package alcance

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// EL AVISO A PEDIDO LO DECIDE UN SOLO SITIO — 23/10/2026.
//
// Hasta el 22/10/2026 una entrega era un pedido de PEDIDO y se le avisaba con su id. Desde que
// nacen de FACTURAS de Ventra (`external_id = factura:<SUC>:<punto>:<número>:<fecha>`) ese id no
// lo conoce nadie allá: PEDIDO contestaba «no existe aquí» y no se enteraba nadie. Jose: LA QUE
// MANDA ES LA FACTURA; el pedido es sólo el dato para localizarlo en PEDIDO; un pedido puede tener
// varias facturas y el estado de CADA una se cuenta por separado.
//
// [AvisoDeLaEntrega] decide TODO (a quién, con qué campos, o a nadie) y la usan el armado, el
// cierre, el despacho, el buzón y el espejo (factura cancelada en Ventra). Vive aquí y no en `api`
// para que el espejo pueda llamarla sin un request HTTP.

// AvisoDeParada es una entrega y en qué punto del reparto quedó. Es el elemento de
// `POST /integration/orders/status` en PEDIDO.
//
// Dos formas, y nunca las dos a la vez: la de un pedido de PEDIDO lleva `pedidoId`; la de una
// factura lleva `folio` + `factura` (+ `sucursal` y `puntoDeVenta`). Todo lo vacío se omite del
// JSON: un `pedidoId: ""` le haría buscar a PEDIDO un pedido que no existe.
type AvisoDeParada struct {
	// PedidoID es el id EN PEDIDO, no el nuestro. Sólo en los avisos de un pedido de PEDIDO.
	PedidoID string `json:"pedidoId,omitempty"`

	// Folio es el pedido (p. ej. PSV26-261021-1062): lo que PEDIDO usa para localizarlo.
	Folio string `json:"folio,omitempty"`
	// Sucursal es el CÓDIGO de la sucursal de Reparto (STG, HAB…).
	Sucursal string `json:"sucursal,omitempty"`
	// Factura es el número de la factura de Ventra a la que se refiere el estado.
	Factura string `json:"factura,omitempty"`
	// PuntoDeVenta es el almacén de Ventra donde se facturó: el número de factura se repite
	// entre puntos de venta.
	PuntoDeVenta string `json:"puntoDeVenta,omitempty"`

	Estado string `json:"estado"`
	Nota   string `json:"nota,omitempty"`

	// At es LA HORA DEL SUCESO, no la de la llamada.
	//
	// Es la diferencia entre que en PEDIDO ponga las cuatro o las siete y media. Con el
	// trabajo sin conexión, el logístico marca el cierre a las 16:04 en un patio sin
	// señal y la cola sube a las 19:30: el vendedor tiene que ver cuándo recibió su
	// cliente, no cuándo pilló señal el teléfono (`docs/sincronizacion.md`, «La hora es
	// la del aparato»).
	//
	// `omitzero` y no `omitempty`: un `time.Time` vacío no es «vacío» para el JSON, se
	// serializaría como el año 1, y PEDIDO se creería esa fecha. Sin hora, el campo no
	// va y PEDIDO pone la suya, que es lo que dice el contrato (`at?`).
	At time.Time `json:"at,omitzero"`
}

// Clave dice de QUÉ es el aviso, para que en un lote haya UNO por cosa y gane el último. Para una
// factura es la factura (sucursal + punto de venta + número), NO el pedido: dos facturas del
// mismo folio son dos avisos.
func (a AvisoDeParada) Clave() string {
	if a.Factura != "" {
		return "factura\x00" + a.Sucursal + "\x00" + a.PuntoDeVenta + "\x00" + a.Factura
	}
	return "pedido\x00" + a.PedidoID
}

// EntregaAAvisar son los datos de la fila de `orders` que hacen falta para decidir el aviso.
type EntregaAAvisar struct {
	ID            uuid.UUID
	Source        *sqlc.Procedencia
	ExternalID    *string
	Folio         *string
	FacturaNumero *string
}

// AvisoDeLaEntrega decide el aviso de una entrega. El `bool` es «hay a quién avisar»; si es
// falso NO es un error y no se hace ruido.
//
//   - Entrega de FACTURA con folio: aviso por factura (folio + sucursal + factura + punto).
//   - Entrega de FACTURA sin folio (la factura no trae pedido): nadie a quien avisar.
//   - Entrega de PEDIDO (`source = pedido` con id): como siempre, con `pedidoId`.
func AvisoDeLaEntrega(e EntregaAAvisar, estado string, cuando time.Time, nota string) (AvisoDeParada, bool) {
	if e.ExternalID == nil {
		return AvisoDeParada{}, false
	}
	av := AvisoDeParada{Estado: estado, Nota: nota, At: cuando}
	if EsDeFactura(*e.ExternalID) {
		folio := strings.TrimSpace(derefTexto(e.Folio))
		sucursal, punto, numero := partesDeLaClave(*e.ExternalID)
		if n := strings.TrimSpace(derefTexto(e.FacturaNumero)); n != "" {
			numero = n
		}
		if folio == "" || numero == "" {
			return AvisoDeParada{}, false
		}
		av.Folio, av.Sucursal, av.Factura, av.PuntoDeVenta = folio, sucursal, numero, punto
		return av, true
	}
	if e.Source == nil || *e.Source != sqlc.ProcedenciaPedido {
		return AvisoDeParada{}, false
	}
	av.PedidoID = *e.ExternalID
	return av, true
}

// partesDeLaClave saca sucursal, punto de venta y número de `factura:<SUC>:<punto>:<número>:<fecha>`.
// Una clave vieja (`factura:<SUC>:<folio>`, de antes de «la entrega es una factura») no trae punto:
// sale vacío y se omite del aviso.
func partesDeLaClave(externalID string) (sucursal, punto, numero string) {
	p := strings.SplitN(strings.TrimPrefix(externalID, PrefijoDeFactura), ":", 4)
	if len(p) == 4 {
		return p[0], p[1], p[2]
	}
	if len(p) > 0 {
		sucursal = p[0]
	}
	return sucursal, "", ""
}

func derefTexto(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// EntregasParaAvisar lee, por id, lo que hace falta para [AvisoDeLaEntrega].
func (a *Acotado) EntregasParaAvisar(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]EntregaAAvisar, error) {
	salida := make(map[uuid.UUID]EntregaAAvisar, len(ids))
	if len(ids) == 0 {
		return salida, nil
	}
	filas, err := a.q.EntregasParaAvisar(ctx, ids)
	if err != nil {
		return nil, err
	}
	for _, f := range filas {
		salida[f.ID] = EntregaAAvisar{
			ID: f.ID, Source: f.Source, ExternalID: f.ExternalID, Folio: f.Folio, FacturaNumero: f.FacturaNumero,
		}
	}
	return salida, nil
}

// EncolarAviso apunta UN aviso en el buzón, tal cual se va a mandar: el reintento lleva lo mismo.
// Para un aviso de factura, `pedido_id` guarda `factura:<SUC>:<punto>:<número>` (la columna es NOT
// NULL y es por donde se lee la tabla) y [DrenarElBuzon] sabe que lo que se manda es lo otro.
func (a *Acotado) EncolarAviso(ctx context.Context, av AvisoDeParada) error {
	cuando := av.At
	if cuando.IsZero() {
		cuando = time.Now().UTC()
	}
	p := sqlc.EncolarAvisoAPedidoParams{
		PedidoID:  av.PedidoID,
		Estado:    av.Estado,
		Nota:      textoONilDe(av.Nota),
		OcurrioAt: pgtype.Timestamptz{Time: cuando, Valid: true},
	}
	if av.Factura != "" {
		p.PedidoID = PrefijoDeFactura + av.Sucursal + ":" + av.PuntoDeVenta + ":" + av.Factura
		p.Folio = textoONilDe(av.Folio)
		p.Sucursal = textoONilDe(av.Sucursal)
		p.Factura = textoONilDe(av.Factura)
		p.PuntoDeVenta = textoONilDe(av.PuntoDeVenta)
	}
	return a.q.EncolarAvisoAPedido(ctx, p)
}

// AvisarFacturaCancelada encola el aviso `cancelado` de UNA factura que Ventra dejó de mandar.
// Devuelve si encoló algo: una factura sin folio no tiene a quién avisar y NO es un error.
//
// LO LLAMA EL ESPEJO (`retirarLoQueYaNoViene`), que no tiene request: el aviso sale por el mismo
// buzón y con los mismos reintentos que el del cierre.
func (a *Acotado) AvisarFacturaCancelada(ctx context.Context, e EntregaAAvisar, cuando time.Time) (bool, error) {
	av, hay := AvisoDeLaEntrega(e, "cancelado", cuando, "")
	if !hay {
		return false, nil
	}
	return true, a.EncolarAviso(ctx, av)
}

// AvisarFacturasCanceladas lo mismo para varias, por id (lee ANTES de que la fila se borre: llamar
// antes del borrado). Devuelve cuántas encoló. Sigue ante un fallo y devuelve el primero.
func (a *Acotado) AvisarFacturasCanceladas(ctx context.Context, ids []uuid.UUID, cuando time.Time) (int, error) {
	filas, err := a.EntregasParaAvisar(ctx, ids)
	if err != nil {
		return 0, err
	}
	var primero error
	n := 0
	for _, id := range ids {
		e, ok := filas[id]
		if !ok {
			continue
		}
		hay, err := a.AvisarFacturaCancelada(ctx, e, cuando)
		if err != nil && primero == nil {
			primero = err
		}
		if hay && err == nil {
			n++
		}
	}
	return n, primero
}

func textoONilDe(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
