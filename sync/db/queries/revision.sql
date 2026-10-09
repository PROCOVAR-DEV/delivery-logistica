-- Las consultas de LA BANDEJA DE REVISIÓN (`docs/bandeja-de-revision.md`, B.2), para sqlc.
--
-- Sólo contabilidad de la sincronización: nada de aquí toca pedidos, rutas ni tablero.
--
-- Mismas convenciones que `sync.sql`: el alcance por sucursal es SEGURIDAD y va en el SQL, nunca en
-- Go (`sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = …`: NULL es «todas», el Super Admin);
-- y lo que se decide va en la propia sentencia (`WHERE estado IN (…)`), no en un «leer y luego
-- escribir».
--
-- «Vivo» = `en_revision`, `aplicando`, `rechazado`: lo que sigue esperando a una persona. Es lo que
-- cuentan los cupos y el número rojo de `/sync/estado`.
--
-- QUÉ ES DE S1 Y QUÉ DE S2. La entrega (lo primero) la usa S1. Lo de «El revisor» y «El libro» lo
-- usará S2 (listar, aplicar, descartar); está aquí para que S2 empiece con migración, consultas y
-- dobles ya entregados, y está probado contra Postgres de verdad (`revision_motor_real_test.go`).

-- ===========================================================================
-- 1 · La entrega
-- ===========================================================================

-- Una fila por token de entrega: la app manda los apuntes de uno en uno, y todos los que llegan con el
-- mismo `jti` caen en la MISMA entrega. El `DO UPDATE` no cambia nada: devuelve la fila que manda.
-- name: AltaRevisionEntrega :one
INSERT INTO revision_entregas (aparato_id, persona, persona_nombre, branch_id, token_jti, desde_ip, agente, version_app)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (aparato_id, token_jti) DO UPDATE SET updated_at = now()
RETURNING *;

-- Serializa las entregas de una sucursal para que contar el cupo y escribir sean UNA sola cosa: sin
-- esto, N peticiones en paralelo pasarían todas por debajo del tope a la vez. Se suelta sola al acabar
-- la transacción.
-- name: BloquearRevisionDeSucursal :exec
SELECT pg_advisory_xact_lock(hashtextextended('revision:' || sqlc.arg('sucursal')::uuid::text, 0));

-- «¿He visto ya esta clave?», SIN el cuerpo (que puede pesar 128 KiB): se pregunta una vez por cada
-- apunte de CADA subida normal y de cada entrega. Va por la primaria.
-- name: EstadoDeRevisionDeApunte :one
SELECT aparato_id, clave, entrega_id, orden, estado, huella, motivo, id_creado, descartados,
       decidido_por_nombre, decidido_at
FROM revision_apuntes
WHERE aparato_id = $1 AND clave = $2;

-- La idempotencia: reentregar la misma clave NO inserta (y no devuelve fila). Quien llama ya miró
-- `EstadoDeRevisionDeApunte`; esto es la red contra dos peticiones a la vez. El orden FIFO lo pone el
-- servidor, por orden de llegada dentro del aparato.
-- name: InsertarRevisionApunte :one
INSERT INTO revision_apuntes (aparato_id, clave, entrega_id, orden, metodo, ruta, cuerpo, provisional,
                              hecho_at, huella, resumen_del_aparato)
VALUES (sqlc.arg('aparato_id'), sqlc.arg('clave'), sqlc.arg('entrega_id'),
        (SELECT COALESCE(MAX(orden), -1) + 1 FROM revision_apuntes WHERE aparato_id = sqlc.arg('aparato_id')),
        sqlc.arg('metodo'), sqlc.arg('ruta'), sqlc.narg('cuerpo'), sqlc.narg('provisional'),
        sqlc.arg('hecho_at'), sqlc.arg('huella'), sqlc.narg('resumen_del_aparato'))
ON CONFLICT (aparato_id, clave) DO NOTHING
RETURNING *;

-- Los cupos de una persona y de una sucursal, sólo de lo VIVO. Una sola pasada.
-- name: CupoDeRevision :one
SELECT (count(*) FILTER (WHERE e.persona = sqlc.arg('persona')::text))::bigint AS de_la_persona,
       (COALESCE(sum(octet_length(a.cuerpo)) FILTER (WHERE e.persona = sqlc.arg('persona')::text), 0))::bigint
           AS bytes_de_la_persona,
       (count(*) FILTER (WHERE e.branch_id = sqlc.arg('sucursal')::uuid))::bigint AS de_la_sucursal
