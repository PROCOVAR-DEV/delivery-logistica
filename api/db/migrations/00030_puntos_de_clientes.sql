-- +goose Up
--
-- LOS PUNTOS QUE EL LOGÍSTICO UBICÓ, GUARDADOS POR CLIENTE — Jose, 28/10/2026.
--
-- Ventra manda la dirección en texto y el punto sale del padrón de clientes por la referencia que teclea el
-- vendedor. Si no coincide (una letra de más, un cliente sin referencia) la factura queda SIN PUNTO y el
-- logístico la ubica a mano con «Ubicar la entrega». Esa ubicación se perdía: la siguiente factura del
-- mismo cliente volvía a salir sin punto. Aquí se guarda, por sucursal y por el nombre del cliente
-- normalizado (mayúsculas, sin espacios ni tildes: `espejo.ClaveDeCliente`), y el espejo la usa como un
-- cliente más del padrón: la factura siguiente nace con su punto.
--
-- Es del espejo y de `PUT /api/orders/{id}/punto`; no toca `customers` (ese padrón es de PEDIDO).
CREATE TABLE puntos_de_clientes (
    sucursal_codigo text             NOT NULL,
    clave           text             NOT NULL,
    nombre          text             NOT NULL,
    lat             double precision NOT NULL,
    lng             double precision NOT NULL,
    direccion       text,
    puesto_por      text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (sucursal_codigo, clave),
    CONSTRAINT puntos_de_clientes_en_el_planeta CHECK (
        lat BETWEEN -90 AND 90 AND lng BETWEEN -180 AND 180 AND NOT (lat = 0 AND lng = 0))
);

CREATE TRIGGER trg_puntos_de_clientes_updated BEFORE UPDATE ON puntos_de_clientes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS puntos_de_clientes;
