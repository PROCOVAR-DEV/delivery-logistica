# El esquema nuevo: en qué se aparta de delivery

La migración es `api/db/migrations/00001_init.sql`. Sale del modelo de Prisma documentado
en `modelo-datos.md`, con los cambios de abajo. **Todos son deliberados y ninguno es
gratis** — si alguno no te cuadra, se discute antes de escribir código encima.

> **Comprobado con el parser de Postgres** (`pglast`, que son las tripas de `libpg_query`):
> las 64 sentencias del `Up` y las 3 del `Down` son válidas, ninguna clave ajena apunta a
> una tabla que todavía no existe, los 8 enums declarados se usan todos y **las 13 tablas
> tienen su trigger de `updated_at`**.
>
> Lo que eso NO comprueba es que el servidor la acepte al aplicarla de verdad. Falta
> correrla contra un Postgres:
>
> ```
> docker run --rm -d --name pg -e POSTGRES_PASSWORD=x -e POSTGRES_DB=reparto postgres:16-alpine
> docker exec -i pg psql -U postgres -d reparto -v ON_ERROR_STOP=1 < api/db/migrations/00001_init.sql
> ```
>
> En este equipo no se pudo: docker está parado y arrancarlo pide la contraseña del PC.

---

## 1 · Ni un solo JSON

Lo que venía en JSON son **datos**, y los datos van en columnas y en tablas. Lo que haga
falta de PEDIDO lo extrae el espejo al traerlo, que para eso está: guardar el documento
entero «por si acaso» es tener el mismo dato en dos sitios y no saber cuál manda.

| Antes | Ahora | Por qué |
|---|---|---|
| `Settings.tiposVehiculo` | tabla **`vehicle_types`** | **El campo nunca existió en el esquema.** La pantalla de vehículos dejaba crear tipos nuevos, los mandaba a guardar y se perdían sin un solo error. Por eso `Vehicle.type` era un conjunto que nadie podía cerrar: su catálogo no estaba en ninguna parte. **14/10/2026: la app tardó en migrarse.** La API ya tenía la tabla y `/api/vehicle-types`, pero la app seguía mandando los tipos en `PUT /api/settings {tiposVehiculo}`; la API ya no lee ese campo (solo deja un WARN) y contesta 200, así que el cajón de tipos «guardaba» y los tipos se perdían en silencio: el mismo fallo de antes, ahora en el cliente. Arreglado ese día: la app usa `/api/vehicle-types` (ver `contratos-api.md`) y `GET /api/settings` ya no devuelve `tiposVehiculo`. |
| `Order.items` | tabla **`order_items`** | Dentro de un JSON no se busca. Por eso existía `productosTexto`, una copia de los nombres en texto plano metida a mano sólo para poder preguntar «¿qué pedidos llevan malta?». **Esa copia desaparece**: un dato copiado en dos sitios acaba discrepando, y este además se copiaba a mano. |
| `Settings.currencies` | tabla **`currencies`** | Una lista de cosas con su clave y su valor es una tabla. Así la moneda es única, se sabe cuándo cambió cada tasa, y corregir una no obliga a reescribir el array entero. |

| `Order.meta` y `Customer.meta` | **fuera** | Eran el documento entero de PEDIDO guardado «por si acaso». Lo que haga falta se extrae en el espejo y va a su columna. La red de seguridad no es una copia del JSON: es que **PEDIDO sigue teniendo el original** y el espejo puede volver a traerlo. |

---

## 2 · `updated_at` en las trece tablas, con trigger

En delivery lo tenían 5 de 11. Ahora lo tienen las trece, y lo mantiene un trigger
(`set_updated_at()`) en vez de la capa de aplicación: así no depende de que nadie se
acuerde, y **sin esa marca no hay bajada por diferencias**, que es lo que hace posible
trabajar sin conexión.

Las marcas de DOMINIO se quedan aparte y con su nombre: `traido_at`, `synced_at`,
`pedido_updated_at`, `cup_rate_updated_at`. Significan «cuándo lo trajo el origen», que no
es «cuándo se tocó la fila». Mezclarlas rompe el espejo.

---

## 3 · Los conjuntos cerrados pasan a ser enums

Prisma los tenía todos como `String`. Los valores salen de buscar qué escribe el código de
verdad, no de lo que el esquema declaraba: `order_status`, `stop_result`, `route_status`,
`vehicle_status`, `trip_leg`, `pedido_estado`, `factura_estado`, `procedencia`.

