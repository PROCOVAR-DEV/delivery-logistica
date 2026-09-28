package api

import (
	"fmt"
	"testing"
)

// LA PUERTA TAMBIÉN LIMPIA LA COMILLA DE EXCEL — 28/09/2026.
//
// El 28/09/2026, en un SM-A165M, el cajón de mover un pedido del tablero enseñaba el
// teléfono del cliente como `'+53 5 2675220`. La comilla la pone Excel delante de un número
// para que no lo convierta, y venía pegada al dato desde el maestro de PEDIDO.
//
// `internal/espejo` la quita en su `textoONada`, y aquí se comprueba la OTRA capa: lo que
// entra por `POST /api/quote/batch`. Hacen falta las dos, porque por la puerta entra también
// lo que empuja el canal firmado de PEDIDO, que no pasa por el espejo — si sólo estuviera en
// el espejo, la mitad de los pedidos seguirían entrando sucios y nadie lo vería, que es
// exactamente el modo de fallo del §3-bis.
//
// Se entra por la puerta de verdad y se mira LO QUE SE ESCRIBE: el `PedidoParaGuardar` que
// recibe el espejo es la fila, así que la comprobación es sobre el dato guardado y no sobre
// una función auxiliar.
func TestLaPuertaNoGuardaLaComillaDeExcel(t *testing.T) {
	cuerpo := fmt.Sprintf(`{"orders":[{
		"externalId":"'ped-1","operationNumber":"'0012","sucursalExternalId":"STG",
		"customerName":"Bodega La Esquina","address":"Calle 4",
		"phone":"'+53 5 2675220","facturaNumero":"'77","vendedor":"'12",
		"lat":%v,"lng":%v,"requiereDomicilio":true,
		"items":[{"code":"PARR0004","name":"Malta","quantity":120,"packs":20,"pesoLineaKg":24}]
	}]}`, latCliente, lngCliente)

	_, escrito := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(), cuerpo)

	if escrito.CustomerPhone == nil || *escrito.CustomerPhone != "+53 5 2675220" {
		t.Errorf("customer_phone = %s y tenía que ser %q\n"+
			"  es el dato que salía en la pantalla del 28/09/2026, con la comilla delante",
			textoDelPuntero(escrito.CustomerPhone), "+53 5 2675220")
	}
	if escrito.OperationNumber == nil || *escrito.OperationNumber != "0012" {
		t.Errorf("operation_number = %s y tenía que ser %q: el folio es un rótulo que "+
			"alguien lee y compara, y los ceros de delante son justo lo que hay que conservar",
			textoDelPuntero(escrito.OperationNumber), "0012")
	}
	if escrito.FacturaNumero == nil || *escrito.FacturaNumero != "77" {
		t.Errorf("factura_numero = %s y tenía que ser %q",
			textoDelPuntero(escrito.FacturaNumero), "77")
	}
	if escrito.Vendedor == nil || *escrito.Vendedor != "12" {
		t.Errorf("vendedor = %s y tenía que ser %q",
			textoDelPuntero(escrito.Vendedor), "12")
	}

	// LA IDENTIDAD SE GUARDA TAL CUAL, con comilla y todo. No es un descuido: si el
	// `externalId` llega sucio llega sucio SIEMPRE, y casa consigo mismo en cada upsert.
	// Limpiarlo aquí partiría en dos cada pedido ya guardado —el viejo con comilla, el nuevo
	// sin ella— y lo duplicaría. El porqué entero está en `espejo.SinLaComillaDeExcel`.
	if escrito.ExternalID == nil || *escrito.ExternalID != "'ped-1" {
		t.Errorf("external_id = %s: la identidad NO se limpia",
			textoDelPuntero(escrito.ExternalID))
	}
}

// Y LA PAREJA: un pedido limpio no cambia al pasar por la puerta.
//
// Sin esta mitad, «quítale la comilla» se cumple con una limpieza que recorta el primer
// carácter de todo, y nadie se enteraría hasta que un teléfono perdiera su `+`.
func TestUnPedidoLimpioPasaLaPuertaSinTocarse(t *testing.T) {
	cuerpo := fmt.Sprintf(`{"orders":[{
		"externalId":"ped-1","operationNumber":"X-2992","sucursalExternalId":"STG",
		"customerName":"O'Brien y Hermanos","address":"Calle 4",
		"phone":"+53 5 2675220","facturaNumero":"F-77",
		"lat":%v,"lng":%v,"requiereDomicilio":true,
		"items":[{"code":"PARR0004","name":"Malta","quantity":120,"packs":20,"pesoLineaKg":24}]
	}]}`, latCliente, lngCliente)

	_, escrito := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(), cuerpo)

	if escrito.CustomerPhone == nil || *escrito.CustomerPhone != "+53 5 2675220" {
		t.Errorf("customer_phone = %s: un teléfono sin comilla tiene que llegar entero, "+
			"con su +", textoDelPuntero(escrito.CustomerPhone))
	}
	if escrito.OperationNumber == nil || *escrito.OperationNumber != "X-2992" {
		t.Errorf("operation_number = %s: el folio no se toca",
			textoDelPuntero(escrito.OperationNumber))
	}
	// EL APÓSTROFO DE UN NOMBRE DE VERDAD SE QUEDA. Es la mitad conservadora de la regla:
	// hay apellidos con apóstrofo, y un nombre roto es un pedido que el chofer no encuentra.
	if escrito.CustomerName != "O'Brien y Hermanos" {
		t.Errorf("customer_name = %q: el apóstrofo de un nombre de verdad no se toca",
			escrito.CustomerName)
	}
}
