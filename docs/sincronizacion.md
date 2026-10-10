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

## 4 · Revisión: lo que entrega quien perdió el permiso — 09/10/2026

Quien pierde `delivery.entrar` conserva su cola en el aparato, pero **no puede subirla**: no hay token normal con el que
hacerlo (`/refresh` le da 403) y `sync` contesta `403 sin_permiso_reparto` sin anotar nada. La revisión es la salida:
con un token de **solo entrega** (Accesos, 10 minutos, un ámbito) el aparato deja cada apunte en una tabla aparte, **tal
como vino y sin aplicarlo**, y una persona con permiso lo **aplica** o lo **descarta con motivo**. Es contabilidad de la
sincronización —«lo que llegó y quién decidió»—, no un dato del negocio: vive en `sync/` (base `reparto_sync`) y no toca
pedidos, rutas ni tablero, que son de la API. Los contratos exactos, con todos sus códigos, en `contratos-api.md` §12; el
diseño y en qué se desvió, en `bandeja-de-revision.md`.

**La regla que manda sobre todo esto: una decisión de una persona se ESCRIBE, no se borra** (`CLAUDE.md` §4). Por eso es
la **base** —no solo el Go— la que lo impide (`sync/db/migrations/00003_la_bandeja_de_revision.sql`).

### Estados

```
entregar            en_revision ──aplicar (candado)──▶ aplicando ──el reparto dice 2xx──▶ aplicado        (final)
(desde el aparato)  en_revision ──descartar──────────▶ descartado                                          (final)
                    aplicando ──el reparto dice 4xx──▶ rechazado   (vivo, motivo LITERAL del reparto)
                    aplicando ──5xx o red────────────▶ en_revision (una caída no es un rechazo; +1 intento)
                    rechazado ──aplicar (reintentar)─▶ aplicando
                    rechazado ──descartar────────────▶ descartado
```

* `en_revision`: entregado, esperando a una persona. `aplicando`: un revisor lo reclamó y se está reenviando al reparto
  (el candado: dos revisores o un doble clic, un solo ganador). `aplicado` y `descartado` son finales y **no se
  reescriben**. `rechazado`: el reparto dijo que no al aplicar; **sigue vivo** con su motivo literal.
* **Vivo** = `en_revision`, `aplicando`, `rechazado`: lo que sigue esperando a una persona. Es lo que cuentan los cupos y el
  segundo «número rojo» de `GET /sync/estado` (`en_revision` por sucursal).
* **Nada se aplica ni se borra solo, por antigüedad ni por nada.** Un `aplicando` de hace 10 minutos o más sale como
  `interrumpido` y solo se reintenta con confirmación a mano (la API no lee `X-Apunte`: si el proceso murió después de
  que el reparto aplicara, reintentar sin mirar lo aplicaría dos veces).

### Las tres tablas

| Tabla | Qué es | Qué impide la base |
|---|---|---|
| `revision_entregas` | Quién entregó (el `sub` y el `name` del token **verificado**, nunca del cuerpo), desde qué aparato, con qué token (su `jti`; el token **jamás** se guarda), IP y agente recortados. `UNIQUE (aparato_id, token_jti)`: varias peticiones del mismo token caen en la misma entrega | `DELETE`, `TRUNCATE` y cualquier cambio de lo que ya consta |
| `revision_apuntes` | Una fila por apunte: `(aparato_id, clave)` es la primaria; `metodo`, `ruta`, `cuerpo` (**los bytes tal cual llegaron**), `hecho_at` (la hora del APARATO), `huella`, y la decisión (estado, quién, cuándo, motivo, `id_creado`, `descartados`, `intentos`) | `DELETE`/`TRUNCATE`; **cambiar el original** (lista blanca de las columnas que sí se mueven: una columna nueva nace inmutable); reescribir un `aplicado` o `descartado`; un descarte sin quién, cuándo y motivo de ≥5 letras; un `aplicando` o `aplicado` sin dueño; un `rechazado` sin motivo |
| `revision_decisiones` | **El libro: solo se añade.** Cada intento de aplicar y cada descarte, con quién, su rol, cuándo (`clock_timestamp()`, para que un «aplicar todo» no empate) y el resultado: `aplicado`, `rechazado`, `descartado`, `caida` o `interrumpido` | `UPDATE`, `DELETE`, `TRUNCATE` |

