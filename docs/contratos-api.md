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

### Sin permiso para Reparto — `403` con `codigo` (Reparto Go, 08/10/2026)

**Quién entra a Reparto lo decide Auth (Accesos), no Reparto** (Jose, 08/10/2026: «Reparto no
decide quién entra; eso lo maneja Auth; Reparto es un microservicio y el login es de Auth»).
Auth firma en el token de acceso (APK y escritorio) y en la respuesta de `/api/auth/exchange`
(web) el campo **`entradas`**: las llaves `<app>.entrar` que la persona tiene
(`["pedido.entrar","delivery.entrar"]`; a un `isSystemAdmin` le van todas las conocidas).
**Reparto entra si y solo si `delivery.entrar` ∈ `entradas`.** Quien no la tiene —sea cual sea su
rol— tiene sesión válida en Accesos pero **no tiene esta aplicación**. Se comprueba en el
servidor, justo después de resolver la identidad y **antes** del alcance de sucursal:

```
HTTP/1.1 403 Forbidden
Content-Type: application/json; charset=utf-8

{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}
```

- **Quién lo recibe:** la cabecera `Authorization: Bearer` de la APK y el escritorio, la cookie
  `token` de la web y el canal en vivo `GET /api/eventos` (que comprueba la sesión por su
  cuenta). Las tres vías contestan **lo mismo, byte por byte**. También `GET /api/apps`.
  El sincronizador (`/sync/*`) aplica la misma lista y contesta el mismo 403.
- **Cómo se decide** (`Usuario.PuedeEntrarAReparto()`, en la API; `puedeEntrarAReparto`, en el
  sincronizador; atadas por `docs/roles-de-reparto.casos.json`):
  1. **`entradas` PRESENTE** (aunque sea `[]`) **decide SOLO ella**: con `delivery.entrar` entra
     **aunque su rol no esté en la lista vieja** (Auth puede dar acceso a otro rol sin tocar
     Reparto), y un rol de la lista vieja **sin** esa llave **no entra**. La llave se compara como
     texto EXACTO (`delivery.entrar`: sin mayúsculas, sin espacios, sin plegado Unicode).
     Presente pero roto (`null`, un texto, un objeto) cuenta como presente y vacío: falla cerrado.
  2. **`entradas` AUSENTE** (token o cookie emitidos antes del cambio) → **caída a la lista de
     roles de ayer**, para que nadie quede fuera durante la transición: SUPER ADMIN,
     DESARROLLADOR, ADMINISTRADOR y LOGISTICO (+ el `admin` heredado), mirando el rol principal
     (`role`, y si viene vacío, `rol`) y la lista `roles`, con `auth.MismoRol` (sin espacios, sin
     distinguir mayúsculas **ASCII**, NADA de plegado Unicode). **«Ausente» y «vacío» NO son lo
     mismo**: ausente = «Auth todavía no lo decía»; `[]` = «Auth dice que no».
  3. **La caída es de transición**: `auth.CaidaPorRolesDeTransicion` (y su gemela en sync).
     **QUITAR cuando caduquen los tokens/cookies anteriores al 08/10/2026** (cookie web 7 días ->
     15/10/2026; access token de la APK, 15 minutos): después Reparto decide solo por `entradas`.
     `TestLaCaidaPorRolesEsDeTransicion` (api y sync) la nombra para que no se olvide.
- **Dos credenciales a la vez** (dos cookies `token`, o cabecera y cookie): entre las VÁLIDAS
  gana la primera que entra a Reparto; si ninguna entra, la primera válida (la del 403).
- **`codigo` distingue este 403 del del alcance de sucursal.** `ErrSinAlcance` («esta cuenta no
  está dada de alta en ninguna sucursal…») y `ErrSucursalSinAlta` («tu sucursal MOA no está dada
  de alta en Reparto…») **no llevan `codigo`**: esos se arreglan en la oficina; éste no se
  arregla aquí, y el cliente manda a la persona a Accesos. El resto de errores de la API siguen
  siendo `{"error":"…"}` sin `codigo` (el campo se omite).
- **No lo reciben** las rutas que no pasan por `Exigir`: `/health`, `/version`, `/api/version`,
  `/mapa`, las cuatro de `/api/auth/*`, ni **`GET /api/me`** (que sigue diciendo quién es la
  persona a cualquier sesión válida: es lo que la app necesita para enseñar «no tienes
  permiso»). Tampoco las puertas de **servicio**: `x-api-key` (espejo, `products/sync`,
  `recompute-weights`, `quote/batch`, `quote/home-delivery`, `service/sucursal`) y el webhook de
  PEDIDO (firma). Llevan `Rol:"SUPER ADMIN"` puesto a mano y no son personas.
- **Registro:** una línea `WARN sin permiso de reparto` con `rol`, `roles`, `sucursal`,
  `persona` (correo o id), `ruta`, `entradas` y `trae_entradas`. **Nunca el token**, ni recortado.
- **Web, `/api/auth/callback`:** el `entradas` del intercambio se conserva **tal cual** en la
  cookie que firma Reparto: ausente se queda ausente (la API cae a los roles), `[]` se queda `[]`
  (no entra), y un `null` o algo que no es un array se escribe como `[]`. `/api/me` no expone
  `entradas`. Los roles del token son los `role` y `roles` de **primer nivel**
  que devuelve `/api/auth/exchange` de Accesos (rol por defecto + los de todas sus membresías,
  sin repetir) y `SUPER ADMIN` si la cuenta es `isSystemAdmin`. Los de las membresías
  (`memberships[].roles`, el `member.role` de better-auth: owner/admin/member…) **solo valen como
  caída cuando el primer nivel viene vacío** (un Accesos viejo). **`admin` a secas nunca se
  acuña** —es el puente de los tokens viejos de la web, Accesos no lo firma—, venga de donde
  venga: un GERENTE con `member.role = 'admin'` NO entra. `role` (el principal que ve `/api/me`)
  prefiere, por este orden, `DESARROLLADOR`, `SUPER ADMIN`, `ADMINISTRADOR`, `LOGISTICO`.
  **Límite conocido:** la sucursal sale de la primera membresía y los roles son de la persona;
  hoy nadie tiene dos membresías (medido el 08/10/2026), pero quien fuera GESTOR en una sucursal
  y ADMINISTRADOR en otra entraría como ADMINISTRADOR en la primera. Hay que ligar el rol a la
  sucursal ANTES de dar una segunda membresía (`TestLimiteConocido…`).
- **El token de ENTREGA a revisión (09/10/2026) no entra por aquí, y no es un permiso.** Lo firma Accesos a quien
  conserva la sesión pero no tiene `delivery.entrar` (`ambito:"reparto.entrega"`, `entradas:[]`, sin roles, 10 minutos)
  y solo abre dos rutas de `sync` (§12). Todo token que traiga `ambito`, **con cualquier valor y aunque lleve la llave**,
  se rechaza en las rutas normales: **401 en la API** (`auth.ErrAmbito`, también en `GET /api/me` y en `/api/eventos`) y
  **403 `sin_permiso_reparto` en `sync`**. La regla vive en DOS módulos, atados por `docs/ambito-de-entrega.casos.json`.
- **Sincronizador, `POST /sync/subida`:** si el reparto contesta este 403 al aplicar un apunte,
  **no es un rechazo del apunte**: la subida contesta `403` con este mismo cuerpo y **no anota
  nada** (ni rechazo, ni apunte), así que la cola del aparato queda pendiente y sube sola cuando
  se le dé el rol. Un 403 del alcance (sin `codigo`) sigue siendo un rechazo del apunte con `200`.

### Accesos invalida las sesiones — `401` y evento `sesion-invalidada` (Reparto Go, 08/10/2026)

Jose: «Accesos debe afectar a las otras sesiones; si inicio en una estoy logueado en las otras, y
si cierro sesión o me cambian un permiso en Accesos se refleja en todas. **Nada de polling: para
eso tenemos SSE y Sentinel**». Antes la cookie de la web valía siete días sin volver a preguntar a
nadie. Ahora Accesos lo **empuja** y Reparto lo aplica **sin llamar a la red en cada petición**.

- **El contrato con Accesos (fijo).** Canal pub/sub Redis `procovar:auth:eventos`; mensaje JSON
  `{"v":1,"tipo":"sesion-cerrada"|"permisos-cambiados","alcance":"web"|"todo","userIds":["<uuid>"],
  "tms":<unix en MILISEGUNDOS>,"motivo":"..."}`. `alcance`: `web` = un cierre de sesión (`logout`);
  `todo` = revocación explícita, baja, cambio de rol, de llaves, de admin, de membresía o borrado.
  Marcas de recuperación en la **DB 6**, DOS claves por persona:
  `procovar:auth:invalida:web:<userId>` y `procovar:auth:invalida:todo:<userId>` (valor `<tms>`,
  TTL 8 días; se escriben ANTES de publicar). Un mensaje con `v` desconocida, JSON roto, tipo o
  alcance desconocidos o sin `tms` **se ignora con un WARN** y no rompe nada; sin `alcance` se lee
  como `todo` (falla cerrado).
- **La regla de la COOKIE web.** La cookie lleva `iatms` (el instante de emisión en milisegundos,
  junto al `iat` de siempre) y la marca `"web": true`. Ya no vale si `max(web[persona], todo[persona]) >= iatms`: `401`
  `{"error":"Unauthorized"}` (`/api/me`: `{"user":null}`; `/api/eventos`: texto plano) **y la
  respuesta borra la cookie** con sus mismos atributos. La web vuelve a entrar por Accesos, que si su
  sesión sigue viva le da una cookie nueva con los roles y las `entradas` recalculados.
  **Una cookie SIN `iatms`** (anterior a este cambio) vale como emitida en el instante 0: cualquier
  marca de esa persona la invalida, pero **no se rechaza por faltarle el claim** (al desplegar no se
  echa a nadie).
