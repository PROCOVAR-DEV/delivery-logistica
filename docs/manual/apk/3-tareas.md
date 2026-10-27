# Tareas sueltas

«Quiero hacer X»: dónde tocar, paso a paso.

---

## Cambiar de sucursal
<!-- tarea -->

**Empieza en:** la barra de arriba, desde cualquier pantalla.

**Sólo pueden `DESARROLLADOR` y `SUPER ADMIN`.** Los otros cinco roles tienen la
suya fija.

1. Arriba, a la izquierda de tu avatar, hay una pastilla con el código de la
   sucursal: **«STG»**, **«HAB»**…
   <!-- señala: barra-sucursal -->
2. **Tócala.** <!-- señala: barra-sucursal -->
3. Elige de la lista. La primera opción es **«Todas (8)»**.
   <!-- señala: barra-elegir-sucursal -->

**Ojo:** el Tablero **no funciona con «Todas»**. Te dirá «Elige una sucursal para ver
su tablero».

---

## Cambiar entre USD y CUP
<!-- tarea -->

**Empieza en:** la barra de arriba, desde cualquier pantalla.

1. Arriba, al lado de la sucursal, hay otra pastilla: **«USD»** o **«CUP»**.
   <!-- señala: barra-moneda -->
2. **Tócala** y elige. <!-- señala: barra-elegir-moneda -->
3. La opción de CUP lleva la tasa: **«1 USD = 320 · del 9/9/2026»**.
   <!-- señala: barra-elegir-moneda -->

Esa fecha no es un adorno: es lo único que demuestra que la tasa es de verdad.

### Si sólo te deja USD

La pastilla sale **en ámbar, con un icono de dinero tachado, y no se abre**. Su
motivo lleva el nombre de tu sucursal dentro:

> «Santiago no tiene tasa de cambio todavía: los importes sólo se pueden ver en
> USD.»

