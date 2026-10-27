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
-- Las condiciones de arriba del WHERE no son filtros de pantalla y no se negocian:
--   * `source = 'pedido'`      — lo que no vino de PEDIDO no se reparte.
--   * `route_id IS NULL`       — si ya va en una ruta, está ocupado.
--   * `end_lat/end_lng`        — sin coordenadas no hay parada que visitar.
--   * `factura_estado IN ('igual','cambiado')` — LO FACTURADO. `cambiado` no es un pedido
--     roto: se facturó distinto de como se pidió y lo que sube al camión son las líneas de
--     la factura. Fuera quedan `sin_factura` (no hay nada que llevar) y el NULL, que
--     significa NO SE SABE: con un NULL colado se armó una ruta sin facturar el 2/09.
--   * NADA DE DOMICILIO (TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro, restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md)). Desde el 07/10/2026 (Amado) se exigía `factura_domicilio > 0`
--     (el cobro) y la cotización de Entrega; la cotización se quitó el 16/10/2026 (Amado,
--     PCC25-261014-1435: marcado, sin cotizar y con 0.05 cobrado en la factura 47073) y el cobro
--     ese mismo día, por ahora (Jose: «que entren todos los pedidos con facturas»). La condición
--     está en cada consulta con el rótulo TEMPORAL, para restaurarla de un vistazo.
--
-- ESTA LISTA OFRECE LO MISMO QUE UNA RUTA ACEPTA, `cambiado` incluido desde el 15/10/2026: sus
-- renglones ya son los de la factura (PEDIDO los manda en cuanto hay cotejo), así que al camión
-- sube lo facturado. La regla ENTERA está en `ListarPedidosSinColocar`, en los recuentos del
-- Panel y en los manejadores del armado (`rechazoDelArmado`, `motivoDeCorteDelArmado`), y la
-- parte del domicilio (hoy sin exigir) también en `ColocarPedido` y `EngancharPedidoARuta`. Las ata
-- `consultas_motor_real_test.go` con los casos de `docs/armado-rechazado.casos.json`.
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
    -- TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro,
    -- restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md).
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
    -- UN MIEMBRO DE CONDUCE NO ES UNA FILA PROPIA (00029, `docs/conduces.md` regla 3): se ve dentro de su
    -- principal. Lista y contador llevan la MISMA línea, y lo ata `conduces_visibilidad_test.go`.
    AND o.conduce_principal_id IS NULL
    -- alcance por sucursal
    AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    -- `branch_id` de la query: estrecha, nunca amplía. Va en AND con el alcance, así que
    -- quien sólo ve una sucursal no puede pedir la de otro poniéndolo a mano.
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    -- Una sola caja de búsqueda: quien la usa no se para a pensar en qué campo está lo
    -- que recuerda. El EXISTS es la pregunta del despacho: «¿qué pedidos llevan malta?».
    -- La factura es `factura_numero` (Ventra), no el folio; con dos («47061, 47062») el ILIKE
    -- encuentra cualquiera de las dos (issue 10 de Amado, 15/10/2026).
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.factura_numero   ILIKE '%' || sqlc.narg('q')::text || '%'
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
    -- LLEVA DOMICILIO si el vendedor lo marcó O la factura lo cobró (`factura_domicilio > 0`).
    -- Sólo con la casilla, el asistente —que arranca en «Sólo con domicilio»— escondía el caso
    -- del issue 10 de Amado (15/10/2026): PBF26-2610131268 sin marcar y con 1.31 de
    -- «ENTREGA A DOMICILIO» en la factura. «Sin domicilio» es el contrario exacto: ni marcado
    -- ni cobrado (no saberlo no es llevarlo, y un cobro en cero no es cobro). Las cuatro
    -- consultas de pedidos lo escriben igual y en el aparato vive en `conDomicilio`
    -- (`nucleo/regla_de_entrada.dart`); lo atan los casos `filtroDeDomicilio` de
    -- `docs/armado-rechazado.casos.json`.
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS TRUE OR o.factura_domicilio > 0))
        OR (NOT sqlc.narg('domicilio')::boolean
            AND o.requiere_domicilio IS NOT TRUE
            AND (o.factura_domicilio IS NULL OR o.factura_domicilio <= 0))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedores')::text[] IS NULL OR o.vendedor = ANY(sqlc.narg('vendedores')::text[]))
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
    -- LA FECHA DE LA FACTURA, EN HORA DE CUBA (issue 16 de Amado, 16/10/2026): el logístico
    -- trabaja contra la factura. `coalesce(factura_at, order_date, created_at)` —un pedido
    -- sin factura va por la fecha del pedido, y uno sin ninguna por `created_at`, para que no
    -- desaparezca de toda búsqueda por fechas— y el DÍA es el de Cuba, no el de UTC. `desde`
    -- y `hasta` son DÍAS (`date`) y los dos van incluidos: quien escribe el 24 quiere los del
    -- 24. Misma regla que «Sin colocar» y que el aparato: `docs/fecha-de-la-factura.casos.json`.
    -- `fecha` (un día suelto de los disponibles) llega ya mezclado en este mismo rango.
    AND (
        sqlc.narg('desde')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           >= sqlc.narg('desde')::date
    )
    AND (
        sqlc.narg('hasta')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           <= sqlc.narg('hasta')::date
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
    -- TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro,
    -- restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md).
    -- ARCHIVADO EN PEDIDO = NO SE REPARTE. Ver el porqué en ListarPedidosDisponibles.
    -- Aquí importa el doble: este recuento es el `total` que la pantalla enseña encima de
    -- la lista, así que sin esto diría «2.771 disponibles» sobre una lista de 1.423.
    AND NOT o.archivado
    -- UN MIEMBRO DE CONDUCE NO ES UNA FILA PROPIA (00029, `docs/conduces.md` regla 3): se ve dentro de su
    -- principal. Lista y contador llevan la MISMA línea, y lo ata `conduces_visibilidad_test.go`.
    AND o.conduce_principal_id IS NULL
    AND (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.factura_numero   ILIKE '%' || sqlc.narg('q')::text || '%'
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
        OR (sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS TRUE OR o.factura_domicilio > 0))
        OR (NOT sqlc.narg('domicilio')::boolean
            AND o.requiere_domicilio IS NOT TRUE
            AND (o.factura_domicilio IS NULL OR o.factura_domicilio <= 0))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedores')::text[] IS NULL OR o.vendedor = ANY(sqlc.narg('vendedores')::text[]))
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
        sqlc.narg('desde')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           >= sqlc.narg('desde')::date
    )
    AND (
        sqlc.narg('hasta')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           <= sqlc.narg('hasta')::date
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
    o.punto_manual, o.punto_manual_por, o.punto_manual_at,
    o.punto_cliente_lat, o.punto_cliente_lng, o.punto_cliente_address,
    o.folio, o.anulada_at, o.anulada_de_ruta_id, o.conduce_principal_id,
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
    -- UN MIEMBRO DE CONDUCE NO ES UNA FILA PROPIA (00029, `docs/conduces.md` regla 3). Lista y contador, la misma línea.
    o.conduce_principal_id IS NULL
    AND (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.factura_numero   ILIKE '%' || sqlc.narg('q')::text || '%'
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
        OR (sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS TRUE OR o.factura_domicilio > 0))
        OR (NOT sqlc.narg('domicilio')::boolean
            AND o.requiere_domicilio IS NOT TRUE
            AND (o.factura_domicilio IS NULL OR o.factura_domicilio <= 0))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedores')::text[] IS NULL OR o.vendedor = ANY(sqlc.narg('vendedores')::text[]))
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
        sqlc.narg('desde')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           >= sqlc.narg('desde')::date
    )
    AND (
        sqlc.narg('hasta')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           <= sqlc.narg('hasta')::date
    )
