-- Almacenes y facturación de Ventra — el lado de la base.
--
-- LOS ALMACENES NO VIVEN AQUÍ. Son de Accesos y se piden por HTTP: `/api/almacenes` los
-- trae firmados y `PUT` se los devuelve tal cual. No se copian a esta base a propósito —
-- un almacén copiado se separa del de verdad en cuanto alguien mueve unas coordenadas
-- allá, y con esas coordenadas se mide el domicilio que se le cobra al cliente.
--
-- Lo que sí es de aquí son dos cosas:
--   1. QUÉ códigos de sucursal puede ver quien pregunta, para filtrar lo que devuelve
--      Accesos. Esa consulta vive en `branches.sql` (`CodigosDeSucursalesVisibles`), que
--      es donde está la tabla.
--   2. La facturación bajada de Ventra (`ventas_facturadas`), que es el almacén de datos
--      propiamente dicho.
--
-- AQUÍ NO SE ESCRIBE EL COTEJO. El cotejo pedido-contra-factura lo hace PEDIDO —el pedido
-- es suyo y es allí donde se corrige cuando la factura dice otra cosa—. Aquí sólo llega el
-- resultado, por el espejo, en `orders.factura_estado`.

-- ---------------------------------------------------------------------------
-- Ventas facturadas
-- ---------------------------------------------------------------------------

-- Las líneas facturadas de una sucursal en un rango de fechas.
--
-- EL ALCANCE VA POR CÓDIGO: `ventas_facturadas` no tiene `branch_id`, tiene
-- `sucursal_codigo`, y aquí es NOT NULL — una venta sin sucursal no existe. El llamante
-- traduce su sucursal con `branches.external_id`; NULL significa todas.
-- name: ListarVentasFacturadas :many
SELECT
    vf.id, vf.ventra_id, vf.sucursal_codigo, vf.fecha, vf.oper_number,
    vf.cliente_codigo, vf.cliente_nombre, vf.producto_codigo,
    vf.producto_nombre, vf.cantidad, vf.precio_usd, vf.traido_at
FROM ventas_facturadas vf
WHERE
    (sqlc.narg('sucursal_codigo')::text IS NULL
     OR vf.sucursal_codigo = sqlc.narg('sucursal_codigo')::text)
    AND (sqlc.narg('desde')::timestamptz IS NULL OR vf.fecha >= sqlc.narg('desde')::timestamptz)
    AND (sqlc.narg('hasta')::timestamptz IS NULL OR vf.fecha <= sqlc.narg('hasta')::timestamptz)
    AND (sqlc.narg('oper_number')::text IS NULL OR vf.oper_number = sqlc.narg('oper_number')::text)
    AND (
        sqlc.narg('q')::text IS NULL
        OR vf.cliente_nombre  ILIKE '%' || sqlc.narg('q')::text || '%'
        OR vf.producto_nombre ILIKE '%' || sqlc.narg('q')::text || '%'
    )
ORDER BY vf.fecha DESC, vf.oper_number ASC;

-- Una factura entera. `oper_number` ES la factura: varias líneas comparten número, y el
-- que las agrupa es ése y no `ventra_id`, que identifica la LÍNEA.
-- name: ObtenerFacturaPorOperacion :many
SELECT
    vf.id, vf.ventra_id, vf.sucursal_codigo, vf.fecha, vf.oper_number,
    vf.cliente_codigo, vf.cliente_nombre, vf.producto_codigo,
    vf.producto_nombre, vf.cantidad, vf.precio_usd, vf.traido_at
FROM ventas_facturadas vf
WHERE vf.oper_number = sqlc.arg('oper_number')
  AND vf.sucursal_codigo = sqlc.arg('sucursal_codigo')
ORDER BY vf.producto_nombre ASC;

-- Alta o actualización por `ventra_id`, que es el id de la LÍNEA en Ventra y por el que se
-- reconoce entre pasadas. Aquí sí hay `ON CONFLICT`: el esquema lo declara UNIQUE.
--
-- Va sin alcance: la bajada entra con clave de servicio y recorre las ocho sucursales.
-- name: GuardarVentaFacturada :one
INSERT INTO ventas_facturadas (
    ventra_id, sucursal_codigo, fecha, oper_number, cliente_codigo,
    cliente_nombre, producto_codigo, producto_nombre, cantidad, precio_usd, traido_at
) VALUES (
    sqlc.arg('ventra_id'), sqlc.arg('sucursal_codigo'), sqlc.arg('fecha'),
    sqlc.arg('oper_number'), sqlc.narg('cliente_codigo'), sqlc.arg('cliente_nombre'),
    sqlc.narg('producto_codigo'), sqlc.arg('producto_nombre'), sqlc.arg('cantidad'),
    sqlc.narg('precio_usd'), now()
)
ON CONFLICT (ventra_id) DO UPDATE SET
    sucursal_codigo = excluded.sucursal_codigo,
    fecha           = excluded.fecha,
    oper_number     = excluded.oper_number,
    cliente_codigo  = excluded.cliente_codigo,
    cliente_nombre  = excluded.cliente_nombre,
    producto_codigo = excluded.producto_codigo,
    producto_nombre = excluded.producto_nombre,
    cantidad        = excluded.cantidad,
    precio_usd      = excluded.precio_usd,
    traido_at       = excluded.traido_at
