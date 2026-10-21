# Pliego de pantallas — delivery (para reconstruir en Flutter)

Fuente: `/mnt/datos/Work/procovar/delivery`, Next.js + React + Tailwind, carpeta
`src/app/(dashboard)/`. Este documento describe **qué hace cada pantalla**, no cómo está
escrita. Todos los literales en español entre comillas son **textuales** y hay que
conservarlos tal cual.

## 0. Armazón común (aplica a las 7 pantallas)

- **Sesión.** El layout del dashboard exige token. Si no hay token en memoria ni en
  `localStorage`, pregunta a `GET /api/me`; si devuelve `{user, token}` entra, si no manda
  a `/login`. Mientras comprueba **no pinta nada** (ni pantalla ni salto al login).
- **Autenticación de cada petición:** cabecera `Authorization: Bearer <token>`.
  Sin token todas las API devuelven `401 {"error":"Unauthorized"}`.
- **Alcance por sucursal.** El servidor filtra por la sucursal de la persona. Quien ve
  varias (Super Admin) elige en la barra superior; ese `sucursalId` entra en las claves de
  caché y al cambiarlo se vuelve a pedir todo (no se recarga la página).
- **Moneda.** Los importes se guardan en USD y se muestran en la moneda elegida en la
  barra (USD / CUP). La tasa es **por sucursal** y viene de Accesos; sin tasa se queda en
  USD y no se ofrece elegir.
- **Idioma.** es / en. Las etiquetas de abajo son las del diccionario `es`.
- **Estructura visual:** barra lateral fija de 256 px en ≥1024 px; en móvil la barra sale
  de pantalla y se abre con el botón «Menú» de la barra superior.
- **Regla de la casa (cajón vs modal):** en el resto de las aplicaciones de Procovar se
  usa **modal en escritorio y cajón por debajo de 1024 px**. **Delivery es una excepción
  aprobada (05/09/2026): usa SIEMPRE cajón lateral, también en escritorio.** En Flutter:
  `showModalBottomSheet`/`Drawer` a pantalla completa en móvil y un panel lateral derecho
  a alto completo en escritorio — no un `AlertDialog` centrado.

---

## 1. Panel — `/dashboard`

**Para qué sirve.** Es la pantalla de la mañana: dice cuánto hay pendiente de repartir y
por dónde empezar. **Quién la usa:** quien despacha y el administrador de sucursal; el
Super Admin la ve agregada de todas sus sucursales.

**Título de la barra:** «Panel».

### Tarjetas de arriba (4, en fila; 1 columna en móvil)

| Etiqueta (literal) | Valor | Subtexto (literal) |
|---|---|---|
| `Facturas sin ruta` | `sinRuta` | `<pesoPendiente redondeado> kg por mover` |
| `Rutas en marcha` | `rutasActivas` | — |
| `Entregados hoy` | `entregadosHoy` | — |
| `Vehículos` | `<vehiculosEnRuta> / <totalVehicles>` | `en ruta / total` |

La tarjeta «Facturas sin ruta» se pinta en ámbar cuando el valor es > 0; si es 0, en color
primario. Cifras con 0 por defecto mientras carga.

### Tarjeta «Pendiente por sucursal»

Lista, una fila por sucursal, con tres columnas sin cabecera: nombre de la sucursal ·
`<pesoKg redondeado> kg` · número de facturas. Ordenada de más a menos facturas.
Al pie, separada por una línea: `Domicilios cobrados` + importe formateado en verde.

- **Estado vacío:** `No queda nada sin ruta.`

### Tarjeta «Acciones Rápidas»

Tres enlaces: `Planificar Rutas` → `/routes`; `Ver Reportes` → `/reports`;
`Gestionar Flota` → `/vehicles`.

### Endpoints

- `GET /api/dashboard` — sin parámetros. Devuelve
  `{ totalOrders, sinRuta, rutasActivas, entregadosHoy, totalVehicles, vehiculosEnRuta,
  pesoPendiente, totalDomicilios, porSucursal: [{sucursal, pedidos, pesoKg}] }`.
- **Definición de «repartible»** (la usa `sinRuta`, `pesoPendiente` y `porSucursal`):
  `routeId = null` **y** `endLat` no nulo **y** la regla de entrada a una ruta:
  `facturaEstado ∈ {igual, cambiado}` **y** `facturaDomicilio > 0` **y** (`pedidoCosto` no
  nulo **o** `requiereDomicilio` distinto de `true`) — issue 10 de Amado, 15/10/2026.
- `entregadosHoy` = facturas con `deliveredAt` desde las 00:00 de hoy.
- `totalDomicilios` = suma de `pedidoCosto` (lo cobrado en PEDIDO, no la estimación de
  delivery).

**Acciones:** ninguna de escritura; sólo navegación. **Paginación:** no tiene.

---

## 2. Facturas — `/facturas` (antes «Pedidos», `/orders`)

**Para qué sirve.** El catálogo de facturas de Ventra: buscar una, ver su ficha, y sobre
todo **sumar el pre-despacho** (cuánto sacar del almacén) de lo filtrado o de lo marcado a
mano. **La fila es la factura** (Jose, 21/10/2026: «ya no son pedidos, son facturas»); el
pedido de PEDIDO es un extra, enlazado por folio, y se ve en la columna `Pedido`.
**Quién la usa:** despacho y almacén. **No se crean facturas aquí**: el alta manual se
retiró el 03/09/2026 (`POST /api/orders` ya no existe).

**Ruta y título.** La ruta es **`/facturas`**; `/orders` se queda como redirección a ella
(para los enlaces y favoritos que ya existen). Título de la pantalla y del menú:
«Facturas». Subtítulo: `Todas las facturas acumuladas de todas las rutas`.

### Arranque acotado (importante)

La lista **arranca filtrada** a lo que puede subir a un camión: `factura=con_factura` y
`archivado=0`. Mientras esos dos sigan exactamente así se muestra una franja azul:

> `Enseñando sólo lo que tiene factura —cuadre o no— y sin archivar. A una ruta entra todo lo facturado (por ahora, el domicilio cobrado ya no se exige): si la factura cambió, al camión va lo facturado.`

con el botón `Ver todas las facturas`, que pone ambos filtros a vacío.

Debajo, el conteo: `<total> facturas` (`1 factura` si es una); si hay fechas puestas añade
` · del <desde> al <hasta>` (o `del <fecha>` si coinciden, `desde el <x>`, `hasta el <x>`)
y siempre `, del más nuevo al más viejo`. Indicador giratorio mientras refresca.

### Filtros y controles (valores por defecto entre paréntesis)

| Control | Título (literal) | Opción «todos» | Opciones | Parámetro |
|---|---|---|---|---|
| Selector | `Estado de reparto en delivery` | `Cualquier reparto` (por defecto) | `Sin entregar`=`sin_entregar`, `En despacho`=`en_despacho`, `En ruta`=`en_ruta`, `Entregado`=`entregado`, `Devuelto o cancelado`=`devuelto`; cada opción lleva de nota cuántas facturas hay en ese estado (`conteoPorRepartoProvider`) | `reparto` |
| Selector | `Municipio del cliente` | `Todos los municipios` (defecto) | de facetas, con el nº de facturas como nota | `municipio` |
| Selector | `Precio del domicilio` | `Cualquier precio de domicilio` (defecto) | `Con precio puesto: el domicilio trae importe`=`con` (`facturaDomicilio > 0`), `Domicilio sin precio puesto: va en $0`=`sin` (nulo o ≤ 0). No es cuentas por cobrar | `cobro` |
| Selector | `Pedido de origen` | `Con o sin pedido` (defecto) | `Con pedido`=`con`, `Sin pedido`=`sin` (por `folio`) | `pedido` |
| Selector **de varios** (cajón con casillas, `SelectorMultiple`; issue 18 de Amado) | `Vendedor de la factura` | `Todos los vendedores` (defecto); «3 vendedores» si hay varios | de facetas, con nº de facturas | `vendedor` repetido (o `vendedores=a,b`) |
| Dos fechas | tooltip `Desde (fecha de la factura)` / `Hasta (fecha de la factura)` | vacías | `desde` acota el `max` de `hasta` y viceversa | `desde`, `hasta` |
| Botón | `sólo ese día` | — | aparece si `desde` y `desde ≠ hasta`; copia `desde` en `hasta` | — |
| Botón (icono ✕) | tooltip `Quitar el filtro de fechas` | — | limpia ambas | — |
| Selector | `Cómo se ordena esta página` | — (defecto `Más recientes`) | `Más recientes`=`recientes`, `Más antiguos`=`antiguos`, `Precio: mayor a menor`=`precio_desc`, `Precio: menor a mayor`=`precio_asc`, `Distancia: más larga`=`distancia_desc`, `Peso: mayor`=`peso_desc` | **local**: ordena SÓLO la página visible |
| Buscador | placeholder `Buscar` | — | 400 ms de espera antes de consultar | `q` |

- La **sucursal NO se filtra aquí**: la manda el selector de la barra superior.
- Cualquier cambio de filtro vuelve a la página 1.

### Endpoints

- `GET /api/orders` con `q, archivado, factura, municipio, vendedor, cotizado, reparto,
  desde, hasta, pagina` (y `porPagina`, tope 200). Respuesta:
  `{ orders[], total, pagina, porPagina, paginas, resumen, pesoTotal }`.
  **Tamaño de página: 50** (lo fija el servidor; el control de tamaño está deshabilitado).
- `GET /api/orders?resumen=1&porPagina=1&<mismos filtros>` — el pre-despacho de lo
  filtrado; se pide **sólo al abrir el desplegable**. Si el total supera **5000** facturas
  devuelve `resumen: null`.
- `GET /api/orders/facetas` — `{ municipios:[{valor,pedidos}], vendedores:[...],
  sucursales:[{valor,nombre,pedidos}] }` (el campo del JSON sigue llamándose `pedidos`). Se cachea 10 minutos.

Semántica de los filtros en el servidor (compartida con el armador de rutas):
`q` busca en cliente, folio, dirección de entrega, dirección, municipio, vendedor y en el
texto de productos. `factura`: `con_factura` = `igual|cambiado`; `cuadra` = sólo `igual`;
`sin_cotejar` = `facturaEstado` nulo. `reparto=sin_entregar` = sin ruta, sin `deliveredAt`
y sin resultado `entregado`.

### Pre-despacho de LO ELEGIDO (tarjeta, sólo si hay marcados)

