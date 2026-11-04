-- +goose Up
--
-- TODOS LOS IDS NUEVOS SON UUIDv7, Y NINGUNA RUTA REPITE CÓDIGO — Jose, 04/11/2026.
--
-- 1) La base ponía los ids con `gen_random_uuid()` (v4, aleatorio) desde la 00001, aunque la casa decidió UUIDv7 desde el principio
--    (Accesos desde el 16/09; `X-Aparato-Id` también). PostgreSQL 17 no trae `uuidv7()` (llega con la 18), así que se crea
--    `uuid_generate_v7()`: 48 bits de milisegundos + el resto aleatorio, con la versión 7 puesta. Los ids que YA existen no se tocan
--    (están referenciados por todas partes y por los aparatos); desde aquí, los nuevos nacen v7. Los aparatos, además, ponen su id
--    ellos mismos (UUIDv7) y el servidor lo respeta.
--
-- 2) El 03/11/2026 había tres rutas planificadas de La Habana con `RT-20261103-004` (y una `-003`): el servidor numeraba CONTANDO
--    las rutas del día +1, y al borrar una ruta el siguiente código se repetía. Ahora el código son 6 caracteres sacados del UUIDv7
--    de la ruta (`internal/api/codigo_de_ruta.go`) y la base lo exige ÚNICO. Antes del índice se arreglan los repetidos que ya
--    existen: la más antigua de cada grupo CONSERVA su código y las demás pasan a uno nuevo corto derivado de su id. Los códigos
--    `RT-YYYYMMDD-NNN` que no se repiten se quedan como están (la gente los tiene dichos por teléfono). El `UPDATE` mueve `updated_at`
--    (trigger), así que los aparatos reciben el código nuevo en su próxima bajada.

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

ALTER TABLE avisos_a_pedido ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE bajas_de_la_bajada ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE board_columns ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE branches ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE customers ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE distribuidores ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE envios_del_webhook ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE order_items ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE order_vehicles ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE orders ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE orders_fuera_de_alcance ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE products ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE recepciones_del_webhook ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE routes ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE saved_origins ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE vehicle_types ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE vehicles ALTER COLUMN id SET DEFAULT uuid_generate_v7();
ALTER TABLE ventas_facturadas ALTER COLUMN id SET DEFAULT uuid_generate_v7();

UPDATE routes r
   SET route_code = upper(substr(md5(r.id::text), 1, 6))
  FROM (
        SELECT id,
               row_number() OVER (PARTITION BY route_code ORDER BY created_at, id) AS orden
          FROM routes
         WHERE route_code IS NOT NULL
       ) d
 WHERE d.id = r.id
   AND d.orden > 1;

CREATE UNIQUE INDEX routes_route_code_uniq ON routes (route_code) WHERE route_code IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS routes_route_code_uniq;
ALTER TABLE avisos_a_pedido ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE bajas_de_la_bajada ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE board_columns ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE branches ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE customers ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE distribuidores ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE envios_del_webhook ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE order_items ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE order_vehicles ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE orders ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE orders_fuera_de_alcance ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE products ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE recepciones_del_webhook ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE routes ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE saved_origins ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE vehicle_types ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE vehicles ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE ventas_facturadas ALTER COLUMN id SET DEFAULT gen_random_uuid();
DROP FUNCTION IF EXISTS uuid_generate_v7();
