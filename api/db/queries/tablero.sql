-- El tablero de preparación: las columnas de la sucursal, lo que hay puesto en cada una y
-- los pedidos que faltan por colocar, ordenados por cercanía al almacén.
--
-- Especificado en ../../../docs/tablero.md. Las tablas, en 00002_tablero.sql.
--
-- EL ALCANCE VA EN EL SQL, igual que en `routes.sql`, y por lo mismo: si el filtro se
-- hiciera en Go después de leer, la columna de otra sucursal ya habría salido de la base, y
-- un `DELETE ... WHERE id = $1` a secas borra el tablero de quien sea.
-- `sqlc.narg('sucursal')` es el parámetro «todas las sucursales»: NULL = no acota.
--
-- Y ADEMÁS DE ESO, UN `branch_id` OBLIGATORIO en las lecturas del tablero. No es
-- redundante y no sobra: **no existe «el tablero de todas»**. Las columnas son de una
-- sucursal, y la cercanía se mide desde el almacén de UNA sucursal — con diez mezcladas, el
-- «más cercano primero» sale midiendo Holguín desde Santiago. El Super Admin, que no tiene
-- alcance, tiene que elegir cuál está mirando. Es el mismo par de parámetros de
-- `ListarPedidosDisponibles`: el alcance manda y el `branch_id` estrecha, nunca amplía.

-- ---------------------------------------------------------------------------
-- Las columnas  (GET /api/board/columns)
-- ---------------------------------------------------------------------------

-- El tablero entero por arriba: cada columna con lo que lleva dentro.
--
-- Los totales vienen de la base y no de sumar las tarjetas en la pantalla, porque la
-- pantalla pagina y el camión no: con 60 pedidos puestos, sumar lo pintado da el peso de
-- los 20 primeros y el aviso de que no cabe no aparece nunca.
--
-- `excede_camion` se calcula contra la capacidad del vehículo PREVISTO, leída del vehículo
-- y no copiada en la columna. Sin camión previsto es NULL, que no es `false`: significa que
-- todavía no se sabe, y pintar «cabe» cuando nadie ha dicho en qué va es peor que no
-- pintar nada.
-- name: ListarColumnasDelTablero :many
SELECT
    c.id, c.branch_id, c.nombre, c.posicion, c.vehicle_id, c.creado_por,
    c.created_at, c.updated_at,
    v.name     AS vehiculo_nombre,
    v.plate    AS vehiculo_matricula,
    v.capacity AS vehiculo_capacidad,
    t.pedidos,
    t.peso_kg,
    t.costo_usd,
    (v.capacity IS NOT NULL AND t.peso_kg > v.capacity) AS excede_camion
FROM board_columns c
LEFT JOIN vehicles v ON v.id = c.vehicle_id
LEFT JOIN LATERAL (
    SELECT
        count(*)                                     AS pedidos,
        coalesce(sum(o.weight), 0)::double precision AS peso_kg,
        -- El costo del domicilio es el de PEDIDO (`pedido_costo`), que es el que puso el
        -- repartidor desde Entrega. `delivery_price` NO participa: es otro número —el
        -- viaje dedicado— y confundirlos es cobrar uno por el otro.
        coalesce(sum(o.pedido_costo), 0)::double precision AS costo_usd
    FROM board_placements p
    JOIN orders o ON o.id = p.order_id
    WHERE p.column_id = c.id
) t ON true
WHERE c.branch_id = sqlc.arg('branch_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY c.posicion ASC, c.created_at ASC;

-- Cero filas es «no existe O no es de tu sucursal»: desde fuera son lo mismo, y tienen que
-- serlo, porque decir «existe pero no es tuya» ya es contar algo.
-- name: ObtenerColumna :one
SELECT c.id, c.branch_id, c.nombre, c.posicion, c.vehicle_id, c.creado_por,
       c.created_at, c.updated_at
FROM board_columns c
WHERE c.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid);

-- La posición se calcula aquí y no la manda la pantalla: una columna nueva va al final,
-- siempre, y dejar que el cliente proponga el número es dejar que dos aparatos sin
-- conexión propongan el mismo.
--
-- El `FROM branches` no es decorativo: valida que la sucursal EXISTA. Sin él, un
-- `branch_id` viejo —los tokens duran siete días y las sucursales se recrearon— crearía
-- columnas en un tablero al que no llega nadie.
-- EL ID LO PUEDE PONER EL APARATO, y con eso la creación pasa a ser IDEMPOTENTE.
--
-- Hasta el 16/09/2026 el id lo ponía siempre la base, así que el aparato creaba la zona
-- con un `local-…` suyo y había que sustituirlo cuando el servidor contestaba. Toda esa
-- maquinaria existía por esto, y con ella una familia entera de fallos: si la respuesta no
-- llegaba —se cayó la red justo después de escribir—, el aparato no sabía si la zona
-- existía arriba, y el reintento creaba otra.
--
-- Con un UUIDv7 puesto por el aparato no hay nada que sustituir y el reintento es seguro:
-- el mismo id entra una sola vez. `ON CONFLICT (id) DO NOTHING` más el `SELECT` de abajo
-- devuelven la fila que ya estaba, así que subir dos veces da el mismo resultado que subir
-- una. Es lo único que convierte «¿llegó o no llegó?» en una pregunta que no hace falta.
--
-- v7 y no v4 porque lleva la hora dentro: las zonas quedan ordenadas por cuándo se
-- crearon aunque se hayan creado en cuatro teléfonos distintos sin señal.
--
-- `id` nulo sigue valiendo: lo pone la base, como siempre. La web vieja y cualquier cosa
-- que no lo mande siguen funcionando igual.
-- name: CrearColumna :one
WITH nueva AS (
    INSERT INTO board_columns (id, branch_id, nombre, posicion, vehicle_id, creado_por)
    SELECT
        coalesce(sqlc.narg('id')::uuid, gen_random_uuid()),
        b.id,
        sqlc.arg('nombre'),
        coalesce((SELECT max(c.posicion) + 1 FROM board_columns c WHERE c.branch_id = b.id), 1),
        sqlc.narg('vehicle_id'),
        sqlc.narg('creado_por')
    FROM branches b
    WHERE b.id = sqlc.arg('branch_id')
      AND (sqlc.narg('sucursal')::uuid IS NULL OR b.id = sqlc.narg('sucursal')::uuid)
    ON CONFLICT (id) DO NOTHING
    RETURNING id, branch_id, nombre, posicion, vehicle_id, creado_por, created_at, updated_at
)
SELECT id, branch_id, nombre, posicion, vehicle_id, creado_por, created_at, updated_at
FROM nueva
UNION ALL
-- LA QUE YA ESTABA. Es la rama del reintento: el aparato mandó dos veces el mismo id
-- porque no supo si la primera llegó. Se le devuelve la zona que ya existe y en paz.
--
-- Va acotada igual que el `INSERT`: sin el `branch_id` aquí, mandar el id de la zona de
-- otra sucursal la devolvería, y eso es enseñar lo que no es de uno.
SELECT c.id, c.branch_id, c.nombre, c.posicion, c.vehicle_id, c.creado_por,
       c.created_at, c.updated_at
