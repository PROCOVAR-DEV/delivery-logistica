-- NO VOLVER A CORRER TRAS LA 00018 (tipos de vehículo por sucursal, 14/10/2026).
--
-- Este traspaso se hizo el día del cambio y no se repite. Si se corriera ahora sobre el esquema
-- actual, asignaría tipos «de todas» (`vehicle_types.branch_id` nulo) a camiones con sucursal,
-- que es justo lo que la 00018 dejó de permitir: el tipo de un camión es de la sucursal del
-- camión. Aquí no se cambia ni una línea de código; sólo este aviso.
--
-- El traspaso de delivery (Prisma) al esquema nuevo.
--
-- Se corre UNA vez, el día del cambio, con los dos esquemas delante. No es una migración
-- de goose: goose crea el esquema vacío, y esto trae los datos que ya hay.
--
-- # Los identificadores
--
-- Delivery usa `cuid` (texto) y aquí son `uuid`. El puente es `md5(viejo)::uuid`: es
-- determinista, así que la misma fila da siempre el mismo uuid y el traspaso se puede
-- repetir sin duplicar. No hay tabla de equivalencias que mantener ni orden que respetar
-- entre tablas — cada clave ajena se calcula sola.
--
-- # Lo que NO se trae
--
-- `User` no existe en el esquema nuevo: era un resto de cuando delivery tuvo login propio
-- y quien manda en personas es auth. Donde hacía falta constancia va `creado_por`, con el
-- id de la persona en auth. Del viejo `userId` no sale ese id, así que se deja vacío: un
-- dato inventado es peor que uno ausente.
--
-- `Settings.currencies` y los renglones de `Order.items` eran JSON y ahora son tablas.
-- Se desgranan más abajo.

SET search_path = nuevo, public;

-- --------------------------------------------------------------------------
-- Sucursales. Primero, que de ellas cuelga todo.
-- --------------------------------------------------------------------------
INSERT INTO nuevo.branches (id, name, address, lat, lng, area_km2, external_id, origin_configured, created_at)
SELECT md5(b.id)::uuid, b.name, b.address, b.lat, b.lng, b."areaKm2", b."externalId",
       b."originConfigured", b."createdAt"
FROM public."Branch" b
ON CONFLICT (id) DO NOTHING;

-- --------------------------------------------------------------------------
-- Tipos de vehículo.
--
-- El catálogo nace sembrado con los cuatro de la pantalla más `Camion`, que es un tipo
-- real de producción escrito a mano. Aquí se añade cualquier otro que aparezca en los
-- datos: si mañana hay uno que no previmos, el traspaso no se cae por eso.
-- --------------------------------------------------------------------------
INSERT INTO nuevo.vehicle_types (nombre)
SELECT DISTINCT v.type FROM public."Vehicle" v
WHERE v.type IS NOT NULL AND v.type <> ''
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO nuevo.vehicles (id, name, vehicle_type_id, plate, capacity, costo_km_usd,
                            usar_para_domicilio, status, notes, branch_id, created_at, updated_at)
SELECT md5(v.id)::uuid, v.name,
       (SELECT t.id FROM nuevo.vehicle_types t WHERE t.nombre = v.type),
       v.plate, v.capacity, v."costoKmUsd", v."usarParaDomicilio",
       -- `status` viejo era texto libre; sólo existen estos dos y cualquier otra cosa se
       -- trata como disponible, que es el valor por defecto y el que no estorba.
       CASE WHEN v.status = 'in_use' THEN 'in_use' ELSE 'available' END::nuevo.vehicle_status,
       v.notes,
       CASE WHEN v."branchId" IS NULL THEN NULL ELSE md5(v."branchId")::uuid END,
       v."createdAt", v."updatedAt"
FROM public."Vehicle" v
ON CONFLICT (id) DO NOTHING;

-- --------------------------------------------------------------------------
-- Catálogo y clientes.
-- --------------------------------------------------------------------------
INSERT INTO nuevo.products (id, name, weight, packaging, units_per_package, category, sku,
                            sucursal_codigo, price, stock, unit, traido_at, created_at, updated_at)
SELECT md5(p.id)::uuid, p.name, p.weight, p.packaging, p."unitsPerPackage", p.category,
       p.sku, p."sucursalCodigo", p.price, p.stock, p.unit, p."traidoAt", p."createdAt", p."updatedAt"
FROM public."Product" p
ON CONFLICT (id) DO NOTHING;

INSERT INTO nuevo.customers (id, source, external_id, name, phone, address, municipio, zona,
                             codigo, vendedor, lat, lng, sucursal_codigo, synced_at, created_at, updated_at)
SELECT md5(c.id)::uuid,
       CASE WHEN c.source = 'pedido' THEN 'pedido' END::nuevo.procedencia,
       c."externalId", c.name, c.phone, c.address, c.municipio, c.zona, c.codigo,
       c.vendedor, c.lat, c.lng, c."sucursalCodigo", c."syncedAt", c."createdAt", c."updatedAt"
FROM public."Customer" c
ON CONFLICT (id) DO NOTHING;
