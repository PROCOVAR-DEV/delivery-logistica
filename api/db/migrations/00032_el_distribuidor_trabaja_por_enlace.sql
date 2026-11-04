-- +goose Up
--
-- EL DISTRIBUIDOR TRABAJA POR ENLACE, SIN CUENTA — Jose, 04/11/2026.
--
-- «Una apk que haga la ruta que le envían por el link, el cual trae la información, y ya se guarda: una vez asignada a un dispositivo no entra
-- en otro lado, y así puede mandarse sin estar logueado.» Nada de usuarios de Accesos para el distribuidor (por ahora):
--
--  * `enlaces_de_ruta`: el logístico genera UN enlace por ruta (`https://reparto.procovar.cloud/r/<token>`) y se lo manda al distribuidor. El
--    token es una capacidad: quien lo tiene puede reclamar la ruta, y SOLO UNA VEZ. El token va en claro (hay que poder volver a copiar el enlace
--    mientras nadie lo ha reclamado); quien lea esta tabla ya lo puede todo, no se añade riesgo guardándolo con hash.
--  * `dispositivos_distribuidor`: el teléfono. Lo crea el primer enlace que reclama y lo identifica el UUIDv7 que pone la app. Su `secreto_hash`
--    (sha256 de un secreto que solo conoce el aparato) deja reclamar más enlaces y renovar su acceso sin volver a mandar nada. `activo = false` lo
--    echa: sus llamadas dan 403 aunque el token siga sin caducar.
--  * `routes.dispositivo_id`: a qué teléfono quedó asignada la ruta al reclamarla. Es la dimensión del alcance del distribuidor: solo ve, baja y toca
--    las rutas cuyo `dispositivo_id` es el suyo. Reasignar = soltar el enlace (nuevo token) y que otro teléfono lo reclame.
--  * `vehicles.distribuidor_id`: quién lleva ese vehículo por defecto (al armar una ruta con él se propone su distribuidor).

CREATE TABLE dispositivos_distribuidor (
    id              uuid PRIMARY KEY,
    nombre          text,
    branch_id       uuid NOT NULL REFERENCES branches (id),
    distribuidor_id uuid REFERENCES distribuidores (id) ON DELETE SET NULL,
    secreto_hash    bytea NOT NULL,
    activo          boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    last_seen_at    timestamptz
);
CREATE INDEX dispositivos_distribuidor_branch_idx ON dispositivos_distribuidor (branch_id);

ALTER TABLE routes ADD COLUMN dispositivo_id uuid REFERENCES dispositivos_distribuidor (id) ON DELETE SET NULL;
CREATE INDEX routes_dispositivo_idx ON routes (dispositivo_id) WHERE dispositivo_id IS NOT NULL;

CREATE TABLE enlaces_de_ruta (
    id             uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    ruta_id        uuid NOT NULL REFERENCES routes (id) ON DELETE CASCADE,
    token          text NOT NULL UNIQUE,
    creado_por     text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    dispositivo_id uuid REFERENCES dispositivos_distribuidor (id) ON DELETE SET NULL,
    reclamado_at   timestamptz,
    revocado_at    timestamptz
);
-- UN enlace VIVO por ruta (los revocados quedan de constancia).
CREATE UNIQUE INDEX enlaces_de_ruta_uno_vivo ON enlaces_de_ruta (ruta_id) WHERE revocado_at IS NULL;

ALTER TABLE vehicles ADD COLUMN distribuidor_id uuid REFERENCES distribuidores (id) ON DELETE SET NULL;
CREATE INDEX vehicles_distribuidor_idx ON vehicles (distribuidor_id) WHERE distribuidor_id IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS vehicles_distribuidor_idx;
ALTER TABLE vehicles DROP COLUMN IF EXISTS distribuidor_id;
DROP TABLE IF EXISTS enlaces_de_ruta;
DROP INDEX IF EXISTS routes_dispositivo_idx;
ALTER TABLE routes DROP COLUMN IF EXISTS dispositivo_id;
DROP TABLE IF EXISTS dispositivos_distribuidor;