Cabecera: `<n> factura(s) elegidas` · `<n> producto(s) · <n> empaques · <kg> kg`.
Si hay marcados fuera de la página actual: `(<n> en otras páginas, sin sumar)`.
Botones: `Ver e imprimir` (abre el pre-despacho, ver §10) y `Quitar la marca`.
Tabla: `Producto` | `Empaques` | `Unidades` | `kg` (kg vacío se pinta `—`).
Se calcula en el cliente sobre las líneas que ya vinieron con las facturas de la página.

### Pre-despacho de LO FILTRADO (bloque plegable)

Título: `Pre-despacho de lo filtrado` + `· <n> producto(s) · <n> empaques · <kg> kg`.
Botón `Ver e imprimir`. Mismas 4 columnas.
- **Cuando el servidor no puede sumarlo:**
  `Son demasiadas facturas para sumarlas. Acotá por día o sucursal y sale.`

#### Los números que NO se enseñan — 22/09/2026

Con el mismo filtro, la franja decía `10 producto(s) · 3185 empaques · 0.0 kg` y la hoja
imprimible decía `264 factura(s) · 24891.0 kg` (entonces `pedido(s)`). Los dos eran ciertos cada uno en su
definición —uno suma el peso resuelto **por producto**, el otro el del **conjunto de
facturas**— y juntos sólo pueden hacer una cosa: que quien carga el camión se crea que no
pesa nada.

Las dos reglas que quedaron, y las dos son la misma:

- **El total por producto (kg y unidades) es nulo mientras falte UNO**, y entonces se
  escribe cuántos faltan por emparejar (`3 de 10 productos sin peso`) en vez de una cifra.
  Sumar lo que hay y callar lo que falta es la misma mentira con menos escándalo: ocho de
  diez resueltos dan un peso que parece completo y se queda corto.
- **Las unidades salen del catálogo** (`empaques × unitsPerPackage`), no de `quantity`.
  `quantity` unas veces trae unidades y otras repite los bultos: por eso la hoja llegó a
  decir `SERVILLETA PROSITO PACA 24P · 7 empaques · 4 unidades` —cuatro unidades dentro de
  siete pacas— y `SOPA DE POLLO CAJA 72 P · 15 empaques · 15 unidades`. Sin catálogo se
  pinta `—`.

La **cabecera de la hoja no cambia**: el peso del conjunto de facturas sí se sabe entero, así
que sigue siendo un número siempre.

En el **móvil** el bloque no cuelga debajo de la lista: se abre en su **cajón** desde un
botón que dice cuántas facturas van contadas. Debajo de la lista había que bajar por
doscientas y pico facturas peleándose con dos desplazamientos, con el pie fijo tapando el
final — «y el pre-despacho, que no lo veo».

### Tabla de facturas

Columnas por orden (la etiqueta literal es la que se pinta). **La factura es la primera
columna** (desde el 21/10/2026; antes lo era la fecha del pedido):

1. **Casilla** de selección. La de la cabecera marca/desmarca toda la página
   (`aria-label`: `Elegir todos los de esta página`). No abre la factura.
2. `Factura` — la fila: el número de factura, solo, en una línea (la fecha tiene su columna y el domicilio
   está en `Precio`: apilar marcas en esta celda partía la fila, 21/10/2026). Oculta bajo 1024 px.
    **Detalle de la columna:** `igual` → nº de factura en verde, tooltip
    `Cuadra con lo pedido: se puede repartir tal cual.`; `cambiado` → nº + `⚠` en ámbar,
    tooltip `Se facturó algo distinto de lo pedido: al camión va lo facturado.` (hasta el
    15/10/2026 decía que no podía ir en una ruta; desde el issue 10 de Amado `cambiado` entra);
    `sin_factura` → `sin facturar`; nulo → `sin cotejar` con tooltip
    `El cotejo contra Ventra no ha pasado por esta factura todavía.`
    **El número de factura no se pierde con la columna** (Amado, issue 8, 14/10/2026: «los
    logísticos operan con número de factura»): entre 768 y 1023 px baja a la celda del cliente,
    bajo el folio (`Factura 1024237`); en la tarjeta del teléfono sube a la cabecera con su rótulo
    y la insignia queda solo con el estado (`Cuadra` / `Cambió !`).
    **Con factura `igual` o `cambiado`, junto al número, una segunda marca con el cobro del
    domicilio** (Amado, 08/10/2026: «en la tabla no está claro qué pedidos han sido facturados
    y cobrados»; entonces la fila era el pedido): `Dom. $0.46` en verde, con el importe, cuando `facturaDomicilio > 0`; y
    `Domicilio sin precio puesto` en gris cuando es nulo o 0, con el tooltip `La factura trae la
    línea ENTREGA A DOMICILIO: esta factura no puede ir a una ruta ni a una zona del tablero
    hasta que el domicilio se cobre en la factura.` Con `sin_factura` o nulo no se añade nada.
    Es la regla del 07/10 hecha visible: sin esa línea la factura no entra en una ruta ni en
    una zona. **El ámbar sólo sale si ése es lo que frena a la factura** (se le pregunta a
    `porQueNoSePuedeColocar`, no se repite la regla): con ruta, entregada o archivada
    lleva sólo el número, o el `Dom.` verde si hay cobro; una devuelta o cancelada sí lleva el
    ámbar, porque se puede reasignar. En el móvil (tarjeta) la marca va dentro de la
    tarjeta, junto al número.
3. `Fecha factura` — el día de la factura en hora de Cuba (`facturaAt`); si falta, `orderDate`, y si tampoco, la de copiado con un `≈`
   y el tooltip `Factura copiada antes de que se guardara su fecha: ésta es la del espejo.`
4. `Sucursal` — **sólo si no hay sucursal elegida arriba**; se oculta bajo 1536 px.
5. `Pedido` — **de qué pedido de PEDIDO viene la factura**: su folio (mono; entero en el tooltip
   `Pedido de PEDIDO: <folio>`). Ya no lleva la insignia de estado: con las facturas de Ventra como
   fuente nadie lo actualiza. **Si la factura no viene de ningún pedido** (no hay folio, o este aparato aún no lo ha
   puesto al día) sale un guion `—`, con el tooltip `Esta factura no viene de ningún pedido de PEDIDO.`
6. `Cliente` — nombre y, debajo, la dirección de entrega (`endAddress` o `address`); si no hay punto (`endLat`/`endLng` nulos), la línea ámbar `Sin ubicación: ponle la dirección en «Ubicar la entrega»`. Es la antigua columna `Dirección`, que se quitó.
7. `Ruta` — código de ruta en insignia azul o `—`. Oculta bajo 1280 px.
8. `Artículos` — primer producto `×<empaques>` y `+<n>` con desplegable al pasar el ratón
   (en Flutter: tocar para abrir). Oculta bajo 1024 px.
9. `Peso` — `<n> kg`, alineada a la derecha.
10. `Precio` — el domicilio de la parada (`costoDeLaParada`): `pedidoCosto` (lo que cotizó Entrega) y, si no, lo que cobró la factura. Si ninguno: `sin precio` en gris, con el tooltip `La factura trae la línea ENTREGA A DOMICILIO pero con el precio en $0: no se puso el precio.` Las marcas `Dom. $x` y `Domicilio sin precio puesto` quedan sólo en la tarjeta del teléfono.
11. `Entrega` — estado de reparto calculado: `Devuelto` / `Cancelado` (ámbar),
    `Entregado` (verde), `En ruta` (azul), `En despacho` (índigo), `Sin entregar` (gris).
    Oculta bajo 768 px.
12. Chevron. La fila entera abre el detalle.

**Sin columna `Vehículo`** (Amado, 08/10/2026, «elimínala para más espacio»): desde la 1.0.28
`orders.vehicle_id` no existe y la celda era un marcador mudo. El camión de una factura sigue
viéndose en el **detalle**, en la sección `Ruta`, porque sale de su ruta.

**Regla de estado de reparto:** manda `resultado` de la parada, **no** el estado de la
ruta. Una ruta completada no convierte en «entregada» una factura devuelta.

### Estados vacíos y carga

- Cargando: `Cargando...`
- Sin resultados: sin filtros, `Aún no hay facturas de esta sucursal.`; con algún filtro
  puesto, `Ninguna factura cuadra con estos filtros.` y debajo el botón `Quitar todos los
  filtros` (limpia **todos**, incluidos los del arranque). Son dos frases distintas a
  propósito: con un filtro que no casa, «aún no hay facturas» es mentira (25/09/2026).

### Paginación

Componente de páginas al pie: `Mostrando <desde>–<hasta> de <total>`, botones
primera/anterior/números (ventana de 5)/siguiente/última. **50 por página, fijo.**

### Detalle de la factura (cajón, ancho `lg`)

Título = nombre del cliente, subtítulo = folio. Secciones:

- `Entrega`: dirección, coordenadas `lat, lng` con enlace `ver mapa` a Google Maps,
  teléfono. **Punto de entrega a mano (issue 19 de Amado, 1.0.39):** si `puntoManual`, la
  insignia ámbar `Punto puesto a mano` (tooltip `Lo puso <persona>`); debajo, el botón
  `Ubicar la entrega` (icono `edit_location_alt_outlined`) o, si la factura ya está
  entregada o su ruta está completada, el literal del porqué en gris y sin botón (ver
  «Ubicar la entrega» abajo).
- `Recorrido`: mapa de 220 px con dos puntos, almacén (origen) → cliente. Pie:
  `Del almacén (<nombre>) al cliente.`
- Banda de factura según `facturaEstado`:
  - `igual`: `Cuadra con la factura <nº> de Ventra: lo pedido es lo facturado.`
  - `cambiado`: `Se facturó algo distinto de lo pedido (factura <nº>). Al camión va lo facturado: los productos de abajo ya son los de la factura.` (con `itemsOrigen = 'factura'`; con `'pedido'` termina en `, pero los productos de abajo son los del pedido: la factura no se pudo atar a este pedido.`, y sin `itemsOrigen` en `Al camión va lo facturado.`)
  - Sin factura: `Todavía no aparece facturado en Ventra.`
  - Con `igual` o `cambiado`, una línea más que dice si entra a una ruta (15/10/2026,
    `lineaDeRutaDeLaFicha`, que pregunta a `porQueNoSePuedeColocar` y no repite la regla):
    `Puede ir a una ruta.` / `No entra a una ruta: la factura no tiene un cobro de domicilio registrado.`
    / `No entra a una ruta: se marcó domicilio y Entrega todavía no lo cotizó.` Nada si ya va
    en una ruta, está entregado o archivado (ni si no tiene punto de entrega).
  - Y si hay línea de domicilio: `La factura cobró <n.nn> USD de domicilio.`
