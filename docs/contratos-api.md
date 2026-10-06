# Contratos de la API de `delivery` (Next.js App Router)

35 rutas en `src/app/api/**/route.ts`. Este documento es el contrato completo para
reimplementarlas en Go sin abrir el repo de Next.

## Convenciones comunes

### Autenticación de usuario (`getUserFromRequest`)

- Token JWT firmado con `JWT_SECRET`, `expiresIn: '7d'`.
- Se lee, en este orden: cabecera `Authorization: Bearer <token>`; si no, cookie `token`.
- Payload obligatorio: `id`, `email`, `name`, `role` (los cuatro `string`; si alguno no es
  string → no hay usuario). `branchId` es `string | null` (si no es string → `null`).
- Sin usuario: `401` con cuerpo `{"error":"Unauthorized"}` (salvo `/api/eventos`, que
  devuelve texto plano `Unauthorized`, y `/api/me`, que devuelve `{"user":null}`).

### Autenticación de servicio (`isValidServiceKey`)

- Cabecera `x-api-key` comparada con `process.env.SERVICE_API_KEY`.
- Si `SERVICE_API_KEY` no está definida → siempre falso.
- Fallo: `401 {"error":"Unauthorized"}`.

### Alcance por sucursal (`resolveScope` / `scopeWhere`)

`resolveScope(req, user) -> { branchId: string|null, actorId: string }`:

1. `pedida = user.branchId || header 'x-sucursal-id' (trim) || null`.
2. Si `pedida` es null → `{ branchId: null, actorId: user.id }` (ve todo).
3. Se comprueba que exista `Branch` con ese id. **Si no existe, NO acota**: se registra
   `[alcance] la sucursal <id> no existe: se pasa a todas` y se devuelve `branchId: null`.
4. Si existe → `{ branchId: pedida, actorId: user.id }`.

`scopeWhere(scope)` → `{ branchId }` si hay alcance, `{}` si no. **Nunca filtra por
usuario/creador.**

`sucursalDeLaPersona(user)`: sólo `user.branchId` (ignora `x-sucursal-id`), y `null` si esa
sucursal no existe. Se usa donde la elección no debe comerse la lista con la que se elige
(`/api/branches`, `/api/almacenes`, `/api/products`).

### Geometría (compartida)

- `haversineDistance(lat1,lon1,lat2,lon2)` / `distanciaHaversineKm(...)`: R = 6371 km,
  fórmula haversine estándar, resultado en km.
- `greedyRouteOptimization(origin, stops[])`: vecino más cercano. Vacío → `[]`; 1 parada →
  `[id]`. Bucle: desde el punto actual (inicio = origen) se elige la parada no visitada de
  menor distancia haversine, se saca de la lista y se añade al recorrido. Devuelve ids
  ordenados.
  **Aquí nos separamos del patrón desde el 21/09/2026**: el greedy pelado deja cruces y un
  último tramo larguísimo de vuelta al almacén —Jose, viéndolo: «esa planificada está mal,
  no hace ruta lógica ni nada»—. El reparto arranca de ese mismo greedy y después le pasa
  **2-opt y Or-opt sobre el circuito cerrado** (`ordenDeVisita`, escrito igual en
  `api/internal/api/rutas.go` y en `app/lib/pantallas/rutas/datos/geo.dart`, atados por
  `docs/orden-de-paradas.casos.json`). Baja un 17% los km en un reparto de La Habana de 12
  paradas. El orden resultante **no** coincide con el del patrón, y es a propósito.
- `calculateRouteSegments(origin, orderedStops)`: array de distancias consecutivas
  `origen→p1, p1→p2, ...`.
- `costoDomicilioEntrega(tarifaBaseCup, cupPorUsd, km, kg)`:
  - `null` si `!tarifaBaseCup` o `!cupPorUsd` o `cupPorUsd <= 0` o `km`/`kg` no finitos.
  - `tarifaUsd = tarifaBaseCup / cupPorUsd`; `usd = redondear(tarifaUsd * km * kg, 2)`.
  - Devuelve `{ distanciaKm: round(km,3), pesoKg: round(kg,3), usd, cup: round(usd*cupPorUsd,2), tarifaUsd }`.
  - `redondear(v,d) = Math.round((v + EPSILON) * 10^d) / 10^d`.

### Filtros compartidos de pedido (`leerFiltros` / `whereDeFiltros`)

Todos son query params de tipo string, opcionales, por defecto `''` (sin filtro), y se les
aplica `trim()`. `q` además se pasa a minúsculas. Los usan `/api/orders` y
`/api/orders/available`.

| Param | Valores | Significado en el `WHERE` |
|---|---|---|
| `q` | texto libre | `OR` con `contains` insensitive sobre `customerName`, `operationNumber`, `endAddress`, `address`, `municipio`, `vendedor`, `productosTexto` |
| `estado` | `completada` \| `en_proceso` \| `expirada` | ver abajo |
| `archivado` | `1` \| `0` | `archivado = true` / `archivado = false` |
| `domicilio` | `1` \| `0` | `requiereDomicilio = true` / `OR[requiereDomicilio null, false]` |
| `cotizado` | `1` \| `0` | `pedidoCosto != null` / `pedidoCosto = null` |
| `municipio` | texto | `municipio = valor` (exacto) |
| `vendedor` | texto | `vendedor = valor` (exacto) |
| `branchId` | id | `branchId = valor`, **AND** con el alcance (no lo amplía) |
| `reparto` | `sin_entregar` \| `en_despacho` \| `en_ruta` \| `entregado` \| `devuelto` | ver abajo |
| `factura` | `con_factura` \| `cuadra` \| `sin_cotejar` \| otro | ver abajo |
| `desde` | `YYYY-MM-DD` | ver abajo |
| `hasta` | `YYYY-MM-DD` | ver abajo |

- `estado`:
  - `noCompletada` = `OR[{estado:null},{estado:{not:'completada'}}]` (los NULL cuentan).
  - `completada` → `estado='completada'`.
  - `en_proceso` → `AND[noCompletada, OR[{fechaComprometida:null},{fechaComprometida:{gte:now}}]]`.
  - `expirada` → `AND[noCompletada, {fechaComprometida:{lt:now}}]`.
- `reparto`:
  - `sin_entregar` → `routeId:null, deliveredAt:null, OR[{resultado:null},{resultado:{not:'entregado'}}]`.
  - `en_despacho` → `routeId != null AND route.status = 'planned'`.
  - `en_ruta` → `routeId != null AND route.status = 'in_progress'`.
  - `entregado` → `OR[{resultado:'entregado'},{deliveredAt:{not:null}}]`.
  - `devuelto` → `resultado IN ('devuelto','cancelado')`.
- `factura`:
  - `con_factura` → `facturaEstado IN ('igual','cambiado')`.
  - `cuadra` → `facturaEstado = 'igual'`.
  - `sin_cotejar` → `facturaEstado = null`.
  - cualquier otro valor no vacío → `facturaEstado = <valor>`.
- Fechas: sólo si `desde`/`hasta` casan `^\d{4}-\d{2}-\d{2}$`.
  `gte = <desde>T00:00:00`, `lte = <hasta>T23:59:59.999` (hora local del servidor), y se
  aplica como `OR[{orderDate: rango}, {orderDate: null, createdAt: rango}]`.

### Eventos en vivo (`avisarCambio`)

Publica en Redis `CANAL_CAMBIOS` un JSON `{ tipo, ...detalle, cuando: ISO8601 }`.
`tipo ∈ 'pedidos' | 'catalogo' | 'rutas' | 'clientes'`. Antirrebote: **como mucho un aviso
cada 15 000 ms por tipo** (en memoria del proceso). Si Redis no está, no hace nada. Nunca
lanza.

### Aviso de estado a PEDIDO (`avisarEstadoAPedido` / `avisarEstadoDeFondo`)

`EstadoEntrega = 'despachado' | 'en_transito' | 'entregado' | 'devuelto' | 'cancelado'`.
Aviso: `{ pedidoId, estado, nota?, at? }`. Se manda en tandas de 200.
Resultado: `{ ok: boolean, enviados: number, aplicados: number, error?: string }`.
Sin `SERVICE_API_KEY` → `{ ok:false, enviados:0, aplicados:0, error:'falta SERVICE_API_KEY' }`.
`avisarEstadoDeFondo` es la versión "dispara y olvida" (no bloquea ni falla la petición).

Todas las rutas son `dynamic = 'force-dynamic'` salvo indicación contraria.

---

# 1. Rutas (`/api/routes`)

## `GET /api/routes`

- **Auth**: usuario. `401 {"error":"Unauthorized"}`.
- **Alcance**: sí, `scopeWhere(scope)` sobre `Route.branchId`.
- **Query**: ninguna.
- **Respuesta 200**: array de `Route` ordenado por `createdAt desc`, con:
  - `branch: { id, name, externalId }`
  - `vehicle: { id, name, type, plate, capacity }`
  - `orders[]` ordenados por `stopOrder asc`, con los campos: `id, operationNumber,
    customerName, address, endAddress, endLat, endLng, status, weight, lat, lng, price,
    segmentKm, stopOrder, tripLeg, items, resultado, resultadoNota, municipio`.
- **Escribe**: nada.

## `POST /api/routes` — armado de ruta (detallado)

- **Auth**: usuario. `401 {"error":"Unauthorized"}`.
- **Alcance**: sí. La sucursal de la ruta es `scope.branchId ?? (branchId del cuerpo, trim)
  ?? null`. Quien tiene alcance NO puede pasar otra sucursal por el cuerpo: manda el suyo.
- **Cuerpo** (campos realmente leídos):

```json
{
  "name": "string?",
  "vehicleId": "string?",
  "originAddress": "string?",
  "originLat": 0,
  "originLng": 0,
  "deliveryDate": "string? (parseable por new Date)",
  "orderIds": ["string"],
  "branchId": "string?"
}
```

`orderIds` por defecto `[]`.

### Validaciones, en orden estricto

1. `originLat == null || originLng == null` →
   `400 {"error":"Las coordenadas del punto de partida son requeridas"}`
2. `!vehicleId` →
   `400 {"error":"Se requiere un vehículo para crear la ruta"}`
3. Si `orderIds` NO es array o está vacío →
   `400 {"error":"Una ruta se arma eligiendo pedidos ya existentes. Manda \`orderIds\`."}`
   (el literal incluye las comillas invertidas alrededor de `orderIds`).

### Con `orderIds` (único camino válido)

Se buscan los pedidos con:
`id IN orderIds AND source='pedido' AND routeId IS NULL AND endLat IS NOT NULL AND
endLng IS NOT NULL` y, si hay sucursal de ruta, `AND branchId = <sucursal>`.

4. `orders.length === 0` →
   `400 {"error":"Los pedidos seleccionados ya no están disponibles: <detalle>"}`
