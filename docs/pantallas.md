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
| `Pedidos sin ruta` | `sinRuta` | `<pesoPendiente redondeado> kg por mover` |
| `Rutas en marcha` | `rutasActivas` | — |
| `Entregados hoy` | `entregadosHoy` | — |
| `Vehículos` | `<vehiculosEnRuta> / <totalVehicles>` | `en ruta / total` |

La tarjeta «Pedidos sin ruta» se pinta en ámbar cuando el valor es > 0; si es 0, en color
primario. Cifras con 0 por defecto mientras carga.

### Tarjeta «Pendiente por sucursal»

Lista, una fila por sucursal, con tres columnas sin cabecera: nombre de la sucursal ·
`<pesoKg redondeado> kg` · número de pedidos. Ordenada de más a menos pedidos.
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
  `routeId = null` **y** `endLat` no nulo **y** `facturaEstado ∈ {igual, cambiado}`.
- `entregadosHoy` = pedidos con `deliveredAt` desde las 00:00 de hoy.
- `totalDomicilios` = suma de `pedidoCosto` (lo cobrado en PEDIDO, no la estimación de
  delivery).

**Acciones:** ninguna de escritura; sólo navegación. **Paginación:** no tiene.

---

## 2. Pedidos — `/orders`

**Para qué sirve.** El catálogo de pedidos espejados de PEDIDO: buscar uno, ver su ficha,
y sobre todo **sumar el pre-despacho** (cuánto sacar del almacén) de lo filtrado o de lo
marcado a mano. **Quién la usa:** despacho y almacén. **No se crean pedidos aquí**: el
alta manual se retiró el 03/09/2026 (`POST /api/orders` ya no existe).

**Título:** «Pedidos». Subtítulo: `Todos los pedidos acumulados de todas las rutas`.

### Arranque acotado (importante)

La lista **arranca filtrada** a lo que puede subir a un camión: `factura=con_factura` y
`archivado=0`. Mientras esos dos sigan exactamente así se muestra una franja azul:

> `Enseñando sólo lo que puede subir a un camión: lo que tiene factura —cuadre o no— y sin archivar. Lo que cambió también sube: se carga con las líneas de la factura, no con las del pedido.`

con el botón `Ver todos los pedidos`, que pone ambos filtros a vacío.

Debajo, el conteo: `<total> pedidos`; si hay fechas puestas añade
` · del <desde> al <hasta>` (o `del <fecha>` si coinciden, `desde el <x>`, `hasta el <x>`)
y siempre `, del más nuevo al más viejo`. Indicador giratorio mientras refresca.

### Filtros y controles (valores por defecto entre paréntesis)

| Control | Título (literal) | Opción «todos» | Opciones | Parámetro |
|---|---|---|---|---|
| Selector | `Estado de reparto en delivery` | `Cualquier reparto` (por defecto) | `Sin entregar`=`sin_entregar`, `En despacho`=`en_despacho`, `En ruta`=`en_ruta`, `Entregado`=`entregado`, `Devuelto o cancelado`=`devuelto` | `reparto` |
| Selector | `Municipio del cliente` | `Todos los municipios` (defecto) | de facetas, con el nº de pedidos como nota | `municipio` |
| Selector | `Precio del domicilio` | `Cualquier precio` (defecto) | `Con precio puesto`=`1`, `Sin cotizar`=`0` | `cotizado` |
| Selector | `Vendedor del pedido` | `Todos los vendedores` (defecto) | de facetas, con nº de pedidos | `vendedor` |
| Dos fechas | tooltip `Desde (fecha del pedido)` / `Hasta (fecha del pedido)` | vacías | `desde` acota el `max` de `hasta` y viceversa | `desde`, `hasta` |
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
  filtrado; se pide **sólo al abrir el desplegable**. Si el total supera **5000** pedidos
  devuelve `resumen: null`.
- `GET /api/orders/facetas` — `{ municipios:[{valor,pedidos}], vendedores:[...],
  sucursales:[{valor,nombre,pedidos}] }`. Se cachea 10 minutos.

