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

## Buscar un pedido
<!-- tarea -->

**Empieza en:** **Menú → «Pedidos»**.

1. **Toca la caja de buscar** («Buscar») y escribe el cliente, el folio, la
   dirección, el municipio, el vendedor o un producto. **Busca solo**, sin darle a
   nada. <!-- señala: pedidos-buscar -->

### Si no aparece

Mira en este orden:

1. **La sucursal de arriba.** Es lo primero, siempre.
2. **La franja azul** de arriba. Al entrar, Pedidos viene acotado: «Enseñando sólo lo
   que puede subir a un camión…». **Toca «Ver todos los pedidos»**.
3. **Los filtros.** Si el vacío dice «Ningún pedido cuadra con estos filtros.», toca
   **«Quitar todos los filtros»**.
4. **Si ya está en una ruta**, míralo en Rutas.
5. **De cuándo son tus datos.** Si la franja dice «Datos de hace 9 h», ese pedido
   puede haber entrado después: trae el día.

---

## Ver el detalle de un pedido
<!-- tarea -->

**Empieza en:** **Menú → «Pedidos»**.

1. **Toca la tarjeta del pedido** (en el teléfono no hay tabla: cada pedido es una
   tarjeta). <!-- señala: pedidos-abrir-el-pedido -->
   - Se abre un cajón con el cliente de título y el folio debajo. Dentro:
     **«Entrega»**, **«Recorrido»**, la banda de la factura, el bloque del domicilio
     y **«Productos (6)»**.

**Es sólo lectura.** Aquí no se edita nada de un pedido: viene de PEDIDO.

---

## Mandar varios pedidos a una zona de golpe
<!-- tarea -->

**Empieza en:** **Menú → «Pedidos»**.

Éste es el atajo para no ir tarjeta por tarjeta en el Tablero.

1. **Filtra por municipio** para dejar los que quieres (o por vendedor, o por
   día). <!-- señala: pedidos-filtro-municipio -->
2. **Toca arriba «Elegir los 50 de esta página»** para marcarlos todos.
   <!-- señala: pedidos-marcar-todos -->
   - O **toca la casilla de cada pedido**, uno a uno.
3. **Toca la casilla de un pedido** para quitar o poner la marca de ese solo.
   <!-- señala: pedidos-marcar-uno -->
   - Aparece una franja azul: **«7 pedido(s) elegidos»**.
4. **Toca «Mandar a una zona»**, en esa franja.
   <!-- señala: pedidos-mandar-a-una-zona -->
   - Se abre el cajón **«Mandar a una zona del tablero»**: «Se colocan en el orden en
     que están marcados, y el gesto es el mismo que arrastrarlos: se guarda aquí y
     sube cuando haya señal.»
5. **Toca la zona** de la lista. Debajo de cada una pone «12 pedido(s) puestos».
   <!-- señala: pedidos-zona-destino -->
   - Si no hay ninguna, toca **«Crear una zona nueva»**, escribe el nombre y
     **«Crear»**.
6. **Toca «Mandar a la zona»** abajo. <!-- señala: pedidos-mandar -->
   - Te dice cómo fue: **«5 pedido(s) en «Centro»»**.

### Si alguno se queda fuera

En ámbar: **«No se pudieron mandar 2, y siguen marcados:»** y debajo, uno a uno:

```
F-2992 · Ana: Ya va en otra ruta
X-3010 · Luis: Sin coordenadas de entrega
```

**Los que sí fueron pierden la marca; los que no, se quedan marcados** para que
puedas seguir con ellos.

---

## Sacar el pre-despacho de lo que tienes filtrado
<!-- tarea -->

**Empieza en:** **Menú → «Pedidos»**.

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
     cuántos pedidos tiene cada uno.
7. Y para quitar la zona entera, **toca «Borrar la columna»**.
   <!-- señala: tablero-borrar-la-zona -->

### Al borrar

**Si la zona está vacía:**

> «La zona se va del tablero. No hay ningún pedido dentro, así que no se pierde
> trabajo del día, pero la zona hay que volver a crearla a mano con su nombre.»

Botones: **«Sí, borrar «Centro»»** y **«No, dejarla»**.

**Si la zona tiene pedidos**, no te deja borrarla sin decidir qué pasa con ellos:

> **«Centro» tiene 8 pedidos puestos** — ¿Qué se hace con ellos?

Y dos salidas: **«Devolverlos a «sin colocar» y borrar»** o **«Mandarlos a otra
columna y borrar»**.

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
     arriba: **«Sucursal» · «Salida» · «Vehículo» · «Pedidos»**.
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
   - Si no hay ninguno: «Esta sucursal no tiene ningún almacén con ubicación…» y un
     botón **«Poner el almacén»**.
