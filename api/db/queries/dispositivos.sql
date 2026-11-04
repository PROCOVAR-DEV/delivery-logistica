-- LOS TELÉFONOS DE LOS DISTRIBUIDORES Y SUS ENLACES (00032, 04/11/2026). Sin cuenta de Accesos: el logístico manda un enlace por ruta y el
-- teléfono que lo reclama queda como dueño de esa ruta.

-- name: DispositivoDistribuidor :one
SELECT id, nombre, branch_id, distribuidor_id, activo FROM dispositivos_distribuidor WHERE id = sqlc.arg('id');

-- name: TocarDispositivoDistribuidor :exec
UPDATE dispositivos_distribuidor SET last_seen_at = now() WHERE id = sqlc.arg('id');

-- name: CrearDispositivoDistribuidor :one
INSERT INTO dispositivos_distribuidor (id, nombre, branch_id, distribuidor_id, secreto_hash)
VALUES (sqlc.arg('id'), sqlc.narg('nombre'), sqlc.arg('sucursal'), sqlc.narg('distribuidor'), sqlc.arg('secreto_hash'))
RETURNING id, nombre, branch_id, distribuidor_id, activo;

-- El secreto con el que el teléfono se identifica al reclamar otra ruta o renovar su acceso.
-- name: SecretoDelDispositivo :one
SELECT secreto_hash, activo, branch_id FROM dispositivos_distribuidor WHERE id = sqlc.arg('id');

-- Para el RECLAMAR: el enlace por su token (con la ruta y su sucursal), sin acotar: aún no hay sesión.
-- name: EnlaceDeRutaPorToken :one
SELECT e.id, e.ruta_id, e.dispositivo_id, e.reclamado_at, e.revocado_at, r.branch_id, r.distribuidor_id, r.status, r.vehicle_id,
       coalesce((SELECT d.nombre FROM distribuidores d WHERE d.id = r.distribuidor_id), '')::text AS distribuidor_nombre
FROM enlaces_de_ruta e JOIN routes r ON r.id = e.ruta_id
WHERE e.token = sqlc.arg('token');

-- Reclamar es ATÓMICO: solo gana quien lo encuentre sin dueño (o ya suyo). Devuelve 0 filas si lo ganó otro teléfono entre medias.
-- name: ReclamarEnlaceDeRuta :execrows
UPDATE enlaces_de_ruta SET dispositivo_id = sqlc.arg('dispositivo'), reclamado_at = coalesce(reclamado_at, now())
WHERE id = sqlc.arg('id') AND revocado_at IS NULL AND (dispositivo_id IS NULL OR dispositivo_id = sqlc.arg('dispositivo'));

-- name: AsignarRutaADispositivo :exec
UPDATE routes SET dispositivo_id = sqlc.arg('dispositivo') WHERE id = sqlc.arg('ruta');

-- El enlace vivo de una ruta (acotado a la sucursal de la oficina que pregunta).
-- name: EnlaceVivoDeUnaRuta :one
SELECT e.id, e.token, e.created_at, e.dispositivo_id, e.reclamado_at, d.nombre AS dispositivo_nombre
FROM enlaces_de_ruta e
JOIN routes r ON r.id = e.ruta_id
LEFT JOIN dispositivos_distribuidor d ON d.id = e.dispositivo_id
WHERE e.ruta_id = sqlc.arg('ruta') AND e.revocado_at IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid);

-- name: CrearEnlaceDeRuta :one
INSERT INTO enlaces_de_ruta (ruta_id, token, creado_por) VALUES (sqlc.arg('ruta'), sqlc.arg('token'), sqlc.narg('creado_por'))
RETURNING id, token, created_at;

-- Soltar el enlace: lo revoca y deja la ruta sin dueño, para mandarle uno nuevo a otro teléfono.
-- name: RevocarEnlacesDeUnaRuta :exec
UPDATE enlaces_de_ruta SET revocado_at = now() WHERE ruta_id = sqlc.arg('ruta') AND revocado_at IS NULL;

-- name: SoltarRutaDeSuDispositivo :exec
UPDATE routes SET dispositivo_id = NULL WHERE id = sqlc.arg('ruta');

-- EL VÍNCULO VEHÍCULO <-> TELÉFONO (00035).
-- name: VinculoVivoDeVehiculo :one
SELECT id, dispositivo_id FROM vinculos_vehiculo_dispositivo WHERE vehicle_id = sqlc.arg('vehiculo') AND hasta IS NULL;

-- name: VinculoVivoDeDispositivo :one
SELECT id, vehicle_id FROM vinculos_vehiculo_dispositivo WHERE dispositivo_id = sqlc.arg('dispositivo') AND hasta IS NULL;

-- name: CrearVinculoDeVehiculo :one
INSERT INTO vinculos_vehiculo_dispositivo (vehicle_id, dispositivo_id, branch_id, vinculado_por)
VALUES (sqlc.arg('vehiculo'), sqlc.arg('dispositivo'), sqlc.arg('sucursal'), sqlc.narg('por'))
RETURNING id;

-- Desvincular: cierra el vínculo vivo del vehículo (acotado a la sucursal de la oficina). 0 filas = no estaba vinculado (o no es de su sucursal).
-- name: CerrarVinculoDeVehiculo :one
UPDATE vinculos_vehiculo_dispositivo vv SET hasta = now(), desvinculado_por = sqlc.narg('por'), motivo = sqlc.narg('motivo')
FROM vehicles v
WHERE vv.vehicle_id = v.id AND vv.vehicle_id = sqlc.arg('vehiculo') AND vv.hasta IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR v.branch_id = sqlc.narg('sucursal')::uuid OR v.branch_id IS NULL)
RETURNING vv.id, vv.dispositivo_id;

-- Las rutas planificadas o en curso del teléfono se sueltan y sus enlaces se revocan (se mandan a otro con un enlace nuevo). Las cerradas se quedan de historia.
-- name: SoltarRutasAbiertasDeUnDispositivo :many
WITH enlaces AS (
    UPDATE enlaces_de_ruta SET revocado_at = now()
    WHERE revocado_at IS NULL
      AND ruta_id IN (SELECT rr.id FROM routes rr WHERE rr.dispositivo_id = sqlc.arg('dispositivo') AND rr.status IN ('planned', 'in_progress'))
)
UPDATE routes AS ru SET dispositivo_id = NULL
WHERE ru.dispositivo_id = sqlc.arg('dispositivo') AND ru.status IN ('planned', 'in_progress')
RETURNING ru.id;

-- name: ListarVinculosDeVehiculo :many
SELECT vv.id, vv.dispositivo_id, d.nombre AS dispositivo_nombre, vv.desde, vv.hasta, vv.vinculado_por, vv.desvinculado_por, vv.motivo
FROM vinculos_vehiculo_dispositivo vv
JOIN vehicles v ON v.id = vv.vehicle_id
JOIN dispositivos_distribuidor d ON d.id = vv.dispositivo_id
WHERE vv.vehicle_id = sqlc.arg('vehiculo')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR v.branch_id = sqlc.narg('sucursal')::uuid OR v.branch_id IS NULL)
ORDER BY vv.desde DESC;
