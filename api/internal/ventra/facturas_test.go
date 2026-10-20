package ventra

// El lector de las facturas con domicilio (issue 20, Fase A), contra un Ventra de mentira.
//
// EL EJEMPLO ESTÁ ANONIMIZADO. El de verdad (16-17/10/2026, Santiago) trae nombres, carnés,
// teléfonos y direcciones de personas reales; aquí todo está inventado y se conserva la FORMA:
// el número de factura como número, el punto de venta con código de texto, un
// `customerReference` que unas veces es un código y otra un NOMBRE, un pedido con DOS facturas,
// una venta sin la nota del pedido y la línea de domicilio con el precio en 1.

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/config"
)

const facturasDeVentra = `{
 "database": "santiago", "branchName": "SANTIAGO", "from": "2026-10-16", "to": "2026-10-17",
 "deliverySkus": ["50","51"], "currency": "USD",
 "summary": {"invoices": 3, "items": 7, "productUnits": 45, "totalUsd": 200.5, "deliveryAmountUsd": 0.9},
 "invoices": [
  {"header": {"invoiceNumber": 47252, "date": "2026-10-17", "operType": 2, "operTypeName": "Venta",
    "database": "santiago", "branchName": "SANTIAGO",
    "pointOfSale": {"id": 2, "code": "2", "name": "ALMACEN UNO"},
    "customer": {"id": 11, "code": "5801", "name": "Cliente Inventado Uno", "contactPerson": null, "idNumber": null,
                 "taxNumber": null, "address": "Calle Falsa 123 altos", "city": "Santiago de Cuba", "phone": "50000001", "email": null},
    "seller": "VENDEDOR INVENTADO", "cashier": "CAJERO", "orderNumber": "PXX26-261017-0001",
    "customerReference": "SC06OTR0001", "note": "P-PXX26-261017-0001; V-VENDEDOR INVENTADO; C-SC06OTR0001;",
    "delivery": {"skus": ["50"], "items": 1, "amount": 0.29}},
   "items": [
    {"line": 1, "lineId": 1, "productId": 154, "productCode": "PARR0002", "productName": "CERVEZA PARRANDA 500 ML BLISTER 6U",
     "unit": "B", "catalog": "PROCOVAR", "quantity": 15, "unitPrice": 3.96, "discount": 0, "amount": 59.4, "isDelivery": false},
    {"line": 2, "lineId": 2, "productId": 1477, "productCode": "50", "productName": "ENTREGA A DOMICILIO - PROCOVAR",
     "unit": "U", "catalog": "PROCOVAR", "quantity": 0.29, "unitPrice": 1, "discount": 0, "amount": 0.29, "isDelivery": true}],
   "totals": {"total": 59.69}, "payments": [{"type": "EFECT CUP", "amountUsd": 59.76}]},
  {"header": {"invoiceNumber": "100", "date": "2026-10-17",
    "pointOfSale": {"id": 7, "code": "PV-DOS", "name": "ALMACEN DOS"},
    "customer": {"code": "478", "name": "Cliente Inventado Dos", "address": "Avenida Falsa 9", "city": "Santiago de Cuba", "phone": "50000002"},
    "seller": "OTRO VENDEDOR", "orderNumber": "", "customerReference": "KIOSCO INVENTADO DOS"},
   "items": [
    {"productCode": "ALIM0002", "productName": "ACEITE SOYA 900 ML CAJA 20U", "unit": "C", "quantity": 2, "unitPrice": 57, "amount": 114, "isDelivery": false},
    {"productCode": "51", "productName": "ENTREGA A DOMICILIO - CES", "unit": "U", "quantity": 0.27, "unitPrice": 1, "amount": 0.27, "isDelivery": true}]},
  {"header": {"invoiceNumber": 100, "date": "2026-10-17",
    "pointOfSale": {"code": "2", "name": "ALMACEN UNO"},
    "customer": {"name": "Cliente Inventado Tres"}, "orderNumber": "PXX26-261017-0001"},
   "items": [
    {"productCode": "PARR0002", "productName": "CERVEZA PARRANDA 500 ML BLISTER 6U", "unit": "B", "quantity": 5, "unitPrice": 3.96, "isDelivery": false},
    {"productCode": "50", "productName": "ENTREGA A DOMICILIO", "quantity": 0.35, "unitPrice": 1, "isDelivery": true}]}
 ]}`

