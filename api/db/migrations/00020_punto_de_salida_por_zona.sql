-- +goose Up
-- EL PUNTO DE SALIDA DE CADA ZONA (Jose, 15/10/2026): «para cambiar el destino de un tablero lo
-- cambiamos arriba; quisiera que cada columna se pudiera configurar de dónde sale, así los
-- tableros quedan preparados para cada punto o almacén sin estar cambiando de lado a lado».
--
-- Es el id del ALMACÉN DE ACCESOS, tal como llega en `/api/service/almacenes` (y en la colección
-- `almacenes` del aparato). Texto y NO clave ajena: el almacén vive en Accesos y aquí no se copia
-- (tablero.md §3, «De dónde sale la distancia»). Que sea de la sucursal de la zona lo comprueba la
-- API al escribirlo y otra vez al armar la ruta, contra la lista viva de Accesos.
--
-- NULO = lo de antes de esta migración: la zona sale del almacén principal de la sucursal
-- (`cotizar.ElegirAlmacen`). Por eso entra nula y no se rellena: ninguna zona cambia de punto de
-- salida al desplegar.
ALTER TABLE board_columns
    ADD COLUMN almacen_id text CHECK (almacen_id IS NULL OR btrim(almacen_id) <> '');

-- +goose Down
-- Pierde el punto de salida que cada zona tuviera puesto; todas vuelven a salir del principal,
-- que es lo que hace la API anterior.
ALTER TABLE board_columns DROP COLUMN almacen_id;
