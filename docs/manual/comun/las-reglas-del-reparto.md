# Las reglas del reparto

Éstas son las reglas que la aplicación aplica sola, sin preguntar. Conocerlas
ahorra la mitad de los «no me deja».

---

## 1. En un camión sólo sube lo facturado y que cuadre

Un pedido que no está facturado **no entra en una ruta**. No es un capricho de la
aplicación: lo que se carga tiene que ser lo que se cobró.

Un pedido puede llevar una de estas marcas. Las cuatro primeras **impiden**
repartirlo hoy; la quinta no:

| Marca | Qué quiere decir | ¿Se puede repartir? |
|---|---|---|
| **«Archivado en PEDIDO»** | Lo dieron de baja en PEDIDO después de colocarlo | **No** |
| **«Ya va en otra ruta»** | Se lo llevó otra ruta, quizá desde otro aparato | **No** |
| **«Sin cotejar»** | No se sabe si la factura cuadra. **No es «cuadra»: es «no se sabe»** | **No** |
| **«Sin factura»** | No hay nada que llevar | **No** |
| **«Cambió en la factura»** | Se facturó distinto de como se pidió | **Sí**, pero el peso ya no es el que era |

Un pedido puede llevar **varias marcas a la vez**: archivado y sin facturar es las
dos cosas.

**Lo que no se puede repartir no se esconde: se marca.** Sigue viéndose en la
pantalla, con el motivo escrito. Así nadie pierde de vista un pedido sin saber por
qué desapareció.

---

## 2. Sin camión no se arma una ruta

Los tres caminos que crean una ruta lo exigen: el Tablero, el asistente «Nueva
Ruta» y el servidor.

Desde el Tablero, el aviso es literalmente éste:

> **La zona «Centro» no tiene camión previsto, y sin camión no se arma su ruta**
>
> - Elige el camión en «Camión previsto», en las opciones de la zona, y vuelve a
>   armar.
> - Sin camión no hay capacidad contra la que medir la carga ni costo por km con
>   el que cotizar el domicilio: la ruta saldría con su peso y su importe sin nada
>   con que contrastarlos.

Desde el asistente, el servidor contesta: **«Se requiere un vehículo para crear la
ruta»**.

Por qué se bloquea aquí y en cambio otros avisos dejan seguir: **este hueco se
tapa con un gesto, en la misma pantalla donde sale el "no"**. Dos toques en
«Camión previsto» y ya está. Los avisos que no bloquean son los que habría que ir
a arreglar cliente a cliente en otro sitio.

Y el motivo de fondo: sin camión, la ruta sale con su `516.5 kg` y su `$2.99` y
**no hay nada contra lo que contrastar esos números**. Un número creíble que no
significa nada es el fallo que más caro sale aquí.

---

## 3. Una ruta se arma con pedidos que YA existen

**No se teclean paradas.** No se puede escribir un cliente y una dirección a mano
y meterlo en una ruta. Una ruta se arma eligiendo pedidos que ya están en el
sistema, traídos de PEDIDO.

Tampoco se dan de alta pedidos ni clientes en esta aplicación. Vienen de PEDIDO.

---

## 4. Sin coordenadas de entrega no hay parada

Un pedido cuyo cliente no tiene coordenadas de entrega **no puede ir en una
ruta**: no hay a dónde llevarlo ni desde dónde medir.

Ese pedido tampoco entra en el peso pendiente del Panel.

---

## 5. Los pedidos del mismo cliente NO se juntan

`X-2992` y `X-2992-2` son **dos pedidos**, con sus renglones, su peso y su costo de
domicilio cada uno. La aplicación **no** los funde en una tarjeta.

Lo único que hace es **decirte** que hay más de uno de ese cliente, para que los
metas en la misma zona a propósito y no por casualidad.

Juntarlos sería repetir un error que ya costó dinero: dos facturas y un solo bulto
cargado.

---

## 6. Armar una ruta no ocupa el camión

Se planifica, no se despacha. **El camión que está repartiendo ahora mismo se
puede elegir para la ruta de mañana**, y hay que poder: armar la ruta de mañana es
justo lo que se hace mientras el camión está fuera.

El camión pasa a estar ocupado cuando la ruta **se inicia**, y se libera cuando se
**completa**.

---

## 7. El orden de las paradas lo pone la aplicación, pero manda el tuyo

Cuando una ruta se arma desde el Tablero, **el orden que va es el que dejó el
logístico** en la columna. La aplicación no lo reordena.

Cuando se arma sin ese orden, la aplicación ordena por **la parada más cercana
cada vez**, empezando desde el almacén de origen. No mira atrás ni busca el mejor
recorrido posible: es una primera propuesta, no una optimización.

Los kilómetros son **en línea recta sobre el mapa**, no por carretera. El camión
hará más.

---

## 8. El código de la ruta

Una ruta creada con conexión se llama así: `RT-20260928-004`.

- `RT-` fijo,
- la fecha del día (`20260928` = 28 de septiembre de 2026),
- y el número de orden de la ruta dentro de ese día (`004` = la cuarta).

Sin conexión, en la APK y en el escritorio, la ruta nace con un nombre provisional
como `local-3df93810` y **se convierte en su `RT-…` en cuanto sube**.

---

## 9. La tasa de cambio es por sucursal, y sin ella no se convierte nada

Si la sucursal no tiene tasa, los importes se ven **sólo en dólares**. No se usa la
tasa de otra sucursal ni un número por defecto.

Ya pasó una vez en otra aplicación de la casa: Granma enseñaba los 685 de La
Habana como si fueran suyos. Un importe así se lee bien y está mal, que es lo peor
que le puede pasar a un número que alguien va a cobrar.

---

## 10. Lo que el servidor rechaza se dice, con su motivo

Nada se descarta en silencio. Si mueves una tarjeta y el servidor dice que no, te
lo dice con el motivo de verdad —«Ese pedido ya va en otra ruta»— y no con un «no
se pudo guardar».

Y un apunte rechazado **no se reintenta solo y no se borra**: se queda a la vista
con su motivo hasta que una persona decida.
