# La bandeja de revisión — qué pasa con la cola de quien pierde `delivery.entrar`

Diseño, 08/10/2026. **Actualización del 09/10/2026: está construido todo salvo la prueba de punta a
punta** (Accesos, `sync`, `api` y la app, pantalla `/sin-permiso` incluida); lo que de verdad se hizo, con sus ficheros y
**en qué se desvió de lo que sigue**, está en «Estado real (09/10/2026)» al final de este
documento. Lo de arriba es el diseño tal como se aprobó, escrito leyendo el código del 08/10;
cada afirmación de la sección A lleva su fichero y su línea para poder comprobarla.

Jose, dueño: «esto de cerrar los datos no sé si se le revoca los datos que se suban, pero que
pasen por un chequeo; así los tenemos, y si mando cosas mal se quitan manual y si no, pues
entran correctamente. Eso es en caso de que a alguien se le quite el rol y ya no pueda subir
sus cosas al sistema: no que se suban, se conserven. Pero ya él no tiene permisos en la
aplicación (APK y escritorio) y esto hay que manejarlo: no está hecho para cuando no tienes
permisos en Reparto.»

## En ocho líneas

1. Hoy la cola de quien pierde el rol **se conserva** en el aparato, pero **no puede subir
   nunca** mientras no recupere el rol: no hay token con el que hacerlo y nadie más la ve.
2. Se añade un camino de **solo entrega**: Accesos da, a quien conserva sesión viva pero no
   tiene `delivery.entrar`, un token de **10 minutos y un solo ámbito** («entrega a revisión»).
   Con él el aparato deja cada apunte en una tabla nueva de `sync/`. **No toca datos del
   negocio.**
3. Un apunte entregado queda **tal como vino** (byte a byte, con su huella) y **no se aplica
   jamás solo**. Lo decide una persona: **Aplicar** o **Descartar**.
4. **Aplicar** reenvía el apunte al reparto por la misma tubería y con las mismas validaciones de
   cualquier subida; si el reparto dice que no, el apunte queda **rechazado con el motivo
   literal** y sigue esperando decisión. **Descartar** exige motivo, lo escribe con nombre y
   hora, y no borra nada.
5. Revisan, por defecto, los que ya entran a Reparto con alcance sobre esa sucursal:
   ADMINISTRADOR de esa sucursal, SUPER ADMIN y DESARROLLADOR. **Es un DEFAULT a confirmar por
   Jose** (pregunta 1).
6. La persona, en la pantalla de «no tienes permiso», ve su trabajo («7 cambios sin enviar»),
   pulsa **Entregar a revisión**, y después ve «En revisión», «Aplicado por …» o «Descartado
   por …: motivo». Nada de eso aparece en la web (la web no tiene cola).
7. Quien está **de baja, con la sesión revocada, o cerró sesión** no puede entregar nada: Accesos
   lo comprueba antes de firmar el token (y hoy **no lo comprueba a tiempo**, ver A.4).
8. Trabajo repartido en 10 paquetes (sección C); dependen de Accesos o lo tocan A1 (es suyo),
   V, S1 y N2.

---

# A. Estado actual, comprobado en el código

## A.1 Qué pasa hoy, paso a paso (APK y escritorio)

| Paso | Qué ocurre | Dónde |
|---|---|---|
| 1 | Se quita `delivery.entrar` en Accesos. El aparato **no se entera**: sigue `dentro`, sigue encolando. El access token que lleva (≤15 min) sigue firmado con `entradas` que SÍ incluyen la llave. | `portero.dart:63` (`haySesionParaSincronizar`), `apk-tokens.ts:59` |
| 2 | Llega el siguiente ciclo (gesto, reconexión o reloj: **5 min en APK/escritorio, 2 en web**). **El ciclo empieza SIEMPRE por renovar**, aunque el access token viejo aún valga. | `ciclo.dart:341-356`, `vigia.dart:141,175` |
| 3 | `POST /api/auth/refresh` contesta `403 {"error":"sin_permiso","codigo":"sin_permiso"}`. **No gasta el refresh** y no cierra nada. | `refresh/route.ts:99-100`, `apk-tokens.ts:467-469`, `puerta-de-entrada.ts:136-140` |
| 4 | El `Renovador` avisa al portero y lanza un `Rechazo` con marca; no es `SesionMuerta`, no se borra nada. El ciclo **aborta antes de subir**. | `renovador.dart:99-113`, `ciclo.dart:438-450` |
| 5 | Portero → `EstadoDeAcceso.sinPermiso`, pantalla `/sin-permiso`. Ciclo y vigía paran (`haySesionParaSincronizar` es falso). Base, cola y sesión intactas. | `portero.dart:199-202`, `portero.dart:63`, `ciclo.dart:257-260` |
| 6 | Mismo desenlace si el 403 lo ve cualquier otra petición (interceptor) o el arranque. | `interceptor_sesion.dart:83`, `arranque.dart:168-181` |
| 7 | Si alguien llegara a mandar la subida con un token viejo, `sync` contesta `403 sin_permiso_reparto` **sin anotar nada**; la cola queda `pendiente`. Un 403 dentro de un 200 tampoco resuelve el apunte. | `subida.go:103-114`, `reparto.go:277-286`, `subida.dart:303-319` |
| 8 | «Cerrar sesión» en esa pantalla pregunta si hay cola y dice que **no la borra**. Pero revoca el refresh en Accesos (cierra la familia; sin red queda apuntado y se revoca al volver, `RevocadorDeCierres`): **desde ese momento ya no habrá token nunca** hasta que la persona vuelva a tener el rol y a entrar. | `pantalla_sin_permiso.dart:86-117`, `portero.dart:328-345`, `apk-tokens.ts:735-753` |
| 9 | De `sinPermiso` no se sale solo, ni siquiera si devuelven el rol: hay que cerrar sesión y entrar de nuevo. Al entrar, la cola sube completa con su token. | `portero.dart:504-519`, `docs/sin-permiso.md` («De dónde se sale») |

## A.2 Las ventanas de tiempo

* **Hasta el primer ciclo con red tras quitar el rol (≤5 min con red; si estaba sin señal, hasta
  que vuelva):** el aparato sigue trabajando y encolando. Nada falla.
* **Desde el primer ciclo:** no sube nada. La ventana del «token anterior aún vigente» es, **en la
  práctica, cero**: el access token viejo sigue valiendo ≤15 min (+1 de margen en `sync`,
  `token.go:203,256`), pero el ciclo renueva primero y aborta en el 403 (A.1 pasos 2-4). Y si
  lo usara alguien a mano, ese token **sí permite APLICAR**, o sea no es una revisión sino el
  agujero de «el access token no se revoca».
* **Mientras el refresh viva:** la persona conserva sesión en Accesos y refresh sin gastar,
  **hasta 30 días desde su última renovación** (`apk-tokens.ts:61`; el 403 no lo renueva ni lo
  gasta). Es el plazo útil para entregar.
* **Al cerrar sesión, al caducar el refresh o al darla de baja:** no hay token posible. La cola
  sigue en el fichero de esa persona (`conexion/nombre.dart`) pero **varada**.
* **Cuando devuelven el rol:** todo sube normal tras cerrar sesión y entrar.

## A.3 Por plataforma

| | Qué pasa con su trabajo |
|---|---|
| **APK / escritorio** | Es el caso de arriba. Cola y base locales intactas, **sin vía de salida** salvo recuperar el rol. El panel de `/sincronizacion` ni siquiera lo sabe: `Exigir` rechaza antes del manejador, así que no se toca `visto_at` ni `pendientes` (`identidad.go:152-157`, `main.go:89`); solo se nota por «horas sin subir». |
| **Web** | **No hay cola ni base local** (CLAUDE.md §1). Los gestos van en vivo y se pintan solo si el servidor dice que sí (`escritura_en_vivo.dart:82-90`). Un gesto que llega con el rol ya quitado recibe el 403 literal («No tienes permiso para entrar a Reparto.»), no se pinta como hecho, y la pantalla se va sola a Accesos a los 3 s. **No hay nada que conservar.** Ojo: la cookie lleva `entradas` congeladas 7 días (`auth_web.go:88,406-412`); el rol quitado solo se nota al volver a entrar o si Accesos avisa por el canal de sesión (no comprobado aquí que lo publique en un cambio de rol). |

## A.4 Cosas de Accesos que condicionan el diseño (comprobadas)

1. **El 403 de `/refresh` no prueba que la sesión viva.** En `renovar`, la llave se comprueba
   (`apk-tokens.ts:469`) **antes** de mirar si la sesión de better-auth está revocada
   (`apk-tokens.ts:638-647`, dentro de `emitirDesde`). Y revocar desde el panel o al cambiar la
   contraseña solo marca `session.revokedAt`, **no** las filas de `refresh_token`
   (`(user)/dashboard/_actions.ts:476-486`, `revoke-session/route.ts`). Resultado: una persona sin
   llave **y con la sesión revocada** recibe 403 `sin_permiso`, no 401. Si el token de entrega
   se firmara «porque el refresh devolvió 403», **una sesión revocada podría entregar**. El
   endpoint nuevo tiene que mirar sesión, `activo` y refresh por su cuenta.
2. **Baja:** `comprobarEntrada` deja pasar a la cuenta de baja (`puerta-de-entrada.ts:166`) y la
   cierra `resolverIdentidad` con `revoked` (`apk-tokens.ts:249`) → 401 y familia cerrada. Eso
   ya es correcto; el endpoint nuevo debe heredarlo.
3. **Ni la API ni `sync` miran `purpose`/`scope` del token** (búsqueda en `api/internal/auth` y
   `sync/internal/identidad`: cero apariciones). Verifican HS256 con el mismo `JWT_SECRET`, `exp`
   y `entradas`. Un token de ámbito restringido solo es seguro hoy porque `entradas` PRESENTE
   (aunque `[]`) falla cerrado (`token.go:374-387`). Hay que dejar eso **atado con una prueba** y
   añadir un rechazo explícito del ámbito en las rutas normales.
4. **`sync` no compara `aparato.Persona` con quien llama**: `aparatoDeLaPeticion` solo exige
   `quien.Ve(aparato.BranchID)` (`bajada.go:219-251`; ningún otro uso de `.Persona` lo compara).
   Hoy otro de la misma sucursal con un aparato conocido podría bajar/subir por él. En la
   entrega esa comparación **es obligatoria**.
5. **La web no puede hablar con `/sync`**: `DeToken` solo lee `Authorization: Bearer`
   (`token.go:100-110`), sin cookie; por eso `/sincronizacion` es solo de APK/escritorio
   (`pantallas/sincronizacion/registro.dart`). Pero `GET /api/me` ya devuelve el token de la
   cookie en el cuerpo (`contratos-api.md` §5, `entrada_por_accesos.dart:96-104`), así que la
   web puede llamar a `sync` con **Bearer explícito**, sin cookie, sin CSRF.
6. **La API no tiene columnas de autoría** (`created_by` y similares: ninguna) y **no lee
   `X-Apunte`** (solo lo escribe `reparto.go:216`). La autoría de lo hecho vive únicamente en el
   registro `actor` (`rastro_de_quien.go:33`). «Aplicar con la autoría original» solo puede
   significar: hora original (`X-Hecho-At`, que sí se lee, `rutas.go:473-483`) + autor original
   en el registro y en la tabla de revisión.

---

# B. Diseño recomendado

## B.0 Principios (salen de CLAUDE.md §4 y de lo que dijo Jose)

* **Conservar no es aplicar.** Entregar a revisión nunca modifica pedidos, rutas ni tablero.
* **Nada se descarta en silencio; una decisión de una persona se ESCRIBE.** Ni un `DELETE` ni un
  `UPDATE` que pierda el original. Las decisiones se añaden, no se reescriben.
* **Solo el caso «sesión viva, sin llave».** Baja, sesión revocada, refresh caducado o cerrado:
  no entrega nada.
* **La autoridad no se presta.** Aplicar se hace con el token del **revisor**, nunca con uno de
  servicio, y acotado a la sucursal del aparato.
* **La web no cambia** (sin cola, sin entrega). Solo tiene, si Jose lo confirma, la bandeja del
  revisor (B.6).