FROM revision_apuntes a
JOIN revision_entregas e ON e.id = a.entrega_id
WHERE a.estado IN ('en_revision', 'aplicando', 'rechazado')
  AND (e.persona = sqlc.arg('persona')::text OR e.branch_id = sqlc.arg('sucursal')::uuid);

-- `GET /sync/revision/mias`: qué ha pasado con lo de este aparato. Lo vivo primero y, dentro, lo más
-- reciente. Sin el cuerpo. El tope lo comprueba quien llama (pide uno más de lo que va a enseñar).
-- name: RevisionDeAparato :many
SELECT clave, entrega_id, orden, estado, decidido_por_nombre, decidido_at, motivo, id_creado, descartados,
       updated_at
FROM revision_apuntes
WHERE aparato_id = sqlc.arg('aparato_id')
ORDER BY (estado IN ('en_revision', 'aplicando', 'rechazado')) DESC, updated_at DESC, clave
LIMIT sqlc.arg('limite')::int;

-- El segundo «número rojo» de `/sync/estado`, por sucursal.
-- name: RevisionSinDecidirPorSucursal :many
SELECT e.branch_id, count(*) AS en_revision
FROM revision_apuntes a
JOIN revision_entregas e ON e.id = a.entrega_id
WHERE a.estado IN ('en_revision', 'aplicando', 'rechazado')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY e.branch_id
ORDER BY en_revision DESC;

-- ===========================================================================
-- 2 · El revisor (S2)
-- ===========================================================================

-- La lista: lo de las sucursales que este revisor ve, lo más antiguo primero (FIFO), sin el cuerpo.
-- `solo_vivos` deja fuera lo decidido; `estado` (opcional) estrecha a uno.
-- name: ListarRevisionParaRevisor :many
SELECT a.aparato_id, a.clave, a.entrega_id, a.orden, a.estado, a.metodo, a.ruta, a.hecho_at,
       a.resumen_del_aparato, a.decidido_por, a.decidido_por_nombre, a.decidido_at, a.motivo, a.id_creado,
       a.intentos, a.updated_at,
       e.persona, e.persona_nombre, e.branch_id, e.entregada_at, COALESCE(left(p.nombre, 200), '')::text AS aparato_nombre
FROM revision_apuntes a
JOIN revision_entregas e ON e.id = a.entrega_id
JOIN aparatos p ON p.id = a.aparato_id
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid)
  AND (NOT sqlc.arg('solo_vivos')::boolean OR a.estado IN ('en_revision', 'aplicando', 'rechazado'))
  AND (sqlc.narg('estado')::revision_estado IS NULL OR a.estado = sqlc.narg('estado')::revision_estado)
ORDER BY e.entregada_at, a.orden, a.clave
LIMIT sqlc.arg('limite')::int;

-- La bandeja del revisor, UNA FILA POR ENTREGA con sus cuentas por estado (exactas: se cuenta TODO lo de la
-- entrega, no sólo lo vivo) y sólo las que aún tienen algo esperando. Con el alcance dentro; el tope lo
-- comprueba quien llama (pide uno más de lo que va a enseñar).
-- name: ListarEntregasParaRevisor :many
SELECT e.id, e.aparato_id, COALESCE(left(p.nombre, 200), '')::text AS aparato_nombre, e.persona, e.persona_nombre, e.branch_id,
       e.entregada_at, e.version_app,
       (count(*) FILTER (WHERE a.estado = 'en_revision'))::bigint AS en_revision,
       (count(*) FILTER (WHERE a.estado = 'aplicando'))::bigint   AS aplicando,
       (count(*) FILTER (WHERE a.estado = 'rechazado'))::bigint   AS rechazados,
       (count(*) FILTER (WHERE a.estado = 'aplicado'))::bigint    AS aplicados,
       (count(*) FILTER (WHERE a.estado = 'descartado'))::bigint  AS descartados
FROM revision_entregas e
JOIN revision_apuntes a ON a.entrega_id = e.id
JOIN aparatos p ON p.id = e.aparato_id
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY e.id, p.id
HAVING count(*) FILTER (WHERE a.estado IN ('en_revision', 'aplicando', 'rechazado')) > 0
ORDER BY e.entregada_at, e.id
LIMIT sqlc.arg('limite')::int;