Semántica de los filtros en el servidor (compartida con el armador de rutas):
`q` busca en cliente, folio, dirección de entrega, dirección, municipio, vendedor y en el
texto de productos. `factura`: `con_factura` = `igual|cambiado`; `cuadra` = sólo `igual`;
`sin_cotejar` = `facturaEstado` nulo. `reparto=sin_entregar` = sin ruta, sin `deliveredAt`
y sin resultado `entregado`.

### Pre-despacho de LO ELEGIDO (tarjeta, sólo si hay marcados)

Cabecera: `<n> pedido(s) elegidos` · `<n> producto(s) · <n> empaques · <kg> kg`.
Si hay marcados fuera de la página actual: `(<n> en otras páginas, sin sumar)`.
Botones: `Ver e imprimir` (abre el pre-despacho, ver §10) y `Quitar la marca`.
Tabla: `Producto` | `Empaques` | `Unidades` | `kg` (kg vacío se pinta `—`).
Se calcula en el cliente sobre las líneas que ya vinieron con los pedidos de la página.

### Pre-despacho de LO FILTRADO (bloque plegable)

Título: `Pre-despacho de lo filtrado` + `· <n> producto(s) · <n> empaques · <kg> kg`.
Botón `Ver e imprimir`. Mismas 4 columnas.
- **Cuando el servidor no puede sumarlo:**
  `Son demasiados pedidos para sumarlos. Acotá por día o sucursal y sale.`

#### Los números que NO se enseñan — 22/09/2026

Con el mismo filtro, la franja decía `10 producto(s) · 3185 empaques · 0.0 kg` y la hoja
imprimible decía `264 pedido(s) · 24891.0 kg`. Los dos eran ciertos cada uno en su
definición —uno suma el peso resuelto **por producto**, el otro el del **conjunto de
pedidos**— y juntos sólo pueden hacer una cosa: que quien carga el camión se crea que no
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

La **cabecera de la hoja no cambia**: el peso del conjunto de pedidos sí se sabe entero, así
que sigue siendo un número siempre.

En el **móvil** el bloque no cuelga debajo de la lista: se abre en su **cajón** desde un
botón que dice cuántos pedidos van contados. Debajo de la lista había que bajar por
doscientos y pico pedidos peleándose con dos desplazamientos, con el pie fijo tapando el
final — «y el pre-despacho, que no lo veo».

### Tabla de pedidos

Columnas por orden (la etiqueta literal es la que se pinta):

1. **Casilla** de selección. La de la cabecera marca/desmarca toda la página
   (`aria-label`: `Elegir todos los de esta página`). No abre el pedido.
2. `Fecha` — fecha del pedido; si falta `orderDate` se pinta la de copiado con un `≈`
   y el tooltip `Pedido copiado antes de que se guardara su fecha: ésta es la del espejo.`
3. `Sucursal` — **sólo si no hay sucursal elegida arriba**; se oculta bajo 1536 px.
4. `Pedido` — insignia de estado EN PEDIDO: `Completada` (verde) / `Expirada` (roja, si
   `fechaComprometida` ya pasó) / `En proceso` (ámbar). Icono de archivo con tooltip
   `Archivado en PEDIDO` si procede; y debajo `sin domicilio` si `requiereDomicilio=false`.
5. `Cliente` — nombre + nº de operación (folio) en mono.
6. `Ruta` — código de ruta en insignia azul o `—`. Oculta bajo 1280 px.
7. `Artículos` — primer producto `×<empaques>` y `+<n>` con desplegable al pasar el ratón
   (en Flutter: tocar para abrir). Oculta bajo 1024 px.
8. `Dirección` — `endAddress` o `address`.
9. `Peso` — `<n> kg`, alineada a la derecha.
10. `Precio` — **`pedidoCosto`** (lo que cobró Entrega), no el precio interno. Si no hay:
    `sin cotizar` en gris.
