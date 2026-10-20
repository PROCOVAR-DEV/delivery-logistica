package espejo

// EL CICLO DE LA FACTURA (issue 20, Fase A): lo que hace el espejo con `SYNC_FUENTE=factura` o
// `ambas`, por cada sucursal que tiene base en Ventra.
//
//  1. REPASO: las facturas de los últimos `RepasoDias` días, en CADA ciclo. Ventra no avisa de
//     nada, así que esto es lo ÚNICO que trae una factura nueva; por eso el ciclo gira cada
//     minuto cuando la fuente incluye la factura (`Opciones.RitmoDelCiclo`).
//  2. BARRIDO: las de los últimos `HistoricoDias`, una vez al día y por sucursal. Es la red
//     de debajo del repaso, igual que el barrido de PEDIDO.
//  3. LO QUE YA NO VIENE: una entrega de factura que estaba dentro de la ventana consultada y
//     ya no aparece (factura anulada) se retira si no va en ninguna ruta ni está entregada. Con
//     ruta se deja y se dice. Las guardas están en [Espejo.retirarLoQueYaNoViene].
//
// NO HAY SEGUNDA PUERTA: las entregas se arman como `PedidoDeFuera` y pasan por el mismo
// `guardar` → `ClienteDelivery.Cotizar` → `POST /api/quote/batch` que los pedidos de PEDIDO,
// con sus motivos de no entrar y su recuento.

import (
	"context"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
)

// BarridoDeFacturasCada: cada cuánto se barre el histórico de facturas de una sucursal.
const BarridoDeFacturasCada = 24 * time.Hour

// zonaDeCuba: el huso fijo de Cuba (-05:00) con el que se decide «hoy» sin `tzdata` (la imagen del
// servicio no la lleva). En horario de verano (-04) entre las 00:00 y la 01:00 de Cuba «hoy» sale
// un día atrás durante esa hora; la ventana del repaso es de varios días, así que no se pierde nada.
var zonaDeCuba = time.FixedZone("CUBA", -5*3600)

