package api

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/store/sqlc"
)

// EL ALTA DEL ESPEJO. `/api/quote/batch` no es un cotizador: es la puerta de entrada de los
// pedidos, y no hay otra. Estuvo un tiempo contestando `persisted:false,
// reason:"espejo-no-montado"` — cotizaba bien y no guardaba nada, así que la base del
// reparto no tenía ni un pedido y desde fuera parecía que todo iba bien.

func textoDelAlta(v string) *string      { return &v }
func flotanteDelAlta(v float64) *float64 { return &v }

func pedidoArmado() PedidoParaGuardar {
	cuando := time.Date(2026, 9, 13, 18, 20, 0, 0, time.UTC)
	fecha := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)
	return PedidoParaGuardar{
		ExternalID:      textoDelAlta("ped-1"),
		Source:          "pedido",
		BranchID:        uuid.MustParse("11111111-1111-1111-1111-111111111111"),
		OperationNumber: textoDelAlta("X-2992"),
		CustomerName:    "Bodega La Esquina",
		Address:         "Calle 4",
		EndAddress:      textoDelAlta("Calle 4"),
		Lat:             20.02, Lng: -75.82, EndLat: 20.02, EndLng: -75.82,
		Weight:             120.5,
		DeliveryDistanceKm: 7.3,
		OrderDate:          &fecha,
		PedidoUpdatedAt:    &cuando,
		Estado:             textoDelAlta("completada"),
		Archivado:          true,
		// RequiereDomicilio se deja SIN PONER: es tri-estado —true, false, desconocido— y
		// «desconocido» es nil. Un false de más anularía el domicilio de un pedido que sí
		// lo lleva.
		PedidoCosto:      flotanteDelAlta(350),
		FacturaEstado:    textoDelAlta("igual"),
		FacturaNumero:    textoDelAlta("F-77"),
		FacturaDomicilio: flotanteDelAlta(350),
		Municipio:        textoDelAlta("Songo"),
		Vendedor:         textoDelAlta("V12"),
		SucursalCodigo:   textoDelAlta("STG"),
	}
}

func TestElAltaLlevaLaMarcaDeAgua(t *testing.T) {
	// SIN ESTO EL ESPEJO NO TIENE `since`: `pedido_updated_at` se queda nulo, la marca de
	// agua no existe nunca y cada ciclo vuelve a barrer el año entero.
	arg := paraLaBase(pedidoArmado())
	if !arg.PedidoUpdatedAt.Valid {
		t.Fatal("el alta tiene que escribir pedido_updated_at: es la marca de agua del espejo")
	}
	if !arg.PedidoUpdatedAt.Time.Equal(time.Date(2026, 9, 13, 18, 20, 0, 0, time.UTC)) {
		t.Errorf("la marca quedó en %v", arg.PedidoUpdatedAt.Time)
	}
}

func TestElAltaVaSiemprePorLaMismaPuerta(t *testing.T) {
	// `source` fijo a 'pedido' y `external_id` del pedido: es el par que hace idempotente
	// al espejo. Con `source` vacío, el `ON CONFLICT` no infiere nada y cada pasada crea
	// otra fila.
	arg := paraLaBase(pedidoArmado())
	if arg.Source == nil || *arg.Source != sqlc.ProcedenciaPedido {
		t.Fatalf("source tenía que ser 'pedido'; fue %v", arg.Source)
	}
	if arg.ExternalID == nil || *arg.ExternalID != "ped-1" {
		t.Fatalf("external_id tenía que ser el del pedido; fue %v", arg.ExternalID)
	}
}

func TestLasCuatroCoordenadasSonLaDelCliente(t *testing.T) {
	// §2.3: `lat/lng` y `end_lat/end_lng` se llenan los cuatro con la del cliente. El
	// armador exige `end_lat` no nulo, así que dejarlas a medias saca el pedido de todas
	// las rutas sin decir por qué.
	arg := paraLaBase(pedidoArmado())
	for nombre, v := range map[string]*float64{
		"lat": arg.Lat, "end_lat": arg.EndLat,
	} {
		if v == nil || *v != 20.02 {
			t.Errorf("%s salió %v", nombre, v)
		}
	}
	for nombre, v := range map[string]*float64{
		"lng": arg.Lng, "end_lng": arg.EndLng,
	} {
		if v == nil || *v != -75.82 {
			t.Errorf("%s salió %v", nombre, v)
		}
	}
}

