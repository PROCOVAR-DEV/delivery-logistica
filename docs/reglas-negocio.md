# Reglas de negocio de `delivery` (para reimplementar en Go)

Fuente: `/mnt/datos/Work/procovar/delivery/src/lib/*.ts` y `src/app/api/routes/route.ts`.
Todo importe se guarda en **USD**; el CUP es derivado. Todo peso en **kg**, distancia en **km**.

---

## 1. `pricing.ts` — geometría del recorrido (ya NO calcula precios)

**Decisión de fondo (conservar):** este fichero tenía CUATRO fórmulas de precio y sólo una se
usaba. `calculateOrderPrice` (base + km + kg), `calculateShareDeliveryPrice` (fracción de peso de
la carga) y `computeRoutePricing` (reparto por tramos) no las llamaba nadie: restos de tres
intentos distintos de cobrar el reparto. `calculateDomicilioOficial` (C = CKK × D × PP) sí se
usaba, pero era la SEGUNDA fórmula viva: **el mismo pedido costaba una cosa entrando por el espejo
y otra entrando a mano**. Se borraron todas.

> **El precio del domicilio lo pone la APK de Entrega y nadie más. Aquí no se calcula: se muestra.**

Lo único que queda es geometría, porque eso sí es de delivery: es lo que arma el recorrido del camión.

### 1.1 `haversineDistance(lat1, lon1, lat2, lon2) -> km`
- Constante: `R = 6371` (radio terrestre en km).
- `dLat = (lat2-lat1)·π/180`, `dLon = (lon2-lon1)·π/180`
- `a = sin²(dLat/2) + cos(lat1·π/180)·cos(lat2·π/180)·sin²(dLon/2)`
- `c = 2·atan2(√a, √(1−a))`
- **Devuelve `R·c`. Sin redondeo.** (Ojo: la variante de `domicilioEntrega.ts` sí redondea al
  exponerla; aquí no. Son la misma fórmula, distinto redondeo de salida.)

### 1.2 `greedyRouteOptimization(origin, stops[]) -> string[]` (orden de visita)
- Entra: origen `{lat,lng}` y paradas `{id,lat,lng}`. Sale: array de `id` en orden de visita.
- **Casos límite explícitos:** `stops.length === 0` → `[]`; `stops.length === 1` → `[stops[0].id]`.
- Algoritmo: **vecino más próximo (greedy)**, sin 2-opt ni nada posterior.
  - `current = origin`; mientras queden no visitadas: se recorre la lista, se calcula
    `haversineDistance(current, candidata)` y se toma el **mínimo estricto** (`dist < nearestDist`,
    inicializado a `Infinity`, `nearestIdx = 0`).
  - **Desempate: gana el PRIMERO de la lista** (comparación estricta `<`, no `<=`). En Go hay que
    conservar esto o el orden de paradas cambia ante distancias iguales.
  - La elegida se **saca** de la lista (`splice`) y pasa a ser `current`.
- No cierra el circuito: el regreso al origen no forma parte del orden (lo suma quien lo llame).

### 1.2-bis Aquí NOS SEPARAMOS del patrón: el greedy no es el orden final (21/09/2026)

Lo de §1.2 se conserva entero —es el punto de partida y la vara de medir— pero **no es lo que
sale por la pantalla**. Jose, viendo una ruta planificada: «esa planificada está mal, no hace
ruta lógica ni nada». Y no estaba rota: el vecino más próximo se come los clientes cercanos,
deja los lejanos sueltos, cruza el recorrido consigo mismo y remata con un viaje entero de
vuelta al almacén.

Encima del greedy van ahora **2-opt y Or-opt (mover 1, 2 o 3 paradas seguidas) sobre el
circuito CERRADO** —almacén → paradas → almacén, que es lo que mide `totalDistance`—, hasta que
no mejore o hasta 50 pasadas. En los casos reales del fichero de abajo baja un 17% los km de un
reparto de doce paradas por La Habana y un 5% los de ocho pueblos de provincia.

Tres cosas que no se negocian, y las tres están atadas con pruebas:

- **El epsilon.** Las mejoras se comparan contra `-1e-9` km, nunca contra `0` a secas: dos
  recorridos iguales se «mejoran» el uno al otro en el último bit y el bucle no termina igual en
  Dart que en Go.
- **El desempate sigue siendo el de §1.2** (`<` estricto, gana el primero de la lista), y las
  pasadas se aplican siempre en el mismo orden (2-opt entera y después Or-opt entera), quedándose
  con la PRIMERA mejora que aparece y no con la mejor.
- **El almacén no es una parada**: es el nodo de los dos extremos, así que el camión siempre sale
  de él.

Se calcula en los dos sitios (`app/lib/pantallas/rutas/datos/geo.dart` y
`api/internal/api/rutas.go`, las dos `ordenDeVisita`) porque la ruta se arma en el patio sin
señal, y los dos tienen que dar EXACTAMENTE el mismo orden. Lo ata
`docs/orden-de-paradas.casos.json`, que leen `app/test/pantallas/rutas/geo_test.dart` y
`api/internal/api/orden_de_paradas_test.go`.

### 1.3 `calculateRouteSegments(origin, orderedStops[]) -> number[]`
- Distancias **consecutivas** `origen→p1, p1→p2, p2→p3…`, una por parada, en el orden dado.
- Uso: sólo para `totalDistance` de la ruta (km reales del camión). No se cobra con esto.

### 1.4 Tipo `HomeDeliveryQuote`
- Campos: `distanceKm`, `chargeableKm`, `weightKg`, `price: number|null`,
  `breakdown {base, distance, weight, beforeMin: number|null, beforeRound: number|null}`.
- **Regla dura de `price`: `null` NO es cero.** Un cero es un precio: se suma, se ordena y se lee
  como «este domicilio es gratis». `null` = no se pudo estimar aquí. Ocurre cuando la sucursal no
  tiene vehículo de referencia o no tiene tasa. El pedido se guarda igual; **lo que se cobra es
  `pedidoCosto` (el costo puesto en PEDIDO), no éste.**

---

## 2. `homeDeliveryQuote.ts` — resolución de PESO y armado del `Order`

`computeOrderQuote` (base + km + kg) fue eliminado junto con `/api/quote`: era la segunda fórmula
que hacía que el mismo pedido costara dos cosas distintas.

### 2.1 `computeItemsWeights(items, catalog?) -> { total, items: WeightedItem[] }`

**Entrada por ítem** (`QuoteItem`): `description`, `name`, `sku`, `code`, `weight`, `quantity`,
`packs` (nº de unidades de venta: blísters/cajas), `pesoKg` (por unidad de venta),
`pesoLineaKg` (línea entera).

**Por qué llegan `pesoKg` y `pesoLineaKg` a la vez:** mandar sólo uno obliga a acordarse de
multiplicar por `packs`, y el día que se olvide *el domicilio sale dividido entre veinticuatro sin
que falle nada*.

**Salida por ítem** (`WeightedItem`): `weightKg` (peso de la LÍNEA), `unitWeightKg` (por pack,
informativo), `matched`, `whName`, `weightSource ∈ {'pedido','manual','catalogo','none'}`.

**Caso límite de entrada:** si `items` no es array o está vacío → `{ total: 0, items: [] }`.

**Cascada de prioridad, en este orden exacto (la primera que aplica gana):**

1. **`pesoLineaKg` de PEDIDO** — si `Number(pesoLineaKg)` es finito y `> 0`:
   `weightKg = pesoLineaKg`; `unitWeightKg = pesoKg` si es finito y `>0`, si no `0`;
   `matched=true`, `whName=null`, `weightSource='pedido'`.
2. **`pesoKg` de PEDIDO × cantidad** — si `Number(pesoKg)` finito y `>0`:
   `cantidad = packs > 0 ? packs : (quantity || 0)`; `linea = pesoKg × cantidad`.
   **Sólo se acepta si `linea > 0`**; si da 0 (sin packs ni quantity) **se sigue cayendo** a la
   rama siguiente, no se devuelve 0. `weightSource='pedido'`.
3. **`weight` manual** — si `Number(weight) || 0` es `> 0`:
   `linea = weight × (quantity || 1)` — ojo, aquí el fallback de cantidad es **1**, no 0.
   `weightSource='manual'`.
4. **Catálogo local** (si se pasó `catalog`): `hit = catalog.resolve(name, sku || code)`.
   Si `hit.weightKg > 0`: `packs = Number(packs) || 0`; `linea = hit.weightKg × packs`
   (**si `packs` es 0, la línea vale 0 pero igualmente se marca `matched=true`** con
   `weightSource='catalogo'` y `whName = hit.whName`).
5. **Nada** → `weightKg: 0, unitWeightKg: 0, matched: false, whName: null, weightSource: 'none'`.

`total` es la suma de las líneas efectivamente sumadas (las ramas 1–4; la 5 aporta 0).

**POR QUÉ PEDIDO va primero y el catálogo detrás:** PEDIDO ya cruza cada línea contra Ventra —con
los vínculos que ató una persona cuando el nombre no se parecía— y manda el resultado. Volver a
cruzarlo aquí contra un catálogo propio es **tener el mismo dato dos veces y descubrir tarde que no
coinciden: el domicilio se cobra por un peso que no es el nuestro.** El catálogo local queda como
respaldo para pedidos antiguos y para el día que PEDIDO no traiga peso.

**Y ESTA CASCADA SE CORRE UNA SOLA VEZ, AQUÍ — 28/09/2026.** Estuvo escrita tres veces: en
`api/internal/cotizar/pesos.go`, en la ficha del pedido y en el pre-despacho de la aplicación. Los
tres tenían que contestar lo mismo y no lo hacían —la ficha decía «40,0 kg» y la hoja del almacén
ponía «—» sobre los mismos veinte empaques—. El resultado se escribe en `order_items.peso_linea_kg`
con `origen_peso` al lado, viaja en `pesoLineaKg` y **la aplicación lo LEE**: no rehace la cuenta ni
consulta su catálogo. Lo único que repite es la regla del cero —vacío o `<= 0` es «no se sabe», no
«no pesa»—, y eso se ata con
`app/test/pantallas/pedidos/el_peso_del_pre_despacho_cambia_de_sucursal_test.dart`.

Corolario, y es lo que cambia al operar: **lo que no se resuelva aquí ya no lo salva nadie.** Un
renglón que se escriba sin `peso_linea_kg` sale como «—» en la ficha, en la hoja del almacén y en el
papel, y entra entero en el contador de «sin peso». Lo vigila
`TestElPesoSeResuelveAntesDeEscribirLaFila` en `api/internal/api/cotizacion_alta_test.go`.

### 2.2 `weightFromItems(items, fallback, catalog?) -> number`
- Si `items` no es array o está vacío → `fallback || 0`.
- Si no → `total` de `computeItemsWeights`, **salvo que `total` no sea `> 0`**, en cuyo caso
  `fallback || 0`. Es decir: un total de 0 se considera «no resuelto» y cede al fallback.

### 2.3 `buildOrderData(input, branch, computed) -> data del Order`
Reglas que no son mapeo trivial:
- `address = input.address || input.customerName` (nunca vacío); `endAddress = input.address || null`.
- `lat/lng` y `endLat/endLng` se llenan los cuatro con `input.lat/lng`.
- `weight = computed.weightKg`. **0 = sin peso resuelto**, y así entra al generador de rutas
  (capacidad del camión).
