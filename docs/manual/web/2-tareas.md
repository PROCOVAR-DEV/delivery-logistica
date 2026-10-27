# Tareas sueltas

«Quiero hacer X»: dónde hacer clic, paso a paso.

---

## Buscar una factura
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. Haz clic en la caja **«Buscar»** y escribe el cliente, el folio, la dirección, el
   municipio, el vendedor o un producto. **Busca solo**, sin darle a intro. <!-- señala: pedidos-buscar -->

### Si no aparece

1. **La sucursal de arriba.** Siempre es lo primero.
2. **La franja azul.** Al entrar, Facturas viene acotado a propósito: «Enseñando sólo
   lo que puede subir a un camión…». **Clic en «Ver todas las facturas»**.
3. **Los filtros.** Si dice «Ninguna factura cuadra con estos filtros.», clic en
   **«Quitar todos los filtros»**.
4. **Si ya está en una ruta**, míralo en Rutas.

---

## Filtrar y ordenar la lista de facturas
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **Clic en «Estado de reparto en delivery»** y elige en qué punto del reparto
   están los que quieres ver. <!-- señala: pedidos-filtro-estado -->
2. **Clic en «Municipio del cliente»** para quedarte con un municipio.
   <!-- señala: pedidos-filtro-municipio -->
3. **Clic en «Cómo se ordena esta página»** para cambiar el orden.
   <!-- señala: pedidos-orden -->
4. Y para dejarlo todo como estaba, **clic en «Quitar todos los filtros»** (sale en
   el vacío, cuando ninguna factura cuadra).
   <!-- señala: pedidos-limpiar-filtros -->

Los filtros van en una fila bajo la cabecera:

| Filtro | Por defecto |
|---|---|
| **«Estado de reparto en delivery»** | «Cualquier reparto» |
| **«Municipio del cliente»** | «Todos los municipios» |
| **«Precio del domicilio»** | «Cualquier precio de domicilio». Con importe o en $0; no es cuentas por cobrar |
| **«Pedido de origen»** | «Con o sin pedido» |
| **«Vendedor de la factura»** | «Todos los vendedores». Uno o varios: casillas en un cajón, salen los de cualquiera de los marcados |
| **«Cómo se ordena esta página»** | «Más recientes» |
| **«Desde (fecha de la factura)»** / **«Hasta (fecha de la factura)»** | vacías |

Con «Desde» puesto aparece un botón **«sólo ese día»**, que copia la fecha en las
dos. Y una equis de quitar («Quitar el filtro de fechas») que limpia las dos.

**Cuidado:** **«Cómo se ordena esta página» ordena sólo la página que ves**, no los
246 facturas enteras.

Cualquier cambio te devuelve a la página 1.

---

## Poner el punto de entrega de una factura a mano
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

**Para qué:** el cliente pide entregar en **otro sitio** y quien factura lo apunta en el
ticket. Esa dirección no coincide con la geolocalización del cliente (la única que
manda PEDIDO). **El logístico le pone el punto bueno a esa factura**, y desde entonces
manda sobre el del cliente: las rutas lo miden desde ahí y **no se pierde cuando el
cliente se vuelve a actualizar**.

1. **Haz clic en la fila de la factura** para abrir su ficha.
   <!-- señala: pedidos-abrir-el-pedido -->
2. En la sección **«Entrega»**, **clic en «Ubicar la entrega»**.
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
   - **Haz clic en el mapa**, en el sitio de la entrega. Debajo sale «Punto puesto en
     20.02470, -75.82190.».
   - **Escribe la dirección** en **«Dirección»** y **clic en «Buscar»** (hacen falta al
     menos 4 letras). Mira el punto en el mapa antes de guardar.
4. **Escribe la dirección de la entrega** en **«Dirección»**, si el mapa no la trajo.
   **Vacía, se queda la que tenía.**
5. **Clic en «Guardar punto»**. No se enciende hasta que algo cambie.
   - **En la web se guarda al instante en el servidor.** Si dice que no, el cajón se
     queda abierto y el motivo sale tal cual debajo (por ejemplo «lat y lng tienen que
     ser un punto del planeta» o «La factura ya está entregada…»).

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
2. **Clic en «Volver al punto del cliente»**. **Pregunta antes**, en un cajón: dice a qué
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

**Una limitación:** una factura cuyo pedido PEDIDO manda **sin coordenadas** no llega a esta
aplicación, así que no se puede abrir. Esto sirve para **cambiar** el punto de una
factura que ya tiene uno.

---

## Juntar facturas en un conduce
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

Un conduce es lo que sale con el camión y puede juntar varias facturas **del mismo
cliente** en UNA parada. **La primera que marcas es la principal**: la que lo crea y dice a
qué cliente va dedicado.

