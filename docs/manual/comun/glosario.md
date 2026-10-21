# Glosario

Las palabras de la casa, ordenadas alfabéticamente.

**Almacén de origen** — el sitio desde el que arranca el camión y desde el que se
mide la distancia hasta cada cliente. De él sale lo que se le cobra al cliente por
el domicilio.

**Apunte** — cada cosa que hiciste y que todavía tiene que llegar al servidor:
mover una tarjeta, armar una ruta, marcar una entrega. La franja de arriba los
cuenta: «2 sin subir».

**Aparato** — el teléfono o el ordenador donde está instalada la aplicación. Cada
aparato pertenece a **una sola sucursal**, y eso se pregunta una vez.

**Cerrar la ruta / completar la ruta** — dar la ruta por terminada. Al hacerlo se
pregunta parada por parada cómo quedó. La ruta pasa al Historial y el camión queda
libre.

**Coleccion / colección** — cada grupo de datos que baja al aparato: Facturas,
Líneas de factura, Rutas, Clientes, Productos, Vehículos, Sucursales, Almacenes,
Ajustes.

**Cola** — lo que está hecho en el aparato y aún no ha subido. Sólo existe en la
APK y en el escritorio.

**Cotizar** — poner precio al domicilio de una factura. Ver «sin cotizar».

**Empaques** — cuántos bultos hay que sacar del almacén de un producto. Es la
columna del pre-despacho que se usa para cargar.

**Entrega** — la aplicación de la casa de donde sale la fórmula del costo del
domicilio y la tasa de cambio.

**Espejo** — la copia de las facturas (y de los pedidos de PEDIDO a los que van
enlazadas) que esta aplicación trae y mantiene al día. Por eso las facturas no se dan
de alta aquí.

**Factura** — lo que se reparte. Es la factura de Ventra con entrega a domicilio, y es
la fila de la pantalla «Facturas» (Jose, 21/10/2026: «ya no son pedidos, son
facturas»). El pedido de PEDIDO es un extra, enlazado a ella por el folio.

**Factura que cuadra** — que lo facturado coincide con lo pedido. Si no cuadra
(«Cambió en la factura»), la factura sube igual a un camión, pero con lo facturado.

**Folio** — el número del pedido de PEDIDO, tipo `X-2992`. Es lo que enlaza una factura
con su pedido (columna «Pedido»). **El sufijo es nuestro**:
`X-2992` y `X-2992-2` son dos pedidos distintos, no el mismo repetido.

**Franja de estado** — la tira de arriba, en todas las pantallas, que dice de qué
hora son los datos y cuántos apuntes quedan sin subir. **No existe en la web.**

**Historial** — la pestaña de Rutas con las rutas **completadas**.

**Línea / renglón de factura** — un producto dentro de una factura, con su cantidad.
Una factura tiene varios renglones.

**PEDIDO** — la aplicación donde se hacen los pedidos, los clientes y los
vendedores de las ocho sucursales. Esta aplicación los lee; no los crea. Un pedido de
PEDIDO se ve aquí como el **extra** de una factura (columna «Pedido»), no como la fila.

**Parada** — una factura dentro de una ruta, con su sitio en el orden de visita.

**Peso de las facturas** — el peso que trae cada factura entera. Siempre se sabe.

**Peso de los productos** — la suma renglón a renglón de la columna `kg`. Puede
salir con `≥` si falta el peso de algún renglón. **No es el mismo número que el
anterior.**

**Post-despacho** — el papel del final: qué salió, qué se entregó y qué vuelve.

**Pre-despacho** — el papel del principio: qué hay que sacar del almacén, por
producto, con sus empaques y su peso.

**Punto puesto a mano** — el punto de entrega que el logístico le pone a una factura
cuando el cliente pidió entregar en otro sitio (la dirección del ticket no coincide
con la geolocalización del cliente). Manda sobre el del cliente y no se pierde cuando
el cliente se actualiza. Se pone en «Ubicar la entrega»; la parada sale en el mapa con
su **número en rojo**, y se puede volver al punto del cliente.

**Renglón sin peso** — una línea de factura cuyo peso no consta. Son las que hacen
que el peso del pre-despacho salga con `≥`.

**Repartible** — una factura que hoy puede subir a un camión: no está en otra ruta,
tiene coordenadas de entrega, está facturado (cuadre o no), la factura cobra el
domicilio y, si el vendedor lo marcó, Entrega ya lo cotizó.

**Ruta en curso** — la que salió y va en el camión ahora mismo.

**Ruta planificada** — la que está armada pero **no ha salido**.

**«sin cotizar»** — este domicilio **todavía no tiene precio**. No es cero, no es
gratis: es que no se sabe.

**Sincronizador** — el servicio que sube lo hecho sin conexión y deja el aparato
al día. Sólo lo usan la APK y el escritorio.

**Sucursal** — una de las ocho: `CAM` Camagüey, `GR` Granma, `GTO` Guantánamo,
`HAB` La Habana, `HOL` Holguín, `SS` Sancti Spíritus, `STG` Santiago, `TUN` Las
Tunas.

**Tarjeta** — cada factura en el Tablero, la cosa que se arrastra a una zona.

**Tasa de cambio** — lo que pasa los importes de USD a CUP. **Es por sucursal** y
se mantiene en Accesos, no aquí.

**Traer el día** — cargar en el aparato todo lo del día para trabajarlo sin señal.
Sólo en la APK y en el escritorio.

**Entregar el día** — subir al servidor lo que se hizo sin señal. Sólo en la APK y
en el escritorio.

**Ventra / AxisPOS** — el sistema de donde salen los catálogos y los pesos de los
productos.

**Zona / columna** — cada grupo del Tablero: «Centro», «Vista Alegre»… Se le pone
camión previsto y de ella sale una ruta.
