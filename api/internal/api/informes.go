// EL INFORME PARA CUADRAR LO REPARTIDO  (GET /api/reports).
//
// Lo usa administración: un rango de fechas, opcionalmente un camión, y salen tres cosas a
// la vez —el detalle pedido a pedido, los cuatro totales y el reparto por vehículo—, que
// es lo que se exporta a Excel en tres hojas.
//
// LAS TRES SALEN DE UNA SOLA LECTURA, y tienen que salir de la misma. Con tres consultas
// —una para el detalle, otra para los totales y otra para el por-vehículo— son tres fotos
// tomadas en tres instantes distintos: el espejo de PEDIDO mete lotes de doscientos
// mientras tanto, y el Excel se va con un total que no es la suma de su propio detalle.
// Nadie encuentra nunca esa diferencia mirando el fichero.
package api

import (
	"net/http"
	"regexp"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// El aviso de tamaño. El contrato de delivery dice «sin paginación ni tope» y así se
// conserva —los cuatro totales se calculan sobre TODO lo filtrado, y traer una página
// descuadraría las tarjetas del resumen—, pero un informe sin rango sobre doce mil pedidos
// es una respuesta enorme por la conexión de allá. No se corta: se deja constancia, que es
// lo que permite descubrirlo antes de que alguien se queje.
const informeGrande = 5000

type InformeSalida struct {
	Orders    []InformePedido   `json:"orders"`
	Summary   InformeResumen    `json:"summary"`
	ByVehicle []InformeVehiculo `json:"byVehicle"`
}

type InformePedido struct {
	ID           uuid.UUID `json:"id"`
	CustomerName string    `json:"customerName"`
	Address      string    `json:"address"`
	EndAddress   *string   `json:"endAddress"`
	Weight       float64   `json:"weight"`
	// Price es el INGRESO ya resuelto: `price` si el pedido lo tiene y si no `pedidoCosto`.
	// En delivery se devolvía `price` crudo y cada consumidor aplicaba la regla por su
	// cuenta; el resultado era una tabla que enseñaba una columna vacía encima de un total
	// que no salía de ella. La regla vive en el COALESCE de la consulta, en un solo sitio.
	Price        float64    `json:"price"`
	SegmentKm    *float64   `json:"segmentKm"`
	CreatedAt    *time.Time `json:"createdAt"`
	RouteName    *string    `json:"routeName"`
	VehicleName  *string    `json:"vehicleName"`
	VehiclePlate *string    `json:"vehiclePlate"`
	// InvoiceNumber es el número de factura del pedido (issue 9 de Amado: la columna de
	// facturas de los reportes): su `factura_numero`, el de Ventra, y nada más —NO el folio
	// (`operation_number`, el «conduce»)—. Con varias facturas, `1024237, 1024240`. `null` =
	// el pedido no tiene ninguna. Ver `numeroDeFactura`.
	InvoiceNumber *string `json:"invoiceNumber"`
}

type InformeResumen struct {
	TotalOrders  int     `json:"totalOrders"`
	TotalRevenue float64 `json:"totalRevenue"`
	TotalWeight  float64 `json:"totalWeight"`
	AvgPrice     float64 `json:"avgPrice"`
}

type InformeVehiculo struct {
	Name    string  `json:"name"`
	Plate   *string `json:"plate"`
	Count   int     `json:"count"`
	Revenue float64 `json:"revenue"`
	Weight  float64 `json:"weight"`
	// InvoiceNumbers son las FACTURAS de sus pedidos, una a una (un pedido con dos aporta las
	// dos), SIN REPETIR y en el orden en que salen en `orders`; WithoutInvoice, cuántos de sus
	// `count` pedidos no tienen ninguna. Es sólo la lista de referencias: no cambia `count` ni
	// ningún total. Ver `agruparFacturas`.
	InvoiceNumbers []string `json:"invoiceNumbers"`
	WithoutInvoice int      `json:"withoutInvoice"`
}

// rutasInformes monta el informe. `admin` no se usa: en delivery tampoco lo exigía, y
// quien ve el informe ya está acotado a su sucursal — un supervisor tiene que poder cuadrar
// lo suyo sin pedirle permiso a nadie.
func (s *Servidor) rutasInformes(rt *httpx.Router, sesion, admin []httpx.Medio) {
	rt.ManejarFunc(http.MethodGet, "/api/reports", s.informe, sesion...)
}

// GET /api/reports?from=&to=&vehicleId=
func (s *Servidor) informe(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()

	desde, ok := fechaDeQuery(w, r, "from", q.Get("from"), false)
	if !ok {
		return
	}
	hasta, ok := fechaDeQuery(w, r, "to", q.Get("to"), true)
	if !ok {
		return
	}
	vehiculo, ok := vehiculoDeQuery(w, r, q.Get("vehicleId"))
	if !ok {
		return
	}

	filas, err := a.ListarPedidosParaInforme(r.Context(), sqlc.ListarPedidosParaInformeParams{
		Desde: desde, Hasta: hasta, VehiculoID: vehiculo,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if len(filas) > informeGrande {
		httpx.Registro(r).Warn("informe muy grande: va entero y sin tope, como manda el contrato",
			"pedidos", len(filas), "desde", q.Get("from"), "hasta", q.Get("to"))
	}

	salida := InformeSalida{
		Orders:    make([]InformePedido, 0, len(filas)),
		ByVehicle: []InformeVehiculo{},
	}
	// El por-vehículo se arma RECORRIENDO las mismas filas, no con otra consulta: así los
	// tres bloques de la respuesta suman siempre lo mismo por construcción.
	//
	// Se agrupa por el ID del camión y no por su nombre: «Camión 1» lo hay en varias
	// sucursales y la matrícula puede estar vacía, así que agrupar por texto juntaría dos
	// camiones distintos en una fila con el doble de ingresos, y desde fuera eso no se ve.
	posicion := map[uuid.UUID]int{}
	// Los números de cada camión, tal cual salen, para juntarlos al final con la misma
	// `agruparFacturas` que prueba el fichero de casos compartido con el aparato.
	numeros := map[uuid.UUID][]*string{}
	for _, f := range filas {
		factura := numeroDeFactura(f.FacturaNumero)
		salida.Orders = append(salida.Orders, InformePedido{
			ID: f.ID, CustomerName: f.CustomerName, Address: f.Address,
			EndAddress: f.EndAddress, Weight: f.Weight, Price: f.Ingreso,
			SegmentKm: f.SegmentKm, CreatedAt: hora(f.CreatedAt),
			RouteName: f.RutaNombre, VehicleName: f.VehiculoNombre,
			VehiclePlate: f.VehiculoMatricula, InvoiceNumber: factura,
		})

		salida.Summary.TotalRevenue += f.Ingreso
		salida.Summary.TotalWeight += f.Weight

		// Sin camión no hay fila en `byVehicle`, y el pedido SÍ sigue contando en el
		// resumen y en el detalle: es trabajo cobrado igual. Es la regla del contrato y
		// explica que las dos pestañas de la pantalla no sumen lo mismo.
		if !f.VehiculoID.Valid {
			continue
		}
		id := uuid.UUID(f.VehiculoID.Bytes)
		i, visto := posicion[id]
		if !visto {
			nombre := ""
			if f.VehiculoNombre != nil {
				nombre = *f.VehiculoNombre
			}
			salida.ByVehicle = append(salida.ByVehicle, InformeVehiculo{
				Name: nombre, Plate: f.VehiculoMatricula,
			})
			i = len(salida.ByVehicle) - 1
			posicion[id] = i
		}
		salida.ByVehicle[i].Count++
		salida.ByVehicle[i].Revenue += f.Ingreso
		salida.ByVehicle[i].Weight += f.Weight
		numeros[id] = append(numeros[id], factura)
	}
	for id, i := range posicion {
		salida.ByVehicle[i].InvoiceNumbers, salida.ByVehicle[i].WithoutInvoice = agruparFacturas(numeros[id])
	}

	salida.Summary.TotalOrders = len(filas)
	// La media se protege del cero a mano y no con una división que dé NaN: `NaN` no es
	// JSON válido, así que el codificador falla y la respuesta sale cortada a la mitad —un
	// informe vacío tumbaría la pantalla entera en vez de enseñar cuatro ceros.
	if salida.Summary.TotalOrders > 0 {
		salida.Summary.AvgPrice = salida.Summary.TotalRevenue / float64(salida.Summary.TotalOrders)
	}

	httpx.JSON(w, r, http.StatusOK, salida)
}

// LA FACTURA DE UN PEDIDO ES `factura_numero` —el de Ventra— Y NADA MÁS (decisión de Jose,
// 14/10/2026, tras el issue 9 de Amado).
//
// Hay dos números en el pedido: `operation_number` (el folio, `PTB25-261005-1479`, el «conduce»)
// y `factura_numero` (`1024237`, el `operNumber` de Ventra; con más de una factura PEDIDO las junta
// con coma: `1024237, 1024240`). Antes los reportes y el pre-despacho enseñaban el folio y caían a
// la factura si faltaba, mientras el tablero y Pedidos enseñaban la factura: la misma aplicación
// decía dos números para lo mismo. Ahora «factura» es `factura_numero` en toda la app, y **sin él NO
// hay número: no se cae al folio** (caer al folio es lo que mezclaba números de dos clases en la
// misma columna).
//
// ESTÁ ESCRITA DOS VECES: aquí y en el aparato (`NumeroDeFactura`,
// `app/lib/nucleo/numero_de_factura.dart`), porque el informe de la APK, del escritorio y de la web
// lo arma la aplicación con su base local. Las ata `docs/numero-de-factura.casos.json` (prueba
// `numero_de_factura_casos_compartidos_test.go`): un comentario no falla (CLAUDE.md §3-bis).

// numerosDeFactura parte el `factura_numero` crudo en sus facturas, una a una: sin blancos en los
// extremos —los de Unicode también, y el BOM, que es lo que `trim()` de Dart quita—, sin la comilla
// de Excel que pudo bajar delante (`'1024237`) y sin trozos vacíos. Vacío si no hay ninguna.
func numerosDeFactura(crudo *string) []string {
	if crudo == nil {
		return nil
	}
	sinComilla := espejo.SinLaComillaDeExcel(blancosFuera(*crudo))
	var facturas []string
	for _, trozo := range strings.Split(sinComilla, ",") {
		if n := blancosFuera(trozo); n != "" {
			facturas = append(facturas, n)
		}
	}
	return facturas
}

// numeroDeFactura es el número que lleva la columna «Factura» de los reportes: las facturas de
// `numerosDeFactura` juntas con coma y espacio, o `nil` si el pedido no tiene ninguna. Nunca un
// texto inventado.
func numeroDeFactura(crudo *string) *string {
	facturas := numerosDeFactura(crudo)
	if len(facturas) == 0 {
		return nil
	}
	n := strings.Join(facturas, ", ")
	return &n
}

func blancosFuera(texto string) string {
	return strings.TrimFunc(texto, func(r rune) bool { return unicode.IsSpace(r) || r == '\ufeff' })
}

// agruparFacturas junta las facturas de los pedidos de un camión: cada una UNA vez, en el orden en
// que aparecen —un pedido con dos aporta las dos, y la ida y la vuelta de un mismo pedido llevan la
// misma—, y cuántos pedidos se quedaron sin ninguna. Recibe el crudo o el ya resuelto por
// `numeroDeFactura`: partir dos veces da lo mismo. Nunca devuelve `nil` en la lista (sale `[]` en el
// JSON, no `null`). Mismo contrato que `NumeroDeFactura.agrupar` del aparato.
func agruparFacturas(numeros []*string) (facturas []string, sinFactura int) {
	facturas = []string{}
	vistos := map[string]bool{}
	for _, crudo := range numeros {
		suyas := numerosDeFactura(crudo)
		if len(suyas) == 0 {
			sinFactura++
		}
		for _, n := range suyas {
			if !vistos[n] {
				vistos[n] = true
				facturas = append(facturas, n)
			}
		}
	}
	return facturas, sinFactura
}

// soloFecha reconoce el `AAAA-MM-DD` que manda el selector de la pantalla.
var soloFecha = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

// fechaDeQuery interpreta `from` y `to`.
//
// EN UTC, como el contrato: `to` incluye el día entero (`T23:59:59.999Z`). No se usa la
// zona del servidor a propósito — administración cuadra el mismo mes desde La Habana y
// desde el VPS, y con la zona local del proceso los dos informes saldrían distintos.
//
// UNA FECHA QUE NO SE ENTIENDE ES UN 400, no un filtro que se ignora. Ignorarla devuelve
// el histórico entero con un 200: el Excel sale bien formado, con los totales de tres años
// donde tenían que ir los de un mes, y nadie lo nota hasta que no cuadra la caja.
func fechaDeQuery(w http.ResponseWriter, r *http.Request, nombre, valor string, finDelDia bool) (pgtype.Timestamptz, bool) {
	valor = strings.TrimSpace(valor)
	if valor == "" {
		return pgtype.Timestamptz{}, true // sin filtro
	}
	if soloFecha.MatchString(valor) {
		t, err := time.ParseInLocation("2006-01-02", valor, time.UTC)
		if err == nil {
			if finDelDia {
				t = t.Add(24*time.Hour - time.Millisecond)
			}
			return pgtype.Timestamptz{Time: t, Valid: true}, true
		}
	}
	// También se acepta una marca completa: la exportación programada manda RFC3339.
	if t, err := time.Parse(time.RFC3339, valor); err == nil {
		return pgtype.Timestamptz{Time: t, Valid: true}, true
	}
	httpx.Error(w, r, http.StatusBadRequest,
		"La fecha '"+nombre+"' no se entiende: se espera AAAA-MM-DD")
	return pgtype.Timestamptz{}, false
}

// vehiculoDeQuery lee `vehicleId`. Un id mal escrito es un 400 por lo mismo que las fechas:
// como filtro que no casa con nada devolvería un informe VACÍO con un 200, y «este mes no
// se repartió nada» es una respuesta que alguien se cree.
func vehiculoDeQuery(w http.ResponseWriter, r *http.Request, valor string) (pgtype.UUID, bool) {
	valor = strings.TrimSpace(valor)
	if valor == "" {
		return pgtype.UUID{}, true // todos los vehículos
	}
	id, err := uuid.Parse(valor)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest,
			"El vehículo indicado no es un identificador válido")
		return pgtype.UUID{}, false
	}
	return pgDe(id), true
}
