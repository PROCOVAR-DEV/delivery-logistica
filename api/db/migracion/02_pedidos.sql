-- Los pedidos, sus renglones y las rutas.
--
-- Va aparte del 01 porque es la parte pesada: 55.495 pedidos y 85.902 renglones en el
-- volcado del 14/09/2026.

SET search_path = nuevo, public;

-- --------------------------------------------------------------------------
-- LOS DUPLICADOS DEL ESPEJO. Primero, porque si no el traspaso ni arranca.
--
-- # Qué se encontró
--
-- El esquema nuevo pone ÚNICO el índice `(source, external_id)` para que dos pasadas del
-- espejo a la vez no creen el mismo pedido dos veces. Al traspasar los datos reales del
-- 14/09/2026 esa restricción saltó: **en producción ya hay 22 pedidos duplicados**.
--
-- No era una carrera hipotética. Se ve en los propios identificadores — `cmt7p7o45002z` y
-- `cmt7p7o470031`, el mismo cliente, el mismo día, milisegundos de diferencia: dos
-- pasadas leyeron «no existe» antes de que ninguna escribiera.
--
-- De las 44 filas implicadas, 17 no están archivadas, así que **salen dos veces en la
-- lista del armador**. Ninguna llegó a una ruta, así que no hay daño hecho todavía.
--
-- # Qué se hace con ellas, y por qué no se borran
--
-- Se queda UNA por pedido y las demás se apartan a `orders_duplicados`, con la fila
-- entera. No se tiran: son datos de producción y la regla de la casa es que nada
-- desaparece en silencio. Alguien tiene que poder mirarlas.
--
-- Gana la que más ha vivido, en este orden:
--   1. la que tiene resultado de entrega — esa ya se repartió y manda sobre cualquier otra
--   2. la que está en una ruta
--   3. la que NO está archivada — la archivada es la que PEDIDO dio de baja
--   4. la tocada más tarde
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nuevo.orders_duplicados (
    id              text PRIMARY KEY,
    source          text,
    external_id     text,
    customer_name   text,
    archivado       boolean,
    created_at      timestamptz,
    updated_at      timestamptz,
    -- La fila entera, tal cual estaba. Para poder mirarla sin ir al volcado.
    fila            jsonb NOT NULL,
    apartado_at     timestamptz NOT NULL DEFAULT now(),
    motivo          text NOT NULL DEFAULT 'duplicado del espejo: (source, external_id) repetido'
);

INSERT INTO nuevo.orders_duplicados (id, source, external_id, customer_name, archivado, created_at, updated_at, fila)
SELECT o.id, o.source, o."externalId", o."customerName", o.archivado, o."createdAt", o."updatedAt", to_jsonb(o)
FROM (
    SELECT *, row_number() OVER (
        PARTITION BY source, "externalId"
        ORDER BY (resultado IS NOT NULL) DESC,
                 ("routeId" IS NOT NULL) DESC,
                 archivado ASC,
                 "updatedAt" DESC
    ) AS puesto
    FROM public."Order"
    WHERE source IS NOT NULL AND "externalId" IS NOT NULL
) o
WHERE o.puesto > 1
ON CONFLICT (id) DO NOTHING;

INSERT INTO nuevo.orders (
    id, operation_number, customer_name, address, end_address, end_lat, end_lng, lat, lng,
    weight, status, trip_leg, notes, price, segment_km, delivery_price,
    delivery_distance_km, branch_id, source, external_id, order_date, pedido_updated_at,
    estado, archivado, fecha_comprometida, requiere_domicilio, pedido_costo, municipio,
    vendedor, sucursal_codigo, factura_estado, factura_numero, factura_at,
    factura_domicilio, factura_corregido_at, customer_phone, stop_order, delivered_at,
    resultado, resultado_at, resultado_nota, created_at, updated_at)
SELECT
    md5(o.id)::uuid, o."operationNumber", o."customerName", o.address, o."endAddress",
    o."endLat", o."endLng", o.lat, o.lng, o.weight,
    CASE WHEN o.status = 'delivered' THEN 'delivered' ELSE 'pending' END::nuevo.order_status,
    CASE WHEN o."tripLeg" = 'return' THEN 'return' ELSE 'outbound' END::nuevo.trip_leg,
    o.notes,
    o.price, o."segmentKm", o."deliveryPrice", o."deliveryDistanceKm",
    CASE WHEN o."branchId" IS NULL THEN NULL ELSE md5(o."branchId")::uuid END,
    CASE WHEN o.source = 'pedido' THEN 'pedido' END::nuevo.procedencia,
    o."externalId", o."orderDate", o."pedidoUpdatedAt",
    -- Sólo los dos valores que existen de verdad. Cualquier otro se deja vacío en vez de
    -- inventarle un sitio: vacío significa «no lo sé», que es la verdad.
    CASE WHEN o.estado IN ('completada','en_proceso') THEN o.estado END::nuevo.pedido_estado,
    o.archivado, o."fechaComprometida", o."requiereDomicilio", o."pedidoCosto",
    o.municipio, o.vendedor, o."sucursalCodigo",
    CASE WHEN o."facturaEstado" IN ('igual','cambiado','sin_factura') THEN o."facturaEstado" END::nuevo.factura_estado,
    o."facturaNumero", o."facturaAt", o."facturaDomicilio", o."facturaCorregidoAt",
    o."customerPhone", o."stopOrder", o."deliveredAt",
    CASE WHEN o.resultado IN ('entregado','devuelto','cancelado') THEN o.resultado END::nuevo.stop_result,
    o."resultadoAt", o."resultadoNota", o."createdAt", o."updatedAt"