ORDER BY o.order_date DESC NULLS LAST, o.created_at DESC
LIMIT sqlc.arg('limite') OFFSET sqlc.arg('desplazamiento');

-- El total del catálogo, para la paginación. Mismo WHERE que `ListarPedidos`.
-- name: ContarPedidos :one
SELECT count(*)
FROM orders o
LEFT JOIN routes r ON r.id = o.route_id
WHERE
    -- UN MIEMBRO DE CONDUCE NO ES UNA FILA PROPIA (00029, `docs/conduces.md` regla 3). Lista y contador, la misma línea.
    o.conduce_principal_id IS NULL
    AND (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.factura_numero   ILIKE '%' || sqlc.narg('q')::text || '%'
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
        OR (sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS TRUE OR o.factura_domicilio > 0))
        OR (NOT sqlc.narg('domicilio')::boolean
            AND o.requiere_domicilio IS NOT TRUE
            AND (o.factura_domicilio IS NULL OR o.factura_domicilio <= 0))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedores')::text[] IS NULL OR o.vendedor = ANY(sqlc.narg('vendedores')::text[]))
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
        sqlc.narg('desde')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           >= sqlc.narg('desde')::date
    )
    AND (
        sqlc.narg('hasta')::date IS NULL
        OR (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
           <= sqlc.narg('hasta')::date
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
    o.punto_manual, o.punto_manual_por, o.punto_manual_at,
    o.punto_cliente_lat, o.punto_cliente_lng, o.punto_cliente_address,
    o.folio, o.anulada_at, o.anulada_de_ruta_id, o.conduce_principal_id,
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
       oi.peso_unitario_kg, oi.peso_linea_kg,
       -- LA FACTURA DE ESTE RENGLÓN (00026, issue 22 de Maikel): NULL = no se sabe de cuál.
       oi.factura_numero
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
       oi.peso_unitario_kg, oi.peso_linea_kg,
       -- LA FACTURA DE ESTE RENGLÓN (00026, issue 22 de Maikel): NULL = no se sabe de cuál.
       oi.factura_numero
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
  AND o.conduce_principal_id IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.municipio
ORDER BY o.municipio ASC;

-- name: FacetasVendedores :many
SELECT o.vendedor AS valor, count(*) AS pedidos
FROM orders o
WHERE o.vendedor IS NOT NULL
  AND o.conduce_principal_id IS NULL
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
  AND o.conduce_principal_id IS NULL
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
  -- Y LOS DE SUS MIEMBROS (conduces, regla 6): se pide por la principal y salen los renglones de todo el conduce.
  AND (o.id = ANY(sqlc.arg('pedido_ids')::uuid[]) OR o.conduce_principal_id = ANY(sqlc.arg('pedido_ids')::uuid[]))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY btrim(oi.description)
ORDER BY formatos DESC, producto ASC;

-- ---------------------------------------------------------------------------
-- Escrituras del catálogo
-- ---------------------------------------------------------------------------

-- PATCH de un pedido a mano. `coalesce` deja pasar sólo lo que viene: lo que no se manda
-- no se pisa con NULL.
--
-- # TAMPOCO TOCA EL PUNTO DE ENTREGA NI LA DIRECCIÓN — 20/10/2026 (issue 19 de Amado)
--
-- Escribía `address`, `end_address`, `end_lat`, `end_lng`, `lat` y `lng` sin validar el rango,
-- sin marcar que eran a mano (el espejo los pisaba al minuto), sin recalcular la distancia ni
-- el `segment_km` de la parada y sin mirar si el pedido ya estaba entregado o en una ruta
-- completada. La única puerta para cambiar el punto de entrega es ahora
-- `PonerPuntoDeEntregaAMano` (`PUT /api/orders/{id}/punto`); el manejador responde 400 si
-- llega alguno de esos seis campos.
--
-- # LO QUE ESTA CONSULTA YA NO TOCA — 08/10/2026 (auditoría de la 1.0.28)
--
-- Hasta la 1.0.28 también escribía `route_id`, `status`, `price`, `weight`, `stop_order` y
-- `delivered_at`, SIN pasar por ninguna regla: cualquier rol podía meter un pedido en la
-- ruta de OTRA sucursal, en una ruta ya completada, uno sin facturar o sin domicilio cobrado,
-- o marcarlo `delivered`, o cambiarle el precio. Todo lo que el armador, el tablero y el
-- cierre de ruta bloquean desde el 07/10 (incidencia 6 de Amado) se podía saltar con un
-- PATCH. Ningún cliente lo usaba (la app no llama a este endpoint; se comprobó con grep en
-- app/lib, sync/, herramientas/ y docs/contratos-api.md), así que se QUITAN de la consulta,
-- no sólo del manejador: no queda una columna que otro llamante pueda volver a abrir por
-- descuido.
--
-- Meter o sacar un pedido de una ruta es SÓLO de /api/routes y /api/board; el estado y la
-- hora de entrega los pone el cierre (`MarcarResultadoDeParada`); el peso lo calcula el
-- servidor (`ActualizarPesoDePedido`, `peso_linea_kg`) y precio y orden de parada vienen de
-- PEDIDO / del armado. El manejador responde 400 si llega alguno de esos campos.
-- name: ActualizarPedido :one
UPDATE orders SET
    operation_number = coalesce(sqlc.narg('operation_number')::text, operation_number),
    customer_name    = coalesce(sqlc.narg('customer_name')::text, customer_name),
    notes            = coalesce(sqlc.narg('notes')::text, notes),
    trip_leg         = coalesce(sqlc.narg('trip_leg')::trip_leg, trip_leg)
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, operation_number, customer_name, address, end_address, end_lat,
          end_lng, lat, lng, weight, status, trip_leg, notes, route_id,
          ultima_ruta_id, price, segment_km, stop_order, delivered_at,
          branch_id, updated_at;

-- ---------------------------------------------------------------------------
-- El punto de entrega puesto a mano  (PUT / DELETE /api/orders/{id}/punto, 00024)
-- ---------------------------------------------------------------------------

-- Lo que el manejador necesita saber antes de escribir: de qué sucursal es, desde qué almacén
-- sale (para medir los km como la cotización), en qué ruta va y si ya se entregó. Con alcance:
-- un pedido de otra sucursal no devuelve fila, que es el mismo 404 que si no existiera.
-- name: LeerPedidoParaElPunto :one
SELECT
    o.id, o.branch_id, o.almacen_salida_codigo, o.route_id, o.resultado, o.delivered_at,
    o.punto_manual, o.punto_cliente_lat, o.punto_cliente_lng
FROM orders o
WHERE o.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid);

-- PONE EL PUNTO DE ENTREGA A MANO. Una sola sentencia: el punto, la marca, la distancia al
-- almacén y el `segment_km` de la parada se escriben juntos o no se escribe nada.
--
-- `end_lat/end_lng` y `lat/lng` se ponen los cuatro, igual que los pone el espejo (§2.3: en un
-- reparto «dónde está» y «dónde termina la parada» son el mismo sitio). `end_address` solo
-- cambia si viene `direccion`; si no, se queda la que tenía.
--
-- EL PUNTO DEL CLIENTE SE GUARDA SOLO LA PRIMERA VEZ: si el pedido ya era manual, `punto_cliente_*`
-- ya tiene el último que mandó el espejo y pisarlo con el punto manual anterior perdería a qué
-- se vuelve con el DELETE.
--
-- `delivery_distance_km` y `segment_km` los calcula el manejador (mismo origen que la cotización,
-- y radial desde el origen de la ruta); `segment_km` solo se toca si el pedido va en una ruta
-- (`coalesce`), y el `stop_order` NO se toca nunca: es lo que decidió el logístico.
--
-- EL WHERE REPITE LO QUE EL MANEJADOR COMPROBÓ, porque entre su lectura y esta escritura puede
-- haber pasado cualquier cosa: ya entregado = no (es histórico: lo que bajó del camión), la
-- ruta tiene que ser la misma que se bloqueó, y el almacén del pedido el mismo con el que se
-- midió (el espejo lo puede cambiar al minuto: otro almacén son otros km). Cero filas = el
-- manejador contesta 409 y no se guarda nada.
-- name: PonerPuntoDeEntregaAMano :one
UPDATE orders SET
    punto_cliente_lat     = CASE WHEN punto_manual THEN punto_cliente_lat ELSE end_lat END,
    punto_cliente_lng     = CASE WHEN punto_manual THEN punto_cliente_lng ELSE end_lng END,
    punto_cliente_address = CASE WHEN punto_manual THEN punto_cliente_address ELSE end_address END,
    end_lat               = sqlc.arg('lat'),
    end_lng               = sqlc.arg('lng'),
    lat                   = sqlc.arg('lat'),
    lng                   = sqlc.arg('lng'),
    end_address           = coalesce(sqlc.narg('direccion')::text, end_address),
    punto_manual          = true,
    punto_manual_por      = sqlc.narg('por')::text,
    punto_manual_at       = now(),
    delivery_distance_km  = sqlc.arg('delivery_distance_km'),
    segment_km            = coalesce(sqlc.narg('segment_km')::double precision, segment_km)
WHERE id = sqlc.arg('id')
  AND route_id IS NOT DISTINCT FROM sqlc.narg('ruta_id')::uuid
  AND almacen_salida_codigo IS NOT DISTINCT FROM sqlc.narg('almacen_salida_codigo')::text
  AND resultado IS DISTINCT FROM 'entregado'::stop_result
  AND delivered_at IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, branch_id, end_lat, end_lng, end_address, punto_manual, punto_manual_por,
          punto_manual_at, delivery_distance_km, segment_km;

-- VUELVE AL PUNTO DEL CLIENTE: el último que mandó el espejo, guardado en `punto_cliente_*`.
-- Quita la marca y limpia lo guardado (hay `punto_cliente_*` solo mientras es manual).
-- Mismas guardas y mismo recálculo que `PonerPuntoDeEntregaAMano`, y además `lat`/`lng` son el
-- punto del cliente CON EL QUE SE MIDIÓ: si el espejo lo corrigió entre la lectura y esta
-- escritura, los km serían los del punto viejo. Cero filas = no era manual, ya se entregó,
-- cambió de ruta o de punto; el manejador distingue lo primero antes, esto cubre la carrera.
-- name: DevolverPuntoDeEntregaAlCliente :one
UPDATE orders SET
    end_lat               = punto_cliente_lat,
    end_lng               = punto_cliente_lng,
    lat                   = punto_cliente_lat,
    lng                   = punto_cliente_lng,
    end_address           = punto_cliente_address,
    punto_manual          = false,
    punto_manual_por      = NULL,
    punto_manual_at       = NULL,
    punto_cliente_lat     = NULL,
    punto_cliente_lng     = NULL,
    punto_cliente_address = NULL,
    delivery_distance_km  = sqlc.arg('delivery_distance_km'),
    segment_km            = coalesce(sqlc.narg('segment_km')::double precision, segment_km)
WHERE id = sqlc.arg('id')
  AND punto_manual
  AND punto_cliente_lat = sqlc.arg('lat') AND punto_cliente_lng = sqlc.arg('lng')
  AND almacen_salida_codigo IS NOT DISTINCT FROM sqlc.narg('almacen_salida_codigo')::text
  AND route_id IS NOT DISTINCT FROM sqlc.narg('ruta_id')::uuid
  AND resultado IS DISTINCT FROM 'entregado'::stop_result
  AND delivered_at IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, branch_id, end_lat, end_lng, end_address, punto_manual, punto_manual_por,
          punto_manual_at, delivery_distance_km, segment_km;

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
-- Y LO QUE SE CONSERVA SI EL PUNTO ES A MANO (`punto_manual`, 00024): el punto de entrega
-- (`end_address`, `lat`, `lng`, `end_lat`, `end_lng`) y la distancia que se midió hasta él.
-- Lo que trae PEDIDO se guarda en `punto_cliente_*`. Ver los CASE del `DO UPDATE` y del `WHERE`.
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
    almacen_salida_mezclado, almacen_salida_motivo, folio
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
    sqlc.narg('almacen_salida_motivo'), sqlc.narg('folio')
)
ON CONFLICT (source, external_id) WHERE source IS NOT NULL AND external_id IS NOT NULL
DO UPDATE SET
    operation_number     = excluded.operation_number,
    customer_name        = excluded.customer_name,
    customer_phone       = excluded.customer_phone,
    address              = excluded.address,
    -- EL PUNTO DE ENTREGA PUESTO A MANO MANDA (issue 19 de Amado, 00024, Jose 20/10/2026).
    -- Mientras `punto_manual` sea true, lo que PEDIDO trae del cliente NO se escribe en el
    -- punto de entrega —`end_address`, `lat`, `lng`, `end_lat`, `end_lng`— ni en la distancia
    -- que se midió hasta él (`delivery_distance_km`, que el servidor recalculó al ponerlo): se
    -- GUARDA aparte, en `punto_cliente_*`, para poder volver a él con la ubicación al día. Sin
    -- esto el punto duraba hasta el siguiente repaso, un minuto.
    --
    -- `orders.punto_manual` es el valor de la fila ANTES de este UPDATE. Y estos mismos
    -- CASE vuelven en el WHERE de abajo: si se quitan de ahí, un pedido con punto manual se
    -- reescribe en cada pasada (stored <> excluded para siempre) y se pierde el ahorro del
    -- 26/09/2026.
    --
    -- Y TAMBIÉN SE CONSERVA EL PUNTO QUE YA HABÍA CUANDO EL QUE ENTRA NO TRAE NINGUNO (auditoría
    -- del 20/10/2026, G1): una entrega de factura cuyo cliente no está en `customers` adopta a una
    -- fila de PEDIDO que SÍ tenía su punto, y sin esto el `DO UPDATE` escribía NULL en `lat`, `lng`,
    -- `end_lat`, `end_lng` y `delivery_distance_km`: la parada de una ruta se quedaba sin punto y el
    -- armador la excluye con `end_lat IS NOT NULL`. Si el entrante trae punto, manda el entrante;
    -- si no, y la fila ya tenía uno, se queda el que tenía CON su dirección y su km (un km de un
    -- punto que ya no está, o un punto sin su km, serían mentira). La regla es UNA función,
    -- `punto_se_conserva` (00025), la misma en el `SET` y en el `WHERE` de abajo.
    end_address          = CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.end_address ELSE excluded.end_address END,
    lat                  = CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.lat ELSE excluded.lat END,
    lng                  = CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.lng ELSE excluded.lng END,
    end_lat              = CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.end_lat ELSE excluded.end_lat END,
    end_lng              = CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.end_lng ELSE excluded.end_lng END,
    punto_cliente_lat     = CASE WHEN orders.punto_manual THEN excluded.end_lat ELSE NULL END,
    punto_cliente_lng     = CASE WHEN orders.punto_manual THEN excluded.end_lng ELSE NULL END,
    punto_cliente_address = CASE WHEN orders.punto_manual THEN excluded.end_address ELSE NULL END,
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
    delivery_distance_km = CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.delivery_distance_km ELSE excluded.delivery_distance_km END,
    delivery_price       = excluded.delivery_price,
    -- DE QUÉ ALMACÉN SALE, y desde dónde se midió. Entra en el UPDATE porque cambia solo:
    -- un pedido entra al reparto antes de estar facturado —sin almacén, medido desde el
    -- principal— y cuando PEDIDO lo cierra contra la factura llega ya con el suyo. Si esto
    -- no se pisara, el kilometraje se quedaría para siempre con el del primer día.
    almacen_salida_codigo   = excluded.almacen_salida_codigo,
    almacen_salida_nombre   = excluded.almacen_salida_nombre,
    almacen_salida_sucursal = excluded.almacen_salida_sucursal,
    almacen_salida_mezclado = excluded.almacen_salida_mezclado,
    almacen_salida_motivo   = excluded.almacen_salida_motivo,
    -- EL FOLIO (00025): la clave con la que una entrega de factura y un pedido de PEDIDO se
    -- reconocen como la misma. Entra en el UPDATE y en la comparación de abajo: si no entrara,
    -- una fila que ganara su folio después (el relleno de la 00025 no llega a las que no
    -- existían) se leería como «no cambió nada» y se quedaría sin él para siempre.
    folio                   = excluded.folio,
    -- UNA FACTURA ANULADA QUE REAPARECE SE REACTIVA, en la misma fila (00027): `archivado` ya viene en
    -- false de `excluded`, y aquí se borra la marca de anulada (el CHECK `orders_anulada_archivada_chk`
    -- no deja una anulada sin archivar). Sin duplicarse: el `ON CONFLICT` la encuentra por su `external_id`.
    anulada_at              = NULL,
    anulada_de_ruta_id      = NULL
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
       orders.almacen_salida_motivo,
       orders.punto_cliente_lat, orders.punto_cliente_lng, orders.punto_cliente_address,
       orders.folio, orders.anulada_at, orders.anulada_de_ruta_id)
   IS DISTINCT FROM
      (excluded.operation_number, excluded.customer_name, excluded.customer_phone,
       excluded.address,
       -- LO QUE ESTE UPSERT ESCRIBIRÍA DE VERDAD, no lo que trae PEDIDO: con punto manual, el
       -- punto de entrega y su distancia son los que ya hay (mismos CASE que el SET). Comparar
       -- contra `excluded.*` a secas daría «distinto» en cada pasada para todo pedido con
       -- punto manual. El punto del cliente, en cambio, SÍ se compara: si PEDIDO lo corrigió,
       -- hay que guardar el nuevo en `punto_cliente_*` aunque nada más haya cambiado.
       CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.end_address ELSE excluded.end_address END,
       CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.lat ELSE excluded.lat END,
       CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.lng ELSE excluded.lng END,
       CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.end_lat ELSE excluded.end_lat END,
       CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.end_lng ELSE excluded.end_lng END,
       excluded.weight, excluded.branch_id,
       excluded.order_date, excluded.pedido_updated_at, excluded.estado, excluded.archivado,
       excluded.fecha_comprometida, excluded.requiere_domicilio, excluded.pedido_costo,
       excluded.municipio, excluded.vendedor, excluded.sucursal_codigo,
       excluded.factura_estado, excluded.factura_numero, excluded.factura_at,
       excluded.factura_domicilio, excluded.factura_corregido_at, excluded.items_origen,
       CASE WHEN punto_se_conserva(orders.punto_manual, orders.end_lat, orders.end_lng, excluded.end_lat, excluded.end_lng) THEN orders.delivery_distance_km ELSE excluded.delivery_distance_km END,
       excluded.delivery_price,
       excluded.almacen_salida_codigo, excluded.almacen_salida_nombre,
       excluded.almacen_salida_sucursal, excluded.almacen_salida_mezclado,
       excluded.almacen_salida_motivo,
       CASE WHEN orders.punto_manual THEN excluded.end_lat ELSE NULL END,
       CASE WHEN orders.punto_manual THEN excluded.end_lng ELSE NULL END,
       CASE WHEN orders.punto_manual THEN excluded.end_address ELSE NULL END,
       excluded.folio, NULL::timestamptz, NULL::uuid)
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