El libro **se escribe y ningún endpoint lo lee todavía.**

**Migraciones de la bandeja: dos.** La `00003` crea todo lo de arriba; la `00004_nombre_de_aparato_acotado.sql` (tanda final, M3) solo
añade `aparatos_nombre_acotado`. `ExigirMigraciones` espera ya la **4** (se deriva de los ficheros incrustados), así que `sync` se
niega a arrancar con la base en la 3. **El `Down` de la 00003 BORRA las tres tablas con lo que haya dentro** (`DROP TABLE`: los
triggers de `DELETE` no saltan), lo que contradice «una decisión se escribe»; la auditoría final lo midió y lo dejó como aviso:
**en producción no se usa** (`despliegue.md` §4-bis). Volver atrás es desplegar la imagen anterior, que no sufre por las tablas sobrantes.

### Idempotencia y huella

* La primaria `(aparato_id, clave)` es la idempotencia, igual que en `apuntes`. Reentregar la misma clave **con el mismo
  contenido** contesta `repetido` con el estado de ahora; con **otro contenido** —la **huella** sha256 de
  `aparato|clave|método|ruta|cuerpo|provisional|hecho` no cuadra— contesta `409 huella_distinta` y **no se sobrescribe
  nada**: o es un fallo de la app o es alguien manipulando, y queda un WARN en el registro. La inserción lleva
  `ON CONFLICT DO NOTHING` como red contra dos peticiones a la vez.
* El cuerpo se guarda como `json.RawMessage` y se hashea **tal cual**: re-serializarlo cambiaría la huella y el original.
* **La subida normal también la mira** (paso 0 de `unApunte`): una clave que está en la bandeja **no se aplica**. Así, quien
  entregó, recupera el rol y reenvía su cola no duplica nada: `en_revision`/`aplicando` → `en_revision`; `aplicado` →
  `repetido` con el `id`; `rechazado`/`descartado` → `repetido` **con motivo** (la app ya lo lee como «no subió»).
* Y al revés: una clave que la subida normal ya había aplicado o rechazado (tabla `apuntes`) **no se entrega**: contesta
  `repetido` sin `revision`, para que un revisor no la aplique otra vez.
* **Aplicar escribe TAMBIÉN en el libro `apuntes`** (con su `id_creado`, `descartados` y la traducción del `local-…`) en la
  misma transacción que el cierre: la idempotencia sobrevive a los 30 días de `expira_at` de la bandeja.

### Quién y qué se comprueba al entregar

En este orden (`revision_entrega.go`): solo el token de **entrega** → tasa (60 peticiones/min por persona, en memoria) →
el aparato **existe** y es **de esta persona y de esta sucursal** (la subida normal no compara `aparato.Persona`; aquí es
obligatorio) → cada apunte **entero** antes de guardar ninguno → idempotencia → **cupos** de lo vivo. Límites, todos con
una frase que dice qué hacer:

| Límite | Valor |
|---|---|
| Método y ruta | `POST/PUT/PATCH/DELETE` sobre las ocho rutas de escritura que la API tiene de rutas y tablero, **por forma** (`/routes`, `/routes/{id}`, `…/stops/{pedido}`, `…/results`, `/board/columns`, `/board/columns/{id}`, `…/route`, `/board/placements/{pedido}`; `{id}` sin puntos; `POST /board` suelto da 422; ni `..` ni `//` ni `%`; ≤300 caracteres). **Es la defensa contra la autoridad prestada** y se vuelve a pasar al aplicar |
| Un apunte | `cuerpo` ≤128 KiB y JSON válido; petición ≤512 KiB; ≤25 apuntes por petición (la app manda 1) |
| Hora del aparato | `hecho` ≤ ahora+24 h y ≥ ahora−60 días |
| `provisional` | Opcional: `local-` y de 1 a 94 letras o números, o un UUID (el id definitivo que pone el aparato al crear una zona del Tablero). La subida normal no valida su forma, solo traduce los `local-…` |
| Lo vivo | ≤500 apuntes y ≤8 MiB de cuerpos **por persona**; ≤3.000 **por sucursal** (`429 cupo_de_revision`) |
| La bandeja | 500 entregas por lista del revisor y 1.000 apuntes en `mias`, con `truncado` si se alcanzó |
| Nombre del aparato | `POST /sync/aparato` lo limpia y lo recorta a **80** letras; `00004_nombre_de_aparato_acotado.sql` recorta a 200 los nombres que ya hubiera y pone `CHECK (char_length(nombre) <= 200) NOT VALID` debajo; la bandeja del revisor lo recorta a 200 al leerlo |

