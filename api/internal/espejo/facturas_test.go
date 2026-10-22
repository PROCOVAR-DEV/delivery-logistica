package espejo

// El mapeo de la factura de Ventra a la entrega (issue 20, Fase A). Sin red y sin base.
//
// TODOS LOS DATOS SON INVENTADOS. El ejemplo real de Ventra trae nombres, carnés, teléfonos y
// direcciones de personas de verdad; aquí se conserva la FORMA (un número de factura que se
// repite entre puntos de venta, una referencia de cliente que a veces es un nombre, la
// cerveza en blísters) y nada más.

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

// factura arma una factura con una línea de mercancía y su línea de domicilio.
func factura(numero, fecha, punto, pedido string, lineas ...LineaDeFactura) FacturaDeVentra {
	nombrePunto := map[string]string{"2": "ALMACEN UNO", "7": "ALMACEN DOS"}[punto]
	return FacturaDeVentra{
		Numero: numero, Fecha: fecha,
		Punto:                PuntoDeVenta{Codigo: punto, Nombre: nombrePunto},
		Cliente:              ClienteDeFactura{Nombre: "Cliente de Prueba Uno", Direccion: "Calle Falsa 123", Ciudad: "Santiago de Cuba", Telefono: "50000001"},
		Vendedor:             "VENDEDOR INVENTADO",
		Pedido:               pedido,
		ReferenciaDelCliente: "SC06TCP0158",
		Lineas:               lineas,
	}
}

func cerveza(cantidad float64) LineaDeFactura {
	return LineaDeFactura{Codigo: "PARR0002", Nombre: "CERVEZA PARRANDA 500 ML BLISTER 6U", Unidad: "B", Cantidad: cantidad, Importe: cantidad * 3.96}
}

func domicilio(importe float64) LineaDeFactura {
	return LineaDeFactura{Codigo: "50", Nombre: "ENTREGA A DOMICILIO - PROCOVAR", Unidad: "U", Cantidad: importe, Importe: importe, EsDomicilio: true}
}

func claves(es []EntregaDeFactura) []string {
	var s []string
	for _, e := range es {
		s = append(s, e.ExternalID())
	}
	return s
}

// ---------------------------------------------------------------------------
// Agrupar
// ---------------------------------------------------------------------------

func TestUnaFacturaConFolioEsUnaEntrega(t *testing.T) {
	es := AgruparPorFolio("STG", []FacturaDeVentra{factura("47252", "2026-10-17", "2", "PJM26-261017-1925", cerveza(15), domicilio(0.29))})
	if len(es) != 1 || es[0].ExternalID() != "factura:STG:PJM262610171925" {
		t.Fatalf("una factura con folio es una entrega con clave <SUC>:<folio normalizado>; salió %v", claves(es))
	}
}

func TestDosFacturasConElMismoFolioSonUnaEntrega(t *testing.T) {
	// «Un conduce puede tener varias facturas» (Jose): en Santiago el 3 % de los pedidos, en
	// Guantánamo el 11 %. Si se tomaran por entregas separadas, el pedido saldría dos veces.
	es := AgruparPorFolio("GTO", []FacturaDeVentra{
		factura("100", "2026-10-17", "2", "PED-1", cerveza(5), domicilio(0.1)),
		factura("101", "2026-10-17", "2", "PED-1", cerveza(5), domicilio(0.1)),
		factura("102", "2026-10-17", "2", "PED-2", cerveza(1), domicilio(0.1)),
	})
	if len(es) != 2 {
		t.Fatalf("PED-1 reúne dos facturas y PED-2 una: tenían que ser 2 entregas; salieron %v", claves(es))
	}
	if len(es[0].Facturas) != 2 {
		t.Errorf("la primera entrega tenía que reunir sus dos facturas; reunió %d", len(es[0].Facturas))
	}
}

func TestLaMismaFacturaDosVecesSeCuentaUna(t *testing.T) {
	f := factura("100", "2026-10-17", "2", "PED-1", cerveza(5), domicilio(0.1))
	es := AgruparPorFolio("STG", []FacturaDeVentra{f, f})
	if len(es) != 1 || len(es[0].Facturas) != 1 {
		t.Fatalf("una factura repetida en la respuesta se cuenta una vez (si no, el camión carga el doble); salió %+v", es)
	}
}

