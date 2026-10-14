-- +goose Up
-- Los tipos de vehículo son POR SUCURSAL (Jose, 14/10/2026).
--
-- Hasta hoy `vehicle_types` era un catálogo de toda la empresa, y el costo por km de un tipo
-- es el que cotiza el domicilio: que el logístico de Santiago editara «truck» movía el precio
-- en las ocho. Ahora cada sucursal tiene SUS tipos y edita sólo los suyos.
--
-- `branch_id` NULO = el tipo «de todas»: los cinco de fábrica de la 00001, que se quedan por
-- los camiones COMPARTIDOS (`vehicles.branch_id` nulo) y que ninguna sucursal puede tocar.
--
-- LA REGLA QUE QUEDA, y la hace cumplir la API (`BuscarTipoDeVehiculoPorNombre`), no la base:
-- el tipo de un camión tiene la MISMA sucursal que el camión (`vehicles.branch_id IS NOT
-- DISTINCT FROM vehicle_types.branch_id`). Esta migración deja la base cumpliéndola; la
-- consulta de comprobación está en `docs/despliegue.md`.
--
-- SIN `ON DELETE CASCADE` a propósito: borrar una sucursal no se puede llevar sus tipos por
-- delante (un camión los referencia). Con la clave ajena a secas, borrar una sucursal con
-- tipos falla en voz alta, igual que ya falla con su punto de partida (`saved_origins`).
ALTER TABLE vehicle_types
    ADD COLUMN branch_id uuid REFERENCES branches(id);

-- El nombre deja de ser único en TODA la tabla y pasa a serlo por sucursal: Santiago y Holguín
-- pueden tener cada una su «rastra». Dos índices porque en un único `(branch_id, nombre)` los
-- nulos no chocan entre sí y se podrían repetir los de todas.
ALTER TABLE vehicle_types DROP CONSTRAINT vehicle_types_nombre_key;
CREATE UNIQUE INDEX vehicle_types_nombre_de_todas ON vehicle_types (nombre) WHERE branch_id IS NULL;
CREATE UNIQUE INDEX vehicle_types_nombre_por_sucursal ON vehicle_types (branch_id, nombre) WHERE branch_id IS NOT NULL;

-- A cada sucursal, una COPIA de los tipos que hay (mismo nombre, costo y estado, retirados
-- incluidos). Sólo se copian los «de todas»: la columna acaba de nacer, así que todos lo son, y
-- si esto se repitiera el índice de arriba rechazaría el duplicado en vez de crearlo.
INSERT INTO vehicle_types (nombre, costo_km_usd, activo, branch_id)
SELECT t.nombre, t.costo_km_usd, t.activo, b.id
FROM vehicle_types t
CROSS JOIN branches b
WHERE t.branch_id IS NULL;

-- ...y cada camión con sucursal pasa a apuntar al de SU sucursal. Los compartidos no se tocan.
UPDATE vehicles v
SET vehicle_type_id = c.id
FROM vehicle_types viejo, vehicle_types c
WHERE v.vehicle_type_id = viejo.id
  AND viejo.branch_id IS NULL
  AND v.branch_id IS NOT NULL
  AND c.branch_id = v.branch_id
  AND c.nombre = viejo.nombre;

-- +goose Down
-- Deja la base como estaba ANTES de la subida, salvo lo que las sucursales hayan hecho después,
-- que no cabe en un catálogo único y se resuelve así:
--
--   - los camiones vuelven al tipo «de todas» del MISMO NOMBRE;
--   - un nombre que sólo exista en sucursales (creado o renombrado después) y lo use algún
--     camión se crea «de todas» para que el camión tenga a dónde volver; su costo se conserva
--     sólo si todas las sucursales coinciden, y si no queda VACÍO (un hueco que se ve, no un
--     número inventado);
--   - los costos que una sucursal haya cambiado en SU copia se pierden: vuelve el del tipo de todas;
--   - los tipos de sucursal sin camiones se borran con lo que contengan.
INSERT INTO vehicle_types (nombre, costo_km_usd, activo)
SELECT s.nombre,
       CASE WHEN count(DISTINCT s.costo_km_usd) = 1 AND bool_and(s.costo_km_usd IS NOT NULL)
            THEN min(s.costo_km_usd) END,
       bool_or(s.activo)
FROM vehicle_types s
WHERE s.branch_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM vehicles v WHERE v.vehicle_type_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM vehicle_types g WHERE g.branch_id IS NULL AND g.nombre = s.nombre)
GROUP BY s.nombre;

UPDATE vehicles v
SET vehicle_type_id = g.id
FROM vehicle_types suyo, vehicle_types g
WHERE v.vehicle_type_id = suyo.id
  AND suyo.branch_id IS NOT NULL
  AND g.branch_id IS NULL
  AND g.nombre = suyo.nombre;
DELETE FROM vehicle_types WHERE branch_id IS NOT NULL;
DROP INDEX vehicle_types_nombre_por_sucursal;
DROP INDEX vehicle_types_nombre_de_todas;
ALTER TABLE vehicle_types ADD CONSTRAINT vehicle_types_nombre_key UNIQUE (nombre);
ALTER TABLE vehicle_types DROP COLUMN branch_id;
