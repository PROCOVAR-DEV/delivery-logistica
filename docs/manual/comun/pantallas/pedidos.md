# Pedidos

**Para qué sirve:** es el catálogo de todo lo que hay por repartir y lo que ya se
repartió. De aquí sale el pre-despacho y de aquí se mandan pedidos al Tablero.

Debajo del título pone: «Todos los pedidos acumulados de todas las rutas».

**Recuerda:** la lista es **de la sucursal que tengas puesta arriba**. Aquí no hay
filtro de sucursal.

---

## La franja azul del arranque

Al entrar, la pantalla **viene acotada a propósito** y lo dice:

> «Enseñando sólo lo que puede subir a un camión: lo que tiene factura —cuadre o
> no— y sin archivar. Lo que cambió también sube: se carga con las líneas de la
> factura, no con las del pedido.»

Debajo, el botón **«Ver todos los pedidos»**, que quita ese acotado.

Si no encuentras un pedido, esto es lo primero que hay que probar.

---

## Los filtros

| Filtro | Por defecto | Qué hace |
|---|---|---|
| **Buscar** | vacío | Busca en cliente, folio, dirección, municipio, vendedor y productos. Busca solo, sin Intro |
| **«Estado de reparto en delivery»** | «Cualquier reparto» | «Sin entregar», «En despacho», «En ruta», «Entregado», «Devuelto o cancelado» |
| **«Municipio del cliente»** | «Todos los municipios» | Cada municipio con cuántos pedidos tiene |
| **«Precio del domicilio»** | «Cualquier precio» | «Con precio puesto» o «Sin cotizar» |
| **«Vendedor del pedido»** | «Todos los vendedores» | Cada vendedor con cuántos pedidos |
| **«Cómo se ordena esta página»** | «Más recientes» | «Más antiguos», «Precio: mayor a menor», «Precio: menor a mayor», «Distancia: más larga», «Peso: mayor» |
| **«Desde (fecha del pedido)»** / **«Hasta (fecha del pedido)»** | vacías | Con «Desde» puesto aparece **«sólo ese día»**, que copia la fecha en las dos |

**Cuidado con el orden:** «Cómo se ordena esta página» ordena **sólo la página que
estás viendo**, no los 246 pedidos enteros.

Cualquier cambio de filtro te devuelve a la página 1.

Si abres un enlace con filtros que no se entienden, sale un aviso en ámbar:

> «Este enlace traía filtros que no se pudieron aplicar: desde=31-12-2026,
> reparto=volando.»
> «La lista que estás viendo NO está acotada por ellos.»

---

## El conteo de arriba

> «246 pedidos · del 1/9/2026 al 28/9/2026, del más nuevo al más viejo»

Cambia según las fechas que tengas puestas: «· del 28/9/2026», «· desde el
1/9/2026», «· hasta el 28/9/2026». Y **siempre** acaba diciendo el orden.

---

## Las columnas de la tabla

| Columna | Qué es |
|---|---|
| (casilla) | Marca el pedido. La de la cabecera dice «Elegir todos los de esta página» |
| **«Fecha»** | La del pedido. Si le falta, sale la del espejo con un `≈` delante: «≈ 12/9/2026» |
| **«Sucursal»** | Sólo sale si no tienes una sucursal elegida arriba |
| **«Pedido»** | El estado **en PEDIDO** |
| **«Cliente»** | El nombre y debajo el folio |
| **«Ruta»** | El código de ruta, o «—» |
| **«Vehículo»** | Un punto si tiene, «—» si no |
| **«Artículos»** | El primer producto y cuántos más («+3»). Todo en el tooltip |
| **«Dirección»** | La de entrega |
| **«Peso»** | «128.0 kg» o «—» |
| **«Precio»** | «$12.50» o **«sin cotizar»** en gris |
| **«Factura»** | Ver abajo |
| **«Entrega»** | El estado de reparto |

En pantalla estrecha no hay tabla: cada pedido es una tarjeta, y la cabecera dice
«Elegir los 50 de esta página».

---

## Los tres estados de un pedido

Son **tres cosas distintas** en tres columnas distintas. No los confundas.

### Columna «Pedido» — cómo va en PEDIDO

| Etiqueta | Qué significa |
|---|---|
| **«Completada»** (verde) | La orden está cerrada en PEDIDO |
| **«En proceso»** (ámbar) | Ni cerrada ni vencida |
| **«Expirada»** (rojo) | No está completada y la fecha comprometida ya pasó |

Si el pedido está archivado, esa insignia lleva el aviso «Archivado en PEDIDO».

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
convierte en entregado un pedido que volvió en el camión.

### Columna «Factura»

| Qué se ve | Qué significa |
|---|---|
| El número en verde | «Cuadra con lo pedido: se puede repartir tal cual.» |
| El número con un `!` en ámbar | «Se facturó algo distinto de lo pedido. No puede ir en una ruta hasta que se corrija.» |
| «sin facturar» en gris | No hay factura |
| «sin cotejar» en gris | «El cotejo contra Ventra no ha pasado por este pedido todavía.» |

---

## El pre-despacho

Hay **dos**, y los dos abren el mismo cajón.

### El de lo elegido

Al marcar pedidos aparece una franja azul: **«7 pedido(s) elegidos»**, con tres
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
productos»** y **«Peso de los pedidos»**, con la frase que los separa:

> «No son el mismo número: el de arriba suma renglón a renglón, y el de abajo es
> el peso que trae cada pedido entero.»