- **La regla del token de la APK y el escritorio (`Bearer`).** Ya no vale si `todo[persona] >=
  emitido`, donde `emitido` es el claim **`iatms`** (milisegundos; Accesos lo firma en el token de
  acceso desde el 08/10/2026) y, **si falta, `iat*1000`** (el `iat` va en SEGUNDOS y se compara por
  arriba: un token sin `iatms` emitido en el mismo segundo que la marca se invalida). Con `iatms` no
  hay **rebote**: la APK renueva en cuanto le llega el aviso, y con `iat*1000` un token pedido 250 ms
  después del evento se rechazaba en ~75 % de los casos. **Un evento `web` no le llega**: cerrar la
  sesión del navegador no echa al teléfono. Mismo `401` que un token inválido y **nunca `403`**: la
  app lo trata como sesión caducada, renueva contra Accesos, y es Accesos quien decide si la sesión
  murió o sólo falta un permiso. Lo aplican `reparto-api` (`Verificador`) y `reparto-sync`
  (`identidad.DeTokenConInvalidaciones`) **antes** de decidir «sin permiso».
- **Qué es «sesión web»** (porque no es sólo «quien llegó por cookie»): la web manda la cookie *y*
  el mismo token como `Authorization: Bearer` (su interceptor, con el token de `/api/me`). Es web toda
  credencial que viaje en una cookie `token` o lleve la marca `"web": true` (sólo la firma
  `auth_web.go`); el resto es de la APK. **No se distingue por `iatms`**: Accesos lo firma también en
  el token de la APK, y con eso un cierre de sesión `web` echaría al teléfono. Una credencial invalidada cuenta como un fallo más: con un Bearer viejo delante de una cookie
  nueva gana la cookie nueva y no se le borra.
- **Topes (auditoría de seguridad, 08/10/2026).** El Redis es el de toda la casa y su clave es
  común, así que lo que llega por el canal o por las marcas **no es de fiar**: se ignora (con WARN)
  un mensaje o una marca con `tms` a más de **60 s en el futuro** —sin esto, un `tms` de 2100 o un
  salto de reloj dejaba a una persona bloqueada para siempre, porque cada cookie nueva seguiría
  siendo «anterior»—; de un mensaje se leen como mucho **1000 ids**; cada mapa guarda como mucho
  **100 000 marcas** y, al pasarse, descarta **las más viejas, nunca las recientes**; la limpieza
  horaria olvida las de más de 8 días y **rebaja** a «ahora» las que quedaron por delante del reloj.
  **Pendiente de infraestructura (no es de esta API):** lo correcto es una ACL de Redis donde sólo
  Accesos pueda `PUBLISH` en `procovar:auth:eventos` y escribir `procovar:auth:invalida:*`; mientras
  la clave sea compartida, estos topes son la única defensa de este lado.
- **Las cuentas de servicio** (`x-api-key`) no pasan por el verificador y no se miran.
- **Sin Redis, o con Redis caído, NO se tumba nada**: la API (y el sincronizador) arrancan y sirven
  como antes —sin el empuje—, lo dicen en el registro (WARN al arrancar y en cada caída, INFO al
  volver, una línea de estado cada hora) y, al reconectar, vuelven a cargar las marcas con SCAN.
- **El evento SSE `sesion-invalidada`** (en `GET /api/eventos`): cuando llega un mensaje, **sólo las
  conexiones de esas personas** reciben
  ```
  event: sesion-invalidada
  data: {"tipo":"sesion-cerrada"}

  ```
  (o `{"tipo":"permisos-cambiados"}`) y **el servidor cierra la conexión justo después**: su
  credencial ya no vale. Las conexiones abiertas con la cookie de la web reciben los dos alcances;
  las abiertas con `Bearer` (APK, escritorio), sólo `todo`. Mensajes de la web: `sesion-cerrada` →
  «Tu sesión se cerró en Accesos»; `permisos-cambiados` → «Tus permisos cambiaron, vuelve a entrar».
  Una conexión cuya cola está llena se cierra sin el aviso (al reconectar encuentra el `401`).
  **Límite conocido:** lo que se invalida *mientras Redis no se oye* no avisa a las conexiones ya
  abiertas (sólo se recargan las marcas); se cierran solas cuando el proxy corta el canal (~5 min) y
  la reconexión recibe `401`.
- **Variables** (las mismas del espejo; sin ellas, sin empuje): `REDIS_CENTINELAS`, `REDIS_MAESTRO`,
  `REDIS_CLAVE` (o `REDIS_DIRECCION` / `REDIS_URL` sin centinela). **La base no se configura**: es la 6.

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

#### Reparto (Go), desde la 1.0.29 — el alcance FALLA CERRADO

Lo de arriba es el contrato heredado de delivery. En `api/internal/alcance` (`Resolver`) la
regla es esta, y donde difiere manda ésta:

1. `pedida` = la sucursal **del token** de la persona (el **código** de Accesos: `CAM`, `HOL`,
   `STG`…, o un uuid). Sólo si **no tiene** sucursal **y su rol ve todas** (`SUPER ADMIN`,
   `DESARROLLADOR`; ver `VeTodasLasSucursales`) se lee la cabecera `X-Sucursal-Id`. Para
   cualquier otro rol **la cabecera ni se mira**, mande lo que mande.
2. Sin `pedida`: todas **sólo** para esos dos roles. Cualquier otro rol →
   `403 {"error":"esta cuenta no está dada de alta en ninguna sucursal: pide en la oficina que te asignen la tuya"}`.
3. Con `pedida` se comprueba que Reparto la **conozca**. Si no la conoce (Accesos sabe de `MOA`
   y `PLS`, Reparto no; o un uuid que no existe):
   - `SUPER ADMIN` / `DESARROLLADOR` → «todas» + aviso en el registro (`[alcance] la sucursal
     <id> … no existe: se le enseñan todas`).
   - **cualquier otro rol** → `403 {"error":"tu sucursal MOA no está dada de alta en Reparto:
     pide en la oficina que la den de alta"}` (el código es el que traiga su cuenta). Hasta la
     1.0.28 esto era «todas»: un operador de una sucursal que Reparto no conoce veía las ocho.
4. Un fallo de la base **nunca** abre el alcance: 500.

Los dos 403 son `errors.Is(err, ErrSinAlcance)`: salen por el mismo middleware (`Exigir`) en
cada ruta con datos, y por `GET /api/eventos` como **texto plano** con el mismo código. El
literal de `ErrSinAlcance` es compartido con la app y **no cambia**; el de la sucursal
desconocida es otro texto para otro caso.

`sucursalDeLaPersona(user)`: sólo `user.branchId` (ignora `x-sucursal-id`), y `null` si esa
sucursal no existe. Se usa donde la elección no debe comerse la lista con la que se elige
(`/api/branches`, `/api/almacenes`, `/api/products`).

### Rastro de quién (Reparto, 1.0.29)

Las acciones que cambian datos de la casa dejan **una línea `Info`** en el registro del
servidor con `actor` (el `sub` de la persona, `auth.Usuario.ID`), `rol` y los ids afectados.
**Nunca el token, ni recortado, ni su firma, ni la cabecera** (`TestElRastroNoEnsenaElToken`;
esa regla es la del 401, donde ni el `sub` sale porque quien pregunta aún no ha demostrado ser
nadie: aquí la persona ya está verificada). No cambia ningún permiso. Sólo se escribe si la
acción **se hizo**; un rechazo no deja «lo hizo».

| Mensaje | Dónde | Campos |
|---|---|---|
| `parada quitada de una ruta planificada` | `DELETE /api/routes/{id}/stops/{orderId}` | `ruta`, `pedido` |
| `ruta borrada` | `DELETE /api/routes/{id}` | `ruta`, `estado`, `vehiculo` |
| `ruta: estado cambiado` | `PATCH /api/routes/{id}` con `status` (despachar / completar) | `ruta`, `de`, `a` |
| `ruta: camión cambiado` | `PATCH /api/routes/{id}` con `vehicleId` | `ruta`, `vehiculo_antes`, `vehiculo_ahora` |
| `cierre de ruta guardado` | `POST /api/routes/{id}/results` (si se guardó alguna parada) | `ruta`, `aplicados`, `rechazados` |
| `vehículo creado` / `vehículo editado` / `vehículo borrado` | `/api/vehicles` | `vehiculo`, `sucursal` (+ `activo`, `estado` al editar) |
| `ajustes guardados` | `PUT /api/settings` | `moneda`, `tasa_cup`, `monedas_tocadas` |
| `recosteo lanzado` | `POST /api/admin/recompute` (antes de pedir nada a PEDIDO) | `dias`, `desde`, `sucursal` |

