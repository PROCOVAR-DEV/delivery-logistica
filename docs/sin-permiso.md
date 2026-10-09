# Sin permiso para Reparto

Jose, 08/10/2026: «a los que no tienen permiso Reparto les diga no tienes permiso y que se
dirijan a Accesos, a su inicio con la ruta rápida».

Solo entran a Reparto **ADMINISTRADOR, SUPER ADMIN, DESARROLLADOR y LOGISTICO**. El resto
de roles de Procovar (GERENTE, SUPERVISOR, GESTOR, OPERADOR…) tienen cuenta en Accesos pero
no esta aplicación. (LOGISTICO no estaba entre los siete roles que lista el `CLAUDE.md` de
Procovar: si no existe aún en Accesos, hay que darlo de alta allí.)

## Qué ve la persona

Una pantalla (`/sin-permiso`, `pantallas/acceso/vista/pantalla_sin_permiso.dart`) con:

> **No tienes permiso para entrar a Reparto**
> Reparto es para el personal de logística y la administración. Si crees que es un error,
> pídele acceso a un administrador.

Se llega a ella **desde cualquier pantalla**, también durante la carga inicial, en cuanto una
sola llamada a la API contesta el 403 de abajo. Sin armazón: ni menú ni selector de sucursal.

## Qué hace cada plataforma

| | Web | APK y escritorio |
|---|---|---|
| Salida a Accesos | **Sola, a los 3 s**, con contador visible («Te llevamos al inicio de Accesos en 3 s…») y botón **«Ir ahora a Accesos»** (al instante) | **Nunca sola.** Botón **«Ir a Accesos»**: abre el inicio de Accesos en el navegador del sistema (`url_launcher`) |
| Cerrar sesión | No (Accesos ya tiene la suya) | Botón **«Cerrar sesión»**: el mismo cierre de la cuenta; si hay apuntes sin subir, **pregunta** y dice que salir NO los borra |
| A dónde | `AUTH_URL` + `/` (el inicio de Accesos: allí ve las aplicaciones a las que SÍ puede entrar) | igual |

La web se va con `navegadorProvider` (navegación de verdad, la misma pieza que el login único),
así que se prueba sin navegador. El destino sale de `Entorno.authUrl` (`--dart-define=AUTH_URL`).

## El contrato con el servidor

Cuando la persona no es de uno de esos 4 roles, **CUALQUIER** llamada autenticada a la API de
Reparto contesta:

```
HTTP 403
{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}
```

Es DISTINTO de los otros 403 (alcance de sucursal: sin `codigo`; siguen siendo un `Rechazo`
normal). La app solo se dispara con las tres cosas a la vez: **403**, respuesta de **nuestra
API** (JSON; el 403 de un proxy no vale) y **`codigo == sin_permiso_reparto`**
(`esSinPermisoDeReparto`, `nucleo/red/interceptor_sesion.dart`). Un 401 con ese cuerpo no
cuenta: un 401 es sesión.

## Cómo se detecta y a dónde va

1. `InterceptorSesion.onError` ve el 403 y avisa (`alFaltarPermiso`). Está en los dos clientes
   (`/api` y `/sync`), así que lo ve cualquier pantalla, la bajada y la subida.
2. `Portero.sinPermiso()` pasa a `EstadoDeAcceso.sinPermiso`. **No es `fuera`**: la sesión, la
   base y la cola de la persona siguen abiertas e intactas.
3. `redirigir` manda a `/sin-permiso` desde cualquier ruta. El estado no se abandona solo
   (`_poner` no deja volver a `dentro`/`configurando`): se sale cerrando sesión o entrando de
   nuevo.
4. En la web, `/api/me` también puede traer ese 403 durante el arranque: `EntradaPorAccesos`
   lo devuelve como `SinPermiso` y `arrancar` lo manda a la pantalla **sin pasar por el login
   único** (si no, Accesos devolvería a la persona con la cookie puesta y sería un bucle).

