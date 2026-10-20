-- Catálogo. Se llena solo: PEDIDO sondea Ventra y aquí se copia lo que él ya tiene.
-- No hay alta manual — dos catálogos escritos por separado discrepan sin que nadie lo vea.
--
-- EL ALCANCE VA POR CÓDIGO DE SUCURSAL, igual que en clientes: `products` no tiene
-- `branch_id`, tiene `sucursal_codigo`. Y tiene que llevarlo: en Ventra el precio y las
-- existencias VARÍAN por sucursal, así que un catálogo único ofrece en Camagüey un
-- producto que sólo hay en La Habana, y al precio de La Habana.
--
-- Quien llama traduce su sucursal a `branches.external_id` y lo pasa en `sucursal`.
-- A diferencia de clientes, aquí NO se dejan pasar las filas sin código: un producto sin
-- sucursal no tiene ni precio ni existencias de ningún sitio.

-- ---------------------------------------------------------------------------
-- El catálogo de una sucursal  (GET /api/products)
-- ---------------------------------------------------------------------------

-- Los productos que se pueden cargar en un camión, de la sucursal que toque.
--
-- SE EXCLUYEN LAS LÍNEAS DE SERVICIO. En el catálogo de Ventra conviven los productos con
-- líneas como «ENTREGA A DOMICILIO» —categoría `SERV`, peso cero—: no es algo que se
-- carga, es el propio cobro del reparto facturado como una línea más. Salía en el buscador
-- con «0 kg» al lado y alguien la iba a elegir tarde o temprano; un pedido con esa línea
-- dentro pesa lo mismo que sin ella y encima cobra el reparto DOS VECES, una en la línea y
-- otra en el domicilio. La misma regla vive en PEDIDO y las dos tienen que estar de
-- acuerdo en qué es mercancía.
--
-- Se compara la frase entera: con «entrega» a secas, cualquier producto que la mencionara
-- desaparecería del catálogo y nadie sabría por qué.
-- name: ListarProductos :many
SELECT
    p.id, p.name, p.weight, p.packaging, p.units_per_package, p.category,
    p.sku, p.sucursal_codigo, p.price, p.stock, p.unit, p.traido_at,
    p.created_at, p.updated_at
FROM products p
WHERE
    (sqlc.narg('sucursal')::text IS NULL OR p.sucursal_codigo = sqlc.narg('sucursal')::text)
    AND (
        sqlc.narg('q')::text IS NULL
        OR p.name     ILIKE '%' || sqlc.narg('q')::text || '%'
        OR p.category ILIKE '%' || sqlc.narg('q')::text || '%'
        OR p.sku      ILIKE '%' || sqlc.narg('q')::text || '%'
    )
    AND lower(btrim(coalesce(p.category, ''))) NOT IN ('serv', 'servicio', 'servicios')
    AND lower(coalesce(p.name, '')) NOT LIKE '%entrega a domicilio%'
    AND lower(coalesce(p.name, '')) NOT LIKE '%servicio de entrega%'
ORDER BY p.name ASC
-- ESTA CONSULTA ES LA DE LA PANTALLA, Y SÓLO LA DE LA PANTALLA. Ordena por nombre, que es
-- como se busca a ojo, y por eso NO sirve para la bajada del aparato: «los 2.000 primeros
-- por nombre» son 2.000 cualesquiera y no hay última fila servida que devolver. La bajada
-- va por `DiferenciasDeProductos`, aquí abajo.
LIMIT sqlc.arg('limite');

-- ---------------------------------------------------------------------------
-- El catálogo de la bajada del aparato  (GET /api/sync/cambios)
-- ---------------------------------------------------------------------------

-- Lo que cambió en el catálogo, ORDENADO POR LA MARCA y acotado por un cursor.
--
-- Es la misma forma que `DiferenciasDePedidos`, y está copiada a propósito en vez de
-- inventada otra vez: quien contesta la bajada devuelve como `hasta` la marca de la ÚLTIMA
-- FILA SERVIDA y no su reloj, y para eso el orden tiene que ser el de la marca. Con el
-- orden por nombre que usa la pantalla, marcar `truncado` y devolver el reloj deja lo que
-- no cupo POR DEBAJO del próximo `desde`, y eso no lo vuelve a pedir nadie nunca más
-- (`CLAUDE.md` §3). Pasó con el padrón: 2.000 clientes redondos de 8.034.
--
-- EL CURSOR LLEVA LA MARCA Y EL ID, y el id no es un adorno. El traspaso metió el catálogo
-- entero en UNA transacción, y `now()` es la del inicio de la transacción: miles de filas
-- comparten `updated_at` al microsegundo. Un cursor de sólo marca o no avanza —vuelve a
-- servir el grupo entero para siempre— o se salta lo que quedaba del grupo. Con `(marca,
-- id)` la tanda siguiente empieza EXACTAMENTE donde acabó la anterior, comparta marca o no.
--
-- Los tres filtros de líneas de servicio se repiten aquí y tienen que seguir repetidos: un
-- «ENTREGA A DOMICILIO» que no sale en la pantalla pero sí baja al teléfono es el mismo
-- cobro duplicado, en el aparato que trabaja sin conexión y sin nadie que lo desmienta.
-- name: DiferenciasDeProductos :many
SELECT
    p.id, p.name, p.weight, p.packaging, p.units_per_package, p.category,
    p.sku, p.sucursal_codigo, p.price, p.stock, p.unit, p.traido_at,
    p.created_at, p.updated_at
