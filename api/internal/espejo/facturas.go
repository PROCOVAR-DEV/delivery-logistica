package espejo

// LA FACTURA CON DOMICILIO DE VENTRA COMO SEGUNDA FUENTE DE ENTREGAS (issue 20 de Amado,
// «Sustitución de Pedido por Factura», Fase A; decidido por Jose el 20/10/2026).
//
// Reparto deja de alimentarse de los PEDIDOS de PEDIDO y pasa a alimentarse de las FACTURAS
// CON DOMICILIO de Ventra. Los CLIENTES se quedan en PEDIDO por ahora: de su espejo salen las
// coordenadas, que Ventra no trae. Esta fase añade la factura como SEGUNDA fuente que convive
// con la de PEDIDO (`SYNC_FUENTE`), sin cortar nada: el corte (apagar PEDIDO) y la limpieza
// (quitar el cotejo, las columnas y los textos de PEDIDO) son fases posteriores.
//
// ESTE FICHERO ES EL MAPEO, entero y sin red ni base, para que se pruebe de verdad. Lo que
// hace es traducir las facturas de una sucursal a `PedidoDeFuera`, o sea al MISMO cuerpo que
// ya entiende la puerta (`POST /api/quote/batch`): NO hay una segunda puerta, y por eso las
// guardas de la primera (sucursal mapeada, punto de partida, nombre del cliente, el upsert
// idempotente) valen igual para las dos fuentes.
//
// # Las decisiones de Jose, que mandan
//
//  1. EL CONDUCE ES EL CONJUNTO DE NÚMEROS DE FACTURA («un conduce puede tener varias
//     facturas»). Una ENTREGA es un pedido de la nota (`orderNumber`), que puede reunir VARIAS
//     facturas —el 3 % de los pedidos de Santiago, el 11 % de los de Guantánamo—. Las facturas
//     de la MISMA sucursal con el MISMO `orderNumber` son UNA entrega; una factura sin
//     `orderNumber` es su propia entrega.
//  2. EL PESO SALE DE VENTRA: `products.weight` × cantidad (tabla local `products`, la que
//     baja `/api/products/sync`; `sku` = `productCode`). Cubre el 100 % de las líneas
//     realmente facturadas.
//
// # La identidad de una FACTURA y la de una ENTREGA
//
// El número de factura SE REPITE entre puntos de venta. Una factura es sucursal + punto de
// venta + número + fecha, nunca el número solo. Una entrega es sucursal + folio, o, sin folio,
// la factura entera. De ahí sale el `external_id`: `factura:` + [EntregaDeFactura.Clave]. La
// convención del prefijo (y por qué no hay un valor nuevo del enum `procedencia`) está en
// `alcance.EsDeFactura`.

import (
	"context"
	"fmt"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"

	"procovar/reparto-api/internal/alcance"
)

// Las tres fuentes que `SYNC_FUENTE` admite. `pedido` es la de siempre y el valor por defecto:
// desplegar esto no cambia NADA hasta que alguien escriba otra cosa.
const (
	FuenteDePedido  = "pedido"
	FuenteDeFactura = "factura"
	FuenteAmbas     = "ambas"
)

// SkusDeDomicilio son los productos que Ventra marca como línea de domicilio: 50 (PROCOVAR), 51
// (CES) y el 45, el producto VIEJO, anterior al 06/10/2026. Por defecto Ventra devuelve sólo
// 50,51, y las facturas de antes de esa fecha se perderían: se piden los tres SIEMPRE.
var SkusDeDomicilio = []string{"45", "50", "51"}

// MotivoYaAdoptado es el `reason` con el que la puerta dice que un pedido de PEDIDO no se guardó
// porque su folio ya es una entrega de factura. No es un fallo.
const MotivoYaAdoptado = "ya-adoptado-por-factura"

// ---------------------------------------------------------------------------
// Lo que Ventra da
// ---------------------------------------------------------------------------