**Sin bucles.** La pantalla no repite la llamada que dio el 403, y el ciclo de sincronización
y el vigía paran (`haySesionParaSincronizar(sinPermiso)` es falso; el vigía solo corre con
`dentro`). Volver de Accesos a Reparto reevalúa porque la persona entra de nuevo (en la web es
una carga nueva de la página; en la APK, cerrar sesión y entrar).

## NO PERDER TRABAJO: la cola — y desde el 09/10/2026, su salida

Un 403 `sin_permiso_reparto` **no es un rechazo del apunte**: es la PERSONA. Convertir su cola
en `rechazado` destruiría trabajo que arregla un administrador dándole el rol.

* Si el 403 llega como respuesta HTTP de `/sync/subida`, sale como `Rechazo` con marca desde
  `_mandarUno` y **nadie resuelve el apunte**: queda `pendiente`, con su ruta y su cuerpo
  intactos (como con un 401, la cola se conserva y espera).
* `Subida._aplicar` tiene una segunda cerradura: si el sync reenvía «No tienes permiso para
  entrar a Reparto.» como rechazo **dentro de un 200**, tampoco se resuelve el apunte.
* Probado en pareja en `test/nucleo/red/sin_permiso_de_reparto_test.dart`: un rechazo normal
  sigue siendo `rechazado`; el 403 con ese `codigo` deja el apunte `pendiente` e intacto.

### El servidor de sync (hecho)

`sync/` responde HTTP 403 con el mismo cuerpo (`{"error","codigo":"sin_permiso_reparto"}`) en
`/sync/subida` y en las demás rutas `/sync/*` si la persona no es de los 4 roles, **sin anotar
nada**: la cola se queda pendiente. La primera cerradura de la app (el 403 HTTP) es la de
verdad. La segunda —el motivo literal «No tienes permiso para entrar a Reparto.» dentro de un
200— ya no la dispara el servidor y queda como defensa. El literal vive en
`api/internal/auth/middleware.go` y `sync/internal/identidad/identidad.go`, y
`app/test/nucleo/red/el_literal_del_sin_permiso_test.dart` lee los dos ficheros y falla si
dejan de coincidir con `fallos.dart`.

`GET /api/me` NO da este 403 (contesta 200 con quién es la persona): el disparador real es la
PRIMERA llamada protegida (la bajada del sync o cualquier `/api/*`). El camino
`quienSoy()` → `SinPermiso` es defensivo.

### Y la salida: la bandeja de revisión

Hasta el 08/10/2026 eso era TODO: la cola se **conservaba** pero **no tenía salida** —sin token
no podía subir y nadie más la veía— salvo recuperar el rol y volver a entrar. Ahora tiene una:
**entregarla a revisión**. El diseño, y en qué se desvió, en `docs/bandeja-de-revision.md`; el
contrato de los endpoints, en `docs/contratos-api.md` §12; el servidor, en `docs/sincronizacion.md` §4.

### La pantalla (hecho, paquete N3)

Está todo: Accesos (`POST /api/auth/entrega`, **lo único desplegado**, `8ba2642`), `sync`, la API, el servicio de la app
(`app/lib/nucleo/sincro/entrega_a_revision.dart`) y la pantalla de `/sin-permiso`. La pantalla son tres piezas:
`app/lib/pantallas/acceso/vista/panel_de_entrega.dart` (`PanelDeEntrega`, `ControlDeEntrega`),
`app/lib/pantallas/acceso/datos/textos_de_entrega.dart` (`TextosDelPanel`: **lo que se dice**, atado por pruebas que
comparan el literal) y `pantalla_sin_permiso.dart`, que monta el panel y trae el «Cerrar sesión» de tres opciones.

