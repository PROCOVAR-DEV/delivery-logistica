-- +goose Up
-- El `X-Aparato-Id` de Accesos (el id de la INSTALACIÓN que se ve en «Dispositivos»), para poder ir de un aparato de Accesos a su
-- actividad aquí (`/sincronizacion?aparato=<id>`). Texto y sin clave ajena: lo manda el aparato y es el mismo UUID v7 que guarda Accesos.
-- Nulo = aparato anterior a esto que aún no ha vuelto a hablar con el sincronizador desde la versión nueva.
ALTER TABLE aparatos ADD COLUMN IF NOT EXISTS instalacion_id text;
CREATE INDEX IF NOT EXISTS aparatos_instalacion_idx ON aparatos (instalacion_id) WHERE instalacion_id IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS aparatos_instalacion_idx;
ALTER TABLE aparatos DROP COLUMN IF EXISTS instalacion_id;