// FacturaDeVentra es una factura con domicilio, ya sin el ruido: lo que el mapeo usa. Los
// pagos NO están (`payments`): un cobro puede cubrir varias facturas y no dice nada de a dónde
// va la mercancía.
type FacturaDeVentra struct {
	Numero string // invoiceNumber, como texto: Ventra lo manda número y a veces cadena
	Fecha  string // AAAA-MM-DD, el día de la factura
	Punto  PuntoDeVenta

	Cliente  ClienteDeFactura
	Vendedor string
	// Pedido es el `orderNumber`: el folio de PEDIDO, sacado de la nota `P-<folio>; V-…; C-…;`
	// de la venta. Llega VACÍO si la venta no trae esa nota.
	Pedido string
	// ReferenciaDelCliente es el `customerReference`: el código de cliente de la nota `C-…`. A
	// veces no es un código sino un NOMBRE (visto en el ejemplo real de Santiago).
	ReferenciaDelCliente string

	Lineas []LineaDeFactura
}

// PuntoDeVenta es el almacén de Ventra. Su `Codigo` es el `objectCode` con el que Reparto
// empareja el almacén de salida.
type PuntoDeVenta struct {
	Codigo string
	Nombre string
}

type ClienteDeFactura struct {
	Nombre    string
	Direccion string
	Ciudad    string
	Telefono  string
}

// LineaDeFactura es un renglón. El DOMICILIO es la línea `EsDomicilio` (SKU 50/51/45) con
// precio 1 USD y la CANTIDAD igual al importe en USD.
type LineaDeFactura struct {
	Codigo      string
	Nombre      string
	Unidad      string
	Cantidad    float64
	Importe     float64
	EsDomicilio bool
}

// FuenteDeFacturas es por dónde se le pregunta a Ventra. Interfaz por lo mismo que
// `FuenteDePedidos`: el ciclo se prueba sin red.
type FuenteDeFacturas interface {
	// Bases devuelve, por CÓDIGO de sucursal nuestro, el slug de su base de Ventra.
	Bases(ctx context.Context) (map[string]string, error)
	// FacturasConDomicilio devuelve las facturas con domicilio de UNA base entre dos días
	// (los dos incluidos). Todo o error: una ventana partida en tramos donde falla uno NO da
	// una lista a medias, porque quien retira lo que «ya no viene» creería que lo que falta se
	// anuló. Una ventana sin facturas es legítima y devuelve lista vacía y SIN error; una
	// respuesta que no se entiende, no.
	FacturasConDomicilio(ctx context.Context, base string, desde, hasta time.Time, skus []string) ([]FacturaDeVentra, error)
}

// ---------------------------------------------------------------------------
// Agrupar: de facturas a entregas
// ---------------------------------------------------------------------------

// EntregaDeFactura es lo que se va a repartir: las facturas de UN pedido.
type EntregaDeFactura struct {
	Sucursal string
	// Folio es el `orderNumber` común. Vacío = la entrega es una factura suelta.
	Folio string
	// Facturas va ordenado por fecha, punto de venta y número, para que el conduce, el almacén
	// «de la primera» y el cliente elegido no cambien de un ciclo al siguiente.
	Facturas []FacturaDeVentra
}

// Clave es la identidad de la entrega dentro del `external_id`:
//
//	<SUC>:<folio normalizado>           si hay folio (`alcance.FolioNormalizado`: `pxx-900` y
//	                                    `PXX - 900` son la MISMA entrega, y la misma que adopta
//	                                    al `PXX-900` de PEDIDO)
//	<SUC>:<punto de venta>:<número>:<fecha>   si no (la factura suelta)
//
// EL PUNTO DE VENTA ES PARTE DE LA CLAVE DE LA FACTURA SUELTA: el número se repite entre
// puntos de venta, y sin él dos facturas distintas serían la misma entrega y una pisaría a la
// otra (la entrega de un cliente en la caja del otro). Lo ata
// `TestElMismoNumeroEnDosPuntosDeVentaSonDosFacturas`.
func (e EntregaDeFactura) Clave() string {
	if e.Folio != "" {
		return e.Sucursal + ":" + alcance.FolioNormalizado(e.Folio)
	}
	f := e.Facturas[0]
	return e.Sucursal + ":" + f.Punto.Codigo + ":" + f.Numero + ":" + f.Fecha
}

