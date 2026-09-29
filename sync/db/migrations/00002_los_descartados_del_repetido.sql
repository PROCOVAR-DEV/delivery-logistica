-- QUIÉN SE CAYÓ, para poder repetirlo.
--
-- Un apunte que se aplicó pero cuya respuesta no llegó al aparato vuelve a subir, y el
-- servicio contesta `repetido` con la MISMA respuesta de la primera vez: el mismo id, y el
-- mismo motivo si aquella vez fue un rechazo. Todo menos una cosa — **los descartados**.
--
-- El caso, entero: se arma una zona sin señal con doce pedidos; el apunte sube; el reparto
-- la crea con NUEVE y nombra a los tres que se cayeron; la respuesta se pierde por el
-- camino. El aparato reintenta, aquí se contesta `repetido`… y el aviso de «salió con menos
-- de lo que pusiste» **no va dentro**. La ruta existe arriba con nueve, en el teléfono
-- parece que fue entera, y nadie se entera de los tres.
--
-- Estaba escrito como agujero conocido en `mismaRespuestaQueLaPrimeraVez` desde el día que
-- se hizo. Se tapa el 29/09/2026, con el resto de «nada se descarta en silencio».
--
-- `jsonb` y no `text`: es lo que ya viaja (`sincro.Aplicado.Descartados`), y así la base
-- rechaza un JSON roto en vez de guardarlo para que reviente dentro de un mes en el
-- teléfono de alguien.
--
-- NULO ES LO NORMAL y no significa «ninguno»: significa «este apunte no descartó nada», que
-- es el caso de casi todos. Las filas de antes de esta migración se quedan nulas, y eso es
-- exactamente lo que eran — no se sabía.

-- +goose Up
ALTER TABLE apuntes ADD COLUMN descartados jsonb;

-- +goose Down
ALTER TABLE apuntes DROP COLUMN descartados;