## B.1 (i) Cómo entrega alguien con sesión válida pero sin `delivery.entrar`

| Opción | Pros | Contras de seguridad | Veredicto |
|---|---|---|---|
| **1. Token restringido de Accesos**, ámbito «solo-entrega-a-revisión», endpoint nuevo `POST /api/auth/entrega` | Accesos sigue siendo la única autoridad sobre sesión/baja/llave. El token solo abre una puerta que **solo escribe en cuarentena**: aunque lo roben, solo se puede dejar basura en revisión, con cupos. TTL corto. El refresh no sale del aparato. Misma regla de Jose: «quién entra lo decide Auth». | Un endpoint más en Accesos (superficie, límites de tasa). Se firma con el mismo `JWT_SECRET`, así que los verificadores Go deben aprender a rechazar el ámbito (A.4.3). Hay que ordenar el despliegue (Accesos primero). | **ELEGIDA** |
| 2. «Token anterior aún vigente» | Cero código. | Ventana ≤16 min que el propio ciclo no usa (A.2). **Aplica de verdad**, sin revisión: es el agujero de revocación, no un remedio. No cubre el caso real (aparato sin señal horas o días). | Descartada |
| 3. `sync` acepta el refresh (o un access caducado) y le pregunta a Accesos | No hay token nuevo. | Pasa el secreto de 30 días a otro servicio, o acepta tokens caducados; `sync` depende de Accesos en cada entrega; mezcla `exp`, que hoy es obligatorio. | Descartada |
| 4. Re-login con contraseña que devuelva token de entrega en el 403 de `/token` | Cubre «cerró sesión». | La copia de la persona se abre por `sub` y en el 403 no se conoce; hay que dejar la contraseña viajar a un flujo más. | **Futuro** (D) |
| 5. Sacarlo por fuera (fichero, correo) | Sin red. | Sin identidad ni idempotencia ni límites. | Descartada |

### El contrato de Accesos (paquete A1)

`POST /api/auth/entrega` — cuerpo `{ "refresh_token": "…" }` (alias `refresh`, como `/refresh`).
**No gasta el refresh y no devuelve refresh.** Comprueba, en este orden y sin firmar nada hasta
el final:

1. límite de tasa por IP y por huella del refresh (no abrir si Redis no contesta: aquí sí se
   cierra, es una puerta nueva);
2. la fila del refresh existe, no está caducada, no está revocada y **no está gastada** (solo la
   cabeza de la cadena que tiene el aparato; un refresh ya gastado = 401 **sin** revocar la
   cuenta, no es esta puerta quien castiga robos);
3. **la sesión de better-auth existe, no está revocada y no ha caducado** (`session.revokedAt`);
4. la persona existe y está `activo` (baja → 401);
5. `resolverIdentidad` no lanza (`sin_sucursal` → 403 con su texto; es una persona sin alcance a
   la que no se le firma nada);
6. **la persona NO tiene `delivery.entrar`** (`accesoDe`/`comprobarEntrada`); si la tiene, no se
   firma: **409 `{"error":"tiene_permiso","codigo":"tiene_permiso"}`** («renueva con /refresh»).
   Esto evita que quien SÍ tiene permiso use la revisión para que otro aplique sus gestos con
   más autoridad.

Respuestas: `200 { token, token_type:"Bearer", expires_in:600, ambito:"reparto.entrega" }`;
`401 {error:"invalid_refresh"}` (todo fallo 2-4, mismo cuerpo, como `/refresh`);
`403 sin_sucursal`; `409 tiene_permiso`; `429`; `503 comprobacion_no_disponible` (la app
conserva todo y reintenta, nunca lo toma por «sin permiso»).

**Claims del token** (HS256, `JWT_SECRET`, `purpose:"apk:entrega"`): `sub`, `name`, `email`,
`sid`, `sucursal` y `branch_id` (el código, como el normal), `ambito:"reparto.entrega"`,
`entradas:[]`, `roles:[]`, `role:""`, `jti`, `iat`, `exp` = 600 s. Sin roles a propósito: nada
que un verificador pueda tomar por un permiso. `name` se incluye para que la bandeja diga
«Yasmani» y no un uuid, sacado del token verificado y no del cuerpo.

Auditoría en Accesos: `auth.apk.entrega` (userId, sessionId, IP, agente) y
`auth.apk.entrega_denegada` (con el motivo interno: `sesion_revocada`, `baja`, `refresh_gastado`,
`tiene_permiso`…). Sin el token ni el refresh.

**Endurecimiento que va en el mismo paquete** (`renovar` en `apk-tokens.ts`): mirar la sesión
revocada y la baja **antes** de la llave, para que el 403 `sin_permiso` de `/refresh` signifique
de verdad «sesión viva, sin llave». Efecto: una sesión revocada sin llave pasa de 403 a 401 y la
app va a `fuera`, que es lo correcto.

### Lo que `sync` y la API verifican del token de entrega (paquete V)

* **`sync`**, función nueva `DeTokenDeEntrega`: firma, `exp` obligatorio, `purpose` y `ambito`
  exactos, `sub` presente, `entradas` **sin** `delivery.entrar` (si la trae, no es un token de
  entrega: 401), sucursal resoluble.
* **Rutas normales (`api/internal/auth` y `sync/internal/identidad`)**: todo token que traiga
  `ambito` se rechaza, también si alguien consiguiera meterle `entradas` con la llave. Ata
  `docs/ambito-de-entrega.casos.json` (nuevo, leído por las pruebas de los dos módulos, como
  `roles-de-reparto.casos.json`).
* El token de entrega solo abre **dos** rutas de `sync` (B.2). Cualquier otra → 403
  `sin_permiso_reparto`, que ya es lo que pasa hoy con `entradas:[]`.

## B.2 (ii) Servidor (`sync/`): la tabla de revisión

La bandeja vive en `sync/` junto al registro de aparatos, porque es contabilidad de la
sincronización («lo que llegó y quién decidió»), no un dato del negocio. Los datos del reparto
siguen siendo de `api/`.

### Esquema (esbozo de `sync/db/migrations/00003_la_bandeja_de_revision.sql`, goose)

```sql
-- +goose Up
CREATE TYPE revision_estado AS ENUM
  ('en_revision', 'aplicando', 'aplicado', 'rechazado', 'descartado');

-- Una fila por ENTREGA (una pulsación del botón). Agrupa y da el contexto.
CREATE TABLE revision_entregas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aparato_id     uuid NOT NULL REFERENCES aparatos(id) ON DELETE RESTRICT,
  persona        text NOT NULL,            -- sub verificado del token
  persona_nombre text,                     -- claim `name`, no el cuerpo
  branch_id      uuid NOT NULL,            -- del aparato, y == sucursal del token
  token_jti      text NOT NULL,            -- qué token entregó (nunca el token)
  desde_ip       text, agente text,        -- recortados; sin cabecera Authorization
  version_app    text,
  entregada_at   timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);

-- Una fila por APUNTE. PK = idempotencia por id de apunte, igual que `apuntes`.
CREATE TABLE revision_apuntes (
  aparato_id   uuid NOT NULL REFERENCES aparatos(id) ON DELETE RESTRICT,
  clave        text NOT NULL,                       -- el ULID del aparato
  entrega_id   uuid NOT NULL REFERENCES revision_entregas(id) ON DELETE RESTRICT,
  orden        integer NOT NULL,                    -- posición FIFO en la cola del aparato
  metodo       text NOT NULL, ruta text NOT NULL,
  cuerpo       text,                                -- TAL CUAL llegó (bytes del JSON), nunca re-serializado
  provisional  text,
  hecho_at     timestamptz NOT NULL,                -- la hora del APARATO
  huella       text NOT NULL,                       -- sha256 hex de aparato|clave|metodo|ruta|cuerpo|hecho
  resumen_del_aparato text,                         -- ayuda de lectura, no vale como dato (<=200)
  estado       revision_estado NOT NULL DEFAULT 'en_revision',
  decidido_por text, decidido_por_nombre text, decidido_at timestamptz,
  motivo       text,                                -- descartar: el de quien decide; rechazado: el LITERAL del reparto
  id_creado    uuid, descartados jsonb,             -- igual que `apuntes`
  intentos     integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (aparato_id, clave),
  CHECK (estado <> 'descartado' OR (decidido_por IS NOT NULL AND decidido_at IS NOT NULL
                                    AND length(btrim(motivo)) >= 5)),
  CHECK (estado <> 'aplicado'  OR (decidido_por IS NOT NULL AND decidido_at IS NOT NULL))
);
CREATE INDEX revision_pendientes_idx ON revision_apuntes (entrega_id, orden)
  WHERE estado IN ('en_revision','aplicando','rechazado');

-- El libro de decisiones: SOLO se añade. Cada intento de aplicar y cada descarte.
CREATE TABLE revision_decisiones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aparato_id uuid NOT NULL, clave text NOT NULL,
  accion text NOT NULL CHECK (accion IN ('aplicar','descartar')),
  por text NOT NULL, por_nombre text, rol text,
  resultado text NOT NULL,            -- aplicado | rechazado | descartado | interrumpido
  http_estado integer, motivo text,
  cuando timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (aparato_id, clave) REFERENCES revision_apuntes (aparato_id, clave)
);
-- Triggers: revision_apuntes no permite UPDATE de metodo/ruta/cuerpo/hecho_at/huella/entrega_id/orden
-- ni ningún DELETE; revision_decisiones no permite UPDATE ni DELETE.
-- +goose Down  (DROP de las tres y del tipo)
```

Consultas nuevas en un fichero propio, `sync/db/queries/revision.sql` (sqlc lee la carpeta):
alta de entrega, inserción de apunte con `ON CONFLICT (aparato_id, clave) DO NOTHING
RETURNING`, lectura por clave, cupos (contar y sumar bytes de lo vivo por persona y por
sucursal), lista de revisor **con el alcance de sucursal dentro del SQL**
(`sqlc.narg('sucursal')::uuid IS NULL OR …`, convención de la casa), pasar a `aplicando`
condicionado (`WHERE estado IN ('en_revision','rechazado')`, devuelve fila o no), cerrar como
`aplicado`/`rechazado`/`descartado`, y anotar en `revision_decisiones`. Código generado con
`~/go/bin/sqlc generate`, **no a mano**; `sqlc diff` tiene que salir limpio.

### Idempotencia por id de apunte

* `(aparato_id, clave)` es la primaria. Reentregar la misma clave con **el mismo contenido** →
  `repetido`, con el estado actual (`en_revision`, `aplicado`…). Con **otro contenido** (la
  huella no cuadra) → `409 huella_distinta`, **no se sobrescribe nada** y queda en el registro:
  o es un fallo de la app o es alguien manipulando.
* `unApunte` (la subida normal) pregunta primero a `revision_apuntes`: si la clave está ahí
  contesta lo que corresponde **sin aplicar**: `aplicado` → `repetido` (el libro `apuntes` ya
  lo tendrá), `descartado` y `rechazado` → `repetido` **con motivo** (la app ya lo lee como «no
  subió», `apunte.dart:83-85`), `en_revision`/`aplicando` → estado nuevo `en_revision`.
* Cuando un apunte se aplica por revisión se anota **también** en el libro `apuntes` (con su
  `id_creado`, `descartados` y la traducción del `local-…` en `ids_provisionales`), así que
  la idempotencia sobrevive a los 30 días de `expira_at`, y la persona, si recupera el rol y
  reenvía, recibe `repetido`.

### Qué se guarda

Quién (persona + nombre del token + aparato), cuándo llegó (`entregada_at`) y cuándo lo hizo el
aparato (`hecho_at`), sucursal, el original **byte a byte**, su huella, y después quién decidió,
cuándo y con qué resultado. No se guarda el token, ni el refresh, ni cabeceras de autorización.

### Límites (todos con un literal que dice qué hacer)

