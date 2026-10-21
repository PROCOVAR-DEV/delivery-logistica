package espejo

// El ciclo de la factura (issue 20, Fase A), con dobles: sin Ventra, sin PEDIDO, sin base. Lo
// que se prueba aquí es QUÉ se pregunta y QUÉ se retira; que lo retirado se retire de verdad en
// Postgres lo prueba `internal/api/facturas_motor_real_test.go`.

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

type peticionDeFacturas struct {
	base         string
	desde, hasta string
	skus         []string
}

type facturasFalsas struct {
	bases      map[string]string
	falloBases error
	// respuestas por base de Ventra.
	respuestas map[string][]FacturaDeVentra
	fallos     map[string]error
	pedidas    []peticionDeFacturas
}

func (f *facturasFalsas) Bases(context.Context) (map[string]string, error) {
	return f.bases, f.falloBases
}

func (f *facturasFalsas) FacturasConDomicilio(_ context.Context, base string, desde, hasta time.Time, skus []string) ([]FacturaDeVentra, error) {
	f.pedidas = append(f.pedidas, peticionDeFacturas{base, desde.Format(time.DateOnly), hasta.Format(time.DateOnly), skus})
	if err := f.fallos[base]; err != nil {
		return nil, err
	}
	return f.respuestas[base], nil
}

type baseDeFacturasFalsa struct {
	puntos    map[string][]PuntoDeCliente
	productos map[string]map[string]ProductoDeVentra
	// guardadas: lo que la base tiene por sucursal. Se devuelve tal cual, y se apunta la ventana
	// con la que se preguntó: es lo que hay que comprobar, que sólo se juzgue lo consultado.
	guardadas map[string][]EntregaGuardada
	ventanas  []string
	retiradas []uuid.UUID
	fallo     error
	// conduces: lo que las entregas ya tienen guardado, por external_id. abierta: el día de la
	// entrega abierta más antigua, por sucursal (nil = ninguna).
	conduces map[string]string
	abierta  map[string]*time.Time
}

func (b *baseDeFacturasFalsa) PuntosDeClientes(_ context.Context, s string) ([]PuntoDeCliente, error) {
	return b.puntos[s], b.fallo
}
func (b *baseDeFacturasFalsa) ProductosDeVentra(_ context.Context, s string) (map[string]ProductoDeVentra, error) {
	return b.productos[s], b.fallo
}
func (b *baseDeFacturasFalsa) EntregasDeFacturaEnVentana(_ context.Context, s string, desde, hasta time.Time) ([]EntregaGuardada, error) {
	b.ventanas = append(b.ventanas, s+" "+desde.Format(time.DateOnly)+".."+hasta.Format(time.DateOnly))
	return b.guardadas[s], b.fallo
}
func (b *baseDeFacturasFalsa) ConducesGuardados(_ context.Context, ids []string) (map[string]string, error) {
	salida := map[string]string{}
	for _, id := range ids {
		if c, hay := b.conduces[id]; hay {
			salida[id] = c
		}
	}
	return salida, b.fallo
}
func (b *baseDeFacturasFalsa) FechaDeLaEntregaAbiertaMasAntigua(_ context.Context, s string) (*time.Time, error) {
	return b.abierta[s], b.fallo
}
func (b *baseDeFacturasFalsa) RetirarEntregasDeFactura(_ context.Context, ids []uuid.UUID) (int64, error) {
	b.retiradas = append(b.retiradas, ids...)
	return int64(len(ids)), b.fallo
}

// montarFacturas arma un espejo de facturas con registro capturado.
func montarFacturas(fuente string, f *facturasFalsas, b *baseDeFacturasFalsa, p *pedidoFalso, d *repartoFalso) (*Espejo, *bytes.Buffer) {
	e := montar(p, d, &baseFalsa{})
	e.Opciones.Fuente = fuente
	e.Facturas, e.BaseF = f, b
	var registro bytes.Buffer
	e.Reg = slog.New(slog.NewTextHandler(io.MultiWriter(&registro), nil))
	return e, &registro
}

func unaFacturaDeSantiago() map[string][]FacturaDeVentra {
	return map[string][]FacturaDeVentra{"santiago": {
		factura("47252", "2026-09-13", "2", "PED-1", cerveza(15), domicilio(0.29)),
	}}
}