**El panel (`PanelDeEntrega`) solo sale en APK y escritorio, y solo si hay algo que contar**: cambios `pendiente`, apuntes
`enRevision` o ya decididos por un revisor. Sin cola, o con cola vacía, **no sale**; en la web **no se monta nunca** (la web
se va sola a Accesos a los 3 s). No navega a ningún sitio: se queda en `/sin-permiso`, y lo único que saca de aquí es volver a
entrar, con el botón de la persona. Lleva, de arriba abajo:

* **Con cambios sin enviar:** «Tienes N cambios sin enviar. No se han perdido ni se han aplicado. Puedes entregarlos a
  revisión: un administrador de tu sucursal los mirará y decidirá si se aplican.», el botón **«Entregar a revisión»**
  (`BotonPrincipal`, con su icono) y debajo «Entregar no aplica nada: tus cambios quedan en revisión hasta que alguien los
  decida.» **La entrega es manual: nada del panel la dispara por su cuenta**, con un toque queda consentida, contada y
  reversible (mientras no se pulse, la cola sigue intacta y subirá normal si devuelven el rol).
* **Lo que dice tras pulsar** (`TextosDelPanel.resultado`, en una región viva para el lector de pantalla): «Entregado: N
  cambios están en revisión. Todavía no se ha aplicado nada.» · «Se entregaron X y quedan Y sin entregar, intactos. …» · «No
  hay nada que entregar.» · o el literal del fallo (tabla de arriba, con «Vuelve a intentarlo en N s.» si el servidor mandó
  `Retry-After`). Si el fallo es **sesión terminada** o **ya tienes permiso**, sale además el botón **«Cerrar sesión y entrar
  de nuevo»**: salir no borra la cola y, al volver a entrar, lo pendiente sube.
* **Una fila por apunte entregado o decidido**, con qué es y en qué está (siguiente subsección), y el botón **«Actualizar
  estados»** (`actualizarEstados()`). Lo que dice: «Sin novedades.» · «N cambios de estado.» · «Hay más entregas de las que caben
  en la lista: puede que alguna ya decidida no se vea todavía.» (el servidor dijo `truncado`) · o el literal del fallo. El panel
  no tiene ningún gesto para quitar de la vista una fila ya decidida.

Pruebas: `test/pantallas/acceso/sin_permiso_test.dart` (+22) y `test/nucleo/cola/cerrar_sesion_con_trabajo_sin_subir_test.dart`
(+1); con 67 mutaciones en copia, todas rojas, entre ellas las 5 de N3 (mostrar el panel en la web, entregar sin pulsar, que
«Salir sin entregar» no avise, que el panel navegue fuera de `/sin-permiso`…) (`G-APP1.md`).

### Cómo se entrega (hecho, `EntregaARevision.entregar()`)

1. **Solo con cola y solo en APK y escritorio.** La web no tiene cola ni base local (`CLAUDE.md`
   §1): `entregar()` devuelve `noAplica` sin pedir nada. Sin apuntes `pendiente`, `nadaQueEntregar`,
   también sin pedir ni un token.
2. **Pide un token de entrega a Accesos** (`POST {AUTH_URL}/api/auth/entrega`, cuerpo
   `{"refresh_token": <el vigente del almacén>}`): 10 minutos, un solo ámbito
   (`reparto.entrega`), **no gasta el refresh y no devuelve otro**. Solo lo da a quien conserva la
   sesión viva, está activo y **de verdad no tiene la llave** (contrato en `contratos-api.md` §12.1).
   Un token que no venga con ese ámbito no se usa.
3. **Manda los apuntes de uno en uno y en orden** a `POST /sync/revision/entrega`, con su propio
   `Dio` y **sin `InterceptorSesion`** (aquel renueva ante un 401 pidiendo el token normal, justo lo
   que NO hay que hacer: `/refresh` le contesta 403). Solo se entrega lo `pendiente`; un `rechazado`
   espera a una persona y un `descartado` ya lo decidió una. Si el token caduca a mitad, pide otro
   **una sola vez** por entrega. Del apunte viaja todo tal cual, **también el `provisional`** (antes la app lo omitía cuando no era un `local-…`: el
   UUIDv7 con el que el Tablero crea una zona lo rechazaba `sync` con 422): `sync` ya acepta también un
   UUID (`reProvisionalDeRevision`, ajuste del 09/10) y la app dejó de omitirlo: el `provisional` viaja siempre que el apunte lo tenga.
