-- EL GPS DEL DISTRIBUIDOR (00033, 04/11/2026). Lo manda el aparato por lotes; lo lee solo la oficina.

-- De las rutas que dice el punto, SOLO las asignadas a este teléfono (incluidas las ya completadas: el punto de «fin» llega después de completar).
-- name: RutasDelDispositivoEntre :many
SELECT r.id, r.distribuidor_id FROM routes r
WHERE r.id = ANY(sqlc.arg('ruta_ids')::uuid[]) AND r.dispositivo_id = sqlc.arg('dispositivo');

-- Idempotente por `id`: un punto ya recibido no se duplica ni falla. Devuelve las filas NUEVAS.
-- name: GuardarPuntoGps :execrows
INSERT INTO puntos_gps (id, dispositivo_id, distribuidor_id, branch_id, ruta_ids, lat, lng, precision_m, velocidad_ms, rumbo, hora, evento, pedido_id)
VALUES (sqlc.arg('id'), sqlc.arg('dispositivo'), sqlc.narg('distribuidor'), sqlc.arg('sucursal'), sqlc.arg('ruta_ids')::uuid[],
        sqlc.arg('lat'), sqlc.arg('lng'), sqlc.narg('precision_m'), sqlc.narg('velocidad_ms'), sqlc.narg('rumbo'),
        sqlc.arg('hora'), sqlc.narg('evento'),
        -- El pedido solo se guarda si es de una de las rutas del punto (auditoría 04/11/2026: se guardó el de otra sucursal).
        (SELECT o.id FROM orders o WHERE o.id = sqlc.narg('pedido_id')::uuid AND coalesce(o.route_id, o.ultima_ruta_id) = ANY(sqlc.arg('ruta_ids')::uuid[])))
ON CONFLICT (id) DO NOTHING;

-- El recorrido de UNA ruta, en el orden en que se hizo. Acotado a la sucursal de quien pregunta.
-- name: PuntosDeUnaRuta :many
SELECT p.id, p.lat, p.lng, p.precision_m, p.velocidad_ms, p.rumbo, p.hora, p.evento, p.pedido_id
FROM puntos_gps p
WHERE p.ruta_ids @> ARRAY[sqlc.arg('ruta')::uuid]
  AND (sqlc.narg('sucursal')::uuid IS NULL OR p.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY p.hora ASC, p.id ASC
LIMIT sqlc.arg('tope');

-- La vida de un vehículo: sus rutas, de la más reciente a la más antigua, con lo que hizo cada una.
-- name: HistorialDeUnVehiculo :many
SELECT r.id, r.route_code, r.name, r.status, r.delivery_date, r.started_at, r.finished_at, r.total_distance,
       r.distribuidor_id, d.nombre AS distribuidor_nombre,
       (SELECT count(*) FROM orders o WHERE coalesce(o.route_id, o.ultima_ruta_id) = r.id AND o.conduce_principal_id IS NULL) AS paradas,
       (SELECT count(*) FROM orders o WHERE coalesce(o.route_id, o.ultima_ruta_id) = r.id AND o.conduce_principal_id IS NULL AND o.resultado = 'entregado') AS entregadas,
       (SELECT count(*) FROM orders o WHERE coalesce(o.route_id, o.ultima_ruta_id) = r.id AND o.conduce_principal_id IS NULL AND o.resultado = 'devuelto') AS devueltas,
       (SELECT count(*) FROM orders o WHERE coalesce(o.route_id, o.ultima_ruta_id) = r.id AND o.conduce_principal_id IS NULL AND o.cobro_entrega = 'cobrado') AS cobradas,
       (SELECT count(*) FROM puntos_gps p WHERE p.ruta_ids @> ARRAY[r.id]) AS puntos
FROM routes r
LEFT JOIN distribuidores d ON d.id = r.distribuidor_id
WHERE r.vehicle_id = sqlc.arg('vehiculo')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY coalesce(r.started_at, r.delivery_date, r.created_at) DESC
LIMIT sqlc.arg('tope');

-- Dónde está cada TELÉFONO AHORA: su último punto, de los que tienen una ruta en curso. Se identifica por el teléfono (siempre lo hay) y no por el
-- distribuidor de la ruta (puede no tenerlo: el enlace solo exige vehículo); el distribuidor y el vehículo vinculado salen si existen.
-- name: UltimoPuntoDeCadaDistribuidor :many
SELECT DISTINCT ON (p.dispositivo_id)
       p.dispositivo_id, p.distribuidor_id, coalesce(d.nombre, '')::text AS distribuidor_nombre,
       coalesce(v.name, '')::text AS vehiculo_nombre,
       p.lat, p.lng, p.hora, p.recibido_at, p.velocidad_ms, p.ruta_ids
FROM puntos_gps p
LEFT JOIN distribuidores d ON d.id = p.distribuidor_id
LEFT JOIN vinculos_vehiculo_dispositivo vv ON vv.dispositivo_id = p.dispositivo_id AND vv.hasta IS NULL
LEFT JOIN vehicles v ON v.id = vv.vehicle_id
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR p.branch_id = sqlc.narg('sucursal')::uuid)
  AND p.hora > now() - interval '12 hours'
  AND EXISTS (SELECT 1 FROM routes r WHERE r.dispositivo_id = p.dispositivo_id AND r.status = 'in_progress')
ORDER BY p.dispositivo_id, p.hora DESC;

-- Las paradas de una ruta con lo que dijo el distribuidor (resultado, hora real y cobro), para ponerlas sobre el recorrido.
-- name: ParadasConSuHoraDeUnaRuta :many
SELECT o.id, o.factura_numero, o.customer_name, o.end_lat, o.end_lng, o.stop_order, o.resultado, o.resultado_at, o.resultado_nota,
       o.cobro_entrega, o.cobro_entrega_at
FROM orders o
WHERE coalesce(o.route_id, o.ultima_ruta_id) = sqlc.arg('ruta') AND o.conduce_principal_id IS NULL
ORDER BY o.stop_order ASC NULLS LAST, o.created_at ASC;