- `items`: se guarda `computed.items` (con el peso ya resuelto por producto) si tiene elementos;
  si no, `input.items`; si no, `[]`.
- `productosTexto`: copia EN TEXTO de los nombres (`name ?? description ?? ''`), filtrando vacíos,
  unidos con `' · '`; si queda vacío → `null`.
  **POR QUÉ:** dentro de un JSON no se puede buscar sin leerse los cincuenta mil pedidos; es la
  pregunta del despacho («¿qué pedidos llevan malta?»).
- **`deliveryPrice = (input.requiereDomicilio === false) ? null : computed.quote.price`.**
  Comparación **estricta con `false`**: `undefined`/`null` NO anulan el precio. Un pedido sin
  domicilio se importa igual (hace falta para rutas y capacidad) pero **con precio NULL, no 0 ni la
  base**.
- `orderDate = new Date(input.orderDate)` o `null`.
  **POR QUÉ existe separado de `createdAt`:** `createdAt` es cuándo lo copió el espejo. Filtrar el
  día del armador de rutas por `createdAt` daba **cero** cualquier día que no fuera hoy: el espejo
  trae quince días de una vez y todos nacen con la fecha de hoy.
- Fechas convertidas con `new Date(...)` si vienen, si no `null`: `pedidoUpdatedAt`,
  `fechaComprometida`, `facturaAt`, `facturaCorregidoAt`.
- `archivado = (input.archivado === true)` (estricto → por defecto `false`).
- `requiereDomicilio = input.requiereDomicilio ?? null` (tri-estado: true/false/desconocido).
- `externalId = input.externalId || input.operationNumber || null`.
- `source = 'pedido'` fijo. `userId = branch.creatorId`. `branchId = branch.id`.
- `meta` sólo se incluye en el objeto **si `input.meta !== undefined`** (para no borrar el payload
  guardado en un update).
- **Campos duplicados a columna a propósito** (`pedidoUpdatedAt`, `estado`, `archivado`,
  `fechaComprometida`, `pedidoCosto`, `facturaEstado`, `facturaNumero`, `facturaAt`,
  `facturaDomicilio`, `facturaCorregidoAt`, `municipio`, `vendedor`, `sucursalCodigo`): todos
  viajan además dentro de `meta`, pero **ahí dentro no se puede filtrar sin leer y descartar el
  pedido entero de cada fila. Con 50.000 pedidos eso no es un filtro.**
- `pedidoCosto` es el costo que la APK puso EN PEDIDO. **No es `deliveryPrice`.**
- `facturaEstado` viene copiado de PEDIDO, que es quien coteja contra la factura. Aquí sólo se
  copia para poder filtrar: **cargar el camión con un pedido que la factura cambió es descuadrar la caja.**

---

## 3. `warehouse.ts` — cliente del Data Warehouse (Ventra, read-only)

- Sólo alcanzable por **VPN WireGuard**. `BASE = WAREHOUSE_API_URL || 'http://10.188.2.2:3001/api/external-api'`.
- `TOKEN = WAREHOUSE_API_TOKEN` (permanente). Si falta → error `'WAREHOUSE_API_TOKEN no configurado (.env)'` **antes** de salir a la red.
- Cabeceras: `Authorization: Bearer <TOKEN>`, `Accept: application/json`, `cache: 'no-store'`.
- Si `!res.ok` → error `Warehouse <status> en <path>: <primeros 200 chars del cuerpo>`.
- Scopes del token: `accounting.read, axis.read, branch_entries.read, branches.read, warehouses.read`.

### Endpoints confirmados (2026-07-07)
| Ruta | Devuelve |
|---|---|
| `GET /branches` | `{id,name,code,warehouses[]}` |
| `GET /warehouses` | `{id,name,code,branch,company}` |
| `GET /branch-entries?database&page&pageSize&from&to` | movimientos contables paginados |
| `GET /products/weights` (= `/axis/products`) | `{sku,name,category,unit,weightKg,isActive}` |
| `GET /axis/databases` | bases/sucursales de Ventra |
| `GET /axis/sales?database&from&to&limit` | líneas de factura |

- `weightKg` = **peso en kg por unidad de venta**, igual para todas las sucursales. `sku` coincide
  con `productCode` de las entries. **Aviso vigente: ~70 de 111 tienen `weightKg` en null** (se están llenando).
- `branchEntries(params)`: sólo se serializan los parámetros **`!= null`**; si no queda ninguno, se
  pide sin query string.

### Helpers de parseo tolerante
- `numero(fila, ...nombres)`: primer campo no `null` y **no cadena vacía** cuyo `Number(v)` no sea
  `NaN`. Ojo: `Number('')` es 0, por eso se descarta `''` antes. Devuelve `null` si ninguno.
- `texto(fila, ...nombres)`: primer campo que sea string y **no quede vacío tras `trim()`**; se
  devuelve ya trimmeado. `null` si ninguno.
- `filas(d)`: `d` si es array; si no `d.items`; si no `d.data`; si no `[]`.

### `ventraDatabases() -> BaseVentra[]`
- `GET /axis/databases` → `{database: texto('database')||'', branchName: texto('branchName','name')||'', connected: f.connected ?? true}`.
- **Filtra fuera las filas sin `database`.**
- **POR QUÉ hay que PREGUNTARLAS y no deducirlas:** los slugs no se parecen a lo esperable —
  `granma` es BAYAMO, `sspiritus` es Sancti Spíritus, `tunas` es Las Tunas—. **Adivinar falla en
  cuatro de diez, y una sucursal entera se queda sin catálogo sin que salte nada.**

### `ventraVentas(database, desde, hasta, tope = 5000) -> LineaVentaVentra[]`
- `GET /axis/sales?database=<enc>&from&to&limit=<tope>`. Se leen `d.rows` si existe, si no `d`.
- Mapeo: `id`, `fecha` = `date|fecha`, `operNumber` = `operNumber|numero`, `clienteCodigo` =
  `customerCode|clienteCodigo`, `clienteNombre` = `customerName|clienteNombre`, `productoCodigo` =
  `productCode|productoCodigo`, `productoNombre` = `productName|productoNombre`,
  `cantidad` = `quantity|cantidad` **con fallback 0**, `precioUsd` = `priceOut|precioUsd` (puede ser null).
- **Se descartan las filas sin `id` o sin `productoNombre`.**
- `database` es **obligatorio**: sin él Ventra devuelve el consolidado de todas y no hay forma de
  saber de qué sucursal es cada factura.
- `operNumber` es el nº de factura y **varias líneas lo comparten**; `cantidad` va en unidades de
  venta, igual que precio y peso del catálogo.

### `ventraCatalogo(database) -> FilaCatalogoVentra[]`
- `GET /products/weights?database=<enc>`. **El `database` es lo que distingue este del
  `productWeights()` pelado:** sin él sólo llegan pesos; **precio y existencias VARÍAN POR
  SUCURSAL**. Un precio «de ninguna sucursal en concreto» guardado como si lo fuera **es peor que
  no tenerlo**.
- `sku` ← `sku|productCode|code`; `name` ← `name|productName|descripcion`;
  `category` ← `category|categoria`; `unit` ← `unit|unidad`;
  `weightKg` ← `weightKg|weight|pesoKg`;
  `stock` ← `existencias|stock|quantity|onHand`;
  `price` ← `precioUsd|price|unitPrice|salePrice|precio`;
  `isActive` ← `f.isActive ?? null`.
- **Los nombres reales son `existencias` y `precioUsd`; los demás son red de seguridad por si
  renombran la columna: perder todos los precios en silencio por un nombre cambiado es el fallo que
  no se ve.**

### Caché de pesos
- `WEIGHTS_TTL = Number(WAREHOUSE_WEIGHTS_TTL || 600)` **segundos** (10 min). El catálogo cambia poco.
- `productWeightsCached()`: lee Redis (`K_WAREHOUSE_WEIGHTS`); si hay, lo devuelve; si no, baja y
  cachea. **Sin Redis, baja directo** (nunca falla por falta de caché).
  POR QUÉ: evita re-bajar por VPN el catálogo entero en cada lote de cotización.
- `invalidateWeightsCache()`: borra la clave. Hay que llamarlo tras importar/actualizar pesos.
- `fetchWeightMap() -> Map<SKU_MAYÚSCULAS, weightKg>`: **sólo los productos con `sku` y
  `weightKg != null`** (un `weightKg` de 0 sí entra).
- `fetchWeightCatalog()`: `buildWeightCatalog(productWeightsCached())` (import dinámico).

---

## 4. `filtrosPedido.ts` — filtros del catálogo de pedidos

**Dos reglas de fondo:** (a) los usan la lista de pedidos **y** el armador de rutas y tienen que
significar lo MISMO en los dos, o los números no cuadran y nadie sabe cuál creerse; (b) **se aplican
en la BASE, no en el navegador**: con 50.000 pedidos, filtrar en pantalla significa mandárselos
todos primero, que es lo que la dejaba colgada.

### `leerFiltros(params)`
Lee de la query, `trim()` a todo, `''` si falta. **`q` además pasa a minúsculas.**
Campos: `q, estado, archivado, domicilio, cotizado, municipio, vendedor, branchId, reparto, factura, desde, hasta`.

### Vocabulario de valores
- `estado`: `completada` | `en_proceso` | `expirada` | `''` (todos).
- `archivado`/`domicilio`/`cotizado`: `'1'` | `'0'` | `''` (los dos).
- `reparto`: `sin_entregar` | `en_despacho` | `en_ruta` | `entregado` | `devuelto`.
- `factura`: `igual` | `cambiado` | `sin_factura` | `sin_cotejar` | `cuadra` | `con_factura`.
- `desde`/`hasta`: `YYYY-MM-DD`.

### `whereDeFiltros(f)` — se devuelve `{ AND: [...] }`, nunca un objeto plano
**POR QUÉ un AND de condiciones sueltas:** varios filtros necesitan su propio `OR` —la búsqueda, el
rango de fechas, lo expirado— y mezclarlos en un solo nivel hace que **el último pise a los
anteriores en silencio**. Si no hay ninguna condición → `{}`.

1. **`q`** → `OR` de `contains` insensible a mayúsculas sobre: `customerName`, `operationNumber`,
   `endAddress`, `address`, `municipio`, `vendedor`, **`productosTexto`**.
   Una sola caja, porque quien la usa no se para a pensar en qué campo está lo que recuerda. El
   último es la copia en texto de los productos: dentro del JSON no se puede buscar sin leerse los
   cincuenta mil pedidos, y es la pregunta del despacho.