- `Domicilio` (caja verde si hay precio; sin precio, ámbar si el vendedor marcó domicilio y
  gris si no): `Distancia` (`<n.nn> km` o `—`), `Peso total` (`<n.nn> kg`), y a la derecha
  el importe o `Sin calcular todavía`.
  Nota al pie: `El costo lo puso el repartidor desde Entrega. La distancia es del almacén al cliente.`
  / (marcado) `El costo lo pone el repartidor desde Entrega; hasta entonces esta factura no tiene precio de domicilio.`
  / (sin marcar) `El vendedor no marcó domicilio y Entrega sólo cotiza los marcados: esta factura no tiene precio de domicilio, y no le hace falta para ir a una ruta.`
- `Productos (<n>)`: por línea, nombre, `<n> unidades`, ` · <n.nn> kg/empaque`,
  `×<empaques> empaques` y el peso de la línea; si no hay peso resuelto: `sin peso`.
  Vacío: `Sin productos`.
- `Ruta`: código, vehículo y fecha de entrega, si la tiene.

**Acciones de escritura en esta pantalla: una, `Ubicar la entrega`.** Lo demás es lectura,
selección local e impresión.

#### Cajón `Ubicar la entrega` (ancho `lg`; issue 19 de Amado)

El cliente pide entregar en otro sitio y el facturador lo apunta en el ticket: la dirección no
coincide con la geolocalización del cliente. El logístico le pone **a mano** el punto de
entrega (lat, lng, dirección); ese punto manda sobre el del cliente y sobrevive al espejo
(lo hace el servidor). Un solo cajón (`CajonUbicarEntrega`), tres puertas: esta ficha, la
tarjeta de la parada del detalle de ruta (junto a `Quitar de ruta`) y cada fila del paso
`Facturas` del asistente (botón pequeño con tooltip `Ubicar la entrega`, que **no** marca
la casilla).

- Título `Ubicar la entrega`, subtítulo `<folio> · <cliente>`. Campos: `Dirección` (+ botón
  `Buscar`, 4 letras como mínimo, **necesita red**), `Coordenadas` (`19.83, -75.82`; **la
  única caja por la que se escribe el punto**: la escriben también el mapa y la búsqueda) y
  el mapa para pulsar (`MapaParaElegirPunto`; funciona sin señal). Vacía, la dirección se queda
  como estaba.
- Pie: `Cancelar` · `Volver al punto del cliente` (sólo si ya es manual; sin fondo, icono
  `undo`, **pregunta antes** en un cajón: `Sí, volver al punto del cliente` / `No, dejar el
  punto a mano`) · `Guardar punto` (`BotonPrincipal`, icono `edit_location_alt_outlined`; no se
  enciende hasta que cambie algo).
- Si no se puede (entregado o ruta completada) el cajón no enseña formulario: dice el literal.
- Los «no» salen **literales** debajo de las cajas, y el cajón se queda abierto.

| Acción | Llamada | Notas |
|---|---|---|
| Poner el punto | `PUT /orders/<id>/punto` `{lat, lng, direccion?}` | 200 `{id, endLat, endLng, endAddress, puntoManual, puntoManualPor, puntoManualAt, deliveryDistanceKm, segmentKm}`. 400 `Se espera { lat, lng }` / `lat y lng tienen que ser un punto del planeta` (rango o (0,0)); 404 `No encontrado`; 409 `La factura ya está entregada: no se le puede cambiar el punto` / `La ruta ya está completada: no se le puede cambiar el punto a sus paradas`; 502 si Accesos no contesta. |
| Volver al del cliente | `DELETE /orders/<id>/punto` | Mismo 200. 409 `La factura no tiene un punto puesto a mano`. |

- **Web:** va al servidor y espera; sin fila escrita si dice que no. **APK y escritorio:** UNA
  transacción escribe la fila (`endLat/endLng/lat/lng`, `endAddress`, `puntoManual`,
  `puntoClienteLat/Lng/Address` la primera vez), recalcula el km de la parada y el total de su
  ruta (mismas cuentas que al armar) y encola el apunte. **No recalcula `deliveryDistanceKm`**
  (el almacén de la factura se elige en el servidor); hasta que suba y baje, se ve la de antes.
  La bandeja de revisión lo reconoce (`Poner el punto de entrega de una factura a mano`).

---

## 3. Rutas — `/routes`

**Para qué sirve.** Armar la ruta de un camión (asistente de 4 pasos), seguirla, cerrarla
parada por parada y compartirla con el chofer. **Quién la usa:** quien despacha.

**Título:** «Rutas». Encabezado interno: `Planificador de Rutas`. Botón `+ Nueva Ruta`.

### Pestañas (contadores en la propia pestaña)

| Pestaña | Qué agrupa | Vacío (literal) |
|---|---|---|
| `Activas` (defecto) | estado ≠ `completed` y ≠ `in_progress` (es decir, `planned`) | `Sin rutas activas. Crea la primera.` |
| `En curso` | `in_progress` | `Sin rutas en curso.` |
| `Historial` | `completed` | `Sin rutas completadas aún.` |

### Columna izquierda — filtros y lista

Filtros (se aplican **en el cliente** sobre las rutas ya traídas):
- Buscador, placeholder `Buscar por código, nombre, vehículo...` (busca en código, nombre,
  dirección de origen, vehículo y sucursal).
- Selector `Rutas de un camión`, opción «todos» `Cualquier vehículo`; cada vehículo con la
  nota `en ruta` si está ocupado.
- Dos fechas (`Desde` / `Hasta`) sobre `createdAt`; `hasta` incluye el día entero.
- Botón ✕ `Limpiar` cuando hay algo puesto.

Tarjeta de ruta: código en insignia azul, nombre, `<n> paradas · <km> km`, sucursal (icono
tienda) sólo si la lista **no** va agrupada, vehículo `Nombre (Placa)`, dirección de
origen, fecha de entrega, insignia de estado (`Planificada` / `En curso` / `Completada`),
insignia `Sobrepeso` si el peso supera la capacidad, importe total y, si la ruta no está
completada, el enlace `Eliminar`.

**Agrupación:** si en la página hay rutas de más de una sucursal, se agrupan bajo un
encabezado pegajoso con el nombre `Sucursal (CÓDIGO)` y el número de rutas. Con una sola
sucursal no se agrupa ni se repite el nombre.

**Paginación de la lista: 20 rutas por página** (cliente), con el mismo componente.

### Columna derecha — detalle de la ruta seleccionada

Sin selección: `Selecciona una ruta para ver el detalle`.

Cabecera: código, nombre y etiqueta con la sucursal. Botones:
- `Ver paradas (<n>)` → panel flotante con: `Carga total` (chips `producto ×cantidad`),
  `Paradas y precio por cliente (<n>)` y una tarjeta por parada con número de orden,
  cliente, dirección, municipio, `<peso> kg · <km> km desde partida`, importe y chips de
  artículos (o `Sin artículos detallados`).
  **Nuevo 07/10/2026 (reparto, no existe en Next):** la tarjeta lleva la insignia
  `Conduce: <número de operación>` (el conduce ES el número de operación de la factura) y,
  **sólo en una ruta `planned`**, el botón `Quitar de ruta`. Éste abre un cajón titulado
  `Quitar de la ruta` (subtítulo `<cliente> · Conduce: <número>`) con el texto `«<cliente>»
  sale de esta ruta y vuelve a facturas disponibles. La ruta se queda con las demás paradas y
  su peso y su importe se recalculan sin él.` + `Si la ruta se armó desde una zona del
  tablero, la factura regresa a esa zona cuando se sincronice (en la web, de inmediato).`,
  y los botones `Sí, quitar «<cliente>» de la ruta` / `No, dejarlo en la ruta` (cerrar sin
  contestar = no). Sin señal (APK/escritorio) se encola y sube al volver; la web lo hace al
  instante. Ni renumera las demás paradas ni recalcula los km de la ruta.
- `Iniciar ruta` (sólo en `planned`; mientras guarda: `Iniciando...`).
- `Cierre` + contador de paradas sin marcar (visible en `in_progress` **y** en
  `completed`, porque el camión vuelve después de que alguien la dé por completada).
- `Marcar como completada` (sólo `in_progress`; mientras: `Completando...`).
- Insignia `Peso total (<w> kg) supera capacidad (<c> kg)` si procede.

**Sección de filtros plegable (issue 6.3 de Amado; hecho el 14/10/2026).** Los filtros de la lista
(buscar, `Rutas de un camión`, `Ubicación de salida`, `Desde`/`Hasta`, `Limpiar`) viven
tras un botón `Filtros` (icono de ajustes, chevrón `v`/`^`) que los pliega y despliega. Con
los dos paneles arranca **plegada**; en el teléfono, **desplegada**. Lo elegido se recuerda
mientras la aplicación está abierta (`filtrosPlegadosProvider`, no se guarda en el aparato).
Plegada, el botón dice `Filtros · <n> activo(s)` y muestra su propio `Limpiar`.

Línea de datos: estado, `<km> km (incl. regreso)`, `<kg> kg`, importe total, vehículo
`Nombre · Placa`, fecha de entrega, `Carga total: <n>` y la **duración** («3 h 20 min»,
sale de `startedAt`/`finishedAt`; tooltip con las horas).

**Pre-despacho de la ruta (issue 8 de Amado; hecho el 14/10/2026).** Debajo de `Carga total` (que se
mantiene), el detalle de **toda** ruta —armada a mano o desde una zona del tablero— trae la
sección `Pre-despacho`: la misma vista que el paso 4 del asistente y que Facturas
(`VistaPreDespacho`), el botón `Ver e imprimir` y, debajo, la tabla `Por producto y factura`. Antes el
pre-despacho sólo existía dentro del asistente, y una ruta del tablero (que va derecha al
detalle) no lo tenía. La suma es **una sola** para las tres entradas:
`ConsultasPedidos.preDespachoDe`; `app/lib/pantallas/rutas/datos/pre_despacho_de_la_ruta.dart`
sólo la reparte factura a factura. Ver §10.1 para la tabla.

Compartir: enlace `Abrir en Google Maps` (origen = almacén, paradas en orden, **destino =
el mismo almacén**, `travelmode=driving&dir_action=navigate`), botón `copiar enlace` que
pasa a `copiado` 2,5 s, y aviso si sobran paradas:
`(Google admite 25 paradas: <n> quedan fuera del enlace)`.

