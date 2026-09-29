# El tiempo real del reparto — investigación y plan

**29/09/2026.** Escrito porque Jose lo pidió así: investigar primero, plan entero
después, y **para todas las vistas**, no para una.

> «SSE es como tenemos que hacerlo.»
> «El evento debe salir de su sucursal, no puede dar una bajada a las otras 7.»
> «Tiene un evento para cada cosa, para cada lugar, y también depende del usuario.»
> «Por tablero no puede actualizarse cada vez que se haga algo en rutas.»
> «El reloj no lo quiero.»

---

## 1. Lo que hay hoy, medido

### 1.1 El aparato sincroniza cada 11–38 segundos, no cada cinco minutos

Medido en el teléfono de Jose el 29/09/2026, con la aplicación abierta y **sin
tocar nada**, leyendo el registro de la api:

```
19:06:23 · 19:08:23 · 19:08:41 · 19:09:17 · 19:09:28 · 19:10:06 · 19:10:23
```

Huecos: 2:00, 0:18, 0:36, 0:11, 0:38, 0:17. El periodo de la APK es de **cinco
minutos**, así que esto no lo dispara el reloj: lo dispara algo.

### 1.2 Y cada vuelta cuesta 3.255 bytes para nada

| Petición | Bytes | Cambió algo |
|---|---|---|
| `GET /api/sync/cambios` | 584 | no |
| `GET /api/almacenes` | 2.671 | no |

**~1,4 MB por hora y por aparato**, con la conexión de allá, sin que haya
cambiado nada. Y el 82 % de eso son los almacenes, que no cambian casi nunca.

### 1.3 El disparador es nuestro, y es de ayer y de hoy

`app/android/app/src/main/kotlin/cloud/procovar/reparto/VeredictoDeRed.kt` manda
el veredicto de red en **cada `onCapabilitiesChanged`**. Android dispara ese
evento constantemente en datos móviles —la estimación de ancho de banda cuenta
como cambio de capacidad— y el canal lo reenvía tal cual, sin mirar si el
veredicto es el mismo de antes.

El 28/09 ese canal sólo pintaba una franja, así que no costaba nada. El 29/09 se
enganchó al vigía para que volver la señal subiera el día — y ahí cada parpadeo
pasó a costar un ciclo.

### 1.4 El canal en vivo se muere con un 401 y no vuelve

```
18:59:40  GET /api/eventos  401  0 ms
```

Y ni un segundo intento en media hora. Un 401 en un mal momento —la sesión recién
cargada tras reinstalar— dejaba al aparato **sin tiempo real hasta que alguien
cerrara y volviera a abrir la aplicación**. Sin error en pantalla y sin aviso.

*(Arreglado ya: ahora espera y vuelve a mirar, sin gastar peticiones mientras la
sesión no cambie. Es lo único de este plan que está hecho.)*

### 1.5 El aviso es global: un cambio en una sucursal le cuesta una bajada a las ocho

El servidor publica **33 avisos desde 10 ficheros**, y ninguno dice de qué
sucursal es ni qué cambió exactamente:

| Aviso | Sitios que lo publican | Dónde |
|---|---|---|
| `tablero` | 7 | `tablero.go` |
| `rutas` | 7 | `rutas.go`, `vehiculos.go` |
| `vehiculos` | 7 | `vehiculos.go`, `tipos_vehiculo.go` |
| `pedidos` | 4 | `pedidos.go`, `vehiculos.go` |
| `canal` | 4 | `webhook_de_pedido.go`, `drenaje_del_buzon.go` |
| `catalogo` | 3 | `espejo.go`, `productos.go` |
| `sucursales` | 3 | `sucursales.go` |
| `almacenes` | 1 | `almacenes.go` |
| `ajustes` | 1 | `ajustes.go` |

Mover una tarjeta en Camagüey publica `tablero` **a secas**, y los aparatos de
las otras siete sucursales se bajan su tablero entero. Ocho navegadores en la
oficina más los teléfonos.

### 1.6 Y el aviso llega demasiado grueso: `rutas` mueve el Tablero

`vehiculos.go` publica `rutas` y `pedidos`; `rutas.go` publica `rutas` y el
armador publica además `tablero`. Un gesto en Rutas acaba moviendo pantallas que
no tenían por qué enterarse. Palabras de Jose: «por tablero no puede actualizarse
cada vez que se haga algo en rutas».

---

## 2. Las trece vistas, y de qué vive cada una

Esto es lo que hace que no se pueda arreglar sólo el Tablero.

