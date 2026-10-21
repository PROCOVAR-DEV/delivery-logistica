# Facturas

**Para qué sirve:** es el catálogo de todo lo que hay por repartir y lo que ya se
repartió. De aquí sale el pre-despacho y de aquí se mandan facturas al Tablero.

**Ya no son pedidos, son facturas** (Jose, 21/10/2026). Lo que se reparte es la
**factura de Ventra**; el pedido de PEDIDO es un extra, enlazado por folio. La pantalla
se llamaba «Pedidos»: ahora es «Facturas», en el menú y en la dirección (`/facturas`; el
enlace viejo `/orders` sigue funcionando y lleva aquí).

Debajo del título pone: «Todas las facturas acumuladas de todas las rutas».

**Recuerda:** la lista es **de la sucursal que tengas puesta arriba**. Aquí no hay
filtro de sucursal.

---

## La franja azul del arranque

Al entrar, la pantalla **viene acotada a propósito** y lo dice:

> «Enseñando sólo lo que tiene factura —cuadre o no— y sin archivar. A una ruta
> entra lo facturado con el domicilio cobrado: si la factura cambió, al camión va lo
> facturado.»

Debajo, el botón **«Ver todas las facturas»**, que quita ese acotado.

Si no encuentras una factura, esto es lo primero que hay que probar.

**Esta lista enseña lo que tiene factura; no todo lo que sale entra en una ruta.** A una
ruta nueva o a una zona sólo entra lo que además tiene **el domicilio cobrado** en la
factura. Una factura que cambió respecto de lo pedido sí entra: al camión va lo
facturado. Ver [Las reglas del reparto](../las-reglas-del-reparto.md).

---

## Los filtros

| Filtro | Por defecto | Qué hace |
|---|---|---|
| **Buscar** | vacío | Busca en cliente, folio, dirección, municipio, vendedor y productos. Busca solo, sin Intro |
| **«Estado de reparto en delivery»** | «Cualquier reparto» | «Sin entregar», «En despacho», «En ruta», «Entregado», «Devuelto o cancelado» |
| **«Municipio del cliente»** | «Todos los municipios» | Cada municipio con cuántas facturas tiene |
| **«Precio del pedido»** | «Cualquier precio» | «Con precio puesto» o «Sin cotizar». Es el precio que cotizó Entrega al pedido, así que **sólo cuenta para las facturas que vienen de un pedido** |
| **«Pedido de origen»** | «Con o sin pedido» | «Con pedido» o «Sin pedido»: si la factura viene de un pedido de PEDIDO (tiene su folio) o no |
| **«Vendedor del pedido»** | «Todos los vendedores» | **Uno o varios**: un cajón con una casilla por vendedor (con cuántas facturas tiene cada uno); salen los de cualquiera de los marcados. «Todos los vendedores» limpia, y la caja dice «3 vendedores» si hay varios |
| **«Cómo se ordena esta página»** | «Más recientes» | «Más antiguos», «Precio: mayor a menor», «Precio: menor a mayor», «Distancia: más larga», «Peso: mayor» |
| **«Desde (fecha de la factura)»** / **«Hasta (fecha de la factura)»** | vacías | Con «Desde» puesto aparece **«sólo ese día»**, que copia la fecha en las dos. Filtran por la **fecha de la factura**, contada en hora de Cuba, los dos días incluidos |

**Cuidado con el orden:** «Cómo se ordena esta página» ordena **sólo la página que
estás viendo**, no las 246 facturas enteras.

Cualquier cambio de filtro te devuelve a la página 1.

Si abres un enlace con filtros que no se entienden, sale un aviso en ámbar:

> «Este enlace traía filtros que no se pudieron aplicar: desde=31-12-2026,
> reparto=volando.»
> «La lista que estás viendo NO está acotada por ellos.»

---

## El conteo de arriba

> «246 facturas · del 1/9/2026 al 28/9/2026, del más nuevo al más viejo»