| Límite | Valor propuesto | Por qué |
|---|---|---|
| Lista blanca de método + ruta | `POST/PUT/PATCH/DELETE` sobre `^/(routes|board)(/…)?(\?…)?$`, sin `..`, sin `//`, ≤300 caracteres | La cola solo emite `/routes…` y `/board…` (`acciones_rutas.dart`, `tablero/datos/repositorio.dart`). Es **la defensa contra la autoridad prestada** (B.2 «Aplicar»). Se vuelve a comprobar al aplicar. |
| Tamaño de un apunte | `cuerpo` ≤128 KiB y JSON válido; petición ≤512 KiB; ≤25 apuntes por petición (la app manda 1) | Una jornada son ~12 apuntes de pocos KB (`subida.dart`). |
| Número vivo | ≤500 apuntes vivos y ≤8 MiB de cuerpos vivos **por persona**; ≤3.000 por sucursal | «Vivo» = `en_revision`, `aplicando`, `rechazado`. Exceder → `429 {"codigo":"cupo_de_revision"}`. |
| Tasa | ≤60 peticiones/min por persona en `sync`; en Accesos 6 tokens/hora por sesión y 20/hora por IP | Contra quien gira el botón. |
| Hora plausible | `hecho` ≤ ahora+24 h y ≥ ahora−60 días | Un reloj roto no mete el año 1970. |
| Quién | `aparato.Persona == sub` y `aparato.BranchID ==` sucursal resuelta del token; el aparato tiene que existir (nunca se da de alta en modo entrega) | A.4.4. |
| Cuál token | **solo** el de ámbito entrega; un token normal se rechaza con 409 | B.1 punto 6. |

### Endpoints de `sync`

* Con token de **entrega**: `POST /sync/revision/entrega`, `GET /sync/revision/mias?aparato=…`
  (esta acepta también un token normal de la misma persona) y `GET /sync/revision/eventos?aparato=…` (el aviso en vivo, SSE;
  solo el de entrega, ver punto 8).
* Con token **normal** de revisor: `GET /sync/revision` (lista, acotada por alcance),
  `GET /sync/revision/{entrega}` (detalle), `POST /sync/revision/{aparato}/{clave}/aplicar`,
  `POST /sync/revision/{entrega}/aplicar` (en orden), `POST /sync/revision/{aparato}/{clave}/descartar`.
* `GET /sync/estado` suma `en_revision` por sucursal (el segundo «número rojo»).
* En `main.go` las dos primeras van detrás de `Exigir(fuenteEntrega, …)` y el resto detrás del
  `Exigir` actual; `ServeMux` elige el patrón más específico.

### «Aplicar»: lo que pasa y lo que NO puede pasar

1. Reclamar la fila con un `UPDATE … WHERE estado IN ('en_revision','rechazado') RETURNING`
   y pasarla a `aplicando` (candado de verdad: dos revisores, un solo ganador; el otro recibe
   409 «ya lo está aplicando X»).
2. Volver a validar: revisor ≠ autor, el revisor ve esa sucursal, método y ruta en la lista
   blanca. Traducir los `local-…` con el mismo traductor de la subida.
3. Reenviar al reparto por **el mismo `Aplicador`** que la subida normal, con
   **`Authorization` = token del REVISOR** (la persona del apunte ya no tiene permiso), más:
   `X-Hecho-At` = hora original, **`X-Sucursal-Id` = sucursal del aparato** (para un SUPER ADMIN o
   DESARROLLADOR sin sucursal en el token, la API solo lee esa cabecera para ellos, con lo que la
   acción queda acotada a esa sucursal aunque quien revisa vea las ocho), y las dos cabeceras
   nuevas **`X-Autor`** (el `sub` original) y **`X-Revision`** (id de la entrega). La API **no las
   usa para autorizar**: solo las añade a la línea de registro (`actor`=revisor, `autor`=original,
   `revision`=id).
4. 2xx → `aplicado` + libro `apuntes` + provisionales + `decisiones`, en una transacción.
   4xx → `rechazado` con **`motivoDe` literal**, sigue vivo y a la vista; **no se reintenta
   solo**. 5xx o red → vuelve a `en_revision` con `intentos+1` (caída, no rechazo, igual que en
   `reparto.go:287-290`). Si el proceso muere con la fila en `aplicando`, el revisor la ve como
   **«interrumpido: comprueba a mano la ruta antes de reintentar»** y reintentar exige confirmar:
   la API no lee `X-Apunte`, así que no hay otra red.
5. **Lo que NO puede pasar:** que el payload de alguien sin permiso se ejecute con la autoridad
   del revisor sobre algo que el autor jamás podría tocar. Por eso: lista blanca, `X-Sucursal-Id`
   forzada, el revisor ve el método, la ruta y el cuerpo exactos antes de pulsar, y no puede
   editarlos.

## B.3 (iii) Quién revisa — DEFAULT a confirmar por Jose

Por defecto: **ADMINISTRADOR de esa sucursal, SUPER ADMIN y DESARROLLADOR**, o sea quien ya
entra a Reparto con alcance sobre la sucursal del aparato (`quien.Ve(branch)`, `Alcance()`).
Exclusiones: LOGISTICO (entra a Reparto pero no revisa lo de otro logístico), y **nadie revisa
lo suyo** (`decidido_por ≠ persona`, comprobado en servidor).

Ojo con el principio del 08/10/2026: «quién entra a Reparto lo decide Auth». Decidir «quién
revisa» por NOMBRE de rol dentro de Reparto es justo lo que Jose quitó para entrar. La
alternativa limpia es una llave nueva de Accesos (`delivery.revisar`) firmada en el token. Cuesta
un paquete más en Accesos (catálogo de permisos + claim). Recomendación: **empezar con el
default por rol** y dejar la llave para cuando haya más de tres revisores (pregunta 1).

## B.4 (iv) Acciones del revisor

* **Aplicar** (uno, o «Aplicar todo en orden» de una entrega). En orden FIFO; un rechazo **no
  detiene** al resto (igual que `aplicarLote`), pero lo que dependía de un `local-…` que no
  llegó sale rechazado con el motivo ya existente («El identificador provisional … todavía no
  corresponde a nada»). Sigue el orden de B.2.
* **Descartar**: exige un **motivo escrito (≥5 caracteres)**, lo guarda con quién y cuándo en el
  apunte y en `revision_decisiones`. El apunte **se queda** (`descartado`); la persona lo ve.
* Un apunte `rechazado` por el reparto al aplicar queda pidiendo decisión: el revisor puede
  **Reintentar** (otra fila en el libro) o **Descartar**. Igual que la bandeja de hoy
  (`cola_salida.dart:342-421`), pero con dueño y motivo.
* No hay «editar el cuerpo» ni «aplicar parcialmente». Si algo está mal, se descarta con motivo
  y la persona rehace el gesto con permiso.

## B.5 (v) Lo que ve la persona en el aparato (APK y escritorio)

### Estados en el aparato

`EstadoApunte` hoy: `pendiente, aplicado, rechazado, descartado` (`tablas/aparato.dart:29`). Se
añaden **dos**: `enRevision` y `descartadoPorRevisor`. Hacen falta columnas nuevas en `apuntes`
(esquema Drift 6 → 7): `revision` (id de la entrega), `revisadoPor`, `revisadoAt` y
**`motivoRevision`**. **No se reutiliza `motivo`**: en un `aplicado`, `motivo` ya significa
«salió con menos de lo que pusiste» (`cola_salida.dart:73-91`), y ponerle ahí «Aplicado por …»
inundaría ese aviso.

| Estado local | Qué lee la persona (texto honesto) |
|---|---|
| `pendiente` (sin entregar) | «Sin entregar. Solo está en este aparato.» |
| `enRevision` | «Entregado a revisión el 8/10, 14:32. **Todavía no está aplicado**: un administrador de tu sucursal tiene que revisarlo.» |
| `aplicado` + `revisadoPor` | «Aplicado por Marta Pérez el 9/10, 9:10.» |
| `rechazado` (por el reparto al aplicar) | «No se pudo aplicar: *<motivo literal del reparto>*. Sigue en revisión.» |
| `descartadoPorRevisor` | «Descartado por Marta Pérez el 9/10: *<motivo escrito>*.» |

### Flujo y pantalla

* Es **un panel dentro de `/sin-permiso`**, no una ruta nueva: así `redirigir` y `Portero` no
  cambian (`portero.dart:552,594-597`) y volver «sin perder nada» es no haberse ido. Solo
  APK/escritorio (la web se va a Accesos a los 3 s, sin cola).
* Si hay cola (`cuantosPendientes() > 0`) se añade bajo el texto de siempre: «Tienes **7
  cambios sin enviar**. No se han perdido ni se han aplicado. Puedes entregarlos a revisión: un
  administrador de tu sucursal los mirará y decidirá si se aplican.» + botón **«Entregar a
  revisión»** (`BotonPrincipal`, con su icono propio, sin fondo) + «Cerrar sesión».
* **Entrega manual**, no automática (recomendación): son datos de una persona que ya no tiene
  permiso y puede haber sido un error del administrador; con un toque queda consentido, contado
  y reversible por el administrador que devuelve el rol (mientras no se pulse, la cola sigue
  intacta y subirá normal). Se recuerda en la pantalla cada vez que se abre.
* Secuencia: pedir token a Accesos con el refresh guardado → mandar **uno a uno, en orden**
  (`/sync/revision/entrega`, cada petición esperando la anterior, como `Subida.ciclo`) → marcar
  `enRevision` apunte por apunte según llega la respuesta → si el token (10 min) caduca a
  mitad, pedir otro **una vez**. Un fallo de red lo deja todo `pendiente`, intacto y
  reintentable. Un `409 huella_distinta` o un `422`/`429` se enseñan con su literal y el
  apunte sigue `pendiente`.
* Estados de la entrega: botón de «Actualizar estados» y consulta al abrir
  (`GET /sync/revision/mias`); sin sondeo automático (la conexión de allá se paga).
* **«Cerrar sesión» con cola** (hoy: «Salir NO los borra… suben cuando te den acceso»): pasa a
  tres opciones: **«Entregar a revisión y salir»**, **«Salir sin entregar»** (con el aviso
  «queda varado: solo subirá si te devuelven el rol y vuelves a entrar»), «Me quedo». Es la
  única forma de que cerrar sesión no deje la cola sin salida.
* Si más tarde devuelven el rol: se entra como siempre; los `pendiente` suben solos; los
  `enRevision` **no se reenvían** y el ciclo normal consulta su estado una vez por vuelta
  **solo si existe alguno**.
* Casos con mensaje literal propio: aparato sin alta (`404 aparato_no_registrado`: **no** se da de
  alta otra vez, no hay token para eso: «Este aparato no estaba registrado. Pide a un
  administrador que te devuelva el acceso.»), Accesos `409 tiene_permiso` («Ya tienes permiso:
  cierra sesión y entra de nuevo»), `401` de Accesos («Tu sesión terminó. No se puede entregar»;
  la cola queda en el aparato).

### Acoplamientos que NO se pueden olvidar (cada uno ya costó un incidente)

* `Huerfanos` decide qué filas locales están «vivas» con listas de estados escritas a mano en
  **tres** SQL (`huerfanos.dart:153` `('pendiente','rechazado')`, `:185` `'descartado'`,
  `:412` los tres). `enRevision` y `descartadoPorRevisor` tienen que entrar ahí o el ciclo
  reencolará como huérfano lo que ya está en revisión: es **exactamente el bucle del
  29/09/2026**.
* `nacio_aqui` (`cola_salida.dart:181-197`): `enRevision` **conserva** la protección (el trabajo
  solo existe en el aparato); `aplicado` y `descartadoPorRevisor` la sueltan, como `resolver` y
  `descartar` hacen hoy.
* `cuantosSinSubir()` (`base.dart:453`) cuenta `pendiente|rechazado`: no debe contar
  `enRevision` en «N sin subir» (ya está arriba), **pero** sí en las guardas de borrar/olvidar a
  una persona y en `_elAparatoTieneDatos` (`arranque.dart:219-223`, `personas.dart`): una cuenta
  con trabajo en revisión no se «olvida» sin avisar.
* `ResultadoApunte.deJson` lanza `FormatException` ante un estado desconocido
  (`apunte.dart:29-34`): la APK que entiende `en_revision` tiene que estar **antes** de que
  `sync` pueda contestarlo. En la práctica solo puede contestarlo a la instalación que entregó.