5. Alguno de los ids elegidos no volvió →
   `409 {"error":"<faltan> de los <orderIds.length> pedidos elegidos no pueden ir en esta ruta: <detalle>"}`

   **Nos separamos del patrón aquí (22/09/2026).** Delivery contestaba `"<faltan> de los <M>
   pedidos ya están en otra ruta. Vuelve a elegirlos."` y eso afirmaba una causa que muchas
   veces no era la de verdad: la consulta descarta además los **archivados en PEDIDO**, los
   que se quedaron **sin coordenadas de entrega**, los que **no vinieron de PEDIDO** y los de
   **otra sucursal**, y los cinco salían con el mismo texto. Para tres de ellos «Vuelve a
   elegirlos» ni siquiera es una salida: se pulsa otra vez y contesta lo mismo. Es el mismo
   fallo que ya se corrigió en el tablero (§16, `descartados`), por el otro camino.

   `faltan` son los ids **distintos** que no volvieron, más los que ni son identificadores;
   mandar dos veces el mismo id ya **no** es un conflicto. `<orderIds.length>` sigue siendo
   lo que la persona marcó en la pantalla.

   `detalle` son los **5 primeros** unidos por `, `, y detrás `" y <N-5> más."` si sobran, o
   `"."`. Cada uno es `` `${operationNumber || customerName} (${motivo})` ``, salvo los que no
   devuelven fila, que salen con su id crudo. Los motivos, **en este orden de prioridad**:

   | Motivo | Cuándo |
   |---|---|
   | `ya se entregó y no puede volver a un camión` | `deliveredAt` o `resultado = 'entregado'`. Va el **primero**: un entregado conserva su `routeId`, y decirle «otro lo subió a un camión» manda a hacer lo contrario de lo que toca. |
   | `ya va en la ruta <routeCode>` | `routeId` puesto. **Se nombra la ruta**: «ya va en otra ruta» deja quince rutas que abrir. Sin código, `ya va en otra ruta`. |
   | `PEDIDO lo archivó` | `archivado`. No se arregla volviendo a elegirlo. |
   | `sin coordenadas de entrega` | `endLat`/`endLng` nulos. Pasa: el upsert del espejo escribe `end_lat = excluded.end_lat` sin `coalesce`. |
   | `no vino de PEDIDO` | `source <> 'pedido'`. |
   | `no existe o no es de tu sucursal` | la consulta no devuelve fila. **No se dice cuál de las dos**, igual que en `GET /api/routes/{id}`: decir «existe pero es de Holguín» ya es contar algo de Holguín. |
   | `no es un identificador de pedido` | el texto ni siquiera es un uuid. |
   | `cambió mientras se armaba` | ninguna de las anteriores. Un motivo equivocado es peor que ninguno. |
6. **Sólo se reparte lo facturado y que cuadra**: `noFacturados = orders.filter(o => o.facturaEstado !== 'igual')`.
   Si hay alguno → `409` con mensaje compuesto:
   - `motivo(e)`: `'cambiado'` → `cambió en la factura`; `'sin_factura'` → `sin facturar`;
     cualquier otro (incl. `null`) → `sin cotejar`.
   - `detalle` = los 5 primeros como `` `${o.operationNumber || o.customerName} (${motivo})` ``
     unidos por `, `.
   - Mensaje: `"En una ruta sólo entra lo facturado y que cuadre. <N> no cumplen: <detalle>"`
     seguido de `" y <N-5> más."` si `N > 5`, o de `"."` si `N <= 5`.
   - Nota: el filtro previo de disponibles permite `igual` y `cambiado` en
     `/api/orders/available`, pero **aquí sólo pasa `igual`**.
7. Capacidad: `totalW = Σ orders.weight (|| 0)`. Si hay `vehicleId` y el vehículo existe y
   `totalW > vehicle.capacity` →
   `400 {"error":"Peso total (<totalW.toFixed(1)> kg) supera la capacidad del vehículo (<vehicle.capacity> kg)"}`
   (el vehículo se busca sin alcance: `findFirst({ id: vehicleId })`; si no existe, no se
   valida capacidad).

### Cálculo y escritura

- `routeBranchId = opts.branchId ?? orders[0].branchId ?? null`.
- **Código de ruta**: `RT-YYYYMMDD-NNN`. `YYYYMMDD` de `new Date().toISOString().slice(0,10)`
  sin guiones (UTC). `NNN` = `count(Route where routeCode startsWith 'RT-<fecha>-') + 1`
  con `padStart(3,'0')`. (No es atómico: hay carrera bajo concurrencia.)
- Se crea `Route` con `name || null`, `routeCode`, `userId = scope.actorId`, `vehicleId` (si
  viene), `branchId` (si hay), `originAddress ?? null`, `originLat`, `originLng`,
  `deliveryDate` (`new Date(deliveryDate)` o `null`). `status` queda en el valor por defecto
  del modelo (`planned`).
- **Orden de visita**: `greedyRouteOptimization({lat:originLat,lng:originLng}, stops)` si hay
  más de una parada; con una sola, el orden tal cual. Paradas = `{ id, lat: endLat, lng: endLng }`.
- **Kilómetros de la ruta** (`totalDistance`): suma de `calculateRouteSegments(origen,
  paradasOrdenadas)` **más el regreso** `haversine(últimaParada, origen)` si hay paradas.
  Es un circuito cerrado.
- **Por pedido**: `segmentKm = haversine(origen, pedido)` — ojo, es la distancia **radial
  desde el origen**, no la del tramo del recorrido.
- `totalWeight = Σ weight`, `totalPrice = Σ pedidoCosto` de las cotizadas. **No los escribe
  el armador**: los mantiene la base en cada cambio de paradas (00014), junto con
  `paradasSinCotizar`. El armador sí suma el peso para validar la capacidad antes de crear
  nada, y lo devuelve en la respuesta.
- Actualiza cada `Order`: `routeId`, `ultimaRutaId` (ambos = id de la ruta), `stopOrder =
  i+1`, `tripLeg = 'outbound'`, `segmentKm`, `price = pedidoCosto || 0`.
- Actualiza la `Route`: `totalDistance`, `optimized = true`.
  - **Nos separamos aquí (21/09/2026):** el cuerpo acepta además `optimizar` (booleano,
    por defecto `true`, que es este mismo comportamiento y el que mandan las APK ya
    instaladas). Con `optimizar:false` **no se reordena**: se respeta el orden en que
    vinieron los `orderIds` y la ruta se guarda con `optimized = false`. `optimized` es la
    firma de quién decidió el orden; escribir `true` sobre un orden puesto a mano es una
    firma falsa, y quien la lee después da por calculado lo que nadie calculó.
- **NO ocupa el vehículo** (el camión se marca `in_use` al pasar la ruta a `in_progress`).
- `avisarCambio('rutas')`.
- `avisarEstadoDeFondo` con `{ pedidoId: externalId, estado: 'despachado' }` para los pedidos
  con `source='pedido'` y `externalId` no nulo (de fondo: si PEDIDO falla, la ruta se crea).

- **Respuesta 201**: la `Route` completa recargada, con `vehicle:{id,name,type,plate,capacity}`
  y `orders[]` completos ordenados por `stopOrder asc`.
- **Modelos que escribe**: `Route` (create + update), `Order` (update por cada pedido).

## `GET /api/routes/[id]`

- **Auth**: usuario. **Alcance**: sí (`{ id, ...scopeWhere }`).
- `404 {"error":"No encontrado"}` si no aparece.
- **200**: la `Route` con `orders[]` completos ordenados por `stopOrder asc`.

## `PATCH /api/routes/[id]`

- Si ya está `completed`, rechaza cualquier cambio con 409 y el mismo motivo del
  borrado: ni nombre, ni vehículo, ni estado pueden reescribir el histórico.
- **Auth**: usuario. **Alcance**: sí. `404 {"error":"No encontrado"}`.
- **Cuerpo** leído: `vehicleId`, `name`, `status`.
- **Camino A — si `vehicleId !== undefined`** (tiene prioridad y **retorna antes**):
  - Si la ruta ya tenía otro vehículo y su `status === 'in_use'` → se pone `available`.
  - Si el nuevo `vehicleId` es truthy → ese vehículo pasa a `in_use`.
  - Se actualiza la ruta con `vehicleId: data.vehicleId || null` y, si vienen, `name` y `status`.
  - **200**: la ruta actualizada con `vehicle:{id,name,type,plate,capacity}`.
  - *(En este camino no se tocan `startedAt`/`finishedAt` ni se avisa a PEDIDO.)*
- **Camino B — resto**:
  - `horasDelEstado`: si `status === 'in_progress'` → `startedAt = now` (sólo si aún es null)
    y `finishedAt = null` (sólo si lo tenía puesto); si `status === 'completed'` →
    `finishedAt = now`; en otro caso, nada.
  - `status === 'in_progress'` y la ruta tiene vehículo → vehículo a `in_use`.
  - `status === 'completed'` y el vehículo estaba `in_use` → vehículo a `available`.
  - Actualiza `name`/`status` (si vienen) + las horas.
  - Si `status === 'in_progress'`: busca `Order` con `routeId=id, source='pedido',
    externalId != null` y lanza `avisarEstadoDeFondo` con `estado:'en_transito'`.
    **Al completar NO se avisa** (cada pedido ya tiene su propio resultado).
  - **200**: la `Route` actualizada (sin includes).
- **Modelos**: `Route`, `Vehicle`.

## `DELETE /api/routes/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"No encontrado"}`.
- **Sólo una ruta completada queda protegida** (regla de Jose, 06/10/2026):
  `409 {"error":"La ruta está completada y no se puede modificar ni eliminar: se conserva como histórico."}`.
  Planificadas y en curso se pueden borrar incluso sin paradas o con resultados
  provisionales. Una marca de parada no completa la ruta. No se borra ningún pedido
  ni se limpia su resultado: un entregado sigue entregado y no se vuelve a repartir.
- Si la ruta tiene vehículo `in_use` → pasa a `available`.
- **No borra pedidos**: `updateMany` sobre `Order where routeId=id` →
  `routeId=null, stopOrder=null, segmentKm=null, tripLeg='outbound'`
  Al borrar la `Route`, las claves foráneas dejan también `ultimaRutaId=null`;
  se conservan el pedido y su resultado, aunque ya no exista ese enlace a la ruta.
- Borra la `Route`.
- **200**: `{"success":true}`.
- **Modelos**: `Vehicle`, `Order`, `Route`.

## `POST /api/routes/[id]/results` — cierre de ruta (detallado)

La UI abre esta revisión sólo al pulsar «Marcar como completada». En la cola nativa,
los resultados deben entregarse antes del `PATCH completed` de la misma ruta. Una
hoja pendiente o rechazada retiene ese cierre, incluso en ciclos posteriores; no
detiene los apuntes de otras rutas. El rechazo conserva su motivo. La ruta local
puede figurar completada mientras sigue en cola: eso no acredita cierre en servidor.
Si la hoja es rechazada, su corrección se resuelve con conexión/en la web y con una
decisión explícita en la bandeja (Reintentar o Descartar), sin descartar datos en silencio.


- Si ya está `completed`, rechaza la hoja con 409 y el motivo del histórico.
  Los resultados se guardan mientras está en curso, antes de completar. La cola
  nativa debe mantener ese orden; una hoja tardía rechazada conserva su motivo
  en la bandeja y no se descarta en silencio.
- **Auth**: usuario. `401 {"error":"Unauthorized"}`.
- **Alcance**: sí, sobre la ruta (`{ id, ...scopeWhere(scope) }`).
- `404 {"error":"No encontrada"}` (femenino, distinto del de `/api/routes/[id]`).
- **Cuerpo**:

