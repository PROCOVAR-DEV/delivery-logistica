-- EL FOLIO DEL PEDIDO (issue 20 de Amado, «Sustitución de Pedido por Factura», Fase A;
-- decidido por Jose el 20/10/2026).
--
-- # El caso
--
-- Reparto deja de alimentarse de los PEDIDOS de PEDIDO y pasa a alimentarse de las FACTURAS
-- CON DOMICILIO de Ventra. El corte no es atómico: durante un tiempo conviven las dos fuentes
-- (`SYNC_FUENTE=ambas`) y el MISMO pedido llega por las dos puertas —como pedido de PEDIDO y
-- como factura de Ventra—. Sin una clave común, saldría dos veces en la lista del armador y
-- alguien lo cargaría dos veces en el camión.
--
-- La clave común es el FOLIO del pedido: PEDIDO lo guarda como `operation_number`, y Ventra
-- lo trae como `orderNumber`, sacado de la nota de la venta (`P-<folio>; V-<vendedor>; …`).
--
-- # Por qué una columna nueva y no usar `operation_number`
--
-- En una entrega de FACTURA, `operation_number` es otra cosa: el «conduce», o sea el CONJUNTO
-- de números de factura de la entrega («un conduce puede tener varias facturas», Jose). Ya no
-- es el folio. Si las dos cosas vivieran en la misma columna, la adopción no tendría por dónde
-- reconocer a la fila de PEDIDO una vez que su `operation_number` cambiara de significado.
--
--   folio   el folio de PEDIDO de la entrega: en las filas de PEDIDO, el `operation_number`
--           de siempre; en las de factura, el `orderNumber` (NULL si la venta no traía la
--           nota, y entonces la entrega es su propia factura y no se adopta ni se adopta a
--           nadie).
--
-- El índice es (sucursal_codigo, folio_normalizado(folio)) porque un folio es único dentro de su sucursal, no en
-- toda la casa, y es la pregunta de la adopción: «¿hay ya una fila de esta sucursal con este
-- folio?».
--
-- # EL FOLIO SE COMPARA NORMALIZADO, NO EXACTO (auditoría del 20/10/2026, hallazgo G3)
--
-- La columna `folio` guarda el valor TAL CUAL llegó. Pero un folio que alguien teclea en la nota
-- de una venta llega como `pxx-900`, `'PXX-900` (la comilla de Excel) o `PXX - 900`, y comparado
-- con `=` no reconoce al `PXX-900` de PEDIDO: la adopción no ocurre y el pedido sale DOS veces,
-- cargable dos veces en el camión. Lo que se compara es `folio_normalizado(folio)`: mayúsculas y
-- sólo letras y dígitos ASCII. ES UNA SOLA FUNCIÓN, y la usan la adopción, el «ya adoptado» y el
-- índice; su gemela en Go (`alcance.FolioNormalizado`, que también arma la clave `external_id`
-- de la entrega) la ata una prueba contra Postgres, no este comentario.
--
-- `PXX-900` y `PXY-900` siguen siendo distintos (`PXX900` / `PXY900`); y un folio que se queda
-- vacío al normalizarlo (`---`) no es un folio: quien llama NO adopta con él.
--
-- # EL PUNTO QUE YA TENÍA NO SE PIERDE (hallazgo G1)
--
-- `punto_se_conserva` decide, para el upsert del espejo (`GuardarPedidoDelEspejo`), si el punto de
-- entrega que ya hay se queda: cuando es a mano, o cuando el que entra NO trae punto y la fila ya
-- tenía uno (una factura cuyo cliente no está en `customers` adopta a una fila de PEDIDO que sí
-- tenía su punto: sin esto el punto, el km y la dirección se borraban, y la parada de una ruta se
-- quedaba fuera del armador por `end_lat IS NULL`). Va como función para que el `SET` y el
-- `WHERE IS DISTINCT FROM` del upsert usen LA MISMA regla y no dos copias que se separan.