FROM board_columns c
WHERE sqlc.narg('id')::uuid IS NOT NULL
  AND c.id = sqlc.narg('id')::uuid
  AND c.branch_id = sqlc.arg('branch_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid)
LIMIT 1;

-- Renombrar y elegir camión. `tocar_vehiculo` existe porque «no me lo toques» y «quítamelo»
-- son dos órdenes distintas y las dos llegan con el campo vacío: sin la bandera, dejar el
-- nombre en blanco desasignaría el camión de paso.
-- name: ActualizarColumna :one
UPDATE board_columns SET
    nombre     = coalesce(sqlc.narg('nombre')::text, nombre),
    vehicle_id = CASE WHEN sqlc.arg('tocar_vehiculo')::boolean
                      THEN sqlc.narg('vehicle_id')::uuid ELSE vehicle_id END
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, branch_id, nombre, posicion, vehicle_id, creado_por, created_at, updated_at;

-- Reordenar el tablero entero de una vez: llega la lista de ids en el orden nuevo y la
-- posición de cada uno es su sitio en esa lista.
--
-- En UNA sola sentencia, no una por columna. Con una por columna, el aparato que se queda
-- sin señal a la mitad deja el tablero con dos «tercera» y ninguna «quinta»; aquí, o entran
-- todas o no entra ninguna. Es también la razón de que la única de `posicion` sea
-- DEFERRABLE: a mitad de este `UPDATE` hay posiciones repetidas, y la comprobación tiene
-- que esperar a que el baile termine.
--
-- Las que no vengan en la lista no se tocan: `array_position` sólo se evalúa sobre las que
-- casan el `WHERE`.
-- name: ReordenarColumnas :execrows
UPDATE board_columns SET
    posicion = array_position(sqlc.arg('ids')::uuid[], id)
WHERE id = ANY(sqlc.arg('ids')::uuid[])
  AND branch_id = sqlc.arg('branch_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- Cuántas tarjetas tiene dentro. Se pregunta ANTES de borrarla, para poder decir «tiene 8
-- pedidos puestos» en vez de devolver el error de clave ajena de Postgres, que no lo
-- entiende nadie.
-- name: ContarPedidosEnColumna :one
SELECT count(*)
FROM board_placements p
JOIN board_columns c ON c.id = p.column_id
WHERE p.column_id = sqlc.arg('columna_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid);

-- Vaciar la columna: las tarjetas vuelven a «sin colocar», que es de donde salieron.
-- No se borra ningún pedido — el tablero nunca borra pedidos, sólo dice dónde están.
-- name: VaciarColumna :execrows
DELETE FROM board_placements p
USING board_columns c
WHERE c.id = p.column_id
  AND p.column_id = sqlc.arg('columna_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid);

-- Mover lo de una columna a otra de golpe, para poder borrar la primera sin perder el
-- trabajo. Las tarjetas se ponen DETRÁS de lo que ya haya en la de destino, en su mismo
-- orden relativo: quien juntó dos zonas no quiere que se le mezclen las paradas.
--
-- Las dos columnas tienen que ser de la misma sucursal. No es un capricho: `orders` guarda
-- su sucursal y una tarjeta en el tablero de otra es un pedido que dos logísticos ven a la
-- vez y ninguno sabe de quién es.
-- name: MoverPedidosDeColumna :execrows
UPDATE board_placements p SET
    column_id = destino.id,
    posicion  = coalesce((SELECT max(p2.posicion) FROM board_placements p2
                          WHERE p2.column_id = destino.id), 0) + p.posicion
FROM board_columns origen, board_columns destino
WHERE p.column_id = origen.id
  AND origen.id  = sqlc.arg('columna_origen')
  AND destino.id = sqlc.arg('columna_destino')
  AND origen.branch_id = destino.branch_id
  AND (sqlc.narg('sucursal')::uuid IS NULL OR origen.branch_id = sqlc.narg('sucursal')::uuid);

-- Con `ON DELETE RESTRICT` en las colocaciones, esto falla si la columna tiene algo dentro.
-- Es lo que se quiere: borrar una columna con pedidos puestos no puede ser silencioso, y
-- quien llama ya sabe —por `ContarPedidosEnColumna`— qué tiene que decirle a la persona.
-- name: BorrarColumna :execrows
DELETE FROM board_columns
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- Las tarjetas puestas  (GET /api/board)
-- ---------------------------------------------------------------------------

-- Todo lo colocado en el tablero de una sucursal, en una sola consulta.
--
-- Una consulta y no una por columna: con doce distritos, lo segundo son doce idas y
-- vueltas para pintar una pantalla que el logístico abre y cierra treinta veces al día, y
-- que además tiene que caber en la conexión de allá.
--
-- OJO CON LO QUE **NO** LLEVA ESTE `WHERE`: no están las condiciones de «repartible»
-- (`factura_estado`, `route_id IS NULL`). Aquí sale TODO lo que esté puesto, se pueda
-- repartir o no, y por eso se devuelven `factura_estado`, `archivado`, `route_id` y
-- `resultado`: la tarjeta se marca, no se esconde.
--
-- Quitar sola una tarjeta que dejó de servir es hacer desaparecer el trabajo de alguien sin
-- decírselo; el logístico volvería a la columna, vería once paradas donde puso doce y no
-- tendría manera de saber cuál falta ni por qué.
-- name: ListarPedidosColocados :many
SELECT
    p.order_id, p.column_id, p.posicion, p.colocado_por, p.colocado_at,
    p.created_at, p.updated_at,
    c.nombre AS columna_nombre,
    c.posicion AS columna_posicion,
    o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.weight, o.pedido_costo,
    o.municipio, o.vendedor, o.order_date, o.external_id, o.source,
    o.branch_id,
    -- Los tres avisos de la tarjeta. Se devuelven crudos y quien pinta decide el color:
    --   `factura_estado`  — 'cambiado' es repartible, pero lo que sube al camión son las
    --                       líneas de la factura y el peso de la columna ya no es el que
    --                       era; NULL o 'sin_factura' es que hoy NO se puede repartir.
    --   `archivado`       — PEDIDO lo dio de baja con la tarjeta puesta.
    --   `route_id`        — se lo llevó otra ruta (el Super Admin, o el armador de siempre,
    --                       que no mira el tablero).
    o.factura_estado, o.archivado, o.route_id, o.resultado,
    -- La cercanía al almacén también de lo colocado: es con lo que se comprueba de un
    -- vistazo que no se coló en «Centro» un pedido que está a 40 km.
    km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng) AS km_al_almacen
FROM board_placements p
JOIN board_columns c ON c.id = p.column_id
JOIN orders o        ON o.id = p.order_id
WHERE c.branch_id = sqlc.arg('branch_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY c.posicion ASC, p.posicion ASC;

-- Cuántas tarjetas puestas ya no se pueden repartir. Es el aviso de arriba del tablero:
-- «3 de los que tienes puestos ya no salen». Se cuenta en la base porque la pantalla no
-- tiene todas las tarjetas cargadas y un aviso que sólo aparece si has bajado hasta la
-- columna de abajo no es un aviso.
--
-- Los tres se cuentan por separado a propósito: «lo archivaron en PEDIDO», «se lo llevó
-- otra ruta» y «no está facturado» se arreglan de tres maneras distintas, y un número
-- único obligaría a abrir las doce columnas para saber cuál de las tres es.
-- name: AvisosDelTablero :one
SELECT
    count(*) FILTER (WHERE o.archivado)                                        AS archivados,
    count(*) FILTER (WHERE o.route_id IS NOT NULL)                             AS en_otra_ruta,
    count(*) FILTER (WHERE o.factura_estado IS NULL
                        OR o.factura_estado = 'sin_factura')                   AS sin_factura,
    count(*) FILTER (WHERE o.factura_estado = 'cambiado')                      AS cambiados,
    count(*)                                                                   AS colocados
FROM board_placements p
JOIN board_columns c ON c.id = p.column_id
JOIN orders o        ON o.id = p.order_id
WHERE c.branch_id = sqlc.arg('branch_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- LOS PEDIDOS SIN COLOCAR, ORDENADOS POR CERCANÍA AL ALMACÉN
-- ---------------------------------------------------------------------------

-- La mitad izquierda del tablero, y la razón por la que existe la función `km_haversine`.
--
-- EL ORDEN ES EL ENCARGO: el más cerca del almacén primero. Es como se decide qué se
-- reparte hoy cuando no cabe todo — lo cerca sale igual, lo lejos espera al día que haya
-- suficiente para ese lado—, y por fecha, que es como sale en `/api/orders/available`, esa
-- decisión no se puede tomar.
--
-- EL ORIGEN LLEGA POR PARÁMETRO Y NO SALE DE AQUÍ. El almacén vive en Accesos, no en esta
-- base, y se copia a propósito en ninguna parte: un almacén copiado se separa del de verdad
-- en cuanto alguien mueve unas coordenadas allá, y con esas coordenadas se mide el
-- domicilio que se le cobra al cliente. Quien llama resuelve el almacén principal de la
-- sucursal (primero el `principal` con coordenadas; si no, el primero que las tenga) y lo
-- pasa aquí. Sin almacén con coordenadas no hay tablero: se dice que no se puede, no se
-- ordena por un punto inventado.
--
-- Las condiciones de «repartible» son LAS MISMAS CINCO de `ListarPedidosDisponibles`, ni
-- una más ni una menos. Si el tablero ofreciera algo que el armador luego rechaza, el
-- logístico prepararía una columna entera para que la ruta le diga que no al final del día.
-- name: ListarPedidosSinColocar :many
SELECT
    o.id, o.order_date, o.created_at, o.operation_number, o.customer_name,
    o.customer_phone, o.address, o.end_address, o.end_lat, o.end_lng,
    o.weight, o.pedido_costo, o.municipio, o.vendedor, o.estado,
    o.fecha_comprometida, o.factura_estado, o.external_id, o.source, o.branch_id,
    km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng) AS km_al_almacen
FROM orders o
WHERE
    o.source = 'pedido'
    AND o.route_id IS NULL
    -- ENTREGADO NO SE VUELVE A OFRECER, Y `route_id IS NULL` NO BASTA PARA SABERLO.
    --
    -- Un entregado CONSERVA su `route_id` (ver `MarcarResultadoDeParada`), así que
    -- mientras la ruta exista este filtro ya lo deja fuera. Pero la clave ajena de
    -- `orders.route_id` es `ON DELETE SET NULL` (`db/migrations/00001_init.sql:446`):
    -- el dia que alguien borre la ruta de ayer, los pedidos que YA SE ENTREGARON
    -- amanecen con `route_id` nulo y vuelven a esta lista como si nada hubiera pasado.
    -- El logistico los coloca otra vez, salen en otro camion y se reparten DOS VECES.
    --
    -- Nada en la fila grita que ese pedido ya se entrego salvo estas dos columnas, que
    -- son las que `MarcarResultadoDeParada` escribe juntas y limpia juntas cuando se
    -- corrige a devuelto. Son las mismas dos con las que `ListarPedidosDisponibles`
    -- define `reparto = 'sin_entregar'`, y por eso se escriben igual aqui.
    AND o.delivered_at IS NULL
    AND (o.resultado IS NULL OR o.resultado <> 'entregado')
    AND o.end_lat IS NOT NULL
    AND o.end_lng IS NOT NULL
    AND o.factura_estado IN ('igual', 'cambiado')
    -- Sin colocar = no está en ninguna columna. Del tablero de NADIE: un pedido es de una
    -- sucursal y sólo puede estar en el suyo, así que si aparece puesto, puesto está.
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
    -- SIN DOMICILIO NO SE COLOCA: NO HAY NADA QUE LLEVAR A CASA DE NADIE.
    --
    -- El tablero es la preparacion de las rutas, y una ruta reparte a domicilio.
    -- Sin este filtro, con los datos reales del 25/09/2026, Santiago ofrecia 246
    -- pedidos sin colocar de los cuales **183 no eran de domicilio**: tres de
    -- cada cuatro. El logistico podia armar una zona entera con ellos —y se
    -- armo, probandolo—, y despues el asistente de rutas no se la aceptaba,
    -- porque alli el filtro si estaba. Preparar el dia para que luego no sirva
    -- es peor que no poder prepararlo. Jose, 25/09/2026: «sin domicilio no los
    -- pongas, por que eso no lleva domicilio».
    --
    -- `IS TRUE` y no `= true` a proposito: la columna admite NULL —un pedido que
    -- nadie ha marcado todavia— y `AND o.requiere_domicilio` con NULL deja la
    -- fila fuera igual, pero leyendolo no se sabe. Asi se lee.
    AND o.requiere_domicilio IS TRUE
    AND NOT EXISTS (SELECT 1 FROM board_placements p WHERE p.order_id = o.id)
    -- El `::uuid` no es adorno: `orders.branch_id` admite NULL, y sin el molde sqlc daría
    -- el parámetro como anulable en Go. Uno vacío dejaría la comparación en NULL y la lista
    -- saldría vacía con 200 y sin una traza — el mismo agujero que filtrar por una sucursal
    -- que ya no existe.
    AND o.branch_id = sqlc.arg('branch_id')::uuid
    AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    -- Una sola caja de búsqueda, la misma de la lista de pedidos: quien la usa no se para
    -- a pensar en qué campo está lo que recuerda. El EXISTS es la pregunta del despacho:
    -- «¿qué pedidos llevan malta?».
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
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    -- El día del pedido, medio abierto por arriba, igual que en el armador. Se ofrece
    -- porque un tablero con el histórico entero no se puede preparar: son 1.700 tarjetas.
    AND (
        sqlc.narg('dia_desde')::timestamptz IS NULL
        OR (o.order_date IS NOT NULL
            AND o.order_date >= sqlc.narg('dia_desde')::timestamptz
            AND o.order_date <  sqlc.narg('dia_hasta')::timestamptz)
        OR (o.order_date IS NULL
            AND o.created_at >= sqlc.narg('dia_desde')::timestamptz
            AND o.created_at <  sqlc.narg('dia_hasta')::timestamptz)
    )
    -- El corte por distancia SÍ va aquí, al revés que en `/api/orders/available`, donde se
    -- aplica después de la consulta para no descuadrar `total` y `truncated`. Aquí el
    -- número que se enseña es el de esta misma consulta, así que bajarlo al SQL no
    -- descuadra nada y evita traerse los 40 km de más por la conexión de allá.
    -- Un pedido sin distancia no existe: los cinco filtros de arriba ya exigen coordenadas.
    AND (
        sqlc.narg('km_max')::double precision IS NULL
        OR km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng)
           <= sqlc.narg('km_max')::double precision
    )
    -- LA TANDA SIGUIENTE. El cursor por la MISMA terna del `ORDER BY`.
    --
    -- Hasta el 18/09/2026 esta consulta terminaba en `LIMIT` y se acabó: sin `OFFSET`, sin
    -- cursor y sin nada por donde seguir. `TopeSinColocar` son 200 y `limite` sólo podía
    -- BAJAR, así que con La Habana en 300 pedidos sin colocar —medido en producción el
    -- 17/09/2026— el logístico veía los 200 más cercanos y LOS 100 MÁS LEJANOS NO SE PODÍAN
    -- PEDIR DE NINGUNA MANERA. `Truncated` avisaba y no llevaba a ningún sitio, que es el
    -- §3 del CLAUDE.md: pedir un tope y no poder seguir.
    --
    -- CURSOR Y NO `OFFSET`, y esto es lo que hay que entender antes de tocarlo: con
    -- `OFFSET`, colocar una tarjeta mientras se pagina CORRE LA LISTA HACIA ARRIBA y el
    -- pedido que ocupaba el sitio 201 pasa al 200 — a la tanda siguiente, que pide desde el
    -- 200, se lo salta. Y colocar tarjetas es exactamente lo que está haciendo la persona
    -- que pagina. Un pedido que desaparece sin que nadie lo vea es el fallo caro de esta
    -- casa. El cursor va por VALORES, no por posición: lo que ya está colocado sale de la
    -- lista sin mover a los demás de sitio.
    --
    -- La terna es la del `ORDER BY` —`km ASC, order_date DESC NULLS LAST, id ASC`— y tiene
    -- que ser la misma o el corte no es estable. Se lee «lo que va DESPUÉS de esta fila»:
    --   · más lejos del almacén, o
    --   · a la misma distancia y más atrás en el desempate por fecha (las sin fecha van al
    --     final, y por eso una `order_date` nula es «después» de cualquier fecha), o
    --   · misma distancia y misma fecha, y el id más grande.
    --
    -- OJO CON LOS PUNTOS Y COMA EN ESTOS COMENTARIOS: no puede haber NINGUNO, ni siquiera
    -- entrecomillado. La prueba que vigila que el contador filtre lo mismo que la lista lee
    -- la consulta hasta el primero que encuentra, así que uno dentro de un comentario le
    -- corta el cuerpo por ahí y deja de comparar todo lo que venga después — en verde y sin
    -- decir nada. Pasó con estas mismas líneas el 18/09/2026, recién escritas, y por eso
    -- hay otra prueba que comprueba que la consulta se lee ENTERA
    -- (`internal/store/consultas_enteras_test.go`).
    --
    -- `desde_id` nulo es «desde el principio». Los tres van juntos o no va ninguno: dos de
    -- tres dejarían la comparación en NULL y la lista saldría VACÍA con 200 y sin una
    -- traza. Lo comprueba quien llama, y un cursor a medias es un 400.
    AND (
        sqlc.narg('desde_id')::uuid IS NULL
        OR km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng)
           > sqlc.narg('desde_km')::double precision
        OR (
            km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng)
            = sqlc.narg('desde_km')::double precision
            AND (
                (sqlc.narg('desde_fecha')::timestamptz IS NOT NULL AND o.order_date IS NULL)
                OR (sqlc.narg('desde_fecha')::timestamptz IS NOT NULL
                    AND o.order_date IS NOT NULL
                    AND o.order_date < sqlc.narg('desde_fecha')::timestamptz)
                OR (o.order_date IS NOT DISTINCT FROM sqlc.narg('desde_fecha')::timestamptz
                    AND o.id > sqlc.narg('desde_id')::uuid)
            )
        )
    )
-- El desempate por fecha no es adorno: dos clientes en el mismo edificio dan exactamente
-- los mismos kilómetros, y sin un segundo criterio el orden cambia entre dos llamadas y las
-- tarjetas bailan solas delante de quien las está arrastrando.
ORDER BY km_al_almacen ASC, o.order_date DESC NULLS LAST, o.id ASC
LIMIT sqlc.arg('limite');

-- El contador de la mitad izquierda: el MISMO `WHERE`, sin tope ni orden. Tiene que ser el
-- mismo o dice «358» encima de una lista de 120.
--
-- Y eso es exactamente lo que pasó: le faltaba `AND NOT o.archivado`, que la lista sí
-- tiene desde el 15/09/2026. Con los datos de La Habana del 17/09/2026 —728 pedidos, 429
-- archivados, 6 colocados— este contador decía **722** encima de una lista de **293**.
--
-- Nadie lo vio en tres días porque el número sale solo, sin nada al lado con qué
-- compararlo: 722 se lee igual de bien que 293. Es el fallo que más caro sale aquí, el de
-- un número creíble y equivocado, y por eso hay una prueba que compara las dos consultas
-- contra la misma siembra en vez de comprobar cada una por su cuenta.
--
-- POR QUÉ LLEVA EL CURSOR SI QUIEN LLAMA SIEMPRE LE PASA NULO. Porque el contrato de estas
-- dos consultas es TEXTUAL: el mismo `WHERE`, palabra por palabra, y así lo comprueba
-- `internal/store/contador_y_lista_test.go`. En cuanto la lista se pagina por cursor, dejar
-- ese trozo fuera de aquí rompe el único vigilante que tiene el número — y el número
-- volvería a poder separarse de la lista sin que nadie se entere, que es lo que pasó tres
-- días seguidos con `AND NOT o.archivado`.
--
-- Y el número que va encima de la lista es el TOTAL, no lo que queda de la tanda en curso:
-- «Sin colocar (300)» no puede bajar a 100 porque alguien haya bajado con el dedo. Por eso
-- `mitadIzquierda` le pasa el cursor nulo SIEMPRE, y por eso «hay más tandas» no se calcula
-- restando de este número sino pidiendo una fila de más (ver `TopeSinColocar`).
-- name: ContarPedidosSinColocar :one
SELECT count(*)
FROM orders o
WHERE
    o.source = 'pedido'
    AND o.route_id IS NULL
    -- ENTREGADO NO SE VUELVE A OFRECER, Y `route_id IS NULL` NO BASTA PARA SABERLO.
    --
    -- Un entregado CONSERVA su `route_id` (ver `MarcarResultadoDeParada`), así que
    -- mientras la ruta exista este filtro ya lo deja fuera. Pero la clave ajena de
    -- `orders.route_id` es `ON DELETE SET NULL` (`db/migrations/00001_init.sql:446`):
    -- el dia que alguien borre la ruta de ayer, los pedidos que YA SE ENTREGARON
    -- amanecen con `route_id` nulo y vuelven a esta lista como si nada hubiera pasado.
    -- El logistico los coloca otra vez, salen en otro camion y se reparten DOS VECES.
    --
    -- Nada en la fila grita que ese pedido ya se entrego salvo estas dos columnas, que
    -- son las que `MarcarResultadoDeParada` escribe juntas y limpia juntas cuando se
    -- corrige a devuelto. Son las mismas dos con las que `ListarPedidosDisponibles`
    -- define `reparto = 'sin_entregar'`, y por eso se escriben igual aqui.
    AND o.delivered_at IS NULL
    AND (o.resultado IS NULL OR o.resultado <> 'entregado')
    AND o.end_lat IS NOT NULL
    AND o.end_lng IS NOT NULL
    AND o.factura_estado IN ('igual', 'cambiado')
    -- La misma línea que la lista, y en el mismo sitio para que se vean juntas al
    -- compararlas a ojo.
    AND NOT o.archivado
    -- SIN DOMICILIO NO SE COLOCA: NO HAY NADA QUE LLEVAR A CASA DE NADIE.
    --
    -- El tablero es la preparacion de las rutas, y una ruta reparte a domicilio.
    -- Sin este filtro, con los datos reales del 25/09/2026, Santiago ofrecia 246
    -- pedidos sin colocar de los cuales **183 no eran de domicilio**: tres de
    -- cada cuatro. El logistico podia armar una zona entera con ellos —y se
    -- armo, probandolo—, y despues el asistente de rutas no se la aceptaba,
    -- porque alli el filtro si estaba. Preparar el dia para que luego no sirva
    -- es peor que no poder prepararlo. Jose, 25/09/2026: «sin domicilio no los
    -- pongas, por que eso no lleva domicilio».
    --
    -- `IS TRUE` y no `= true` a proposito: la columna admite NULL —un pedido que
    -- nadie ha marcado todavia— y `AND o.requiere_domicilio` con NULL deja la
    -- fila fuera igual, pero leyendolo no se sabe. Asi se lee.
    AND o.requiere_domicilio IS TRUE
    AND NOT EXISTS (SELECT 1 FROM board_placements p WHERE p.order_id = o.id)
    AND o.branch_id = sqlc.arg('branch_id')::uuid
    AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
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
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('dia_desde')::timestamptz IS NULL
        OR (o.order_date IS NOT NULL
            AND o.order_date >= sqlc.narg('dia_desde')::timestamptz
            AND o.order_date <  sqlc.narg('dia_hasta')::timestamptz)
        OR (o.order_date IS NULL
            AND o.created_at >= sqlc.narg('dia_desde')::timestamptz
            AND o.created_at <  sqlc.narg('dia_hasta')::timestamptz)
    )
    AND (
        sqlc.narg('km_max')::double precision IS NULL
        OR km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng)
           <= sqlc.narg('km_max')::double precision
    )
    -- LA TANDA SIGUIENTE. El cursor por la MISMA terna del `ORDER BY`.
    --
    -- Hasta el 18/09/2026 esta consulta terminaba en `LIMIT` y se acabó: sin `OFFSET`, sin
    -- cursor y sin nada por donde seguir. `TopeSinColocar` son 200 y `limite` sólo podía
    -- BAJAR, así que con La Habana en 300 pedidos sin colocar —medido en producción el
    -- 17/09/2026— el logístico veía los 200 más cercanos y LOS 100 MÁS LEJANOS NO SE PODÍAN
    -- PEDIR DE NINGUNA MANERA. `Truncated` avisaba y no llevaba a ningún sitio, que es el
    -- §3 del CLAUDE.md: pedir un tope y no poder seguir.
    --
    -- CURSOR Y NO `OFFSET`, y esto es lo que hay que entender antes de tocarlo: con
    -- `OFFSET`, colocar una tarjeta mientras se pagina CORRE LA LISTA HACIA ARRIBA y el
    -- pedido que ocupaba el sitio 201 pasa al 200 — a la tanda siguiente, que pide desde el
    -- 200, se lo salta. Y colocar tarjetas es exactamente lo que está haciendo la persona
    -- que pagina. Un pedido que desaparece sin que nadie lo vea es el fallo caro de esta
    -- casa. El cursor va por VALORES, no por posición: lo que ya está colocado sale de la
    -- lista sin mover a los demás de sitio.
    --
    -- La terna es la del `ORDER BY` —`km ASC, order_date DESC NULLS LAST, id ASC`— y tiene
    -- que ser la misma o el corte no es estable. Se lee «lo que va DESPUÉS de esta fila»:
    --   · más lejos del almacén, o
    --   · a la misma distancia y más atrás en el desempate por fecha (las sin fecha van al
    --     final, y por eso una `order_date` nula es «después» de cualquier fecha), o
    --   · misma distancia y misma fecha, y el id más grande.
    --
    -- OJO CON LOS PUNTOS Y COMA EN ESTOS COMENTARIOS: no puede haber NINGUNO, ni siquiera
    -- entrecomillado. La prueba que vigila que el contador filtre lo mismo que la lista lee
    -- la consulta hasta el primero que encuentra, así que uno dentro de un comentario le
    -- corta el cuerpo por ahí y deja de comparar todo lo que venga después — en verde y sin
    -- decir nada. Pasó con estas mismas líneas el 18/09/2026, recién escritas, y por eso
    -- hay otra prueba que comprueba que la consulta se lee ENTERA
    -- (`internal/store/consultas_enteras_test.go`).
    --
    -- `desde_id` nulo es «desde el principio». Los tres van juntos o no va ninguno: dos de
    -- tres dejarían la comparación en NULL y la lista saldría VACÍA con 200 y sin una
    -- traza. Lo comprueba quien llama, y un cursor a medias es un 400.
    AND (
        sqlc.narg('desde_id')::uuid IS NULL
        OR km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng)
           > sqlc.narg('desde_km')::double precision
        OR (
            km_haversine(sqlc.arg('origen_lat'), sqlc.arg('origen_lng'), o.end_lat, o.end_lng)
            = sqlc.narg('desde_km')::double precision
            AND (
                (sqlc.narg('desde_fecha')::timestamptz IS NOT NULL AND o.order_date IS NULL)
                OR (sqlc.narg('desde_fecha')::timestamptz IS NOT NULL
                    AND o.order_date IS NOT NULL
                    AND o.order_date < sqlc.narg('desde_fecha')::timestamptz)
                OR (o.order_date IS NOT DISTINCT FROM sqlc.narg('desde_fecha')::timestamptz
                    AND o.id > sqlc.narg('desde_id')::uuid)
            )
        )
    );