```json
{ "resultados": [ { "orderId": "string", "resultado": "entregado|devuelto|cancelado", "nota": "string|null" } ] }
```

  Si el JSON no parsea → `{}`. Si `resultados` no es array → `[]`.
- Si no hay entradas → `400 {"error":"No vino ningún resultado"}`.
- **Universo de pedidos válidos**: `Order where ultimaRutaId = id` (**no** `routeId`, para
  poder corregir el resultado de uno ya devuelto que soltó su `routeId`). Se seleccionan
  `id, externalId, source, customerName`.
- **Respuesta (18/09/2026): `200` sólo si NO hubo ningún rechazo.** Con una sola parada
  rechazada la respuesta es `409`, con el mismo cuerpo más un campo `error` que resume
  «Se guardaron N de las M paradas de esta hoja. K no se pudieron guardar: …».
  Lo aplicado **sigue aplicado**: el 409 no deshace nada y `aplicados` viaja entero.
  Motivo: el sincronizador marca `aplicado` cualquier 2xx **sin mirar el cuerpo**
  (`sync/internal/reparto/reparto.go`), así que un rechazo dentro de un 200 no llega a
  ninguna bandeja y el apunte se borra de la cola del aparato — una entrega de verdad
  desaparecía sin rastro. Con un 4xx queda `rechazado` con su motivo, que «no se reintenta
  y no se borra».
- **Por cada entrada** (no aborta; acumula):
  - `orderId` ausente o no pertenece a esa ruta → rechazado con
    `motivo: "ese pedido no va en esta ruta"`.
  - `resultado` ausente o no ∈ `{entregado, devuelto, cancelado}` → rechazado con
    `` motivo: `resultado '<valor>' desconocido` `` (con el valor tal cual, interpolado;
    si falta, sale `resultado 'undefined' desconocido`).
  - Válido: `nota = nota.trim().slice(0,500)` si hay contenido tras trim, si no `null`.
  - `entregado = (resultado === 'entregado')`.
  - Actualiza `Order`: `resultado`, `resultadoAt = now`, `resultadoNota = nota`,
    `deliveredAt = entregado ? now : null`, `status = entregado ? 'delivered' : 'pending'`,
    y **si NO es entregado** además `routeId = null` (baja del camión y vuelve a la lista de
    disponibles). `ultimaRutaId` y `stopOrder` NO se tocan nunca.
  - Se apunta en `aplicados`. Si `source==='pedido'` y hay `externalId`, se añade al lote de
    avisos con `estado = resultado` (`entregado`/`devuelto`/`cancelado`) y la nota.
- **Aviso a PEDIDO síncrono** (`avisarEstadoAPedido`, se espera la respuesta), luego
  `avisarCambio('rutas')`.
- **Respuesta 200**:

```json
{
  "aplicados": [ { "orderId": "...", "resultado": "entregado" } ],
  "rechazados": [ { "orderId": "...", "motivo": "ese pedido no va en esta ruta" } ],
  "aPedido": { "ok": true, "enviados": 0, "aplicados": 0, "error": "..." }
}
```

- **Modelos que escribe**: `Order`. No toca inventario ni el estado de la `Route`.

---

# 2. Pedidos (`/api/orders`)

## `GET /api/orders`

- **Auth**: usuario. **Alcance**: sí (`AND[scopeWhere, whereDeFiltros]`).
- **Query**: todos los filtros compartidos (tabla arriba) más:
  - `pagina`: entero, por defecto `1`, mínimo `1` (`max(1, Number(x)||1)`).
  - `porPagina`: entero, por defecto `50`, tope `200` (`min(200, max(1, Number(x)||50))`).
  - `resumen`: `'1'` para pedir el pre-despacho; cualquier otro valor/ausente → no se calcula.
- **Orden**: `orderDate desc nulls last`, luego `createdAt desc`. Paginación por
  `skip=(pagina-1)*porPagina`, `take=porPagina`.
- **Campos por fila**: `id, operationNumber, customerName, customerPhone, address,
  endAddress, endLat, endLng, weight, status, notes, routeId, deliveryPrice,
  deliveryDistanceKm, items, orderDate, createdAt, deliveredAt, resultado, resultadoNota,
  stopOrder, estado, archivado, fechaComprometida, requiereDomicilio, pedidoCosto,
  facturaEstado, facturaNumero, facturaDomicilio, municipio, vendedor, sucursalCodigo`,
  `route: { id, name, routeCode, status, deliveryDate, vehicle:{name,plate} }`,
  `branch: { id, name, lat, lng }`, más el añadido **`price = deliveryPrice ?? null`**.
- **Pre-despacho** (`resumen=1` y `total <= 5000`): se releen **todos** los pedidos filtrados
  (`items`, `weight`) y se agrupa por nombre de línea (`item.name || item.description`, trim;
  vacío se salta): `{ producto, formatos: Σ packs, unidades: Σ quantity, pesoKg: Σ weightKg
  redondeado a 2 }`, ordenado por `formatos desc`.
- **Respuesta 200**:

```json
{
  "orders": [ ... ],
  "total": 0,
  "pagina": 1,
  "porPagina": 50,
  "paginas": 1,
  "resumen": [ { "producto": "...", "formatos": 0, "unidades": 0, "pesoKg": 0 } ],
  "resumenTope": 5000,
  "pesoTotal": 0
}
```

  - `resumen`: ausente (`undefined`, se omite del JSON) si no se pidió; `null` si se pidió
    pero `total > 5000`; array si se pudo calcular.
  - `paginas = max(1, ceil(total/porPagina))`.
  - `pesoTotal` = suma de pesos **de lo leído para el resumen** (por tanto `0` si no se pidió
    resumen o si se superó el tope).
- **Escribe**: nada.
- **`POST /api/orders` NO EXISTE**: el alta manual se eliminó el 03/09/2026. No hay handler
  exportado (Next responderá 405).

## `GET /api/orders/available` — todos los filtros (detallado)

- **Auth**: usuario. `401 {"error":"Unauthorized"}`. **Alcance**: sí.
- **Query**:
  - Todos los filtros compartidos: `q`, `estado`, `archivado`, `domicilio`, `cotizado`,
    `municipio`, `vendedor`, `branchId`, `reparto`, `factura`, `desde`, `hasta`.
  - `fecha`: `YYYY-MM-DD`, opcional. Si casa el patrón, acota **un día natural completo**
    en hora local: `gte = fecha T00:00:00`, `lt = fecha+1 día T00:00:00`, aplicado como
    `OR[{orderDate: rango}, {orderDate:null, createdAt: rango}]`. Si no casa, se ignora.
  - `branchId` (además de su papel en los filtros): sólo se aplica aquí
    **si no hay alcance o coincide con el alcance** (puede estrechar, nunca ampliar).
  - `kmMax`: número, opcional. Se filtra en memoria (post-consulta):
    descarta si `deliveryDistanceKm != null && deliveryDistanceKm > kmMax`.
    Un pedido **sin** distancia medida NUNCA se descarta.
  - `costoMin`: número, opcional. Descarta si `(pedidoCosto ?? 0) < costoMin`.
  - Para ambos: cadena vacía o no numérica → se ignora el filtro.
- **Condiciones fijas, no negociables**: `source = 'pedido'`, `routeId IS NULL`,
  `endLat IS NOT NULL`, `endLng IS NOT NULL`, `facturaEstado IN ('igual','cambiado')`.
- **Orden**: `orderDate desc nulls last`, luego `createdAt desc`. **`take = 2000`** (TOPE).
- **Campos por fila**: `id, orderDate, createdAt, operationNumber, customerName, address,
  endAddress, endLat, endLng, weight, deliveryPrice, deliveryDistanceKm, items, estado,
  archivado, requiereDomicilio, pedidoCosto, municipio, vendedor`.
- **Respuesta 200**: `{ "orders": [...], "total": <count del where, sin kmMax/costoMin>,
  "truncated": total > orders.length }`.
  Ojo: `orders` es la lista ya filtrada por `kmMax`/`costoMin`, pero `total` y `truncated`
  se calculan **antes** de esos dos filtros.
- **Escribe**: nada.

## `GET /api/orders/facetas`

- **Auth**: usuario. **Alcance**: sí (`scopeWhere` sobre todos los `groupBy`).
- **Query**: ninguna.
- **200**:

```json
{
  "municipios":  [ { "valor": "...", "pedidos": 0 } ],
  "vendedores":  [ { "valor": "...", "pedidos": 0 } ],
  "sucursales":  [ { "valor": "<branchId>", "nombre": "Nombre (COD)", "pedidos": 0 } ]
}
```

  - `municipios`/`vendedores`: `groupBy` con el campo no nulo, ordenados asc por el valor.
  - `sucursales`: `groupBy` por `branchId` no nulo; `nombre` = `externalId ? "<name> (<externalId>)" : name`,
    o `"Sin sucursal"` si la sucursal no se encuentra; ordenadas por `nombre` con `localeCompare`.
- **Escribe**: nada.

## `GET /api/orders/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"Not found"}` (en inglés).
- **200**: la `Order` completa con `route:{id,name}` y `vehicle:{id,name,type,plate}`.

## `PATCH /api/orders/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"Not found"}`.
- **Cuerpo** — sólo se aplican los campos presentes (`!== undefined`):
  `operationNumber, customerName, address, endAddress, endLat, endLng, lat, lng, weight,
  notes, status, tripLeg, routeId, price, stopOrder`.
  Además, **si `status === 'delivered'`** se pone `deliveredAt = now`.
- **200**: la `Order` actualizada con `route:{id,name}`.
- **Modelos**: `Order`.

## `DELETE /api/orders/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"Not found"}`.
- Borra la `Order`. **200**: `{"success":true}`.

## `POST /api/orders/recompute-weights`

- **Auth**: **servicio** (`x-api-key`). `401 {"error":"Unauthorized"}`. **Sin alcance por sucursal.**
- **Cuerpo** (opcional; si no parsea → `{}`): `{ "source": "pedido", "dryRun": false }`.
  `source` por defecto `'pedido'` (sólo se usa si es string). `dryRun` sólo si es
  estrictamente `true`.
- Invalida la caché de pesos y baja el catálogo del warehouse. Si falla →
  `502 {"error":"No se pudo leer el catálogo del warehouse (¿VPN?): <mensaje>"}`.
- Recorre `Order where source = <source>`. Para cada uno: `w = weightFromItems(items, 0, catalog)`.
  Si `|w - (weight||0)| < 1e-6` → `unchanged++`; si no y no es `dryRun` → `update weight = w`,
  `updated++`. Si `w === 0` → `sinPeso++`.
  Además, por cada línea con `weight` manual `<= 0` que el catálogo no resuelva
  (`hit.weightKg <= 0`), se cuenta el nombre (`name.trim()` o `'(sin nombre)'`).
- **200**:

```json
{
  "dryRun": false,
  "totalOrders": 0,
  "updated": 0,
  "unchanged": 0,
  "ordersSinPeso": 0,
  "productosSinPeso": [ { "name": "...", "veces": 0 } ]
}
```

  `productosSinPeso` ordenado por `veces desc`.
- **Modelos**: `Order` (sólo `weight`).

---

# 3. Cotización (`/api/quote`)

## `POST /api/quote` — RETIRADO

- **Sin auth** (no comprueba nada). Ignora el cuerpo por completo.
- **Siempre `410`**:

