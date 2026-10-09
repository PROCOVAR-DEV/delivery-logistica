# delivery-logistica — lo que hay que saber antes de tocar nada

Este fichero se carga solo al abrir cualquier cosa de este repo. El de
`procovar/CLAUDE.md` sigue mandando sobre lo del servidor y las credenciales;
esto es lo de **este** proyecto.

---

## 1. LA REGLA QUE MANDA SOBRE TODAS: qué trabaja sin conexión y qué no

Son **tres** formas de la misma aplicación y **no se comportan igual**. Esto no
es un detalle de implementación: es la razón de existir del proyecto, y Jose lo
ha tenido que repetir tres veces.

### Rutas: el histórico se fija al completar — Jose, 06/10/2026

Una ruta planificada o en curso se puede editar y eliminar, incluso con cero paradas
cargadas o con marcas provisionales de entrega/devolución. **Una marca no completa la
ruta.** El bloqueo anterior por «N paradas cerradas» impedía borrar una ruta de prueba
en curso con cero paradas visibles y un devuelto por `ultima_ruta_id`.

Los estados de las paradas se marcan **sólo al pulsar «Marcar como completada»**.
Antes de ese gesto no hay cierre editable; siempre se revisan las paradas en su
hoja antes de confirmar (incluidas marcas anteriores).

**Cerrar con rechazo parcial (07/10/2026, incidencia 1 de Amado).** EN LA WEB, si el
servidor guarda unas paradas y rechaza otras (409 con `aplicados` y `rechazados`), lo
guardado vale, el rechazo se dice con su motivo literal y se puede completar. Un 409 en
que no se guardó NINGUNA es rechazo total y no deja completar. **En la APK y el
escritorio NO**: el sincronizador (`sync/internal/reparto`) convierte cualquier 4xx en
un rechazo del apunte entero sin leer `aplicados`, así que una hoja con una parada
rechazada queda `rechazada` en la bandeja y retiene el `completed` hasta que una
persona decida (Reintentar/Descartar). Es deliberado de momento y está a la vista.

**La causa de aquel 409 NO está demostrada.** El 07/10/2026 el pedido rechazado
(`PTB25-261005-1480`) tenía `route_id` y `ultima_ruta_id` NULOS en el servidor, o sea
que nunca estuvo en esa ruta allí; el servidor decía la verdad y la hoja del cliente
tenía una parada que el servidor no conocía. Qué la metió en la hoja queda sin explicar.
Por eso el cierre ahora, además, reconoce las paradas por `route_id` y por
`ultima_ruta_id` sólo si ya soltaron su ruta con un resultado (devueltos y cancelados),
y el renglón de log del cierre rechazado dice `route_id`, `ultima_ruta_id` y
`branch_id` del pedido: la próxima vez habrá con qué diagnosticarlo.

**Quitar una parada de una ruta planificada** (`DELETE /api/routes/{id}/stops/{orderId}`)
pone `route_id` Y `ultima_ruta_id` a NULL. Dejar `ultima_ruta_id` la convertía en
«parada fantasma»: seguía en la hoja, en los totales y con su botón de quitar.

Sólo `completed` impide modificar o borrar: incluye nombre, vehículo, estado y cierre.
Se conserva como histórico. Los resultados de la cola nativa se mandan **antes** de
completar; un cierre que llegue después se rechaza con su motivo visible, sin borrar
el apunte silenciosamente. Una hoja pendiente o rechazada retiene el completed de
su misma ruta en cada ciclo de subida, sin detener rutas independientes. El completed
local optimista no acredita el servidor; un rechazo exige resolver con conexión/web
y decidir explícitamente en la bandeja (Reintentar/Descartar). No cambiar los pedidos
entregados a pendientes al borrar
una ruta viva: el resultado del pedido sigue valiendo y evita repartirlo dos veces.

### La web NO trabaja sin conexión. Nunca.

> «el trabajo sin conexion es solo para las aplicaciones cojone la web siempre va
> a estar en internet»
> «la web siempre va a tener el internet por q esta en la nube eso es para la apk
> y la desktop quitame eso de la web»

En la web **no se enseña nada** del aparato de sin-conexión: ni «Configurando
Reparto», ni el botón de traer o entregar el día, ni la franja de «trabajando sin
conexión», ni el aviso de que el aparato no guarda la sesión. Se entra y ya se
está dentro.

### Y NO TIENE BASE LOCAL. Eso también es la regla, no un detalle

Esto estuvo escrito a medias y costó caro. Decía que la base local «sigue ahí por
dentro, como una caché de la que nadie habla». **Mal.** Jose, 16/09/2026:

> «la web es para eso, el desktop y las apks tienen su propia base de datos para
> trabajar sin conexión; la web siempre está con conexión porque está en el
> servidor»
> «la web siempre está en vivo porque saca de la base de datos de la nube, no de
> una extra»

La base local existe **para la APK y el escritorio**, que son los que se van sin
señal. El sincronizador está para eso: subir lo que se hizo sin conexión y dejar
el aparato al día para el siguiente día sin señal. **La web no necesita nada de
eso y no debe tenerlo.**

Lo que pasa si se le deja una caché, y pasó: la web guardó su cola, la cola se
atascó, el tablero **se negó a bajar durante hora y media para no pisar lo que no
había subido**, y la pantalla enseñaba una foto vieja mientras el teléfono subía
sin problema. Refrescar no hacía nada. Una caché en un navegador sólo puede
mentir: no hay ningún caso en el que gane algo.

**La prueba de si algo sobra en la web:** ¿sirve de algo a alguien que tiene
internet ahora mismo? Si la respuesta es «le guarda lo que hizo por si se cae la
red», fuera de la web.

Lo que sí se dice en la web es que **ahora mismo** no hay conexión, si la pierde
a mitad. Lo que se quita es el aparato de **prepararse** para no tenerla.

### La APK de Android y la de escritorio SÍ, y tienen que hacerlo perfecto

> «las apk la de androide y la de desktop»

Ahí está todo: la configuración inicial con su porcentaje, traer el día,
entregarlo, trabajar la jornada entera sin señal, y que la sesión sobreviva a
cerrar la aplicación. **Es su razón de ser y no se negocia.**

La regla de la sesión, de `docs/identidad.md`:

> Para entrar hace falta conexión. Una vez dentro, no.

Y su contrapartida, que hay que tener presente al tocar esto: el par de tokens
dura 30 días (el de acceso, 15 minutos). Pasados ésos, o si Accesos rechaza la
renovación, la sesión muere y se vuelve a la puerta. Quien sea dado de baja deja
de entrar **en cuanto su aparato tenga señal**, no antes.

### Cómo se decide, en una pregunta

**¿Esto le sirve a alguien que abre un navegador con internet?** Si la respuesta
es «le explica algo que en su caso nunca pasa», fuera de la web.