11. `Factura` — `igual` → nº de factura en verde, tooltip
    `Cuadra con lo pedido: se puede repartir tal cual.`; `cambiado` → nº + `⚠` en ámbar,
    tooltip `Se facturó algo distinto de lo pedido. No puede ir en una ruta hasta que se corrija.`;
    `sin_factura` → `sin facturar`; nulo → `sin cotejar` con tooltip
    `El cotejo contra Ventra no ha pasado por este pedido todavía.` Oculta bajo 1024 px.
    **Con factura `igual` o `cambiado`, junto al número, una segunda marca con el cobro del
    domicilio** (Amado, 08/10/2026: «en la tabla no está claro qué pedidos han sido facturados
    y cobrados»): `Dom. $0.46` en verde, con el importe, cuando `facturaDomicilio > 0`; y
    `Sin cobro de domicilio` en ámbar cuando es nulo o 0, con el tooltip `La factura no trae la
    línea ENTREGA A DOMICILIO: este pedido no puede ir a una ruta ni a una zona del tablero
    hasta que el domicilio se cobre en la factura.` Con `sin_factura` o nulo no se añade nada.
    Es la regla del 07/10 hecha visible: sin esa línea el pedido no entra en una ruta ni en
    una zona. **El ámbar sólo sale si ése es lo que frena al pedido** (se le pregunta a
    `porQueNoSePuedeColocar`, no se repite la regla): con ruta, entregado o archivado
    lleva sólo el número, o el `Dom.` verde si hay cobro; un devuelto o cancelado sí lleva el
    ámbar, porque se puede reasignar. En el móvil (tarjeta) la marca va dentro de la
    tarjeta, junto al número.
12. `Entrega` — estado de reparto calculado: `Devuelto` / `Cancelado` (ámbar),
    `Entregado` (verde), `En ruta` (azul), `En despacho` (índigo), `Sin entregar` (gris).
    Oculta bajo 768 px.
13. Chevron. La fila entera abre el detalle.

**Sin columna `Vehículo`** (Amado, 08/10/2026, «elimínala para más espacio»): desde la 1.0.28
`orders.vehicle_id` no existe y la celda era un marcador mudo. El camión de un pedido sigue
viéndose en el **detalle**, en la sección `Ruta`, porque sale de su ruta.

**Regla de estado de reparto:** manda `resultado` de la parada, **no** el estado de la
ruta. Una ruta completada no convierte en «entregado» un pedido devuelto.

### Estados vacíos y carga

- Cargando: `Cargando...`
- Sin resultados: sin filtros, `Aún no hay pedidos de esta sucursal.`; con algún filtro
  puesto, `Ningún pedido cuadra con estos filtros.` y debajo el botón `Quitar todos los
  filtros` (limpia **todos**, incluidos los del arranque). Son dos frases distintas a
  propósito: con un filtro que no casa, «aún no hay pedidos» es mentira (25/09/2026).

### Paginación

Componente de páginas al pie: `Mostrando <desde>–<hasta> de <total>`, botones
primera/anterior/números (ventana de 5)/siguiente/última. **50 por página, fijo.**

### Detalle del pedido (cajón, ancho `lg`)

Título = nombre del cliente, subtítulo = folio. Secciones:

- `Entrega`: dirección, coordenadas `lat, lng` con enlace `ver mapa` a Google Maps,
  teléfono.
- `Recorrido`: mapa de 220 px con dos puntos, almacén (origen) → cliente. Pie:
  `Del almacén (<nombre>) al cliente.`
- Banda de factura según `facturaEstado`:
  - `Cuadra con la factura <nº> de Ventra: se puede repartir tal cual.`
  - `Se facturó algo distinto de lo pedido (factura <nº>). Lo que va en el camión es lo facturado.`
  - `Todavía no aparece facturado en Ventra.`
  - Y si hay línea de domicilio: `La factura cobró <n.nn> USD de domicilio.`
- `Domicilio` (caja verde si hay precio, ámbar si no): `Distancia` (`<n.nn> km` o `—`),
  `Peso total` (`<n.nn> kg`), y a la derecha el importe o `Sin calcular todavía`.
  Nota al pie: `El costo lo puso el repartidor desde Entrega. La distancia es del almacén al cliente.`
  / `El costo lo pone el repartidor desde Entrega; hasta entonces este pedido no tiene precio de domicilio.`
