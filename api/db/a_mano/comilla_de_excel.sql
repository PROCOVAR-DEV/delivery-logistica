-- LA COMILLA DE EXCEL EN LO QUE YA ESTÁ GUARDADO — 28/09/2026.
--
-- El arreglo del código (`espejo.SinLaComillaDeExcel`, aplicado en el embudo del espejo y
-- en la puerta `/api/quote/batch`) sólo limpia lo que ENTRA de ahora en adelante. Lo que ya
-- está en la base se queda con la comilla, y el espejo NO lo va a repasar solo: pide
-- `since = max(pedido_updated_at)`, así que un pedido que no se ha tocado en PEDIDO no
-- vuelve a bajar nunca.
--
-- ESTO NO SE EJECUTA SOLO Y NO ES UNA MIGRACIÓN. Vive aquí, fuera de `db/migrations`, a
-- propósito: lo lanza Jose contra `procovar_reparto` cuando quiera, mirando antes lo que va
-- a tocar. Una migración que reescribe datos de producción sin que nadie mire el «antes» es
-- la forma de romper 8.000 filas en silencio.
--
-- Uso:
--   1. la PRIMERA consulta mide (no toca nada) y dice en qué columnas está y cuántas filas;
--   2. las de abajo arreglan, columna por columna, y cada una lleva su `RETURNING` para ver
--      qué cambió.
--
-- LA REGLA ES LA MISMA QUE LA DEL CÓDIGO, y por eso el `WHERE` es largo: la comilla se quita
-- SÓLO cuando lo que queda detrás no puede ser un nombre —dígitos y la puntuación de un
-- teléfono, un folio o una fecha, con al menos un dígito—. Un `'t Hooft` no se toca.
--
-- Y LAS IDENTIDADES NO SE TOCAN: `orders.external_id` y `customers.external_id` se quedan
-- como están. Si llegaron sucias, llegaron sucias siempre y casan consigo mismas; limpiarlas
-- ahora partiría cada fila en dos —la vieja con comilla, la nueva sin ella— y duplicaría el
-- padrón en la siguiente bajada.


-- ---------------------------------------------------------------------------
-- 1. MEDIR. En qué columnas aparece y en cuántas filas. No escribe nada.
-- ---------------------------------------------------------------------------
WITH candidatas(tabla, columna, valor) AS (
    SELECT 'orders', 'customer_phone',   customer_phone   FROM orders
    UNION ALL SELECT 'orders', 'operation_number', operation_number FROM orders
    UNION ALL SELECT 'orders', 'customer_name',    customer_name    FROM orders
    UNION ALL SELECT 'orders', 'address',          address          FROM orders
    UNION ALL SELECT 'orders', 'end_address',      end_address      FROM orders
    UNION ALL SELECT 'orders', 'factura_numero',   factura_numero   FROM orders
    UNION ALL SELECT 'orders', 'municipio',        municipio        FROM orders
    UNION ALL SELECT 'orders', 'vendedor',         vendedor         FROM orders
    UNION ALL SELECT 'orders', 'external_id',      external_id      FROM orders
    UNION ALL SELECT 'customers', 'phone',      phone      FROM customers
    UNION ALL SELECT 'customers', 'name',       name       FROM customers
    UNION ALL SELECT 'customers', 'address',    address    FROM customers
    UNION ALL SELECT 'customers', 'municipio',  municipio  FROM customers
    UNION ALL SELECT 'customers', 'zona',       zona       FROM customers
    UNION ALL SELECT 'customers', 'codigo',     codigo     FROM customers
    UNION ALL SELECT 'customers', 'vendedor',   vendedor   FROM customers
    UNION ALL SELECT 'customers', 'external_id', external_id FROM customers
)
SELECT tabla, columna,
       count(*) AS con_comilla,
       -- Cuántas de ésas limpiaría la regla conservadora. Si este número es MENOR que el de
       -- al lado, ahí hay comillas delante de algo que NO es un número: eso hay que mirarlo
       -- a ojo antes de tocar nada, porque puede ser un nombre de verdad.
       count(*) FILTER (
           WHERE btrim(substring(valor from 2)) ~ '^[0-9 +().,/-]+$'
             AND btrim(substring(valor from 2)) ~ '[0-9]'
       ) AS limpiaria_la_regla,
       min(valor) AS un_ejemplo
FROM candidatas
WHERE valor LIKE '''%'
GROUP BY tabla, columna
ORDER BY tabla, columna;


-- ---------------------------------------------------------------------------
-- 2. ARREGLAR. Una por columna, cada una con su `RETURNING`.
--    Lanzar dentro de una transacción y mirar el `RETURNING` antes del COMMIT.
-- ---------------------------------------------------------------------------
-- BEGIN;

-- UPDATE orders SET customer_phone = btrim(substring(customer_phone from 2))
--  WHERE customer_phone LIKE '''%'
--    AND btrim(substring(customer_phone from 2)) ~ '^[0-9 +().,/-]+$'
--    AND btrim(substring(customer_phone from 2)) ~ '[0-9]'
--  RETURNING id, customer_phone;

-- UPDATE orders SET operation_number = btrim(substring(operation_number from 2))
--  WHERE operation_number LIKE '''%'
--    AND btrim(substring(operation_number from 2)) ~ '^[0-9 +().,/-]+$'
--    AND btrim(substring(operation_number from 2)) ~ '[0-9]'
--  RETURNING id, operation_number;

-- UPDATE orders SET factura_numero = btrim(substring(factura_numero from 2))
--  WHERE factura_numero LIKE '''%'
--    AND btrim(substring(factura_numero from 2)) ~ '^[0-9 +().,/-]+$'
--    AND btrim(substring(factura_numero from 2)) ~ '[0-9]'
--  RETURNING id, factura_numero;

-- UPDATE customers SET phone = btrim(substring(phone from 2))
--  WHERE phone LIKE '''%'
--    AND btrim(substring(phone from 2)) ~ '^[0-9 +().,/-]+$'
--    AND btrim(substring(phone from 2)) ~ '[0-9]'
--  RETURNING id, phone;

-- UPDATE customers SET codigo = btrim(substring(codigo from 2))
--  WHERE codigo LIKE '''%'
--    AND btrim(substring(codigo from 2)) ~ '^[0-9 +().,/-]+$'
--    AND btrim(substring(codigo from 2)) ~ '[0-9]'
--  RETURNING id, codigo;

-- COMMIT;


-- ---------------------------------------------------------------------------
-- 3. Y LO DE DENTRO DE LOS TELÉFONOS: la base LOCAL de cada aparato.
-- ---------------------------------------------------------------------------
-- No hace falta tocarla y no se puede desde aquí. La APK se limpia sola: en cuanto el
-- espejo vuelva a bajar el pedido, el `customer_phone` limpio lo pisa. Y mientras tanto la
-- pantalla ya no lo enseña sucio — `app/lib/nucleo/texto_de_fuera.dart` es la segunda línea
-- de defensa, puesta el mismo día justo para este hueco.