---

## 2. El patrón se sigue SALVO donde se equivoca

`/mnt/datos/Work/procovar/delivery` (Next) es el patrón y casi siempre tiene
razón: sus comentarios largos guardan incidentes de verdad que costaron dinero.
Pero copiarlo con los ojos cerrados también trae sus fallos.

Cuando nos separemos del patrón, **se escribe por qué en el código**, con el caso
concreto. Ya hay tres así:

- **Reportes SÍ va en el menú.** El Next no lo tiene en su barra lateral y sólo
  se llega desde las acciones rápidas del Panel. Copiado fielmente, Jose no
  encontró la pantalla.
- **Un tipo de vehículo sin costo por km se deja VACÍO, no en cero.** El Next
  escribe `0`, y un cero guardado se lee como «el kilómetro es gratis»: un número
  creíble y equivocado. Un hueco se ve y se rellena.
- ~~**Los avisos del armador son aviso, no bloqueo.**~~ **REEMPLAZADO el 07/10/2026
  por Amado** (`docs/incidencias-reparto.md`, punto 6): el domicilio ya es un servicio
  que se cobra y dejar entrar cualquier pedido es una vulnerabilidad. Ahora el armador
  BLOQUEA, y lo mismo la lista de disponibles y el tablero: sólo entra lo **facturado y
  que cuadre** (`factura_estado = 'igual'`; `cambiado` NO entra —es la regla vieja de
  Jose, «en el camión sólo sube lo que cuadra con la factura», y Amado no pidió
  cambiarla—), con **domicilio cobrado** (`factura_domicilio > 0`) y **cotizado en
  Entrega** (`pedido_costo` no nulo). Lo que se rechaza se nombra por su número de
  operación. Con los datos reales del 07/10/2026, de 1.914 pedidos repartibles sólo 29
  cumplían las tres cosas (64 con domicilio cobrado, 33 cotizados): la lista de
  disponibles se queda corta hasta que Entrega cotice más, y es lo que Amado pidió. El argumento de antes (657 de 686 sin costo el 14/09) era cierto
  mientras la APK de Entrega no estaba encendida; si vuelve a haber pedidos sin costo
  en masa, la respuesta es cotizarlos en Entrega, no abrir la puerta. **El «conduce» de Amado
  es el NÚMERO DE OPERACIÓN de la factura** (`orders.operation_number`; aclarado por
  Jose el 07/10/2026): no hay dato ni columna aparte, y por eso todo rechazo nombra al
  pedido por ese número. Un cobro a domicilio que sale como conduce se identifica con él.
- **El estado de cada parada se pregunta AL COMPLETAR la ruta, no después.** El
  Next deja el botón `Cierre` vivo sobre una ruta ya completada, y ahí se
  equivoca: cerrar una ruta *es* cuadrar lo que bajó del camión, así que la
  pregunta va antes, no después. Jose, 17/09/2026, viendo el cierre ofrecido
  sobre una ruta cerrada: «ese estado se pone cuando están en ruta, no
  completados; ahí el cierre ya viene con el estado de cuando le van a dar a
  completado, es que se pregunta ese estado». En una ruta `completed` el cierre
  se mira y no se toca: ni botones de marcar apagados, ni botón de guardar.
  `ModoDelCierre` en `app/lib/pantallas/rutas/vista/cierre_de_ruta.dart`.

---

## 3. Pedir un tope y no comprobar el resultado

**En un día cazamos tres veces el mismo fallo**, y por eso está aquí:

1. La bajada del aparato se quedaba en **2.000 clientes clavados** de 8.034: el
   servidor servía `LIMIT 2000` sin desplazamiento y marcaba `truncado`, y la
   tanda siguiente pedía exactamente lo mismo.
2. El barrido del espejo pedía `limit=5000` y **no miraba cuántos venían**.
   PEDIDO corta sin decirlo: **2.284 pedidos perdidos** en una sola ventana, con
   200 OK.
3. `POST /api/admin/recompute` pedía 5.000 de una ventana de 30 días que hoy son
   ~13.000. **Ya no se lo calla** (21/09/2026): el tope es `TopeDelRecosteo` para poder
   compararlo, y si vuelven justo esos 5.000 la respuesta lleva `truncado` y un aviso que
   dice cuántos días reducir. Paginar no se puede —`/integration/orders` no da cursor—; lo
   que sí se hace es partir la ventana en tramos, y eso ya lo hace `internal/espejo`, que
   es quien barre el histórico. Pruebas en pareja (avisa cuando toca y **no** avisa cuando
   no) en `api/internal/api/sync_tope_test.go`.

La regla: **si pides un tope, comprueba si lo alcanzaste**, y si no puedes seguir
paginando, dilo con un aviso que nombre lo que se quedó fuera. Un truncamiento en
silencio es el fallo que más caro sale aquí, porque no se ve.

Y su pariente: **una respuesta vacía no es una respuesta buena.** Un catálogo de
Ventra vacío es un ERROR, no «no hay productos»: una base caída devuelve `[]` sin
error.

---

## 3-bis. Dos preguntas sobre lo mismo que se separan sin que salte nada

El 17/09/2026 el tablero de La Habana decía **«Sin colocar (722)»** encima de una
lista de **293**. Ni un error, ni una pantalla en blanco, ni un tirón: sólo un
número 429 unidades más alto de lo real. A `ContarPedidosSinColocar` le faltaba
`AND NOT o.archivado`, que `ListarPedidosSinColocar` tenía desde el 15/09. Tres
días así. Encima, el comentario que había sobre el contador ya lo avisaba —«tiene
que ser el mismo o dice 358 encima de una lista de 120»— y no sirvió de nada,
porque **un comentario no falla**.

La regla: cuando dos consultas tienen que contestar lo mismo —una lista y su
contador, un total y su detalle, un aviso y lo que cuenta—, **hay que atarlas con
una prueba, no con un comentario**. Está hecho para ésta en
`api/internal/store/contador_y_lista_test.go`, que compara el `WHERE` **y** el
`FROM` con sus `JOIN` (un `JOIN` filtra igual que un `WHERE`; que se escriba en
otra línea es cosa de SQL, no del contrato).

Lo que esa prueba **todavía no cubre**, y hay que saberlo: los parámetros se
copian a mano en Go (`api/internal/api/tablero.go`, al armar
`ContarPedidosSinColocarParams`). Quitar ahí un `Municipio:` deja toda la suite en
verde y el número vuelve a mentir.

---

## 3-ter. Una respuesta que se pide UNA vez sobre algo que cambia después

En la APK la base sobrevive, así que al pintar una pantalla los datos ya están.
**En la web la base es en memoria y nace vacía en cada carga**, y el ciclo la
llena un segundo más tarde. Ahí, un `FutureProvider` —una sola respuesta, la del
instante en que se pinta— se queda **congelado en el peor momento posible**.