- `Productos (<n>)`: por línea, nombre, `<n> unidades`, ` · <n.nn> kg/empaque`,
  `×<empaques> empaques` y el peso de la línea; si no hay peso resuelto: `sin peso`.
  Vacío: `Sin productos`.
- `Ruta`: código, vehículo y fecha de entrega, si la tiene.

**Acciones de escritura en esta pantalla: ninguna.** Sólo lectura, selección local e
impresión.

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
  sale de esta ruta y vuelve a pedidos disponibles. La ruta se queda con las demás paradas y
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

Línea de datos: estado, `<km> km (incl. regreso)`, `<kg> kg`, importe total, vehículo
`Nombre · Placa`, fecha de entrega, `Carga total: <n>` y la **duración** («3 h 20 min»,
sale de `startedAt`/`finishedAt`; tooltip con las horas).

Compartir: enlace `Abrir en Google Maps` (origen = almacén, paradas en orden, **destino =
el mismo almacén**, `travelmode=driving&dir_action=navigate`), botón `copiar enlace` que
pasa a `copiado` 2,5 s, y aviso si sobran paradas:
`(Google admite 25 paradas: <n> quedan fuera del enlace)`.

Mapa a lo alto restante. Sin coordenadas: `Sin coordenadas GPS para esta ruta`.
Leyenda: `Punto de partida` (verde) · `Paradas` (azul) · `Regreso al depósito` (naranja).

### Asistente «Nueva Ruta» (cajón a pantalla **completa**, con pie fijo)

Barra de progreso de 4 pasos con las etiquetas `Sucursal`, `Salida`, `Vehículo`,
`Pedidos`; se pinta **un paso cada vez** y se puede volver a uno ya hecho pulsando su
tramo. Si la sucursal y la salida ya vienen resueltas, arranca directamente en el paso 3.
Pie fijo: `Cancelar` y `Generar Ruta` (mientras: `Generando ruta...`), deshabilitado si
falta salida, vehículo o pedidos, o si hay sobrepeso.

1. **Sucursal.** Selector `Sucursal de la ruta`, placeholder `Elige la sucursal…`.
   Nota: `Los pedidos, los vehículos y el punto de partida serán los de esta sucursal.`
   Botón `Siguiente`. La sucursal se autocompleta con la del usuario, o con la de la barra
   superior, o con la única disponible.
2. **`Punto de partida`.** Es un **almacén de la sucursal** (de Accesos), nunca un punto
   propio. Con varios: selector `Almacén del que sale el camión`, el principal primero y
   con la nota `principal`. Mapa de 220 px con el punto. Sin almacenes con ubicación:
   `Esta sucursal no tiene ningún almacén con ubicación. Se pone en Almacenes, y hasta entonces no hay desde dónde medir.`
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
4. **`Pedidos de cliente (<n>)`.** Dos columnas: lista a la izquierda, pre-despacho fijo a
   la derecha.

   Filtros de la lista de disponibles:
   - Selector `Sucursal de la ruta` (repetido) + campo fecha `Día de los pedidos` +
     botón `Todos los días`.
   - Selector `Vendedor del pedido` / `Todos los vendedores` (con buscador siempre).
   - `km máx.` (número) y `costo mín.` (número).
   - Selector `Estado del pedido en PEDIDO` / `Cualquier estado`: `En proceso`=`en_proceso`,
     `Completada`=`completada`, `Expirada`=`expirada`.
   - Selector `Si el pedido lleva entrega a domicilio` / `Con y sin domicilio`:
     `Sólo con domicilio`=`1` **(por defecto `1`)**, `Sólo sin domicilio`=`0`.
   - Selector `Si Entrega ya le puso costo de domicilio` / `Cotizados y sin cotizar`:
     `Ya cotizados`=`1`, `Sin cotizar`=`0`.
   - Botón `Limpiar` (vuelve a domicilio=`1`).
   - Buscador `Buscar pedido...` y selector `Municipio del cliente` / `Todos los municipios`
     (este último se aplica **en el cliente**).
   - **El cuadre con la factura NO es configurable:** siempre se manda `factura=cuadra`.

   Aviso si la lista viene recortada (tope de 2000 en el servidor):
   `Hay más pedidos de los que caben en la lista. Elegí la sucursal y el día para verlos todos: una ruta se arma con los de un sitio y un día.`

   Barra de capacidad: `<peso> / <capacidad> kg (<n>%)`, verde <80 %, ámbar ≥80 %, roja
   ≥100 %; insignia `LLENO` y texto `Camión lleno — no cabe más`. Sin vehículo:
   `Elige un vehículo para ver la capacidad`.

   Cada fila: casilla, cliente, dirección, chips de artículos, `<peso> kg` y el costo de
   domicilio o `sin cotizar`. Los pedidos que **no caben** quedan deshabilitados con
   `No cabe en el camión` (tooltip igual).

   Pie de la lista: `<n> pedidos seleccionados` y, si alguno ya no sale con los filtros,
   `(<n> de otro día o filtro, siguen contando)`; a la derecha `<peso> / <capacidad> kg`.
   Sobrepeso: `Peso ({w} kg) supera capacidad del vehículo ({c} kg)`.

   Estados: `Cargando pedidos...` / `No hay pedidos disponibles para rutear.`

   **Pre-despacho lateral** (`Pre-despacho`): botón `Ver e imprimir`; tabla `Producto` |
   `Emp.` | `Uds.`; totales `Pedidos`, `Empaques`, `Unidades`, `Peso` (`<w> / <cap> kg`).
   Vacío: `Según vayas eligiendo pedidos, aquí sale cuánto hay que sacar de cada producto.`

