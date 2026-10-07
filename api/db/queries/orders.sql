-- Pedidos: el catálogo, los disponibles para repartir, las facetas y el espejo de PEDIDO.
--
-- CONVENCIÓN DE PARÁMETROS (vale para todos los ficheros de esta carpeta)
--
--   El alcance por sucursal es SEGURIDAD y va SIEMPRE en el SQL, nunca en Go. Se expresa
--   con un solo parámetro que admite «todas las sucursales» como NULL:
--
--       (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
--
--   `sqlc.narg('sucursal')` ES el `$1` posicional: sqlc lo numera igual, pero además le
--   pone nombre en el struct de Go. Con doce filtros opcionales, un struct de `Column1..
--   Column12` es exactamente la forma de colar el municipio en la casilla de la sucursal
--   sin que el compilador diga nada. El `::uuid` explícito es lo que obliga a sqlc a
--   generarlo como anulable.
--
--   Los demás filtros opcionales siguen el mismo patrón: NULL = no filtra.
--
-- EL TEXTO DE LOS RENGLONES YA NO SE COPIA. Donde delivery buscaba en `productosTexto`
-- —una copia a mano de los nombres, porque dentro de un JSON no se busca— aquí va un
-- EXISTS contra `order_items`. Un dato copiado en dos sitios acaba discrepando.

-- ---------------------------------------------------------------------------
-- La lista de pedidos por repartir  (GET /api/orders/available)
-- ---------------------------------------------------------------------------

-- ¿Qué pedidos puedo meter HOY en una ruta, de los que yo puedo ver?
--
-- Las cinco condiciones de arriba del WHERE no son filtros de pantalla y no se negocian:
--   * `source = 'pedido'`      — lo que no vino de PEDIDO no se reparte.
--   * `route_id IS NULL`       — si ya va en una ruta, está ocupado.
--   * `end_lat/end_lng`        — sin coordenadas no hay parada que visitar.
--   * `factura_estado IN ('igual','cambiado')` — LO REPARTIBLE. `cambiado` no es un pedido
--     roto: se facturó distinto de como se pidió y lo que sube al camión son las líneas de
--     la factura. Fuera quedan `sin_factura` (no hay nada que llevar) y el NULL, que
--     significa NO SE SABE: con un NULL colado se armó una ruta sin facturar el 2/09.
--
-- `km_max` y `costo_min` NO están aquí a propósito: el contrato los aplica después de la
-- consulta, y `total`/`truncated` se calculan ANTES que ellos. Bajarlos al SQL cambiaría
-- esos dos números y la pantalla diría «358» sobre una tabla de 120.
-- name: ListarPedidosDisponibles :many
SELECT
    o.id, o.order_date, o.created_at, o.operation_number, o.customer_name,
    o.address, o.end_address, o.end_lat, o.end_lng, o.weight,
    o.delivery_price, o.delivery_distance_km, o.estado, o.archivado,
    o.requiere_domicilio, o.pedido_costo, o.municipio, o.vendedor,
    o.branch_id, o.factura_estado, o.sucursal_codigo,
    -- ¿ESTE PESO SALE DE ALGO? `weight` no sabe decir «no se sabe» —un peso sin resolver
    -- entra como 0 y lo anterior al traspaso como 1, que es perfectamente creíble para un
    -- paquete—, así que la respuesta viaja al lado, sin cambiarle el tipo a nadie.
    -- Tres estados: false = hay constancia y nada lo respalda, el número es inventado;
    -- true = algún renglón trae peso propio; NULL = NO CONSTA, que no es «está bien».
    -- La definición vive en UN sitio (00007_lo_que_no_se_sabe.sql) para que las tres
    -- consultas no puedan contestar cosas distintas a la misma pregunta.
    pp.peso_respaldado
FROM orders o
LEFT JOIN peso_de_los_pedidos pp ON pp.id = o.id
WHERE
    o.source = 'pedido'
    AND o.route_id IS NULL
    -- UN PEDIDO ENTREGADO NO SE VUELVE A OFRECER. `route_id IS NULL` no basta: un
    -- entregado conserva su `route_id`, pero la clave ajena es `ON DELETE SET NULL`
    -- (`db/migrations/00001_init.sql:446`), así que borrar la ruta de ayer deja sueltos
    -- a los que ya se repartieron y esta lista los volvería a ofrecer para el camión de
    -- mañana. Es el mismo par de columnas de `reparto = 'sin_entregar'`, ahí abajo.
    AND o.delivered_at IS NULL
    AND (o.resultado IS NULL OR o.resultado <> 'entregado')
    AND o.end_lat IS NOT NULL
    AND o.end_lng IS NOT NULL
    AND o.factura_estado IN ('igual', 'cambiado')
    AND o.factura_domicilio > 0
    AND o.pedido_costo IS NOT NULL
    -- ARCHIVADO EN PEDIDO = NO SE REPARTE.
    --
    -- Faltaba, y con los datos reales del 15/09/2026 eso metia 1.348 pedidos archivados
    -- en la lista del armador: casi la mitad de los 2.771 que se ofrecian. PEDIDO los dio
    -- de baja y aqui salian como disponibles, sin un solo error — la lista se veia
    -- perfectamente normal y el camion salia con mercancia que nadie esperaba.
    --
    -- `archivado` es el borrado blando de PEDIDO y son la INMENSA MAYORIA del historico
    -- (50.810 de 55.622), asi que olvidarlo no es un detalle: es ofrecer el archivo entero.
    AND NOT o.archivado
    -- alcance por sucursal
    AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    -- `branch_id` de la query: estrecha, nunca amplía. Va en AND con el alcance, así que
    -- quien sólo ve una sucursal no puede pedir la de otro poniéndolo a mano.
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    -- Una sola caja de búsqueda: quien la usa no se para a pensar en qué campo está lo
    -- que recuerda. El EXISTS es la pregunta del despacho: «¿qué pedidos llevan malta?».
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    -- `expirada` se CALCULA con `now()` en cada llamada y no se guarda: un booleano
    -- guardado se queda viejo al día siguiente y empieza a mentir solo.
    -- El `estado IS NULL` explícito es obligatorio: `estado <> 'completada'` sobre un NULL
    -- da NULL, que no es TRUE, y la fila se cae de los tres filtros a la vez.
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    -- «Sin domicilio» incluye los que no traen el dato: no saberlo no es llevarlo.
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    -- El estado de REPARTO es propio del reparto: no tiene nada que ver con el estado del
    -- pedido en PEDIDO ni con el de la factura. Manda el RESULTADO de la parada y NO el
    -- estado de la ruta: una ruta completada no dice nada de cada parada, y darlo por
    -- bueno convertía en «entregado» lo que el propio cierre había grabado como devuelto.
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'planned'))
        OR (sqlc.narg('reparto')::text = 'en_ruta'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'in_progress'))
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    -- `sin_cotejar` tiene opción propia porque NULL NO es «cuadra»: quiere decir que no se
    -- sabe —VPN a Ventra caída, pedido fuera de los días que se repasan, sucursal sin base—.
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    -- La segunda rama es para los pedidos anteriores a que se guardara `order_date`:
    -- con sólo la primera desaparecerían de toda búsqueda por fechas, y desaparecer sin
    -- decir nada es peor que salir con la fecha aproximada, que la pantalla ya marca.
    -- `hasta` lo manda el llamante ya como fin de día: quien escribe el 24 quiere los del 24.
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    )
    -- `fecha` acota UN día natural, medio abierto por arriba. Es otro filtro que el rango:
    -- la pantalla del armador ofrece los dos y se combinan en AND.
    AND (
        sqlc.narg('dia_desde')::timestamptz IS NULL
        OR (o.order_date IS NOT NULL
            AND o.order_date >= sqlc.narg('dia_desde')::timestamptz
            AND o.order_date <  sqlc.narg('dia_hasta')::timestamptz)
        OR (o.order_date IS NULL
            AND o.created_at >= sqlc.narg('dia_desde')::timestamptz
            AND o.created_at <  sqlc.narg('dia_hasta')::timestamptz)
    )
