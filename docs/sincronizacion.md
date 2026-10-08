# El protocolo de sincronización

Entre la aplicación (`app/`) y el sincronizador (`sync/`). Es lo que hace posible que un
logístico trabaje un día entero sin conexión y no pierda nada.

## El día que hay que soportar

Diez logísticos, uno por sucursal, que arman las rutas de la suya. Por la mañana tienen
conexión. Durante el día, no. Al final del día, a veces.

```
mañana     con red   →  baja el día
día        sin red   →  prepara el tablero, arma rutas, cierra las que vuelven
cuando     con red   →  sube lo trabajado, en orden y con su hora
```

No hay un «modo sin conexión» que se encienda. **La aplicación se comporta igual siempre**:
guarda en el aparato y sube por detrás. Quien tenga red todo el día simplemente sube a
medida que trabaja.

---

## 1 · Bajada por diferencias

```
GET /sync/bajada?desde=<marca>&sucursal=<id>
```

Devuelve lo que cambió desde `desde`. Sin `desde`, la primera carga completa.

```jsonc
{
  "hasta": "2026-09-14T11:02:31.481Z",   // la marca para la próxima vez
  "completa": false,                      // true si fue carga inicial
  "cambios": {
    "orders":    { "puestos": [ … ], "quitados": ["id", …] },
    "routes":    { "puestos": [ … ], "quitados": ["id", …] },
    "customers": { "puestos": [ … ], "quitados": ["id", …] },
    "products":  { "puestos": [ … ], "quitados": ["id", …] },
    "vehicles":  { "puestos": [ … ], "quitados": ["id", …] },
    "branches":  { "puestos": [ … ], "quitados": ["id", …] },
    "warehouses":{ "puestos": [ … ], "quitados": [] },
    "settings":  { "puestos": [ … ], "quitados": [] }
  },
  "truncado": false,                      // hay más: repetir con el `hasta` devuelto
  "continuar": "eyJjIjoyMDAwfQ"           // …y con esto, cuando venga (ver abajo)
}
```

**`hasta` lo pone el servidor, nunca el aparato.** El reloj de un teléfono se mueve — se
cambia a mano, se va con la batería, salta de zona horaria. Si el aparato dijera desde
cuándo pedir, un reloj atrasado se perdería cambios para siempre sin que nadie lo note.

**`quitados` hace falta de verdad.** Sin él, un pedido archivado o una ruta borrada se
quedan en el aparato para siempre: la lista local sólo crece y nunca se limpia.

**Y hasta el 17/09/2026 se llenaba SÓLO para `orders`.** Este mismo documento pintaba
`"quitados": []` en las otras siete y nadie lo leyó como lo que era —el ayudante `conjunto()`
de `espejo.go` devolvía la lista vacía siempre—, sino como un hueco que ya se rellenaría. Se
vio con un teléfono delante: se borró una ruta desde la web y el aparato la siguió enseñando,
«Completada», 0 paradas, porque nadie le dijo nunca que ya no existía. Jose: «¿por qué no
actualiza a partir de lo que tiene el servidor? Eso no puede pasar».

Las lápidas de las demás colecciones viven en `bajas_de_la_bajada`
(`api/db/migrations/00006_bajas_de_la_bajada.sql`), puestas por disparador y con su motivo:
`borrado` o `movido` de sucursal, que **no son lo mismo para quien pregunta**. A quien ve las
ocho sucursales, algo que se mudó de Santiago a Holguín no se le ha ido de la vista: sigue
ahí, en otra sucursal, y mandárselo en `quitados` le borraría del aparato algo que existe.

Las dos que siguen vacías lo están por decisión escrita, no por olvido: `settings` es UNA
fila global que no se borra nunca, y `warehouses` vive en Accesos, que no dice qué borró.
Los dos motivos largos están en `espejo.go`, donde se sirven.

**`truncado`** existe porque la primera bajada de una sucursal grande no cabe de una vez en
la conexión de allá. Se pide por tandas hasta que venga `false`.

### `continuar`: por dónde seguir en lo que no tiene marca — 15/09/2026

**`truncado` sin esto era mentira, y costó un cuarto de los clientes.** Se probó la
aplicación de escritorio contra producción y la base del aparato quedó con
`clientes = 2000` redondos; con esa cuenta (Super Admin) son **8.034**. Dos mil es el tope
de una tanda (`TopeDeBajada`), y la bajada se dio por buena.

El motivo: `customers` y `products` **no se pueden trocear por marca de tiempo**. Se
ordenan por nombre, y las marcas que tienen (`synced_at`, `updated_at`) las comparten a
miles las filas que PEDIDO trae de una vez, porque entran en una sola transacción y
Postgres les pone la misma hora. Así que el servidor decía «queda más» y devolvía sólo
`hasta` — y el aparato volvía a pedir **exactamente lo mismo**, tanda tras tanda.