Mapa a lo alto restante. Sin coordenadas: `Sin coordenadas GPS para esta ruta`.
Leyenda: `Punto de partida` (verde) · `Paradas` (azul) · `Regreso al depósito` (naranja) ·
`Punto puesto a mano` (rojo: el **número** de una parada con el punto puesto a mano sale en
rojo, `ColoresDelMapa.puntoManual`, y manda sobre entregada y regreso; en un grupo `2·3` basta
una manual para que salga rojo; el globo añade la línea `Punto puesto a mano`). Cada
tarjeta de parada con `puntoManual` lleva la insignia `Punto puesto a mano` y, si se puede
(sin entregar, ruta no completada), el botón `Ubicar la entrega`.

### Asistente «Nueva Ruta» (cajón a pantalla **completa**, con pie fijo)

Barra de progreso de 4 pasos con las etiquetas `Sucursal`, `Salida`, `Vehículo`,
`Facturas`; se pinta **un paso cada vez** y se puede volver a uno ya hecho pulsando su
tramo. Si la sucursal y la salida ya vienen resueltas, arranca directamente en el paso 3.
Pie fijo: `Cancelar` y `Generar Ruta` (mientras: `Generando ruta...`), deshabilitado si
falta salida, vehículo o facturas, o si hay sobrepeso.

1. **Sucursal.** Selector `Sucursal de la ruta`, placeholder `Elige la sucursal…`.
   Nota: `Las facturas, los vehículos y el punto de partida serán los de esta sucursal.`
   Botón `Siguiente`. La sucursal se autocompleta con la del usuario, o con la de la barra
   superior, o con la única disponible.
2. **`Punto de partida`.** Es un **almacén de la sucursal** (de Accesos), nunca un punto
   propio. Con varios: selector `Almacén del que sale el camión`, el principal primero y
   con la nota `principal`. Mapa de 220 px con el punto. Sin almacenes con ubicación:
   `Esta sucursal no tiene ningún almacén con ubicación. Los almacenes se ponen en el CRM, y hasta entonces no hay desde dónde medir.` Con el botón `Ver los almacenes`, que lleva a la pantalla de consulta.
   Botón `Continuar →`.
3. **`Vehículo *`.** Selector `Vehículo de la ruta`, placeholder `Elige el vehículo…`;
   cada opción con la nota `<capacidad> kg`, `<capacidad> kg · en ruta` o `<capacidad> kg ·
   en el taller`. **Se ofrecen los vehículos activos, también los ocupados y los del
   taller** (los inactivos no). Al elegir uno del taller sale, en ámbar, `<nombre> está
   marcado EN EL TALLER. La ruta se arma igual —tiene su capacidad y su costo por km— pero
   ese camión no puede salir hoy. Si ya volvió, sácalo del taller en Vehículos.`: aviso, no
   bloqueo. Sin ningún activo: `Los vehículos de esta sucursal están inactivos, y a una ruta
   nueva sólo se asigna un vehículo activo. Actívalo en Vehículos.` Campo de nombre, placeholder
   `Nombre (el código se genera solo)`. Campo `Fecha de entrega (opcional)`.
   Sin vehículos: `No hay vehículos disponibles. Crea o libera uno en Vehículos para poder crear la ruta.`
4. **`Facturas de cliente (<n>)`.** Dos columnas: lista a la izquierda, pre-despacho fijo a
   la derecha.

   Filtros de la lista de disponibles:
   - Selector `Sucursal de la ruta` (repetido) + los controles de fecha de Facturas:
     `Desde (fecha de la factura)` / `Hasta (fecha de la factura)` / `sólo ese día` / ✕ (los dos días
     incluidos; hasta el 15/10/2026 era un solo `Día de los pedidos` con `Todos los días`,
     issue 13 de Amado).
   - Selector **de varios** `Vendedor del pedido` / `Todos los vendedores` (con buscador siempre; issue 18 de Amado).
   - `km máx.` (número) y `costo mín.` (número).
   - Selector `Estado del pedido en PEDIDO` / `Cualquier estado`: `En proceso`=`en_proceso`,
     `Completada`=`completada`, `Expirada`=`expirada`.
   - Selector `Si lleva domicilio: marcado por el vendedor o cobrado en la factura` /
     `Con y sin domicilio`: `Sólo con domicilio`=`1` **(por defecto `1`)**, `Sólo sin
     domicilio`=`0`. «Con» es `requiereDomicilio = true` **o** `facturaDomicilio > 0`;
     «sin», el contrario exacto (desde el 15/10/2026, issue 10).
   - Selector `Si Entrega ya le puso costo de domicilio` / `Cotizados y sin cotizar`:
     `Ya cotizados`=`1`, `Sin cotizar`=`0`.
   - Botón `Limpiar` (vuelve a domicilio=`1`).
   - Buscador `Buscar factura...` y selector `Municipio del cliente` / `Todos los municipios`
     (este último se aplica **en el cliente**).
   - **La regla de entrada NO es configurable:** la lista sólo trae lo que una ruta acepta
     —`facturaEstado ∈ {igual, cambiado}`, `facturaDomicilio > 0` y `pedidoCosto` no nulo
     si `requiereDomicilio` es `true`— y no hay filtro de factura. Hasta el 15/10/2026 se
     mandaba siempre `factura=cuadra` (sólo `igual`); ya no, porque dejaba fuera los
     `cambiado`. `domicilio=1`, que es el defecto, cuenta también el cobro de la
     factura, así que ya no esconde las facturas sin marcar que sí entran (hasta el
     15/10/2026 miraba sólo la casilla `requiereDomicilio` y los escondía).

   Aviso si la lista viene recortada (tope de 2000 en el servidor):
   `Hay más facturas de las que caben en la lista. Elegí la sucursal y el día para verlos todos: una ruta se arma con los de un sitio y un día.`

   Barra de capacidad: `<peso> / <capacidad> kg (<n>%)`, verde <80 %, ámbar ≥80 %, roja
   ≥100 %; insignia `LLENO` y texto `Camión lleno — no cabe más`. Sin vehículo:
   `Elige un vehículo para ver la capacidad`.

   Cada fila: casilla, cliente, dirección, chips de artículos, `<peso> kg` y el costo de
   domicilio o `sin cotizar`, y a la derecha un botón pequeño `Ubicar la entrega` (tooltip) que
   abre el cajón del punto a mano sin marcar ni desmarcar la casilla. Las facturas que **no caben** quedan deshabilitados con
   `No cabe en el camión` (tooltip igual).

   Pie de la lista: `<n> facturas seleccionadas` y, si alguna ya no sale con los filtros,
   `(<n> de otro día o filtro, siguen contando)`; a la derecha `<peso> / <capacidad> kg`.
   Sobrepeso: `Peso ({w} kg) supera capacidad del vehículo ({c} kg)`.

   Estados: `Cargando facturas...` / `No hay facturas disponibles para rutear.`

   **Pre-despacho lateral** (`Pre-despacho`): botón `Ver e imprimir`; tabla `Producto` |
   `Emp.` | `Uds.`; totales `Facturas`, `Empaques`, `Unidades`, `Peso` (`<w> / <cap> kg`).
   Vacío: `Según vayas eligiendo facturas, aquí sale cuánto hay que sacar de cada producto.`

### Endpoints y acciones

| Acción | Llamada | Notas |
|---|---|---|
| Listar rutas | `GET /api/routes` | Sin parámetros; trae ruta + sucursal + vehículo + paradas ordenadas por `stopOrder`. |
| Vehículos | `GET /api/vehicles` | Para el selector y el filtro. |
| Almacenes | `GET /api/almacenes` | Punto de partida (por código de sucursal). |
| Sucursales | `GET /api/branches` | Las que la persona puede ver. |
| Facturas elegibles | `GET /api/orders/available` con `q, branchId, fecha, vendedor, kmMax, costoMin, estado, cotizado, domicilio` | Devuelve `{orders, total, truncated}`; tope 2000. Sin `factura`: la regla de entrada va fija en la consulta. |
| Opciones de filtro | misma URL sin `q`, `vendedor` ni municipio | Para que elegir un vendedor no borre los demás. |
| Crear ruta | `POST /api/routes` con `{name?, branchId, vehicleId, deliveryDate?, originAddress, originLat, originLng, orderIds[]}` | 201 con la ruta creada; se selecciona sola. |
| Iniciar | `PATCH /api/routes/<id>` `{status:'in_progress'}` | Pasa a la pestaña `En curso`; marca el vehículo `in_use`. |
| Completar | `PATCH /api/routes/<id>` `{status:'completed'}` | Libera el vehículo, pasa a `Historial`. |
| Eliminar | `DELETE /api/routes/<id>` | Sólo rutas no completadas; libera el vehículo. El cajón de confirmación (`Borrar «RT-…»`) añade, desde el 07/10/2026: `Si la ruta se armó desde una zona del tablero, las facturas vuelven a esa zona cuando se sincronice el borrado (en la web, de inmediato). Mientras tanto, sin señal, salen en «Sin colocar».` |
| Quitar una parada | `DELETE /api/routes/<id>/stops/<orderId>` | Sólo rutas `planned`. 409 `Sólo se pueden retirar paradas de una ruta planificada` / `La factura no pertenece a una ruta planificada o ya fue retirada`. |
| Cerrar parada por parada | `POST /api/routes/<id>/results` | Ver §9.1. |

**Errores del servidor, literales (salen como aviso emergente, no dentro del cajón):**
- `Las coordenadas del punto de partida son requeridas` (400)
- `Se requiere un vehículo para crear la ruta` (400)
- `Las facturas seleccionadas ya no están disponibles: <detalle>` (400)
- `<n> de las <total> facturas elegidas no pueden ir en esta ruta: <folio> (ya va en la ruta RT-…|ya se entregó y no puede volver a un camión|PEDIDO lo archivó|sin coordenadas de entrega|no vino de PEDIDO|no existe o no es de tu sucursal|no es un identificador de factura), … y <k> más.` (409)
  — con `<n>` = 1 el verbo va en singular (`no puede ir`), y si se eligió UNA SOLA
  factura la cabecera entera es `La factura elegida no puede ir en esta ruta: …`:
  los dos números serían el mismo y no informan de nada. La escriben igual el
  servidor y el aparato —la ruta se arma sin señal—, y lo que las ata es
  `docs/armado-rechazado.casos.json`.
- `En una ruta sólo entra lo facturado. <n> no cumplen: <conduce> (sin facturar|sin cotejar), … y <n> más.` (409)
  — desde el 15/10/2026; antes decía `lo facturado y que cuadre` y tenía el motivo
  `cambió en la factura`, que ya no existe: `cambiado` entra.