func TestUnaFacturaSinFolioEsSuPropiaEntrega(t *testing.T) {
	es := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("100", "2026-10-17", "2", "", cerveza(5), domicilio(0.1)),
		factura("101", "2026-10-17", "2", "", cerveza(5), domicilio(0.1)),
	})
	if len(es) != 2 {
		t.Fatalf("dos facturas sin folio son dos entregas, no una; salieron %v", claves(es))
	}
	if got, want := es[0].ExternalID(), "factura:STG:2:100:2026-10-17"; got != want {
		t.Errorf("la clave sin folio es <SUC>:<punto>:<número>:<fecha>; salió %q y tocaba %q", got, want)
	}
}

func TestElMismoNumeroEnDosPuntosDeVentraSonDosFacturas(t *testing.T) {
	// EL NÚMERO DE FACTURA SE REPITE ENTRE PUNTOS DE VENTA. La identidad es sucursal + punto
	// de venta + número + fecha. Con la clave en solo el número, la entrega del cliente del
	// punto 7 pisaría la del cliente del punto 2: dos casas, una sola parada.
	a := factura("100", "2026-10-17", "2", "", cerveza(5), domicilio(0.1))
	b := factura("100", "2026-10-17", "7", "", cerveza(9), domicilio(0.2))
	es := AgruparPorFolio("STG", []FacturaDeVentra{a, b})
	if len(es) != 2 {
		t.Fatalf("el mismo número en dos puntos de venta son DOS facturas y dos entregas; salieron %v", claves(es))
	}
	if es[0].ExternalID() == es[1].ExternalID() {
		t.Fatalf("las dos entregas comparten external_id %q: una pisaría a la otra", es[0].ExternalID())
	}
}

func TestElConduceVaOrdenadoYSinRepetir(t *testing.T) {
	es := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("101", "2026-10-17", "2", "PED-1", cerveza(1), domicilio(0.1)),
		factura("99", "2026-10-17", "2", "PED-1", cerveza(1), domicilio(0.1)),
		factura("1000", "2026-10-18", "2", "PED-1", cerveza(1), domicilio(0.1)),
	})
	if got, want := es[0].Conduce(), "99, 101, 1000"; got != want {
		t.Errorf("el conduce son los números ordenados como número (99 antes que 101); salió %q y tocaba %q", got, want)
	}
}

func TestLaFechaEsLaDeLaFacturaMasAntiguaAMediodiaDeCuba(t *testing.T) {
	es := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("2", "2026-10-18", "2", "PED-1", cerveza(1), domicilio(0.1)),
		factura("1", "2026-10-16", "2", "PED-1", cerveza(1), domicilio(0.1)),
	})
	p, _ := es[0].APedido(ContextoDeMapeo{})
	if p.Fecha != "2026-10-16T12:00:00-05:00" || p.FacturaAt != p.Fecha {
		t.Errorf("order_date y factura_at son la fecha más antigua a las 12:00 de Cuba; salió %q / %q", p.Fecha, p.FacturaAt)
	}
}

// ---------------------------------------------------------------------------
// El mapeo
// ---------------------------------------------------------------------------

func productosDePrueba() map[string]ProductoDeVentra {
	return map[string]ProductoDeVentra{
		// La cerveza: una B (blíster) pesa 3,2 kg y trae 6 unidades.
		"PARR0002": {Sku: "PARR0002", PesoKg: 3.2, UnidadesPorEmpaque: 6},
		"ALIM0013": {Sku: "ALIM0013", PesoKg: 10, UnidadesPorEmpaque: 10},
		"SINPESO1": {Sku: "SINPESO1", PesoKg: 0, UnidadesPorEmpaque: 4},
	}
}