Dos decisiones dentro de esto:

- **`route_status` incluye `cancelled`** aunque hoy nadie lo escriba: el tablero ya lo
  excluye en sus consultas, y dejarlo fuera obligaría a un `ALTER TYPE` el día que se use.
- **`vehicle_status` NO incluye `maintenance`**: no existe en el código.

---

## 4 · Identificadores uuid

Los internos pasan de cuid a uuid. Los de sistemas ajenos —PEDIDO, Ventra— siguen siendo
`text` y se quedan como vienen: no son nuestros y no tienen por qué ser uuid.

Esto no rompe a nadie: quien consume el reparto lo hace por `external_id`, que es el id
**de PEDIDO**, no el nuestro.

---

## 5 · Reglas que pasan del comentario a la base

- **Un solo vehículo de referencia por sucursal.** En delivery era un comentario que pedía
  que «sólo uno debería tenerla en true». Ahora es un índice único parcial.
  *Hueco conocido:* los vehículos sin sucursal (`branch_id` NULL) se escapan, porque en un
  índice único los NULL son distintos entre sí. Si hace falta cerrarlo, va con
  `NULLS NOT DISTINCT`.
- **`settings` tiene una sola fila y la base lo impide** (`id boolean PRIMARY KEY CHECK
  (id)`), en vez de confiarlo a un `findFirst`. Dos filas de ajustes es media aplicación
  mirando una y media mirando la otra.

---

## 6 · No hay tabla de personas

El modelo `User` era un resto de cuando delivery tuvo login propio. Quien manda en
personas, roles y sucursales es **auth**, y el propio código de delivery lo delataba:

- `products/sync` tenía que **inventarse un dueño** (`findFirst where branchId null`) para
  poder escribir una fila del catálogo.
- Hay un comentario en `vehicles/[id]` diciendo que filtrar por `userId` devolvía **404
  sobre vehículos que existen**, porque los dio de alta otra cuenta.
- El tablero contaba «los pedidos de la cuenta que mira» en vez de los de la sucursal.
- Y su propio `scope.ts` ya lo dice: *«aquí nada pertenece a una persona: los pedidos
  entran solos desde PEDIDO y son de la sucursal que los originó»*.

Así que fuera la tabla y fuera los `user_id`. Donde hace falta dejar constancia de quién
hizo algo va **`creado_por`**: el id de esa persona en auth, como texto y sin clave ajena.
Es constancia, no una copia de la lista de personas que habría que mantener al día.

---

## 7 · Los índices del espejo pasan a ser ÚNICOS

`orders_origen_idx` y `customers_origen_idx`, sobre `(source, external_id)`, eran índices
normales. Eso deja una carrera real: dos pasadas del espejo a la vez leen «no existe» antes
de que ninguna escriba, y **crean el mismo pedido dos veces** — que sale dos veces en el
armador de rutas.

Ahora son únicos y parciales (`WHERE source IS NOT NULL AND external_id IS NOT NULL`),
porque el alta manual no tiene origen ni id externo y de esa puede haber las que sean.

Comprobado contra Postgres: el segundo `INSERT` con el mismo `(pedido, PAH25-001)` lo
rechaza la base, y dos altas manuales idénticas entran sin problema.

Con esto el upsert del espejo puede y debe ser `ON CONFLICT`, que es atómico. Las consultas
que hoy hacen buscar-y-escribir hay que cambiarlas.

---

## 8 · Los tipos de vehículo son POR SUCURSAL (00018, Jose 14/10/2026)

La tabla `vehicle_types` nació (§1) como el catálogo de **toda la empresa**, y el costo por km
de un tipo es el que cotiza el domicilio: que el logístico de Santiago editara «truck» movía el
precio en las ocho sucursales. Desde la `00018_tipos_de_vehiculo_por_sucursal.sql` cada sucursal
tiene SUS tipos y quien trabaja en una ve y toca sólo los suyos.

- **`vehicle_types.branch_id`** (nulable, sin `ON DELETE CASCADE`). **NULO = el tipo «de todas»**:
  los cinco de fábrica de la `00001`, que se quedan por los camiones **compartidos**
  (`vehicles.branch_id` nulo) y que ninguna sucursal puede tocar.
