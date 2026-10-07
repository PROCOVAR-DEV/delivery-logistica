-- +goose Up
-- Las rutas nacidas del tablero conservan de qué columna vino cada parada y su orden.
-- Al borrar una ruta planificada, `SoltarPedidosDeRuta` puede restaurarlas en el tablero.
CREATE TABLE board_route_origins (
    route_id uuid NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    column_id uuid NOT NULL REFERENCES board_columns(id) ON DELETE RESTRICT,
    posicion integer NOT NULL,
    colocado_por text,
    PRIMARY KEY (route_id, order_id),
    UNIQUE (order_id)
);
CREATE INDEX board_route_origins_column_idx
    ON board_route_origins (column_id, posicion);

-- +goose Down
DROP TABLE IF EXISTS board_route_origins;