// hoyEnCuba es el día de Cuba de `ahora`, a medianoche UTC (las ventanas son fechas sin hora).
func hoyEnCuba(ahora time.Time) time.Time {
	y, m, d := ahora.In(zonaDeCuba).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

// facturas es un ciclo de la fuente de facturas: todas las sucursales con base en Ventra.
func (e *Espejo) facturas(ctx context.Context) int {
	if e.Facturas == nil || e.BaseF == nil {
		e.Reg.Error("SYNC_FUENTE incluye la factura pero el espejo no tiene el lector de Ventra o su base: no se trae nada")
		return 0
	}
	bases, err := e.Facturas.Bases(ctx)
	if err != nil {
		// Sin saber qué base es de quién no se puede pedir nada, y NADA se retira: es un fallo, no
		// una anulación. El ciclo siguiente lo vuelve a intentar.
		e.Reg.Error("no se pudieron pedir las bases de Ventra: este ciclo no trae facturas", "err", err)
		return 0
	}
	codigos := make([]string, 0, len(bases))
	for c := range bases {
		codigos = append(codigos, c)
	}
	sort.Strings(codigos)

	ahora := e.Ahora()
	hoy := hoyEnCuba(ahora)
	if e.ultimoBarridoDeFacturas == nil {
		e.ultimoBarridoDeFacturas = map[string]time.Time{}
	}

	total := 0
	for _, codigo := range codigos {
		if ctx.Err() != nil {
			return total
		}
		// `SUCURSAL_CODIGO` limita al espejo a una sucursal, también aquí.
		if e.Opciones.SucursalCodigo != "" && codigo != e.Opciones.SucursalCodigo {
			continue
		}
		desde := hoy.AddDate(0, 0, -e.Opciones.RepasoDias)
		de := "repaso"
		barrer := ahora.Sub(e.ultimoBarridoDeFacturas[codigo]) >= BarridoDeFacturasCada
		if barrer {
			// El barrido incluye al repaso: una sola petición por sucursal y ciclo.
			desde = hoy.AddDate(0, 0, -e.Opciones.HistoricoDias)
			de = "histórico"
		} else {
			desde = e.repasoQueVeLasEntregasAbiertas(ctx, codigo, desde, hoy)
		}
		guardadas, bien := e.facturasDeLaSucursal(ctx, codigo, bases[codigo], desde, hoy, de, barrer)
		total += guardadas
		if barrer && bien {
			e.ultimoBarridoDeFacturas[codigo] = ahora
		}
		if err := e.dormir(ctx); err != nil {
			return total
		}
	}
	return total
}

// repasoQueVeLasEntregasAbiertas ensancha la ventana del repaso de una sucursal hasta la fecha de
// su entrega de factura ABIERTA (ni entregada ni cerrada) más antigua, con tope en `HistoricoDias`.
//
// POR QUÉ (auditoría del 20/10/2026, G2): una entrega reúne las facturas de un folio, y la fecha
// de la entrega es la de la MÁS ANTIGUA. Con un folio de la factura 100 del 10/10 y la 101 del
// 19/10, el repaso de tres días sólo veía la 101 y reescribía la entrega con ella sola (conduce
// «101», peso a la mitad); el barrido diario la dejaba bien y el repaso siguiente la volvía a
// romper. Mirar atrás hasta la entrega abierta más vieja hace que el repaso vea TODAS las facturas
// de todo lo que todavía se puede repartir. Lo cerrado no hace falta verlo, y si de todos modos
// llegara partido lo frena [Espejo.entregasQueEncogerian].
func (e *Espejo) repasoQueVeLasEntregasAbiertas(ctx context.Context, codigo string, desde, hoy time.Time) time.Time {
	abierta, err := e.BaseF.FechaDeLaEntregaAbiertaMasAntigua(ctx, codigo)
	if err != nil {
		// No es motivo para no repasar: la guarda de no encoger sigue puesta.
		e.Reg.Warn("no se pudo leer la entrega de factura abierta más antigua: el repaso usa su ventana normal",
			"sucursal", codigo, "err", err)
		return desde
	}
	if abierta == nil || !abierta.Before(desde) {
		return desde
	}
	y, m, d := abierta.Date()
	mas := time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
	if tope := hoy.AddDate(0, 0, -e.Opciones.HistoricoDias); mas.Before(tope) {
		e.Reg.Warn("hay una entrega de factura abierta más antigua que el histórico: el repaso llega sólo hasta el tope",
			"sucursal", codigo, "abierta", mas.Format(time.DateOnly), "tope", tope.Format(time.DateOnly))
		mas = tope
	}
	return mas
}

// entregasQueEncogerian devuelve los `external_id` de las entregas cuyo conduce guardado tiene
// números de factura que en esta respuesta NO vinieron: guardarlas las dejaría con una parte de
// sus facturas (conduce, peso y packs a la mitad). Se dejan como están; sólo el barrido, que ve
// todo el histórico, puede encoger o rehacer una entrega. Si no se puede leer lo guardado, se
// devuelve el error y quien llama no guarda nada de este repaso.
func (e *Espejo) entregasQueEncogerian(ctx context.Context, entregas []EntregaDeFactura) (map[string]bool, error) {
	ids := make([]string, 0, len(entregas))
	for _, en := range entregas {
		ids = append(ids, en.ExternalID())
	}
	guardados, err := e.BaseF.ConducesGuardados(ctx, ids)
	if err != nil {
		return nil, err
	}
	parciales := map[string]bool{}
	for _, en := range entregas {
		viejo, hay := guardados[en.ExternalID()]
		if !hay {
			continue
		}
		vienen := map[string]bool{}
		for _, f := range en.Facturas {
			vienen[f.Numero] = true
		}
		for _, n := range strings.Split(viejo, ",") {
			if n = strings.TrimSpace(n); n != "" && !vienen[n] {
				parciales[en.ExternalID()] = true
				break
			}
		}
	}
	return parciales, nil
}

// facturasDeLaSucursal trae, guarda y, si procede, retira, para UNA sucursal y UNA ventana.
// `bien` es que la respuesta de Ventra y la lectura de la base fueron buenas (aunque no hubiera
// nada que guardar): es lo que permite dar por barrido el histórico.
func (e *Espejo) facturasDeLaSucursal(
	ctx context.Context, codigo, base string, desde, hasta time.Time, de string, barrido bool,
) (guardadas int, bien bool) {
	ventana := desde.Format(time.DateOnly) + ".." + hasta.Format(time.DateOnly)
	facturas, err := e.Facturas.FacturasConDomicilio(ctx, base, desde, hasta, SkusDeDomicilio)
	if err != nil {
		// UNA SUCURSAL QUE FALLA NO TUMBA A LAS OTRAS, y NO RETIRA NADA: lo que no se pudo ver no
		// se da por anulado.
		e.Reg.Warn("las facturas de Ventra fallaron: no se guarda ni se retira nada de esta sucursal",
			"de", de, "sucursal", codigo, "base", base, "ventana", ventana, "err", err)
		return 0, false
	}
	entregas := AgruparPorFolio(codigo, facturas)

	// Lo que hace falta de la base para armar y pesar. Si no se puede leer, esta sucursal espera
	// al ciclo siguiente: guardar sin los puntos borraría las coordenadas de lo ya guardado, y
	// sin los pesos dejaría las entregas "sin peso" por un fallo de la base y no del producto.
	var ctxMapeo ContextoDeMapeo
	if len(entregas) > 0 {
		puntos, err := e.BaseF.PuntosDeClientes(ctx, codigo)
		if err != nil {
			e.Reg.Error("no se pudieron leer los clientes para ponerle punto a las facturas: se espera al ciclo siguiente",
				"sucursal", codigo, "err", err)
			return 0, false
		}
		productos, err := e.BaseF.ProductosDeVentra(ctx, codigo)
		if err != nil {
			e.Reg.Error("no se pudieron leer los productos para pesar las facturas: se espera al ciclo siguiente",
				"sucursal", codigo, "err", err)
			return 0, false
		}
		ctxMapeo = ContextoDeMapeo{Puntos: NuevosPuntos(puntos), Productos: productos}
	}

	var resumen ResumenDeFacturas
	resumen.Facturas, resumen.Entregas = len(facturas), len(entregas)
	// EL REPASO NUNCA ENCOGE UNA ENTREGA (G2): si una entrega ya guardada tiene facturas que esta
	// respuesta no trae, la parcial no la reescribe. El barrido, que sí lo ve todo, es el único que
	// puede encoger o rehacer una entrega.
	var parciales map[string]bool
	if !barrido && len(entregas) > 0 {
		var err error
		if parciales, err = e.entregasQueEncogerian(ctx, entregas); err != nil {
			e.Reg.Error("no se pudieron leer los conduces guardados: este repaso no guarda nada de esta sucursal",
				"sucursal", codigo, "err", err)
			return 0, false
		}
	}
	pedidos := make([]PedidoDeFuera, 0, len(entregas))
	for _, en := range entregas {
		p, inf := en.APedido(ctxMapeo)
		resumen.sumar(inf)
		if parciales[en.ExternalID()] {
			resumen.Parciales++
			continue
		}
		pedidos = append(pedidos, p)
	}
	if len(pedidos) > 0 {
		guardadas = e.guardar(ctx, pedidos, de+" facturas "+codigo+" "+ventana)
	}
	resumen.Guardadas = guardadas

	retiradas, conRuta, retiroBien := e.retirarLoQueYaNoViene(ctx, codigo, desde, hasta, entregas, len(facturas))

	e.Reg.Info("facturas de Ventra",
		"de", de, "sucursal", codigo, "ventana", ventana,
		"facturas", resumen.Facturas, "entregas", resumen.Entregas, "guardadas", resumen.Guardadas,
		"puntoPorCodigo", resumen.PuntoPorCodigo, "puntoPorNombre", resumen.PuntoPorNombre,
		"sinPunto", resumen.SinPunto, "sinMercancia", resumen.SinMercancia,
		"retiradas", retiradas, "anuladasConRuta", conRuta, "parciales", resumen.Parciales)
	if resumen.Parciales > 0 {
		e.Reg.Warn("entrega parcial: se espera al barrido. Este repaso trae MENOS facturas de las que la entrega ya tiene; "+
			"no se reescribe con la parcial y el barrido diario (que ve todo el histórico) la rehace",
			"sucursal", codigo, "ventana", ventana, "entregas", resumen.Parciales)
	}
	// LO QUE NO SE PUDO RESOLVER SE DICE, no se esconde. Cada cifra tiene su arreglo y su dueño:
	// el punto lo pone el logístico a mano (o se corrige el cliente en PEDIDO), el peso lo pone
	// quien mantiene el catálogo de Ventra.
	if resumen.SinPunto > 0 {
		e.Reg.Warn("entregas de factura SIN coordenadas: se guardan igual y se ubican a mano (PUT /api/orders/{id}/punto) "+
			"o corrigiendo el cliente en PEDIDO",
			"sucursal", codigo, "sinPunto", resumen.SinPunto, "dudosas", resumen.PuntoAmbiguo)
	}
	if len(resumen.ProductosSinPeso) > 0 || len(resumen.ProductosFueraDelCatalogo) > 0 {
		e.Reg.Warn("productos de factura SIN peso: cuentan como «sin peso» hasta que el catálogo de Ventra lo tenga",
			"sucursal", codigo,
			"conPesoCero", codigosOrdenados(resumen.ProductosSinPeso),
			"fueraDelCatalogo", codigosOrdenados(resumen.ProductosFueraDelCatalogo),
			"entregasAfectadas", resumen.ConProductosSinPeso)
	}
	if resumen.SinMercancia > 0 {
		e.Reg.Info("entregas de factura con SOLO la línea de domicilio (sin mercancía): se guardan igual",
			"sucursal", codigo, "entregas", resumen.SinMercancia)
	}
	if resumen.LineasSinCantidad > 0 {
		e.Reg.Warn("renglones de factura con cantidad cero o negativa: no se cargan",
			"sucursal", codigo, "renglones", resumen.LineasSinCantidad)
	}
	return guardadas, retiroBien
}

// retirarLoQueYaNoViene retira las entregas de factura que estaban dentro de la ventana y ya
// no aparecen en Ventra. Devuelve cuántas retiró, cuántas dejó por llevar ruta, y si pudo
// compararlo con garantías.
//
// LAS GUARDAS, TODAS OBLIGATORIAS, y cada una tiene su prueba contra Postgres de verdad:
//
//  1. SOLO SE JUZGA LO QUE SE PREGUNTÓ. La consulta trae únicamente las entregas de factura de
//     esa sucursal cuyo día de factura cae en [desde, hasta]; fuera de la ventana no se toca nada.
//  2. UN VACÍO NO ES UNA ANULACIÓN. Si Ventra no devolvió ni una factura y en la base hay entregas
//     de esa ventana, eso es un ERROR (una base caída contesta así, sin error), no que se hayan
//     anulado todas. Es el mismo principio que el catálogo vacío (CLAUDE.md §3).
//  3. LA RESPUESTA TIENE QUE HABER SIDO BUENA: esta función sólo se llama si
//     `FacturasConDomicilio` no falló, y esa devuelve todo o error.
//  4. LO QUE YA VA EN UNA RUTA O TIENE RESULTADO NO SE BORRA: se deja y se cuenta como «anulada
//     con ruta», para que una persona decida. Lo que ya está en el camión no se desvanece.
func (e *Espejo) retirarLoQueYaNoViene(
	ctx context.Context, codigo string, desde, hasta time.Time, entregas []EntregaDeFactura, nFacturas int,
) (retiradas, conRuta int, bien bool) {
	guardadas, err := e.BaseF.EntregasDeFacturaEnVentana(ctx, codigo, desde, hasta)
	if err != nil {
		e.Reg.Error("no se pudieron leer las entregas de factura guardadas: no se retira nada",
			"sucursal", codigo, "err", err)
		return 0, 0, false
	}
	if len(guardadas) == 0 {
		return 0, 0, true
	}
	if nFacturas == 0 {
		e.Reg.Error("Ventra no devolvió ninguna factura de una ventana en la que la base tiene entregas: "+
			"se toma por un ERROR (una base caída contesta así) y NO se retira nada",
			"sucursal", codigo, "ventana", desde.Format(time.DateOnly)+".."+hasta.Format(time.DateOnly),
			"entregasEnLaBase", len(guardadas))
		return 0, 0, false
	}

	vienen := make(map[string]bool, len(entregas))
	for _, en := range entregas {
		vienen[en.ExternalID()] = true
	}
	var quitar []uuid.UUID
	var conRutaIDs []string
	for _, g := range guardadas {
		if vienen[g.ExternalID] {
			continue
		}
		if g.Ocupada {
			conRuta++
			conRutaIDs = append(conRutaIDs, g.ExternalID)
			continue
		}
		quitar = append(quitar, g.ID)
	}
	if conRuta > 0 {
		e.Reg.Warn("entregas de factura ANULADAS que ya van en una ruta o tienen resultado: se dejan",
			"sucursal", codigo, "entregas", conRuta, "externalIds", codigosOrdenados(contar(conRutaIDs)))
	}
	if len(quitar) > 0 {
		n, err := e.BaseF.RetirarEntregasDeFactura(ctx, quitar)
		if err != nil {
			e.Reg.Error("no se pudieron retirar las entregas anuladas", "sucursal", codigo, "err", err)
			return 0, conRuta, false
		}
		retiradas = int(n)
	}
	return retiradas, conRuta, true
}

func contar(xs []string) map[string]int {
	m := map[string]int{}
	for _, x := range xs {
		m[x]++
	}
	return m
}

// CicloDeFacturas hace SOLO el paso de la factura de un ciclo y devuelve cuántas entregas
// guardó. Es lo que `Ciclo` llama cuando la fuente incluye la factura; está exportado para que
// la prueba contra Postgres de verdad pueda correr este paso sin el de PEDIDO ni el de los
// clientes (que borra los que no vienen: en una base de pruebas con clientes sembrados a mano
// los llevaría por delante).
func (e *Espejo) CicloDeFacturas(ctx context.Context) int { return e.facturas(ctx) }
