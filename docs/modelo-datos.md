# Modelo de datos — delivery (Prisma + PostgreSQL)

Fuente: `prisma/schema.prisma` (datasource `postgresql`, generator `prisma-client-js`).
11 modelos: `User`, `Product`, `Customer`, `Branch`, `SavedOrigin`, `Vehicle`, `Order`,
`OrderVehicle`, `Route`, `VentaFacturada`, `Settings`.

Tipos Prisma → Postgres (mapeo por defecto, sin `@db.*` en ningún campo del esquema):

| Prisma | Postgres | Go sugerido |
|---|---|---|
| `String` | `text` | `string` |
| `String?` | `text NULL` | `*string` / `sql.NullString` |
| `Int` | `integer` | `int32` |
| `Float` | `double precision` | `float64` |
| `Boolean` | `boolean` | `bool` |
| `DateTime` | `timestamp(3)` | `time.Time` |
| `Json` | `jsonb` | `json.RawMessage` / `map[string]any` |

No hay `enum` de Prisma en todo el esquema: **todos los estados son `String`** (ver §3).
No hay `onDelete` explícito salvo en `OrderVehicle` (`Cascade` en ambos FK). El resto de
relaciones usa el default de Prisma (`SetNull` para FK opcionales, `Restrict` para las
obligatorias) — al reconstruir en Go/SQL hay que declararlo a mano.

---

## 1. Modelos

### 1.1 `User`

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `email` | String | no | — | `@unique` |
| `password` | String | no | — | hash |
| `name` | String | no | — | |
| `role` | String | no | `"admin"` | pseudo-enum, §3.1 |
| `createdAt` | DateTime | no | `now()` | |
| `branchId` | String? | sí | — | FK → `Branch.id`, relación `UserBranch` |

Índices/restricciones: PK `id`; UNIQUE `email`. **No hay `updatedAt`.**

Relaciones salientes (colecciones): `orders Order[]`, `routes Route[]`, `vehicles Vehicle[]`,
`savedOrigins SavedOrigin[]`, `products Product[]`, `createdBranches Branch[]` (`BranchCreator`),
`branch Branch?` (`UserBranch`).

---

### 1.2 `Product`

Catálogo espejo de Ventra **por sucursal**. Se llena solo (sondeo cada 12 h,
`src/app/api/products/sync/route.ts`); no hay alta manual.

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `name` | String | no | — | escrito por el sync |
| `weight` | Float | no | `0` | kg por **unidad de venta** (pack/caja) |
| `packaging` | String? | sí | — | legado; el sync NO lo escribe |
| `unitsPerPackage` | Float? | sí | — | legado; el sync NO lo escribe |
| `category` | String? | sí | — | de Ventra |
| `sku` | String? | sí | — | código de Ventra; clave de reconciliación |
| `sucursalCodigo` | String? | sí | — | `HAB`, `CMG`… `null` = fila antigua/global |
| `price` | Float? | sí | — | precio EN esa sucursal |
| `stock` | Float? | sí | — | existencias EN esa sucursal |
| `unit` | String? | sí | — | unidad de venta |
| `traidoAt` | DateTime? | sí | — | cuándo lo trajo Ventra (frescura) |
| `userId` | String | no | — | FK → `User.id` (dueño del catálogo) |
| `createdAt` | DateTime | no | `now()` | |
| `updatedAt` | DateTime | no | `now()` + `@updatedAt` | |

Índices/restricciones: PK `id`; `@@unique([sucursalCodigo, sku])` (clave del upsert);
`@@index([sucursalCodigo])`; `@@index([name])`.

Ojo Go/SQL: en Postgres un UNIQUE con `sucursalCodigo NULL` **no** impide duplicados
(NULL ≠ NULL). Si hay filas antiguas con `sucursalCodigo = NULL` el upsert por esa clave no
las dedupica. Considerar `NULLS NOT DISTINCT` o un centinela.

---

### 1.3 `Customer`

Espejo de los clientes **geolocalizados** de PEDIDO. Mismo patrón que `Order`:
`source` + `externalId`, idempotente. Se sincroniza en `sync-queue.mjs::syncCustomers()`.
Sin `lat`/`lng` no entra (se filtra antes de escribir).

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `source` | String? | sí | — | `"pedido"` o `null` (manual). §3.5 |
| `externalId` | String? | sí | — | id del cliente EN PEDIDO |
| `name` | String | no | — | |
| `phone` | String? | sí | — | |
| `address` | String? | sí | — | |
| `municipio` | String? | sí | — | |
| `zona` | String? | sí | — | |
| `codigo` | String? | sí | — | código tipo `SC06TCP1257` |
| `vendedor` | String? | sí | — | desnormalizado de `meta` para poder filtrar |
| `lat` | Float | **no** | — | obligatorio |
| `lng` | Float | **no** | — | obligatorio |
| `sucursalCodigo` | String? | sí | — | |
| `meta` | Json? | sí | — | payload COMPLETO de PEDIDO (`jsonb`) |
| `syncedAt` | DateTime | no | `now()` | se reescribe a `now()` en cada update del sync |
| `createdAt` | DateTime | no | `now()` | |
| `updatedAt` | DateTime | no | `@updatedAt` | |

