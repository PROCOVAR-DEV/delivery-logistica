-- Las consultas del sincronizador, para sqlc.
--
-- Están escritas a partir de las preguntas que se hacen de verdad, no de las tablas:
--
--   «¿qué sucursal lleva sin reportar?»      → PanelDeEstado, AparatosSinSubir
--   «¿he visto ya esta clave?»               → BuscarApunte
--   «¿qué le queda a este aparato?»          → EstadoDeAparato, AparatosConPendientes
--   «¿qué se le rechazó y por qué?»          → RechazosSinAtender, RechazosDeAparato
--   «¿de qué ruta hablaba este local-…?»     → ResolverProvisional
--
-- Los índices del esquema son los de estas consultas y de ninguna más.
--
-- CONVENCIÓN DE PARÁMETROS, la misma que en `api/db/queries`:
--
--   El alcance por sucursal es SEGURIDAD y va SIEMPRE en el SQL, nunca en Go. Se expresa
--   con un solo parámetro que admite «todas las sucursales» como NULL — el Super Admin:
--
--       (sqlc.narg('sucursal')::uuid IS NULL OR a.branch_id = sqlc.narg('sucursal')::uuid)
--
--   Aquí importa el doble, porque el panel es justo lo que enseña quién no ha subido: sin
--   esa línea, el logístico de Camagüey vería la cola y los rechazos de las otras nueve
--   sucursales. El `::uuid` explícito es lo que obliga a sqlc a generarlo como anulable.

-- ===========================================================================
-- 1 · Registro de aparatos
-- ===========================================================================

-- El alta de una instalación: `POST /sync/aparato`. El uuid lo pone la base y es lo que el
-- aparato guarda; nunca se lo inventa él.
-- name: AltaAparato :one
INSERT INTO aparatos (persona, branch_id, nombre, visto_at)
VALUES ($1, $2, $3, now())
RETURNING *;

-- name: AparatoPorId :one
SELECT * FROM aparatos WHERE id = $1;

-- La señal de vida. Se llama en CADA petición del aparato, baje o suba: es lo que
-- distingue «el teléfono está apagado en un cajón» de «el teléfono trabaja pero no sube».
-- name: TocarAparato :exec
UPDATE aparatos SET visto_at = now() WHERE id = $1;

-- Los aparatos de una sucursal. Con el alcance cerrado por sucursal, es lo que puede ver
-- quien no es Super Admin.
-- name: AparatosDeSucursal :many
SELECT * FROM aparatos
WHERE branch_id = $1
ORDER BY created_at;

-- ===========================================================================
-- 2 · Estado de sincronización
-- ===========================================================================

-- La fila de estado se abre en el alta, vacía. Así el panel enseña al aparato recién dado
-- de alta como «nunca ha subido» en vez de no enseñarlo: un aparato que no aparece es un
-- aparato del que nadie se acuerda.
--
-- Va sin RETURNING y como `:exec` a propósito: con `DO NOTHING` la fila que ya existía no
-- se devuelve, así que un `:one` daría «no hay filas» justo en el caso normal de volver a
-- abrirla. Para leerla está `EstadoDeAparato`.
-- name: AbrirEstado :exec
INSERT INTO aparato_estado (aparato_id)
VALUES ($1)
ON CONFLICT (aparato_id) DO NOTHING;

-- Tras servir `GET /sync/bajada`. `bajada_hasta` es el `hasta` que se le devolvió — lo
-- pone el servidor, nunca el aparato.
-- name: AnotarBajada :exec
UPDATE aparato_estado
SET bajada_at = now(),
    bajada_hasta = $2
WHERE aparato_id = $1;

-- Tras procesar un lote de `POST /sync/subida`. Los `pendientes` los dice el aparato (la
-- cola vive en el teléfono); los rechazos del lote se SUMAN al contador, no lo sustituyen.
-- name: AnotarSubida :exec
UPDATE aparato_estado
SET subida_at = now(),
    pendientes = sqlc.arg('pendientes'),
    rechazados = rechazados + sqlc.arg('rechazados_del_lote')
WHERE aparato_id = sqlc.arg('aparato_id');

-- «¿Qué le queda a este aparato?», de un tirón.
-- name: EstadoDeAparato :one
SELECT a.id, a.persona, a.branch_id, a.nombre, a.visto_at, a.created_at AS alta_at,
       e.bajada_at, e.bajada_hasta, e.subida_at, e.pendientes, e.rechazados
FROM aparatos a
JOIN aparato_estado e ON e.aparato_id = a.id
WHERE a.id = $1;