// ExternalID es el `external_id` con el que la entrega se guarda: `factura:` + la clave.
func (e EntregaDeFactura) ExternalID() string { return alcance.PrefijoDeFactura + e.Clave() }

// Conduce son los números de factura de la entrega, sin repetir y ordenados, unidos por «, ».
// Es el `operation_number` de la fila («un conduce puede tener varias facturas») y también su
// `factura_numero`, donde `informes.go` ya acepta la coma.
func (e EntregaDeFactura) Conduce() string {
	vistos := map[string]bool{}
	numeros := make([]string, 0, len(e.Facturas))
	for _, f := range e.Facturas {
		if !vistos[f.Numero] {
			vistos[f.Numero] = true
			numeros = append(numeros, f.Numero)
		}
	}
	sort.SliceStable(numeros, func(i, j int) bool { return menorNumero(numeros[i], numeros[j]) })
	return strings.Join(numeros, ", ")
}

// menorNumero ordena como lo lee una persona: 9 antes que 10 si los dos son números, y por
// texto si no.
func menorNumero(a, b string) bool {
	na, ea := strconv.ParseInt(a, 10, 64)
	nb, eb := strconv.ParseInt(b, 10, 64)
	if ea == nil && eb == nil && na != nb {
		return na < nb
	}
	return a < b
}

// AgruparPorFolio junta las facturas de una sucursal en entregas.
//
//   - Las de la MISMA sucursal con el MISMO folio son UNA entrega.
//   - Una sin folio es su propia entrega.
//   - Una factura repetida en la respuesta (misma sucursal, punto de venta, número y fecha) se
//     cuenta UNA vez: si no, sus renglones se sumarían dos veces y el camión cargaría el doble.
//
// El orden de salida es el de la primera aparición de cada entrega, que es estable mientras
// Ventra conteste en el mismo orden, y de todos modos no importa: la clave es la identidad.
func AgruparPorFolio(sucursal string, facturas []FacturaDeVentra) []EntregaDeFactura {
	vistas := map[string]bool{}
	var salida []EntregaDeFactura
	indice := map[string]int{}
	for _, f := range facturas {
		f.Pedido = SinLaComillaDeExcel(strings.TrimSpace(f.Pedido))
		// Un folio que no deja ni una letra ni un dígito (`---`) no es un folio.
		clave := alcance.FolioNormalizado(f.Pedido)
		if clave == "" {
			f.Pedido = ""
		}
		id := sucursal + "|" + f.Punto.Codigo + "|" + f.Numero + "|" + f.Fecha
		if vistas[id] {
			continue
		}
		vistas[id] = true

		if f.Pedido == "" {
			salida = append(salida, EntregaDeFactura{Sucursal: sucursal, Facturas: []FacturaDeVentra{f}})
			continue
		}
		// Se agrupa por el folio NORMALIZADO: dos facturas del mismo pedido tecleadas distinto
		// (`PXX-900` y `pxx-900`) son UNA entrega, no dos que se pisarían con la misma clave.
		if i, hay := indice[clave]; hay {
			salida[i].Facturas = append(salida[i].Facturas, f)
			continue
		}
		indice[clave] = len(salida)
		salida = append(salida, EntregaDeFactura{Sucursal: sucursal, Folio: f.Pedido, Facturas: []FacturaDeVentra{f}})
	}
	for i := range salida {
		fs := salida[i].Facturas
		sort.SliceStable(fs, func(a, b int) bool {
			if fs[a].Fecha != fs[b].Fecha {
				return fs[a].Fecha < fs[b].Fecha
			}
			if fs[a].Punto.Codigo != fs[b].Punto.Codigo {
				return fs[a].Punto.Codigo < fs[b].Punto.Codigo
			}
			return menorNumero(fs[a].Numero, fs[b].Numero)
		})
		// El folio que se guarda es el de la primera factura ya ORDENADA, no el de la que llegó
		// primero: que Ventra cambie el orden de su respuesta no puede reescribir la columna.
		if salida[i].Folio != "" {
			salida[i].Folio = fs[0].Pedido
		}
	}
	return salida
}