2. **`estado`.** Se define `noCompletada = OR[ estado IS NULL, estado != 'completada' ]`.
   - `completada` → `estado = 'completada'`.
   - `en_proceso` → `AND[ noCompletada, OR[ fechaComprometida IS NULL, fechaComprometida >= AHORA ] ]`.
   - `expirada` → `AND[ noCompletada, fechaComprometida < AHORA ]`.
   - **`AHORA` se evalúa en cada llamada (`new Date()`), no se guarda.** En PEDIDO sólo se guarda
     `completada`; «expirada» se calcula aquí porque **un booleano guardado se queda viejo al día
     siguiente y empieza a mentir solo**.
   - **El `estado IS NULL` explícito es obligatorio:** `NOT (estado = 'completada')` sobre un NULL
     da NULL en SQL, que no es TRUE, y la fila se cae del filtro. En producción hay **29 pedidos sin
     estado** que se caían de los TRES filtros a la vez, así que la suma de los tres no daba el
     catálogo y no había forma de llegar a ellos.

3. **`archivado`**: `'1'` → `archivado = true`; `'0'` → `archivado = false`.

4. **`domicilio`**: `'1'` → `requiereDomicilio = true`;
   `'0'` → `OR[ requiereDomicilio IS NULL, requiereDomicilio = false ]`.
   **«Sin domicilio» incluye los que no traen el dato: no saberlo no es llevarlo.** El NULL se
   nombra a mano por lo mismo del punto 2.

5. **`cotizado`**: `'1'` → `pedidoCosto != null`; `'0'` → `pedidoCosto = null`.

6. **`municipio`/`vendedor`**: igualdad exacta.

7. **`branchId`**: igualdad, **como un filtro más y nunca en lugar del alcance**. Se combina en AND
   con el `where` del alcance, así que quien sólo ve una sucursal no puede pedir la de otro
   poniéndolo a mano: el AND de los dos no deja pasar nada.

8. **`reparto`** (estado de REPARTO, propio de delivery; **no tiene nada que ver con el estado del
   pedido ni con el de la factura; las tres cosas se dicen por separado y ninguna manda sobre las
   otras**):
   - `sin_entregar` → `routeId IS NULL` **AND** `deliveredAt IS NULL` **AND**
     `OR[ resultado IS NULL, resultado != 'entregado' ]`.
   - `en_despacho` → `routeId != null` AND `route.status = 'planned'`.
   - `en_ruta` → `routeId != null` AND `route.status = 'in_progress'`.
   - `entregado` → `OR[ resultado = 'entregado', deliveredAt != null ]`.
   - `devuelto` → `resultado IN ('devuelto','cancelado')`.
   - **`devuelto` no es un estado sino el RESULTADO de la parada**: el pedido baja del camión y
     vuelve a `sin_entregar`, listo para la ruta de mañana.
   - **REGLA CRÍTICA — manda el RESULTADO de la parada, no el estado de la ruta.** «Entregado» era
     `deliveredAt` **o que la ruta estuviera completada**, y eso convertía en entregado a todo lo
     que iba en una ruta cerrada, **incluido lo que el propio cierre había grabado como DEVUELTO**.
     Delivery se contradecía: guardaba «devuelto», se lo contaba a PEDIDO y luego lo pintaba
     «entregado». Pasó con un pedido real de La Habana el **2 de septiembre**. Una ruta completada
     no dice nada de cada parada; lo que lo dice es `resultado`.
   - Antes esto se filtraba **sobre la página que se estaba viendo**: el conteo decía 358 y la tabla
     salía vacía.

9. **`factura`** (cadena `if/else if`, exclusiva):
   - `con_factura` → `facturaEstado IN ('igual','cambiado')`. **LO REPARTIBLE.** `cambiado` **no es
     un pedido roto**: se facturó distinto de como se pidió, y lo que sube al camión son las líneas
     de la FACTURA (PEDIDO ya las manda así, con `itemsOrigen: 'factura'`), así que se reparte igual
     de bien. Quedan fuera `sin_factura` (no hay nada que llevar) y el NULL.
   - **Pero `cambiado` NO entra a una ruta** (Jose: «en el camión sólo sube lo que cuadra con la
     factura»): esta lista lo OFRECE para que se vea y se revise, y el armado lo rechaza
     nombrándolo (§15.3). Y desde el **07/10/2026 (Amado)** la lista de disponibles, «Sin colocar»
     del tablero, su contador, `ColocarPedido` y los recuentos del panel exigen además **domicilio
     cobrado** (`factura_domicilio > 0`) y **cotizado** (`pedido_costo` no nulo): ver §15.13.
   - `cuadra` → `facturaEstado = 'igual'` (sólo lo comprobado y coincidente).
   - `sin_cotejar` → `facturaEstado IS NULL`.
   - cualquier otro valor no vacío → `facturaEstado = <valor>`.
   - **POR QUÉ el NULL tiene opción propia:** `cuadra` incluía antes el NULL, con la idea de que
     «todavía no se ha cotejado» era casi lo mismo que «cuadra». **No lo es.** NULL quiere decir que
     NO SE SABE: la VPN a Ventra caída, el pedido fuera de los días que se repasan, o su sucursal
     sin base en Ventra. Con eso **se armó una ruta con un pedido sin facturar el 2 de septiembre**.

10. **Fechas — `porFecha(f)`:**
    - Validación: `ES_FECHA = /^\d{4}-\d{2}-\d{2}$/`. **Si ni `desde` ni `hasta` la pasan, no se
      añade condición (`null`).** Cada extremo se valida por separado; uno solo basta.
    - `desde` → `gte = new Date('<desde>T00:00:00')` (hora **local**, sin zona).
    - `hasta` → `lte = new Date('<hasta>T23:59:59.999')`. **El `hasta` incluye el día entero: quien
      escribe el 24 quiere los del 24, no los del 24 a las 00:00.**
    - Condición: `OR[ { orderDate: rango }, { orderDate: null, createdAt: rango } ]`.
      **POR QUÉ la segunda rama:** los pedidos anteriores a que se guardara `orderDate` lo tienen en
      null y desaparecerían de cualquier búsqueda por fechas; **desaparecer sin decir nada es peor
      que salir con la fecha aproximada, que además la pantalla marca**.

### `hayFiltros(f) -> bool`
`true` si **algún** valor del objeto es distinto de `''`. Sirve para distinguir un cero de «no hay»
frente a «no cuadra ninguno».

---

## 5. `productMatch.ts` — emparejar producto de PEDIDO con el catálogo de pesos

**Problema:** los pedidos NO traen código de producto, sólo el nombre y en otro formato que el
warehouse (`"PARRANDA 0.33L"` vs `"CERVEZA PARRANDA 330 ML BLISTER 6U"`).
**Peso del ítem = `weightKg(SKU) × packs`**, donde el peso del warehouse es **por unidad de venta**.

### 5.1 `NOISE` (constante literal, 24 palabras)
`ALIMENTOS, ASEO, HIGIENE, HOGAR, HIGIENEHOGAR, TECNOLOGIA, BEBIDAS, CONFITERIA, RONES, CERVEZA,
BLISTER, CAJA, PACA, PALET, TONEL, BOTELLA, SACO, UNIDAD, UNIDADES, PAQUETE, DE, X, REFRESCO`
(son 23 + nota: categorías y empaque, no identifican el producto).

### 5.2 `normalizeProduct(name) -> {tokens, volMl, key}` — orden de pasos EXACTO
1. `stripAccents` (NFD + quitar diacríticos) y `toUpperCase()` sobre `String(name || '')`.
2. `,` seguida de dígito → `.` (`0,33` → `0.33`). Regex: `/[,](?=\d)/g`.
3. **Volumen en ML:** `/(\d+(?:\.\d+)?)\s*ML\b/g` → `volMl = round(parseFloat(n))`, sustituye por
   ` V<volMl> `.
4. **Volumen en L:** `/(\d+(?:\.\d+)?)\s*L\b/g` → `volMl = round(parseFloat(n) × 1000)`, sustituye
   por ` V<volMl> `. **Se ejecuta DESPUÉS de ML** y si hay varias coincidencias **gana la última**
   (`volMl` se sobreescribe en cada reemplazo).
5. **Conteos de empaque fuera:** `/\b\d+\s*[UP]\b/g` → espacio (`6U`, `24U`, `12P`, `4U`). No
   identifican: ya está `packs`.
6. Tokenizar por `/[^A-Z0-9+.]+/`, descartar vacíos.
7. Quedarse con tokens de **longitud > 1** o que sean **un solo dígito** (`/^\d$/`); es decir, se
   descartan las letras sueltas pero se conservan los dígitos sueltos.
8. Quitar los que estén en `NOISE`.
9. **Únicos** (`Set`) y **ordenados alfabéticamente** (`.sort()` por defecto de JS, orden de unidad
   de código UTF-16).
10. `key = tokens.join(' ')`.

Se conservan a propósito los números significativos (año del ron `12`, tamaño `7 PIES`, `25KG`) y el
token de volumen `V<ml>`.

### 5.3 `damerau(a, b)` — Damerau-Levenshtein con transposición de adyacentes
- **Corte rápido: si `|len(a) − len(b)| > 1` devuelve 2** (">1 no nos interesa").
- Matriz `(al+1)×(bl+1)`, inicializada `d[i][0]=i`, `d[0][j]=j`.
- `cost = (a[i-1] === b[j-1]) ? 0 : 1`;
  `d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)`;
  si `i>1 && j>1 && a[i-1]===b[j-2] && a[i-2]===b[j-1]` → `d[i][j] = min(d[i][j], d[i-2][j-2]+1)`.
- Sirve para detectar UN typo: `NIGTH ↔ NIGHT` es transposición = distancia 1.

### 5.4 `buildWeightCatalog(products)` y `resolve(name?, code?) -> WeightHit`
Construcción:
- `w = (p.weightKg == null) ? 0 : p.weightKg` — **null se convierte en 0, no se descarta la fila.**
- `bySku[sku.toUpperCase()] = w` si hay `sku`.
- `byKey[key]` se llena **sólo si no existía**: gana el **primer SKU con esa clave**.
- `entries[]` guarda todas las filas (incluidas las de clave repetida) para el fuzzy.

Resolución, en orden:
1. **Por SKU**: si `code` y `bySku` contiene `code.toUpperCase()` → `{weightKg, sku, how:'sku'}`.
   (Puede devolver `weightKg = 0` legítimamente si ese SKU no tiene peso cargado.)
2. Si no hay `name` → `{weightKg: 0, how: 'none'}`.
3. **Exacto por nombre**: `byKey.get(normalizeProduct(name).key)` →
   `{weightKg, sku, whName, how:'name-exact'}`.
4. **Fuzzy**, recorriendo todas las `entries` y exigiendo **las cuatro condiciones**:
   - `e.volMl === n.volMl` (mismo volumen, incluido `null === null`),
   - `e.tokens.length === n.tokens.length` (misma cantidad de tokens),
   - la diferencia simétrica es **exactamente un token por lado** (`onlyP.length === 1 &&
     onlyC.length === 1`),
   - `min(len(onlyP[0]), len(onlyC[0])) >= 4` (para no cruzar palabras cortas) **y**
     `damerau(onlyP[0], onlyC[0]) <= 1`.
   - **Se cuenta cuántas entradas cumplen (`bestCount`). Sólo se acepta si `bestCount === 1`**: con
     dos candidatas ambiguas se devuelve `none`. `best` guarda la ÚLTIMA que cumplió.
5. Si nada → `{weightKg: 0, how: 'none'}`.

`MatchHow = 'sku' | 'name-exact' | 'name-fuzzy' | 'none'`.

---

