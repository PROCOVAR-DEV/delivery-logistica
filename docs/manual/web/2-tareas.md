# Tareas sueltas

«Quiero hacer X»: dónde hacer clic, paso a paso.

---

## Buscar un pedido

**Empieza en:** **Menú → «Pedidos»**.

1. **Menú → «Pedidos».**
2. Haz clic en la caja **«Buscar»** y escribe el cliente, el folio, la dirección, el
   municipio, el vendedor o un producto. **Busca solo**, sin darle a intro.

### Si no aparece

1. **La sucursal de arriba.** Siempre es lo primero.
2. **La franja azul.** Al entrar, Pedidos viene acotado a propósito: «Enseñando sólo
   lo que puede subir a un camión…». **Clic en «Ver todos los pedidos»**.
3. **Los filtros.** Si dice «Ningún pedido cuadra con estos filtros.», clic en
   **«Quitar todos los filtros»**.
4. **Si ya está en una ruta**, míralo en Rutas.

---

## Filtrar y ordenar la lista de pedidos

**Empieza en:** **Menú → «Pedidos»**.

Los filtros van en una fila bajo la cabecera:

| Filtro | Por defecto |
|---|---|
| **«Estado de reparto en delivery»** | «Cualquier reparto» |
| **«Municipio del cliente»** | «Todos los municipios» |
| **«Precio del domicilio»** | «Cualquier precio» |
| **«Vendedor del pedido»** | «Todos los vendedores» |
| **«Cómo se ordena esta página»** | «Más recientes» |
| **«Desde (fecha del pedido)»** / **«Hasta (fecha del pedido)»** | vacías |

Con «Desde» puesto aparece un botón **«sólo ese día»**, que copia la fecha en las
dos. Y una equis de quitar («Quitar el filtro de fechas») que limpia las dos.

**Cuidado:** **«Cómo se ordena esta página» ordena sólo la página que ves**, no los
246 pedidos enteros.

Cualquier cambio te devuelve a la página 1.

---

## Mandar varios pedidos a una zona de golpe

**Empieza en:** **Menú → «Pedidos»**.

1. **Menú → «Pedidos»** y **filtra** lo que quieras.
2. **Marca los pedidos**: clic en su casilla, o en la casilla de la cabecera («Elegir
   todos los de esta página»).
3. Aparece la franja azul **«7 pedido(s) elegidos»**.
4. **Clic en «Mandar a una zona»**.
5. Se abre **«Mandar a una zona del tablero»**:

   > «Se colocan en el orden en que están marcados, y el gesto es el mismo que
   > arrastrarlos.»

6. **Clic en la zona** de la lista. Debajo de cada una pone «12 pedido(s) puestos».
   - Si no hay ninguna: **«Crear una zona nueva»**, el nombre, y **«Crear»**.
7. **Clic en «Mandar a la zona»**.
8. Te dice cómo fue: **«5 pedido(s) en «Centro»»**.

**Si alguno se queda fuera**, sale en ámbar con el motivo de cada uno:

```
No se pudieron mandar 2, y siguen marcados:
F-2992 · Ana: Ya va en otra ruta
X-3010 · Luis: Sin coordenadas de entrega
```

**Los que sí fueron pierden la marca; los que no, se quedan marcados.**

---

## Ver el detalle de un pedido

**Empieza en:** **Menú → «Pedidos»**.

1. **Menú → «Pedidos».**
2. **Clic en cualquier sitio de la fila** (la fila entera abre el detalle).
3. Se abre un cajón por la derecha, con el cliente de título y el folio debajo:
   **«Entrega»**, **«Recorrido»**, la banda de la factura, el bloque del domicilio y
   **«Productos (6)»**.

**Es sólo lectura.** Los pedidos vienen de PEDIDO y aquí no se editan.

---

## Renombrar, vaciar o borrar una zona

**Empieza en:** **Menú → «Tablero»**.

1. **Menú → «Tablero»**, y **clic en el ⋮** de la cabecera de la zona.
2. Elige:
   - **«Renombrar»**
   - **«Vaciar»** — «Las tarjetas vuelven a «sin colocar»»
   - **«Mover todo a otra columna»**
   - **«Borrar la columna»**

