-- +goose Up
--
-- LA SEGUNDA LLAVE: LA LOGÍSTICA REVISA LO QUE DICE EL DISTRIBUIDOR — Jose, 04/11/2026: «cuando no entreguen, marcar como no entregada; así el
-- logístico chequea de todas formas, dos veces, en vez de tener una sola palabra». Una ruta completada por su distribuidor queda «pendiente de
-- revisión» hasta que alguien de la oficina la confirma (o corrige las paradas con el mismo cierre de siempre y la confirma).

ALTER TABLE routes ADD COLUMN revisada_at timestamptz, ADD COLUMN revisada_por text;
CREATE INDEX routes_por_revisar_idx ON routes (branch_id, finished_at DESC) WHERE status = 'completed' AND revisada_at IS NULL AND dispositivo_id IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS routes_por_revisar_idx;
ALTER TABLE routes DROP COLUMN IF EXISTS revisada_por, DROP COLUMN IF EXISTS revisada_at;
