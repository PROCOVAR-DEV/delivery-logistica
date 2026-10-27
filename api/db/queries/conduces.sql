-- Conduces (super factura): juntar varias facturas de un mismo cliente en UNA parada.
-- La especificación entera, `docs/conduces.md`; el contrato, `docs/contratos-api.md` «Conduces».
--
-- `orders.conduce_principal_id` (00029): NULL = factura suelta o PRINCIPAL; uuid = MIEMBRO, apunta a su principal.
-- Solo lo escribe una persona, y SOLO estas consultas (el upsert del espejo no lo nombra).
--
-- EL ALCANCE VA EN EL SQL (`sucursal`), como en todos los ficheros de esta carpeta. Y las reglas se comprueban
-- DOS veces: el manejador lee con `LeerFilasParaConduce` (con candado) para poder NOMBRAR la factura que lo
-- impide, y la escritura repite las guardas en su `WHERE` por si algo cambió entre las dos cosas; cero filas de
-- más o de menos deshacen la transacción.

-- Las filas que importan a un conduce, CON CANDADO (FOR UPDATE): las pedidas por id más, si se da `principal`,
-- la principal y todos sus miembros. Dentro de una transacción, nadie las mueve mientras se decide.
-- Con alcance: una fila de otra sucursal no devuelve nada, que es el mismo 404 que si no existiera.
-- name: LeerFilasParaConduce :many
SELECT
    o.id, o.branch_id, o.customer_name, o.operation_number, o.factura_numero,
    o.route_id, o.resultado, o.delivered_at, o.archivado, o.anulada_at,
    o.conduce_principal_id,
    r.route_code AS ruta_codigo,
    (SELECT coalesce(nullif(btrim(p.factura_numero), ''), p.operation_number)
       FROM orders p WHERE p.id = o.conduce_principal_id) AS principal_numero,
    EXISTS (SELECT 1 FROM orders m WHERE m.conduce_principal_id = o.id) AS tiene_miembros
FROM orders o
LEFT JOIN routes r ON r.id = o.route_id
WHERE (o.id = ANY(sqlc.arg('ids')::uuid[])
       OR (sqlc.narg('principal')::uuid IS NOT NULL AND o.conduce_principal_id = sqlc.narg('principal')::uuid))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.id
FOR UPDATE OF o;

-- CREAR (o AMPLIAR) UN CONDUCE: las `ids` pasan a ser miembros de la principal. Una sola sentencia con TODAS las
-- guardas en el WHERE: cada miembro suelto (ni miembro ni principal de otro), libre (sin ruta, sin resultado, sin
-- entrega, sin archivar) y de la MISMA sucursal que una principal que también está libre y no es miembro. Un
-- miembro que tuviera tarjeta en una zona del tablero la pierde: va dentro de su principal y ya no se coloca.
-- Devuelve los que se juntaron; si son menos que los pedidos, el manejador deshace todo (409).
-- name: CrearConduce :many
WITH miembros AS (
    UPDATE orders m SET conduce_principal_id = sqlc.arg('principal_id')::uuid
    WHERE m.id = ANY(sqlc.arg('ids')::uuid[])
      AND m.id <> sqlc.arg('principal_id')::uuid
      AND m.conduce_principal_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM orders x WHERE x.conduce_principal_id = m.id)
      AND m.route_id IS NULL AND m.resultado IS NULL AND m.delivered_at IS NULL AND NOT m.archivado
      AND EXISTS (SELECT 1 FROM orders p
                   WHERE p.id = sqlc.arg('principal_id')::uuid
                     AND p.conduce_principal_id IS NULL
                     AND p.route_id IS NULL AND p.resultado IS NULL AND p.delivered_at IS NULL AND NOT p.archivado
                     AND p.branch_id IS NOT DISTINCT FROM m.branch_id)
      AND (sqlc.narg('sucursal')::uuid IS NULL OR m.branch_id = sqlc.narg('sucursal')::uuid)
    RETURNING m.id
), sin_tarjeta AS (
    DELETE FROM board_placements p USING miembros m WHERE p.order_id = m.id
)
SELECT id FROM miembros;

-- DESHACER: todos los miembros vuelven a ser facturas sueltas. Solo si NINGUNA fila del conduce (la principal ni
-- los miembros) va en una ruta o tiene resultado: lo que ya salió del almacén es historia.
-- name: DeshacerConduce :many
UPDATE orders m SET conduce_principal_id = NULL
WHERE m.conduce_principal_id = sqlc.arg('principal_id')::uuid
  AND NOT EXISTS (SELECT 1 FROM orders x
                   WHERE (x.id = sqlc.arg('principal_id')::uuid OR x.conduce_principal_id = sqlc.arg('principal_id')::uuid)
                     AND (x.route_id IS NOT NULL OR x.resultado IS NOT NULL OR x.delivered_at IS NOT NULL))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR m.branch_id = sqlc.narg('sucursal')::uuid)
RETURNING m.id;

-- SACAR UN MIEMBRO: misma condición que deshacer (ninguna fila del conduce en ruta ni con resultado).
-- name: SacarMiembroDeConduce :execrows
UPDATE orders m SET conduce_principal_id = NULL
WHERE m.id = sqlc.arg('id')::uuid
  AND m.conduce_principal_id = sqlc.arg('principal_id')::uuid
  AND NOT EXISTS (SELECT 1 FROM orders x
                   WHERE (x.id = sqlc.arg('principal_id')::uuid OR x.conduce_principal_id = sqlc.arg('principal_id')::uuid)
                     AND (x.route_id IS NOT NULL OR x.resultado IS NOT NULL OR x.delivered_at IS NOT NULL))
  AND (sqlc.narg('sucursal')::uuid IS NULL OR m.branch_id = sqlc.narg('sucursal')::uuid);

-- LOS MIEMBROS DE VARIAS PRINCIPALES de una vez: lo que enseña `conduce` en `GET /api/orders` y lo que necesita el
-- cierre para avisar a PEDIDO por cada factura. En el orden en que se leen, que es el del número de factura
-- (primero los más cortos: «999» antes que «1000») y el id para desempatar. Sin archivadas: una factura archivada
-- sale de su conduce (00029, trigger) y no cuenta.
-- name: MiembrosDeConduces :many
SELECT m.conduce_principal_id AS principal_id, m.id, m.factura_numero, m.operation_number,
       m.weight, m.route_id, m.resultado, m.delivered_at,
       p.factura_numero AS principal_factura, p.operation_number AS principal_operacion
FROM orders m
JOIN orders p ON p.id = m.conduce_principal_id
WHERE m.conduce_principal_id = ANY(sqlc.arg('principal_ids')::uuid[])
  AND NOT m.archivado
  AND (sqlc.narg('sucursal')::uuid IS NULL OR m.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY m.conduce_principal_id, length(coalesce(m.factura_numero, m.operation_number, '')),
         coalesce(m.factura_numero, m.operation_number, ''), m.id;