Contar el cupo y escribir son una sola cosa: la sucursal se bloquea (`pg_advisory_xact_lock`) hasta el fin de la transacción.

### **El `Aplicador` no se llama NUNCA en la entrega**

Entregar no es aplicar: el payload de alguien **sin permiso** nunca se ejecuta con la autoridad de nadie al entregarlo.
`entregar` ni siquiera toca `s.aplicador`, y la prueba lo cuenta (`revision_entrega_test.go`: el doble del reparto tiene
que acabar con **cero llamadas**, entregue lo que entregue). Solo **aplicar**, que hace una persona, llama al reparto (y antes mira el libro `apuntes`: si la subida normal ya había aplicado esa clave la cierra como `aplicado` sin reenviar, y si la había rechazado la deja `rechazado`; lo que aplica lo copia al libro con `ON CONFLICT DO NOTHING`), y
lo hace con **el token del REVISOR** —nunca uno de servicio— por la misma tubería que la subida normal (`reenviar`),
con `X-Sucursal-Id` forzada a la sucursal del apunte y `X-Autor`/`X-Revision` para el rastro de la API.

### Cerrar sesión en el navegador también corta la bandeja web

El revisor de la web llama a `sync` con el token de la cookie (siete días, `web:true`) como Bearer. Hasta la tanda final de S2 `sync`
solo conocía el corte `todo`: tras un cierre de sesión SOLO del navegador ese Bearer seguía aplicando y descartando. Ahora `sync`
guarda dos mapas (`web`, `todo`), recoge las dos familias de marcas de Redis (también al recargar) y a un token `web:true` le aplica
`max(web, todo)`; resultado: **401 en `/sync/*`**, igual que la API. La APK y el escritorio siguen con solo `todo`.

### Aviso en vivo para quien entregó — `GET /sync/revision/eventos` (10/10/2026)

Hasta aquí la persona se enteraba de qué había decidido el revisor pulsando «Actualizar estados» (o en el ciclo). Jose pidió
aviso en vivo y por SSE —«nada de polling, para eso tenemos SSE»— **para la persona** (el revisor sigue pulsando «Actualizar»).
Es una ruta más de las que abre el token de entrega, aparte de `entrega` y `mias`, y **solo ése** (el normal de la APK no):

```
GET /sync/revision/eventos?aparato=<uuid>      Authorization: Bearer <token de entrega>
200 text/event-stream; charset=utf-8 · Cache-Control: no-cache, no-transform · X-Accel-Buffering: no  (y NUNCA Connection: keep-alive)
: abierto\n\n                                  (nada más entrar)
event: revision\ndata: {"v":1}\n\n             (una decisión cambió un apunte de ESTA persona)
: ka\n\n                                       (cada 25 s)
```

* **El aviso es una señal vacía**: no lleva clave, estado ni motivo. La app, al recibirla, consulta `mias`, que sí pasa por el
  alcance y la comprobación del aparato; así no se filtra nada por un flujo largo.
* **Quién y cuándo** (`revision_aplicar.go`, `aplicarDeRevision`; `revision_revisor.go`, `descartarApunte`): después de CONFIRMAR
  —nunca dentro de una transacción— un apunte `aplicado`, `rechazado` al aplicar o `descartado`, a la **dueña de la entrega** (no a
  quien decide). Un 5xx del reparto, que devuelve el apunte a `en_revision`, no avisa. El aviso es un extra: sin suscriptores no hace
  nada y un fallo suyo no toca la respuesta al revisor.
* **Se cierra solo** cuando caduca el token de entrega (`Identidad.Caduca`, su `exp`; la app reconecta con otro), cuando el cliente se
  va o cuando el servicio se apaga (`CerrarAvisos` registrado con `Server.RegisterOnShutdown`: un SSE no queda inactivo nunca y
  `Shutdown` lo esperaría hasta el plazo de 30 s).
