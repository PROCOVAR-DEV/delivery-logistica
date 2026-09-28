# Rutas

**Para qué sirve:** es donde vive la ruta desde que se arma hasta que se cierra.
Se ve la lista a la izquierda y el detalle de la elegida a la derecha (en el
teléfono, el detalle se abre en un cajón).

El título de la pantalla es **«Planificador de Rutas»**.

---

## Las tres pestañas

| Pestaña | Qué lleva | Si está vacía dice |
|---|---|---|
| **«Planificadas»** | Armadas y **sin salir** | «Sin rutas planificadas. Crea la primera.» |
| **«En curso»** | Las que salieron | «Sin rutas en curso.» |
| **«Historial»** | Las completadas | «Sin rutas completadas aún.» |

El número entre paréntesis —«Planificadas (0) · En curso (1) · Historial (0)»—
cuenta **rutas de la sucursal, sin aplicar los filtros**. Por eso, con filtros
puestos, ese número y las tarjetas que ves pueden no coincidir.

**Cambiar de pestaña cierra el detalle que tuvieras abierto.**

---

## Buscar y filtrar

- **Buscador**: «Buscar por código, nombre, vehículo...». Busca en el código de la
  ruta, su nombre, la dirección de salida, el camión y la sucursal. Busca solo,
  sin Intro.
- **«Rutas de un camión»** — por defecto «Cualquier vehículo». Los camiones que
  están fuera salen con la nota «en ruta».
- **«Ubicación de salida»** — por defecto «Cualquier ubicación». Las opciones son
  los sitios de los que han salido rutas de verdad, cada uno con cuántas. Las que
  no tienen salida guardada se agrupan al final en **«Sin punto de partida»**.
- **Desde / Hasta** — por la fecha en que se creó la ruta. «Hasta» incluye el día
  entero.
- **«Limpiar»** — sólo aparece si hay algún filtro puesto, y los quita todos.

La lista va de **20 rutas por página**.

---

## Qué se ve en cada tarjeta de la lista

```
RT-20260928-001                                   En curso
3 paradas · 68.0 km · 28/9/2026
   Camión 1 (P-001) · EN RUTA en RT-20260928-002
   Carretera Central km 3
$5212.78                                         Eliminar
```

- **El código** a la izquierda y **el estado** a la derecha: «Planificada» (ámbar),
  «En curso» (azul) o «Completada» (verde).
- **Paradas, kilómetros y fecha de entrega.** Si la fecha no está, sale «—». Si
  las paradas todavía no se saben, ese trozo **no sale**: nunca dice «0 paradas».
- **El camión**, y **cómo anda ese camión**, que es un dato muy útil:
  - «· libre» — no lo tiene cogido ninguna ruta.
  - «· EN RUTA en RT-20260928-002» — está fuera, en otra ruta.
  - «· ya va en RT-20260929-001» — está apalabrado para otra ruta planificada.
  - Si todavía no se sabe, **no dice nada**. Nunca dice «libre» sin comprobarlo.
  - Sin camión: **«Sin vehículo»**.
- **De dónde sale**, o «Sin punto de partida».
- **«Sobrepeso»** en ámbar si la ruta pesa más que la capacidad del camión.
- **El importe**, que **se suma de las paradas**. Si falta cotizar alguna sale en
  ámbar: «— (2 de 5 sin cotizar)». Nunca sale `$0.00` por falta de datos.
- **«Eliminar»** — **sólo si la ruta no está completada**.

---

## El detalle de una ruta

### La línea de datos

Todo en un renglón, separado por puntos:

```
En curso · 68.0 km (incl. regreso) · 516 kg · $5212.78 · Camión 1 · P-001 · libre
· 28/9/2026 · Carga total: 3 · 2 h 15 min en ruta
```