**Autoría de la bandeja de revisión (09/10/2026).** Cuando `sync` aplica lo que otra persona entregó, llama a esta API con el
token del REVISOR y añade `X-Autor` (el `sub` de quien hizo el gesto) y `X-Revision` (el id de la entrega). **No se escriben en
las líneas de arriba sino en la línea `peticion`** de `RegistrarPeticiones` (`api/internal/httpx/middleware.go`), que sale para
**toda escritura** (POST, PUT, PATCH y DELETE; un GET no) y por eso cubre también rutas que no llaman a `rastroDeQuien`, como
`/board/columns`: la prueba de punta a punta vio que aplicar el tablero por revisión no dejaba ni rastro de las dos personas
(`autor=` y `revision=`). `rastroDeQuien` ya NO las escribe; la línea de quién y la de la petición comparten el id `peticion=`.
`actor` y `rol` siguen siendo los del token verificado, las cabeceras **no autorizan nada**, se recortan a 64 caracteres (con
`…`) y una vacía no se anota. **Riesgo aceptado:** `RegistrarPeticiones` está por fuera de la sesión, así que `autor=`/`revision=`
salen aunque la petición se rechace (también un 401) y las puede escribir cualquiera que llegue a la API: son texto para leer el
registro, nunca prueba de nada (B1 de `AUDITOR-SEG-BANDEJA.md`). Detalle en §12.5.

`POST /api/admin/recompute` y `PUT /api/settings` siguen pasando por sesión **sin `ExigirAdmin`**:
decidir si deben exigirlo es una DECISIÓN ABIERTA de Jose; esta entrega sólo deja el rastro.

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

**El camión tiene que ser de la sucursal de la ruta o compartido** (1.0.29). El camión se lee
sin alcance (el contrato dice que un id que no existe arma la ruta sin camión), pero si existe
y su `branch_id` es **otra** sucursal distinta de la de la ruta → `400
{"error":"No existe el vehículo '<id>'"}`, el mismo texto que al cambiar el camión de una ruta.
Se mira **antes** de `is_active` y de la capacidad: decir «inactivo» de un camión ajeno sería
confirmar que existe. Un camión compartido (`branch_id` NULL) vale.

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
     `/api/orders/available`, pero **aquí sólo pasa `igual`**. **`cambiado` NO entra a una
     ruta** (Jose: «en el camión sólo sube lo que cuadra con la factura»). El 07/10/2026 se
     aceptó `cambiado` aquí «porque también es una factura» y se volvió a `igual` el mismo
     día: Amado pidió sumar lo de abajo, no aflojar esto.
6-bis. **Domicilio cobrado** (Amado, 07/10/2026, incidencia 6): todo pedido tiene que traer
   `facturaDomicilio > 0` (lo cobrado en el mostrador). Si alguno no → `409`
   `"En una ruta sólo entra lo facturado con domicilio cobrado. <N> no cumplen: <detalle>"`,
   con el mismo formato de cinco nombrados + `" y <N-5> más."` / `"."`. El cero y los
   negativos no demuestran que se cobró.
6-ter. **Domicilio cotizado** (Amado, 07/10/2026): todo pedido tiene que traer `pedidoCosto`
   no nulo (el cero SÍ vale; nulo no). Si alguno no → `409`
   `"No se puede crear la ruta: <N> pedidos no tienen cotizado el domicilio en Entrega: <detalle>"`
   (mismo formato). **Bloquea, no avisa**: hasta el 07/10/2026 esto era un aviso («AVISO, no
   portazo») y la respuesta del `201` podía llevar `{"ruta":…,"avisos":{"sinCosto":N}}`. Esa
   forma **ya no existe**: la respuesta es siempre la ruta sola, con el id en la raíz.
   Los tres cortes (6, 6-bis, 6-ter) van en ese orden y cada pedido sale **por su número de
   operación** (ver «El conduce» más abajo).
   La misma condición se repite, como segunda llave, en el `UPDATE` que engancha cada
   pedido (`factura_domicilio > 0 AND pedido_costo IS NOT NULL`); si un pedido la perdió
   entre la validación y el enganche, la ruta entera se deshace con el `409` de siempre.
7. Capacidad: `totalW = Σ orders.weight (|| 0)`. Si hay `vehicleId` y el vehículo existe y
   `totalW > vehicle.capacity` →
   `400 {"error":"Peso total (<totalW.toFixed(1)> kg) supera la capacidad del vehículo (<vehicle.capacity> kg)"}`
   (el vehículo se busca sin alcance: `findFirst({ id: vehicleId })`; si no existe, no se
   valida capacidad).
7-bis. **Vehículo inactivo** (Amado, 07/10/2026, incidencia 4): si el vehículo existe y
   `isActive = false` →
   `400 {"error":"El vehículo está inactivo y no se puede asignar a una ruta."}`. Se comprueba
   **justo antes** que la capacidad: si el camión no sirve, decir además que no cabe manda a
   cambiar la carga cuando lo que hay que cambiar es el camión. El mismo literal sale al
   cambiarle el camión a una ruta (`PATCH`) y al armar una zona del tablero.

### El conduce (aclaración de Jose, 07/10/2026, punto 6 de Amado)

**El conduce ES el número de operación de la factura** (`orders.operation_number`, p. ej.
`PTB25-261005-1479`). No hay dato, columna ni estado aparte: la identificación ya existe y
ese número se puede usar y mostrar como conduce. Todos los rechazos del armado de una ruta
(`409` de arriba, `descartados` del tablero) **nombran cada pedido por ese número** y sólo
caen al nombre del cliente si falta. Un cobro a domicilio «que sale como conduce» no es un
caso aparte: es un pedido más, y entra o no según la regla de arriba (facturado `igual`,
domicilio cobrado y cotizado).

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
  - **Reasignar es un intento nuevo (1.0.29, I-2).** Además deja a `NULL` **`resultado`,
    `resultadoAt`, `resultadoNota` y `deliveredAt`**: un pedido devuelto o cancelado conserva
    esas columnas al soltar su ruta, y pegado a la ruta nueva hacía que «Quitar de ruta»
    contestara un `409` engañoso y que, al borrar la ruta, no volviera a su zona. Lo que pasó en
    el intento anterior consta en el registro y en PEDIDO; la parada nueva empieza limpia. Un
    **entregado no se reasigna nunca** (`resultado = entregado` o `deliveredAt` no nulo, ya en el
    `WHERE` del `UPDATE`, además del `409` del manejador). Es **la misma consulta** que usa el
    armado del tablero (`POST /api/board/columns/{id}/route`): un solo sitio asigna pedidos a
    rutas.
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
  - **Vehículo inactivo** (07/10/2026): si el nuevo `vehicleId` existe en el alcance pero
    `isActive = false` → `400 {"error":"El vehículo está inactivo y no se puede asignar a una ruta."}`
    y no se toca nada. Se mira **después** del alcance (decir «inactivo» de un camión de otra
    sucursal es contar algo suyo). Quitar el camión (`vehicleId` vacío) no pasa por aquí.
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
- **Si la ruta nació del tablero** (07/10/2026, incidencia 3 de Amado): cada parada vuelve a
  su zona y a su posición de origen (`board_route_origins`), no se pierde la relación
  factura–tablero. Si la zona ya no existe, sus orígenes se fueron con ella
  (`ON DELETE CASCADE`) y el pedido queda en «sin colocar». Una ruta armada a mano no
  restaura nada en el tablero.

## `DELETE /api/routes/{id}/stops/{orderId}` — quitar UNA parada (07/10/2026)

Incidencia 2 de Amado: antes, para sacar una factura de una ruta planificada había que borrar
la ruta entera. **No existe en delivery (Next): es propio del reparto.**

- **Auth**: usuario. **Alcance**: sí.
- **200** `{"success":true}`. El pedido NO se borra: vuelve a la lista de disponibles y, si la
  ruta nació del tablero, a su zona y su posición. En la misma sentencia pasa lo que importa:
  `route_id`, **`ultima_ruta_id`**, `stop_order` y `segment_km` a `NULL`. Poner también
  `ultima_ruta_id` a `NULL` es lo que hace que el trigger de totales (`00014`) recalcule
  `total_weight`, `total_price` y `paradas_sin_cotizar` de la ruta y que el pedido deje de
  ser parada suya (la «parada fantasma»: antes seguía contando en la cabecera y salía en su
  hoja de cierre, donde se podía marcar «entregado»).
  **No se renumeran** los `stop_order` de las demás (queda un hueco) y **`total_distance` no se
  recalcula** (es el circuito que midió quien armó la ruta, no una suma de paradas).
- **Errores**:

| Código | Mensaje | Cuándo |
|---|---|---|
| 400 | `Identificador de pedido no válido` | `orderId` no es un uuid |
| 404 | `No encontrado` | la ruta no existe o no es de tu sucursal |
| 409 | `Sólo se pueden retirar paradas de una ruta planificada` | la ruta está `in_progress`, `completed` o `cancelled` |
| 409 | `La ruta está completada y no se puede modificar ni eliminar: se conserva como histórico.` | se completó entre la lectura y la escritura |
| 409 | `El pedido no pertenece a una ruta planificada o ya fue retirado` | el pedido no va en esa ruta, ya tiene resultado o ya se entregó. Quitar dos veces la misma parada da este `409` |

- Avisa en vivo a `rutas`, `pedidos` y `tablero` de la sucursal de la ruta.

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
- **Universo de pedidos válidos**: los que **viajaron** en la ruta: `routeId = id`, o bien
  (`routeId IS NULL AND ultimaRutaId = id AND resultado IS NOT NULL`). La segunda rama deja
  corregir el resultado de un devuelto o cancelado, que soltó su `routeId`; el
  `resultado IS NOT NULL` deja **fuera** al pedido simplemente quitado de la ruta
  (`DELETE …/stops/{orderId}`), que no viajó. Antes era `ultimaRutaId = id` a secas, y una
  ruta armada desde el tablero (con `routeId` y a veces sin `ultimaRutaId`) rechazaba sus
  propias paradas como «no va en esta ruta» (incidencia 1 de Amado). Las mismas tres
  condiciones valen para marcar, desmarcar y para los renglones de la hoja de carga. Se
  seleccionan `id, externalId, source, customerName`.