Cambia según las fechas que tengas puestas: «· del 28/9/2026», «· desde el
1/9/2026», «· hasta el 28/9/2026». Y **siempre** acaba diciendo el orden.

---

## Las columnas de la tabla

**Cada fila es una factura de Ventra con entrega a domicilio. Si viene de un pedido de
PEDIDO, la columna Pedido enseña su folio; si no, un guion.**

**La factura es la primera columna** (después de la casilla): ella es la fila. El pedido
es un extra, y por eso va más a la derecha y puede faltar.

| Columna | Qué es |
|---|---|
| (casilla) | Marca la factura. La de la cabecera dice «Elegir todos los de esta página» |
| **«Factura»** | **La primera.** El número de factura de Ventra, y si cuadra o cambió y si el domicilio está cobrado. Ver abajo |
| **«Fecha factura»** | El día de la factura, en hora de Cuba. Si le falta, sale la del espejo con un `≈` delante: «≈ 12/9/2026» |
| **«Sucursal»** | Sólo sale si no tienes una sucursal elegida arriba |
| **«Pedido»** | **De qué pedido de PEDIDO viene la factura:** su folio (entero en el tooltip). Un **«—»** si la factura no viene de ningún pedido |
| **«Cliente»** | El nombre y, debajo, **a dónde se lleva** (la dirección de entrega). Si la factura no trae punto, una línea ámbar: «Sin ubicación: ponle la dirección en «Ubicar la entrega»» |
| **«Ruta»** | El código de ruta, o «—» |
| **«Artículos»** | El primer producto y cuántos más («+3»). Todo en el tooltip |
| **«Peso»** | «128.0 kg» o «—» |
| **«Precio»** | El domicilio de la parada: lo que cotizó Entrega o, si no, lo que cobró la propia factura. **«sin cotizar»** en gris si no hay ninguno |
| **«Entrega»** | El estado de reparto |

En pantalla estrecha no hay tabla: cada factura es una tarjeta, y la cabecera dice
«Elegir los 50 de esta página». **El título de la tarjeta es el número de factura**
(`Factura 1024237 · 15/10/2026`: el número de Ventra y, después, la fecha en que se facturó, en hora de Cuba; sin factura no se pone fecha), y debajo va el cliente, en negrita y más pequeño; luego
el número de operación, que es otro, y la fecha. Sin número de factura, el título dice
**«Sin número de factura»**, en gris. La tabla de escritorio pone la fecha de la factura bajo el número, y además la tiene en su propia columna, **«Fecha factura»**. En la tarjeta, lo de la columna «Factura» queda en una insignia que
solo dice el estado: **«Cuadra»** en verde o **«Cambió !»** en ámbar.

---

## Los tres estados de una factura

Son **tres cosas distintas** en tres columnas distintas. No los confundas.

### Columna «Pedido» — cómo va el pedido en PEDIDO

Es el estado **del pedido de PEDIDO del que viene la factura**, y sale debajo de su
folio. Si la factura no viene de ningún pedido, la columna dice «—» y no hay estado.

| Etiqueta | Qué significa |
|---|---|
| **«Completada»** (verde) | La orden está cerrada en PEDIDO |
| **«En proceso»** (ámbar) | Ni cerrada ni vencida |
| **«Expirada»** (rojo) | No está completada y la fecha comprometida ya pasó |

Si el pedido está archivado en PEDIDO, esa insignia lleva el aviso «Archivado en PEDIDO».

### Columna «Entrega» — cómo acabó en el reparto

| Etiqueta | Cuándo sale |
|---|---|
| **«Entregado»** (verde) | La parada se marcó entregada |
| **«Devuelto»** (ámbar) | La parada se marcó devuelta |
| **«Cancelado»** (ámbar) | La parada se marcó cancelada |
| **«En ruta»** (azul) | Va en una ruta que está **en curso** |
| **«En despacho»** | Va en una ruta **planificada** |
| **«Sin entregar»** (gris) | Todo lo demás |

**Manda cómo acabó la parada, no el estado de la ruta.** Una ruta completada no
convierte en entregada una factura que volvió en el camión.