func TestElMapeoCompletoConLaCerveza(t *testing.T) {
	// El caso de Amado: «CERVEZA PARRANDA 500 ML BLISTER 6U, 15 B» = 15 empaques, 90 unidades.
	puntos := NuevosPuntos([]PuntoDeCliente{{Codigo: "SC06TCP0158", Nombre: "Otro Nombre", Lat: 20.05, Lng: -75.8}})
	es := AgruparPorFolio("STG", []FacturaDeVentra{factura("47252", "2026-10-17", "2", "PJM26-261017-1925", cerveza(15), domicilio(0.29))})
	p, inf := es[0].APedido(ContextoDeMapeo{Puntos: puntos, Productos: productosDePrueba()})

	if p.ID != "factura:STG:PJM262610171925" || p.FolioDelPedido != "PJM26-261017-1925" {
		t.Errorf("external_id y folio mal: %q / %q", p.ID, p.FolioDelPedido)
	}
	if p.Folio != "47252" || p.FacturaNumero != "47252" {
		t.Errorf("el conduce (operation_number) y factura_numero son los números de factura; salió %q / %q", p.Folio, p.FacturaNumero)
	}
	if p.FacturaEstado != "igual" || p.ItemsOrigen != "factura" || !p.RequiereDomicilio || p.Archivado {
		t.Errorf("la factura es la verdad: estado igual, renglones de factura, domicilio, sin archivar; salió %+v", p)
	}
	if p.Estado != "" || p.FechaComprometida != "" || p.CostoDomicilio != nil {
		t.Errorf("estado, fecha comprometida y pedido_costo no existen en una factura: %+v", p)
	}
	if p.FacturaDomicilio == nil || *p.FacturaDomicilio != 0.29 {
		t.Errorf("factura_domicilio es la suma de las líneas de domicilio: %v", p.FacturaDomicilio)
	}
	if p.Cliente == nil || p.Cliente.Nombre != "Cliente de Prueba Uno" || p.Cliente.Municipio != "Santiago de Cuba" {
		t.Errorf("cliente mal: %+v", p.Cliente)
	}
	if p.Direccion != "Calle Falsa 123, Santiago de Cuba" || p.Telefono != "50000001" {
		t.Errorf("la dirección lleva la ciudad detrás si no la tenía: %q / %q", p.Direccion, p.Telefono)
	}
	if p.Vendedor == nil || p.Vendedor.Nombre != "VENDEDOR INVENTADO" {
		t.Errorf("vendedor mal: %+v", p.Vendedor)
	}
	if p.Almacen == nil || p.Almacen.Codigo != "2" || p.Almacen.Nombre != "ALMACEN UNO" || p.Almacen.SucursalCodigo != "STG" ||
		p.Almacen.Mezclado == nil || *p.Almacen.Mezclado {
		t.Errorf("el almacén de salida es el punto de venta: %+v", p.Almacen)
	}
	if p.Cliente.Latitud == nil || *p.Cliente.Latitud != 20.05 || inf.Punto != PuntoPorCodigo {
		t.Errorf("las coordenadas salen del cliente por su código: %+v / %q", p.Cliente, inf.Punto)
	}

	if len(p.Items) != 1 {
		t.Fatalf("un renglón (la línea de domicilio NO es mercancía); salieron %d", len(p.Items))
	}
	r := p.Items[0]
	if r.Codigo != "PARR0002" || r.Descripcion != "CERVEZA PARRANDA 500 ML BLISTER 6U" {
		t.Errorf("code y description mal: %+v", r)
	}
	if r.Packs == nil || *r.Packs != 15 {
		t.Errorf("packs son las unidades de venta de la factura (15 B); salió %v", r.Packs)
	}
	if r.Unidades == nil || *r.Unidades != 90 {
		t.Errorf("las unidades son packs × lo que trae cada una (15 × 6 = 90); salió %v", r.Unidades)
	}
	if r.PesoKg == nil || *r.PesoKg != 3.2 {
		t.Errorf("pesoKg es el de products por unidad de venta; la puerta multiplica por packs: %v", r.PesoKg)
	}
	if r.PesoLineaKg != nil {
		t.Errorf("la línea entera NO se calcula aquí (lo hace la cascada de pesos de la puerta): %v", r.PesoLineaKg)
	}

	// Y lo que sale por el cable es EL MISMO cuerpo que entiende `POST /api/quote/batch`.
	crudo, err := json.Marshal(ArmarLote([]PedidoDeFuera{p}))
	if err != nil {
		t.Fatal(err)
	}
	var cuerpo map[string]any
	_ = json.Unmarshal(crudo, &cuerpo)
	o := cuerpo["orders"].([]any)[0].(map[string]any)
	if o["externalId"] != "factura:STG:PJM262610171925" || o["folio"] != "PJM26-261017-1925" || o["operationNumber"] != "47252" ||
		o["facturaEstado"] != "igual" || o["lat"] != 20.05 {
		t.Errorf("el cuerpo del lote no lleva lo que debe: %v", o)
	}
}