4. **Marca `enRevision` con la respuesta del servidor en la mano**, nunca antes: marcar al mandar
   dejaría un apunte que ni sube ni está arriba si la respuesta se pierde. No toca el cuerpo, la
   ruta ni la clave (la huella del servidor es la del original) y **no suelta `nacio_aqui`**.
5. **Nunca da de alta el aparato** (no hay token para eso): un aparato sin alta dice «Este aparato
   no estaba registrado. Pide a un administrador que te devuelva el acceso.»
6. **Un fallo lo deja todo `pendiente`**, intacto y reintentable: sin red, 429, cupo, un 401 de
   Accesos o de `sync`. Si lo que se pierde es la RESPUESTA (el servidor guardó y el
   aparato no se enteró), el reintento recibe `repetido` —misma clave, misma huella— y no duplica; y aunque entretanto un revisor
   haya aplicado el primer apunte, la app ya **no reescribe los `local-…` de los dependientes pendientes** (`resolverRevision`
   pasa `reescribirApuntes: false`), así que el reintento no choca con `409 huella_distinta` (hallazgo R3 de la auditoría final). La cola de una persona **no sale con la sesión de otra** (la misma cerradura
   de `Subida`).

Lo que cuenta el servicio a la pantalla (`ResumenDeEntrega`): cuántos entregados, cuántos siguen sin
entregar y el literal de lo que falló. Los literales que ya existen en el código
(`TextosDeEntrega`, `entrega_a_revision.dart`):

| Cuándo | Qué se le dice |
|---|---|
| Accesos `409 tiene_permiso` | «Ya tienes permiso: cierra sesión y entra de nuevo.» |
| Accesos `401` / sin sesión guardada | «Tu sesión terminó. No se puede entregar. Tus cambios siguen en este aparato.» |
| Sin red | «Sin conexión con el servidor. Tus cambios siguen en este aparato: vuelve a intentarlo.» |
| Aparato sin alta (`404 aparato_no_registrado`) | «Este aparato no estaba registrado. Pide a un administrador que te devuelva el acceso.» |
| Cola de otra persona | «Estos cambios son de otra persona. Entra con su cuenta para entregarlos.» |
| Accesos `403 sin_sucursal` | «Tu cuenta no tiene una sucursal asignada. Pide a un administrador que te la asigne; tus cambios siguen en este aparato.» |
| Accesos `429 rate_limited` / `sync` `429` | «Has pedido demasiadas entregas seguidas. Espera un momento y vuelve a pulsar; tus cambios siguen en este aparato.» (con el `Retry-After` si lo hubo) |
| Un token que `sync` no acepta | «El servidor no aceptó la entrega. Inténtalo más tarde; tus cambios siguen en este aparato.» |
| `422`, `409 huella_distinta` por apunte | El literal del servidor; ese apunte sigue `pendiente` y los demás siguen |

### Qué ve la persona en cada estado

El estado vive en la fila local del apunte (esquema Drift 7, `app/lib/nucleo/base/tablas/aparato.dart`) y lo pinta el panel con
`TextosDelPanel.estadoDe` (`textos_de_entrega.dart`). Cada fila empieza por **qué es el apunte, dicho con palabras** y sacado de
la ruta, que es lo único que lo dice: «Resultados de entrega de una ruta», «Parada quitada de una ruta», «Ruta nueva», «Ruta
eliminada», «Cierre de una ruta», «Cambio en una ruta», «Pedido movido en el tablero», «Ruta armada desde una zona», «Cambio
en una zona del tablero» o, si no es ninguna, «Un cambio».