-- ---------------------------------------------------------------------------
-- Arrastrar  (PUT /api/board/placements/[pedidoId])
-- ---------------------------------------------------------------------------

-- Colocar un pedido en una columna, o moverlo de sitio. Es la MISMA orden: soltar una
-- tarjeta en una columna es decir «este pedido va aquí», venga de donde venga.
--
-- Cinco cosas van juntas en una sola sentencia y ninguna se puede comprobar antes en Go
-- sobre una lectura que ya puede estar vieja:
--
--  1. El pedido y la columna tienen que ser de la MISMA sucursal. Es la comprobación que
--     ninguna clave ajena puede hacer, porque son dos tablas distintas.
--  2. `o.route_id IS NULL`: un pedido que ya va en un camión no se coloca. Cero filas es
--     ese rechazo, y es el mismo instante en el que se comprueba — con diez logísticos y un
--     Super Admin armando rutas a la vez, entre pintar la lista y soltar la tarjeta pasan
--     cosas de verdad.
--  3. El alcance, que aquí es seguridad: sin él, mandar el id de una columna ajena mete tu
--     pedido en el tablero de otra sucursal.
--  4. `ON CONFLICT (order_id)`: mover es actualizar la fila que ya hay. Sin esto habría que
--     borrar y volver a insertar, y entre las dos el pedido no está en ninguna parte.
--  5. `colocado_at` se refresca al mover: es cuándo quedó donde está ahora.
--
-- La condición de `factura_estado` NO está: un pedido colocado que deja de ser repartible
-- se queda puesto y marcado (ver `ListarPedidosColocados`), así que volver a colocarlo
-- tampoco se prohíbe. Lo que no puede salir es la RUTA, y eso lo corta el armador.
--
-- # Y DEVUELVE LA SUCURSAL DE LA COLUMNA, QUE NO ES UN ADORNO — 01/10/2026
--
-- El aviso en vivo del tablero tiene que salir de la sucursal de la FILA que se acaba de
-- escribir y no del alcance de quien llamó (`api/internal/api/eventos.go`), porque el
-- alcance de un SUPER ADMIN es «todas» y entonces el aviso sale pelado y las ocho
-- sucursales se bajan el tablero entero. `board_placements` no tiene `branch_id` —cuelga de
-- la columna—, así que la sucursal hay que sacarla de `board_columns`.
--
-- Y VA EN **UNA** SENTENCIA, CON UN CTE, no con una segunda lectura detrás. Un
-- `SELECT branch_id FROM board_columns` aparte sería una segunda versión de los hechos: la
-- columna puede haberse borrado entre el INSERT y esa lectura, y entonces el aviso saldría
-- global o no saldría. Aquí el `JOIN` se hace sobre la fila que la sentencia ACABA de
-- escribir, en la misma instantánea.
--
-- `RETURNING` de un `INSERT` **no puede ver** los `FROM` de su propio `SELECT` (sólo la fila
-- insertada), y por eso no basta con añadirle `c.branch_id`: hace falta el CTE. Si vuelve a
-- intentarse sin él, Postgres contesta «missing FROM-clause entry for table c».
--
-- Cero filas sigue significando lo mismo: si el INSERT no coloca nada, el CTE va vacío, el
-- `SELECT` de fuera tampoco devuelve nada y el manejador recibe su `pgx.ErrNoRows` para
-- traducirlo en `porQueNoSePudoColocar`.
-- name: ColocarPedido :one
WITH puesta AS (
    INSERT INTO board_placements (order_id, column_id, posicion, colocado_por, colocado_at)
    SELECT o.id, c.id, sqlc.arg('posicion'), sqlc.narg('colocado_por'), now()
    FROM orders o, board_columns c
    WHERE o.id = sqlc.arg('pedido_id')
      AND c.id = sqlc.arg('columna_id')
      AND o.branch_id = c.branch_id
      AND o.route_id IS NULL
      -- Y NO SE PUEDE COLOCAR LO QUE YA SE ENTREGÓ. `route_id IS NULL` no lo cubre: la
      -- clave ajena es `ON DELETE SET NULL`, así que borrar la ruta de ayer deja sueltos a
      -- los entregados. Quien lo traduce a un 409 con su motivo es `porQueNoSePudoColocar`.
      AND o.delivered_at IS NULL
      AND (o.resultado IS NULL OR o.resultado <> 'entregado')
      AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid)
    ON CONFLICT (order_id) DO UPDATE SET
        column_id    = excluded.column_id,
        posicion     = excluded.posicion,
        colocado_por = excluded.colocado_por,
        colocado_at  = now()
    RETURNING order_id, column_id, posicion, colocado_por, colocado_at, created_at, updated_at
)
SELECT p.order_id, p.column_id, p.posicion, p.colocado_por, p.colocado_at,
       p.created_at, p.updated_at, c.branch_id