## B.6 (vi) La web

* **Sin cola, sin entrega, sin pantallas de aparato** (CLAUDE.md §1). Quien pierde el rol sigue
  yendo a Accesos a los 3 s; su último gesto salió rechazado con el literal del 403 y no se
  pintó. Nada que conservar.
* **Pregunta abierta (2):** la **bandeja del revisor** no es «el aparato de prepararse para no
  tener señal»: es un buzón de oficina, y por la prueba de la casa («¿sirve de algo a alguien
  que tiene internet ahora mismo?») **sí sirve en la web**. Pero hoy la web no puede llamar a
  `sync`. Recomendación: **sí, en la web también**, llamando a `sync` con **Bearer explícito
  sacado de `/api/me`** (el token ya se lo devuelve a la app web, `entrada_por_accesos.dart:96-104`),
  sin cookie ni CSRF. Cuesta una opción nueva en `ClienteApi` (`bearerExplicito`). Si Jose dice
  que no, la bandeja es solo de escritorio/APK y los administradores de oficina tendrían que
  usar el escritorio.

## B.7 (vii) Auditoría y avisos

* **Auditoría** (ya incluida en las tablas): quién entregó, quién decidió, cuándo, el resultado y
  el motivo literal; `revision_decisiones` es solo-añadir. En el registro de `sync`, una línea
  `Info` por entrega («persona, aparato, sucursal, n apuntes, entrega») y por decisión, **sin
  token** (misma regla que `rastro_de_quien.go`). En la API, `actor`/`autor`/`revision` en las
  líneas de «rastro de quién». En Accesos, `auth.apk.entrega` y `…_denegada`.
* **Aviso visible sin notify (fase 1):** número «en revisión» por sucursal en `/sync/estado` y en
  la cabecera del panel/menú del revisor, junto al «sin atender» que ya existe.
* **notify (fase 2, no bloquea):** un aviso HIGH por sucursal cuando haya entregas sin decidir
  más de 1 h, **uno por huella y día** (no uno por apunte: «un aviso que sale siempre deja de
  leerse»), y otro al pasar 7 días. Se manda con el mismo canal firmado que ya existe en la API
  (`api/internal/api/canal_notify.go`, `/v1/notifications`). `sync` no tiene cliente de notify
  ni emails; hay que copiarlo o pedir los destinatarios a notify por sucursal+rol (por decidir).
  Nunca se aplica ni se borra solo por antigüedad.

---

# C. Paquetes de trabajo

Reglas para repartir: (1) **cada paquete es dueño de sus ficheros**; ninguno edita los de otro;
(2) **ningún agente lanza `./comprobar.sh`** hasta que todos suelten el árbol (cada uno lanza lo
suyo: `go build && go vet && go test` en su módulo, `flutter analyze <carpeta>`,
`timeout 300 flutter test <fichero>`, `npx tsc`/vitest en Accesos); (3) **los ficheros de
`api/internal/auth` y `app/lib/nucleo/**` los están tocando otros agentes ahora mismo**: los
paquetes V, N1 y N2 no empiezan hasta que los sueltan; (4) sin `git add -A`; (5) cada mutación
se restaura y se barre el árbol (`grep -rn "if (false)\|if (true)\||| true)"`) antes de soltar.

Orden y dependencias: **A1 → V → S1 → S2**, **P** libre; app: **N1 → N2 → N3**, **N4** después de
S2. Despliegue: Accesos, V (api+sync), S1+S2, P, y la APK/escritorio al final.

| ID | Paquete | Depende de Accesos |
|---|---|---|
| A1 | Accesos: endpoint de entrega + endurecer la renovación | **Sí (es de Accesos)** |
| V | Verificadores Go: ámbito y token de entrega | Sí (contrato de claims de A1) |
| S1 | `sync`: datos + endpoint de entrega + límites | Sí (consume el token de A1/V) |
| S2 | `sync`: revisor (listar, aplicar, descartar) | No directamente |
| P | `api`: leer `X-Autor`/`X-Revision` solo para el registro | No |
| N1 | App: estados, columnas locales y acoplamientos | No |
| N2 | App: servicio de entrega y consulta de estados | **Sí** (llama a `/api/auth/entrega`) |
| N3 | App: pantalla `/sin-permiso` con la entrega y «Cerrar sesión» | Indirecto (por N2) |
| N4 | App: bandeja del revisor (APK, escritorio y, si se confirma, web) | No |
| D | Documentos y prueba de punta a punta | — |

## A1 — Accesos (repo `/mnt/datos/Work/procovar/auth`)

* **Nuevos:** `src/app/api/auth/entrega/route.ts`; `src/app/api/auth/__tests__/apk-entrega.test.ts`.
* **Modifica:** `src/lib/apk-tokens.ts` (`emitirEntrega`, `PROPOSITO_ENTREGA`, `AMBITO_ENTREGA`;
  en `renovar`, sesión revocada y baja **antes** de `sinLlaveDeEntrada`); `src/lib/acciones-auditoria.ts`
  (las dos acciones nuevas); `src/lib/cors-apk.ts` solo si la lista de rutas permitidas lo pide.
* **Contrato:** B.1. Entrada `{refresh_token}`; salida 200/401/403/409/429/503 como arriba;
  claims fijos; `exp` ≤600 s; no gasta el refresh; no devuelve refresh.
* **Pruebas y mutaciones obligatorias** (cada una debe poner una prueba en rojo, y si no, la
  prueba no vale): quitar la comprobación de `session.revokedAt` → «sesión revocada sin llave NO
  recibe token»; quitar `activo` → «baja no recibe token»; firmar aunque tenga la llave →
  «con llave: 409»; gastar el refresh → «refresh intacto tras entregar»; aceptar un refresh ya
  gastado; meter `delivery.entrar` en `entradas`; alargar `exp`; devolver refresh en la
  respuesta; quitar el límite de tasa; **y en `renovar`:** invertir el nuevo orden → «sesión
  revocada sin llave da 401, no 403».
* **Aviso:** `src/lib/sync-clients.ts`, `puerta-de-entrada.ts` y `apk-tokens.ts` los comparten
  otros flujos; ninguna prueba de `puerta-de-entrada.test.ts` puede cambiar de significado.

## V — Verificadores Go (dos módulos)

* **Nuevos:** `sync/internal/identidad/entrega.go` (`DeTokenDeEntrega`) y `entrega_test.go`;
  `api/internal/auth/ambito_test.go`; `docs/ambito-de-entrega.casos.json`.
* **Modifica:** `sync/internal/identidad/token.go` (leer `ambito`, `purpose`, `name`, `jti`; las
  rutas normales rechazan todo token con `ambito`); `api/internal/auth/auth.go` (lo mismo:
  rechazar `ambito`). **`auth.go` está en manos de otro agente ahora: esperar.**
* **Contrato:** `DeTokenDeEntrega` devuelve `Identidad{Persona, Nombre, Sucursal, Jti}` o
  `ErrSinSesion`; nunca roles. El mismo `casos.json` lo leen las pruebas de `api/` y `sync/`.
* **Mutaciones:** quitar el rechazo de `ambito` en `DeToken` (con un token de entrega que
  además traiga la llave) → rojo; aceptar un token normal en `DeTokenDeEntrega`; aceptar
  `purpose` distinto; no exigir `exp`; aceptar si `entradas` contiene la llave; en `api`, quitar el
  rechazo → rojo. Prueba en pareja: el token de entrega **no** entra por `/api/*`,
  `/sync/subida`, `/sync/bajada`, `/sync/estado`.

## S1 — `sync`: datos y entrega

* **Nuevos:** `sync/db/migrations/00003_la_bandeja_de_revision.sql`;
  `sync/db/queries/revision.sql`; `sync/internal/sincro/revision_entrega.go`,
  `revision_limites.go`, `revision_rutas.go` (`RutasDeRevision`), `revision_entrega_test.go`,
  `dobles_revision_test.go` (los métodos nuevos de `baseFalsa`, **en fichero aparte** para no
  tocar `dobles_test.go`).
* **Modifica:** `sync/internal/sincro/subida.go` (**solo** el paso 0 de `unApunte`: mirar
  `revision_apuntes`); `sync/internal/sincro/estado.go` (`en_revision` por sucursal);
  `sync/cmd/sync/main.go` (monta las dos rutas de entrega con `DeTokenDeEntrega`);
  `sync/db/migraciones_test.go` si lista versiones; regenera `sync/internal/store/sqlc/*`
  con `~/go/bin/sqlc generate` (no a mano).
* **Contrato:** `POST /sync/revision/entrega` → `{resultados:[{clave, estado:"en_revision"|"repetido",
  estadoActual, revision, motivo?}]}`; errores `409 huella_distinta`, `422 entrega_no_admitida`,
  `429 cupo_de_revision`, `404 aparato_no_registrado` (con la marca de siempre) y `403
  sin_permiso_reparto` para cualquier token que no sea de entrega. `GET /sync/revision/mias` →
  `{entregas:[{clave, estado, decididoPorNombre, decididoAt, motivo, idCreado}]}` (con una
  fuente de identidad que acepta el token de entrega **o** el normal, siempre de la misma
  persona del aparato).
* **Pruebas y mutaciones obligatorias:** **invariante central: el `Aplicador` NO se llama NUNCA
  en la entrega** (el doble cuenta llamadas; mutación: llamar al aplicador → rojo). Además:
  quitar `ON CONFLICT` (idempotencia) → «entregar dos veces = 1 fila»; quitar la comparación
  `aparato.Persona == sub`; quitar la comparación de sucursal; quitar la lista blanca (ruta
  `/admin/recompute`, `..`, `//`); quitar cada cupo (500 apuntes, 8 MiB, 3.000 por sucursal);
  re-serializar el cuerpo (la huella ya no cuadra con el original); aceptar token normal;
  guardar sin `hecho`; `huella_distinta` que sobrescribe. **Con Postgres de verdad** (nuevo
  `SYNC_MOTOR_REAL_DSN`, al estilo de `REPARTO_MOTOR_REAL_DSN`): los triggers que impiden
  `DELETE` y cambiar el original, y el `CHECK` del descarte sin motivo.

## S2 — `sync`: el revisor

* **Nuevos:** `sync/internal/sincro/revision_revisor.go`, `revision_aplicar.go`,
  `revision_revisor_test.go`, `revision_aplicar_test.go`.
* **Modifica:** `sync/internal/sincro/subida.go` (**solo** extraer `unApunte` para que acepte un
  «origen» opcional: autor + revisión; la subida normal no cambia de comportamiento);
  `sync/internal/reparto/reparto.go` (`Peticion` gana `Autor`, `Revision`, `SucursalPedida` y
  `Aplicar` pone `X-Autor`, `X-Revision`, `X-Sucursal-Id`); `sync/internal/sincro/servicio.go`
  y `main.go` (registrar `RutasDelRevisor`).
  **Empieza cuando S1 entregue migración, consultas y dobles.**
* **Contrato:** B.2 «Aplicar» y B.4. Respuestas con el resultado por apunte y, si falla, el
  motivo literal. `409` si otro lo está aplicando; `403` si el revisor es el autor o no ve la
  sucursal; `422` si el descarte no trae motivo.
* **Mutaciones:** quitar «revisor ≠ autor»; quitar el alcance de sucursal en el SQL (el
  ADMINISTRADOR de CAM **no** lista ni aplica lo de HOL, probado por lista **y** por id);
  quitar `X-Sucursal-Id`; quitar el candado `aplicando` (doble clic aplica dos veces: el doble
  cuenta); aplicar sin volver a pasar la lista blanca; descartar sin motivo; borrar en vez de
  marcar; que un LOGISTICO pueda revisar; que un 5xx se marque `rechazado`; que un 4xx se
  reintente solo; no copiar al libro `apuntes` al aplicar (la reentrega normal debe dar `repetido`).

## P — `api`: rastro de autoría

* **Modifica:** `api/internal/api/rastro_de_quien.go` (añade `autor` y `revision` a la línea si
  llegan `X-Autor`/`X-Revision`) y su prueba. **No autoriza nada con ellas** y las recorta.
* **Mutaciones:** que la cabecera cambie el `actor`; que el token salga en el registro
  (`TestElRastroNoEnsenaElToken` ya lo ata).

