-- La flota.
--
-- `branch_id` NULL en un vehículo significa «de todas las sucursales», así que el filtro
-- del alcance tiene que dejarlos pasar: un camión compartido que no salga en la lista de
-- nadie es un camión que no se puede usar. Eso es distinto de pedidos y rutas, donde un
-- `branch_id` NULL sería un dato incompleto, no una decisión.
--
-- NO SE FILTRA POR QUIÉN DIO DE ALTA EL VEHÍCULO. En delivery se intentó, y hay un
-- comentario en su propio código diciendo que devolvía 404 sobre vehículos que existen
-- de verdad, porque los había dado de alta otra cuenta de la misma sucursal.

-- ---------------------------------------------------------------------------
-- La lista  (GET /api/vehicles)
-- ---------------------------------------------------------------------------

-- name: ListarVehiculos :many
SELECT
    v.id, v.name, v.vehicle_type_id, v.plate, v.capacity, v.costo_km_usd,
    v.usar_para_domicilio, v.status, v.notes, v.branch_id,
    v.created_at, v.updated_at,
    vt.nombre       AS tipo_nombre,
    vt.costo_km_usd AS tipo_costo_km_usd,
    b.name          AS sucursal_nombre,
    -- Los tres conteos de la tarjeta. Van como subconsultas y no como JOIN + GROUP BY
    -- porque tres JOIN a la vez multiplican las filas entre sí y los tres números salen
    -- inflados: el clásico de contar rutas y pedidos en la misma consulta.
    (SELECT count(*) FROM routes r         WHERE r.vehicle_id  = v.id) AS rutas,
    -- LOS PEDIDOS QUE LLEVA ESTE CAMIÓN SALEN DE SUS RUTAS, no de `orders.vehicle_id`.
    --
    -- Aquí se contaba `orders.vehicle_id`, y esa columna la escribe SÓLO el tablero
    -- (`tablero.sql`, `tocar_vehiculo`): armar una ruta nunca la toca, porque el camión de
    -- un pedido es el de la ruta en la que viaja. Resultado, visto el 22/09/2026 en el
    -- teléfono de Jose: la tarjeta decía «Rutas 7» y debajo «0 órdenes asignadas», con
    -- 125,3 kg cargados. Dos números de la misma tarjeta contándose cosas distintas, y el
    -- cero es el que se lee.
    (SELECT count(*) FROM orders o
        JOIN routes r ON r.id = o.route_id
        WHERE r.vehicle_id = v.id) AS pedidos,
    (SELECT count(*) FROM order_vehicles ov WHERE ov.vehicle_id = v.id) AS asignaciones
FROM vehicles v
JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
LEFT JOIN branches b  ON b.id  = v.branch_id
WHERE (sqlc.narg('sucursal')::uuid IS NULL
       OR v.branch_id = sqlc.narg('sucursal')::uuid
       OR v.branch_id IS NULL)
ORDER BY v.created_at DESC;

-- name: ObtenerVehiculo :one
SELECT
    v.id, v.name, v.vehicle_type_id, v.plate, v.capacity, v.costo_km_usd,
    v.usar_para_domicilio, v.status, v.notes, v.branch_id,
    v.created_at, v.updated_at,
    vt.nombre       AS tipo_nombre,
    vt.costo_km_usd AS tipo_costo_km_usd,
    (SELECT count(*) FROM routes r          WHERE r.vehicle_id  = v.id) AS rutas,
    -- Igual que en `ListarVehiculos`: por sus rutas. Ver el comentario de allí.
    (SELECT count(*) FROM orders o
        JOIN routes r ON r.id = o.route_id
        WHERE r.vehicle_id = v.id) AS pedidos,
    (SELECT count(*) FROM order_vehicles ov WHERE ov.vehicle_id = v.id) AS asignaciones
FROM vehicles v
JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
WHERE v.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL
       OR v.branch_id = sqlc.narg('sucursal')::uuid
       OR v.branch_id IS NULL);