| Trozo | Qué es |
|---|---|
| `En curso` | El estado |
| `68.0 km (incl. regreso)` | Los kilómetros del camión: almacén → parada 1 → … → parada n → **vuelta al almacén** |
| `516 kg` | El peso de la ruta, redondeado |
| `$5212.78` | Lo que suman los domicilios de sus paradas |
| `Camión 1 · P-001 · libre` | El camión, su matrícula y cómo anda |
| `28/9/2026` | La fecha de entrega, o «—» |
| `Carga total: 3` | Cuántas **paradas** lleva |
| `2 h 15 min en ruta` | Lo que lleva fuera. Si ya terminó, lo que duró: «3 h 20 min» |

Si falta cotizar alguna parada, debajo sale en ámbar:

> «Faltan cotizar 2 paradas de 5: sin ellas no hay importe de la ruta.»

Si la ruta pesa más que el camión, una insignia:

> «Peso total (1250.5 kg) supera capacidad (1000 kg)»

### Los dos kilometrajes, que NO son el mismo

1. **`68.0 km (incl. regreso)`** de la línea de datos son **los del camión**: el
   circuito entero, ida y vuelta.
2. **Los de cada parada** son **la línea recta desde la salida hasta ese cliente**.
   Por eso el rótulo lo dice: **«10.4 km en recta desde la partida»**. Es la
   medida con la que se cobra el domicilio.

**Sumar los de las paradas no da los de la ruta.** No es un error.

Si la parada no tiene coordenadas, pone **«sin ubicar»**; si no las tiene el
almacén de salida, **«sin punto de partida»**.

### Los botones, y en qué estado sale cada uno

| Botón | En qué estado |
|---|---|
| **«Ver paradas (3)»** | Siempre |
| **«Iniciar ruta»** | Sólo planificada |
| **«Cierre (3)»** | Sólo en curso. El número son las paradas sin marcar |
| **«Marcar como completada»** | Sólo en curso |
| **«Ver cierre»** | Sólo completada. **Solo lectura**, y por eso no lleva número |

- **«Iniciar ruta»** cambia el estado, **marca el camión ocupado** y te lleva
  sola a la pestaña «En curso» con la ruta abierta.
- **«Marcar como completada»**: si quedan paradas sin marcar, abre primero el
  cierre. Al terminar, suelta la ruta y salta al «Historial».

### «Ver paradas»

Se abre un cajón titulado **«Paradas y precio por cliente (3)»**. Por cada parada:
su número, el cliente, la dirección de entrega, los renglones que se bajan ahí
(«12× MALTA GUAJIRA»), el peso, los km en recta, el número de operación, y a la
derecha **el importe en grande**: `$12.00` o **«sin cotizar»**.

### «Recorrido» — el mapa

Si todo va bien (calles y recorrido por carretera) **no dice nada**. Cuando no:

- «Mapa de calles.»
- «Sin señal: croquis con las coordenadas del aparato.» (APK y escritorio)
- «El mapa de calles no cargó: esto es el croquis.» (web)
- «Recorrido aproximado, en línea recta.»

Si no hay nada que dibujar:

- «Esta ruta todavía no tiene paradas, así que no hay recorrido que dibujar.»
- «No se puede dibujar el recorrido: ni el almacén de salida ni ninguna de las 3
  paradas tienen coordenadas guardadas.»

**Cuatro botones:** **«Abrir en Google Maps»**, **«WhatsApp»**, **«Compartir»** y
**«Copiar»**. El único que se apaga es el primero, si no hay enlace que abrir.

Avisos del enlace:

- «Google admite 25 paradas: 3 paradas quedan fuera.»
- «2 paradas no tienen coordenadas y no entran en el enlace.»
- «Esta ruta no tiene guardadas las coordenadas del almacén de salida, así que no
  se puede armar el enlace de Google Maps.»

Al copiar: **«Copiado. Ya se puede pegar en un chat.»**

### «Carga total»

Al final del detalle, una insignia por producto con lo que lleva el camión en
total: «MALTA GUAJIRA ×48».

---

## El asistente «Nueva Ruta»

Se abre con **«+ Nueva Ruta»**. Son **cuatro pasos**: **«Sucursal»**,
**«Salida»**, **«Vehículo»** y **«Pedidos»**. Abajo, siempre, **«Cancelar»** y
**«Generar Ruta»**.