**Al borrar una zona vacía:** «La zona se va del tablero. No hay ningún pedido
dentro, así que no se pierde trabajo del día, pero la zona hay que volver a crearla a
mano con su nombre.» Con **«Sí, borrar «Centro»»** y **«No, dejarla»**.

**Al borrar una zona con pedidos** no te deja sin decidir qué pasa con ellos:

> **«Centro» tiene 8 pedidos puestos** — ¿Qué se hace con ellos?

Y dos salidas: **«Devolverlos a «sin colocar» y borrar»** o **«Mandarlos a otra
columna y borrar»**.

---

## Armar una ruta sin usar el Tablero

**Empieza en:** **Menú → «Rutas»**.

Es el camino largo, para cuando la ruta no sale de una zona entera.

1. **Menú → «Rutas»**, y arriba a la derecha de la lista, **clic en «+ Nueva
   Ruta»**.
2. Se abre un cajón a pantalla completa, **«Nueva Ruta»**, con cuatro tramos arriba:
   **«Sucursal» · «Salida» · «Vehículo» · «Pedidos»**.
3. **«Sucursal»** — elige en **«Sucursal de la ruta»** y **«Siguiente»**.
   **Cambiarla borra todo lo elegido después.**
4. **«Salida»** — elige en **«Almacén del que sale el camión»** y **«Siguiente»**.
   Sólo salen los que tienen coordenadas. Si no hay ninguno: «Esta sucursal no tiene
   ningún almacén con ubicación…» y un botón **«Poner el almacén»**.
5. **«Vehículo»** — **obligatorio**. Se ofrecen todos, con su capacidad de nota: «1000
   kg», «1000 kg · en el taller», «1000 kg · en ruta».
   - Si eliges uno del taller, sale un aviso en ámbar pero **se arma igual**.
   - Opcionalmente, el nombre y la **«Fecha de entrega»**, que **viene puesta en
     hoy**.
6. **«Pedidos»** — marca los que quieras.
   - **La barra de capacidad**: «115.6 / 10000 kg (1%)». Al 100 % sale **«LLENO»** y
     **«Camión lleno — no cabe más»**.
   - **Las filas que ya no caben se apagan**, con el motivo «No cabe en el camión».
   - Puedes marcar **una zona entera del tablero** con su casilla. Te dirá qué entró:
     **«9 de 12 de «Vista» · 1 ya estaban · 1 ya no se pueden repartir hoy · 1 no caben
     en el vehículo»**.
   - Si la zona trae otro camión distinto del que elegiste, te avisa y te da un botón
     **«Dejar el mío»**.
   - Debajo, el resumen: **«12 pedidos seleccionados (2 de otro día o filtro, siguen
     contando)»**. Ese «siguen contando» es literal: **siguen en la ruta y siguen
     sumando peso** aunque los filtros ya no los enseñen.
7. **Clic en «Generar Ruta»**.

Para volver atrás, **clic en el nombre del tramo** arriba («Vehículo», «Salida»…).

### Si «Generar Ruta» está apagado

Falta salida, camión o pedidos, o te has pasado de peso.

### Si sale un aviso en ámbar encima del botón

| Aviso | Qué hacer |
|---|---|
| **«Se requiere un vehículo para crear la ruta»** | Vuelve al tramo «Vehículo» |
| **«En una ruta sólo entra lo facturado y que cuadre. 3 no cumplen: X-2992 (sin facturar)…»** | Desmarca ésos |
| **«2 de los 12 pedidos elegidos no pueden ir en esta ruta: X-2992 (ya va en la ruta RT-20260922-003)…»** | Desmarca ésos |
| **«Peso total (1250.5 kg) supera la capacidad del vehículo (1000 kg)»** | Quita pedidos o cambia de camión |

---

## Filtrar la lista de rutas

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
aplicar estos filtros. Por eso «Planificadas (12)» puede salir encima de una lista de
3. No es un fallo.

**Y los filtros no se pueden mandar en un enlace.** Viven sólo mientras tengas la
pantalla abierta, y recargar los borra.

---

## Eliminar una ruta

**Empieza en:** **Menú → «Rutas»**.

1. **Menú → «Rutas»** y busca la ruta en su pestaña: **«Planificadas»** o **«En
   curso»**.
2. **Mira el código de la tarjeta** antes de nada, para no borrar la de al lado.
3. Al final de su tarjeta, **clic en «Eliminar»** (el botón rojo, con contorno y
   papelera, sin relleno).
