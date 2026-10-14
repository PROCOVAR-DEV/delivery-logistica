-- El catálogo de tipos de vehículo — LA TABLA QUE FALTABA.
--
-- En delivery esto se guardaba en `Settings.tiposVehiculo`, un campo que NUNCA EXISTIÓ en
-- el esquema: la pantalla de vehículos dejaba crear tipos nuevos, los mandaba a guardar y
-- se perdían sin un solo error. Por eso `Vehicle.type` era un conjunto abierto que nadie
-- podía cerrar — su catálogo no estaba en ninguna parte.
--
-- POR SUCURSAL desde la 00018 (Jose, 14/10/2026). Cada sucursal tiene SUS tipos, y el costo por
-- km del tipo es el que cotiza el domicilio de SU flota: que Santiago editara «truck» movía el
-- precio en las ocho. `branch_id` NULO = el tipo «de todas»: los de fábrica, que sólo usan los
-- camiones compartidos (`vehicles.branch_id` nulo).
--
-- OJO con la forma del filtro, que NO es la de vehículos: allí `branch_id IS NULL` pasa para
-- que un camión compartido salga en la lista de todas; aquí NO. Quien tiene sucursal ve y toca
-- sólo los SUYOS, y los «de todas» le son tan ajenos como los de Holguín (404, no 403). Sólo
-- quien no tiene sucursal (SUPER ADMIN / DESARROLLADOR en modo «todas») ve todos.

-- Los tipos que se pueden elegir. Por defecto sólo los activos: `activo` existe para poder
-- RETIRAR un tipo sin romper los vehículos que ya lo usan — borrarlo dejaría la clave
-- ajena colgando y no hay a dónde mover un camión que ya es de ese tipo.
--
-- Lleva la sucursal (id y nombre) porque quien ve todas tiene el mismo nombre varias veces
-- y, sin ella, no sabe cuál es cuál.
-- name: ListarTiposDeVehiculo :many
SELECT
    vt.id, vt.nombre, vt.costo_km_usd, vt.activo, vt.created_at, vt.updated_at,
    vt.branch_id,
    b.name AS sucursal_nombre,
    (SELECT count(*) FROM vehicles v WHERE v.vehicle_type_id = vt.id) AS vehiculos
FROM vehicle_types vt
LEFT JOIN branches b ON b.id = vt.branch_id
WHERE (sqlc.narg('solo_activos')::boolean IS NULL
       OR NOT sqlc.narg('solo_activos')::boolean
       OR vt.activo)
  AND (sqlc.narg('sucursal')::uuid IS NULL OR vt.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY vt.nombre ASC, b.name ASC NULLS FIRST;

-- name: ObtenerTipoDeVehiculo :one
SELECT vt.id, vt.nombre, vt.costo_km_usd, vt.activo, vt.created_at, vt.updated_at, vt.branch_id
FROM vehicle_types vt
WHERE vt.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR vt.branch_id = sqlc.narg('sucursal')::uuid);

-- Por nombre, para el alta y la edición de vehículos: el cuerpo del POST manda
-- `type: "truck"`, un texto, y hay que traducirlo al id del catálogo.
--
-- `sucursal_del_camion` NO ES EL ALCANCE de quien pregunta: es la sucursal del camión que se
-- da de alta o se edita (nulo = compartido), y el tipo tiene que ser de ESA sucursal. Distinto
-- por una razón concreta: un SUPER ADMIN en modo «todas» que edita el camión de Holguín tiene
-- alcance nulo y tiene que encontrar el «truck» de Holguín, no el de todas; y uno que mira
-- Santiago y edita un camión compartido tiene que encontrar el de todas, no el de Santiago.
-- `IS NOT DISTINCT FROM` y no `=`: el nulo es «de todas» y con `=` no casaría nunca. Los dos
-- índices únicos parciales de la 00018 dejan UNA fila como máximo.
-- name: BuscarTipoDeVehiculoPorNombre :one
SELECT vt.id, vt.nombre, vt.costo_km_usd, vt.activo, vt.branch_id
FROM vehicle_types vt
WHERE vt.nombre = sqlc.arg('nombre')
  AND vt.branch_id IS NOT DISTINCT FROM sqlc.narg('sucursal_del_camion')::uuid;

