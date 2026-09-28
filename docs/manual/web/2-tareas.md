# Tareas sueltas

«Quiero hacer X»: dónde hacer clic, paso a paso.

---

## Buscar un pedido

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

1. **Menú → «Pedidos».**
2. **Clic en cualquier sitio de la fila** (la fila entera abre el detalle).
3. Se abre un cajón por la derecha, con el cliente de título y el folio debajo:
   **«Entrega»**, **«Recorrido»**, la banda de la factura, el bloque del domicilio y
   **«Productos (6)»**.

**Es sólo lectura.** Los pedidos vienen de PEDIDO y aquí no se editan.

---

## Renombrar, vaciar o borrar una zona

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

1. **Menú → «Rutas»** y busca la ruta en su pestaña.
2. Al final de su tarjeta, **clic en «Eliminar»** (el botón rojo con la papelera).

**Las rutas completadas no se pueden eliminar**: ese botón no aparece.

Al eliminarla, **sus pedidos vuelven a estar disponibles**.

Si el servidor no deja, te dice por qué, con sus palabras: por ejemplo que esa ruta
ya tiene paradas cerradas.

---

## Sacar un pedido de una ruta

**No hay ningún botón para quitar una parada.** Las dos formas:

- **Eliminar la ruta entera** y volver a armarla sin ese pedido.
- **Marcarlo en el cierre como devuelto o cancelado**: al completar la ruta, ese
  pedido queda libre.

---

## Consultar un cliente

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

## Poner o corregir un almacén

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

## Cambiar entre USD y CUP

1. Arriba, al lado de la sucursal, **clic en la pastilla «USD» / «CUP»**.
2. Elige. La opción de CUP lleva la tasa: **«1 USD = 320 · del 9/9/2026»**.

**Si sólo te deja USD** y la pastilla está en ámbar, esa sucursal **no tiene tasa de
cambio**. No se usa la de otra, a propósito. Se arregla en Accesos.

---

## Ir a otra aplicación de la casa

1. **Clic en tu avatar**, arriba a la derecha.
2. En la sección **«Ir a»** hay una baldosa por aplicación, con su nombre y su
   descripción. **Se abren en otra pestaña.**

Si esa sección no sale, es que no se pudieron leer. No es un error, y el resto del
menú funciona igual.