Ahora, cuando `truncado` es `true`, la respuesta trae `continuar`: una cadena **opaca** que
el aparato devuelve tal cual en la petición siguiente (`?continuar=…`) y **no mira por
dentro**. Lleva los desplazamientos de esas dos colecciones y, además, el `desde` de la
PRIMERA tanda de la cadena — sin eso, la segunda tanda filtraría el padrón contra una marca
que ya avanzó y no emitiría una sola fila.

Los pedidos siguen continuándose por `hasta`, que para ellos sí funciona: tienen
`cambiado_at` y el corte se hace por la marca de la última fila servida.

**Quien encadena tiene que parar cuando nada se mueve.** Si llega `truncado` y no avanzan
ni `hasta` ni `continuar`, la tanda siguiente traería lo mismo: se para **y se dice**. Una
bajada que se queda a medias no puede devolver un resumen indistinguible del de una
completa — ése fue el fallo de verdad, no que se cortara, sino que se cortara callándoselo.
En el aparato eso es `ResumenDeBajada.entera` (`app/lib/nucleo/sincro/bajada.dart`), y la
pantalla de «Configurando Reparto» se planta en «faltó» en vez de entrar.

### Requisito que hay que cerrar antes

Los 11 modelos necesitan `updatedAt`. Hoy sólo lo tienen 6, y sin esa marca **no hay
diferencias posibles**: habría que bajar el mundo entero cada mañana. Como no hay nada en
producción, esto no es una migración — es escribir el esquema bien a la primera.

**`orders` ya está cerrado** (14/09/2026). Y al cerrarlo salieron dos cosas que el
protocolo no decía y que valen para las demás colecciones:

- **La marca del pedido es la de sus renglones también.** Se filtra y se devuelve
  `GREATEST(orders.updated_at, max(order_items.updated_at))`: si cambia una línea, el
  pedido no se toca, y sin esto el aparato se queda con la lista de mercancía vieja.
- **`quitados` son tres casos, no uno.** Borrado, archivado y *salido del alcance de la
  sucursal*. Los dos primeros son obvios; el tercero —PEDIDO corrige la sucursal de un
  pedido— no se ve mirando la tabla de la sucursal vieja, porque la fila ya no está en
  ella. Hace falta dejar constancia de la salida (aquí, `orders_fuera_de_alcance`).
- **Con `truncado`, el `hasta` que se devuelve es el de la última fila servida**, no el
  reloj. Con el reloj, lo que no cupo cae por debajo del siguiente `desde` y no lo vuelve
  a pedir nadie. Quien encadena las tandas tiene que anotar el `hasta` DEVUELTO.

---

## 2 · Subida por lotes

```
POST /sync/subida
```

La cola del aparato entera, **en el orden en que se hizo**.

```jsonc
{
  "aparato": "…",                     // el identificador de esta instalación
  "apuntes": [
    {
      "clave": "01J8…",               // idempotencia: la pone el aparato, una por apunte
      "hecho": "2026-09-14T16:04:22Z",// la hora del APARATO, no la de la subida
      "metodo": "POST",
      "ruta": "/api/routes/local-9f3a/results",
      "cuerpo": { … },
      "provisional": "local-9f3a"     // si este apunte CREA algo, el id inventado
    }
  ]
}
```

Respuesta, **apunte por apunte** y en el mismo orden:

```jsonc
{
  "resultados": [
    { "clave": "01J8…", "estado": "aplicado", "id": "cm2x…" },
    { "clave": "01J8…", "estado": "repetido", "id": "cm2x…" },
    { "clave": "01J8…", "estado": "rechazado",
      "motivo": "3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos." }
  ]
}
```

### El orden importa

Marcar una parada y luego corregirla son dos apuntes sobre el mismo pedido. Subirlos al
revés deja puesta la primera marca. La cola es FIFO y el número lo pone la base local, no
el reloj.

### `repetido` no es un error

Una subida a medias —el servidor guardó y se cortó antes de contestar— reintenta. La
`clave` es lo que deja al servidor reconocerla y devolver lo mismo que la primera vez en
vez de aplicarla otra vez. Sin esto, una ruta creada sin red puede acabar duplicada.

**Lo MISMO quiere decir todo, y hasta el 29/09/2026 faltaba una cosa: los `descartados`.**
El caso: se arma una zona sin señal con doce pedidos, el apunte sube, el reparto crea la
ruta con **nueve** y nombra a los tres que se cayeron, y la respuesta se pierde por el
camino. El aparato reintenta, el servidor contesta `repetido` —correcto— pero sin el aviso
dentro: la ruta quedaba arriba con nueve de doce y en el teléfono parecía que había ido
entera. Ahora se guardan en `apuntes.descartados`
(`sync/db/migrations/00002_los_descartados_del_repetido.sql`) y vuelven con el `repetido`.

Un apunte anterior a esa migración la tiene **nula**, y se deja nula a propósito: no se
inventa una lista vacía, que se leería como «lo comprobé y no se cayó nadie».

### Los identificadores provisionales

