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
	// anuladas: lo que se pidió quitar de su ruta (00027). `noSePuede` son las que el UPDATE real
	// rechazaría (ruta completada, resultado…): la base falsa no las devuelve.
	anuladas  []uuid.UUID
	noSePuede map[uuid.UUID]bool
	// deMenos: cuántas borra de menos el DELETE real respecto a las pedidas (la guarda repetida en el SQL).
	deMenos int
	fallo   error
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
func (b *baseDeFacturasFalsa) RetirarEntregasDeFactura(_ context.Context, ids []uuid.UUID) (int64, error) {
	b.retiradas = append(b.retiradas, ids...)
	return int64(len(ids) - b.deMenos), b.fallo
}

func (b *baseDeFacturasFalsa) AnularEntregasEnRuta(_ context.Context, ids []uuid.UUID) ([]EntregaAnulada, error) {
	b.anuladas = append(b.anuladas, ids...)
	var hechas []EntregaAnulada
	for _, id := range ids {
		if !b.noSePuede[id] {
			externo := ""
			for _, gs := range b.guardadas {
				for _, g := range gs {
					if g.ID == id {
						externo = g.ExternalID
					}
				}
			}
			hechas = append(hechas, EntregaAnulada{ID: id, ExternalID: externo, RutaID: uuid.New()})
		}
	}
	return hechas, b.fallo
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
	if len(d.lotes) != 1 || len(d.lotes[0]) != 1 || d.lotes[0][0].ID != "factura:STG:2:47252:2026-09-13" {
		t.Fatalf("la entrega tenía que llegar a la puerta como factura:STG:2:47252:2026-09-13; llegó %+v", d.lotes)
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
	return EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47252:2026-09-13"},
		EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47000:2026-09-13"},
		EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47001:2026-09-13", Ocupada: true}
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

func TestLaAnuladaQueVaEnUnaRutaVivaSeQuitaDeLaRutaYSeDice(t *testing.T) {
	_, _, enRuta := entregasGuardadas()
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {enRuta}}}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 {
		t.Fatalf("lo que ya está en el camión no se borra: %v", b.retiradas)
	}
	if len(b.anuladas) != 1 || b.anuladas[0] != enRuta.ID {
		t.Fatalf("se pide quitarla de su ruta y marcarla: %v", b.anuladas)
	}
	if !strings.Contains(reg.String(), "se quitó de su ruta") || !strings.Contains(reg.String(), "anuladasQuitadasDeRuta=1") ||
		!strings.Contains(reg.String(), "anuladasConRuta=0") {
		t.Errorf("se quita y SE DICE:\n%s", reg.String())
	}
}

// Si el UPDATE no la deja (ruta completada, resultado, entregada) la fila se queda como está y se cuenta.
func TestLaAnuladaQueElUpdateNoDejaQuitarSeDejaYSeCuenta(t *testing.T) {
	_, _, enRuta := entregasGuardadas()
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {enRuta}}, noSePuede: map[uuid.UUID]bool{enRuta.ID: true}}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 {
		t.Fatalf("lo que ya está en el camión no se borra: %v", b.retiradas)
	}
	if !strings.Contains(reg.String(), "historial") || !strings.Contains(reg.String(), "anuladasConRuta=1") ||
		!strings.Contains(reg.String(), "anuladasQuitadasDeRuta=0") {
		t.Errorf("se deja y SE DICE:\n%s", reg.String())
	}
}

func TestUnaRespuestaVaciaConEntregasEnLaBaseNoEsUnaAnulacion(t *testing.T) {
	// Una base de Ventra caída contesta lista vacía y SIN error. Tomarlo por «se anularon todas»
	// borraría la ventana entera de una sucursal. Es un ERROR y no se retira nada.
	viene, anulada, enRuta := entregasGuardadas()
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: map[string][]FacturaDeVentra{"santiago": {}}}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {viene, anulada, enRuta}}}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 || len(b.anuladas) != 0 {
		t.Fatalf("una respuesta vacía no retira NI QUITA DE SU RUTA nada: %v %v", b.retiradas, b.anuladas)
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
	viene, anulada, enRuta := entregasGuardadas()
	f := &facturasFalsas{
		bases:  map[string]string{"STG": "santiago"},
		fallos: map[string]error{"santiago": errors.New("Ventra 500")},
	}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {viene, anulada, enRuta}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 || len(b.ventanas) != 0 || len(b.anuladas) != 0 {
		t.Fatalf("un fallo no es una anulación: ni se mira la base (%v) ni se retira (%v)", b.ventanas, b.retiradas)
	}
}