FROM puesta p
JOIN board_columns c ON c.id = p.column_id;

-- Hacer sitio antes de soltar una tarjeta EN MEDIO de una columna: todo lo que esté de esa
-- posición para abajo se corre uno. En un solo `UPDATE` —y por eso la única es DEFERRABLE—
-- porque a mitad del corrimiento hay dos filas con la misma posición.
-- name: AbrirHuecoEnColumna :execrows
UPDATE board_placements p SET
    posicion = p.posicion + 1
FROM board_columns c
WHERE c.id = p.column_id
  AND p.column_id = sqlc.arg('columna_id')
  AND p.posicion >= sqlc.arg('desde_posicion')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid);

-- Cerrar el hueco que dejó una tarjeta al salir. Se hace DESPUÉS de sacarla, y si no se
-- hiciera tampoco se rompería nada —el orden se lee, no se cuenta—, pero las posiciones se
-- irían separando hasta que un día alguien las lea como «la parada número 47» de una
-- columna de nueve.
-- name: CerrarHuecoEnColumna :execrows
UPDATE board_placements p SET
    posicion = p.posicion - 1
FROM board_columns c
WHERE c.id = p.column_id
  AND p.column_id = sqlc.arg('columna_id')
  AND p.posicion > sqlc.arg('desde_posicion')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid);