-- ---------------------------------------------------------------------------
-- La adopción entre PEDIDO y la factura de Ventra  (issue 20, 00025)
-- ---------------------------------------------------------------------------
--
-- Mientras conviven las dos fuentes (`SYNC_FUENTE=ambas`), el mismo pedido llega como fila de
-- PEDIDO (`external_id` = su id) y como entrega de factura (`external_id` = `factura:<clave>`,
-- la convención que define `espejo.EsDeFactura`). La identidad entre las dos es
-- (`sucursal_codigo`, `folio_normalizado(folio)`): el folio se guarda tal cual, pero se COMPARA en
-- mayúsculas y sin nada que no sea letra o dígito (00025, auditoría G3: `pxx-900`, `'PXX-900` y
-- `PXX - 900` son el `PXX-900` de PEDIDO). Su gemela en Go es `alcance.FolioNormalizado`. Estas consultas van juntas, dentro de la transacción de
-- `EspejoGuardarPedido`, y en este orden: candado, adoptar o descartar, y el upsert de siempre.
--
-- `starts_with(external_id, 'factura:')` ES LA GEMELA SQL DE `espejo.EsDeFactura`: si una
-- cambia, cambia la otra (las ata `TestMotorReal_LaAdopcion…`, no un comentario).

-- EL CANDADO DEL FOLIO. Sin él, un ciclo de PEDIDO y uno de factura que traen el mismo folio a
-- la vez, sin fila previa de ninguno, insertan cada uno la suya (external_id distinto, nada
-- que choque) y el pedido sale DOS veces. Un candado de transacción por (sucursal, folio) los
-- pone en fila; el segundo ya ve la fila del primero. Se suelta solo al terminar la transacción.
-- name: BloquearFolioDePedido :exec
SELECT pg_advisory_xact_lock(
    hashtextextended('orders-folio:' || sqlc.arg('sucursal_codigo')::text || ':' || folio_normalizado(sqlc.arg('folio')::text), 0));