## N1 — App: estados y acoplamientos locales

* **Modifica:** `app/lib/nucleo/base/tablas/aparato.dart` (enum + 4 columnas);
  `app/lib/nucleo/base/base.dart` (`schemaVersion` 7, `onUpgrade`, `cuantosEnRevision`, guardas);
  `app/lib/nucleo/base/base.g.dart` (**generado**, no a mano); `app/lib/nucleo/sincro/huerfanos.dart`
  (los tres SQL); `app/lib/nucleo/cola/cola_salida.dart` (`marcarEnRevision`, `resolverRevision`,
  `lote()` sigue devolviendo solo `pendiente`); `app/lib/nucleo/cola/apunte.dart`
  (`ResultadoApunte` entiende `en_revision`); `app/lib/nucleo/base/personas.dart`;
  `app/lib/arranque/arranque.dart` (`_elAparatoTieneDatos`).
* **Pruebas (sembrar DENTRO del cuerpo, §3-ter):** `test/nucleo/cola/revision_test.dart`,
  ampliar `test/nucleo/base/la_migracion_no_se_lleva_el_trabajo_test.dart`,
  `test/nucleo/sincro/huerfanos_test.dart`.
* **Mutaciones:** quitar `enRevision` de cada uno de los **tres** SQL de huérfanos → «lo
  entregado no se reencola» rojo (una por SQL); `lote()` que incluya `enRevision`; `aplicado`
  por revisión que no suelte `nacio_aqui`; `enRevision` que sí lo suelte; contar `enRevision`
  en «N sin subir»; no contarlo en la guarda de olvidar; escribir `motivo` en vez de
  `motivoRevision`.
* **Aviso:** `lib/nucleo/**` lo están tocando otros agentes: esperar a que lo suelten.

## N2 — App: servicio de entrega

* **Nuevos:** `app/lib/nucleo/sincro/entrega_a_revision.dart` (flujo completo, con su propio
  `Dio` sin `InterceptorSesion` para no entrar en bucle de renovar);
  `app/test/nucleo/sincro/entrega_a_revision_test.dart`.
* **Modifica:** `app/lib/nucleo/proveedores.dart` (un provider; **fichero compartido: el cambio
  es de una línea y se pide permiso al dueño del momento**); `app/lib/nucleo/sincro/ciclo.dart`
  (consulta `mias` solo si hay `enRevision`).
* **Contrato:** pide token a `{AUTH_URL}/api/auth/entrega`; manda de uno en uno a
  `/sync/revision/entrega`; actualiza el estado local solo con la respuesta; devuelve un
  resumen con cuántos entregados / sin entregar / error literal.
* **Mutaciones:** que entregue `rechazado` o `descartado`; que marque `enRevision` antes de la
  respuesta; que borre el apunte al entregarlo; que use el token normal; que reintente el
  token sin tope; que dé de alta el aparato ante un 404; que un `FalloDeRed` deje algo en
  estado intermedio; que un 401 de Accesos borre la cola; que un `409 tiene_permiso` entregue.

## N3 — App: pantalla `/sin-permiso`

* **Modifica:** `app/lib/pantallas/acceso/vista/pantalla_sin_permiso.dart`;
  nuevo `app/lib/pantallas/acceso/vista/panel_de_entrega.dart` y
  `app/lib/pantallas/acceso/datos/textos_de_entrega.dart` (los literales de B.5);
  pruebas: ampliar `test/pantallas/acceso/sin_permiso_test.dart` y
  `test/nucleo/cola/cerrar_sesion_con_trabajo_sin_subir_test.dart`.
* **Pruebas en pareja (§3-quinquies):** con cola → sale el panel y el botón; **sin cola → no
  sale**; **en la web → nunca sale**; «Cerrar sesión» con cola ofrece las tres opciones; el
  botón es `BotonPrincipal` con icono (`el_principal_lleva_su_icono_test.dart` ya lo vigila).
* **Mutaciones:** mostrar el panel en la web; entregar sin pulsar; que «Salir sin entregar» no
  avise; que el panel navegue fuera de `/sin-permiso`.

## N4 — App: la bandeja del revisor

* **Nuevos:** carpeta `app/lib/pantallas/revision/{datos,estado,vista}/`, su `registro.dart`;
  pruebas en `app/test/pantallas/revision/`.
* **Modifica:** el índice de pantallas registradas (donde cuelgan `registrarSincronizacion` y
  compañía) y, si se confirma la web, `app/lib/nucleo/red/cliente_api.dart` (`bearerExplicito`)
  y `app/lib/nucleo/plataforma.dart` (`Destino`); `contrato_registro_test.dart` obliga a
  declarar la ruta.
* **Contrato:** consume B.2. Muestra por apunte: método, ruta y cuerpo exactos (colapsable),
  la hora del aparato, quién y desde qué aparato; «Aplicar», «Aplicar todo en orden» y
  «Descartar» (motivo obligatorio, `BotonDestructivo`). Solo se registra en el menú para quien
  puede revisar.
* **Mutaciones:** botón Aplicar visible para un LOGISTICO; descarte sin motivo; la web que
  mande cookie en vez de Bearer; que se pinte «Aplicado» antes de la respuesta.

## D — Documentos y punta a punta (al final, un solo dueño)

* **Modifica:** `docs/sin-permiso.md` (la sección «NO PERDER TRABAJO» cambia: la cola ya tiene
  salida), `docs/contratos-api.md` (endpoints nuevos y las dos cabeceras), `docs/sincronizacion.md`
  (§ revisión), `docs/despliegue.md` (orden de despliegue), y una entrada en `CLAUDE.md` §4.
* **Prueba de punta a punta (`qa-como-usuario`)** con dos aparatos y Accesos local
  (`deploy/accesos-local`): quitar la llave a una persona con 3 apuntes; entregar; revisor
  aplica 2 y descarta 1; la persona lo ve; revocar la sesión de otra con la llave quitada y
  comprobar que **no** puede entregar; baja → no entrega; cerrar sesión → no entrega.
* Lanzar `auditar-el-reparto` **antes de cada commit** y **una pasada final** que rompa guardas
  de otros paquetes (CLAUDE.md §4-bis).

---

# D. Riesgos, lo que no se hace ahora, preguntas

## Riesgos

1. **Autoridad prestada** (el mayor): el payload de alguien sin permiso se aplica con el poder
   del revisor. Mitigación: lista blanca, `X-Sucursal-Id` forzada, ver el original antes de
   pulsar, sin editar, y un test por cada una. Si se relaja una, vuelve el riesgo.
2. **Quien revoca la sesión sigue recibiendo un 403 «de buena fe»** hoy (A.4.1). Se arregla en
   A1, pero **hasta que A1 no esté desplegado no se puede abrir la entrega**.
3. **Spam a la bandeja** por una persona con sesión viva: cupos y tasa. Aun así puede ocupar
   500 apuntes de revisor; se ve en el contador y se descarta con un gesto por entrega.
4. **Datos viejos**: un apunte aplicado días después puede chocar con lo que cambió. Lo ataja el
   reparto con su motivo literal; el revisor ve la hora del aparato y la de la entrega.
5. **Doble aplicación por caída**: la API no lee `X-Apunte`; la red es el estado `aplicando`
   con reintento confirmado a mano. No se promete más.
6. **Estados nuevos en la cola local** rompen cualquier lista de estados escrita a mano. Las
   que se conocen están en B.5; hay que **buscar el resto** (`grep "EstadoApunte"` y `estado IN`).
7. **`sync` sin `aparato.Persona` en la subida normal** (A.4.4): lo cierro en la entrega; la
   subida normal queda como está salvo que Jose quiera endurecerla (es un cambio aparte).
8. **Un nombre de rol como llave de revisión** contradice el 08/10 de Jose (B.3). Decisión suya.
9. **Orden de despliegue**: si `sync` contesta `en_revision` a una APK vieja, esta lanza
   `FormatException` en cada ciclo. Solo ocurre con la instalación que entregó, que ya es nueva.
10. **Una persona que cerró sesión antes de entregar queda varada.** Se mitiga con el nuevo
    diálogo de «Cerrar sesión», no se resuelve del todo (opción 4 de B.1).

## Qué NO se hace ahora

* Entrega **automática** (se pide un toque).
* Entrega desde el **login** o con la sesión ya cerrada (opción 4).
* **Retirar** una entrega o editarla desde el aparato.
* **Editar** el cuerpo en la revisión, aplicar a medias, aplicar en bloque a varias sucursales.
* Autoaplicar o autodescartar por antigüedad. Nada caduca ni se borra.
* Llave `delivery.revisar` en Accesos (queda para cuando haga falta; ver pregunta 1).
* aviso por **notify** (fase 2; el contador y el número rojo cubren la fase 1).
* Cambiar la web, su cookie de 7 días o el aviso de cambio de rol.
* Endurecer la subida normal con `aparato.Persona == sub` (se recomienda, es otro cambio).
* Entrega para quien tiene la **baja o la sesión revocada**: jamás.

## Tres preguntas para Jose

1. **¿Quién revisa?** Propuesta por defecto: ADMINISTRADOR de esa sucursal, SUPER ADMIN y
   DESARROLLADOR (por nombre de rol, como hoy en el resto de Reparto), y **nadie revisa lo
   suyo**. *Recomiendo confirmarlo así para empezar;* si más adelante hay más revisores, pasar
   a una llave de Accesos (`delivery.revisar`), que es lo coherente con «quién entra lo decide
   Auth».
2. **¿La bandeja del revisor también en la web?** Choca en apariencia con «la web sin nada del
   aparato», pero es un buzón de oficina, no una cola. *Recomiendo que sí*, llamando a `sync`
   con el token de `/api/me` como Bearer; el administrador de oficina trabaja en la web, no en
   el escritorio.
3. **¿Cuánto puede esperar una entrega y quién se entera?** *Recomiendo:* nunca se aplica ni se
   borra sola; contador rojo desde el primer minuto; **un solo correo por sucursal y día** por
   notify cuando haya algo sin decidir más de 1 hora, y otro a los 7 días. La entrega
   la hace la persona con un toque (manual), no automáticamente.

---

## Decisiones de Jose (08/10/2026)

Jose aprobó las tres recomendaciones de este documento («las decisiones tuyas las veo bien»):

1. **Quién revisa:** ADMINISTRADOR de esa sucursal, SUPER ADMIN y DESARROLLADOR; **nadie revisa lo suyo**.
2. **La bandeja del revisor también en la web:** sí.
3. **Plazos y avisos:** nada se aplica ni se borra solo; un correo por sucursal y día (lo manda notify, no un script suelto).

Se implementa en una ronda aparte (1.0.32), después de desplegar la ronda de sesión única, para no mezclar los dos despliegues.

---

## Estado real (09/10/2026)

Escrito el 09/10/2026 leyendo el código y los cuadernos de cada agente
(`~/Notas/Procovar/Pendiente/sesion-unica/`: `A1-ACCESOS`, `FIXES-A1`, `HARDENING-ACCESOS`,
`G-SYNC1`, `G-SYNC2`, `G-API`, `G-APP1`, `G-APP2`, y las tres pasadas de control: `AUDITOR-SEG-BANDEJA`, `QA-E2E` y
`AUDITORIA-FINAL-1032`). **Lo de arriba es el diseño; esto es lo que hay.**
Donde difieren, manda esto. Al escribir esto nada estaba desplegado salvo Accesos (`8ba2642`) ni commiteado; el 09/10/2026 por la tarde se commiteó (`fa0295a`) y se desplegó todo, y se publicó la APK/Windows 1.0.32+33 (`c92aca6`). Orden de despliegue y estado de
los riesgos 2, 9 y 10: `docs/despliegue.md` §4-bis.

### Qué se hizo, por paquete