## 6. `emparejarVentra.ts` — nuestra sucursal ↔ la base de Ventra

Vive aparte del `route.ts` que lo usa por dos razones: Next no deja exportar de un `route.ts` nada
que no sea un manejador, y **esto es justo lo que hay que poder probar solo: cuando falla no salta
nada, simplemente una sucursal se queda sin catálogo**.

### `normalizarNombre(s)`
NFD → quitar diacríticos → `toLowerCase()` → todo lo que **no** sea `[a-z0-9]` se sustituye por **un
espacio** → `trim()`. (No colapsa espacios internos múltiples salvo por el `+` del regex, que sí los
agrupa.)

### `emparejarConVentra(sucursales, bases) -> (SucursalLocal & {database: string|null})[]`
1. **Índice `porClave`**: para cada base de Ventra se registran **dos** claves normalizadas →
   `b.database`: la del **slug** (`b.database`) y la del **`branchName`** (si no está vacío).
   **POR QUÉ las dos:** hay que preguntárselo a Ventra, no deducirlo — `granma` es BAYAMO,
   `sspiritus` es Sancti Spíritus, `tunas` es Las Tunas; **adivinar falla en cuatro de diez**.
2. **Formas de NUESTRO nombre** (`formas(s)`), todas normalizadas y sin vacías, en este orden:
   - el nombre tal cual,
   - el nombre **sin paréntesis** (`/\([^)]*\)/g` → espacio),
   - el contenido **de cada paréntesis**,
   - `s.externalId ?? ''`.
   **POR QUÉ:** nuestros nombres llevan cosas que Ventra no usa. «Bayamo (Granma)» lleva las dos en
   una y «Santiago de Cuba» lleva el «de Cuba» que allí no está. **Los dos se quedaron sin catálogo
   en la primera pasada y sólo se vio porque el sondeo lo dice.**
3. **Coincidencia exacta**: la primera forma que exista en `porClave` gana → `database = esa`.
4. **Último recurso (contención)**: se recorre `porClave` y se descartan las claves de **longitud
   < 4**; se acepta la base si **alguna** forma nuestra `f` cumple `f.includes(clave)` **o**
   `clave.includes(f)`. Se acumulan las bases distintas en un `Set`.
   - **`database = (candidatas.size === 1) ? la única : null`.**
   - **POR QUÉ null con dos:** así «Santiago de Cuba» encuentra `santiago`, pero si encajaran dos
     bases distintas se devuelve null **a propósito**: *darle a una sucursal el catálogo de otra sale
     con precios y existencias creíbles que nadie cuestiona, y eso no se arregla después.*

---

## 7. `domicilioEntrega.ts` — el costo del domicilio (fórmula de Entrega, calcada)

**Regla de fondo:** un pedido metido a mano en delivery tiene que salir por el **mismo número** que
uno hecho desde el teléfono. Si aquí se inventa una fórmula parecida, el mismo reparto vale una cosa
en un sitio y otra en el otro, y nadie sabe cuál cobrar.

**La de Entrega** (`services/calculo.ts` en la APK y `SyncService` en su backend) es:

    tarifa base (USD por km·kg) × distancia (km) × peso (kg)

con distancia **en línea recta (Haversine)** del **almacén** al cliente y **redondeo a dos
decimales**. La tarifa se guarda allí **en CUP**, así que se pasa a USD **dividiendo por la tasa de
ESA sucursal** — exactamente lo que hace la APK antes de multiplicar.

**Nada de esto se configura aquí:** tarifa y tasa vienen de Entrega a través de Accesos. Tener una
copia editable en delivery es volver a tener dos números para lo mismo.

### Constantes y helpers
- `RADIO_TIERRA_KM = 6371`.
- `distanciaHaversineKm(lat1,lon1,lat2,lon2)`: idéntica a `pricing.haversineDistance`
  (`R·2·atan2(√a, √(1−a))`), **sin redondear**.
- `redondear(valor, decimales = 2) = Math.round((valor + Number.EPSILON) · 10^decimales) / 10^decimales`.
  **El `+ Number.EPSILON` es deliberado** (empuja los casos de medio exacto que la coma flotante deja
  justo por debajo). En Go hay que replicarlo: `math.Round((v+2.220446049250313e-16)*f)/f`. Nótese
  que `Math.round` de JS redondea **hacia +∞** en el empate (`-0.5 → -0`), no «half away from zero».

### `costoDomicilioEntrega(tarifaBaseCup, cupPorUsd, distanciaKm, pesoKg) -> CostoDomicilio | null`
**Rechazos (devuelven `null`, nunca 0):**
- `!tarifaBaseCup` (falsy: incluye `null`, `undefined` y **`0`**),
- `!cupPorUsd` o `cupPorUsd <= 0`,
- `distanciaKm` o `pesoKg` no finitos (`NaN`, `Infinity`).

**POR QUÉ `null` y no `0`:** *un cero se suma y se lee como «este domicilio es gratis», que es peor
que decir que no se sabe.*

**Cálculo:**
- `tarifaUsd = tarifaBaseCup / cupPorUsd` — **sin redondear** (se devuelve tal cual).
- `usd = redondear(tarifaUsd × distanciaKm × pesoKg, 2)`.
- `cup = redondear(usd × cupPorUsd, 2)` — **se calcula sobre el `usd` YA REDONDEADO**, no sobre el
  valor crudo. Importa: reimplementarlo al revés da otro número.
- `distanciaKm = redondear(distanciaKm, 3)`, `pesoKg = redondear(pesoKg, 3)` (**3 decimales**, sólo
  para informar; los del cálculo son los crudos).

Salida: `{distanciaKm, pesoKg, usd, cup, tarifaUsd}`.

---

## 8. `tasaCambio.ts` — la tasa USD→CUP por sucursal

**Regla de fondo:** la tasa **se PIDE a Accesos, no se teclea aquí.** Antes vivía en Configuración →
«Monedas»: alguien escribía un número a mano y ése usaba toda la aplicación, mientras PEDIDO la
traía de Entrega. **Dos tasas para lo mismo se separan en cuanto una se olvida —y se olvida, porque
la de aquí no la refresca nadie—, y el mismo domicilio vale distinto según dónde se mire. Eso no
falla en pantalla: sale un importe creíble y cuadra mal en la caja, que es donde se descubre tarde.**
Aquí **no hay ninguna copia editable**: si Accesos no contesta, no hay tasa, y se dice.

### Tipo `Tasa`
`{codigo, cupPorUsd, tarifaBase: number|null, fuente: string|null, traidoAt: string, fresca: boolean}`.
- `tarifaBase` = **CUP por km y por kg**, con lo que Entrega cobra el domicilio.
  `importe USD = (tarifaBase / cupPorUsd) × distancia × peso`. Viaja para que un pedido metido a
  mano salga por el mismo número que uno del teléfono.
- `fresca = false` cuando lleva demasiado sin actualizarse **en Accesos** (lo decide Accesos).

### Constantes de caché (en memoria del proceso, se pierde al reiniciar — correcto para algo que no es nuestro)
- `RECUERDO_MS = Number(TASA_CACHE_MS || 5 × 60 × 1000)` = **5 min** para una tasa que SÍ existe.
  POR QUÉ existe la caché: el costo se calcula por **lotes de 200 pedidos** y cada uno necesita la
  tasa de su sucursal; sin esto son 200 llamadas a Accesos por tanda. Dura poco a propósito: la tasa
  se mueve a diario, no por minuto.
- `RECUERDO_SIN_TASA_MS = Number(TASA_CACHE_VACIA_MS || 20 × 1000)` = **20 s** para el «no hay tasa».
  **POR QUÉ mucho menos:** «esta sucursal todavía no tiene» es un estado que alguien está arreglando
  ahora mismo: se pone en Entrega, Accesos la trae… y aquí seguía diciendo que no hay durante cinco
  minutos más. **Pasó de verdad: la tasa estaba puesta y la pantalla seguía en USD.**

### `preguntarAAccesos(codigo)`
- `GET /api/service/tasas?codigo=<enc>` mediante `pedirFirmado`.
  **Accesos no acepta una clave suelta en una cabecera:** cada aplicación firma con SU llave —método,
  ruta, hora, nonce y hash del cuerpo—, así que una petición copiada de un registro no vale al minuto
  siguiente. Delivery reutiliza la llave del login único en vez de abrir una segunda puerta.
- **Accesos contesta 200 con `tasa: null` cuando esa sucursal no tiene: que falte es un estado
  normal, no un error, y por eso no viene como 404.**
- Se devuelve `null` si `b.tasa === null` **o** `typeof b.cupPorUsd !== 'number'`.
- Mapeo: `codigo = b.codigo ?? codigo.toUpperCase()`; `tarifaBase` sólo si es `number`, si no `null`;
  `fuente = b.fuente ?? null`; `traidoAt = String(b.traidoAt ?? '')`; **`fresca = (b.fresca !== false)`**
  (ausente ⇒ true).

### `tasaDeSucursal(codigo) -> Tasa | null`
- `null` inmediato si no hay código. Clave = `codigo.trim().toUpperCase()`.
- **El TTL depende de lo recordado:** `dura = guardada?.tasa ? RECUERDO_MS : RECUERDO_SIN_TASA_MS`.
  Si `Date.now() − guardada.cuando < dura` → se devuelve lo guardado (incluido el `null`).
- Al pedir con éxito, **se cachea también el `null`**.
- **Si Accesos lanza (catch): se devuelve `guardada?.tasa ?? null` — lo último que se supo, aunque
  esté pasado, y SIN refrescar la marca de tiempo.** POR QUÉ: *una tasa de ayer convierte con un
  error pequeño, y sin ninguna no se puede cotizar ni un pedido. Lo que no se hace es guardarlo como
  si fuera fresco: se devuelve tal cual, con su fecha, y quien lo enseñe puede avisar.*
- **NUNCA la de otra sucursal.** Es el error que más daño hace aquí: *convertir un importe de Granma
  con la tasa de La Habana da un número creíble que nadie cuestiona, y aparece en la caja.* Sin
  tasa, el pedido se queda sin precio en CUP **y se dice de qué sucursal falta**.

### `tasaDeAlmacen(branchId) -> Tasa | null`
`null` si no hay `branchId`; si no, `Branch.findUnique(id).externalId` → `tasaDeSucursal(externalId)`.
**POR QUÉ la traducción vive aquí:** delivery trabaja con `Branch.id`, las tasas van por **CÓDIGO de
sucursal**, que es la clave que cruza todas las aplicaciones; así quien cotiza no tiene que llevarse
el mapa.

---

## 9. `geocode.ts` — geocodificación (Nominatim / OpenStreetMap, sin API key)

Constantes: `NOMINATIM = 'https://nominatim.openstreetmap.org'`, `UA = 'ProCovarDelivery/1.0'`.

### `forwardGeocode(query) -> LatLng | null`
- **Corte previo: si `query.trim().length < 4` devuelve `null` sin salir a la red.**
- `GET /search?format=json&q=<enc>&limit=1&accept-language=es`, cabeceras `User-Agent: UA` y
  `Accept-Language: es`.
- Toma **el primer resultado**: `{lat: parseFloat(d[0].lat), lng: parseFloat(d[0].lon)}`; si la lista
  viene vacía → `null`.
