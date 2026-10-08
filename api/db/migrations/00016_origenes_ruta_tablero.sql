-- +goose Up
-- Las rutas nacidas del tablero conservan de qué columna vino cada parada y su orden.
-- Al borrar una ruta planificada, `SoltarPedidosDeRuta` puede restaurarlas en el tablero.
--
-- `column_id` es `ON DELETE CASCADE` y NO `RESTRICT` — 07/10/2026, y es lo que hace que
-- esta tabla no estorbe a nadie. Con `RESTRICT`, borrar una zona que ya estaba vacía pero
-- tenía una ruta planificada nacida de ella contestaba el 409 «tiene 0 pedidos puestos»:
-- falso, porque en la zona no hay nada puesto, hay sólo el RECUERDO de dónde estuvo una
-- parada que hoy va en un camión. Y la persona no tenía manera de arreglarlo desde
-- ninguna pantalla: la zona estaba vacía.
--
-- Lo que se pierde al borrar la zona es justo ese recuerdo. Borrar la ruta después ya no
-- restaura nada en una zona que no existe: el pedido queda suelto y vuelve a «sin
-- colocar», que es donde tiene que estar. `route_id` y `order_id` ya eran CASCADE por la
-- misma razón: este registro es auxiliar y no puede retener la fila de la que cuelga.
--
-- Las colocaciones (`board_placements.column_id`) siguen en `RESTRICT`: ésas SÍ son trabajo
-- de una persona y borrar una zona con pedidos puestos no puede ser silencioso.
CREATE TABLE board_route_origins (
    route_id uuid NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    column_id uuid NOT NULL REFERENCES board_columns(id) ON DELETE CASCADE,
    posicion integer NOT NULL,
    colocado_por text,
    PRIMARY KEY (route_id, order_id),
    UNIQUE (order_id)
);
CREATE INDEX board_route_origins_column_idx
    ON board_route_origins (column_id, posicion);

-- +goose Down
DROP TABLE IF EXISTS board_route_origins;