| Estado local | Qué guarda | Lo que lee la persona |
|---|---|---|
| `pendiente` | Sigue en la cola; sube sola si recupera el rol | No tiene fila: cuenta en el «Tienes N cambios sin enviar» |
| `enRevision` | `revision` (id de la entrega) y la hora de entrega (`resueltoAt`). **No sube, no cuenta en «N sin subir», conserva `nacio_aqui`, retiene el `completed` de su ruta, y cuenta antes de olvidar a la persona** | «Entregado a revisión el 8/10, 14:32. Todavía no está aplicado: un administrador de tu sucursal tiene que revisarlo.» |
| `enRevision` con `motivoRevision` | El reparto no pudo aplicarlo; **sigue en revisión, NO es `rechazado` local** (un `rechazado` ofrecería «Reintentar» y «Descartar» a la persona sobre algo que decide otra) | «No se pudo aplicar: *<literal del reparto>*. Sigue en revisión.» |
| `aplicado` con `revisadoPor` | Quién y cuándo; el `local-…` pasa a ser el id real; `motivo` solo si algo «salió con menos» | «Aplicado por Marta Pérez el 9/10, 9:10.» (sin nombre: «un administrador») |
| `descartadoPorRevisor` | Quién, cuándo y `motivoRevision` (el motivo escrito); suelta `nacio_aqui`; **se queda a la vista, no se borra** | «Descartado por Marta Pérez el 9/10: *<motivo>*.» (con el día, sin la hora) |

Un `aplicado` sin `revisadoPor` (lo subió la vía normal) y los `rechazado` y `descartado` de siempre **no salen en este panel**: no
son de la revisión (`estadoDe` devuelve nada para ellos). **«N cambios sin enviar» cuenta solo los `pendiente`**: un `enRevision` no es «sin
subir» (ya está arriba), por eso el menú de cuenta y «salir con el gesto» no se tocaron. Lo que SÍ hace es avisar antes de **olvidar
una copia** de la persona (`PersonaEnElAparato.enRevision`): ese apunte local es lo único que le dice qué entregó y qué se hizo
con ello.

Cómo se enteran estos estados: el botón «Actualizar estados» y **el ciclo normal**, que consulta `GET /sync/revision/mias` entre
subir y bajar **solo si hay algo `enRevision`**, sin que un fallo tumbe la bajada. No hay sondeo ni aviso en vivo. Si más tarde
devuelven el rol: se entra como siempre, los `pendiente` suben solos y **los `enRevision` no se reenvían** (`lote()` solo devuelve
`pendiente`); si `sync` contesta `en_revision` a una subida, la app lo entiende (`EstadoResultado.enRevision`) y no lo toma por
rechazo.

### Qué NO está en la web

Nada de esto. La web no tiene cola, ni base local, ni botón de entregar, ni estados de entrega: quien pierde el
rol sigue yendo a Accesos a los 3 s y su último gesto salió rechazado con el literal del 403 (no hay nada que
conservar). **Lo único que la web tiene de la revisión es la bandeja del REVISOR** (`/revision`), que es un buzón
de oficina y no una cola: la ven ADMINISTRADOR, SUPER ADMIN y DESARROLLADOR, y llama a `sync` con el token de
`/api/me` como Bearer explícito, sin cookie (`docs/contratos-api.md` §12.4); y cerrar sesión solo en el navegador la corta (401 en
`sync`, `contratos-api.md` §12.2).

### Si cierra sesión antes de entregar: la cola se queda VARADA