func TestSinPuntoLaEntregaSeMapeaIgualYSinCoordenadas(t *testing.T) {
	// «Nada se descarta en silencio»: la entrega de un cliente que no está en el espejo de
	// clientes se guarda sin coordenadas, no se pierde.
	es := AgruparPorFolio("STG", []FacturaDeVentra{factura("1", "2026-10-17", "2", "PED-1", cerveza(1), domicilio(0.1))})
	p, inf := es[0].APedido(ContextoDeMapeo{Puntos: NuevosPuntos(nil), Productos: productosDePrueba()})
	if p.Cliente.Latitud != nil || p.Cliente.Longitud != nil {
		t.Errorf("sin cliente no hay punto, y no se inventa uno: %+v", p.Cliente)
	}
	if inf.Punto != PuntoNoEncontrado {
		t.Errorf("tiene que decir que no se encontró: %q", inf.Punto)
	}
	var r ResumenDeFacturas
	r.sumar(inf)
	if r.SinPunto != 1 {
		t.Errorf("el resumen tiene que contarla como sin punto: %+v", r)
	}
}

func TestLosRenglonesDelMismoProductoSeSumanDentroDeUnaFactura(t *testing.T) {
	// La misma cerveza dos veces en la MISMA factura es un renglón de 12 B (72 uds).
	es := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("1", "2026-10-17", "2", "PED-1", cerveza(5), cerveza(7), domicilio(0.1)),
	})
	p, _ := es[0].APedido(ContextoDeMapeo{Productos: productosDePrueba()})
	if len(p.Items) != 1 || *p.Items[0].Packs != 12 || *p.Items[0].Unidades != 72 {
		t.Fatalf("la misma cerveza dos veces en una factura es UN renglón de 12 B (72 uds); salió %+v", p.Items)
	}
	if p.Items[0].FacturaNumero != "1" {
		t.Errorf("el renglón tiene que decir de qué factura sale: %q", p.Items[0].FacturaNumero)
	}
}

// Issue 22 de Maikel (Santiago, 22/10/2026): dos facturas del MISMO folio son UNA entrega, pero
// cada renglón sabe de cuál sale. El mismo producto en las dos ya no se suma en uno: son dos
// renglones, y entre los dos la entrega pesa y cuenta lo mismo que antes.
func TestDosFacturasDelMismoFolioDanRenglonesConSuFactura(t *testing.T) {
	es := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("47360", "2026-10-17", "2", "PED-1", cerveza(7), domicilio(0.2)),
		factura("47359", "2026-10-17", "2", "PED-1", cerveza(5), domicilio(0.1)),
	})
	if len(es) != 1 {
		t.Fatalf("mismo folio = UNA entrega (la identidad no se toca); salieron %d", len(es))
	}
	p, _ := es[0].APedido(ContextoDeMapeo{Productos: productosDePrueba()})
	if p.FacturaNumero != "47359, 47360" {
		t.Errorf("la entrega sigue diciendo las dos facturas juntas: %q", p.FacturaNumero)
	}
	if len(p.Items) != 2 {
		t.Fatalf("la misma cerveza en dos facturas son DOS renglones, cada uno de la suya; salieron %+v", p.Items)
	}
	vistos := map[string]float64{}
	total, unidades := 0.0, 0.0
	for _, r := range p.Items {
		vistos[r.FacturaNumero] = *r.Packs
		total += *r.Packs
		unidades += *r.Unidades
	}
	if vistos["47359"] != 5 || vistos["47360"] != 7 {
		t.Errorf("cada renglón con SU cantidad y SU factura: %v", vistos)
	}
	if total != 12 || unidades != 72 {
		t.Errorf("la entrega no cambia de cuenta: 12 B y 72 uds; salieron %v y %v", total, unidades)
	}
}

