-- +goose Up
-- La asignacion del camion vive en routes.vehicle_id. orders.vehicle_id duplicaba
-- esa relacion y se quedaba desactualizada cuando el pedido cambiaba de ruta.
DROP INDEX IF EXISTS orders_vehiculo_idx;
ALTER TABLE orders DROP COLUMN IF EXISTS vehicle_id;

-- +goose Down
ALTER TABLE orders ADD COLUMN vehicle_id uuid REFERENCES vehicles(id);
UPDATE orders o
SET vehicle_id = r.vehicle_id
FROM routes r
WHERE o.route_id = r.id
  AND r.vehicle_id IS NOT NULL;
CREATE INDEX orders_vehiculo_idx ON orders (vehicle_id);
