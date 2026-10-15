package api

// EL NÚMERO DE FACTURA DE LOS REPORTES, Y QUE SEA EL MISMO QUE EL DEL APARATO.
//
// Issue 9 de Amado: «Adicionar la factura como elemento de referencia importante:
// adicionar a los reportes la columna de facturas». Decisión de Jose, 14/10/2026: «factura» es
// `orders.factura_numero` —el de Ventra— en TODA la aplicación; el folio (`operation_number`, el
// «conduce») no lo es, y sin `factura_numero` no hay número: no se cae al folio.
//
// La regla está escrita DOS veces: aquí (`numeroDeFactura`, que contesta `GET /api/reports`) y en
// el aparato (`NumeroDeFactura.de`, que arma el informe de la APK, del escritorio y de la web con
// su base local, y de la que cuelgan el tablero, Pedidos y el pre-despacho). Si se separan, el
// mismo pedido lleva un número en la pantalla y otro en el Excel del servidor, y no falla nada:
// se lee igual de bien. Un comentario no falla (`CLAUDE.md` §3-bis).
//
// `docs/numero-de-factura.casos.json` lo leen esta prueba y
// `app/test/nucleo/el_numero_de_factura_test.dart` (más las de las pantallas). Es EL MISMO
// fichero, no una copia: una copia se desincroniza y entonces las dos pruebas salen verdes
// diciendo cosas distintas.

import (
	"encoding/json"
	"net/http"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// La ruta es la que espera el `COPY` de `deploy/Dockerfile.api` y `deploy/Dockerfile.espejo`:
// desde `/src/internal/api`, `../../../docs/…` cae en `/docs/…`. Si falta, esto hace
// `Fatalf` y la imagen no se construye, que es lo que se quiere.
const rutaDeLosCasosDeFactura = "../../../docs/numero-de-factura.casos.json"

type casoDeNumero struct {
	Nombre        string   `json:"nombre"`
	FacturaNumero *string  `json:"facturaNumero"`
	Esperado      *string  `json:"esperado"`
	Separadas     []string `json:"separadas"`
}

type pedidoDeCaso struct {
	Cliente         string  `json:"cliente"`
	OperationNumber *string `json:"operationNumber"`
	FacturaNumero   *string `json:"facturaNumero"`
	Ingreso         float64 `json:"ingreso"`
}

type casoDeAgrupar struct {
	Nombre     string         `json:"nombre"`
	Pedidos    []pedidoDeCaso `json:"pedidos"`
	Facturas   []string       `json:"facturas"`
	SinFactura int            `json:"sinFactura"`
}

type informeDeCaso struct {
	Camion   string         `json:"camion"`
	Pedidos  []pedidoDeCaso `json:"pedidos"`
	Esperado struct {
		PorPedido map[string]*string `json:"porPedido"`
		Camion    struct {
			Ordenes    int      `json:"ordenes"`
			Ingresos   float64  `json:"ingresos"`
			Facturas   []string `json:"facturas"`
			SinFactura int      `json:"sinFactura"`
		} `json:"camion"`
	} `json:"esperado"`
}

type ficheroDeCasosDeFactura struct {
	Resolver []casoDeNumero  `json:"resolver"`
	Agrupar  []casoDeAgrupar `json:"agrupar"`
	Informe  informeDeCaso   `json:"informe"`
}

func leerCasosDeFactura(t *testing.T) ficheroDeCasosDeFactura {
	t.Helper()
	b, err := os.ReadFile(rutaDeLosCasosDeFactura)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v\n"+
			"Es el fichero que ata esta regla con la del aparato. Sin él, esta prueba no "+
			"comprueba nada y el contrato se queda sin vigilante.", rutaDeLosCasosDeFactura, err)
	}
	var f ficheroDeCasosDeFactura
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDeFactura, err)
	}
	if len(f.Resolver) == 0 || len(f.Agrupar) == 0 || len(f.Informe.Pedidos) == 0 {
		t.Fatalf("%s no tiene casos de alguna de sus tres partes: una prueba sobre una lista "+
			"vacía sale verde sin haber comprobado nada", rutaDeLosCasosDeFactura)
	}
	return f
}

func numeroOHueco(p *string) string {
	if p == nil {
		return "null"
	}
	return `"` + *p + `"`
}