* **El concentrador** (`avisos.go`): suscripciones por persona en memoria, canal de búfer 1 y envío no bloqueante (**señal, no
  cola**: «aplicar todo en orden» son N avisos y, para quien mira, una actualización), alta y baja con `sync.Mutex`. **Topes: 3
  canales por persona, 500 en total** —el que sobra, `429` con `Retry-After: 30`—. En lugar del limitador de 60/min de `mias`, que
  no sirve para un flujo largo.
* **`WriteTimeout`:** el servidor tiene 60 s de plazo de escritura (absoluto, desde que se leyó la petición) y este flujo lo supera por
  diseño; el manejador lo sustituye **en su petición y en ninguna otra** por un plazo que **se renueva antes de cada escritura**
  (`http.ResponseController.SetWriteDeadline(ahora + 60 s)`). No se quita del todo: un cliente que dejó de leer sin cerrar tumbaría la
  escritura a los 60 s en vez de retener el canal hasta el timeout de TCP. Para que llegue al escritor de verdad, `httpx.Registro`
  expone `Unwrap` en su espía (sin él, `Flush` y el plazo contestaban `ErrNotSupported`).
* **A quién se avisa sale de lo ya leído, sin consultas de más:** el descarte devuelve `e.persona` en la propia sentencia
  (`RETURNING`, `DescartarRevisionApunte`), y aplicar la tiene en la fila que ya cargó. Así el aviso no retiene la respuesta al revisor
  (`net/http` no vacía hasta que el manejador vuelve) ni depende del contexto de su petición: si cierra la pestaña justo tras
  confirmar, la persona recibe el aviso igual.
* **Límite de despliegue: memoria de UN proceso.** `reparto-sync` tiene una réplica. Con más habría que pasar el aviso por Redis
  (los `REDIS_*` ya están en `sync`): si no, el revisor que decide en la réplica A no avisa a quien escucha en la B. Hasta entonces el
  aviso es «mejor esfuerzo» y `mias` es la fuente de verdad. Tampoco corta un flujo ya abierto un cierre de sesión de Accesos: el token
  se verifica al abrir, y el flujo no lleva datos y muere con su `exp` (≤ 10 minutos).
* El contrato exacto, con todos sus códigos, en `contratos-api.md` §12.3.

### Quién revisa

**ADMINISTRADOR de esa sucursal, SUPER ADMIN y DESARROLLADOR, y nadie revisa lo suyo** (Jose, 08/10/2026). Por **nombre
de rol** (`identidad.RolDeRevisor`) y con token; el alcance y «no lo tuyo» los decide el SQL en la misma sentencia que
escribe. LOGISTICO entra a Reparto pero no revisa.

### Lo que hace la app

Cuando el aparato ve el 403 `sin_permiso_reparto` conserva la cola y la pantalla `/sin-permiso` (solo en APK y escritorio, y solo
con algo que contar) ofrece **«Entregar a revisión»** con un toque (`docs/sin-permiso.md`). `EntregaARevision`
(`app/lib/nucleo/sincro/entrega_a_revision.dart`) pide el token a Accesos y manda **un apunte por petición, en orden**,
marcando `enRevision` solo con la respuesta en la mano; si el token (10 min) caduca a mitad pide otro **una vez**. Un fallo
de red lo deja todo `pendiente`, intacto. Después, el ciclo normal consulta `GET /sync/revision/mias` **solo si hay algo
`enRevision`**, entre subir y bajar, y un fallo de esa consulta no tumba la bajada. Un `enRevision` no sube ni cuenta en
«N sin subir» (ya está arriba), pero sí retiene el `completed` de su ruta y cuenta antes de olvidar a una persona. No hay
sondeo: el aviso en vivo lo da `GET /sync/revision/eventos` (arriba), y «Actualizar estados» sigue siendo la fuente de verdad.

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
   lo guardado por bueno**: la ruta se completa con lo guardado y sale un **cajón de acuse**
   (no un aviso que se va solo) que no se va hasta pulsar «Entendido»: «Ruta completada: N
   paradas no se guardaron» y, por cada una, «Conduce <número de operación>: <motivo
   literal del servidor>». Cerrarlo por la ✕, el velo, Escape o el atrás no cuenta y vuelve
   a salir. Si sólo se guardaba (sin completar), la hoja se queda abierta con las
   rechazadas aún marcadas. Si no se guardó **ninguna** parada, es rechazo total y no se
   completa. La ruta local puede figurar
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
