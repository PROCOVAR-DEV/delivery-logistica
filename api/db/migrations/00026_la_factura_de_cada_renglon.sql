-- LA FACTURA DE CADA RENGLÓN (issue 22 de Maikel, Santiago, 22/10/2026).
--
-- # El caso
--
-- En «Por producto y factura» (el pre-despacho de una ruta) salía una fila con la factura
-- «47359, 47360» y cantidad 50. Maikel: «debería hacer referencia a una única factura». La
-- tarjeta de estiba se rebaja por cantidad Y factura (Amado, issue 8): una fila que junta dos
-- facturas no dice de cuál de las dos se sacó la mercancía.
--
-- # Por qué pasaba
--
-- Una entrega de FACTURA junta en UNA fila de `orders` todas las facturas de Ventra que
-- comparten el folio del pedido (`espejo.AgruparPorFolio`, decisión de Jose: la identidad de la
-- entrega NO se toca), y `orders.factura_numero` guarda sus números unidos con coma. Pero
-- `order_items` NO decía de qué factura salía cada renglón, y la tabla no podía partirse sin
-- repetir mercancía en cada factura (rebajarla dos veces).
--
-- Con Ventra SÍ se sabe: al escribir las líneas de la entrega, cada línea viene de UNA factura.
-- Esta columna lo guarda.
--
-- # Qué es la columna y qué NO es
--
--   factura_numero   el número de la factura de Ventra de la que sale ESTE renglón, tal como
--                    lo escribe `orders.factura_numero` (un solo número, sin coma).
--
-- NULL = NO SE SABE. Y es el valor de TODO lo que ya hay: los renglones de pedidos de PEDIDO
-- (que no traen la factura por renglón: el cotejo la saca del pedido entero) y los de las
-- entregas de factura escritas antes de esta migración, hasta que el espejo las vuelva a pasar
-- (`renglonesIguales` compara esta columna, así que en cuanto la factura se repase se
-- reescriben). Quien lee tiene que tratar el NULL como «no sé de cuál», nunca como «de la
-- primera»: la tabla «Por producto y factura» deja juntas las facturas de la entrega si ALGÚN
-- renglón suyo viene sin la suya.
--
-- Un mismo producto en dos facturas de la misma entrega son AHORA DOS renglones (antes se
-- sumaban en uno): la cuenta total de la entrega (empaques, unidades, kilos) no cambia, porque
-- todo lo que la suma es por renglón.
--
-- Es aditiva y anulable: no baja nada de lo existente, ni toca `updated_at` de las filas que
-- ya hay (la bajada de los aparatos se pide por la marca de los renglones: los reescritos por
-- el espejo viajan solos; los demás se quedan NULL en el servidor y en el aparato).

-- +goose Up

ALTER TABLE order_items ADD COLUMN IF NOT EXISTS factura_numero text;

COMMENT ON COLUMN order_items.factura_numero IS
    'número de la factura de Ventra de la que sale ESTE renglón (uno solo, sin coma). NULL = no se sabe: renglones de PEDIDO y de entregas de factura anteriores a la 00026. No es orders.factura_numero, que junta las de toda la entrega (00026)';

-- +goose Down
-- QUÉ SE PIERDE: de qué factura sale cada renglón. «Por producto y factura» vuelve a juntar las
-- facturas de una entrega en una sola fila. La API de esta versión deja de arrancar sin la
-- columna (la lee en la bajada).
ALTER TABLE order_items DROP COLUMN IF EXISTS factura_numero;