var (
	desde = time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	hasta = time.Date(2026, 10, 17, 0, 0, 0, 0, time.UTC)
	skus  = []string{"45", "50", "51"}
)

func TestLasFacturasSeLeenConTodoLoQueElMapeoUsa(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, facturasDeVentra) })

	fs, err := c.FacturasConDomicilio(context.Background(), "santiago", desde, hasta, skus)
	if err != nil {
		t.Fatalf("tenía que leerlas: %v", err)
	}
	if len(fs) != 3 {
		t.Fatalf("tres facturas; salieron %d", len(fs))
	}

	a := fs[0]
	if a.Numero != "47252" || a.Fecha != "2026-10-17" || a.Punto.Codigo != "2" || a.Punto.Nombre != "ALMACEN UNO" {
		t.Errorf("cabecera mal: %+v", a)
	}
	if a.Cliente.Nombre != "Cliente Inventado Uno" || a.Cliente.Direccion != "Calle Falsa 123 altos" ||
		a.Cliente.Ciudad != "Santiago de Cuba" || a.Cliente.Telefono != "50000001" {
		t.Errorf("cliente mal: %+v", a.Cliente)
	}
	if a.Vendedor != "VENDEDOR INVENTADO" || a.Pedido != "PXX26-261017-0001" || a.ReferenciaDelCliente != "SC06OTR0001" {
		t.Errorf("vendedor, pedido y referencia mal: %+v", a)
	}
	if len(a.Lineas) != 2 || a.Lineas[0].Codigo != "PARR0002" || a.Lineas[0].Cantidad != 15 || a.Lineas[0].EsDomicilio ||
		!a.Lineas[1].EsDomicilio || a.Lineas[1].Importe != 0.29 || a.Lineas[1].Codigo != "50" {
		t.Errorf("líneas mal (el domicilio es la `isDelivery`): %+v", a.Lineas)
	}

	// Número como cadena, punto de venta de texto, sin nota del pedido (llega vacío).
	b := fs[1]
	if b.Numero != "100" || b.Punto.Codigo != "PV-DOS" || b.Pedido != "" || b.ReferenciaDelCliente != "KIOSCO INVENTADO DOS" {
		t.Errorf("la segunda trae el número entre comillas, un punto de venta de texto y el pedido vacío: %+v", b)
	}
	// Sin `amount`, el importe es cantidad × precio.
	if fs[2].Lineas[1].Importe != 0.35 {
		t.Errorf("sin amount, el importe es cantidad × precio unitario: %+v", fs[2].Lineas[1])
	}
	// El mismo número 100 en dos puntos de venta es DOS facturas: aquí se leen las dos.
	if fs[1].Numero != fs[2].Numero || fs[1].Punto.Codigo == fs[2].Punto.Codigo {
		t.Errorf("el mismo número en dos puntos de venta tiene que leerse como dos facturas: %+v %+v", fs[1], fs[2])
	}

	// Y la petición: ruta, base, fechas y los tres skus.
	vistas := v.vistas()
	if len(vistas) != 1 {
		t.Fatalf("una sola petición: %v", vistas)
	}
	u, _ := url.Parse(vistas[0])
	q := u.Query()
	if u.Path != "/axis/home-delivery-invoices" || q.Get("database") != "santiago" || q.Get("from") != "2026-10-16" ||
		q.Get("to") != "2026-10-17" || q.Get("skus") != "45,50,51" {
		t.Errorf("petición mal armada: %s", vistas[0])
	}
}

func TestLasFacturasVanConElBearer(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, facturasDeVentra) })
	if _, err := c.FacturasConDomicilio(context.Background(), "santiago", desde, hasta, skus); err != nil {
		t.Fatal(err)
	}
	if got := v.cabezas[0].Get("authorization"); got != "Bearer token-de-pruebas" {
		t.Errorf("el mismo Bearer que el catálogo; salió %q", got)
	}
}

