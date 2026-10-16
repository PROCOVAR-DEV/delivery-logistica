-- +goose Up
-- EL IMPORTE DE LA RUTA SUMA LO COBRADO EN LA FACTURA (Jose, 16/10/2026, con la regla «entra todo lo
-- facturado»; caso real PCC25-261014-1435: marcado, sin cotizar en Entrega, factura con 0.05 de domicilio).
--
-- La 00014 sumaba sólo `pedido_costo` y contaba como «sin cotizar» toda parada con `pedido_costo` nulo.
-- Ahora el costo de una parada es `pedido_costo` si existe (lo que cotizó Entrega) y, si no, lo que la
-- factura cobró (`factura_domicilio > 0`); sólo cuenta como «sin cotizar» la que no tiene ninguno de los
-- dos. Es la misma regla que `costoDeLaParada` (api/internal/api/rutas.go) y la de la app.
--
-- Y el disparador vigila también `factura_domicilio`: sin eso, un cobro que llega después del pedido en
-- una ruta no refrescaría el total.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION totales_de_ruta(ruta uuid)
RETURNS TABLE (peso double precision, importe double precision, sin_cotizar integer)
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(o.weight), 0)::double precision,
           coalesce(sum(coalesce(o.pedido_costo,
                                 CASE WHEN o.factura_domicilio > 0 THEN o.factura_domicilio END)), 0)::double precision,
           count(*) FILTER (WHERE o.pedido_costo IS NULL
                              AND NOT (coalesce(o.factura_domicilio, 0) > 0))::integer
      FROM orders o
     WHERE o.ultima_ruta_id = ruta;
$$;
-- +goose StatementEnd

DROP TRIGGER IF EXISTS trg_orders_totales_de_ruta ON orders;
CREATE TRIGGER trg_orders_totales_de_ruta
    AFTER INSERT OR DELETE OR UPDATE OF ultima_ruta_id, weight, pedido_costo, factura_domicilio ON orders
    FOR EACH ROW EXECUTE FUNCTION refrescar_totales_de_ruta();

-- Las rutas que ya existen se recalculan una vez (sólo las no completadas: el histórico se fija al completar).
UPDATE routes r
   SET total_price         = (SELECT importe FROM totales_de_ruta(r.id)),
       paradas_sin_cotizar = (SELECT sin_cotizar FROM totales_de_ruta(r.id))
 WHERE r.status <> 'completed';

-- +goose Down
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION totales_de_ruta(ruta uuid)
RETURNS TABLE (peso double precision, importe double precision, sin_cotizar integer)
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(o.weight), 0)::double precision,
           coalesce(sum(o.pedido_costo), 0)::double precision,
           count(*) FILTER (WHERE o.pedido_costo IS NULL)::integer
      FROM orders o
     WHERE o.ultima_ruta_id = ruta;
$$;
-- +goose StatementEnd

DROP TRIGGER IF EXISTS trg_orders_totales_de_ruta ON orders;
CREATE TRIGGER trg_orders_totales_de_ruta
    AFTER INSERT OR DELETE OR UPDATE OF ultima_ruta_id, weight, pedido_costo ON orders
    FOR EACH ROW EXECUTE FUNCTION refrescar_totales_de_ruta();