func TestConLaFuentePedidoNoSeTocaVentra(t *testing.T) {
	// El valor por defecto: desplegar esto no cambia NADA.
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	p := &pedidoFalso{}
	e, _ := montarFacturas(FuenteDePedido, f, &baseDeFacturasFalsa{}, p, &repartoFalso{})
	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(f.pedidas) != 0 {
		t.Errorf("con SYNC_FUENTE=pedido no se pregunta nada a Ventra; se preguntó %+v", f.pedidas)
	}
	if len(p.pedidas) == 0 {
		t.Error("y PEDIDO sigue trayéndose como siempre")
	}
}

func TestConLaFuenteFacturaNoSePideNadaAPedido(t *testing.T) {
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	p := &pedidoFalso{}
	d := &repartoFalso{}
	e, _ := montarFacturas(FuenteDeFactura, f, &baseDeFacturasFalsa{}, p, d)
	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(p.pedidas) != 0 {
		t.Errorf("con SYNC_FUENTE=factura PEDIDO no trae pedidos; se pidió %+v", p.pedidas)
	}
	if len(d.lotes) != 1 || len(d.lotes[0]) != 1 || d.lotes[0][0].ID != "factura:STG:PED1" {
		t.Fatalf("la entrega tenía que llegar a la puerta como factura:STG:PED1; llegó %+v", d.lotes)
	}
}

func TestConAmbasSeTraenLasDosFuentes(t *testing.T) {
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	p := &pedidoFalso{}
	e, _ := montarFacturas(FuenteAmbas, f, &baseDeFacturasFalsa{}, p, &repartoFalso{})
	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(f.pedidas) == 0 || len(p.pedidas) == 0 {
		t.Errorf("ambas = las dos: Ventra %d veces, PEDIDO %d", len(f.pedidas), len(p.pedidas))
	}
}

func TestPedidoConservaSuRitmoCuandoElCicloGiraPorLaFactura(t *testing.T) {
	// Con avisos, PEDIDO se repasa cada 3 horas. Con `ambas` el ciclo gira cada minuto por la
	// factura (Ventra no avisa), y eso NO puede arrastrar a PEDIDO a 1.440 repasos al día.
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	p := &pedidoFalso{}
	e, _ := montarFacturas(FuenteAmbas, f, &baseDeFacturasFalsa{}, p, &repartoFalso{})
	e.Opciones.TocanLaPuerta = true // a PEDIDO le avisan: su ritmo es de 3 horas
	ahora := hoy
	e.Ahora = func() time.Time { return ahora }

	if got := e.Opciones.RitmoDelCiclo(false); got != time.Minute {
		t.Fatalf("con factura el ciclo gira cada minuto (Ventra no avisa); salió %v", got)
	}
	_ = e.Ciclo(context.Background())
	antes := len(p.pedidas)
	if antes == 0 {
		t.Fatal("el primer ciclo trae lo de PEDIDO")
	}
	ahora = ahora.Add(time.Minute)
	_ = e.Ciclo(context.Background())
	if len(p.pedidas) != antes {
		t.Errorf("a un minuto del primer ciclo PEDIDO no se vuelve a pedir; se pidió %d veces más", len(p.pedidas)-antes)
	}
	if len(f.pedidas) < 2 {
		t.Errorf("pero la factura sí, en cada ciclo: %d peticiones", len(f.pedidas))
	}
	ahora = ahora.Add(PollConAvisos)
	_ = e.Ciclo(context.Background())
	if len(p.pedidas) == antes {
		t.Error("pasado su ritmo propio, a PEDIDO le vuelve a tocar")
	}
}

