-- Rutas: el tablero, el detalle con sus paradas y sus renglones, el armado y el cierre.
--
-- El alcance por sucursal va en el SQL de TODAS, incluidas las escrituras: si el filtro se
-- hiciera en Go después de leer, una ruta de otra sucursal ya habría salido de la base, y
-- un `UPDATE ... WHERE id = $1` a secas cierra la ruta de quien sea.
-- `sqlc.narg('sucursal')` es el parámetro «todas las sucursales»: NULL = no acota.

-- ---------------------------------------------------------------------------
-- El tablero de rutas  (GET /api/routes)
-- ---------------------------------------------------------------------------

-- name: ListarRutas :many
SELECT
    r.id, r.name, r.route_code, r.status, r.origin_address, r.origin_lat,
    r.origin_lng, r.total_distance, r.total_weight, r.total_price,
    -- Cuántas paradas entraron sin costo. Va PEGADO a `total_price` en las dos consultas
    -- a propósito: el total sin ese número al lado es el `$0.00` de RT-20260921-007, que
    -- no dice «no hay tarifa», dice que el reparto fue gratis.
    --
    -- Las tres —`total_weight`, `total_price` y este contador— son la suma de las paradas
    -- de la ruta, y las mantiene la base en cada cambio de paradas desde 00014. Antes se
    -- escribían una sola vez al armar, y por eso lo que se leía aquí era el total del día
    -- del armado y no el de las paradas de hoy.
    --
    -- El `NULL = no consta` que decía aquí **ya no puede darse**: 00014 recalculó todas las
    -- rutas al aplicarse y desde entonces ninguna se queda sin el número. Se sigue leyendo
    -- como puntero por si alguien deshace la migración (su `Down` quita el mantenimiento,
    -- no los valores).
    r.paradas_sin_cotizar,
    r.delivery_date, r.vehicle_id, r.branch_id, r.creado_por,
    r.started_at, r.finished_at, r.optimized, r.created_at, r.updated_at,
    b.name        AS sucursal_nombre,
    b.external_id AS sucursal_codigo,
    v.name        AS vehiculo_nombre,
    v.plate       AS vehiculo_matricula,
    v.capacity    AS vehiculo_capacidad,
    vt.nombre     AS vehiculo_tipo,
    -- Cuántas paradas lleva, para no tener que traerlas todas sólo para enseñar el número.
    (SELECT count(*) FROM orders o WHERE o.route_id = r.id) AS paradas
FROM routes r
LEFT JOIN branches      b  ON b.id  = r.branch_id
LEFT JOIN vehicles      v  ON v.id  = r.vehicle_id
LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid)
  AND (sqlc.narg('estado')::route_status IS NULL OR r.status = sqlc.narg('estado')::route_status)
ORDER BY r.created_at DESC;

-- ---------------------------------------------------------------------------
-- El detalle de una ruta  (GET /api/routes/[id])
-- ---------------------------------------------------------------------------

-- La cabecera. Cero filas es «no existe O no es de tu sucursal»: desde fuera son lo mismo,
-- y tienen que serlo, porque decir «existe pero no es tuya» ya es contar algo.
-- name: ObtenerRuta :one
SELECT
    r.id, r.name, r.route_code, r.status, r.origin_address, r.origin_lat,
    r.origin_lng, r.total_distance, r.total_weight, r.total_price,
    -- Cuántas paradas entraron sin costo. Va PEGADO a `total_price` en las dos consultas
    -- a propósito: el total sin ese número al lado es el `$0.00` de RT-20260921-007, que
    -- no dice «no hay tarifa», dice que el reparto fue gratis.
    --
    -- Las tres —`total_weight`, `total_price` y este contador— son la suma de las paradas
    -- de la ruta, y las mantiene la base en cada cambio de paradas desde 00014. Antes se
    -- escribían una sola vez al armar, y por eso lo que se leía aquí era el total del día
    -- del armado y no el de las paradas de hoy.
    --
    -- El `NULL = no consta` que decía aquí **ya no puede darse**: 00014 recalculó todas las
    -- rutas al aplicarse y desde entonces ninguna se queda sin el número. Se sigue leyendo
    -- como puntero por si alguien deshace la migración (su `Down` quita el mantenimiento,
    -- no los valores).
    r.paradas_sin_cotizar,
    r.delivery_date, r.vehicle_id, r.branch_id, r.creado_por,
    r.started_at, r.finished_at, r.optimized, r.created_at, r.updated_at,
    b.name        AS sucursal_nombre,
    b.external_id AS sucursal_codigo,
    v.name        AS vehiculo_nombre,
    v.plate       AS vehiculo_matricula,
    v.capacity    AS vehiculo_capacidad,
    v.status      AS vehiculo_estado,
    vt.nombre     AS vehiculo_tipo
FROM routes r
LEFT JOIN branches      b  ON b.id  = r.branch_id
LEFT JOIN vehicles      v  ON v.id  = r.vehicle_id
LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
WHERE r.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid);

-- Serializa completar, editar, borrar y marcar sobre la MISMA fila.
-- Debe llamarse dentro de EnTx y conservar el bloqueo hasta terminar la escritura.
-- name: BloquearRuta :one
SELECT status FROM routes
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
FOR UPDATE;