-- SIN alcance, a propósito, y SIN cuerpo: sólo para decidir CÓMO se dice «no» cuando la consulta con
-- alcance no encontró nada (404 si no existe; 403 si existe en una sucursal que el revisor no ve). Nunca
-- decide un permiso: la decisión es la consulta con alcance, esta sólo pone la frase.
-- name: RevisionEntregaPorId :one
SELECT id, persona, branch_id FROM revision_entregas WHERE id = $1;

-- Un apunte entero (con el cuerpo, que es lo que el revisor tiene que ver antes de pulsar), CON EL
-- ALCANCE DENTRO: el administrador de CAM no lee ni aplica lo de HOL, ni por lista ni por id.
-- name: RevisionApunteDeRevisor :one
SELECT a.aparato_id, a.clave, a.entrega_id, a.orden, a.estado, a.metodo, a.ruta, a.cuerpo, a.provisional,
       a.hecho_at, a.huella, a.resumen_del_aparato, a.decidido_por, a.decidido_por_nombre, a.decidido_at,
       a.motivo, a.id_creado, a.descartados, a.intentos, a.created_at, a.updated_at,
       e.persona, e.persona_nombre, e.branch_id, e.entregada_at, e.token_jti, e.desde_ip, e.agente,
       e.version_app, COALESCE(left(p.nombre, 200), '')::text AS aparato_nombre
FROM revision_apuntes a
JOIN revision_entregas e ON e.id = a.entrega_id
JOIN aparatos p ON p.id = a.aparato_id
WHERE a.aparato_id = sqlc.arg('aparato_id') AND a.clave = sqlc.arg('clave')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid);

-- Una entrega entera, en orden, con el alcance dentro. Es lo que recorre «Aplicar todo en orden».
-- name: RevisionDeEntrega :many
SELECT a.aparato_id, a.clave, a.entrega_id, a.orden, a.estado, a.metodo, a.ruta, a.cuerpo, a.provisional,
       a.hecho_at, a.huella, a.resumen_del_aparato, a.decidido_por, a.decidido_por_nombre, a.decidido_at,
       a.motivo, a.id_creado, a.descartados, a.intentos,
       e.persona, e.persona_nombre, e.branch_id, e.entregada_at
