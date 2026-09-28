package espejo

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// EL LOTE: por dónde entran los pedidos en el reparto.
//
// SE MANDA TODO EL LOTE EN UNA SOLA LLAMADA, y no de uno en uno, porque el reparto de carga
// de cada pedido es su FRACCIÓN DE PESO del envío: depende del peso total de lo que va en
// ese camión. Cotizando de a uno, la carga sería el peso de ese pedido y el número saldría
// mal.
//
// `/api/quote/batch` no es un cotizador: es LA PUERTA DE ENTRADA de los pedidos. Lo que
// contesta con `persisted:false` no entró, y hay que mirarlo.

// DestinoDeLotes es la otra punta: la API del reparto. Interfaz por lo mismo que
// `FuenteDePedidos` — las pruebas del ciclo no levantan un servidor.
type DestinoDeLotes interface {
	Cotizar(ctx context.Context, pedidos []PedidoDeFuera) (RespuestaDelLote, error)
	SincronizarCatalogo(ctx context.Context) (*RespuestaDelCatalogo, error)
}

// RespuestaDelLote es lo que contesta `/api/quote/batch`.
type RespuestaDelLote struct {
	Total         int                  `json:"total"`
	Persisted     int                  `json:"persisted"`
	Skipped       int                  `json:"skipped"`
	WeightsSource string               `json:"weightsSource"`
	Results       []ResultadoDelPedido `json:"results"`
}

type ResultadoDelPedido struct {
	Ref       *string `json:"ref"`
	Status    string  `json:"status"`
	Reason    string  `json:"reason"`
	OrderID   *string `json:"orderId"`
	Persisted *bool   `json:"persisted"`
}

// Entro dice si ese pedido acabó escrito. `persisted` ausente significa que la ruta ni lo
// intentó (vista previa o un salto de los pasos 1 a 4), que tampoco es haber entrado.
func (r ResultadoDelPedido) Entro() bool { return r.Persisted != nil && *r.Persisted }

// RespuestaDelCatalogo es lo que contesta `/api/products/sync`.
type RespuestaDelCatalogo struct {
	// Saltado lo decide el propio endpoint: contesta `{saltado:true}` cuando la última foto
	// del catálogo es reciente. Aquí NO se lleva la cuenta a propósito — el botón de «traer
	// ahora» de la pantalla y este sondeo comparten así la misma regla, en vez de tener dos
	// que se puedan contradecir.
	Saltado  bool `json:"saltado"`
	Escritos int  `json:"escritos"`
	ConError int  `json:"conError"`
}

// ClienteDelivery habla con la API del reparto.
type ClienteDelivery struct {
	Base    string
	Clave   string
	Cliente *http.Client
}

func NuevoClienteDelivery(base, clave string) *ClienteDelivery {
	return &ClienteDelivery{
		Base:  strings.TrimRight(base, "/"),
		Clave: clave,
		// El catálogo de ocho sucursales se pide por la VPN de allá y tarda: el plazo es
		// largo a propósito, pero existe.
		Cliente: &http.Client{Timeout: 300 * time.Second},
	}
}

func (c *ClienteDelivery) Cotizar(ctx context.Context, pedidos []PedidoDeFuera) (RespuestaDelLote, error) {
	cuerpo, err := json.Marshal(ArmarLote(pedidos))
	if err != nil {
		return RespuestaDelLote{}, err
	}
	crudo, err := c.pedir(ctx, "/api/quote/batch", cuerpo)
	if err != nil {
		return RespuestaDelLote{}, err
	}
	var r RespuestaDelLote
	if err := json.Unmarshal(crudo, &r); err != nil {
		return RespuestaDelLote{}, fmt.Errorf("el lote contestó algo que no se entiende: %w", err)
	}
	return r, nil
}

func (c *ClienteDelivery) SincronizarCatalogo(ctx context.Context) (*RespuestaDelCatalogo, error) {
	crudo, err := c.pedir(ctx, "/api/products/sync", nil)
	if err != nil {
		return nil, err
	}
	var r RespuestaDelCatalogo
	if err := json.Unmarshal(crudo, &r); err != nil {
		return nil, fmt.Errorf("el catálogo contestó algo que no se entiende: %w", err)
	}
	return &r, nil
}