-- # EL RELLENO DE LAS FILAS DE PEDIDO, y por qué va AQUÍ
--
-- `UPDATE orders SET folio = operation_number WHERE folio IS NULL` sobre las ~15.000 filas que
-- hay. Va en la migración y no en un paso aparte porque sin él el primer repaso del espejo
-- reescribiría cada pedido de los últimos días (el upsert compara `folio` y vería «distinto»)
-- y, peor, los pedidos de hace más de tres días no se reescribirían NUNCA y la adopción no los
-- encontraría: una factura de un pedido viejo que llegara tarde saldría duplicada.
--
-- Cuesta segundos (15.000 filas, una tabla estrecha) y NO MUEVE `updated_at`: la bajada de los
-- aparatos se pide por `updated_at` (`DiferenciasDePedidos`), así que un UPDATE normal haría
-- que cada teléfono y cada escritorio se volviera a bajar los 15.000 pedidos para recibir una
-- columna que no leen. Por eso se apaga SÓLO `trg_orders_updated` mientras dura el UPDATE.
-- Los otros dos triggers de `orders` no se disparan: `trg_orders_totales_de_ruta` mira
-- `ultima_ruta_id, weight, pedido_costo, factura_domicilio` y `trg_orders_salida`, `branch_id`.
--
-- Qué cuesta en bloqueos: `ALTER TABLE … DISABLE TRIGGER` pide SHARE ROW EXCLUSIVE sobre
-- `orders` hasta el COMMIT de la migración, o sea que durante esos segundos ni el espejo ni la
-- API escriben pedidos (las lecturas siguen). Se reintentan en el ciclo siguiente. Es la razón
-- de que esta migración se aplique ANTES que la API y con el espejo parado o a su ritmo normal,
-- nunca en mitad de un barrido de histórico.
--
-- # NINGUNA FILA DE FACTURA EXISTE AL DESPLEGAR
--
-- Hasta que alguien ponga `SYNC_FUENTE=factura|ambas` en el espejo, todo sigue como estaba. La
-- columna es anulable y las filas nuevas de PEDIDO la rellenan solas en el upsert.
--
-- Y OJO CON EL ORDEN AL DESPLEGAR: esta migración va ANTES que la API o la API no arranca
-- (tiene su propia guarda, `db/migraciones.go`).

-- +goose Up

ALTER TABLE orders ADD COLUMN IF NOT EXISTS folio text;

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION folio_normalizado(folio text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT upper(regexp_replace(folio, '[^A-Za-z0-9]', '', 'g')) $$;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION punto_se_conserva(
    manual boolean, ya_lat double precision, ya_lng double precision,
    nuevo_lat double precision, nuevo_lng double precision
) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT coalesce(manual, false)
        OR (ya_lat IS NOT NULL AND ya_lng IS NOT NULL AND (nuevo_lat IS NULL OR nuevo_lng IS NULL))
$$;
-- +goose StatementEnd

COMMENT ON COLUMN orders.folio IS
    'folio de PEDIDO de la entrega (en filas de PEDIDO = operation_number; en las de factura, el orderNumber de Ventra). NULL si no lo hay. Clave de la adopción entre las dos fuentes (00025)';

ALTER TABLE orders DISABLE TRIGGER trg_orders_updated;

UPDATE orders SET folio = operation_number
WHERE folio IS NULL AND operation_number IS NOT NULL AND source = 'pedido';

ALTER TABLE orders ENABLE TRIGGER trg_orders_updated;

-- Sirve a la adopción: «¿hay ya una fila de esta sucursal con este folio, normalizado?».
CREATE INDEX IF NOT EXISTS orders_sucursal_folio_idx ON orders (sucursal_codigo, folio_normalizado(folio));

-- +goose Down
-- QUÉ SE PIERDE: la columna y su índice. Las entregas que ya nacieron de una factura
-- (`external_id` con prefijo `factura:`) se QUEDAN, pero sin folio: dejan de poder adoptar a una
-- fila de PEDIDO y de ser reconocidas por ella, así que si el espejo vuelve a traer los pedidos
-- de PEDIDO saldrán DUPLICADAS. Bajar esto sólo vale junto con volver a `SYNC_FUENTE=pedido` y
-- retirar a mano las filas `factura:%`. Y la API de esta versión deja de arrancar sin la columna.
DROP INDEX IF EXISTS orders_sucursal_folio_idx;
ALTER TABLE orders DROP COLUMN IF EXISTS folio;
DROP FUNCTION IF EXISTS punto_se_conserva(boolean, double precision, double precision, double precision, double precision);
DROP FUNCTION IF EXISTS folio_normalizado(text);
