# Trabajar sin señal

Ésta es la razón de ser de la aplicación de Android. **Con el día dentro, la
jornada entera funciona sin una raya de cobertura.**

---

## Cómo saber que estás sin señal

**La franja de arriba te lo dice en medio segundo.** Cuando se cae la red:

1. El icono pasa a ser una **nube tachada**.
2. Aparece **«Sin conexión»** en ámbar, **delante** de la hora.
3. La franja entera se pone en ámbar.

Y al volver la señal se quita **en menos de un segundo**, sola.

El Panel lo dice con más palabras:

> **Trabajando sin conexión**
>
> No hay conexión con el servidor. Puedes seguir trabajando: todo se guarda aquí y
> sube solo cuando vuelva la señal.

**No sale de si el teléfono cree que hay wifi**, sino de si las peticiones llegan de
verdad. En Cuba pasa mucho que el icono del wifi está encendido y no sale ni un
paquete: eso la aplicación lo detecta.

---

## Lo que SÍ puedes hacer sin señal

**El camino entero del día:**

- Ver el Panel, con sus cifras
- Ver el Tablero, filtrar, buscar
- **Crear zonas y ponerles camión**
- **Colocar pedidos en zonas, moverlos, subirlos, bajarlos, sacarlos**
- **Armar la ruta de una zona**
- Ver Rutas, filtrar, buscar, abrir el detalle
- **Armar una ruta con el asistente «Nueva Ruta»**
- **Iniciar una ruta**
- **Marcar las entregas, con su motivo**
- **Completar la ruta**
- **Eliminar una ruta** (planificada o en curso; una completada es histórico)
- **Quitar una parada de una ruta planificada**, con «Quitar de ruta»
- Ver el pre-despacho y el post-despacho, y sacar sus PDF
- Ver Pedidos, filtrarlos, abrir su detalle
- Ver Clientes, incluidos **los kilómetros**, que se calculan en el propio teléfono
- Ver Reportes (cuadrados con lo que tengas bajado)
- El mapa de la ruta: **las paradas, su orden y el recorrido se dibujan igual**. Si
  descargaste el mapa de Cuba, además con calles de fondo

---

## Lo que NO puedes hacer sin señal

| No se puede | Por qué |
|---|---|
| **Entrar** | «Para entrar hace falta conexión. Una vez dentro, no.» Es a propósito: si no, dar de baja a alguien no serviría de nada |
| **«Abrir en Google Maps»** y mandar el enlace por WhatsApp | Necesita el navegador y la red |
| **Vehículos**: dar de alta, editar, dejar inactivo, borrar, marcar disponible | Se configuran con conexión. No hay cola para esto |
| **Almacenes**: crear, editar, borrar | Viven en Accesos |
| **Buscar una dirección** en Almacenes | Pregunta a un servicio de mapas. Pero **tocar en el mapa y escribir las coordenadas sí funcionan** |
| **Sincronización** | Se lee del servidor cada vez, no guarda copia |
| **Traer el día** y **Entregar el día** | Los dos son gestos contra el servidor |
| **Ver el fondo de calles del mapa**, si no descargaste el mapa de Cuba | Las teselas vienen del servidor |

En los dos botones del día, el motivo sale escrito al lado: **«Sin conexión con el
servidor»**.

---

## Qué pasa al volver la señal

**Sube solo. No hay que tocar nada.**

Medido en el teléfono, en una prueba real:

1. Se trabajó sin señal: se armó una zona, se armó su ruta, se inició y se marcaron
   entregas. La franja decía **«2 sin subir»**.
2. Volvió la señal. El aviso de «Sin conexión» se fue en menos de un segundo.
3. **En unos 6 segundos**, sin tocar nada: la franja pasó a **«Todo al día»**.
4. Y la ruta, que se llamaba **`local-3df93810`**, pasó a llamarse
   **`RT-20260928-004`**.

**Ese cambio de nombre es normal.** La ruta es la misma; lo que pasa es que el
servidor le da su código de verdad al recibirla.

Aparte de eso, la aplicación **se pone al día sola cada 5 minutos** cuando hay
señal.

---

## Lo que queda en espera mientras no hay señal