-- Sacar una tarjeta del tablero: vuelve a «sin colocar», donde la lista la pondrá otra vez
-- en su sitio por cercanía. Devuelve la columna y la posición que tenía para poder cerrar
-- el hueco sin volver a preguntar.
--
-- Y DEVUELVE LA SUCURSAL DE LA COLUMNA POR LO MISMO QUE `ColocarPedido`: el aviso en vivo
-- sale de la sucursal de la FILA, no del alcance de quien llamó.
--
-- Va con el mismo CTE, y aquí el motivo es otro: Postgres sí deja que el `RETURNING` de un
-- `DELETE` nombre sus `USING`, pero **el analizador de sqlc no** — con
-- `RETURNING p.order_id, …, c.branch_id` contesta `column "branch_id" does not exist` y no
-- genera nada. Probado el 01/10/2026 con sqlc v1.31.1. Así que el `JOIN` se hace fuera, que
-- además lo deja igual que su gemela de arriba.
-- name: QuitarPedidoDelTablero :one
WITH quitada AS (
    DELETE FROM board_placements p
    USING board_columns c
    WHERE c.id = p.column_id
      AND p.order_id = sqlc.arg('pedido_id')
      AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid)
    RETURNING p.order_id, p.column_id, p.posicion
)
SELECT q.order_id, q.column_id, q.posicion, c.branch_id
FROM quitada q
JOIN board_columns c ON c.id = q.column_id;

