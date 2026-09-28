# Qué significa cada número

Esta página es la que hay que abrir cuando dos pantallas parecen decir cosas
distintas. Casi siempre no se contradicen: **están contando cosas distintas**.

---

## La regla que explica la mitad de las dudas: la sucursal de arriba

**Todas las pantallas enseñan lo de la sucursal que tengas puesta arriba**, en la
barra superior. No lo de toda la empresa.

Si estás en Santiago y el pedido es de Holguín, ese pedido **no sale**. Ni en
Pedidos, ni en el Panel, ni en el Tablero, ni en Reportes. No es que falte: es que
no es de la sucursal que estás mirando.

Antes de dar nada por perdido: **mira arriba qué sucursal pone**.

Sólo `DESARROLLADOR` y `SUPER ADMIN` pueden cambiar de sucursal y ver las ocho.
Los otros cinco roles tienen la suya fija. Ver
[Roles y sucursales](roles-y-sucursales.md).

---

## «Entregados hoy» frente al Historial de Rutas

Esta es la pregunta que más se repite:

> «me dice que entregado uno y en historial me sale vacío»

**No es un fallo. Son dos cuentas distintas.**

| | Qué cuenta | Cuándo sube |
|---|---|---|
| **«Entregados hoy»** (tarjeta del Panel) | **PEDIDOS** entregados | En cuanto marcas una parada como entregada |
| **Historial** (pestaña de Rutas) | **RUTAS** cerradas | Sólo cuando la ruta entera se da por completada |

Un camión que está en la calle con **una parada ya hecha** sale en el primero y
no sale en el segundo. Es lo normal a media mañana.

Dos detalles más de «Entregados hoy»:

- Cuenta desde las **00:00 de hoy según el reloj del aparato**, no según el
  servidor. Si el reloj del teléfono está mal, este número está mal. Ver
  [Cuando algo sale mal](cuando-algo-sale-mal.md).
- Cuenta **pedidos**, no paradas ni bultos.

Y del Historial: una ruta aparece ahí cuando está **completada**. Una ruta
cancelada no está en el Historial; tampoco en «En curso».

---

## Las tres pestañas de Rutas, y qué mide cada número

- **«Planificadas»** — la ruta está armada pero **no ha salido**. Todo lo que no
  está ni completado ni en curso cae aquí.
- **«En curso»** — la ruta salió. Es la que va en el camión ahora mismo.
- **«Historial»** — completadas.

El número que sale entre paréntesis en cada pestaña cuenta **rutas**, no pedidos
ni paradas.

Un aviso de la casa: la primera pestaña se llamó «Activas» y se cambió a
«Planificadas» a propósito, porque quien leía «Activas (1)» se creía que tenía un
camión en la calle, y no lo tenía.

---

## «Rutas en marcha» del Panel

Cuenta sólo las rutas **en curso**, las que salieron. Las planificadas **no**
entran aquí: están en Rutas, en su pestaña, con su propio número.

Si el Panel dice «Rutas en marcha: 1» y en Rutas ves seis, es que hay una en la
calle y cinco esperando en la oficina.

---

## `≥ 17318.8 kg (462 renglones sin peso)` — el peso del pre-despacho

Esto sale tal cual en el pre-despacho y no es un error. Se lee así:

> «El camión pesa **por lo menos** 17.318,8 kg. Podría pesar más, porque hay
> **462 renglones a los que no les conocemos el peso**.»

Desglosado:

- **El `≥` (mayor o igual)** sale **sólo cuando falta el peso de algún renglón**.
  Si el peso se sabe entero, el `≥` no aparece y el número va limpio:
  `17318.8 kg`.
- **Un «renglón sin peso»** es una línea de un pedido —un producto pedido por un
  cliente— cuyo peso no consta. Suele ser un producto que todavía no tiene peso
  puesto en el catálogo.
- **Los renglones que faltan no suman cero: se dejan fuera de la suma**, y por eso
  la cifra es un mínimo y no un total.

Un ejemplo real del pre-despacho de Santiago:

```
15 producto(s) · 10197 empaques · ≥ 17318.8 kg (462 renglones sin peso)
```

Quince productos distintos, 10.197 empaques que sacar del almacén, y el camión
pesa **al menos** 17.318,8 kg. Con eso se puede cargar; lo que no se puede es
firmar que ése es el peso exacto.

Se dice el número en vez de dejar una raya porque **con una raya no se carga un
camión**. Y se le pone el `≥` porque un total corto con pinta de completo hace que
se cargue de menos y no se descubre hasta que el camión ya se fue.

### Y ojo: en el pre-despacho hay DOS pesos que no son el mismo