func TestSinTokenOSinURLLasFacturasNoSalenALaRed(t *testing.T) {
	llamadas := 0
	srv := montarSinCliente(t, &llamadas)
	for nombre, cfg := range map[string]*config.Config{
		"sin token": {VentraURL: srv},
		"sin url":   {VentraToken: "t"},
	} {
		c := Nuevo(cfg, callado())
		_, err := c.FacturasConDomicilio(context.Background(), "santiago", desde, hasta, skus)
		if err == nil || !strings.Contains(err.Error(), "WAREHOUSE_API_") {
			t.Errorf("%s: tenía que decir qué variable falta: %v", nombre, err)
		}
	}
	if llamadas != 0 {
		t.Errorf("sin configuración NO sale a la red; salió %d veces", llamadas)
	}
}

func TestSinBaseNoSePideNada(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, facturasDeVentra) })
	if _, err := c.FacturasConDomicilio(context.Background(), " ", desde, hasta, skus); err == nil {
		t.Fatal("una sucursal por llamada: sin base es un error")
	}
	if len(v.vistas()) != 0 {
		t.Errorf("y no sale a la red: %v", v.vistas())
	}
}

func TestUnaVentanaSinFacturasEsLegitimaYUnaRespuestaRotaNo(t *testing.T) {
	// Lo que hay que distinguir: `invoices: []` es una ventana sin facturas con domicilio (bueno);
	// que falte la clave, o no sea JSON, es una respuesta que no se entiende (error).
	casos := []struct {
		nombre string
		cuerpo string
		estado int
		malo   string // texto que tiene que llevar el error ("" = tiene que ir bien)
	}{
		{"vacía de verdad", `{"database":"santiago","summary":{"invoices":0},"invoices":[]}`, 200, ""},
		{"sin la lista", `{"database":"santiago","summary":{"invoices":0}}`, 200, "sin la lista"},
		{"no es JSON", `<html>502 Bad Gateway</html>`, 200, "no se entiende"},
		{"cuerpo vacío", ``, 200, "no se entiende"},
		{"la lista no es una lista", `{"database":"santiago","invoices":"nada"}`, 200, "no se entiende"},
		{"otra base", `{"database":"habana","invoices":[]}`, 200, "habana"},
		{"el resumen no cuadra", `{"database":"santiago","summary":{"invoices":5},"invoices":[]}`, 200, "cortada"},
		{"sin número de factura", `{"database":"santiago","invoices":[{"header":{"date":"2026-10-17"},"items":[]}]}`, 200, "invoiceNumber"},
		{"fecha rota", `{"database":"santiago","invoices":[{"header":{"invoiceNumber":1,"date":"17/10/2026"},"items":[]}]}`, 200, "AAAA-MM-DD"},
		{"HTTP 500", `{"error":"base caída"}`, 500, "Ventra 500"},
		{"HTTP 401", `{"error":"scope"}`, 401, "Ventra 401"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			cl, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(c.estado)
				responder(w, c.cuerpo)
			})
			fs, err := cl.FacturasConDomicilio(context.Background(), "santiago", desde, hasta, skus)
			if c.malo == "" {
				if err != nil || len(fs) != 0 {
					t.Fatalf("una ventana vacía es buena: %v %v", fs, err)
				}
				return
			}
			if err == nil {
				t.Fatalf("tenía que ser un error y devolvió %v", fs)
			}
			if !strings.Contains(err.Error(), c.malo) {
				t.Errorf("el error tiene que decir %q: %v", c.malo, err)
			}
			if len(fs) != 0 {
				t.Errorf("y NO devuelve nada a medias: %v", fs)
			}
		})
	}
}