**«Generar Ruta» está apagado** hasta que haya salida, haya vehículo, haya al
menos un pedido elegido y no haya sobrepeso.

### Paso 1 — «Sucursal»

**«Sucursal de la ruta»**, obligatorio. «Los pedidos, los vehículos y el punto de
partida serán los de esta sucursal.» Se rellena solo con la de arriba.

**Cambiar de sucursal borra la salida y todo lo elegido.**

### Paso 2 — «Punto de partida»

**«Almacén del que sale el camión»**, obligatorio. **Sólo salen los almacenes con
coordenadas**; el principal va primero, con la nota «principal».

Si la sucursal no tiene ninguno:

> «Esta sucursal no tiene ningún almacén con ubicación. Se pone en Almacenes, y
> hasta entonces no hay desde dónde medir.»

Con el botón **«Poner el almacén»**, que cierra el asistente y lleva a Almacenes.

### Paso 3 — «Vehículo»

**«Vehículo de la ruta»**, **obligatorio**. Se ofrecen **todos**, también los
ocupados y los del taller, con su capacidad de nota: «1000 kg · en el taller»,
«1000 kg · en ruta».

Si eliges uno del taller sale un **aviso, no un bloqueo**:

> «Camión 1 está marcado EN EL TALLER. La ruta se arma igual —tiene su capacidad y
> su costo por km— pero ese camión no puede salir hoy. Si ya volvió, sácalo del
> taller en Vehículos.»

Además: un nombre opcional («Nombre (el código se genera solo)») y la **«Fecha de
entrega»**, que **arranca en hoy**.

Si no hay camiones:

- «No hay vehículos disponibles. Crea o libera uno en Vehículos para poder crear
  la ruta.»
- «Esta sucursal no tiene ningún vehículo dado de alta. Los que hay son de otras
  sucursales, y un camión de otra sucursal no está donde sale esta ruta.»

### Paso 4 — «Pedidos de cliente (12)»

Los filtros:

| Filtro | Por defecto |
|---|---|
| «Sucursal de la ruta» | la del paso 1 |
| «Día de los pedidos» + «Todos los días» | — |
| «Buscar pedido...» | vacío |
| «Vendedor del pedido» | «Todos los vendedores» |
| «Municipio del cliente» | «Todos los municipios» |
| «km máx.» | sin tope. Se aplica al salir del campo |
| «costo mín.» | sin tope |
| «Estado del pedido en PEDIDO» | «Cualquier estado» |
| «Si el pedido lleva entrega a domicilio» | **«Sólo con domicilio»** |
| «Si Entrega ya le puso costo de domicilio» | «Cotizados y sin cotizar» |

**«Limpiar»** vuelve a «Sólo con domicilio», no a «sin nada».

**Cuidado con «costo mín.»:** un pedido sin cotizar cuenta como cero, así que
cualquier «costo mín.» mayor que cero lo deja fuera.

**El cuadre con la factura no se puede cambiar**: siempre entra sólo lo que
cuadra.

### La barra de capacidad

```
115.6 / 10000 kg (1%)
```

Verde por debajo del 80 %, ámbar entre 80 y 99, roja al 100 % o más. Al llegar al
100 % sale **«LLENO»** y **«Camión lleno — no cabe más»**.

Las filas de los pedidos que ya no caben **se apagan**, no se esconden, con el
motivo: **«No cabe en el camión»**.

### Elegir una zona entera del tablero

Las zonas del Tablero salen en esta lista con su propia casilla, que marca la zona
completa. Debajo: «12 pedidos · 340 kg · camión: Camión 1» o «… · sin camión
previsto».

Al marcarla, un aviso dice exactamente qué entró y qué no:

> «9 de 12 de «Vista» · 1 ya estaban · 1 ya no se pueden repartir hoy · 1 no caben
> en el vehículo»

Y si la zona trae un camión distinto del que ya habías elegido, se te avisa y
tienes un botón **«Dejar el mío»**.

### La línea de resumen

> «12 pedidos seleccionados (2 de otro día o filtro, siguen contando)»