-- EL PANEL: `GET /sync/estado`. Todo lo que hay que ver de todos los aparatos, con el que
-- peor está arriba.
--
-- El orden es el de la urgencia, no el alfabético: primero el que nunca subió (NULLS
-- FIRST), luego el que lleva más tiempo sin hacerlo. Ordenar por sucursal dejaría a Palma
-- enterrada entre nueve filas verdes.
-- name: PanelDeEstado :many
SELECT a.id, a.persona, a.branch_id, a.nombre, a.visto_at, a.created_at AS alta_at,
       e.bajada_at, e.bajada_hasta, e.subida_at, e.pendientes, e.rechazados,
       -- Cuánto lleva sin subir, EN SEGUNDOS y sin decimales.
       --
       -- En segundos y no en horas porque el panel decide el aviso por umbral y una
       -- división ahí obliga a decidir el redondeo en dos sitios. Y **-1, no vacío**:
       -- el que nunca ha subido es justo el que más importa —sale el primero con
       -- `NULLS FIRST`— y un vacío en el tipo generado dejaba la columna sin tipo.
       -- El panel distingue «nunca» por `subida_at`, que sí viene vacío.
       COALESCE(EXTRACT(EPOCH FROM (now() - e.subida_at)), -1)::bigint AS segundos_sin_subir
FROM aparatos a
JOIN aparato_estado e ON e.aparato_id = a.id
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR a.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY e.subida_at ASC NULLS FIRST;

-- «¿Qué aparatos llevan más de N horas sin subir?» — la llamada de teléfono.
--
-- `IS NULL OR` y no sólo la comparación: un aparato que NUNCA subió no cumple ninguna
-- comparación de fechas y se quedaría fuera de la lista justo el que más falta hace ver.
-- name: AparatosSinSubir :many
SELECT a.id, a.persona, a.branch_id, a.nombre, a.visto_at,
       e.subida_at, e.bajada_at, e.pendientes, e.rechazados
FROM aparatos a
JOIN aparato_estado e ON e.aparato_id = a.id
WHERE (e.subida_at IS NULL
       OR e.subida_at < now() - make_interval(hours => sqlc.arg('horas')::int))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR a.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY e.subida_at ASC NULLS FIRST;

-- Los que tienen trabajo sin subir ahora mismo, el que más primero.
-- name: AparatosConPendientes :many
SELECT a.id, a.persona, a.branch_id, a.nombre,
       e.subida_at, e.pendientes, e.rechazados