-- Las paradas, en el orden en que el camión las visita.
--
-- Va por `route_id`: es la hoja del camión de HOY, lo que lleva cargado ahora mismo.
-- name: ListarParadasDeRuta :many
SELECT
    o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.lat, o.lng, o.status, o.weight,
    o.price, o.segment_km, o.stop_order, o.trip_leg, o.resultado,
    o.resultado_at, o.resultado_nota, o.delivered_at, o.municipio,
    o.pedido_costo, o.external_id, o.source, o.branch_id
FROM orders o
WHERE o.route_id = sqlc.arg('ruta_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, o.created_at ASC;

-- Las paradas que VIAJARON en esta ruta, se hayan bajado del camión o no.
--
-- La ruta actual se reconoce por `route_id`. Si la parada ya se devolvió o canceló, su
-- `route_id` está NULL y se reconoce por `ultima_ruta_id`, que es lo que deja corregir su
-- resultado histórico. Si las dos columnas divergen, nunca se roba un pedido que ya
-- pertenece a otra ruta.
--
-- # LA RAMA DE `route_id IS NULL` EXIGE `resultado IS NOT NULL` — LA PARADA FANTASMA
--
-- Un devuelto o un cancelado SIEMPRE tiene resultado: es lo que lo suelta de la ruta. Un
-- pedido que simplemente se QUITÓ de una ruta planificada (`SoltarParadaPlanificada`, el
-- «Quitar de ruta» de Amado) no lo tiene, y no viajó nunca. Sin esta condición, un pedido
-- quitado que conservara `ultima_ruta_id = R` seguía saliendo en la hoja de cierre de R:
-- se podía marcar «entregado» desde ahí, y esa marca le devuelve el `route_id = R` a un
-- pedido que quizá ya iba en OTRA ruta, y que el total de R seguía contando como suyo.
-- `SoltarParadaPlanificada` ya no deja ese rastro, pero esta condición es la segunda llave
-- por si la fila viene de antes o la deja otro camino.
--
-- Esta misma condición va en `ListarRenglonesDeRuta`, `MarcarResultadoDeParada` y
-- `LimpiarResultadoDeParada`: las cuatro tienen que contestar lo mismo a «¿viajó este
-- pedido en esta ruta?», y lo ata `consultas_motor_real_test.go`.
-- name: ListarParadasQueViajaronEnRuta :many
SELECT
    o.id, o.operation_number, o.customer_name, o.address, o.end_address,
    o.weight, o.stop_order, o.resultado, o.resultado_at, o.resultado_nota,
    o.delivered_at, o.external_id, o.source, o.branch_id
FROM orders o
WHERE (o.route_id = sqlc.arg('ruta_id')
       OR (o.route_id IS NULL AND o.ultima_ruta_id = sqlc.arg('ruta_id') AND o.resultado IS NOT NULL))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, o.created_at ASC;

-- Los renglones de TODAS las paradas de la ruta, de una vez.
--
-- Es la hoja de carga y la del post-despacho: lo que sube al camión y, al volver, lo que
-- debería seguir arriba. Una sola consulta y no una por parada — con 40 paradas, lo
-- segundo son 40 idas y vueltas por una pantalla que se abre veinte veces al día.
--
-- Por la ruta actual o, para pedidos soltados con resultado (un devuelto o un cancelado),
-- por `ultima_ruta_id`. La condición de `resultado IS NOT NULL` es la de
-- `ListarParadasQueViajaronEnRuta`, que explica por qué: sin ella, los renglones de un
-- pedido quitado de la ruta seguirían en la hoja de carga de una ruta que no lo lleva.
-- name: ListarRenglonesDeRuta :many
SELECT
    oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs, oi.product_id,
    o.customer_name, o.stop_order, o.resultado
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE (o.route_id = sqlc.arg('ruta_id')
       OR (o.route_id IS NULL AND o.ultima_ruta_id = sqlc.arg('ruta_id') AND o.resultado IS NOT NULL))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, oi.linea ASC;

-- Las paradas de VARIAS rutas de una vez, para el tablero.
--
-- Existe para no repetir `ListarParadasDeRuta` una vez por ruta: el tablero sale sin
-- filtro de fecha y con un año de trabajo son cientos de rutas, o sea cientos de idas y
-- vueltas a la base para pintar UNA pantalla. Con un array de ids son tres consultas
-- fijas: las rutas, sus paradas y sus renglones.
--
-- Va por `route_id` —lo que el camión lleva cargado— igual que la de una sola.
-- name: ListarParadasDeRutas :many
SELECT
    o.route_id, o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.lat, o.lng, o.status, o.weight,
    o.price, o.segment_km, o.stop_order, o.trip_leg, o.resultado,
    o.resultado_at, o.resultado_nota, o.delivered_at, o.municipio,
    o.pedido_costo, o.external_id, o.source, o.branch_id
FROM orders o
WHERE o.route_id = ANY(sqlc.arg('ruta_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, o.created_at ASC;

-- Los renglones de las paradas de VARIAS rutas, de una vez.
--
-- Por `route_id` y no por `ultima_ruta_id` a propósito: éstos son los renglones de lo que
-- va EN el camión, que es lo que acompaña a cada parada de la lista. Los de lo que ya se
-- bajó (un devuelto que soltó su `route_id`) son otra pregunta y los trae
-- `ListarRenglonesDeRuta`, que es la del post-despacho.
-- name: ListarRenglonesDeRutas :many
SELECT
    o.route_id, oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs, oi.product_id
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.route_id = ANY(sqlc.arg('ruta_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, oi.linea ASC;

-- ---------------------------------------------------------------------------
-- Armado de ruta  (POST /api/routes)
-- ---------------------------------------------------------------------------

-- Los pedidos elegidos que TODAVÍA se pueden meter en una ruta.
--
-- Esta consulta es la validación, no una lectura previa a ella: se pide por ids y devuelve
-- sólo los que siguen cumpliendo. Si vuelven menos de los que se pidieron, alguien se los
-- llevó entre que se pintó la lista y se pulsó el botón — con diez logísticos armando
-- rutas a la vez eso pasa de verdad — y de ahí sale el 409 con «N de los M ya están en
-- otra ruta». Comprobarlo en Go sobre una lectura anterior es mirar una foto vieja.
--
-- `factura_estado` se deja pasar `igual` y `cambiado` porque es el mismo listón de la
-- lista de disponibles. El corte a sólo `igual` lo hace el handler DESPUÉS, para poder
-- nombrar en el error cuál falla y por qué («cambió en la factura» / «sin cotejar»).
-- Un WHERE que los descarte aquí deja el mismo 409 sin nada que decir.
--
-- `cambiado` NO entra a una ruta (Jose, reglas-negocio.md): en el camión sólo sube lo que
-- cuadra con la factura. Lo que se añadió el 07/10/2026 (Amado) es aparte y se SUMA: el
-- domicilio cobrado (`factura_domicilio > 0`) y cotizado en Entrega (`pedido_costo` no
-- nulo). Esos dos salen también como DATO y los corta el handler, por la misma razón.
-- name: PedidosParaArmarRuta :many
SELECT
    o.id, o.operation_number, o.customer_name, o.end_lat, o.end_lng,
    o.weight, o.pedido_costo, o.factura_estado, o.branch_id, o.external_id, o.source,
    -- LO QUE YA SE ENTREGÓ NO VUELVE A SUBIR A UN CAMIÓN, y `route_id IS NULL` no lo
    -- sabe: un entregado conserva su `route_id`, pero la clave ajena es `ON DELETE SET
    -- NULL` (`db/migrations/00001_init.sql:446`), así que el día que alguien borre la
    -- ruta de ayer los entregados amanecen sueltos y este `WHERE` los da por libres.
    --
    -- Salen como DATO y no como filtro, exactamente igual que `factura_estado` y por la
    -- misma razón: filtrarlos aquí los mandaría al «N de los M ya están en otra ruta»,
    -- que sería FALSO —no están en ninguna ruta, se entregaron— y no se arregla volviendo
    -- a elegirlos. Los nombra `mensajeYaEntregados` en el manejador.
    o.delivered_at, o.resultado,
    -- LO QUE SE COBRÓ DE DOMICILIO EN EL MOSTRADOR, y desde el 07/10/2026 sin ello mayor
    -- que cero el pedido no entra en una ruta (Amado: el domicilio ya es un servicio que
    -- se cobra). Sale como DATO y no como filtro, igual que `factura_estado`: lo nombra
    -- `mensajeDomicilioSinCobrar` en el manejador. `requiere_domicilio`, la casilla que se
    -- marca al tomar el pedido, ya no se lee aquí: no manda nada sobre lo que se cobró.
    o.factura_domicilio
FROM orders o
WHERE o.id = ANY(sqlc.arg('pedido_ids')::uuid[])
  AND o.source = 'pedido'
  AND o.route_id IS NULL
  AND o.end_lat IS NOT NULL
  AND o.end_lng IS NOT NULL
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
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.created_at ASC;

-- POR QUÉ NO SE PUEDE ARMAR CON ÉSTE. Es la explicación del 409, no un filtro.
--
-- `PedidosParaArmarRuta` devuelve MENOS de los que se le piden por cinco motivos distintos
-- —ya va en otra ruta, se quedó sin coordenadas, PEDIDO lo archivó, no vino de PEDIDO, o
-- no es de tu sucursal— y durante meses la diferencia entera se le atribuyó a «ya están en
-- otra ruta». Era el mismo fallo que ya se arregló en el tablero (`tablero.go`,
-- `porQueNoEsCandidato`) y aquí seguía: el motivo equivocado, sin decir CUÁL de los
-- quince, y con un «Vuelve a elegirlos» que para un pedido archivado no arregla nada —
-- volver a pulsar da exactamente lo mismo, que es un rechazo permanente disfrazado de
-- reintento.
--
-- Trae los datos en crudo y el motivo lo decide Go (`porQueNoSeArma`), que es donde están
-- escritas las prioridades: un entregado conserva su `route_id`, así que mirar la ruta
-- primero le contaría al logístico que «otro lo subió a un camión» cuando lo que pasó es
-- que ese pedido ya está en casa del cliente.
--
-- El `LEFT JOIN` es lo que deja NOMBRAR la ruta: «ya va en la ruta RT-20260922-003» le
-- dice a alguien dónde mirar; «ya va en otra ruta» le deja quince rutas que abrir.
--
-- EL ALCANCE VA AQUÍ TAMBIÉN, y por eso un pedido de otra sucursal no devuelve fila: desde
-- fuera «no existe» y «no es tuyo» tienen que ser lo mismo, igual que en `ObtenerRuta`.
-- Quien no devuelve fila se nombra igual, con ese motivo y sin contar nada de él.
-- name: PorQueNoSePuedeArmar :many
SELECT
    o.id, o.operation_number, o.customer_name,
    o.route_id, o.delivered_at, o.resultado,
    o.end_lat, o.end_lng, o.archivado, o.source,
    r.route_code AS ruta_codigo,
    r.name       AS ruta_nombre
FROM orders o
LEFT JOIN routes r ON r.id = o.route_id
WHERE o.id = ANY(sqlc.arg('pedido_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid);

-- Cuántas rutas se llevan hoy, para el `NNN` de `RT-YYYYMMDD-NNN`.
--
-- OJO: no es atómico. Dos armados a la vez leen el mismo número y salen con el mismo
-- código. Delivery tenía la misma carrera; se hereda tal cual para no cambiar el formato
-- del código, que es lo que la gente se dice por teléfono. Si empieza a chocar, la salida
-- es una secuencia por día, no un reintento.
-- name: ContarRutasDelDia :one
SELECT count(*) FROM routes r
WHERE r.route_code LIKE sqlc.arg('prefijo')::text || '%';

-- La ruta nace `planned` y `optimized` en false: los totales y el orden de visita se
-- calculan después, con las paradas ya enganchadas, y se fijan con `FijarTotalesDeRuta`.
--
-- `creado_por` es el id de la persona EN AUTH y es CONSTANCIA, no un filtro: aquí nada
-- pertenece a nadie. Filtrar por el creador fue lo que dejó los 3.528 pedidos importados a
-- nombre del Super Admin y escondió los de Holguín a sus propios compañeros de Holguín.
-- name: CrearRuta :one
INSERT INTO routes (
    name, route_code, origin_address, origin_lat, origin_lng,
    delivery_date, vehicle_id, branch_id, creado_por
) VALUES (
    sqlc.narg('name'), sqlc.arg('route_code'), sqlc.narg('origin_address'),
    sqlc.arg('origin_lat'), sqlc.arg('origin_lng'), sqlc.narg('delivery_date'),
    sqlc.narg('vehicle_id'), sqlc.narg('branch_id'), sqlc.narg('creado_por')
)
RETURNING id, name, route_code, status, origin_address, origin_lat, origin_lng,
          total_distance, total_weight, total_price, delivery_date, vehicle_id,
          branch_id, creado_por, started_at, finished_at, optimized,
          created_at, updated_at;

-- Engancha un pedido a la ruta como parada número `stop_order`.
--
-- `route_id` y `ultima_ruta_id` se ponen los DOS y valen lo mismo hoy: el primero dice
-- «está ocupado» y el segundo «en qué camión fue». Son dos preguntas distintas y con un
-- solo campo no se pueden responder las dos.
--
-- `segment_km` es la distancia RADIAL desde el origen, no la del tramo del recorrido: se
-- hereda así de delivery porque es el número con el que se repartió la carga hasta hoy.
-- `price` es ese reparto de carga y NO el costo del domicilio, que es `pedido_costo`.
--
-- El alcance va aquí también: sin él, mandar el id de un pedido de otra sucursal en
-- `orderIds` lo subiría a tu camión.
--
-- LA SEGUNDA LLAVE DEL DOMICILIO Y LA COTIZACIÓN. `factura_domicilio > 0` y
-- `pedido_costo IS NOT NULL` se comprueban también aquí (07/10/2026, Amado) porque la
-- validación de `PedidosParaArmarRuta` se hizo hace unos milisegundos, y el espejo repasa
-- `pedido_costo` cada minuto: un pedido que perdió su cotización entre medias no puede
-- entrar con el importe a cero. Cero filas lo devuelve el manejador como 409.
--
-- `factura_estado` NO está aquí, y es a propósito: el corte a sólo `igual` lo hace el
-- manejador (`mensajeNoFacturados`, `armarRutaDeColumna`) para poder nombrar cuál falla y
-- por qué. Aquí `cambiado` pasaría igual que antes, y por eso la regla «en el camión sólo
-- sube lo que cuadra» vive en esos dos manejadores y los vigilan sus pruebas.
-- name: EngancharPedidoARuta :execrows
UPDATE orders SET
    route_id       = sqlc.arg('ruta_id'),
    ultima_ruta_id = sqlc.arg('ruta_id'),
    stop_order     = sqlc.arg('stop_order'),
    trip_leg       = 'outbound',
    segment_km     = sqlc.narg('segment_km'),
    price          = coalesce(sqlc.narg('price')::double precision, 0)
WHERE id = sqlc.arg('pedido_id')
  AND route_id IS NULL
  AND factura_domicilio > 0
  AND pedido_costo IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- El recorrido y la firma de quién ordenó, ya con las paradas puestas.
-- `total_distance` es el CIRCUITO CERRADO: los tramos más el regreso al origen. El camión
-- vuelve, y no contar la vuelta subestima el viaje justo a la mitad de las rutas largas.
--
-- `optimized` DICE QUIÉN ORDENÓ LAS PARADAS, y aquí estaba clavado a `true`. Daba igual
-- que el orden fuese el que la persona puso a mano: la ruta se guardaba diciendo que lo
-- había calculado la máquina. Quien lo lee después —la pantalla, un informe, alguien
-- decidiendo si vuelve a optimizar— se creía esa firma, y reoptimizar «lo que ya estaba
-- optimizado» es justo lo que nadie hace. El orden del logístico se perdía sin que nadie
-- lo dijera.
--
-- Va como `narg` y no como `arg` a propósito: NULL significa «lo ordenó la máquina», que
-- es lo que hacía este UPDATE desde siempre, así que ningún llamador que no lo mande
-- cambia de comportamiento por esta línea. Quien sabe la respuesta la manda.
-- AQUÍ YA NO SE ESCRIBEN NI `total_weight` NI `total_price` NI `paradas_sin_cotizar`
-- —29/09/2026—, y ése es el arreglo entero. Esta consulta corre UNA vez, al armar, así que
-- lo que escribiera en esas tres columnas quedaba congelado en el día del armado: el
-- `$0.00` del 22/09 y los «420 kg» sobre 516,5 del 28/09 salieron de ahí. Las tres son la
-- suma de las paradas y las mantiene la base en cada cambio de paradas
-- (`db/migrations/00014_los_totales_de_la_ruta_no_se_congelan.sql`), que es el único sitio
-- donde vive esa aritmética. Volver a ponerlas aquí es volver a tener dos.
--
-- Lo que sí se queda es lo que NO es una suma de las paradas: el recorrido y la firma.
-- name: FijarTotalesDeRuta :one
UPDATE routes SET
    total_distance = sqlc.arg('total_distance'),
    optimized      = coalesce(sqlc.narg('optimizado')::boolean, true)
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, name, route_code, status, origin_address, origin_lat, origin_lng,
          total_distance, total_weight, total_price, paradas_sin_cotizar, delivery_date, vehicle_id,
          branch_id, started_at, finished_at, optimized, created_at, updated_at;

-- ---------------------------------------------------------------------------
-- Cambios de estado de la ruta  (PATCH /api/routes/[id])
-- ---------------------------------------------------------------------------

-- Nombre y estado, con las horas de salida y regreso.
--
-- `started_at` sólo se pone la PRIMERA vez que arranca: volver a marcar `in_progress`
-- después de una corrección no debe reescribir la hora de salida, que es con la que se
-- mide cuánto se demoró. `finished_at` se limpia al arrancar de nuevo por lo mismo.
-- Ninguna de las dos se deduce de `created_at` —la ruta se arma la noche anterior— ni de
-- `updated_at`, que se mueve al tocar cualquier cosa.
-- name: ActualizarEstadoDeRuta :one
WITH actualizada AS (
UPDATE routes SET
    name   = coalesce(sqlc.narg('name')::text, name),
    status = coalesce(sqlc.narg('status')::route_status, status),
    started_at = CASE
        WHEN sqlc.narg('status')::route_status = 'in_progress' AND started_at IS NULL THEN now()
        ELSE started_at
    END,
    finished_at = CASE
        WHEN sqlc.narg('status')::route_status = 'in_progress' THEN NULL
        WHEN sqlc.narg('status')::route_status = 'completed'   THEN now()
        ELSE finished_at
    END
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, name, route_code, status, vehicle_id, branch_id,
          started_at, finished_at, total_distance, total_weight, total_price,
          delivery_date, created_at, updated_at
), origenes_liberados AS (
    DELETE FROM board_route_origins o
    USING actualizada r
    WHERE o.route_id = r.id AND r.status = 'completed'
    RETURNING o.order_id
)
SELECT * FROM actualizada;

-- Cambiar el camión. Va aparte del cambio de estado porque en el contrato tiene prioridad
-- y retorna antes: liberar el camión viejo y ocupar el nuevo es lo único que hace.
-- name: CambiarVehiculoDeRuta :one
UPDATE routes SET
    vehicle_id = sqlc.narg('vehicle_id'),
    name       = coalesce(sqlc.narg('name')::text, name),
    status     = coalesce(sqlc.narg('status')::route_status, status)
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, name, route_code, status, vehicle_id, branch_id,
          started_at, finished_at, created_at, updated_at;

-- ---------------------------------------------------------------------------
-- Cierre de ruta  (POST /api/routes/[id]/results)
-- ---------------------------------------------------------------------------

-- Cómo acabó UNA parada. Es la consulta más delicada del reparto: de aquí sale lo que se
-- le cuenta a PEDIDO y la cuenta del post-despacho.
--
-- Cuatro cosas van juntas a propósito y en una sola sentencia:
--
--  1. El `WHERE` acepta la parada que sigue en la ruta (`route_id`) y, además, la que ya
--     la soltó con un resultado (`route_id` NULL, `ultima_ruta_id` = esta y `resultado` no
--     nulo): así se puede corregir el resultado de un devuelto al cerrar. Y sirve de
--     validación — cero filas significa «ese pedido no va en esta ruta», que es el
--     rechazo del contrato, sin tener que comprobarlo antes en Go sobre una lectura que
--     ya puede estar vieja. El `resultado IS NOT NULL` es el de
--     `ListarParadasQueViajaronEnRuta` (la parada fantasma): un pedido quitado de la ruta
--     no se puede marcar desde su hoja de cierre.
--  2. `route_id = NULL` SÓLO si no se entregó: el pedido baja del camión y vuelve a la
--     lista de disponibles para la ruta de mañana. `ultima_ruta_id` y `stop_order` no se
--     tocan NUNCA: son la hoja de lo que bajó del camión.
--  3. `delivered_at` se limpia cuando no se entregó. Un devuelto que conserve la hora de
--     entrega de un intento anterior se pinta «entregado» en la lista, que es exactamente
--     la contradicción que se vio con un pedido de La Habana el 2 de septiembre.
--  4. `resultado_nota` se guarda siempre: un devuelto sin motivo es un número que nadie
--     sabe explicar tres semanas después.
--
-- Ni `devuelto` ni `cancelado` tocan inventario: el reintegro lo hace Ventra.
-- name: MarcarResultadoDeParada :execrows
UPDATE orders SET
    resultado      = sqlc.arg('resultado')::stop_result,
    ultima_ruta_id = sqlc.arg('ruta_id'),
    resultado_at   = now(),
    resultado_nota = sqlc.narg('nota'),
    delivered_at = CASE
        WHEN sqlc.arg('resultado')::stop_result = 'entregado' THEN now()
        ELSE NULL
    END,
    status = CASE
        WHEN sqlc.arg('resultado')::stop_result = 'entregado' THEN 'delivered'::order_status
        ELSE 'pending'::order_status
    END,
    route_id = CASE
        WHEN sqlc.arg('resultado')::stop_result = 'entregado' THEN sqlc.arg('ruta_id')
        ELSE NULL
    END
WHERE id = sqlc.arg('pedido_id')
  AND (route_id = sqlc.arg('ruta_id')
       OR (route_id IS NULL AND ultima_ruta_id = sqlc.arg('ruta_id') AND resultado IS NOT NULL))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- QUITAR LA MARCA DE UNA PARADA — 28/09/2026.
--
-- Jose: «desmarco el estado de cierre y no se guarda cuando salgo por q razon».
--
-- En la hoja de cierre, pulsar dos veces el mismo botón DESMARCA: es como se corrige un
-- dedazo, y estaba puesto desde el principio en la pantalla. Lo que no existía era el
-- camino de vuelta: el aparato sólo mandaba las paradas CON resultado, así que quitar la
-- marca no producía ningún apunte y la marca vieja seguía en la base. Al volver a abrir la
-- hoja, ahí estaba otra vez. El clásico de «un campo que no viene» leído como «no lo
-- toques» en vez de como «bórralo» — y aquí ni siquiera venía.
--
-- Deshace EXACTAMENTE lo que hizo `MarcarResultadoDeParada`, columna por columna, porque
-- media vuelta atrás es peor que ninguna:
--
--  1. `resultado`, `resultado_at` y `resultado_nota` a NULL. La nota se va con la marca:
--     un motivo de devolución colgando de una parada sin resultado es una explicación de
--     algo que ya no consta.
--  2. `delivered_at` a NULL y `status` a `pending`. Si no, la parada se queda sin resultado
--     pero con hora de entrega, y la lista la pinta «entregada»: la misma contradicción del
--     2 de septiembre, al revés.
--  3. `route_id = ultima_ruta_id`, que es la que MÁS importa y la que no es obvia. Un
--     devuelto SOLTÓ su `route_id` al marcarse; si al desmarcarlo no se le devuelve, el
--     pedido se queda fuera de su ruta —vuelve a la lista de disponibles de mañana— con la
--     ruta todavía abierta, y entonces sale en DOS camiones. `ultima_ruta_id` es la hoja de
--     lo que subió, así que es de ahí de donde se recupera.
--
-- El `WHERE` es el mismo que el de marcar, y por lo mismo: también por `ultima_ruta_id`
-- cuando la parada ya soltó su `route_id` CON UN RESULTADO, para poder desmarcar un
-- devuelto. Cero filas es «ese pedido no va en esta ruta», el rechazo del contrato.
-- name: LimpiarResultadoDeParada :execrows
UPDATE orders SET
    resultado      = NULL,
    ultima_ruta_id = sqlc.arg('ruta_id'),
    resultado_at   = NULL,
    resultado_nota = NULL,
    delivered_at   = NULL,
    status         = 'pending'::order_status,
    route_id       = sqlc.arg('ruta_id')
WHERE id = sqlc.arg('pedido_id')
  AND (route_id = sqlc.arg('ruta_id')
       OR (route_id IS NULL AND ultima_ruta_id = sqlc.arg('ruta_id') AND resultado IS NOT NULL))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- DÓNDE ESTÁN ESTOS PEDIDOS, para el renglón del servidor cuando un cierre rechaza paradas.
--
-- Un «ese pedido no va en esta ruta» llegó a Amado con 409 y sin que el servidor dijera POR
-- QUÉ: si el pedido iba en otra ruta, si nunca tuvo ruta, si es de otra sucursal… Quien lo
-- diagnostica tiene delante sólo el registro, y tenía que ir al VPS a preguntárselo a la
-- base. Esta consulta le da al registro las tres cosas que hacen falta: `route_id`,
-- `ultima_ruta_id` y `branch_id` del pedido (no hay nada secreto en ellas).
--
-- NO LLEVA ALCANCE, A PROPÓSITO, y sólo es seguro por lo que es: la usa únicamente
-- `cerrarRuta` en el camino del rechazo, y su resultado va al REGISTRO del servidor, nunca
-- a la respuesta. Acotarla por sucursal borraría justo la causa más sutil —el pedido es de
-- otra sucursal— y dejaría la línea diciendo «no está» sobre un pedido que sí existe. Es
-- por ids (clave primaria), así que cuesta lo mismo que cualquier lectura de una fila.
-- name: DondeEstanLosPedidos :many
SELECT o.id, o.route_id, o.ultima_ruta_id, o.branch_id
FROM orders o
WHERE o.id = ANY(sqlc.arg('pedido_ids')::uuid[]);

-- ---------------------------------------------------------------------------
-- Borrar una ruta  (DELETE /api/routes/[id])
-- ---------------------------------------------------------------------------

-- QUITAR UNA SOLA PARADA DE UNA RUTA PLANIFICADA (`DELETE /api/routes/{id}/stops/{orderId}`,
-- incidencia 2 de Amado). El pedido NO se borra: se suelta y vuelve a la lista de
-- disponibles, y si la ruta nació del tablero vuelve además a su zona y a su posición.
--
-- # `ultima_ruta_id` TAMBIÉN SE PONE A NULL — LA PARADA FANTASMA, 07/10/2026
--
-- Aquí se conservaba, por el mismo motivo que en `SoltarPedidosDeRuta` («el pasado de un
-- pedido no se reescribe»), y es un error: esa regla es para un pedido que VIAJÓ. Éste no
-- viajó nunca, porque la ruta sigue `planned` y sin resultado. Con `ultima_ruta_id = R`
-- puesto, el pedido seguía siendo «parada de R» para todo lo que pregunta por esa columna:
--
--   · el trigger de totales (`00014`) lo contaba en `total_weight`, `total_price` y
--     `paradas_sin_cotizar` de R, así que la cabecera decía 516 kg sobre una ruta que ya
--     sólo cargaba 420, y la capacidad del camión se medía contra ese número;
--   · salía en la hoja de cierre de R (`ListarParadasQueViajaronEnRuta`) y se podía marcar
--     «entregado» desde ahí, devolviéndole el `route_id` de R a un pedido que quizá ya
--     iba en otra ruta.
--
-- Al ponerla a NULL el trigger recalcula los totales de R en esta misma sentencia, y el
-- pedido deja de ser parada de R. Las otras cuatro consultas que preguntan «¿viajó en R?»
-- llevan además `resultado IS NOT NULL` en la rama de `route_id IS NULL`, por si la fila
-- viene de antes.
--
-- LO QUE NO SE HACE, y queda dicho para que nadie lo busque aquí:
--   · los `stop_order` de las demás paradas NO se renumeran: el orden relativo no cambia,
--     sólo queda un hueco (1, 3, 4…) que ninguna pantalla lee como posición absoluta.
--   · `total_distance` NO se recalcula: es el circuito que midió quien armó la ruta y no
--     una suma de paradas (00014 lo deja fuera a propósito). Tras quitar una parada
--     seguirá diciendo los km del recorrido original hasta que se vuelva a optimizar.
-- name: SoltarParadaPlanificada :one
WITH liberada AS (
    UPDATE orders o SET
        route_id = NULL, ultima_ruta_id = NULL, stop_order = NULL, segment_km = NULL,
        trip_leg = 'outbound'
    FROM routes r
    WHERE o.id = sqlc.arg('pedido_id')
      AND o.route_id = sqlc.arg('ruta_id')
      AND r.id = o.route_id
      AND r.status = 'planned'
      AND o.delivered_at IS NULL
      AND o.resultado IS NULL
      AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    RETURNING o.id AS id
), origen AS (
    DELETE FROM board_route_origins o
    WHERE o.route_id = sqlc.arg('ruta_id')
      AND o.order_id = sqlc.arg('pedido_id')
      AND EXISTS (SELECT 1 FROM liberada)
    RETURNING o.order_id, o.column_id, o.posicion, o.colocado_por
), corrimientos AS (
    UPDATE board_placements p SET posicion = p.posicion + 1
    FROM origen o
    WHERE p.column_id = o.column_id AND p.posicion >= o.posicion
    RETURNING p.order_id
), restaurada AS (
    INSERT INTO board_placements (order_id, column_id, posicion, colocado_por)
    SELECT order_id, column_id, posicion, colocado_por FROM origen
    ON CONFLICT (order_id) DO NOTHING
    RETURNING order_id
)
SELECT sqlc.arg('pedido_id')::uuid AS id FROM liberada;

-- Borrar la ruta entera: los pedidos NO se borran, se sueltan y vuelven a la lista de
-- disponibles. Si la ruta nació del tablero, vuelven además a su zona y a su posición
-- (`board_route_origins`). `ultima_ruta_id` se conserva — el pasado de un pedido no se
-- reescribe porque alguien deshaga la ruta de hoy — y la clave ajena
-- `orders_ultima_ruta_fk` (`ON DELETE SET NULL`) la suelta sola cuando `BorrarRuta`
-- elimina la fila.
-- name: SoltarPedidosDeRuta :execrows
WITH origenes AS (
    SELECT o.route_id, o.order_id, o.column_id, o.posicion, o.colocado_por
    FROM board_route_origins o
    JOIN routes r ON r.id = o.route_id
    JOIN orders pedido ON pedido.id = o.order_id
    WHERE o.route_id = sqlc.arg('ruta_id')
      AND r.status <> 'completed'
      AND pedido.route_id = o.route_id
      AND pedido.delivered_at IS NULL
      AND pedido.resultado IS NULL
      AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid)
), corrimientos AS (
    UPDATE board_placements p SET
        posicion = p.posicion + (
            SELECT count(*)::integer FROM origenes o
            WHERE o.column_id = p.column_id AND o.posicion <= p.posicion
        )
    WHERE EXISTS (SELECT 1 FROM origenes o
                  WHERE o.column_id = p.column_id AND o.posicion <= p.posicion)
    RETURNING p.order_id
), restaurados AS (
    INSERT INTO board_placements (order_id, column_id, posicion, colocado_por)
    SELECT o.order_id, o.column_id,
           o.posicion + (SELECT count(*)::integer FROM origenes prev
                         WHERE prev.column_id = o.column_id AND prev.posicion < o.posicion),
           o.colocado_por
    FROM origenes o
    ON CONFLICT (order_id) DO NOTHING
    RETURNING order_id
)
UPDATE orders SET
    route_id   = NULL,
    stop_order = NULL,
    segment_km = NULL,
    trip_leg   = 'outbound'
WHERE orders.route_id = sqlc.arg('ruta_id')
  -- El histórico se fija al completar: ni aquí se desengancha una parada de una ruta
  -- `completed`. El manejador ya lo impide (`rutaEditableEnTx`); esto es la segunda llave.
  AND NOT EXISTS (SELECT 1 FROM routes cerrada
                  WHERE cerrada.id = orders.route_id AND cerrada.status = 'completed')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR orders.branch_id = sqlc.narg('sucursal')::uuid);

-- name: BorrarRuta :execrows
DELETE FROM routes
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- Para el panel y para la flota
-- ---------------------------------------------------------------------------

-- Rutas vivas. `cancelled` se excluye igual que `completed` aunque hoy nadie lo escriba:
-- el enum lo tiene declarado para no obligar a un ALTER TYPE el día que se use, y el
-- tablero ya lo descarta.
-- name: ContarRutasActivas :one
SELECT count(*) FROM routes r
WHERE r.status NOT IN ('completed', 'cancelled')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid);

-- La ruta viva más reciente de un camión, para la tarjeta de la flota.
-- name: RutaActivaDeVehiculo :one
SELECT r.id, r.name, r.route_code, r.status, r.created_at
FROM routes r
WHERE r.vehicle_id = sqlc.arg('vehiculo_id')
  AND r.status <> 'completed'
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY r.created_at DESC
LIMIT 1;

-- Al liberar un camión a mano se cierra la ruta que llevaba: un camión disponible con una
-- ruta abierta detrás es una ruta que nadie va a cerrar nunca y que sigue contando como
-- activa en el panel.
-- name: CompletarRutasDeVehiculo :execrows
UPDATE routes SET status = 'completed', finished_at = coalesce(finished_at, now())
WHERE vehicle_id = sqlc.arg('vehiculo_id')
  AND status <> 'completed'
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- El buzón de salida hacia PEDIDO
-- ---------------------------------------------------------------------------
--
-- Se escribe en la MISMA transacción que el resultado de la parada: o los dos o ninguno.
-- El porqué entero está en `00010_avisos_a_pedido.sql`.

-- name: EncolarAvisoAPedido :exec
INSERT INTO avisos_a_pedido (pedido_id, folio, estado, nota, ocurrio_at)
VALUES (
    sqlc.arg('pedido_id'), sqlc.narg('folio'), sqlc.arg('estado'),
    sqlc.narg('nota'), sqlc.arg('ocurrio_at')
);

-- Los que hay que mandar, los más viejos primero: un aviso no se queda al fondo porque
-- entren otros. `FOR UPDATE SKIP LOCKED` para que dos procesos del reparto —la api y el
-- espejo— no manden el mismo dos veces.
-- name: AvisosAPedidoPendientes :many
SELECT id, pedido_id, folio, estado, nota, ocurrio_at, intentos
FROM avisos_a_pedido
WHERE situacion = 'pendiente'
ORDER BY created_at ASC
LIMIT sqlc.arg('tope')
FOR UPDATE SKIP LOCKED;

-- name: AvisoAPedidoEnviado :exec
UPDATE avisos_a_pedido
SET situacion = 'enviado', intentos = intentos + 1, motivo = NULL,
    resuelto_at = now(), updated_at = now()
WHERE id = sqlc.arg('id');

-- PEDIDO dijo que NO, y con su motivo. No se borra: se queda a la vista hasta que una
-- persona decida (`CLAUDE.md` §4).
-- name: AvisoAPedidoRechazado :exec
UPDATE avisos_a_pedido
SET situacion = 'rechazado', intentos = intentos + 1,
    motivo = sqlc.arg('motivo'), resuelto_at = now(), updated_at = now()
WHERE id = sqlc.arg('id');

-- No se pudo ni preguntar —PEDIDO caído, la red—. Sigue PENDIENTE: eso no es un rechazo y
-- confundirlos daría por perdido lo que sólo estaba esperando.
-- name: AvisoAPedidoSeReintenta :exec
UPDATE avisos_a_pedido
SET intentos = intentos + 1, motivo = sqlc.arg('motivo'), updated_at = now()
WHERE id = sqlc.arg('id');

-- La pantalla de administración: los últimos avisos, con lo que pasó con cada uno.
-- name: ListarAvisosAPedido :many
SELECT id, pedido_id, folio, estado, nota, ocurrio_at, situacion, intentos,
       motivo, resuelto_at, created_at
FROM avisos_a_pedido
WHERE (sqlc.narg('situacion')::aviso_a_pedido_estado IS NULL
       OR situacion = sqlc.narg('situacion')::aviso_a_pedido_estado)
ORDER BY created_at DESC
LIMIT sqlc.arg('tope');

-- Los tres números de arriba de esa pantalla.
-- name: ContarAvisosAPedido :one
SELECT
    count(*) FILTER (WHERE situacion = 'pendiente')::bigint AS pendientes,
    count(*) FILTER (WHERE situacion = 'enviado')::bigint   AS enviados,
    count(*) FILTER (WHERE situacion = 'rechazado')::bigint AS rechazados
FROM avisos_a_pedido;