- `El vehículo está inactivo y no se puede asignar a una ruta.` (400)
- `Peso total (<w> kg) supera la capacidad del vehículo (<c> kg)` (400)
- `Una ruta se arma eligiendo facturas ya existentes. Manda \`orderIds\`.`
- Respaldos del cliente: `Error al crear la ruta`, `Error al iniciar la ruta`,
  `Error al completar la ruta`.

---

## 4. Clientes — `/customers`

**Para qué sirve.** Consultar la cartera de clientes espejada de PEDIDO (sólo los que
tienen geolocalización) más los manuales antiguos, y acotarla por distancia al almacén
para decidir a quién meter en la ruta de hoy. **Quién la usa:** despacho y ventas.
**Sólo lectura:** el alta manual se retiró el 03/09/2026.

**Título:** «Clientes». Encabezado `Clientes` + subtítulo:
`Clientes de PEDIDO (sincronizados, sólo con geo) + los manuales de delivery. <total> en total` y, si hay más de una página, ` · página <n> de <n>.`

### Filtros (aparecen sólo si tienen más de una opción, salvo los fijos)

| Control | Título | «Todos» | Opciones | Parámetro |
|---|---|---|---|---|
| Selector | `Municipio del cliente` | `Todos los municipios` | de la base, con nº de clientes | `municipio` |
| Selector | `Vendedor que lo atiende` | `Todos los vendedores (<n>)` | de la base, con nº de clientes | `vendedor` |
| Selector | `A qué distancia del almacén` | `A cualquier distancia` (defecto) | `Hasta 5 km`=`5`, `Hasta 10 km`=`10`, `Hasta 20 km`=`20`, `Hasta 50 km`=`50` | `kmMax` |
| Selector | `Si tiene teléfono` | `Con y sin teléfono` (defecto) | `Con teléfono`=`1`, `Sin teléfono`=`0` (con el nº de clientes sin teléfono como nota) | `telefono` |
| Selector | `Zona de reparto` | `Todas las zonas` | de la base | `zona` |
| Selector | `De dónde salió el cliente` | `De PEDIDO y manuales` (defecto) | `Sólo los de PEDIDO`=`pedido`, `Sólo los manuales`=`manual` | `origen` |
| Botón | `Quitar filtros` | — | aparece si hay municipio, zona, origen o búsqueda | — |
| Buscador | placeholder `Buscar por nombre, dirección o municipio…` | — | 400 ms de espera | `q` |

La sucursal la manda la barra superior. Cualquier cambio vuelve a la página 1.

### Tabla

| Columna (literal) | Contenido |
|---|---|
| `Cliente` | nombre; debajo el código en mono; debajo el teléfono o `sin teléfono` en ámbar |
| `Dirección` | `dirección · municipio`, o `—` |
| `Vendedor` | vendedor o `—`; debajo `<n> km` cuando se filtró por distancia |
| `Origen` | insignia `PEDIDO` (azul) o `Manual` (gris) |

En pantallas estrechas **se desplaza la tabla, no la página** (ancho mínimo 736 px).

### Estados

- Cargando: `Cargando…`
- Sin ninguno: `Sin clientes todavía. Los de PEDIDO aparecen solos cuando tengan geolocalización.`
- Con filtros que no cuadran: `Sin resultados.`

### Paginación

**50 por página** (`TOPE` del servidor). Dos juegos de controles:
- Arriba, junto al subtítulo: `◀ <pagina> / <paginas> ▶`.
- Al pie de la tabla: `<desde>–<hasta> de <total>` y los botones `Anterior` / `Siguiente`
  con `<pagina> / <paginas>` en medio.

### Endpoint

`GET /api/customers` con `q, municipio, zona, vendedor, telefono, kmMax, origen, pagina`.
Respuesta: `{customers[], total, pagina, paginas, porPagina, truncated, almacenDeReferencia,
municipios[], sucursales[], zonas[], vendedores[], sinTelefono}`. La distancia se mide en
línea recta desde el **almacén principal** de la sucursal en curso, con dos decimales.

**Acciones de escritura:** ninguna.

---

## 5. Vehículos — `/vehicles`

**Para qué sirve.** Mantener la flota: alta, edición y baja de camiones, su capacidad, su
costo por km y cuál se usa para calcular el domicilio. **Quién la usa:** administración de
flota.

**Título:** «Vehículos». Texto de ayuda:
`Gestiona tu flota. Las tarifas se configuran globalmente en Configuración.`

### Controles de cabecera

- Buscador (placeholder `Buscar`) — filtra **en el cliente** por nombre y placa.
- Botón `Tipos de vehículo` → abre el cajón de tipos.
- Botón `Agregar Vehículo` → abre la ficha vacía.

### Tarjeta de vehículo (rejilla 1 / 2 / 3 columnas)

- Icono por tipo, nombre, placa en mono, insignia de estado: `Disponible` (verde) /
  `En uso` (azul) / `Mantenimiento` (ámbar).
- **Si el vehículo está dado de baja (`isActive = false`), insignia `Inactivo`** debajo
  (borde e icono de prohibido, sin relleno), aparte de la de estado: un camión puede estar
  libre y de baja (07/10/2026).
- Chip con el tipo.
- Si es el del cálculo del domicilio: chip `Cálculo domicilio` + `<importe>/km`.
  Si no: botón `Usar para domicilio`.
- Dos cajas: `Capacidad` = `<n> kg`; `Rutas` = nº de rutas.
- Si está `En uso` y tiene ruta activa: caja azul `Ruta activa` + nombre o código de ruta
  (respaldo: `sin nombre`).
- Línea `<n> órdenes asignadas`.
- Notas, si las hay.
- Botones: `Marcar disponible` (sólo si está `in_use`), `Editar`, `Eliminar`.

### Estados

- Cargando: `Cargando vehículos...`
- Sin ninguno: `Sin vehículos` + `Agrega tu primer vehículo para asignarlo a rutas` +
  botón `Agregar Vehículo`.

### Paginación

**25 por página** (cliente), con selector de tamaño `25 / 50 / 100` (`<n> / pág.`).

### Ficha de vehículo (cajón `lg`)

Título `Nuevo Vehículo` o `Editar Vehículo`. Campos:

| Etiqueta (literal) | Tipo | Defecto |
|---|---|---|
| `Nombre del Vehículo *` | texto, obligatorio, placeholder `Ej: Camión #1, Furgoneta Azul` | vacío |
| `Vehículo activo` | interruptor; subtítulo `Aparece en los selectores para crear rutas.` / `Se oculta de los selectores de rutas nuevas.` (07/10/2026) | encendido |
| `Tipo` | desplegable de tipos configurados (`nombre · $<costo>/km`) + `+ Crear tipo nuevo…` | `truck` |
| `Placa (opcional)` | texto en mayúsculas, placeholder `ABC-1234` | vacío |
| `Capacidad Máx. (kg)` | número ≥1 | `1000` |
| `Estado` | selector `Estado del vehículo`: `Disponible`=`available`, `En ruta`=`in_route`, `En mantenimiento`=`maintenance` | `available` |
| `Costo por km (USD)` | número, placeholder `1.65` | vacío |
| `Usar este vehículo para calcular el domicilio` + `Solo un vehículo por TIPO.` | casilla | desmarcado |
| `Notas (opcional)` | área de texto, placeholder `Información relevante del vehículo...` | vacío |

Al elegir un tipo **hereda su costo/km** (editable después).
Crear tipo en línea: `Nombre del tipo` (placeholder `Camión`) y `Costo por km (USD)`
(placeholder `1.65`); botones `Crear tipo` y `Cancelar`.

Ayudante plegable `¿No sabes el costo por km?`: `El camionero cobra (CUP)` (placeholder
`180000`) y `hasta ___ km (ida)` (placeholder `72`), botón `Calcular`, resultado
`= $<n>/km`, nota `Tipo de cambio: <n> CUP/USD. Se divide entre 2×km (ida y vuelta).`
Fórmula: `costo_km(USD) = cobroCUP / (2 × km × tasa)`. Tasa por defecto **320**.

Aviso azul: `Las tarifas de precios se configuran globalmente en Configuración.`
Botones: `Cancelar` y `Agregar Vehículo` / `Actualizar`.

### Cajón «Tipos de vehículo» (ancho `md`)

Texto: `Define cada tipo con su costo por km por defecto. Al crear un vehículo de ese tipo se hereda el costo/km (editable por vehículo).`
Tabla editable: `Nombre` | `Costo/km (USD)` | papelera (tooltip `Quitar`).
Vacío: `Sin tipos. Agrega el primero.` Botón `Agregar tipo`. Pie: `Cancelar` y `Guardar`.

### Endpoints y acciones

| Acción | Llamada |
|---|---|
| Listar | `GET /api/vehicles` (incluye `_count.routes`, `_count.orders` y la ruta activa) |
| Ajustes / tasa | `GET /api/settings` (ya no trae `tiposVehiculo`) |
| Tipos de vehículo | `GET /api/vehicle-types` (todos, retirados incluidos; junto a `/vehicles` y `/settings`: son TRES peticiones al abrir la pantalla) |
| Crear | `POST /api/vehicles` `{name, type, plate, capacity, status, notes, costoKmUsd, usarParaDomicilio}` |
| Editar | `PATCH /api/vehicles/<id>` con los mismos campos |
| Eliminar | `DELETE /api/vehicles/<id>` (en el reparto **pregunta antes**, en un cajón). Un vehículo con rutas, aunque sean históricas, **no se borra**: 409 `No se puede eliminar este vehículo porque tiene rutas asociadas, incluso históricas. Márcalo como inactivo para impedir que se use en nuevas rutas.` Se desactiva con el interruptor `Vehículo activo`. |
| `Usar para domicilio` | `PATCH /api/vehicles/<id>` `{usarParaDomicilio:true}` |
| `Marcar disponible` | `PATCH /api/vehicles/<id>` `{status:'available'}` (refresca también rutas) |
| Crear un tipo (desde la ficha del vehículo) | `GET /api/vehicle-types` (para ver los retirados) y después `POST /api/vehicle-types` `{nombre, costoKmUsd}`; si ya hay un tipo **retirado** con ese nombre se reactiva con `PATCH /api/vehicle-types/<id>` `{activo:true}` (y `costoKmUsd` sólo si se escribió uno: mandar `null` borraría el que tenía) en vez de chocar con el 409 `Ya existe un tipo de vehículo con ese nombre`. |
| Guardar tipos | El cajón **reconcilia tipo a tipo** contra `/api/vehicle-types` (`contratos-api.md`), partiendo de lo que tenía AL ABRIRSE: primero `DELETE /api/vehicle-types/<id>` de cada tipo quitado (un 404 es «ya estaba borrado»; si algún camión lo usa el servidor lo **retira**, `retirado:true`, no lo borra), luego `PATCH /api/vehicle-types/<id>` sólo con los campos que esa persona cambió (`nombre` y/o `costoKmUsd`; `null` vacía el costo) y `POST /api/vehicle-types` `{nombre, costoKmUsd}` por cada fila nueva (antes se vuelve a leer `GET /api/vehicle-types`: si el nombre ya existe activo no se repite y si está retirado se reactiva). **No es atómico**: una petición por tipo; si una falla cuando otras ya entraron, la pantalla dice «Se guardó sólo una parte». Ya **no** se manda `PUT /api/settings {tiposVehiculo}`: la API lo ignora (WARN) y los tipos se perdían en silencio hasta el 14/10/2026. Escribir tipos lo puede cualquier sesión de Reparto, también `LOGISTICO` (Jose, 14/10/2026). |