4. **Se abre un cajón que pregunta antes**, titulado **«Borrar «RT-20260928-004»»**,
   y te dice lo que se pierde:

   > «La ruta desaparece con su código, su fecha, el orden de visita y los
   > kilómetros que se calcularon al armarla. Para tenerla otra vez hay que volver a
   > armarla desde el asistente, a mano.
   >
   > Lo que NO se borra son los pedidos: sueltan esta ruta y vuelven a la lista de
   > disponibles, listos para ponerlos en otra. Y el camión se queda libre.»

5. **Clic en «Sí, borrar «RT-20260928-004»»**, o en **«No, dejarla»** para salir.

> **Ojo:** **cerrar el cajón sin contestar es NO.** La ✕, clic fuera o Escape dejan
> la ruta donde estaba.

### Si no te deja borrarla

Si la ruta ya tiene paradas marcadas en el cierre, **ni pregunta**: sale el motivo
abajo, con las palabras del servidor:

> «Esa ruta ya tiene 3 parada(s) cerradas y no se puede borrar: se perdería la hoja
> de lo que bajó del camión. Márcala como cancelada si hace falta.»

**Las rutas completadas no se pueden eliminar**: ese botón no aparece.

Al eliminarla, **sus pedidos vuelven a estar disponibles**.

---

## Sacar un pedido de una ruta

**Empieza en:** **Menú → «Rutas»**.

**No hay ningún botón para quitar una parada.** Las dos formas:

- **Eliminar la ruta entera** y volver a armarla sin ese pedido.
- **Marcarlo en el cierre como devuelto o cancelado**: al completar la ruta, ese
  pedido queda libre.

---

## Consultar un cliente

**Empieza en:** **Menú → «Clientes»**.

1. **Menú → «Clientes».**
2. Escribe en **«Buscar por nombre, dirección o municipio…»**. Busca también por
   teléfono, código, zona y vendedor.
3. **Clic en la fila.** Se abre la ficha, con el **teléfono el primero**.

**No se crean, ni se editan, ni se borran.** Vienen de PEDIDO, y sólo los que tienen
geolocalización.

**Para ver los kilómetros de cada cliente**, filtra por **«A qué distancia del
almacén»**: sólo entonces sale la columna de km.

---

## Dar de alta un camión

**Empieza en:** **Menú → «Vehículos»**.

1. **Menú → «Vehículos».**
2. **Clic en «Agregar Vehículo»**.
3. Rellena:
   - **«Nombre del Vehículo *»** — obligatorio
   - **«Tipo»** — al elegirlo **hereda su costo por km**
   - **«Placa (opcional)»**
   - **«Capacidad Máx. (kg)»** — viene en 1000
   - **«Estado del vehículo»** — sólo hay **«Disponible»** y **«En mantenimiento»**
   - **«Costo por km (USD)»**
4. **Clic en «Agregar Vehículo»**. Verás **«Vehículo agregado.»**

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

**Empieza en:** **Menú → «Vehículos»**.

De este camión sale **el costo por km con el que se le cobra al cliente el
domicilio**. No está en el paso a paso del Panel, pero decide dinero.

1. **Menú → «Vehículos»**.
2. Busca la tarjeta del camión. **Debajo del nombre, en la fila de pastillas**, mira
   qué hay:
   - **«Cálculo domicilio · $1.65/km»**, con una casita — ya es el que calcula.
   - El botón **«Usar para domicilio»** — no lo es.
3. **Clic en «Usar para domicilio»**.
4. Abajo sale **«Se usará este vehículo para calcular el domicilio.»** y la tarjeta
   cambia: el botón desaparece y queda la pastilla **«Cálculo domicilio»**.

**También desde la ficha:** **clic en «Editar»** y marca **«Usar este vehículo para
calcular el domicilio»**. Debajo pone **«Solo un vehículo por TIPO.»**

> **Ojo:** si la pastilla dice **«Cálculo domicilio»** **y no lleva importe
> detrás**, ese camión está elegido y **no tiene costo por km**. Edítalo y ponle
> uno: así es como un domicilio sale sin precio teniendo camión.

---

## Marcar un camión en el taller

**Empieza en:** **Menú → «Vehículos»**.