func TestElMismoProductoDeDosAlmacenesNoSeSuma(t *testing.T) {
	// El renglón lleva SU almacén (`almacen_salida_*`): sumar dos puntos de venta dejaría la
	// línea apuntada a uno solo y el que despacha iría a por mercancía que está en el otro.
	es := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("1", "2026-10-17", "2", "PED-1", cerveza(5), domicilio(0.1)),
		factura("2", "2026-10-17", "7", "PED-1", cerveza(7), domicilio(0.2)),
	})
	p, _ := es[0].APedido(ContextoDeMapeo{Productos: productosDePrueba()})
	if len(p.Items) != 2 {
		t.Fatalf("dos puntos de venta, dos renglones; salieron %d", len(p.Items))
	}
	if p.Almacen.Mezclado == nil || !*p.Almacen.Mezclado {
		t.Error("facturas de puntos de venta distintos = almacén mezclado")
	}
	if p.Almacen.Codigo != "2" {
		t.Errorf("de las mezcladas se usa el de la primera; salió %q", p.Almacen.Codigo)
	}
}

func TestUnProductoSinPesoSeDiceYNoSeInventa(t *testing.T) {
	f := factura("1", "2026-10-17", "2", "PED-1",
		LineaDeFactura{Codigo: "SINPESO1", Nombre: "COSA SIN PESO", Cantidad: 3, Importe: 9},
		LineaDeFactura{Codigo: "NOESTA99", Nombre: "COSA FUERA DEL CATALOGO", Cantidad: 2, Importe: 4},
		cerveza(1), domicilio(0.1))
	p, inf := AgruparPorFolio("STG", []FacturaDeVentra{f})[0].APedido(ContextoDeMapeo{Productos: productosDePrueba()})

	if !reflect.DeepEqual(inf.SinPeso, []string{"SINPESO1"}) || !reflect.DeepEqual(inf.FueraDelCatalogo, []string{"NOESTA99"}) {
		t.Errorf("tiene que nombrar el que pesa cero y el que no está: %+v", inf)
	}
	for _, r := range p.Items {
		if (r.Codigo == "SINPESO1" || r.Codigo == "NOESTA99") && r.PesoKg != nil {
			t.Errorf("%s no tiene peso y NO se le pone ninguno: %v", r.Codigo, *r.PesoKg)
		}
	}
	// Y sin catálogo, las unidades son los packs: nunca 0.
	for _, r := range p.Items {
		if r.Codigo == "NOESTA99" && (r.Unidades == nil || *r.Unidades != 2) {
			t.Errorf("sin unidades por empaque las unidades son los packs, nunca cero: %v", r.Unidades)
		}
	}
	var r ResumenDeFacturas
	r.sumar(inf)
	if r.ProductosSinPeso["SINPESO1"] != 1 || r.ProductosFueraDelCatalogo["NOESTA99"] != 1 || r.ConProductosSinPeso != 1 {
		t.Errorf("el resumen tiene que contarlos: %+v", r)
	}
}

func TestUnaEntregaSoloConDomicilioSeGuardaYSeCuenta(t *testing.T) {
	f := factura("1", "2026-10-17", "2", "PED-1", domicilio(0.5))
	p, inf := AgruparPorFolio("STG", []FacturaDeVentra{f})[0].APedido(ContextoDeMapeo{})
	if len(p.Items) != 0 || !inf.SinMercancia {
		t.Errorf("sin mercancía: cero renglones y dicho: %+v / %+v", p.Items, inf)
	}
	if *p.FacturaDomicilio != 0.5 {
		t.Errorf("el domicilio se cobra igual: %v", *p.FacturaDomicilio)
	}
	var r ResumenDeFacturas
	r.sumar(inf)
	if r.SinMercancia != 1 {
		t.Errorf("se cuenta aparte: %+v", r)
	}
}

func TestElNombreDelClienteTieneSuCascada(t *testing.T) {
	sin := func(mut func(*FacturaDeVentra)) PedidoDeFuera {
		f := factura("1", "2026-10-17", "2", "PED-1", cerveza(1), domicilio(0.1))
		mut(&f)
		p, _ := AgruparPorFolio("STG", []FacturaDeVentra{f})[0].APedido(ContextoDeMapeo{})
		return p
	}
	// customer.name; si viene vacío, customerReference; y si tampoco, «Cliente» (lo pone
	// `nombreDelCliente` del lote).
	if got := sin(func(f *FacturaDeVentra) {}).Cliente.Nombre; got != "Cliente de Prueba Uno" {
		t.Errorf("manda customer.name: %q", got)
	}
	if got := sin(func(f *FacturaDeVentra) { f.Cliente.Nombre = "" }).Cliente.Nombre; got != "SC06TCP0158" {
		t.Errorf("sin nombre, la referencia: %q", got)
	}
	vacio := sin(func(f *FacturaDeVentra) { f.Cliente.Nombre = ""; f.ReferenciaDelCliente = "" })
	if got := nombreDelCliente(vacio); got != "Cliente" {
		t.Errorf("sin nada, «Cliente»: %q", got)
	}
}