Desde el 07/10/2026 **sólo se ofrecen para una ruta nueva** (paso `Vehículo` del asistente y
`Camión previsto` de una zona) los vehículos **activos**; los inactivos se siguen viendo en
los filtros de rutas y en los informes. **Un vehículo en `maintenance` (en el taller) SÍ se
ofrece, con un aviso en ámbar** («en el taller»): es aviso, no bloqueo (decisión de Jose del
28/09/2026, restaurada en la 1.0.29: la 1.0.28 lo había quitado por error), porque una
sucursal con un solo camión olvidado en el taller se quedaría sin poder armar rutas.

Error del servidor al crear sin nombre: `Vehicle name is required` (400).
`GET/PATCH/DELETE` de un id inexistente: `Not found` (404).

---

## 6. Almacenes — `/warehouses`

**SOLO LECTURA desde el 20/10/2026 (decisión de Jose).** La matriz de almacenes pasa al
**CRM**; Reparto solo los **lee**. No hay crear, editar, eliminar, marcar principal ni
activar/desactivar, y no queda ningún botón ni menú de escritura (lo fija
`app/test/pantallas/almacenes/solo_lectura_test.dart`).

**Para qué sirve.** Ver el punto desde el que se mide cada domicilio y del que sale el
camión. **Quién la usa:** administración de sucursal y logística.

**Título:** «Almacenes». Texto:
`El punto desde el que se mide cada domicilio. Un almacén sin coordenadas no sirve para cotizar: la distancia se mide desde aquí.`

**Aviso fijo, arriba:** `Los almacenes se editan en el CRM. Aquí solo se consultan.`
Con enlace **«Abrir el CRM»**, que por defecto lleva a `https://crm.procovar.cloud/catalogos/almacenes`
(`Entorno.crmUrl`, se cambia con `--dart-define=CRM_URL=<url>`); **si `CRM_URL` se compila vacía, el aviso
sale sin enlace**, solo el texto.

### Controles

- Selector `Sucursal` (icono tienda) **sólo si hay más de una a la vista**; cada opción
  con la nota `<n>` o `sin almacenes`. Con una sola, se pinta su nombre sin desplegable.
- Nada más: ni botón `Nuevo almacén`, ni editor, ni selector de almacén.
- Aviso si la sucursal no tiene ninguno, **sin botón**:
  `Esta sucursal no tiene ninguno: sus domicilios no se pueden cotizar. Se dan de alta en el CRM.`

### Lista de almacenes

Una fila por almacén, **sin acción al pulsar**: icono estrella si es el principal, nombre
(o `(sin nombre)`), y debajo, separado por `·`, dirección (o `sin dirección`), las
coordenadas (o la marca `sin punto`), `código X` (o `sin código`), `principal` si lo es
e `inactivo` si no está activo.

Se repinta sola: pide la lista otra vez cuando llega el aviso en vivo `almacenes`
(el CRM avisa por el mismo canal) y, en la APK y el escritorio, con la bajada.

### Endpoints

- `GET /api/almacenes` → `{sucursales:[{codigo, nombre, almacenes:[{id, nombre, codigo,
  direccion, latitud, longitud, principal, activo}]}]}`. Es el único que usa la pantalla.
- `PUT /api/almacenes` **ya no existe** (se quitó del servidor el 20/10/2026: contesta 405). Los almacenes viven en Accesos y se editan desde el CRM.

**Errores visibles, literales:**
- Fallo al leer: `No se pudieron traer los almacenes de Accesos. Lo de abajo está vacío por eso, no porque no haya ninguno.`
- Sin conexión (APK y escritorio): `Sin conexión. Los almacenes se piden al servidor y ahora no hay con qué traerlos. Vuelve a intentarlo cuando haya red.`
- Sin respuesta (web): `Accesos no contesta. La página cargó, así que conexión hay: los almacenes se piden al servidor y ahora mismo no responde. Prueba otra vez y, si sigue igual, avisa a la oficina.`
- Sin sucursales: `No hay ninguna sucursal a la vista con código en Accesos.`
- Del servidor: `No se pudieron traer los almacenes de Accesos: <detalle>`, `Sin acceso a esa sucursal` (403).

**Paginación:** no tiene.

---

## 7. Reportes — `/reports`

**Para qué sirve.** Cuadrar lo repartido en un rango de fechas: totales, reparto por
vehículo y detalle factura a factura, con exportación a Excel. **Quién la usa:**
administración.

**Título:** «Reportes».

### Filtros

Bloque `Filtros`: `Desde` (fecha), `Hasta` (fecha), `Vehículo` (selector `Vehículo` con
opción `Todos los vehículos`), botón `Limpiar` (si hay algo puesto) y botón
`Exportar a Excel` (deshabilitado mientras carga o si no hay órdenes).
Sin valores por defecto: arranca sin rango y sin vehículo.

### Pestañas

`Resumen` (defecto) · `Por Vehículo` · `Detalle de Órdenes` (con el nº de órdenes en una
insignia). Cargando: `Cargando reporte...`

**Resumen** — cuatro tarjetas: `Total Órdenes`, `Ingresos Totales`, `Precio Promedio`,
`Peso Total` (`<n.n> kg`). Debajo, `Top vehículos`: las 3 primeras tarjetas con nombre,
placa e `<importe> · <n> órdenes`. Si no hay órdenes: `No hay órdenes para los filtros seleccionados.`

**Por Vehículo** — tabla:
`Vehículo` | `Placa` | `Órdenes` | `Ingresos` | `Peso Total` | `Promedio/Orden` | `Facturas`;
fila de pie `Totales` con la suma de órdenes, ingresos y peso (sin total de facturas: es una
lista de referencias, no una suma). `Facturas` (issue 9 de Amado) dice las DOS primeras
facturas del camión y cuántas quedan fuera —`PTB25-261005-1479, F-000777 y 1 más`— y, aparte,
cuántas de sus facturas no tienen número —`· 1 sin número`—; la lista entera está en el Excel.
Un número que se repite en dos filas (la ida y la vuelta) cuenta una vez; las `Órdenes` y los
totales no se mueven.
Vacío: `No hay datos de vehículos para los filtros seleccionados.`

**Detalle de Órdenes** — tabla:
`Fecha` | `Factura` | `Cliente` | `Ruta` | `Destino` | `Vehículo` | `Peso` | `Precio`;
fila de pie `Totales:` con peso total (`<n.n> kg`) e importe total. `Factura` (issue 9 de
Amado) es el número de la factura —ver «El número de factura de los reportes» en `reglas-negocio.md`
§15.13—; sin número, la raya `—`, nunca en blanco.
Vacío: `No hay órdenes para los filtros seleccionados.`

### Endpoints

- `GET /api/vehicles` — para el selector.
- `GET /api/reports?from=&to=&vehicleId=` — `{orders[], summary:{totalOrders, totalRevenue,
  totalWeight, avgPrice}, byVehicle:[{name, plate, count, revenue, weight, invoiceNumbers,
  withoutInvoice}]}`; cada `orders[]` lleva además `invoiceNumber` (`null` si no tiene).
  El rango se aplica sobre `createdAt`; `to` incluye el día entero.
  **Ingreso de una factura = `price` si lo tiene, si no `pedidoCosto`.**

### Exportación a Excel

Fichero `reporte-procovar-AAAA-MM-DD.xlsx`, tres hojas:
1. **`Resumen`**: `Reporte de transportación — ProCovar`; `Generado` + fecha y hora;
   `Filtro fecha` = `<desde|—> - <hasta|—>`; `Moneda` = código; luego `Total Órdenes`,
   `Ingresos Totales (<MONEDA>)`, `Precio Promedio (<MONEDA>)`, `Peso Total (kg)`.
2. **`Por Vehículo`**: `Vehículo`, `Placa`, `Órdenes`, `Ingresos (<MONEDA>)`, `Peso (kg)`,
   `Promedio/Orden (<MONEDA>)`, `Facturas` (la lista ENTERA de los números del camión,
   separados por coma; con un techo de 30.000 letras por celda —Excel no abre una celda de más
   de 32.767— y, si se llega, se corta por números enteros diciendo `y N más`).
3. **`Detalle de Órdenes`**: `Fecha`, `Factura`, `Cliente`, `Ruta`, `Destino`, `Vehículo`,
   `Km desde partida`, `Peso (kg)`, `Precio (<MONEDA>)`.

Los importes se convierten a la moneda mostrada y se redondean a 2 decimales; los pesos a
1 decimal.

**Paginación:** no tiene; la tabla de detalle sale entera.
**Acciones de escritura:** ninguna.

---

## 8. Navegación

### 8.1 `Sidebar.tsx` — barra lateral

Ancho 256 px, alto completo, fija a la izquierda. Cabecera: logo (camión) + `ProCovar` y,
debajo, `Plataforma de Delivery`.

Entradas, en este orden (la activa lleva fondo tenue, texto en color primario y una barra
vertical a la izquierda):

| Ruta | Etiqueta | Icono |
|---|---|---|
| `/dashboard` | `Panel` | `mdi:view-dashboard-outline` |
| `/routes` | `Rutas` | `mdi:map-marker-path` |
| `/facturas` (`/orders` redirige) | `Facturas` | `mdi:package-variant-closed` |
| `/customers` | `Clientes` | `mdi:account-multiple-outline` |
| `/vehicles` | `Vehículos` | `mdi:truck-outline` |
| `/warehouses` | `Almacenes` | `mdi:warehouse` |