func TestLaVentanaEsElRepasoYUnaVezAlDiaElHistoricoPorSucursal(t *testing.T) {
	f := &facturasFalsas{
		bases:      map[string]string{"STG": "santiago", "HOL": "holguinmoa"},
		respuestas: map[string][]FacturaDeVentra{"santiago": nil, "holguinmoa": nil},
	}
	e, _ := montarFacturas(FuenteDeFactura, f, &baseDeFacturasFalsa{}, &pedidoFalso{}, &repartoFalso{})

	_ = e.Ciclo(context.Background())
	// Hoy es 2026-09-14 (en Cuba). La primera vez, por sucursal: el histórico entero (60 días).
	want := []peticionDeFacturas{
		{"holguinmoa", "2026-07-16", "2026-09-14", SkusDeDomicilio},
		{"santiago", "2026-07-16", "2026-09-14", SkusDeDomicilio},
	}
	if len(f.pedidas) != 2 {
		t.Fatalf("una petición por sucursal con base; fueron %d", len(f.pedidas))
	}
	for i, w := range want {
		g := f.pedidas[i]
		if g.base != w.base || g.desde != w.desde || g.hasta != w.hasta || strings.Join(g.skus, ",") != "45,50,51" {
			t.Errorf("petición %d: salió %+v y tocaba %+v (los skus son 45,50,51: el 45 es el producto viejo)", i, g, w)
		}
	}

	// Un ciclo después, el mismo día: sólo el repaso (los últimos 3 días).
	f.pedidas = nil
	_ = e.Ciclo(context.Background())
	for _, g := range f.pedidas {
		if g.desde != "2026-09-11" || g.hasta != "2026-09-14" {
			t.Errorf("el repaso son los últimos 3 días; se pidió %+v", g)
		}
	}
	// Y al día siguiente, otra vez el histórico.
	f.pedidas = nil
	e.Ahora = func() time.Time { return hoy.Add(25 * time.Hour) }
	_ = e.Ciclo(context.Background())
	for _, g := range f.pedidas {
		if g.desde != "2026-07-17" {
			t.Errorf("pasadas 24 horas toca barrer el histórico otra vez: %+v", g)
		}
	}
}

func TestUnaSucursalQueFallaNoTumbaALasOtras(t *testing.T) {
	f := &facturasFalsas{
		bases:      map[string]string{"STG": "santiago", "HOL": "holguinmoa"},
		respuestas: unaFacturaDeSantiago(),
		fallos:     map[string]error{"holguinmoa": errors.New("Ventra 500")},
	}
	d := &repartoFalso{}
	e, _ := montarFacturas(FuenteDeFactura, f, &baseDeFacturasFalsa{}, &pedidoFalso{}, d)
	_ = e.Ciclo(context.Background())
	if len(d.lotes) != 1 {
		t.Errorf("Santiago tenía que entrar aunque Holguín falle; lotes: %d", len(d.lotes))
	}
}

func TestSoloUnaSucursalSiSeLimita(t *testing.T) {
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago", "HOL": "holguinmoa"}}
	e, _ := montarFacturas(FuenteDeFactura, f, &baseDeFacturasFalsa{}, &pedidoFalso{}, &repartoFalso{})
	e.Opciones.SucursalCodigo = "HOL"
	_ = e.Ciclo(context.Background())
	if len(f.pedidas) != 1 || f.pedidas[0].base != "holguinmoa" {
		t.Errorf("SUCURSAL_CODIGO=HOL limita también a la factura: %+v", f.pedidas)
	}
}

// ---------------------------------------------------------------------------
// Lo que ya no viene
// ---------------------------------------------------------------------------

func entregasGuardadas() (vieneUna, anulada, conRuta EntregaGuardada) {
	return EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:PED1"},
		EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:PEDANULADO"},
		EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:PEDENRUTA", Ocupada: true}
}

func TestLaFacturaAnuladaSinRutaSeRetira(t *testing.T) {
	viene, anulada, _ := entregasGuardadas()
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {viene, anulada}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 1 || b.retiradas[0] != anulada.ID {
		t.Fatalf("se retira SOLO la que ya no viene: %v (la anulada es %v)", b.retiradas, anulada.ID)
	}
}

func TestLaAnuladaQueYaVaEnUnaRutaSeDejaYSeDice(t *testing.T) {
	_, _, enRuta := entregasGuardadas()
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {enRuta}}}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 {
		t.Fatalf("lo que ya va en el camión no se borra: %v", b.retiradas)
	}
	if !strings.Contains(reg.String(), "ANULADAS que ya van en una ruta") || !strings.Contains(reg.String(), "anuladasConRuta=1") {
		t.Errorf("se deja y SE DICE:\n%s", reg.String())
	}
}