// ---------------------------------------------------------------------------
// Las coordenadas
// ---------------------------------------------------------------------------

func TestElPuntoSaleDelCodigoNormalizado(t *testing.T) {
	p := NuevosPuntos([]PuntoDeCliente{{Codigo: "SC06TCP0158", Nombre: "A", Lat: 1, Lng: 2}})
	for _, ref := range []string{"SC06TCP0158", "sc06tcp0158", " SC06 TCP0158 "} {
		if lat, lng, como := p.Buscar(ref); como != PuntoPorCodigo || lat != 1 || lng != 2 {
			t.Errorf("%q tenía que dar el punto por código; dio %v %v %q", ref, lat, lng, como)
		}
	}
}

func TestSiLaReferenciaEsUnNombreSeBuscaPorNombreSoloSiEsUnico(t *testing.T) {
	// En el ejemplo real, `customerReference` era un NOMBRE («KIOSCO …») y no un código.
	p := NuevosPuntos([]PuntoDeCliente{
		{Codigo: "C1", Nombre: "Kiosco Prueba Dos", Lat: 1, Lng: 2},
		{Codigo: "C2", Nombre: "Repetido", Lat: 3, Lng: 4},
		{Codigo: "C3", Nombre: "REPETIDO", Lat: 5, Lng: 6},
		{Codigo: "C4", Nombre: "Mellizo", Lat: 7, Lng: 8},
		{Codigo: "C5", Nombre: "Mellizo", Lat: 7, Lng: 8},
	})
	if _, _, como := p.Buscar("KIOSCO PRUEBA DOS"); como != PuntoPorNombre {
		t.Errorf("un nombre único da punto: %q", como)
	}
	if lat, lng, como := p.Buscar("repetido"); como != PuntoAmbiguo || lat != 0 || lng != 0 {
		t.Errorf("dos clientes con el mismo nombre y puntos distintos NO dan punto: %v %v %q", lat, lng, como)
	}
	if _, _, como := p.Buscar("Mellizo"); como != PuntoPorNombre {
		t.Errorf("el mismo cliente dado de alta dos veces (mismo punto) sí vale: %q", como)
	}
	if _, _, como := p.Buscar("Nadie"); como != PuntoNoEncontrado {
		t.Errorf("lo que no está, no está: %q", como)
	}
	if _, _, como := p.Buscar(""); como != PuntoNoEncontrado {
		t.Errorf("sin referencia, sin punto: %q", como)
	}
}

func TestElCodigoMandaSobreElNombre(t *testing.T) {
	p := NuevosPuntos([]PuntoDeCliente{
		{Codigo: "X1", Nombre: "Y2", Lat: 1, Lng: 1},
		{Codigo: "Y2", Nombre: "Otro", Lat: 9, Lng: 9},
	})
	if lat, _, como := p.Buscar("Y2"); como != PuntoPorCodigo || lat != 9 {
		t.Errorf("el código gana al nombre: %v %q", lat, como)
	}
}

// ---------------------------------------------------------------------------
// La dirección
// ---------------------------------------------------------------------------

func TestLaDireccionNoRepiteLaCiudad(t *testing.T) {
	for dir, ciudad := range map[string]string{
		"Calle 1, Santiago de Cuba": "Santiago de Cuba",
		"Calle 1 SANTIAGO DE CUBA":  "Santiago de Cuba",
	} {
		if got := direccionConCiudad(dir, ciudad); got != dir {
			t.Errorf("%q ya lleva la ciudad: %q", dir, got)
		}
	}
	if got := direccionConCiudad("", "Holguin"); got != "Holguin" {
		t.Errorf("sin dirección, la ciudad: %q", got)
	}
	if got := direccionConCiudad("Calle 1", ""); got != "Calle 1" || strings.Contains(got, ",") {
		t.Errorf("sin ciudad, la dirección sola: %q", got)
	}
}