Índices: PK `id`; `@@index([source, externalId])`; `@@index([vendedor])`; `@@index([codigo])`.
**No hay UNIQUE sobre `[source, externalId]`** — la idempotencia es aplicativa
(`findFirst` + `update`/`create`). En Go conviene añadir el UNIQUE real.

Sin relaciones. El borrado de bajas es un `deleteMany` de `source='pedido'` con `id notIn`
la lista traída; nunca toca `source = null`.

---

### 1.4 `Branch`

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `name` | String | no | — | |
| `address` | String? | sí | — | |
| `lat` | Float | no | — | punto de partida (almacén) |
| `lng` | Float | no | — | |
| `areaKm2` | Float | no | `1` | |
| `externalId` | String? | sí | — | **`@unique`**; id de la sucursal en PEDIDO |
| `originConfigured` | Boolean | no | `false` | mientras sea `false` NO se cotizan domicilios de esta sucursal |
| `creatorId` | String | no | — | FK → `User.id` (`BranchCreator`) |
| `createdAt` | DateTime | no | `now()` | |

Índices/restricciones: PK `id`; UNIQUE `externalId`. **No hay `updatedAt`.**

Colecciones: `members User[]` (`UserBranch`), `origins SavedOrigin[]`, `orders Order[]`,
`vehicles Vehicle[]` (`BranchVehicles`), `routes Route[]` (`BranchRoutes`).

También se usa como `sucursalCodigo` de facto: en el sync de catálogo el código es
`branch.externalId ?? branch.name`.

---

### 1.5 `SavedOrigin`

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `name` | String | no | — | |
| `address` | String | **no** | — | obligatorio |
| `lat` | Float | no | — | |
| `lng` | Float | no | — | |
| `userId` | String | no | — | FK → `User.id` |
| `branchId` | String? | sí | — | FK → `Branch.id` |
| `createdAt` | DateTime | no | `now()` | |

Índices: solo PK. Sin `@@index`, sin UNIQUE. **No hay `updatedAt`.**

---

### 1.6 `Vehicle`

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `name` | String | no | — | |
| `type` | String | no | `"truck"` | pseudo-enum abierto, §3.4 |
| `plate` | String? | sí | — | sin UNIQUE |
| `capacity` | Float | no | `1000` | kg; se valida contra `Route.totalWeight` al crear ruta |
| `costoKmUsd` | Float? | sí | — | USD/km declarado por el camionero |
| `usarParaDomicilio` | Boolean | no | `false` | vehículo de referencia de la sucursal (debería ser uno solo; **no está forzado**) |
| `status` | String | no | `"available"` | pseudo-enum, §3.3 |
| `notes` | String? | sí | — | |
| `userId` | String | no | — | FK → `User.id` |
| `branchId` | String? | sí | — | FK → `Branch.id` (`BranchVehicles`); `null` = de todas |
| `createdAt` | DateTime | no | `now()` | |
| `updatedAt` | DateTime | no | `@updatedAt` | |

Índices: solo PK. Ningún `@@index` ni UNIQUE pese a que se filtra por `branchId`.

Colecciones: `routes Route[]`, `orders Order[]`, `orderAssignments OrderVehicle[]`.

---

### 1.7 `Order`

