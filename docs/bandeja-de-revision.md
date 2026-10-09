# La bandeja de revisión — qué pasa con la cola de quien pierde `delivery.entrar`

Diseño, 08/10/2026. **Nada de esto está construido.** Está escrito leyendo el código tal como
está hoy; cada afirmación de la sección A lleva su fichero y su línea para poder comprobarla.

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

* Con token de **entrega**: `POST /sync/revision/entrega` y `GET /sync/revision/mias?aparato=…`
  (esta última acepta también un token normal de la misma persona).
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
