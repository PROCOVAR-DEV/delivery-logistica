-- +goose Up
--
-- QUÉ VERSIÓN TIENE CADA TELÉFONO (Jose, 06/11/2026: la app del distribuidor lleva su propia versión «para poder darle mejor soporte y mejor control»).
-- La app manda `X-App-Version: <versión>+<compilación>` y el servidor la apunta en cada llamada del teléfono; la oficina la ve en la pestaña «Teléfonos».
ALTER TABLE dispositivos_distribuidor ADD COLUMN app_version text;
ALTER TABLE dispositivos_distribuidor ADD COLUMN app_compilacion integer;

-- +goose Down
ALTER TABLE dispositivos_distribuidor DROP COLUMN IF EXISTS app_compilacion;
ALTER TABLE dispositivos_distribuidor DROP COLUMN IF EXISTS app_version;