// ---------------------------------------------------------------------------
// Las coordenadas: del espejo de clientes de PEDIDO
// ---------------------------------------------------------------------------

// PuntoDeCliente es un cliente geolocalizado del espejo de clientes.
type PuntoDeCliente struct {
	Codigo string
	Nombre string
	Lat    float64
	Lng    float64
}

// PuntosDeClientes busca el punto de un cliente por su código y, si eso no es un código, por su
// nombre. Una sucursal por instancia: los códigos y los nombres se repiten entre sucursales.
type PuntosDeClientes struct {
	porCodigo map[string][]PuntoDeCliente
	porNombre map[string][]PuntoDeCliente
}

// NuevosPuntos indexa los clientes de UNA sucursal.
func NuevosPuntos(clientes []PuntoDeCliente) *PuntosDeClientes {
	p := &PuntosDeClientes{porCodigo: map[string][]PuntoDeCliente{}, porNombre: map[string][]PuntoDeCliente{}}
	for _, c := range clientes {
		if k := normalizarReferencia(c.Codigo); k != "" {
			p.porCodigo[k] = append(p.porCodigo[k], c)
		}
		if k := normalizarReferencia(c.Nombre); k != "" {
			p.porNombre[k] = append(p.porNombre[k], c)
		}
	}
	return p
}

// normalizarReferencia: mayúsculas y sin espacios. Así «sc06 tcp0158» y «SC06TCP0158» son el
// mismo código, que es como los escribe quien teclea la nota de una venta.
func normalizarReferencia(s string) string {
	var b strings.Builder
	for _, r := range s {
		if !unicode.IsSpace(r) {
			b.WriteRune(unicode.ToUpper(r))
		}
	}
	return b.String()
}

// Cómo se halló (o no) el punto. Se cuenta en el ciclo: un cliente sin punto es una entrega
// que alguien tiene que ubicar a mano, y quien despliega tiene que ver cuántas son.
const (
	PuntoPorCodigo    = "codigo"
	PuntoPorNombre    = "nombre"
	PuntoAmbiguo      = "ambiguo"
	PuntoNoEncontrado = "ninguno"
)

// Buscar devuelve el punto de la referencia del cliente (`customerReference`).
//
// Primero por CÓDIGO. Si no hay código con eso, por NOMBRE, y SOLO si es único en la sucursal:
// dos clientes con el mismo nombre en sitios distintos son dos personas, y un punto elegido
// entre ellos al azar es un domicilio cobrado a la distancia de otra casa. Lo ambiguo y lo
// que no está NO dan punto, y se dicen aparte. Dos filas que coinciden en las coordenadas
// (el mismo cliente dado de alta dos veces) sí valen.
func (p *PuntosDeClientes) Buscar(referencia string) (lat, lng float64, como string) {
	k := normalizarReferencia(referencia)
	if k == "" || p == nil {
		return 0, 0, PuntoNoEncontrado
	}
	if cs := p.porCodigo[k]; len(cs) > 0 {
		return unicoPunto(cs, PuntoPorCodigo)
	}
	if cs := p.porNombre[k]; len(cs) > 0 {
		return unicoPunto(cs, PuntoPorNombre)
	}
	return 0, 0, PuntoNoEncontrado
}