- **Respuesta (18/09/2026): `200` sólo si NO hubo ningún rechazo.** Con una sola parada
  rechazada la respuesta es `409`, con el mismo cuerpo más un campo `error` que resume
  «Se guardaron N de las M paradas de esta hoja. K no se pudieron guardar: …».
  Lo aplicado **sigue aplicado**: el 409 no deshace nada y `aplicados` viaja entero.

  **El 409 PARCIAL y el TOTAL se distinguen por `aplicados` (07/10/2026, incidencia 1).**
  Si el `409` trae `aplicados` **no vacío**, es PARCIAL: lo guardado vale, cada rechazo trae su
  motivo literal en `rechazados[]` y la ruta **se puede completar**. Si `aplicados` viene
  **vacío**, es TOTAL: no se guardó ninguna parada y no hay nada que completar. Quien cierra
  (la web) enseña el motivo de cada rechazo y deja completar sólo en el caso parcial; la
  APK y el escritorio dejan la hoja en la bandeja con el rechazo y retienen el completar
  hasta que una persona decida (Reintentar o Descartar).

  **Cada parada se nombra por su número de operación — el CONDUCE (1.0.29, I-3).** El 07/10/2026
  el `error` decía `8cb90608-76da-4fae-879d-126ff9ab4c3c (ese pedido no va en esta ruta)` y
  nadie sabía de qué pedido hablaba. Ahora cada elemento de `rechazados[]` lleva
  **`numeroOperacion`** (string, **siempre presente**, nunca `null`: el `operation_number` del
  pedido, o `""` si no tiene o **no es visible para quien cierra**) y el `error` nombra cada
  parada por él, con el `orderId` crudo —recortado a 64 caracteres— sólo como último recurso.
  El número se lee **con el alcance de quien cierra**, dentro de la misma transacción: un id de
  otra sucursal no revela su conduce (sale `""` y se nombra por el id que mandó el cliente).
  `orderId` se mantiene tal como vino (el aparato lo compara con lo que mandó) y `motivo` sigue
  siendo el texto corto, sin el conduce delante.

```json
{
  "error": "Se guardaron 1 de las 2 paradas de esta hoja. 1 no se pudieron guardar: PTB25-261005-1480 (ese pedido no va en esta ruta).",
  "aplicados":  [ { "orderId": "<uuid>", "resultado": "entregado" } ],
  "rechazados": [ { "orderId": "<uuid>", "numeroOperacion": "PTB25-261005-1480", "motivo": "ese pedido no va en esta ruta" } ],
  "aPedido": { "ok": true, "enviados": 1, "aplicados": 1 }
}
```

  Con más de cinco rechazadas el texto nombra las cinco primeras y termina `… y <K-5> más.`.
  Un servidor anterior a la 1.0.29 no manda la clave: el cliente cae al `orderId`.

  **Para diagnosticar un rechazo sin ir al VPS**: el servidor escribe UN `Error` de resumen
  (`un cierre llegó con paradas que no van en esa ruta`: `ruta`, `ruta_branch_id`, cuántas se
  guardaron y cuántas no, y el `motivo`) y, por cada parada rechazada, un renglón **Warn**
  `parada rechazada en el cierre` con `ruta`, `pedido`, `numero_operacion`, `route_id`,
  `ultima_ruta_id` y `branch_id` del pedido (`NULL` si no tiene) y el `motivo`. Son ids de
  filas, nada de la sesión. Sólo se escribe en el camino del rechazo (el cierre bueno no
  pregunta nada) y se detallan las 20 primeras; la lectura que lo alimenta pregunta por 50 ids
  como mucho, y el `orderId` que no es un uuid se recorta a 64 caracteres antes de escribirse.
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
  "rechazados": [ { "orderId": "...", "numeroOperacion": "PTB25-261005-1480", "motivo": "ese pedido no va en esta ruta" } ],
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
  `endLat IS NOT NULL`, `endLng IS NOT NULL`, `facturaEstado IN ('igual','cambiado')` y, desde
  el 07/10/2026 (Amado), **`facturaDomicilio > 0`** (domicilio cobrado) y **`pedidoCosto IS NOT
  NULL`** (domicilio cotizado). La lista ofrece `cambiado` (para que se vea y se revise) pero
  una ruta **no** lo acepta; lo que no puede pasar es lo contrario: que se ofrezca algo que
  el armador rechaza por domicilio o cotización. Por eso `cotizado=false` ya sólo puede dar
  una lista vacía. **El mismo listón** lo aplican «Sin colocar» del tablero, su contador, el
  `ColocarPedido` y los recuentos del panel (`sin_ruta`, `peso_pendiente`, por sucursal).
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
- **Cuerpo** — sólo se aplican los campos presentes:
  `operationNumber, customerName, address, endAddress, endLat, endLng, lat, lng, notes,
  tripLeg`. Es el parche de una equivocación al teclear (dirección, coordenadas, nota…).
- **`routeId`, `status`, `price`, `weight` y `stopOrder` YA NO SE ACEPTAN (1.0.29).** Hasta la
  1.0.28 este PATCH los escribía sin pasar por ninguna regla —de cualquier rol, sin validar la
  sucursal ni el estado de la ruta ni la facturación—: era la puerta de atrás de todo lo que
  el armador, el tablero y el cierre ya bloquean (meter un pedido en la ruta de otra
  sucursal o en una completada, marcarlo `delivered`, cambiarle el precio). Ningún cliente los
  mandaba (se comprobó con `grep` en `app/lib`, `sync/`, `herramientas/` y este contrato: la
  app no llama a este endpoint). Si llega **cualquiera** de ellos —también con `null`— →
  `400 {"error":"Ese campo no se cambia por aquí: usa las rutas o el tablero (<campos>)"}`,
  con los nombres de los campos que sobran en el orden `routeId, status, price, weight,
  stopOrder`, **y no se aplica nada del cuerpo** (ni los campos buenos que lo acompañen).
  Meter o sacar un pedido de una ruta es sólo de `/api/routes` y `/api/board`; el estado y la
  hora de entrega los pone el cierre; el peso lo calcula el servidor. Tampoco se pone ya
  `deliveredAt` desde aquí.
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
  4. **Sesión invalidada por Accesos** (Reparto Go, 08/10/2026), sólo para las conexiones de la
     persona afectada, y la conexión **se cierra después**:

     ```
     event: sesion-invalidada
     data: {"tipo":"sesion-cerrada"}

     ```

     `tipo` es `sesion-cerrada` o `permisos-cambiados`. Detalle (alcances, quién lo recibe, qué
     pasa con Redis caído) en «Accesos invalida las sesiones», arriba. El cliente que no conozca
     el nombre lo ignora, como cualquier evento desconocido; el servidor cierra igual y la
     reconexión recibe `401`.
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
- **Reparto Go (08/10/2026):** la cookie la emite `Canjear` con `iatms`, y si Accesos la invalidó
  (cierre de sesión o cambio de permisos posterior a su emisión) contesta `401 {"user":null}` **y
  borra la cookie**: ver «Accesos invalida las sesiones».
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

> **`isActive` (Amado, 07/10/2026, incidencia 4).** Todo vehículo lleva `isActive: boolean`
> (default `true`; columna `vehicles.is_active`, migración `00017`). Es distinto de `status`:
> `status` (`available`, `in_use`, `maintenance`) dice en qué anda hoy un camión activo;
> `isActive = false` lo deja fuera de la selección para rutas **nuevas** conservando su
> historial. Sale en `GET /api/vehicles`, `GET /api/vehicles/[id]`, en el cuerpo de `POST` y
> `PATCH` y **en la bajada del espejo** (`cambios.vehicles[].isActive`; ausente = activo).
> Un vehículo inactivo no se puede asignar a una ruta: `400 El vehículo está inactivo y no se
> puede asignar a una ruta.` (armar ruta, `PATCH` de la ruta, armar zona y fijar el camión
> previsto de una zona).

## `GET /api/vehicles`

- **Auth**: usuario. **Alcance**: sí.
- **200**: array de `Vehicle` por `createdAt desc`, con
  `_count: { routes, orders, orderAssignments }` y
  `routes: [ { id, name, routeCode, status } ]` — **sólo la más reciente** (`take:1`,
  `createdAt desc`) entre las que tienen `status != 'completed'`.

## `POST /api/vehicles`

- **Auth**: usuario. **Alcance**: sí (el vehículo nace en `scope.branchId`, si lo hay).
- **Cuerpo**: `{ name, type?, plate?, capacity?, status?, isActive?, notes?, costoKmUsd?, usarParaDomicilio? }`.
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
- **Cuerpo** (sólo los presentes): `name`, `type`, `plate`, `capacity`, `status`, `isActive`,
  `notes`, `costoKmUsd`, `usarParaDomicilio` (se normaliza a `=== true`). `isActive` ausente
  no cambia nada.
- Si `usarParaDomicilio === true`: dentro de la transacción se desmarcan los demás del
  `targetType` (`data.type` si viene, si no el actual) dentro del alcance, excluyendo el
  propio id.
- **Después** de la transacción: si `data.status === 'available'` y el vehículo estaba
  `in_use` → `Route.updateMany where { vehicleId: id, status: { not:'completed' } }
  → status:'completed'` (auto-completa su ruta activa).
