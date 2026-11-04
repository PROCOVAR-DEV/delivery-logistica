-- +goose Up
--
-- EL COBRO EN LA ENTREGA Y EL GPS DEL DISTRIBUIDOR — Jose, 04/11/2026.
--
-- 1) `orders.cobro_entrega`: lo que el DISTRIBUIDOR dice al marcar la parada —«cobrado» o «no cobrado»—. Reparto no sabe de importes de factura (viven
--    en Ventra), así que es solo el aviso de si cobró; NO sustituye a «cobrado = facturado en Ventra». Nulo = nadie lo ha dicho. Con su hora.
--
-- 2) `puntos_gps`: el recorrido del distribuidor, punto a punto, SOLO mientras tiene una ruta en curso. El aparato lo guarda en local y lo sube
--    por lotes cuando hay red, así que el `id` (UUIDv7 que pone el aparato) es la idempotencia: subir dos veces el mismo punto no lo duplica.
--    Un distribuidor puede tener VARIAS rutas en curso a la vez: el punto es único y lleva la lista de rutas activas en ese instante.
--    `hora` es la del APARATO (cuándo estuvo allí); `recibido_at`, la del servidor. Lo ve la oficina; el distribuidor, nunca. No se borra nada.

ALTER TABLE orders
    ADD COLUMN cobro_entrega    text CHECK (cobro_entrega IN ('cobrado', 'no_cobrado')),
    ADD COLUMN cobro_entrega_at timestamptz;

CREATE TABLE puntos_gps (
    id              uuid PRIMARY KEY,
    distribuidor_id uuid NOT NULL REFERENCES distribuidores (id),
    persona_id      text NOT NULL,
    branch_id       uuid NOT NULL REFERENCES branches (id),
    ruta_ids        uuid[] NOT NULL DEFAULT '{}',
    lat             double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lng             double precision NOT NULL CHECK (lng BETWEEN -180 AND 180),
    precision_m     real,
    velocidad_ms    real,
    rumbo           real,
    hora            timestamptz NOT NULL,
    recibido_at     timestamptz NOT NULL DEFAULT now(),
    evento          text CHECK (evento IN ('inicio', 'parada', 'fin')),
    pedido_id       uuid
);
CREATE INDEX puntos_gps_ruta_idx ON puntos_gps USING gin (ruta_ids);
CREATE INDEX puntos_gps_distribuidor_hora_idx ON puntos_gps (distribuidor_id, hora);
CREATE INDEX puntos_gps_branch_hora_idx ON puntos_gps (branch_id, hora DESC);

-- +goose Down
DROP TABLE IF EXISTS puntos_gps;
ALTER TABLE orders DROP COLUMN IF EXISTS cobro_entrega_at, DROP COLUMN IF EXISTS cobro_entrega;