- **Cualquier excepción (red, JSON inválido) → `null`.** Nunca propaga.

### `reverseGeocode(lat, lng) -> string`
- `GET /reverse?format=json&lat&lon&accept-language=es`, cabecera `User-Agent: UA`.
- Devuelve `display_name`; **si falta o hay excepción, `formatCoords(lat,lng)`**. Nunca devuelve
  vacío ni lanza.

### `formatCoords(lat, lng)`
`` `${lat.toFixed(5)}, ${lng.toFixed(5)}` `` — **5 decimales, coma + espacio**.

### `zoomFromArea(areaKm2) -> number`
- `a = areaKm2 > 0 ? areaKm2 : 1` (protege el log de 0 y negativos).
- `z = round(13 − log2(√a))`.
- **Acotado a `[8, 16]`**: `max(8, min(16, z))`. Área mayor → zoom menor.

### `parseCoordInput(text) -> LatLng | null`
- Regex: `/^(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$/` sobre `text.trim()`.
  Acepta `"-23.5505, -46.6333"`, `"23.55 -46.63"`, y `;` como separador. **Máximo 3 dígitos enteros.**
- Rechaza (→ `null`) si no casa, si algún `parseFloat` da `NaN`, o si
  **`lat < −90 || lat > 90 || lng < −180 || lng > 180`**.

---

## 10. `almacenes.ts` — almacenes de una sucursal (leídos de Accesos)

**Regla de fondo:** los almacenes **se gestionan en esta aplicación** (pantalla Almacenes) **pero
viven en Accesos**: el almacén es de la sucursal. Aquí sólo se **leen**, firmado, y se recuerdan un
rato — hacen falta para medir cada domicilio y no cambian de un minuto a otro.

- `Almacen = {id, codigo, nombre, direccion: string|null, latitud: number|null,
  longitud: number|null, principal: boolean, activo: boolean}`.
- **`codigo` es NUEVO (26/09/2026) y es la IDENTIDAD, junto con la sucursal.** Es el `objectCode`
  de Ventra. El nombre no identifica: `PV-STGO` está en Santiago **y** en Palma Soriano, y
  `Tiendas Parranda` en cinco sucursales con cinco ids. El código solo tampoco: `objectCode: 2`
  es AURORA en Santiago, PV CAMAGUEY en Camagüey y PV GTMO en Guantánamo.
- `RECUERDO_MS = Number(ALMACENES_CACHE_MS || 5 × 60 × 1000)` = **5 min**.
- **Caché global única** (`recuerdo: {cuando, porCodigo: Map}`), no por código: una sola llamada a
  `GET /api/service/almacenes` (firmada, `pedirFirmado`) trae **todas** las sucursales con sus
  almacenes y se indexan por `codigo.toUpperCase()`.
- `almacenesDeSucursal(codigo)`: clave = `codigo.trim().toUpperCase()`.
  - Si la caché está viva (`Date.now() − cuando < RECUERDO_MS`) → `porCodigo.get(clave) ?? []`.
  - Si no → se recarga TODO y se reindexa; devuelve `?? []`.
  - **Una sucursal desconocida devuelve `[]`, no error.**
  - `r.sucursales ?? []` y `s.almacenes ?? []` toleran respuesta incompleta.
  - **Si `pedirFirmado` lanza, la excepción SÍ sale** (la caché no se actualiza). Quien llama es
    quien decide: en `/api/quote/home-delivery` se hace `.catch(() => [])`.

### Regla de selección del almacén de origen (vive en `/api/quote/home-delivery/route.ts`)
1. Primer almacén con `principal === true` **y** `latitud != null` **y** `longitud != null`.
2. Si no hay, **el primero con coordenadas**, principal o no.
3. **Si no hay ninguno con coordenadas → 409 `"<Sucursal> no tiene ningún almacén con
   coordenadas"`.** *Es desde donde sale la mercancía, que es lo que mide la APK. Sin almacén con
   coordenadas no se contesta un número aproximado: se dice que no se puede.*

#### AQUÍ NOS SEPARAMOS DEL PATRÓN — 24/09/2026 (`CLAUDE.md` §2)

Eso es lo que hace el Next, y le faltan dos condiciones y un desempate. La regla de **este**
proyecto es una sola y vale para los cinco consumidores (cotización, tablero, clientes, Panel y
el aparato):

1. **Sirven para medir** los que están `activo`, tienen las **dos** coordenadas y **no** están
   en `(0,0)`.
2. De ésos gana el `principal`; si hay varios o ninguno, **el primero por nombre ascendente**
   (y el `id` desempata a dos nombres iguales).
3. Si no sirve ninguno, el mismo 409.

**Por qué `activo`:** el servidor no lo filtraba y el aparato sí, así que en una sucursal con el
almacén principal dado de baja —con coordenadas buenas— el mismo botón «Armar la ruta de esta
zona» daba **dos kilometrajes** según se pulsara en el navegador o en el teléfono, y de esos km
sale el cobro. Jose: *«no puede dar distinto, debe dar igual […] eso debe dar igual en todos los
datos»*. **Por qué el nombre:** «el primero de la lista» deja la decisión en manos de quien
sirva la lista, y Accesos (HTTP) y la base local no la sirven igual.

Vive en `api/internal/cotizar/almacen.go` (`ElegirAlmacen`) y en
`app/lib/nucleo/almacenes/almacen_de_referencia.dart` (`AlmacenDeReferencia`), y lo que ata a los
dos es `docs/almacen-de-origen.casos.json` —el mismo fichero para las pruebas de Go y las de
Dart—, no un comentario (§3-bis).

### Y AHORA MANDA EL ALMACÉN DEL PEDIDO, no el principal de la sucursal — 26/09/2026

Todo lo de arriba sigue en pie, pero **elige el almacén de una SUCURSAL**, y ésa dejó de ser la
pregunta. Mientras cada sucursal tuvo un almacén, «el de la sucursal» y «el del que sale este
pedido» eran la misma frase. Contado por la sesión de PEDIDO:

```
SANTIAGO    2.185 líneas desde AURORA · 804 desde PV-STGO · 11 desde PTO MONEDERO
CAMAGÜEY    2.778 desde PV CAMAGUEY   · 183 desde FLORIDA · 39 desde ALM CAMAGUEY
GUANTÁNAMO  2.060 desde PV GTMO       · 940 desde ALM CENTRAL
```

**En Santiago dos de cada tres pedidos salen de AURORA** y el reparto los medía todos desde
PV-STGO, que es el principal. De esos kilómetros sale el costo del domicilio.

PEDIDO manda ahora el almacén en cada pedido y en cada renglón (`docs/contratos-api.md`, el
cuerpo de `/api/quote/batch`), y la regla es `cotizar.ElegirOrigenDelPedido`:

1. Del almacén que trae el pedido, emparejado **por código** entre los de SU sucursal. Nunca por
   nombre, ni como respaldo: un respaldo por nombre no falla, sólo mide desde el almacén de otra
   sucursal.
2. Si no trae, si no está dado de alta, si no tiene punto o si en Accesos no hay códigos
   todavía → **el principal**, con la regla de arriba, y **queda escrito el motivo**
   (`orders.almacen_salida_motivo`, seis valores; la tabla está en el contrato).
3. Si no hay ni un almacén con punto → desde el punto de la **sucursal**, con su propio motivo,
   porque ése NO es el sitio del que sale la carga y no puede confundirse con «desde el
   principal».

**Nada se descarta en silencio** (`CLAUDE.md` §4): el almacén que llegó se guarda con su código y
su nombre aunque no se haya podido usar, y la vista `almacenes_del_pedido_sin_medir` (00012) dice
qué almacenes están haciendo que se mida desde otro sitio, con cuántos pedidos y desde cuándo.
Sale además en `GET /api/admin/webhook` (`sinMedir`, con su `sinMedirTruncado`).

**Un almacén sin coordenadas se salta y se mide con el que las tenga. Eso es lo normal estos
días, no un fallo**: los 6 almacenes nuevos se dieron de alta sin punto a propósito —los ponen
los logísticos—, así que el dato llega antes que las coordenadas.

**LO QUE TODAVÍA MIDE DESDE EL PRINCIPAL**, y está escrito en `docs/integracion-pendiente.md`:
el armado de rutas (`tablero.go`: el origen de la ruta, `segment_km` y `total_distance`), la lista
de Clientes, y la APK, que resuelve el tablero y el armado en local.

---

## 11. `scope.ts` — a qué datos llega quien pide

**Regla de fondo: POR SUCURSAL, NUNCA POR CUENTA.** *Aquí nada pertenece a una persona: los pedidos
entran solos desde PEDIDO y son de la sucursal que los originó.*

### `Scope = {branchId: string|null, actorId: string}`
- `branchId` es **lo ÚNICO que decide qué se ve**. `null` = todas.
- `actorId` sirve **sólo** para dejar constancia de quién creó algo. **No filtra.**

### `resolveScope(req, user) -> Scope`
- `pedida = user.branchId || header 'x-sucursal-id'.trim() || null`. **La del usuario tiene
  prioridad sobre la cabecera**: quien pertenece a una sucursal no puede pedir otra.
- Si no hay `pedida` → `{branchId: null, actorId: user.id}` (Super Admin: todas, o la que elija).
- Si hay `pedida`, **se comprueba que la sucursal EXISTA** (`Branch.findUnique`). Si no existe:
  `console.warn('[alcance] la sucursal <id> no existe: se pasa a todas')` y se devuelve `branchId: null`.
- **POR QUÉ esa comprobación:** el id llega por dos sitios y los dos pueden traer uno viejo. El token
  del login único **dura siete días** y lleva dentro la sucursal que la persona tenía CUANDO entró; la
  cabecera sale de lo que el navegador guardó. **Las sucursales se recrearon en algún momento —unas
  tienen id cuid y otras hexadecimal—**, así que ambos pueden apuntar a algo que ya no está.
  Y **filtrar por un id inexistente no da error: da CERO.** Cero pedidos, cero clientes, cero rutas,
  cero vehículos y hasta cero sucursales —con lo que desaparece el selector con el que se podría
  arreglar—. Todo con 200 y sin una traza. **Se vio en producción y desde dentro es indistinguible de
  «no hay nada todavía».** Pasar a «todas» es lo correcto para quien administra y además deja ver el
  problema en vez de esconderlo.

> **En el reparto (Go) desde la 1.0.29 el alcance FALLA CERRADO** — auditoría de la 1.0.28,
> 08/10/2026. Donde difiere de lo de arriba (heredado de delivery), manda esto:
> - **La cabecera `X-Sucursal-Id` sólo la lee quien ve todas las sucursales** (`SUPER ADMIN`,
>   `DESARROLLADOR`) **y no tiene sucursal propia**. Para cualquier otro rol la cabecera ni se
>   mira: antes, un OPERADOR cuyo token llegaba sin sucursal mandaba `X-Sucursal-Id: STG` y veía
>   Santiago, o `basura` y —por el «no existe → todas»— las ocho.
> - **Sin sucursal y sin esos dos roles: siempre 403** (`esta cuenta no está dada de alta en
>   ninguna sucursal…`), mande la cabecera que mande.
> - **Una sucursal del token que Reparto no conoce** (Accesos sabe de `MOA` y `PLS`; Reparto no)
>   **es 403** para cualquier otro rol —`tu sucursal MOA no está dada de alta en Reparto: pide en
>   la oficina que la den de alta`— y «todas + aviso» **sólo** para `SUPER ADMIN` y
>   `DESARROLLADOR`. Hasta la 1.0.28 un OPERADOR de Moa veía las ocho sucursales con 200 y sin un
>   error: la regla 1 de la casa fallando abierta.
> - Un fallo de la base sigue sin abrir el alcance (500).
> Lo ata `api/internal/alcance/alcance_test.go` (en pareja: lo que cierra, y lo que sigue abierto
> para quien debe) y, por HTTP, `api/internal/api/api_test.go` y `eventos_test.go`.