FROM public."Order" o
WHERE o.id NOT IN (SELECT id FROM nuevo.orders_duplicados)
ON CONFLICT (id) DO NOTHING;

-- --------------------------------------------------------------------------
-- Los renglones: de un JSON por pedido a una fila por línea.
--
-- `ordinality` da el número de línea, que es el orden en que venían en el pedido. Hace
-- falta para que la hoja del despacho salga en el mismo orden que el papel del vendedor.
--
-- `description` sale de `name` y no de `descripcion`: en los datos reales `descripcion`
-- dice «SIN DESCRIPCION» en la inmensa mayoría, y lo que la gente lee es el nombre.
-- --------------------------------------------------------------------------
INSERT INTO nuevo.order_items (
    order_id, linea, description, quantity, packs, nombre, codigo, almacen_nombre,
    caso, peso_unitario_kg, peso_linea_kg, origen_peso)
SELECT
    md5(o.id)::uuid,
    e.ord::int,
    coalesce(nullif(e.item->>'name',''), nullif(e.item->>'descripcion',''), '(sin nombre)'),
    coalesce((e.item->>'quantity')::double precision, 0),
    (e.item->>'packs')::double precision,
    e.item->>'name',
    e.item->>'code',
    e.item->>'whName',
    (e.item->>'matched')::boolean,
    coalesce((e.item->>'unitWeightKg')::double precision, (e.item->>'pesoKg')::double precision),
    coalesce((e.item->>'pesoLineaKg')::double precision, (e.item->>'weightKg')::double precision),
    e.item->>'weightSource'
FROM public."Order" o,
     LATERAL jsonb_array_elements(o.items::jsonb) WITH ORDINALITY AS e(item, ord)
WHERE o.id NOT IN (SELECT id FROM nuevo.orders_duplicados)
ON CONFLICT (order_id, linea) DO NOTHING;

-- --------------------------------------------------------------------------
-- Rutas. Después de los pedidos, porque `route_id` los apunta.
-- --------------------------------------------------------------------------
INSERT INTO nuevo.routes (id, name, route_code, status, origin_address, origin_lat, origin_lng,
                          total_distance, total_weight, total_price, delivery_date, vehicle_id,
                          branch_id, started_at, finished_at, optimized, created_at, updated_at)
SELECT md5(r.id)::uuid, r.name, r."routeCode",
       CASE r.status WHEN 'in_progress' THEN 'in_progress' WHEN 'completed' THEN 'completed'
                     WHEN 'cancelled' THEN 'cancelled' ELSE 'planned' END::nuevo.route_status,
       r."originAddress", r."originLat", r."originLng", r."totalDistance", r."totalWeight",
       r."totalPrice", r."deliveryDate",
       CASE WHEN r."vehicleId" IS NULL THEN NULL ELSE md5(r."vehicleId")::uuid END,
       CASE WHEN r."branchId" IS NULL THEN NULL ELSE md5(r."branchId")::uuid END,
       r."startedAt", r."finishedAt", r.optimized, r."createdAt", r."updatedAt"
FROM public."Route" r
ON CONFLICT (id) DO NOTHING;

-- Y ahora sí los dos punteros de ruta, que necesitaban las rutas creadas.
UPDATE nuevo.orders n
SET route_id        = CASE WHEN o."routeId" IS NULL THEN NULL ELSE md5(o."routeId")::uuid END,
    ultima_ruta_id  = CASE WHEN o."ultimaRutaId" IS NULL THEN NULL ELSE md5(o."ultimaRutaId")::uuid END
FROM public."Order" o
WHERE n.id = md5(o.id)::uuid
  AND (o."routeId" IS NOT NULL OR o."ultimaRutaId" IS NOT NULL);

-- --------------------------------------------------------------------------
-- Ajustes y monedas: de un JSON a su tabla.
-- --------------------------------------------------------------------------
UPDATE nuevo.settings s
SET sync_barrido_dia    = v."syncBarridoDia",
    catalogo_traido_at  = v."catalogoTraidoAt",
    currency            = v.currency,
    cup_rate            = v."cupRate",
    cup_rate_updated_at = v."cupRateUpdatedAt"
FROM (SELECT * FROM public."Settings" LIMIT 1) v
WHERE s.id;

INSERT INTO nuevo.currencies (code, rate)
SELECT e->>'code', (e->>'rate')::double precision
FROM (SELECT * FROM public."Settings" LIMIT 1) v,
     LATERAL jsonb_array_elements(v.currencies::jsonb) e
WHERE e->>'code' IS NOT NULL
ON CONFLICT (code) DO UPDATE SET rate = EXCLUDED.rate;