**Un devuelto o cancelado que se mete en otra ruta empieza de cero.** La factura que
volvió ayer en el camión y hoy se mete en una ruta nueva sale como una cualquiera
(«En despacho», luego «En ruta»), **sin el resultado de la vez anterior**: no arrastra
ni el «Devuelto» ni el «Cancelado». Su resultado se marca de nuevo al cerrar la ruta
nueva.

### Columna «Factura» — la primera

Es la fila misma: el número de factura de Ventra y, debajo, su fecha.

| Qué se ve | Qué significa |
|---|---|
| El número en verde | «Cuadra con lo pedido: se puede repartir tal cual.» |
| El número con un `!` en ámbar | «Se facturó algo distinto de lo pedido: al camión va lo facturado.» |
| «sin facturar» en gris | No hay factura |
| «sin cotejar» en gris | «El cotejo contra Ventra no ha pasado por este pedido todavía.» |

**Y, junto al número, si el domicilio está cobrado.** Sólo cuando hay factura (el número
en verde o con el `!`):

| Qué se ve | Qué significa |
|---|---|
| **«Dom. $0.46»** en verde | La factura trae la línea «ENTREGA A DOMICILIO» y cobra ese importe: el domicilio está cobrado |
| **«Sin cobro de domicilio»** en gris | «La factura no trae la línea ENTREGA A DOMICILIO. No impide ir a una ruta: en «Cobro del domicilio» se filtra por con cobro o sin cobro.» |

Así se ve **antes de marcar** si una factura trae el domicilio cobrado o no: hay factura, pero
puede que no cobrara el domicilio. Con «sin facturar» o «sin cotejar»
no sale esta marca, porque ya está dicho que falta la factura.

**El ámbar sólo sale si ése es el motivo.** Una factura que ya va en una ruta, que ya se
entregó o que está archivada no tiene nada que colocar, así que lleva sólo el número de
factura (o el «Dom.» verde, si la factura sí cobró el domicilio). Un devuelto o cancelado
sí lo lleva, porque se puede volver a meter en otra ruta.

La columna «Factura» no sale en pantallas de menos de 1024 px de ancho (y con ella se va
la primera posición: la tabla empieza entonces por «Fecha factura»). **El número de
factura no desaparece con ella**: entre 768 y 1023 px baja a la celda del cliente, debajo del
número de operación, como `Factura 1024237`; en el teléfono es **el título de la tarjeta**,
y la marca del domicilio va en la insignia de abajo.

---

## El pre-despacho

Hay **dos**, y los dos abren el mismo cajón.

### El de lo elegido

Al marcar facturas aparece una franja azul: **«7 factura(s) elegidas»**, con tres
botones:

1. El del pre-despacho
2. **«Mandar a una zona»**
3. **«Quitar la marca»**

### El de lo filtrado

Es un botón, en la misma fila que las fechas. **La suma no se hace hasta que lo
pulsas.**

### El rótulo del botón

- Antes de sumar: **«Pre-despacho»**
- Después: **«Pre-despacho · 24 productos»**

### Lo que hay dentro

Cajón **«Pre-despacho»**, con el resumen arriba:

```
24 producto(s) · 23150 empaques · ≥ 26320.0 kg (21 renglones sin peso)
```

Y una tabla de cuatro columnas: **«Producto» | «Empaques» | «Unidades» | «kg»**.
En pantalla estrecha, una tarjeta por producto con cada cifra y su rótulo pegado:
«1234 empaques», «88.5 kg».

Abajo, los cuatro totales: **«Empaques»**, **«Unidades»**, **«Peso de los
productos»** y **«Peso de las facturas»**, con la frase que los separa:

> «No son el mismo número: el de arriba suma renglón a renglón, y el de abajo es
> el peso que trae cada factura entera.»

Y el botón **«Ver e imprimir»**, que abre la **«Hoja de pre-despacho»** para
imprimir: «264 factura(s) · 24891.0 kg».

### El peso, con todo detalle