ORDER BY o.order_date DESC NULLS LAST, o.created_at DESC
LIMIT sqlc.arg('limite');

-- El `total` de la pantalla de disponibles: el mismo WHERE, sin tope ni orden.
-- Tiene que ser EL MISMO o el contador dice una cosa y la tabla otra.
-- name: ContarPedidosDisponibles :one
SELECT count(*)
FROM orders o
WHERE
    o.source = 'pedido'
    AND o.route_id IS NULL
    -- UN PEDIDO ENTREGADO NO SE VUELVE A OFRECER. `route_id IS NULL` no basta: un
    -- entregado conserva su `route_id`, pero la clave ajena es `ON DELETE SET NULL`
    -- (`db/migrations/00001_init.sql:446`), así que borrar la ruta de ayer deja sueltos
    -- a los que ya se repartieron y esta lista los volvería a ofrecer para el camión de
    -- mañana. Es el mismo par de columnas de `reparto = 'sin_entregar'`, ahí abajo.
    AND o.delivered_at IS NULL
    AND (o.resultado IS NULL OR o.resultado <> 'entregado')
    AND o.end_lat IS NOT NULL
    AND o.end_lng IS NOT NULL
    AND o.factura_estado IN ('igual', 'cambiado')
    AND o.factura_domicilio > 0
    AND o.pedido_costo IS NOT NULL
    -- ARCHIVADO EN PEDIDO = NO SE REPARTE. Ver el porqué en ListarPedidosDisponibles.
    -- Aquí importa el doble: este recuento es el `total` que la pantalla enseña encima de
    -- la lista, así que sin esto diría «2.771 disponibles» sobre una lista de 1.423.
    AND NOT o.archivado
    AND (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'planned'))
        OR (sqlc.narg('reparto')::text = 'en_ruta'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'in_progress'))
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    )
    AND (
        sqlc.narg('dia_desde')::timestamptz IS NULL
        OR (o.order_date IS NOT NULL
            AND o.order_date >= sqlc.narg('dia_desde')::timestamptz
            AND o.order_date <  sqlc.narg('dia_hasta')::timestamptz)
        OR (o.order_date IS NULL
            AND o.created_at >= sqlc.narg('dia_desde')::timestamptz
            AND o.created_at <  sqlc.narg('dia_hasta')::timestamptz)
    );

-- ---------------------------------------------------------------------------
-- El catálogo de pedidos  (GET /api/orders)
-- ---------------------------------------------------------------------------

-- La lista paginada, con su ruta y su sucursal. Mismos filtros que los disponibles —tienen
-- que significar lo MISMO en las dos pantallas o los números no cuadran y nadie sabe cuál
-- creerse—, pero SIN las cinco condiciones fijas: aquí se ve todo el histórico.
-- name: ListarPedidos :many
SELECT
    o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.weight, o.status, o.notes,
    o.route_id, o.delivery_price, o.delivery_distance_km, o.order_date,
    o.created_at, o.delivered_at, o.resultado, o.resultado_nota, o.stop_order,
    o.estado, o.archivado, o.fecha_comprometida, o.requiere_domicilio,
    o.pedido_costo, o.factura_estado, o.factura_numero, o.factura_domicilio,
    o.municipio, o.vendedor, o.sucursal_codigo, o.branch_id, o.updated_at,
    r.name          AS ruta_nombre,
    r.route_code    AS ruta_codigo,
    r.status        AS ruta_estado,
    r.delivery_date AS ruta_fecha,
    v.name          AS vehiculo_nombre,
    v.plate         AS vehiculo_matricula,
    b.name          AS sucursal_nombre,
    b.lat           AS sucursal_lat,
    b.lng           AS sucursal_lng,
    -- ¿Este peso sale de algo? Ver el comentario largo en `ListarPedidosDisponibles`.
    -- false = inventado, true = algún renglón lo respalda, NULL = no consta.
    pp.peso_respaldado
FROM orders o
LEFT JOIN routes   r ON r.id = o.route_id
LEFT JOIN vehicles v ON v.id = r.vehicle_id
LEFT JOIN branches b ON b.id = o.branch_id
LEFT JOIN peso_de_los_pedidos pp ON pp.id = o.id
WHERE
    (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho' AND r.status = 'planned')
        OR (sqlc.narg('reparto')::text = 'en_ruta'     AND r.status = 'in_progress')
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    )
ORDER BY o.order_date DESC NULLS LAST, o.created_at DESC
LIMIT sqlc.arg('limite') OFFSET sqlc.arg('desplazamiento');

-- El total del catálogo, para la paginación. Mismo WHERE que `ListarPedidos`.
-- name: ContarPedidos :one
SELECT count(*)
FROM orders o
LEFT JOIN routes r ON r.id = o.route_id
WHERE
    (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho' AND r.status = 'planned')
        OR (sqlc.narg('reparto')::text = 'en_ruta'     AND r.status = 'in_progress')
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    );

-- ---------------------------------------------------------------------------
-- Un pedido suelto
-- ---------------------------------------------------------------------------

-- name: ObtenerPedido :one
SELECT
    o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.lat, o.lng, o.weight, o.status,
    o.trip_leg, o.notes, o.route_id, o.ultima_ruta_id, r.vehicle_id AS vehicle_id, o.price,
    o.segment_km, o.delivery_price, o.delivery_distance_km, o.branch_id,
    o.source, o.external_id, o.order_date, o.pedido_updated_at, o.estado,
    o.archivado, o.fecha_comprometida, o.requiere_domicilio, o.pedido_costo,
    o.municipio, o.vendedor, o.sucursal_codigo, o.factura_estado,
    o.factura_numero, o.factura_at, o.factura_domicilio, o.factura_corregido_at,
        o.items_origen,
    o.stop_order, o.delivered_at, o.resultado, o.resultado_at, o.resultado_nota,
    o.created_at, o.updated_at,
    r.name  AS ruta_nombre,
    v.name  AS vehiculo_nombre,
    v.plate AS vehiculo_matricula,
    vt.nombre AS vehiculo_tipo,
    -- ¿Este peso sale de algo? Ver el comentario largo en `ListarPedidosDisponibles`.
    -- false = inventado, true = algún renglón lo respalda, NULL = no consta.
    pp.peso_respaldado