### Endpoints y acciones

| Acción | Llamada | Notas |
|---|---|---|
| Listar rutas | `GET /api/routes` | Sin parámetros; trae ruta + sucursal + vehículo + paradas ordenadas por `stopOrder`. |
| Vehículos | `GET /api/vehicles` | Para el selector y el filtro. |
| Almacenes | `GET /api/almacenes` | Punto de partida (por código de sucursal). |
| Sucursales | `GET /api/branches` | Las que la persona puede ver. |
| Pedidos elegibles | `GET /api/orders/available` con `q, branchId, fecha, vendedor, kmMax, costoMin, estado, cotizado, domicilio, factura=cuadra` | Devuelve `{orders, total, truncated}`; tope 2000. |
| Opciones de filtro | misma URL sin `q`, `vendedor` ni municipio | Para que elegir un vendedor no borre los demás. |
| Crear ruta | `POST /api/routes` con `{name?, branchId, vehicleId, deliveryDate?, originAddress, originLat, originLng, orderIds[]}` | 201 con la ruta creada; se selecciona sola. |
| Iniciar | `PATCH /api/routes/<id>` `{status:'in_progress'}` | Pasa a la pestaña `En curso`; marca el vehículo `in_use`. |
| Completar | `PATCH /api/routes/<id>` `{status:'completed'}` | Libera el vehículo, pasa a `Historial`. |
| Eliminar | `DELETE /api/routes/<id>` | Sólo rutas no completadas; libera el vehículo. El cajón de confirmación (`Borrar «RT-…»`) añade, desde el 07/10/2026: `Si la ruta se armó desde una zona del tablero, las facturas vuelven a esa zona cuando se sincronice el borrado (en la web, de inmediato). Mientras tanto, sin señal, salen en «Sin colocar».` |
| Quitar una parada | `DELETE /api/routes/<id>/stops/<orderId>` | Sólo rutas `planned`. 409 `Sólo se pueden retirar paradas de una ruta planificada` / `El pedido no pertenece a una ruta planificada o ya fue retirado`. |
| Cerrar parada por parada | `POST /api/routes/<id>/results` | Ver §9.1. |

