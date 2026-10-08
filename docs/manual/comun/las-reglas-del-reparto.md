# Las reglas del reparto

Éstas son las reglas que la aplicación aplica sola, sin preguntar. Conocerlas
ahorra la mitad de los «no me deja».

---

## 1. En un camión sólo sube lo facturado y que cuadre

Un pedido que no está facturado **no entra en una ruta**. No es un capricho de la
aplicación: lo que se carga tiene que ser lo que se cobró.

Y no basta con que haya factura: tiene que **cuadrar** con ella. Si la factura cambió
respecto a lo pedido, ese pedido tampoco sube hoy.

Un pedido puede llevar una de estas marcas. **Las cinco impiden repartirlo hoy**:

| Marca | Qué quiere decir | ¿Se puede repartir? |
|---|---|---|
| **«Archivado en PEDIDO»** | Lo dieron de baja en PEDIDO después de colocarlo | **No** |
| **«Ya va en otra ruta»** | Se lo llevó otra ruta, quizá desde otro aparato | **No** |
| **«Sin cotejar»** | No se sabe si la factura cuadra. **No es «cuadra»: es «no se sabe»** | **No** |
| **«Sin factura»** | No hay nada que llevar | **No** |
| **«Cambió en la factura»** | Se facturó distinto de como se pidió | **No**: al armar la ruta se descarta y se nombra por su conduce |

Un pedido puede llevar **varias marcas a la vez**: archivado y sin facturar es las
dos cosas.

### Y además: el domicilio tiene que estar cobrado y cotizado

El domicilio ahora es un servicio que se cobra, y dejar entrar cualquier pedido sería
repartir sin cobrar. Por eso, **para entrar en una ruta nueva, y para colocarse en una
zona del Tablero, un pedido tiene que cumplir las tres a la vez**:

1. **Facturado y que cuadre** con la factura (lo de arriba).
2. **Con el domicilio cobrado**: el importe de domicilio de la factura es **mayor que
   cero**.
3. **Cotizado en Entrega**: el repartidor ya le puso el costo del domicilio.

Lo que no cumple **no se ofrece** en la lista de disponibles de Rutas, y si se intenta
meter igualmente **se rechaza diciendo cuál es**, por su conduce. Los mensajes están en
[Cuando algo sale mal](cuando-algo-sale-mal.md#no-me-deja-armar-la-ruta).

**Un pedido sin cotizar o sin cobro de domicilio no está «mal»: está pendiente.** Se
arregla cobrando o cotizando donde toca (Entrega), y entonces aparece solo.

### El conduce

El **conduce** es el **número de operación de la factura**. No es un dato aparte: es el
mismo número con el que ya se busca un pedido. Con él se identifica cada parada de una
ruta, y también cada rechazo («Conduce: PTB25-261005-1480»). Un cobro a domicilio que
sale como conduce se identifica con ese número.

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

Por qué se bloquea aquí: **este hueco se tapa con un gesto, en la misma pantalla donde
sale el "no"**. Dos toques en «Camión previsto» y ya está.

**Y el camión tiene que estar activo.** Un camión «Inactivo» (dado de baja) no se
ofrece para rutas nuevas, y si se intenta asignar a mano el servidor contesta **«El
vehículo está inactivo y no se puede asignar a una ruta»**. **Un camión en el taller sí
se ofrece, con un aviso en ámbar («en el taller»)**: es aviso, no bloqueo. Lo decidió
Jose el 28/09/2026 porque una sucursal con un solo camión olvidado en el taller se
quedaría sin poder armar rutas. Los camiones dados de baja se siguen viendo en filtros e informes, para que las
rutas que ya hicieron sigan diciendo en qué camión fueron.

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

---

## 11. Un camión con rutas no se borra: se pone «Inactivo»

Un camión que tiene rutas —**aunque sean del histórico**— no se puede eliminar: el
servidor lo rechaza para no perder qué camión hizo cada reparto. Para dejar de usarlo
se apaga el interruptor **«Vehículo activo»** de su ficha, y la tarjeta pasa a llevar la
insignia **«Inactivo»**. Sólo se borra de verdad un camión que nunca se usó.

---

## 12. Una ruta se puede deshacer entera o parada a parada, mientras no salga

- **Una parada** se saca de una ruta **planificada** con **«Quitar de ruta»** (con una
  pregunta antes). Una ruta en curso o completada no lo permite.
- **La ruta entera** se borra mientras no esté completada. Una completada es histórico.

En los dos casos el pedido vuelve a la lista de disponibles y, **si la ruta nació del
Tablero, la factura vuelve a su zona**: no se pierde la relación, y se puede volver a
planificar sin recrear nada.
