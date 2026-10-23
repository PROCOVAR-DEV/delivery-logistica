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
//     ya no aparece (factura anulada) se retira si no va en ninguna ruta ni está entregada. Si va en
//     una ruta SIN COMPLETAR y sin resultado, se QUITA de la ruta y se MARCA como anulada (00027) para
//     que la app lo diga; en una ruta completada o con resultado se deja (historial) y se cuenta. Las
//     guardas están en [Espejo.retirarLoQueYaNoViene]. LA ENTREGA ES
//     UNA FACTURA (22/10/2026): lo que se compara es factura contra factura, así que la cancelada
//     sale en el MISMO repaso que deja de verla, sin esperar al barrido, y la viva no se toca.
//
// NO HAY SEGUNDA PUERTA: las entregas se arman como `PedidoDeFuera` y pasan por el mismo
// `guardar` → `ClienteDelivery.Cotizar` → `POST /api/quote/batch` que los pedidos de PEDIDO,
// con sus motivos de no entrar y su recuento.

import (
	"context"
	"sort"
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
		}
		guardadas, bien := e.facturasDeLaSucursal(ctx, codigo, bases[codigo], desde, hoy, de)
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

// facturasDeLaSucursal trae, guarda y, si procede, retira, para UNA sucursal y UNA ventana.
// `bien` es que la respuesta de Ventra y la lectura de la base fueron buenas (aunque no hubiera
// nada que guardar): es lo que permite dar por barrido el histórico.
func (e *Espejo) facturasDeLaSucursal(
	ctx context.Context, codigo, base string, desde, hasta time.Time, de string,
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
	entregas, sinPrecio := ConDomicilioCobrado(UnaEntregaPorFactura(codigo, facturas))

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
	pedidos := make([]PedidoDeFuera, 0, len(entregas))
	for _, en := range entregas {
		p, inf := en.APedido(ctxMapeo)
		resumen.sumar(inf)
		pedidos = append(pedidos, p)
	}
	if len(pedidos) > 0 {
		guardadas = e.guardar(ctx, pedidos, de+" facturas "+codigo+" "+ventana)
	}
	resumen.Guardadas = guardadas

	retiradas, anuladas, conRuta, retiroBien := e.retirarLoQueYaNoViene(ctx, codigo, desde, hasta, entregas, len(facturas))

	e.Reg.Info("facturas de Ventra",
		"de", de, "sucursal", codigo, "ventana", ventana,
		"facturas", resumen.Facturas, "entregas", resumen.Entregas, "guardadas", resumen.Guardadas,
		"puntoPorCodigo", resumen.PuntoPorCodigo, "puntoPorNombre", resumen.PuntoPorNombre,
		"sinPunto", resumen.SinPunto, "sinMercancia", resumen.SinMercancia,
		"retiradas", retiradas, "anuladasQuitadasDeRuta", anuladas, "anuladasConRuta", conRuta,
		"sinPrecioDeDomicilio", sinPrecio)
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

// EntregaCancelada es una factura que Ventra dejó de mandar y que el espejo retiró (borrada) o quitó de su
// ruta (archivada con `anulada_at`). `RutaID` es el cero si no iba en ninguna.
type EntregaCancelada struct {
	ID         uuid.UUID
	ExternalID string
	Sucursal   string
	RutaID     uuid.UUID
}

// avisarCancelada es el GANCHO para avisar a PEDIDO de que la factura se canceló: lo llama
// `retirarLoQueYaNoViene` UNA vez por factura retirada o quitada de una ruta, y NUNCA por una que se deja
// (historial, guardas). `AvisarCancelada` nil = no hace nada.
func (e *Espejo) avisarCancelada(ctx context.Context, c EntregaCancelada) {
	if e.AvisarCancelada != nil {
		e.AvisarCancelada(ctx, c)
	}
}

// retirarLoQueYaNoViene retira las entregas de factura que estaban dentro de la ventana y ya
// no aparecen en Ventra. Devuelve cuántas borró, cuántas quitó de su ruta y marcó como anuladas,
// cuántas dejó tal cual (historial), y si pudo compararlo con garantías.
//
// Se llama DESPUÉS de guardar: las filas antiguas (clave por folio) que tenían alguna de las facturas
// vivas ya han sido adoptadas por la clave nueva de la primera de ellas (`alcance.alFolio`) y cuentan
// como «vienen»; las antiguas SIN ninguna factura viva no están en `vienen` y salen por aquí: retiradas
// si no van en ruta, anuladas si van en una ruta viva.
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
//  4. LO QUE YA ESTÁ EN EL CAMIÓN NO SE BORRA NUNCA. Con ruta o con resultado no hay borrado: si la
//     ruta NO está completada y no hay resultado ni entrega, se QUITA de la ruta y se marca anulada
//     (la fila queda archivada: nadie la cuenta y la app puede avisar); en cualquier otro caso (ruta
//     completada, resultado, entregada) se deja como está y se cuenta, que es historial. Esa
//     distinción la hace el UPDATE (`AnularEntregasDeFacturaEnRuta`) y SÓLO él.
func (e *Espejo) retirarLoQueYaNoViene(
	ctx context.Context, codigo string, desde, hasta time.Time, entregas []EntregaDeFactura, nFacturas int,
) (retiradas, anuladas, conRuta int, bien bool) {
	guardadas, err := e.BaseF.EntregasDeFacturaEnVentana(ctx, codigo, desde, hasta)
	if err != nil {
		e.Reg.Error("no se pudieron leer las entregas de factura guardadas: no se retira nada",
			"sucursal", codigo, "err", err)
		return 0, 0, 0, false
	}
	if len(guardadas) == 0 {
		return 0, 0, 0, true
	}
	if nFacturas == 0 {
		e.Reg.Error("Ventra no devolvió ninguna factura de una ventana en la que la base tiene entregas: "+
			"se toma por un ERROR (una base caída contesta así) y NO se retira nada",
			"sucursal", codigo, "ventana", desde.Format(time.DateOnly)+".."+hasta.Format(time.DateOnly),
			"entregasEnLaBase", len(guardadas))
		return 0, 0, 0, false
	}

	vienen := make(map[string]bool, len(entregas))
	for _, en := range entregas {
		vienen[en.ExternalID()] = true
	}
	var quitar, ocupadas []uuid.UUID
	externas := make(map[uuid.UUID]string, len(guardadas))
	for _, g := range guardadas {
		if vienen[g.ExternalID] {
			continue
		}
		externas[g.ID] = g.ExternalID
		if g.Ocupada {
			ocupadas = append(ocupadas, g.ID)
			continue
		}
		quitar = append(quitar, g.ID)
	}
	if len(ocupadas) > 0 {
		hechas, err := e.BaseF.AnularEntregasEnRuta(ctx, ocupadas)
		if err != nil {
			e.Reg.Error("no se pudieron quitar de su ruta las entregas anuladas", "sucursal", codigo, "err", err)
			return 0, 0, len(ocupadas), false
		}
		anuladas = len(hechas)
		conRuta = len(ocupadas) - anuladas
		for _, h := range hechas {
			e.avisarCancelada(ctx, EntregaCancelada{ID: h.ID, ExternalID: h.ExternalID, Sucursal: codigo, RutaID: h.RutaID})
			e.Reg.Info("factura ANULADA en Ventra: se quitó de su ruta y se marcó como anulada",
				"sucursal", codigo, "externalId", h.ExternalID, "ruta", h.RutaID)
		}
		if conRuta > 0 {
			e.Reg.Warn("entregas de factura ANULADAS que ya van en una ruta completada o tienen resultado: se dejan (historial)",
				"sucursal", codigo, "entregas", conRuta)
		}
	}
	if len(quitar) > 0 {
		// SE AVISA ANTES DE BORRAR: el aviso a PEDIDO se arma leyendo la fila (su folio y su número de
		// factura), y después del DELETE ya no existe. Es seguro aunque el borrado falle o deje alguna:
		// la cancelación es un hecho de Ventra (la factura dejó de venir), el aviso es idempotente («cada
		// aviso lleva el estado completo») y el ciclo siguiente la volvería a avisar.
		for _, id := range quitar {
			e.avisarCancelada(ctx, EntregaCancelada{ID: id, ExternalID: externas[id], Sucursal: codigo})
		}
		n, err := e.BaseF.RetirarEntregasDeFactura(ctx, quitar)
		if err != nil {
			e.Reg.Error("no se pudieron retirar las entregas anuladas", "sucursal", codigo, "err", err)
			return 0, anuladas, conRuta, false
		}
		retiradas = int(n)
	}
	return retiradas, anuladas, conRuta, true
}

// CicloDeFacturas hace SOLO el paso de la factura de un ciclo y devuelve cuántas entregas
// guardó. Es lo que `Ciclo` llama cuando la fuente incluye la factura; está exportado para que
// la prueba contra Postgres de verdad pueda correr este paso sin el de PEDIDO ni el de los
// clientes (que borra los que no vienen: en una base de pruebas con clientes sembrados a mano
// los llevaría por delante).
func (e *Espejo) CicloDeFacturas(ctx context.Context) int { return e.facturas(ctx) }
