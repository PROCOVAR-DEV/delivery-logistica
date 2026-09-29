-- LOS TOTALES DE UNA RUTA DEJAN DE SER UNA FOTO DEL DÍA EN QUE SE ARMÓ.
--
-- `routes.total_weight` y `routes.total_price` se escribían UNA vez, al armar, y nadie
-- las volvía a tocar. Mordió dos veces, las dos con un número creíble:
--
--   * 22/09/2026 — `RT-20260921-007` decía `$0.00` con sus dos paradas marcadas «sin
--     cotizar» y el camión a 1,50 USD/km. Un cero no dice «no hay tarifa»: dice que el
--     reparto fue gratis.
--   * 28/09/2026 — la cabecera de `RT-20260928-003` decía **420 kg** mientras sus dos
--     paradas sumaban **516,5** (419,7 + 96,8) tres líneas más abajo, en la misma
--     pantalla. Y lo grave: la capacidad del camión se medía contra esa columna, así que
--     un camión podía parecer que cabía sin caber.
--
-- Las pantallas ya no las leen: suman de las paradas (`pantallas/rutas/datos/
-- peso_de_la_ruta.dart` e `importe_de_la_ruta.dart`, con sus dos pruebas que se ponen
-- rojas si alguien vuelve a leer `totalWeight` o `totalPrice`). Lo que quedaba abierto
-- —y es lo que arregla esta migración— es **el servidor**: quien lee esas columnas por
-- SQL o las exporta seguía viendo el total del día en que se armó la ruta, no el de sus
-- paradas de hoy. Medido en el Postgres local el 29/09/2026: bastaba con que el espejo
-- repasara el peso de un pedido de una ruta ya armada —que es lo que hace cada minuto,
-- `GuardarPedidoDelEspejo` pisa `weight` y `pedido_costo`— para que la cabecera y sus
-- paradas se separaran y no hubiera nada que lo dijera.
--
-- # La decisión: la columna se queda como ESPEJO, y el espejo lo mantiene la base
--
-- La regla del proyecto es que la columna **no es el dato**: es el espejo de la
-- aritmética del servidor. Para que un espejo no mienta sólo hace falta una cosa, que es
-- justo la que faltaba: **que se vuelva a mirar en cada cambio de las paradas**.
--
-- Se hace con un trigger sobre `orders` y no llamando a un recálculo desde Go por lo que
-- ya está escrito en el `CLAUDE.md` §3-sexies —«la regla vive en UN sitio, no en tres»— y
-- por lo que enseñó el §3-bis: lo que se copia a mano en Go es lo que un día se queda sin
-- copiar, con toda la suite en verde. Las paradas de una ruta se mueven desde seis sitios
-- que hoy existen (armar desde Rutas, armar desde el Tablero, cerrar una parada,
-- desmarcarla, soltar la ruta entera al borrarla, y el espejo repasando `weight` y
-- `pedido_costo` cada minuto) y desde los que se inventen mañana, incluido un `UPDATE` a
-- mano por SQL. El trigger los cubre todos; una llamada en Go cubre los que alguien se
-- acuerde de tocar.
--
-- # Qué son «las paradas» de una ruta: `ultima_ruta_id`, no `route_id`
--
-- Es la misma respuesta que ya dieron la aplicación y el post-despacho, y tiene que serlo
-- o vuelven a ser dos preguntas con dos respuestas. Un pedido que NO se entrega suelta su
-- `route_id` al cerrarse la ruta para poder repartirse mañana, pero `ultima_ruta_id` no se
-- suelta nunca: es la hoja de lo que subió al camión. Con `route_id`, una ruta cerrada se
-- iría quedando sin peso según se marcan los devueltos.
--
-- # Lo que esto NO hace
--
--   * **No toca `total_distance`.** Eso no es una suma de las paradas: es el recorrido
--     —los tramos más el regreso al origen— y lo calcula quien arma. Sigue donde estaba.
--   * **No cambia el contrato.** `totalWeight`, `totalPrice` y `paradasSinCotizar` salen
--     por el mismo sitio y con el mismo tipo; lo que cambia es que ahora dicen la verdad.
--   * **No hace nulable `total_price`.** Sigue sin saber decir «no se sabe»; quien lo
--     lee tiene al lado `paradas_sin_cotizar`, que ahora está SIEMPRE puesto (antes el
--     armador del Tablero lo dejaba en NULL y el total parecía completo sin serlo).

-- +goose Up