- **«Peso de los productos»** — se suma renglón a renglón, de la columna `kg`. Es
  el que puede llevar `≥`.
- **«Peso de los pedidos»** — es el peso que trae cada pedido entero. Éste
  siempre se sabe.

La propia hoja lo dice debajo:

> «No son el mismo número: el de arriba suma renglón a renglón, y el de abajo es
> el peso que trae cada pedido entero.»

No los restes a ojo: no cuadra y no tiene por qué cuadrar.

---

## «sin cotizar» en vez de `$0.00`

Donde iría un importe, a veces pone **«sin cotizar»**. No es un cero: es que
**ese domicilio todavía no tiene precio**.

La diferencia importa porque es dinero: un `$0.00` se lee como «este reparto salió
gratis», y eso es mentira. «sin cotizar» dice la verdad, que es que no se sabe.

Pasó de verdad: la ruta `RT-20260921-007` enseñaba `$0.00` con dos paradas sin
cotizar, el camión a 1,50 USD por kilómetro y 10,4 km de recorrido. Ninguna
pantalla lo desmentía.

### Y en el importe de una ruta entera

Si **alguna** parada está sin cotizar, la ruta **no enseña un total**. Enseña una
raya con la cuenta al lado:

```
— (2 de 5 sin cotizar)
```

Y debajo, qué hacer:

> «Faltan cotizar 2 paradas de 5: sin ellas no hay importe de la ruta.»

Con una sola parada sin cotizar la frase cambia al singular: «Falta cotizar 1
parada de 5: sin ella no hay importe de la ruta.»

**Un total a medias es peor que ninguno**: parece completo y se queda corto.

### Por qué un domicilio se queda sin cotizar

Casi siempre es una de estas tres, y ninguna se arregla desde esta aplicación:

1. **La sucursal no tiene puesto su punto de partida.** Sin él no hay desde dónde
   medir la distancia.
2. **El cliente no tiene coordenadas de entrega.**
3. **La sucursal no tiene tasa de cambio.** Sin tasa no se convierte nada.

El Panel las enseña una a una en su paso a paso, con qué se rompe sin cada una.

---

## La tasa de cambio, y por qué a veces sólo ves dólares

**La tasa es por sucursal.** Si la sucursal que estás mirando no tiene tasa, los
importes se ven **sólo en USD** y no se convierten a CUP.

No se cae a la tasa de otra sucursal ni a un número por defecto, y es a propósito:
convertir sin tasa es inventarse un número, y un número inventado acaba cobrado.

La tasa **no se pone aquí**. La mantiene Accesos, que la trae de Entrega. Se
arregla allí y baja sola con el día.

---

## Los dos kilometrajes de una ruta, que tampoco son el mismo

- **Los kilómetros de la ruta** son los del camión: del origen a la primera
  parada, de ésa a la siguiente, y **más la vuelta al origen**.
- **Los kilómetros de un pedido** son la distancia **directa** desde el almacén de
  salida hasta ese cliente, en línea recta. No es el tramo del recorrido.

El segundo es el que se usa para cobrar el domicilio. Por eso sumar los
kilómetros de todos los pedidos **no da** los kilómetros de la ruta.

Las dos medidas son en línea recta sobre el mapa, no por carretera. La distancia
real que hace el camión será mayor.

---

## El peso pendiente del Panel

Suma el peso de los pedidos **repartibles** que todavía no están en ninguna ruta.
Un pedido es repartible cuando cumple las tres a la vez:

1. no está ya metido en otra ruta,
2. tiene coordenadas de entrega, y
3. está facturado y cuadra (o cambió en la factura).

Un pedido sin coordenadas **no** entra en este número aunque esté sin repartir:
no se puede llevar a ningún sitio.

---

## Vehículos «en ruta»

El contador de vehículos en ruta cuenta los camiones que van en una ruta **en
curso**. Armar una ruta **no ocupa el camión**: se planifica, no se despacha.

Esto es a propósito, y se puede comprobar: el camión que está repartiendo ahora
mismo **sí** se puede elegir para armar la ruta de mañana. El camión se ocupa
cuando la ruta pasa a en curso y se libera al completarla.

---

## Dos números que hoy NO son de fiar

Están detectados y en arreglo. Mientras tanto, no te apoyes en ellos:

1. **El peso del pre-despacho no cambia al cambiar de sucursal.** Si cambias
   arriba de sucursal, ese peso puede seguir siendo el de la anterior.
2. **Una ruta con dos pedidos del mismo cliente cuenta el peso de uno solo** en su
   cabecera. El peso real de esa ruta es mayor que el que enseña.
