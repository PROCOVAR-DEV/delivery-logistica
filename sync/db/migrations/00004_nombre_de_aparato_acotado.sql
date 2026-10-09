-- EL NOMBRE DE UN APARATO TIENE TOPE (auditoría de seguridad, 09/10/2026, M3).
--
-- `aparatos.nombre` es texto que manda el aparato al darse de alta ("el Samsung de Palma") y no tenía tope:
-- el alta lo leía de un cuerpo de hasta 32 MiB y lo guardaba entero, y el panel y la bandeja del revisor lo
-- devolvían entero a quien lo mirara. `POST /sync/aparato` ahora lo limpia y lo recorta a 80 letras
-- (`limpio(…, 80)`); esto es la red debajo, para que ni un alta torcida ni una mano en la base lo desborden.
--
-- Los nombres que YA estén guardados por encima de 200 letras se recortan aquí mismo (`left(nombre, 200)`):
-- es el rótulo que el aparato se puso a sí mismo, no una decisión de una persona, y dejarlos largos haría
-- fallar TODO `UPDATE` de esa fila (`TocarAparato` mueve `visto_at` en cada subida, y si falla sólo avisa:
-- el panel de «horas sin subir» mentiría para ese aparato). El recorte NO se deshace con el `down`.
--
-- NOT VALID sigue puesto para que la migración no dependa de una carrera con un alta que llegue en este
-- mismo instante desde el binario viejo: la restricción se exige a todo lo que se escriba desde ahora, y las
-- consultas de la bandeja recortan al leer (`left(…, 200)`) por si una mano la quitó y coló uno largo.
--
-- Esta migración es NUEVA: la 00003 (la bandeja) no se edita.

-- +goose Up
UPDATE aparatos SET nombre = left(nombre, 200) WHERE char_length(nombre) > 200;

ALTER TABLE aparatos
    ADD CONSTRAINT aparatos_nombre_acotado CHECK (char_length(nombre) <= 200) NOT VALID;

-- +goose Down
ALTER TABLE aparatos DROP CONSTRAINT IF EXISTS aparatos_nombre_acotado;