Lo que se veía el 17/09/2026 en `/orders`: la cabecera diciendo «299 pedidos», el
pie diciendo «Mostrando 1-50 de 299», y en medio «Esta pantalla no se ha
descargado todavía». El total y la página eran `Stream` y se enteraban; el cartel
no. Lo mismo en Rutas, en los desplegables de filtros de Pedidos y en la lista de
camiones del Tablero — **cuatro sitios, el mismo patrón**.

La regla: **lo que se pinta y puede cambiar cuando llega la bajada va por
`Stream`**, no por `Future`. `RegistroDeFrescura.mirar` para la frescura, y
`tableUpdates` para lo que sale de una tabla. `seDescargo` sigue ahí para decidir
en seco, donde no hay nada que repintar.

Y la prueba que lo caza tiene una forma concreta, porque las que había no valían:
**montar con la base VACÍA y sembrar DESPUÉS, sin volver a montar la pantalla.**
Sembrar en el `setUp` es justo el caso que un `Future` resuelve bien. Moldes en
`app/test/pantallas/pedidos/llega_la_bajada_test.dart` y su gemelo de rutas.

---

## 3-quater. El proxy se queda con `/api` y con `/sync` antes que la aplicación

En el servidor, Traefik reparte por camino, y lo suyo no llega nunca a la web:

```
Host(`reparto.procovar.cloud`) && PathPrefix(`/api`)   -> el reparto
Host(`reparto.procovar.cloud`) && PathPrefix(`/sync`)  -> el sincronizador
Host(`reparto.procovar.cloud`)                         -> la aplicación
```

La pantalla de Sincronización vivía en `/sync`. Por el menú funcionaba —eso lo
resuelve el enrutador dentro del navegador, sin pedirle nada al servidor— y por
eso nadie lo vio: **el único camino que falla es recargar ahí o abrir el enlace**,
y entonces contesta el sincronizador con un `401` que no tiene nada que ver con la
aplicación. Movida a `/sincronizacion`; el prefijo no se toca, que es la dirección
que ya usan las APK instaladas.

Y es prefijo de **cadena, no de segmento**: `PathPrefix(/sync)` atrapa
`/sync-estado` igual que `/sync`. Lo vigila
`app/test/navegacion/contrato_registro_test.dart`.

---

## 3-quinquies. Quitar un aviso de la web deja un agujero que hay que tapar

El 17/09/2026 se quitaron de la web, y bien quitados, el sello «Datos de las
10:36», el «N sin subir», el «Visto por última vez a las…» y el «conecta y espera
a que suba» de cerrar sesión. Todos hablan de **tu copia** y de **tu cola**, y en
un navegador no hay ninguna de las dos.

Pero ese «N sin subir» era lo único que delataba un gesto que no llegó. Sin él: la
tarjeta se mueve en la pantalla, el servidor dice que no, y **no se entera nadie**
hasta que alguien recarga y la ve volver a su sitio.

La regla: **en la web, lo que el servidor rechaza se dice, y con su motivo
literal.** «Ese pedido ya va en otra ruta» le dice a alguien qué hacer; «no se
pudo guardar» no le dice nada.

Y la trampa de al lado, que casi sale peor que el agujero: el primer intento fue
esperar al ciclo tras cada gesto y mirar si la cola quedaba vacía. **Eso salta en
CADA movimiento**, porque un apunte está legítimamente pendiente ese instante. Un
aviso que sale siempre deja de leerse, y entonces tampoco se lee el día que
importa. Lo único inequívoco es un apunte **rechazado**. Por eso las pruebas de
esto van en pareja: una que el aviso salga cuando toca, y otra que **no salga**
cuando no.

---

## 3-septies. Un 401 que el cliente no puede ver se escribe ENTERO en el servidor

El 29/09/2026 a las 21:30:50 UTC, `GET /api/eventos` contestó 401. Lo que ese
rechazo dejó escrito fue un `motivo` —«no viene token», «está caducado», «la firma
no cuadra»…— y nada más.

**No dice de quién.** Y ésa era la única pregunta, porque las dos puertas de esta
casa duran cosas distintas —la cookie de la web, SIETE DÍAS
(`duracionDeLaSesionWeb`); el token de la APK, QUINCE MINUTOS— y el arreglo no se
parece en nada. **La causa quedó sin concluir**: no se pudo decidir cuál de los
dos clientes fue el rechazado.

Y encima, para leer bien ese registro hay que saber dos cosas que no están en él:
**la hora es la del FINAL de la petición** (`RegistrarPeticiones` escribe
`time.Since(inicio)` después del manejador), así que a un renglón de `299999ms`
hay que restarle cinco minutos para saber cuándo empezó; y **la hora es UTC**, no
la del portátil. Leídas como horas de inicio, las mismas cuatro líneas cuentan una
película distinta y falsa.

La regla: **cuando el cliente no puede ver el código de una respuesta, el renglón
del servidor es la única versión de los hechos que va a existir, y tiene que
bastarse solo.** `EventSource` no da el código —lo único que la web ve es
`readyState == CLOSED`, que igual es un 401 que un `Content-Type` equivocado—, así
que un `motivo` suelto ahí no es medio dato: es ninguno.

Lo que se escribe está en `api/internal/auth/rastro.go` (`RastroDe`) y va en los
dos sitios que rechazan sesión, `Exigir` y `servirEventos`: `via` (cabecera = APK
y escritorio, cookie = web), `cookies_token` (**dos cookies `token` a la vez es una
avería**, no una sesión vencida), `vida` = `exp − iat` —`168h0m0s` es la web,
`15m0s` es la APK—, `caduco_hace` —dos segundos es un reloj desfasado, tres horas
es que nadie renovó— y el `agente` recortado.

Y su mitad prohibida, atada por `TestElRastroNoEnsenaElToken`: **el token no sale
ahí ni recortado, ni su firma, ni el `sub`.** Un registro acaba pegado en un
correo y en un chat; un token de siete días pegado en un chat es una sesión
regalada.

Lo demás lo atan `TestElRastroSeparaLaWebDeLaAPK`,
`TestDosCookiesTokenYLaBuenaEsLaSegunda` y `TestElRastroDiceCuandoNoVinoNada`, en
`api/internal/auth/rastro_test.go`.

---

## 4. Lo que no puede pasar nunca

- **Nada se descarta en silencio.** Un apunte rechazado se queda a la vista con
  su motivo hasta que una persona decida. Una colección que no bajó se dice, y se
  dice **qué se rompe sin ella**. Si algo falla, la pantalla **no se queda
  verde**.