1. **Menú → «Vehículos»**.
2. En la tarjeta del camión, abajo, **clic en «Editar»**.
3. En el desplegable **«Estado del vehículo»**, elige **«En mantenimiento»**.
4. **Lee la explicación que sale debajo del desplegable, en ámbar:**

   > «En el taller: no se le puede dar ruta hasta que vuelva. Escribe el motivo en
   > Notas, aquí abajo — es lo único que le dice al de al lado por qué no puede
   > contar con él. Marcarlo NO cierra la ruta que ya tuviera abierta: eso se
   > arregla en la tarjeta del camión.»

5. **Escribe el motivo en «Notas (opcional)»**, más abajo.
6. **Clic en «Actualizar»**. La insignia de la tarjeta pasa a **«Mantenimiento»** en
   ámbar.

> **Ojo:** el desplegable sólo tiene **«Disponible»** y **«En mantenimiento»**.
> **«En ruta» no está, a propósito**: eso sale de las rutas del camión y no se
> escribe a mano.

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

**Empieza en:** **Menú → «Vehículos»**.

1. **Menú → «Vehículos»**.
2. Busca la tarjeta del camión y **comprueba el nombre y la placa**.
3. Al final de la tarjeta, **clic en «Eliminar»** (rojo, con papelera, sin relleno).
4. **Se abre un cajón que pregunta antes**, titulado **«Borrar «Camión 1»»**, y dice
   lo que se pierde:

   > «El camión se va de la flota. Las rutas y los pedidos que lo llevaban puesto NO
   > se borran —el histórico de lo repartido se queda— pero se quedan sin camión, y
   > hay que ponerles otro. Y el camión hay que volver a darlo de alta a mano, con su
   > placa, su capacidad y su costo por km.»

5. **Clic en «Sí, borrar «Camión 1»»**, o en **«No, dejarlo»**.
6. Sale **«Vehículo eliminado.»** y la tarjeta desaparece de la lista.

> **Ojo:** **cerrar sin contestar es NO.** Y si era el camión del **«Cálculo
> domicilio»**, elige otro antes de irte: sin ninguno, los domicilios salen sin
> precio.

---

## Definir los tipos de camión y su costo por km

**Empieza en:** **Menú → «Vehículos»**.

El tipo es **el punto de partida del costo por km**: al crear un camión de ese tipo,
hereda su costo, y luego se puede cambiar camión por camión.

1. **Menú → «Vehículos»**.
2. Arriba, en la misma fila que la caja de buscar, **clic en «Tipos de vehículo»**.
3. Se abre un cajón, **«Tipos de vehículo»**, que empieza explicando para qué es:

   > «Define cada tipo con su costo por km por defecto. Al crear un vehículo de ese
   > tipo se hereda el costo/km (editable por vehículo).»

4. Por cada fila, rellena **«Nombre»** y **«Costo/km (USD)»**. La papelera
   (**«Quitar»**) borra la fila.
5. Para una fila más, **clic en «Agregar tipo»**, abajo.
6. Al pie, **clic en «Guardar»** (al lado de **«Cancelar»**). Sale **«Tipos
   guardados.»**

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

**Empieza en:** **Menú → «Rutas»**.

**No se puede.** Una ruta ya armada no deja cambiarle el camión: no hay ningún
botón para eso, ni en la tarjeta ni en el detalle. Las dos salidas:

**Si la ruta todavía no ha salido (pestaña «Planificadas»):**

