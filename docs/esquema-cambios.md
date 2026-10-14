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