Ver [Qué significa cada número](../que-significa-cada-numero.md). En corto:

| Caso | Qué se escribe |
|---|---|
| No se sabe el peso de **ninguna** línea | «sin peso en las facturas» |
| Se sabe el de **todas** | «26320.0 kg» |
| Se sabe el de **unas sí y otras no** | «≥ 26320.0 kg (21 renglones sin peso)» |

Con un solo renglón faltando, el texto va en singular: «≥ 1200.0 kg (1 renglón sin
peso)».

**Dentro de la tabla, en la celda, el texto es más corto**: «≥ 26320.0», sin el
paréntesis. El rótulo de la columna ya dice «kg».

Las unidades siguen la misma regla: «≥ 600 (3 renglones sin unidades)».

**Un renglón sin peso** es una línea de la factura cuyo peso no consta: ni lo manda
Ventra en ese renglón ni se puede sacar del catálogo. De los 129 productos de
Ventra sólo 57 traen peso, así que esto es lo normal, no una avería.

---

## El detalle de una factura

Se abre tocando la fila. **Es de lectura: aquí no se edita nada** salvo **una** cosa, el
punto de entrega (ver [«Ubicar la entrega»](#ubicar-la-entrega--el-punto-de-entrega-puesto-a-mano)).

Lleva, en este orden:

1. **«Entrega»** — dirección, coordenadas y teléfono del cliente. Si el punto se puso a
   mano, la etiqueta **«Punto puesto a mano»**. Debajo, el botón **«Ubicar la entrega»**
   (o, si no se puede, el motivo).
2. **«Recorrido»** — «Del almacén (ALMACÉN CENTRAL) al cliente.» o «Sin
   coordenadas GPS para esta ruta».
3. **La banda de la factura**, que empieza por **el número y cuándo se facturó**, en
   negrita: `Factura F-2992 · facturada el 12/10/2026` (la fecha es la del cotejo contra
   Ventra, que ronda la hora en que se facturó; sin número de factura no sale), y sigue
   con el estado:
   - Verde: «Cuadra con la factura F-2992 de Ventra: lo pedido es lo facturado.»
   - Ámbar: «Se facturó algo distinto de lo pedido (factura F-2992). Al camión va lo
     facturado: los productos de abajo ya son los de la factura.» **Esta factura sí
     sube a una ruta**, con lo facturado. Si la factura no se pudo atar a este pedido,
     dice en cambio «…, pero los productos de abajo son los del pedido: la factura no se
     pudo atar a este pedido.», y si no se sabe, sólo «Al camión va lo facturado.».
   - Gris: «Todavía no aparece facturado en Ventra.»
   - Con factura, una línea que dice si puede ir a una ruta:
     - «Puede ir a una ruta.»
     - «No entra a una ruta: la factura no tiene un cobro de domicilio registrado.»
     - «No entra a una ruta: se marcó domicilio y Entrega todavía no lo cotizó.»

     No sale nada si la factura ya va en una ruta, ya se entregó o está archivada.
   - Y si la factura cobró domicilio: «La factura cobró 15.00 USD de domicilio.»
     **Sin ese cobro, la factura no se ofrece para una ruta ni para una zona.**
4. **El bloque del domicilio** — «Distancia 4.35 km · Peso total 128.0 kg» y, a la
   derecha, el importe o **«Sin calcular todavía»**. Debajo:
   - Con precio: «El costo lo puso el repartidor desde Entrega. La distancia es
     del almacén al cliente.»
   - Sin precio, si el vendedor marcó domicilio: «El costo lo pone el repartidor desde
     Entrega; hasta entonces este pedido no tiene precio de domicilio.»
   - Sin precio, si **no** lo marcó («Sin calcular todavía» sale en gris): «El vendedor
     no marcó domicilio y Entrega sólo cotiza los marcados: este pedido no tiene precio
     de domicilio, y no le hace falta para ir a una ruta.»
5. **«Productos (6)»** — una línea por renglón, **con los empaques primero** (el blíster,
   la caja, la paca: lo que se carga y se transporta) y las unidades detrás: «MALTA
   GUAJIRA CAJA 24U · 10 empaques · 240 unidades · 88.5 kg». Si el renglón no trae
   peso, pone «sin peso». Las unidades solo salen cuando se pueden afirmar: si la
   cifra que manda Ventra queda por debajo de los empaques («SERVILLETA PROSITO PACA
   24P · 7 empaques · 4») no son unidades de nada y la línea solo dice los empaques.
6. **«Ruta»** — sólo si va en una: el código, el camión y la fecha de entrega.

---

## «Ubicar la entrega» — el punto de entrega puesto a mano

**El caso (issue 19 de Amado).** El cliente pide entregar en **otro sitio** y quien
factura lo apunta en el ticket. Esa dirección no coincide con la geolocalización del
cliente, que es la única que manda PEDIDO. El logístico, al armar la ruta, le pone **a
mano** el punto de entrega (latitud, longitud y dirección) a esa factura. Ese punto
**manda sobre el del cliente** y **no se pierde** cuando el cliente se vuelve a
actualizar. Nada de esto se hace en PEDIDO: se hace aquí.

Se abre desde **tres sitios**, con **el mismo cajón**: la ficha de la factura (sección
«Entrega»), la tarjeta de la parada en el detalle de una ruta («Ver paradas») y cada fila
del paso «Facturas» del asistente de rutas (botón pequeño con el tooltip «Ubicar la
entrega»).

**El cajón «Ubicar la entrega»** tiene el folio y el cliente de subtítulo y estas cosas:

- **«Dirección»**, con su botón **«Buscar»**: la dirección de la entrega, y buscarla en el
  mapa (hacen falta 4 letras; **necesita conexión**).
- **«Coordenadas»**: `19.83, -75.82`. **Escribirlas a mano funciona siempre**, también sin
  señal. Es la caja por la que pasa el punto: lo que se guarda es lo que pone ahí.
- **El mapa**: pulsar donde es la entrega pone el punto. También funciona sin señal.
- **«Guardar punto»**, que no se enciende hasta que algo cambie, y **«Cancelar»**.
- **«Volver al punto del cliente»**, sólo si la factura ya tiene un punto a mano: pregunta
  antes («Sí, volver al punto del cliente» / «No, dejar el punto a mano»).

**Cuándo se ofrece.** Sólo si la factura **no está entregada** y su **ruta no está
completada**. Si no se puede, no hay botón y la ficha dice por qué:

- «La factura ya está entregada: no se le puede cambiar el punto»
- «La ruta ya está completada: no se le puede cambiar el punto a sus paradas»

**Qué cambia al guardar:**

- La ficha y la tarjeta de la parada llevan **«Punto puesto a mano»**.
- **En el mapa de la ruta el número de la parada sale en rojo** (ver [Rutas](rutas.md)).
- Se vuelven a medir los **km de la parada** y el **total de la ruta**, si va en una ruta
  que no está completada, y la **distancia del domicilio**. **El orden de las paradas no
  se toca.**
- **En la web** se guarda al instante en el servidor; si dice que no, el motivo sale tal
  cual en el cajón y no se guarda nada. **En la APK y el escritorio** se guarda en el
  aparato (con los km de la parada y de la ruta ya recalculados) y **sube cuando hay
  señal**; la distancia del domicilio la pone el servidor al subir. Si al subir dice que
  no, el cambio queda en la bandeja con su motivo.

Los «no» del servidor, letra por letra: «Se espera { lat, lng }»; «lat y lng tienen que
ser un punto del planeta» (fuera de rango, o el (0,0), que es el golfo de Guinea);
«La factura ya está entregada: no se le puede cambiar el punto»; «La ruta ya está
completada: no se le puede cambiar el punto a sus paradas»; «La factura no tiene un punto
puesto a mano» (al volver al del cliente) y «No encontrado».

**Una limitación:** una entrega que PEDIDO manda **sin coordenadas** no llega a esta
aplicación por esa vía, así que no se puede abrir; esto sirve para **cambiar** el punto de una que ya
tiene uno.

---

## «Mandar a una zona»

Con facturas marcadas, el botón **«Mandar a una zona»** abre el cajón **«Mandar a
una zona del tablero»**, con **«7 factura(s) marcadas»** arriba y este texto:

> «Se colocan en el orden en que están marcados, y el gesto es el mismo que
> arrastrarlos: se guarda aquí y sube cuando haya señal.»

Debajo, las zonas de la sucursal, cada una con «12 factura(s) puestas». Si no hay
ninguna:

> «Este tablero todavía no tiene ninguna zona. Crea la primera con el nombre del
> barrio o del distrito.»

También hay **«Crear una zona nueva»**, que pide el «Nombre de la zona nueva».

Al pie: **«Cancelar»** y **«Mandar a la zona»**, que está apagado hasta que elijas
una.

### Qué te dice al terminar

> «5 factura(s) en «Centro»»

Y si alguno se quedó, en ámbar:

> «No se pudieron mandar 2, y siguen marcados:»
> `PTB25-261005-1480 · Ana: Esa factura ya está en una ruta`
> `PTB25-261005-1502 · Luis: No se puede asociar al tablero: primero cotiza el domicilio del pedido.`

Cada factura sale por su **conduce**, que es su número de operación.

Si alguna se quedó por el domicilio sin cobrar, el cajón añade debajo del aviso una
línea de ayuda:

> «Mira la marca de Factura en Facturas: ahí se ve si el domicilio está cobrado.»

Sólo sale con ese motivo: con los demás (archivado, otra sucursal…) la marca de «Factura»
no tiene la respuesta.

Los motivos posibles: «No está en este aparato», «Es de otra sucursal», «Sin
coordenadas de entrega», «Archivado en PEDIDO», «Sin cotejar», «Sin factura», y los
mismos «no» que da el servidor al colocar una tarjeta:

- «Esa factura ya se entregó»
- «Esa factura ya está en una ruta»
- «No se puede asociar al tablero: la factura no tiene un cobro de domicilio
  registrado.»
- «No se puede asociar al tablero: primero cotiza el domicilio del pedido.»

**A una zona sólo se coloca lo que tiene el domicilio cobrado, y cotizado si el vendedor
lo marcó.** Es la misma regla que para armar una ruta: ver [Tablero](tablero.md).

**Las que sí fueron pierden la marca; las que no, se quedan marcadas** para poder
seguir trabajando con ellos.

---

## Estados vacíos y paginación

- **Cargando**: «Cargando...»
- **Vacío sin filtros**: «Aún no hay facturas de esta sucursal.»
- **Vacío con filtros**: «Ninguna factura cuadra con estos filtros.» y el botón
  **«Quitar todos los filtros»**, que quita **también** el acotado del arranque.
- **En la APK, si esta parte no bajó**: «Esta pantalla no se ha descargado todavía.
  Con conexión baja sola.»
- **En la web, si no llegó**: «No se pudieron traer las facturas. La página cargó,
  así que conexión hay: el que no contesta es el servidor. Prueba otra vez y, si
  sigue igual, avisa a la oficina.»

**50 facturas por página.** El pie dice «Mostrando 51–100 de 246», con los botones
««», «‹», los números, «›» y «»».

---

## Lo que Facturas NO hace

- **No se dan de alta facturas.** Vienen de Ventra (y, las que traen pedido, quedan enlazadas con él por folio).
- **No se edita nada de una factura**: ni el cliente, ni el peso, ni el precio del
  domicilio. **La única excepción es el punto de entrega** (y su dirección), que el
  logístico puede poner a mano con «Ubicar la entrega».
- **No se pone el precio del domicilio aquí.** Lo pone el repartidor desde
  Entrega.
- **No se enseña el precio interno de la factura.** La columna «Precio» es lo que
  cobró Entrega por el domicilio.
- **No hay filtro de sucursal**: la manda el selector de arriba.