func TestElPrecioDelRepartoNuncaSeEscribe(t *testing.T) {
	// El reparto ya no cotiza. Lo que se cobra es `pedido_costo`, que puso la APK de
	// Entrega. Un 0 en `delivery_price` se suma, se ordena y se lee como «gratis».
	arg := paraLaBase(pedidoArmado())
	if arg.DeliveryPrice != nil {
		t.Errorf("delivery_price tenía que ir nulo; fue %v", *arg.DeliveryPrice)
	}
	if arg.PedidoCosto == nil || *arg.PedidoCosto != 350 {
		t.Errorf("pedido_costo tenía que ser 350; fue %v", arg.PedidoCosto)
	}
}

func TestUnEstadoDesconocidoNoTumbaElPedido(t *testing.T) {
	// Postgres rechazaría la fila entera —y con ella el lote— por un estado nuevo que
	// alguien añadió en PEDIDO. Se guarda como NULL, que es la verdad, y el pedido entra.
	p := pedidoArmado()
	p.Estado = textoDelAlta("expirada")
	p.FacturaEstado = textoDelAlta("a medias")
	arg := paraLaBase(p)
	if arg.Estado != nil {
		t.Errorf("un estado que el enum no admite tenía que quedar nulo; quedó %v", *arg.Estado)
	}
	if arg.FacturaEstado != nil {
		t.Errorf("lo mismo con el de la factura; quedó %v", *arg.FacturaEstado)
	}

	// Y los buenos sí pasan.
	arg = paraLaBase(pedidoArmado())
	if arg.Estado == nil || *arg.Estado != sqlc.PedidoEstadoCompletada {
		t.Errorf("«completada» tenía que pasar; pasó %v", arg.Estado)
	}
	if arg.FacturaEstado == nil || *arg.FacturaEstado != sqlc.FacturaEstadoIgual {
		t.Errorf("«igual» tenía que pasar; pasó %v", arg.FacturaEstado)
	}
}

func TestLosRenglonesVanASuTablaYConservanElOrden(t *testing.T) {
	// Ya no son un JSON: van a `order_items`, una fila por línea. El orden es el del papel
	// del vendedor, que es como sale la hoja del despacho.
	renglones := []cotizar.RenglonPesado{
		{Renglon: cotizar.Renglon{Name: "Malta", Quantity: cotizar.De(24), Packs: cotizar.De(2)}},
		{Renglon: cotizar.Renglon{Description: "Refresco de cola", Quantity: cotizar.De(6)}},
	}
	filas := renglonesParaLaBase(renglones)
	if len(filas) != 2 {
		t.Fatalf("tenían que salir dos filas; salieron %d", len(filas))
	}
	if filas[0].Linea != 1 || filas[0].Description != "Malta" || filas[0].Quantity != 24 {
		t.Errorf("la primera fila salió %+v", filas[0])
	}
	if filas[0].Packs == nil || *filas[0].Packs != 2 {
		t.Errorf("los bultos tenían que llegar; llegaron %v", filas[0].Packs)
	}
	// Sin nombre se cae a la descripción: es lo que se busca en el despacho («¿qué pedidos
	// llevan malta?»), y con `productosTexto` eso era una copia a mano al lado del JSON.
	if filas[1].Linea != 2 || filas[1].Description != "Refresco de cola" {
		t.Errorf("la segunda fila salió %+v", filas[1])
	}
	// Sin bultos, la columna va nula: un 0 diría «cero cajas», que no es lo mismo que «la
	// factura no distingue cajas de unidades».
	if filas[1].Packs != nil {
		t.Errorf("sin bultos la columna va nula; fue %v", *filas[1].Packs)
	}
}

func TestUnaLineaSinTextoNoSeEscribeYDejaSuHueco(t *testing.T) {
	// `description` es obligatoria y una fila vacía no se puede ni buscar ni despachar. El
	// hueco en la numeración dice que allí venía algo que no se entendió.
	renglones := []cotizar.RenglonPesado{
		{Renglon: cotizar.Renglon{Name: "Malta"}},
		{Renglon: cotizar.Renglon{Name: "   "}},
		{Renglon: cotizar.Renglon{Name: "Agua"}},
	}
	filas := renglonesParaLaBase(renglones)
	if len(filas) != 2 {
		t.Fatalf("tenían que salir dos filas; salieron %d", len(filas))
	}
	if filas[1].Linea != 3 {
		t.Errorf("la última línea conserva su posición (3); salió %d", filas[1].Linea)
	}
}