```json
{"error":"El cotizador individual se retiró. El costo del domicilio lo pone Entrega y lo escribe en PEDIDO. Para el reparto de carga de delivery, usa POST /api/quote/batch."}
```

- No exporta ningún otro método.

## `POST /api/quote/batch` — el espejo de PEDIDO (detallado)

- **Auth**: **servicio** (`x-api-key`). `401 {"error":"Unauthorized"}`. **Sin alcance por sucursal.**
- **Cuerpo**:

```json
{
  "preview": false,
  "useWarehouseWeights": true,
  "orders": [ {
    "externalId": "string?",
    "operationNumber": "string?",
    "sucursalExternalId": "string?",
    "customerName": "string?",
    "address": "string?",
    "phone": "string?",
    "lat": 0, "lng": 0,
    "weight": 0,
    "requiereDomicilio": true,
    "facturaEstado": "igual|cambiado|sin_factura|null",
    "orderDate": "string?",
    "items": [ { "code": "...", "name": "...", "quantity": 1, "packs": 1, "pesoKg": 0, "pesoLineaKg": 0,
                 "almacenCodigo": "2?", "almacenNombre": "AURORA?" } ],
    "almacen": { "codigo": "2", "nombre": "AURORA", "sucursalCodigo": "STG", "mezclado": false },
    "meta": {}
  } ]
}
```

### `almacen` — DE QUÉ ALMACÉN SALE EL PEDIDO (26/09/2026)

**Lo manda PEDIDO y es opcional.** Sin él, todo se comporta como antes.

De este almacén sale la distancia del domicilio, y de esa distancia el costo que alguien cobra.
Mientras cada sucursal tuvo UN almacén, «el de la sucursal» y «el del pedido» eran la misma
frase; con varios, dejaron de serlo. Contado por la sesión de PEDIDO:

```
SANTIAGO    2.185 líneas desde AURORA · 804 desde PV-STGO · 11 desde PTO MONEDERO
CAMAGÜEY    2.778 desde PV CAMAGUEY   · 183 desde FLORIDA · 39 desde ALM CAMAGUEY
GUANTÁNAMO  2.060 desde PV GTMO       · 940 desde ALM CENTRAL
```

En Santiago **dos de cada tres pedidos salen de AURORA** y se medían todos desde PV-STGO.

- `codigo` es el `objectCode` de Ventra y **es la identidad junto con `sucursalCodigo`**. El
  nombre NO identifica: `Tiendas Parranda` existe en cinco sucursales con cinco ids y `PV-STGO`
  está en Santiago **y** en Palma Soriano. Y el código solo tampoco: `objectCode: 2` es AURORA en
  Santiago, PV CAMAGUEY en Camagüey y PV GTMO en Guantánamo. **El reparto no empareja por nombre
  ni como respaldo**: un respaldo por nombre no falla nunca, sólo mide desde el almacén de otra
  sucursal.
- `nombre` se guarda **aunque el almacén no esté dado de alta en Accesos**: sin él, lo que queda
  apuntado es un «28» que no le dice nada a nadie.
- `sucursalCodigo` es la sucursal DEL ALMACÉN, que puede no ser la del pedido.
- `mezclado: true` significa que sus renglones salen de **más de un almacén**; entonces `codigo`
  y `nombre` son los del que pone **más renglones**. **El desempate lo hace PEDIDO**, que es
  quien tiene los renglones delante; el reparto lo copia y no lo recalcula.
  **Ausente NO es `false`**: se guarda NULL («no se sabe»). Un `false` afirma «comprobado que
  sale de uno solo», y si es mentira el que despacha va a un almacén y se deja media carga en el
  otro.
- En `items[]`, `almacenCodigo` y `almacenNombre` son los de ESE renglón, que en un pedido
  mezclado no son los del pedido. Vacío = ausente.

- Si el JSON no parsea o `orders` no es array →
  `400 {"error":"Se espera { orders: [...] }"}`.
- `Settings`: se lee el primero; si no hay ninguno, **se crea uno vacío** (efecto lateral).
- **Catálogo de pesos**: sólo se baja si alguna línea del lote NO trae ni `pesoLineaKg > 0`
  ni `pesoKg > 0`, y `body.useWarehouseWeights !== false`. `weightsSource`:
  `'pedido'` si todas traían peso; `'none'` si faltaba alguno y no se pudo/no se pidió
  catálogo; `'mixto'` si se bajó el catálogo con éxito. (`'warehouse'` está declarado pero
  nunca se emite.)
- **Por cada pedido, en orden** (`ref = externalId || operationNumber || null`):
  1. `lat == null || lng == null` → `skipped`, `reason: "sin-geolocalizacion"`.
  2. `Branch.findUnique({ externalId: sucursalExternalId })` (con caché por externalId; si no
     hay `sucursalExternalId` → null) → si no existe: `skipped`, `reason: "sucursal-no-mapeada"`.
  3. `branch.originConfigured === false` → `skipped`, `reason: "sucursal-sin-punto-de-partida"`.
  4. `requiereDomicilio === false` **y** `facturaEstado !== 'igual'` → `skipped`,
     `reason: "sin-domicilio-y-sin-factura"` (no se guarda nada).
  5. Peso: `computeItemsWeights(items, catalog)`; `weightKg = itemsTotal > 0 ? itemsTotal :
     (Number(weight) || 0)`.
     **`price` siempre `null`** (delivery ya no cotiza; nunca `0`).
  5-bis. **DISTANCIA: desde el almacén del pedido** (26/09/2026). Antes era
     `haversine(branch.lat, branch.lng, ...)`, o sea desde el punto de la SUCURSAL —que no es el
     sitio del que sale la carga— mientras `/api/quote/home-delivery`, el tablero y Clientes
     medían desde el almacén. La cascada, y cada escalón deja escrito su motivo:

     | caso | desde dónde se mide | `almacenMotivo` |
     |---|---|---|
     | el pedido trae un almacén que existe y tiene punto | **ese almacén** | `almacen-del-pedido` |
     | el pedido no trae almacén | el principal de la sucursal | `el-pedido-no-trae-almacen` |
     | lo trae y no está dado de alta en Accesos | el principal | `almacen-no-dado-de-alta` |
     | lo trae, está dado de alta y sin coordenadas (o de baja, o en (0,0)) | el principal | `almacen-sin-coordenadas` |
     | NINGÚN almacén de esa sucursal tiene `codigo` en Accesos | el principal | `accesos-sin-codigos` |
     | no hay NI UN almacén con punto | el punto de la **sucursal** | `sucursal-sin-almacen-con-punto+<el de arriba>` |

     **Nada se descarta**: un almacén que no se puede usar degrada al principal y **no tira el
     pedido** — esta ruta es LA PUERTA de los pedidos y rechazar uno es perderlo. El almacén que
     llegó se guarda igual, con su código y su nombre.
     **Accesos caído** se trata como lista vacía y el pedido entra midiendo desde la sucursal.
     Los almacenes se piden **una vez por sucursal y tanda** (más el recuerdo de 5 min del
     cliente de Accesos).
  6. Resultado base: si `requiereDomicilio === false` →
     `{ ref, status:"skipped", reason:"sin-domicilio", distanceKm, weightKg, branch:{id,name} }`;
     si no → `{ ref, status:"quoted", price:null, distanceKm, weightKg, branch:{id,name} }`.
     **Y desde el 26/09/2026, los dos llevan además** `almacenDesde` (el NOMBRE del almacén desde
     el que se midió, ausente si no se midió desde ninguno) y `almacenMotivo` (la tabla de 5-bis).
     Van en la respuesta para que PEDIDO pueda ver qué pedidos se están midiendo desde el sitio
     equivocado y por qué: sin eso, un kilometraje medido desde el principal es indistinguible de
     uno bueno — mismos decimales, misma tarjeta.
  7. Si `preview` es truthy → se añade el base y se pasa al siguiente (no escribe).
  8. Si falta `customerName` → se añade `{...base, persisted:false, reason:"falta-customerName"}`.
  9. Persistencia **idempotente por (`source='pedido'`, `externalId`)**: busca; si existe →
     `update`, si no → `create`. `persisted++`, resultado `{...base, orderId, persisted:true}`.
- Si `persisted > 0` → `avisarCambio('pedidos', { pedidos: persisted })`.
- **Respuesta 200**:

```json
{
  "total": 0,
  "quoted": 0,
  "persisted": 0,
  "skipped": 0,
  "weightsSource": "pedido|warehouse|mixto|none",
  "currency": "USD",
  "results": [ ... ]
}
```

  **`quoted` es siempre `0`**: la variable se declara pero nunca se incrementa.
  Los `results` con `reason:"sin-domicilio"` llevan `status:"skipped"` pero **no** cuentan en
  `skipped` (sólo cuentan los de los pasos 1–4).
- **Modelos que escribe**: `Order` (create/update), `Settings` (create si no había).

## `POST /api/quote/home-delivery` — precio de un domicilio (detallado)

- **Auth**: **servicio**, comparando a mano `req.headers.get('x-api-key') === process.env.SERVICE_API_KEY`
  (falla también si la cabecera falta). `401 {"error":"Unauthorized"}`. **Sin alcance por sucursal.**
- **Cuerpo** (si no parsea → `{}`): `{ sucursalCodigo, lat, lng, pesoKg, almacenCodigo? }`.
  `sucursalCodigo` se normaliza con `trim().toUpperCase()`; los numéricos con `Number(...)`.
- **`almacenCodigo` es OPCIONAL y nuevo (26/09/2026)**. Es el `codigo` del almacén del que sale
  la mercancía, el mismo que PEDIDO manda en `almacen.codigo` del lote. Quien no lo mande —la APK
  de Entrega instalada hoy— recibe **exactamente lo de siempre**, medido desde el principal.
  Por qué hacía falta: **ésta es la única cuenta de dinero de esta API** y la APK cobra el número
  que devuelve. Sin el campo, en Santiago se cobraban desde PV-STGO las 2.185 líneas que salen de
  AURORA. Y el lote ya mide desde el almacén del pedido: dejar esta ruta como estaba pondría en
  la misma tarjeta un kilometraje bueno y un importe malo, sin nada que dijera cuál creer.
- **Validaciones, en orden**:
  1. `!codigo` → `400 {"error":"Falta sucursalCodigo"}`
  2. `lat` o `lng` no finitos → `400 {"error":"Falta la ubicación del cliente (lat/lng)"}`
  3. `pesoKg` no finito o `<= 0` → `400 {"error":"Falta el peso (pesoKg > 0)"}`
  4. `Branch.findUnique({ externalId: codigo })` inexistente →
     `404 {"error":"No hay sucursal con código <CODIGO>"}`
  5. Almacenes de la sucursal (servicio externo Accesos; si falla → lista vacía). **Con
     `almacenCodigo` se toma ESE almacén**; sin él, o si el pedido trae uno que no se puede usar,
     se cae al **principal con lat y lng**, si no al **primero con lat y lng** — la misma cascada
     y los mismos `almacenMotivo` que el lote (tabla de 5-bis, arriba). Si no hay ninguno →
     `409 {"error":"<nombre de la sucursal> no tiene ningún almacén con coordenadas"}`.
     **Aquí SÍ se contesta 409 y en el lote no**, y la diferencia es la de siempre: esto es una
     cuenta de dinero y el lote es una puerta. Un importe aproximado se cobra igual que uno
     bueno; un pedido rechazado en la puerta se pierde. Un `almacenCodigo` que no se encuentra
     **no** es un 409: hay un número que dar, sólo que peor, y se dice en `almacenMotivo`.
  6. Tasa de la sucursal (si falla la llamada → `null`). Si no hay `cupPorUsd` →
     `409 {"error":"No hay tasa de cambio de <CODIGO> en Accesos"}`
  7. Si no hay `tarifaBase` →
     `409 {"error":"No hay tarifa base de <CODIGO> en Entrega"}`
  8. `km = haversine(almacen, cliente)`; `costo = costoDomicilioEntrega(tarifaBase, cupPorUsd, km, peso)`.
     Si devuelve `null` → `409 {"error":"No se pudo calcular con los datos que hay"}`