| Vista | De dónde lee | Cómo se entera hoy | Qué necesita |
|---|---|---|---|
| **Tablero** | red (`GET /api/board`) + base | aviso `tablero` (suscripción propia) | aviso `tablero` **de su sucursal y su almacén** |
| **Vehículos** | red (`/vehicles`, `/settings`) | `refrescarConElAviso([vehiculos])` | aviso `vehiculos` de su sucursal |
| **Almacenes** | red (`/almacenes`) | `refrescarConElAviso([almacenes])` | aviso `almacenes` de su sucursal |
| **Canal con PEDIDO** | red | `refrescarConElAviso([canal])` | global: es de administración |
| **Sincronización** | red (al sincronizador) | *nada, hasta hoy* | estado del sincronizador; sin sucursal |
| **Panel** | base | el ciclo escribe y repinta | que el ciclo traiga **sólo lo que cambió** |
| **Pedidos** | base | ídem | ídem |
| **Rutas** | base | ídem | ídem |
| **Clientes** | base | ídem | ídem |
| **Informes** | base | ídem | ídem |
| **Entregar el día** | base (cola) | ídem | ídem |
| **Traer el día** | base | ídem | ídem |
| **Acceso** | — | — | — |

**Las cuatro primeras piden a la red y el evento las toca directamente.** Las
demás viven de la base local: el evento dispara un ciclo, el ciclo escribe, y
Drift las repinta.

Y de ahí sale **cómo se usan los avisos para nosotros**, que son dos casos
distintos y no se tratan igual:

- **Las nueve de la base no necesitan grano fino para ahorrar.** Les basta con
  que el aviso dispare el ciclo, que ya es *una* petición de 584 bytes en vacío.
  El grano les sirve para lo otro: **no** disparar cuando el cambio no es suyo.
- **Las cuatro de red sí lo necesitan**, porque a ellas cada aviso les cuesta una
  petición de verdad — la flota, los almacenes, la foto del tablero.

---

## 3. El plan

Cinco pasos, en este orden, porque cada uno se apoya en el anterior.

### Paso 1 · Que el canal no se muera — HECHO

Un 401 repetido ya no cierra el canal para toda la sesión: espera y vuelve a
mirar, **sin gastar ni una petición ni una renovación** mientras la sesión sea la
misma. Entra solo en cuanto el ciclo renueve. Atado por
`app/test/nucleo/red/eventos_io_test.dart`.

Va primero porque **sin canal vivo, todo lo demás da igual.**

### Paso 2 · Que el veredicto de red no parpadee

En el Kotlin: **no mandar un veredicto igual al anterior**. Hoy manda uno por
cada `onCapabilitiesChanged`, y eso en datos móviles es constante.

Cierra el ciclo cada 11–38 segundos del §1.1. Es el arreglo más barato y el que
más datos ahorra hoy mismo.

### Paso 3 · El evento con grano fino, copiando a PEDIDO

**PEDIDO ya tiene esto resuelto** («tenemos SSE por pedido, refresca sólo una
sucursal y no todas»). El diseño sale de ahí, no de cero. Tres cosas:

1. **Qué cambió**, más fino que hoy: que tocar una ruta no mueva el Tablero.
2. **De dónde es**: la sucursal, y en el Tablero también el almacén de salida.
3. **Para quién**: el filtro va en el **servidor**, no sólo en el aparato. Saber
   que «cambió el tablero de Camagüey» ya es contar algo, y el alcance sale de
   quién pregunta y nunca de lo que mande el cliente (regla 1 de la casa, la que
   ya costó dinero con los precios de La Habana).

   `DESARROLLADOR` y `SUPER ADMIN` siguen viendo las ocho. Ojo con
   `ADMINISTRADOR`, que es de UNA sucursal.

Y el aviso de reconexión (`al-volver`) **no lleva sucursal y tiene que seguir
llegándole a todo el mundo**: significa «estuve desconectado», no «cambió algo».

### Paso 4 · Sacar los almacenes de cada vuelta

**Este paso decía otra cosa y era un error mío. Queda escrito porque la
investigación lo corrigió, y eso vale más que haberlo acertado.**

Decía: «que el ciclo baje sólo la colección que cambió». Al mirar cómo baja de
verdad (`nucleo/sincro/bajada.dart`), resulta que **`GET /api/sync/cambios` no
sirve una colección: sirve las OCHO de una vez**, con una sola marca de agua
(`desde`). Por eso una vuelta en vacío cuesta 584 bytes: es *una* petición que
contesta «no cambió nada» para todo.

