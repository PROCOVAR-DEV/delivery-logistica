package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// EL AVISO A PEDIDO VA POR FACTURA — 23/10/2026.
//
// Las entregas nacen de facturas de Ventra y su `external_id` no lo conoce PEDIDO: se le avisa
// con folio + sucursal + factura + punto de venta, una vez por FACTURA (un pedido puede tener
// varias). Una factura sin folio no tiene a quién avisar y no hace ruido.

// deFactura convierte un pedido del doble en la entrega de una factura.
func deFactura(d *dobleDeRutas, id uuid.UUID, punto, numero string, folio *string) {
	p := d.pedidos[id]
	p.externalID = textoDeRutas(fmt.Sprintf("factura:STG:%s:%s:2026-10-22", punto, numero))
	p.folio, p.facturaNumero = folio, textoDeRutas(numero)
}

func cerrarYRecoger(t *testing.T, d *dobleDeRutas, cuerpo func(ruta uuid.UUID) string, ids ...uuid.UUID) ([]AvisoDeParada, string) {
	t.Helper()
	var registro bytes.Buffer
	h, s := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	ruta := armarRutaDePrueba(t, h, jwt, ids...)
	var mandados []AvisoDeParada
	var candado sync.Mutex
	s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		candado.Lock()
		defer candado.Unlock()
		mandados = append(mandados, avisos...)
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+ruta.String()+"/results", jwt, cuerpo(ruta))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	candado.Lock()
	defer candado.Unlock()
	return append([]AvisoDeParada(nil), mandados...), registro.String()
}

func TestUnaFacturaConFolioAvisaPorFacturaConTodosSusCampos(t *testing.T) {
	d, p, _ := datosDeReparto()
	deFactura(d, p[0], "P01", "1001", textoDeRutas("PSV26-261021-1062"))
	mandados, _ := cerrarYRecoger(t, d, func(uuid.UUID) string {
		return fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, p[0])
	}, p[0])

	if len(mandados) != 1 {
		t.Fatalf("tenía que salir 1 aviso y salieron %d: %+v", len(mandados), mandados)
	}
	a := mandados[0]
	if a.Folio != "PSV26-261021-1062" || a.Sucursal != "STG" || a.Factura != "1001" ||
		a.PuntoDeVenta != "P01" || a.PedidoID != "" || a.Estado != "entregado" {
		t.Fatalf("aviso por factura mal armado: %+v", a)
	}
	crudo, _ := json.Marshal(a)
	if strings.Contains(string(crudo), "pedidoId") {
		t.Fatalf("el JSON de una factura no puede llevar pedidoId (ni vacío): %s", crudo)
	}
	// Y al buzón con los mismos campos, para que el reintento mande lo mismo.
	if len(d.avisosEncolados) != 1 {
		t.Fatalf("al buzón tenía que ir 1 y fueron %d", len(d.avisosEncolados))
	}
	e := d.avisosEncolados[0]
	if e.Folio == nil || *e.Folio != a.Folio || e.Sucursal == nil || *e.Sucursal != "STG" ||
		e.Factura == nil || *e.Factura != "1001" || e.PuntoDeVenta == nil || *e.PuntoDeVenta != "P01" {
		t.Fatalf("el buzón no guardó los campos de la factura: %+v", e)
	}
}

func TestUnaFacturaSinFolioNoAvisaNiHaceRuido(t *testing.T) {
	d, p, _ := datosDeReparto()
	deFactura(d, p[0], "P01", "1001", nil)
	mandados, registro := cerrarYRecoger(t, d, func(uuid.UUID) string {
		return fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, p[0])
	}, p[0])

	if len(mandados) != 0 || len(d.avisosEncolados) != 0 {
		t.Fatalf("sin folio no hay a quién avisar: mandados=%+v buzón=%+v", mandados, d.avisosEncolados)
	}
	for _, linea := range strings.Split(registro, "\n") {
		if strings.Contains(linea, "level=ERROR") ||
			(strings.Contains(linea, "level=WARN") && strings.Contains(strings.ToLower(linea), "avis")) {
			t.Fatalf("una factura sin folio no es un error y no debe hacer ruido:\n%s", linea)
		}
	}
}