El modelo central. Mezcla tres cosas: copia del pedido de PEDIDO (espejo), estado de reparto
de delivery, y resultado del cierre de ruta.

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `operationNumber` | String? | sí | — | nº de operación/folio en PEDIDO (§6) |
| `customerName` | String | **no** | — | obligatorio para persistir la cotización |
| `address` | String | **no** | — | fallback: `input.address || customerName` |
| `endAddress` | String? | sí | — | dirección de destino |
| `endLat` | Float? | sí | — | destino; lo usa el optimizador de ruta |
| `endLng` | Float? | sí | — | |
| `lat` | Float? | sí | — | duplicado de `endLat` al importar |
| `lng` | Float? | sí | — | duplicado de `endLng` al importar |
| `weight` | Float | no | `1` | kg calculados (§5); `0` = sin peso resuelto |
| `status` | String | no | `"pending"` | pseudo-enum de reparto, §3.2 |
| `tripLeg` | String | no | `"outbound"` | `outbound` \| `return`, §3.6 |
| `notes` | String? | sí | — | |
| `routeId` | String? | sí | — | FK → `Route.id`, relación **`RutaActual`**. Ocupación actual; se libera |
| `ultimaRutaId` | String? | sí | — | FK → `Route.id`, relación **`RutaViajada`**. Histórico; NO se libera nunca |
| `vehicleId` | String? | sí | — | FK → `Vehicle.id` |
| `userId` | String | no | — | FK → `User.id` (= `branch.creatorId` al importar) |
| `price` | Float? | sí | — | reparto de ruta (§5) |
| `segmentKm` | Float? | sí | — | km origen→parada (§5) |
| `deliveryPrice` | Float? | sí | — | precio del envío individual (§5) |
| `deliveryDistanceKm` | Float? | sí | — | km sucursal→cliente (§5) |
| `branchId` | String? | sí | — | FK → `Branch.id`; sucursal de origen del cálculo |
| `source` | String? | sí | — | `"pedido"` \| `null` (manual), §3.5 |
| `orderDate` | DateTime? | sí | — | fecha DEL PEDIDO en PEDIDO (≠ `createdAt`) |
| `pedidoUpdatedAt` | DateTime? | sí | — | marca de agua del espejo: `since = max(pedidoUpdatedAt)` |
| `estado` | String? | sí | — | estado EN PEDIDO, §3.7 |
| `archivado` | Boolean | no | `false` | borrado blando en PEDIDO |
| `fechaComprometida` | DateTime? | sí | — | `expirado` NO se guarda: se deriva (`< now()` y no completada) |
| `requiereDomicilio` | Boolean? | sí | — | tri-estado: `true`/`false`/`null` (desconocido) |
| `pedidoCosto` | Float? | sí | — | costo del domicilio puesto por la APK Entrega |
| `municipio` | String? | sí | — | copiado de `meta` para poder filtrar |
| `productosTexto` | String? | sí | — | nombres de items concatenados con `" · "` (§5) |
| `facturaEstado` | String? | sí | — | §3.8 |
| `facturaNumero` | String? | sí | — | |
| `facturaAt` | DateTime? | sí | — | |
| `facturaDomicilio` | Float? | sí | — | lo que la factura cobró por reparto |
| `facturaCorregidoAt` | DateTime? | sí | — | cuándo PEDIDO reescribió el pedido según factura |
| `vendedor` | String? | sí | — | copiado de `meta` |
| `sucursalCodigo` | String? | sí | — | |
| `externalId` | String? | sí | — | id/folio en PEDIDO; clave de idempotencia (§6) |
| `items` | Json | **no** | `"[]"` | `[{description|name, quantity, ...peso resuelto}]` |
| `customerPhone` | String? | sí | — | |
| `meta` | Json? | sí | — | payload COMPLETO (cliente + pedido) |
| `createdAt` | DateTime | no | `now()` | cuándo lo copió el espejo |
| `updatedAt` | DateTime | no | `@updatedAt` | |
| `stopOrder` | Int? | sí | — | orden de parada, 1-based (§5) |
| `deliveredAt` | DateTime? | sí | — | (§5) |
| `resultado` | String? | sí | — | `entregado` \| `devuelto` \| `cancelado`, §3.9 |
| `resultadoAt` | DateTime? | sí | — | (§5) |
| `resultadoNota` | String? | sí | — | motivo; truncado a **500** caracteres en la API |

Índices (`@@index`, todos simples salvo el primero):
`[source, externalId]`, `[orderDate]`, `[pedidoUpdatedAt]`, `[estado]`, `[archivado]`,
`[municipio]`, `[vendedor]`, `[requiereDomicilio]`, `[resultado]`, `[ultimaRutaId]`.

**No hay UNIQUE sobre `[source, externalId]`**: la idempotencia es aplicativa
(`findFirst({source:'pedido', externalId})` → `update` o `create` en
`src/app/api/quote/batch/route.ts`). Es una carrera latente; en Go conviene UNIQUE parcial
`WHERE source IS NOT NULL AND external_id IS NOT NULL`.

**No hay índice sobre `routeId`** pese a que es el filtro más caliente
(`routeId: null` = disponible). Añadirlo.

Colecciones: `vehicleAssignments OrderVehicle[]`.

---

### 1.8 `OrderVehicle`

Tabla puente (asignación múltiple de vehículos a un pedido).

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `orderId` | String | no | — | FK → `Order.id`, **`onDelete: Cascade`** |
| `vehicleId` | String | no | — | FK → `Vehicle.id`, **`onDelete: Cascade`** |
| `isPrimary` | Boolean | no | `false` | |
| `createdAt` | DateTime | no | `now()` | |

Restricciones: PK `id`; `@@unique([orderId, vehicleId])`. **No hay `updatedAt`.**

Convive con `Order.vehicleId` (asignación simple). Dos mecanismos para lo mismo; nada
garantiza que concuerden.

---