// EL PESO DE CADA RENGLÓN SE GUARDA, QUE PARA ESO ESTÁ LA COLUMNA.
//
// `00004_peso_por_renglon.sql` añadió `peso_unitario_kg`, `peso_linea_kg`, `origen_peso`,
// `almacen_nombre` y `caso` precisamente para no recalcular el peso con el catálogo de HOY
// sobre un pedido de hace tres meses: el catálogo cambia —precios, envases, productos que
// salen— y un peso recalculado sobre una ruta vieja no es el peso con el que se cargó ese
// camión.
//
// Y estaban en NULL en los 7.515 renglones de producción, comprobado el 26/09/2026.
// `renglonesParaLaBase` escribía sólo cuatro campos y tiraba el resto, mientras un
// comentario de `orders.sql` afirmaba que los ponía. **Un comentario no falla.**
//
// No hay nada que calcular aquí: `cotizar.Resolver` ya lo devolvió. Sólo había que dejar
// de tirarlo, y esta prueba es lo que impide que se vuelva a caer.
func TestElPesoDeCadaRenglonSeGuarda(t *testing.T) {
	almacen := "Camagüey"
	filas := renglonesParaLaBase([]cotizar.RenglonPesado{{
		Renglon:      cotizar.Renglon{Name: "MALTA GUAJIRA 330 ML BLISTER 6U"},
		WeightKg:     24.194,
		UnitWeightKg: 2.4194,
		Matched:      true,
		WhName:       &almacen,
		WeightSource: cotizar.PesoDePedido,
	}})

	if len(filas) != 1 {
		t.Fatalf("renglones: %d", len(filas))
	}
	f := filas[0]
	if f.PesoLineaKg == nil || *f.PesoLineaKg != 24.194 {
		t.Fatalf(
			"el peso de la línea se tiró: sin él, dentro de tres meses el peso de esta "+
				"ruta se recalcula con el catálogo de entonces y no es el que se cargó. %v",
			f.PesoLineaKg,
		)
	}
	if f.PesoUnitarioKg == nil || *f.PesoUnitarioKg != 2.4194 {
		t.Fatalf("el peso por unidad de venta se tiró: %v", f.PesoUnitarioKg)
	}
	if f.OrigenPeso == nil || *f.OrigenPeso != string(cotizar.PesoDePedido) {
		t.Fatalf("no consta de dónde salió el peso: %v", f.OrigenPeso)
	}
	if f.AlmacenNombre == nil || *f.AlmacenNombre != almacen {
		t.Fatalf("no consta con qué almacén se emparejó: %v", f.AlmacenNombre)
	}
	if f.Caso == nil || !*f.Caso {
		t.Fatalf("no consta que se emparejó: %v", f.Caso)
	}
}

// LA OTRA MITAD: un renglón que no sabe lo que pesa se guarda VACÍO, no en cero.
//
// Un cero se lee como «este producto no pesa», que es un número creíble y equivocado — y
// con él se carga un camión. `origen_peso` SÍ se escribe aunque sea `none`: es el renglón
// confesando que lo intentó y no pudo, y es lo que la vista mira para pintar el «—».
func TestUnRenglonSinPesoSeGuardaVacioYNoEnCero(t *testing.T) {
	filas := renglonesParaLaBase([]cotizar.RenglonPesado{{
		Renglon:      cotizar.Renglon{Name: "PRODUCTO QUE NO ESTÁ EN EL CATÁLOGO"},
		WeightSource: cotizar.PesoDesconocido,
	}})

	f := filas[0]
	if f.PesoLineaKg != nil {
		t.Fatalf(
			"se guardó un peso de %v en un renglón que no lo sabe: un cero se lee como "+
				"«no pesa» y con eso se carga un camión", *f.PesoLineaKg,
		)
	}
	if f.OrigenPeso == nil || *f.OrigenPeso != string(cotizar.PesoDesconocido) {
		t.Fatalf(
			"no consta que se intentó y no se pudo: la vista necesita eso para pintar "+
				"el «—» en vez de un hueco. %v", f.OrigenPeso,
		)
	}
}

