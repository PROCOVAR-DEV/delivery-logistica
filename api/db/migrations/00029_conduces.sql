-- +goose Up
--
-- CONDUCES (super factura) — Jose, 21 y 27/10/2026. La especificación entera está en `docs/conduces.md`.
--
-- UNA FILA SIGUE SIENDO UNA FACTURA. El conduce no suma ni mezcla datos en la principal: el espejo reescribe
-- cada fila desde su factura y pisaría lo acumulado. Lo único que se guarda es el enlace:
--
--     conduce_principal_id  NULL      factura suelta, o PRINCIPAL de un conduce
--     conduce_principal_id  <uuid>    MIEMBRO, apunta a su principal
--
-- Lo escribe SOLO una persona (`POST/DELETE /api/conduces…`). El upsert del espejo (`GuardarPedidoDelEspejo`)
-- no nombra esta columna a propósito: una fila miembro reescrita por el espejo sigue siendo miembro.
--
-- ON DELETE SET NULL: si la principal se borra (el espejo retira una factura que ya no viene) los miembros
-- quedan SUELTOS, nunca se destruyen.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS conduce_principal_id uuid
    REFERENCES orders(id) ON DELETE SET NULL;

-- Parcial: casi todas las filas son sueltas. Sirve a «los miembros de esta principal».
CREATE INDEX IF NOT EXISTS orders_conduce_principal_idx
    ON orders (conduce_principal_id) WHERE conduce_principal_id IS NOT NULL;

COMMENT ON COLUMN orders.conduce_principal_id IS
    'conduce (00029): NULL = factura suelta o PRINCIPAL de un conduce; uuid = MIEMBRO y apunta a su principal. Sin cadenas. Solo lo escribe una persona';

-- SIN CADENAS Y DE LA MISMA SUCURSAL. Un CHECK no ve otras filas, así que es un trigger. Es la última llave:
-- los endpoints ya lo comprueban y nombran la factura que lo impide; esto es lo que queda si alguien escribe
-- por otro camino. Una principal nunca es miembro, un miembro nunca es principal, y van en la misma sucursal.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION conduce_sin_cadenas() RETURNS trigger AS $$
BEGIN
    IF NEW.conduce_principal_id = NEW.id THEN
        RAISE EXCEPTION 'una factura no puede ser miembro de su propio conduce' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM orders p
                WHERE p.id = NEW.conduce_principal_id AND p.conduce_principal_id IS NOT NULL) THEN
        RAISE EXCEPTION 'la principal de un conduce no puede ser miembro de otro' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM orders m WHERE m.conduce_principal_id = NEW.id) THEN
        RAISE EXCEPTION 'una factura con miembros no puede ser miembro de otro conduce' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM orders p
                WHERE p.id = NEW.conduce_principal_id AND p.branch_id IS DISTINCT FROM NEW.branch_id) THEN
        RAISE EXCEPTION 'un conduce no mezcla sucursales' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER trg_orders_conduce_sin_cadenas
    BEFORE INSERT OR UPDATE OF conduce_principal_id ON orders
    FOR EACH ROW WHEN (NEW.conduce_principal_id IS NOT NULL)
    EXECUTE FUNCTION conduce_sin_cadenas();

-- UNA FACTURA ARCHIVADA DEJA SU CONDUCE (regla 7). Si el espejo archiva un MIEMBRO, sale del conduce; si archiva
-- la PRINCIPAL, sus miembros quedan sueltos (y salen de la ruta con ella si la principal ya no tiene ruta y ellos
-- no tienen resultado): nada se destruye y nada queda huérfano e invisible detrás de una principal archivada.
-- SALVO la anulación de una ruta (`anulada_at`): esa la hace `AnularEntregasDeFacturaEnRuta` en UNA sentencia con
-- todos los ids y libera ella misma a los miembros; un trigger que tocara las mismas filas dentro de esa
-- sentencia las dejaría «ya modificadas» y la reventaría.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION conduce_al_archivar() RETURNS trigger AS $$
BEGIN
    NEW.conduce_principal_id := NULL;
    UPDATE orders m SET
        conduce_principal_id = NULL,
        route_id       = CASE WHEN NEW.route_id IS NULL AND m.resultado IS NULL AND m.delivered_at IS NULL
                              THEN NULL ELSE m.route_id END,
        ultima_ruta_id = CASE WHEN NEW.route_id IS NULL AND m.resultado IS NULL AND m.delivered_at IS NULL
                              THEN NULL ELSE m.ultima_ruta_id END,
        stop_order     = CASE WHEN NEW.route_id IS NULL AND m.resultado IS NULL AND m.delivered_at IS NULL
                              THEN NULL ELSE m.stop_order END,
        segment_km     = CASE WHEN NEW.route_id IS NULL AND m.resultado IS NULL AND m.delivered_at IS NULL
                              THEN NULL ELSE m.segment_km END
    WHERE m.conduce_principal_id = NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER trg_orders_conduce_al_archivar
    BEFORE UPDATE OF archivado ON orders
    FOR EACH ROW WHEN (NEW.archivado AND NOT OLD.archivado AND NEW.anulada_at IS NULL)
    EXECUTE FUNCTION conduce_al_archivar();