func TestUnaRespuestaMasGrandeQueElTopeEsUnErrorYNoUnJSONCortado(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		responder(w, `{"database":"santiago","invoices":[],"relleno":"`+strings.Repeat("x", 2048)+`"}`)
	})
	_, err := c.pedirConTope(context.Background(), rutaFacturas, nil, 1024)
	if err == nil || !strings.Contains(err.Error(), "más de") {
		t.Fatalf("pasarse del tope es un error que lo dice: %v", err)
	}
}

// ---------------------------------------------------------------------------
// Tramos de 93 días
// ---------------------------------------------------------------------------

func TestUnaVentanaLargaSePartePorTramosDeComoMucho93Dias(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, r *http.Request) {
		responder(w, `{"database":"santiago","summary":{"invoices":0},"invoices":[]}`)
	})
	ini := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	fin := time.Date(2026, 10, 17, 0, 0, 0, 0, time.UTC) // 290 días
	if _, err := c.FacturasConDomicilio(context.Background(), "santiago", ini, fin, skus); err != nil {
		t.Fatal(err)
	}

	prev := ini.AddDate(0, 0, -1)
	for i, ruta := range v.vistas() {
		u, _ := url.Parse(ruta)
		d, _ := time.Parse(time.DateOnly, u.Query().Get("from"))
		h, _ := time.Parse(time.DateOnly, u.Query().Get("to"))
		if dias := int(h.Sub(d).Hours()/24) + 1; dias > MaxDiasPorLlamada {
			t.Errorf("el tramo %d tiene %d días y el tope es %d: Ventra contestaría 400", i, dias, MaxDiasPorLlamada)
		}
		if !d.Equal(prev.AddDate(0, 0, 1)) {
			t.Errorf("el tramo %d empieza el %s y tenía que empezar el día siguiente al anterior (%s): un hueco son facturas que no se ven, un solape son facturas contadas dos veces",
				i, d.Format(time.DateOnly), prev.Format(time.DateOnly))
		}
		prev = h
	}
	if !prev.Equal(fin) {
		t.Errorf("los tramos tenían que llegar hasta el %s; llegaron al %s", fin.Format(time.DateOnly), prev.Format(time.DateOnly))
	}
	if n := len(v.vistas()); n != 4 {
		t.Errorf("290 días son 4 tramos de a lo sumo 93; fueron %d", n)
	}
}

func TestSiFallaUnTramoNoSeDevuelveUnaListaAMedias(t *testing.T) {
	// Quien compara con lo guardado creería que las facturas del tramo que falló se anularon.
	n := 0
	c, _ := montar(t, func(w http.ResponseWriter, r *http.Request) {
		n++
		if n == 2 {
			w.WriteHeader(500)
			responder(w, `caído`)
			return
		}
		responder(w, facturasDeVentra)
	})
	fs, err := c.FacturasConDomicilio(context.Background(), "santiago",
		time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), time.Date(2026, 10, 17, 0, 0, 0, 0, time.UTC), skus)
	if err == nil || len(fs) != 0 {
		t.Fatalf("un tramo caído es un error y no una lista parcial: %d facturas, %v", len(fs), err)
	}
}

func TestUnaVentanaAlReves(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, facturasDeVentra) })
	if _, err := c.FacturasConDomicilio(context.Background(), "santiago", hasta, desde, skus); err == nil {
		t.Fatal("una ventana al revés es un error")
	}
	if len(v.vistas()) != 0 {
		t.Error("y no sale a la red")
	}
}

func TestLaHoraDelDiaNoCambiaLaVentana(t *testing.T) {
	// Las ventanas son fechas: 23:59 y 00:01 del mismo día son el mismo tramo.
	tramos, err := tramosDeVentra(time.Date(2026, 10, 16, 23, 59, 0, 0, time.UTC), time.Date(2026, 10, 17, 0, 1, 0, 0, time.UTC))
	if err != nil || len(tramos) != 1 {
		t.Fatalf("%v %v", tramos, err)
	}
}

// montarSinCliente levanta un Ventra que sólo cuenta cuántas veces le tocan la puerta.
func montarSinCliente(t *testing.T, llamadas *int) string {
	t.Helper()
	_, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { *llamadas++ })
	return v.URL
}
