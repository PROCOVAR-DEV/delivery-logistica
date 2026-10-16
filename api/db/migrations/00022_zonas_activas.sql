-- +goose Up
-- INACTIVAR UNA ZONA DEL TABLERO (Jose, 16/10/2026, versión 1.0.38): una zona que hoy no se usa
-- se apaga en vez de borrarse, y se enciende cuando vuelve a hacer falta.
--
-- Una zona inactiva no se lista (ni en `GET /api/board` ni en la bajada del aparato, salvo
-- `?incluirInactivas=1`), no admite tarjetas, no arma rutas y no es destino de un mover. Al
-- inactivarla sus pedidos vuelven a «Sin colocar» (lo hace la API, en la misma transacción).
--
-- Entra en TRUE: ninguna zona existente cambia de estado al desplegar. Es la misma forma que
-- `vehicles.is_active` (00017) —un booleano a secas, sin fecha ni motivo—.
ALTER TABLE board_columns
    ADD COLUMN activa boolean NOT NULL DEFAULT true;

-- +goose Down
-- Las zonas inactivas vuelven a salir en todas partes (el resto de la API anterior no sabe de
-- esta columna). Los pedidos que se devolvieron a «Sin colocar» no vuelven a su zona.
ALTER TABLE board_columns DROP COLUMN activa;