-- ADOPTAR: la fila de PEDIDO de ese folio pasa a ser la de la factura, cambiándole SOLO el
-- `external_id`. Conserva el `id` y con él la ruta, `stop_order`, el resultado, el punto a mano
-- y todo lo que es del reparto; los campos del mapeo los pone el upsert que viene detrás.
--
-- Una sola fila (`LIMIT 1` por antigüedad) por si PEDIDO repitiera el folio: dos filas con el
-- mismo `external_id` nuevo chocarían con el índice único. Y no adopta si el `external_id` de
-- la factura ya existe (carrera sin candado, o fila ya adoptada): entonces el upsert normal
-- actualiza la de la factura.
-- name: AdoptarPedidoPorFolio :execrows
UPDATE orders SET external_id = sqlc.arg('external_id')::text
WHERE id = (
    SELECT o.id FROM orders o
    WHERE o.source = 'pedido'
      AND o.sucursal_codigo = sqlc.arg('sucursal_codigo')::text
      AND folio_normalizado(o.folio) = folio_normalizado(sqlc.arg('folio')::text)
      AND o.external_id IS NOT NULL
      AND NOT starts_with(o.external_id, 'factura:')
    ORDER BY o.created_at ASC, o.id ASC
    LIMIT 1)
  AND NOT EXISTS (
    SELECT 1 FROM orders x
    WHERE x.source = 'pedido' AND x.external_id = sqlc.arg('external_id')::text);