**Reportes NO está en el menú**: la pantalla existe y se llega por URL (y desde las
acciones rápidas del panel). Tampoco hay Productos, Sucursales ni Configuración.
Abajo no hay nada de la cuenta: cerrar sesión y cambiar de aplicación viven en el avatar.

**Móvil:** por debajo de 1024 px la barra está fuera de pantalla; se abre con el botón de
menú de la barra superior, se superpone con un velo oscuro, pulsar fuera cierra y **se
cierra sola al cambiar de pantalla**.

### 8.2 `Navbar.tsx` — barra superior

Alto 64 px, pegajosa arriba. Izquierda: botón de menú (**sólo en móvil**), título de la
pantalla y, mientras haya cualquier consulta en vuelo, `actualizando…` con un giro.

Derecha:
1. **Sucursal.** Con varias: selector `Sucursal que se está mirando`, opción
   `Todas las sucursales (<n>)`, cada sucursal con su código como nota. Al cambiarla se
   invalidan todas las consultas (no se recarga la página). Con una sola: etiqueta fija
   `Nombre (CÓDIGO)`. Con ninguna: no se pinta nada.
   Si la sucursal guardada ya no está entre las visibles, se olvida.
2. **Idioma** (`Idioma`): `Español`/`ES`, `English`/`EN`. **Se oculta por debajo de 640 px.**
3. **Moneda** (`Moneda de visualización`): USD y las que tengan tasa; cada una con la nota
   `1 USD = <tasa>`. Sin tasa se pinta `USD` fijo, con borde ámbar y el motivo en el
   tooltip.
4. **Avatar** → menú de cuenta (quién eres, ir a otra aplicación, salir).

---

## 9. Componentes a rehacer

### 9.1 `CierreDeRuta.tsx` — el cierre parada por parada

**Para qué.** El camión vuelve y hay que cuadrar lo que baja. Se marca **cada parada** y
de ahí sale el post-despacho. Se abre desde el detalle de la ruta con el botón `Cierre`,
disponible en rutas `in_progress` **y** `completed`.

Va en un cajón de ancho `xl`. Título `Cierre de ruta`; subtítulo `<código/nombre> · <n> parada(s)`.

Texto de cabecera (literal):
> `Marca cada parada según cómo acabó. De aquí sale el post-despacho: lo que tiene que quedar en el camión es todo lo que no se entregó. Lo devuelto y lo cancelado no tocan el inventario —eso lo hace Ventra—: aquí queda la constancia y el control de lo que baja.`

Fila de atajos: `Todas:` + botones `Entregado`, `Devuelto`, `Cancelado` (marcan todas de
golpe). Si quedan sin marcar:
`<n> sin marcar · cuentan como que siguen en el camión`.

Por cada parada: número de orden (`stopOrder`, respaldo el índice + 1), cliente,
dirección, y tres botones de resultado — `Entregado` (verde), `Devuelto` (rojo),
`Cancelado` (gris). **Pulsar el mismo botón dos veces desmarca.**
Si el resultado es `Devuelto` o `Cancelado` aparece un campo de motivo, placeholder:
`¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)` (máx. 500 caracteres
al guardar).

Bloque de vista previa `Queda en el camión`: chips `producto ×<empaques>` con lo que no se
entregó, recalculado en vivo. Vacío: `Nada: se entregó todo lo que salió.`

Pie: `Post-despacho` (abre la hoja, §10.2), `Cerrar`, y
`Guardar <n> marcada(s)` (deshabilitado con 0 marcadas; mientras guarda: `Guardando…`).

**Al abrir** se parte de lo ya guardado en cada parada (resultado y nota).

**Endpoint:** `POST /api/routes/<id>/results` con
`{resultados:[{orderId, resultado, nota}]}`, `resultado ∈ {entregado, devuelto, cancelado}`.
Efectos por factura: guarda `resultado`, `resultadoAt`, `resultadoNota`; `deliveredAt` sólo
si se entregó; `status` = `delivered`/`pending`; y **lo que no se entrega suelta su
`routeId`** para poder ir en la ruta de mañana (`ultimaRutaId` y `stopOrder` se conservan).
Además avisa a PEDIDO del estado de cada pedido espejado.

**Mensajes:** éxito → `Cierre guardado. En PEDIDO cada pedido ya dice si se entregó o volvió.`
Errores → `No vino ningún resultado` (400), `No encontrada` (404), respaldo
`No se pudo guardar el cierre`. Rechazos por factura: `esa factura no va en esta ruta`,
`resultado '<x>' desconocido`.

**Cierre parcial (409 con `aplicados` y `rechazados`), sólo en la WEB** (1.0.29, antes era
un aviso de 8 s que se iba solo). Se guarda lo bueno y se completa la ruta con eso, y se
abre un cajón de acuse (`abrirCajon`, ancho `md`) que **obliga** a pulsar el único botón,
`Entendido` (icono de doble visto): la ✕, el velo, `Escape` y el atrás no cuentan y el cajón
vuelve a salir. Título al completar `Ruta completada: <n> paradas no se guardaron` (con una:
`Ruta completada: 1 parada no se guardó`); si sólo se guardaba, sin el prefijo. Subtítulo
`El resto del cierre sí quedó guardado.` (completando) o `El resto del cierre sí se guardó.`
Texto: `Estas paradas se quedaron sin resultado. Apunta su conduce y corrígelas en PEDIDO.` o,
si sólo se guardaba, `Estas paradas siguen marcadas aquí pero el servidor no las guardó.
Corrige la marca y vuelve a guardar.` Una línea en negrita por parada:
`Conduce <número de operación>: <motivo literal del servidor>` (si la factura no trae número
de operación, sale su id interno). Al acusar: completando, se cierra la hoja y se va al
Historial; sólo guardando, la hoja se queda abierta con las rechazadas aún marcadas y
contadas como sin guardar. Sin ninguna guardada no hay cierre parcial: es rechazo total y
no se completa. En la APK y el escritorio no existe: el sincronizador rechaza el apunte
entero (ver `sincronizacion.md`).

### 9.2 `Drawer.tsx` — el patrón cajón

Panel que entra deslizándose **por la derecha**, a alto completo, sobre un velo negro al
40 %. Estructura fija: cabecera (título en negrita + subtítulo pequeño + botón de cerrar
con `aria-label` `Cerrar`), cuerpo **desplazable**, y pie opcional pegado abajo con los
botones de acción **siempre a la vista**.

Anchos en pantalla grande: `md` = 448 px, `lg` = 672 px, `xl` = 896 px, `completo` = todo
el ancho. **En móvil siempre ocupa la pantalla entera.**

Comportamiento: `Escape` cierra; pulsar el velo cierra; mientras haya algún cajón abierto
el fondo no se desplaza — **y el bloqueo se lleva por contador**, porque con dos cajones
montados a la vez el segundo dejaba la página bloqueada para siempre al cerrarse.
Animación de entrada: 180 ms, desde 24 px a la derecha.

**Excepción de la casa:** esta aplicación usa cajón también en escritorio (decisión de
05/09/2026). No hay variante modal.

Usos: detalle de factura (`lg`), asistente de ruta (`completo`, con pie), cierre de ruta
(`xl`, con pie), ficha de vehículo (`lg`), tipos de vehículo (`md`). (El editor de almacén
(`lg`, con pie) se quitó el 20/10/2026: Almacenes es de solo lectura.)

### 9.3 `RouteSummaryCard.tsx`

Tarjeta resumida de una ruta: nombre, insignia de estado (colores: `planned` ámbar,
`in_progress` azul, `completed` verde; el texto es el estado con el guion bajo sustituido
por un espacio) y una rejilla de 2×2 con las etiquetas **en inglés, sin traducir**:
`Stops` (nº de facturas), `Distance` (`<n.n> km`), `Weight` (`<n.n> kg`), `Revenue`
(`$<n.nn>`). Es clicable. **Hoy no lo usa ninguna pantalla** (la lista de rutas pinta su
propia tarjeta); en Flutter sólo merece la pena si se reutiliza, y entonces con las
etiquetas en español.

### 9.4 `CustomerPicker.tsx`

Caja de búsqueda de clientes con desplegable. Placeholder:
`Buscar cliente (de PEDIDO, con geolocalización)…`
Sin texto: los 8 primeros bajo el encabezado `Clientes`. Con texto: hasta 30 coincidencias
por nombre, dirección o municipio, bajo el encabezado `Resultados`.
Cada fila: nombre + `dirección · municipio` (o `Sin dirección`) y un icono verde de punto
confirmado. Al elegir devuelve el cliente completo (con lat/lng) y limpia la caja.
Estados: `Cargando…`; sin nada:
`No hay clientes geolocalizados todavía (se sincronizan solos desde PEDIDO).`;
sin coincidencias: `Sin resultados.`
**Endpoint:** `GET /api/customers` (usa `data.customers`).

### 9.5 `ProductPicker.tsx`

Caja de búsqueda de productos. Placeholder `Buscar producto...`.
Sin texto: los **5 más usados**, bajo el encabezado `Más usados` con icono de llama.
Con texto: hasta 30 coincidencias por nombre, grupo o empaque, bajo `Resultados`.
Orden: por `usageCount` descendente y luego por nombre.
Cada fila: nombre, `<empaque> · <grupo>` y a la derecha `<peso> kg`.
Vacío: `Sin resultados`.
**Endpoint:** `GET /api/products` o `GET /api/products?sucursal=<código>` — el catálogo es
por sucursal (precio y existencias varían).

### 9.6 `Selector.tsx` (desplegable con buscador)

No es un `<select>` del sistema: es un botón que abre un menú posicionado contra el borde
del botón. Muestra caja de búsqueda **a partir de 4 opciones** (configurable; en el
vendedor del armador de rutas se fuerza a mostrarla siempre). Cada opción tiene etiqueta y
una **nota** pequeña a la derecha (un conteo, un código). La opción «todos» es la primera
y su texto lo pone cada pantalla. Soporta icono dentro del botón.

### 9.7 `Pagination.tsx`

Barra al pie: `Mostrando <desde>–<to> de <total>`, selector de tamaño opcional
(`25 / pág.`, `50 / pág.`, `100 / pág.`), y botones primera (`«`), anterior (`‹`), hasta
**5 números** alrededor de la actual, siguiente (`›`), última (`»`). No se pinta si el
total es 0. Tamaños por lista: facturas **50 fijo** (servidor), clientes **50** (servidor,
controles propios), vehículos **25** (cliente, cambiable), rutas **20** (cliente).

---

## 10. Lo que sale IMPRESO (hay que rehacerlo como PDF)