func TestUnaRespuestaVaciaConEntregasEnLaBaseNoEsUnaAnulacion(t *testing.T) {
	// Una base de Ventra caída contesta lista vacía y SIN error. Tomarlo por «se anularon todas»
	// borraría la ventana entera de una sucursal. Es un ERROR y no se retira nada.
	viene, anulada, _ := entregasGuardadas()
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: map[string][]FacturaDeVentra{"santiago": {}}}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {viene, anulada}}}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 {
		t.Fatalf("una respuesta vacía no retira NADA: %v", b.retiradas)
	}
	if !strings.Contains(reg.String(), "se toma por un ERROR") {
		t.Errorf("y tiene que decirlo:\n%s", reg.String())
	}
}

func TestUnaRespuestaVaciaSinEntregasEnLaBaseEsNormal(t *testing.T) {
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: map[string][]FacturaDeVentra{"santiago": {}}}
	e, reg := montarFacturas(FuenteDeFactura, f, &baseDeFacturasFalsa{}, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if strings.Contains(reg.String(), "ERROR") {
		t.Errorf("una ventana sin facturas y sin nada guardado no es un error:\n%s", reg.String())
	}
}

func TestSiVentraFallaNoSeRetiraNada(t *testing.T) {
	viene, anulada, _ := entregasGuardadas()
	f := &facturasFalsas{
		bases:  map[string]string{"STG": "santiago"},
		fallos: map[string]error{"santiago": errors.New("Ventra 500")},
	}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {viene, anulada}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 || len(b.ventanas) != 0 {
		t.Fatalf("un fallo no es una anulación: ni se mira la base (%v) ni se retira (%v)", b.ventanas, b.retiradas)
	}
}

func TestSoloSeJuzgaLaVentanaConsultada(t *testing.T) {
	// A la base se le pregunta por EXACTAMENTE la ventana que se le preguntó a Ventra. Una
	// entrega de hace 40 días no está en el repaso de 3: no se puede decir que «ya no viene».
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {{ID: uuid.New(), ExternalID: "factura:STG:X"}}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy} // ya se barrió hoy: sólo repaso
	_ = e.Ciclo(context.Background())
	if len(b.ventanas) != 1 || b.ventanas[0] != "STG 2026-09-11..2026-09-14" {
		t.Errorf("la ventana de la base tiene que ser la del repaso; fue %v", b.ventanas)
	}
}

func TestSiNoSePuedenLeerLosClientesNoSeGuardaSinPuntos(t *testing.T) {
	// Guardar sin los puntos reescribiría con NULL las coordenadas de lo ya guardado.
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{fallo: errors.New("la base no contesta")}
	d := &repartoFalso{}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, d)
	_ = e.Ciclo(context.Background())
	if len(d.lotes) != 0 || len(b.retiradas) != 0 {
		t.Errorf("sin poder leer clientes no se guarda ni se retira: lotes %d, retiradas %v", len(d.lotes), b.retiradas)
	}
}

// ---------------------------------------------------------------------------
// El repaso no encoge una entrega (auditoría del 20/10/2026, G2)
// ---------------------------------------------------------------------------

func dia(s string) *time.Time {
	t, _ := time.Parse(time.DateOnly, s)
	return &t
}