func (c *ClienteDelivery) pedir(ctx context.Context, ruta string, cuerpo []byte) ([]byte, error) {
	var lector io.Reader
	if cuerpo != nil {
		lector = bytes.NewReader(cuerpo)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.Base+ruta, lector)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Api-Key", c.Clave)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")

	res, err := c.Cliente.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	leido, err := io.ReadAll(io.LimitReader(res.Body, 32<<20))
	if err != nil {
		return nil, err
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("%s contestó %d: %s", ruta, res.StatusCode, recorte(leido, 200))
	}
	return leido, nil
}

// ---------------------------------------------------------------------------
// El cuerpo del lote
// ---------------------------------------------------------------------------

// CuerpoDelLote es el cuerpo de `/api/quote/batch` (ver `docs/contratos-api.md` §3).
type CuerpoDelLote struct {
	Preview bool `json:"preview"`
	// `useWarehouseWeights` en true deja que el reparto baje su catálogo local de pesos
	// como RESPALDO, y sólo si alguna línea vino sin peso de PEDIDO.
	UseWarehouseWeights bool              `json:"useWarehouseWeights"`
	Orders              []PedidoDelCuerpo `json:"orders"`
}

// PedidoDelCuerpo es un pedido en la forma que entiende el lote.
//
// TODO LO QUE HACE FALTA PARA FILTRAR VA A SU PROPIO CAMPO. Antes esto viajaba dentro de un
// `meta` con el pedido entero, así que filtrar por municipio o por estado obligaba a leer y
// descartar cincuenta mil pedidos completos en cada consulta. Eso no es un filtro.
type PedidoDelCuerpo struct {
	ExternalID         string           `json:"externalId"`
	OperationNumber    string           `json:"operationNumber"`
	SucursalExternalID string           `json:"sucursalExternalId"`
	CustomerName       string           `json:"customerName"`
	Address            *string          `json:"address"`
	Phone              *string          `json:"phone"`
	Lat                *float64         `json:"lat"`
	Lng                *float64         `json:"lng"`
	Items              []RenglonDelLote `json:"items"`
	OrderDate          *string          `json:"orderDate"`

	// La marca de agua. Sin esto el reparto guarda el pedido con `pedido_updated_at` nulo,
	// el `since` no existe nunca y cada ciclo vuelve a barrer el año entero.
	PedidoUpdatedAt *string `json:"pedidoUpdatedAt"`

	Estado            *string  `json:"estado"`
	Archivado         bool     `json:"archivado"`
	FechaComprometida *string  `json:"fechaComprometida"`
	PedidoCosto       *float64 `json:"pedidoCosto"`
	Municipio         *string  `json:"municipio"`
	Vendedor          *string  `json:"vendedor"`
	SucursalCodigo    *string  `json:"sucursalCodigo"`
	// SÓLO los marcados `requiere_domicilio = true` llevan costo. Los demás se importan
	// igual —hacen falta para las rutas y la capacidad del camión— pero sin domicilio.
	RequiereDomicilio bool `json:"requiereDomicilio"`

	// El cotejo contra la FACTURA, tal como lo dejó PEDIDO. Se copia para poder FILTRAR: el
	// armador de rutas ofrece por defecto los que cuadran, porque cargar el camión con un
	// pedido que la factura cambió es descuadrar la caja. Cuando PEDIDO corrige un pedido,
	// sus líneas YA son las de la factura, y por eso el pre-despacho cuadra sin hacer nada.
	FacturaEstado    *string  `json:"facturaEstado"`
	FacturaNumero    *string  `json:"facturaNumero"`
	FacturaAt        *string  `json:"facturaAt"`
	FacturaDomicilio *float64 `json:"facturaDomicilio"`
	// Si cuadra porque se corrigió o porque vino bien no es lo mismo, y quien carga el
	// camión tiene que poder verlo.
	FacturaCorregidoAt *string `json:"facturaCorregidoAt"`
	// `factura` cuando los renglones son los de la FACTURA, `pedido` cuando son los que
	// tomo el vendedor. Ver `PedidoCrudo.ItemsOrigen`.
	ItemsOrigen *string `json:"itemsOrigen"`

	// DE QUÉ ALMACÉN SALE. Se pasa TAL CUAL a la puerta, con la misma forma con la que llegó
	// de PEDIDO: es de ahí de donde se mide la distancia del domicilio, y de esos kilómetros
	// sale lo que alguien cobra. Puntero para que «no vino» y «vino vacío» no se confundan.
	Almacen *AlmacenDelPedido `json:"almacen"`
}

