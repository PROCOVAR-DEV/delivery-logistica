-- Los distribuidores: el nomenclador de QUIÉN REPARTE, POR SUCURSAL (issue 7 de Amado, 14/10/2026).
--
-- Es la persona responsable de la entrega y de devolver las facturas entregadas: el chofer
-- mismo si va en triciclo, un empleado de Procovar si el vehículo es rentado. Se asocia a la
-- ruta AL CREARLA (`routes.distribuidor_id`, nulo = ruta histórica o armada sin él).
--
-- El filtro es el de siempre en las rutas: `sucursal` NULL = «todas» (SUPER ADMIN y
-- DESARROLLADOR sin sucursal elegida) y no acota; con sucursal, un distribuidor de otra es un
-- 404 y no un 403, igual que un id que no existe. A diferencia de los tipos de vehículo NO hay
-- «de todas»: `branch_id` es NOT NULL y quien ve todas ve todas las listas (cada fila dice de qué
-- sucursal es). Lo que NO hace el modo «todas» es CREAR: nacería sin dueño (el manejador contesta
-- 400 pidiendo elegir sucursal).

-- La lista. Por defecto salen TODOS, activos y retirados: la usan la pantalla de mantenimiento
-- (tiene que ver lo retirado para volver a activarlo) y la BAJADA del aparato (una ruta vieja
-- enseña el nombre de quien la repartió aunque ya esté retirado). `solo_activos` es para el
-- selector de una ruta nueva, que sólo ofrece a quien sigue en activo.
--
-- `rutas` dice cuántas rutas lo usan: de ahí sale «se retira, no se borra».
-- name: ListarDistribuidores :many
SELECT
    d.id, d.branch_id, d.nombre, d.activo, d.created_at, d.updated_at,
    b.name AS sucursal_nombre,
    (SELECT count(*) FROM routes r WHERE r.distribuidor_id = d.id) AS rutas
FROM distribuidores d
JOIN branches b ON b.id = d.branch_id
WHERE (sqlc.narg('solo_activos')::boolean IS NULL
       OR NOT sqlc.narg('solo_activos')::boolean
       OR d.activo)
  AND (sqlc.narg('sucursal')::uuid IS NULL OR d.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY b.name ASC, lower(d.nombre) ASC, d.id ASC;

-- Uno, para validar el `distribuidorId` que viene en el cuerpo de una ruta. Cero filas es «no
-- existe O no es de tu sucursal»: desde fuera son lo mismo.
-- name: ObtenerDistribuidor :one
SELECT d.id, d.branch_id, d.nombre, d.activo
FROM distribuidores d
WHERE d.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR d.branch_id = sqlc.narg('sucursal')::uuid);

-- Nace en la sucursal de quien llama (`branch_id` lo rellena `alcance.Acotado`). El manejador no
-- llama a esta consulta sin sucursal: en modo «todas» contesta 400.
-- name: CrearDistribuidor :one
INSERT INTO distribuidores (branch_id, nombre, activo)
VALUES (sqlc.arg('branch_id'), sqlc.arg('nombre'), sqlc.arg('activo'))
RETURNING id, branch_id, nombre, activo, created_at, updated_at;

-- Renombrar o volver a activar/retirar. La sucursal de un distribuidor NO se cambia nunca: una
-- ruta ya firmada por él seguiría apuntando a quien dejó de ser de su sucursal.
-- name: ActualizarDistribuidor :one
UPDATE distribuidores SET
    nombre = coalesce(sqlc.narg('nombre')::text, nombre),
    activo = coalesce(sqlc.narg('activo')::boolean, activo)
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, branch_id, nombre, activo, created_at, updated_at;

-- Retirar NO es borrar: se desactiva. Deja de ofrecerse en una ruta nueva y las rutas que ya lo
-- llevan siguen diciendo quién las repartió. DEVUELVE LA SUCURSAL del distribuidor, de donde sale
-- el aviso en vivo. `:one`: cero filas es «no existe O no es de tu sucursal», o sea el 404.
-- name: RetirarDistribuidor :one
UPDATE distribuidores SET activo = false
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING branch_id;

-- Sólo se borra de verdad al que no usa ninguna ruta. Se comprueba aquí, en la misma sentencia, y
-- no con un conteo antes: entre el conteo y el borrado cabe una ruta nueva.
--
-- Cero filas NO es el 404: es «no existe, no es tuyo, o lo usa una ruta», y el manejador lo
-- distingue intentando retirarlo (que también va acotado). Devuelve la sucursal del borrado,
-- porque cuando se avisa la fila ya no está.
-- name: BorrarDistribuidorSinUso :one
DELETE FROM distribuidores d
WHERE d.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR d.branch_id = sqlc.narg('sucursal')::uuid)
  AND NOT EXISTS (SELECT 1 FROM routes r WHERE r.distribuidor_id = d.id)
RETURNING d.branch_id;