- **`nombre` deja de ser único en toda la tabla.** Son dos índices únicos parciales
  (`vehicle_types_nombre_de_todas`, `vehicle_types_nombre_por_sucursal`): el mismo nombre en dos
  sucursales sí, en la misma no. Son DOS porque en un único `(branch_id, nombre)` los nulos no
  chocan entre sí y se podrían repetir los «de todas».
- **A cada sucursal se le dio una COPIA de los tipos** (nombre, costo y estado), y cada camión con
  sucursal pasó a apuntar a la de la suya. Una sucursal creada después (`POST /api/branches`) recibe
  la misma copia de los «de todas» en la misma transacción.
- **La regla que queda** es: el tipo de un camión es de la sucursal del camión
  (`vehicles.branch_id IS NOT DISTINCT FROM vehicle_types.branch_id`). **La hace cumplir la API**
  (`BuscarTipoDeVehiculoPorNombre` busca por nombre PARA la sucursal del camión; un tipo de otra
  sucursal es un 400), no la base: no hay clave compuesta ni disparador. La consulta que la
  comprueba sobre datos reales está en `docs/despliegue.md`.
- **El filtro NO es el de los vehículos.** En `vehicles`, `branch_id` nulo pasa el filtro de
  alcance (un camión compartido sale en la lista de todas) y quien ve todas ve todo. En los tipos es
  `branch_id IS NOT DISTINCT FROM sucursal`, igual para las dos puntas: quien tiene sucursal ve y toca
  sólo los suyos (los «de todas» le son ajenos), y quien está en modo «todas» ve y toca **sólo los «de
  todas»**. Un id fuera de eso es un 404, no un 403. La API **no crea** tipos «de todas» (el alta en
  modo «todas» es 400): los de fábrica los creó la migración, y se editan, se retiran y se copian a
  las sucursales nuevas.
- **Sin vuelta atrás sin pérdida.** El `Down` devuelve los camiones al tipo «de todas» del mismo
  nombre y borra los de sucursal, pero **los costos que una sucursal haya editado en SU copia se
  pierden** (vuelve el del tipo de todas) y un nombre que sólo exista en sucursales se crea «de
  todas», con costo sólo si todas coinciden. Dicho en el propio `.sql` y atado por
  `TestMotorReal_Migracion00018TiposPorSucursal`.

## 9 · Los distribuidores, POR SUCURSAL (00019, issue 7 de Amado, 15/10/2026)

El distribuidor es la persona responsable de la entrega y de devolver las facturas entregadas: el
chofer mismo si va en triciclo, un empleado de Procovar si el vehículo es rentado. Es un
**nomenclador de cada sucursal**, no una persona de Accesos (§6: aquí no hay tabla de personas, sólo
un nombre y si sigue en activo). Se asocia a la ruta **al crearla**.

- **`distribuidores`** (`id`, `branch_id` **NOT NULL** sin `ON DELETE CASCADE`, `nombre` con
  `CHECK (btrim(nombre) <> '')`, `activo`, `created_at`/`updated_at` con `set_updated_at`). No hay «de
  todas» como en los tipos de vehículo.
- **Nombre único dentro de la sucursal** sin distinguir mayúsculas ni espacios de los bordes
  (`distribuidores_nombre_por_sucursal` sobre `(branch_id, lower(btrim(nombre)))`); la API además deja
  un solo espacio entre palabras.
- **`routes.distribuidor_id`** nulo y sin cascada. **NULO = ruta histórica o armada sin
  distribuidor**: la migración no inventa ninguno. Índice parcial para «¿lo usa alguna ruta?».
- **Retirar en vez de borrar**: el `DELETE` de la API sólo borra al que no usa ninguna ruta (lo
  comprueba en la misma sentencia); si alguna lo usa, lo pone `activo = false`.
- **La API valida la ruta** (`distribuidorDeLaRuta`, `rutas.go`/`distribuidores.go`): el distribuidor
  tiene que ser de la MISMA sucursal que la ruta y estar en activo; la clave ajena sola no sabe de
  sucursales.
- **Baja al aparato** como la colección `distribuidores` (valor nuevo de `coleccion_de_la_bajada`,
  lápida por disparador `AFTER DELETE`): la APK y el escritorio lo eligen sin conexión.
- **Alcance**: el de las rutas, no el de los tipos. Quien tiene sucursal ve y toca sólo los suyos (los
  ajenos son 404); el modo «todas» lee las listas de todas (cada fila con su sucursal) porque una ruta
  de cualquier sucursal tiene que poder decir quién la reparte, pero **no crea** (400).
