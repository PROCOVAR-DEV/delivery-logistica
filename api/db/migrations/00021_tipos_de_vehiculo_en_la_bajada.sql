-- +goose Up
-- LOS TIPOS DE VEHÍCULO BAJAN AL APARATO (issue 14 de Amado, 16/10/2026).
--
-- La APK y el escritorio tienen que listar y CREAR tipos, camiones y distribuidores SIN
-- CONEXIÓN. Los camiones y los distribuidores ya bajaban; los tipos no: eran de «sólo con
-- conexión». Ahora el catálogo baja en la colección `vehicle_types` de `GET /api/sync/cambios`
-- y, como lo que se borra de verdad ya no tiene fila, necesita su lápida (00006), como los
-- distribuidores de la 00019.
--
-- `ADD VALUE` DENTRO de la transacción de goose, igual que en la 00019: en Postgres 12+ se
-- puede, y es seguro porque NADA en esta migración USA el valor nuevo —el disparador lo
-- recibe como TEXTO y lo convierte al dispararse, que es en otra transacción—.
--
-- EL `Down` NO LO PUEDE QUITAR (no hay `DROP VALUE` en Postgres): el valor se queda en el
-- tipo, inofensivo. `IF NOT EXISTS` hace que subir otra vez no falle.
ALTER TYPE coleccion_de_la_bajada ADD VALUE IF NOT EXISTS 'vehicle_types';

-- Sólo DELETE, por lo mismo que los distribuidores: un tipo no se muda de sucursal (la API no
-- lo permite) y su id sale siempre de `gen_random_uuid()`, así que no vuelve (no hace falta el
-- INSERT que quita la lápida ni el UPDATE `movido`).
--
-- `branch_id` PUEDE SER NULO aquí —el tipo «de todas», los de fábrica de la 00001— y el
-- disparador genérico lo sabe tratar: `(to_jsonb(OLD) ->> 'branch_id')::uuid` da NULL y la
-- lápida nace con `branch_id` nulo. Quién la recibe lo decide `quitadosDe` con
-- `sinSucursalTambien = false` (`espejo.go`): la lista de tipos (`ListarTiposDeVehiculo`) NO deja
-- pasar los «de todas» a quien tiene sucursal (filtra con `IS NOT DISTINCT FROM`), así que a
-- ese aparato la lápida de uno «de todas» sería una orden sobre algo que nunca fue suyo; y
-- quien ve «todas» recibe todas las lápidas sin condición y ahí sí le sirve. Un tipo «de todas»
-- sólo lo borran migraciones: la API no lo permite (404 desde modo «todas»).
CREATE TRIGGER trg_vehicle_types_baja
    AFTER DELETE ON vehicle_types
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('vehicle_types', 'id', 'branch_id');

-- +goose Down
-- Deja la base como estaba antes de la subida: fuera el disparador y las lápidas de la
-- colección. El valor `vehicle_types` SE QUEDA en `coleccion_de_la_bajada`: Postgres no sabe
-- quitar un valor de un enum. No estorba a nadie; la API anterior no lo lee y una subida
-- posterior lo reaprovecha.
DROP TRIGGER IF EXISTS trg_vehicle_types_baja ON vehicle_types;
DELETE FROM bajas_de_la_bajada WHERE coleccion::text = 'vehicle_types';