Partirla por colección **no ahorraría nada y añadiría peticiones**. Descartado.

Lo que sí es desperdicio de verdad, y es el 82 % de lo que se gasta en reposo:
**`GET /almacenes` se pide en CADA vuelta**, fuera de `cambios`, y son 2.671 de
los 3.255 bytes. Los almacenes no cambian casi nunca.

Se piden cuando haga falta:

- la primera vez, o si la copia está vacía;
- cuando llegue su aviso (`almacenes`);
- y cada mucho tiempo como red de seguridad, porque **los almacenes viven en
  Accesos** y un cambio hecho allí no publica ningún aviso del reparto. Eso hay
  que tenerlo presente: sin ese suelo, un almacén nuevo tardaría en llegar.

### Paso 5 · Y entonces sí, fuera el reloj

Con el canal resistente (1), sin parpadeo (2), con avisos finos (3) y un ciclo
que sólo trae lo suyo (4), **el temporizador deja de ser el mecanismo**:

- **canal vivo → cero peticiones.** Los cambios llegan cuando pasan.
- **canal caído → despierta**, y sólo hasta que vuelva.

Eso es lo que pide Jose —«el reloj no lo quiero»— sin dejar ningún aparato ciego,
que es el único motivo por el que el reloj estaba ahí.

---

## 4. Lo que hay que decidir, y no lo decido yo

1. ~~**¿El aviso lleva la sucursal dentro?**~~ **DECIDIDO por Jose el 29/09/2026:
   filtra el SERVIDOR, por conexión.** Sus palabras: «la decisión, dale, para que
   haga correcto: más trabajo y sin fugas, exactamente eso».

   O sea que el servidor **no manda** a una conexión nada que no le toque. No es
   que el aparato descarte lo que no es suyo: es que no le llega. Saber que «en
   Camagüey pasó algo» ya es contar algo, y el alcance sale de quién pregunta.

   Lo que eso obliga a hacer, y por eso es más trabajo: cada conexión al canal
   tiene que llevar consigo **de quién es** —sucursal y rol, resueltos en el
   servidor con el mismo `alcance` que usan las demás rutas, nunca con lo que
   mande el cliente— y el bus de eventos tiene que repartir mirando eso.

   `DESARROLLADOR` y `SUPER ADMIN` reciben las ocho. Los otros cinco roles, la
   suya. Y ojo con `ADMINISTRADOR`, que es de UNA: una comprobación del tipo
   «¿contiene admin?» le daría las ocho, y ésa es la fuga.
2. **¿Qué grano exacto?** ¿`tablero` por sucursal, o por sucursal **y almacén**?
   El Tablero se ordena desde el almacén de salida, así que el almacén importa.
3. **¿Los almacenes salen del ciclo?** Hoy se piden en cada vuelta. Sacarlos
   ahorra el 82 % del tráfico en reposo, pero hay que asegurarse de que llegan
   igual el día que cambian.

---

## 5. Lo que ya está hecho de este plan

Sólo el **paso 1**. Todo lo demás está escrito y sin tocar.

---

# Lo que se aprendió probándolo contra producción — 29/09/2026, por la noche

El plan de arriba estaba bien pensado y **no funcionaba en la web**. Se vio poniendo
un agente con el navegador delante y otro con el teléfono de Jose, los dos a la vez.
Lo que se midió, y lo que costó cada cosa.

## 1. La web NUNCA abrió el canal. Ni una vez

No es que se cayera: **no nacía**. Tres medidas independientes, en producción:

- `/api/eventos` no aparece ni una sola vez en el panel de red;
- `performance.getEntriesByType('resource')` no tiene ni una entrada hacia `/eventos`;
- un espía puesto sobre el constructor `EventSource` registró **cero intentos** en hora y media.

**Cero errores en consola.** Fallaba en silencio absoluto, que es la forma de fallo que
este proyecto ya tiene escrita como la más cara.

La causa: `eventos_web.dart` se plantaba en un `if (token == null) return;` con un
comentario que daba por hecho que «en la web el token ya vive en `localStorage`». Eso
sólo es cierto por la **puerta de respaldo** (usuario y contraseña). Por la puerta
normal se entra por Accesos, y esa sesión es una cookie `httpOnly` que el JavaScript
no puede leer: `localStorage` está vacío **siempre**.