-- El camión de una ruta que se está armando, para comprobar la capacidad.
--
-- Va SIN alcance a propósito, calcado del contrato: si el vehículo no aparece, delivery no
-- valida la capacidad en vez de negarse. Acotarlo por sucursal aquí haría que un camión
-- compartido dejara de validar peso justo cuando más importa.
-- name: ObtenerVehiculoParaCapacidad :one
SELECT v.id, v.name, v.capacity, v.status, v.branch_id
FROM vehicles v
WHERE v.id = sqlc.arg('id');

-- ---------------------------------------------------------------------------
-- Altas y cambios
-- ---------------------------------------------------------------------------

-- El vehículo nace en la sucursal del alcance. Quien no tiene alcance —el Super Admin—
-- puede dejarlo sin sucursal, que significa «de todas».
--
-- `costo_km_usd` puede quedar vacío: lo pone el camionero, y dos camiones del mismo tipo
-- no cuestan igual. Vacío quiere decir «usa el del tipo», no «cero».
-- name: CrearVehiculo :one
INSERT INTO vehicles (
    name, vehicle_type_id, plate, capacity, costo_km_usd,
    usar_para_domicilio, status, notes, branch_id
) VALUES (
    sqlc.arg('name'), sqlc.arg('vehicle_type_id'), sqlc.narg('plate'),
    sqlc.arg('capacity'), sqlc.narg('costo_km_usd'), sqlc.arg('usar_para_domicilio'),
    sqlc.arg('status'), sqlc.narg('notes'), sqlc.narg('branch_id')
)
RETURNING id, name, vehicle_type_id, plate, capacity, costo_km_usd,
          usar_para_domicilio, status, notes, branch_id, created_at, updated_at;

-- name: ActualizarVehiculo :one
UPDATE vehicles SET
    name                = coalesce(sqlc.narg('name')::text, name),
    vehicle_type_id     = coalesce(sqlc.narg('vehicle_type_id')::uuid, vehicle_type_id),
    plate               = CASE WHEN sqlc.arg('tocar_plate')::boolean
                               THEN sqlc.narg('plate')::text ELSE plate END,
    capacity            = coalesce(sqlc.narg('capacity')::double precision, capacity),
    costo_km_usd        = CASE WHEN sqlc.arg('tocar_costo')::boolean
                               THEN sqlc.narg('costo_km_usd')::double precision
                               ELSE costo_km_usd END,
    usar_para_domicilio = coalesce(sqlc.narg('usar_para_domicilio')::boolean, usar_para_domicilio),
    status              = coalesce(sqlc.narg('status')::vehicle_status, status),
    notes               = CASE WHEN sqlc.arg('tocar_notes')::boolean
                               THEN sqlc.narg('notes')::text ELSE notes END
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL
       OR branch_id = sqlc.narg('sucursal')::uuid
       OR branch_id IS NULL)
RETURNING id, name, vehicle_type_id, plate, capacity, costo_km_usd,
          usar_para_domicilio, status, notes, branch_id, created_at, updated_at;

-- Sólo un vehículo de referencia por sucursal, y lo impide el índice único parcial
-- `vehicles_una_referencia_por_sucursal`. Por eso hay que DESMARCAR a los demás antes de
-- marcar el nuevo, y las dos cosas dentro de la MISMA transacción: si no, el INSERT choca
-- contra el índice.
--
-- HUECO CONOCIDO: los vehículos sin sucursal (`branch_id` NULL) se escapan del índice,
-- porque en un índice único los NULL son distintos entre sí. Puede haber dos de referencia
-- «de todas». Se cierra con `NULLS NOT DISTINCT` el día que estorbe.
-- name: DesmarcarReferenciaDeDomicilio :execrows
UPDATE vehicles SET usar_para_domicilio = false
WHERE usar_para_domicilio
  AND id <> sqlc.arg('excepto_id')
  AND branch_id IS NOT DISTINCT FROM sqlc.narg('sucursal')::uuid;