RETURNING id, ventra_id, sucursal_codigo, oper_number, traido_at;

-- Hasta cuándo se tiene facturación de una sucursal.
--
-- Es lo que distingue «este pedido no está facturado» de «de ese día todavía no hemos
-- bajado nada». Las dos cosas dejan `factura_estado` en NULL y desde fuera son idénticas;
-- la diferencia es que la primera es un problema del pedido y la segunda es que la VPN a
-- Ventra lleva caída desde el lunes. Con esa confusión se armó una ruta con un pedido sin
-- facturar el 2 de septiembre.
-- name: UltimaFacturacionDeSucursal :one
SELECT
    max(vf.fecha)::timestamptz     AS hasta_fecha,
    max(vf.traido_at)::timestamptz AS traido_at,
    count(*)                       AS lineas
FROM ventas_facturadas vf
WHERE vf.sucursal_codigo = sqlc.arg('sucursal_codigo');

-- Cuántas líneas hay por día, para ver de un vistazo qué días están bajados y cuáles no.
-- Un día que falta no sale como cero: sale como que no está, y eso es lo correcto — un
-- cero inventado se lee como «ese día no se vendió nada».
-- name: DiasConFacturacion :many
SELECT
    date_trunc('day', vf.fecha)::timestamptz AS dia,
    count(*)                                 AS lineas,
    max(vf.traido_at)::timestamptz           AS traido_at
FROM ventas_facturadas vf
WHERE (sqlc.narg('sucursal_codigo')::text IS NULL
       OR vf.sucursal_codigo = sqlc.narg('sucursal_codigo')::text)
  AND (sqlc.narg('desde')::timestamptz IS NULL OR vf.fecha >= sqlc.narg('desde')::timestamptz)
GROUP BY date_trunc('day', vf.fecha)
ORDER BY dia DESC;

-- Lo cotejado de una sucursal, para comparar contra la de Next mientras las dos están en
-- pie. Los NULL se cuentan aparte de los `sin_factura`: no son lo mismo y confundirlos es
-- exactamente lo que hay que poder ver.
-- name: ResumenDeCotejo :one
SELECT
    count(*)                                                    AS total,
    count(*) FILTER (WHERE o.factura_estado = 'igual')          AS cuadran,
    count(*) FILTER (WHERE o.factura_estado = 'cambiado')       AS cambiados,
    count(*) FILTER (WHERE o.factura_estado = 'sin_factura')    AS sin_factura,
    count(*) FILTER (WHERE o.factura_estado IS NULL)            AS sin_cotejar
FROM orders o
-- Sin lo archivado (00027): una factura anulada y quitada de su ruta no es una factura que cuadre.
WHERE NOT o.archivado
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
  AND (sqlc.narg('desde')::timestamptz IS NULL
       OR coalesce(o.order_date, o.created_at) >= sqlc.narg('desde')::timestamptz);

-- ---------------------------------------------------------------------------
-- Los pedidos que NO se midieron desde su propio almacén
-- ---------------------------------------------------------------------------

-- QUÉ ALMACENES ESTÁN HACIENDO QUE SE MIDA DESDE OTRO SITIO, Y POR QUÉ.
--
-- Es la mitad visible de la regla «nada se descarta en silencio» (`CLAUDE.md` §4). Un pedido
-- cuyo almacén no se pudo usar no se tira y no se cambia por el principal a escondidas: se
-- guarda su código y su nombre tal cual, se mide desde donde se pudo, y sale AQUÍ con el
-- motivo para que alguien lo arregle.
--
-- LOS MOTIVOS SE ARREGLAN EN SITIOS DISTINTOS y por eso viajan separados: dar de alta el
-- almacén en Accesos, ponerle el punto, ponerle el código, o que PEDIDO empiece a mandar el
-- campo. Y el peor —`sucursal-sin-almacen-con-punto`— no se midió desde ningún almacén, sino
-- desde el punto de la sucursal.
--
-- SE ACOTA POR CÓDIGO DE SUCURSAL: `sucursales` NULL es «todas» —el caso de administración—
-- y con una lista sólo salen ésas. Sin esto, unir esta vista a una respuesta de la API le
-- enseñaría Santiago al logístico de Camagüey, que es la regla 1 de la casa y ya pasó una vez
-- en delivery.
--
-- `pedidos AS cuantos` no es un capricho: cuando el SELECT es exactamente las columnas de la
-- vista y en su orden, sqlc reutiliza el modelo de la vista y lo llama
-- `AlmacenesDelPedidoSinMedirum`. Con un alias emite un `...Row` que se puede leer.
-- name: AlmacenesDelPedidoSinMedir :many
SELECT sucursal_codigo, motivo, codigo, nombre, pedidos AS cuantos, desde, hasta
FROM almacenes_del_pedido_sin_medir
WHERE sqlc.narg('sucursales')::text[] IS NULL
   OR sucursal_codigo = ANY(sqlc.narg('sucursales')::text[])
ORDER BY pedidos DESC, sucursal_codigo ASC, motivo ASC
LIMIT sqlc.arg('tope');