func TestUnPedidoDePedidoSigueAvisandoConSuPedidoID(t *testing.T) {
	d, p, _ := datosDeReparto()
	mandados, _ := cerrarYRecoger(t, d, func(uuid.UUID) string {
		return fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"devuelto"}]}`, p[0])
	}, p[0])
	if len(mandados) != 1 || mandados[0].PedidoID != "PED-1" || mandados[0].Folio != "" || mandados[0].Factura != "" {
		t.Fatalf("un pedido de PEDIDO tenía que avisar como siempre: %+v", mandados)
	}
	crudo, _ := json.Marshal(mandados[0])
	for _, campo := range []string{"folio", "factura", "sucursal", "puntoDeVenta"} {
		if strings.Contains(string(crudo), campo) {
			t.Fatalf("el aviso de un pedido lleva %q: %s", campo, crudo)
		}
	}
}

// Un pedido con DOS facturas manda DOS avisos, uno por factura.
func TestDosFacturasDelMismoFolioSonDosAvisos(t *testing.T) {
	d, p, _ := datosDeReparto()
	folio := textoDeRutas("PSV26-261021-1062")
	deFactura(d, p[0], "P01", "1001", folio)
	deFactura(d, p[1], "P01", "1002", folio)
	mandados, _ := cerrarYRecoger(t, d, func(uuid.UUID) string {
		return fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"},{"orderId":%q,"resultado":"devuelto"}]}`, p[0], p[1])
	}, p[0], p[1])
	if len(mandados) != 2 {
		t.Fatalf("dos facturas del mismo folio tenían que ser 2 avisos y fueron %d: %+v", len(mandados), mandados)
	}
	por := map[string]string{}
	for _, a := range mandados {
		por[a.Factura] = a.Estado
	}
	if por["1001"] != "entregado" || por["1002"] != "devuelto" {
		t.Fatalf("cada factura con su estado: %v", por)
	}
}

// La MISMA factura marcada dos veces en la hoja: un aviso, el último.
func TestLaMismaFacturaDosVecesEnElCierreMandaUnAvisoYElUltimo(t *testing.T) {
	d, p, _ := datosDeReparto()
	deFactura(d, p[0], "P01", "1001", textoDeRutas("PSV26-261021-1062"))
	mandados, _ := cerrarYRecoger(t, d, func(uuid.UUID) string {
		return fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"},{"orderId":%q,"resultado":"devuelto"}]}`, p[0], p[0])
	}, p[0])
	if len(mandados) != 1 || mandados[0].Estado != "devuelto" {
		t.Fatalf("tenía que salir UN aviso, el último (devuelto): %+v", mandados)
	}
}

// Al armar sale «despachado» por factura, de fondo.
func TestAlArmarUnaFacturaSaleDespachadaPorFactura(t *testing.T) {
	d, p, _ := datosDeReparto()
	deFactura(d, p[0], "P01", "1001", textoDeRutas("PSV26-261021-1062"))
	deFactura(d, p[1], "P01", "1002", nil) // sin folio: no sale
	h, s := montarRutasCon(t, d)
	var candado sync.Mutex
	var visto []AvisoDeParada
	llegaron := make(chan struct{}, 1)
	s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		candado.Lock()
		visto = append(visto, avisos...)
		candado.Unlock()
		llegaron <- struct{}{}
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}
	armarRutaDePrueba(t, h, deSantiagoEnRutas(t), p[0], p[1])
	select {
	case <-llegaron:
	case <-time.After(2 * time.Second):
		t.Fatal("el aviso de despachado no salió")
	}
	candado.Lock()
	defer candado.Unlock()
	if len(visto) != 1 || visto[0].Factura != "1001" || visto[0].Estado != estadoDespachado || visto[0].PedidoID != "" {
		t.Fatalf("al armar tenía que salir 1 «despachado» de la 1001: %+v", visto)
	}
}