-- LO QUE PESA Y LO QUE COBRA UN CONDUCE ENTERO. La principal pesa lo suyo MÁS lo de sus miembros: el camión
-- carga todas. Una función para que el tablero, el panel y el armado no escriban la suma cada uno. El costo
-- es `costoDeLaParada` (`pedido_costo`, y si no `factura_domicilio` cuando es > 0).
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION conduce_peso(principal uuid) RETURNS double precision
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(m.weight), 0)::double precision FROM orders m WHERE m.conduce_principal_id = principal;
$$;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION conduce_costo(principal uuid) RETURNS double precision
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(coalesce(m.pedido_costo, CASE WHEN m.factura_domicilio > 0 THEN m.factura_domicilio END)), 0)::double precision
      FROM orders m WHERE m.conduce_principal_id = principal;
$$;
-- +goose StatementEnd

-- LOS TOTALES DE LA RUTA CUENTAN UNA PARADA POR CONDUCE. El peso y el importe suman todas las filas de la ruta
-- (el camión las carga todas y cada factura cobra lo suyo), pero «paradas sin cotizar» cuenta PARADAS: un
-- miembro no es una parada, y un conduce está sin cotizar solo si NINGUNA de sus facturas trae costo.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION totales_de_ruta(ruta uuid)
RETURNS TABLE (peso double precision, importe double precision, sin_cotizar integer)
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(o.weight), 0)::double precision,
           coalesce(sum(coalesce(o.pedido_costo,
                                 CASE WHEN o.factura_domicilio > 0 THEN o.factura_domicilio END)), 0)::double precision,
           count(*) FILTER (WHERE o.conduce_principal_id IS NULL
                              AND o.pedido_costo IS NULL
                              AND NOT (coalesce(o.factura_domicilio, 0) > 0)
                              AND NOT EXISTS (SELECT 1 FROM orders m
                                               WHERE m.conduce_principal_id = o.id
                                                 AND m.ultima_ruta_id = ruta
                                                 AND (m.pedido_costo IS NOT NULL
                                                      OR coalesce(m.factura_domicilio, 0) > 0)))::integer
      FROM orders o
     WHERE o.ultima_ruta_id = ruta;
$$;
-- +goose StatementEnd

DROP TRIGGER IF EXISTS trg_orders_totales_de_ruta ON orders;
CREATE TRIGGER trg_orders_totales_de_ruta
    AFTER INSERT OR DELETE OR UPDATE OF ultima_ruta_id, weight, pedido_costo, factura_domicilio, conduce_principal_id ON orders
    FOR EACH ROW EXECUTE FUNCTION refrescar_totales_de_ruta();

-- +goose Down
DROP TRIGGER IF EXISTS trg_orders_totales_de_ruta ON orders;
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
CREATE TRIGGER trg_orders_totales_de_ruta
    AFTER INSERT OR DELETE OR UPDATE OF ultima_ruta_id, weight, pedido_costo, factura_domicilio ON orders
    FOR EACH ROW EXECUTE FUNCTION refrescar_totales_de_ruta();

DROP FUNCTION IF EXISTS conduce_costo(uuid);
DROP FUNCTION IF EXISTS conduce_peso(uuid);
DROP TRIGGER IF EXISTS trg_orders_conduce_al_archivar ON orders;
DROP FUNCTION IF EXISTS conduce_al_archivar();
DROP TRIGGER IF EXISTS trg_orders_conduce_sin_cadenas ON orders;
DROP FUNCTION IF EXISTS conduce_sin_cadenas();
DROP INDEX IF EXISTS orders_conduce_principal_idx;
ALTER TABLE orders DROP COLUMN IF EXISTS conduce_principal_id;