- **El alcance sale de quién pregunta, no de lo que mande el cliente.** Si
  saliera del parámetro, el logístico de Camagüey vería las otras siete
  cambiándolo. Ya pasó en delivery: un operador de Santiago vio los precios de La
  Habana. **Y el alcance FALLA CERRADO** (08/10/2026): una auditoría de seguridad demostró que
  una sucursal en el token que Reparto no resolvía (un código de Accesos que Reparto no
  conoce, como `MOA` o `PLS`, o un uuid inexistente) caía en «no existe, así que todas», y
  que `X-Sucursal-Id` con basura abría las ocho a quien no tenía sucursal. Ahora: la cabecera
  sólo la lee SUPER ADMIN o DESARROLLADOR; quien trae una sucursal que no se resuelve recibe un
  403 (`ErrSucursalSinAlta`) que dice cuál es; «todas» es sólo para esos dos roles. **Si se da de
  alta una sucursal nueva en Accesos, hay que darla de alta TAMBIÉN en Reparto**
  (`branches.external_id`), o su gente no entra. **Trampa del código:** la APK y el escritorio
  llevan `organization.codigo` en el token, pero la web lo saca del `slug` en mayúsculas
  (`auth_web.go`), y en Accesos son columnas distintas. Hoy coinciden en las diez menos `PLS`
  (su slug es `palma-soriano`): antes de dar de alta `PLS` en Reparto hay que hacer que la web
  lea `codigo` (el intercambio de Accesos, `auth/src/app/api/auth/exchange/route.ts`, sólo
  manda `slug`). `PATCH /api/orders/{id}` ya no cambia
  `routeId`, `status`, `price`, `weight` ni `stopOrder`: se entra y se sale de una ruta sólo
  por `/api/routes` y `/api/board`, que son los que validan.
- **La tasa es POR SUCURSAL** y sin la de esa sucursal no se convierte nada: no
  se cae a la de otra ni a un número por defecto. En PEDIDO está contado así:
  «Granma enseñaba los 685 de La Habana como si fueran suyos: un importe así se
  lee bien y está mal, que es lo peor que puede pasarle a un número que alguien
  va a cobrar».
- **Quitar algo es quitarlo ENTERO**: sus tipos, sus llamadas, sus enlaces, su
  entrada de menú y sus pruebas.
- **El camión en el taller es AVISO, no bloqueo** (Jose, 28/09/2026; la 1.0.28 lo bloqueó por
  error y se revirtió en la 1.0.29): una sucursal con UN camión olvidado en `maintenance` se
  quedaría sin poder armar rutas. Se ofrece con un aviso ámbar «en el taller». Lo que NUNCA se
  ofrece es un camión INACTIVO (`is_active`, el que pidió Amado), y el servidor lo rechaza.
- **El armado local y el del servidor son la MISMA regla**: sólo entra a una ruta una factura
  `igual` con domicilio cobrado y cotizado; las demás se descartan y se NOMBRAN por su conduce
  (el número de operación). Los literales de lo que se descarta están en
  `docs/armado-rechazado.casos.json`, que leen las pruebas de los dos lados.
- **Reasignar un pedido devuelto o cancelado a otra ruta es un intento nuevo**: sin su
  `resultado`, nota ni hora de entrega, en el servidor (`EngancharPedidoARuta`) y en los dos
  armados locales. Un `entregado` no se puede reasignar nunca.
- **Un cierre parcial en la web no se avisa con algo que se va solo**: cajón que obliga a acusar
  recibo, con «Conduce <número>: <motivo>» de cada parada que no se guardó. La ruta se completa
  con lo guardado y es histórico: lo rechazado no se puede dejar pasar en silencio.
- **El cierre de ruta no pregunta «¿salir sin guardar?» cuando ya no hay nada que perder, y SÍ
  pregunta cuando lo hay** (issue 2 de Amado, 08/10/2026: «Tienes 0 sin guardar»). `PopScope.canPop`
  es el valor del ÚLTIMO dibujo y `_guardar` mueve la foto de lo guardado sin redibujar: la
  decisión se toma de nuevo en `onPopInvokedWithResult` con `_cambios` y `_soloLectura` de AHORA.
  Y escribir en la nota de una parada redibuja el cajón (`alEscribirLaNota`): sin eso, editar sólo
  la nota y dar atrás salía sin preguntar y la nota se perdía en silencio.
- **QUIÉN ENTRA A REPARTO LO DECIDE AUTH, NO REPARTO** (Jose, 08/10/2026: «Reparto no decide quién
  entra; eso lo maneja Auth; Reparto es un microservicio y el login es de Auth»). Hoy entran sólo
  `SUPER ADMIN`, `DESARROLLADOR`, `ADMINISTRADOR` y `LOGISTICO` porque Auth sólo le da `delivery.entrar`
  a esos cuatro (script `retirar-reparto-de-roles`, 08/10/2026); darle acceso a otro rol es dársela a
  ese rol en Accesos, SIN tocar Reparto. Auth firma en el token de la APK/escritorio y en
  `/api/auth/exchange` el campo `entradas` (llaves `<app>.entrar` de la persona; todas si es
  `isSystemAdmin`) y Reparto entra si y sólo si trae `delivery.entrar` (texto exacto); si no, **403**
  `{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}`, tras la
  identidad y ANTES del alcance de sucursal. Con `entradas` PRESENTE (aunque `[]`) decide sólo ella,
  sea cual sea el rol; AUSENTE (token o cookie anteriores al 08/10/2026) cae a la lista de roles de
  antes, detrás de `auth.CaidaPorRolesDeTransicion`/`caidaPorRolesDeTransicion`: **QUITAR cuando
  caduquen las cookies web viejas (7 días → 15/10/2026)**. Ausente y vacío NO son lo mismo. La regla
  vive en DOS módulos (`api/internal/auth/auth.go` y `sync/internal/identidad/token.go`) atados por
  `docs/roles-de-reparto.casos.json` (viaja en las imágenes): **si lo cambias, cambia los dos**. Se
  aplica en `Verificador.Exigir`, en el canal `/api/eventos` (que NO pasa por Exigir) y en el
  sincronizador. La web toma los roles de `role`+`roles` de PRIMER NIVEL del exchange (las membresías
  sólo como caída; nunca `admin`). La comparación es `auth.MismoRol`/exacta (ASCII, SIN plegado
  Unicode: `strings.EqualFold` casaba «ſUPER ADMIN»). `GET /api/me` NO da 403 (contesta quién es). Las
  cuentas de servicio no pasan por Exigir y llevan SUPER ADMIN. `SYNC_IDENTIDAD=cabeceras` no arranca
  sin `SYNC_PERMITIR_CABECERAS=1` (no tiene roles que comprobar); en producción es `token`. Un
  logístico se da de alta poniéndole el rol LOGISTICO en Accesos; Reparto no guarda personas ni roles.
  **TRAMPA: antes de dar una SEGUNDA MEMBRESÍA a alguien hay que ligar el rol a la sucursal** (hoy
  nadie tiene más de una; los roles son de la persona y la sucursal es la de la primera
  membresía: `TestLimiteConocido…`). **TRAMPA del despliegue:** Accesos primero (crea LOGISTICO y
  firma `entradas`), luego asignar LOGISTICO a quien trabaje en Reparto, luego `sync` y `api`; en la
  web el rol se refresca al volver a entrar (la cookie dura 7 días).