**No se convierte con la tasa de otra, a propósito.** Se arregla en Accesos — ver
[Dejar una sucursal lista para
trabajar](../comun/puesta-en-marcha.md#paso-4--la-tasa-de-cambio-de-la-sucursal).

### Si al lado de la pastilla sale un reloj ámbar

Sólo sale **mirando en CUP**, y quiere decir que la tasa está vieja:

> «La tasa es del 9/9/2026 y puede estar desfasada.»

**Se sigue usando** —una tasa de ayer convierte con un error pequeño; sin ninguna no
se puede convertir nada—, pero si vas a cobrar con ese número, pídela actualizada.

---

## Buscar una factura
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **Toca la caja de buscar** («Buscar») y escribe el cliente, el folio, la
   dirección, el municipio, el vendedor o un producto. **Busca solo**, sin darle a
   nada. <!-- señala: pedidos-buscar -->

### Si no aparece

Mira en este orden:

1. **La sucursal de arriba.** Es lo primero, siempre.
2. **La franja azul** de arriba. Al entrar, Facturas viene acotada: «Enseñando sólo lo
   que puede subir a un camión…». **Toca «Ver todas las facturas»**.
3. **Los filtros.** Si el vacío dice «Ninguna factura cuadra con estos filtros.», toca
   **«Quitar todos los filtros»**.
4. **Si ya está en una ruta**, mírala en Rutas.
5. **De cuándo son tus datos.** Si la franja dice «Datos de hace 9 h», esa factura
   puede haber entrado después: trae el día.

---

## Ver el detalle de una factura
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **Toca la tarjeta de la factura** (en el teléfono no hay tabla: cada factura es una
   tarjeta). <!-- señala: pedidos-abrir-el-pedido -->
   - Se abre un cajón con el cliente de título y el folio debajo. Dentro:
     **«Entrega»**, **«Recorrido»**, la banda de la factura, el bloque del domicilio
     y **«Productos (6)»**.

**Es de lectura.** Aquí no se edita nada de una factura: viene de PEDIDO. La única acción
es **«Ubicar la entrega»**: [poner a mano el punto de entrega](#poner-el-punto-de-entrega-de-una-factura-a-mano).

---

## Poner el punto de entrega de una factura a mano
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

**Para qué:** el cliente pide entregar en **otro sitio** y quien factura lo apunta en el
ticket. Esa dirección no coincide con la geolocalización del cliente (la única que
manda PEDIDO). **El logístico le pone el punto bueno a esa factura**, y desde entonces
manda sobre el del cliente: las rutas lo miden desde ahí y **no se pierde cuando el
cliente se vuelve a actualizar**.

1. **Toca la tarjeta de la factura** para abrir su ficha.
   <!-- señala: pedidos-abrir-el-pedido -->
2. En la sección **«Entrega»**, **toca «Ubicar la entrega»**.
   - Se abre un cajón titulado **«Ubicar la entrega»**, con el folio y el cliente
     debajo.
   - Si la factura **ya está entregada** o va en una **ruta completada**, no hay botón:
     en su lugar la ficha dice por qué («La factura ya está entregada: no se le puede
     cambiar el punto» / «La ruta ya está completada: no se le puede cambiar el punto a
     sus paradas»). Son histórico.
3. Pon el punto de **una de las tres formas** (las tres escriben en la misma caja de
   **«Coordenadas»**, y lo que se guarda es lo que ponga ahí; puedes buscar y luego
   corregir a mano):
   - **Escribe las coordenadas** en **«Coordenadas»**, así: `19.83, -75.82`. Si no se
     entiende, debajo pone «No se entiende. Escríbelo como «19.83, -75.82».»
   - **Toca en el mapa**, en el sitio de la entrega. Debajo sale «Punto puesto en
     20.02470, -75.82190.».
   - **Escribe la dirección** en **«Dirección»** y **toca «Buscar»** (hacen falta al
     menos 4 letras). Mira el punto en el mapa antes de guardar.
4. **Escribe la dirección de la entrega** en **«Dirección»**, si el mapa no la trajo.
   **Vacía, se queda la que tenía.**
5. **Toca «Guardar punto»**. No se enciende hasta que algo cambie.
   - **Funciona sin señal.** Se guarda en el teléfono, la parada ya sale con su punto
     nuevo y el cambio **sube cuando vuelve la señal**; al subir, el servidor repite las
     cuentas y manda lo suyo (los km del domicilio, que el teléfono no recalcula, se
     ponen entonces). Pulsar en el mapa y escribir las coordenadas funcionan siempre;
     **«Buscar» necesita señal** y, sin ella, lo dice y deja el punto como estaba.
   - Si al subir el servidor dice que no (por ejemplo, la ruta se completó entretanto),
     el cambio queda en la bandeja con su motivo, como cualquier otro.

Qué cambia:

- La ficha (y la tarjeta de la parada, en Rutas) lleva la etiqueta **«Punto puesto a
  mano»**.
- **En el mapa de la ruta, el número de esa parada sale en ROJO**, y su globo dice
  «Punto puesto a mano». La leyenda de abajo lo explica.
- Los **km de esa parada** y el **total de la ruta** se vuelven a medir desde el punto
  nuevo (si la ruta ya está armada y no está completada), y la distancia del domicilio
  también. **El orden de las paradas no se toca**: si ya no es el mejor, reordénalas
  tú.

### Volver al punto del cliente

1. Abre otra vez **«Ubicar la entrega»** en esa factura: ahora trae también **«Volver al
   punto del cliente»**.
2. **Toca «Volver al punto del cliente»**. **Pregunta antes**, en un cajón: dice a qué
   punto vuelve y que los km se miden otra vez.
3. **«Sí, volver al punto del cliente»** o **«No, dejar el punto a mano»**.

Si la factura no tiene punto a mano, el servidor lo dice: «La factura no tiene un punto
puesto a mano».

### Desde una ruta o desde el asistente

El **mismo cajón** se abre desde otros dos sitios, sin salir de lo que estás haciendo:

- **En Rutas**, en el detalle de la ruta → **«Ver paradas»** → en la tarjeta de la
  parada, **«Ubicar la entrega»** (junto a «Quitar de ruta"). No sale en una ruta
  completada ni en una parada ya entregada.
- **Al armar una ruta**, en el paso **«Facturas»** del asistente, cada fila lleva un
  botón pequeño con el tooltip **«Ubicar la entrega»**. Pulsarlo **no marca ni desmarca**
  la factura.

**Una limitación:** una factura que PEDIDO manda **sin coordenadas** no llega a esta
aplicación, así que no se puede abrir. Esto sirve para **cambiar** el punto de una
factura que ya tiene uno.

---

## Juntar facturas en un conduce
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

Un conduce es lo que sale con el camión y puede juntar varias facturas **del mismo
cliente** en UNA parada. **La primera que marcas es la principal**: la que lo crea y dice a
qué cliente va dedicado. **Funciona sin señal**: se guarda en el teléfono y sube cuando
haya.

1. **Toca la casilla de las facturas** que van juntas. La **primera** que toques será la
   principal. <!-- señala: pedidos-marcar-uno -->
2. **Toca «Crear conduce»**, en la franja azul de lo marcado (sale con dos o más).
   <!-- señala: pedidos-crear-conduce -->
   - Se abre el cajón **«Crear conduce»**: **«La principal será 47313 (Cliente). Las demás
     irán con ella»**.
3. **Toca «Crear conduce»**, abajo del cajón. <!-- señala: pedidos-confirmar-conduce -->
   - La principal pasa a decir **«Conduce 47313 + 47314»** con el peso y el domicilio de
     todas. Las demás **ya no salen como tarjetas**: van con ella.

**Si no se puede, el cajón lo dice y el botón queda apagado:** clientes distintos, otra
sucursal, o una factura que ya va en una ruta, ya se entregó o ya va en otro conduce.

**Si el servidor lo rechaza al subir** (porque en la oficina alguien movió una de las
facturas), el cambio queda en la bandeja de errores de **«Sincronización»** con su motivo,
sin perderse, hasta que decidas.

**Al armar una ruta o mandar a una zona, elige la principal**: el conduce entero se mueve
con ella y es UNA parada. En el cierre, lo que marques en esa parada vale para todas sus
facturas.

---

## Sacar una factura de un conduce o deshacerlo
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **En «Facturas», pasa a la pestaña «Conduces»** (la flecha de las bolitas).
   <!-- señala: pedidos-pestanas -->
2. **«Sacar»**, al lado de una factura, la devuelve a ser una factura suelta.
3. **«Deshacer conduce»** suelta todas. <!-- señala: pedidos-deshacer-conduce -->
   - También está en la ficha de la principal (toca su tarjeta).

**No se puede sacar ni deshacer un conduce que ya va en una ruta o tiene resultado**: el
botón sale apagado y dice por qué.

---

## Mandar varias facturas a una zona de golpe
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

Éste es el atajo para no ir tarjeta por tarjeta en el Tablero.

1. **Filtra por municipio** para dejar las que quieres (o por vendedor, o por
   día). <!-- señala: pedidos-filtro-municipio -->
2. **Toca arriba «Elegir los 50 de esta página»** para marcarlos todos.
   <!-- señala: pedidos-marcar-todos -->
   - O **toca la casilla de cada factura**, una a una.
3. **Toca la casilla de una factura** para quitar o poner la marca de esa sola.
   <!-- señala: pedidos-marcar-uno -->
   - Aparece una franja azul: **«7 factura(s) elegidas»**.
4. **Toca «Mandar a una zona»**, en esa franja.
   <!-- señala: pedidos-mandar-a-una-zona -->
   - Se abre el cajón **«Mandar a una zona del tablero»**: «Se colocan en el orden en
     que están marcados, y el gesto es el mismo que arrastrarlos: se guarda aquí y
     sube cuando haya señal.»
5. **Toca la zona** de la lista. Debajo de cada una pone «12 factura(s) puestas».
   <!-- señala: pedidos-zona-destino -->
   - Si no hay ninguna, toca **«Crear una zona nueva»**, escribe el nombre y
     **«Crear»**.
6. **Toca «Mandar a la zona»** abajo. <!-- señala: pedidos-mandar -->
   - Te dice cómo fue: **«5 factura(s) en «Centro»»**.

### Si alguna se queda fuera

En ámbar: **«No se pudieron mandar 2, y siguen marcados:»** y debajo, una a una:

```
PTB25-261005-1480 · Ana: Esa factura ya está en una ruta
PTB25-261005-1502 · Luis: Esa factura va dentro del conduce 47313: arma el conduce entero
```

Cada factura sale por su **conduce** (el número de operación de la factura). Los motivos
son los mismos que daría el servidor: ya entregada, ya en una ruta o miembro suelto de
un conduce, además de «Archivado en PEDIDO», «Sin cotejar», «Sin factura», «Sin
coordenadas de entrega» o «Es de otra sucursal». **El domicilio sin cobrar o sin cotizar
ya no es un motivo.**

**Las que sí fueron pierden la marca; las que no, se quedan marcadas** para que
puedas seguir con ellas.

---

## Sacar el pre-despacho de lo que tienes filtrado
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **Filtra por municipio** lo que quieras (o por día).
   <!-- señala: pedidos-filtro-municipio -->
2. **Toca el botón «Pre-despacho»**, en la misma fila que las fechas.
   <!-- señala: pedidos-pre-despacho-de-lo-filtrado -->
   - La suma **se hace al pulsar**, no antes. Al terminar, el botón pasa a
     **«Pre-despacho · 24 productos»** y se abre el cajón.
   - Dentro: el resumen, la tabla por producto, los cuatro totales y **«Ver e
     imprimir»** para la hoja en PDF.

---

## Renombrar, vaciar o borrar una zona
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

1. **Desliza hasta la página de la zona**, con las flechas o las bolitas de abajo.
   <!-- señala: tablero-carrusel-de-zonas -->
2. **Toca el ⋮** de la cabecera, arriba a la derecha de la zona.
   <!-- señala: tablero-menu-de-la-zona -->
3. Para cambiarle el nombre, **toca «Renombrar»**.
   <!-- señala: tablero-renombrar -->
4. **Escribe el nombre nuevo** en «Nombre de la zona».
   <!-- señala: tablero-nombre-de-la-zona -->
5. **Toca «Guardar»**. <!-- señala: tablero-guardar-la-zona -->
6. Para devolver sus tarjetas a «sin colocar», en el mismo ⋮ **toca «Vaciar»**.
   <!-- señala: tablero-vaciar -->
   - **«Mover todo a otra columna»**, al lado, te saca la lista de destinos con
     cuántas facturas tiene cada uno.
7. Y para quitar la zona entera, **toca «Borrar la columna»**.
   <!-- señala: tablero-borrar-la-zona -->

### Al borrar

**Si la zona está vacía:**

> «La zona se va del tablero. No hay ninguna factura dentro, así que no se pierde
> trabajo del día, pero la zona hay que volver a crearla a mano con su nombre.»

Botones: **«Sí, borrar «Centro»»** y **«No, dejarla»**.

**Si la zona tiene facturas**, no te deja borrarla sin decidir qué pasa con ellas:

> **«Centro» tiene 8 facturas puestas** — ¿Qué se hace con ellas?

Y dos salidas: **«Devolver las 8 facturas a «Sin colocar» y borrar»** o **«Mover las 8 facturas a otra
zona y borrar»**. Cuenta las que cuenta el servidor, también las que este aparato no ve (por ejemplo, facturas ya archivadas): lo dice debajo.

Y una tercera, **«Inactivar la zona»**: la quita del tablero y sus facturas vuelven a
«Sin colocar», pero **se conserva** (con su nombre y su historia de rutas). Para
volver a usarla, arriba **«Zonas inactivas»** y **«Activar»**; vuelve vacía. Funciona
sin señal y sube después.

---

## Reordenar las zonas
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

**No se puede desde el teléfono.** Las zonas se reordenan arrastrando su cabecera, y
eso sólo funciona en pantalla grande (la web o el escritorio).

---

## Armar una ruta sin usar el Tablero
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

Es el camino largo. Sirve cuando la ruta no sale de una zona entera.

1. Arriba, **toca «+ Nueva Ruta»**. <!-- señala: rutas-nueva-ruta -->
   - Se abre un cajón a pantalla completa, **«Nueva Ruta»**, con cuatro tramos
     arriba: **«Sucursal» · «Salida» · «Vehículo» · «Facturas»**.
2. **Paso «Sucursal»** — elige en **«Sucursal de la ruta»**.
   <!-- señala: rutas-asistente-sucursal -->
   - Suele venir rellena con la de arriba.
   - **Cambiarla borra todo lo que hayas elegido después.**
3. **Toca «Siguiente»**, abajo a la derecha de la tarjeta.
   <!-- señala: rutas-asistente-siguiente -->
   - Los pasos 2 y 3 llevan su propio **«Siguiente»** en el mismo sitio.
4. **Paso «Salida»** — elige en **«Almacén del que sale el camión»** y toca
   **«Siguiente»**. <!-- señala: rutas-asistente-almacen -->
   - Sólo salen almacenes **con coordenadas**.
   - Si no hay ninguno: «Esta sucursal no tiene ningún almacén con ubicación. Los
     almacenes se ponen en el CRM…» y un botón **«Ver los almacenes»** (lleva a la
     pantalla de consulta).
5. **Paso «Vehículo»** — elige en **«Vehículo de la ruta»** y toca **«Siguiente»**.
   **Es obligatorio.** <!-- señala: rutas-asistente-vehiculo -->
   - Cada uno sale con su capacidad: «1000 kg», «1000 kg · en el taller», «1000 kg ·
     en ruta». **Se pueden elegir todos los que están activos.**
   - **Un camión «Inactivo» (dado de baja) no sale en la lista.** Si no ves el que
     buscas, mira en **Menú → «Vehículos»** si está dado de baja.
   - Si eliges uno del taller sale un **aviso en ámbar**, pero **se arma igual**: es
     aviso, no bloqueo. Dice que el camión está marcado «EN EL TALLER» y que no puede
     salir hoy; si ya volvió, sácalo del taller en Vehículos.
   - Si no queda ninguno: «Los vehículos de esta sucursal están inactivos, y a una
     ruta nueva sólo se asigna un vehículo activo. Actívalo en Vehículos.»
   - Puedes ponerle un nombre («Nombre (el código se genera solo)») y cambiar la
     **«Fecha de entrega»**, que **viene puesta en hoy**.
6. **Paso «Facturas»** — busca y **marca las que quieras**.
   <!-- señala: rutas-asistente-buscar -->
   - En el teléfono los filtros van **uno por línea**: sucursal, día, buscador,
     vendedor, municipio, «km máx.», «costo mín.», estado, domicilio y cotización.
   - **Sólo salen las facturas facturadas (cuadren o no).** Ya no se exige el domicilio
     cobrado ni cotizado. Pero el filtro de domicilio arranca en «Sólo con domicilio», que
     cuenta lo marcado por el vendedor **o** lo cobrado en la factura: si te falta una que
     ni el vendedor marcó ni la factura cobró, elige **«Con y sin domicilio»**.
   - **Mira la barra de capacidad**: «115.6 / 10000 kg (1%)». Al 100 % sale **«LLENO»**
     y **«Camión lleno — no cabe más»**.
   - **Las filas de las facturas que ya no caben se apagan**, con el motivo: «No cabe
     en el camión».
   - Puedes marcar **una zona entera del tablero** tocando su casilla. Te dirá qué
     entró: **«9 de 12 de «Vista» · 1 ya estaban · 1 ya no se pueden repartir hoy · 1
     no caben en el vehículo»**.
7. **Toca «Pre-despacho de los N elegidos»** si quieres la hoja del almacén antes de
   armar. <!-- señala: rutas-pre-despacho -->
8. **Toca «Generar Ruta»** abajo. <!-- señala: rutas-asistente-generar -->

### Si «Generar Ruta» está apagado

Falta algo: salida, camión, alguna factura, o te has pasado de peso.

### Si sale un aviso en ámbar encima del botón

Te dice exactamente qué pasa, y cada factura sale por su **conduce** (el número de
operación de la factura). **Sin señal sale igual**: la aplicación lo dice antes de
guardar la ruta, para que no te llegue horas después a la bandeja de rechazados. Los
más comunes:

| Aviso | Qué hacer |
|---|---|
| **«Se requiere un vehículo para crear la ruta»** | Vuelve al paso «Vehículo» |
| **«En una ruta sólo entra lo facturado. 3 no cumplen: PTB25-261005-1480 (sin facturar)…»** | Desmarca esas tres |
| **«El vehículo está inactivo y no se puede asignar a una ruta.»** | Ese camión está dado de baja. Elige otro |
| **«2 de las 12 facturas elegidas no pueden ir en esta ruta: PTB25-261005-1480 (ya va en la ruta RT-20260922-003)…»** | Desmarca ésas |
| **«Peso total (1250.5 kg) supera la capacidad del vehículo (1000 kg)»** | Quita facturas o cambia de camión |

Para volver a un tramo anterior, **toca su nombre** en la barra de arriba
(«Vehículo», «Salida»…), o dale al botón «atrás» del teléfono, que **va al paso
anterior y no cierra el asistente**.

---

## Eliminar una ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. **Toca la tarjeta de la ruta** y mira que es la que quieres: el código está
   arriba. <!-- señala: rutas-tarjeta-de-ruta -->
   - Antes, **desliza a la pestaña** donde esté: **«Planificadas»** o **«En curso»**.
2. Al final de su tarjeta, **toca «Eliminar»** (el botón rojo, con contorno y
   papelera, sin relleno). <!-- señala: rutas-eliminar -->
   - **Se abre un cajón que pregunta antes**, titulado
     **«Borrar «RT-20260928-004»»**. Dentro te dice lo que se pierde:

   > «La ruta desaparece con su código, su fecha, el orden de visita y los
   > kilómetros que se calcularon al armarla. Para tenerla otra vez hay que volver a
   > armarla desde el asistente, a mano.
   >
   > Lo que NO se borra son las facturas ni sus resultados: sueltan esta ruta. Las
   > pendientes vuelven a la lista de disponibles; las entregadas siguen entregadas y
   > no se reparten otra vez. Y el camión se queda libre.
   >
   > Si la ruta se armó desde una zona del tablero, las facturas vuelven a esa zona
   > cuando se sincronice el borrado (en la web, de inmediato). Mientras tanto, sin
   > señal, salen en «Sin colocar».»

3. **Toca «Sí, borrar «RT-20260928-004»»** para borrarla, o **«No, dejarla»**
   para salir. <!-- señala: confirmar-el-borrado -->

> **Ojo:** **cerrar el cajón sin contestar es NO.** La ✕ de la cabecera, tocar
> fuera o la tecla Escape dejan la ruta donde estaba. Lo irreversible no se hace por
> un descuido.

### Cuándo se puede borrar

Una ruta **planificada o en curso se puede eliminar**, aunque no tenga paradas
cargadas o ya haya marcas de entrega, devolución o cancelación. Las marcas son
provisionales mientras no se complete la ruta.

**Las rutas completadas no se pueden editar ni eliminar**: forman el histórico,
y el botón «Eliminar» no aparece. Su cierre sólo se consulta.

Al eliminar la ruta no se borra ninguna factura ni se cambia su resultado. Las
pendientes y devueltas quedan disponibles; las ya entregadas siguen entregadas
y no se vuelven a repartir.

### Si la ruta se hizo desde el tablero

**Las facturas vuelven a su zona del tablero**: no se pierde la relación y no hay que
volver a crear la zona ni a repartir las facturas.

- **Con señal**, en cuanto sube el borrado y baja el tablero, cada factura aparece en su
  zona.
- **Sin señal**, el borrado queda en espera en el teléfono y **las facturas salen en
  «Sin colocar»** hasta que suba y baje el tablero. No es que se hayan perdido: es que
  el servidor todavía no se ha enterado. Cuando vuelva la señal (casi nunca hace falta
  pulsar nada), se colocan solas donde estaban.
- Si la ruta **no** salió del tablero, no hay zona a la que volver: las facturas vuelven
  sólo a la lista de disponibles.
- **Una ruta completada es histórico y no se borra.**

---

## Sacar una factura de una ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

En una ruta **planificada** (que todavía no ha salido) se puede quitar **una sola
parada**, sin borrar la ruta.

1. **Desliza a «Planificadas»** y **toca la tarjeta de la ruta**.
   <!-- señala: rutas-tarjeta-de-ruta -->
2. En el detalle, **toca «Ver paradas»**. <!-- señala: rutas-ver-paradas -->
3. En la tarjeta de la parada que sobra, **toca «Quitar de ruta»**.
   - Se abre un cajón, **«Quitar de la ruta»**, con el cliente y su conduce debajo
     («Casa Pérez · Conduce: PTB25-261005-1480»), que dice qué pasa:

   > «Casa Pérez sale de esta ruta y vuelve a facturas disponibles. La ruta se queda
   > con las demás paradas y su peso y su importe se recalculan sin él.
   >
   > Si la ruta se armó desde una zona del tablero, la factura regresa a esa zona
   > cuando se sincronice (en la web, de inmediato).»

4. **Toca «Sí, quitar «Casa Pérez» de la ruta»**, o **«No, dejarlo en la ruta»**.
   **Cerrar el cajón sin contestar es No.**

La parada desaparece de la hoja, y el peso y el importe de la ruta se recalculan sin
ella. La factura **vuelve a la lista de disponibles** y, si la ruta nació del tablero,
**a su zona del tablero**.

**Funciona sin señal**: el cambio se guarda en el teléfono, queda en espera y **sube
cuando vuelve la señal**. Hasta entonces la factura puede verse en «Sin colocar» y no
en su zona.

**Sólo en una ruta planificada.** En una ruta **en curso** no hay botón: marca esa
factura como devuelta o cancelada al completar la ruta, y queda libre para mañana. Una
ruta **completada** es histórico y no se toca. Si el servidor lo rechaza al subir,
dice el motivo en la bandeja: «Sólo se pueden retirar paradas de una ruta planificada»
o «La factura no pertenece a una ruta planificada o ya fue retirada».

(Y si lo que sobra es la ruta entera, [elimínala](#eliminar-una-ruta).)

---

## Cambiar el camión de una ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

**No se puede.** Una ruta ya armada no deja cambiarle el camión: no hay ningún botón
para eso, ni en la tarjeta ni dentro del cajón del detalle. Las dos salidas:

**Si la ruta todavía no ha salido (pestaña «Planificadas»):**

1. **Desliza a «Planificadas»** y **toca la tarjeta de la ruta**.
   <!-- señala: rutas-tarjeta-de-ruta -->
2. **Toca «Eliminar»** al final de su tarjeta y confirma — ver [Eliminar una
   ruta](#eliminar-una-ruta). Las facturas pendientes quedan disponibles; las entregadas conservan su
   resultado. El camión queda libre. Si la ruta salió del tablero, **las facturas
   vuelven a su zona** (sin señal, salen en «Sin colocar» hasta que suba el borrado).
   <!-- señala: rutas-eliminar -->
3. Vete a **Menú → «Tablero»** y **desliza a la página de la zona**.
   <!-- señala: tablero-carrusel-de-zonas -->
4. **Toca el ⋮** de la cabecera. <!-- señala: tablero-menu-de-la-zona -->
5. **Toca «Camión previsto»** y elige el otro camión (**activo**; si está en el taller
   sale marcado en ámbar, y se puede elegir igual). <!-- señala: tablero-camion-previsto -->
6. Otra vez **⋮** y, abajo del cajón, **«Armar la ruta de esta zona»**.
   <!-- señala: tablero-armar-la-ruta -->

**Si la ruta está «En curso»**, también se puede eliminar con confirmación y armar
otra para las facturas pendientes. Los resultados anteriores se conservan.
**Si está completada**, no se modifica ni elimina: conserva su camión como histórico.

> **Ojo:** mandar un camión al taller **no** le quita la ruta. La aplicación lo dice
> en su tarjeta: «mandarlo al taller no la cierra, porque una ruta cerrada es una
> ruta repartida».

---

## Consultar un cliente
<!-- tarea -->

**Empieza en:** **Menú → «Clientes»**.

1. **Menú → «Clientes».** <!-- señala: menu-clientes -->
2. **Toca la caja de buscar** («Buscar por nombre, dirección o municipio…»). Busca
   también por teléfono, código, zona y vendedor.
   <!-- señala: clientes-buscar -->
3. **Toca la tarjeta del cliente.** Se abre su ficha, con el **teléfono el primero**.
   <!-- señala: clientes-abrir-el-cliente -->

**Los clientes no se crean, ni se editan, ni se borran aquí.** Vienen de PEDIDO.

Y sólo aparecen los que **tienen geolocalización**.

---

## Dar de alta un camión
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**.

**Esto necesita señal.** Vehículos no se guarda en el teléfono.

1. **Toca «Agregar Vehículo»**, arriba a la derecha.
   <!-- señala: vehiculos-agregar -->
2. Escribe el **«Nombre del Vehículo *»**. Es obligatorio: «Ej: Camión #1, Furgoneta
   Azul». <!-- señala: vehiculos-nombre -->
3. Elige el **«Tipo»**. Al elegirlo **hereda su costo por km**.
   <!-- señala: vehiculos-tipo -->
4. Escribe la **«Placa (opcional)»**. <!-- señala: vehiculos-placa -->
5. Pon la **«Capacidad Máx. (kg)»**. Viene en 1000.
   <!-- señala: vehiculos-capacidad -->
6. Mira el **«Estado del vehículo»**: sólo hay **«Disponible»** y **«En
   mantenimiento»**. <!-- señala: vehiculos-estado -->
7. Pon el **«Costo por km (USD)»**. <!-- señala: vehiculos-costo-por-km -->
8. **Toca «Agregar Vehículo»** abajo. Vas a ver **«Vehículo agregado.»**
   <!-- señala: vehiculos-guardar -->

**El interruptor «Vehículo activo»** viene encendido: un camión nuevo se ofrece en las
rutas nuevas. Se apaga más adelante si hay que darlo de baja (ver [Dejar un camión
inactivo](#dejar-un-camión-inactivo)).

### Si no sabes el costo por km

**Déjalo vacío, nunca en cero.** Un cero se lee como «el kilómetro es gratis» y se
propaga al precio del domicilio.

O usa el ayudante: **toca «¿No sabes el costo por km?»**, escribe **«El camionero
cobra (CUP)»** (por ejemplo 180000) y **«hasta ___ km (ida)»** (por ejemplo 72), y
toca **«Calcular»**. Te rellena el campo.

## Marcar un camión en el taller
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

1. En su tarjeta, **toca «Editar»**. <!-- señala: vehiculos-editar -->
2. En **«Estado del vehículo»**, elige **«En mantenimiento»**.
   <!-- señala: vehiculos-estado -->
3. **Escribe el motivo en «Notas»**. Es lo único que le dice al de al lado por qué
   no puede contar con él. <!-- señala: vehiculos-notas -->
4. **Toca «Actualizar»** abajo. <!-- señala: vehiculos-guardar -->

**Marcarlo en el taller NO cierra la ruta que ya tuviera abierta.** Eso se arregla en
la tarjeta del camión.

**Mientras esté en mantenimiento se sigue ofreciendo para rutas nuevas, pero con un
aviso en ámbar**: sale con «en el taller» en el paso «Vehículo» de «Nueva Ruta» y en el
«Camión previsto» del Tablero. Es aviso, no bloqueo: así una sucursal con un solo camión
olvidado en el taller no se queda sin poder armar rutas. Cuando vuelva, pásalo otra vez a
**«Disponible»**.

## Liberar un camión que sale ocupado y no lo está
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

Su tarjeta lo dice:

> «El estado guardado dice «en uso» y no lleva ninguna ruta abierta. Márcalo
> disponible: hasta entonces sale como ocupado al elegir camión.»

1. **Toca «Marcar disponible»** en esa misma tarjeta.
   <!-- señala: vehiculos-marcar-disponible -->

---

## Decir qué camión calcula el domicilio
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

De este camión sale **el costo por km con el que se le cobra al cliente el
domicilio**. No está en el paso a paso del Panel, pero decide dinero.

1. Busca la tarjeta del camión y **toca «Usar para domicilio»**, debajo del nombre,
   en la fila de pastillas. <!-- señala: vehiculos-usar-para-domicilio -->
   - Si ahí pone **«Cálculo domicilio · $1.65/km»** con una casita, ya es el que
     calcula y el botón no está.
   - Abajo sale **«Se usará este vehículo para calcular el domicilio.»**
2. También se puede desde la ficha: **toca «Editar»** en su tarjeta.
   <!-- señala: vehiculos-editar -->
3. Marca la casilla **«Usar este vehículo para calcular el domicilio»**. Debajo pone
   **«Solo un vehículo por TIPO.»** <!-- señala: vehiculos-calcula-el-domicilio -->
4. **Toca «Actualizar»** abajo. <!-- señala: vehiculos-guardar -->

> **Ojo:** si la pastilla dice **«Cálculo domicilio»** **y no lleva importe
> detrás**, ese camión está elegido y **no tiene costo por km**. Edítalo y ponle
> uno: así es como un domicilio sale sin precio teniendo camión.

---

## Dar de baja un camión
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

**Si el camión ya tiene rutas, aunque sean del histórico, NO se puede borrar: se deja
«Inactivo»** ([cómo, aquí abajo](#dejar-un-camión-inactivo)). Borrar sólo sirve para un
camión que nunca se usó (uno dado de alta por error, por ejemplo).

1. Busca la tarjeta del camión y **comprueba el nombre y la placa** antes de nada.
   Al final de la tarjeta, **toca «Eliminar»** (rojo, con contorno y papelera, sin
   relleno). <!-- señala: vehiculos-eliminar -->
   - **Se abre un cajón que pregunta antes**, titulado **«Borrar «Camión 1»»**,
     y dice lo que se pierde:

   > «El camión se va de la flota y hay que volver a darlo de alta a mano, con su
   > placa, su capacidad y su costo por km.
   >
   > Un camión que ya tiene rutas —aunque sean del histórico— NO se puede borrar: el
   > servidor lo rechaza para no perder qué camión hizo cada reparto. Si ese es el
   > caso, no lo borres: ábrelo con «Editar» y márcalo como inactivo. Así deja de
   > ofrecerse en las rutas nuevas y su historial se queda intacto.»

2. **Toca «Sí, borrar «Camión 1»»**, o **«No, dejarlo»** para salir. Sale
   **«Vehículo eliminado.»** y la tarjeta desaparece.
   <!-- señala: confirmar-el-borrado -->

Si el camión tenía rutas y tocaste «Sí», el servidor no lo borra y lo dice:

> «No se puede eliminar este vehículo porque tiene rutas asociadas, incluso
> históricas. Márcalo como inactivo para impedir que se use en nuevas rutas.»

> **Ojo:** **cerrar el cajón sin contestar es NO** — la ✕, tocar fuera, Escape. Y si
> era el camión del **«Cálculo domicilio»**, elige otro antes de irte: sin ninguno,
> los domicilios salen sin precio.

---

## Dejar un camión inactivo
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

Es la forma de dar de baja un camión que **ya se usó**: deja de ofrecerse para rutas
nuevas y su historial se queda intacto.

1. En su tarjeta, **toca «Editar»**. <!-- señala: vehiculos-editar -->
2. **Apaga el interruptor «Vehículo activo»**, justo debajo del nombre. Debajo pone:
   «Se oculta de los selectores de rutas nuevas.»
3. **Toca «Actualizar»** abajo. <!-- señala: vehiculos-guardar -->
   - Sale **«Vehículo actualizado.»** y la tarjeta lleva la insignia **«Inactivo»**.

**Qué cambia:** el camión **ya no sale** en el paso «Vehículo» de «Nueva Ruta» ni en el
«Camión previsto» de las zonas del Tablero. (Con el taller no pasa: un camión en
mantenimiento sí sale, con su aviso; el que nunca se ofrece es el inactivo.) **Sigue
viéndose** en el filtro «Rutas de un camión», en los informes y en las rutas que ya hizo.

**Para recuperarlo**, vuelve a **«Editar»** y enciende el interruptor.

> **Ojo:** «Inactivo» no es lo mismo que «En mantenimiento». El mantenimiento es un
> camión que va a volver y **se ofrece con un aviso**; inactivo es una baja y **no se
> ofrece nunca**.

---

## Definir los tipos de camión y su costo por km
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

El tipo es **el punto de partida del costo por km**: un camión de ese tipo lo hereda,
y luego se puede cambiar camión por camión.

1. Arriba, en la misma fila que la caja de buscar, **toca «Tipos de vehículo»**.
   <!-- señala: vehiculos-tipos -->
   - Se abre el cajón **«Tipos de vehículo»**, que empieza diciendo para qué es:
     «Define cada tipo con su costo por km por defecto. Al crear un vehículo de ese
     tipo se hereda el costo/km (editable por vehículo).»
2. Escribe el **«Nombre»** del tipo. <!-- señala: vehiculos-tipo-nombre -->
3. Escribe su **«Costo/km (USD)»**. La papelera (**«Quitar»**) borra la fila.
   <!-- señala: vehiculos-tipo-costo -->
4. Para otra fila, **toca «Agregar tipo»**, abajo.
   <!-- señala: vehiculos-anadir-tipo -->
5. Al pie, **toca «Guardar»** (al lado de **«Cancelar»**). Sale **«Tipos
   guardados.»** <!-- señala: vehiculos-guardar-tipos -->

> **Ojo:** **las filas sin nombre no se guardan.** Y un costo que no sepas **se deja
> vacío, nunca en cero**: un cero se lee como «el kilómetro es gratis».

**Si no hay ninguno**, el cajón pone **«Sin tipos. Agrega el primero.»**

### El atajo desde la ficha de un camión

En la ficha de un vehículo, **el desplegable «Tipo» tiene como última opción «+ Crear
tipo nuevo…»**. Ábrela, escribe **«Nombre del tipo»** y su **«Costo/km (USD)»**, y
**toca «Crear tipo»**. El tipo queda elegido y su costo se copia al campo del camión.

---

## Consultar los almacenes de una sucursal
<!-- tarea -->

**Empieza en:** **Menú → «Almacenes»**. **Necesita señal.**

**Los almacenes ya no se crean, se editan ni se quitan desde aquí: se editan en el
CRM.** Esta pantalla es de solo lectura, y arriba lo dice: «Los almacenes se editan
en el CRM. Aquí solo se consultan.» Si la aplicación trae la dirección del CRM
puesta, al lado sale **«Abrir el CRM»**.

1. Elige la sucursal arriba, si hay más de una.
   <!-- señala: almacenes-sucursal -->
2. Mira la lista. Cada renglón dice la dirección, las coordenadas (o **«sin punto»**),
   el código, si es el **principal** (lleva estrella) y si está **inactivo**.

**Un almacén sin punto no sirve para cotizar**: desde él no se puede medir el
domicilio. Si falta uno, o hay que corregir un punto, se arregla en el CRM.

> **Ojo:** el teléfono mide con los almacenes que bajó la última vez que tuvo red.
> Si en el CRM se retira o se cambia uno, **avisa a quien tenga la aplicación en el
> teléfono para que traiga el día**, o ese día cobra desde un sitio que ya no existe.

---

## Sacar el informe y mandarlo por WhatsApp
<!-- tarea -->

**Empieza en:** **Menú → «Reportes»**.

1. **Menú → «Reportes».** <!-- señala: menu-reportes -->
2. **Lee lo que dice encima de las pestañas**: «Cuadrado con los datos del aparato,
   del 28/9/2026, 10:36.» **Si sale un aviso ámbar de que los datos tienen más de un
   día, esto no sirve para cerrar.** Trae el día primero.
   <!-- señala: informes-advertencia -->
3. Pon **«Desde»** y **«Hasta»**, y el **«Vehículo»** si quieres.
   <!-- señala: informes-desde -->
4. Mira las tres pestañas: **«Resumen»**, **«Por Vehículo»**, **«Detalle de
   Órdenes»**. <!-- señala: informes-pestanas -->
5. **Toca «Exportar a Excel»**. <!-- señala: informes-exportar -->
6. Mientras lo arma dice **«Armando el Excel...»**.
   <!-- señala: informes-exportar -->
7. Al terminar: **«Excel listo: elegí dónde mandarlo o guardarlo.»** y **se abre el
   cajón de compartir de Android**: WhatsApp, Telegram, correo, Archivos.

**El fichero ya está guardado antes de abrirse el cajón**, así que aunque cierres el
cajón no lo pierdes.

### Si el botón está apagado

Tócalo y mira el motivo: «No hay ninguna orden que exportar con estos filtros.», «No
hay nada descargado todavía: no hay nada que exportar.»

### Si dice que no se puede en CUP

> «Se pidió el Excel en CUP y esta sucursal no tiene tasa de cambio: no se convierte
> ningún importe con la tasa de otra.»

Cambia arriba a **USD** y vuelve a exportar.

---

## Actualizar la aplicación
<!-- tarea -->

**Empieza en:** la franja de arriba, desde cualquier pantalla.

Cuando hay versión nueva sale una franja ámbar arriba del todo.

1. **Antes de nada, sube lo que tengas.** Si hay trabajo sin subir, la franja ni te
   deja instalar:

   > **Hay una versión nueva, pero antes hay que subir el trabajo** — Te quedan 3 cosas
   > por subir. Instalar ahora puede llevárselas: primero sube, después actualiza.

2. Con la cola vacía, la franja dice **«Hay una versión nueva: 1.0.7»**.
3. **Toca «Cómo instalarla»**. <!-- señala: franja-version-nueva -->
4. Lee lo que va a pasar: «Son 74 MB y se descargan aquí dentro, con su barra: no hace
   falta salir al navegador ni buscar el fichero después. Si se corta la conexión,
   continúa desde donde iba. Al terminar, Android enseña su propia pantalla de
   «¿instalar?» y ahí hay que confirmar: eso no lo puede hacer la aplicación.»
5. **Toca «Descargar e instalar»**. <!-- señala: cajon-descargar-e-instalar -->
   La barra va diciendo los MB. Puedes cerrar el cajón: **no para la descarga**, y el
   cajón lo dice.
6. Al terminar sale la pantalla de **«¿instalar?» de Android**. Confirma ahí y la nueva
   entra encima de la que hay.

**La primera vez te va a pedir un permiso**, y no es un fallo: Android no deja instalar
nada que no venga de su tienda hasta que se le dice que de esta aplicación sí. La franja
te lo dice con el botón **«Dar el permiso»**, que abre el ajuste; al volver, **«Ya lo di:
instalar»**. Lo descargado **no se pierde** mientras das el permiso.

**Si se corta la conexión**, el cajón dice cuántos MB llegaron y **«Seguir descargando»**:
continúa donde iba, no empieza de cero. A los tres cortes seguidos ofrece además el
navegador.

**Si la huella no cuadra**, no se instala y lo dice: «La actualización llegó completa pero
no es la que el servidor dice tener». Con **«Empezar de nuevo»**. Eso es a propósito — una
aplicación a medio instalar es peor que no actualizar.

**«Ahora no» no mata el aviso: lo calla 30 minutos y vuelve.**