-- ADOPTAR LA FILA ANTIGUA DE UNA FACTURA (22/10/2026, «la entrega es una factura»). Hasta ese día la
-- entrega de una factura CON folio se guardaba como `factura:<SUC>:<folio normalizado>`, juntando todas
-- las facturas del folio en un conduce «a, b». Ahora la clave es siempre la de la factura
-- (`factura:<SUC>:<punto>:<n>:<fecha>`), y sin esto cada fila con folio ya guardada se duplicaría: la que
-- va en una ruta quedaría doble (ella y las facturas nuevas en «Sin colocar»).
--
-- Adopta la fila antigua si el número de ESTA factura está en su conduce (una factura o varias): le
-- cambia el `external_id` a la clave nueva y conserva el `id`, la ruta, el orden, el resultado y el
-- punto a mano; el upsert que viene detrás le pone el mapeo (renglones y conduce de esta sola factura).
-- Si el conduce tiene varias, la adopta la PRIMERA de sus facturas vivas que llega, y el espejo las
-- procesa ordenadas por número (`espejo.UnaEntregaPorFactura`), así que es determinista; las demás
-- facturas del conduce nacen como filas nuevas. Si ninguna de sus facturas viene viva, nadie la adopta
-- y `retirarLoQueYaNoViene` sigue su camino de siempre.
--
-- La fila antigua se halla por su `external_id` EXACTO (índice único), calculado con la misma regla
-- con la que se escribió: `factura:` + sucursal + `:` + folio normalizado. Misma salvaguarda que
-- `AdoptarPedidoPorFolio`: no adopta si la clave nueva ya existe.
-- name: AdoptarEntregaAntiguaDeFactura :execrows
UPDATE orders SET external_id = sqlc.arg('external_id')::text
WHERE id = (
    SELECT o.id FROM orders o
    WHERE o.source = 'pedido'
      AND o.external_id = 'factura:' || sqlc.arg('sucursal_codigo')::text || ':' || folio_normalizado(sqlc.arg('folio')::text)
      AND o.sucursal_codigo = sqlc.arg('sucursal_codigo')::text
      AND EXISTS (
        SELECT 1 FROM unnest(string_to_array(o.operation_number, ',')) AS n
        WHERE btrim(n) = sqlc.arg('numero_de_factura')::text))
  AND NOT EXISTS (
    SELECT 1 FROM orders x
    WHERE x.source = 'pedido' AND x.external_id = sqlc.arg('external_id')::text);