- **LA SESIÓN LA INVALIDA ACCESOS, POR REDIS, SIN SONDEO** (Jose, 08/10/2026: «si cierro sesión o me cambian un
  permiso en Accesos se refleja en todas. Nada de polling: para eso tenemos SSE y Sentinel»; y «la web es la web y las
  APK son la APK»). Accesos publica en `procovar:auth:eventos` del Redis de la casa (mismas `REDIS_*` que el espejo;
  marcas de recuperación en la DB 6, `procovar:auth:invalida:{web,todo}:<userId>`, TTL 8 días)
  `{"v":1,"tipo":"sesion-cerrada|permisos-cambiados","alcance":"web|todo","userIds":[…],"tms":<ms>,…}`. La API
  (`api/internal/sesiones`, enganchada en `auth.Verificador`) y el sincronizador (`sync/internal/sesiones`, gemela
  recortada) mantienen un mapa en memoria; **ninguna petición sale a la red**. La cookie web (`iatms` + `web:true`)
  emitida antes de `max(web,todo)` da 401 y se borra; el token de la APK/escritorio emitido antes de `todo` (su `iatms`,
  o `iat*1000` si no lo trae) da **401, nunca 403**, en api y sync; un evento `web` no toca a la APK. **«Sesión web» es
  la que viaja en cookie o lleva `web:true`, NO la que lleva `iatms`** (Accesos también lo firma en la APK) y OJO: la
  web manda la cookie Y el mismo token como Bearer, así que «el Bearer no se mira» dejaría la web sin cortar. SSE:
  evento `sesion-invalidada` `{"tipo":…}` sólo a las conexiones de esa persona (las de Bearer sólo en `todo`) y el
  servidor cierra la conexión. Redis caído o sin configurar **no tumba nada** (WARN, recarga de marcas al reconectar).
  Topes: se ignora un `tms` a más de 60 s en el futuro, 1000 ids por mensaje, 100.000 marcas por mapa (se van las
  viejas). La clave de Redis es compartida: **falta una ACL** (sólo Accesos publica/escribe). Variables `REDIS_*` en
  `reparto-api` Y `reparto-sync` (NO `REDIS_BASE`). Pruebas: `internal/sesiones` (api y sync),
  `la_sesion_web_la_invalida_accesos_test.go`, `la_apk_tambien_la_invalida_accesos_test.go`,
  `sync/internal/identidad/accesos_corta_la_sesion_test.go`; Redis real con `REPARTO_REDIS_REAL_ADDR`.
  **App** (`docs/sin-permiso.md`, sección final): WEB: `eventos_web.dart` hace `close()` del EventSource (si no, el
  navegador reconecta contra una sesión muerta) y emite `sesion-invalidada:<tipo>`; el embudo `avisosDelServidorProvider`
  lo corta (jamás llega al vigía: no es un cambio) y `Portero.sesionInvalidada` manda a `fuera` con el mensaje «Tu sesión
  se cerró en Accesos. Vuelve a entrar.» / «Tus permisos cambiaron. Vuelve a entrar.»; la puerta lo dice 3 s y va a
  Accesos; idempotente (dos eventos = una navegación). APK/ESCRITORIO: el aviso no echa a nadie; `Portero.renovarPorAviso`
  renueva YA y decide el refresco (401 = «Tu sesión se cerró», 403 `sin_permiso` = pantalla sin permiso, 200/sin red =
  nada); la cola y la base no se tocan JAMÁS. Al volver la red el ciclo renueva primero y se entera solo. Cerrar sesión
  SIN red deja el refresco en un hueco aparte (`reparto.por_revocar`, por persona) que `RevocadorDeCierres` presenta a
  `/logout` al arrancar, al entrar y al volver la red; sólo se borra con 200 o 401 de nuestro servidor y **NUNCA se usa
  para entrar**. La app manda `User-Agent: ProcovarReparto/<versión> (<plataforma>)` a Accesos (no en la web) para que
  la lista de dispositivos distinga Android de Windows. **Qué NO está hecho todavía:** una persona que pierde el rol
  con cola sin subir la conserva pero no puede entregarla — diseño aprobado en `docs/bandeja-de-revision.md` (1.0.32).
- **Un 403 `sin_permiso_reparto` NO es un rechazo del apunte** (es la PERSONA, no el apunte): en el
  sincronizador `/sync/subida` contesta 403 sin anotar nada, y en la app el interceptor pasa el
  portero a `EstadoDeAcceso.sinPermiso` (pantalla `/sin-permiso`, ciclo y vigía parados; sesión, base
  y cola intactas). Si se convirtiera en `rechazado`, se destruiría la cola de quien sólo necesita
  que le den el rol. Web: va sola al inicio de Accesos (`AUTH_URL/`) a los 3 s, con contador y «Ir
  ahora»; APK y escritorio: «Ir a Accesos» y «Cerrar sesión» (que pregunta si hay cola). De
  `sinPermiso` sólo se sale con `salir()` y entrando de nuevo. Detalle en `docs/sin-permiso.md`.
- **La tabla de Pedidos enseña SI EL DOMICILIO ESTÁ COBRADO y ya no tiene columna «Vehículo»**
  (Amado, 08/10/2026, incidencias 3 y 4). «No se puede asociar al tablero: la factura no tiene un
  cobro de domicilio registrado» era CORRECTO: la factura cuadraba pero no traía la línea «ENTREGA A
  DOMICILIO» (`factura_domicilio` nulo, también en PEDIDO; ~9 de cada 10 pedidos a domicilio con
  factura que cuadra están así). La celda «Factura» (`tabla_pedidos.dart`) añade, con factura `igual`
  o `cambiado`, «Dom. $0.46» (verde, `facturaDomicilio > 0`) o «Sin cobro de domicilio» (ámbar), con
  el tooltip que explica la consecuencia; el ámbar sólo sale si ese es lo que frena al pedido
  (`frenaElDomicilioSinCobrar`, que pregunta a `porQueNoSePuedeColocar` y no repite la regla; con
  ruta, entregado o archivado va sólo el número o el verde). La regla NO cambió: la marca la hace
  visible. La columna «Vehículo» se quitó entera (desde la 1.0.28 `orders.vehicle_id` no existe); el
  camión sigue en el detalle. Trampa: la columna Factura se esconde bajo 1024 px.