1. **Menú → «Facturas»** y **marca las facturas** que van juntas: clic en su casilla. La
   **primera** que marques será la principal. <!-- señala: pedidos-marcar-uno -->
2. **Clic en «Crear conduce»**, en la franja azul de lo marcado (sale con dos o más).
   <!-- señala: pedidos-crear-conduce -->
   - Se abre el cajón **«Crear conduce»** y te dice quién manda: **«La principal será 47313
     (Cliente). Las demás irán con ella»**.
3. **Clic en «Crear conduce»**, abajo del cajón. <!-- señala: pedidos-confirmar-conduce -->
   - En la lista, la principal pasa a decir **«Conduce 47313 + 47314»** con el peso y el
     domicilio de todas sus facturas. Las demás **ya no salen como filas**: van con ella.

**Si no se puede, el cajón lo dice y el botón queda apagado:** clientes distintos («Un
conduce junta facturas del mismo cliente»), de otra sucursal, o una factura que ya va en una
ruta, ya se entregó o ya va en otro conduce.

**Al armar una ruta o mandar a una zona, elige la principal**: el conduce entero se mueve con
ella y es UNA parada. En el cierre de la ruta, lo que marques en esa parada vale para todas
sus facturas.

---

## Sacar una factura de un conduce o deshacerlo
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **En «Facturas», abre la pestaña «Conduces»**. <!-- señala: pedidos-pestanas -->
   - Arriba pone qué es un conduce y debajo salen los que hay, con sus facturas.
2. **«Sacar»**, al lado de una factura, la devuelve a ser una factura suelta.
3. **«Deshacer conduce»** suelta todas. <!-- señala: pedidos-deshacer-conduce -->
   - También está en la ficha de la principal (clic en su fila).

**No se puede sacar ni deshacer un conduce que ya va en una ruta o tiene resultado**: el
botón sale apagado y dice por qué. Si el servidor dice que no, aquí mismo sale su motivo,
tal cual.

---

## Mandar varias facturas a una zona de golpe
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **Menú → «Facturas»** y **filtra** lo que quieras. <!-- señala: pedidos-filtro-municipio -->
2. **Marca las facturas**: clic en su casilla, o en la casilla de la cabecera («Elegir
   todos los de esta página»). <!-- señala: pedidos-marcar-todos -->
3. **Clic en «Mandar a una zona»**, en la franja azul que dice **«7 factura(s)
   elegidas»**. <!-- señala: pedidos-mandar-a-una-zona -->
   - Se abre **«Mandar a una zona del tablero»**:

   > «Se colocan en el orden en que están marcados, y el gesto es el mismo que
   > arrastrarlos.»

4. **Clic en la zona** de la lista. Debajo de cada una pone «12 factura(s) puestas».
   - Si no hay ninguna: **«Crear una zona nueva»**, el nombre, y **«Crear»**. <!-- señala: pedidos-zona-destino -->
5. **Clic en «Mandar a la zona»**. Te dice cómo fue: **«5 factura(s) en «Centro»»**.
   <!-- señala: pedidos-mandar -->

**Si alguno se queda fuera**, sale en ámbar con el motivo de cada uno:

```
No se pudieron mandar 2, y siguen marcados:
PTB25-261005-1480 · Ana: Esa factura ya está en una ruta
PTB25-261005-1502 · Luis: Esa factura va dentro del conduce 47313: arma el conduce entero
```

Cada factura sale por su **conduce** (el número de operación). Los motivos
son los mismos que daría el servidor: ya entregado, ya en una ruta o miembro suelto de
un conduce, además de «Archivado en PEDIDO», «Sin cotejar», «Sin factura», «Sin
coordenadas de entrega» o «Es de otra sucursal». **El domicilio sin cobrar o sin cotizar
ya no es un motivo.**

**Las que sí fueron pierden la marca; las que no, se quedan marcadas.**

---

## Ver el detalle de una factura
<!-- tarea -->

**Empieza en:** **Menú → «Facturas»**.

1. **Clic en cualquier sitio de la fila** (la fila entera abre el detalle).
   <!-- señala: pedidos-abrir-el-pedido -->
   - Se abre un cajón por la derecha, con el cliente de título y el folio debajo:
     **«Entrega»**, **«Recorrido»**, la banda de la factura, el bloque del domicilio
     y **«Productos (6)»**.