### `scopeWhere(scope) -> {branchId?}`
`{branchId}` si hay, `{}` si no.
**Qué había antes y por qué estaba mal:** filtraba por `userId` usando como «dueño» al creador de la
sucursal. Como las ocho sucursales las creó el Super Admin, **los 3.528 pedidos importados quedaron
todos a su nombre**. Eso escondía datos: un pedido creado por una operadora de Holguín llevaba SU
identificador, no casaba con el del creador, y **sus propios compañeros de Holguín no lo veían**; el
mismo fallo al revés con dos administradores, cada uno viendo sólo lo suyo. `Order.branchId` ya
guardaba bien la sucursal desde el principio. `userId` se sigue escribiendo al crear algo a mano,
**para saber quién lo hizo y para nada más**.

### `sucursalDeLaPersona(user) -> string | null`
- `null` si el usuario no tiene `branchId`; si lo tiene, se comprueba que exista y, si no,
  `console.warn('[alcance] la sucursal <id> de <email> no existe: se le enseñan todas')` → `null`.
- **POR QUÉ es distinta del alcance:** el alcance mezcla el permiso con la sucursal elegida arriba.
  Hay sitios —**la lista de sucursales**— donde eso no vale: ahí se pregunta «a cuáles puedes
  llegar», que sólo depende de la persona. **Si se acotara también por la elegida, elegir una
  devolvería una sola, el selector se volvería una etiqueta fija y no habría forma de cambiar a otra:
  la elección se comería la lista con la que se elige.**

---

## 12. `armarPostDespacho.ts` — la cuenta del post-despacho

**Puro y testeable a propósito:** entran los pedidos de la ruta, sale la hoja. *Se hace aquí y no en
la pantalla porque es una resta que decide si falta mercancía.*

### Entradas
- `DatosDeRuta {ruta, sucursal, vehiculo, salida?, regreso?}` (se copian tal cual a la salida).
- `PedidoDeRuta[] {customerName, resultado?: 'entregado'|'devuelto'|'cancelado'|null, resultadoNota?, items?}`.

### Extracción de líneas (`lineas(p)`)
- `items` sólo si es array; si no, `[]`.
- `producto = (it.name || it.description || '').trim()`.
- **`formatos = (Number(it.packs) > 0) ? Number(it.packs) : (Number(it.quantity) || 0)`.**
  *Los formatos son la unidad con la que se carga y se cuenta un camión. Cuando la línea no los
  trae, se cae a las unidades: es lo que hay, y cero sería mentira.*
- **Se descartan las líneas con `producto` vacío.**

### Conteo de paradas
`entregadas` si `resultado === 'entregado'`; si no, `devueltas` (`'devuelto'`), `canceladas`
(`'cancelado'`) o **`sinMarcar`** para todo lo demás, incluido `null`/`undefined` y cualquier valor
desconocido.

### Agregado por producto (`LineaPostDespacho {producto, salio, entregado, queda}`)
Por cada línea de cada pedido, acumulando en un mapa **por nombre de producto exacto**:
- `salio += formatos` **siempre**.
- Si la parada es `entregado`: `entregado += formatos`; **en cualquier otro caso `queda += formatos`**.
- Invariante: `salio = entregado + queda`.

**REGLA CLAVE — lo que QUEDA es todo lo que no se entregó: lo devuelto, lo cancelado y —sobre todo—
lo que nadie marcó.** *Eso último se cuenta como que sigue arriba a propósito: dar por entregada una
parada que nadie tocó es justo como se pierde mercancía sin que salte nada. En la hoja sale aparte,
para que se vea que falta marcarla.*

### `pendientes: ParadaPendiente[]`
Se añade **toda parada que no sea `entregado`** (incluidas las sin marcar), con
`{cliente: customerName, resultado: resultado ?? null, nota: resultadoNota ?? null, productos: sus líneas}`,
**en el orden en que llegaron los pedidos**.

### Orden de `lineas`
`sort` por **`queda` descendente** y, a igualdad, **`producto.localeCompare(producto)` ascendente**.
*Lo que más queda primero: es por donde se empieza a contar al bajar el camión.*

---

## 13. `avisarEstadoAPedido.ts` — contarle a PEDIDO en qué punto del reparto va cada pedido

**POR QUÉ existe:** en PEDIDO el vendedor ve su pedido y nada más: no sabe si salió, si llegó o si
volvió al almacén. Lo sabe delivery, porque es donde pasan esas cosas. **A la APK de Entrega no se
le puede avisar —trabaja sin conexión—, así que el sitio donde esto tiene que quedar escrito es
PEDIDO, que siempre está en pie y del que la APK sincroniza cuando puede.**

### Estados (`EstadoEntrega`)
| Valor | Significado |
|---|---|
| `despachado` | la ruta se creó con ese pedido dentro: ya está cargado |
| `en_transito` | la ruta arrancó |
| `entregado` | se le dio al cliente |
| `devuelto` | volvió al almacén: el cliente no lo quiso |
| `cancelado` | se canceló antes de salir o durante el reparto |

### Constantes
- `PEDIDO_API_URL = process.env.PEDIDO_API_URL || 'http://localhost:8400'`.
- `KEY = process.env.SERVICE_API_KEY || ''`.
- **`TANDA = 200`.** *PEDIDO acepta hasta 500, pero cada una escribe y publica un aviso en vivo por
  pedido. Con tandas cortas, lo que se pierde si algo se cae es una tanda.*

### `avisarEstadoAPedido(avisos) -> {ok, enviados, aplicados, error?}`
- `avisos` vacío → `{ok: true, enviados: 0, aplicados: 0}` **sin llamar a nada**.
- Sin `KEY` → `{ok: false, enviados: 0, aplicados: 0, error: 'falta SERVICE_API_KEY'}`.
- Por cada tanda de 200: `POST {PEDIDO_API_URL}/integration/orders/status`,
  cabeceras `content-type: application/json` y `x-api-key: KEY`, cuerpo `{pedidos: tanda}`,
  `cache: 'no-store'`.
- `AvisoEstado = {pedidoId, estado, nota?, at?}`. **`pedidoId` es el id EN PEDIDO; delivery lo
  guarda en `externalId` de cada copia.**
- Si `!res.ok` → `error = "PEDIDO contestó <status>"` y **`continue`: se siguen mandando las tandas
  restantes**, no se aborta.
- Si va bien: `aplicados += cuerpo.aplicados?.length ?? 0`; y **sólo si aún no había error** y hay
  `rechazados`, `error = rechazados[0].motivo` (se guarda el PRIMER motivo, no todos).
- Excepción de red → `error = e.message` y sigue con la siguiente tanda.
- **`ok = !error`**: basta un fallo en cualquier tanda para que sea `false`, pero `aplicados` cuenta
  lo que sí entró.

### `avisarEstadoDeFondo(avisos): void`
Dispara sin esperar (`void ... .then`). Si el resultado no es `ok`:
`console.warn('[estado] PEDIDO no tomó los estados:', error)`.
**POR QUÉ:** lo usan el arranque y el cierre de ruta; *quien pulsa el botón no tiene por qué quedarse
mirando a que PEDIDO conteste, y si PEDIDO está caído la ruta arranca igual.* Es «lo mejor que se
pueda»: **si PEDIDO no contesta, aquí no se rompe nada; lo que no se pudo contar se cuenta la
próxima vez que ese pedido se mueva.**

---

## 14. `avisarCambio.ts` — aviso de invalidación a las pantallas

Se publica en **Redis** (`CANAL_CAMBIOS`) y lo reparte `/api/eventos` a cada navegador abierto.

- `TipoCambio = 'pedidos' | 'catalogo' | 'rutas' | 'clientes'`.
  **El aviso lleva QUÉ cambió porque invalidarlo todo en cada cambio significa volver a pedir el
  catálogo entero cada vez que alguien cotiza un domicilio.**
- **Freno (debounce) por tipo: `FRENO_MS = 15000` (15 s)**, con un `Map<tipo, últimoMs>`.
  - Si `ahora − ULTIMO[tipo] < 15000` → **se descarta el aviso y se sale** (no se encola, no se
    reprograma). El sello se actualiza sólo cuando el aviso pasa el freno.
  - **POR QUÉ:** el espejo importa por lotes de doscientos y avisaba por cada uno: **veinte avisos
    seguidos y la pantalla recargándose veinte veces.** Lo que pasa en ese rato **viaja en el
    siguiente aviso**.
- Si `redisEnabled()` es falso → **no hace nada y no falla**; las pantallas siguen refrescando por su
  cuenta **cada treinta segundos**.
- Payload publicado: `{tipo, ...detalle, cuando: new Date().toISOString()}`.
- **Cualquier excepción se traga en silencio:** *un aviso perdido no puede tumbar una importación de
  mil pedidos.* Nunca revienta ni bloquea: es un aviso, no el trabajo.

---

## 15. `src/app/api/routes/route.ts` — armado de ruta

### 15.0 Contexto
`OrderItem`, `StopInput` y `weightFromItems` vivían aquí para **teclear** paradas dentro de una
ruta. Se fueron el **03/09/2026**: *una ruta se arma con pedidos que ya existen, y el peso lo trae
cada pedido ya resuelto desde el espejo.*

### 15.1 `POST /api/routes` — validaciones de entrada (en este orden)
1. `getUserFromRequest` → sin usuario, **401 `Unauthorized`**.
2. Cuerpo: `{name?, vehicleId?, originAddress?, originLat?, originLng?, deliveryDate?, orderIds = [], branchId?}`.
3. `originLat == null || originLng == null` → **400 «Las coordenadas del punto de partida son
   requeridas»** (comparación `==` con null: acepta el 0, rechaza `null` y `undefined`).
4. `!vehicleId` → **400 «Se requiere un vehículo para crear la ruta»**. El vehículo es obligatorio
   aquí aunque luego la comprobación de capacidad tolere que no exista.
5. `scope = resolveScope(req, user)`.
6. **Sucursal de la ruta: `sucursalRuta = scope.branchId ?? (branchId?.trim() || null)`.**
   *Un Super Admin trabaja con alcance «todas», así que `scope.branchId` es null y la ruta se creaba
   sin sucursal —o con la del primer pedido, por casualidad—. Ahora la dice él en el primer paso del
   asistente. Quien SÍ tiene alcance no puede saltárselo pasando otra por el cuerpo: manda el suyo.*