- **Cajón siempre**, también en escritorio (excepción aprobada para este
  proyecto el 05/09/2026). Sin emojis en la interfaz.
- **Una decisión de una persona se ESCRIBE, no se borra.** Borrar no es decidir:
  borrar deja un hueco, y otra pieza rellena ese hueco con lo que ella cree.

  El 29/09/2026 costó semanas de «los errores se acumulan y nunca se borran»
  (Jose). El botón «Descartar» de la bandeja existía y **borraba de verdad** —
  ése era el fallo. Al irse el apunte, la fila que iba a subir se quedaba sin
  nada que la nombrara, o sea huérfana, el ciclo la reencolaba, el servidor
  repetía su «no» y el rechazo volvía a la bandeja con clave nueva. Ninguna
  pieza mentía: fallaba la junta de tres.

  Ahora `descartar` marca `EstadoApunte.descartado` y lo huérfano lo lee como
  «esto ya se decidió». Y la segunda mitad, sin la cual se cambia un bucle por un
  atasco: **también hay que soltar lo que protegía esa fila** (`nacio_aqui`), o la
  bajada no la toca nunca más.

  Su pariente, y por eso va aquí: **un aviso sin acción es un aviso que se queda
  puesto para siempre.** «Sólo en este aparato» contaba trabajo que no iba a
  subir y no tenía ni un botón. Si algo espera «hasta que una persona decida»,
  tiene que haber **con qué** decidir desde donde se está mirando.
- **Los botones van SIN FONDO.** Lo que los diferencia es el **color, el borde y
  el icono**, no un rectángulo relleno. Jose lo ha dicho más de una vez y el
  28/09/2026 tuvo que repetirlo —«te dije bien claro q sin background y de
  colores y los bordes y iconos lo diferenciaban»—, así que queda escrito aquí:
  **si no está en este fichero, se pierde**, y perderlo cuesta que lo diga otra
  vez.

  La jerarquía no desaparece, cambia de material: la acción principal se
  distingue por su color y su icono, no por ir rellena. Lo que decide es el
  tema (`app/lib/diseno/tema.dart`), no un `style:` puesto a mano en cada
  pantalla — un relleno suelto en un fichero es lo que hace que dentro de un mes
  haya dos aspectos en la misma aplicación.

  **Y el icono no lo puede poner el tema**, porque es un hijo del widget y no
  una propiedad del estilo: el mismo 28/09/2026 quedaban **25 `FilledButton(`
  sin icono contra 9 con él**, o sea la mayoría de las acciones principales con
  dos rasgos de los tres. Así que lo principal entra por `BotonPrincipal` igual
  que lo destructivo entra por `BotonDestructivo` — **el icono es obligatorio en
  el constructor y no tiene valor por defecto**. Ni `FilledButton(` ni
  `ElevatedButton(` a pelo: los dos cuelgan del mismo nivel y lo vigila
  `app/test/diseno/el_principal_lleva_su_icono_test.dart`, que barre `lib/`.

  Y el icono es **el de SU acción**, uno por uno: guardar, añadir, armar,
  imprimir, traer, entregar, reintentar. El mismo glifo repetido no diferencia
  nada, que es justo lo que se vino a arreglar. Cuando una acción no tenga
  ninguno honesto —una pestaña, por ejemplo, que no es una acción sino dónde
  estás— **no se le pone uno cualquiera**: se escribe aparte y se explica por
  qué, como `_Pestana` en `app/lib/diseno/pestanas.dart`.

---

## 3-sexies. El peso de un renglón son TRES escalones, y un cero no es ninguno

El 28/09/2026 la hoja de pre-despacho enseñaba **el mismo peso para Santiago que para
las ocho sucursales**, idéntico hasta el decimal, con un 68 % más de empaques. Los
empaques y las unidades sí se recalculaban; los kilos se quedaban clavados. Se vio en un
teléfono, no en una prueba.

La causa: la cascada tenía **dos** escalones —`peso_linea_kg` y el catálogo local— y le
faltaba el de en medio, `peso_kg × empaques`, que es lo que pesa UN empaque y viene en el
propio renglón. Como el catálogo local **no trae el peso de ningún producto**, un renglón
con `peso_kg` y sin `peso_linea_kg` no aportaba ni un kilo **y se iba entero al contador
de «sin peso»**: por eso lo que entraba de más al ensanchar el alcance sólo movía el
contador y dejaba la cifra quieta.

Los tres escalones, en este orden:

1. `peso_linea_kg` — lo que pesa la línea entera, ya multiplicado;
2. `peso_kg × empaques` — lo que pesa un empaque, por los que van;
3. el catálogo local — `products.weight × empaques`.

**Y un CERO no es un peso: es «este escalón no lo sabe».** Con un `COALESCE` a secas, un
`peso_linea_kg` guardado en cero tapa los dos escalones de debajo y la celda dice
`0.0 kg` teniendo el dato. Cada escalón pasa por su `> 0`.

### Y la regla vive en UN sitio, no en tres — la misma noche

La regla estaba escrita TRES veces: `api/internal/cotizar/pesos.go` (`PesosDeRenglones`,
§2.1 de `reglas-negocio.md`), la ficha del pedido y el pre-despacho, los dos últimos en
`pantallas/pedidos/datos/repositorio_pedidos.dart`. Y **estuvieron distintos**: la ficha
decía «40,0 kg» y la hoja del almacén ponía «—» sobre los mismos veinte empaques. Jose:
«como q 3 veces lo repetiste mijo era mas facil ponerlo en el api y ya q lo consuman una
cada uno».

Y el proyecto **ya estaba diseñado así**: la `00004_peso_por_renglon.sql` añadió
`peso_linea_kg` y `origen_peso` «precisamente para no tener que recalcular el peso con el
catálogo de hoy sobre un pedido de hace tres meses». Los tres sitios no eran el diseño:
eran una desviación suya, y por eso se desincronizaron.

Así que **el servidor resuelve y el aparato LEE**. La cascada corre una vez, al entrar el
pedido; el resultado se escribe en `order_items.peso_linea_kg`, viaja en `pesoLineaKg` y la
aplicación lo lee de su base local —con señal o sin ella: el trabajo sin conexión no
pierde nada, es la misma columna que ya bajaba—.

Lo único que la aplicación repite es **la regla del cero**, y a propósito: un
`peso_linea_kg` vacío o en cero es «no se sabe» y se pinta «—», nunca «0,0 kg». Está
escrita dos veces —`soloSiPesa` en Dart y `_siPesa` en SQL— y que las dos contesten igual
lo ata `app/test/pantallas/pedidos/el_peso_del_pre_despacho_cambia_de_sucursal_test.dart`,
que es también donde viven las otras tres guardas de esa noche.