func unicoPunto(cs []PuntoDeCliente, como string) (float64, float64, string) {
	for _, c := range cs[1:] {
		if c.Lat != cs[0].Lat || c.Lng != cs[0].Lng {
			return 0, 0, PuntoAmbiguo
		}
	}
	return cs[0].Lat, cs[0].Lng, como
}

// ---------------------------------------------------------------------------
// Los pesos: del catálogo local de Ventra
// ---------------------------------------------------------------------------

// ProductoDeVentra es lo que la tabla `products` sabe de un producto de una sucursal.
type ProductoDeVentra struct {
	Sku string
	// PesoKg es lo que pesa UNA UNIDAD DE VENTA (una B de cerveza, una caja, una PACA).
	PesoKg float64
	// UnidadesPorEmpaque: cuántas unidades trae esa unidad de venta (0 = no se sabe).
	UnidadesPorEmpaque float64
}

// ---------------------------------------------------------------------------
// El mapeo: de entrega a pedido
// ---------------------------------------------------------------------------

// ContextoDeMapeo es lo que el mapeo necesita de la base, ya leído: así el mapeo no la toca.
type ContextoDeMapeo struct {
	Puntos    *PuntosDeClientes
	Productos map[string]ProductoDeVentra // por sku normalizado (`claveDeProducto`)
}

func claveDeProducto(sku string) string { return strings.ToUpper(strings.TrimSpace(sku)) }

// InformeDeEntrega es lo que el mapeo NO pudo resolver, para decirlo y no esconderlo: «nada se
// descarta en silencio».
type InformeDeEntrega struct {
	// Punto: cómo se halló (`Punto*`). Distinto de `PuntoPorCodigo`/`PuntoPorNombre` = SIN
	// coordenadas: la entrega se guarda igual y se ubica a mano (`PUT /api/orders/{id}/punto`).
	Punto string
	// SinMercancia: la factura sólo trae la línea de domicilio. Se guarda igual.
	SinMercancia bool
	// FueraDelCatalogo y SinPeso: los productos que no se pudieron pesar, por código. Sin peso la
	// línea cuenta como «sin peso» en todas las pantallas; nunca se inventa uno.
	FueraDelCatalogo []string
	SinPeso          []string
	// LineasSinCantidad: renglones con cantidad cero o negativa, que no se cargan.
	LineasSinCantidad int
}