### 1.9 `Route`

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `name` | String? | sí | — | |
| `routeCode` | String? | sí | — | `RT-YYYYMMDD-NNN` (§6); **sin UNIQUE** |
| `status` | String | no | `"planned"` | pseudo-enum, §3.3 |
| `originAddress` | String? | sí | — | |
| `originLat` | Float? | sí | — | |
| `originLng` | Float? | sí | — | |
| `totalDistance` | Float | no | `0` | km del recorrido incl. regreso (§5) |
| `totalWeight` | Float | no | `0` | kg (§5). **No se escribe al armar: es la suma de las paradas y la mantiene la base** (00014) |
| `totalPrice` | Float | no | `0` | (§5). Ídem, y suma sólo lo cotizado: va con `paradasSinCotizar` |
| `deliveryDate` | DateTime? | sí | — | fecha planificada |
| `vehicleId` | String? | sí | — | FK → `Vehicle.id` |
| `userId` | String | no | — | FK → `User.id` |
| `branchId` | String? | sí | — | FK → `Branch.id` (`BranchRoutes`) |
| `startedAt` | DateTime? | sí | — | se marca al pasar a `in_progress` (§5) |
| `finishedAt` | DateTime? | sí | — | se marca al pasar a `completed` (§5) |
| `createdAt` | DateTime | no | `now()` | |
| `updatedAt` | DateTime | no | `@updatedAt` | |
| `optimized` | Boolean | no | `false` | **quién ordenó las paradas**: `true` si lo hizo `ordenDeVisita`, `false` si se respetó el orden que puso la persona (`optimizar:false`). No es «ya se calculó algo»: es una firma, y escribirla en falso hace que nadie vuelva a optimizar esa ruta |

Índices: **solo PK**. Ninguno sobre `status`, `branchId`, `deliveryDate`, `routeCode`.
`generateRouteCode()` cuenta filas con `startsWith(prefix)` sin bloqueo → colisión posible
con concurrencia; en Go usar secuencia o UNIQUE + reintento.

Colecciones: `orders Order[]` (`RutaViajada`, por `ultimaRutaId`),
`paradas Order[]` (`RutaActual`, por `routeId`).

---

### 1.10 `VentaFacturada`

**RETIRADA**: ya no se escribe desde ningún punto de `src/`. El cotejo contra facturación se
hace en PEDIDO y llega copiado en `Order.facturaEstado`. Se conserva con los datos históricos.

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `ventraId` | String | no | — | **`@unique`**; id de la línea en Ventra |
| `sucursalCodigo` | String | **no** | — | `HAB`, `CMG`… |
| `fecha` | DateTime | **no** | — | |
| `operNumber` | String | **no** | — | nº de factura; varias líneas lo comparten |
| `clienteCodigo` | String? | sí | — | |
| `clienteNombre` | String | **no** | — | |
| `productoCodigo` | String? | sí | — | |
| `productoNombre` | String | **no** | — | |
| `cantidad` | Float | **no** | — | |
| `precioUsd` | Float? | sí | — | |
| `traidoAt` | DateTime | no | `now()` | |

Índices: PK `id`; UNIQUE `ventraId`; `@@index([sucursalCodigo, fecha])`;
`@@index([clienteNombre])`; `@@index([operNumber])`.
**No hay `createdAt` ni `updatedAt`** (`traidoAt` hace de ambos).

---

### 1.11 `Settings`

Singleton de facto: el código hace `findFirst()` y, si no hay, `create({data:{}})`
(`src/app/api/settings/route.ts`, `products/sync`, `quote/batch`, `sync-queue.mjs`).
**Nada impide que existan varias filas.** En Go: PK fija (`id = 'singleton'`) o
`CHECK`/índice único sobre constante.

| Campo | Tipo | Opcional | Default | Notas |
|---|---|---|---|---|
| `id` | String | no | `cuid()` | PK |
| `syncBarridoDia` | Int | no | `0` | posición del barrido histórico, en días hacia atrás; da la vuelta al llegar a `HISTORICO_DIAS` |
| `catalogoTraidoAt` | DateTime? | sí | — | sólo se actualiza si entró ≥1 producto |
| `currency` | String | no | `"USD"` | |
| `cupRate` | Float | no | `320.0` | CUP por 1 USD |
| `cupRateUpdatedAt` | DateTime | no | `now()` | |
| `currencies` | Json | no | `"[]"` | `[{"code":"CUP","rate":320}]`, rate = unidades por 1 USD |

Índices: solo PK. **No hay `createdAt` ni `updatedAt`.**

Deuda detectada: `src/app/(dashboard)/vehicles/page.tsx` lee y escribe
`settings.tiposVehiculo` (línea 120, 124, 139) y ese campo **no existe en el esquema**.
Los parámetros de precio (`dom*`, `domConfigured`, tarifa base, costo/km, costo/kg) se
eliminaron el 03/09/2026 (migración `20260903130000_fuera_los_precios`).

---

## 2. Relaciones (ambos sentidos)