Ese «siguen contando» es importante: los pedidos que elegiste y luego dejaron de
salir con los filtros **siguen en la ruta y siguen sumando peso**.

### El pre-despacho del asistente

Caja **«Pre-despacho»** con **«Ver e imprimir»**. Vacía dice: «Según vayas
eligiendo pedidos, aquí sale cuánto hay que sacar de cada producto.»

En el teléfono es un botón: **«Pre-despacho — elige pedidos primero»** (apagado) o
**«Pre-despacho de los 12 elegidos»**.

---

## Los «no» al pulsar «Generar Ruta»

Salen **dentro del cajón, justo encima del botón**, en ámbar y con su equis para quitarlo. Se
comprueban en este orden:

1. **«Las coordenadas del punto de partida son requeridas»**
2. **«Se requiere un vehículo para crear la ruta»** — éste es el motivo de que
   **no se pueda armar una ruta sin camión**. Es bloqueo, no aviso.
3. **«Una ruta se arma eligiendo pedidos ya existentes.»**
4. **Pedidos que no pueden ir**, con el motivo de cada uno:

   > «2 de los 12 pedidos elegidos no pueden ir en esta ruta: X-2992 (ya va en la
   > ruta RT-20260922-003), X-3010 (sin coordenadas de entrega).»

   Los motivos posibles: «ya se entregó y no puede volver a un camión», «ya va en
   la ruta RT-…», «PEDIDO lo archivó», «sin coordenadas de entrega», «no vino de
   PEDIDO».
5. **Facturación**:

   > «En una ruta sólo entra lo facturado y que cuadre. 3 no cumplen: X-2992 (sin
   > facturar), X-3010 (cambió en la factura), X-3011 (sin cotejar).»
6. **Capacidad**:

   > «Peso total (1250.5 kg) supera la capacidad del vehículo (1000 kg)»

   Igualar la capacidad exacta **sí** pasa.

---

## El cierre de ruta

Título **«Cierre de ruta»**, con el código y cuántas paradas: «RT-20260928-001 · 3
parada(s)».

**Hay tres modos**, y cambian lo que se puede tocar:

| Modo | Cuándo | Qué dice arriba |
|---|---|---|
| **Marcar** | Ruta en curso, botón «Cierre (3)» | «Marca cada parada según cómo acabó. De aquí sale el post-despacho: lo que tiene que quedar en el camión es todo lo que no se entregó…» |
| **Al completar** | Al pulsar «Marcar como completada» quedando paradas sin marcar | «Antes de dar la ruta por completada: ¿cómo acabó cada parada? **Lo que dejes sin marcar se da por no entregado y cuenta como que sigue en el camión.**» |
| **Solo lectura** | Ruta completada, botón «Ver cierre» | «La ruta ya está completada: así acabó cada parada. **Para corregir algo, hay que hacerlo en PEDIDO.**» |

### Qué se pregunta en cada parada

Tres botones, y sólo uno a la vez:

- **«Entregado»** (verde)
- **«Devuelto»** (rojo)
- **«Cancelado»** (gris)

**Pulsar el mismo botón dos veces lo desmarca**, para corregir un dedazo.

Si marcas «Devuelto» o «Cancelado» aparece un campo de nota, **opcional**, con la
pista: «¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)». Hasta
500 caracteres.

Arriba hay atajos: **«Todas:»** «Entregado» / «Devuelto» / «Cancelado».

Si quedan paradas sin marcar, aviso en ámbar:

> «3 sin marcar · cuentan como que siguen en el camión»

### «Queda en el camión»

Se recalcula con cada marca, en vivo:

- Si no queda nada: **«Nada: se entregó todo lo que salió.»**
- Si queda: una insignia por producto, «MALTA GUAJIRA ×36».
- Y un aviso que hay que leer:

  > «2 paradas no se entregaron y sus pedidos no traen renglones: NO CONSTA qué
  > baja del camión. Cuéntalo a mano contra la lista de abajo.»

### Los botones de abajo

- **«Post-despacho»** — abre la hoja con lo marcado **en este momento**, aunque
  todavía no lo hayas guardado.