-- LA ARITMÉTICA, ESCRITA UNA SOLA VEZ.
--
-- Es letra por letra la de la aplicación (`pesoPorRuta` e `importePorRuta`, que agrupan
-- `orders` por `ultima_ruta_id`) y la que hacía Go al armar. Si esto y aquello se separan,
-- el aparato y el servidor dan dos totales de la misma ruta.
--
-- `sin_cotizar` cuenta las paradas SIN `pedido_costo`, y va pegado al importe porque
-- `importe` suma sólo lo que sí está cotizado: sin ese número al lado, un total corto
-- parece completo.
--
-- `STABLE` y no `IMMUTABLE`: lee tablas.
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

-- ESCRIBIR EL ESPEJO. Lo único que escribe estas tres columnas en todo el proyecto.
--
-- `IS DISTINCT FROM` para no tocar la fila cuando ya cuadra: `routes` tiene su
-- `trg_routes_updated`, así que un UPDATE de más movería `updated_at` y la ruta volvería
-- a bajar a todos los aparatos sin haber cambiado nada. Es la misma razón por la que
-- `GuardarPedidoDelEspejo` no toca un pedido que llega igual.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION fijar_espejo_de_totales_de_ruta(ruta uuid) RETURNS void AS $$
    UPDATE routes r
       SET total_weight        = t.peso,
           total_price         = t.importe,
           paradas_sin_cotizar = t.sin_cotizar
      FROM totales_de_ruta(ruta) AS t
     WHERE r.id = ruta
       AND (r.total_weight, r.total_price, r.paradas_sin_cotizar)
           IS DISTINCT FROM (t.peso, t.importe, t.sin_cotizar);
$$ LANGUAGE sql;
-- +goose StatementEnd

-- EL DISPARADOR. Se refrescan las DOS rutas: de la que el pedido se fue y a la que llegó.
--
-- Un pedido que cambia de camión descuadraría la ruta vieja si sólo se mirara la nueva, y
-- ésa es la que nadie va a volver a abrir.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION refrescar_totales_de_ruta() RETURNS trigger AS $$
DECLARE
    vieja uuid;
    nueva uuid;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        vieja := OLD.ultima_ruta_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        nueva := NEW.ultima_ruta_id;
    END IF;

    IF vieja IS NOT NULL THEN
        PERFORM fijar_espejo_de_totales_de_ruta(vieja);
    END IF;
    -- `IS DISTINCT FROM` y no `<>`: con dos nulos, `<>` da NULL y el IF no entra. Aquí
    -- `vieja` es NULL en todos los INSERT, que es el caso más común de todos.
    IF nueva IS NOT NULL AND nueva IS DISTINCT FROM vieja THEN
        PERFORM fijar_espejo_de_totales_de_ruta(nueva);
    END IF;

    RETURN NULL; -- AFTER: lo que devuelva no se usa
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

-- AFTER y no BEFORE: el total se calcula sobre lo que ya está guardado. Con BEFORE, la
-- fila que dispara todavía no está en la tabla y su propio peso no entraría en la suma.
--
-- `UPDATE OF` acota el disparo a las tres columnas que alimentan la cuenta, que es lo que
-- hace que esto no se note: el espejo repasa 5.452 pedidos cada minuto y la inmensa
-- mayoría de sus UPDATE no tocan ninguna de las tres.
--
-- **Esa lista tiene que ser EXACTAMENTE las columnas que lee `totales_de_ruta`.** Si la
-- cuenta pasa a mirar una cuarta y aquí no se añade, el total se congela otra vez para esa
-- cuarta y en silencio, que es el fallo de siempre. Lo ata una prueba, no este comentario
-- (`CLAUDE.md` §3-bis): `internal/store/totales_de_ruta_test.go`.
CREATE TRIGGER trg_orders_totales_de_ruta
    AFTER INSERT OR DELETE OR UPDATE OF ultima_ruta_id, weight, pedido_costo ON orders
    FOR EACH ROW EXECUTE FUNCTION refrescar_totales_de_ruta();

-- Y LAS QUE YA ESTABAN CONGELADAS. Sin esto, el trigger arregla las rutas del futuro y
-- deja mintiendo a todas las de atrás, que son las que alguien exporta.
SELECT fijar_espejo_de_totales_de_ruta(r.id) FROM routes r;

-- +goose Down

-- Se quita el mantenimiento, NO los valores: las columnas se quedan con el último total
-- bueno que calculó el trigger. Volver a escribir ahí el de aquel día es imposible —ese
-- número no está guardado en ningún sitio— y dejarlas en cero sería peor que dejarlas
-- viejas: un cero es una cifra.
DROP TRIGGER IF EXISTS trg_orders_totales_de_ruta ON orders;
DROP FUNCTION IF EXISTS refrescar_totales_de_ruta();
DROP FUNCTION IF EXISTS fijar_espejo_de_totales_de_ruta(uuid);
DROP FUNCTION IF EXISTS totales_de_ruta(uuid);