| Origen | Campo FK | Destino | Cardinalidad | Nombre de relación | Inversa |
|---|---|---|---|---|---|
| `User` | `branchId?` | `Branch` | N:1 opcional | `UserBranch` | `Branch.members User[]` |
| `Branch` | `creatorId` | `User` | N:1 obligatoria | `BranchCreator` | `User.createdBranches Branch[]` |
| `Product` | `userId` | `User` | N:1 obligatoria | — | `User.products Product[]` |
| `SavedOrigin` | `userId` | `User` | N:1 obligatoria | — | `User.savedOrigins SavedOrigin[]` |
| `SavedOrigin` | `branchId?` | `Branch` | N:1 opcional | — | `Branch.origins SavedOrigin[]` |
| `Vehicle` | `userId` | `User` | N:1 obligatoria | — | `User.vehicles Vehicle[]` |
| `Vehicle` | `branchId?` | `Branch` | N:1 opcional | `BranchVehicles` | `Branch.vehicles Vehicle[]` |
| `Order` | `userId` | `User` | N:1 obligatoria | — | `User.orders Order[]` |
| `Order` | `branchId?` | `Branch` | N:1 opcional | — | `Branch.orders Order[]` |
| `Order` | `vehicleId?` | `Vehicle` | N:1 opcional | — | `Vehicle.orders Order[]` |
| `Order` | `routeId?` | `Route` | N:1 opcional | **`RutaActual`** | `Route.paradas Order[]` |
| `Order` | `ultimaRutaId?` | `Route` | N:1 opcional | **`RutaViajada`** | `Route.orders Order[]` |
| `Route` | `userId` | `User` | N:1 obligatoria | — | `User.routes Route[]` |
| `Route` | `vehicleId?` | `Vehicle` | N:1 opcional | — | `Vehicle.routes Route[]` |
| `Route` | `branchId?` | `Branch` | N:1 opcional | `BranchRoutes` | `Branch.routes Route[]` |
| `OrderVehicle` | `orderId` | `Order` | N:1, Cascade | — | `Order.vehicleAssignments` |
| `OrderVehicle` | `vehicleId` | `Vehicle` | N:1, Cascade | — | `Vehicle.orderAssignments` |

`Order` ↔ `Vehicle` es **N:M** a través de `OrderVehicle` (UNIQUE `[orderId, vehicleId]`),
y además **N:1** directa por `Order.vehicleId`.

`Customer` y `VentaFacturada` **no tienen ninguna relación declarada**. La correspondencia
`Customer` ↔ `Order` es lógica, por `codigo`/`meta`, no por FK.

Doble arista `Order` → `Route` (la clave del diseño):
- `routeId` (`RutaActual`) = «está ocupado ahora». Se pone al crear la ruta, se pone a `null`
  al borrar la ruta, al desasignar, y cuando el `resultado` es `devuelto`/`cancelado`.
- `ultimaRutaId` (`RutaViajada`) = «en qué camión viajó». Se pone al crear la ruta y **nunca**
  se limpia. Es el que consulta el cierre de ruta (`/api/routes/[id]/results`).

---

## 3. Pseudo-enums (String en Prisma → tipo en Go)

Valores verificados por búsqueda de literales en `src/` y `sync-queue.mjs`.

### 3.1 `User.role`
`"admin"` (default). Es el único valor comparado en todo el código
(`api/apps`, `api/branches`, `lib/es-super-admin.ts`, `lib/procovar-auth.ts`).
Conjunto efectivo: **`admin`**. Cualquier otro valor equivale a «no admin».

### 3.2 `Order.status` — estado de reparto
Escrituras reales: default `"pending"`; `/api/routes/[id]/results` escribe
`entregado ? 'delivered' : 'pending'`; `/api/orders/[id]` PATCH detecta `'delivered'`.

Conjunto cerrado: **`pending` | `delivered`**

Cuidado: `PATCH /api/orders/[id]` acepta el `status` que venga del cliente sin validar; el
único efecto especial es que `'delivered'` fija `deliveredAt = now()`. El estado que la UI
muestra de verdad NO sale de aquí sino de `resultado`/`deliveredAt`/`route.status`
(`deliveryStatus()` en `orders/page.tsx`: `devuelto`, `entregado`, `en_ruta`, `en_despacho`,
`sin_entregar` — son etiquetas derivadas, no columnas).

### 3.3 `Route.status` y `Vehicle.status`

`Route.status`: default `"planned"`. Transiciones en `/api/routes/[id]` y `routes/page.tsx`.
Conjunto cerrado: **`planned` | `in_progress` | `completed`**
(`'cancelled'` aparece sólo en `notIn: ['completed','cancelled']` del dashboard; nunca se
escribe. Reservarlo o descartarlo conscientemente.)

`Vehicle.status`: default `"available"`.
Conjunto cerrado: **`available` | `in_use`**
Se ocupa al pasar la ruta a `in_progress` y se libera al `completed` o al borrar la ruta.
No existe `maintenance` en el código.

### 3.4 `Vehicle.type`
Default `"truck"`. La UI ofrece: **`truck` | `van` | `motorcycle` | `car`**.
Es **abierto**: `createTipoInlineMutation` permite crear tipos nuevos por nombre libre
(se guardarían en el inexistente `Settings.tiposVehiculo`). En Go: tratarlo como string
validado contra catálogo, no como enum cerrado.

