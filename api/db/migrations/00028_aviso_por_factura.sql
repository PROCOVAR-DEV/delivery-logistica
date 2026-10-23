-- EL AVISO A PEDIDO LLEGA POR FACTURA, no sólo por pedido (23/10/2026).
--
-- Desde el 22/10/2026 las entregas nacen de FACTURAS de Ventra y su `external_id`
-- (`factura:<SUC>:<punto>:<número>:<fecha>`) es un id que PEDIDO no conoce. Lo que PEDIDO
-- entiende es el FOLIO del pedido más la factura: un pedido puede tener varias y el estado de
-- cada una se cuenta por separado. El buzón guarda el aviso TAL CUAL se va a mandar, para que
-- el reintento de mañana lleve exactamente lo mismo que el de hoy.
--
-- `folio` ya existía (00010). Se añaden las tres que faltan, todas NULL en los avisos viejos
-- (por pedido), que siguen mandándose con `pedido_id` como siempre. En un aviso de factura,
-- `pedido_id` guarda el `external_id` de la entrega: sigue siendo NOT NULL y sigue siendo la
-- clave con la que se lee esta tabla, pero NO es lo que se manda.

-- +goose Up
ALTER TABLE avisos_a_pedido
    ADD COLUMN sucursal        text,
    ADD COLUMN factura         text,
    ADD COLUMN punto_de_venta  text;

-- +goose Down
ALTER TABLE avisos_a_pedido
    DROP COLUMN IF EXISTS punto_de_venta,
    DROP COLUMN IF EXISTS factura,
    DROP COLUMN IF EXISTS sucursal;