**Errores del servidor, literales (salen como aviso emergente, no dentro del cajón):**
- `Las coordenadas del punto de partida son requeridas` (400)
- `Se requiere un vehículo para crear la ruta` (400)
- `Los pedidos seleccionados ya no están disponibles: <detalle>` (400)
- `<n> de los <total> pedidos elegidos no pueden ir en esta ruta: <folio> (ya va en la ruta RT-…|ya se entregó y no puede volver a un camión|PEDIDO lo archivó|sin coordenadas de entrega|no vino de PEDIDO|no existe o no es de tu sucursal|no es un identificador de pedido), … y <k> más.` (409)
  — con `<n>` = 1 el verbo va en singular (`no puede ir`), y si se eligió UN SOLO
  pedido la cabecera entera es `El pedido elegido no puede ir en esta ruta: …`:
  los dos números serían el mismo y no informan de nada. La escriben igual el
  servidor y el aparato —la ruta se arma sin señal—, y lo que las ata es
  `docs/armado-rechazado.casos.json`.
- `En una ruta sólo entra lo facturado y que cuadre. <n> no cumplen: <conduce> (cambió en la factura|sin facturar|sin cotejar), … y <n> más.` (409)
- `En una ruta sólo entra lo facturado con domicilio cobrado. <n> no cumplen: <conduce>, … y <k> más.` (409)
- `No se puede crear la ruta: <n> pedidos no tienen cotizado el domicilio en Entrega: <conduce>, … y <k> más.` (409)
- `El vehículo está inactivo y no se puede asignar a una ruta.` (400)
- `Peso total (<w> kg) supera la capacidad del vehículo (<c> kg)` (400)
- `Una ruta se arma eligiendo pedidos ya existentes. Manda \`orderIds\`.`
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
| Ajustes / tipos / tasa | `GET /api/settings` |
| Crear | `POST /api/vehicles` `{name, type, plate, capacity, status, notes, costoKmUsd, usarParaDomicilio}` |
| Editar | `PATCH /api/vehicles/<id>` con los mismos campos |
| Eliminar | `DELETE /api/vehicles/<id>` (en el reparto **pregunta antes**, en un cajón). Un vehículo con rutas, aunque sean históricas, **no se borra**: 409 `No se puede eliminar este vehículo porque tiene rutas asociadas, incluso históricas. Márcalo como inactivo para impedir que se use en nuevas rutas.` Se desactiva con el interruptor `Vehículo activo`. |
| `Usar para domicilio` | `PATCH /api/vehicles/<id>` `{usarParaDomicilio:true}` |
| `Marcar disponible` | `PATCH /api/vehicles/<id>` `{status:'available'}` (refresca también rutas) |
| Guardar tipos | `PUT /api/settings` `{tiposVehiculo:[{nombre, costoKmUsd}]}` |

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

**Para qué sirve.** Poner y corregir el punto desde el que se mide cada domicilio y del
que sale el camión. El dato vive en **Accesos** (una sola copia) y esta pantalla lo lee y
lo escribe. **Quién la usa:** administración de sucursal y logística.

**Título:** «Almacenes». Texto:
`El punto desde el que se mide cada domicilio. Un almacén sin coordenadas no sirve para cotizar: la distancia se mide desde aquí.`

### Controles

- Selector `Sucursal` (icono tienda) **sólo si hay más de una a la vista**; cada opción
  con la nota `<n>` o `sin almacenes`. Con una sola, se pinta su nombre sin desplegable.
- Selector `Almacén`: una opción por almacén (etiqueta = nombre o `(sin nombre)`; nota
  `principal` o `sin punto`) más `+ Añadir un almacén`.
- Botón `Nuevo almacén`.
- Aviso si la sucursal no tiene ninguno:
  `Esta sucursal no tiene ninguno: sus domicilios no se pueden cotizar.`

### Lista de almacenes

Una fila por almacén: icono estrella si es el principal, nombre (o `(sin nombre)`),
dirección (o `sin dirección`), marca `sin punto` si falta la coordenada, marca `inactivo`
si no está activo, y chevron. Al pulsar abre el editor.

### Editor (cajón `lg`)

Título `Nuevo almacén` o el nombre del almacén; subtítulo = nombre de la sucursal.
- Campo de texto, placeholder `Nombre del almacén`.
- Botón conmutador `Principal` (tooltip `Desde éste se mide cuando nadie dice cuál`).
- Botón conmutador `Activo` / `Inactivo`.
- Botón papelera (sólo en uno existente) con confirmación:
  `¿Quitar «<nombre>»? Deja de poder medirse desde ahí.`