func TestSoloSeJuzgaLaVentanaConsultada(t *testing.T) {
	// A la base se le pregunta por EXACTAMENTE la ventana que se le preguntó a Ventra. Una
	// entrega de hace 40 días no está en el repaso de 3: no se puede decir que «ya no viene».
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {{ID: uuid.New(), ExternalID: "factura:STG:2:1:2026-07-20"}}}}
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
// La entrega es una factura (Jose, 22/10/2026): la cancelada sale, la viva se queda
// ---------------------------------------------------------------------------

// El caso de Amado en Santiago: PWC26-261021-1128 con las facturas 47412 (cancelada) y 47415 (viva).
// Antes eran UNA entrega «47412, 47415» y el repaso nunca la encogía; ahora son dos filas y la
// cancelada, que Ventra ya no manda, se retira en el MISMO repaso (sin esperar al barrido).
func dosFacturasDelMismoPedido() (cancelada, viva EntregaGuardada, respuesta map[string][]FacturaDeVentra) {
	cancelada = EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47412:2026-09-13"}
	viva = EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47415:2026-09-13"}
	respuesta = map[string][]FacturaDeVentra{"santiago": {
		factura("47415", "2026-09-13", "2", "PWC26-261021-1128", cerveza(15), domicilio(0.29)),
	}}
	return
}

func TestLaFacturaCanceladaDeUnPedidoSeRetiraEnElMismoRepasoYLaVivaSeQueda(t *testing.T) {
	cancelada, viva, respuesta := dosFacturasDelMismoPedido()
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: respuesta}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {cancelada, viva}}}
	d := &repartoFalso{}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, d)
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy} // SOLO REPASO
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 1 || b.retiradas[0] != cancelada.ID {
		t.Fatalf("la cancelada (47412) se retira en el repaso y la viva no: retiradas %v (cancelada %v, viva %v)",
			b.retiradas, cancelada.ID, viva.ID)
	}
	if len(d.lotes) != 1 || len(d.lotes[0]) != 1 || d.lotes[0][0].ID != viva.ExternalID || d.lotes[0][0].Folio != "47415" {
		t.Errorf("y la viva se guarda con SU número como conduce: %+v", d.lotes)
	}
}

func TestLaCanceladaQueYaVaEnUnaRutaSeQuitaDeEllaAunqueLaVivaSiga(t *testing.T) {
	cancelada, viva, respuesta := dosFacturasDelMismoPedido()
	cancelada.Ocupada = true
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: respuesta}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {cancelada, viva}}}
	e, reg := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 || len(b.anuladas) != 1 || b.anuladas[0] != cancelada.ID || !strings.Contains(reg.String(), "anuladasQuitadasDeRuta=1") {
		t.Fatalf("la cancelada que va en una ruta se QUITA de ella (y la viva no); retiradas %v anuladas %v\n%s", b.retiradas, b.anuladas, reg.String())
	}
}

// El barrido y el repaso producen LO MISMO sobre lo que ambos ven: ya no hay una regla que sólo el
// barrido pueda cumplir (la vieja «el repaso nunca encoge»).
func TestElBarridoYElRepasoHacenLoMismo(t *testing.T) {
	for _, barrido := range []bool{false, true} {
		cancelada, viva, respuesta := dosFacturasDelMismoPedido()
		f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: respuesta}
		b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {cancelada, viva}}}
		d := &repartoFalso{}
		e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, d)
		if !barrido {
			e.ultimoBarridoDeFacturas = map[string]time.Time{"STG": hoy}
		}
		_ = e.Ciclo(context.Background())
		if len(b.retiradas) != 1 || b.retiradas[0] != cancelada.ID || len(d.lotes) != 1 || d.lotes[0][0].ID != viva.ExternalID {
			t.Errorf("barrido=%v: tenía que retirar la cancelada y guardar la viva; retiradas %v, lotes %+v", barrido, b.retiradas, d.lotes)
		}
	}
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
	if len(d.lotes) != 1 || len(d.lotes[0]) != 1 || d.lotes[0][0].ID != "factura:STG:2:47252:2026-09-13" {
		t.Fatalf("sólo la del domicilio cobrado llega a la puerta; llegó %+v", d.lotes)
	}
	if !strings.Contains(reg.String(), "sinPrecioDeDomicilio=1") {
		t.Errorf("y se dice cuántas se dejaron fuera:\n%s", reg.String())
	}
}