- **200**: el `Vehicle` actualizado.
- **Un camión COMPARTIDO (`branch_id` NULL) sólo lo cambia quien ve todas las sucursales**
  (`SUPER ADMIN`, `DESARROLLADOR`; 1.0.29): `403 {"error":"Este vehículo es compartido por todas
  las sucursales: sólo un SUPER ADMIN o un DESARROLLADOR puede modificarlo, darlo de baja o
  eliminarlo."}`, **antes** de escribir nada. Verlo y usarlo en una ruta sigue siendo de todas;
  quién puede dar de alta o editar un camión **propio** no cambia.
- **Modelos**: `Vehicle`, `Route`.

## `DELETE /api/vehicles/[id]`

- **Auth**: usuario. **Alcance**: sí. `404 {"error":"Not found"}`.
- **Compartido (`branch_id` NULL)**: el mismo `403` que el PATCH para quien no ve todas.
- **La carrera con una ruta recién creada** (1.0.29): si entre la comprobación y el `DELETE`
  otra petición crea una ruta con este camión, la clave ajena responde 23503 y eso se contesta
  `409` con el mismo literal de «tiene rutas asociadas» (antes, `500 Error interno`).
- **Un vehículo con rutas NO se borra, ni siquiera con las históricas** (07/10/2026,
  incidencia 4): `409 {"error":"No se puede eliminar este vehículo porque tiene rutas
  asociadas, incluso históricas. Márcalo como inactivo para impedir que se use en nuevas
  rutas."}`. Se comprueba antes de la transacción y otra vez dentro (una ruta pudo
  aparecer entre medias) y el `DELETE` lleva su propia guarda. Antes se soltaba el camión de
  sus rutas y se borraba; esa consulta se eliminó. El texto antes decía «Ponlo en
  mantenimiento»: el mantenimiento es un `status` pasajero que no impide asignarlo, y lo que
  se pidió es el estado activo/inactivo.
- Sin rutas: borra sus asignaciones (`OrderVehicle.deleteMany({vehicleId:id})`) y el `Vehicle`.
  Ya no existe `Order.vehicleId` que desasociar (ver `modelo-datos.md`).
- **200**: `{"success":true}`.
- **Modelos**: `OrderVehicle`, `Vehicle`.

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
- Deja la línea de rastro `ajustes guardados` (ver «Rastro de quién»). Que **no exija admin**
  es una DECISIÓN ABIERTA de Jose (1.0.29): la tasa del día la pone quien esté, y también
  puede cambiarla cualquiera con sesión.

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

# 11. Tablero: colocar una tarjeta y armar una zona (propio del reparto, 07/10/2026)

Esto **no existe en delivery (Next)**. El tablero entero está especificado en `tablero.md`; aquí
sólo lo que cambió el 07/10/2026 y que otros clientes copian.

## `PUT /api/board/placements/{pedidoId}` — colocar o mover una tarjeta

Cuerpo `{ "columnaId": "uuid", "posicion": 1 }`. La validación es el `WHERE` de la propia
sentencia que escribe (sin lectura previa que se quede vieja); cero filas se traduce a **un
solo** `409`/`404`, y el motivo se elige en este orden de prioridad:

| Código | Mensaje | Cuándo |
|---|---|---|
| 409 | `Ese pedido ya se entregó` | `deliveredAt` o `resultado = 'entregado'`. Va **primero**: un entregado no está esperando a nada. |
| 409 | `Ese pedido ya está en una ruta` | `routeId` puesto |
| 409 | `No se puede asociar al tablero: la factura no tiene un cobro de domicilio registrado.` | `facturaDomicilio` nulo o `<= 0` (Amado, 07/10/2026) |
| 409 | `No se puede asociar al tablero: primero cotiza el domicilio del pedido.` | `pedidoCosto` nulo (Amado, 07/10/2026) |
| 404 | `Esa zona del tablero ya no existe` | el pedido existe y está libre: lo que no cuadra es la columna |
| 404 | `Ese pedido no existe o no es de tu sucursal` | no existe **o** es de otra sucursal (no se distingue) |
| 409 | `Otro aparato puso una tarjeta en ese mismo sitio en el mismo momento. Vuelve a intentarlo.` | choque de posición al confirmar |

- **`facturaEstado` NO es condición de colocar.** Se llegó a exigir `igual`/`cambiado`
  («primero coteja la factura del pedido») y se quitó el mismo día: un pedido `cambiado` o sin
  cotejar se puede preparar en una zona. **Lo corta el armado**, con su motivo. Y `cambiado`
  **no entra a una ruta**.
- Un rechazo **no mueve la tarjeta**: la transacción se deshace y el pedido sigue en la
  columna de la que venía.
- «Sin colocar» (`GET /api/board`, mitad izquierda) y su contador sólo ofrecen lo que esto
  acepta por las dos condiciones de Amado, y por eso nunca ofrecen una tarjeta que acabe en
  el `409` de arriba.

## `POST /api/board/columns/{id}/route` — armar una zona

Lo que no puede subir se cae **nombrado** en `descartados[]` (`pedidoId`, `operationNumber`
—el conduce—, `customerName`, `motivo`, `queHacer`) y la ruta sale con el resto; si no queda
ninguno, `409` con `descartados` dentro. Motivos de la factura y el domicilio, en este orden
(tras `ya se entregó` y `archivado en PEDIDO`): `sin cotejar` (nulo), `sin factura`,
`cambió en la factura` (**`cambiado` no sube**), **`la factura no tiene domicilio cobrado`** y
**`domicilio sin cotizar`** (los dos últimos, Amado 07/10/2026).

**Lo que el aparato no eligió se nombra con su motivo VERDADERO (1.0.29).** Cuando la APK manda
`pedidoIds`/`orderIds` con las buenas solamente, una tarjeta de la zona que no se puede cargar
(sin cotizar, sin domicilio cobrado…) tampoco viene en su lista. El servidor le decía «lo pusieron
en la zona después de que armaras», que es falso; ahora dice su motivo de la lista de arriba (el
mismo código decide ambos bucles). «Lo pusieron en la zona después…» queda sólo para las que
sí serían buenas. No cambia ningún literal.

Camión: `400 El vehículo está inactivo y no se puede asignar a una ruta.` tanto si viene en el
cuerpo como si es el **previsto** de la zona (un camión que se dio de baja después de
asignarlo a la zona). Se mira después de la comprobación de sucursal.

## Borrar una zona

Una zona vacía de tarjetas se borra aunque tenga una ruta planificada nacida de ella
(`board_route_origins.column_id` es `ON DELETE CASCADE` desde el 07/10/2026): antes contestaba
el `409` falso «tiene 0 pedidos puestos». Con tarjetas puestas la base sigue negándose.

---

# 12. La bandeja de revisión: entregar lo que no se pudo subir y decidir (Accesos + `sync`, 09/10/2026)

Quien pierde `delivery.entrar` conserva su cola en el aparato pero no tiene token con el que subirla. Accesos le
da, **solo si conserva la sesión viva**, un token de 10 minutos y un solo ámbito; con él el aparato deja cada apunte
en una tabla de `sync`, **tal como vino y sin aplicarlo**; y una persona que sí tiene permiso lo **aplica** o lo
**descarta con motivo**. El diseño y la lista de lo que cambió respecto a él están en
`docs/bandeja-de-revision.md` («Estado real (09/10/2026)»); lo que sigue es el contrato **tal como está en el código**.

Formato de error: Accesos contesta `{"error":"<marca>"}`; `sync` contesta `{"error":"<frase>","codigo":"<marca>"}` y
el `codigo` se omite cuando no hay marca (`sync/internal/httpx`). La frase es la que lee la persona.

## 12.1 Accesos: `POST /api/auth/entrega`

`auth/src/app/api/auth/entrega/route.ts` y `emitirEntrega` en `auth/src/lib/apk-tokens.ts`. CORS y `Cache-Control:
no-store` como las otras tres puertas de la APK.

- **Cuerpo:** `{"refresh_token":"…"}` (`refresh` vale como alias), de 1 a 256 caracteres. **No gasta el refresh y no
  devuelve refresh**: el par de la persona queda como estaba.
- **Qué comprueba, en este orden y sin firmar nada hasta el final:** límite de tasa (por IP y por huella del refresh;
  **si Redis no contesta en 800 ms se CIERRA**: es una puerta nueva) → el refresh existe → no está revocado → no está
  gastado (solo vale la cabeza de la cadena; uno ya gastado es 401 **sin** revocar la cuenta: castigar robos es cosa
  de `/refresh`) → no está caducado → es de Reparto → la **sesión** de better-auth existe, no está revocada ni caducada
  → la persona está **activa** y tiene sucursal (`resolverIdentidad`) → y **la llave la última**: si SÍ tiene
  `delivery.entrar`, no se firma.
- **Límites de tasa:** por IP, cubo de 60 con reposición de 1 por segundo; por huella del refresh, cubo de 10 con 1 cada
  10 segundos. La huella (sha256) es lo único que va a Redis; el refresh no.

