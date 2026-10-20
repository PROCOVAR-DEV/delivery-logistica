package ventra

// LAS FACTURAS CON DOMICILIO: la segunda fuente de entregas del espejo (issue 20, Fase A).
//
//	GET {WAREHOUSE_API_URL}/axis/home-delivery-invoices?database=<slug>&from=AAAA-MM-DD&to=AAAA-MM-DD&skus=45,50,51
//
// El mismo Bearer (`axis.read`) que el catálogo. UNA sucursal por llamada (no hay «all»), con
// un máximo de 93 días entre `from` y `to`. La respuesta es
// `{database, branchName, from, to, deliverySkus, currency, summary, invoices:[{header, items,
// totals, payments}]}`; aquí sólo se lee lo que el mapeo usa (ver `espejo.FacturaDeVentra`).
//
// # LO QUE ESTE LECTOR GARANTIZA, y es lo mismo que `Catalogo`, más una cosa
//
//   - Bearer, plazo y tope de lectura. Sin URL o sin token NO sale a la red y lo dice.
//   - UNA RESPUESTA MAL FORMADA ES UN ERROR. Que no sea JSON, que no traiga `invoices`, que
//     la base que contesta no sea la que se pidió, que `summary.invoices` no cuadre con las
//     que vinieron, una factura sin número o con la fecha rota: todo error. Nada se «arregla».
//   - Pero un `invoices: []` es una respuesta BUENA: una ventana sin facturas con domicilio es
//     legítima (a diferencia del catálogo, que vacío es una base caída). Lo que hay que distinguir
//     es el vacío del ERROR, y eso lo hace la diferencia entre `[]` y la clave ausente. Quien
//     retira lo que «ya no viene» (`espejo.facturasDeLaSucursal`) además se niega a creerse un
//     vacío cuando en la base hay entregas de esa ventana.
//   - TODO O ERROR: una ventana de más de 93 días se parte en tramos, y si falla UNO no se
//     devuelve una lista a medias, porque quien la compara con lo guardado creería que las
//     facturas del tramo que falló se anularon.

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"time"

	"procovar/reparto-api/internal/espejo"
)

// Que el compilador avise si la interfaz del espejo cambia y este cliente deja de valer.
var _ espejo.FuenteDeFacturas = (*Cliente)(nil)

const rutaFacturas = "/axis/home-delivery-invoices"

// MaxDiasPorLlamada: Ventra admite 93 días «entre ambas»; se cuenta INCLUSIVE (desde y hasta
// cuentan), que es la lectura segura. Un día de más es un 400 y un tramo sin traer.
const MaxDiasPorLlamada = 93

// topeDeFacturas: lo que se lee de una respuesta. Un barrido de 60 días de una sucursal grande
// son varios megas; pasarse de aquí es un ERROR y no un JSON cortado a la mitad que se «lee».
const topeDeFacturas = 64 << 20

var reFecha = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

// FacturasConDomicilio: ver `espejo.FuenteDeFacturas`.
func (c *Cliente) FacturasConDomicilio(
	ctx context.Context, base string, desde, hasta time.Time, skus []string,
) ([]espejo.FacturaDeVentra, error) {
	base = strings.TrimSpace(base)
	if base == "" {
		return nil, errors.New(
			"se pidieron las facturas sin decir de qué base de Ventra: es una sucursal por llamada")
	}
	tramos, err := tramosDeVentra(desde, hasta)
	if err != nil {
		return nil, err
	}
	var todas []espejo.FacturaDeVentra
	for _, t := range tramos {
		fs, err := c.unTramoDeFacturas(ctx, base, t[0], t[1], skus)
		if err != nil {
			return nil, err
		}
		todas = append(todas, fs...)
	}
	return todas, nil
}

// tramosDeVentra parte [desde, hasta] (días, los dos incluidos) en tramos contiguos de a lo
// sumo [MaxDiasPorLlamada] días. Sin huecos ni solapes: un hueco son facturas que no se ven, un
// solape son facturas contadas dos veces.
func tramosDeVentra(desde, hasta time.Time) ([][2]time.Time, error) {
	desde, hasta = dia(desde), dia(hasta)
	if hasta.Before(desde) {
		return nil, fmt.Errorf("la ventana de facturas va al revés: desde %s, hasta %s",
			desde.Format(time.DateOnly), hasta.Format(time.DateOnly))
	}
	var tramos [][2]time.Time
	for ini := desde; !ini.After(hasta); {
		fin := ini.AddDate(0, 0, MaxDiasPorLlamada-1)
		if fin.After(hasta) {
			fin = hasta
		}
		tramos = append(tramos, [2]time.Time{ini, fin})
		ini = fin.AddDate(0, 0, 1)
	}
	return tramos, nil
}

