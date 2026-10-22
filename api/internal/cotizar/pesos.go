package cotizar

// RESOLUCIÓN DEL PESO (§2.1 y §2.2 de reglas-negocio.md).
//
// El peso es la otra mitad del importe del domicilio (tarifa × distancia × PESO) y es
// además lo que decide si la carga cabe en el camión. Equivocarlo no revienta nada: da un
// número creíble y se descubre en la caja o en el muelle.

// FuentePeso dice de dónde salió el peso de la línea. Viaja hasta la pantalla para que se
// pueda ver qué pedidos llevan peso de verdad y cuáles van a ojo.
type FuentePeso string

const (
	PesoDePedido    FuentePeso = "pedido"   // lo mandó PEDIDO, ya cruzado contra Ventra
	PesoManual      FuentePeso = "manual"   // lo escribió una persona en la línea
	PesoDeCatalogo  FuentePeso = "catalogo" // respaldo: el catálogo local de pesos
	PesoDesconocido FuentePeso = "none"     // no se pudo resolver; la línea vale 0
)

// Renglon es la línea que llega en el cuerpo (`QuoteItem`).
//
// POR QUÉ LLEGAN `PesoKg` Y `PesoLineaKg` A LA VEZ, que parece redundante: mandar sólo uno
// obliga a acordarse de multiplicar por `Packs`, y el día que se olvide *el domicilio sale
// dividido entre veinticuatro sin que falle nada*.
type Renglon struct {
	Description string `json:"description"`
	Name        string `json:"name"`
	SKU         string `json:"sku"`
	Code        string `json:"code"`
	Weight      Numero `json:"weight"`      // peso manual POR UNIDAD
	Quantity    Numero `json:"quantity"`    // unidades sueltas
	Packs       Numero `json:"packs"`       // unidades de venta: blísters, cajas
	PesoKg      Numero `json:"pesoKg"`      // de PEDIDO, por unidad de venta
	PesoLineaKg Numero `json:"pesoLineaKg"` // de PEDIDO, la línea entera

	// DE QUÉ ALMACÉN SALE ESTA LÍNEA. No entra en la cascada del peso ni la toca: viaja
	// pegada al renglón porque `RenglonPesado` la incrusta, y de ahí va a `order_items`.
	//
	// NO CONFUNDIR CON `RenglonPesado.WhName`, que está dos structs más abajo y se llama
	// «wh» por warehouse: eso es el nombre del PRODUCTO con el que casó el catálogo local de
	// pesos y por eso se escribe en `order_items.almacen_nombre`. La columna lleva ese nombre
	// desde la 00004 y el comentario de aquella migración ya lo decía mal. El almacén de
	// verdad va en `almacen_salida_*` (00012).
	AlmacenCodigo string `json:"almacenCodigo"`
	AlmacenNombre string `json:"almacenNombre"`

	// DE QUÉ FACTURA DE VENTRA SALE ESTA LÍNEA (00026, issue 22 de Maikel). Sólo la manda el
	// espejo de facturas; viaja pegada al renglón como el almacén y va a
	// `order_items.factura_numero`. Vacío = no se sabe (PEDIDO no la trae).
	FacturaNumero string `json:"facturaNumero"`
}

// RenglonPesado es la línea con el peso ya resuelto.
type RenglonPesado struct {
	Renglon
	WeightKg     float64    `json:"weightKg"`     // peso de la LÍNEA entera
	UnitWeightKg float64    `json:"unitWeightKg"` // por unidad de venta; informativo
	Matched      bool       `json:"matched"`
	WhName       *string    `json:"whName"`
	WeightSource FuentePeso `json:"weightSource"`
}

// Acierto es lo que devuelve el catálogo local al emparejar un producto.
type Acierto struct {
	WeightKg float64
	WhName   *string
}

// Catalogo es el respaldo: el catálogo local de pesos (§5, `productMatch.ts`).
//
// Es una interfaz y no una estructura porque aquí sólo interesa el resultado del
// emparejamiento; el emparejamiento en sí (normalización, Damerau ≤ 1, candidata única)
// es otro asunto y otro fichero. Nil significa «no hay catálogo», que es el caso normal:
// sólo se baja cuando alguna línea del lote no trae peso de PEDIDO.
type Catalogo interface {
	// Resolver recibe el nombre y el código (`sku || code`) y devuelve el acierto.
	// Un acierto con WeightKg <= 0 es «no lo encontré».
	Resolver(nombre, codigo string) Acierto
}

// PesosResueltos es lo que sale de la cascada.
type PesosResueltos struct {
	Total     float64
	Renglones []RenglonPesado
}