FROM products p
WHERE
    (sqlc.narg('sucursal')::text IS NULL OR p.sucursal_codigo = sqlc.narg('sucursal')::text)
    AND lower(btrim(coalesce(p.category, ''))) NOT IN ('serv', 'servicio', 'servicios')
    AND lower(coalesce(p.name, '')) NOT LIKE '%entrega a domicilio%'
    AND lower(coalesce(p.name, '')) NOT LIKE '%servicio de entrega%'
    -- `desde` ESTRICTO y `hasta` INCLUSIVO, como en los pedidos: dos ventanas seguidas no
    -- se pisan ni dejan hueco. Y `hasta` hace falta DE VERDAD aquí: sin él se servirían
    -- filas por encima de la ventana y el corte devolvería una marca mayor que el `hasta`
    -- de la respuesta, que es otra manera de dejar filas por debajo de la raya.
    AND (sqlc.narg('desde')::timestamptz IS NULL OR p.updated_at > sqlc.narg('desde')::timestamptz)
    AND (sqlc.narg('hasta')::timestamptz IS NULL OR p.updated_at <= sqlc.narg('hasta')::timestamptz)
    AND (
        sqlc.narg('cursor_marca')::timestamptz IS NULL
        OR p.updated_at > sqlc.narg('cursor_marca')::timestamptz
        OR (p.updated_at = sqlc.narg('cursor_marca')::timestamptz
            AND p.id > sqlc.narg('cursor_id')::uuid)
    )
ORDER BY p.updated_at ASC, p.id ASC
LIMIT sqlc.arg('tope');