-- El de referencia de una sucursal: con su capacidad y su costo por km define el CKK de la
-- fórmula del domicilio. Si el vehículo no trae costo propio se cae al del tipo.
-- name: VehiculoDeReferenciaDeSucursal :one
SELECT
    v.id, v.name, v.capacity,
    coalesce(v.costo_km_usd, vt.costo_km_usd) AS costo_km_usd,
    v.branch_id
FROM vehicles v
JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
WHERE v.usar_para_domicilio
  AND v.branch_id IS NOT DISTINCT FROM sqlc.narg('sucursal')::uuid;

-- Ocupar y liberar el camión. El vehículo se marca `in_use` al DESPACHAR la ruta (pasarla
-- a `in_progress`), no al armarla: entre que se arma la noche anterior y sale por la
-- mañana, el camión sigue disponible para otra cosa.
-- name: CambiarEstadoDeVehiculo :execrows
UPDATE vehicles SET status = sqlc.arg('status')::vehicle_status
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL
       OR branch_id = sqlc.narg('sucursal')::uuid
       OR branch_id IS NULL);

-- ---------------------------------------------------------------------------
-- Borrado
-- ---------------------------------------------------------------------------
--
-- Antes de borrar hay que desasociar: rutas (`DesvincularVehiculoDeRutas`, en routes.sql),
-- pedidos y asignaciones. El histórico de lo que se repartió no se borra porque un camión
-- se dé de baja.

-- name: DesvincularVehiculoDePedidos :execrows
UPDATE orders SET vehicle_id = NULL
WHERE vehicle_id = sqlc.arg('vehiculo_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- name: BorrarAsignacionesDeVehiculo :execrows
DELETE FROM order_vehicles WHERE vehicle_id = sqlc.arg('vehiculo_id');

-- DEVUELVE LA SUCURSAL DEL CAMIÓN BORRADO, y no es un adorno — 01/10/2026. El aviso en
-- vivo de la flota sale de la sucursal de la FILA y no del alcance de quien llamó, y aquí la
-- fila ya no está cuando se avisa: o la trae el DELETE, o no la trae nadie.
--
-- `branch_id` puede venir NULL, que es un camión COMPARTIDO entre sucursales. Eso se lee
-- como «de todas» y el aviso sale global, que es lo correcto: su alta o su baja la ven las
-- ocho.
--
-- `:one` y no `:execrows`: cero filas es «no existe O no es de tu sucursal», o sea el 404, y
-- ése es ahora `pgx.ErrNoRows`.
-- name: BorrarVehiculo :one
DELETE FROM vehicles
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL
       OR branch_id = sqlc.narg('sucursal')::uuid
       OR branch_id IS NULL)
RETURNING branch_id;

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------

-- name: ContarVehiculos :one
SELECT count(*) FROM vehicles v
WHERE (sqlc.narg('sucursal')::uuid IS NULL
       OR v.branch_id = sqlc.narg('sucursal')::uuid
       OR v.branch_id IS NULL);