FROM orders o
LEFT JOIN routes        r  ON r.id  = o.route_id
LEFT JOIN vehicles      v  ON v.id  = r.vehicle_id
LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
LEFT JOIN peso_de_los_pedidos pp ON pp.id = o.id
WHERE o.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid);

-- Los renglones de UN pedido, en el orden del papel del vendedor. `linea` no es decorativa:
-- la hoja del despacho tiene que salir igual que lo que el vendedor escribió.
--
-- El JOIN contra `orders` está SÓLO para poder acotar por sucursal: `order_items` no tiene
-- `branch_id` y sin él bastaría con acertar un uuid de pedido para leer qué mercancía
-- lleva un cliente de otra sucursal. El id del pedido llega de fuera; no se da por bueno.
-- name: ListarRenglonesDePedido :many
SELECT oi.id, oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs,
       oi.product_id, oi.updated_at,
       -- EL PESO DEL RENGLÓN, que hasta el 26/09/2026 no salía de aquí y por eso la
       -- aplicación lo recalculaba contra su catálogo local. Lo que se veía: la ficha
       -- decía «sin peso» en un renglón mientras el total del pedido decía 72,6 kg, y el
       -- pre-despacho —la hoja con la que se carga el camión— salía con las 14 filas en
       -- raya y «sin peso en el catálogo», con 7.446 empaques debajo.
       --
       -- El dato estaba aquí desde la 00004, y su propio comentario dice para qué se
       -- añadió: «precisamente para no tener que recalcular el peso con el catálogo de
       -- hoy». Un producto que hoy no está en el catálogo de esa sucursal no tiene por
       -- qué perder el peso con el que se facturó ayer.
       oi.peso_unitario_kg, oi.peso_linea_kg
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE oi.order_id = sqlc.arg('pedido_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY oi.linea ASC;

-- Los renglones de VARIOS pedidos de una vez. Una sola consulta para toda la página, no
-- una por fila: con 200 pedidos en pantalla, lo segundo son 200 idas y vueltas.
-- El alcance va aquí también aunque los ids ya vengan de una consulta acotada: si un id se
-- cuela desde el cliente, sin este filtro se leerían los renglones de otra sucursal.
-- name: ListarRenglonesDePedidos :many
SELECT oi.id, oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs,
       oi.product_id, oi.updated_at,
       -- EL PESO DEL RENGLÓN, que hasta el 26/09/2026 no salía de aquí y por eso la
       -- aplicación lo recalculaba contra su catálogo local. Lo que se veía: la ficha
       -- decía «sin peso» en un renglón mientras el total del pedido decía 72,6 kg, y el
       -- pre-despacho —la hoja con la que se carga el camión— salía con las 14 filas en
       -- raya y «sin peso en el catálogo», con 7.446 empaques debajo.
       --
       -- El dato estaba aquí desde la 00004, y su propio comentario dice para qué se
       -- añadió: «precisamente para no tener que recalcular el peso con el catálogo de
       -- hoy». Un producto que hoy no está en el catálogo de esa sucursal no tiene por
       -- qué perder el peso con el que se facturó ayer.
       oi.peso_unitario_kg, oi.peso_linea_kg
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE oi.order_id = ANY(sqlc.arg('pedido_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY oi.order_id, oi.linea ASC;

-- ---------------------------------------------------------------------------
-- Facetas del catálogo  (GET /api/orders/facetas)
-- ---------------------------------------------------------------------------

-- Los municipios que EXISTEN de verdad en lo que esta persona puede ver, para llenar el
-- desplegable. Si se sacaran de una lista fija, ofrecería municipios sin un solo pedido.
-- name: FacetasMunicipios :many
SELECT o.municipio AS valor, count(*) AS pedidos
FROM orders o
WHERE o.municipio IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.municipio
ORDER BY o.municipio ASC;

-- name: FacetasVendedores :many
SELECT o.vendedor AS valor, count(*) AS pedidos
FROM orders o
WHERE o.vendedor IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.vendedor
ORDER BY o.vendedor ASC;

-- Las sucursales con pedidos. El nombre se compone aquí —«Nombre (COD)»— porque es lo que
-- la gente reconoce: el código a secas no dice nada y el nombre solo se repite.
-- name: FacetasSucursales :many
SELECT
    o.branch_id AS valor,
    b.name        AS sucursal_nombre,
    b.external_id AS sucursal_codigo,
    count(*)      AS pedidos
FROM orders o
LEFT JOIN branches b ON b.id = o.branch_id
WHERE o.branch_id IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.branch_id, b.name, b.external_id
ORDER BY b.name ASC NULLS LAST;

-- ---------------------------------------------------------------------------
-- Pre-despacho: qué mercancía hay que sacar del almacén
-- ---------------------------------------------------------------------------

-- La cuenta de lo que hay que preparar, agrupada por nombre de renglón.
--
-- `formatos` son los bultos y son la unidad con la que se carga y se cuenta un camión;
-- cuando el renglón no los trae se cae a las unidades, porque es lo que hay y cero sería
-- mentira. El peso sale ahora del catálogo (`products.weight`), que es el mismo dato con
-- el que PEDIDO cotiza: el `pesoLineaKg` que venía dentro del JSON de `items` ya no existe.
-- name: ResumenPreDespacho :many
SELECT
    btrim(oi.description) AS producto,
    sum(CASE WHEN oi.packs > 0 THEN oi.packs ELSE oi.quantity END) AS formatos,
    sum(oi.quantity)                                               AS unidades,
    round(sum(coalesce(p.weight, 0) * oi.quantity)::numeric, 2)     AS peso_kg
FROM order_items oi
JOIN orders o        ON o.id = oi.order_id
LEFT JOIN products p ON p.id = oi.product_id
WHERE btrim(oi.description) <> ''
  AND o.id = ANY(sqlc.arg('pedido_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY btrim(oi.description)
ORDER BY formatos DESC, producto ASC;

-- ---------------------------------------------------------------------------
-- Escrituras del catálogo
-- ---------------------------------------------------------------------------

-- PATCH de un pedido a mano. `coalesce` deja pasar sólo lo que viene: lo que no se manda
-- no se pisa con NULL. `delivered_at` se pone solo al marcar `delivered` — no se le pide
-- al cliente que lo mande, que es como acaban dos pedidos con la misma hora de entrega.
-- name: ActualizarPedido :one
UPDATE orders SET
    operation_number = coalesce(sqlc.narg('operation_number')::text, operation_number),
    customer_name    = coalesce(sqlc.narg('customer_name')::text, customer_name),
    address          = coalesce(sqlc.narg('address')::text, address),
    end_address      = coalesce(sqlc.narg('end_address')::text, end_address),
    end_lat          = coalesce(sqlc.narg('end_lat')::double precision, end_lat),
    end_lng          = coalesce(sqlc.narg('end_lng')::double precision, end_lng),
    lat              = coalesce(sqlc.narg('lat')::double precision, lat),
    lng              = coalesce(sqlc.narg('lng')::double precision, lng),
    weight           = coalesce(sqlc.narg('weight')::double precision, weight),
    notes            = coalesce(sqlc.narg('notes')::text, notes),
    status           = coalesce(sqlc.narg('status')::order_status, status),
    trip_leg         = coalesce(sqlc.narg('trip_leg')::trip_leg, trip_leg),
    price            = coalesce(sqlc.narg('price')::double precision, price),
    stop_order       = coalesce(sqlc.narg('stop_order')::integer, stop_order),
    -- `route_id` va con interruptor y no con coalesce porque ponerlo a NULL es la mitad
    -- de su utilidad: es como se baja un pedido de un camión a mano. Y NO toca
    -- `ultima_ruta_id`, igual que en delivery: en qué ruta viajó no se reescribe desde
    -- una corrección suelta. Meter o sacar pedidos de una ruta de verdad es cosa de
    -- /api/routes; esto es el parche de una equivocación.
    route_id         = CASE WHEN sqlc.arg('tocar_route_id')::boolean
                            THEN sqlc.narg('route_id')::uuid ELSE route_id END,
    delivered_at     = CASE
        WHEN sqlc.narg('status')::order_status = 'delivered' THEN now()
        ELSE delivered_at
    END
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, operation_number, customer_name, address, end_address, end_lat,
          end_lng, lat, lng, weight, status, trip_leg, notes, route_id,
          ultima_ruta_id, price, segment_km, stop_order, delivered_at,
          branch_id, updated_at;

-- :one y no :exec: «no existe O no es de tu sucursal» es el 404, y con :exec no hay forma
-- de distinguirlo de un borrado hecho. `pgx.ErrNoRows` es ese caso.
--
-- Y DEVUELVE LA SUCURSAL DEL PEDIDO BORRADO — 01/10/2026. Era `:execrows` y lo único que
-- volvía era el número de filas, así que el aviso en vivo de `pedidos` no tenía de dónde
-- sacar la sucursal y salía del alcance de quien llamó: para un SUPER ADMIN, «de todas», y
-- las ocho sucursales se bajaban la lista de pedidos por un borrado de una sola. La fila ya
-- no está cuando se avisa, así que el dato tiene que venir del propio DELETE.
-- name: BorrarPedido :one
DELETE FROM orders
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING branch_id;

-- Recalcular el peso desde el catálogo (POST /api/orders/recompute-weights). Va sin
-- alcance a propósito: es una faena de servicio sobre todo el espejo, con clave de API.
-- name: ActualizarPesoDePedido :exec
UPDATE orders SET weight = sqlc.arg('weight')::double precision
WHERE id = sqlc.arg('id');

-- Los pedidos de una procedencia, para el repaso de pesos. Sin alcance: es de servicio.
-- name: ListarPedidosPorFuente :many
SELECT o.id, o.weight, o.external_id
FROM orders o
WHERE o.source = sqlc.arg('source')::procedencia
ORDER BY o.created_at ASC;

-- El peso que le TOCA a cada pedido según el catálogo, junto al que tiene guardado.
--
-- POR QUÉ SE SUMA EN LA BASE Y NO EN GO: el repaso es sobre el espejo ENTERO —decenas de
-- miles de pedidos y sus renglones—, y traérselo todo para multiplicar y sumar es cargar
-- el espejo en la memoria del proceso para devolver dos números por fila.
--
-- El peso sale de `products.weight`, que es el mismo dato con el que PEDIDO cotiza. El
-- `pesoLineaKg` que venía dentro del JSON de `items` YA NO EXISTE: era una copia, y una
-- copia acaba discrepando del catálogo que la originó.
--
-- El LEFT JOIN a `order_items` es a propósito: un pedido SIN renglones tiene que salir
-- igual, con peso calculado 0. Si se cayera de la lista, `totalOrders` diría menos
-- pedidos de los que hay y nadie sabría cuáles faltan.
-- name: PesosDelCatalogoPorFuente :many
SELECT
    o.id,
    o.weight AS peso_guardado,
    coalesce(sum(coalesce(p.weight, 0) * oi.quantity), 0)::double precision AS peso_catalogo
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.id
LEFT JOIN products    p  ON p.id = oi.product_id
WHERE o.source = sqlc.arg('source')::procedencia
GROUP BY o.id, o.weight
ORDER BY o.created_at ASC;

-- Los renglones que el catálogo NO sabe pesar, contados por nombre. Es la lista que hay
-- que llevarle a quien mantiene el catálogo de Ventra: sin ella, `ordersSinPeso` dice que
-- hay un problema pero no dice de qué producto.
--
-- `(sin nombre)` literal para el renglón con la descripción en blanco: agruparlos bajo la
-- cadena vacía deja una fila sin etiqueta en la pantalla que nadie sabe leer.
-- name: RenglonesSinPesoPorFuente :many
SELECT
    (coalesce(nullif(btrim(oi.description), ''), '(sin nombre)'))::text AS nombre,
    count(*) AS veces
FROM order_items oi
JOIN orders o        ON o.id = oi.order_id
LEFT JOIN products p ON p.id = oi.product_id
WHERE o.source = sqlc.arg('source')::procedencia
  AND coalesce(p.weight, 0) <= 0
GROUP BY 1
ORDER BY veces DESC, nombre ASC;

-- ---------------------------------------------------------------------------
-- El espejo de PEDIDO  (POST /api/quote/batch)
-- ---------------------------------------------------------------------------

-- Alta o actualización idempotente por (`source`, `external_id`): volver a pasar el mismo
-- lote no duplica. Va sin alcance porque el espejo entra con clave de servicio y trae las
-- ocho sucursales de una vez; la sucursal de cada pedido la decide el propio lote.
--
-- POR QUÉ UNA SOLA CONSULTA CON `ON CONFLICT` Y NO BUSCAR-Y-ESCRIBIR: `orders_origen_idx`
-- es un índice ÚNICO parcial (ver la migración). Con buscar-y-escribir, dos pasadas del
-- espejo a la vez leen «no existe» antes de que ninguna escriba y crean el mismo pedido
-- DOS VECES — y entonces sale dos veces en la lista del armador, con el mismo folio, y
-- alguien lo carga dos veces en el camión. Con el upsert la carrera la resuelve Postgres.
--
-- El `WHERE` del `ON CONFLICT` repite el del índice parcial: sin él Postgres no sabe qué
-- índice inferir y rechaza la consulta al ejecutarla.
--
-- LO QUE NO SE PISA NUNCA al actualizar: `route_id`, `ultima_ruta_id`, `stop_order`,
-- `resultado`, `resultado_nota` y `delivered_at`. Eso es del reparto y PEDIDO no sabe nada
-- de ello: dejarlo entrar borraría de un plumazo el resultado de una parada ya cerrada,
-- que es justo el dato que dice qué mercancía bajó del camión.
--
-- `xmax = 0` es el truco de Postgres para saber si la fila se INSERTÓ o se ACTUALIZÓ: en
-- una fila recién insertada el id de la transacción que la borró todavía es cero. Hace
-- falta para poder decir en el registro cuántos pedidos son nuevos sin una consulta más.
-- name: GuardarPedidoDelEspejo :one
INSERT INTO orders (
    operation_number, customer_name, customer_phone, address, end_address,
    lat, lng, end_lat, end_lng, weight, branch_id, source, external_id, order_date,
    pedido_updated_at, estado, archivado, fecha_comprometida, requiere_domicilio,
    pedido_costo, municipio, vendedor, sucursal_codigo, factura_estado,
    factura_numero, factura_at, factura_domicilio, factura_corregido_at,
    items_origen, delivery_distance_km, delivery_price,
    almacen_salida_codigo, almacen_salida_nombre, almacen_salida_sucursal,
    almacen_salida_mezclado, almacen_salida_motivo
) VALUES (
    sqlc.narg('operation_number'), sqlc.arg('customer_name'), sqlc.narg('customer_phone'),
    sqlc.arg('address'), sqlc.narg('end_address'),
    sqlc.narg('lat'), sqlc.narg('lng'), sqlc.narg('end_lat'), sqlc.narg('end_lng'),
    sqlc.arg('weight'), sqlc.narg('branch_id'), sqlc.arg('source'), sqlc.narg('external_id'),
    sqlc.narg('order_date'), sqlc.narg('pedido_updated_at'), sqlc.narg('estado'),
    sqlc.arg('archivado'), sqlc.narg('fecha_comprometida'), sqlc.narg('requiere_domicilio'),
    sqlc.narg('pedido_costo'), sqlc.narg('municipio'), sqlc.narg('vendedor'),
    sqlc.narg('sucursal_codigo'), sqlc.narg('factura_estado'), sqlc.narg('factura_numero'),
    sqlc.narg('factura_at'), sqlc.narg('factura_domicilio'), sqlc.narg('factura_corregido_at'),
    sqlc.narg('items_origen'), sqlc.narg('delivery_distance_km'), sqlc.narg('delivery_price'),
    sqlc.narg('almacen_salida_codigo'), sqlc.narg('almacen_salida_nombre'),
    sqlc.narg('almacen_salida_sucursal'), sqlc.narg('almacen_salida_mezclado'),
    sqlc.narg('almacen_salida_motivo')
)
ON CONFLICT (source, external_id) WHERE source IS NOT NULL AND external_id IS NOT NULL
DO UPDATE SET
    operation_number     = excluded.operation_number,
    customer_name        = excluded.customer_name,
    customer_phone       = excluded.customer_phone,
    address              = excluded.address,
    end_address          = excluded.end_address,
    lat                  = excluded.lat,
    lng                  = excluded.lng,
    end_lat              = excluded.end_lat,
    end_lng              = excluded.end_lng,
    weight               = excluded.weight,
    branch_id            = excluded.branch_id,
    order_date           = excluded.order_date,
    pedido_updated_at    = excluded.pedido_updated_at,
    estado               = excluded.estado,
    archivado            = excluded.archivado,
    fecha_comprometida   = excluded.fecha_comprometida,
    requiere_domicilio   = excluded.requiere_domicilio,
    pedido_costo         = excluded.pedido_costo,
    municipio            = excluded.municipio,
    vendedor             = excluded.vendedor,
    sucursal_codigo      = excluded.sucursal_codigo,
    factura_estado       = excluded.factura_estado,
    factura_numero       = excluded.factura_numero,
    factura_at           = excluded.factura_at,
    factura_domicilio    = excluded.factura_domicilio,
    factura_corregido_at = excluded.factura_corregido_at,
    items_origen         = excluded.items_origen,
    delivery_distance_km = excluded.delivery_distance_km,
    delivery_price       = excluded.delivery_price,
    -- DE QUÉ ALMACÉN SALE, y desde dónde se midió. Entra en el UPDATE porque cambia solo:
    -- un pedido entra al reparto antes de estar facturado —sin almacén, medido desde el
    -- principal— y cuando PEDIDO lo cierra contra la factura llega ya con el suyo. Si esto
    -- no se pisara, el kilometraje se quedaría para siempre con el del primer día.
    almacen_salida_codigo   = excluded.almacen_salida_codigo,
    almacen_salida_nombre   = excluded.almacen_salida_nombre,
    almacen_salida_sucursal = excluded.almacen_salida_sucursal,
    almacen_salida_mezclado = excluded.almacen_salida_mezclado,
    almacen_salida_motivo   = excluded.almacen_salida_motivo
-- UN PEDIDO QUE LLEGA IGUAL NO SE TOCA. Medido en producción el 26/09/2026:
--
--     orders   5.452 filas  ·  7.170.587 actualizaciones
--
-- Mil trescientas veces cada pedido, casi siempre para dejarlo exactamente igual: el
-- espejo repasa cada minuto y además siempre los últimos tres días. Es la tercera pata
-- del 36 % de CPU del Postgres, con los 98 millones de `customers` y los 8,8 de
-- `order_items` — las otras dos ya cortadas el mismo día.
--
-- `IS DISTINCT FROM` y no `<>`: con `<>`, un nulo a cada lado da NULL y la fila no se
-- actualizaría NUNCA. Un pedido al que le ponen la factura por primera vez se quedaría
-- sin ella para siempre, y en silencio.
--
-- LO QUE NO ENTRA EN LA COMPARACIÓN, y es lo que hace que esto funcione:
--
--   * `pedido_updated_at` sí entra — es la marca de agua de PEDIDO y, si cambió, el
--     pedido cambió aunque el resto se vea igual;
--   * `route_id`, `ultima_ruta_id`, `stop_order`, `resultado`, `delivered_at` y `status`
--     NO están en el upsert siquiera: son NUESTROS, los escribe el reparto, y el espejo
--     no los toca. Meterlos aquí sería comparar contra algo que este INSERT no manda.
--
-- Y OJO CON EL `RETURNING`: cuando el WHERE dice que no hay nada que cambiar, **no
-- devuelve fila**. Quien llama tiene que saber que eso NO es un error — se resuelve con
-- `BuscarPedidoPorReferencia`, aquí abajo. Ver `EspejoGuardarPedido`.
WHERE (orders.operation_number, orders.customer_name, orders.customer_phone,
       orders.address, orders.end_address, orders.lat, orders.lng,
       orders.end_lat, orders.end_lng, orders.weight, orders.branch_id,
       orders.order_date, orders.pedido_updated_at, orders.estado, orders.archivado,
       orders.fecha_comprometida, orders.requiere_domicilio, orders.pedido_costo,
       orders.municipio, orders.vendedor, orders.sucursal_codigo,
       orders.factura_estado, orders.factura_numero, orders.factura_at,
       orders.factura_domicilio, orders.factura_corregido_at, orders.items_origen,
       orders.delivery_distance_km, orders.delivery_price,
       orders.almacen_salida_codigo, orders.almacen_salida_nombre,
       orders.almacen_salida_sucursal, orders.almacen_salida_mezclado,
       orders.almacen_salida_motivo)
   IS DISTINCT FROM
      (excluded.operation_number, excluded.customer_name, excluded.customer_phone,
       excluded.address, excluded.end_address, excluded.lat, excluded.lng,
       excluded.end_lat, excluded.end_lng, excluded.weight, excluded.branch_id,
       excluded.order_date, excluded.pedido_updated_at, excluded.estado, excluded.archivado,
       excluded.fecha_comprometida, excluded.requiere_domicilio, excluded.pedido_costo,
       excluded.municipio, excluded.vendedor, excluded.sucursal_codigo,
       excluded.factura_estado, excluded.factura_numero, excluded.factura_at,
       excluded.factura_domicilio, excluded.factura_corregido_at, excluded.items_origen,
       excluded.delivery_distance_km, excluded.delivery_price,
       excluded.almacen_salida_codigo, excluded.almacen_salida_nombre,
       excluded.almacen_salida_sucursal, excluded.almacen_salida_mezclado,
       excluded.almacen_salida_motivo)
RETURNING id, branch_id, external_id, (xmax = 0)::boolean AS es_nuevo;

-- EL PEDIDO QUE NO HIZO FALTA TOCAR, para poder seguir con sus renglones.
--
-- El upsert de arriba no devuelve fila cuando nada cambió, y quien llama necesita el `id`
-- igualmente: los renglones se comparan contra los que ya hay, y para eso hace falta saber
-- de qué pedido son. Un SELECT por el índice único cuesta mucho menos que el UPDATE con su
-- WAL que esto viene a evitar.
-- name: BuscarPedidoPorReferencia :one
SELECT id, branch_id, external_id
FROM orders
WHERE source = sqlc.arg('source') AND external_id = sqlc.arg('external_id');

-- Los renglones se reescriben enteros en cada pasada del espejo: PEDIDO puede haber
-- quitado una línea, y un UPDATE línea a línea dejaría la vieja colgada. Se borran y se
-- vuelven a poner dentro de la MISMA transacción que el upsert de arriba.
-- LOS RENGLONES QUE YA HAY, para no reescribirlos si son los mismos.
--
-- Hoy los renglones se borran y se reinsertan ENTEROS en cada pasada del espejo. Medido en
-- producción el 26/09/2026:
--
--     order_items   7.450 filas  ·  8.892.252 insertados  ·  8.884.802 borrados
--
-- Mil ciento noventa veces cada renglón, casi siempre para dejarlo exactamente igual. Es
-- la otra mitad del 36 % de CPU del Postgres, junto con los 98 millones de `customers`.
--
-- Se leen SÓLO los campos que se comparan: `id` y las fechas no entran, porque cambian
-- aunque el renglón sea el mismo y harían que la comparación diera «distinto» siempre — la
-- guarda parecería puesta y no serviría de nada.
--
-- `ORDER BY linea` para que dos lecturas del mismo pedido salgan en el mismo orden: sin
-- eso, comparar dos listas iguales en otro orden dice «cambió» y se reescribe igual.
-- name: RenglonesDePedidoParaComparar :many
SELECT linea, description, quantity, packs, product_id, nombre, codigo,
       almacen_nombre, caso, peso_unitario_kg, peso_linea_kg, origen_peso,
       almacen_salida_codigo, almacen_salida_nombre
FROM order_items
WHERE order_id = sqlc.arg('pedido_id')
ORDER BY linea ASC;

-- name: BorrarRenglonesDePedido :exec
DELETE FROM order_items WHERE order_id = sqlc.arg('pedido_id');

-- LA CONSTANCIA DEL PESO, que estaba dada de alta y no la escribía nadie.
--
-- 00004_peso_por_renglon.sql añadió `caso`, `peso_unitario_kg`, `peso_linea_kg` y
-- `origen_peso` precisamente para no tener que recalcular el peso con el catálogo de hoy
-- sobre un pedido de hace tres meses. Esta sentencia insertaba sólo
-- `(order_id, linea, description, quantity, packs, product_id)`, así que desde el traspaso
-- del 14/09/2026 **esas columnas llegan vacías en todo lo que escribe el espejo** y la
-- vista `peso_de_los_pedidos` no puede decir nada de los pedidos nuevos: los deja en NULL.
--
-- Los valores YA están calculados al llegar aquí, en `cotizar.RenglonPesado`
-- (`WeightKg`, `UnitWeightKg`, `Matched`, `WhName`, `WeightSource`): no hay que calcular
-- nada, sólo dejar de tirarlos. Quien los pone es `renglonesParaLaBase`, en
-- `internal/api/cotizacion.go`.
--
-- Todos anulables a propósito: un renglón que no sabe lo que pesa se guarda VACÍO, no en
-- cero. `origen_peso = 'none'` —`cotizar.PesoDesconocido`— es otra cosa y sí se escribe:
-- es el renglón confesando que lo intentó y no pudo, que es lo que la vista mira.
--
-- Y OJO CON LAS DOS COLUMNAS QUE SE PARECEN: `almacen_nombre` es el nombre del PRODUCTO con
-- el que casó el catálogo local de pesos (`RenglonPesado.WhName`) y no tiene nada que ver
-- con un almacén, a pesar de cómo se llama. El almacén del que sale el renglón —00012— es
-- `almacen_salida_codigo` / `almacen_salida_nombre`. Escribir un almacén en la primera
-- dejaría a quien busca un producto leyendo «2» y «AURORA».
-- name: CrearRenglonDePedido :one
INSERT INTO order_items (
    order_id, linea, description, quantity, packs, product_id,
    nombre, codigo, almacen_nombre, caso, peso_unitario_kg, peso_linea_kg, origen_peso,
    almacen_salida_codigo, almacen_salida_nombre
)
VALUES (
    sqlc.arg('pedido_id'), sqlc.arg('linea'), sqlc.arg('description'),
    sqlc.arg('quantity'), sqlc.narg('packs'), sqlc.narg('product_id'),
    sqlc.narg('nombre'), sqlc.narg('codigo'), sqlc.narg('almacen_nombre'),
    sqlc.narg('caso'), sqlc.narg('peso_unitario_kg'), sqlc.narg('peso_linea_kg'),
    sqlc.narg('origen_peso'),
    sqlc.narg('almacen_salida_codigo'), sqlc.narg('almacen_salida_nombre')
)
RETURNING id, order_id, linea, description, quantity, packs, product_id,
          nombre, codigo, almacen_nombre, caso, peso_unitario_kg, peso_linea_kg,
          origen_peso, almacen_salida_codigo, almacen_salida_nombre;

-- La marca de agua del espejo: `since` de la próxima bajada.
--
-- Se DERIVA de los datos y no de un contador aparte a propósito: un contador se adelanta
-- si una tanda falla a medias, y entonces el espejo se salta esos pedidos para siempre
-- sin dar un solo error.
-- name: MarcaDeAguaDelEspejo :one
SELECT max(o.pedido_updated_at)::timestamptz AS marca
FROM orders o
WHERE o.source = 'pedido'
  AND (sqlc.narg('sucursal_codigo')::text IS NULL
       OR o.sucursal_codigo = sqlc.narg('sucursal_codigo')::text);

-- ---------------------------------------------------------------------------
-- Panel  (GET /api/dashboard)  e informes  (GET /api/reports)
-- ---------------------------------------------------------------------------

-- Los siete números del panel en UNA consulta.
--
-- REPARTIBLE es el mismo listón del armador de rutas —sin ruta, con coordenadas y con
-- factura que se puede llevar—: si el panel contara otra cosa, diría «40 por repartir» y
-- el armador ofrecería 12, y la respuesta correcta sería «ninguno de los dos».
-- name: PanelResumen :one
SELECT
    count(*)                                                        AS total_pedidos,
    count(*) FILTER (WHERE o.route_id IS NULL
                       AND o.end_lat IS NOT NULL
                       AND o.factura_estado IN ('igual','cambiado')) AS sin_ruta,
    count(*) FILTER (WHERE o.delivered_at >= sqlc.arg('hoy')::timestamptz) AS entregados_hoy,
    coalesce(sum(o.weight) FILTER (WHERE o.route_id IS NULL
                       AND o.end_lat IS NOT NULL
                       AND o.factura_estado IN ('igual','cambiado')), 0)::double precision AS peso_pendiente,
    coalesce(sum(o.pedido_costo), 0)::double precision              AS total_domicilios
FROM orders o
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid);

-- El reparto de lo repartible por sucursal. Lo ve quien no tiene alcance —el Super Admin—;
-- a quien sí lo tiene le sale una sola fila, que es justo lo correcto.
-- name: PanelPorSucursal :many
SELECT
    o.branch_id,
    b.name    AS sucursal_nombre,
    count(*)  AS pedidos,
    coalesce(sum(o.weight), 0)::double precision AS peso_kg
FROM orders o
LEFT JOIN branches b ON b.id = o.branch_id
WHERE o.route_id IS NULL
  AND o.end_lat IS NOT NULL
  AND o.factura_estado IN ('igual','cambiado')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.branch_id, b.name
ORDER BY pedidos DESC;

-- El informe. `ingreso` es `price` si lo hay y si no `pedido_costo`: `price` es el reparto
-- de carga de una ruta y `pedido_costo` lo que cobró Entrega; no son lo mismo y cobrar uno
-- por el otro es el error que este COALESCE hace visible en un solo sitio.
-- name: ListarPedidosParaInforme :many
SELECT
    o.id, o.customer_name, o.address, o.end_address, o.weight,
    coalesce(o.price, o.pedido_costo, 0) AS ingreso,
    o.segment_km, o.created_at,
    coalesce(r.route_code, r.name) AS ruta_nombre,
    -- El id del camión sale para poder AGRUPAR por él en `byVehicle`. Agrupar por nombre
    -- juntaría dos camiones distintos que se llamen igual —«Camión 1» lo hay en varias
    -- sucursales, y la matrícula puede estar vacía—, y el informe daría un vehículo con el
    -- doble de ingresos sin que nada falle.
    v.id    AS vehiculo_id,
    v.name  AS vehiculo_nombre,
    v.plate AS vehiculo_matricula
FROM orders o
LEFT JOIN routes   r ON r.id = o.route_id
LEFT JOIN vehicles v ON v.id = r.vehicle_id
WHERE
    (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
    AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz)
    AND (sqlc.narg('vehiculo_id')::uuid IS NULL OR r.vehicle_id = sqlc.narg('vehiculo_id')::uuid)
ORDER BY o.created_at DESC;

-- ---------------------------------------------------------------------------
-- La bajada del aparato  (GET /api/sync/cambios, colección `orders`)
-- ---------------------------------------------------------------------------

-- LO QUE CAMBIÓ DESDE UNA MARCA, en una sucursal. Es la consulta que faltaba y sin la
-- cual el trabajo sin conexión no existe: el logístico se baja los pedidos por la mañana
-- y los prepara todo el día sin red.
--
-- `cambiado_at` NO ES `o.updated_at`, y ésa es la razón de ser de esta consulta.
--
--   Es el más nuevo de los dos: el del pedido y el de sus renglones. Si cambia un renglón
--   —PEDIDO reescribe las líneas con lo que dijo la factura— el pedido NO se toca, así que
--   su `updated_at` se queda quieto y el pedido no saldría en las diferencias. El aparato
--   se quedaría con la lista de mercancía vieja y el camión cargaría lo que ya no es.
--   Por eso el renglón arrastra a su pedido.
--
--   Y es también LA MARCA QUE SE DEVUELVE: el aparato la guarda y con ella pide la
--   siguiente vez. Devolver `o.updated_at` y filtrar por el otro sería darle una marca
--   atrasada con la que volvería a bajarse lo mismo una y otra vez.
--
-- EL `desde` ES ESTRICTO (`>`) y el `hasta` INCLUSIVO (`<=`): así dos bajadas seguidas
-- —`(a,b]` y `(b,c]`— no se pisan ni dejan un hueco en `b`.
--
-- LOS ARCHIVADOS ENTRAN CON INTERRUPTOR, `con_archivados`:
--   * En la carga inicial va en false. Un pedido archivado hace ocho meses no tiene por
--     qué bajarse: el aparato empieza vacío y no hay nada que quitarle. Con true, el tope
--     se lo comerían los archivados del histórico y lo del día no cabría.
--   * En las diferencias va en true, porque archivar es justamente lo que hay que
--     contarle al aparato para que lo BORRE. Quien contesta la bajada mira `archivado` y
--     lo manda a `quitados`.
--
-- Las dos sucursales del WHERE son las de la casa: `sucursal` es el alcance, que lo pone
-- `internal/alcance` y no se puede pasar desde fuera, y `branch_id` es la que pide quien
-- llama. Van en AND: la segunda estrecha, nunca amplía.
-- name: DiferenciasDePedidos :many
WITH tocados AS (
    -- Los pedidos tocados por sí mismos...
    SELECT o.id
    FROM orders o
    WHERE sqlc.narg('desde')::timestamptz IS NULL
       OR o.updated_at > sqlc.narg('desde')::timestamptz
    UNION
    -- ...y los que arrastra un renglón suyo. UNION y no UNION ALL: un pedido con tres
    -- renglones tocados es un pedido, no tres.
    SELECT oi.order_id AS id
    FROM order_items oi
    WHERE sqlc.narg('desde')::timestamptz IS NOT NULL
      AND oi.updated_at > sqlc.narg('desde')::timestamptz
),
marcados AS (
    SELECT
        o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
        o.end_address, o.end_lat, o.end_lng, o.lat, o.lng, o.weight, o.status,
        o.trip_leg, o.notes, o.route_id, o.ultima_ruta_id, o.price,
        o.segment_km, o.delivery_price, o.delivery_distance_km, o.branch_id,
        o.source, o.external_id, o.order_date, o.pedido_updated_at, o.estado,
        o.archivado, o.fecha_comprometida, o.requiere_domicilio, o.pedido_costo,
        o.municipio, o.vendedor, o.sucursal_codigo, o.factura_estado,
        o.factura_numero, o.factura_at, o.factura_domicilio, o.factura_corregido_at,
        o.items_origen,
        o.stop_order, o.delivered_at, o.resultado, o.resultado_at, o.resultado_nota,
        o.created_at, o.updated_at,
        GREATEST(
            o.updated_at,
            coalesce(
                (SELECT max(oi.updated_at) FROM order_items oi WHERE oi.order_id = o.id),
                o.updated_at
            )
        )::timestamptz AS cambiado_at
    FROM orders o
    JOIN tocados t ON t.id = o.id
    WHERE (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
      AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
      AND (sqlc.arg('con_archivados')::boolean OR NOT o.archivado)
)
SELECT
    id, operation_number, customer_name, customer_phone, address, end_address,
    end_lat, end_lng, lat, lng, weight, status, trip_leg, notes, route_id,
    ultima_ruta_id, price, segment_km, delivery_price,
    delivery_distance_km, branch_id, source, external_id, order_date,
    pedido_updated_at, estado, archivado, fecha_comprometida, requiere_domicilio,
    pedido_costo, municipio, vendedor, sucursal_codigo, factura_estado,
    factura_numero, factura_at, factura_domicilio, factura_corregido_at,
    items_origen,
    stop_order, delivered_at, resultado, resultado_at, resultado_nota,
    created_at, updated_at, cambiado_at
FROM marcados
WHERE sqlc.narg('hasta')::timestamptz IS NULL
   OR cambiado_at <= sqlc.narg('hasta')::timestamptz
-- POR LA MARCA Y HACIA ADELANTE, que es lo que hace que el tope no pierda nada: lo que no
-- cabe en esta tanda se pide en la siguiente con la marca de la última fila servida. Con
-- cualquier otro orden, «los 2.000 primeros» son 2.000 cualesquiera y el resto no vuelve.
-- El `id` desempata para que dos tandas iguales salgan iguales.
ORDER BY cambiado_at ASC, id ASC
LIMIT sqlc.arg('tope');

-- LO QUE SE FUE DE LA SUCURSAL, para `quitados`.
--
-- `quitados` no es sólo lo borrado, y por eso esta consulta no mira `orders`: mira las
-- lápidas de 00003_bajada_pedidos.sql. Un pedido borrado ya no tiene fila que consultar, y
-- uno que se mudó de sucursal tiene la suya intacta pero con OTRA sucursal, así que no
-- sale en ninguna consulta acotada a la vieja. En los dos casos el aparato se quedaría con
-- él para siempre: la lista local sólo crece.
--
-- EL ARCHIVADO NO ESTÁ AQUÍ y no se le olvidó a nadie: su fila sigue existiendo, con el
-- `updated_at` movido, así que sale por `DiferenciasDePedidos` y quien contesta la bajada
-- lo manda a `quitados` al ver `archivado`. Ponerlo también aquí sería mandarlo dos veces.
--
-- Y SIN SUCURSAL —el Super Admin, que ve las ocho— sólo cuentan los BORRADOS: un pedido
-- que se mudó de Santiago a Holguín no se le ha ido de la vista, y mandárselo en
-- `quitados` le borraría del aparato un pedido que existe y que está en su lista.
-- name: PedidosQueSalieronDelAlcance :many
SELECT f.order_id, f.branch_id, f.motivo, f.salio_at
FROM orders_fuera_de_alcance f
WHERE (sqlc.narg('desde')::timestamptz IS NULL OR f.salio_at >  sqlc.narg('desde')::timestamptz)
  AND (sqlc.narg('hasta')::timestamptz IS NULL OR f.salio_at <= sqlc.narg('hasta')::timestamptz)
  -- El alcance primero, como siempre: aunque quien llama pida otra sucursal, sólo puede
  -- enterarse de lo que se fue de la suya.
  AND (sqlc.narg('sucursal')::uuid  IS NULL OR f.branch_id = sqlc.narg('sucursal')::uuid)
  AND (sqlc.narg('branch_id')::uuid IS NULL OR f.branch_id = sqlc.narg('branch_id')::uuid)
  AND (
      sqlc.narg('sucursal')::uuid  IS NOT NULL
      OR sqlc.narg('branch_id')::uuid IS NOT NULL
      OR f.motivo = 'borrado'
  )
ORDER BY f.salio_at ASC, f.order_id ASC
LIMIT sqlc.arg('tope');

-- LOS PEDIDOS QUE PEDIDO BORRÓ, quitados por su referencia.
--
-- Llega por el aviso del stream con `motivo = borrado`. Es el único de los cuatro que no
-- requiere ir a pedir nada, y el único que si se ignora deja el pedido aquí para siempre:
-- se queda en la lista de disponibles, alguien lo mete en un camión y nadie lo echa en
-- falta hasta que el cliente dice que él no pidió eso.
--
-- SÓLO los de `source = 'pedido'`. El alta MANUAL del reparto no tiene origen ni id
-- externo, y un id que coincidiera por casualidad se llevaría por delante un pedido que no
-- está en ningún otro sitio.
--
-- Un pedido que ya no está NO es un error: el aviso puede llegar dos veces —el stream
-- entrega al menos una— y la segunda no encuentra nada. Por eso `:execrows` y no `:one`.
-- name: QuitarPedidosDelEspejo :execrows
DELETE FROM orders
WHERE source = 'pedido' AND external_id = ANY(sqlc.arg('external_ids')::text[]);