// EL REINTENTO DEL BUZÓN lleva exactamente lo que se encoló; uno viejo con pedidoId sigue yendo.
func TestElBuzonReenviaLosCamposDeLaFacturaYElAvisoViejoSigueYendo(t *testing.T) {
	d, p, _ := datosDeReparto()
	deFactura(d, p[0], "P01", "1001", textoDeRutas("PSV26-261021-1062"))
	mandados, _ := cerrarYRecoger(t, d, func(uuid.UUID) string {
		return fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado","nota":"ok"}]}`, p[0])
	}, p[0])
	e := d.avisosEncolados[0]

	b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{
		{ID: uuid.New(), PedidoID: e.PedidoID, Folio: e.Folio, Estado: e.Estado, Nota: e.Nota, OcurrioAt: e.OcurrioAt,
			Sucursal: e.Sucursal, Factura: e.Factura, PuntoDeVenta: e.PuntoDeVenta},
		{ID: uuid.New(), PedidoID: "PED-VIEJO", Estado: "entregado",
			OcurrioAt: pgtype.Timestamptz{Time: time.Now(), Valid: true}},
	}}
	var reenviados []AvisoDeParada
	s := servidorConBuzon(t, b, func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		reenviados = append(reenviados, avisos...)
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	})
	s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if len(reenviados) != 2 {
		t.Fatalf("se esperaban 2 reenvíos y hubo %d", len(reenviados))
	}
	original := mandados[0]
	original.At = reenviados[0].At // la hora sale del buzón en UTC; se compara aparte
	if reenviados[0] != original || !reenviados[0].At.Equal(mandados[0].At) {
		t.Fatalf("el reintento no es idéntico al aviso original:\n  original  %+v\n  reintento %+v", mandados[0], reenviados[0])
	}
	if reenviados[1].PedidoID != "PED-VIEJO" || reenviados[1].Factura != "" {
		t.Fatalf("el aviso viejo con pedidoId se rompió: %+v", reenviados[1])
	}
}

// LA FACTURA CANCELADA EN VENTRA (la llama el espejo): encola «cancelado» con folio; sin folio, nada.
func TestAvisarFacturaCanceladaEncolaConFolioYSinFolioNoHaceNada(t *testing.T) {
	d, p, _ := datosDeReparto()
	deFactura(d, p[0], "P01", "1001", textoDeRutas("PSV26-261021-1062"))
	deFactura(d, p[1], "P01", "1002", nil)
	a := acotadoDeBuzon(d)
	cuando := time.Date(2026, 10, 23, 9, 0, 0, 0, time.UTC)

	n, err := a.AvisarFacturasCanceladas(context.Background(), []uuid.UUID{p[0], p[1], uuid.New()}, cuando)
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v; se esperaba 1 y sin error", n, err)
	}
	e := d.avisosEncolados[0]
	if len(d.avisosEncolados) != 1 || e.Estado != "cancelado" || *e.Folio != "PSV26-261021-1062" ||
		*e.Factura != "1001" || *e.PuntoDeVenta != "P01" || *e.Sucursal != "STG" || !e.OcurrioAt.Time.Equal(cuando) {
		t.Fatalf("aviso cancelado mal encolado: %+v", d.avisosEncolados)
	}

	hay, err := a.AvisarFacturaCancelada(context.Background(), alcance.EntregaAAvisar{
		ExternalID: d.pedidos[p[1]].externalID, FacturaNumero: d.pedidos[p[1]].facturaNumero}, cuando)
	if hay || err != nil || len(d.avisosEncolados) != 1 {
		t.Fatalf("sin folio no se avisa: hay=%v err=%v buzón=%d", hay, err, len(d.avisosEncolados))
	}
}