- **Respuesta 200**:

```json
{
  "distanciaKm": 0, "pesoKg": 0, "usd": 0, "cup": 0, "tarifaUsd": 0,
  "desde": "almacen:<SUCURSAL>:<CODIGO_DEL_ALMACEN>",
  "almacen": "nombre o null",
  "almacenCodigo": "2 o null",
  "almacenMotivo": "almacen-del-pedido | ...",
  "sucursal": "nombre de la sucursal"
}
```

- **`desde` LLEVA EL ALMACÉN desde el 26/09/2026.** Decía `almacen:<SUCURSAL>` y su trabajo es
  explicar de dónde salió el importe: con varios almacenes por sucursal, `almacen:STG` era la
  misma cadena para uno medido desde PV-STGO y otro desde AURORA, así que **los dos quedaban
  indistinguibles en el histórico de PEDIDO**, que es donde viven los importes cobrados. Sin
  código de almacén se queda en `almacen:<SUCURSAL>`, como antes; el trozo nuevo va DETRÁS para
  que quien parta por `:` y coja los dos primeros siga funcionando.
- **Escribe**: nada. El costo lo guarda PEDIDO.

---

# 4. Eventos en vivo (`/api/eventos`) — SSE

## `GET /api/eventos`

- `runtime = 'nodejs'`, `dynamic = 'force-dynamic'`.
- **Auth**: usuario. Sin él: `401` con **cuerpo de texto plano** `Unauthorized` (no JSON).
- **Query**: ninguna. **Sin alcance por sucursal**: todo suscriptor recibe todos los avisos.
- **Sin Redis** (o sin suscriptor): respuesta **inmediata y cerrada**, cuerpo literal:

```
event: sin-vivo
data: {}

```

  con cabeceras `content-type: text/event-stream` y `cache-control: no-store`.
  La pantalla debe entender que le toca refrescar sola (cada 30 s).
- **Con Redis**: flujo abierto con cabeceras
  `content-type: text/event-stream; charset=utf-8`,
  `cache-control: no-store, no-transform`,
  `x-accel-buffering: no`.
  **NUNCA `connection: keep-alive`** (HTTP/2 y HTTP/3 lo prohíben; con Cloudflare/HTTP3
  provoca `ERR_QUIC_PROTOCOL_ERROR`).
- **Formato de los eventos** (cada bloque termina en `\n\n`):
  1. Al abrir, siempre el primero:

     ```
     event: listo
     data: {"vivo":true}

     ```
  2. Por cada mensaje publicado en `CANAL_CAMBIOS`:

     ```
     event: cambio
     data: {"tipo":"pedidos","cuando":"2026-09-14T10:00:00.000Z"}

     ```

     `data` es el JSON publicado tal cual (`{ tipo, ...detalle, cuando }`;
     `detalle` según el emisor, p. ej. `{"pedidos":42}` o `{"productos":300}`).

     Los `tipo` que publica **reparto-api** hoy (17/09/2026), uno por pantalla que
     los enseña: `pedidos` · `catalogo` · `rutas` · `clientes` · `tablero` ·
     `vehiculos` · `almacenes` · `sucursales` · `ajustes`. La lista viva está en
     `api/internal/api/eventos.go`. Un tipo que el cliente no espere **se recibe y
     se ignora**, así que añadir no rompe nada; renombrar sí.

     `clientes` está declarado y **hoy no lo publica nadie**: en esta API no hay
     ninguna puerta que escriba `customers`. El único que los escribe es el
     proceso del espejo (`cmd/espejo`), y el bus vive en la memoria del proceso de
     la API.
     Si el mensaje **no** es JSON válido, se emite `event: cambio` con
     `data: {"tipo":"desconocido"}`.
  3. **Latido cada 20 000 ms**: línea de comentario SSE, sin evento:

     ```
     : latido

     ```

     Imprescindible: los proxys cierran conexiones calladas al minuto o dos.
- Al abortar la petición (`req.signal`): se limpia el intervalo, se cierra el suscriptor de
  Redis y el flujo.
- **Escribe**: nada.

---

# 5. Autenticación (`/api/auth`, `/api/me`)

## `GET /api/auth/entrar`

- **Sin auth**. **Query**: `volverA` (opcional, string) — se pasa por `destinoSeguro(volverA, origen)`
  antes de usarse (no se acepta un destino arbitrario).
- Si el login único no está disponible (falta configuración) →
  `redirect 307 a <origen>/login?sso=nodisponible`.
- Pide la redirección a Accesos con `redirectUri = <origen>/api/auth/callback` y `volverA`;
  éxito → `redirect` a `redirectUrl` de Accesos.
- Error al pedir la redirección → se registra y `redirect a <origen>/login?sso=error`.
- `origen` se calcula de la propia petición (`origenPublico(req)`), no de una variable de entorno.
- **Escribe**: nada.

## `GET /api/auth/callback`

- **Sin auth previa**. **Query**: `code` (obligatorio).
- Sin `code` → `redirect a <origen>/login?sso=sincodigo`.
- Canjea el código en Accesos → `persona { email, name, codigoSucursal, returnTo, ... }`.
- Sucursal: `Branch.findUnique({ externalId: persona.codigoSucursal })`; si no existe, entra
  **sin sucursal** (no se le niega la entrada).
- `rol = rolDeDelivery(persona)`.
- **`User.upsert` por `email`**:
  - update: `name`, `role`, `branchId` (la contraseña local se deja como está).
  - create: `email, name, role, branchId, password: 'sin-contrasena-local'`.
- Firma JWT con `{ id, email, name, role, branchId }` (7 días) y hace
  `redirect a destinoSeguro(persona.returnTo, origen)` poniendo la cookie:
  `token`, `httpOnly: true`, `secure: origen empieza por https://`, `sameSite: 'lax'`,
  `path: '/'`, `maxAge: 604800` (7 días).
- Cualquier excepción → log `[login unico] fallo el canje del codigo: <msg>` y
  `redirect a <origen>/login?sso=error`.
- **Modelos que escribe**: `User`.

## `GET /api/auth/logout`

- **Sin auth**. **Query**: ninguna.
- `redirect a <PROCOVAR_AUTH_URL||https://auth.procovar.cloud>/logout?returnTo=<origen>/api/auth/logout/done&cancelUrl=<origen>/`.
- **No borra la cookie aquí** a propósito: cancelar en Accesos no debe dejar a medias.
- **Escribe**: nada.

## `GET /api/auth/logout/done`

- **Sin auth**. `redirect a <origen>/` borrando la cookie `token` con **exactamente los
  mismos atributos** con los que se puso (`httpOnly`, `secure`, `sameSite:'lax'`, `path:'/'`)
  y `maxAge: 0`.
- **Escribe**: nada.

## `GET /api/me`

- **Auth**: usuario. Sin él: **`401` con cuerpo `{"user":null}`** (no `{"error":...}`).
- **200**: `{ "user": { "id","email","name","role","branchId" }, "token": "<valor de la cookie token> | null" }`.
  Devuelve el token para que el cliente pueda seguir usando `Authorization: Bearer`.
- **Escribe**: nada.

---

# 6. Sucursales, orígenes y almacenes

## `GET /api/branches`

- **Auth**: usuario. **Alcance**: usa `sucursalDeLaPersona(user)` (**no** `resolveScope`): si
  la persona tiene sucursal, `where { id: suya }`; si no, todas. Así el selector no se come
  a sí mismo.
- **Query**: ninguna.
- **200**: array de `Branch` por `createdAt desc`, con `_count: { members, origins }`.

## `POST /api/branches`

- **Auth**: usuario **admin**. `401 {"error":"Unauthorized"}`;
  si `role !== 'admin'` → `403 {"error":"Admin access required"}`.
- **Cuerpo**: `{ name, address?, lat, lng, areaKm2?, externalId? }`.
- `!name || lat == null || lng == null` → `400 {"error":"Nombre y coordenadas son requeridos"}`.
- Crea `Branch` con `address || null`, `areaKm2 ?? 1`, `externalId || null`,
  `originConfigured: true`, `creatorId: user.id`, y **auto-crea un `SavedOrigin`** con
  `name`, `address || "<lat>, <lng>"`, `lat`, `lng`, `userId: user.id`.
- **201**: la `Branch` con `_count: { origins }`.
- **Modelos**: `Branch`, `SavedOrigin`.

## `PATCH /api/branches/[id]`

- **Auth**: usuario admin (mismos mensajes que arriba).
- **Alcance**: `resolveScope`; se busca `Branch where { id, ...(scope.branchId ? { id: scope.branchId } : {}) }`
  (si hay alcance, el `id` del path queda sobrescrito por el del alcance).
  No encontrada → `404 {"error":"No encontrado"}`.
- **Cuerpo** (sólo los presentes): `name`, `address` (→ `address || null`), `lat`, `lng`,
  `areaKm2`, `externalId` (→ `externalId || null`). Si viene `lat` **o** `lng` →
  `originConfigured: true`.
- **Backfill**: si tras el update la sucursal tiene `lat` y `lng` y no tiene ningún
  `SavedOrigin`, se crea el por defecto (`name`, `address || "<lat>, <lng>"`, `lat`, `lng`,
  `userId`, `branchId`).
- **200**: la `Branch` actualizada.
- **Modelos**: `Branch`, `SavedOrigin`.

## `DELETE /api/branches/[id]`

- **Auth**: usuario admin. Mismos `401`/`403`. **Alcance**: igual que el PATCH.
  `404 {"error":"No encontrado"}`.
- Desasocia miembros (`User.updateMany where branchId=id → branchId=null`) y borra la `Branch`.
- **200**: `{"success":true}`.
- **Modelos**: `User`, `Branch`.

## `GET /api/origins`

- **Auth**: usuario. **Alcance**: sí. `where`: si hay alcance → `{ branchId: scope.branchId }`;
  si no y viene `branchId` en query → `{ branchId }`; si no → `{}`.
- **Query**: `branchId` (opcional, sólo se usa sin alcance).
- **200**: array de `SavedOrigin` por `createdAt desc` con `branch: { id, name }`.

## `POST /api/origins`

- **Auth**: usuario. **Alcance**: sí.
- **Cuerpo**: `{ name, address, lat, lng, branchId? }`.
- `!name || !address || lat == null || lng == null` →
  `400 {"error":"Faltan campos requeridos: name, address, lat, lng"}`.
- `typeof lat !== 'number' || typeof lng !== 'number'` →
  `400 {"error":"lat y lng deben ser números"}`.