«Cerrar sesión» revoca el refresh en Accesos (sin red queda apuntado y se revoca al volver, `RevocadorDeCierres`), y ese hueco
**jamás se usa para entrar ni para entregar**. A partir de ahí no hay token de ningún tipo: `POST /api/auth/entrega` contesta 401
(`refresh_revocado`) y la cola sigue en el fichero de esa persona (`conexion/nombre.dart`) **sin salida** hasta que recupere el
rol y vuelva a entrar; entonces los `pendiente` suben solos. Es el riesgo 10 del diseño y **no se resuelve del todo**, se mitiga con
el cartel de «Cerrar sesión», que con cola (`cuantosPendientes() > 0`) pregunta con **tres opciones**
(`pantalla_sin_permiso.dart`, textos en `TextosDelPanel`):

> **Queda trabajo sin subir** — Hay N apuntes sin subir al servidor. Salir NO los borra: se quedan en este aparato. Puedes
> entregarlos a revisión antes de salir: un administrador de tu sucursal los mirará y decidirá si se aplican. Si sales SIN
> entregar, quedan varados en este aparato: nadie los ve y solo subirán si te devuelven el acceso a Reparto y vuelves a entrar.

* **«Entregar a revisión y salir»** (el botón principal, con su icono): entrega **y solo sale si TODO quedó entregado**; si algo
  falla, se queda en la pantalla con el motivo a la vista en el panel y el trabajo donde estaba.
* **«Salir sin entregar»**: sale, y el texto de arriba ya avisó de que la cola queda varada.
* **«Me quedo»**. Cerrar el cartel sin contestar (tocar fuera, Escape) **también es quedarse**.

Sin cola, «Cerrar sesión» sale sin preguntar. **Fuera de alcance, a propósito:** entregar desde el login o con la sesión ya cerrada
(opción 4 de B.1) y retirar una entrega. Quien ya cerró sesión sin entregar no puede entregar.

### La entrega NO sustituye a la renovación

El token de entrega no es un token normal: abre **solo** `POST /sync/revision/entrega` y `GET /sync/revision/mias`
(en la API y en el resto de `sync` no entra: 401 en la API, 403 en `sync`). Y **no renueva nada**: quien no tiene la
llave sigue recibiendo en `/api/auth/refresh` el `403 {"error":"sin_permiso","codigo":"sin_permiso"}`, que **no
rota el refresh** ni lo alarga. Por eso el plazo para entregar es el del refresh —**hasta 30 días desde la última
renovación con éxito** (`SEGUNDOS_REFRESH`, `apk-tokens.ts`)— y se acaba aunque la persona siga entregando. Desde
`8ba2642`, ese 403 de `/refresh` significa de verdad «tienes sesión y no tienes llave»: una sesión **revocada** o una
**baja** sin llave reciben 401 (`puertaDeRenovar` mira la sesión y la baja antes de la llave) y por tanto no entregan.

## Accesos también lo dice: en el login y en el refresco

Accesos (`/api/auth/token` y `/api/auth/refresh`) contesta
`403 {"error":"sin_permiso","codigo":"sin_permiso","message":"No tienes permiso para entrar a
Reparto."}` si la cuenta no tiene `delivery.entrar` (`esSinPermisoDeAccesos`,
`nucleo/identidad/renovador.dart`; la marca vale en `error` o en `codigo`). No es la de la API
(`sin_permiso_reparto`) y no se confunden.

* **Login (APK y escritorio).** `MotivoDeAcceso.sinPermiso`, como `sin_sucursal`: aviso ámbar
  con el mensaje, «Reparto es para el personal de logística y la administración…» y el botón
  **«Ir a Accesos»** (el inicio de Accesos, en el navegador del sistema). **No se deja nada**:
  ninguna sesión guardada, el portero no se mueve, la cola de nadie se toca. El formulario se
  queda, para probar con otra cuenta.
* **Refresco (el token se renueva al sincronizar).** La persona perdió el permiso a media
  jornada. `Renovador` avisa al portero (`sinPermiso`) y lanza un `Rechazo` con la marca de
  «sin permiso», **no** `SesionMuerta`: la sesión no se tira, el par se queda (con él se revoca
  al cerrar sesión), y **la cola y la base se conservan**. Lo ven igual el interceptor
  (peticiones), el ciclo (sincronizar) y el arranque (`Arranque.sinPermiso`, con la sesión).
  «Cerrar sesión» sigue preguntando si hay apuntes sin subir. Un 401 al renovar sigue siendo
  sesión muerta. (Un 403 al renovar SIN la marca sigue como hasta hoy: `FalloDeRed`.)