1. **Menú → «Rutas»**, pestaña **«Planificadas»**.
2. **Elimina la ruta** — ver [Eliminar una ruta](#eliminar-una-ruta). Sus pedidos
   vuelven a la lista de disponibles y el camión queda libre.
3. **Menú → «Tablero»**, ve a la zona, **⋮ → «Camión previsto»**, elige el otro
   camión y **⋮ → «Armar la ruta de esta zona»**.

**Si la ruta ya está «En curso»**, no la borres: tiene paradas que el servidor no
va a dejar perder. Se termina con el camión que lleva y se cuadra en el cierre.

> **Ojo:** mandar un camión al taller **no** le quita la ruta. La aplicación lo dice
> en su tarjeta: «mandarlo al taller no la cierra, porque una ruta cerrada es una
> ruta repartida».

---

## Poner o corregir un almacén

**Empieza en:** **Menú → «Almacenes»**.

1. **Menú → «Almacenes».**
2. Elige la sucursal arriba, si hay más de una.
3. **Clic en «Nuevo almacén»**, o clic en el almacén que quieras corregir.
4. Escribe el **nombre**.
5. Pon el punto, de una de las **tres formas**:
   - **Escribe la dirección y clic en «Buscar»** (al menos 4 letras).
   - **Clic en el mapa.**
   - **Escribe las coordenadas a mano**: `19.83, -75.82`.
6. Si va a ser el principal, **clic en el chip «Principal»**.
7. **Clic en «Guardar»**. Verás **«Guardado en Accesos.»**

**Sólo puede haber un principal:** al marcar uno, los demás se desmarcan.

**Un almacén sin punto se puede guardar, pero desde él no se cotiza**, y te lo avisa:
«Sin coordenadas: desde éste no se puede medir el domicilio.»

---

## Cambiar cuál es el almacén principal

**Empieza en:** **Menú → «Almacenes»**.

El principal es el que se usa **cuando nadie dice cuál**. Lo dice el propio chip:
«Desde éste se mide cuando nadie dice cuál».

1. **Menú → «Almacenes»**, y arriba elige la sucursal si hay más de una.
2. En la lista, **clic en el renglón del almacén** que va a ser el principal. Se
   abre su cajón, con su nombre de título.
3. Debajo del nombre, **clic en el chip «Principal»** (la estrella se rellena).
4. **Clic en «Guardar»**. Sale **«Guardado en Accesos.»**
5. En la lista, la **estrella** se ha movido a ese almacén.

> **Ojo:** **sólo puede haber un principal.** Al marcar éste, los demás se
> desmarcan solos — no hay que ir a quitárselo al anterior.

---

## Quitar un almacén de la sucursal

**Empieza en:** **Menú → «Almacenes»**.

1. **Menú → «Almacenes»**, y arriba elige la sucursal.
2. **Clic en el renglón del almacén.** Se abre su cajón.
3. Debajo del nombre, a la derecha de los chips **«Principal»** y **«Activo»**, hay
   una **papelera** (**«Quitar»**). **Clic ahí.**
4. **Se abre un cajón que pregunta antes**, **«Borrar «Almacén Central»»**, y dice
   las cuatro cosas que pasan:

   > «El almacén se va de Accesos: se guarda la lista de Santiago sin él, así que
   > desaparece para todo el mundo y no sólo en esta pantalla. Deja de poder medirse
   > desde ahí: los pedidos que lo traen puesto pasan a medirse desde el principal de
   > la sucursal, con otro kilometraje y otro importe que se cobra igual que uno
   > bueno; y si era el último con punto, los domicilios de Santiago salen sin precio.
   > Los teléfonos que ya lo bajaron siguen midiendo desde él hasta la próxima vez que
   > tengan red —Accesos no avisa de los que se retiran—, así que cada entrega de ese
   > día se cobra mal y no se ve hasta cuadrar la caja. Volver a ponerlo es darlo de
   > alta a mano, con su dirección y su punto.»

5. **Clic en «Sí, borrar «Almacén Central»»**, o en **«No, dejarlo»**.

> **Ojo:** si sólo quieres que deje de usarse pero no perderlo, **no lo quites**:
> abre su cajón y **clic en el chip «Activo»** para dejarlo en **«Inactivo»**, y
> **«Guardar»**. En la lista queda con el rótulo «inactivo» y no se ofrece para
> salir.

---

## Cambiar entre USD y CUP

**Empieza en:** la barra de arriba, desde cualquier pantalla.

1. Arriba, a la derecha de la pastilla de la sucursal, **clic en la pastilla «USD» /
   «CUP»**.
2. Elige. **La opción de CUP lleva la tasa y su fecha como nota**: **«1 USD = 320 ·
   del 9/9/2026»**. Esa fecha no es un adorno: es lo único que demuestra que la tasa
   es de verdad.
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

**Empieza en:** tu avatar, arriba a la derecha.

1. **Clic en tu avatar**, arriba a la derecha.
2. En la sección **«Ir a»** hay una baldosa por aplicación, con su nombre y su
   descripción. **Se abren en otra pestaña.**

Si esa sección no sale, es que no se pudieron leer. No es un error, y el resto del
menú funciona igual.