type RenglonDelLote struct {
	Code        string   `json:"code"`
	Name        string   `json:"name"`
	Description string   `json:"descripcion"`
	Quantity    float64  `json:"quantity"`
	Packs       *float64 `json:"packs"`
	PesoKg      *float64 `json:"pesoKg"`
	PesoLineaKg *float64 `json:"pesoLineaKg"`

	// El almacén de ESTE renglón, con los mismos nombres que usa PEDIDO. Un pedido mezclado
	// sale de dos almacenes y el que despacha necesita saber qué línea va en cada uno.
	AlmacenCodigo *string `json:"almacenCodigo"`
	AlmacenNombre *string `json:"almacenNombre"`
}

// ArmarLote traduce lo que dio PEDIDO a lo que entiende el lote.
//
// `preview` es false y `useWarehouseWeights` true, siempre: esto no es una simulación —lo
// que se pide es justamente que los pedidos ENTREN—, y el catálogo local es el respaldo
// para las líneas que vengan sin peso.
func ArmarLote(pedidos []PedidoDeFuera) CuerpoDelLote {
	salida := CuerpoDelLote{
		UseWarehouseWeights: true,
		Orders:              make([]PedidoDelCuerpo, 0, len(pedidos)),
	}
	for _, p := range pedidos {
		salida.Orders = append(salida.Orders, pedidoAlLote(p))
	}
	return salida
}

func pedidoAlLote(p PedidoDeFuera) PedidoDelCuerpo {
	out := PedidoDelCuerpo{
		ExternalID: p.ID,
		// El folio pasa por la limpieza y el id NO. El folio es un rótulo que alguien lee y
		// compara; el id es la identidad, y limpiarla partiría en dos cada fila ya guardada
		// (ver [SinLaComillaDeExcel]).
		OperationNumber:    SinLaComillaDeExcel(strings.TrimSpace(p.Folio)),
		SucursalExternalID: p.SucursalCodigo,
		CustomerName:       nombreDelCliente(p),
		Address:            textoONada(direccionDelCliente(p)),
		Phone:              textoONada(p.Telefono),
		Lat:                latitud(p),
		Lng:                longitud(p),
		Items:              renglonesAlLote(p.Items),

		// La fecha del PEDIDO. Sin ella el pedido nace con la de hoy —cuándo lo copió el
		// espejo— y filtrar por día en el armador de rutas devuelve cero cualquier otro día,
		// porque el espejo trae quince días de una vez y todos nacerían hoy.
		OrderDate:       textoONada(p.Fecha),
		PedidoUpdatedAt: textoONada(p.UpdatedAt),

		Estado:            textoONada(p.Estado),
		Archivado:         p.Archivado,
		FechaComprometida: textoONada(p.FechaComprometida),
		PedidoCosto:       p.CostoDomicilio,
		Municipio:         textoONada(municipioDelCliente(p)),
		Vendedor:          textoONada(nombreDelVendedor(p.Vendedor)),
		SucursalCodigo:    textoONada(p.SucursalCodigo),
		RequiereDomicilio: p.RequiereDomicilio,

		FacturaEstado:      textoONada(p.FacturaEstado),
		FacturaNumero:      textoONada(p.FacturaNumero),
		FacturaAt:          textoONada(p.FacturaAt),
		FacturaDomicilio:   p.FacturaDomicilio,
		FacturaCorregidoAt: textoONada(p.FacturaCorregidoAt),
		ItemsOrigen:        textoONada(p.ItemsOrigen),

		// EL ALMACÉN VIAJA TAL CUAL Y NO SE LIMPIA AQUÍ. Ni se descarta el que venga sin
		// código, ni se rellena con el principal, ni se deduce de los renglones: quien decide
		// qué hacer con un almacén que no se puede usar es la puerta, que es la única que
		// tiene delante los almacenes de Accesos. Arreglarlo aquí sería decidir dos veces, y
		// la segunda a ciegas.
		Almacen: p.Almacen,
	}
	return out
}