// PesosDeRenglones es `computeItemsWeights`.
//
// CASCADA DE PRIORIDAD, EN ESTE ORDEN EXACTO — la primera que aplica gana:
//
//  1. `pesoLineaKg` de PEDIDO (la línea entera, ya multiplicada allá).
//  2. `pesoKg` de PEDIDO × cantidad, y SÓLO si el producto da > 0.
//  3. `weight` manual × cantidad (aquí el respaldo de cantidad es 1, no 0).
//  4. El catálogo local × packs.
//  5. Nada: la línea vale 0 y se marca como no resuelta.
//
// POR QUÉ PEDIDO VA PRIMERO Y EL CATÁLOGO DETRÁS: PEDIDO ya cruza cada línea contra Ventra
// —con los vínculos que ató una persona cuando el nombre no se parecía— y manda el
// resultado. Volver a cruzarlo aquí contra un catálogo propio es tener el mismo dato dos
// veces y descubrir tarde que no coinciden: *el domicilio se cobra por un peso que no es
// el nuestro.* El catálogo local queda como respaldo para pedidos antiguos y para el día
// que PEDIDO no traiga peso.
func PesosDeRenglones(renglones []Renglon, catalogo Catalogo) PesosResueltos {
	// Caso límite de entrada: sin líneas, total 0 y lista VACÍA (no nil: es un `[]`).
	if len(renglones) == 0 {
		return PesosResueltos{Total: 0, Renglones: []RenglonPesado{}}
	}

	salida := make([]RenglonPesado, 0, len(renglones))
	total := 0.0

	for _, r := range renglones {
		p := RenglonPesado{Renglon: r, WeightSource: PesoDesconocido}

		switch {
		// --- 1. La línea entera, tal como la mandó PEDIDO ---------------------
		case r.PesoLineaKg.Positivo():
			p.WeightKg = r.PesoLineaKg.Valor
			// El unitario es informativo: si no viene, 0. No se deduce dividiendo por
			// packs, porque `pesoLineaKg` puede incluir cosas que el unitario no tiene.
			if r.PesoKg.Positivo() {
				p.UnitWeightKg = r.PesoKg.Valor
			}
			p.Matched = true
			p.WeightSource = PesoDePedido
			total += p.WeightKg

		// --- 2. El unitario de PEDIDO por la cantidad -------------------------
		case r.PesoKg.Positivo() && pesoDeLinea(r) > 0:
			// SÓLO se acepta si la multiplicación da > 0. Si no hay ni `packs` ni
			// `quantity`, la línea daría 0 y NO se devuelve 0: se sigue cayendo a la
			// rama siguiente. Un 0 aquí se lee como «este producto no pesa».
			p.WeightKg = pesoDeLinea(r)
			p.UnitWeightKg = r.PesoKg.Valor
			p.Matched = true
			p.WeightSource = PesoDePedido
			total += p.WeightKg

		// --- 3. El peso escrito a mano ----------------------------------------
		case r.Weight.O(0) > 0:
			// OJO: aquí el respaldo de la cantidad es 1, no 0. Es distinto de la rama
			// anterior a propósito: un peso tecleado sin cantidad es «una unidad», no
			// «ninguna». Está así en la de Next y se conserva.
			p.WeightKg = r.Weight.O(0) * r.Quantity.O(1)
			p.UnitWeightKg = r.Weight.O(0)
			p.Matched = true
			p.WeightSource = PesoManual
			total += p.WeightKg

		// --- 4. El catálogo local, como respaldo ------------------------------
		case catalogo != nil && catalogo.Resolver(r.Name, primeroNoVacio(r.SKU, r.Code)).WeightKg > 0:
			hit := catalogo.Resolver(r.Name, primeroNoVacio(r.SKU, r.Code))
			packs := r.Packs.O(0)
			// Si `packs` es 0 la línea vale 0 y AUN ASÍ se marca como emparejada: el
			// producto se reconoció, lo que falta es cuántos van. Distinguirlo importa
			// para el informe de «productos sin peso», que si no acusaría al catálogo
			// de un fallo que es del pedido.
			p.WeightKg = hit.WeightKg * packs
			p.UnitWeightKg = hit.WeightKg
			p.Matched = true
			p.WhName = hit.WhName
			p.WeightSource = PesoDeCatalogo
			total += p.WeightKg

		// --- 5. Nada ----------------------------------------------------------
		default:
			p.WeightKg = 0
			p.UnitWeightKg = 0
			p.Matched = false
			p.WhName = nil
			p.WeightSource = PesoDesconocido
		}

		salida = append(salida, p)
	}

	return PesosResueltos{Total: total, Renglones: salida}
}

// pesoDeLinea es la rama 2: `pesoKg × (packs > 0 ? packs : (quantity || 0))`.
func pesoDeLinea(r Renglon) float64 {
	cantidad := r.Quantity.O(0)
	if r.Packs.O(0) > 0 {
		cantidad = r.Packs.O(0)
	}
	return r.PesoKg.Valor * cantidad
}

// PesoDeRenglones es `weightFromItems(items, fallback, catalog)`.
//
// UN TOTAL DE 0 SE CONSIDERA «NO RESUELTO» Y CEDE AL RESPALDO. No es lo mismo que un
// pedido que de verdad no pesa nada: eso no existe. Si de las líneas no sale peso, vale
// más el número que trajo el propio pedido, aunque sea aproximado, que un cero que luego
// dice que en el camión cabe todo.
func PesoDeRenglones(renglones []Renglon, respaldo Numero, catalogo Catalogo) float64 {
	if len(renglones) == 0 {
		return respaldo.O(0)
	}
	total := PesosDeRenglones(renglones, catalogo).Total
	if total > 0 {
		return total
	}
	return respaldo.O(0)
}

func primeroNoVacio(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