func TestElRepasoSeEnsanchaHastaLaEntregaAbiertaMasAntigua(t *testing.T) {
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	// Hoy es 2026-09-14. Sin nada abierto, o con lo abierto dentro de los 3 días, el repaso es el de siempre.
	for nombre, abierta := range map[string]*time.Time{"nada abierto": nil, "abierta de hoy": dia("2026-09-14"), "abierta del borde": dia("2026-09-11")} {
		f.pedidas = nil
		b := &baseDeFacturasFalsa{abierta: map[string]*time.Time{"STG": abierta}}
		e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
		e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
		_ = e.Ciclo(context.Background())
		if len(f.pedidas) != 1 || f.pedidas[0].desde != "2026-09-11" {
			t.Errorf("%s: el repaso son los últimos 3 días (desde 2026-09-11); se pidió %+v", nombre, f.pedidas)
		}
	}
	// Con una entrega abierta más vieja, el repaso llega hasta su día.
	f.pedidas = nil
	b := &baseDeFacturasFalsa{abierta: map[string]*time.Time{"STG": dia("2026-09-02")}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
	_ = e.Ciclo(context.Background())
	if len(f.pedidas) != 1 || f.pedidas[0].desde != "2026-09-02" || f.pedidas[0].hasta != "2026-09-14" {
		t.Errorf("con una entrega abierta del 02/09 el repaso ve desde el 02/09; se pidió %+v", f.pedidas)
	}
	// Y la base se juzga con LA MISMA ventana que se le preguntó a Ventra.
	if len(b.ventanas) != 1 || b.ventanas[0] != "STG 2026-09-02..2026-09-14" {
		t.Errorf("la ventana de lo que ya no viene es la ensanchada: %v", b.ventanas)
	}
}

func TestElRepasoEnsanchadoTieneTopeEnElHistorico(t *testing.T) {
	// Una entrega abierta de hace un año no puede convertir el repaso de cada minuto en pedir un
	// año a Ventra: el tope es HistoricoDias (60), el mismo del barrido.
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{abierta: map[string]*time.Time{"STG": dia("2025-09-14")}}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
	_ = e.Ciclo(context.Background())
	if len(f.pedidas) != 1 || f.pedidas[0].desde != "2026-07-16" {
		t.Errorf("el tope son 60 días (2026-07-16); se pidió %+v", f.pedidas)
	}
	if !strings.Contains(reg.String(), "más antigua que el histórico") {
		t.Errorf("y se dice:\n%s", reg.String())
	}
	// Exactamente en el tope: llega a él, sin aviso.
	f.pedidas = nil
	b.abierta["STG"] = dia("2026-07-16")
	e, reg = montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
	_ = e.Ciclo(context.Background())
	if f.pedidas[0].desde != "2026-07-16" || strings.Contains(reg.String(), "más antigua que el histórico") {
		t.Errorf("una abierta justo en el tope entra entera y sin aviso: %+v\n%s", f.pedidas, reg.String())
	}
}

func TestElBarridoNoSeEnsanchaNiSeAcortaPorLaEntregaAbierta(t *testing.T) {
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{abierta: map[string]*time.Time{"STG": dia("2026-09-02")}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background()) // la primera vez es barrido
	if len(f.pedidas) != 1 || f.pedidas[0].desde != "2026-07-16" {
		t.Errorf("el barrido son los 60 días de siempre: %+v", f.pedidas)
	}
}

func TestUnRepasoParcialNoReescribeLaEntregaYElBarridoSi(t *testing.T) {
	// El conduce guardado es «100, 101» y esta respuesta sólo trae la 101: guardarla dejaría la
	// entrega con la mitad. En un repaso se deja y se DICE; el barrido, que ve todo, la rehace.
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: map[string][]FacturaDeVentra{"santiago": {
		factura("101", "2026-09-13", "2", "PED-1", cerveza(15), domicilio(0.29)),
	}}}
	b := &baseDeFacturasFalsa{conduces: map[string]string{"factura:STG:PED1": "100, 101"}}
	d := &repartoFalso{}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, d)
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy} // sólo repaso
	_ = e.Ciclo(context.Background())
	if len(d.lotes) != 0 {
		t.Fatalf("la entrega parcial NO se manda a la puerta: %+v", d.lotes)
	}
	if !strings.Contains(reg.String(), "entrega parcial: se espera al barrido") || !strings.Contains(reg.String(), "parciales=1") {
		t.Errorf("y se cuenta y se dice:\n%s", reg.String())
	}

	// Una entrega NUEVA o una que ya tiene todos sus números sí se guarda en el repaso (la pareja:
	// sin ella, «no reescribe lo parcial» se cumpliría con un repaso que no guarda nada).
	for nombre, guardado := range map[string]string{"nueva": "", "con todas": "101", "creció": "101"} {
		d = &repartoFalso{}
		b = &baseDeFacturasFalsa{conduces: map[string]string{}}
		if guardado != "" {
			b.conduces["factura:STG:PED1"] = guardado
		}
		e, reg = montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, d)
		e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
		_ = e.Ciclo(context.Background())
		if len(d.lotes) != 1 || strings.Contains(reg.String(), "entrega parcial") {
			t.Errorf("%s: se guarda en el repaso (%d lotes)\n%s", nombre, len(d.lotes), reg.String())
		}
	}

	// El barrido SÍ la rehace con lo que ve.
	d = &repartoFalso{}
	b = &baseDeFacturasFalsa{conduces: map[string]string{"factura:STG:PED1": "100, 101"}}
	e, reg = montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, d)
	_ = e.Ciclo(context.Background()) // la primera vez es barrido
	if len(d.lotes) != 1 || strings.Contains(reg.String(), "entrega parcial") {
		t.Errorf("el barrido es el único que puede encoger o rehacer una entrega: %d lotes\n%s", len(d.lotes), reg.String())
	}
}