- `Dónde está`: dirección con autocompletado + mapa; se abre centrado en el punto actual.
- Aviso: `Sin coordenadas: desde éste no se puede medir el domicilio.`
- Validación: `Le falta el nombre.` (el botón Guardar queda deshabilitado).
- Pie: `Cerrar` y `Guardar` (mientras: `Guardando…`).
- Confirmación: `Guardado en Accesos.`

**Regla:** sólo puede haber **un** almacén principal; al marcar uno, los demás se
desmarcan. Se envía **la lista completa** de la sucursal, no el almacén suelto.

### Endpoints

- `GET /api/almacenes` → `{sucursales:[{codigo, nombre, almacenes:[{id, nombre, direccion,
  latitud, longitud, principal, activo}]}]}`.
- `PUT /api/almacenes` `{codigo, almacenes:[...]}` → `{aviso, almacenes}`.

**Errores visibles, literales:**
- Fallo al leer: `No se pudieron traer los almacenes de Accesos. Lo de abajo está vacío por eso, no porque no haya ninguno.`
- Sin sucursales: `No hay ninguna sucursal a la vista con código en Accesos.`
- Del servidor: `No se pudieron traer los almacenes de Accesos: <detalle>`,
  `Accesos no aceptó el cambio: <detalle>` (502), `Se espera { codigo, almacenes: [...] }`
  (400), `Sin acceso a esa sucursal` (403).
- Respaldo del cliente al guardar: `No se pudo guardar`.

**Paginación:** no tiene.

---

## 7. Reportes — `/reports`

**Para qué sirve.** Cuadrar lo repartido en un rango de fechas: totales, reparto por
vehículo y detalle pedido a pedido, con exportación a Excel. **Quién la usa:**
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
`Vehículo` | `Placa` | `Órdenes` | `Ingresos` | `Peso Total` | `Promedio/Orden`;
fila de pie `Totales` con la suma de órdenes, ingresos y peso.
Vacío: `No hay datos de vehículos para los filtros seleccionados.`

**Detalle de Órdenes** — tabla:
`Fecha` | `Cliente` | `Ruta` | `Destino` | `Vehículo` | `Peso` | `Precio`;
fila de pie `Totales:` con peso total (`<n.n> kg`) e importe total.
Vacío: `No hay órdenes para los filtros seleccionados.`

### Endpoints

- `GET /api/vehicles` — para el selector.
- `GET /api/reports?from=&to=&vehicleId=` — `{orders[], summary:{totalOrders, totalRevenue,
  totalWeight, avgPrice}, byVehicle:[{name, plate, count, revenue, weight}]}`.
  El rango se aplica sobre `createdAt`; `to` incluye el día entero.
  **Ingreso de un pedido = `price` si lo tiene, si no `pedidoCosto`.**

### Exportación a Excel

Fichero `reporte-procovar-AAAA-MM-DD.xlsx`, tres hojas:
1. **`Resumen`**: `Reporte de transportación — ProCovar`; `Generado` + fecha y hora;
   `Filtro fecha` = `<desde|—> - <hasta|—>`; `Moneda` = código; luego `Total Órdenes`,
   `Ingresos Totales (<MONEDA>)`, `Precio Promedio (<MONEDA>)`, `Peso Total (kg)`.
2. **`Por Vehículo`**: `Vehículo`, `Placa`, `Órdenes`, `Ingresos (<MONEDA>)`, `Peso (kg)`,
   `Promedio/Orden (<MONEDA>)`.
3. **`Detalle de Órdenes`**: `Fecha`, `Cliente`, `Ruta`, `Destino`, `Vehículo`,
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
| `/orders` | `Pedidos` | `mdi:package-variant-closed` |
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
Efectos por pedido: guarda `resultado`, `resultadoAt`, `resultadoNota`; `deliveredAt` sólo
si se entregó; `status` = `delivered`/`pending`; y **lo que no se entrega suelta su
`routeId`** para poder ir en la ruta de mañana (`ultimaRutaId` y `stopOrder` se conservan).
Además avisa a PEDIDO del estado de cada pedido espejado.