FROM aparatos a
JOIN aparato_estado e ON e.aparato_id = a.id
WHERE e.pendientes > 0
  AND (sqlc.narg('sucursal')::uuid IS NULL OR a.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY e.pendientes DESC;

-- ===========================================================================
-- 3 · Idempotencia
-- ===========================================================================

-- «¿He visto ya esta clave?» Se pregunta una vez por cada apunte del lote, antes de
-- aplicarlo, y es la consulta más repetida de todo el servicio: va por la primaria.
--
-- Trae el motivo con LEFT JOIN porque para contestar `repetido` hay que devolver la MISMA
-- respuesta de la primera vez, y si aquella fue un rechazo, la respuesta incluye su motivo.
-- Y trae los `descartados` de aquella vez por lo mismo: si el apunte entró dejando pedidos
-- fuera, ese aviso forma parte de la respuesta y tiene que volver igual. Sin él, un apunte
-- cuya respuesta se perdió vuelve como `repetido` sobre una ruta que salió con nueve de
-- doce y nadie se entera de los tres.
-- name: BuscarApunte :one
SELECT p.aparato_id, p.clave, p.metodo, p.ruta, p.estado, p.id_creado, p.hecho_at,
       p.created_at, p.descartados, r.motivo
FROM apuntes p
LEFT JOIN apuntes_rechazados r
       ON r.aparato_id = p.aparato_id AND r.clave = p.clave
WHERE p.aparato_id = $1 AND p.clave = $2;

-- Se anota DESPUÉS de aplicarlo y en la misma transacción que el cambio en el reparto. Al
-- revés —anotar y luego aplicar— un corte en medio dejaría la clave marcada como hecha con
-- el trabajo sin hacer, y el reintento contestaría `repetido` sobre algo que no existe.
-- name: AnotarApunteAplicado :one
INSERT INTO apuntes (aparato_id, clave, metodo, ruta, estado, id_creado, hecho_at, descartados)
VALUES ($1, $2, $3, $4, 'aplicado', $5, $6, $7)
RETURNING *;

-- El rechazo también se anota: `rechazado` no se reintenta, así que si el aparato vuelve a
-- mandarlo hay que contestarle lo mismo y no volver a evaluarlo.
-- name: AnotarApunteRechazado :one
INSERT INTO apuntes (aparato_id, clave, metodo, ruta, estado, hecho_at)
VALUES ($1, $2, $3, $4, 'rechazado', $5)
RETURNING *;

-- La barrida de caducados, para que la tabla no crezca para siempre. Sólo los APLICADOS:
-- los rechazados se quedan hasta que una persona decida, y además su fila hace falta para
-- la clave ajena de la bandeja.
-- name: PurgarApuntes :execrows
DELETE FROM apuntes
WHERE estado = 'aplicado' AND expira_at < now();

-- Lo último que mandó un aparato, para mirar un caso concreto cuando algo no cuadra.
-- name: UltimosApuntesDeAparato :many
SELECT * FROM apuntes
WHERE aparato_id = $1
ORDER BY created_at DESC
LIMIT $2;

-- ===========================================================================
-- 4 · Los rechazados
-- ===========================================================================

-- Se escribe en la misma transacción que `AnotarApunteRechazado`: el apunte y su motivo
-- entran juntos o no entra ninguno. Un apunte marcado rechazado sin motivo en la bandeja
-- es exactamente el descarte en silencio que esto viene a impedir.
-- name: AnotarRechazo :one
INSERT INTO apuntes_rechazados (aparato_id, clave, motivo, cuerpo)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- LA BANDEJA: lo que está esperando a que una persona decida, lo más reciente arriba.
-- Con la sucursal y el aparato, porque el motivo solo no dice a quién hay que llamar.
-- name: RechazosSinAtender :many
SELECT r.id, r.aparato_id, r.clave, r.motivo, r.rechazado_at, r.cuerpo,
       a.persona, a.branch_id, a.nombre,
       p.metodo, p.ruta, p.hecho_at
FROM apuntes_rechazados r
JOIN aparatos a ON a.id = r.aparato_id
JOIN apuntes  p ON p.aparato_id = r.aparato_id AND p.clave = r.clave
WHERE r.atendido_at IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR a.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY r.rechazado_at DESC;

-- Todo lo que se le rechazó a un aparato, atendido o no.
-- name: RechazosDeAparato :many
SELECT r.id, r.aparato_id, r.clave, r.motivo, r.rechazado_at, r.cuerpo,
       r.atendido_at, r.atendido_por,
       p.metodo, p.ruta, p.hecho_at
FROM apuntes_rechazados r
JOIN apuntes p ON p.aparato_id = r.aparato_id AND p.clave = r.clave
WHERE r.aparato_id = $1
ORDER BY r.rechazado_at DESC;

-- Una persona lo dio por visto. No se borra nunca: queda con quién lo atendió y cuándo.
-- Si no devuelve fila es que ya estaba atendido —otro llegó antes—, no que no exista.
-- name: AtenderRechazo :one
UPDATE apuntes_rechazados
SET atendido_at = now(),
    atendido_por = sqlc.arg('atendido_por')
WHERE id = sqlc.arg('id') AND atendido_at IS NULL
RETURNING *;

-- Cuántos quedan sin atender por sucursal. Es el número rojo de la cabecera del panel.
-- name: RechazosSinAtenderPorSucursal :many
SELECT a.branch_id, count(*) AS sin_atender
FROM apuntes_rechazados r
JOIN aparatos a ON a.id = r.aparato_id
WHERE r.atendido_at IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR a.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY a.branch_id
ORDER BY sin_atender DESC;

-- ===========================================================================
-- 5 · Identificadores provisionales
-- ===========================================================================

-- Se anota al aplicar el apunte que creó la cosa, junto con el id que se devuelve.
--
-- Si ese `local-…` ya está traducido, LA TRADUCCIÓN BUENA ES LA PRIMERA. Sobrescribirla
-- con un id nuevo dejaría huérfano al de verdad —la ruta ya creada— y es justamente cómo
-- se duplica una ruta armada sin conexión.
--
-- Por eso el `DO UPDATE` se asigna el valor que ya tenía: no cambia nada, pero devuelve la
-- fila que manda. Con `DO NOTHING` no volvería ninguna y quien llama no sabría con qué id
-- contestarle al aparato, que es lo único que necesita.
-- name: AnotarProvisional :one
INSERT INTO ids_provisionales (aparato_id, provisional, id_real)
VALUES ($1, $2, $3)
ON CONFLICT (aparato_id, provisional)
DO UPDATE SET id_real = ids_provisionales.id_real
RETURNING *;

-- «¿De qué era este local-…?» Se pregunta cuando llega un apunte que todavía trae el
-- provisional en la ruta: el aparato se cortó antes de sustituirlo en el resto de su cola.
-- Traducirlo aquí es lo que evita el 404 sobre el trabajo de toda la tarde.
-- name: ResolverProvisional :one
SELECT id_real FROM ids_provisionales
WHERE aparato_id = $1 AND provisional = $2;

-- Los del aparato, para poder mandarle el mapeo entero si perdió el suyo.
-- name: ProvisionalesDeAparato :many
SELECT * FROM ids_provisionales
WHERE aparato_id = $1
ORDER BY created_at;