-- ---------------------------------------------------------------------------
-- De una columna sale una ruta  (POST /api/board/columns/[id]/route)
-- ---------------------------------------------------------------------------

-- Los pedidos de la columna que TODAVÍA se pueden meter en una ruta, en el orden en que el
-- logístico los dejó puestos.
--
-- Es la hermana de `PedidosParaArmarRuta` y hace el mismo trabajo, pero el universo no son
-- unos ids marcados a mano: es la columna entera. Y como allí, es LA VALIDACIÓN y no una
-- lectura previa a ella — si vuelven menos de los que hay puestos, alguien se los llevó
-- entre que se pintó el tablero y se pulsó el botón, y de ahí sale el «N de los M ya están
-- en otra ruta».
--
-- `factura_estado` deja pasar `igual` y `cambiado` por lo mismo que en `routes.sql`: el
-- corte a sólo `igual` lo hace el handler DESPUÉS, para poder nombrar cuál falla y por qué.
-- Un WHERE que los descarte aquí deja el mismo rechazo sin nada que decir, y el logístico
-- se queda mirando una columna de doce que produce una ruta de nueve sin explicación.
--
-- `posicion` sale para que el armador pueda RESPETAR el orden del logístico: él conoce las
-- calles de su distrito y el vecino más próximo no. Quién de los dos manda lo decide el
-- handler; lo que no puede es no tener el dato.
-- name: PedidosDeColumnaParaArmarRuta :many
SELECT
    o.id, o.operation_number, o.customer_name, o.end_lat, o.end_lng,
    o.weight, o.pedido_costo, o.factura_estado, o.branch_id,
    o.external_id, o.source, o.archivado,
    -- SE ENTREGA EL DATO, NO SE FILTRA AQUÍ, igual que `factura_estado` y por lo mismo:
    -- un `WHERE` que los descarte deja el descarte sin nada que decir, y el logístico se
    -- queda mirando una columna de doce que produce una ruta de nueve sin explicación.
    -- El corte lo hace `armarRutaDeColumna`, que los nombra uno a uno en `descartados`.
    o.delivered_at, o.resultado,
    p.posicion
FROM board_placements p
JOIN board_columns c ON c.id = p.column_id
JOIN orders o        ON o.id = p.order_id
WHERE p.column_id = sqlc.arg('columna_id')
  AND o.source = 'pedido'
  AND o.route_id IS NULL
  AND o.end_lat IS NOT NULL
  AND o.end_lng IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY p.posicion ASC;

-- Las tarjetas de los pedidos que acaban de subirse a una ruta salen del tablero.
--
-- Se llama DENTRO de la misma transacción que engancha las paradas. La columna se vacía
-- porque el pedido ya no está por preparar: está cargado. Dejarlo puesto sería enseñar dos
-- veces el mismo trabajo —una en el tablero y otra en la ruta— y la segunda vez que alguien
-- «prepara» esa columna se encuentra con que ya salió.
--
-- No se borra la COLUMNA: el distrito sigue existiendo mañana. Lo que se vacía es lo que
-- lleva dentro hoy.
-- name: QuitarDelTableroLosDeRuta :execrows
DELETE FROM board_placements p
USING orders o, board_columns c
WHERE o.id = p.order_id
  AND c.id = p.column_id
  AND o.route_id = sqlc.arg('ruta_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR c.branch_id = sqlc.narg('sucursal')::uuid);