func TestElNumeroDeFacturaEsElDelAparato(t *testing.T) {
	f := leerCasosDeFactura(t)

	// Los casos que motivaron todo esto tienen que seguir estando: sin esta comprobación, quitarlos
	// del JSON deja la suite en verde y la regla sin vigilante.
	hay := map[string]bool{}
	for _, c := range f.Resolver {
		hay[c.Nombre] = true
		t.Run(c.Nombre, func(t *testing.T) {
			salio := numeroDeFactura(c.FacturaNumero)
			if numeroOHueco(salio) != numeroOHueco(c.Esperado) {
				t.Errorf("con facturaNumero=%s el número tiene que ser %s y salió %s.\n"+
					"Es la misma regla que `NumeroDeFactura.de` del aparato "+
					"(app/lib/nucleo/numero_de_factura.dart): si cambia, cambian los DOS lados y %s.",
					numeroOHueco(c.FacturaNumero), numeroOHueco(c.Esperado), numeroOHueco(salio),
					rutaDeLosCasosDeFactura)
			}
			separadas := numerosDeFactura(c.FacturaNumero)
			if len(separadas) != len(c.Separadas) || (len(separadas) > 0 && !reflect.DeepEqual(separadas, c.Separadas)) {
				t.Errorf("con facturaNumero=%s las facturas sueltas tienen que ser %q y salieron %q "+
					"(`NumeroDeFactura.separar` del aparato)",
					numeroOHueco(c.FacturaNumero), c.Separadas, separadas)
			}
		})
	}
	for _, requerido := range []string{
		"un número de Ventra se dice tal cual",
		"varias facturas del pedido se dicen tal cual, y separadas son dos",
		"la comilla de Excel se quita",
		"nulo no es un número",
	} {
		if !hay[requerido] {
			t.Fatalf("al fichero de casos le falta «%s»", requerido)
		}
	}
}

// LA PAREJA QUE LE IMPORTA A AMADO, escrita a mano y sin el fichero: con factura_numero sale ESE
// número aunque el folio sea otro; sin él no sale ninguno aunque haya folio. Si alguien vuelve a
// hacer que el folio respalde a la factura, el fichero de casos ya lo caza; esto lo dice con
// palabras.
func TestElFolioNoHaceDeFactura(t *testing.T) {
	camion := uuid.New()
	conFactura := filaDeInforme("Con factura", 10, 1, &camion, "Camión 1")
	folio, factura := "PTB25-261005-1479", "1024237"
	conFactura.OperationNumber, conFactura.FacturaNumero = &folio, &factura
	sinFactura := filaDeInforme("Sin factura", 10, 1, &camion, "Camión 1")
	otroFolio := "PTB25-261005-1480"
	sinFactura.OperationNumber = &otroFolio

	h := montarDePanel(t, &dobleDePanel{informe: []sqlc.ListarPedidosParaInformeRow{conFactura, sinFactura}})
	w := pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	inf := leerJSONDePanel[InformeSalida](t, w)
	porCliente := map[string]*string{}
	for _, o := range inf.Orders {
		porCliente[o.CustomerName] = o.InvoiceNumber
	}
	if got := numeroOHueco(porCliente["Con factura"]); got != `"1024237"` {
		t.Errorf("con factura_numero el número tiene que ser el de Ventra, \"1024237\"; salió %s", got)
	}
	if got := numeroOHueco(porCliente["Sin factura"]); got != "null" {
		t.Errorf("sin factura_numero tiene que salir null, aunque el pedido tenga folio; salió %s "+
			"(caer al folio es lo que hacía decir números distintos a cada pantalla)", got)
	}
	if v := inf.ByVehicle[0]; !reflect.DeepEqual(v.InvoiceNumbers, []string{"1024237"}) || v.WithoutInvoice != 1 {
		t.Errorf("el camión tiene que listar [1024237] y contar 1 sin número; salió %q y %d",
			v.InvoiceNumbers, v.WithoutInvoice)
	}
}

func TestLaAgrupacionDeFacturasEsLaDelAparato(t *testing.T) {
	for _, c := range leerCasosDeFactura(t).Agrupar {
		t.Run(c.Nombre, func(t *testing.T) {
			// Como el servidor: cada pedido pasa primero por `numeroDeFactura`, y la agrupación
			// parte ese texto otra vez (con varias facturas, `1024237, 1024240`).
			var numeros []*string
			for _, p := range c.Pedidos {
				numeros = append(numeros, numeroDeFactura(p.FacturaNumero))
			}
			facturas, sin := agruparFacturas(numeros)
			if !reflect.DeepEqual(facturas, c.Facturas) && !(len(facturas) == 0 && len(c.Facturas) == 0) {
				t.Errorf("salieron las facturas %q y se esperaban %q", facturas, c.Facturas)
			}
			if sin != c.SinFactura {
				t.Errorf("salieron %d pedidos sin número y se esperaban %d", sin, c.SinFactura)
			}
			if facturas == nil {
				t.Error("la lista salió nil: en el JSON sería `null` en vez de `[]`")
			}
		})
	}
}

