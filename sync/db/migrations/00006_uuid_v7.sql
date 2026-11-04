-- +goose Up
--
-- LOS IDS NUEVOS SON UUIDv7 — Jose, 04/11/2026 («desde el principio mandé v7»). Igual que la 00031 del reparto: PostgreSQL 17 no trae
-- `uuidv7()` (llega con la 18), así que se crea `uuid_generate_v7()` (48 bits de milisegundos + aleatorio, versión 7) y se pone de
-- defecto en las tablas que usaban `gen_random_uuid()`. Los ids que ya existen no se tocan.

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION uuid_generate_v7() RETURNS uuid AS $$
  SELECT encode(
    set_bit(
      set_bit(
        overlay(uuid_send(gen_random_uuid())
                placing substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3)
                FROM 1 FOR 6),
        52, 1),
      53, 1),
    'hex')::uuid;
$$ LANGUAGE sql VOLATILE;
-- +goose StatementEnd

ALTER TABLE aparatos ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE apuntes_rechazados ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE revision_decisiones ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE revision_entregas ALTER COLUMN id SET DEFAULT uuid_generate_v7();

-- +goose Down
ALTER TABLE aparatos ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE apuntes_rechazados ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE revision_decisiones ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE revision_entregas ALTER COLUMN id SET DEFAULT gen_random_uuid();
DROP FUNCTION IF EXISTS uuid_generate_v7();