func TestSiNoSePuedenLeerLosConducesElRepasoNoGuarda(t *testing.T) {
	// Sin saber qué tiene cada entrega no se puede asegurar que el repaso no la encoja.
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsaSinConduces{baseDeFacturasFalsa: &baseDeFacturasFalsa{}}
	d := &repartoFalso{}
	e, reg := montarFacturas(FuenteDeFactura, f, b.baseDeFacturasFalsa, &pedidoFalso{}, d)
	e.BaseF = b
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
	_ = e.Ciclo(context.Background())
	if len(d.lotes) != 0 || !strings.Contains(reg.String(), "no se pudieron leer los conduces guardados") {
		t.Errorf("sin poder leer los conduces el repaso no guarda y lo dice (%d lotes)\n%s", len(d.lotes), reg.String())
	}
}

type baseDeFacturasFalsaSinConduces struct{ *baseDeFacturasFalsa }

func (baseDeFacturasFalsaSinConduces) ConducesGuardados(context.Context, []string) (map[string]string, error) {
	return nil, errors.New("la base no contesta")
}

func TestUnaCantidadCeroSeDiceEnElCiclo(t *testing.T) {
	// f-cantidad-cero, el otro extremo: el ciclo avisa de los renglones que no cargó.
	cero := cerveza(0)
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: map[string][]FacturaDeVentra{"santiago": {
		factura("1", "2026-09-13", "2", "PED-1", cero, cerveza(4), domicilio(0.29)),
	}}}
	d := &repartoFalso{}
	e, reg := montarFacturas(FuenteDeFactura, f, &baseDeFacturasFalsa{}, &pedidoFalso{}, d)
	_ = e.Ciclo(context.Background())
	if !strings.Contains(reg.String(), "cantidad cero o negativa") {
		t.Errorf("el renglón sin cantidad se dice:\n%s", reg.String())
	}
	if len(d.lotes) != 1 || len(d.lotes[0][0].Items) != 1 {
		t.Errorf("y sólo el renglón con cantidad llega a la puerta: %+v", d.lotes)
	}
}

// ---------------------------------------------------------------------------
// Las opciones
// ---------------------------------------------------------------------------

func TestLaFuenteSeLeeYPorDefectoEsPedido(t *testing.T) {
	o, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k"}))
	if err != nil || o.Fuente != FuenteDePedido || o.LeeFactura() || !o.LeePedido() {
		t.Fatalf("por defecto SYNC_FUENTE=pedido y nada de Ventra: %+v %v", o, err)
	}
	for _, f := range []string{"factura", "AMBAS", " ambas "} {
		o, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_FUENTE": f,
			"WAREHOUSE_API_URL": "http://ventra.local/api/external-api/", "WAREHOUSE_API_TOKEN": "t",
			"VENTRA_BASES": "STG=santiago,hol=holguinmoa"}))
		if err != nil || !o.LeeFactura() {
			t.Errorf("%q tenía que cargar con la factura: %v", f, err)
		}
		if o.VentraURL != "http://ventra.local/api/external-api" || o.VentraBases["HOL"] != "holguinmoa" {
			t.Errorf("la URL pierde la barra final y las bases se leen: %+v", o)
		}
	}
	if o, _ := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_FUENTE": "factura",
		"WAREHOUSE_API_URL": "http://x", "WAREHOUSE_API_TOKEN": "t"})); o.LeePedido() {
		t.Error("factura sola no lee PEDIDO")
	}
}

func TestUnaFuenteQueNoSeEntiendeEsUnErrorYNoPedido(t *testing.T) {
	_, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_FUENTE": "facturas"}))
	if err == nil || !strings.Contains(err.Error(), "SYNC_FUENTE") {
		t.Fatalf("«facturas» (con plural) no puede leerse como el valor por defecto: %v", err)
	}
}