* Pruebas: `test/nucleo/identidad/sin_permiso_al_renovar_test.dart` y
  `test/pantallas/acceso/sin_permiso_en_el_login_test.dart`, las dos con dos apuntes pendientes
  en la cola.

## De dónde se sale

* `Portero.sinPermiso()` estando `fuera` **se ignora**: un 403 tardío de una petición que iba en
  vuelo cuando se hizo `salir()`/`murio()` no resucita la pantalla.
* De `sinPermiso` **solo se sale SALIENDO**: `salir()` y volver a entrar desde el acceso (en la
  web, recargando). `entro()` estando en `sinPermiso` no lleva a `dentro`: se traga en silencio,
  **por diseño** (fijado en `test/navegacion/portero_sin_permiso_test.dart`).
* `AUTH_URL` vacío (`--dart-define=AUTH_URL=`) cae en `https://auth.procovar.cloud`; vacío
  mandaría la web a `/`, es decir a sí misma, cada 3 s.

## Accesibilidad de la web

La salida sola se anuncia una vez (`Semantics(liveRegion: true)`: «Te llevamos al inicio de
Accesos en unos segundos»); el contador visual va en `ExcludeSemantics` para que el lector de
pantalla no diga «3, 2, 1». El botón «Ir ahora a Accesos» se queda.

## Cómo se le QUITA el acceso a alguien (y por qué la membresía no basta)

Para que alguien caiga en esta pantalla y pueda **entregar su cola**, en Accesos hay que **cambiarle el ROL a la persona**
(Personas → `cambiarRol`), a uno sin la llave `delivery.entrar`, y **dejarle la sesión viva**. **Vaciar su membresía no basta**: la
prueba de punta a punta (`QA-E2E.md`, hallazgo F1) vio que `PUT /api/rbac/orgs/<org>/members/<miembro>/roles {"roleIds":[]}` **no
quita `delivery.entrar` si el rol por defecto de la persona la trae**: su token siguió con `entradas` y `roles:["LOGISTICO"]`, y
`/api/auth/refresh` seguía dando 200. Con el rol cambiado, `/refresh` da `403 sin_permiso`, `/api/auth/entrega` da 200 y la app
cae aquí. Si en cambio se le **revoca la sesión**, se le da de **baja** o **cierra sesión**, `/entrega` da 401 y no entrega nada
(es lo correcto; lo de cerrar sesión es el riesgo 10). El runbook completo, en `docs/despliegue.md` §4-bis.

Dos cosas más que la misma prueba dejó claras: quien tiene un token de entrega vivo (10 min) y luego pierde la sesión por un corte
de Accesos recibe 401 en `sync`; y una persona que sigue siendo ADMINISTRADOR de su sucursal ve su propia entrega en la bandeja pero
no puede decidir sobre ella (`403 es_lo_tuyo`).

## Cómo se da acceso

En Accesos se le da a la persona el rol **LOGISTICO** (o ADMINISTRADOR / SUPER ADMIN /
DESARROLLADOR). No hay nada que tocar en Reparto: al volver a entrar, la API deja de contestar
el 403. Si la sucursal de la persona no está dada de alta en Reparto, es otro 403 (sin
`codigo`) y se trata como siempre.

## Sesión cerrada o permisos cambiados en Accesos — 08/10/2026