5. **Paso «Vehículo»** — elige en **«Vehículo de la ruta»** y toca **«Siguiente»**.
   **Es obligatorio.** <!-- señala: rutas-asistente-vehiculo -->
   - Cada uno sale con su capacidad: «1000 kg», «1000 kg · en el taller», «1000 kg ·
     en ruta». **Se pueden elegir todos.**
   - Si eliges uno del taller sale un aviso en ámbar, pero **se arma igual**.
   - Puedes ponerle un nombre («Nombre (el código se genera solo)») y cambiar la
     **«Fecha de entrega»**, que **viene puesta en hoy**.
6. **Paso «Pedidos»** — busca y **marca los que quieras**.
   <!-- señala: rutas-asistente-buscar -->
   - En el teléfono los filtros van **uno por línea**: sucursal, día, buscador,
     vendedor, municipio, «km máx.», «costo mín.», estado, domicilio y cotización.
   - **Mira la barra de capacidad**: «115.6 / 10000 kg (1%)». Al 100 % sale **«LLENO»**
     y **«Camión lleno — no cabe más»**.
   - **Las filas de los pedidos que ya no caben se apagan**, con el motivo: «No cabe
     en el camión».
   - Puedes marcar **una zona entera del tablero** tocando su casilla. Te dirá qué
     entró: **«9 de 12 de «Vista» · 1 ya estaban · 1 ya no se pueden repartir hoy · 1
     no caben en el vehículo»**.
7. **Toca «Pre-despacho de los N elegidos»** si quieres la hoja del almacén antes de
   armar. <!-- señala: rutas-pre-despacho -->
8. **Toca «Generar Ruta»** abajo. <!-- señala: rutas-asistente-generar -->

### Si «Generar Ruta» está apagado

Falta algo: salida, camión, algún pedido, o te has pasado de peso.

### Si sale un aviso en ámbar encima del botón

Te dice exactamente qué pasa. Los más comunes:

| Aviso | Qué hacer |
|---|---|
| **«Se requiere un vehículo para crear la ruta»** | Vuelve al paso «Vehículo» |
| **«En una ruta sólo entra lo facturado y que cuadre. 3 no cumplen: X-2992 (sin facturar)…»** | Desmarca esos tres |
| **«2 de los 12 pedidos elegidos no pueden ir en esta ruta: X-2992 (ya va en la ruta RT-20260922-003)…»** | Desmarca ésos |
| **«Peso total (1250.5 kg) supera la capacidad del vehículo (1000 kg)»** | Quita pedidos o cambia de camión |

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
   > Lo que NO se borra son los pedidos ni sus resultados: sueltan esta ruta. Los
   > pendientes vuelven a la lista de disponibles; los entregados siguen entregados y
   > no se reparten otra vez. Y el camión se queda libre.»

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

Al eliminar la ruta no se borra ningún pedido ni se cambia su resultado. Los
pendientes y devueltos quedan disponibles; los ya entregados siguen entregados
y no se vuelven a repartir.

---

## Sacar un pedido de una ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

**No hay ningún botón para quitar una parada.** Las dos formas:

- **Eliminar la ruta entera** y volver a armarla sin ese pedido.
- **Marcarlo en el cierre como devuelto o cancelado**: al completar la ruta, ese
  pedido queda libre para mañana.

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
   ruta](#eliminar-una-ruta). Los pedidos pendientes quedan disponibles; los entregados conservan su
   resultado. El camión queda libre. <!-- señala: rutas-eliminar -->
3. Vete a **Menú → «Tablero»** y **desliza a la página de la zona**.
   <!-- señala: tablero-carrusel-de-zonas -->
4. **Toca el ⋮** de la cabecera. <!-- señala: tablero-menu-de-la-zona -->
5. **Toca «Camión previsto»** y elige el otro camión.
   <!-- señala: tablero-camion-previsto -->
6. Otra vez **⋮** y, abajo del cajón, **«Armar la ruta de esta zona»**.
   <!-- señala: tablero-armar-la-ruta -->

**Si la ruta está «En curso»**, también se puede eliminar con confirmación y armar
otra para los pedidos pendientes. Los resultados anteriores se conservan.
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

1. Busca la tarjeta del camión y **comprueba el nombre y la placa** antes de nada.
   Al final de la tarjeta, **toca «Eliminar»** (rojo, con contorno y papelera, sin
   relleno). <!-- señala: vehiculos-eliminar -->
   - **Se abre un cajón que pregunta antes**, titulado **«Borrar «Camión 1»»**,
     y dice lo que se pierde:

   > «El camión se va de la flota. Las rutas y los pedidos que lo llevaban puesto NO
   > se borran —el histórico de lo repartido se queda— pero se quedan sin camión, y
   > hay que ponerles otro. Y el camión hay que volver a darlo de alta a mano, con su
   > placa, su capacidad y su costo por km.»

2. **Toca «Sí, borrar «Camión 1»»**, o **«No, dejarlo»** para salir. Sale
   **«Vehículo eliminado.»** y la tarjeta desaparece.
   <!-- señala: confirmar-el-borrado -->

> **Ojo:** **cerrar el cajón sin contestar es NO** — la ✕, tocar fuera, Escape. Y si
> era el camión del **«Cálculo domicilio»**, elige otro antes de irte: sin ninguno,
> los domicilios salen sin precio.

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

## Poner o corregir un almacén
<!-- tarea -->

**Empieza en:** **Menú → «Almacenes»**.

**Esto necesita señal.**

1. Elige la sucursal arriba, si hay más de una.
   <!-- señala: almacenes-sucursal -->
2. **Toca «Nuevo almacén»**. <!-- señala: almacenes-nuevo -->
   - O **toca el renglón del almacén** que quieras corregir.
3. Escribe el **nombre del almacén**. <!-- señala: almacenes-nombre -->
4. Forma 1 de poner el punto: **escribe la dirección**…
   <!-- señala: almacenes-direccion -->
5. …y **toca «Buscar»** (necesita señal, y al menos 4 letras).
   <!-- señala: almacenes-buscar-la-direccion -->
6. Forma 2: **toca en el mapa** — funciona sin señal.
   <!-- señala: almacenes-mapa -->
7. Forma 3: **escribe las coordenadas a mano** en la caja «Coordenadas», así:
   `19.83, -75.82` — funciona siempre.
   <!-- señala: almacenes-coordenadas -->
8. Si quieres que sea el principal, **toca el chip «Principal»**. «Desde éste se mide
   cuando nadie dice cuál.» <!-- señala: almacenes-principal -->
9. **Toca «Guardar»**. Vas a ver **«Guardado en Accesos.»**
   <!-- señala: almacenes-guardar -->

**Un almacén sin punto se puede guardar, pero desde él no se cotiza**, y te lo avisa:
«Sin coordenadas: desde éste no se puede medir el domicilio.»

---

## Cambiar cuál es el almacén principal
<!-- tarea -->

**Empieza en:** **Menú → «Almacenes»**. **Necesita señal.**

El principal es el que se usa **cuando nadie dice cuál**. Lo dice el propio chip:
«Desde éste se mide cuando nadie dice cuál».

1. Arriba, elige la sucursal si hay más de una.
   <!-- señala: almacenes-sucursal -->
2. **Toca el renglón del almacén** que va a ser el principal. Se abre su cajón, con
   su nombre de título. <!-- señala: almacenes-abrir -->
3. Debajo del nombre, **toca el chip «Principal»** (la estrella se rellena).
   <!-- señala: almacenes-principal -->
4. **Toca «Guardar»**. Sale **«Guardado en Accesos.»** En la lista, la **estrella**
   se ha movido a ese almacén. <!-- señala: almacenes-guardar -->

> **Ojo:** **sólo puede haber un principal.** Al marcar éste, los demás se desmarcan
> solos — no hay que ir a quitárselo al anterior.

---

## Quitar un almacén de la sucursal
<!-- tarea -->

**Empieza en:** **Menú → «Almacenes»**. **Necesita señal.**

1. Arriba, elige la sucursal. <!-- señala: almacenes-sucursal -->
2. **Toca el renglón del almacén.** Se abre su cajón.
   <!-- señala: almacenes-abrir -->
3. Debajo del nombre, a la derecha de los chips **«Principal»** y **«Activo»**, hay
   una **papelera** (**«Quitar»**). **Tócala.**
   <!-- señala: almacenes-quitar -->
   - **Se abre un cajón que pregunta antes**, **«Borrar «Almacén Central»»**, y
     dice las cuatro cosas que pasan de verdad:

   > «El almacén se va de Accesos: se guarda la lista de Santiago sin él, así que
   > desaparece para todo el mundo y no sólo en esta pantalla. Deja de poder medirse
   > desde ahí: los pedidos que lo traen puesto pasan a medirse desde el principal de
   > la sucursal, con otro kilometraje y otro importe que se cobra igual que uno
   > bueno; y si era el último con punto, los domicilios de Santiago salen sin precio.
   > Los teléfonos que ya lo bajaron siguen midiendo desde él hasta la próxima vez que
   > tengan red —Accesos no avisa de los que se retiran—, así que cada entrega de ese
   > día se cobra mal y no se ve hasta cuadrar la caja. Volver a ponerlo es darlo de
   > alta a mano, con su dirección y su punto.»

4. **Toca «Sí, borrar «Almacén Central»»**, o **«No, dejarlo»**.
   <!-- señala: confirmar-el-borrado -->

> **Ojo:** eso de que **los teléfonos que ya lo bajaron siguen midiendo desde él** es
> literal. Después de quitar un almacén, **avisa a quien tenga la aplicación en el
> teléfono para que traiga el día**, o ese día cobra desde un sitio que ya no existe.

Y si sólo quieres que deje de usarse pero no perderlo: **no lo quites**. Abre su
cajón, **toca el chip «Activo»** para dejarlo en **«Inactivo»** y **«Guardar»**. En
la lista queda con el rótulo «inactivo» y no se ofrece para salir.

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