-- El costo por km del tipo es un VALOR POR DEFECTO, no el bueno: cada vehículo puede tener
-- el suyo porque quien lo da es el camionero y dos camiones del mismo tipo no cuestan
-- igual. Se deja vacío a propósito en los cuatro que vienen de fábrica — ponerle un número
-- inventado es peor que no tenerlo, porque se cobra igual y nadie lo revisa.
--
-- El tipo NACE en la sucursal del alcance (`branch_id`, que lo rellena `alcance.Acotado`);
-- quien no tiene alcance lo deja «de todas».
-- name: CrearTipoDeVehiculo :one
INSERT INTO vehicle_types (nombre, costo_km_usd, activo, branch_id)
VALUES (sqlc.arg('nombre'), sqlc.narg('costo_km_usd'), sqlc.arg('activo'), sqlc.narg('branch_id'))
RETURNING id, nombre, costo_km_usd, activo, created_at, updated_at, branch_id;

-- name: ActualizarTipoDeVehiculo :one
UPDATE vehicle_types SET
    nombre       = coalesce(sqlc.narg('nombre')::text, nombre),
    costo_km_usd = CASE WHEN sqlc.arg('tocar_costo')::boolean
                        THEN sqlc.narg('costo_km_usd')::double precision
                        ELSE costo_km_usd END,
    activo       = coalesce(sqlc.narg('activo')::boolean, activo)
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, nombre, costo_km_usd, activo, created_at, updated_at, branch_id;

-- Retirar un tipo NO es borrarlo. Se desactiva: deja de ofrecerse en el desplegable y los
-- camiones que ya lo tienen siguen funcionando. Un DELETE choca contra la clave ajena de
-- `vehicles.vehicle_type_id`, y hacerlo a la fuerza dejaría camiones sin tipo, que es un
-- camión sin costo por km y por tanto sin fórmula del domicilio.
--
-- DEVUELVE LA SUCURSAL DEL TIPO, por lo mismo que `BorrarVehiculo`: de ahí sale el aviso en
-- vivo. `:one`: cero filas es «no existe O no es de tu sucursal», o sea el 404.
-- name: RetirarTipoDeVehiculo :one
UPDATE vehicle_types SET activo = false
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING branch_id;

-- Sólo se puede borrar de verdad un tipo que no use nadie. Se comprueba aquí, en la misma
-- sentencia, y no con un conteo antes: entre el conteo y el borrado cabe un alta.
--
-- Cero filas aquí NO es el 404: es «no existe, no es tuyo, o lo usa un camión», y el manejador
-- lo distingue intentando retirarlo (que también va acotado). Devuelve la sucursal del tipo
-- borrado, porque cuando se avisa la fila ya no está.
-- name: BorrarTipoDeVehiculoSinUso :one
DELETE FROM vehicle_types vt
WHERE vt.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR vt.branch_id = sqlc.narg('sucursal')::uuid)
  AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.vehicle_type_id = vt.id)
RETURNING vt.branch_id;

-- Una sucursal nueva nace con COPIA de los tipos «de todas» (nombre, costo y estado), como
-- las que ya existían cuando la 00018 se los dio a cada una. Sin esto empezaría con el catálogo
-- vacío y su primer camión (`type` por defecto «truck») daría 400. Va en la misma transacción
-- que el alta de la sucursal.
-- name: SembrarTiposDeVehiculoEnSucursal :execrows
INSERT INTO vehicle_types (nombre, costo_km_usd, activo, branch_id)
SELECT t.nombre, t.costo_km_usd, t.activo, sqlc.arg('sucursal')::uuid
FROM vehicle_types t
WHERE t.branch_id IS NULL;