- `targetBranchId = scope.branchId ?? branchId ?? null`. Si hay `targetBranchId`, se
  comprueba que exista (buscando por `scope.branchId` si hay alcance, si no por
  `targetBranchId`); si no existe → `403 {"error":"Sucursal no válida"}`.
- Crea `SavedOrigin` con `userId: scope.actorId` (sólo constancia) y `branchId` validado.
- **201**: el `SavedOrigin` creado.
- **Modelos**: `SavedOrigin`.

## `DELETE /api/origins/[id]`

- **Auth**: usuario. **Alcance**: sí (`{ id, ...scopeWhere(scope) }`).
  `404 {"error":"No encontrado"}`.
- Borra el `SavedOrigin`. **200**: `{"success":true}`.

## `GET /api/almacenes`

- **Auth**: usuario. **Alcance**: sí, pero especial — `codigosVisibles` usa
  `sucursalDeLaPersona(user) ?? resolveScope(...).branchId`, y de ahí saca el conjunto de
  `externalId` de `Branch` (sólo los que tienen `externalId != null`).
- **Query**: ninguna.
- Pide a Accesos (firmado) `GET /api/service/almacenes` y **filtra** las sucursales
  devueltas quedándose con las de códigos visibles.
- **200**: `{ "sucursales": [ { "codigo", "nombre", "almacenes": [ { id?, codigo?, nombre, direccion?, latitud?, longitud?, principal?, activo? } ] } ] }`.
- **`codigo` (del almacén) es NUEVO y es la identidad**, junto con el código de la sucursal. Es
  el `objectCode` de Ventra, el mismo que PEDIDO manda dentro de cada pedido. **Sin él, el
  reparto no puede emparejar «el almacén del que sale este pedido» con «el almacén que tiene las
  coordenadas»** y lo mide todo desde el principal: en Santiago, dos de cada tres pedidos salen
  de AURORA. Es opcional en el contrato y se trata como ausente sin error; mientras NINGÚN
  almacén de una sucursal lo traiga, los pedidos de esa sucursal se apuntan con
  `almacenMotivo: "accesos-sin-codigos"`, que es una tarea distinta de «dar de alta un almacén».
  El `PUT` manda el cuerpo a Accesos tal cual, así que en cuanto la pantalla de Almacenes lo
  escriba, llegará.
- Error de Accesos → `502 {"error":"No se pudieron traer los almacenes de Accesos: <mensaje>"}`.
- **Escribe**: nada en local.

## `PUT /api/almacenes`

- **Auth**: usuario. **Alcance**: sí (mismo `codigosVisibles`).
- **Cuerpo**: `{ codigo, almacenes: [...] }`. Si el JSON no parsea o falta `codigo` o
  `almacenes` no es array → `400 {"error":"Se espera { codigo, almacenes: [...] }"}`.
- Si `codigo` no está entre los visibles → `403 {"error":"Sin acceso a esa sucursal"}`.
- Manda `PUT /api/service/almacenes` firmado a Accesos con el cuerpo tal cual.
  Error → `502 {"error":"Accesos no aceptó el cambio: <mensaje>"}`.
- **200**: la respuesta de Accesos (`{ almacenes: [...] }`) más
  `aviso`: `"<N> almacén(es) sin coordenadas: desde ésos no se puede medir el domicilio."`
  contando los que tienen `latitud == null || longitud == null`; `null` si no hay ninguno.
- **Escribe**: nada en la base local (todo vive en Accesos).

---

# 7. Vehículos (`/api/vehicles`)

## `GET /api/vehicles`

- **Auth**: usuario. **Alcance**: sí.
- **200**: array de `Vehicle` por `createdAt desc`, con
  `_count: { routes, orders, orderAssignments }` y
  `routes: [ { id, name, routeCode, status } ]` — **sólo la más reciente** (`take:1`,
  `createdAt desc`) entre las que tienen `status != 'completed'`.

## `POST /api/vehicles`

- **Auth**: usuario. **Alcance**: sí (el vehículo nace en `scope.branchId`, si lo hay).
- **Cuerpo**: `{ name, type?, plate?, capacity?, status?, notes?, costoKmUsd?, usarParaDomicilio? }`.
- `!name` → `400 {"error":"Vehicle name is required"}` (en inglés).
- Defaults: `type || 'truck'`, `plate || null`, `capacity ?? 1000`, `status || 'available'`,
  `notes || null`, `costoKmUsd`: `undefined → null`, en otro caso el valor;
  `usarParaDomicilio = (usarParaDomicilio === true)`.
- **Transacción**: si `usarParaDomicilio`, primero se desmarcan los demás del mismo `type`
  **y de la misma sucursal** (`updateMany where { type, usarParaDomicilio:true, branchId? }
  → usarParaDomicilio:false`). La exclusividad es **por tipo y por sucursal**, no por persona.
- Crea con `userId = scope.actorId` y `branchId` si hay alcance.
- **201**: el `Vehicle` creado.
- **Modelos**: `Vehicle`.

## `GET /api/vehicles/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"Not found"}`.
- **200**: el `Vehicle` con `routes: [ { id, name, status, createdAt } ]` (todas) y
  `_count: { routes, orders, orderAssignments }`.

## `PATCH /api/vehicles/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"Not found"}`.
- **Cuerpo** (sólo los presentes): `name`, `type`, `plate`, `capacity`, `status`, `notes`,
  `costoKmUsd`, `usarParaDomicilio` (se normaliza a `=== true`).
- Si `usarParaDomicilio === true`: dentro de la transacción se desmarcan los demás del
  `targetType` (`data.type` si viene, si no el actual) dentro del alcance, excluyendo el
  propio id.
- **Después** de la transacción: si `data.status === 'available'` y el vehículo estaba
  `in_use` → `Route.updateMany where { vehicleId: id, status: { not:'completed' } }
  → status:'completed'` (auto-completa su ruta activa).
- **200**: el `Vehicle` actualizado.
- **Modelos**: `Vehicle`, `Route`.

## `DELETE /api/vehicles/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"Not found"}`.
- Desasocia antes de borrar: `Route.updateMany({vehicleId:id} → vehicleId:null)`,
  `Order.updateMany({vehicleId:id} → vehicleId:null)`,
  `OrderVehicle.deleteMany({vehicleId:id})`. Luego borra el `Vehicle`.
- **200**: `{"success":true}`.
- **Modelos**: `Route`, `Order`, `OrderVehicle`, `Vehicle`.

---

# 8. Productos (`/api/products`)

## `GET /api/products`

- **Auth**: usuario. **Alcance**: mixto —
  `branchId = sucursalDeLaPersona(user) ?? resolveScope(...).branchId`, y de ahí se saca el
  `externalId` como `codigo`. El `scopeWhere(scope)` normal se usa sólo para el conteo de uso.
- **Query**:
  - `q`: texto, opcional, `trim().toLowerCase()`. Busca `contains` insensitive en `name`,
    `category`, `sku`.
  - `sucursal`: código de sucursal, opcional, `trim().toUpperCase()`. **Tiene prioridad**
    sobre el derivado del alcance.
- Filtro: `sucursalCodigo = codigo` si hay código; si no, sin filtro de sucursal.
  Orden `name asc`, `take: 500`.
- **Uso**: se leen los últimos 2000 `Order` del alcance (`createdAt desc`) y se suman
  `quantity` por `item.productId || item.sku`.
- Se **excluyen los servicios** (`esServicio(p)`, p. ej. «ENTREGA A DOMICILIO», categoría
  `SERV`, peso 0): no se cargan en un camión.
- **200**: array de `Product` con el añadido `usageCount = usage[p.id] || usage[p.sku ?? ''] || 0`.

## `POST /api/products` — RETIRADO

- **Sin auth**, ignora el cuerpo. **Siempre `410`**:

```json
{"error":"El catálogo se trae solo de Ventra (a través de PEDIDO). No hay alta manual de productos."}
```

## `PATCH /api/products/[id]`

- **Auth**: usuario **y** `esSuperAdmin(user)`. Sin usuario → `401 {"error":"Unauthorized"}`;
  no super admin → `403 {"error":"Solo el Super Admin puede tocar el catálogo"}`.
- **Sin alcance por sucursal** (el catálogo es de toda la empresa).
- Producto inexistente → `404 {"error":"No encontrado"}`.
- **Cuerpo** (sólo los presentes): `name` (`String(name).trim()`), `weight`
  (`Number(weight) || 0`), `packaging` (`toString().trim() || null`), `unitsPerPackage`
  (`!= null && !== '' ? Number(x) : null`), `category` (`toString().trim() || null`).
- **200**: el `Product` actualizado. **Modelos**: `Product`.

## `DELETE /api/products/[id]`

- Mismos requisitos y mensajes de auth que el PATCH. `404 {"error":"No encontrado"}`.
- Borra el `Product`. **200**: `{"success":true}`.

## `POST /api/products/sync`

- `maxDuration = 300`.
- **Auth**: **servicio (`x-api-key`) O usuario con sesión**. Si ninguna →
  `401 {"error":"Unauthorized"}`. **Sin alcance**: recorre todas las sucursales.
- **Query**: `forzar` = `'1'` para saltarse el intervalo.
- **Intervalo**: `CATALOGO_CADA_MS` (por defecto `12*60*60*1000`). Si no se fuerza y
  `Settings.catalogoTraidoAt` es más reciente que el intervalo →
  **200** `{ "saltado": true, "traidoAt": "<fecha>" }`.
- `Settings`: se lee el primero; si no hay, se crea vacío.
- Dueño del catálogo: primer `User` con `branchId: null` por `createdAt asc`. Si no hay →
  `500 {"error":"No hay ningún usuario al que colgar el catálogo"}`.
- `ventraDatabases()` falla → `502 {"error":"No se pudo preguntar a Ventra (¿VPN?): <mensaje>"}`.
- Empareja `Branch[]` con las bases de Ventra. Por cada sucursal:
  - Sin base emparejada → fila con `error: "sin base de Ventra que le cuadre"`, `leidos:0, escritos:0`.
  - Con base: `ventraCatalogo(db)`. Se saltan filas sin `sku` o sin `name`, y las de
    `isActive === false`. **Upsert idempotente por `(sucursalCodigo, sku)`** con
    `{ name, weight: weightKg ?? 0, category, unit, price, stock, sku, sucursalCodigo:
    externalId ?? name, traidoAt: now, userId: dueño.id }`.
  - **No borra** lo que deja de venir (media lista por corte de VPN no debe vaciar el catálogo).
  - Excepción en una sucursal → fila con su `error` y ceros; el resto sigue.
- Si `escritos > 0`: se actualiza `Settings.catalogoTraidoAt = now` y se llama
  `avisarCambio('catalogo', { productos: escritos })`. Si TODAS fallaron, **no** se marca la
  hora (para poder reintentar antes de 12 h).
- **200**:

```json
{
  "sucursales": [ { "sucursal": "...", "database": "..."|null, "leidos": 0, "escritos": 0, "error": "..." } ],
  "escritos": 0,
  "conError": 0
}
```

- **Modelos que escribe**: `Product` (upsert), `Settings` (create/update).

---

# 9. Panel, informes y configuración

## `GET /api/dashboard`