| Respuesta | Cuándo |
|---|---|
| `200 {"token","token_type":"Bearer","expires_in":600,"ambito":"reparto.entrega"}` | Sesión viva, persona activa con sucursal y **sin** la llave |
| `400 {"error":"invalid_json"}` / `{"error":"invalid_body"}` | Cuerpo que no es JSON / sin refresh o de más de 256 caracteres |
| `401 {"error":"invalid_refresh"}` | Refresh inexistente, revocado, gastado, caducado o de otra aplicación; **sesión revocada o caducada; persona de baja**. Mismo cuerpo para todos (distinguirlos solo le cuenta a quien prueba tokens en qué estado están las filas); el motivo real queda en la auditoría |
| `403 {"error":"sin_sucursal","message":"La cuenta no está dada de alta en ninguna sucursal, o la sucursal pedida no es suya."}` | Entró bien pero no hay alcance que firmarle |
| `409 {"error":"tiene_permiso","codigo":"tiene_permiso"}` | **SÍ** tiene `delivery.entrar`: que renueve con `/refresh`. Si no, podría usar la revisión para que otro aplique sus gestos con más autoridad |
| `429 {"error":"rate_limited"}` | Tasa por IP o por huella |
| `503 {"error":"comprobacion_no_disponible"}` | El limitador (Redis) no contestó, o la base falló. **Nunca un 500**, y nunca un 401/403: la app conserva toda su cola y reintenta |

- **Auditoría en Accesos:** `auth.apk.entrega` y `auth.apk.entrega_denegada` (con el motivo interno: `refresh_revocado`,
  `refresh_gastado`, `refresh_caducado`, `otro_cliente`, `sesion_revocada`, `baja`, `sin_sucursal`, `tiene_permiso`).
  Sin el token ni el refresh.
- **`/api/auth/refresh` ya no contesta lo mismo.** Desde `8ba2642`, `renovar` mira la sesión revocada y la baja
  **antes** de la llave (`puertaDeRenovar`), en el camino normal y en la gracia: una sesión revocada sin llave da
  **401** (y cierra la familia), no 403. Con esto, el `403 {"error":"sin_permiso","codigo":"sin_permiso"}` de
  `/refresh` quiere decir de verdad «tienes sesión y no tienes llave». **A esa misma persona `/refresh` le da 403 y
  `/entrega` le da 200: la entrega NO sustituye a la renovación** (no rota el refresh ni devuelve un token normal).
  Si la base cae después de gastar el refresh, `/refresh` da 503 (`RenovacionNoDisponible`) y no un 500.

## 12.2 El token de entrega

HS256 con el `JWT_SECRET` de siempre (el mismo que firma el acceso), `purpose:"apk:entrega"`.

| Claim | Valor |
|---|---|
| `sub`, `name`, `email`, `sid` | La persona (el `name` sale de aquí, **no** del cuerpo de la entrega) y su sesión |
| `sucursal`, `branch_id` | El **código** de la sucursal (`STG`), como el acceso normal |
| `ambito` | `"reparto.entrega"` |
| `entradas`, `roles`, `role` | `[]`, `[]`, `""`: nada que un verificador pueda tomar por un permiso |
| `iatms` | La hora, en milisegundos, de **leer la sesión** (igual que el acceso; para las marcas de invalidación de Accesos). Extra respecto al diseño |
| `jti`, `iat`, `exp`, `iss` | `exp = iat + 600` |

- **Qué abre:** solo `POST /sync/revision/entrega` y `GET /sync/revision/mias` (12.3). En **cualquier otra ruta**
  es una credencial que no vale: **la API contesta `401`** (`auth.ErrAmbito`: se rechaza por **presencia** de `ambito`,
  con cualquier valor y aunque traiga `delivery.entrar`) y **`sync` contesta `403 sin_permiso_reparto`**
  (`identidad.verificar`; lo mismo con `Ambito` o `AMBITO`). `GET /api/me` con él da `401 {"user":null}`. Las dos mitades
  se atan con `docs/ambito-de-entrega.casos.json` (44 casos), que solo compara «entra / no entra», no el código.
- **El corte `web` también llega a `sync` (tanda final, 09/10/2026).** La bandeja del revisor en la web llama a `sync` con el token de
  la cookie (siete días, `web:true`) como Bearer. `sync` guarda ahora **dos mapas de marcas, `web` y `todo`** (`sync/internal/sesiones`,
  gemelo de la API; el SCAN de Redis recoge las dos familias, también al recargar): un token `web:true` no vale si `max(web, todo) >=
  iatms`, o sea que **tras cerrar sesión SOLO en el navegador, ese Bearer da 401 en `/sync/*`** (antes seguía aplicando y descartando
  hasta 7 días). La APK, el escritorio y el token de entrega siguen con solo `todo`: un cierre del navegador no los toca.
- **Qué exige `sync` para aceptarlo** (`identidad.DeTokenDeEntrega`): firma, `exp` obligatorio, `nbf`, `sub`, el
  corte de sesiones de Accesos (un cierre `todo` posterior lo mata: 401), `ambito` y `purpose` **exactos**, `entradas`
  **presente, array y sin `delivery.entrar`**, ningún rol, `jti` e `iat` presentes, vida ≤ 11 minutos (los 10 y un
  minuto de holgura) y sucursal resoluble. Nunca guarda el token en `Identidad.Token`: lo que se reenvíe al reparto
  tiene que ser un token de persona con llave, y este jamás.

## 12.3 `sync`: lo que entrega quien perdió el permiso (token de ENTREGA)

Montadas en el mux público de `sync/cmd/sync/main.go` (`RutasDeRevision`), cada una con su fuente de identidad:
`entrega` acepta **solo** el token de entrega; `mias`, ese **o** el normal de la misma persona. Todas las demás rutas
`/sync/*` siguen detrás del `Exigir` normal, que rechaza el token de entrega.

### `POST /sync/revision/entrega`

```jsonc
{
  "aparato": "<uuid del aparato>",
  "version_app": "1.0.32",              // opcional; constancia
  "apuntes": [                           // 1 a 25 por petición; la app manda 1, en orden
    { "clave": "01J8…", "hecho": "2026-10-09T14:02:11Z",
      "metodo": "POST", "ruta": "/routes/local-9f3a/results",
      "cuerpo": { … },                   // se guarda TAL CUAL, los bytes; nunca se re-serializa
      "provisional": "local-9f3a",       // opcional; `local-` + 1 a 94 letras/números, o un UUID (hasta 100 caracteres)
      "resumen": "Marcar parada" }       // opcional; ayuda de lectura, ≤200, no vale como dato
  ]
}
```

**Comprobaciones, en este orden** (`revision_entrega.go`): (1) token de entrega, sin ser Super Admin y sin
`Token`; (2) tasa, 60 peticiones por minuto **por persona**; (3) el aparato **existe** (nunca se da de alta en modo
entrega) y es de **esta persona y de esta sucursal**; (4) **cada** apunte, entero, antes de guardar ninguno (una
entrega con un solo apunte malo no guarda ninguno): `clave` `^[A-Za-z0-9_.:-]{1,100}$` y no repetida en el envío,
método `POST|PUT|PATCH|DELETE`, **ruta de la lista blanca POR FORMA**: solo las ocho que la API tiene de escritura —`/routes`,
`/routes/{id}`, `/routes/{id}/stops/{pedido}`, `/routes/{id}/results`, `/board/columns`, `/board/columns/{id}`,
`/board/columns/{id}/route` y `/board/placements/{pedido}`—, con `{id}` = letras, números, `_` y `-` (un uuid, un `local-…`,
`orden`; **nunca un punto**) y, a continuación, una query opcional de pares simples. La forma es la profundidad exacta: `POST /board`
suelto, `/routes/.` o `/routes/a/b/c/d` dan 422 (antes valía «lo que venga detrás» y esas rutas entraban, el reparto contestaba 404
y `Aplicar` lo tomaba por una caída que paraba «aplicar todo» en un apunte que jamás iba a entrar). Sin `..` ni `//`, ≤300 caracteres, `hecho` presente, no más de 24 h en el futuro ni más de 60 días en el pasado,
cuerpo ≤128 KiB y JSON válido en UTF-8; (5) idempotencia por `(aparato, clave)`; (6) cupos de lo **vivo**
(`en_revision`, `aplicando`, `rechazado`), con la sucursal bloqueada para que contar y escribir sean una cosa.
La petición entera no puede pasar de 512 KiB.

**200:**

```jsonc
{ "resultados": [
  { "clave": "01J8…", "estado": "en_revision",      // lo acabo de guardar
    "estadoActual": "en_revision", "revision": "<uuid de la entrega>" },
  { "clave": "01J9…", "estado": "repetido",          // ya lo tenía
    "estadoActual": "aplicado|rechazado|descartado|aplicando|en_revision",
    "revision": "<uuid>",                             // ausente si lo resolvió antes la subida normal
    "motivo": "…",                                    // el literal del reparto (rechazado) o la FRASE «Descartado en la revisión por X: motivo»
    "id": "<uuid>", "descartados": [ … ],             // si ya se aplicó (bandeja o libro `apuntes`): lo que creó y quién se cayó
    "decididoPorNombre": "Marta Pérez", "decididoAt": "…",   // si lo decidió una persona (aplicado o descartado)
    "motivoDelDescarte": "…" }                        // solo descartado: el texto que escribió quien descartó, SIN montar
] }
```

- **Lo que lleva un `repetido`** (ajuste del 09/10 pedido por la app, aditivo; todo `omitempty`): `id` y `descartados` cuando el apunte
  ya está aplicado —sin el `id` la app no puede sustituir su `local-…` por el de verdad y el apunte se queda con el aviso de
  huérfano—, tanto si salió del libro `apuntes` como de una revisión (las filas anteriores a la 00002 tienen `descartados` nulo y no
  se inventa una lista vacía); `decididoPorNombre` y `decididoAt` cuando lo decidió una persona; `motivoDelDescarte` en un
  descartado. `motivo` **no cambia**: sigue llevando la frase ya montada (no puede repetirse como clave). La subida normal
  (`POST /sync/subida`, paso 0) añade a su `repetido` de un descartado `decididoPorNombre` y `motivoDelDescarte` (sin `decididoAt`).
