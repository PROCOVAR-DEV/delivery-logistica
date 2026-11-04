-- +goose Up
--
-- EL DISTRIBUIDOR TIENE USUARIO Y VEHÍCULO — Jose, 04/11/2026.
--
-- Hasta hoy `distribuidores` era un NOMENCLADOR de nombres («Angel», «Wilson Columbie»): ninguna persona de Accesos detrás, ningún vehículo
-- propio. La app del distribuidor necesita saber QUIÉN es el que inició sesión para bajarle SOLO sus rutas y dejarle completar SUS paradas.
--
--  * `distribuidores.persona_id`: el `sub` del token de Accesos (texto: viene de un sistema ajeno). Único donde existe: una persona es UN
--    distribuidor. Nulo = todavía sin usuario (los 11 de hoy). Se rellena al crearle el usuario desde Reparto.
--  * `vehicles.distribuidor_id`: quién lleva ese vehículo por defecto. Al armar una ruta con ese vehículo se propone su distribuidor
--    (de las 17 rutas de los últimos 30 días, 7 se armaron sin distribuidor). `ON DELETE SET NULL`: borrar un distribuidor no borra camiones.

ALTER TABLE distribuidores ADD COLUMN persona_id text;
CREATE UNIQUE INDEX distribuidores_persona_uniq ON distribuidores (persona_id) WHERE persona_id IS NOT NULL;

ALTER TABLE vehicles ADD COLUMN distribuidor_id uuid REFERENCES distribuidores (id) ON DELETE SET NULL;
CREATE INDEX vehicles_distribuidor_idx ON vehicles (distribuidor_id) WHERE distribuidor_id IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS vehicles_distribuidor_idx;
ALTER TABLE vehicles DROP COLUMN IF EXISTS distribuidor_id;
DROP INDEX IF EXISTS distribuidores_persona_uniq;
ALTER TABLE distribuidores DROP COLUMN IF EXISTS persona_id;