**A1 — Accesos (HECHO y DESPLEGADO, commit `8ba2642` de `PROCOVAR-DEV/procovar-auth`).**
`POST /api/auth/entrega` (`src/app/api/auth/entrega/route.ts`, nuevo): token de 10 minutos y ámbito
`reparto.entrega`, sin gastar ni devolver el refresh. La regla vive en `emitirEntrega`
(`src/lib/apk-tokens.ts`; `PROPOSITO_ENTREGA`, `AMBITO_ENTREGA`, `SEGUNDOS_ENTREGA`) y comprueba en este orden:
refresh existe → no revocado → no gastado → no caducado → es de Reparto → sesión viva → persona activa y con
sucursal → **la llave la última** (409 si la tiene). En `renovar`, `puertaDeRenovar`/`sesionOPersonaMuerta` miran
la sesión revocada y la baja **antes** de la llave, en el camino normal y en la gracia (una sesión revocada sin
llave pasa de 403 a 401), y `RenovacionNoDisponible` da 503 si la base cae a mitad. Auditoría:
`auth.apk.entrega` y `auth.apk.entrega_denegada` (`src/lib/acciones-auditoria.ts`). Endurecimientos del mismo
commit que tocan este camino (`FIXES-A1.md`): `src/lib/con-tope.ts` (tope de 800 ms a Redis en `/entrega`, `/token`,
`/refresh`), `commandTimeout` de 1,5 s en el cliente `locks` (`src/lib/redis.ts`), `Cache-Control: no-store` en las
cuatro rutas de la APK (`src/lib/cors-apk.ts`), `.max(256)` al refresh, la baja antes del atajo de los clientes sin
llave (`src/lib/puerta-de-entrada.ts`), `iatms` = la lectura de la sesión. Y `exchange` manda `organization.codigo`
(`HARDENING-ACCESOS.md`). Pruebas: `src/app/api/auth/__tests__/apk-entrega.test.ts` (32), más lo añadido en
`apk-puerta.test.ts`, `apk-tokens.test.ts`, `limitador-colgado.test.ts`; 24 mutaciones de A1 y 18 de los arreglos,
todas rojas (cuadernos). **Contrato real:** `200 {token, token_type:"Bearer", expires_in:600, ambito:"reparto.entrega"}`; `400`
(`invalid_json`, `invalid_body`); `401 invalid_refresh` (mismo cuerpo para refresh inexistente, revocado, gastado, caducado, de otra
aplicación, sesión revocada o caducada y baja); `403 sin_sucursal`; `409 tiene_permiso`; `429 rate_limited`; `503
comprobacion_no_disponible` (limitador sin contestar a los 800 ms —aquí SÍ se cierra— o la base caída). Límites: por IP, cubo de 60
con 1/s; por huella del refresh, cubo de 10 con 1 cada 10 s. Detalle en `docs/contratos-api.md` §12.1.

**V — verificadores Go (HECHO).**
`sync/internal/identidad/entrega.go` (`DeTokenDeEntrega`, `FuentesDeEntrega`) y `token.go` (`bearerDe`, `abrir`,
`verificar` rechaza todo token con `ambito`); `api/internal/auth/auth.go` (`ErrAmbito`, rechazo por presencia).
Compartido por los dos módulos: `docs/ambito-de-entrega.casos.json` (44 casos; `deploy/Dockerfile.api`,
`.espejo` y `.sync` lo copian, y sin él la imagen no construye). Pruebas: `sync/internal/identidad/entrega_test.go`,
`api/internal/auth/ambito_test.go`, `ambito_casos_test.go`, `api/internal/api/ambito_de_entrega_test.go`.

**S1 — `sync`: datos y entrega (HECHO).**
Migración `sync/db/migrations/00003_la_bandeja_de_revision.sql` (3 tablas, el tipo `revision_estado`, 4 funciones y
11 triggers: ni `DELETE` ni `TRUNCATE`, el original de un apunte inmutable, el libro de decisiones solo se añade),
consultas `sync/db/queries/revision.sql` (+ `sync/internal/store/sqlc/revision.sql.go`, generado), entrega y `mias`
en `sync/internal/sincro/revision_entrega.go`, límites en `revision_limites.go`, montaje en `revision_rutas.go` y
`sync/cmd/sync/main.go`; el paso 0 de `unApunte` (`subida.go`) y `en_revision` en `/sync/estado` (`estado.go`).
**El `Aplicador` no se llama nunca en la entrega** (el doble del reparto tiene que acabar con cero llamadas; lo ata
`revision_entrega_test.go`). Con Postgres de verdad: `revision_motor_real_test.go`, solo con `SYNC_MOTOR_REAL_DSN`
(`docs/entorno-local.md` §7-quater; `./comprobar.sh` dice «SALTADO» sin ella).

**S2 — `sync`: el revisor (HECHO).**
`sync/internal/sincro/revision_revisor.go` (lista, detalle, descartar, el «por qué no» de cada 4xx),
`revision_aplicar.go` (aplicar uno, aplicar en orden), `sync/internal/identidad/revisor.go` (`RolDeRevisor`),
`sync/internal/reparto/reparto.go` (`X-Autor`, `X-Revision`, `X-Sucursal-Id` solo si vienen), `subida.go`
(`reenviar` y `origenDeRevision`: la subida normal y la revisión comparten tubería), `servicio.go` (`Peticion` gana
`Autor`, `Revision`, `SucursalPedida`; `Rutas` monta `RutasDelRevisor`). Contrato en `docs/contratos-api.md` §12.

**Tanda final de `sync` (auditoría de seguridad y auditoría final, 09/10/2026, `G-SYNC2.md`).**
(1) **El corte `web`**: `sync/internal/sesiones` guarda dos mapas (`web`, `todo`) y recoge las dos familias de marcas de Redis; un
token `web:true` (el de la cookie que la bandeja web usa como Bearer) no vale si `max(web, todo) >= iatms`: tras cerrar sesión solo
en el navegador, 401 en `/sync/*` (`identidad/token.go`). (2) **Migración nueva `00004_nombre_de_aparato_acotado.sql`**
(recorta a 200 los nombres que ya hubiera y añade `CHECK (char_length(nombre) <= 200) NOT VALID`); `POST /sync/aparato` limpia y recorta el nombre a 80 (`aparato.go`,
`topeNombreDeAparato`) y la bandeja del revisor lo recorta a 200 al leerlo; **`ExigirMigraciones` espera ya la 4**. (3) **Lista blanca
de ruta POR FORMA** (`revision_limites.go`): las ocho rutas de escritura que la API tiene de rutas y tablero, con `{id}` sin puntos;
`POST /board` suelto ya no entra (422). (4) **`aplicar` mira el libro `apuntes`** tras reclamar (B6): si la subida normal ya había
aplicado la clave, cierra `aplicado` sin reenviar; si la rechazó, `rechazado`; y copia lo que aplica al libro con
`CopiarApunteAplicadoAlLibro` (`ON CONFLICT DO NOTHING`). (5) Pruebas nuevas: `TestReclamarUnAplicandoInterrumpidoTambienExigeOtraPersonaYElAlcance`,
`TestMainSeNiegaAArrancarConLaBaseAtrasada` (AST de `main`) y `TestUnTokenDeEntregaSinSucursalSeRechazaAntesDelResolutor`. 27
mutaciones: 26 rojas y 1 equivalente (quitar el `left()` del SQL no cambia lo que sale porque Go recorta igual).

**P — `api`: autoría (HECHO, y movido de sitio por la prueba de punta a punta).** `X-Autor` y `X-Revision` salen como `autor` y
`revision` en la línea `peticion` de **toda escritura** (POST, PUT, PATCH, DELETE) en `api/internal/httpx/middleware.go`
(`RegistrarPeticiones`, `autoriaDe`, `TopeDeLaAutoria` = 64); **ya no** en `rastroDeQuien` (`api/internal/api/rastro_de_quien.go`),
que solo cubre diez sitios y dejaba sin autoría `/board/*` (hallazgo F2 de `QA-E2E.md`). No autorizan nada ni cambian `actor` ni
`rol`. Pruebas: `api/internal/httpx/autoria_test.go` (los 7 métodos) y las de `rastro_de_quien_test.go`; 10 mutaciones rojas
(`G-API.md`, ronda 2). De paso, `Reset` con candado en `registroSeguro` y esperas más holgadas para que las pruebas pasen con
`-race`.

**Web leyendo `codigo` (HECHO, no estaba en el diseño).** `api/internal/api/auth_web.go` (`codigoDeSucursal`): manda
`organization.codigo` y, si falta, cae al `slug` en mayúsculas; sirve para que el `PLS` de Palma Soriano no pida
`PALMA-SORIANO`. Accesos ya lo manda desde `8ba2642`.

**N1 — app: estados y acoplamientos locales (HECHO).** `app/lib/nucleo/base/tablas/aparato.dart` (`EstadoApunte`
gana `enRevision` y `descartadoPorRevisor`; columnas `revision`, `revisadoPor`, `revisadoAt`, `motivoRevision`),
`base/base.dart` (`schemaVersion` 7, la migración solo añade las columnas que faltan, `cuantosEnRevision`),
`base/base.g.dart` (generado), `cola/apunte.dart` (`EstadoResultado.enRevision`, `DecisionDeRevision`),
`cola/cola_salida.dart` (`marcarEnRevision`, `resolverRevision`, `enRevision()`, `decididosPorRevision()`),
`sincro/huerfanos.dart` (los tres SQL salen de UNA lista), `sincro/subida.dart` (`_cierreSinAceptar` también retiene
el `completed` si la hoja está `enRevision`; fuera de la lista de N1), `base/personas.dart` y `arranque/arranque.dart`.
Pruebas: `test/nucleo/cola/revision_test.dart`, `huerfanos_test.dart`, `la_migracion_no_se_lleva_el_trabajo_test.dart`,
`base_test.dart` (48 mutaciones rojas, cuaderno G-APP1).

**N2 — app: servicio de entrega (HECHO).** `app/lib/nucleo/sincro/entrega_a_revision.dart` (`EntregaARevision`:
`entregar()`, `actualizarEstados()`, `consultarConSesion()`), `sincro/ciclo.dart` (`_preguntarPorLaRevision`, entre
subir y bajar, solo si hay algo `enRevision`), `nucleo/proveedores.dart` (`entregaARevisionProvider`). Su propio
`Dio` sin `InterceptorSesion`; manda un apunte por petición y en orden; marca `enRevision` con la respuesta en la
mano; renueva el token de entrega una sola vez; nunca da de alta el aparato. Prueba:
`test/nucleo/sincro/entrega_a_revision_test.dart`. **Rondas 3 y 4 (G-APP1):** el `provisional` viaja siempre; el `repetido` trae lo que
hace falta (`id`, `descartados`, `decididoPorNombre`, `motivoDelDescarte`) y no hace falta ir a `mias`; y, por el hallazgo SERIO 1 de la
auditoría final (R3: si se pierde la respuesta de una entrega, un revisor aplica el apunte 1 y la reentrega sustituía el `local-…` en el
apunte 2 pendiente, que llegaba con otro cuerpo → `409 huella_distinta` para siempre), **`resolverRevision(aplicado)` ya NO reescribe los
apuntes pendientes dependientes** (`Provisionales.sustituir(…, reescribirApuntes: false)`: la equivalencia y las filas locales sí se
sustituyen, la ruta y el cuerpo de los pendientes no, porque `sync` guarda el original con `local-…` y traduce él al aplicar). El `repetido`
del LIBRO (sin `revision`) sigue sustituyendo como antes. 5 mutaciones nuevas rojas.