Hay tres cosas que **se hacen en el teléfono al momento pero que el servidor todavía no
sabe**. Mientras no suban, el teléfono te enseña lo que tú hiciste, no lo que el
servidor tiene:

1. **Borrar una ruta que salió del tablero.** Las facturas vuelven a su zona del
   tablero, pero **hasta que suba el borrado y baje el tablero salen en «Sin colocar»**,
   no en su zona. No se han perdido. Con señal, se colocan solas donde estaban.
2. **Quitar una parada de una ruta planificada** («Quitar de ruta»). El pedido sale de
   la hoja y vuelve a disponibles al momento; si la ruta venía del tablero, su factura
   regresa a la zona **cuando suba el cambio**. Hasta entonces puede verse en «Sin
   colocar».
3. **Completar una ruta.** El teléfono la enseña como completada, pero eso todavía no
   confirma el cierre en el servidor: los estados de las paradas suben primero y el
   cierre después. Si el servidor rechaza una parada, **el cierre queda en la bandeja
   «Rechazados, esperando a una persona»** con su motivo, y la ruta no se completa en
   el servidor hasta que decidas con **«Reintentar»** o **«Descartar»** (en la web, en
   cambio, lo que se guardó vale). Ver [Si algo falla](5-si-algo-falla.md).

---

## El orden en que sube, y por qué importa

Cuando vuelve la red, la aplicación hace tres cosas **en este orden**:

1. **Comprueba la sesión** (después de horas sin red, el acceso hay que renovarlo).
2. **Sube lo que hiciste.**
3. **Baja lo nuevo.**

Primero sube y después baja, a propósito: si bajara primero, lo de allá pisaría lo
que acabas de hacer.

Por eso también, **a mano**, el botón de enviar se apaga si hay que traer el día
primero:

> «Trae el día primero: no se envía nada sin tener lo de ahora»

Enviar con el teléfono desfasado sube decisiones tomadas sobre datos viejos —un
pedido que aquí sale libre y allá ya entró en otra ruta—, y eso vuelve rechazado
horas después.

---

## Qué se puede perder, y qué no

**Lo único que se puede perder es lo que no ha subido.** Y no se pierde por sí solo:

- **Cerrar la aplicación no borra nada.** La sesión aguanta y la cola sigue entera.
- **Quedarse sin batería no borra nada.**
- **Cerrar sesión no borra la cola.** Te lo avisa: «Salir NO los borra: se quedan en
  este aparato hasta que vuelvas a entrar.»
- **Desinstalar la aplicación SÍ se lo lleva todo.** Nunca desinstales con trabajo
  sin subir.

---

## El aviso que hay que tomarse en serio

> **Hay trabajo que no va a subir solo**
>
> Está sólo en este aparato y no le queda ningún apunte que lo suba. No cierres
> sesión ni borres esta copia: avisa a la oficina para que lo rehagan.

En la franja sale como **«Sólo en este aparato: 1 ruta, 2 vehículos»**.

**No es «todavía no ha subido». Es «no va a subir».** Qué hacer:

1. **No cierres sesión. No desinstales.**
2. Conéctate: con señal, el sincronizador vuelve a encolar solo lo que sabe rehacer
   — las **zonas del tablero** suben solas así.
3. **Lo que siga saliendo ahí después de subir hay que volver a hacerlo con
   conexión.** Las rutas, los vehículos y los almacenes no se rehacen solos.
4. **Y cuando ya lo hayas rehecho, quita el aviso**: abre «Entregar el día», toca
   **«Dar por perdido: 1 ruta»** en ese mismo recuadro ámbar y confirma. No borra nada
   del aparato — sólo deja de avisar. Paso a paso en
   [Cuando algo sale mal](../comun/cuando-algo-sale-mal.md).

---

## Cuánto aguanta la sesión sin conectarse

**Treinta días sin conectarse ni una sola vez.** Un teléfono que coge señal cada
mañana se renueva indefinidamente y no caduca nunca.

Si pasan esos treinta días, hay que volver a entrar, y para eso hace falta señal. La
cola sigue entera: cuando entres, sube.

Y si te dan de baja en la oficina, tu teléfono deja de entrar **en cuanto tenga
señal**, no antes.
