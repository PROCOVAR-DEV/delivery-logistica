-- LA FACTURA ANULADA QUE IBA EN UNA RUTA (Jose y Amado, 23/10/2026: «la cancelada que ya va en una
-- ruta, si ya no aparece, quitarla e INFORMAR que esa factura ya fue cancelada»).
--
-- # El caso
--
-- La entrega es UNA factura de Ventra (22/10/2026). Cuando Ventra deja de mandar una factura que
-- está dentro de la ventana consultada, el espejo (`retirarLoQueYaNoViene`) la retira: sin ruta, la
-- borra; con ruta, hasta hoy la dejaba y la contaba en el registro, donde no la lee nadie, y el
-- camión salía a entregar una factura que ya no existe.
--
-- Ahora, si va en una ruta SIN COMPLETAR (`planned` o `in_progress`) y sin resultado ni entrega, el
-- espejo la QUITA de la ruta (igual que `DELETE /api/routes/{id}/stops/{orderId}`: `route_id` y
-- `ultima_ruta_id` a NULL, y el trigger de totales refresca la ruta) y la MARCA como anulada en vez
-- de borrarla, para poder informar de ella. Las de rutas completadas o con resultado no se tocan
-- (historial).
--
--   anulada_at          cuándo la quitó el espejo. NULL = no está anulada (TODO lo que ya hay).
--   anulada_de_ruta_id  la ruta de la que salió. Sin clave ajena A PROPÓSITO: la ruta puede borrarse
--                       después y el aviso ya dado no tiene que desaparecer ni bloquear el borrado.
--
-- # LA FILA ANULADA ESTÁ ARCHIVADA, y esa es la garantía de que no la cuenta nadie
--
-- `archivado = true` ya excluye a la fila de las listas, los contadores, el armado y el tablero (y
-- la bajada de los aparatos la manda en `quitados`). El CHECK ata las dos cosas: una anulada que no
-- estuviera archivada contaría en todo. El upsert del espejo, si la factura REAPARECE, pone
-- `archivado = false` y `anulada_at = NULL` en el mismo UPDATE (la misma fila, sin duplicarse).
--
-- # Cuánto cuesta aplicarla
--
-- Dos columnas anulables (sin reescribir la tabla) y un CHECK que Postgres comprueba una vez sobre
-- las filas que hay (todas con `anulada_at` NULL: pasa sin mirar nada más). Pide un bloqueo breve
-- sobre `orders`; no hay datos que rellenar y no se mueve ningún `updated_at`.

-- +goose Up

ALTER TABLE orders ADD COLUMN IF NOT EXISTS anulada_at timestamptz;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS anulada_de_ruta_id uuid;

ALTER TABLE orders ADD CONSTRAINT orders_anulada_archivada_chk
    CHECK (anulada_at IS NULL OR archivado);

-- Para la bajada, que pregunta «las anuladas de los últimos 7 días»: son un puñado.
CREATE INDEX IF NOT EXISTS orders_anuladas_idx ON orders (anulada_at) WHERE anulada_at IS NOT NULL;

COMMENT ON COLUMN orders.anulada_at IS
    'cuándo el espejo quitó de su ruta una factura que Ventra dejó de mandar (00027). NULL = no anulada. Implica archivado = true';
COMMENT ON COLUMN orders.anulada_de_ruta_id IS
    'la ruta de la que salió la factura anulada (00027). Sin clave ajena a propósito: la ruta puede borrarse después';

-- +goose Down
-- QUÉ SE PIERDE: el aviso de «esta factura se canceló y se quitó de la ruta». Las filas anuladas
-- siguen archivadas (no vuelven a ninguna lista) y la API de esta versión deja de arrancar sin las
-- columnas (las lee en la bajada).
DROP INDEX IF EXISTS orders_anuladas_idx;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_anulada_archivada_chk;
ALTER TABLE orders DROP COLUMN IF EXISTS anulada_de_ruta_id;
ALTER TABLE orders DROP COLUMN IF EXISTS anulada_at;