// filasDelInformeDeCaso arma lo que devolvería la consulta: del más nuevo al más viejo.
func filasDelInformeDeCaso(inf informeDeCaso) []sqlc.ListarPedidosParaInformeRow {
	camion := uuid.New()
	ahora := time.Date(2026, 9, 13, 12, 0, 0, 0, time.UTC)
	var filas []sqlc.ListarPedidosParaInformeRow
	for i, p := range inf.Pedidos {
		f := filaDeInforme(p.Cliente, p.Ingreso, 10, &camion, inf.Camion)
		f.OperationNumber, f.FacturaNumero = p.OperationNumber, p.FacturaNumero
		f.CreatedAt = pgtype.Timestamptz{Time: ahora.Add(-time.Duration(i) * time.Hour), Valid: true}
		filas = append(filas, f)
	}
	return filas
}

// compararInformeConElDeCaso es lo que tienen que dar el doble y el Postgres de verdad.
func compararInformeConElDeCaso(t *testing.T, inf InformeSalida, caso informeDeCaso) {
	t.Helper()
	if len(inf.Orders) != len(caso.Pedidos) {
		t.Fatalf("el detalle trae %d pedidos y el caso tiene %d", len(inf.Orders), len(caso.Pedidos))
	}
	for _, o := range inf.Orders {
		esperado, hay := caso.Esperado.PorPedido[o.CustomerName]
		if !hay {
			t.Fatalf("el caso no dice qué número lleva %q", o.CustomerName)
		}
		if numeroOHueco(o.InvoiceNumber) != numeroOHueco(esperado) {
			t.Errorf("%s lleva el número %s y tiene que llevar %s", o.CustomerName,
				numeroOHueco(o.InvoiceNumber), numeroOHueco(esperado))
		}
	}
	if len(inf.ByVehicle) != 1 {
		t.Fatalf("byVehicle trae %d filas, se esperaba 1", len(inf.ByVehicle))
	}
	v, e := inf.ByVehicle[0], caso.Esperado.Camion
	if !reflect.DeepEqual(v.InvoiceNumbers, e.Facturas) {
		t.Errorf("las facturas del camión son %q y tienen que ser %q", v.InvoiceNumbers, e.Facturas)
	}
	if v.WithoutInvoice != e.SinFactura {
		t.Errorf("el camión tiene %d pedidos sin número y tienen que ser %d", v.WithoutInvoice, e.SinFactura)
	}
	// LA PAREJA, y es lo que más le importa a quien cuadra caja: la columna de facturas NO
	// mueve ni las órdenes ni los ingresos.
	if v.Count != e.Ordenes || v.Revenue != e.Ingresos {
		t.Errorf("las cuentas del camión son %d órdenes y %v de ingresos; tienen que seguir siendo %d y %v",
			v.Count, v.Revenue, e.Ordenes, e.Ingresos)
	}
	if inf.Summary.TotalOrders != e.Ordenes || inf.Summary.TotalRevenue != e.Ingresos {
		t.Errorf("el resumen es %+v; tiene que seguir en %d órdenes y %v", inf.Summary, e.Ordenes, e.Ingresos)
	}
}

// GET /api/reports, con el doble, sobre el informe del fichero compartido.
func TestElInformeDelServidorLlevaLasFacturasDelFicheroCompartido(t *testing.T) {
	caso := leerCasosDeFactura(t).Informe
	h := montarDePanel(t, &dobleDePanel{informe: filasDelInformeDeCaso(caso)})

	w := pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	compararInformeConElDeCaso(t, leerJSONDePanel[InformeSalida](t, w), caso)
}

// Un camión sin ningún número tiene que salir con `[]`, no con `null`: el consumidor itera la
// lista sin comprobar nada.
func TestUnCamionSinFacturasSaleConListaVaciaYNoConNull(t *testing.T) {
	camion := uuid.New()
	f := filaDeInforme("Ana", 10, 1, &camion, "Camión 1") // sin operación ni factura
	h := montarDePanel(t, &dobleDePanel{informe: []sqlc.ListarPedidosParaInformeRow{f}})

	w := pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	var crudo struct {
		ByVehicle []map[string]any `json:"byVehicle"`
		Orders    []map[string]any `json:"orders"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &crudo); err != nil {
		t.Fatal(err)
	}
	lista, hay := crudo.ByVehicle[0]["invoiceNumbers"].([]any)
	if !hay || len(lista) != 0 {
		t.Errorf("invoiceNumbers tiene que ser [] y es %#v", crudo.ByVehicle[0]["invoiceNumbers"])
	}
	if crudo.ByVehicle[0]["withoutInvoice"] != float64(1) {
		t.Errorf("withoutInvoice tiene que ser 1 y es %#v", crudo.ByVehicle[0]["withoutInvoice"])
	}
	if v, hay := crudo.Orders[0]["invoiceNumber"]; !hay || v != nil {
		t.Errorf("invoiceNumber de un pedido sin número tiene que estar y ser null; es %#v (¿está?: %v)", v, hay)
	}
}