FROM revision_apuntes a
JOIN revision_entregas e ON e.id = a.entrega_id
WHERE a.entrega_id = sqlc.arg('entrega_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY a.orden, a.clave;

-- EL CANDADO. Pasa a `aplicando` SÓLO lo que sigue esperando (`en_revision`, o `rechazado` para
-- reintentar), SÓLO si lo entregó otra persona (nadie revisa lo suyo) y SÓLO dentro del alcance del
-- revisor. Devuelve la fila o ninguna: dos revisores a la vez, un solo ganador.
-- name: ReclamarRevisionApunte :one
UPDATE revision_apuntes AS a
SET estado = 'aplicando',
    decidido_por = sqlc.arg('revisor')::text,
    decidido_por_nombre = sqlc.narg('revisor_nombre')::text,
    decidido_at = now()
FROM revision_entregas e
WHERE e.id = a.entrega_id
  AND a.aparato_id = sqlc.arg('aparato_id') AND a.clave = sqlc.arg('clave')
  AND a.estado IN ('en_revision', 'rechazado')
  AND e.persona <> sqlc.arg('revisor')::text
  AND (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid)
RETURNING a.aparato_id, a.clave, a.entrega_id, a.orden, a.estado, a.metodo, a.ruta, a.cuerpo, a.provisional,
          a.hecho_at, a.huella, a.decidido_por, a.decidido_por_nombre, a.decidido_at, a.intentos;

-- Un apunte que se quedó en `aplicando` porque el proceso murió: SÓLO pasa a manos de un revisor si lleva
-- más de `antiguedad_segundos` así, y quien llama ya confirmó a mano que la ruta no se aplicó (la API no
-- lee `X-Apunte`: no hay otra red). Mismas condiciones de alcance y de autor que `ReclamarRevisionApunte`.
-- name: ReclamarRevisionInterrumpida :one
UPDATE revision_apuntes AS a
SET decidido_por = sqlc.arg('revisor')::text,
    decidido_por_nombre = sqlc.narg('revisor_nombre')::text,
    decidido_at = now()
FROM revision_entregas e
WHERE e.id = a.entrega_id
  AND a.aparato_id = sqlc.arg('aparato_id') AND a.clave = sqlc.arg('clave')
  AND a.estado = 'aplicando'
  AND a.updated_at < now() - make_interval(secs => sqlc.arg('antiguedad_segundos')::int)
  AND e.persona <> sqlc.arg('revisor')::text
  AND (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid)
RETURNING a.aparato_id, a.clave, a.entrega_id, a.orden, a.estado, a.metodo, a.ruta, a.cuerpo, a.provisional,
          a.hecho_at, a.huella, a.decidido_por, a.decidido_por_nombre, a.decidido_at, a.intentos;

-- El reparto dijo que sí. SÓLO cierra quien lo reclamó (`decidido_por`), y SÓLO desde `aplicando`.
-- name: CerrarRevisionComoAplicado :one
UPDATE revision_apuntes
SET estado = 'aplicado', motivo = NULL, intentos = intentos + 1,
    id_creado = sqlc.narg('id_creado')::uuid, descartados = sqlc.narg('descartados')::jsonb
WHERE aparato_id = sqlc.arg('aparato_id') AND clave = sqlc.arg('clave')
  AND estado = 'aplicando' AND decidido_por = sqlc.arg('revisor')::text
RETURNING *;

-- El reparto dijo que no (un 4xx): se queda VIVO y a la vista, con el motivo LITERAL, esperando decisión.
-- No se reintenta solo.
-- name: CerrarRevisionComoRechazado :one
UPDATE revision_apuntes
SET estado = 'rechazado', motivo = sqlc.arg('motivo')::text, intentos = intentos + 1
WHERE aparato_id = sqlc.arg('aparato_id') AND clave = sqlc.arg('clave')
  AND estado = 'aplicando' AND decidido_por = sqlc.arg('revisor')::text
RETURNING *;

-- Una caída (5xx o red), no un rechazo: vuelve a `en_revision` con un intento más, sin dueño.
-- name: DevolverRevisionAEnRevision :one
UPDATE revision_apuntes
SET estado = 'en_revision', intentos = intentos + 1,
    decidido_por = NULL, decidido_por_nombre = NULL, decidido_at = NULL
WHERE aparato_id = sqlc.arg('aparato_id') AND clave = sqlc.arg('clave')
  AND estado = 'aplicando' AND decidido_por = sqlc.arg('revisor')::text
RETURNING *;

-- DESCARTAR: SÓLO lo que sigue esperando, SÓLO de otra persona, SÓLO dentro del alcance, y con un motivo
-- escrito (la base lo exige: ≥ 5 caracteres). No borra: marca `descartado` con quién y cuándo.
-- name: DescartarRevisionApunte :one
UPDATE revision_apuntes AS a
SET estado = 'descartado',
    decidido_por = sqlc.arg('revisor')::text,
    decidido_por_nombre = sqlc.narg('revisor_nombre')::text,
    decidido_at = now(),
    motivo = sqlc.arg('motivo')::text
FROM revision_entregas e
WHERE e.id = a.entrega_id
  AND a.aparato_id = sqlc.arg('aparato_id') AND a.clave = sqlc.arg('clave')
  AND a.estado IN ('en_revision', 'rechazado')
  AND e.persona <> sqlc.arg('revisor')::text
  AND (sqlc.narg('sucursal')::uuid IS NULL OR e.branch_id = sqlc.narg('sucursal')::uuid)
RETURNING a.aparato_id, a.clave, a.entrega_id, a.orden, a.estado, a.decidido_por, a.decidido_por_nombre,
          a.decidido_at, a.motivo;

-- ===========================================================================
-- 3 · El libro de decisiones (sólo se añade)
-- ===========================================================================

-- name: AnotarRevisionDecision :one
INSERT INTO revision_decisiones (aparato_id, clave, accion, por, por_nombre, rol, resultado, http_estado, motivo)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
RETURNING *;

-- name: RevisionDecisionesDeApunte :many
SELECT * FROM revision_decisiones
WHERE aparato_id = $1 AND clave = $2
ORDER BY cuando, id;

-- Al aplicar por revisión, el apunte se copia al libro `apuntes` (para que la reentrega normal dé `repetido`).
-- SIN fallar si la clave YA estaba (auditoría final, B6): `aplicar` mira el libro antes de reenviar y no
-- reenvía lo que ya está; esto es la red por si la subida normal de un sync viejo se coló entre mirar y
-- escribir —la transacción no se cae por una fila que ya cuenta lo mismo—. Devuelve cuántas filas escribió.
-- name: CopiarApunteAplicadoAlLibro :execrows
INSERT INTO apuntes (aparato_id, clave, metodo, ruta, estado, id_creado, hecho_at, descartados)
VALUES ($1, $2, $3, $4, 'aplicado', $5, $6, $7)
ON CONFLICT (aparato_id, clave) DO NOTHING;