### 3.5 `Order.source` / `Customer.source`
Conjunto cerrado: **`"pedido"` | `NULL`**. `NULL` = alta manual en delivery.
Único literal en todo el código: `'pedido'` (7 apariciones).

### 3.6 `Order.tripLeg`
Default `"outbound"`. Conjunto cerrado: **`outbound` | `return`**.
Sólo se escribe `'outbound'` (al crear la ruta y al desasignar). `'return'` únicamente se
lee en `MapComponent.tsx` para pintar el tramo. La ida/vuelta no se escribe hoy.

### 3.7 `Order.estado` — estado EN PEDIDO (copiado, no autoritativo)
Conjunto cerrado: **`completada` | `en_proceso` | `NULL`**.
`expirada` NO es un valor almacenado: es derivado (`fechaComprometida < now()` y no
completada) — ver `lib/filtrosPedido.ts:151-157` y `estadoPedido()` en `orders/page.tsx`.

### 3.8 `Order.facturaEstado`
Conjunto cerrado: **`igual` | `cambiado` | `sin_factura` | `NULL`**.
- `igual` — lo facturado coincide con lo pedido; el armador de rutas lo ofrece por defecto.
- `cambiado` — se facturó otra cosa.
- `sin_factura` — todavía no facturado.
- `NULL` — no cotejado (no hay facturación de ese día).
Copiado de PEDIDO; delivery no lo calcula, sólo filtra por él.

### 3.9 `Order.resultado` — cierre de parada
Validado server-side contra un `Set` explícito
(`src/app/api/routes/[id]/results/route.ts:29`):
```
const RESULTADOS = new Set(['entregado', 'devuelto', 'cancelado'])
```
Conjunto cerrado: **`entregado` | `devuelto` | `cancelado` | `NULL`** (`NULL` = sin cerrar).
Ni `devuelto` ni `cancelado` tocan inventario (el reintegro lo hace Ventra).

### 3.10 Estados enviados a PEDIDO (no se almacenan aquí)
`src/lib/avisarEstadoAPedido.ts:25`:
```
type EstadoEntrega = 'despachado' | 'en_transito' | 'entregado' | 'devuelto' | 'cancelado'
```
- `despachado` — al crear la ruta (`/api/routes` POST).
- `en_transito` — al poner la ruta `in_progress` (`/api/routes/[id]` PATCH).
- `entregado`/`devuelto`/`cancelado` — al cerrar la ruta, reenviando `Order.resultado`.
Es el contrato del webhook saliente; en Go debe ser un tipo aparte del de `resultado`.

---

## 4. `updatedAt`: quién lo tiene y quién no

| Modelo | `createdAt` | `updatedAt` | Observación |
|---|---|---|---|
| `Product` | sí | **sí** | `@default(now()) @updatedAt` (el único con default) |
| `Customer` | sí | **sí** | además `syncedAt` |
| `Vehicle` | sí | **sí** | |
| `Order` | sí | **sí** | |
| `Route` | sí | **sí** | |
| `User` | sí | **NO** | hueco |
| `Branch` | sí | **NO** | hueco |
| `SavedOrigin` | sí | **NO** | hueco |
| `OrderVehicle` | sí | **NO** | hueco (tabla puente; discutible) |
| `VentaFacturada` | **NO** | **NO** | sólo `traidoAt @default(now())` |
| `Settings` | **NO** | **NO** | sólo `cupRateUpdatedAt` (específico de `cupRate`) |

5 de 11 lo tienen; **6 no**. Al reconstruir en Go: poner `created_at`/`updated_at` en las 11
con trigger o en la capa de repositorio, y mantener `traidoAt`/`syncedAt`/`cupRateUpdatedAt`
como campos de dominio adicionales (significan «cuándo lo trajo el origen», no «cuándo se
tocó la fila»).

---

## 5. Campos calculados: quién los escribe