7. Si `orderIds` es array **no vacío** → `createRouteFromExistingOrders(scope.actorId, …)`.
8. **Si no hay `orderIds`: 400 «Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`.»**
   *Aquí se podían TECLEAR las paradas y la ruta creaba pedidos nuevos con ellas. Eso creaba pedidos
   sin folio de PEDIDO: sin factura que atarles, sin cotejo, y por tanto imposibles de repartir bajo
   la regla de que en un camión sólo sube lo facturado. Una puerta para crear algo que no servía.*
   Quitado el **03/09/2026** junto con el alta de pedidos y clientes a mano.

### 15.2 Selección de los pedidos (`prisma.order.findMany`)
Condiciones **todas obligatorias**:
- `id IN orderIds`
- **`source = 'pedido'`** (sólo los del espejo; el alta a mano ya no existe)
- **`routeId IS NULL`** (no está ya en otra ruta)
- **`endLat != null` y `endLng != null`** (sin coordenadas no hay parada)
- `branchId = sucursalRuta`, **sólo si `sucursalRuta` no es nulo**.

**Se busca por SUCURSAL, nunca por quién los creó.** Aquí estaba `userId` y era la razón de «los
pedidos seleccionados ya no están disponibles»: estos pedidos los trae la sincronización desde
PEDIDO, así que su `userId` es el de quien la lanzó, no el de quien crea la ruta. La consulta no
cuadraba con ninguno y el formulario lo contaba como si hubieran desaparecido, cuando estaban ahí,
recién elegidos. **Es el mismo fallo ya corregido para LEER (`scopeWhere`) que al escribir se quedó puesto.**

### 15.3 Rechazos, en orden
1. **`orders.length === 0` → 400** `{error: 'Los pedidos seleccionados ya no están disponibles: <detalle>'}`.
2. **Alguno de los elegidos no volvió → 409**
   `` `${faltan} de los ${orderIds.length} pedidos elegidos no pueden ir en esta ruta: ` + detalle ``

   **Aquí nos separamos del patrón (22/09/2026).** Delivery decía «ya están en otra ruta» para
   los cinco motivos por los que la consulta descarta un pedido —otra ruta, archivado en PEDIDO,
   sin coordenadas de entrega, no vino de PEDIDO, de otra sucursal—, y para tres de ellos
   «Vuelve a elegirlos» es un rechazo permanente disfrazado de reintento: se pulsa otra vez y
   contesta lo mismo. Ahora **cada uno se nombra con su motivo de verdad, y el que va en una ruta
   dice EN CUÁL**. El pliego entero, con la tabla de motivos y su orden de prioridad, en
   `docs/contratos-api.md` §15.1. Es lo que pidió Jose el 21/09/2026: «esto ocurriría cuando la
   ruta se haya creado con pedidos que ya estuvieran en otra ruta, pero hay que notificarlo».

   Y los **repetidos ya no cuentan como faltantes**: mandar dos veces el mismo id daba `1 < 2` y
   contestaba 409 sobre un pedido que estaba libre.
3. **Facturación — `noFacturados = orders.filter(o => o.facturaEstado !== 'igual')`. Si hay alguno →
   409.** Mensaje:
   `` `En una ruta sólo entra lo facturado y que cuadre. ${n} no cumplen: ` + detalle + (n > 5 ? ` y ${n-5} más.` : '.') ``
   donde `detalle` son **los 5 primeros**, `` `${operationNumber || customerName} (${motivo})` ``
   unidos por `', '`, y `motivo` = `'cambió en la factura'` si `cambiado`, `'sin facturar'` si
   `sin_factura`, **`'sin cotejar'` en cualquier otro caso (incluido `null`)**.
   **POR QUÉ se comprueba aquí aunque la pantalla ya filtre:** *una pantalla no es una garantía;
   basta con que alguien mande los ids a mano, o con que un pedido se coteje otra vez entre que se
   eligió y se generó la ruta. Lo que se carga tiene que ser lo que se cobró.* Y se dice CUÁLES:
   *un «no se pudo» a secas obliga a adivinar cuál de los quince pedidos es el que sobra.*
   > Nota de coherencia: el armado exige **estrictamente `facturaEstado === 'igual'`**, más duro que
   > el filtro `con_factura` de `filtrosPedido.ts`, que admite también `cambiado`.
   > **`cambiado` NO entra a una ruta, y se confirmó el 07/10/2026**: ese día se llegó a aceptar
   > «porque también es una factura» y se volvió a `igual` el mismo día. La regla es de Jose y
   > Amado no pidió cambiarla.
3-bis. **Domicilio cobrado — 409** (Amado, 07/10/2026). Todo pedido tiene que traer
   `facturaDomicilio > 0`. Mensaje:
   `` `En una ruta sólo entra lo facturado con domicilio cobrado. ${n} no cumplen: ` + detalle + (n > 5 ? ` y ${n-5} más.` : '.') ``
   con el `detalle` de siempre (5 primeros por número de operación). Nulo, cero y negativo no
   cuentan como cobrado.
3-ter. **Domicilio cotizado — 409** (Amado, 07/10/2026). Todo pedido tiene que traer `pedidoCosto`
   no nulo (el cero SÍ es una cotización; el nulo no). Mensaje:
   `` `No se puede crear la ruta: ${n} pedidos no tienen cotizado el domicilio en Entrega: ` + detalle + (n > 5 ? ` y ${n-5} más.` : '.') ``
   **BLOQUEA, NO AVISA.** Hasta el 07/10/2026 esto era «aviso, no portazo» (decisión de Jose del
   14/09/2026, con los datos delante: 657 de 686 sin costo porque la APK de Entrega no estaba
   encendida) y el pedido entraba valiendo cero con el total de la ruta más bajo. Amado lo
   cambió: el domicilio ya es un servicio que se cobra y dejar entrar cualquier pedido es una
   vulnerabilidad. **Si vuelve a haber pedidos sin costo en masa, la respuesta es cotizarlos en
   Entrega, no abrir la puerta.** Ver §15.13.
4. **Capacidad por peso:** `totalW = Σ (o.weight || 0)` (un peso sin resolver cuenta **0 kg**).
   `vehicle = vehicleId ? Vehicle.findFirst({id}) : null`.
   **Si `vehicle` existe y `totalW > vehicle.capacity` → 400**
   `` `Peso total (${totalW.toFixed(1)} kg) supera la capacidad del vehículo (${vehicle.capacity} kg)` ``.
   Casos límite deliberados: **comparación estricta `>` (igualar la capacidad exacta SÍ pasa)**; si
   el `vehicleId` no corresponde a ningún vehículo, **no se valida capacidad y la ruta se crea igual**;
   el peso del mensaje va a **1 decimal** y la capacidad sin formatear.
   **Antes de la capacidad** (07/10/2026, incidencia 4 de Amado): si el vehículo existe y está
   **inactivo** (`isActive = false`) → **400 «El vehículo está inactivo y no se puede asignar a una
   ruta.»** Lo mismo al cambiarle el camión a una ruta y al armar una zona del tablero (camión del
   cuerpo o previsto). Quitar el camión de una ruta no pasa por la comprobación.

### 15.4 Sucursal de la ruta
`routeBranchId = opts.branchId ?? orders[0].branchId ?? null`.
*La ruta pertenece a la sucursal de sus pedidos, o a la elegida por el admin.*

### 15.5 Código de ruta — `generateRouteCode()`
- `prefix = 'RT-' + YYYYMMDD + '-'`, con la fecha de **hoy en UTC** (`toISOString().slice(0,10)` sin
  guiones).
- `count = Route.count({routeCode startsWith prefix})`; `seq = String(count + 1).padStart(3, '0')`.
- Resultado: `RT-20260914-001`.
- **Caso límite conocido: se cuenta, no se lee el máximo — si se borra una ruta del día, el
  siguiente código se repite; y no hay bloqueo, así que dos creaciones simultáneas pueden chocar.**

### 15.6 Creación de la `Route`
`{name: name || null, routeCode, userId, vehicleId (sólo si viene), branchId (sólo si no es nulo),
originAddress: originAddress ?? null, originLat, originLng,
deliveryDate: deliveryDate ? new Date(deliveryDate) : null}`.

### 15.7 Orden de las paradas
- `stopsForOpt = orders.map(o => ({id, lat: o.endLat, lng: o.endLng}))` — **se usa `endLat/endLng`
  (el destino), no `lat/lng`**.
- `optimizedIds = (stopsForOpt.length > 1) ? greedyRouteOptimization(origin, stopsForOpt) : [su id]`.
- Es decir: **vecino más próximo desde el origen (§1.2), con Haversine**, sin volver atrás ni
  optimizar después. `stopOrder` = posición en ese orden, **empezando en 1**.
- El orden en que salen de la base (`findMany`) determina el desempate del greedy.

### 15.8 Kilómetros — DOS medidas distintas, no confundirlas
1. **`route.totalDistance` (km reales del camión, informativo):**
   `Σ calculateRouteSegments(origin, orderedStops)` **+ el regreso**
   `haversineDistance(últimaParada, origin)`. El cierre sólo se suma **si hay al menos una parada**.
   O sea: `origen→p1→p2→…→pn→origen`.
2. **`order.segmentKm` (por pedido):** `haversineDistance(origin, o.endLat, o.endLng)` —
   **la distancia DIRECTA desde el almacén/origen a ese cliente**, NO el tramo del recorrido
   anterior→actual. Es la medida con la que se cobra un domicilio (misma base que
   `domicilioEntrega.ts`). Su nombre engaña; conservar la semántica.

Ninguna de las dos se redondea al guardarse.

### 15.9 Totales y escritura por pedido
Recorriendo `optimizedIds` con índice `i` desde 0:
- `totalWeight += o.weight || 0`
- **`totalPrice += o.pedidoCosto || 0`** — *el costo del domicilio es el de PEDIDO: lo pone el
  repartidor desde Entrega.* (`deliveryPrice` **no** participa.)
- `Order.update`: `{routeId: route.id, ultimaRutaId: route.id, stopOrder: i + 1,
  tripLeg: 'outbound', segmentKm: distKm, price: o.pedidoCosto || 0}`.
  - **`ultimaRutaId` va junto a `routeId` y no se suelta nunca: es en qué camión viajó** (cuando el
    pedido se devuelve y `routeId` vuelve a null, `ultimaRutaId` se queda).
  - `price` se **copia** de `pedidoCosto`; un `null` se guarda como **0** aquí.
  - Las actualizaciones se hacen **una a una y sin transacción**.
- Luego `Route.update {totalDistance, optimized: true}`.
  - **Nos separamos aquí (29/09/2026):** `totalWeight`, `totalPrice` y `paradasSinCotizar`
    **ya no se escriben al armar**. Un total escrito una vez se queda con el número de aquel
    día mientras sus paradas siguen moviéndose —el espejo de PEDIDO repasa `weight` y
    `pedidoCosto` cada minuto—, y de ahí salieron el `$0.00` del 22/09 y los «420 kg» sobre
    dos paradas de 516,5 del 28/09. Los mantiene la base en cada cambio de paradas
    (`api/db/migrations/00014_los_totales_de_la_ruta_no_se_congelan.sql`). `totalWeight` se
    sigue sumando aquí para validar la capacidad ANTES de crear nada, que es otra cosa.

### 15.10 El vehículo NO se ocupa al crear la ruta
*Crear una ruta no ocupa el camión: se planifica, no se despacha.* Se marcaba «en uso» al crearla,
así que **el camión que está repartiendo ahora no se podía usar para armar la ruta de mañana — y
armarla es justo lo que se hace mientras el camión está fuera.** El camión se ocupa cuando la ruta
pasa a **EN CURSO** y se libera al **completarla**.

### 15.11 Efectos finales
- Se relee la ruta con `vehicle {id,name,type,plate,capacity}` y `orders` ordenados por `stopOrder asc`.
- `await avisarCambio('rutas')` — *una ruta nueva se lleva pedidos de la lista de disponibles: hay
  que enterarse.*
- `avisarEstadoDeFondo(...)` con los pedidos que tengan `source === 'pedido'` **y** `externalId`,
  estado **`'despachado'`**. *Es la primera noticia que tiene el vendedor de que su pedido se movió.
  Va de fondo: si PEDIDO no contesta, la ruta se crea igual — lo que no puede pasar es que no se
  pueda armar una ruta porque otra aplicación esté caída.*
- Respuesta **201** con la ruta completa.

### 15.12 `GET /api/routes`
- Sin usuario → **401**.
- `where = scopeWhere(resolveScope(...))`, `orderBy createdAt desc`.
- Incluye **`branch {id, name, externalId}`**: *no venía, y el Super Admin —que las ve todas— tenía
  las de las ocho sucursales en una sola lista sin nada que las distinguiera: dos rutas del mismo día
  con el mismo aspecto podían ser de Holguín y de La Habana. La pantalla las agrupa por aquí.*
- Incluye `vehicle {id,name,type,plate,capacity}` y `orders` ordenados por `stopOrder asc` con:
  `id, operationNumber, customerName, address, endAddress, endLat, endLng, status, weight, lat, lng,
  price, segmentKm, stopOrder, tripLeg, items, resultado, resultadoNota, municipio`.
  **`resultado`/`resultadoNota` son cómo acabó la parada al volver el camión: de ahí sale el
  post-despacho (§12) — lo que queda arriba es lo que no se entregó.**
- `dynamic = 'force-dynamic'` (sin caché de Next).

---

## Apéndice — constantes en un vistazo

| Constante | Valor | Dónde |
|---|---|---|
| Radio terrestre | `6371` km | `pricing.ts`, `domicilioEntrega.ts` |
| Redondeo de importes | 2 decimales, `+ Number.EPSILON` | `domicilioEntrega.ts` |
| Redondeo de km/kg informativos | 3 decimales | `domicilioEntrega.ts` |
| `WAREHOUSE_API_URL` por defecto | `http://10.188.2.2:3001/api/external-api` | `warehouse.ts` |
| TTL caché de pesos | `WAREHOUSE_WEIGHTS_TTL` o **600 s** | `warehouse.ts` |
| Tope `ventraVentas` | `5000` líneas | `warehouse.ts` |
| Caché de tasa (existe) | `TASA_CACHE_MS` o **5 min** | `tasaCambio.ts` |
| Caché de tasa (no hay) | `TASA_CACHE_VACIA_MS` o **20 s** | `tasaCambio.ts` |
| Caché de almacenes | `ALMACENES_CACHE_MS` o **5 min** | `almacenes.ts` |
| Tanda de avisos a PEDIDO | **200** (PEDIDO admite 500) | `avisarEstadoAPedido.ts` |
| `PEDIDO_API_URL` por defecto | `http://localhost:8400` | `avisarEstadoAPedido.ts` |
| Freno de avisos SSE | **15 s** por tipo | `avisarCambio.ts` |
| Refresco de pantalla sin Redis | 30 s | `avisarCambio.ts` |
| Zoom del mapa | acotado a `[8, 16]`, `13 − log2(√área)` | `geocode.ts` |
| Longitud mínima para geocodificar | 4 caracteres | `geocode.ts` |
| Decimales de coordenadas mostradas | 5 | `geocode.ts` |
| Fuzzy de producto | Damerau ≤ 1, token ≥ 4 chars, candidata **única** | `productMatch.ts` |
| Clave de Ventra en el match por contención | longitud ≥ 4 | `emparejarVentra.ts` |
| Formato de código de ruta | `RT-YYYYMMDD-NNN` (UTC, `count+1`) | `routes/route.ts` |