**N4 — app: la bandeja del revisor (HECHO y reconciliado con el contrato real de S2, `G-APP2.md`).** `app/lib/pantallas/revision/**`
(ruta `/revision`, en el menú solo para ADMINISTRADOR, SUPER ADMIN y DESARROLLADOR), `nucleo/red/interceptor_sesion.dart` y
`cliente_api.dart` (`bearerExplicito`: en la web `sync` se llama con Bearer a mano y nunca con cookie; `mandar(reintentar: false)`),
`navegacion/pantallas.dart` (una línea). Reconciliación con S2: «aplicar todo» se detiene y la tarjeta lo dice («Aplicar todo se
detuvo en <método ruta>. Quedan N apuntes sin procesar. Motivo: …»); un 502 `reparto_no_disponible` se dice como «El reparto no
contestó; el apunte sigue en revisión, no está rechazado» y **nunca se pinta rechazado**; un `aplicando` marcado `interrumpido`
solo se reintenta tras `vista/confirmar_reintento.dart` (`{"reintentarInterrumpido":true}`); las órdenes de aplicar y descartar
**no se repiten solas** (un 5xx se reintentaba 3 veces por defecto); sin conexión dice «no se sabe si la orden llegó»; nada se pinta
«Aplicado» antes de la respuesta. Pruebas: `test/pantallas/revision/`, `test/nucleo/red/bearer_explicito_test.dart`,
`mandar_sin_reintento_test.dart`, `test/navegacion/contrato_registro_test.dart` (31 mutaciones en copia, todas rojas). **Confirmaciones
(M2 de la auditoría de seguridad, `G-APP2.md`):** «Aplicar todo en orden» abre un cajón «Confirma antes de aplicar» con el recuento por
método y por qué hace cada ruta en palabras (`datos/que_hace.dart`, `vista/confirmar_aplicar.dart`); si hay algún `DELETE` o más de 25
apuntes, hay que **escribir el número**; un `DELETE` o `PATCH` suelto pide una confirmación corta; cerrar el cajón con Escape es «no»; y
la fila enseña el texto legible además del crudo. 15 mutaciones más, todas rojas. **La pantalla no se ha probado contra el `sync` real
ni en un navegador real**; el contrato del revisor sí, con scripts, en `QA-E2E.md`.

**N3 — app: `/sin-permiso` con «Entregar a revisión» y el «Cerrar sesión» de tres opciones (HECHO, `G-APP1.md`).**
`app/lib/pantallas/acceso/vista/panel_de_entrega.dart` (nuevo: `PanelDeEntrega`, `ControlDeEntrega`),
`acceso/datos/textos_de_entrega.dart` (nuevo: `TextosDelPanel`, los literales de B.5) y `pantalla_sin_permiso.dart` (monta el panel
solo en APK y escritorio; «Cerrar sesión» con cola = **Entregar a revisión y salir** —solo sale si todo quedó entregado— / **Salir
sin entregar** / **Me quedo**, y cerrar el cartel sin contestar es quedarse). El panel **no sale sin cola ni en la web**. `enRevision` no
cuenta como «sin subir» (por eso `menu_de_cuenta.dart` y `salir_con_el_gesto.dart` no se tocaron) pero sí avisa antes de olvidar una
copia. Pruebas: `test/pantallas/acceso/sin_permiso_test.dart` (+22), `test/nucleo/cola/cerrar_sesion_con_trabajo_sin_subir_test.dart`
(+1); 67 mutaciones en copia, todas rojas. Los textos y los estados, en `docs/sin-permiso.md`.

**Ajustes de `sync` pedidos por la app (S2, 09/10/2026, `G-SYNC2.md`).** `reProvisionalDeRevision` acepta `local-` + 1 a 94
letras o números **o un UUID** (el UUIDv7 con el que el Tablero crea una zona tumbaba la entrega con un 422); lo ata
`TestElProvisionalDeLaRevisionEsComoElDeLaSubida`. El `repetido` de la entrega lleva ahora `id`, `descartados`, `decididoPorNombre`,
`decididoAt` y `motivoDelDescarte` (aditivo; `motivo` no cambia). 13 mutaciones, todas rojas. **La app ya los consume**
(G-APP1, ronda 3, 09/10/2026): un `repetido` ya decidido se anota sin ir a `GET /sync/revision/mias` cuando la respuesta basta (si falta
algo, conserva la ida a `mias`), el `id` y los `descartados` sustituyen al `local-…`, y el apaño que omitía el `provisional` se quitó:
ahora viaja siempre que el apunte lo tenga.

**D — documentos (este paquete).** `docs/sin-permiso.md`, `contratos-api.md` §12, `sincronizacion.md` §4,
`despliegue.md` §4-bis, `entorno-local.md` §7-quater, `docs/README.md` (índice), `CLAUDE.md` §4 y §5, y este apartado. La prueba de punta a punta, más abajo.

### Desviaciones del diseño, verificadas

1. **El token de entrega lleva `iatms` y `entradas:[]`.** Claims reales: `sub`, `name`, `email`, `sid`, `sucursal`,
   `branch_id`, `ambito`, `entradas:[]`, `roles:[]`, `role:""`, `iatms` (extra: igual que el acceso, para las marcas
   de invalidación de Accesos; es la hora de LEER la sesión), `jti`, `iat`, `exp` (+600 s), `iss`,
   `purpose:"apk:entrega"` (`apk-tokens.ts`, `emitirEntrega`; `A1-ACCESOS.md`).
2. **`/refresh` da 403 y `/entrega` da 200 a la misma persona.** Quien perdió la llave y conserva sesión recibe en
   `/api/auth/refresh` `403 sin_permiso` (no gasta el refresh, no rota nada) y en `/api/auth/entrega` el token de
   entrega. **La entrega no sustituye a la renovación**: sigue sin haber token normal.
3. **Un token de entrega en una ruta normal da 401 en la API y 403 `sin_permiso_reparto` en `sync`.** El diseño decía
   «403» para las dos; `api/internal/auth/auth.go` (`ErrAmbito` → el 401 de siempre) y `sync/internal/identidad/token.go`
   (`ErrSinPermisoDeReparto`) difieren, y `docs/ambito-de-entrega.casos.json` solo ata «no entra», no el código.
4. **«Aplicar todo en orden» SE DETIENE en el primer apunte que no queda aplicado.** B.4 decía que un rechazo no
   detiene al resto; la tarea de S2 mandó lo contrario (lo de detrás puede depender de lo que no entró). La respuesta
   dice dónde (`detenidoEn`), por qué (`detenidoPorque`) y cuántos quedaron sin tocar (`sinProcesar`)
   (`revision_aplicar.go`, `aplicarEntrega`).
5. **`aplicando` interrumpido.** Una fila en `aplicando` de hace 10 minutos o más sale con `interrumpido:true`;
   reintentarla exige `{"reintentarInterrumpido":true}` y deja `interrumpido` en el libro (`ReclamarRevisionInterrumpida`).
   Además el libro admite `resultado = caida` (5xx o red al aplicar), que el diseño no listaba.
6. **No hay `sucursalNombre`.** La bandeja del revisor trae `sucursal` (uuid) y no su nombre; la app lo saca de su copia
   de sucursales o, si aún no bajó, enseña el principio del uuid (`pantalla_revision.dart`, `nombreDe`). La lista es una
   fila por entrega con sus cuentas por estado (`ListarEntregasParaRevisor`), no una fila por apunte.
7. **El rechazo del reparto al aplicar NO deja el apunte local `rechazado`**: sigue `enRevision` con `motivoRevision`
   puesto («No se pudo aplicar: …. Sigue en revisión.»). Un `rechazado` local ofrecería «Reintentar» y «Descartar» a la
   persona sobre algo que el revisor aún puede aplicar (`aparato.dart`, `cola_salida.dart`, `resolverRevision`).
8. **Aviso en vivo: SÍ para la persona que entregó (10/10/2026), NO para el revisor.** `sync` ofrece `GET /sync/revision/eventos`
   (SSE, solo token de entrega): cuando un revisor aplica, rechaza al aplicar o descarta un apunte suyo, a esa persona le llega
   una señal vacía `event: revision` y consulta `mias` (`avisos.go`, `revision_eventos.go`; contrato en `contratos-api.md` §12.3).
   **Lado app (APK y escritorio, 10/10/2026):** la pantalla `/sin-permiso` mantiene UNA conexión a ese flujo mientras el panel está
   montado, el portero sigue en `sinPermiso` y hay algo `enRevision` (la web no abre nada: no tiene cola), y al recibir `revision`
   hace la misma consulta que «Actualizar estados», que se queda de respaldo. **También la hace en cada (re)apertura del flujo**
   (el servidor no guarda eventos: lo decidido con el flujo cerrado solo se sabe preguntando; `contratos-api.md` §12.3). Sin
   sondeo: ningún temporizador consulta. Solo habla cuando cambia algo o falla; reconecta con espera creciente (2 a 60 s,
   `Retry-After` respetado) y pidiendo otro token al caducar el de entrega. La consulta reutiliza el token del flujo mientras le
   queden más de 60 s (el cubo de Accesos es de 10 y 1 cada 10 s). Qué hace con cada código, qué no hace y dónde está cada pieza: `docs/sin-permiso.md`, «El aviso en vivo».
   Memoria de un proceso (con más de una réplica habría que pasarlo por Redis). **El revisor sigue sin aviso**: se entera al
   pulsar «Actualizar», al volver de una desconexión y tras cada decisión propia (`G-APP2.md`), y no hay `CambioEnVivo.revision`.
   Lo único «en vivo» del lado del revisor es el contador `en_revision` de `GET /sync/estado`, y ninguna pantalla lo enseña todavía.
9. **Sin correo de notify (fase 2).** `sync` no tiene cliente de notify; no hay aviso por sucursal y día ni a los 7 días.
10. **La API no lee `X-Apunte`** (solo lo escribe `reparto.go`), así que no hay red contra la doble aplicación: la única
    es el estado `aplicando` y la confirmación a mano. `X-Autor` y `X-Revision` son solo rastro, y **no van en las líneas de
    «rastro de quién» como decía el diseño (P) sino en la línea `peticion` de toda escritura** (`RegistrarPeticiones`): el rastro
    solo cubría diez rutas y dejaba sin autoría `/board/*`.
11. **Límites de Accesos distintos de los del diseño.** Real: por IP, cubo de 60 con reposición de 1 por segundo; por
    huella del refresh, cubo de 10 con 1 cada 10 s (`entrega/route.ts`). El diseño decía 20/hora por IP y 6/hora por
    sesión. `sync` sí cumple: 60 peticiones por minuto por persona, en memoria (se vacía al reiniciar).
12. **La entrega agrupa por token, no por pulsación.** `revision_entregas` tiene `UNIQUE (aparato_id, token_jti)`: la
    app manda los apuntes de uno en uno y todos los del mismo token caen en la misma entrega. `orden` lo pone el servidor
    por orden de llegada dentro del aparato (`MAX(orden)+1`), no la posición en la cola local.
13. **La base impone más que el esbozo:** `CHECK` de `aplicando` con dueño y de `rechazado` con motivo, lista blanca de
    columnas que se pueden mover, y un apunte `aplicado` o `descartado` no se reescribe en nada
    (`00003_la_bandeja_de_revision.sql`).
14. **Todo lo posterior al candado `aplicando` va con `context.WithoutCancel`**: que el revisor cierre la pestaña no deja
    el reparto a medias. Y si el reparto aplicó y la base no lo pudo anotar, el apunte se queda `aplicando` y la
    respuesta es `500 no_se_pudo_anotar` (`revision_aplicar.go`).
15. **El `provisional` de la entrega no es el de la subida normal, aunque se alineó.** La subida normal no valida su forma
    (`valido()` no lo mira; solo traduce los `local-[A-Za-z0-9]+`); la entrega admite `local-` + 1 a 94 letras o números o un
    UUID, y el diseño decía solo `local-…`. No cabe «exactamente lo mismo» en una regex: la prueba ata que todo lo que la subida
    traduce entero cabe en la entrega (`revision_limites.go`).
16. **La lista blanca de ruta es POR FORMA, no «lo que venga detrás».** El diseño decía `^/(routes|board)(/…)?`; ahora son las ocho
    rutas de escritura reales de la API, con `{id}` sin puntos. **Cambio de significado:** `POST /board` suelto estaba entre las
    «buenas» de `TestLaListaBlancaDeMetodoYRuta` y no es una ruta de escritura de la API: ahora da 422. Se mantiene
    `/board/columns/orden`. Antes, `/routes/.` o `/routes/a/b/c/d` entraban, el reparto contestaba 404 con una página que no era
    suya y `Aplicar` lo tomaba por una caída (502) que paraba «aplicar todo» en un apunte que jamás iba a entrar (B3).
17. **`sync` aplica el corte `web` de Accesos**, cosa que el diseño no previó: la bandeja web usa como Bearer el token de la cookie
    de 7 días, y sin esto seguía aplicando y descartando tras cerrar sesión solo en el navegador (hallazgo SERIO 2 de la auditoría
    final y MEDIO 1 de la de seguridad).