- **Auth**: usuario. **Alcance**: sí (`scopeWhere` en todas las consultas).
- **Query**: ninguna.
- `REPARTIBLE` = `routeId: null AND endLat != null AND facturaEstado IN ('igual','cambiado')`
  — el mismo listón que el armador de rutas.
- `hoy` = fecha actual con `setHours(0,0,0,0)` (hora local del servidor).
- **200**:

```json
{
  "totalOrders": 0,
  "sinRuta": 0,
  "rutasActivas": 0,
  "entregadosHoy": 0,
  "totalVehicles": 0,
  "vehiculosEnRuta": 0,
  "pesoPendiente": 0,
  "totalDomicilios": 0,
  "porSucursal": [ { "sucursal": "Nombre|Sin sucursal", "pedidos": 0, "pesoKg": 0 } ]
}
```

  - `totalOrders`: `count(Order)` del alcance.
  - `sinRuta`: `count(Order)` con `REPARTIBLE`.
  - `rutasActivas`: `count(Route)` con `status NOT IN ('completed','cancelled')`.
  - `entregadosHoy`: `count(Order)` con `deliveredAt >= hoy`.
  - `totalVehicles`: `count(Vehicle)`.
  - `vehiculosEnRuta`: vehículos con algún `Order` cuya ruta no esté `completed`/`cancelled`.
  - `pesoPendiente`: `SUM(weight)` sobre `REPARTIBLE` (`?? 0`).
  - `totalDomicilios`: `SUM(pedidoCosto)` sobre todo el alcance (`?? 0`) — lo cobrado, no la
    estimación propia.
  - `porSucursal`: `groupBy branchId` sobre `REPARTIBLE`, con nombre resuelto
    (`'Sin sucursal'` si no hay o no se encuentra), ordenado por `pedidos desc`.
- **Escribe**: nada.

## `GET /api/reports`

- **Auth**: usuario. **Alcance**: sí.
- **Query** (todos opcionales):
  - `from`: fecha (`new Date(from)`) → `createdAt >= from`.
  - `to`: fecha → `createdAt <= new Date(to + 'T23:59:59.999Z')` (**UTC**).
  - `vehicleId`: id → `route.vehicleId = vehicleId`.
  - Si no hay `from` ni `to`, no se filtra por fecha.
- Orden: `createdAt desc`. **Sin paginación ni tope.**
- `revenueOf(o) = o.price != null ? o.price : (o.pedidoCosto ?? 0)`.
- **200**:

```json
{
  "orders": [ { "id","customerName","address","endAddress","weight","price","segmentKm","createdAt","routeName","vehicleName","vehiclePlate" } ],
  "summary": { "totalOrders": 0, "totalRevenue": 0, "totalWeight": 0, "avgPrice": 0 },
  "byVehicle": [ { "name": "...", "plate": "..."|null, "count": 0, "revenue": 0, "weight": 0 } ]
}
```

  - `routeName = route.routeCode || route.name || null`.
  - `avgPrice = orders.length > 0 ? totalRevenue / orders.length : 0`.
  - `byVehicle` sólo incluye pedidos cuya ruta tiene vehículo.
- **Escribe**: nada.

## `GET /api/settings`

- **Auth**: usuario. **Sin alcance**: los ajustes son globales (una sola fila).
- Si no existe ninguna fila `Settings`, **la crea vacía** (efecto lateral en un GET).
- **200**: el objeto `Settings` completo.

## `PUT /api/settings`

- **Auth**: usuario (**no exige admin**). **Sin alcance**.
- **Cuerpo** — sólo cuatro campos se leen: `currency`, `cupRate`, `currencies`,
  `tiposVehiculo`. Todo lo demás se ignora. Si viene `cupRate`, además se pone
  `cupRateUpdatedAt = now`.
- Si hay fila → `update`; si no → `create` con esos datos.
- **200**: el `Settings` resultante. **Modelos**: `Settings`.

## `GET /api/tasa`

- **Auth**: usuario. **Alcance**: sí (decide el modo de respuesta).
- **Query**: ninguna (la sucursal sale de `x-sucursal-id` / `user.branchId`).
- **Sin alcance** (todas las sucursales) — **200**, y `tasa` siempre `null`:

```json
{
  "tasa": null,
  "motivo": "varias-sucursales",
  "aviso": "Elegí una sucursal arriba para ver los importes en CUP: cada una tiene su tasa.",
  "sinTasa": ["Nombre de sucursal sin tasa", "..."]
}
```

  (`sinTasa` se calcula consultando la tasa de cada `Branch` con `externalId != null`.)
- **Con alcance y sin tasa** — **200**:

```json
{
  "tasa": null,
  "motivo": "sin-tasa",
  "sucursal": "Nombre|null",
  "aviso": "<Nombre|Esta sucursal> no tiene tasa de cambio todavía: los importes sólo se pueden ver en USD."
}
```

- **Con tasa** — **200**:

```json
{
  "tasa": 0,
  "fuente": "...",
  "traidoAt": "<fecha>",
  "fresca": true,
  "sucursal": "Nombre|null",
  "aviso": null
}
```

  Si `fresca` es falso, `aviso` = `"La tasa es del <fecha en es-ES> y puede estar desfasada."`
  (`new Date(traidoAt).toLocaleDateString('es')`).
- **Escribe**: nada.

## `GET /api/version`

- **Sin auth**, sin query. Handler **síncrono**.
- **200**: `{ "version": "<VERSION_APP>|null" }` con cabecera
  `Cache-Control: no-store, must-revalidate`.
- `VERSION_APP` se sustituye en tiempo de compilación (literal incrustado), no se lee en
  ejecución.
- **AMPLIADA (15/09/2026)**, sin romper lo de arriba: la respuesta lleva además `ultima`,
  con la versión de la **aplicación** que hay colgada y de dónde se baja, o `null` si no se
  anunció ninguna. `version` (la del servicio) sigue igual y **no es el mismo número**. La
  forma entera y las tres reglas del aviso están en `docs/actualizaciones.md`.

## `GET /api/apps`

- **Auth**: usuario. **Sin alcance por sucursal**, pero sí por rol.
- **Query**: ninguna.
- Lista fija de destinos. `esAdminGlobal = (user.role === 'admin' && !user.branchId)`.
  Los marcados `soloAdmin` (hoy sólo **Accesos**) sólo salen para el admin global. El campo
  `soloAdmin` **no** se devuelve.
- **200**:

```json
{ "apps": [ { "href": "...", "icon": "...", "title": "...", "description": "..." } ] }
```

  Lista completa, en orden:
  1. `https://pedidos.procovar.cloud` · `mdi:clipboard-list-outline` · **PEDIDO** · «Pedidos, clientes y vendedores.»
  2. `https://entrega.procovar.cloud` · `mdi:package-variant-closed-check` · **Entrega** · «El panel de los repartidores.»
  3. `https://rutas.procovar.cloud` · `mdi:routes` · **Rutas** · «Recorridos de los vendedores en el mapa.»
  4. `https://analitics.procovar.cloud` · `mdi:chart-bar` · **Analitics** · «Informes de ventas y gestores.»
  5. `https://caja.procovar.cloud` · `mdi:cash-register` · **Caja** · «Cobros y cierres de caja.»
  6. `https://traslado.procovar.cloud` · `mdi:swap-horizontal` · **Traslado** · «Mercancía entre sucursales.»
  7. `https://ccsa.procovar.cloud` · `mdi:view-dashboard-outline` · **Tablero Parranda** · «El tablero de Parranda / CCSA.»
  8. `https://procovar.cloud` · `mdi:home-outline` · **Portal** · «La entrada común a todo lo demás.»
  9. `https://auth.procovar.cloud/dashboard` · `mdi:shield-account-outline` · **Accesos** · «Cuentas, sucursales y permisos.» *(soloAdmin)*
- **Escribe**: nada.

## `POST /api/admin/recompute`

- `maxDuration = 300`.
- **Auth**: usuario. `401 {"error":"Unauthorized"}`.
- Si falta `SERVICE_API_KEY` en el entorno →
  `500 {"error":"SERVICE_API_KEY no configurada en el servidor"}`.
- **Alcance**: sí. De `scope.branchId` se saca el `externalId` de la sucursal
  (`sucursalCodigo`); vacío = todas.
- **Query**: `dias` — entero, por defecto **30**, acotado a `[1, 120]`
  (`min(max(1, Number(dias)||30), 120)`).
- Llama a `GET <PEDIDO_API_URL>/integration/orders?desde=<hoy-dias, YYYY-MM-DD>&limit=5000
  [&sucursalCodigo=<cod>]` con `x-api-key`, `cache: no-store`.
  Respuesta no OK → `502 {"error":"PEDIDO <status>: <primeros 200 chars del cuerpo>"}`.
- Si `orders.length === 0` → **200**:

```json
{ "total": 0, "recosteados": 0, "dias": 30, "message": "No hay pedidos con geolocalización en los últimos <dias> días." }
```

- Si hay pedidos, los mapea y hace `POST <DELIVERY_URL>/api/quote/batch` con `x-api-key`.
  Mapeo por pedido: `sucursalExternalId: pedido.sucursalCodigo`,
  `customerName: cliente.nombre || pedido.encargado || 'Cliente'`,
  `address: pedido.direccion || cliente.direccion || null`, `phone: pedido.telefono || null`,
  `lat: cliente.latitud ?? null`, `lng: cliente.longitud ?? null`,
  `items: [{ code: it.codigo, name: it.producto, quantity: it.unidades || 1, packs, descripcion, pesoKg ?? null, pesoLineaKg ?? null }]`,
  `operationNumber: pedido.folio`, `externalId: pedido.id`, `orderDate: pedido.fecha ?? null`,
  `meta: pedido`.
  Respuesta no OK → `502 {"error":"Cotización <status>: <primeros 200 chars>"}`.
- `recosteados` = número de pedidos cuyo resultado en el batch tiene `status === 'quoted'` y
  `price != null`. **Como el batch devuelve siempre `price: null`, en la práctica es 0.**
- **200**:

```json
{ "total": 0, "recosteados": 0, "dias": 30, "weightsSource": "pedido|mixto|none", "sucursal": "<codigo>|todas" }
```

- **Escribe**: indirectamente, vía `/api/quote/batch` → `Order`, `Settings`.
  **Ya no escribe nada en PEDIDO** (antes pisaba el costo del domicilio).

---

# 10. Clientes (`/api/customers`)

## `GET /api/customers`

- **Auth**: usuario. **Alcance**: sí, pero traducido a **código** de sucursal, porque
  `Customer` no tiene `branchId` sino `sucursalCodigo`:
  si hay `scope.branchId` y su `Branch` tiene `externalId`, se aplica
  `OR[{sucursalCodigo: externalId}, {sucursalCodigo: null}]` — **los clientes manuales
  (sin código) se ven siempre**.