### 15.13 La regla de entrada a una ruta — Amado, 07/10/2026 (`docs/incidencias-reparto.md`, puntos 2 y 6)

> «Al crear una nueva ruta, solo deben considerarse los pedidos "facturados" que tengan
> domicilio, ya que el domicilio ahora es un servicio que se cobra. Si se permite cualquier
> pedido, es una vulnerabilidad.»

**Entra a una ruta, o a una zona del tablero, el pedido que cumple LAS TRES:**

1. **Facturado y que cuadre**: `facturaEstado = 'igual'`. (La lista de disponibles y «Sin
   colocar» también ofrecen `cambiado` para que se revise; **una ruta no lo acepta**.)
2. **Domicilio cobrado**: `facturaDomicilio > 0`.
3. **Domicilio cotizado en Entrega**: `pedidoCosto` no nulo.

**Bloquea, no avisa.** Sustituye a «los avisos del armador son aviso, no bloqueo» (Jose,
14/09/2026), que se escribió con el 96 % de los pedidos sin costo porque la APK de Entrega no
estaba encendida. Lo que se rechaza **se nombra por su número de operación** (§ «El conduce»).

**Dónde se aplica, y tiene que ser lo MISMO en todos** (`CLAUDE.md` §3-bis: dos preguntas sobre lo
mismo se atan con una prueba, no con un comentario; el 07/10/2026 las dos condiciones se añadieron
a `ColocarPedido` y no a «Sin colocar», y el tablero ofrecía tarjetas que el `409` devolvía):

| Sitio | Condiciones |
|---|---|
| `GET /api/orders/available` y su contador | `igual`/`cambiado` + las dos |
| «Sin colocar» del tablero y su contador | `igual`/`cambiado` + las dos |
| `PUT /api/board/placements/{id}` (`ColocarPedido`) | **sólo las dos** (no mira `facturaEstado`) |
| Armar una zona (`descartados`) | `igual` + las dos |
| `POST /api/routes` (validación y `UPDATE` que engancha) | `igual` + las dos (el `UPDATE` sólo las dos) |
| Panel: `sin_ruta`, `peso_pendiente`, por sucursal | `igual`/`cambiado` + las dos |

> **Divergencia conocida, PENDIENTE de decidir (07/10/2026):** el Panel del SERVIDOR cuenta
> `igual`/`cambiado` + las dos (decisión D2: no se tocó su criterio de `factura_estado`), pero el
> Panel de la APLICACIÓN lo calcula en local (`consultas_panel.dart`, `_repartible`) y cuenta
> sólo `igual`. Las dos cifras pueden diferir en los pedidos `cambiado`. Antes de que se noten
> hay que elegir un criterio para las dos; no se resolvió aquí.

Lo ata `api/internal/store/sqlc/consultas_motor_real_test.go` contra Postgres de verdad y
`api/internal/store/guardas_del_reparto_test.go` por su texto.

**El conduce.** Jose, 07/10/2026: el *conduce* **es el número de operación de la factura**
(`orders.operation_number`, p. ej. `PTB25-261005-1479`). No hay dato ni columna nueva: la
identificación ya existe y ese número se puede usar y mostrar como conduce. «El cobro a
domicilio que sale como conduce» (punto 6 de Amado) no es un caso aparte: es un pedido más.
Todos los rechazos de armado nombran cada pedido por ese número.

**Quitar UNA parada de una ruta planificada** (punto 2): `DELETE /api/routes/{id}/stops/{orderId}`.
Suelta `route_id` **y `ultima_ruta_id`** (si no, el pedido seguiría contando en los totales de la
ruta y saldría en su hoja de cierre: la «parada fantasma»); no renumera los `stop_order` ni
recalcula `total_distance`. Si la ruta nació del tablero, la parada vuelve a su zona y su posición.

**Borrar una ruta armada desde el tablero** (punto 3): las paradas vuelven a su zona
(`board_route_origins`); si la zona ya no existe, quedan en «sin colocar».

**Vehículos** (puntos 4 y 5): un vehículo con rutas, aunque sean históricas, no se borra: se marca
`isActive = false` y deja de ofrecerse para rutas nuevas. `orders.vehicle_id` ya no existe: el
camión de un pedido es el de su ruta.

### 15.14 Lo que endurece la 1.0.29 (auditoría de la 1.0.28, 08/10/2026)

Seis reglas nacidas de la auditoría. Cada una tiene su prueba **en pareja** (avisa cuando toca, no
avisa cuando no) y la guarda de SQL, su prueba de motor real.

1. **El alcance falla cerrado** (§ 11): la cabecera sólo la lee quien ve todas; una sucursal que
   Reparto no conoce es un 403 que dice cuál, no «todas».
2. **`PATCH /api/orders/{id}` ya no mueve pedidos entre rutas, ni de estado, ni de precio/peso/orden.**
   `routeId`, `status`, `price`, `weight` y `stopOrder` se rechazan con `400 Ese campo no se cambia
   por aquí: usa las rutas o el tablero (<campos>)`, y no se aplica nada del cuerpo. Antes se saltaba
   TODAS las reglas del armado (sucursal de la ruta, estado de la ruta, facturado, domicilio
   cobrado y cotizado). Se quitó también de la consulta: `ActualizarPedido` ya no tiene esas columnas.
3. **El camión de otra sucursal no se asigna al armar** (`POST /api/routes`): `400 No existe el
   vehículo '<id>'`, antes que `is_active`. Propio y compartido (`branch_id` NULL) valen. Es lo mismo
   que ya hacían el cambio de camión de una ruta y el armado del tablero.
4. **Un camión compartido sólo lo cambia, desactiva o borra quien ve todas las sucursales**
   (`SUPER ADMIN`, `DESARROLLADOR`): `403` en `PATCH`/`DELETE`. Ver y usarlo sigue siendo de todas;
   quién crea o edita un camión propio no cambia.
5. **Reasignar un devuelto o cancelado es un intento nuevo**: al asignarlo a una ruta se limpian
   `resultado`, `resultado_at`, `resultado_nota` y `delivered_at` (sólo hay una consulta que asigna
   pedidos a rutas, `EngancharPedidoARuta`, y la usan el armado y el tablero). Un entregado no se
   reasigna nunca. La app lo replica en su armado local.
6. **Los rechazos del cierre nombran la parada por su número de operación** (el conduce), no por su
   UUID: `rechazados[].numeroOperacion` y el `error`. Se lee con el alcance de quien cierra.

**Rastro de quién.** Las acciones que cambian datos dejan una línea `Info` con `actor` (el `sub`,
nunca el token) y los ids: ver «Rastro de quién» en `contratos-api.md`.

**Decisión abierta de Jose.** `PUT /api/settings` y `POST /api/admin/recompute` no exigen
`ExigirAdmin`: cualquier rol con sesión puede cambiar la tasa del día y lanzar un recosteo de
hasta 5.000 pedidos. Esta entrega sólo les pone el rastro; si deben exigir admin lo decide él.