// nombreDelCliente: el del cliente, si no el encargado, si no «Cliente».
//
// NUNCA VACÍO: el lote no guarda un pedido sin nombre —contesta `falta-customerName`— y el
// nombre es lo que el chofer busca en la puerta.
func nombreDelCliente(p PedidoDeFuera) string {
	if p.Cliente != nil && strings.TrimSpace(p.Cliente.Nombre) != "" {
		return p.Cliente.Nombre
	}
	if strings.TrimSpace(p.Encargado) != "" {
		return p.Encargado
	}
	return "Cliente"
}

// direccionDelCliente: la del pedido manda sobre la de la ficha del cliente. La del pedido
// es a dónde hay que llevar ESTA mercancía; la de la ficha es dónde suele estar.
func direccionDelCliente(p PedidoDeFuera) string {
	if strings.TrimSpace(p.Direccion) != "" {
		return p.Direccion
	}
	if p.Cliente != nil {
		return p.Cliente.Direccion
	}
	return ""
}

func municipioDelCliente(p PedidoDeFuera) string {
	if p.Cliente != nil {
		return p.Cliente.Municipio
	}
	return ""
}

// latitud y longitud salen de la FICHA DEL CLIENTE, que es donde vive la geolocalización.
// Sin ellas el lote salta el pedido con `sin-geolocalizacion`, y hace bien: sin coordenadas
// no se puede ordenar la ruta ni medir la distancia.
func latitud(p PedidoDeFuera) *float64 {
	if p.Cliente == nil {
		return nil
	}
	return p.Cliente.Latitud
}

func longitud(p PedidoDeFuera) *float64 {
	if p.Cliente == nil {
		return nil
	}
	return p.Cliente.Longitud
}

func nombreDelVendedor(v *VendedorDelPedido) string {
	if v == nil {
		return ""
	}
	if strings.TrimSpace(v.Nombre) != "" {
		return v.Nombre
	}
	return v.Codigo
}

func renglonesAlLote(items []RenglonDeFuera) []RenglonDelLote {
	salida := make([]RenglonDelLote, 0, len(items))
	for _, it := range items {
		r := RenglonDelLote{
			Code:        it.Codigo,
			Name:        it.Producto,
			Description: it.Descripcion,
			// Sin unidades se manda 1 y no 0: un 0 haría que el peso por unidad de venta
			// multiplicara a cero y la línea entera pesara nada.
			Quantity:    1,
			Packs:       it.Packs,
			PesoKg:      it.PesoKg,
			PesoLineaKg: it.PesoLineaKg,
			// Vacío se manda como AUSENTE, igual que el resto de los textos: un `""`
			// guardado se lee en pantalla como un dato que está y no dice nada, y filtrar
			// «qué se recoge en este almacén» por él devuelve cosas que no son.
			AlmacenCodigo: textoONada(it.AlmacenCodigo),
			AlmacenNombre: textoONada(it.AlmacenNombre),
		}
		if it.Unidades != nil && *it.Unidades > 0 {
			r.Quantity = *it.Unidades
		}
		salida = append(salida, r)
	}
	return salida
}

// textoONada: la cadena vacía se manda como ausente. Un `""` guardado se lee en pantalla
// como un dato que está y no dice nada, y filtrar por él devuelve cosas que no son.
//
// Y DE PASO SE QUITA LA COMILLA DE EXCEL, porque éste es el embudo por el que pasa TODO el
// texto que el espejo copia de PEDIDO —el teléfono, el folio, el número de factura, el
// código y la zona del cliente, el municipio, el vendedor— y limpiarlo aquí es limpiarlo
// una vez para todos los que lo consumen después. Las identidades (`ID` del pedido y del
// cliente) NO pasan por aquí, y es a propósito: ver [SinLaComillaDeExcel].
func textoONada(s string) *string {
	s = strings.TrimSpace(SinLaComillaDeExcel(strings.TrimSpace(s)))
	if s == "" {
		return nil
	}
	return &s
}
