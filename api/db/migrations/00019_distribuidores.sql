-- +goose Up
-- El DISTRIBUIDOR es un nomenclador POR SUCURSAL (Amado, issue 7, 14/10/2026).
--
-- Es la persona responsable de la entrega: si se reparte en triciclo es el mismo chofer; si es
-- un vehículo rentado, un empleado de Procovar que responde de las entregas y de devolver las
-- facturas entregadas. La asociación se hace AL CREAR LA RUTA (`routes.distribuidor_id`).
--
-- NO es un usuario de Accesos ni un camión: es un nombre que la sucursal mantiene en su lista.
-- Reparto no guarda personas (CLAUDE.md §4) y por eso no hay aquí ni correo ni documento: sólo
-- el nombre y si sigue en activo.
--
-- `branch_id` es NOT NULL: aquí no hay «distribuidores de todas» como en los tipos de vehículo.
-- Quien trabaja en una sucursal ve y toca sólo los suyos (la API acota por sucursal).
--
-- SIN `ON DELETE CASCADE`, ni en la sucursal ni en la ruta, a propósito: borrar una sucursal no
-- se puede llevar por delante a sus distribuidores, y borrar un distribuidor que una ruta usa
-- no puede dejar la ruta sin quien respondió de ella. Con la clave ajena a secas ambos fallan
-- en voz alta; la API lo ataja antes (retira en vez de borrar si lo usa alguna ruta).
CREATE TABLE distribuidores (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id  uuid NOT NULL REFERENCES branches(id),
    nombre     text NOT NULL CHECK (btrim(nombre) <> ''),
    -- Para poder RETIRAR a uno que ya firmó rutas sin romper su historial.
    activo     boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_distribuidores_updated BEFORE UPDATE ON distribuidores
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- El nombre es único DENTRO de la sucursal y sin distinguir mayúsculas ni espacios de los
-- bordes («Juan Pérez» y « juan pérez » son la misma persona), como las zonas del tablero
-- (`board_columns_nombre_idx`). Entre sucursales se puede repetir.
CREATE UNIQUE INDEX distribuidores_nombre_por_sucursal
    ON distribuidores (branch_id, lower(btrim(nombre)));

-- NULO = ruta histórica, anterior a esta migración (o armada sin distribuidor): NO se inventa
-- uno. Un hueco se ve y se rellena; un nombre puesto por la migración sería un dato falso.
ALTER TABLE routes
    ADD COLUMN distribuidor_id uuid REFERENCES distribuidores(id);
-- Para «¿lo usa alguna ruta?» (borrar o retirar) sin recorrer todas las rutas.
CREATE INDEX routes_distribuidor_idx ON routes (distribuidor_id) WHERE distribuidor_id IS NOT NULL;

-- LA BAJADA DEL APARATO. La APK y el escritorio eligen el distribuidor SIN CONEXIÓN al crear la
-- ruta, así que el nomenclador baja con el día (`distribuidores` en `GET /api/sync/cambios`) y,
-- como lo que se borra de verdad ya no tiene fila, necesita su lápida (00006).
--
-- `ADD VALUE` DENTRO de la transacción de goose: en Postgres 12+ se puede, y aquí es seguro
-- porque NADA en esta migración USA el valor nuevo —el disparador lo recibe como TEXTO y lo
-- convierte al dispararse, que es en otra transacción—. A diferencia de la 00013, que lo usaba
-- a continuación y por eso iba fuera de transacción.
--
-- EL `Down` NO LO PUEDE QUITAR (no hay `DROP VALUE` en Postgres): el valor se queda en el tipo,
-- inofensivo. `IF NOT EXISTS` hace que subir otra vez no falle.
ALTER TYPE coleccion_de_la_bajada ADD VALUE IF NOT EXISTS 'distribuidores';

-- Sólo DELETE: un distribuidor no se muda de sucursal (la API no lo permite), así que no hay
-- lápida `movido`; y el id sale siempre de `gen_random_uuid()`, así que no vuelve (no hace falta
-- el INSERT que quita la lápida).
CREATE TRIGGER trg_distribuidores_baja
    AFTER DELETE ON distribuidores
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('distribuidores', 'id', 'branch_id');

-- +goose Down
-- Deja la base como estaba antes de la subida. Pierde, y no hay otra salida, QUIÉN repartió cada
-- ruta (`routes.distribuidor_id`) y la lista de distribuidores de cada sucursal: no caben en el
-- esquema anterior. Las lápidas de la colección se borran con ellos.
--
-- El valor `distribuidores` SE QUEDA en `coleccion_de_la_bajada`: Postgres no sabe quitar un valor
-- de un enum. No estorba a nadie; la API anterior no lo lee y una subida posterior lo reaprovecha.
DROP TRIGGER IF EXISTS trg_distribuidores_baja ON distribuidores;
DELETE FROM bajas_de_la_bajada WHERE coleccion::text = 'distribuidores';
DROP INDEX IF EXISTS routes_distribuidor_idx;
ALTER TABLE routes DROP COLUMN distribuidor_id;
DROP TABLE distribuidores;