// ---------------------------------------------------------------------------
// Auditoría del 20/10/2026
// ---------------------------------------------------------------------------

func TestElFolioSeAgrupaYSeClavaNormalizado(t *testing.T) {
	// G3: el mismo pedido tecleado de cuatro maneras es UNA entrega con UNA clave, la misma con la
	// que adopta al `PXX-900` de PEDIDO. Si la clave llevara el folio crudo, saldrían cuatro
	// external_id distintos y cuatro filas.
	es := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("1", "2026-10-17", "2", "PXX-900", cerveza(1), domicilio(0.1)),
		factura("2", "2026-10-17", "2", "pxx-900", cerveza(1), domicilio(0.1)),
		factura("3", "2026-10-17", "2", "'PXX-900", cerveza(1), domicilio(0.1)),
		factura("4", "2026-10-17", "2", "PXX - 900", cerveza(1), domicilio(0.1)),
		factura("5", "2026-10-17", "2", " PXX-900 ", cerveza(1), domicilio(0.1)),
	})
	if len(es) != 1 || es[0].ExternalID() != "factura:STG:PXX900" {
		t.Fatalf("cinco maneras de escribir PXX-900 son UNA entrega factura:STG:PXX900; salió %v", claves(es))
	}
	if got := es[0].Conduce(); got != "1, 2, 3, 4, 5" {
		t.Errorf("y reúne las cinco facturas: %q", got)
	}
	if es[0].Folio != "PXX-900" {
		t.Errorf("el folio que se guarda es el de la primera factura (ordenada), tal cual llegó: %q", es[0].Folio)
	}
	// Otro prefijo NO es el mismo pedido.
	otro := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("1", "2026-10-17", "2", "PXX-900", cerveza(1)), factura("2", "2026-10-17", "2", "PXY-900", cerveza(1)),
	})
	if len(otro) != 2 || otro[0].ExternalID() == otro[1].ExternalID() {
		t.Errorf("PXX-900 y PXY-900 son dos pedidos: %v", claves(otro))
	}
	// Un folio que no deja ni una letra ni un dígito no es un folio: cada factura, su entrega.
	nada := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("1", "2026-10-17", "2", "---", cerveza(1)), factura("2", "2026-10-17", "2", "---", cerveza(1)),
	})
	if len(nada) != 2 || nada[0].Folio != "" || nada[1].Folio != "" {
		t.Errorf("«---» no es un folio y no puede juntar dos facturas: %v", claves(nada))
	}
}

func TestElConduceSeOrdenaComoNumeroNoPorFechaNiComoTexto(t *testing.T) {
	// f-conduce-orden. EL DISEÑO: el conduce son los números de factura ordenados como NÚMERO
	// ascendente («9, 10»). Ni por fecha de la factura (la 10 es del 18/10 y la 9 del 19/10: por
	// fecha saldría «10, 9») ni como texto («10» < «9»: también «10, 9»). Y vale con las facturas
	// llegando en cualquier orden, porque Ventra no promete ninguno.
	f10 := factura("10", "2026-10-18", "2", "PXX-1", cerveza(1), domicilio(0.1))
	f9 := factura("9", "2026-10-19", "2", "PXX-1", cerveza(1), domicilio(0.1))
	for nombre, entrada := range map[string][]FacturaDeVentra{"10 antes que 9": {f10, f9}, "9 antes que 10": {f9, f10}} {
		es := AgruparPorFolio("STG", entrada)
		if got := es[0].Conduce(); got != "9, 10" {
			t.Errorf("%s: el conduce tiene que ser «9, 10» y salió %q", nombre, got)
		}
	}
}