Y el botón **«Ver e imprimir»**, que abre la **«Hoja de pre-despacho»** para
imprimir: «264 pedido(s) · 24891.0 kg».

### El peso, con todo detalle

Ver [Qué significa cada número](../que-significa-cada-numero.md). En corto:

| Caso | Qué se escribe |
|---|---|
| No se sabe el peso de **ninguna** línea | «sin peso en los pedidos» |
| Se sabe el de **todas** | «26320.0 kg» |
| Se sabe el de **unas sí y otras no** | «≥ 26320.0 kg (21 renglones sin peso)» |

Con un solo renglón faltando, el texto va en singular: «≥ 1200.0 kg (1 renglón sin
peso)».

**Dentro de la tabla, en la celda, el texto es más corto**: «≥ 26320.0», sin el
paréntesis. El rótulo de la columna ya dice «kg».

Las unidades siguen la misma regla: «≥ 600 (3 renglones sin unidades)».

**Un renglón sin peso** es una línea de pedido cuyo peso no consta: ni lo manda
Ventra en ese renglón ni se puede sacar del catálogo. De los 129 productos de
Ventra sólo 57 traen peso, así que esto es lo normal, no una avería.

---

## El detalle de un pedido

Se abre tocando la fila. **Es sólo lectura: aquí no se edita nada.**

Lleva, en este orden:

1. **«Entrega»** — dirección, coordenadas y teléfono del cliente.
2. **«Recorrido»** — «Del almacén (ALMACÉN CENTRAL) al cliente.» o «Sin
   coordenadas GPS para esta ruta».
3. **La banda de la factura**:
   - Verde: «Cuadra con la factura F-2992 de Ventra: se puede repartir tal cual.»
   - Ámbar: «Se facturó algo distinto de lo pedido (factura F-2992). Lo que va en
     el camión es lo facturado.»
   - Gris: «Todavía no aparece facturado en Ventra.»
   - Y si la factura cobró domicilio: «La factura cobró 15.00 USD de domicilio.»
4. **El bloque del domicilio** — «Distancia 4.35 km · Peso total 128.0 kg» y, a la
   derecha, el importe o **«Sin calcular todavía»**. Debajo:
   - Con precio: «El costo lo puso el repartidor desde Entrega. La distancia es
     del almacén al cliente.»
   - Sin precio: «El costo lo pone el repartidor desde Entrega; hasta entonces este
     pedido no tiene precio de domicilio.»
5. **«Productos (6)»** — una línea por renglón: «MALTA GUAJIRA CAJA 24U · 240
   unidades · ×10 empaques · 88.5 kg». Si el renglón no trae peso, pone «sin
   peso».
6. **«Ruta»** — sólo si va en una: el código, el camión y la fecha de entrega.

---

## «Mandar a una zona»

Con pedidos marcados, el botón **«Mandar a una zona»** abre el cajón **«Mandar a
una zona del tablero»**, con **«7 pedido(s) marcados»** arriba y este texto:

> «Se colocan en el orden en que están marcados, y el gesto es el mismo que
> arrastrarlos: se guarda aquí y sube cuando haya señal.»

Debajo, las zonas de la sucursal, cada una con «12 pedido(s) puestos». Si no hay
ninguna:

> «Este tablero todavía no tiene ninguna zona. Crea la primera con el nombre del
> barrio o del distrito.»

También hay **«Crear una zona nueva»**, que pide el «Nombre de la zona nueva».

Al pie: **«Cancelar»** y **«Mandar a la zona»**, que está apagado hasta que elijas
una.

### Qué te dice al terminar

> «5 pedido(s) en «Centro»»

Y si alguno se quedó, en ámbar:

> «No se pudieron mandar 2, y siguen marcados:»
> `F-2992 · Ana: Ya va en otra ruta`
> `X-3010 · Luis: Sin coordenadas de entrega`

Los motivos posibles: «No está en este aparato», «Es de otra sucursal», «Sin
coordenadas de entrega», «Archivado en PEDIDO», «Ya va en otra ruta», «Sin
cotejar», «Sin factura».

**Los que sí fueron pierden la marca; los que no, se quedan marcados** para poder
seguir trabajando con ellos.

---

## Estados vacíos y paginación

- **Cargando**: «Cargando...»
- **Vacío sin filtros**: «Aún no hay pedidos de esta sucursal.»
- **Vacío con filtros**: «Ningún pedido cuadra con estos filtros.» y el botón
  **«Quitar todos los filtros»**, que quita **también** el acotado del arranque.
- **En la APK, si esta parte no bajó**: «Esta pantalla no se ha descargado todavía.
  Con conexión baja sola.»
- **En la web, si no llegó**: «No se pudieron traer los pedidos. La página cargó,
  así que conexión hay: el que no contesta es el servidor. Prueba otra vez y, si
  sigue igual, avisa a la oficina.»

**50 pedidos por página.** El pie dice «Mostrando 51–100 de 246», con los botones
««», «‹», los números, «›» y «»».

---

## Lo que Pedidos NO hace

- **No se dan de alta pedidos.** Vienen de PEDIDO.
- **No se edita nada de un pedido**: ni el cliente, ni la dirección, ni el peso, ni
  el precio del domicilio.
- **No se pone el precio del domicilio aquí.** Lo pone el repartidor desde
  Entrega.
- **No se enseña el precio interno del pedido.** La columna «Precio» es lo que
  cobró Entrega por el domicilio.
- **No hay filtro de sucursal**: la manda el selector de arriba.