**Lo que hay que saber antes de tocar el espejo:** ya no hay red de seguridad. Un renglón
que se escriba sin `peso_linea_kg` sale «—» en la ficha, en la hoja del almacén y en el
papel, y cuenta entero en «sin peso». Y los renglones **viejos** no se arreglan solos: el
espejo sólo vuelve a pedirle a PEDIDO lo que se movió desde la marca de agua, así que un
cambio que sólo afecta al cálculo no llega nunca a las filas de hace tres meses. Hay que
relanzarlas (`internal/espejo`, el barrido del histórico, o `POST /api/admin/recompute` por
tramos). Lo que SÍ funciona sin ayuda es la reescritura: `renglonesIguales` compara
`peso_linea_kg` y `origen_peso`, así que en cuanto un pedido vuelve a pasar por el lote sus
renglones se reescriben aunque la fila del pedido no haya cambiado.

---

## 4-bis. El auditor NO es opcional

Hay un auditor en `.claude/agents/auditor-del-reparto.md` con su skill
`auditar-el-reparto`. **Se lanza antes de cada commit y antes de cada
despliegue**, sin excepción, y se le va contando lo que se hace según se hace —
no se le entrega el código al final.

No es celo. El 16/09/2026 se metieron en producción, todos con «Todo en verde»:
la cola del tablero contestando 401 y sin subir nada; 84 lotes de PEDIDO
rechazados con 403; una mutación de prueba desplegada por un `git add -A`; y una
carga inicial que dejaba 2.000 de 8.103 clientes dándose por completa. Ninguna la
habría visto leer el diff. Todas se cazan ejecutando y rompiendo guardas.

Dos reglas que salieron de ese día:

- **Nunca `git add -A` mientras un agente está mutando el árbol.** Se le lleva la
  mutación al commit. Pasó, y se desplegó.
- **Los tres Dockerfile corren sus pruebas antes de construir.** `Dockerfile.api`
  y `.sync` hacen `go vet && go test`; `Dockerfile.app` hace `flutter analyze` y
  `flutter test`. Poner eso en la imagen de la web costó dos
  intentos y los dos enseñan lo mismo —**una imagen no es esta máquina**—:
  `.dockerignore` excluía los textos generados y `analyze` no los genera (sí lo
  hacía `build web`, que era lo único que había antes), así que hubo que meter un
  `flutter gen-l10n` delante — **ese paso ya no está**: la traducción al inglés se
  quitó entera el 24/09/2026 y con ella los `.arb`, el `l10n.yaml`, la clase
  generada, el `generate: true` del pubspec y la línea del `.dockerignore`
  (`app/lib/idioma.dart`); y las pruebas abren bases
  de verdad con Drift, así que hace falta `libsqlite3-dev` — **el `-dev`, no el
  `-0`**, porque el `-0` instala `libsqlite3.so.0` y Dart abre la biblioteca por
  su nombre sin versión. El de sync sólo compilaba, y por eso la mutación llegó al
  servidor. El de la web se quedó sin arreglar aquel día y estuvo un día entero
  construyendo sin pasar una sola prueba — el mismo agujero, en el otro lado.
- **Con agentes escribiendo a la vez, no se lanza `./comprobar.sh`.** Mide un
  árbol a medio escribir y contesta `FALLA` sobre ficheros que están bien: el
  17/09/2026 dio dos falsos rojos seguidos mientras cuatro agentes trabajaban.
  Cada agente comprueba **lo suyo** (`flutter analyze <carpeta>`, sus pruebas con
  `timeout 300`, o `go build && go vet && go test` en `api/`), y el guion entero
  se pasa **una vez, al final**, cuando todos han soltado los ficheros. Y por lo
  mismo: **no se despliega con agentes vivos.**
- **A cada agente se le dice qué ficheros NO puede tocar**, con la lista de lo que
  tienen los demás. Sin eso se pisan, y el que pierde es el que no se entera.
- **NO SE MUTA UN FICHERO QUE OTRO AGENTE TIENE ABIERTO, aunque el guion
  restaure por hash.** El 17/09/2026 se mutaron seis guardas de
  `detalle_ruta.dart` mientras su agente seguía escribiéndolo. Cinco salieron
  rojas; la sexta salió **verde sin serlo** —a mano fallaba— y, al acabar, el
  `if (false)` de otra de las mutaciones **seguía puesto en el árbol**. El guion
  restauraba, sí, pero el agente escribía encima entre medias y se perdía la
  carrera. Si eso llega a un `git add`, es la mutación desplegada del 16/09 otra
  vez, con la diferencia de que esta vez la puso quien audita.

  Las dos señales de que ha pasado, y las dos hay que mirarlas: **una mutación
  que sale verde** no es una prueba floja hasta que se comprueba a mano, y al
  terminar se barre el árbol —`grep -rn "if (false)\|if (true)\||| true)"` fuera
  de las pruebas— **antes** de tocar git. Se muta cuando el fichero es de uno, y
  si no lo es, se espera.
- **Cada agente muta lo suyo y nadie muta lo del vecino.** Por eso la auditoría
  del final tiene que romper guardas que NO escribió quien las audita. El
  17/09/2026, con todo «en verde» y cinco agentes que habían mutado cada uno su
  parte, la pasada final encontró **tres mutaciones que nadie cazaba**: un
  parámetro del contador quitado (toda la api verde), un tipo de aviso renombrado
  en Go (toda la api verde, y Flutter sin enterarse), y la guarda que evita el
  «Vista (0)» puesta a `false` (853 pruebas verdes).
- **Una mutación verde no siempre es una prueba floja: a veces las dos opciones
  son EQUIVALENTES ahí.** El 05/10/2026, al poner el cartel de «¿seguro que
  quieres salir?» en el armazón, cambiar su `BackButtonListener` por un
  `PopScope` dejó las 20 pruebas en verde. No había prueba floja: en esa posición
  —colgado de la página del `ShellRoute`— los `maybePop` que preocupaban en
  `diseno/cajon.dart` son de **otras rutas** (la del cajón, la de una subruta) y
  no pasan por él. La advertencia de `cajon.dart` es verdad donde está escrita,
  dentro de la misma ruta que se va a cerrar, y se estaba aplicando fuera de su
  sitio.

  Qué se hace entonces, que es lo que importa: **no se inventa una prueba que la
  finja, y no se calla.** La decisión se escribe con su motivo —en el código y en
  el fichero de pruebas— y se dice ahí mismo que cambiarlo no pone nada en rojo.
  Un comentario que promete una guarda inexistente es el «Sin colocar (722)» del
  §3-bis otra vez: lo peor no es no tener la guarda, es creer que la tienes.

