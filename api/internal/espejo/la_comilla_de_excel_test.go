package espejo

import "testing"

// LA COMILLA DE EXCEL, EN PAREJA: la que se quita y la que NO se toca.
//
// La segunda mitad es la que importa y la que se olvida. «Quítale la comilla del principio»
// cumplido a lo bruto rompe `'t Hooft` y cualquier nombre que empiece por apóstrofo, y un
// nombre de cliente roto es un pedido que el chofer no encuentra.
func TestLaComillaDeExcelSeQuitaSoloDelanteDeUnNumero(t *testing.T) {
	casos := []struct {
		entra  string
		quiere string
		porQue string
	}{
		// --- se quita
		{`'+53 5 2675220`, `+53 5 2675220`,
			"es el teléfono que Jose vio el 28/09/2026 en el cajón de mover un pedido"},
		{`'52675220`, `52675220`, "un móvil sin prefijo"},
		{`'0012`, `0012`,
			"un folio con ceros delante: la comilla es justo lo que Excel pone para no comérselos"},
		{`'2026-09-28`, `2026-09-28`, "una columna de fechas exportada a CSV"},
		{`'(22) 62-1234`, `(22) 62-1234`, "un fijo con paréntesis"},
		{`'  52675220  `, `52675220`, "la comilla con espacios pegados detrás"},

		// --- NO se toca
		{`'t Hooft`, `'t Hooft`,
			"hay apellidos que empiezan por apóstrofo, y ahí la comilla es el nombre"},
		{`O'Brien`, `O'Brien`, "la comilla no va delante: no es la de Excel"},
		{`'`, `'`, "sin nada detrás no hay número que rescatar"},
		{`'   `, `'   `, "lo mismo con espacios"},
		{`'PV-STGO`, `'PV-STGO`,
			"tiene letras, así que no es un número: pudiera ser un nombre y no se adivina"},
		{`'2026-09-28T15:03:00Z`, `'2026-09-28T15:03:00Z`,
			"la T y la Z son letras: queda fuera A PROPÓSITO, ensanchar la regla para colar " +
				"dos letras concretas es el primer paso para que acabe tocando nombres"},
		{`+53 5 2675220`, `+53 5 2675220`, "el caso normal, sin comilla: no se toca nada"},
		{``, ``, "vacío"},
	}

	for _, c := range casos {
		if hay := SinLaComillaDeExcel(c.entra); hay != c.quiere {
			t.Errorf("SinLaComillaDeExcel(%q) = %q y tenía que dar %q\n  por qué: %s",
				c.entra, hay, c.quiere, c.porQue)
		}
	}
}

// Y LA MISMA LIMPIEZA EN EL EMBUDO DEL ESPEJO. `textoONada` es por donde pasa TODO el texto
// que el espejo copia de PEDIDO, así que si la limpieza no está ahí no está en ninguno de
// los campos de golpe.
func TestElEspejoNoCopiaLaComillaDeExcel(t *testing.T) {
	p := pedidoCompleto()
	p.Telefono = `'+53 5 2675220`
	p.Folio = `'0012`
	p.FacturaNumero = `'77`
	p.Direccion = `'53 esquina 12`
	p.Cliente.Municipio = `'Songo`

	o := ArmarLote([]PedidoDeFuera{p}).Orders[0]

	if o.Phone == nil || *o.Phone != `+53 5 2675220` {
		t.Errorf("phone = %s: la comilla de Excel llegó al cuerpo del lote", textoDelPtr(o.Phone))
	}
	if o.OperationNumber != `0012` {
		t.Errorf("operationNumber = %q: el folio viaja con la comilla y los ceros "+
			"delante son justo lo que hay que conservar", o.OperationNumber)
	}
	if o.FacturaNumero == nil || *o.FacturaNumero != `77` {
		t.Errorf("facturaNumero = %s: el número de factura viaja con la comilla",
			textoDelPtr(o.FacturaNumero))
	}
	// Y LO QUE TIENE LETRAS NO SE TOCA: ni la dirección ni el municipio, porque ahí la
	// comilla podría ser el dato. Se comprueba para que quede escrito que esto NO es
	// «quítale la comilla a todo» — es lo que protege los nombres de cliente.
	if o.Address == nil || *o.Address != `'53 esquina 12` {
		t.Errorf("address = %s: tiene letras, así que no es un número y no se toca",
			textoDelPtr(o.Address))
	}
	if o.Municipio == nil || *o.Municipio != `'Songo` {
		t.Errorf("municipio = %s: un texto con letras no se toca, que es lo que "+
			"protege los nombres de cliente", textoDelPtr(o.Municipio))
	}

	// LA IDENTIDAD NO SE LIMPIA. Si llegara sucia, llegaría sucia siempre y casaría consigo
	// misma; limpiarla ahora partiría cada fila ya guardada en dos.
	p2 := pedidoCompleto()
	p2.ID = `'123`
	if got := ArmarLote([]PedidoDeFuera{p2}).Orders[0].ExternalID; got != `'123` {
		t.Errorf("externalId = %q: la identidad NO se limpia, y el porqué está en "+
			"SinLaComillaDeExcel", got)
	}
}

func textoDelPtr(s *string) string {
	if s == nil {
		return "<nil>"
	}
	return `"` + *s + `"`
}