- **Idempotencia y huella.** Reentregar la misma clave con **el mismo contenido** → `repetido` con el estado de ahora;
  con **otro contenido** (la huella sha256 de `aparato|clave|método|ruta|cuerpo|provisional|hecho` no cuadra) →
  `409 huella_distinta` y **no se sobrescribe nada**. Una clave que la subida normal ya había aplicado o rechazado
  (libro `apuntes`) vuelve `repetido` **sin** `revision`, para no dejar que un revisor la aplique otra vez.
- **El `Aplicador` no se llama nunca aquí.** Entregar no toca pedidos, rutas ni tablero; solo escribe `revision_*`.
- **La subida normal también lo sabe** (`POST /sync/subida`, paso 0 de `unApunte`): una clave que está en la bandeja
  **no se aplica**; contesta `en_revision` si espera (o `aplicando`), `repetido` con el `id` si se aplicó, y `repetido`
  **con motivo** si está rechazada o descartada. `en_revision` es un estado nuevo del protocolo: la APK que lo entiende
  (`ResultadoApunte.deJson`, esquema 7 de la app) tiene que estar antes de que pueda contestarlo.

| Código | `codigo` | Cuándo y qué dice |
|---|---|---|
| 400 | — | `El cuerpo de la petición no es JSON válido` · `Falta el aparato` · `El aparato no es un identificador válido` |
| 401 | — | `Unauthorized`: token roto, caducado, cortado por Accesos, o de entrega pero con la llave / roles / otro `purpose` |
| 403 | `sin_permiso_reparto` | Token que **no es de entrega** (uno normal): `No tienes permiso para entrar a Reparto.` |
| 403 | `aparato_ajeno` | `Ese aparato no es tuyo.` (la persona o la sucursal del aparato no son las del token) |
| 404 | `aparato_no_registrado` | `Ese aparato no está registrado. Vuelve a darlo de alta.` Con la marca de siempre; **no** se da de alta |
| 409 | `huella_distinta` | `El apunte <clave> ya se entregó con otro contenido. No se ha guardado nada: avisa a quien mantiene la aplicación.` Queda un WARN en el registro |
| 422 | `entrega_no_admitida` | Sin apuntes · más de 25 · clave inválida o repetida · método o ruta fuera de la lista blanca por forma · `provisional` que no es `local-…` (1 a 94 letras o números) ni un UUID · sin `hecho` o con hora implausible · cuerpo de más de 128 KiB o que no es JSON · petición de más de 512 KiB. Cada una con su frase y el número del apunte |
| 429 | `tasa_de_revision` | `Demasiadas peticiones seguidas. Espera un minuto y vuelve a intentarlo: tu trabajo sigue en el aparato.` + cabecera `Retry-After` |
| 429 | `cupo_de_revision` | Tres frases: más de **500** cambios vivos por persona, más de **8 MiB** de cuerpos vivos por persona, más de **3.000** vivos por sucursal. Todas dicen «No se ha entregado nada» y qué hacer |
| 500 | — | `No se pudo guardar la entrega. Tu trabajo sigue en el aparato: vuelve a intentarlo.` |
| 503 | — | `No se pudo comprobar tu sucursal ahora mismo. Tu sesión sigue valiendo: se reintenta solo.` (el reparto no tradujo el código de sucursal) |

**El nombre del aparato tiene tope** (auditoría de seguridad, M3). `POST /sync/aparato` limpia y recorta `nombre` a **80** letras, la
migración `00004_nombre_de_aparato_acotado.sql` pone debajo `CHECK (char_length(nombre) <= 200) NOT VALID` (solo exige a las filas
nuevas o modificadas; antes recorta a 200 los nombres que ya hubiera, porque uno más largo haría fallar todo `UPDATE` de su fila), y la bandeja del revisor lo recorta a 200 al
leerlo (`left()` en las tres consultas y en Go). En la bandeja, `aparatoNombre` es un texto: `""` quiere decir «sin nombre».

### `GET /sync/revision/mias?aparato=<uuid>`

Qué ha pasado con lo que este aparato entregó. Acepta el token de entrega **o** el normal, **siempre de la misma
persona del aparato** (`403 aparato_ajeno` si no: ni un Super Admin lee lo de otra persona por aquí) y dentro de su
alcance. Mismos 400, 404 `aparato_no_registrado` y 429 `tasa_de_revision` que arriba; 500 `No se pudo leer el estado de
tus entregas`.

```jsonc
{ "entregas": [ { "clave":"01J8…", "estado":"en_revision|aplicando|aplicado|rechazado|descartado",
                  "revision":"<uuid>", "decididoPorNombre":"Marta Pérez", "decididoAt":"…",
                  "motivo":"…", "idCreado":"<uuid>", "descartados":[…] } ],
  "truncado": false }
```

Lo vivo primero y, dentro, lo más reciente; **tope de 1.000** (`truncado:true` si se alcanzó: lo que se queda fuera es
lo más viejo ya decidido). `motivo` es el motivo escrito del descarte, o el literal del reparto si no pudo aplicarlo.
Sin sondeo automático en la app: lo consulta el ciclo (solo si hay algo en revisión) o «Actualizar estados».

## 12.4 `sync`: la bandeja del revisor (token NORMAL)

Cinco rutas, montadas en `Servicio.Rutas` (`RutasDelRevisor`), o sea detrás del `Exigir` normal: **el token de entrega no
entra**.

**Quién revisa** (`identidad.RolDeRevisor`): el rol **por nombre**, exacto en ASCII (sin plegado Unicode), entre
`ADMINISTRADOR`, `SUPER ADMIN` y `DESARROLLADOR`, y **con token** y sin `ambito`. LOGISTICO entra a Reparto pero no
revisa; el `admin` heredado tampoco; en modo cabeceras (`SYNC_IDENTIDAD=cabeceras`, sin token) nunca se aplica.
**Nadie revisa lo suyo** (`persona <> revisor`). El **alcance** es el de siempre (`Identidad.Alcance()`): el
ADMINISTRADOR de CAM no lista ni aplica lo de HOL, ni por lista ni por id; un SUPER ADMIN o DESARROLLADOR sin sucursal
ve las ocho. Ambas cosas las decide **el SQL, en la misma sentencia que escribe**; `porQueNo` solo pone la frase con una
segunda lectura que no concede nada.

| Ruta | Qué hace |
|---|---|
| `GET /sync/revision[?sucursal=<uuid>]` | `{"entregas":[{"id","aparato","aparatoNombre","persona","personaNombre","sucursal","entregadaAt","versionApp","enRevision","aplicando","rechazados","aplicados","descartados"}],"truncado"}`. Una fila **por entrega** con algo esperando; las cuentas son de **toda** la entrega. FIFO, **tope 500** (`truncado`). `?sucursal` solo estrecha y solo a quien ve todas; a un administrador se le ignora. Sin nombre de sucursal (solo el uuid) |
| `GET /sync/revision/{entrega}` | `{"entrega":{…igual…},"apuntes":[{"aparato","clave","orden","metodo","ruta","cuerpo","provisional?","hechoAt","estado","motivo","decididoPorNombre","decididoAt","intentos","idCreado","descartados?","resumenDelAparato?","interrumpido?"}]}`. `cuerpo` es **un texto con el original exacto**, no un objeto |
| `POST /sync/revision/{aparato}/{clave}/aplicar` | Cuerpo opcional `{"reintentarInterrumpido":true}`. `200 {"resultados":[{"clave","estado":"aplicado"\|"rechazado","motivo?","id?","descartados?"}]}` |
| `POST /sync/revision/{entrega}/aplicar` | «Aplicar todo en orden». `200 {"resultados":[…],"detenido?","detenidoEn?","detenidoPorque?","sinProcesar?"}`. **Se detiene** en el primer apunte que no queda `aplicado`. Salta lo `aplicado` y lo `descartado`; reintenta lo `rechazado` (gesto explícito) una sola vez |
| `POST /sync/revision/{aparato}/{clave}/descartar` | `{"motivo":"…"}` de **≥5 caracteres** (contados en letras, tras recortar). `200 {"resultados":[{"clave","estado":"descartado","motivo","decididoPorNombre","decididoAt"}]}`. **No borra**: marca `descartado` con quién y cuándo, y lo anota en el libro |

**Aplicar, en orden** (`revision_aplicar.go`): (1) el candado: `UPDATE … WHERE estado IN ('en_revision','rechazado') AND
persona <> revisor AND <alcance>` a `aplicando` — dos revisores o un doble clic, un solo ganador; (2) se vuelve a
validar lo de la subida normal y **la lista blanca de método y ruta** (entre entregar y aplicar pueden pasar días);
(3) **la misma tubería** que la subida normal (`reenviar`: mismo traductor de `local-…`, mismo `Aplicador`) con el
**token del revisor** y las tres cabeceras de 12.5; (4) el resultado:

* **Antes de reenviar**, tras reclamar la fila, `aplicar` mira el libro `apuntes` (B6 de la auditoría): si la subida normal ya había
  **aplicado** esa clave (p. ej. con un `sync` viejo), cierra el apunte como `aplicado` **sin reenviar**, con el `id` y los
  `descartados` del libro y una nota en el libro de decisiones; si la había **rechazado**, lo deja `rechazado` con ese motivo literal.
  Así no se aplica dos veces.