// dia deja sólo el día (año, mes, día) en UTC: las ventanas son fechas, sin hora ni huso.
func dia(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func (c *Cliente) unTramoDeFacturas(
	ctx context.Context, base string, desde, hasta time.Time, skus []string,
) ([]espejo.FacturaDeVentra, error) {
	q := url.Values{
		"database": {base},
		"from":     {desde.Format(time.DateOnly)},
		"to":       {hasta.Format(time.DateOnly)},
	}
	if len(skus) > 0 {
		q.Set("skus", strings.Join(skus, ","))
	}
	crudo, err := c.pedirConTope(ctx, rutaFacturas, q, topeDeFacturas)
	if err != nil {
		return nil, err
	}
	return leerFacturas(crudo, base)
}

// ---------------------------------------------------------------------------
// Leer la respuesta
// ---------------------------------------------------------------------------

type respuestaDeFacturas struct {
	Database string `json:"database"`
	Summary  *struct {
		Invoices *int `json:"invoices"`
	} `json:"summary"`
	// PUNTERO: la clave ausente (error) y `[]` (ventana sin facturas, bueno) son cosas distintas.
	Invoices *[]facturaCruda `json:"invoices"`
}

type facturaCruda struct {
	Header struct {
		InvoiceNumber textoONumero `json:"invoiceNumber"`
		Date          string       `json:"date"`
		PointOfSale   struct {
			Code textoONumero `json:"code"`
			Name string       `json:"name"`
		} `json:"pointOfSale"`
		Customer struct {
			Name    string `json:"name"`
			Address string `json:"address"`
			City    string `json:"city"`
			Phone   string `json:"phone"`
		} `json:"customer"`
		Seller            string `json:"seller"`
		OrderNumber       string `json:"orderNumber"`
		CustomerReference string `json:"customerReference"`
	} `json:"header"`
	Items []struct {
		ProductCode textoONumero `json:"productCode"`
		ProductName string       `json:"productName"`
		Unit        string       `json:"unit"`
		Quantity    float64      `json:"quantity"`
		Amount      *float64     `json:"amount"`
		UnitPrice   float64      `json:"unitPrice"`
		IsDelivery  bool         `json:"isDelivery"`
	} `json:"items"`
}

// textoONumero lee un campo que Ventra manda unas veces como número (`47252`) y otras como
// cadena (`"2"`, `"PARR0002"`), y lo deja como texto TAL CUAL, sin pasar por un float: un
// número de factura no puede perder dígitos ni ganar un `.0`.
type textoONumero string

func (t *textoONumero) UnmarshalJSON(b []byte) error {
	s := strings.TrimSpace(string(b))
	if s == "null" {
		*t = ""
		return nil
	}
	if strings.HasPrefix(s, `"`) {
		var cadena string
		if err := json.Unmarshal(b, &cadena); err != nil {
			return err
		}
		*t = textoONumero(strings.TrimSpace(cadena))
		return nil
	}
	*t = textoONumero(s)
	return nil
}

// leerFacturas decodifica y VALIDA el cuerpo. `base` es la que se pidió.
func leerFacturas(crudo []byte, base string) ([]espejo.FacturaDeVentra, error) {
	var r respuestaDeFacturas
	if err := json.NewDecoder(bytes.NewReader(crudo)).Decode(&r); err != nil {
		return nil, fmt.Errorf("Ventra contestó algo que no se entiende en %s (%s): %w",
			rutaFacturas, recorte(string(crudo), 120), err)
	}
	if r.Invoices == nil {
		return nil, fmt.Errorf("Ventra contestó %s sin la lista `invoices`: %s",
			rutaFacturas, recorte(string(crudo), 120))
	}
	if r.Database != "" && clave(r.Database) != clave(base) {
		return nil, fmt.Errorf(
			"Ventra contestó las facturas de la base %q cuando se pidió %q: guardarlas como de la otra "+
				"sucursal sería repartir sus entregas desde el almacén equivocado", r.Database, base)
	}
	// El resumen dice cuántas facturas hay: si no cuadran con las que vinieron, la respuesta se
	// cortó o se recortó por el camino. Pedir un tope y no comprobar el resultado (CLAUDE.md §3).
	if r.Summary != nil && r.Summary.Invoices != nil && *r.Summary.Invoices != len(*r.Invoices) {
		return nil, fmt.Errorf(
			"Ventra dice %d facturas en el resumen y trajo %d en la lista (base %q): la respuesta está "+
				"cortada y no se usa", *r.Summary.Invoices, len(*r.Invoices), base)
	}

	salida := make([]espejo.FacturaDeVentra, 0, len(*r.Invoices))
	for i, f := range *r.Invoices {
		h := f.Header
		numero := strings.TrimSpace(string(h.InvoiceNumber))
		if numero == "" {
			return nil, fmt.Errorf("la factura %d de la respuesta de Ventra no trae `invoiceNumber`", i+1)
		}
		if !reFecha.MatchString(h.Date) {
			return nil, fmt.Errorf("la factura %s de la respuesta de Ventra trae la fecha %q, que no es AAAA-MM-DD",
				numero, h.Date)
		}
		fa := espejo.FacturaDeVentra{
			Numero: numero,
			Fecha:  h.Date,
			Punto: espejo.PuntoDeVenta{
				Codigo: strings.TrimSpace(string(h.PointOfSale.Code)),
				Nombre: strings.TrimSpace(h.PointOfSale.Name),
			},
			Cliente: espejo.ClienteDeFactura{
				Nombre:    strings.TrimSpace(h.Customer.Name),
				Direccion: strings.TrimSpace(h.Customer.Address),
				Ciudad:    strings.TrimSpace(h.Customer.City),
				Telefono:  strings.TrimSpace(h.Customer.Phone),
			},
			Vendedor:             strings.TrimSpace(h.Seller),
			Pedido:               strings.TrimSpace(h.OrderNumber),
			ReferenciaDelCliente: strings.TrimSpace(h.CustomerReference),
		}
		for _, it := range f.Items {
			importe := it.Quantity * it.UnitPrice
			if it.Amount != nil {
				importe = *it.Amount
			}
			fa.Lineas = append(fa.Lineas, espejo.LineaDeFactura{
				Codigo:      strings.TrimSpace(string(it.ProductCode)),
				Nombre:      strings.TrimSpace(it.ProductName),
				Unidad:      strings.TrimSpace(it.Unit),
				Cantidad:    it.Quantity,
				Importe:     importe,
				EsDomicilio: it.IsDelivery,
			})
		}
		salida = append(salida, fa)
	}
	return salida, nil
}