-- ¿YA LO ADOPTÓ UNA FACTURA? La pregunta del lado de PEDIDO: si hay una fila de factura con
-- ese (sucursal, folio), el pedido de PEDIDO NO crea otra. No es un fallo: es la convivencia.
-- name: ExisteEntregaDeFacturaDelFolio :one
SELECT EXISTS (
    SELECT 1 FROM orders o
    WHERE o.source = 'pedido'
      AND o.sucursal_codigo = sqlc.arg('sucursal_codigo')::text
      AND folio_normalizado(o.folio) = folio_normalizado(sqlc.arg('folio')::text)
      AND o.external_id IS NOT NULL
      AND starts_with(o.external_id, 'factura:')
)::boolean AS existe;

-- ---------------------------------------------------------------------------
-- Lo que ya no viene en Ventra  (issue 20, «ya no va»)
-- ---------------------------------------------------------------------------

-- LAS ENTREGAS DE FACTURA DE UNA VENTANA, para saber cuáles ya no aparecen en la respuesta de
-- Ventra. SOLO las de factura (`factura:`), de ESA sucursal y cuyo día de factura en Cuba cae
-- DENTRO de [desde, hasta]: una fila fuera de la ventana consultada no se puede juzgar, porque
-- Ventra no fue preguntada por ella. El día se pasa a hora de Cuba igual que los filtros de
-- fecha de la factura (issue 16, `coalesce(factura_at, order_date, created_at)`).
-- `ocupada` es lo que impide retirarla: va o fue en una ruta, o tiene resultado.
--
-- LAS YA ANULADAS (`anulada_at`, 00027) NO SE LISTAN: ya se quitaron de su ruta y se marcaron. Sin esta
-- línea el ciclo siguiente las vería «sin ruta, y ya no vienen» y las BORRARÍA, y con ellas el aviso.
-- name: EntregasDeFacturaEnVentana :many
SELECT o.id, o.external_id,
       (o.route_id IS NOT NULL OR o.ultima_ruta_id IS NOT NULL
        OR o.resultado IS NOT NULL OR o.delivered_at IS NOT NULL)::boolean AS ocupada
FROM orders o
WHERE o.source = 'pedido'
  AND o.external_id IS NOT NULL
  AND starts_with(o.external_id, 'factura:')
  AND o.sucursal_codigo = sqlc.arg('sucursal_codigo')::text
  AND o.anulada_at IS NULL
  AND (coalesce(o.factura_at, o.order_date, o.created_at) AT TIME ZONE 'America/Havana')::date
        BETWEEN sqlc.arg('desde')::date AND sqlc.arg('hasta')::date;