// En pareja: la de domicilio cobrado SÍ se guarda (la prueba de arriba la comprueba) y la guardada que
// ahora va en $0 se retira sola si no va en ninguna ruta.
func TestLaEntregaGuardadaQueAhoraVaEnCeroSeRetiraSiNoVaEnRuta(t *testing.T) {
	enCero := EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47253:2026-09-13"}
	cobrada := EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47252:2026-09-13"}
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: conUnoEnCero()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {cobrada, enCero}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 1 || b.retiradas[0] != enCero.ID {
		t.Fatalf("se retira SOLO la de $0 (%v); retiradas: %v", enCero.ID, b.retiradas)
	}
}

func TestLaEntregaEnCeroQueYaVaEnUnaRutaSeDeja(t *testing.T) {
	enRuta := EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47253:2026-09-13", Ocupada: true}
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: conUnoEnCero()}
	b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {enRuta}}}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	_ = e.Ciclo(context.Background())
	if len(b.retiradas) != 0 {
		t.Fatalf("lo que ya va en el camión no se borra aunque ahora cuente $0: %v", b.retiradas)
	}
}

func TestConDomicilioCobradoJuzgaCadaFacturaPorSi(t *testing.T) {
	// Dos facturas del mismo pedido son dos entregas: la de 0 se deja fuera y la de 0.35 entra, sin
	// que la una arrastre a la otra.
	todas := UnaEntregaPorFactura("STG", []FacturaDeVentra{
		factura("1", "2026-09-13", "2", "PED-A", cerveza(1), domicilio(0)),
		factura("2", "2026-09-13", "2", "PED-A", cerveza(1), domicilio(0.35)),
	})
	con, sin := ConDomicilioCobrado(todas)
	if len(con) != 1 || sin != 1 || con[0].Conduce() != "2" {
		t.Fatalf("la 2 cobra 0.35 (cuenta) y la 1 cobra 0 (no): con=%d sin=%d", len(con), sin)
	}
}

// EL GANCHO PARA AVISAR A PEDIDO: una vez por factura retirada o quitada de una ruta; nunca por una
// que se deja ni por las guardas que no retiran.
func TestElGanchoDeCanceladaSeLlamaUnaVezPorFacturaQueSale(t *testing.T) {
	viene, borrable, enRuta := entregasGuardadas()
	historial := EntregaGuardada{ID: uuid.New(), ExternalID: "factura:STG:2:47002:2026-09-13", Ocupada: true}
	f := &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: unaFacturaDeSantiago()}
	b := &baseDeFacturasFalsa{
		guardadas: map[string][]EntregaGuardada{"STG": {viene, borrable, enRuta, historial}},
		noSePuede: map[uuid.UUID]bool{historial.ID: true},
	}
	e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
	llamadas := map[string]int{}
	e.AvisarCancelada = func(_ context.Context, c EntregaCancelada) { llamadas[c.ExternalID]++ }
	_ = e.Ciclo(context.Background())
	if len(llamadas) != 2 || llamadas[borrable.ExternalID] != 1 || llamadas[enRuta.ExternalID] != 1 {
		t.Fatalf("una vez la borrada y una la quitada de su ruta; ni la que viene ni la de historial: %v", llamadas)
	}
}

func TestElGanchoDeCanceladaNoSeLlamaEnLasGuardasQueNoRetiran(t *testing.T) {
	viene, borrable, enRuta := entregasGuardadas()
	llamado := 0
	probar := func(nombre string, f *facturasFalsas) {
		b := &baseDeFacturasFalsa{guardadas: map[string][]EntregaGuardada{"STG": {viene, borrable, enRuta}}}
		e, _ := montarFacturas(FuenteDeFactura, f, b, &pedidoFalso{}, &repartoFalso{})
		e.AvisarCancelada = func(context.Context, EntregaCancelada) { llamado++ }
		_ = e.Ciclo(context.Background())
		if llamado != 0 {
			t.Fatalf("%s: no retira nada y no avisa de nada (%d avisos)", nombre, llamado)
		}
	}
	probar("respuesta vacía", &facturasFalsas{bases: map[string]string{"STG": "santiago"}, respuestas: map[string][]FacturaDeVentra{"santiago": {}}})
	probar("Ventra falla", &facturasFalsas{bases: map[string]string{"STG": "santiago"}, fallos: map[string]error{"santiago": errors.New("Ventra 500")}})
}
