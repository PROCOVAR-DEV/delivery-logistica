package api

// «CAMBIADO» TAMBIÉN ES UNA FACTURA, y creerse lo contrario congeló un tercio del espejo.
//
// EL INCIDENTE, del 28/09/2026 y localizado entre dos sesiones a lo largo de la tarde:
//
// Jose miraba la hoja de pre-despacho y había productos con la columna `kg` en blanco. Al
// contarlo salían 81 renglones sin peso. Se barrió el espejo TRES veces —reposicionando
// incluso el cursor del histórico, que llevaba en el día 213 con una ventana de 60— y el
// número no se movía: 81 antes y 81 después, **producto por producto idénticos**.
//
// La sesión de PEDIDO demostró, con cuatro folios concretos y por cuatro caminos distintos
// —por id, por rango de fechas, con el filtro `soloRepartibles` puesto y corriendo su
// propio serializador—, que ella servía esos pedidos CON el peso dentro. Así que la pérdida
// estaba entre la respuesta y la escritura.
//
// Y la pista que lo cerró no fue el peso: fue que `factura_estado` TAMBIÉN llegaba distinto
// —PEDIDO decía `cambiado`, la copia del reparto seguía en `igual`—. O sea que no se perdía
// un campo: **la fila entera no se reescribía**. Estaba aquí, en el punto 4 del filtro del
// lote:
//
//	facturaIgual := p.FacturaEstado != nil && *p.FacturaEstado == "igual"
//	if sinDomicilio && !facturaIgual { → se descarta }
//
// `igual` a secas. Pero cotejada son DOS estados, `igual` y `cambiado`, y así está escrito
// en todo el resto del proyecto —el armador de rutas, el panel, el pre-despacho— y en el
// propio `soloRepartibles` de PEDIDO. `cambiado` quiere decir que la factura existe y
// difiere del pedido, no que no haya factura.
//
// El ciclo completo del fallo, con un pedido de MOSTRADOR:
//
//  1. entra en el espejo el día que su factura está en `igual`;
//  2. PEDIDO la coteja más tarde y la pasa a `cambiado`;
//  3. desde ese momento TODOS los barridos lo tiran, y su fila se queda congelada con lo
//     que hubiera el primer día — el peso, la factura y lo que venga después.
//
// Son ~3.300 de los 5.480 pedidos del reparto: los que se recogen en el almacén, que no van
// a domicilio pero cuya mercancía hay que sacar igual.
//
// Y encima el aviso MENTÍA: `sin-domicilio-y-sin-factura` sobre pedidos que tienen factura.
// Quien leyera el log iba a buscar donde no era.

import "testing"

func siNo(v bool) *bool         { return &v }
func estadoDe(s string) *string { return &s }

// LA TABLA ENTERA, porque lo que falló fue un caso de cuatro y no la idea.
func TestCuandoUnPedidoDeMostradorSeDescarta(t *testing.T) {
	casos := []struct {
		nombre     string
		domicilio  *bool
		factura    *string
		seDescarta bool
		porque     string
	}{
		{
			nombre:    "mostrador con la factura CAMBIADA se queda",
			domicilio: siNo(false), factura: estadoDe("cambiado"), seDescarta: false,
			porque: "ES EL FALLO DEL 28/09/2026: «cambiado» es una factura que existe y " +
				"difiere, no la ausencia de factura. Descartarlo congela la fila del " +
				"pedido para siempre, porque el barrido vuelve a tirarlo cada vez",
		},
		{
			nombre:    "mostrador con la factura IGUAL se queda",
			domicilio: siNo(false), factura: estadoDe("igual"), seDescarta: false,
			porque: "es el caso que ya funcionaba y no se puede perder al arreglar el otro",
		},
		{
			nombre:    "mostrador SIN factura se descarta",
			domicilio: siNo(false), factura: estadoDe("sin_factura"), seDescarta: true,
			porque: "no va a salir en ningún camión y ocupa sitio en la lista del logístico",
		},
		{
			nombre:    "mostrador sin cotejar todavía se descarta",
			domicilio: siNo(false), factura: nil, seDescarta: true,
			porque: "nulo es «nadie la ha cotejado», que todavía no es una factura",
		},
		{
			nombre:    "CON domicilio entra siempre, tenga la factura que tenga",
			domicilio: siNo(true), factura: nil, seDescarta: false,
			porque: "este filtro es sólo para los de mostrador; un pedido a domicilio se " +
				"reparte aunque la factura no esté todavía",
		},
		{
			nombre:    "sin marcar el domicilio entra: nulo NO es mostrador",
			domicilio: nil, factura: estadoDe("sin_factura"), seDescarta: false,
			porque: "`requiereDomicilio` es tri-estado y nil es «nadie lo ha marcado». " +
				"Descartar por lo que no se sabe es descartar de verdad",
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			hubo := esMostradorSinFactura(c.domicilio, c.factura)
			if hubo != c.seDescarta {
				verbo := "se descartó"
				if !hubo {
					verbo = "NO se descartó"
				}
				t.Fatalf("%s, y no tocaba: %s", verbo, c.porque)
			}
		})
	}
}

// Y LOS DOS ESTADOS, sueltos. Es la pregunta que se escribía a mano en cada sitio y por eso
// se pudo escribir mal en uno.
func TestLaFacturaCotejadaSonDosEstadosYNoUno(t *testing.T) {
	if !facturaCotejada(estadoDe("igual")) {
		t.Error("«igual» es una factura cotejada")
	}
	if !facturaCotejada(estadoDe("cambiado")) {
		t.Error("«cambiado» TAMBIÉN es una factura cotejada: existe y difiere del pedido. " +
			"Es el par `IN ('igual','cambiado')` que usa el resto del proyecto")
	}
	if facturaCotejada(estadoDe("sin_factura")) {
		t.Error("«sin_factura» no es una factura")
	}
	if facturaCotejada(nil) {
		t.Error("nulo es «nadie la ha cotejado todavía», no una factura")
	}
}