- **«Cerrar»**, o **«Salir sin guardar (3 sin guardar)»** si dejaste algo. **Se
  dice, no se bloquea.**
- El de guardar, con cuatro textos según el caso: «Guardando…», «Guardar y
  completar», «Guardar 4 y quitar 1», «Guardar 5 marcada(s)».

Al guardar bien:

> «Cierre guardado. En PEDIDO cada pedido ya dice si se entregó o volvió.»

### En una ruta ya completada

- **No hay botones de resultado, ni siquiera apagados.** Cada parada enseña su
  resultado, o la insignia **«Sin marcar · siguió en el camión»**.
- La nota se ve, pero no se edita.
- **No hay botón de guardar.** No está apagado: no está.
- El post-despacho **sí** se puede seguir viendo e imprimiendo.

---

## Lo que se imprime

### Pre-despacho — antes de salir

Se saca del **paso 4 del asistente**, con «Ver e imprimir». Título del cajón:
**«Hoja de pre-despacho»**, con «12 pedido(s) · 340.5 kg». El fichero se llama
`pre-despacho.pdf`.

Lleva: sucursal y vehículo, el día, cuántos pedidos, el peso, y una tabla de
**«Producto» | «Empaques» | «Unidades» | «kg» | «Sacado»** —la última en blanco,
para ir marcando a mano—, con su fila de **«Total»**, los dos pesos («Peso de los
productos» y «Peso de los pedidos») con su explicación, y las dos firmas: **«Sacó
del almacén»** y **«Recibió (chofer)»**.

### Post-despacho — al volver

Se saca del **cierre**, con «Post-despacho». Título **«Post-despacho»**, y debajo
el resumen: «8 entregadas · 2 devueltas · 1 canceladas · 1 sin marcar». El fichero
se llama `post-despacho.pdf`.

Lleva dos secciones:

1. **«Tiene que quedar en el camión»** — tabla de «Producto» | «Salió» |
   «Entregado» | «Queda» | «Bajó» (la última en blanco, para contar a mano).
2. **«De quién es lo que vuelve»** — una línea por parada no entregada, con
   «Devuelto», «Cancelado» o «Sin marcar», y qué llevaba.

Y las firmas: **«Entregó (chofer)»** y **«Recibió en almacén»**.

**Lo que queda en el camión es todo lo que no se entregó**: lo devuelto, lo
cancelado y **lo que nadie marcó**.

### El mensaje al chófer

Los botones «WhatsApp», «Compartir» y «Copiar» arman este mensaje:

```
Ruta RT-20260928-001 — Reparto Vista
3 paradas · 68.0 km (incl. regreso) · Camión 1 (P-001) · 28/9/2026
https://www.google.com/maps/dir/?api=1&origin=…
```

El enlace va en la última línea a propósito: en WhatsApp es el que se convierte en
tarjeta. El origen y el destino son el **mismo almacén**, porque el camión vuelve.
El tope es de **25 paradas**, y lo que se queda fuera se dice en el propio mensaje.

---

## Lo que Rutas NO hace

- **No se puede quitar una parada de una ruta.** No hay ese botón. Para sacar un
  pedido de una ruta hay que **eliminar la ruta entera** o **marcarlo como no
  entregado en el cierre**; en los dos casos el pedido vuelve a estar disponible.
- **No se pueden reordenar las paradas a mano** desde esta pantalla.
- **No se puede eliminar una ruta completada.** El botón «Eliminar» ni siquiera
  aparece.
- **No se puede corregir el cierre de una ruta completada.** Hay que hacerlo en
  PEDIDO.
- **No se teclean paradas a mano.**
- **No se puede mandar un enlace de esta pantalla con los filtros puestos**: los
  filtros, la pestaña y el buscador viven sólo mientras la tienes abierta, y
  recargar los borra.
- **Lo único que necesita señal en toda esta pantalla es «Abrir en Google Maps».**
  Ver, filtrar, armar, iniciar, completar, eliminar y cerrar funcionan sin red (en
  la APK y en el escritorio).