**Es de lectura.** Las facturas vienen de Ventra y aquí no se editan. La única acción es
**«Ubicar la entrega»**: [poner a mano el punto de entrega](#poner-el-punto-de-entrega-de-una-factura-a-mano).

---

## Renombrar, vaciar o borrar una zona
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

1. **Clic en el ⋮** de la cabecera de la zona.
   <!-- señala: tablero-menu-de-la-zona -->
2. Para cambiarle el nombre, **clic en «Renombrar»**, escríbelo y **«Guardar»**.
   <!-- señala: tablero-renombrar -->
3. Para devolver sus tarjetas a «sin colocar», **clic en «Vaciar»**.
   <!-- señala: tablero-vaciar -->
4. Y para quitar la zona entera, **clic en «Borrar la columna»**.
   <!-- señala: tablero-borrar-la-zona -->
5. Confirma con **«Sí, borrar «Centro»»**.
   <!-- señala: confirmar-el-borrado -->

Lo que hay en ese ⋮:
   - **«Renombrar»**
   - **«Vaciar»** — «Las tarjetas vuelven a «sin colocar»»
   - **«Mover todo a otra columna»**
   - **«Borrar la columna»**

**Al borrar una zona vacía:** «La zona se va del tablero. No hay ninguna factura
dentro, así que no se pierde trabajo del día, pero la zona hay que volver a crearla a
mano con su nombre.» Con **«Sí, borrar «Centro»»** y **«No, dejarla»**.

**Al borrar una zona con facturas** no te deja sin decidir qué pasa con ellos:

> **«Centro» tiene 8 facturas puestas** — ¿Qué se hace con ellas?

Y dos salidas: **«Devolver las 8 facturas a «Sin colocar» y borrar»** o **«Mover las 8 facturas a otra
zona y borrar»**. Cuenta los que cuenta el servidor, también los que este aparato no ve (por ejemplo, facturas ya archivadas): lo dice debajo.

Y una tercera, **«Inactivar la zona»**: la quita del tablero y sus facturas vuelven a
«Sin colocar», pero **se conserva** (con su nombre y su historia de rutas). Para
volver a usarla, arriba **«Zonas inactivas»** y **«Activar»**; vuelve vacía.

---

## Armar una ruta sin usar el Tablero
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

Es el camino largo, para cuando la ruta no sale de una zona entera.

1. Arriba a la derecha de la lista, **clic en «+ Nueva Ruta»**.
   <!-- señala: rutas-nueva-ruta -->
   - Se abre un cajón a pantalla completa, **«Nueva Ruta»**, con cuatro tramos
     arriba: **«Sucursal» · «Salida» · «Vehículo» · «Facturas»**.
2. **«Sucursal»** — elige en **«Sucursal de la ruta»** y **«Siguiente»**.
   **Cambiarla borra todo lo elegido después.** <!-- señala: rutas-asistente-sucursal -->
3. **«Salida»** — elige en **«Almacén del que sale el camión»** y **«Siguiente»**.
   Sólo salen los que tienen coordenadas. Si no hay ninguno: «Esta sucursal no tiene
   ningún almacén con ubicación. Los almacenes se ponen en el CRM…» y un botón
   **«Ver los almacenes»** (lleva a la pantalla de consulta). <!-- señala: rutas-asistente-almacen -->
4. **«Vehículo»** — **obligatorio**. Se ofrecen los camiones **activos**, con su
   capacidad de nota: «1000 kg», «1000 kg · en el taller», «1000 kg · en ruta».
   - **Un camión «Inactivo» (dado de baja) no sale en la lista.** Si no ves el que
     buscas, mira en **Menú → «Vehículos»** si está dado de baja.
   - Si eliges uno del taller, sale un **aviso en ámbar** pero **se arma igual**: es
     aviso, no bloqueo. Dice que el camión está marcado «EN EL TALLER» y que no puede
     salir hoy; si ya volvió, sácalo del taller en Vehículos.
   - Si no queda ninguno: «Los vehículos de esta sucursal están inactivos, y a una
     ruta nueva sólo se asigna un vehículo activo. Actívalo en Vehículos.»
   - Opcionalmente, el nombre y la **«Fecha de entrega»**, que **viene puesta en
     hoy**. <!-- señala: rutas-asistente-vehiculo -->
5. **«Facturas»** — marca las que quieras.
   - **La barra de capacidad**: «115.6 / 10000 kg (1%)». Al 100 % sale **«LLENO»** y
     **«Camión lleno — no cabe más»**.
   - **Sólo salen las facturas facturadas (cuadren o no con el pedido).** Ya no se exige el
     domicilio cobrado ni cotizado. Pero el filtro de domicilio arranca en «Sólo con
     domicilio», que cuenta lo marcado por el vendedor **o** lo cobrado en la factura: si te
     falta una que ni el vendedor marcó ni la factura cobró, elige **«Con y sin domicilio»**.
   - **Las filas que ya no caben se apagan**, con el motivo «No cabe en el camión».
   - Puedes marcar **una zona entera del tablero** con su casilla. Te dirá qué entró:
     **«9 de 12 de «Vista» · 1 ya estaban · 1 ya no se pueden repartir hoy · 1 no caben
     en el vehículo»**.
   - Si la zona trae otro camión distinto del que elegiste, te avisa y te da un botón
     **«Dejar el mío»**.
   - Debajo, el resumen: **«12 facturas seleccionadas (2 de otro día o filtro, siguen
     contando)»**. Ese «siguen contando» es literal: **siguen en la ruta y siguen
     sumando peso** aunque los filtros ya no las enseñen. <!-- señala: rutas-asistente-buscar -->
6. **Clic en «Generar Ruta»**. <!-- señala: rutas-asistente-generar -->

Para volver atrás, **clic en el nombre del tramo** arriba («Vehículo», «Salida»…).

### Si «Generar Ruta» está apagado

Falta salida, camión o facturas, o te has pasado de peso.

### Si sale un aviso en ámbar encima del botón

Las facturas se nombran por su **conduce**, que es su número de operación
(el mismo que ves en «Conduce: PTB25-…» en las paradas).

| Aviso | Qué hacer |
|---|---|
| **«Se requiere un vehículo para crear la ruta»** | Vuelve al tramo «Vehículo» |
| **«En una ruta sólo entra lo facturado. 3 no cumplen: PTB25-261005-1480 (sin facturar)…»** | Desmarca ésas |
| **«El vehículo está inactivo y no se puede asignar a una ruta.»** | Ese camión está dado de baja. Elige otro |
| **«2 de las 12 facturas elegidas no pueden ir en esta ruta: PTB25-261005-1480 (ya va en la ruta RT-20260922-003)…»** | Desmarca ésas |
| **«Peso total (1250.5 kg) supera la capacidad del vehículo (1000 kg)»** | Quita facturas o cambia de camión |

---

## Filtrar la lista de rutas
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

En la columna de la izquierda:

- **El buscador**: «Buscar por código, nombre, vehículo...»
- **«Rutas de un camión»** — por defecto «Cualquier vehículo»
- **«Ubicación de salida»** — por defecto «Cualquier ubicación». Las opciones son los
  sitios de los que han salido rutas de verdad, con cuántas. Las que no tienen salida
  guardada se agrupan en **«Sin punto de partida»**
- **«Desde»** y **«Hasta»** — por la fecha en que se creó la ruta
- **«Limpiar»** — sólo aparece si hay algo puesto

**Ojo con el número de las pestañas:** cuenta **todas** las rutas de la sucursal, sin
aplicar estos filtros. Por eso «Planificadas (12)» puede salir encima de una lista
de 3, y no es un fallo.

**Y los filtros no se pueden mandar en un enlace.** Viven sólo mientras tengas la
pantalla abierta, y recargar los borra.

---

## Eliminar una ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. **Mira el código de la tarjeta** antes de nada, para no borrar la de al lado.
   <!-- señala: rutas-tarjeta-de-ruta -->
   - Busca la ruta en su pestaña: **«Planificadas»** o **«En curso»**.
2. Al final de su tarjeta, **clic en «Eliminar»** (el botón rojo, con contorno y
   papelera, sin relleno). <!-- señala: rutas-eliminar -->
   - **Se abre un cajón que pregunta antes**, titulado **«Borrar «RT-20260928-004»»**,
     y te dice lo que se pierde:

   > «La ruta desaparece con su código, su fecha, el orden de visita y los
   > kilómetros que se calcularon al armarla. Para tenerla otra vez hay que volver a
   > armarla desde el asistente, a mano.
   >
   > Lo que NO se borra son las facturas ni sus resultados: sueltan esta ruta. Los
   > pendientes vuelven a la lista de disponibles; los entregados siguen entregados y
   > no se reparten otra vez. Y el camión se queda libre.
   >
   > Si la ruta se armó desde una zona del tablero, las facturas vuelven a esa zona
   > cuando se sincronice el borrado (en la web, de inmediato). Mientras tanto, sin
   > señal, salen en «Sin colocar».»

3. **Clic en «Sí, borrar «RT-20260928-004»»**, o en **«No, dejarla»** para salir.
   <!-- señala: confirmar-el-borrado -->

> **Ojo:** **cerrar el cajón sin contestar es NO.** La ✕, clic fuera o Escape dejan
> la ruta donde estaba.

### Cuándo se puede borrar

Una ruta **planificada o en curso se puede eliminar**, aunque no tenga paradas
cargadas o ya haya marcas de entrega, devolución o cancelación. Las marcas son
provisionales mientras no se complete la ruta.

**Las rutas completadas no se pueden editar ni eliminar**: forman el histórico,
y el botón «Eliminar» no aparece. Su cierre sólo se consulta.

Al eliminar la ruta no se borra ninguna factura ni se cambia su resultado. Las
pendientes y devueltos quedan disponibles; los ya entregados siguen entregados
y no se vuelven a repartir.

### Si la ruta se hizo desde el tablero

**Las facturas vuelven a su zona del tablero**: no se pierde la relación y no hay que
volver a crear la zona ni a repartir las facturas. **En la web es inmediato**: al
volver a **Menú → «Tablero»** las facturas ya están en su zona, listas para planificar
otra vez. Si la ruta se hizo con el asistente «Nueva Ruta» y no salió del tablero, las
facturas vuelven sólo a la lista de disponibles.

---

## Sacar una factura de una ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

En una ruta **planificada** (que todavía no ha salido) se puede quitar **una sola
parada**, sin borrar la ruta.

1. Busca la ruta en la pestaña **«Planificadas»** y **haz clic en su tarjeta**.
   <!-- señala: rutas-tarjeta-de-ruta -->
2. En el detalle, **clic en «Ver paradas»**. <!-- señala: rutas-ver-paradas -->
3. En la tarjeta de la parada que sobra, **clic en «Quitar de ruta»**.
   - Se abre un cajón, **«Quitar de la ruta»**, con el cliente y su conduce debajo
     («Casa Pérez · Conduce: PTB25-261005-1480»), que dice qué pasa:

   > «Casa Pérez sale de esta ruta y vuelve a facturas disponibles. La ruta se queda
   > con las demás paradas y su peso y su importe se recalculan sin él.
   >
   > Si la ruta se armó desde una zona del tablero, la factura regresa a esa zona
   > cuando se sincronice (en la web, de inmediato).»

4. **Clic en «Sí, quitar «Casa Pérez» de la ruta»**, o en **«No, dejarlo en la
   ruta»**. **Cerrar el cajón sin contestar es No.**

La parada desaparece de la hoja, y el peso y el importe de la ruta se recalculan sin
ella. La factura **vuelve a la lista de disponibles** y, si la ruta nació del tablero,
**a su zona del tablero**. **En la web es al instante.**

**Sólo en una ruta planificada.** En una ruta **en curso** no hay botón: marca esa
factura como devuelta o cancelada al completar la ruta, y queda libre. Una ruta
**completada** es histórico y no se toca. Si el servidor lo rechaza, dice el motivo:
«Sólo se pueden retirar paradas de una ruta planificada» o «La factura no pertenece a
una ruta planificada o ya fue retirada».

(Y si lo que sobra es la ruta entera, [elimínala](#eliminar-una-ruta).)

---

## Consultar un cliente
<!-- tarea -->

**Empieza en:** **Menú → «Clientes»**.

1. **Menú → «Clientes».** <!-- señala: menu-clientes -->
2. Escribe en **«Buscar por nombre, dirección o municipio…»**. Busca también por
   teléfono, código, zona y vendedor. <!-- señala: clientes-buscar -->
3. **Clic en la fila.** Se abre la ficha, con el **teléfono el primero**.
   <!-- señala: clientes-abrir-el-cliente -->

**No se crean, ni se editan, ni se borran.** Vienen de PEDIDO, y sólo los que tienen
geolocalización.

**Para ver los kilómetros de cada cliente**, filtra por **«A qué distancia del
almacén»**: sólo entonces sale la columna de km.

---

## Dar de alta un camión
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**.

1. **Clic en «Agregar Vehículo»**, arriba a la derecha.
   <!-- señala: vehiculos-agregar -->
2. Escribe el **«Nombre del Vehículo *»**. Es obligatorio.
   <!-- señala: vehiculos-nombre -->
3. Elige el **«Tipo»**: al elegirlo **hereda su costo por km**.
   <!-- señala: vehiculos-tipo -->
4. Escribe la **«Placa (opcional)»**. <!-- señala: vehiculos-placa -->
5. Pon la **«Capacidad Máx. (kg)»** — viene en 1000.
   <!-- señala: vehiculos-capacidad -->
6. Deja el **«Estado del vehículo»** en **«Disponible»**: sólo hay ésa y **«En
   mantenimiento»**. <!-- señala: vehiculos-estado -->
7. Pon el **«Costo por km (USD)»**. <!-- señala: vehiculos-costo-por-km -->
8. **Clic en «Agregar Vehículo»**. Verás **«Vehículo agregado.»**
   <!-- señala: vehiculos-guardar -->

**El interruptor «Vehículo activo»** viene encendido: un camión nuevo se ofrece en las
rutas nuevas. Se apaga más adelante si hay que darlo de baja (ver [Dejar un camión
inactivo](#dejar-un-camión-inactivo)).

### Si no sabes el costo por km

**Déjalo vacío, nunca en cero.** Un cero se lee como «el kilómetro es gratis».

O usa el ayudante: **clic en «¿No sabes el costo por km?»**, escribe **«El camionero
cobra (CUP)»** y **«hasta ___ km (ida)»**, y **«Calcular»**. Te rellena el campo.

### Definir los tipos de camión

1. Arriba, **clic en «Tipos de vehículo»**.
2. Por cada fila, **«Nombre»** y **«Costo/km (USD)»**. La papelera («Quitar») la
   borra.
3. **«Agregar tipo»** para una fila más.
4. **«Guardar»**. Verás **«Tipos guardados.»**

Las filas **sin nombre no se guardan**.

### Si un camión sale ocupado y no lo está

Su tarjeta lo dice: «El estado guardado dice «en uso» y no lleva ninguna ruta
abierta.» **Clic en «Marcar disponible»** en esa misma tarjeta.

---

## Decir qué camión calcula el domicilio
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**.

De este camión sale **el costo por km con el que se le cobra al cliente el
domicilio**. No está en el paso a paso del Panel, pero decide dinero.

   - Busca la tarjeta del camión. **Debajo del nombre, en la fila de pastillas**, mira
     qué hay:
     - **«Cálculo domicilio · $1.65/km»**, con una casita — ya es el que calcula.
     - El botón **«Usar para domicilio»** — no lo es.
1. **Clic en «Usar para domicilio»**.
   <!-- señala: vehiculos-usar-para-domicilio -->
   - Abajo sale **«Se usará este vehículo para calcular el domicilio.»** y la
     tarjeta cambia: el botón desaparece y en su sitio queda la pastilla
     **«Cálculo domicilio»**.
**También desde la ficha:** **clic en «Editar»** y marca **«Usar este vehículo para
calcular el domicilio»**. Debajo pone **«Solo un vehículo por TIPO.»**

> **Ojo:** si la pastilla dice **«Cálculo domicilio»** **y no lleva importe
> detrás**, ese camión está elegido y **no tiene costo por km**. Edítalo y ponle
> uno: así es como un domicilio sale sin precio teniendo camión.

---

## Marcar un camión en el taller
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**.

1. En la tarjeta del camión, abajo, **clic en «Editar»**.
   <!-- señala: vehiculos-editar -->
2. En el desplegable **«Estado del vehículo»**, elige **«En mantenimiento»**. <!-- señala: vehiculos-estado -->
   - **Lee la explicación que sale debajo del desplegable, en ámbar:**

   > «En el taller: se puede elegir para una ruta nueva, pero sale marcado con un
   > aviso. Escribe el motivo en Notas, aquí abajo — es lo único que le dice al de al
   > lado por qué no puede contar con él. Marcarlo NO cierra la ruta que ya tuviera
   > abierta: eso se arregla en la tarjeta del camión.»

3. **Escribe el motivo en «Notas (opcional)»**, más abajo.
   <!-- señala: vehiculos-notas -->
4. **Clic en «Actualizar»**. La insignia de la tarjeta pasa a **«Mantenimiento»** en
   ámbar. <!-- señala: vehiculos-guardar -->

> **Ojo:** el desplegable sólo tiene **«Disponible»** y **«En mantenimiento»**.
> **«En ruta» no está, a propósito**: eso sale de las rutas del camión y no se
> escribe a mano.

**Mientras un camión esté en mantenimiento se sigue ofreciendo para rutas nuevas, pero
con un aviso en ámbar**: sale con «en el taller» en el tramo «Vehículo» de «Nueva Ruta»
y en el «Camión previsto» del Tablero. Es aviso, no bloqueo: así una sucursal con un solo
camión olvidado en el taller no se queda sin poder armar rutas. Cuando vuelva, pásalo
otra vez a **«Disponible»**.

### Si el camión llevaba una ruta abierta

**Mandarlo al taller no la cierra.** La tarjeta te lo dice:

> «Está en el taller y lleva la ruta R-0412 abierta. O vuelve a estar disponible, o
> esa ruta la tiene que llevar otro camión: mandarlo al taller no la cierra, porque
> una ruta cerrada es una ruta repartida.»

**Y esa ruta no se le puede cambiar el camión**: hay que eliminarla y volver a
armarla con otro. Ver [Cambiar el camión de una
ruta](#cambiar-el-camión-de-una-ruta).

### Si sale como ocupado y no lo está

Su tarjeta lo dice: «El estado guardado dice «en uso» y no lleva ninguna ruta
abierta. Márcalo disponible: hasta entonces sale como ocupado al elegir camión.»
**Clic en «Marcar disponible»** en esa misma tarjeta. Sale **«Vehículo marcado como
disponible.»**

---

## Dar de baja un camión
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**.

**Si el camión ya tiene rutas, aunque sean del histórico, NO se puede borrar: se deja
«Inactivo»** ([cómo, aquí abajo](#dejar-un-camión-inactivo)). Borrar sólo sirve para un
camión que nunca se usó (uno dado de alta por error, por ejemplo).

1. Busca la tarjeta del camión, **comprueba el nombre y la placa** y, al final de la
   tarjeta, **clic en «Eliminar»** (rojo, con papelera, sin relleno).
   <!-- señala: vehiculos-eliminar -->
   - **Se abre un cajón que pregunta antes**, titulado **«Borrar «Camión 1»»**, y dice
     lo que se pierde:

   > «El camión se va de la flota y hay que volver a darlo de alta a mano, con su
   > placa, su capacidad y su costo por km.
   >
   > Un camión que ya tiene rutas —aunque sean del histórico— NO se puede borrar: el
   > servidor lo rechaza para no perder qué camión hizo cada reparto. Si ese es el
   > caso, no lo borres: ábrelo con «Editar» y márcalo como inactivo. Así deja de
   > ofrecerse en las rutas nuevas y su historial se queda intacto.»

2. **Clic en «Sí, borrar «Camión 1»»**, o en **«No, dejarlo»**. Sale **«Vehículo
   eliminado.»** y la tarjeta desaparece de la lista.
   <!-- señala: confirmar-el-borrado -->

Si el camión tenía rutas y le diste a «Sí», el servidor no lo borra y lo dice:

> «No se puede eliminar este vehículo porque tiene rutas asociadas, incluso
> históricas. Márcalo como inactivo para impedir que se use en nuevas rutas.»

> **Ojo:** **cerrar sin contestar es NO.** Y si era el camión del **«Cálculo
> domicilio»**, elige otro antes de irte: sin ninguno, los domicilios salen sin
> precio.

---

## Dejar un camión inactivo
<!-- tarea -->

**Empieza en:** **Menú → «Vehículos»**.

Es la forma de dar de baja un camión que **ya se usó**: deja de ofrecerse para rutas
nuevas y su historial se queda intacto.

1. En la tarjeta del camión, **clic en «Editar»**. <!-- señala: vehiculos-editar -->
2. **Apaga el interruptor «Vehículo activo»**, justo debajo del nombre. Debajo pone:
   «Se oculta de los selectores de rutas nuevas.»
3. **Clic en «Actualizar»**. <!-- señala: vehiculos-guardar -->
   - Sale **«Vehículo actualizado.»** y la tarjeta lleva la insignia **«Inactivo»**.

**Qué cambia:** el camión **ya no sale** en el tramo «Vehículo» de «Nueva Ruta» ni en el
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

**Empieza en:** **Menú → «Vehículos»**.

El tipo es **el punto de partida del costo por km**: al crear un camión de ese tipo,
hereda su costo, y luego se puede cambiar camión por camión.

1. Arriba, en la misma fila que la caja de buscar, **clic en «Tipos de vehículo»**.
   <!-- señala: vehiculos-tipos -->
   - Se abre un cajón, **«Tipos de vehículo»**, que empieza explicando para qué es:

   > «Define cada tipo con su costo por km por defecto. Al crear un vehículo de ese
   > tipo se hereda el costo/km (editable por vehículo).»

2. Por cada fila, rellena **«Nombre»**… <!-- señala: vehiculos-tipo-nombre -->
3. …y su **«Costo/km (USD)»**. La papelera (**«Quitar»**) borra la fila.
   <!-- señala: vehiculos-tipo-costo -->
4. Para una fila más, **clic en «Agregar tipo»**, abajo. <!-- señala: vehiculos-anadir-tipo -->
5. Al pie, **clic en «Guardar»** (al lado de **«Cancelar»**). Sale **«Tipos
   guardados.»** <!-- señala: vehiculos-guardar-tipos -->

> **Ojo:** **las filas sin nombre no se guardan.** Y el costo que no sepas,
> **déjalo vacío, nunca en cero**: un cero se lee como «el kilómetro es gratis».

**Si no hay ninguno todavía**, el cajón pone **«Sin tipos. Agrega el primero.»**

### El atajo desde la ficha de un camión

No hace falta salir a este cajón: en la ficha de un vehículo, **el desplegable
«Tipo» tiene como última opción «+ Crear tipo nuevo…»**. Ábrela, escribe **«Nombre
del tipo»** y su **«Costo/km (USD)»**, y **clic en «Crear tipo»**. El tipo queda
elegido y su costo se copia al campo del camión.

---

## Cambiar el camión de una ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

**No se puede.** Una ruta ya armada no deja cambiarle el camión: no hay ningún
botón para eso, ni en la tarjeta ni en el detalle. Las dos salidas:

**Si la ruta todavía no ha salido (pestaña «Planificadas»):**

1. En la pestaña **«Planificadas»**, **elimina la ruta** — ver [Eliminar una
   ruta](#eliminar-una-ruta). Las facturas pendientes
   quedan disponibles; las entregadas conservan su resultado. El camión queda libre.
   Si la ruta salió del tablero, **las facturas vuelven a su zona**. <!-- señala: rutas-eliminar -->
2. **Menú → «Tablero»**, ve a la zona, **⋮ → «Camión previsto»**, elige el otro
   camión (**activo**; si está en el taller sale marcado en ámbar, y se puede elegir
   igual) y **⋮ → «Armar la ruta de esta zona»**. <!-- señala: tablero-camion-previsto -->

**Si la ruta está «En curso»**, también se puede eliminar con confirmación y armar
otra para las facturas pendientes. Los resultados anteriores se conservan.
**Si está completada**, no se modifica ni elimina: conserva su camión como histórico.

> **Ojo:** mandar un camión al taller **no** le quita la ruta. La aplicación lo dice
> en su tarjeta: «mandarlo al taller no la cierra, porque una ruta cerrada es una
> ruta repartida».

---

## Consultar los almacenes de una sucursal
<!-- tarea -->

**Empieza en:** **Menú → «Almacenes»**.

**Los almacenes ya no se crean, se editan ni se quitan desde aquí: se editan en el
CRM.** Esta pantalla es de solo lectura, y arriba lo dice: «Los almacenes se editan
en el CRM. Aquí solo se consultan.» Si la aplicación trae la dirección del CRM
puesta, al lado sale **«Abrir el CRM»**.

1. Elige la sucursal arriba, si hay más de una.
   <!-- señala: almacenes-sucursal -->
2. Mira la lista. Cada renglón dice la dirección, las coordenadas (o **«sin punto»**),
   el código, si es el **principal** (lleva estrella) y si está **inactivo**.

**Un almacén sin punto no sirve para cotizar**: desde él no se puede medir el
domicilio. Si falta uno, o hay que corregir un punto, se arregla en el CRM y esta
pantalla se actualiza sola cuando se guarda allí.

---

## Cambiar entre USD y CUP
<!-- tarea -->

**Empieza en:** la barra de arriba, desde cualquier pantalla.

1. Arriba, a la derecha de la pastilla de la sucursal, **clic en la pastilla «USD» /
   «CUP»**. <!-- señala: barra-moneda -->
2. Elige. **La opción de CUP lleva la tasa y su fecha como nota**: **«1 USD = 320 ·
   del 9/9/2026»**. Esa fecha no es un adorno: es lo único que demuestra que la tasa
   es de verdad. <!-- señala: barra-elegir-moneda -->
3. Los importes de todas las pantallas pasan a esa moneda.

### Si sólo te deja USD

La pastilla sale **en ámbar, con un icono de dinero tachado, y no se abre**. Pasa el
ratón por encima y lee el motivo, que lleva el nombre de tu sucursal dentro:

> «Santiago no tiene tasa de cambio todavía: los importes sólo se pueden ver en
> USD.»

**No se usa la tasa de otra sucursal, y es a propósito.** Se arregla en Accesos —ver
[Dejar una sucursal lista para trabajar](../comun/puesta-en-marcha.md#paso-4--la-tasa-de-cambio-de-la-sucursal).

### Si al lado de la pastilla sale un reloj ámbar

Sólo sale **mirando en CUP**, y quiere decir que la tasa está vieja:

> «La tasa es del 9/9/2026 y puede estar desfasada.»

**Se sigue usando**: una tasa de ayer convierte con un error pequeño, y sin ninguna
no se puede convertir nada. Pero si vas a cobrar con ese número, pídela actualizada.

---

## Ir a otra aplicación de la casa
<!-- tarea -->

**Empieza en:** tu avatar, arriba a la derecha.

1. **Clic en tu avatar**, arriba a la derecha. <!-- señala: cuenta-avatar -->
2. En la sección **«Ir a»** hay una baldosa por aplicación, con su nombre y su
   descripción. **Se abren en otra pestaña.**
   <!-- señala: cuenta-ir-a-la-aplicacion -->

Si esa sección no sale, es que no se pudieron leer. No es un error, y el resto del
menú funciona igual.