// EL APARATO YA NO TIENE RED DE SEGURIDAD: LO QUE NO SE RESUELVA AQUÍ, NO SE RESUELVE —
// 28/09/2026.
//
// Hasta ese día la misma cascada del peso estaba escrita TRES veces: aquí
// (`PesosDeRenglones`), en la ficha del pedido y en el pre-despacho. Los tres tenían que
// contestar lo mismo y no lo hacían —la ficha decía «40,0 kg» y la hoja del almacén ponía
// «—» sobre los mismos veinte empaques—, así que las dos del aparato se quitaron. Jose:
// «era mas facil ponerlo en el api y ya q lo consuman una cada uno».
//
// Lo que eso cambia, y es la razón de esta prueba: **antes, un renglón que llegaba con el
// peso del EMPAQUE y sin el de la línea lo salvaba el aparato multiplicando; ahora no lo
// salva nadie.** Si la cascada dejara de correr entre la puerta y `order_items`, la celda
// diría «—» en toda la flota y no fallaría ni una prueba de las de arriba, porque todas
// entran ya con `WeightKg` puesto a mano.
//
// Por eso ésta arranca en la forma CRUDA que manda PEDIDO y termina en la fila.
func TestElPesoSeResuelveAntesDeEscribirLaFila(t *testing.T) {
	// La forma de producción: `pesoKg` es lo que pesa UN empaque y vienen 12. `pesoLineaKg`
	// NO viene, que es el caso de los renglones que dejaban la hoja en blanco.
	crudos := []cotizar.Renglon{{
		Name:   "MALTA GUAJIRA 330 ML BLISTER 6U",
		PesoKg: cotizar.De(2),
		Packs:  cotizar.De(12),
	}}

	filas := renglonesParaLaBase(cotizar.PesosDeRenglones(crudos, nil).Renglones)
	if len(filas) != 1 {
		t.Fatalf("renglones: %d", len(filas))
	}
	if filas[0].PesoLineaKg == nil {
		t.Fatal(
			"la línea se guardó SIN peso teniendo con qué resolverlo (2 kg × 12 empaques). " +
				"El aparato ya no rehace esta cuenta: lo que salga vacío de aquí sale como " +
				"«—» en la ficha, en la hoja del almacén y en el papel, y el renglón entero " +
				"se va al contador de «sin peso»",
		)
	}
	if *filas[0].PesoLineaKg != 24 {
		t.Fatalf("2 kg × 12 empaques son 24, no %v", *filas[0].PesoLineaKg)
	}
	// Y de dónde salió, que es lo que la vista mira para distinguir «no pesa» de «no se sabe».
	if filas[0].OrigenPeso == nil || *filas[0].OrigenPeso != string(cotizar.PesoDePedido) {
		t.Fatalf("no consta de dónde salió el peso: %v", filas[0].OrigenPeso)
	}
}

// Y LA PAREJA, que es la que impide que la de arriba se «arregle» escribiendo siempre algo.
//
// Un renglón que de verdad no se puede pesar tiene que salir VACÍO y con `origen_peso` en
// `none`: es la única forma de que el aparato lo cuente en «sin peso» en vez de sumar un
// cero. Un aviso que sale siempre deja de leerse; un peso que sale siempre deja de ser un
// peso.
func TestUnRenglonQueNoSePuedePesarSaleVacioDeLaCascada(t *testing.T) {
	crudos := []cotizar.Renglon{{Name: "PRODUCTO SIN NADA"}}

	filas := renglonesParaLaBase(cotizar.PesosDeRenglones(crudos, nil).Renglones)
	if filas[0].PesoLineaKg != nil {
		t.Fatalf(
			"se inventó un peso de %v: un cero se suma y se lee como «no pesa», y con eso "+
				"se carga un camión", *filas[0].PesoLineaKg,
		)
	}
	if filas[0].OrigenPeso == nil || *filas[0].OrigenPeso != string(cotizar.PesoDesconocido) {
		t.Fatalf("no consta que se intentó y no se pudo: %v", filas[0].OrigenPeso)
	}
}