Jose: «si cierro sesión o me cambian un permiso en Accesos, que se refleje en todas las
aplicaciones, sin polling: para eso hay SSE». La API de Reparto escucha los avisos de Accesos
y empuja por `/api/eventos` un evento `sesion-invalidada` con `{"tipo":"sesion-cerrada"}` o
`{"tipo":"permisos-cambiados"}`, y cierra esa conexión. El cliente lo pasa por el mismo
stream como `sesion-invalidada:<tipo>` (`nucleo/red/eventos.dart`); el embudo
(`avisosDelServidorProvider`) lo corta —no llega al vigía ni a las pantallas— y se lo da al
portero. Un `data` roto, vacío o con un tipo desconocido es `sesion-cerrada`.

### Qué ve la persona

| | Web | APK y escritorio |
|---|---|---|
| Al llegar el aviso | **Al instante** el portero pasa a `fuera` (`Portero.sesionInvalidada`) y la puerta dice «Tu sesión se cerró en Accesos. Vuelve a entrar.» (o «Tus permisos cambiaron. Vuelve a entrar.») con el botón **«Entrar ahora»**; a los 3 s se va sola a Accesos. | **No se echa a nadie por el aviso.** Se intenta renovar el token YA (`Portero.renovarPorAviso`) y decide el refresco. |
| Refresco 401 (Accesos cerró la sesión) | — | A la puerta con «Tu sesión se cerró en Accesos. Vuelve a entrar.» y el formulario debajo. |
| Refresco 403 `sin_permiso` | — | Pantalla de «sin permiso» (el `Renovador` ya avisa al portero). |
| Refresco 200 (p. ej. cambiaron permisos pero sigue entrando) / sin red | — | No pasa nada. Sin red lo recoge el primer ciclo al volver la señal. |
| Cola y base local | no hay | **No se tocan jamás** (`murio` solo cambia de copia). |

Dos eventos seguidos son **una** salida y **una** navegación: el segundo llega con la persona
ya `fuera` y se ignora (conserva el mensaje del primero). Un 401 de una petición de la web (la
cookie ya era inválida) ya llevaba al login —`InterceptorSesion` → `murio` → puerta → Accesos—,
sin mensaje y sin esperar; queda atado en `test/navegacion/portero_sesion_invalidada_test.dart`.

El transporte de la web (`eventos_web.dart`) hace `close()` del `EventSource` en cuanto llega
el evento (si no, el navegador reconecta solo contra una sesión muerta) y cierra su stream:
no reintenta. Solo se prueba en Chrome (ver el encabezado de `test/nucleo/red/eventos_web_test.dart`).

### Al recuperar la conexión

El aparato se entera solo: al volver la red el vigía lanza un ciclo y el ciclo **renueva
primero** (`ciclo.dart`, paso 1); un refresco cerrado en Accesos da 401 → sesión muerta → puerta.
Ya era así; queda atado en `test/nucleo/identidad/el_aparato_se_entera_test.dart` (grupo B).

### Cerrar sesión sin conexión: «pendiente de revocar»

Antes, sin red el `POST /logout` fallaba, se registraba un aviso y el refresco quedaba vivo en
Accesos hasta 30 días sin reintento. Ahora `ServicioDeAcceso.salir`, **antes** de borrar la
sesión local, guarda el refresco aparte (`RefrescoPorRevocar`: `sub` + `refresh`, en el mismo
almacén que la sesión —llavero en Android, fichero cifrado en Linux—, clave `reparto.por_revocar` /
fichero `por_revocar.caja`). `RevocadorDeCierres` lo presenta a `/logout`:

* al arrancar (`Portero.comprobar`), al entrar (`entro`: entrar prueba que hay red) y cuando
  vuelve la red (el portero escucha el aviso de red mientras quede algo pendiente);
* se borra el hueco **solo** si el servidor confirma: 200, o 401 de nuestro servidor («ya
  cerrado»). Sin red, 5xx o cualquier otra cosa → sigue pendiente;
* **jamás autentica**: `leer()`, el arranque y el renovador no lo miran; solo viaja en el cuerpo
  de `/logout`. En la web no existe (su sesión es la cookie).