| Campo | Dónde se escribe | Qué lo produce |
|---|---|---|
| `Order.weight` | `lib/homeDeliveryQuote.ts::buildOrderData` | `computeItemsWeights(items, catalog)`: Σ (cantidad × `Product.weight` por SKU); si da 0 cae a `input.weight`; 0 = SKU sin peso |
| `Order.items` | `buildOrderData` | items con el peso ya resuelto por producto; si vacíos, los del payload tal cual |
| `Order.productosTexto` | `buildOrderData` | `items.map(name ?? description).filter(Boolean).join(' · ')`; `null` si vacío — copia denormalizada para poder buscar «malta» sin escanear el JSON |
| `Order.deliveryDistanceKm` | `buildOrderData` | `haversineDistance(branch.lat, branch.lng, order.lat, order.lng)` — línea recta sucursal→cliente |
| `Order.deliveryPrice` | `buildOrderData` | `requiereDomicilio === false ? null : computed.quote.price`; hoy `price` es **siempre `null`** (`quote/batch:167`): el precio lo pone la APK Entrega y llega en `pedidoCosto` |
| `Order.routeId` | `POST /api/routes` (= `route.id`); `null` en `DELETE /api/routes/[id]`, en desasignar (`[id]/route.ts:224`) y en `results` cuando el resultado ≠ `entregado` | ocupación actual |
| `Order.ultimaRutaId` | `POST /api/routes` (= `route.id`) | histórico de qué camión lo llevó; **nunca** se limpia |
| `Order.stopOrder` | `POST /api/routes`: `i + 1` sobre `greedyRouteOptimization(origin, stops)`; `null` al desasignar | orden de visita 1-based; se conserva tras el cierre para leer la hoja en orden |
| `Order.segmentKm` | `POST /api/routes`: `haversineDistance(origin, order.end*)`; `null` al desasignar | km origen→parada (NO parada a parada) |
| `Order.price` | `POST /api/routes`: `o.pedidoCosto || 0` | reparto de carga de la ruta; copia del costo de PEDIDO |
| `Order.tripLeg` | `POST /api/routes` y desasignar: `'outbound'` | siempre ida |
| `Order.deliveredAt` | `POST /api/routes/[id]/results`: `entregado ? new Date() : null`; y `PATCH /api/orders/[id]` cuando `status === 'delivered'` | momento de entrega; un devuelto lo pierde |
| `Order.resultado` | `POST /api/routes/[id]/results`, validado contra `RESULTADOS` | cierre manual parada a parada |
| `Order.resultadoAt` | `POST /api/routes/[id]/results`: `new Date()` | |
| `Order.resultadoNota` | `POST /api/routes/[id]/results` | `nota.trim().slice(0, 500)` o `null` |
| `Order.status` | `results`: `entregado ? 'delivered' : 'pending'` | |
| `Route.routeCode` | `generateRouteCode()` en `POST /api/routes` | `RT-{YYYYMMDD}-{count+1 pad 3}` |
| `Route.totalDistance` | `POST /api/routes` (update posterior) | Σ `calculateRouteSegments(origin, stops)` + haversine última parada → origen (incluye el regreso) |
| `Route.totalWeight` | **La base, en cada cambio de paradas** (trigger `trg_orders_totales_de_ruta`, 00014) | Σ `order.weight` de las paradas (`ultimaRutaId`). Al armar se valida además contra `Vehicle.capacity` **antes** (HTTP 400) |
| `Route.totalPrice` | **La base, en cada cambio de paradas** (00014) | Σ `order.pedidoCosto` de las cotizadas; las que no lo están se cuentan en `paradasSinCotizar` |
| `Route.paradasSinCotizar` | **La base, en cada cambio de paradas** (00014) | Cuántas paradas entraron sin `pedidoCosto`. Va pegado a `totalPrice`: sin él, un total corto parece completo |
| `Route.optimized` | `POST /api/routes`: el `optimizar` del cuerpo (por defecto `true`) | `true` tras `ordenDeVisita`; `false` cuando se respeta el orden de los `orderIds`. El SQL lo clavaba a `true` y firmaba como calculado el orden de la persona (21/09/2026) |
| `Route.startedAt` | `PATCH /api/routes/[id]` al pasar a `in_progress`, sólo si estaba `null` | y limpia `finishedAt` si había |
| `Route.finishedAt` | `PATCH /api/routes/[id]` al pasar a `completed`: `new Date()` | con `startedAt` da la duración real |
| `Vehicle.status` | `PATCH`/`DELETE /api/routes/[id]`, `/api/vehicles/[id]` | `in_use` al arrancar la ruta, `available` al completarla o borrarla |
| `Product.*` (`name`,`weight`,`price`,`stock`,`unit`,`category`,`sku`,`sucursalCodigo`,`traidoAt`) | `POST /api/products/sync` — `upsert` por `sucursalCodigo_sku` | lectura directa del catálogo de Ventra por VPN; salta filas sin `sku`/`name` o con `isActive === false` |
| `Settings.catalogoTraidoAt` | `POST /api/products/sync`, sólo si `escritos > 0` | evita congelar el reloj cuando la VPN está caída |
| `Settings.syncBarridoDia` | `sync-queue.mjs:203` | `dia >= HISTORICO_DIAS ? 0 : dia` — cursor circular del barrido histórico |
| `Customer.*` + `syncedAt` | `sync-queue.mjs::syncCustomers` | copia del cliente de PEDIDO; `syncedAt = now()` en cada update |
| `Order.*` del espejo (`orderDate`, `pedidoUpdatedAt`, `estado`, `archivado`, `fechaComprometida`, `requiereDomicilio`, `pedidoCosto`, `factura*`, `municipio`, `vendedor`, `sucursalCodigo`, `customerPhone`, `meta`) | `buildOrderData` vía `POST /api/quote/batch` | copiados literalmente del payload de PEDIDO; delivery no los decide |