// APedido traduce la entrega al `PedidoDeFuera` que entiende la puerta. El mapeo, campo a
// campo, está en `docs/contratos-api.md` («La entrega que nace de una factura»).
func (e EntregaDeFactura) APedido(ctx ContextoDeMapeo) (PedidoDeFuera, InformeDeEntrega) {
	var inf InformeDeEntrega
	primera := e.Facturas[0]

	// FECHA: la de la factura más antigua, a las 12:00 de Cuba. Mediodía y no medianoche
	// a propósito: los filtros pasan `factura_at` al día de America/Havana, y a las 12:00 el día
	// es el mismo con el huso de invierno (-05) y con el de verano (-04), así que no hay
	// medianoche que se cuele en el día de antes. El huso va FIJO en -05:00 porque la imagen del
	// servicio no lleva `tzdata` y `time.LoadLocation` fallaría dentro y funcionaría en el portátil.
	fecha := primera.Fecha + "T12:00:00-05:00"

	conduce := e.Conduce()
	p := PedidoDeFuera{
		ID:             e.ExternalID(),
		Folio:          conduce, // el «conduce» (operation_number)
		FolioDelPedido: e.Folio,
		Fecha:          fecha,

		SucursalCodigo: e.Sucursal,

		// LA FACTURA ES LA VERDAD: entra. `igual` es el único estado que el cotejo de PEDIDO
		// no puede contradecir aquí, porque no hay cotejo.
		FacturaEstado:     "igual",
		FacturaNumero:     conduce,
		FacturaAt:         fecha,
		ItemsOrigen:       "factura",
		RequiereDomicilio: true,
		// Estado, FechaComprometida y CostoDomicilio (pedido_costo) NO existen en una factura: nil.
	}

	// --- El cliente ----------------------------------------------------------
	var nombre, telefono, direccion, ciudad, vendedor string
	for _, f := range e.Facturas {
		nombre = primeroNoVacio(nombre, f.Cliente.Nombre)
		telefono = primeroNoVacio(telefono, f.Cliente.Telefono)
		direccion = primeroNoVacio(direccion, f.Cliente.Direccion)
		ciudad = primeroNoVacio(ciudad, f.Cliente.Ciudad)
		vendedor = primeroNoVacio(vendedor, f.Vendedor)
	}
	var referencia string
	for _, f := range e.Facturas {
		referencia = primeroNoVacio(referencia, f.ReferenciaDelCliente)
	}
	// customer.name; si viene vacío, customerReference; y si tampoco, `nombreDelCliente` pone
	// «Cliente».
	p.Cliente = &ClienteDelPedido{Nombre: primeroNoVacio(nombre, referencia), Municipio: ciudad}
	p.Telefono = telefono
	p.Direccion = direccionConCiudad(direccion, ciudad)
	if vendedor != "" {
		p.Vendedor = &VendedorDelPedido{Nombre: vendedor}
	}

	// --- Las coordenadas: del espejo de clientes ------------------------------
	lat, lng, como := ctx.Puntos.Buscar(referencia)
	inf.Punto = como
	if como == PuntoPorCodigo || como == PuntoPorNombre {
		p.Cliente.Latitud, p.Cliente.Longitud = &lat, &lng
	}

	// --- El almacén de salida: el punto de venta de Ventra ---------------------
	mezclado := false
	for _, f := range e.Facturas {
		if f.Punto.Codigo != primera.Punto.Codigo {
			mezclado = true
		}
	}
	p.Almacen = &AlmacenDelPedido{
		Codigo: primera.Punto.Codigo, Nombre: primera.Punto.Nombre,
		SucursalCodigo: e.Sucursal, Mezclado: &mezclado,
	}

	// --- Domicilio y renglones -------------------------------------------------
	domicilio := 0.0
	var orden []string
	renglones := map[string]*RenglonDeFuera{}
	vistos := map[string]bool{}
	for _, f := range e.Facturas {
		for _, l := range f.Lineas {
			if l.EsDomicilio {
				domicilio += l.Importe
				continue
			}
			if !(l.Cantidad > 0) {
				inf.LineasSinCantidad++
				continue
			}
			// Un renglón es de UNA factura (00026, issue 22 de Maikel: la tarjeta de estiba se rebaja
			// por cantidad Y factura): el mismo producto en dos facturas de la entrega son DOS
			// renglones, no uno sumado. Dentro de la misma factura sí se suma, y no si salen de
			// puntos de venta distintos: el renglón lleva SU almacén, y sumarlos lo dejaría
			// apuntado a uno solo. La cuenta de la entrega no cambia: todo lo que suma es por renglón.
			k := claveDeProducto(l.Codigo) + "|" + f.Punto.Codigo + "|" + f.Numero
			r, hay := renglones[k]
			if !hay {
				r = &RenglonDeFuera{
					Codigo: l.Codigo, Producto: l.Nombre, Descripcion: l.Nombre,
					Packs: new(float64), AlmacenCodigo: f.Punto.Codigo, AlmacenNombre: f.Punto.Nombre,
					FacturaNumero: f.Numero,
				}
				renglones[k] = r
				orden = append(orden, k)
			}
			*r.Packs += l.Cantidad

			if !vistos[claveDeProducto(l.Codigo)] {
				vistos[claveDeProducto(l.Codigo)] = true
				if prod, hay := ctx.Productos[claveDeProducto(l.Codigo)]; !hay {
					inf.FueraDelCatalogo = append(inf.FueraDelCatalogo, l.Codigo)
				} else if !(prod.PesoKg > 0) {
					inf.SinPeso = append(inf.SinPeso, l.Codigo)
				}
			}
		}
	}
	for _, k := range orden {
		r := *renglones[k]
		prod, hay := ctx.Productos[claveDeProducto(r.Codigo)]
		// LA CANTIDAD DE LA FACTURA ES EN UNIDADES DE VENTA (B, C, PACA): son los `packs`. Las
		// unidades salen de multiplicar por lo que trae cada una, y si eso no se sabe son los
		// mismos números (nunca 0: un 0 haría que el peso por unidad de venta diera cero).
		packs := *r.Packs
		porEmpaque := 0.0
		if hay {
			porEmpaque = prod.UnidadesPorEmpaque
		}
		// El catálogo local no trae las unidades por empaque (ningún producto las tiene), pero el NOMBRE de
		// Ventra las dice: «PACA 10U», «CAJA 24U», «BLISTER 6U» (Jose, 21/10/2026: «20 pacas son 200 unidades, no 20»).
		if !(porEmpaque > 0) {
			porEmpaque = unidadesPorEmpaqueDelNombre(r.Producto)
		}
		unidades := packs
		if porEmpaque > 0 {
			unidades = packs * porEmpaque
		}
		r.Unidades = &unidades
		// El peso es por unidad de venta y la cascada de pesos de la puerta (`cotizar.PesosDeRenglones`,
		// escalón 2) hace `pesoKg × packs`. Aquí NO se multiplica: se escribiría otra cuenta.
		// Sin peso en `products`, el campo se queda AUSENTE y la línea cuenta como sin peso.
		if hay && prod.PesoKg > 0 {
			peso := prod.PesoKg
			r.PesoKg = &peso
		}
		p.Items = append(p.Items, r)
	}
	inf.SinMercancia = len(p.Items) == 0

	// La suma de las líneas de domicilio, a céntimos: 0.29 + 0.35 no es 0.6399999.
	dom := math.Round(domicilio*100) / 100
	p.FacturaDomicilio = &dom
	return p, inf
}