Ambas hojas se abren hoy en una ventana nueva de 900×700 con HTML propio y **no lanzan el
diálogo de impresión**: la hoja se revisa primero y se imprime desde su propio botón.
Botones flotantes abajo a la derecha, que **no se imprimen**: `Imprimir` y `Cerrar`.
Márgenes: 24 px en pantalla, **12 mm al imprimir**. Tipografía de sistema, 13 px / 1.4.
En Flutter: generar el PDF y ofrecer vista previa + imprimir/compartir.

### 10.1 Pre-despacho (`src/lib/imprimirPreDespacho.ts`)

**Qué es:** la hoja con la que alguien baja al almacén a sacar mercancía.
**Quién la dispara:** la pantalla de Facturas (marcados y filtrados) y el paso 4 del
asistente de rutas.

Datos de entrada: `sucursal`, `vehiculo`, `dia` (`AAAA-MM-DD`, opcional), `pedidos`
(número), `pesoKg`, y `lineas[] = {producto, formatos, unidades, pesoKg}`.

**Estructura del documento:**

1. Cabecera a dos lados.
   - Izquierda: título `Pre-despacho` (20 px, negrita); debajo `<sucursal>` y, si hay
     vehículo, ` · <vehículo>`; debajo, si hay día, `Facturas del <AAAA-MM-DD>`.
   - Derecha: `<n> factura(s)`, **`Peso de las facturas <n.n> kg`** y la fecha y hora
     de impresión (`toLocaleString('es')`).

     El rótulo de ese kg **es nuestro, no de Next** (23/09/2026): era el último
     peso sin rótulo de la hoja, y con el pie de la tabla ya corregido habría
     quedado un `29835.4` arriba contra un `—` abajo sin nada que lo explicara.
2. Tabla a todo el ancho, cabecera con fondo gris claro, versalitas en mayúsculas:

   | `Producto` | `Empaques` | `Unidades` | `kg` | `Sacado` |
   |---|---|---|---|---|
   | nombre | derecha | derecha | derecha, 1 decimal, `—` si es 0 | **columna vacía de 70 px para marcar a mano** |

   Filas con línea inferior fina.
3. Pie de tabla (negrita, línea superior gruesa): `Total` | suma de empaques | suma de
   unidades | **la suma de ESA columna** con 1 decimal | vacío.

   **Aquí nos separamos de Next, y es la separación que más importa de esta hoja**
   (23/09/2026). La de Next imprime ahí `pesoKg`, que es el peso **de las
   facturas**, mientras que cada línea imprime el peso **por producto** del
   catálogo: misma columna, misma unidad, dos cuentas distintas y nada que lo
   diga. En producción se vieron **diez guiones encima de un total de 29.835,4**,
   y quien cuadra el camión resta esas dos cifras a ojo. Ahora el pie suma la
   columna con la misma regla que las líneas: si una celda imprime `—`, el total
   imprime `—`. El porqué entero está sobre `TotalesPreDespacho` en
   `app/lib/impresion/hoja.dart`.
4. **Los dos pesos, cada uno con su rótulo** — el bloque que la hoja de Next no
   tiene, palabra por palabra igual que `TotalesDelPreDespacho` de la pantalla:

   ```
   Peso de los productos    300.0 kg      (o «1 de 3 productos sin peso»)
   Peso de las facturas     412.5 kg
   No son el mismo número: el de arriba lo pone el catálogo producto a producto,
   y el de abajo viene en cada factura.
   ```

   Los tres literales están **atados a los de la pantalla con una prueba**, no con
   un comentario (`app/test/impresion/los_dos_pesos_del_pre_despacho_test.dart`),
   que es la regla del §3-bis del `CLAUDE.md`.
5. **`Por producto y factura` (issue 8 de Amado, hecho el 14/10/2026 y rehecho el 15/10/2026 con
   la hoja que Amado adjuntó; no existe en Next).** Sólo si la hoja sabe de qué factura sale cada
   cosa —la que se imprime desde el detalle de una ruta; la de Facturas no la lleva—. La tarjeta de
   estiba es por producto y sus salidas se rebajan por cantidad **y factura**: de 20 blister, 10 son
   de una factura y 10 de otra. Título `POR PRODUCTO Y FACTURA` y una tabla con **un bloque por
   producto** (en el orden de la tabla de arriba: más empaques primero y, a igualdad, por nombre),
   **una fila por factura** que lo lleva (por número; `Sin número` al final del bloque) y el
   **subtotal del producto** en negrita, sin total general (lo da la tabla de arriba):

   | `Factura` | `Producto` | `Cant.` | `Kg` |
   |---|---|---|---|

   Sin columna de unidades (Amado no la pone). `Cant.` son empaques. La fila del subtotal dice
   `Subtotal` en la columna de la factura y deja el producto en blanco. Las columnas se cambian en
   **un solo sitio**, la lista `columnasPorProductoYFactura` (`app/lib/impresion/por_producto_y_factura.dart`),
   que leen la pantalla (`tabla_por_producto_y_factura.dart`; bajo 640 px, una tarjeta por producto)
   y este PDF. La factura es `orders.factura_numero` (`NumeroDeFactura.de`): sin él, `Sin número`,
   nunca el folio; un pedido con dos facturas lleva las dos en su fila. Cada cifra sigue la regla de
   la tabla de arriba (`≥` si falta algún renglón, `—` si no se sabe, el cero no es un peso), y una
   factura sin renglones sale al final como `Sin renglones`.
6. Firmas, dos huecos con línea superior: `Sacó del almacén` · `Recibió (chofer)`.

Las líneas vienen ya ordenadas de más a menos empaques. Los caracteres `& < > "` se
escapan.

### 10.2 Post-despacho (`src/lib/imprimirPostDespacho.ts` + `armarPostDespacho.ts`)

**Qué es:** la cuenta de lo que tiene que **quedar en el camión** al volver, para contarlo
contra lo que de verdad baja. **Quién la dispara:** el botón `Post-despacho` del cierre de
ruta, con lo marcado en ese momento (aunque todavía no se haya guardado).

**Cómo se calcula (`armarPostDespacho`):** por cada parada se toman sus líneas; el número
de una línea son sus **empaques (`packs`)** y, si no los trae, sus **unidades
(`quantity`)** — nunca cero. Por producto:
- `salio` = todo lo que se cargó (todas las paradas).
- `entregado` = lo de las paradas marcadas `entregado`.
- `queda` = **todo lo demás: lo devuelto, lo cancelado y lo que nadie marcó.**
Las líneas se ordenan por `queda` descendente y luego por nombre. Se cuentan
`entregadas`, `devueltas`, `canceladas` y `sinMarcar`. Se guarda además la lista de
paradas **no entregadas** con su cliente, resultado, nota y productos.

**Estructura del documento:**

1. Cabecera a dos lados.
   - Izquierda: título `Post-despacho`; debajo `<ruta> · <sucursal>` y, si hay vehículo,
     ` · <vehículo>`; debajo, si se sabe, `Salió <fecha y hora>` y ` · volvió <fecha y hora>`.
   - Derecha: fecha y hora de impresión.
2. Fila de píldoras: `<n> entregada(s)`, `<n> devuelta(s)`, `<n> cancelada(s)` y, si las
   hay, `<n> sin marcar`.
3. Sección `TIENE QUE QUEDAR EN EL CAMIÓN` (los títulos de sección van en mayúsculas):

   | `Producto` | `Salió` | `Entregado` | `Queda` | `Bajó` |
   |---|---|---|---|---|
   | nombre | derecha | derecha | derecha, **en negrita** | **columna vacía de 78 px para marcar a mano** |

   **Sólo se listan los productos con `queda > 0`.** Un producto entregado entero no sale.
   Pie de tabla (negrita, línea gruesa): `Total` con la suma de `Salió`, `Entregado` y
   `Queda` **de las filas mostradas**, y la última celda vacía.
   Si no queda nada: `Nada: se entregó todo lo que salió.` (en cursiva gris).
4. Sección `DE QUIÉN ES LO QUE VUELVE`: una entrada por parada no entregada, con el
   nombre del cliente y una etiqueta pequeña — `Devuelto` (fondo rosa), `Cancelado`
   (fondo gris) o `Sin marcar` (fondo ámbar) —; debajo la nota en cursiva gris, si la hay;
   y debajo los productos como `producto × <n>` separados por ` · ` (o `—`).
   Si no hay ninguna: `Todas las paradas se entregaron.`
5. Firmas, dos huecos: `Entregó (chofer)` · `Recibió en almacén`.

---

## 11. Diferencias entre móvil y escritorio

| Sitio | Escritorio (≥1024 px) | Móvil |
|---|---|---|
| **Cajón/modal** | Cajón lateral derecho, ancho `md/lg/xl/completo`. **Excepción de la casa: aquí también es cajón, no modal.** | Cajón a pantalla completa |
| Barra lateral | Fija, siempre visible, contenido desplazado 256 px | Fuera de pantalla; botón de menú + velo; se cierra sola al navegar |
| Idioma en la barra | Visible | **Oculto** (<640 px); sucursal y moneda se quedan |
| Rutas (armazón) | Alto fijo a la ventana, sin desplazamiento de página; la lista y el detalle se desplazan por dentro; 3 columnas (1 lista + 2 detalle) | La página se desplaza como cualquier otra; una sola columna; **sin** desplazamiento interno (evita el doble scroll) |
| Rutas, paso 4 | Dos columnas: facturas + pre-despacho pegajoso a la derecha | Una columna, pre-despacho debajo |
| Tabla de Facturas | 13 columnas, la primera `Factura` | Se esconden por orden de prescindibilidad: `Sucursal` bajo 1536 px; `Ruta` bajo 1280 px; `Artículos` y `Factura` bajo 1024 px; `Entrega` bajo 768 px. **Nunca se van:** cliente, dirección, peso, precio y estado |
| Tabla de Clientes | Completa | Se desplaza **la tabla**, no la página (ancho mínimo 736 px) |
| Vehículos | Rejilla de 3 columnas (2 en tabletas) | 1 columna; el grupo buscador + 2 botones **envuelve** en vez de salirse |
| Rutas, cabecera | Título, 3 pestañas y botón en una fila | Envuelve; las pestañas se desplazan de lado sin partir palabras |
| Menús de Selector | Menú anclado al botón | Igual, pero con buscador desde 4 opciones (ayuda más con el teclado del teléfono) |
| Tablas del pre-despacho | Normales | Desplazamiento horizontal propio: sin él empujan la página entera de lado |