Y lo que duele: **ese token no hacía ninguna falta**. El servidor acepta
`Authorization: Bearer` **o la cookie `token`** (`internal/auth/auth.go`), y esa cookie
es la que ya deja puesta el login único (`internal/api/auth_web.go`). Con
`withCredentials: true` el navegador la manda solo. Estaba todo puesto; se plantaba
antes de intentarlo.

**La regla que queda:** una condición que decide si algo se intenta siquiera tiene que
probarse **con la forma de entrar de verdad**, no con la de las pruebas. Aquí había
pruebas del canal, verdes, todas con token — que es el único caso que en la web no se
da nunca.

## 2. Un canal sano se leía como muerto, y el reloj seguía pidiendo

`_ultimoDelCanal` sólo se apuntaba con un **`cambio`**. El latido de cada 20 s no
llegaba al vigía, así que un canal perfecto por el que no cambiaba nada en 6 minutos
se daba por muerto y el reloj pedía la vuelta entera. O sea: el polling seguía puesto,
sólo que más espaciado. Medido en la web, clavado a los 2 minutos:

```
20:07:42 → 20:09:40 → 20:11:41 → 20:13:40   GET /api/sync/cambios
```

Arreglado con `PulsoDelCanal`: una hora suelta que se marca con **cualquier** señal del
canal. **No viaja por el stream de los avisos, y es a propósito** — por ahí cada cosa
cuesta un ciclo más las peticiones de cada pantalla, así que un latido ahí sería una
bajada cada 20 segundos, lo contrario de lo que se pide.

Jornada de 8 h con el canal sano y sin un solo cambio en el servidor:

| | antes | ahora |
|---|---|---|
| web (periodo 2 min) | 240 ciclos | **0** |
| APK (periodo 5 min) | 96 ciclos | **0** |

## 3. El latido no se ve desde un navegador, y por eso deja de ser un comentario

`EventSource` **descarta los comentarios SSE** por especificación, y el latido salía
como comentario (`: latido`). En la APK daba igual —lee los bytes en crudo— pero en la
web el latido era invisible, así que allí el silencio del reloj colgaba del `listo` de
cada reconexión: el proxy corta cada **300 s** contra un plazo de **6 min**, o sea
**60 segundos de margen**. Con la conexión de allá eso se rompe: si la reconexión tarda
61 s son 9 ciclos de reloj en una jornada en vez de 0.

Por eso el latido pasa a ser un **evento con nombre**. Es el mismo tráfico por el socket
—sigue sirviendo para que un proxy no corte una conexión callada— y además se puede ver
desde el navegador.

Lo que NO se hizo, y conviene que quede escrito porque era lo fácil: **fiarse de
`readyState`**. Un `EventSource` medio muerto se queda en `OPEN` para siempre —el
navegador no le pone plazo—, así que el reloj se callaría eternamente y la web se
quedaría ciega **sin ninguna forma de volver**: ahí no hay aviso de red que valga ni
gesto para traer el día a mano. El reloj usa una petición HTTP aparte, que es justo lo
que sigue funcionando cuando ese socket ya no.

## 4. Ni la APK ni la web dejaban registro, y por eso no se podía contestar la pregunta

La pregunta de la noche era **«¿esto bajó porque lo empujó el canal o porque tocó el
reloj?»**, y no había forma de contestarla: la APK 1.0.17 no escribía **ni una línea**
en `logcat` —cero del proceso, cero con la etiqueta `flutter`, en cuatro mil renglones—
y la web tampoco en la consola.

Eran dos cosas a la vez: `developer.log` no llega a `logcat` en una compilación de
release (va al servicio de la máquina virtual, y en un aparato con la aplicación
instalada no hay nadie escuchando ahí), y además el nivel `info` se tiraba entero en
release — o sea justo «tocó el reloj», «canal de eventos: …», que son los que cuentan
la historia. Ahora se escribe también por la salida estándar, que el arrancador de
Flutter vuelca a `logcat`, y en la web sale por la consola del navegador:

```
adb logcat -s flutter | grep reparto
```

## 5. Y el almacén que no era: la pantalla no miraba la barra

Con **Santiago** puesto arriba, Almacenes listaba **los tres de Camagüey** — no uno.
`GET /api/almacenes` está bien y devuelve las ocho a propósito; era la pantalla, que
tenía su propio selector arrancando en «la primera de la lista». La primera que
devuelve Accesos es Camagüey, o sea la de nadie. Y no es cosmético: desde el almacén se
mide lo que se cobra por el domicilio.

La regla está en `cualSeConfigura`: manda lo que se elija a mano, luego **la barra**, y
sólo cuando arriba dice «Todas» se cae en la primera.