- **Query** (todos opcionales, `trim()`):
  - `q`: `contains` insensitive sobre `name`, `address`, `municipio`, `zona`, `phone`,
    `codigo`, `vendedor`.
  - `municipio`: exacto.
  - `sucursalCodigo`: exacto (además del alcance).
  - `zona`: exacto.
  - `origen`: `'pedido'` → `source = 'pedido'`; `'manual'` → `source = null`; otro → ignorado.
  - `vendedor`: exacto.
  - `telefono`: `'1'` → `phone != null`; `'0'` → `OR[{phone:null},{phone:''}]`.
  - `kmMax`: número > 0. Requiere una sucursal de referencia
    (`sucursalCodigo` de la query, o el `externalId` del alcance). Se pide el almacén
    **principal con latitud**, si no el **primero con latitud**. Con él:
    - **Caja previa** (resoluble por índice): `gradosLat = kmMax/111`,
      `gradosLng = kmMax / (111 * max(0.1, cos(lat*π/180)))`; se filtra
      `lat ∈ [lat0-gradosLat, lat0+gradosLat]`, `lng ∈ [lng0-gradosLng, lng0+gradosLng]`.
    - **Distancia exacta después**, sólo sobre la página: se añade
      `kmDelAlmacen = round(haversine(almacen, cliente), 2)` y se descartan los `> kmMax`.
    - Si no hay almacén con coordenadas, no se filtra por distancia y `almacenDeReferencia`
      queda `null`.
  - `pagina`: entero, por defecto `1`, mínimo `1`.
- **Paginación**: **`TOPE = 50` por página, fijo** (no configurable).
  Orden `name asc`, `skip=(pagina-1)*50`, `take=50`.
- **Campos por cliente**: `id, source, externalId, name, phone, address, municipio, zona,
  lat, lng, sucursalCodigo, codigo, vendedor, syncedAt` (+ `kmDelAlmacen` si hubo almacén).
- **Facetas** (calculadas sobre toda la base del alcance, **no** sobre la página, y
  **sin** aplicar los filtros de búsqueda): `municipios`, `sucursales`, `zonas`, `vendedores`
  (`groupBy` con el campo no nulo, orden asc) y `sinTelefono` (conteo).
- **200**:

```json
{
  "count": 0,
  "total": 0,
  "pagina": 1,
  "porPagina": 50,
  "paginas": 1,
  "truncated": false,
  "customers": [ ... ],
  "almacenDeReferencia": { "latitud": 0, "longitud": 0 },
  "municipios":  [ { "valor": "...", "clientes": 0 } ],
  "sucursales":  [ { "valor": "...", "clientes": 0 } ],
  "zonas":       [ { "valor": "...", "clientes": 0 } ],
  "vendedores":  [ { "valor": "...", "clientes": 0 } ],
  "sinTelefono": 0
}
```

  - `count` = filas devueltas tras el filtro de distancia; `total` = `count` de la consulta
    (sin el filtro de distancia exacto); `paginas = max(1, ceil(total/50))`;
    `truncated = total > customers.length`.
- **Escribe**: nada.
- **`POST /api/customers` NO EXISTE**: el alta manual se retiró el 03/09/2026. Los clientes
  llegan por el espejo de PEDIDO. No hay handler exportado (405).

---

# Apéndice: inventario de mensajes de error literales

| Ruta | Código | Mensaje exacto |
|---|---|---|
| todas con sesión | 401 | `Unauthorized` |
| `/api/eventos` | 401 | `Unauthorized` (texto plano, sin JSON) |
| `/api/me` | 401 | `{"user":null}` |
| `/api/routes` POST | 400 | `Las coordenadas del punto de partida son requeridas` |
| `/api/routes` POST | 400 | `Se requiere un vehículo para crear la ruta` |
| `/api/routes` POST | 400 | ``Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`.`` |
| `/api/routes` POST | 400 | `Los pedidos seleccionados ya no están disponibles: <detalle>` |
| `/api/routes` POST | 409 | `<N> de los <M> pedidos elegidos no pueden ir en esta ruta: <detalle>[ y <K> más.\|.]` |
| `/api/routes` POST | 409 | `En una ruta sólo entra lo facturado y que cuadre. <N> no cumplen: <detalle>[ y <K> más.|.]` |
| `/api/routes` POST | 400 | `Peso total (<X.X> kg) supera la capacidad del vehículo (<C> kg)` |
| `/api/routes/[id]` GET/PATCH/DELETE | 404 | `No encontrado` |
| `/api/routes/[id]/results` | 404 | `No encontrada` |
| `/api/routes/[id]/results` | 400 | `No vino ningún resultado` |
| `/api/routes/[id]/results` | 200 (rechazado) | `ese pedido no va en esta ruta` |
| `/api/routes/[id]/results` | 200 (rechazado) | `resultado '<v>' desconocido` |
| `/api/orders/[id]` | 404 | `Not found` |
| `/api/orders/recompute-weights` | 502 | `No se pudo leer el catálogo del warehouse (¿VPN?): <msg>` |
| `/api/quote` | 410 | `El cotizador individual se retiró. El costo del domicilio lo pone Entrega y lo escribe en PEDIDO. Para el reparto de carga de delivery, usa POST /api/quote/batch.` |
| `/api/quote/batch` | 400 | `Se espera { orders: [...] }` |
| `/api/quote/home-delivery` | 400 | `Falta sucursalCodigo` |
| `/api/quote/home-delivery` | 400 | `Falta la ubicación del cliente (lat/lng)` |
| `/api/quote/home-delivery` | 400 | `Falta el peso (pesoKg > 0)` |
| `/api/quote/home-delivery` | 404 | `No hay sucursal con código <CODIGO>` |
| `/api/quote/home-delivery` | 409 | `<Sucursal> no tiene ningún almacén con coordenadas` |
| `/api/quote/home-delivery` | 409 | `No hay tasa de cambio de <CODIGO> en Accesos` |
| `/api/quote/home-delivery` | 409 | `No hay tarifa base de <CODIGO> en Entrega` |
| `/api/quote/home-delivery` | 409 | `No se pudo calcular con los datos que hay` |
| `/api/branches` POST, `/api/branches/[id]` | 403 | `Admin access required` |
| `/api/branches` POST | 400 | `Nombre y coordenadas son requeridos` |
| `/api/branches/[id]` | 404 | `No encontrado` |
| `/api/origins` POST | 400 | `Faltan campos requeridos: name, address, lat, lng` |
| `/api/origins` POST | 400 | `lat y lng deben ser números` |
| `/api/origins` POST | 403 | `Sucursal no válida` |
| `/api/origins/[id]` | 404 | `No encontrado` |
| `/api/almacenes` GET | 502 | `No se pudieron traer los almacenes de Accesos: <msg>` |
| `/api/almacenes` PUT | 400 | `Se espera { codigo, almacenes: [...] }` |
| `/api/almacenes` PUT | 403 | `Sin acceso a esa sucursal` |
| `/api/almacenes` PUT | 502 | `Accesos no aceptó el cambio: <msg>` |
| `/api/almacenes` PUT | 200 (aviso) | `<N> almacén(es) sin coordenadas: desde ésos no se puede medir el domicilio.` |
| `/api/vehicles` POST | 400 | `Vehicle name is required` |
| `/api/vehicles/[id]` | 404 | `Not found` |
| `/api/products` POST | 410 | `El catálogo se trae solo de Ventra (a través de PEDIDO). No hay alta manual de productos.` |
| `/api/products/[id]` | 403 | `Solo el Super Admin puede tocar el catálogo` |
| `/api/products/[id]` | 404 | `No encontrado` |
| `/api/products/sync` | 500 | `No hay ningún usuario al que colgar el catálogo` |
| `/api/products/sync` | 502 | `No se pudo preguntar a Ventra (¿VPN?): <msg>` |
| `/api/products/sync` | 200 (fila) | `sin base de Ventra que le cuadre` |
| `/api/admin/recompute` | 500 | `SERVICE_API_KEY no configurada en el servidor` |
| `/api/admin/recompute` | 502 | `PEDIDO <status>: <cuerpo recortado a 200>` |
| `/api/admin/recompute` | 502 | `Cotización <status>: <cuerpo recortado a 200>` |
| `/api/admin/recompute` | 200 | `No hay pedidos con geolocalización en los últimos <dias> días.` |
| `/api/tasa` | 200 (aviso) | `Elegí una sucursal arriba para ver los importes en CUP: cada una tiene su tasa.` |
| `/api/tasa` | 200 (aviso) | `<Sucursal> no tiene tasa de cambio todavía: los importes sólo se pueden ver en USD.` |
| `/api/tasa` | 200 (aviso) | `La tasa es del <fecha> y puede estar desfasada.` |

# Apéndice: tabla resumen de las 35 rutas

| # | Ruta | Métodos | Auth | Alcance | Escribe |
|---|---|---|---|---|---|
| 1 | `/api/admin/recompute` | POST | usuario + SERVICE_API_KEY en entorno | sí | vía batch: Order, Settings |
| 2 | `/api/almacenes` | GET, PUT | usuario | sí (códigos visibles) | nada local (Accesos) |
| 3 | `/api/apps` | GET | usuario | no (sí por rol) | no |
| 4 | `/api/auth/callback` | GET | no (código SSO) | no | User |
| 5 | `/api/auth/entrar` | GET | no | no | no |
| 6 | `/api/auth/logout` | GET | no | no | no |
| 7 | `/api/auth/logout/done` | GET | no | no | no (borra cookie) |
| 8 | `/api/branches` | GET, POST | usuario / admin | `sucursalDeLaPersona` | Branch, SavedOrigin |
| 9 | `/api/branches/[id]` | PATCH, DELETE | admin | sí | Branch, SavedOrigin, User |
| 10 | `/api/customers` | GET | usuario | sí (por `sucursalCodigo`) | no |
| 11 | `/api/dashboard` | GET | usuario | sí | no |
| 12 | `/api/eventos` | GET | usuario | no | no |
| 13 | `/api/me` | GET | usuario | no | no |
| 14 | `/api/orders` | GET | usuario | sí | no |
| 15 | `/api/orders/available` | GET | usuario | sí | no |
| 16 | `/api/orders/facetas` | GET | usuario | sí | no |
| 17 | `/api/orders/[id]` | GET, PATCH, DELETE | usuario | sí | Order |
| 18 | `/api/orders/recompute-weights` | POST | servicio | no | Order |
| 19 | `/api/origins` | GET, POST | usuario | sí | SavedOrigin |
| 20 | `/api/origins/[id]` | DELETE | usuario | sí | SavedOrigin |
| 21 | `/api/products` | GET, POST(410) | usuario | mixto | no |
| 22 | `/api/products/[id]` | PATCH, DELETE | super admin | no | Product |
| 23 | `/api/products/sync` | POST | servicio o usuario | no | Product, Settings |
| 24 | `/api/quote` | POST | ninguna | no | no (410) |
| 25 | `/api/quote/batch` | POST | servicio | no | Order, Settings |
| 26 | `/api/quote/home-delivery` | POST | servicio | no | no |
| 27 | `/api/reports` | GET | usuario | sí | no |
| 28 | `/api/routes` | GET, POST | usuario | sí | Route, Order |
| 29 | `/api/routes/[id]` | GET, PATCH, DELETE | usuario | sí | Route, Vehicle, Order |
| 30 | `/api/routes/[id]/results` | POST | usuario | sí | Order |
| 31 | `/api/settings` | GET, PUT | usuario | no | Settings |
| 32 | `/api/tasa` | GET | usuario | sí | no |
| 33 | `/api/vehicles` | GET, POST | usuario | sí | Vehicle |
| 34 | `/api/vehicles/[id]` | GET, PATCH, DELETE | usuario | sí | Vehicle, Route, Order, OrderVehicle |
| 35 | `/api/version` | GET | ninguna | no | no |
