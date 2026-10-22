package api

// LA PUERTA ANTE UNA ENTREGA QUE NACE DE UNA FACTURA (issue 20, Fase A). Sin base: la puerta de
// verdad (`POST /api/quote/batch` con su llave) y lo que le llega a `GuardarPedidoDelEspejo`.
// La adopción, la convivencia y la retirada contra Postgres, en `facturas_motor_real_test.go`.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/espejo"
)

// mandarLote manda el cuerpo por la puerta y devuelve la respuesta y TODO lo que se intentó
// escribir. `guardar` decide qué contesta la escritura (nil = guarda bien).
func mandarLote(t *testing.T, cuerpo string, guardar func(PedidoParaGuardar) error) ([]baseDelLote, []PedidoParaGuardar) {
	t.Helper()
	conAccesos(t, &accesosFalso{sucursales: almacenesDeSantiagoDeAccesos()})
	var escritos []PedidoParaGuardar
	antes := GuardarPedidoDelEspejo
	t.Cleanup(func() { GuardarPedidoDelEspejo = antes })
	GuardarPedidoDelEspejo = func(_ context.Context, _ *alcance.Acotado, p PedidoParaGuardar) (uuid.UUID, error) {
		escritos = append(escritos, p)
		if guardar != nil {
			if err := guardar(p); err != nil {
				return uuid.Nil, err
			}
		}
		return uuid.New(), nil
	}
	h := montarCotizacion(t, &dobleDelOrigen{})
	r := httptest.NewRequest(http.MethodPost, "/api/quote/batch", strings.NewReader(cuerpo))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("la puerta contestó %d: %s", w.Code, w.Body.String())
	}
	var salida struct {
		Results []baseDelLote `json:"results"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("la respuesta no se entiende: %v — %s", err, w.Body.String())
	}
	return salida.Results, escritos
}

// pedidoDeLote arma un pedido del lote en JSON a mano (se prueba que los campos se LEEN del
// cuerpo), con las coordenadas que se le digan o sin ellas.
func pedidoDeLote(externalID, folio string, conPunto bool) string {
	punto := ""
	if conPunto {
		punto = fmt.Sprintf(`"lat":%v,"lng":%v,`, latCliente, lngCliente)
	}
	return fmt.Sprintf(`{"orders":[{
		"externalId":%q,"operationNumber":"47252, 47253","sucursalExternalId":"STG","folio":%q,
		"customerName":"Cliente Inventado","address":"Calle 4",%s"requiereDomicilio":true,
		"facturaEstado":"igual","facturaNumero":"47252, 47253","facturaDomicilio":0.29,"itemsOrigen":"factura",
		"items":[{"code":"PARR0002","name":"CERVEZA PARRANDA 500 ML BLISTER 6U","descripcion":"CERVEZA PARRANDA 500 ML BLISTER 6U",
		          "quantity":90,"packs":15,"pesoKg":2.4,"almacenCodigo":"2","almacenNombre":"AURORA"}],
		"almacen":{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":false}
	}]}`, externalID, folio, punto)
}

func TestUnaEntregaDeFacturaSinCoordenadasSeGuardaSinCoordenadas(t *testing.T) {
	res, escritos := mandarLote(t, pedidoDeLote("factura:STG:PJM26-1", "PJM26-1", false), nil)
	if len(escritos) != 1 {
		t.Fatalf("una entrega de factura sin punto se GUARDA (nada se descarta en silencio); se escribieron %d", len(escritos))
	}
	if res[0].Persisted == nil || !*res[0].Persisted || res[0].Reason == "sin-geolocalizacion" {
		t.Errorf("y la respuesta lo dice: %+v", res[0])
	}
	fila := paraLaBase(escritos[0])
	if fila.Lat != nil || fila.Lng != nil || fila.EndLat != nil || fila.EndLng != nil {
		t.Errorf("sin coordenadas: NULL en las cuatro, no ceros (cero es un punto en el golfo de Guinea): %v %v %v %v",
			fila.Lat, fila.Lng, fila.EndLat, fila.EndLng)
	}
	if fila.DeliveryDistanceKm != nil {
		t.Errorf("sin punto no hay distancia, ni un kilometraje 'medido' hasta ningún sitio: %v", *fila.DeliveryDistanceKm)
	}
	if fila.Weight <= 0 {
		t.Errorf("pero el peso sí se resuelve: 15 B × 2,4 kg = 36; salió %v", fila.Weight)
	}
	if fila.Folio == nil || *fila.Folio != "PJM26-1" {
		t.Errorf("el folio de una entrega de factura es el que manda el cuerpo: %v", fila.Folio)
	}
	if fila.AlmacenSalidaCodigo == nil || *fila.AlmacenSalidaCodigo != "2" {
		t.Errorf("el almacén de salida llega igual: %v", fila.AlmacenSalidaCodigo)
	}
}

func TestUnaEntregaDeFacturaConCoordenadasSeMideComoSiempre(t *testing.T) {
	_, escritos := mandarLote(t, pedidoDeLote("factura:STG:PJM26-1", "PJM26-1", true), nil)
	fila := paraLaBase(escritos[0])
	if fila.Lat == nil || *fila.Lat != latCliente || fila.DeliveryDistanceKm == nil || *fila.DeliveryDistanceKm <= 0 {
		t.Errorf("con punto, todo como un pedido: %+v", fila)
	}
}

func TestUnPedidoDePedidoSinCoordenadasSigueDescartandose(t *testing.T) {
	// La mitad que no puede romperse al abrir la puerta a las facturas.
	res, escritos := mandarLote(t, pedidoDeLote("ped-1", "", false), nil)
	if len(escritos) != 0 {
		t.Fatalf("un pedido de PEDIDO sin coordenadas NO se guarda; se escribió %+v", escritos)
	}
	if res[0].Status != "skipped" || res[0].Reason != "sin-geolocalizacion" {
		t.Errorf("y se dice con su motivo de siempre: %+v", res[0])
	}
}

func TestSoloElPrefijoDeFacturaAbreLaPuertaSinCoordenadas(t *testing.T) {
	// `factura` a secas, o con el prefijo en medio, NO es una entrega de factura: la convención
	// es UNA y vive en `alcance.EsDeFactura`.
	for _, id := range []string{"factura", "FACTURA:STG:1", " factura:STG:1", "x-factura:STG:1"} {
		_, escritos := mandarLote(t, pedidoDeLote(id, "", false), nil)
		if len(escritos) != 0 {
			t.Errorf("%q no es de factura y no tiene coordenadas: no entra", id)
		}
	}
}

func TestElFolioDeUnPedidoDePedidoEsSuNumeroDeOperacion(t *testing.T) {
	// El cuerpo manda `folio: OTRO` y `operationNumber: 47252, 47253`: en un pedido de PEDIDO el
	// folio es SIEMPRE su número de operación. Si se leyera el del cuerpo, quien mande el lote
	// podría adoptar la fila de otro pedido poniendo su folio.
	_, escritos := mandarLote(t, pedidoDeLote("ped-1", "FOLIO-AJENO", true), nil)
	if f := escritos[0].Folio; f == nil || *f != "47252, 47253" {
		t.Errorf("el folio de un pedido de PEDIDO es su operationNumber; salió %v", f)
	}
}

func TestUnFolioVacioEnUnaEntregaDeFacturaEsNulo(t *testing.T) {
	// Un folio vacío guardado casaría a todas las entregas sin folio entre sí.
	_, escritos := mandarLote(t, pedidoDeLote("factura:STG:2:100:2026-10-17", "  ", true), nil)
	if f := escritos[0].Folio; f != nil {
		t.Errorf("sin folio, nulo: %q", *f)
	}
}

func TestUnPedidoYaAdoptadoPorUnaFacturaNoEsUnFallo(t *testing.T) {
	res, escritos := mandarLote(t, pedidoDeLote("ped-1", "", true), func(PedidoParaGuardar) error {
		return fmt.Errorf("envuelto: %w", alcance.ErrYaAdoptadoPorFactura)
	})
	if len(escritos) != 1 || len(res) != 1 {
		t.Fatalf("la puerta intentó guardar y siguió con 200: %d %d", len(escritos), len(res))
	}
	if res[0].Persisted == nil || *res[0].Persisted {
		t.Errorf("no se guardó: %+v", res[0])
	}
	if res[0].Reason != "ya-adoptado-por-factura" || espejo.MotivoYaAdoptado != "ya-adoptado-por-factura" {
		t.Errorf("y lo dice con su motivo: %q", res[0].Reason)
	}
}

func TestUnFalloDeVerdadAlGuardarSigueSiendoUn500(t *testing.T) {
	// La otra mitad: sólo el error de la adopción es benigno.
	conAccesos(t, &accesosFalso{sucursales: almacenesDeSantiagoDeAccesos()})
	antes := GuardarPedidoDelEspejo
	t.Cleanup(func() { GuardarPedidoDelEspejo = antes })
	GuardarPedidoDelEspejo = func(context.Context, *alcance.Acotado, PedidoParaGuardar) (uuid.UUID, error) {
		return uuid.Nil, errors.New("la base se cayó")
	}
	h := montarCotizacion(t, &dobleDelOrigen{})
	r := httptest.NewRequest(http.MethodPost, "/api/quote/batch", strings.NewReader(pedidoDeLote("ped-1", "", true)))
	r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusInternalServerError {
		t.Errorf("un error de la base es un 500; salió %d", w.Code)
	}
}

// LA FACTURA DE CADA RENGLÓN LLEGA A LA FILA DE `order_items` (00026, issue 22 de Maikel): el
// campo viaja por la puerta (`facturaNumero` del renglón del cuerpo) hasta lo que se escribe, y
// un renglón que no la trae (PEDIDO) se escribe NULL, no con la de la entrega.
func TestLaFacturaDeCadaRenglonLlegaALaFilaDeLaBase(t *testing.T) {
	cuerpo := `{"orders":[{
		"externalId":"factura:STG:PJM26-1","operationNumber":"47359, 47360","sucursalExternalId":"STG","folio":"PJM26-1",
		"customerName":"Cliente Inventado","address":"Calle 4","lat":20.02,"lng":-75.82,"requiereDomicilio":true,
		"facturaEstado":"igual","facturaNumero":"47359, 47360","facturaDomicilio":0.29,"itemsOrigen":"factura",
		"items":[
		  {"code":"PARR0002","name":"CERVEZA PARRANDA 500 ML BLISTER 6U","descripcion":"CERVEZA","quantity":30,"packs":5,"pesoKg":2.4,"almacenCodigo":"2","almacenNombre":"AURORA","facturaNumero":"47359"},
		  {"code":"PARR0002","name":"CERVEZA PARRANDA 500 ML BLISTER 6U","descripcion":"CERVEZA","quantity":42,"packs":7,"pesoKg":2.4,"almacenCodigo":"2","almacenNombre":"AURORA","facturaNumero":"47360"},
		  {"code":"MALT0001","name":"MALTA SIN FACTURA","descripcion":"MALTA","quantity":6,"packs":1,"pesoKg":1.2,"almacenCodigo":"2","almacenNombre":"AURORA"}
		],
		"almacen":{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":false}
	}]}`
	_, escritos := mandarLote(t, cuerpo, nil)
	if len(escritos) != 1 {
		t.Fatalf("se esperaba una entrega escrita; salieron %d", len(escritos))
	}
	filas := renglonesParaLaBase(escritos[0].Renglones)
	if len(filas) != 3 {
		t.Fatalf("se esperaban 3 renglones; salieron %d", len(filas))
	}
	quiere := []string{"47359", "47360", ""}
	for i, f := range filas {
		switch {
		case quiere[i] == "" && f.FacturaNumero != nil:
			t.Errorf("renglón %d: sin factura en el cuerpo tiene que escribirse NULL, salió %q", i+1, *f.FacturaNumero)
		case quiere[i] != "" && (f.FacturaNumero == nil || *f.FacturaNumero != quiere[i]):
			t.Errorf("renglón %d: la factura se perdió por el camino (quería %q): %v", i+1, quiere[i], f.FacturaNumero)
		}
	}
}