- **Una guarda que sólo se recalcula al bajar la foto no se entera de lo que pasa
  después.** El aviso de «el servidor rechazó tu cambio» se calculaba dentro de
  la bajada, que corre al cambiar de sucursal y con un aviso del canal — y el
  rechazo llega **después**, con la pantalla ya abierta. No salía nunca. Y la
  prueba no lo cazaba porque sembraba el rechazo ANTES de montar, que es justo la
  forma que prohíbe el §3-ter, escrita aquí y rota el mismo día. **Lo que cambia
  con la pantalla delante se vigila con un stream sobre la tabla**, no
  preguntando cuando uno se acuerda.

## 5. Cómo se comprueba

`./comprobar.sh` desde la raíz: gofmt, vet, test, build y `sqlc diff` en `api/` y
`sync/`, y `analyze` + `test` en `app/`. Tiene que decir **«Todo en verde»**.

- `sqlc` está en `~/go/bin/sqlc`. **El código generado no se escribe a mano.**
- **Las consultas se prueban contra Postgres de verdad, y sólo si lo pides.** Los dobles de
  `internal/api` reimplementan el SQL y NO lo ven: el 08/10/2026 una auditoría mutó 14
  guardas del SQL generado y sólo `api/internal/store/sqlc/consultas_motor_real_test.go` las
  cazó. Sin `REPARTO_MOTOR_REAL_DSN` esa prueba se salta **en silencio** (también en el
  `Dockerfile.api`, que no tiene Postgres). `./comprobar.sh` ahora dice «SALTADO» en vez de
  callarlo. Para correrla: base local aislada `verif_reparto` en el contenedor
  `reparto-postgres-1` (rol `verif`, ver `docs/entorno-local.md`), migrada con `goose` hasta
  la última, y `REPARTO_MOTOR_REAL_DSN=postgres://verif:verif@127.0.0.1:5433/verif_reparto?sslmode=disable ./comprobar.sh`.
  **Antes de cada despliegue con cambios de SQL, hay que correrla.**
- **Lo mismo con Redis (sesión única).** `api/internal/sesiones/redis_real_test.go` y su gemela de
  `sync/` se saltan en silencio sin `REPARTO_REDIS_REAL_ADDR`; `./comprobar.sh` las corre si está
  puesta y dice «SALTADO» si no. Un Redis local de usar y tirar (`docker run --rm -d --name
  reparto-go-redis -p 127.0.0.1:6391:6379 redis:7-alpine`, `docs/entorno-local.md` §7-bis). Sin Redis,
  `sesiones/contrato_test.go` ata la DB 6, el canal y los prefijos al contrato de Accesos, y
  `internal/api/sesion_cableada_test.go` / `sync/internal/identidad/fuente_de_la_casa_test.go` atan el
  cableado de `main` (el servidor se construye con `api.NuevoServidorConSesiones` e
  `identidad.FuenteDeLaCasa`, que son lo único que llaman los dos `main`).
- **Y con Chrome (la web).** `app/test/nucleo/red/agente_de_usuario_web_test.dart` (`@TestOn('browser')`)
  es lo único que ejecuta la guarda del `User-Agent` con `kIsWeb` de verdad (en la VM `kIsWeb` es
  siempre falso, y quitar la guarda salía en verde: cabecera no segura para CORS, preflight al login
  de Accesos). Se corría solo a mano; `./comprobar.sh` ahora tiene el bloque `chrome (web)`: corre
  esa prueba si hay Chrome (`CHROME_EXECUTABLE` o `google-chrome-stable` en el `PATH`) y dice
  «SALTADO (instala Chrome o exporta CHROME_EXECUTABLE: docs/entorno-local.md)» si no
  (`docs/entorno-local.md` §7-ter). Sus dos pruebas cubren cosas distintas, dicho en su cabecera.
- **El cableado de `main` se ata por AST, no por texto.** `sesion_cableada_test.go` (api) y
  `fuente_de_la_casa_test.go` (sync) analizan `cmd/*/main.go` con `go/parser`: un comentario no cuenta
  (`_ = ctx // inv.Correr(ctx)` y `nil /* sesiones.DeRedis(cfg.Redis) */` pasaban la guarda de texto), y
  en sync `identidad.Exigir` ha de recibir la fuente que salió de `FuenteDeLaCasa`.
- **Pruebas colgadas**, y son DOS trampas hermanas, las dos de lo mismo: dentro
  de un widget test el tiempo lo manda el `tester` y no avanza solo.
  1. Nada de `await` sobre el primer valor de un stream de Drift ahí dentro: la
     prueba **se cuelga en vez de fallar**, que es lo peor que puede hacer una
     prueba.
  2. **Nada de sembrar la base en el `setUp` de un `testWidgets`.** El `setUp`
     corre fuera del reloj falso, y lo que Drift deja empezado allí no avanza
     dentro: el 17/09/2026 un cajón se quedó girando diciendo «no hay ninguna
     zona» encima de un tablero con dos, y la prueba no fallaba, se colgaba. La
     base se abre donde sea, pero **se escribe y se lee dentro del cuerpo**.

  Usa `timeout 300` siempre: es lo único que convierte un cuelgue en un fallo.
- **Una prueba que copia la dirección del código que prueba no comprueba la
  dirección.** Las del Tablero repetían `/api/api/board` y todo salía verde
  mientras las diez llamadas daban 404.
- **Mutación**: rompe la guarda a propósito y comprueba que hay una prueba que la
  caza y que lo dice con un mensaje entendible. Si no la caza, la prueba no vale.

### La regla dura del entorno

`lib/nucleo/red/entorno.dart` tiene las URL de **producción** como `defaultValue`,
así que un `flutter build web` sin `--dart-define` deja una aplicación que llama a
`reparto.procovar.cloud` en cuanto alguien la abre. El `CLAUDE.md` de Procovar
prohíbe cualquier petición a un dominio de Procovar desde este PC —a la oficina le
bloquearon la IP por eso—, así que:

```bash
flutter build web --dart-define=API_URL=http://127.0.0.1:8099/api ...
grep -c "procovar\.cloud" build/web/main.dart.js   # 4 con API_URL, SYNC_URL y AUTH_URL locales
```

**El «0» de antes era inalcanzable** (lo midió la re-auditoría del 09/10/2026): quedan 4 apariciones que son
TEXTO y no peticiones —el valor de respaldo de `AUTH_URL` vacío (`entorno.dart`), el valor por defecto de
`oferta_de_la_puerta.dart`, la etiqueta «Ir a procovar.cloud» de `pantalla_acceso.dart` y el enlace al portal—.
Lo que se vigila es que **ninguna línea nueva añada otra** (`git diff -U0 -- app/lib | grep procovar.cloud` vacío) y
que las tres URL de arriba vayan siempre con `--dart-define` locales; con solo `API_URL` salen 7.


Y **cierra las pestañas y para los servidores al terminar**: una aplicación viva
dispara un ciclo de sincronización cada pocos minutos. Ya pasó.