* 2xx → `aplicado`, y en **una transacción**: el cierre, el libro `apuntes` —copiado con `ON CONFLICT DO NOTHING` (`CopiarApunteAplicadoAlLibro`); si ya estaba, un aviso «DOS VECES» en el registro— (para que la reentrega normal dé `repetido`
  pasados los 30 días de la bandeja), el `local-…` traducido y el libro de decisiones.
* 4xx del reparto (o un rechazo propio: lista blanca, validación, un `local-…` que no llegó) → `rechazado` con el
  **motivo literal**; sigue vivo y a la vista; **no se reintenta solo**.
* 5xx o red → **no es un rechazo**: vuelve a `en_revision` con un intento más y `502 reparto_no_disponible`.
* El reparto dice `403 sin_permiso_reparto` → el que no tiene permiso es el **revisor**: el apunte vuelve a `en_revision`.
* Si el proceso muere con la fila en `aplicando`, pasados 10 minutos sale con `"interrumpido":true`; reintentarla exige
  `reintentarInterrumpido:true` (la API no lee `X-Apunte`: no hay otra red) y deja `interrumpido` en el libro.
* Todo lo posterior al candado va con `context.WithoutCancel`: cerrar la pestaña no deja el reparto a medias.

| Código | `codigo` | Cuándo |
|---|---|---|
| 400 | — | `La sucursal no es un identificador válido` · `La entrega no es un identificador válido` · `El aparato no es un identificador válido` · `La clave del apunte no es válida` · `El cuerpo de la petición no es JSON válido` |
| 401 | — | `Unauthorized`; con el token de entrega, **403 `sin_permiso_reparto`** |
| 403 | `no_revisa` | `No tienes permiso para revisar. Revisan el administrador de la sucursal, el super administrador y el desarrollador.` |
| 403 | `es_lo_tuyo` | `Lo entregaste tú. Nadie revisa lo suyo: tiene que decidirlo otra persona.` |
| 403 | `sucursal_ajena` | `Esa entrega es de una sucursal que no ves.` / `Ese apunte es de una sucursal que no ves.` |
| 403 | `sin_permiso_reparto` | Al aplicar: el **revisor** no tiene permiso en Reparto. El apunte vuelve a `en_revision` |
| 404 | `no_encontrado` | `Esa entrega no existe.` / `Ese apunte no existe.` |
| 409 | `ya_se_esta_aplicando` | `Ya lo está aplicando <quién>. Espera a que termine y actualiza la bandeja.` / `Otro revisor acaba de tomarlo. Actualiza la bandeja.` |
| 409 | `ya_decidido` | `Ya está aplicado (lo aplicó <quién>).` / `Ya está descartado (lo descartó <quién>).` |
| 422 | `motivo_obligatorio` | `Descartar exige un motivo escrito de al menos 5 caracteres: queda anotado con tu nombre y la hora.` (y el `CHECK` de la base por debajo) |
| 502 | `reparto_no_disponible` | `El reparto no contestó. El apunte sigue en revisión: vuelve a intentarlo en un momento.` |
| 500 | `no_se_pudo_anotar` | El reparto aplicó (o rechazó) y la base no lo pudo anotar: el apunte queda `aplicando`. `comprueba a mano la ruta … ANTES de reintentarlo, o se aplicará dos veces` |
| 500 | — | `No se pudo leer la bandeja de revisión` · `No se pudo leer la entrega` · `No se pudo leer el apunte` · `No se pudo aplicar. Actualiza la bandeja para ver cómo quedó antes de repetir.` · `No se pudo descartar. Nada cambió: vuelve a intentarlo.` |

En «aplicar todo», si **ni el primero** se pudo tomar, la respuesta es el error de ese apunte (no un `200` con
`detenido`); si se detiene después de al menos un resultado, es un `200` con `detenido:true`.

## 12.5 Cabeceras que `sync` añade al aplicar: `X-Autor`, `X-Revision`, `X-Sucursal-Id`

Solo las pone la revisión (`sync/internal/reparto/reparto.go`, solo si vienen; la subida normal no las manda).

| Cabecera | Valor | Qué hace la API con ella |
|---|---|---|
| `X-Autor` | El `sub` de quien hizo el gesto | **Solo rastro**: sale como `autor` en la línea `peticion` de **toda escritura** (POST/PUT/PATCH/DELETE) |
| `X-Revision` | El id de la entrega | **Solo rastro**: sale como `revision`, en la misma línea |
| `X-Sucursal-Id` | La sucursal del apunte, **forzada** | La API ya la leía, y **solo para SUPER ADMIN y DESARROLLADOR sin sucursal en el token**: acota a UNA sucursal a un revisor que ve las ocho |

`X-Autor` y `X-Revision` **no autorizan nada, no cambian `actor` ni `rol`** (siempre salen del token verificado), se
recortan a 64 caracteres (con `…`) y un valor vacío no se anota (`api/internal/httpx/middleware.go`, `autoriaDe`; ya no en
`api/internal/api/rastro_de_quien.go`). Como son
cabeceras de quien llama, **cualquiera que llegue a la API puede escribirlas** (la línea sale aunque no haya sesión): sirven para leer el registro, nunca para
decidir. La API **no lee `X-Apunte`** (solo lo escribe `sync`).

## 12.6 `GET /sync/estado` suma `en_revision`

`{"aparatos":[…],"bandeja":[…],"sin_atender":[…],"en_revision":[{"sucursal":"<uuid>","en_revision":N}]}`: lo vivo
(`en_revision`, `aplicando`, `rechazado`) por sucursal, con el alcance de siempre (`RevisionSinDecidirPorSucursal`). Es el
segundo «número rojo». Ninguna pantalla lo enseña todavía.

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
| `/api/routes` POST | 409 | `En una ruta sólo entra lo facturado con domicilio cobrado. <N> no cumplen: <detalle>[ y <K> más.\|.]` |
| `/api/routes` POST | 409 | `No se puede crear la ruta: <N> pedidos no tienen cotizado el domicilio en Entrega: <detalle>[ y <K> más.\|.]` |
| `/api/routes` POST, `/api/routes/[id]` PATCH, `/api/board/columns/[id]/route` | 400 | `El vehículo está inactivo y no se puede asignar a una ruta.` |
| `/api/routes` POST | 400 | `Peso total (<X.X> kg) supera la capacidad del vehículo (<C> kg)` |
| `/api/routes/{id}/stops/{orderId}` DELETE | 400 | `Identificador de pedido no válido` |
| `/api/routes/{id}/stops/{orderId}` DELETE | 409 | `Sólo se pueden retirar paradas de una ruta planificada` |
| `/api/routes/{id}/stops/{orderId}` DELETE | 409 | `El pedido no pertenece a una ruta planificada o ya fue retirado` |
| `/api/board/placements/[id]` PUT | 409 | `No se puede asociar al tablero: la factura no tiene un cobro de domicilio registrado.` |
| `/api/board/placements/[id]` PUT | 409 | `No se puede asociar al tablero: primero cotiza el domicilio del pedido.` |
| `/api/routes/[id]` GET/PATCH/DELETE | 404 | `No encontrado` |
| `/api/routes/[id]/results` | 404 | `No encontrada` |
| `/api/routes/[id]/results` | 400 | `No vino ningún resultado` |
| `/api/routes/[id]/results` | 409 (rechazado) | `ese pedido no va en esta ruta` |
| `/api/routes/[id]/results` | 409 (rechazado) | `resultado '<v>' desconocido` |
| `/api/routes/[id]/results` | 409 | `Se guardaron <A> de las <T> paradas de esta hoja. <K> no se pudieron guardar: <conduce> (<motivo>)[, …][ y <K-5> más.\|.]` (`<conduce>` = `numeroOperacion`; el `orderId` recortado a 64 sólo si no hay) |
| `/api/orders/[id]` | 404 | `Not found` |
| `/api/orders/[id]` PATCH | 400 | `Ese campo no se cambia por aquí: usa las rutas o el tablero (<campos>)` |
| `/api/routes` POST | 400 | `No existe el vehículo '<id>'` (camión de otra sucursal) |
| `/api/vehicles/[id]` PATCH, DELETE | 403 | `Este vehículo es compartido por todas las sucursales: sólo un SUPER ADMIN o un DESARROLLADOR puede modificarlo, darlo de baja o eliminarlo.` |
| todas con alcance | 403 | `esta cuenta no está dada de alta en ninguna sucursal: pide en la oficina que te asignen la tuya` |
| todas con alcance | 403 | `tu sucursal <CÓDIGO> no está dada de alta en Reparto: pide en la oficina que la den de alta` |
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
| `/api/vehicles/[id]` DELETE | 409 | `No se puede eliminar este vehículo porque tiene rutas asociadas, incluso históricas. Márcalo como inactivo para impedir que se use en nuevas rutas.` |
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

# Apéndice: tabla resumen de las 35 rutas de delivery (más las propias del reparto, anotadas «-bis»)

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
| 29-bis | `/api/routes/{id}/stops/{orderId}` | DELETE (propia del reparto, 07/10/2026) | usuario | sí | Order, board_placements, board_route_origins |
| 30 | `/api/routes/[id]/results` | POST | usuario | sí | Order |
| 31 | `/api/settings` | GET, PUT | usuario | no | Settings |
| 32 | `/api/tasa` | GET | usuario | sí | no |
| 33 | `/api/vehicles` | GET, POST | usuario | sí | Vehicle |
| 34 | `/api/vehicles/[id]` | GET, PATCH, DELETE | usuario | sí | Vehicle, Route, Order, OrderVehicle |
| 35 | `/api/version` | GET | ninguna | no | no |