// unidadesDelNombre lee las unidades por empaque del nombre del producto en Ventra: `PACA 10U` son 10,
// `CAJA 24U` 24, `BLISTER 6U` 6 y `PACA 12P DE 4U` 12 paquetes de 4 = 48. Sin ese patrón (un panel solar, un
// producto suelto) devuelve 0 y quien llama deja las unidades igual a los empaques. Es una lectura del nombre,
// no del catálogo: si Ventra algún día manda las unidades por empaque de verdad, manda el catálogo.
var unidadesDelNombre = regexp.MustCompile(`(?i)\b(\d+)\s*P\s*DE\s*(\d+)\s*U\b|\b(\d+)\s*U\b`)

func unidadesPorEmpaqueDelNombre(nombre string) float64 {
	m := unidadesDelNombre.FindStringSubmatch(nombre)
	if m == nil {
		return 0
	}
	num := func(s string) float64 {
		n, err := strconv.ParseFloat(s, 64)
		if err != nil {
			return 0
		}
		return n
	}
	if m[1] != "" {
		return num(m[1]) * num(m[2])
	}
	return num(m[3])
}

// DomicilioUsd es la suma de las líneas de domicilio de la entrega, a céntimos. Es lo que la factura cobra por
// llevar: cero si la línea de domicilio está pero con el precio sin poner.
func (e EntregaDeFactura) DomicilioUsd() float64 {
	suma := 0.0
	for _, f := range e.Facturas {
		for _, l := range f.Lineas {
			if l.EsDomicilio {
				suma += l.Importe
			}
		}
	}
	return math.Round(suma*100) / 100
}