18. **`aplicar` mira el libro `apuntes` antes de reenviar** (B6): con un `sync` viejo desplegado por medio, la subida normal pudo
    haber aplicado ya la clave; el diseño solo miraba `revision_apuntes`.
19. **El nombre del aparato tiene tope** (80 al darse de alta, `CHECK ≤ 200` en la 00004, 200 al leerlo en la bandeja): el diseño no
    decía nada y la auditoría de seguridad llegó a pasar 5 MiB de nombre al revisor (M3).
20. **«Aplicar todo» y los `DELETE`/`PATCH` sueltos piden confirmación con recuento** en la app (M2); el diseño solo hablaba de
    «ver el original antes de pulsar».

### Las dos auditorías finales y la prueba de punta a punta

Tres pasadas de control, todas sobre el árbol sin commitear de la ronda, en copias y con bases propias (nunca contra el servidor);
sus cuadernos están en `~/Notas/Procovar/Pendiente/sesion-unica/`.

**`AUDITOR-SEG-BANDEJA.md` (seguridad): sin CRÍTICO ni ALTO; 3 MEDIO y 6 BAJO.** Lo comprobado OK, ejecutando (doble y Postgres real): alcance
de sucursal por lista, por `?sucursal=`, por detalle, por aplicar uno y por entrega, por descartar y por estado; roles parecidos y
Unicode; `ambito`/`Token`; nadie revisa lo suyo; `X-Sucursal-Id` forzada; lista blanca; cupos; triggers, `CHECK` y `TRUNCATE CASCADE`;
migración `up/down/up`. Qué pasó con cada hallazgo:

| Hallazgo | Estado |
|---|---|
| MEDIO 1: `sync` no aplicaba el corte `web` a los tokens web que ahora sirven de Bearer en `/sync/revision/*` | **Arreglado** (desviación 17) |
| MEDIO 2: «Aplicar todo» sin confirmación y con rutas UUID crudas | **Arreglado** en la app (M2, desviación 20) |
| MEDIO 3: `aparato.nombre` sin tope llegaba entero al revisor (5 MiB probado) | **Arreglado** (desviación 19, migración 00004) |
| BAJO B3: apunte hostil disfrazado de caída (404 sin JSON) | **Arreglado** con la lista blanca por forma (desviación 16) |
| BAJO B6: `aplicar` no miraba el libro `apuntes` (doble aplicación con un `sync` viejo) | **Arreglado** (desviación 18) |
| BAJO **B1**: `X-Autor`/`X-Revision` forjables | **ACEPTADO, no arreglado.** Son cabeceras de quien llama y la línea `peticion` sale aunque no haya sesión: cualquiera que llegue a la API puede escribir `autor=`/`revision=`. Sirven para leer el registro, no para decidir nada |
| BAJO **B2**: el literal del reparto vuelve al autor | **ACEPTADO.** Un rechazo al aplicar se guarda con el motivo literal del reparto y `mias` se lo devuelve a la persona que entregó; si ese literal dijera algo que no debería saber, lo sabría |
| BAJO **B4**: los triggers no protegen frente al rol dueño de la base | **ACEPTADO.** El rol con el que corre la app es dueño de las tablas y podría hacer `DISABLE TRIGGER`; los triggers frenan al Go y a la mano torpe, no a quien tiene la base |
| BAJO **B5**: revisión por NOMBRE de rol sin ligarla a la sucursal (la trampa de las dos membresías) | **ACEPTADO.** Es el límite conocido de `CLAUDE.md` §4 («ligar el rol a la sucursal ANTES de dar una segunda membresía»); `RolDeRevisor` mira los roles del token, que son los de la persona entera |

**`QA-E2E.md` y `QA-E2E-evidencia.md` (punta a punta, 13:25 a 14:25):** Accesos `8ba2642` real (copia, con Redis y centinela), el reparto
`9f97400` más la ronda sin commitear, `sync` y API reales, todo en 127.0.0.1; dos sucursales (CAM y HOL), un LOGISTICO, dos
ADMINISTRADOR, un SUPER ADMIN. Once pasos: quitar la llave a alguien con 3 apuntes, entregar desde dos aparatos, el token de entrega
no abre nada más, quién ve y quién aplica, aplicar 2 y descartar 1, doble clic y rechazo y reparto apagado, sesión revocada, baja y cierre
de sesión, sesión única. El cuaderno cuenta **65 comprobaciones: 64 PASA y 1 FALLA (7.c)**. Cuatro hallazgos:

* **F1 (medio, preexistente de Accesos; NO arreglado, documentado):** para quitarle `delivery.entrar` a alguien hay que cambiar su ROL
  (`cambiarRol`), no vaciar su membresía (`PUT …/roles {"roleIds":[]}` no la quita si el rol por defecto trae la llave). Runbook en
  `docs/despliegue.md` §4-bis y `docs/sin-permiso.md`.
* **F2 (bajo; ARREGLADO):** aplicar `/board/*` no dejaba `autor=`/`revision=` en el log de la API (era el 7.c). Ver P.
* **F3 (info):** una ADMINISTRADOR ve su propia entrega pero no puede decidirla (`403 es_lo_tuyo`).
* **F4 (entorno; documentado):** el reparto local necesita `PROCOVAR_AUTH_SIGNING_KEY` derivada de `SERVICE_AUTH_SECRET` y un `Almacen`
  con coordenadas en Accesos para aplicar `POST /board/columns` (`docs/entorno-local.md` §2).

Dos incoherencias dentro de la propia evidencia, que conviene saber: el fichero trae **68 PASA y 6 FALLA** (cuenta el primer intento del
paso 3, descartado, y dos líneas que el cuaderno reclasifica: 6.f como F3 y 7.i, donde los cinco intentos de borrar o reescribir dieron
error de Postgres y el «4/5» es del guion), y **termina en el paso 10**: el cuaderno dice que el 11 pasa, sin evidencia escrita.

**`AUDITORIA-FINAL-1032.md` (final): veredicto NO LISTO a las 14:55**, con 148 de 160 mutaciones rojas, 134 en Go/SQL/migración y 26 en
Dart. Tres hallazgos graves, **todos arreglados después por los autores** (cuadernos): **H1** (app, R3: la reentrega tras perder una
respuesta chocaba con `huella_distinta` para siempre) → G-APP1 ronda 4; **H2** (`sync` ignoraba el corte `web`) → desviación 17; **H3**
(la guarda `persona <>` de `ReclamarRevisionInterrumpida` no tenía prueba) → `TestReclamarUnAplicandoInterrumpidoTambienExigeOtraPersonaYElAlcance`.
También encontró dos guardas sin prueba (`main` sin `ExigirMigraciones` y la sucursal vacía en `DeTokenDeEntrega`), que G-SYNC2 cerró
con `TestMainSeNiegaAArrancarConLaBaseAtrasada` y `TestUnTokenDeEntregaSinSucursalSeRechazaAntesDelResolutor`, y dejó dos avisos menores:
el `Down` de la 00003 destruye lo entregado (más abajo) y un token de entrega caducado hace menos de un minuto todavía se acepta (la
holgura `margen` de 1 minuto, igual que el token normal). **En los cuadernos no consta una re-auditoría posterior que confirme los
arreglos.** Dos carreras de datos bajo `-race` con mucha carga (`TestArmarConUnOrigenFueraDelPlaneta…` y
`TestLosMensajesQueNoSeEntiendenSeIgnoran…`) no se reprodujeron en más de 80 pasadas aisladas.

### Lo que NO se hizo / seguimiento

La lista honesta, a 09/10/2026:

* **Re-auditoría tras los arreglos de la tanda final: HECHA, LISTO** (09/10/2026 ~15:30 Cuba, `AUDITORIA-FINAL-1032.md`: los tres SERIOS
  arreglados, 38 mutaciones rojas de 39). La prueba de punta a punta (`QA-E2E.md`) se hizo **antes** de esos arreglos, y la pantalla
  del revisor (N4) nunca se ha probado contra el `sync` real ni en un navegador real de producción: que un ADMINISTRADOR abra
  `/revision` con una entrega real sigue pendiente.
* **Desplegado el 09/10/2026**: Accesos `8ba2642`; migraciones 00003 y 00004, sync, API y web de `fa0295a`; APK y Windows 1.0.32+33
  (`c92aca6`). Orden y ritual en `docs/despliegue.md` §4-bis. Falta la prueba física en un teléfono y un PC.
* **Aviso en vivo (SSE) de revisión: solo para la persona que entregó** (`GET /sync/revision/eventos`, 10/10/2026; punto 8 de arriba).
  **El revisor no lo tiene**: no hay `CambioEnVivo.revision`; se entera al pulsar «Actualizar», al volver de una desconexión y tras
  cada decisión propia. La persona, además del aviso, tiene «Actualizar estados» y el ciclo.
* **Sin correo de notify (fase 2)**: `sync` no tiene cliente de notify; no hay aviso por sucursal y día ni a los 7 días.
* **Sin badge del contador «en revisión» en el menú ni en el panel de Sincronización.** `GET /sync/estado` ya trae `en_revision` por
  sucursal, y ninguna pantalla lo enseña (hoy el contador está solo en la cabecera de `/revision`).
* **`app/lib/pantallas/tablero/datos/consultas.dart` no distingue `enRevision`** en la insignia de zona (`sin_subir`/`rechazada`):
  no rompe, pero no lo dice (`G-APP1.md`).
* **La API no lee `X-Apunte`** (solo lo escribe `reparto.go`): no hay red contra la doble aplicación más que el estado `aplicando`
  y la confirmación a mano. `X-Autor` y `X-Revision` son solo rastro.
* **Tres cosas de `sync` escritas y sin manejador:** la consulta `RevisionDecisionesDeApunte` (**el libro `revision_decisiones` se
  escribe pero ningún endpoint lo lee**), la consulta `ListarRevisionParaRevisor` (la lista usa `ListarEntregasParaRevisor`) y la
  constante `CodigoSigueEnCurso` de `revision_revisor.go`.
* **Riesgos aceptados de la auditoría de seguridad, sin arreglar** (tabla de arriba): **B1** `X-Autor`/`X-Revision` forjables, **B2** el
  literal del reparto vuelve al autor, **B4** el rol de la app es dueño de las tablas y puede hacer `DISABLE TRIGGER`, **B5** la revisión
  por nombre de rol no se liga a la sucursal (la trampa de las dos membresías).
* **El `Down` de la 00003 BORRA las tres tablas con los datos dentro**, lo que contradice «una decisión se escribe»: aviso en
  `docs/despliegue.md` §4-bis; en producción solo se vuelve atrás desplegando la imagen anterior.
* **F1 de Accesos, preexistente y sin arreglar**: `PUT …/members/…/roles {"roleIds":[]}` no quita `delivery.entrar` si el rol por
  defecto de la persona la trae. Hoy es un runbook (cambiar el ROL en Personas), no un arreglo.
* **Retirar una entrega** y **entregar desde el login o con la sesión ya cerrada** (opción 4 de B.1): siguen fuera; quien cierra sesión
  sin entregar queda varado (riesgo 10).
* **Quién revisa sigue siendo por NOMBRE de rol** (`identidad/revisor.go`), no por una llave `delivery.revisar` de Accesos (riesgo 8
  del diseño, decisión de Jose del 08/10/2026).
* **Riesgo conocido de A1** (`A1-ACCESOS.md`): si la base cae DESPUÉS de reclamar la gracia, el reintento da `gracia_gastada` (401); y
  si la caída dura más de 2 minutos tras gastar el refresh, el reintento ya es «robo». Es el diseño previo de la gracia; el 503 solo
  mejora lo que ve la app.
* **Límites sin cerrar de los arreglos de Accesos** (`FIXES-A1.md`): con Redis caído mucho rato la cola offline de `ioredis` crece hasta
  reconectar; el cliente `sessions` sigue sin tope; un `clientId` que no es ni de `LLAVE_DEL_CLIENTE` ni de `SIN_LLAVE` pasa sin mirar
  la baja. Decididos por Jose y no hechos: MEDIO-2 (IP del limitador), BAJO-6 a BAJO-9.
