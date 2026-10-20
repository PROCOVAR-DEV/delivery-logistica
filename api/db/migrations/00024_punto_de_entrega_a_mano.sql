-- EL PUNTO DE ENTREGA PUESTO A MANO (issue 19 de Amado, «Geolocalización», Reparto 1.0.39;
-- decidido por Jose el 20/10/2026).
--
-- # El caso
--
-- El cliente pide que le entreguen en otro sitio y quien factura lo apunta en el ticket. Esa
-- dirección no coincide con la geolocalización del cliente, que es la única que PEDIDO manda
-- (`lat`/`lng` de cada pedido son las del cliente). El camión iba a la casa de siempre.
--
-- El logístico, al armar la ruta, tiene que poder ponerle a MANO el punto de entrega a un
-- pedido —lat, lng y dirección— y ese punto tiene que MANDAR sobre el del cliente.
--
-- # Por qué hace falta una MARCA y no basta con escribir `end_lat`/`end_lng`
--
-- El espejo repasa cada minuto los últimos tres días y reescribe `address, end_address, lat,
-- lng, end_lat, end_lng` desde PEDIDO en cada pasada (`GuardarPedidoDelEspejo`). Un punto
-- puesto a mano sin marca duraría hasta el siguiente repaso: un minuto. Con `punto_manual` el
-- espejo CONSERVA lo que hay y guarda el punto que trae el cliente aparte.
--
-- Decisión de Jose: NADA de webhooks ni de payloads de PEDIDO para esto. Reparto trabaja
-- contra Ventra/facturas; el logístico lo pone en Reparto y su punto gana.
--
-- # Las columnas
--
--   punto_manual           ¿el punto de entrega lo puso una persona? DEFAULT false.
--   punto_manual_por       quién (el `sub` de Accesos, como `creado_por`), constancia.
--   punto_manual_at        cuándo.
--   punto_cliente_lat/lng  el punto que traía el CLIENTE cuando se puso el manual, y que el
--   punto_cliente_address  espejo sigue actualizando mientras sea manual: es a lo que se
--                          vuelve con «devolver al del cliente», ya al día.
--
-- # LO QUE SE RECALCULA AL PONERLO (en el manejador, no aquí)
--
-- `delivery_distance_km` (desde el almacén del PEDIDO, como la cotización), `segment_km` de
-- la parada y `total_distance` de su ruta si no está completada. Los dos primeros son
-- números del cobro: guardar el punto nuevo con el kilometraje viejo sería un número
-- creíble y equivocado.
--
-- # NINGUNA FILA CAMBIA AL DESPLEGAR
--
-- `punto_manual` nace `false` (DEFAULT, y `NOT NULL` es seguro: Postgres 11+ añade una
-- columna con DEFAULT constante sin reescribir la tabla) y las demás nacen NULL = «no hay».
-- No hay UPDATE de relleno. Mismo criterio que la 00009 y la 00012.
--
-- Y OJO CON EL ORDEN AL DESPLEGAR: esta migración va ANTES que la API o la API no arranca
-- (tiene su propia guarda, `db/migraciones.go`).

-- +goose Up

ALTER TABLE orders
    ADD COLUMN IF NOT EXISTS punto_manual          boolean          NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS punto_manual_por      text,
    ADD COLUMN IF NOT EXISTS punto_manual_at       timestamptz,
    ADD COLUMN IF NOT EXISTS punto_cliente_lat     double precision,
    ADD COLUMN IF NOT EXISTS punto_cliente_lng     double precision,
    ADD COLUMN IF NOT EXISTS punto_cliente_address text;

COMMENT ON COLUMN orders.punto_manual IS
    'true = una persona puso el punto de entrega (end_lat, end_lng, end_address) y el espejo NO lo pisa; el del cliente vive en punto_cliente_*';
COMMENT ON COLUMN orders.punto_manual_por IS
    'quién puso el punto a mano (el sub de Accesos); NULL si no es manual';
COMMENT ON COLUMN orders.punto_manual_at IS
    'cuándo se puso el punto a mano; NULL si no es manual';
COMMENT ON COLUMN orders.punto_cliente_lat IS
    'latitud que traía el cliente (PEDIDO) mientras el punto es manual, siempre la última que mandó el espejo; NULL si no es manual';
COMMENT ON COLUMN orders.punto_cliente_lng IS
    'longitud que traía el cliente (PEDIDO) mientras el punto es manual; NULL si no es manual';
COMMENT ON COLUMN orders.punto_cliente_address IS
    'dirección que traía el cliente (PEDIDO) mientras el punto es manual; NULL si no es manual o no traía';

-- +goose Down
-- QUÉ SE PIERDE: la marca y el punto del cliente guardado. Los pedidos que tenían un punto a
-- mano se QUEDAN con él en `end_lat`/`end_lng`/`end_address` —como si fuera el del cliente— hasta
-- que el espejo vuelva a pasar por ellos (sólo repasa los últimos tres días: los más viejos
-- se quedan con el punto a mano para siempre). Y la API de esta versión deja de arrancar sin
-- las columnas, así que el `Down` sólo vale junto con volver a la imagen anterior.
ALTER TABLE orders
    DROP COLUMN IF EXISTS punto_cliente_address,
    DROP COLUMN IF EXISTS punto_cliente_lng,
    DROP COLUMN IF EXISTS punto_cliente_lat,
    DROP COLUMN IF EXISTS punto_manual_at,
    DROP COLUMN IF EXISTS punto_manual_por,
    DROP COLUMN IF EXISTS punto_manual;