func TestLaFacturaSinVentraConfiguradoNoArranca(t *testing.T) {
	_, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_FUENTE": "ambas"}))
	if err == nil || !strings.Contains(err.Error(), "WAREHOUSE_API_URL") {
		t.Fatalf("sin la URL y el token de Ventra, ambas no puede arrancar: %v", err)
	}
	_, err = Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_FUENTE": "ambas",
		"WAREHOUSE_API_URL": "ventra.local", "WAREHOUSE_API_TOKEN": "t"}))
	if err == nil || !strings.Contains(err.Error(), "http://") {
		t.Fatalf("una URL sin esquema falla al arrancar y no dentro del ciclo: %v", err)
	}
	_, err = Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "VENTRA_BASES": "STG santiago"}))
	if err == nil {
		t.Fatal("un VENTRA_BASES mal escrito es un error, no se ignora")
	}
}

func TestSinFacturasConfiguradasCorrerSeNiega(t *testing.T) {
	e, _ := montarFacturas(FuenteAmbas, nil, nil, &pedidoFalso{}, &repartoFalso{})
	e.Facturas, e.BaseF = nil, nil
	if err := e.Correr(context.Background()); err == nil {
		t.Fatal("un espejo de facturas sin Ventra parecería sano sin traer una: no arranca")
	}
}

// ---------------------------------------------------------------------------
// El domicilio en $0 no es un domicilio (Amado y Jose, 21/10/2026)
// ---------------------------------------------------------------------------

func conUnoEnCero() map[string][]FacturaDeVentra {
	return map[string][]FacturaDeVentra{"santiago": {
		factura("47252", "2026-09-13", "2", "PED-1", cerveza(15), domicilio(0.29)),
		factura("47253", "2026-09-13", "2", "PED-2", cerveza(10), domicilio(0)),
	}}
}

func TestUnaFacturaConElDomicilioEnCeroNoSeGuarda(t *testing.T) {
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: conUnoEnCero()}
	d := &repartoFalso{}
	e, reg := montarFacturas(FuenteDeFactura, f, &baseDeFacturasFalsa{}, &pedidoFalso{}, d)
	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(d.lotes) != 1 || len(d.lotes[0]) != 1 || d.lotes[0][0].ID != "factura:STG:PED1" {
		t.Fatalf("sólo la del domicilio cobrado llega a la puerta; llegó %+v", d.lotes)
	}
	if !strings.Contains(reg.String(), "sinPrecioDeDomicilio=1") {
		t.Errorf("y se dice cuántas se dejaron fuera:\n%s", reg.String())
	}
}

// En pareja: la de domicilio cobrado SÍ se guarda (la prueba de arriba la comprueba) y la guardada que
// ahora va en $0 se retira sola si no va en ninguna ruta.
func TestLaEntregaGuardadaQueAhoraVaEnCeroSeRetiraSiNoVaEnRuta(t *testing.T) {
	enCero := EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:PED2"}
	cobrada := EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:PED1"}
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: conUnoEnCero()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {cobrada, enCero}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 1 || b.retiradas[0] != enCero.ID {
		t.Fatalf("se retira SOLO la de $0 (%v); retiradas: %v", enCero.ID, b.retiradas)
	}
}

func TestLaEntregaEnCeroQueYaVaEnUnaRutaSeDeja(t *testing.T) {
	enRuta := EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:PED2", Ocupada: true}
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: conUnoEnCero()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {enRuta}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 {
		t.Fatalf("lo que ya va en el camión no se borra aunque ahora cuente $0: %v", b.retiradas)
	}
}

func TestConDomicilioCobradoCuentaVariasFacturasDeLaMismaEntrega(t *testing.T) {
	// Dos facturas del mismo pedido: 0 y 0.35 suman 0.35 y la entrega SÍ cuenta; 0 y 0 no.
	juntas := AgruparPorFolio("STG", []FacturaDeVentra{
		factura("1", "2026-09-13", "2", "PED-A", cerveza(1), domicilio(0)),
		factura("2", "2026-09-13", "2", "PED-A", cerveza(1), domicilio(0.35)),
		factura("3", "2026-09-13", "2", "PED-B", cerveza(1), domicilio(0)),
		factura("4", "2026-09-13", "2", "PED-B", cerveza(1), domicilio(0)),
	})
	con, sin := ConDomicilioCobrado(juntas)
	if len(con) != 1 || sin != 1 || con[0].Folio != "PED-A" {
		t.Fatalf("PED-A cobra 0.35 (cuenta) y PED-B 0 (no): con=%d sin=%d", len(con), sin)
	}
}