Una ruta armada sin conexión no tiene identificador: lo pone la base de datos. Pero la
pantalla necesita uno **ya** para poder enseñarla, imprimir el despacho y cerrarla después.
El aparato se inventa uno (`local-…`), y cuando el apunte que la crea sube, la respuesta
trae el de verdad. **El aparato tiene que sustituirlo en todo lo que quedara en la cola
detrás**: la ruta sube bien y el cierre de la tarde iría a `/api/routes/local-9f3a/results`,
que no existe en ningún sitio. Se perdería el trabajo justo después de haberlo subido.

### `rechazado` no se reintenta y no se borra

El servidor dijo que no por algo. Queda a la vista con su motivo y su hora hasta que una
persona decida. Un apunte que desaparece solo es trabajo perdido que nadie sabe que perdió.

### La hora es la del aparato

Lo que se marca a las cuatro llega como las cuatro, aunque suba a las siete. En PEDIDO el
vendedor tiene que ver cuándo recibió su cliente, no cuándo pilló señal el teléfono.

---

## 3 · Registro de aparatos

```
POST /sync/aparato       alta de esta instalación
GET  /sync/estado        lo que ve el panel de control
```

Por cada aparato: quién lo usa, de qué sucursal, cuándo bajó por última vez, cuándo subió,
cuánto le queda pendiente y qué se le rechazó.

**Esto es lo que hoy no existe y es lo más valioso de todo.** Un logístico cierra el día, se
va a su casa y deja el cierre de la ruta sin subir; nadie se entera hasta que no cuadra el
inventario. Con el registro se ve que Palma lleva desde el martes sin subir, y se puede
llamar.

---

## Conflictos: casi no hay

El alcance ya está cerrado por sucursal: quien pertenece a una ve sólo la suya. Con un
logístico por sucursal son diez cajones que no se tocan — nadie le puede quitar un pedido a
nadie, y desaparece todo el arbitraje entre aparatos.

**La excepción es el Super Admin**, que ve todas. Si arma una ruta de Palma mientras el
logístico de Palma está sin señal, ahí sí chocan. El servidor lo rechaza —*«N de los M
pedidos ya están en otra ruta»*— y ese rechazo tiene que llegar de vuelta al aparato en vez
de perderse.

---

## Lo que el aparato dice antes y lo que el servidor confirma después — 07/10/2026

Tres gestos de la jornada se aplican **en el aparato al momento** y el servidor los
conoce al subir. Mientras tanto la pantalla enseña lo hecho en el aparato, y eso hay que
saberlo leer:

1. **Borrar una ruta que salió del tablero** (y **quitar una parada** de una ruta
   planificada). El apunte sube con la cola. Mientras no suba —y hasta que baje el tablero
   después— **las facturas salen en «Sin colocar»** y no en su zona, porque el origen de
   cada una (`board_route_origins`) vive sólo en el servidor y la bajada no lo trae.
   No se pierde nada: al subir el borrado el servidor las devuelve a su zona y a su
   posición, y la bajada siguiente las coloca. En la web no hay cola y es inmediato. Ver
   `tablero.md` §7.6-bis. Tampoco hay que renumerar ni recalcular nada a mano: quitar una
   parada deja el hueco en `stop_order` y no toca `total_distance`.
2. **Colocar una tarjeta sin domicilio cobrado o sin cotizar.** El servidor lo rechaza con
   un 409. Como arrastrar en la APK no llama a nadie, **el aparato dice el mismo «no» antes
   de colocar** (las mismas palabras que el servidor, para que no haya dos idiomas) y no
   encola el apunte: si se encolara, el rechazo llegaría horas después a la bandeja con la
   zona ya preparada. Lo mismo vale para armar con un camión inactivo
   (`El vehículo está inactivo y no se puede asignar a una ruta.`) y para los tres «no» de
   armar (`facturado y que cuadre`, `domicilio cobrado`, `domicilio cotizado`).
3. **Cerrar una ruta con una parada que el servidor rechaza.** El sincronizador convierte
   cualquier 4xx en un rechazo del apunte **entero**, sin leer `aplicados`: la hoja queda
   `rechazada` en la bandeja con el motivo y **retiene el `completed` de esa ruta** (las
   demás rutas siguen subiendo) hasta que una persona decida —*Reintentar* o *Descartar*—.
   Es deliberado de momento y está a la vista. **En la web, en cambio, un 409 parcial deja
   lo guardado por bueno**: el aviso dice el motivo y la ruta se puede completar; si no se
   guardó **ninguna** parada, es rechazo total y no se completa. La ruta local puede figurar
   completada mientras el apunte sigue en cola: eso no acredita el cierre en el servidor.

---

## Orden al recuperar la señal

```
1. renovar la sesión        ← primero, SIEMPRE
2. subir la cola
3. bajar diferencias
```

Ocho horas sin conexión dejan el token de acceso caducado. Si la cola sale con el viejo,
todo responde 401 y se para con el trabajo del día dentro. Ver `identidad.md`, y en especial
el candado: **una sola renovación en vuelo**.