func TestUnRenglonConCantidadCeroONegativaNoSeCargaYSeCuenta(t *testing.T) {
	// f-cantidad-cero: un renglón sin cantidad no es mercancía a cargar (pesaría 0 y ensuciaría el
	// conteo de «sin peso»). Se descarta, se cuenta aparte y se DICE; la línea buena sí entra.
	cero, negativa := cerveza(0), cerveza(-3)
	cero.Codigo, negativa.Codigo = "PARR0010", "PARR0011"
	f := factura("1", "2026-10-17", "2", "PXX-1", cero, negativa, cerveza(2), domicilio(0.5))
	p, inf := AgruparPorFolio("STG", []FacturaDeVentra{f})[0].APedido(ContextoDeMapeo{})
	if len(p.Items) != 1 || *p.Items[0].Packs != 2 {
		t.Fatalf("sólo la línea de cantidad 2 se carga: %+v", p.Items)
	}
	if inf.LineasSinCantidad != 2 {
		t.Errorf("las dos líneas sin cantidad se cuentan aparte: %d", inf.LineasSinCantidad)
	}
	var r ResumenDeFacturas
	r.sumar(inf)
	if r.LineasSinCantidad != 2 {
		t.Errorf("y llegan al resumen del ciclo: %+v", r)
	}
	// Una factura que sólo trae líneas sin cantidad queda SIN mercancía, no con renglones vacíos.
	solo := factura("2", "2026-10-17", "2", "PXX-2", cero, domicilio(0.5))
	if p, inf := AgruparPorFolio("STG", []FacturaDeVentra{solo})[0].APedido(ContextoDeMapeo{}); len(p.Items) != 0 || !inf.SinMercancia {
		t.Errorf("sin renglones de verdad es una entrega sin mercancía: %+v %+v", p.Items, inf)
	}
}

// LAS UNIDADES SE LEEN DEL NOMBRE (Jose, 21/10/2026): el catálogo local no trae unidades por empaque, y con
// eso «20 pacas de ARROZ 10U» salían como 20 unidades en vez de 200.
func TestLasUnidadesPorEmpaqueSeLeenDelNombre(t *testing.T) {
	casos := []struct {
		nombre string
		sale   float64
	}{
		{"ARROZ RIVIERA 1 KG PACA 10U", 10},
		{"AZUCAR PATEKO 1 KG PACA 10U", 10},
		{"REFRESCO SANTA COLA 330 ML CAJA 24U", 24},
		{"CERVEZA PARRANDA 500 ML BLISTER 6U", 6},
		{"ACEITE SOYA SAUDE 900 ML CAJA 20U", 20},
		{"PAPEL HIGIENICO MANATI 15 M PACA 12P DE 4U", 48}, // 12 paquetes de 4
		{"PANEL SOLAR BIFACIAL JINKO 625 W", 0},            // sin patrón: no se inventa
		{"PAQUETE DE HOJAS 4 P A4", 0},
		{"SERVILLETA PROSITO PACA 24P", 0}, // «P» sola no son unidades
		{"", 0},
	}
	for _, c := range casos {
		if got := unidadesPorEmpaqueDelNombre(c.nombre); got != c.sale {
			t.Errorf("unidadesPorEmpaqueDelNombre(%q) = %v; quería %v", c.nombre, got, c.sale)
		}
	}
}

func TestVeinteDeArrozDe10UnSonDoscientasUnidades(t *testing.T) {
	arroz := LineaDeFactura{Codigo: "ALIM0019", Nombre: "ARROZ RIVIERA 1 KG PACA 10U", Unidad: "P", Cantidad: 20, Importe: 20 * 9}
	panel := LineaDeFactura{Codigo: "PANE0001", Nombre: "PANEL SOLAR BIFACIAL JINKO 625 W", Unidad: "U", Cantidad: 40, Importe: 40 * 100}
	en := EntregaDeFactura{Sucursal: "STG", Facturas: []FacturaDeVentra{factura("1", "2026-10-20", "2", "PED-9", arroz, panel, domicilio(1))}}
	p, _ := en.APedido(ContextoDeMapeo{Puntos: NuevosPuntos(nil), Productos: map[string]ProductoDeVentra{}})
	got := map[string]float64{}
	for _, it := range p.Items {
		got[it.Codigo] = *it.Unidades
	}
	if got["ALIM0019"] != 200 {
		t.Errorf("20 pacas de 10 unidades son 200 unidades; salió %v", got["ALIM0019"])
	}
	if got["PANE0001"] != 40 {
		t.Errorf("un producto sin unidades por empaque se queda 1 a 1 (40): %v", got["PANE0001"])
	}
}