-- Cuánto se ha pedido de cada producto últimamente, para ordenar el buscador por lo que la
-- gente usa de verdad y no por orden alfabético.
--
-- Se cuenta sobre los últimos N pedidos DEL ALCANCE, no sobre todo el histórico: lo que se
-- movía hace ocho meses no dice nada de lo que hay que tener a mano hoy. El tope lo pone
-- el llamante para que la cuenta no crezca sola con la base.
-- name: UsoDeProductos :many
SELECT oi.product_id, sum(oi.quantity)::double precision AS unidades
FROM order_items oi
WHERE oi.product_id IS NOT NULL
  AND oi.order_id IN (
      SELECT o.id FROM orders o
      WHERE (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
      ORDER BY o.created_at DESC
      LIMIT sqlc.arg('pedidos_recientes')
  )
GROUP BY oi.product_id;

-- name: ObtenerProducto :one
SELECT
    p.id, p.name, p.weight, p.packaging, p.units_per_package, p.category,
    p.sku, p.sucursal_codigo, p.price, p.stock, p.unit, p.traido_at,
    p.created_at, p.updated_at
FROM products p
WHERE p.id = sqlc.arg('id');

-- Emparejar un renglón de pedido con el catálogo de SU sucursal. El `sku` sólo es único
-- dentro de una sucursal —la clave de la tabla es (`sucursal_codigo`, `sku`)—, así que
-- buscarlo sin ella devuelve el precio y las existencias de donde no toca.
-- name: BuscarProductoPorSku :one
SELECT p.id, p.name, p.weight, p.sku, p.sucursal_codigo, p.price, p.stock, p.unit
FROM products p
WHERE p.sucursal_codigo = sqlc.arg('sucursal_codigo')
  AND p.sku = sqlc.arg('sku');

-- ---------------------------------------------------------------------------
-- Bajada del catálogo  (POST /api/products/sync)
-- ---------------------------------------------------------------------------

-- Upsert por (`sucursal_codigo`, `sku`), que es la única clave de verdad: es por el código
-- de Ventra como se reconoce una fila entre pasadas. Aquí SÍ hay `ON CONFLICT` porque el
-- esquema declara esa pareja como UNIQUE.
--
-- Lo que NO se hace: borrar lo que deja de venir. Media lista por un corte de VPN no debe
-- vaciar el catálogo de una sucursal — lo viejo se nota por `traido_at`, que dice si lo
-- que se está mirando es de hace diez minutos o de hace tres días.
-- name: GuardarProductoDelCatalogo :one
INSERT INTO products (
    name, weight, packaging, units_per_package, category, sku,
    sucursal_codigo, price, stock, unit, traido_at
) VALUES (
    sqlc.arg('name'), sqlc.arg('weight'), sqlc.narg('packaging'),
    sqlc.narg('units_per_package'), sqlc.narg('category'), sqlc.narg('sku'),
    sqlc.narg('sucursal_codigo'), sqlc.narg('price'), sqlc.narg('stock'),
    sqlc.narg('unit'), now()
)
ON CONFLICT (sucursal_codigo, sku) DO UPDATE SET
    name              = excluded.name,
    weight            = excluded.weight,
    packaging         = excluded.packaging,
    units_per_package = excluded.units_per_package,
    category          = excluded.category,
    price             = excluded.price,
    stock             = excluded.stock,
    unit              = excluded.unit,
    traido_at         = excluded.traido_at
RETURNING id, name, sku, sucursal_codigo, traido_at;

-- ---------------------------------------------------------------------------
-- Correcciones del catálogo  (sólo Super Admin, sin alcance: es de toda la empresa)
-- ---------------------------------------------------------------------------

-- Lo que se puede corregir a mano es sólo lo que Ventra no da bien: el peso, el envase y
-- la categoría. Ni el precio ni las existencias, que son de Ventra y se vuelven a pisar en
-- la siguiente pasada; dejarlos editar es prometer un cambio que dura doce horas.
-- name: ActualizarProducto :one
UPDATE products SET
    name              = coalesce(sqlc.narg('name')::text, name),
    weight            = coalesce(sqlc.narg('weight')::double precision, weight),
    packaging         = CASE WHEN sqlc.arg('tocar_packaging')::boolean
                             THEN sqlc.narg('packaging')::text ELSE packaging END,
    units_per_package = CASE WHEN sqlc.arg('tocar_units')::boolean
                             THEN sqlc.narg('units_per_package')::double precision
                             ELSE units_per_package END,
    category          = CASE WHEN sqlc.arg('tocar_category')::boolean
                             THEN sqlc.narg('category')::text ELSE category END
WHERE id = sqlc.arg('id')
RETURNING id, name, weight, packaging, units_per_package, category, sku,
          sucursal_codigo, price, stock, unit, traido_at, updated_at;

-- name: BorrarProducto :execrows
DELETE FROM products WHERE id = sqlc.arg('id');

-- ---------------------------------------------------------------------------
-- Un producto suelto, ACOTADO  (GET /api/products/[id])
-- ---------------------------------------------------------------------------

-- El mismo producto que `ObtenerProducto`, pero filtrado por el código de la sucursal.
--
-- POR QUÉ HAY DOS. `ObtenerProducto` va sin alcance a propósito: es la que usan las
-- correcciones del Super Admin, que son de toda la empresa. Ésta es la de la PANTALLA, y
-- ahí enseñar el producto de otra sucursal no es sólo un fallo de permisos: el PRECIO y
-- las EXISTENCIAS son por sucursal, así que una ficha de La Habana abierta desde Camagüey
-- lleva un precio que en Camagüey no se cobra y unas existencias que allí no hay. Eso se
-- copia en un pedido y no lo desmiente nadie hasta que llega la factura.
--
-- NULL en `sucursal` = todas (Super Admin sin sucursal elegida).
-- name: ObtenerProductoDelAlcance :one
SELECT
    p.id, p.name, p.weight, p.packaging, p.units_per_package, p.category,
    p.sku, p.sucursal_codigo, p.price, p.stock, p.unit, p.traido_at,
    p.created_at, p.updated_at
FROM products p
WHERE p.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::text IS NULL OR p.sucursal_codigo = sqlc.narg('sucursal')::text);

-- LO QUE PESA Y CUÁNTO TRAE CADA PRODUCTO DE UNA SUCURSAL, para pesar los renglones de una
-- entrega que nace de una FACTURA (issue 20, Fase A). El peso sale de Ventra, no de PEDIDO
-- (Jose, 20/10/2026): `weight` es por UNIDAD DE VENTA y `units_per_package` es cuántas
-- unidades trae esa unidad de venta (una B de cerveza: 6). El `sku` es el `productCode` de la
-- factura. Va sin alcance, igual que el resto de lo del espejo.
-- name: PesosDeProductosDeLaSucursal :many
SELECT sku, name, weight, units_per_package
FROM products
WHERE sucursal_codigo = sqlc.arg('sucursal_codigo')::text AND sku IS NOT NULL;