-- QUITAR DE SU RUTA LA FACTURA QUE VENTRA YA NO MANDA y dejarla MARCADA (00027, Jose y Amado,
-- 23/10/2026). Es `SoltarParadaPlanificada` (`DELETE /api/routes/{id}/stops/{orderId}`) con tres
-- diferencias, y las tres son a propósito:
--
--   · sirve para rutas `planned` Y `in_progress` (la anulada ya iba en el camión), nunca `completed`
--     ni `cancelled`: el histórico se fija al completar;
--   · la fila NO se borra: queda `archivado = true` con `anulada_at` y `anulada_de_ruta_id`, y así
--     ninguna lista, contador, armado ni tablero la cuenta (todas excluyen `archivado`) y la app
--     puede decir «esta factura se canceló y se quitó de la ruta X»;
--   · NO vuelve a su zona del tablero (`board_route_origins` se borra sin restaurar): una factura
--     cancelada no tiene que reaparecer en ninguna columna. Su colocación, si la hubiera, también se va.
--
-- `ultima_ruta_id` a NULL por lo mismo que en `SoltarParadaPlanificada` (la parada fantasma, 07/10/2026):
-- el trigger de totales (`refrescar_totales_de_ruta`) recalcula peso, importe y «sin cotizar» de la ruta
-- en esta misma sentencia. Los `stop_order` de las demás no se renumeran (queda un hueco, como allí).
--
-- LAS GUARDAS ESTÁN AQUÍ Y SÓLO AQUÍ (quien llama no las repite): factura (`factura:`), ruta sin
-- completar, SIN resultado y SIN entrega, y aún no anulada. Entre la lectura y esta orden el logístico
-- puede haber cerrado la ruta, y una factura que ya se entregó no se toca.
-- name: AnularEntregasDeFacturaEnRuta :many
WITH quitadas AS (
    UPDATE orders o SET
        anulada_at = now(), anulada_de_ruta_id = o.route_id, archivado = true,
        route_id = NULL, ultima_ruta_id = NULL, stop_order = NULL, segment_km = NULL,
        trip_leg = 'outbound',
        -- UNA FACTURA CANCELADA SALE DE SU CONDUCE (00029, regla 7). La actualización es de ella; los demás
        -- miembros los suelta `liberados`, aquí abajo.
        conduce_principal_id = NULL
    FROM routes r
    WHERE o.id = ANY(sqlc.arg('ids')::uuid[])
      AND o.source = 'pedido'
      AND o.external_id IS NOT NULL
      AND starts_with(o.external_id, 'factura:')
      AND r.id = o.route_id
      AND r.status IN ('planned', 'in_progress')
      AND o.resultado IS NULL
      AND o.delivered_at IS NULL
      AND o.anulada_at IS NULL
    RETURNING o.id, o.external_id, o.anulada_de_ruta_id AS ruta_id
), liberados AS (
    -- SI SE CANCELA LA PRINCIPAL, LOS MIEMBROS QUEDAN SUELTOS (regla 7): salen de su conduce y, como la principal
    -- ya no va en la ruta, también de la ruta (si no tienen resultado: un miembro entregado es historial). Nada
    -- se destruye. Los miembros que SON de `quitadas` (cancelados en la misma tanda) los trata la primera
    -- cláusula: tocar dos veces la misma fila en una sentencia no está definido.
    UPDATE orders m SET
        conduce_principal_id = NULL,
        route_id       = CASE WHEN m.resultado IS NULL AND m.delivered_at IS NULL THEN NULL ELSE m.route_id END,
        ultima_ruta_id = CASE WHEN m.resultado IS NULL AND m.delivered_at IS NULL THEN NULL ELSE m.ultima_ruta_id END,
        stop_order     = CASE WHEN m.resultado IS NULL AND m.delivered_at IS NULL THEN NULL ELSE m.stop_order END,
        segment_km     = CASE WHEN m.resultado IS NULL AND m.delivered_at IS NULL THEN NULL ELSE m.segment_km END
    FROM quitadas q
    WHERE m.conduce_principal_id = q.id
      AND NOT EXISTS (SELECT 1 FROM quitadas q2 WHERE q2.id = m.id)
), origenes AS (
    DELETE FROM board_route_origins b
    USING quitadas q
    WHERE b.order_id = q.id AND b.route_id = q.ruta_id
), colocaciones AS (
    DELETE FROM board_placements p
    USING quitadas q
    WHERE p.order_id = q.id
)
SELECT id, external_id, ruta_id FROM quitadas;

-- RETIRAR LAS QUE YA NO VAN. Aunque quien llama ya filtró, la guarda se repite en el propio
-- DELETE: entre la lectura y el borrado una ruta puede haberla recogido, y borrar lo que ya
-- está en el camión es justo lo que no puede pasar. Solo `factura:`, solo sin ruta ni resultado.
-- El borrado deja su lápida (`trg_orders_salida`) y los aparatos la quitan.
-- name: RetirarEntregasDeFactura :execrows
DELETE FROM orders
WHERE id = ANY(sqlc.arg('ids')::uuid[])
  AND source = 'pedido'
  AND external_id IS NOT NULL
  AND starts_with(external_id, 'factura:')
  AND route_id IS NULL AND ultima_ruta_id IS NULL
  AND resultado IS NULL AND delivered_at IS NULL;

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
       almacen_salida_codigo, almacen_salida_nombre, factura_numero
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
--
-- `factura_numero` (00026) es la factura de Ventra de la que sale ESTE renglón, un solo número.
-- Sólo la escribe el espejo de facturas; los renglones de PEDIDO la dejan NULL.
-- name: CrearRenglonDePedido :one
INSERT INTO order_items (
    order_id, linea, description, quantity, packs, product_id,
    nombre, codigo, almacen_nombre, caso, peso_unitario_kg, peso_linea_kg, origen_peso,
    almacen_salida_codigo, almacen_salida_nombre, factura_numero
)
VALUES (
    sqlc.arg('pedido_id'), sqlc.arg('linea'), sqlc.arg('description'),
    sqlc.arg('quantity'), sqlc.narg('packs'), sqlc.narg('product_id'),
    sqlc.narg('nombre'), sqlc.narg('codigo'), sqlc.narg('almacen_nombre'),
    sqlc.narg('caso'), sqlc.narg('peso_unitario_kg'), sqlc.narg('peso_linea_kg'),
    sqlc.narg('origen_peso'),
    sqlc.narg('almacen_salida_codigo'), sqlc.narg('almacen_salida_nombre'),
    sqlc.narg('factura_numero')
)
RETURNING id, order_id, linea, description, quantity, packs, product_id,
          nombre, codigo, almacen_nombre, caso, peso_unitario_kg, peso_linea_kg,
          origen_peso, almacen_salida_codigo, almacen_salida_nombre, factura_numero;

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
-- REPARTIBLE es el mismo listón del armador de rutas —sin ruta, con coordenadas, con
-- factura que se puede llevar (`igual` o `cambiado`) y, desde el 07/10/2026, con el domicilio
-- cobrado (`factura_domicilio > 0`) y cotizado, que desde el 16/10/2026 NO se exigen — TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro, restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md)—:
-- si el panel contara otra cosa, diría «40 por repartir» y el armador ofrecería 12, y la
-- respuesta correcta sería «ninguno de los dos». `sin_ruta` y `peso_pendiente` llevan las mismas condiciones que
-- `PanelPorSucursal` y que `ContarPedidosDisponibles`.
-- name: PanelResumen :one
SELECT
    -- LOS CONTEOS SON DE FILAS PROPIAS (un miembro de conduce va dentro de su principal, 00029) y las SUMAS
    -- de peso e importe llevan todas las facturas: el camión carga el conduce entero.
    count(*) FILTER (WHERE o.conduce_principal_id IS NULL)          AS total_pedidos,
    count(*) FILTER (WHERE o.conduce_principal_id IS NULL
                       AND o.route_id IS NULL
                       AND o.end_lat IS NOT NULL
                       AND o.factura_estado IN ('igual','cambiado')) AS sin_ruta,
    count(*) FILTER (WHERE o.conduce_principal_id IS NULL
                       AND o.delivered_at >= sqlc.arg('hoy')::timestamptz) AS entregados_hoy,
    coalesce(sum(o.weight) FILTER (WHERE o.route_id IS NULL
                       AND o.end_lat IS NOT NULL
                       AND o.factura_estado IN ('igual','cambiado')), 0)::double precision AS peso_pendiente,
    coalesce(sum(o.pedido_costo), 0)::double precision              AS total_domicilios