**Mensajes:** éxito → `Cierre guardado. En PEDIDO cada pedido ya dice si se entregó o volvió.`
Errores → `No vino ningún resultado` (400), `No encontrada` (404), respaldo
`No se pudo guardar el cierre`. Rechazos por pedido: `ese pedido no va en esta ruta`,
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
`Conduce <número de operación>: <motivo literal del servidor>` (si el pedido no trae número
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

Usos: detalle de pedido (`lg`), asistente de ruta (`completo`, con pie), cierre de ruta
(`xl`, con pie), ficha de vehículo (`lg`), tipos de vehículo (`md`), editor de almacén
(`lg`, con pie).

### 9.3 `RouteSummaryCard.tsx`

Tarjeta resumida de una ruta: nombre, insignia de estado (colores: `planned` ámbar,
`in_progress` azul, `completed` verde; el texto es el estado con el guion bajo sustituido
por un espacio) y una rejilla de 2×2 con las etiquetas **en inglés, sin traducir**:
`Stops` (nº de pedidos), `Distance` (`<n.n> km`), `Weight` (`<n.n> kg`), `Revenue`
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
total es 0. Tamaños por lista: pedidos **50 fijo** (servidor), clientes **50** (servidor,
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
**Quién la dispara:** la pantalla de Pedidos (marcados y filtrados) y el paso 4 del
asistente de rutas.

Datos de entrada: `sucursal`, `vehiculo`, `dia` (`AAAA-MM-DD`, opcional), `pedidos`
(número), `pesoKg`, y `lineas[] = {producto, formatos, unidades, pesoKg}`.

**Estructura del documento:**

1. Cabecera a dos lados.
   - Izquierda: título `Pre-despacho` (20 px, negrita); debajo `<sucursal>` y, si hay
     vehículo, ` · <vehículo>`; debajo, si hay día, `Pedidos del <AAAA-MM-DD>`.
   - Derecha: `<n> pedido(s)`, **`Peso de los pedidos <n.n> kg`** y la fecha y hora
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
   (23/09/2026). La de Next imprime ahí `pesoKg`, que es el peso **de los
   pedidos**, mientras que cada línea imprime el peso **por producto** del
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
   Peso de los pedidos      412.5 kg
   No son el mismo número: el de arriba lo pone el catálogo producto a producto,
   y el de abajo viene en cada pedido.
   ```

   Los tres literales están **atados a los de la pantalla con una prueba**, no con
   un comentario (`app/test/impresion/los_dos_pesos_del_pre_despacho_test.dart`),
   que es la regla del §3-bis del `CLAUDE.md`.
5. Firmas, dos huecos con línea superior: `Sacó del almacén` · `Recibió (chofer)`.

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
| Rutas, paso 4 | Dos columnas: pedidos + pre-despacho pegajoso a la derecha | Una columna, pre-despacho debajo |
| Tabla de Pedidos | 12 columnas | Se esconden por orden de prescindibilidad: `Sucursal` bajo 1536 px; `Ruta` bajo 1280 px; `Artículos` y `Factura` bajo 1024 px; `Entrega` bajo 768 px. **Nunca se van:** cliente, dirección, peso, precio y estado |
| Tabla de Clientes | Completa | Se desplaza **la tabla**, no la página (ancho mínimo 736 px) |
| Vehículos | Rejilla de 3 columnas (2 en tabletas) | 1 columna; el grupo buscador + 2 botones **envuelve** en vez de salirse |
| Rutas, cabecera | Título, 3 pestañas y botón en una fila | Envuelve; las pestañas se desplazan de lado sin partir palabras |
| Menús de Selector | Menú anclado al botón | Igual, pero con buscador desde 4 opciones (ayuda más con el teclado del teléfono) |
| Tablas del pre-despacho | Normales | Desplazamiento horizontal propio: sin él empujan la página entera de lado |