Notas de cálculo: toda distancia es **haversine (línea recta)**, no ruta por carretera.
La optimización parte del **greedy de vecino más cercano** y le pasa **2-opt y Or-opt sobre
el circuito cerrado** (`ordenDeVisita`, en el aparato y en el servidor, atados por
`docs/orden-de-paradas.casos.json`). Sigue sin ser un TSP óptimo: es una heurística, pero
ya no deja cruces ni el tramo final larguísimo que Jose vio el 21/09/2026.
`totalDistance` cierra el circuito (vuelve al origen); `segmentKm` no.

---

## 6. Identificadores y referencias externas

**PK internas** — los 11 modelos usan `String @id @default(cuid())`. En Postgres: `text`.
El cuid de Prisma v1 es de 25 caracteres, empieza por `c`, minúsculas+dígitos
(p.ej. `clx3k9f2a0000abcd1234efgh`). No es UUID ni ordenable lexicográficamente de forma
fiable entre procesos. En Go: `github.com/lucsky/cuid` o equivalente si se quiere conservar
compatibilidad de datos existentes; migrar a UUIDv7 obliga a reescribir todas las FK.

**Hexadecimal** — el único uso en el código es el nonce de autenticación
(`src/lib/procovar-auth.ts:48`, `randomBytes(16).toString('hex')`, 32 chars). No es un id
de base de datos; no persiste en ninguna tabla.

**Códigos legibles generados**:
- `Route.routeCode` = `RT-YYYYMMDD-NNN` (secuencia diaria por conteo, sin UNIQUE ni bloqueo).

**Referencias a sistemas externos**:

| Campo | Sistema | Significado |
|---|---|---|
| `Order.externalId` | PEDIDO | id/folio del pedido. Clave de idempotencia junto con `source`. Fallback: `input.externalId \|\| input.operationNumber` |
| `Order.operationNumber` | PEDIDO / Ventra | nº de operación del pedido |
| `Order.source` | — | `"pedido"` = vino del espejo; `null` = manual |
| `Order.sucursalCodigo` | Ventra/PEDIDO | `HAB`, `CMG`… |
| `Order.pedidoUpdatedAt` | PEDIDO | marca de agua: `since = max(pedidoUpdatedAt)`. Deliberadamente derivada de los datos y no de un contador aparte |
| `Order.facturaNumero` | Ventra | nº de factura con la que cuadró |
| `Order.meta` | PEDIDO | payload íntegro (cliente + pedido) |
| `Customer.externalId` | PEDIDO | id del cliente |
| `Customer.codigo` | PEDIDO | código legible, p.ej. `SC06TCP1257` |
| `Customer.source` | — | `"pedido"` o `null` |
| `Customer.meta` | PEDIDO | payload íntegro del cliente |
| `Branch.externalId` | PEDIDO | **`@unique`**; id de la sucursal. Permite que PEDIDO cotice mandando sólo el id y delivery resuelva coordenadas. Se usa además como `sucursalCodigo` del catálogo (`externalId ?? name`) |
| `Product.sku` | Ventra | código de producto; con `sucursalCodigo` forma la clave natural |
| `Product.sucursalCodigo` | Ventra | base/sucursal de la que se leyó |
| `VentaFacturada.ventraId` | Ventra | **`@unique`**; id de la línea de factura |
| `VentaFacturada.operNumber` | Ventra | nº de operación = LA factura; varias líneas lo comparten |

Patrón de idempotencia del espejo: **`[source, externalId]`** en `Order` y `Customer`. Está
implementado en aplicación (`findFirst` + `update`/`create`) y respaldado sólo por un
`@@index`, **no por un UNIQUE**. Reconstruyendo en Go es el primer constraint a añadir
(`UNIQUE (source, external_id) WHERE source IS NOT NULL`) y a usar con `ON CONFLICT`.

---

## 7. Huecos conocidos (checklist para la reconstrucción)

1. Faltan `updatedAt` en `User`, `Branch`, `SavedOrigin`, `OrderVehicle`, `VentaFacturada`,
   `Settings` (y `createdAt` en los dos últimos).
2. Falta UNIQUE real en `Order[source, externalId]` y `Customer[source, externalId]`.
3. Falta índice en `Order.routeId` (filtro más usado) y en `Route.status`/`Route.branchId`.
4. `Route.routeCode` sin UNIQUE y generado por conteo → colisión bajo concurrencia.
5. `Settings` es singleton por convención, no por constraint.
6. `Vehicle.usarParaDomicilio` debería ser único por `branchId` y no lo es.
7. Doble camino `Order.vehicleId` vs `OrderVehicle` sin garantía de coherencia.
8. `Product` UNIQUE `[sucursalCodigo, sku]` no dedupica filas con `sucursalCodigo NULL`.
9. `Settings.tiposVehiculo` se lee y escribe desde la UI pero no existe en el esquema.
10. `Order.lat/lng` duplican `endLat/endLng` al importar; sólo `endLat/endLng` se usan para rutear.
11. `VentaFacturada` es tabla muerta (sin escritores) que conserva histórico.
12. Sin `onDelete` explícito salvo `OrderVehicle`; definir la política en SQL al migrar.