FROM orders o
-- NO CUENTA LO ARCHIVADO (23/10/2026, 00027): una factura anulada y quitada de su ruta queda
-- archivada, sin ruta y con coordenadas, y sin esto entraba en `sin_ruta` y en `peso_pendiente`
-- como si hubiera que repartirla. Es la misma regla de `ListarPedidosDisponibles`.
WHERE NOT o.archivado
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid);

-- El reparto de lo repartible por sucursal. Lo ve quien no tiene alcance —el Super Admin—;
-- a quien sí lo tiene le sale una sola fila, que es justo lo correcto.
-- name: PanelPorSucursal :many
SELECT
    o.branch_id,
    b.name    AS sucursal_nombre,
    -- Filas propias (el miembro va dentro de su principal, 00029); el peso lleva todas las facturas.
    count(*) FILTER (WHERE o.conduce_principal_id IS NULL) AS pedidos,
    coalesce(sum(o.weight), 0)::double precision AS peso_kg
FROM orders o
LEFT JOIN branches b ON b.id = o.branch_id
WHERE o.route_id IS NULL
  AND NOT o.archivado
  AND o.end_lat IS NOT NULL
  AND o.factura_estado IN ('igual','cambiado')
  -- TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro,
  -- restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md).
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.branch_id, b.name
ORDER BY pedidos DESC;

-- El informe. `ingreso` es `price` si lo hay y si no `pedido_costo`: `price` es el reparto
-- de carga de una ruta y `pedido_costo` lo que cobró Entrega; no son lo mismo y cobrar uno
-- por el otro es el error que este COALESCE hace visible en un solo sitio.
--
-- `operation_number` y `factura_numero` salen CRUDOS (issue 9 de Amado: la columna de
-- facturas). «El número de factura» es SÓLO `factura_numero` (el de Ventra; el folio
-- `operation_number` NO lo es y no hace de respaldo): lo decide `numeroDeFactura` en
-- `internal/api/informes.go`, atado al aparato por `docs/numero-de-factura.casos.json`, que
-- lleva un folio distinto en cada pedido para que se vea si alguien lo usa. No se resuelve
-- aquí en SQL a propósito: son DOS escritos de la regla y no tres.
-- name: ListarPedidosParaInforme :many
SELECT
    o.id, o.customer_name, o.address, o.end_address, o.weight,
    coalesce(o.price, o.pedido_costo, 0) AS ingreso,
    o.segment_km, o.created_at,
    o.operation_number, o.factura_numero,
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
-- LAS FACTURAS ANULADAS RECIENTES (00027) ENTRAN TAMBIÉN, con `anuladas_desde` puesto: son filas
-- archivadas que el aparato NUEVO quiere ver (para decir «la factura 47412 se canceló y se quitó de
-- la ruta Centro») y que, sin esto, saldrían sólo en `quitados`. Va en la carga inicial también: un
-- aparato que se instala hoy tiene que enterarse de lo que se canceló ayer. Nulo = no se pide (el
-- aparato anterior a la 1.0.43, que no sabe qué hacer con una fila archivada). Quien contesta la
-- bajada decide qué hace con ellas (`pedidosDeLaBajada`).
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
        o.items_origen, o.almacen_salida_codigo,
        o.punto_manual, o.punto_manual_por, o.punto_manual_at,
        o.folio,
        o.punto_cliente_lat, o.punto_cliente_lng, o.punto_cliente_address,
        o.anulada_at, o.anulada_de_ruta_id,
        -- LOS MIEMBROS DE CONDUCE BAJAN AL APARATO (regla 9): trabaja sin conexión y los oculta él. NO se filtran aquí.
        o.conduce_principal_id,
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
      AND (sqlc.arg('con_archivados')::boolean OR NOT o.archivado
           OR (sqlc.narg('anuladas_desde')::timestamptz IS NOT NULL
               AND o.anulada_at >= sqlc.narg('anuladas_desde')::timestamptz))
)
SELECT
    id, operation_number, customer_name, customer_phone, address, end_address,
    end_lat, end_lng, lat, lng, weight, status, trip_leg, notes, route_id,
    ultima_ruta_id, price, segment_km, delivery_price,
    delivery_distance_km, branch_id, source, external_id, order_date,
    pedido_updated_at, estado, archivado, fecha_comprometida, requiere_domicilio,
    pedido_costo, municipio, vendedor, sucursal_codigo, factura_estado,
    factura_numero, factura_at, factura_domicilio, factura_corregido_at,
    -- El almacén del que sale el pedido: con él, el aparato pone primero en «Sin colocar» los
    -- del almacén elegido arriba sin preguntar a nadie (`docs/orden-sin-colocar.casos.json`).
    items_origen, almacen_salida_codigo,
    -- El punto de entrega puesto a mano (00024): el aparato pinta la parada diferenciada y no
    -- hay otra forma de saberlo sin señal. Lo ata `la_bajada_no_pierde_campos_test.go`.
    punto_manual, punto_manual_por, punto_manual_at,
    -- De qué pedido de PEDIDO viene la factura (`orders.folio`, 00025): la tabla lo dice.
    folio,
    -- El punto que traía el cliente (null si no es manual): el aparato vuelve a él SIN conexión copiando
    -- estos tres a `endLat`/`endLng`/`endAddress`.
    punto_cliente_lat, punto_cliente_lng, punto_cliente_address,
    -- La factura anulada y quitada de su ruta (00027): sólo viaja en las filas archivadas que
    -- `anuladas_desde` deja entrar; en el resto, null.
    anulada_at, anulada_de_ruta_id,
    conduce_principal_id,
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