// ConDomicilioCobrado separa las entregas cuyo domicilio trae un importe de las que lo llevan en $0
// (Amado y Jose, 21/10/2026: «las que tienen costo 0 que no me salgan en domicilio»: unos 200 domicilios
// reales, a lo sumo 400, y no los 1.600 que salen si se cuentan las de precio sin poner). Una entrega en $0
// NO se guarda, y como el ciclo retira «lo que ya no viene», las que ya estaban guardadas sin ruta ni
// resultado se van solas; las que ya van en una ruta se quedan y se dicen. Se reactiva quitando este filtro:
// Ventra sigue mandándolas y vuelven en el ciclo siguiente.
func ConDomicilioCobrado(entregas []EntregaDeFactura) (con []EntregaDeFactura, sinPrecio int) {
	con = make([]EntregaDeFactura, 0, len(entregas))
	for _, en := range entregas {
		if en.DomicilioUsd() > 0 {
			con = append(con, en)
			continue
		}
		sinPrecio++
	}
	return con, sinPrecio
}

// direccionConCiudad: la dirección y, si la ciudad no está ya dentro, la ciudad detrás.
func direccionConCiudad(direccion, ciudad string) string {
	direccion, ciudad = strings.TrimSpace(direccion), strings.TrimSpace(ciudad)
	switch {
	case ciudad == "":
		return direccion
	case direccion == "":
		return ciudad
	case strings.Contains(strings.ToLower(direccion), strings.ToLower(ciudad)):
		return direccion
	}
	return direccion + ", " + ciudad
}

func primeroNoVacio(a, b string) string {
	if strings.TrimSpace(a) != "" {
		return a
	}
	return strings.TrimSpace(b)
}

// Resumen del informe de un ciclo de una sucursal, para el registro. Son contadores, no
// avisos sueltos: una línea por entrega son miles de líneas por barrido.
type ResumenDeFacturas struct {
	Facturas, Entregas, Guardadas, Parciales               int
	PuntoPorCodigo, PuntoPorNombre, PuntoAmbiguo, SinPunto int
	SinMercancia, ConProductosSinPeso, LineasSinCantidad   int
	ProductosSinPeso, ProductosFueraDelCatalogo            map[string]int
}

func (r *ResumenDeFacturas) sumar(i InformeDeEntrega) {
	switch i.Punto {
	case PuntoPorCodigo:
		r.PuntoPorCodigo++
	case PuntoPorNombre:
		r.PuntoPorNombre++
	case PuntoAmbiguo:
		r.PuntoAmbiguo++
		r.SinPunto++
	default:
		r.SinPunto++
	}
	if i.SinMercancia {
		r.SinMercancia++
	}
	r.LineasSinCantidad += i.LineasSinCantidad
	if len(i.SinPeso) > 0 || len(i.FueraDelCatalogo) > 0 {
		r.ConProductosSinPeso++
	}
	for _, c := range i.SinPeso {
		if r.ProductosSinPeso == nil {
			r.ProductosSinPeso = map[string]int{}
		}
		r.ProductosSinPeso[c]++
	}
	for _, c := range i.FueraDelCatalogo {
		if r.ProductosFueraDelCatalogo == nil {
			r.ProductosFueraDelCatalogo = map[string]int{}
		}
		r.ProductosFueraDelCatalogo[c]++
	}
}

// codigosOrdenados devuelve las claves de un contador, de la más frecuente a la menos, para que
// el registro nombre PRIMERO el producto que más líneas deja sin peso.
func codigosOrdenados(m map[string]int) string {
	claves := make([]string, 0, len(m))
	for k := range m {
		claves = append(claves, k)
	}
	sort.Slice(claves, func(i, j int) bool {
		if m[claves[i]] != m[claves[j]] {
			return m[claves[i]] > m[claves[j]]
		}
		return claves[i] < claves[j]
	})
	if len(claves) > 15 {
		claves = append(claves[:15], fmt.Sprintf("… (%d más)", len(m)-15))
	}
	return strings.Join(claves, ", ")
}