-- ---------------------------------------------------------------------------
-- EN QUÉ ANDA CADA CAMIÓN: se DEDUCE de sus rutas, no se mantiene a mano
-- ---------------------------------------------------------------------------
--
-- Jose, 28/09/2026: «si la idea es q salga el vehiculo y ese vehiculo se ponga su estado
-- para q saber como anda ese vehiculo y saber de la flota».
--
-- `vehicles.status` ya existía y NO es la respuesta: es un campo que alguien pone y alguien
-- tiene que quitar, y un estado que nadie mantiene miente a los dos días. Aquí abajo ya
-- estaba escrito, en `ContarVehiculosEnRuta`: «se mira la ruta y no `vehicles.status`
-- porque el estado es un campo que alguien puede haber dejado a mano en `available` con la
-- ruta todavía abierta». Esto es esa misma cuenta, POR CAMIÓN en vez de en total, para que
-- la tarjeta de Vehículos diga en qué anda cada uno y la ficha de una ruta diga cómo anda
-- el suyo. Nace correcta para los camiones que ya existen, que es lo que un campo nuevo no
-- puede hacer.
--
-- UNA ruta por camión, la que manda. `DISTINCT ON` con su `ORDER BY`, y el orden no es
-- caprichoso: primero la que está EN CURSO —ésa es la que tiene el camión fuera ahora
-- mismo—, y entre planificadas la del día más próximo. Sin ese orden, una planificada de la
-- semana que viene taparía la que está rodando hoy.
--
-- VA COMO CONSULTA APARTE y no como `LEFT JOIN` dentro de `ListarVehiculos`, y es por una
-- razón concreta, no por gusto: sqlc no sabe que un `LEFT JOIN` a una tabla derivada puede
-- no casar, así que tipaba `ruta_abierta_id` como `uuid.UUID` y `ruta_abierta_estado` como
-- `RouteStatus`, los dos NO nulos. El primer camión libre de la lista habría reventado el
-- `Scan` en producción con un error que no dice nada. Probado con `LEFT JOIN LATERAL` y con
-- `DISTINCT ON`: las dos formas dan el mismo tipo equivocado, y `nullif` para forzarlo sale
-- tipado como `bool`. Aquí cada fila que vuelve es una ruta de verdad, así que no hay nada
-- que pueda venir nulo, y el camión sin ruta es sencillamente el que no sale.
--
-- El alcance se copia de `ListarVehiculos`: se acota por la sucursal de la RUTA, que es la
-- misma por la que se acota `ContarVehiculosEnRuta`.
-- name: RutasAbiertasDeLaFlota :many
SELECT DISTINCT ON (r.vehicle_id)
       r.vehicle_id, r.id, r.route_code, r.name, r.status, r.delivery_date
FROM routes r
WHERE r.vehicle_id IS NOT NULL
  AND r.status NOT IN ('completed', 'cancelled')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY r.vehicle_id,
         (r.status = 'in_progress') DESC,
         r.delivery_date ASC NULLS LAST,
         r.created_at ASC;

-- Camiones que están fuera ahora mismo: los que llevan una ruta sin cerrar. Se mira la
-- ruta y no `vehicles.status` porque el estado es un campo que alguien puede haber dejado
-- a mano en `available` con la ruta todavía abierta.
-- name: ContarVehiculosEnRuta :one
SELECT count(DISTINCT r.vehicle_id) FROM routes r
WHERE r.vehicle_id IS NOT NULL
  AND r.status NOT IN ('completed', 'cancelled')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- Asignación de varios camiones a un pedido
-- ---------------------------------------------------------------------------

-- El INSERT va con SELECT y no con VALUES para poder acotar por sucursal: `order_vehicles`
-- no tiene `branch_id`, así que la única forma de comprobar el alcance es preguntarle al
-- pedido. Con VALUES, el id del pedido entra tal cual desde el cliente y un camión de
-- Holguín acaba colgado de un pedido de La Habana. Cero filas es el 404.
-- name: AsignarVehiculoAPedido :one
INSERT INTO order_vehicles (order_id, vehicle_id, is_primary)
SELECT o.id, sqlc.arg('vehicle_id'), sqlc.arg('is_primary')
FROM orders o
WHERE o.id = sqlc.arg('order_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ON CONFLICT (order_id, vehicle_id) DO UPDATE SET is_primary = excluded.is_primary
RETURNING id, order_id, vehicle_id, is_primary;

-- name: ListarVehiculosDePedido :many
SELECT ov.id, ov.vehicle_id, ov.is_primary, v.name, v.plate, v.capacity
FROM order_vehicles ov
JOIN vehicles v ON v.id = ov.vehicle_id
JOIN orders   o ON o.id = ov.order_id
WHERE ov.order_id = sqlc.arg('pedido_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY ov.is_primary DESC, v.name ASC;
