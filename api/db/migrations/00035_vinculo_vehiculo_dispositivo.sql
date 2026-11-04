-- +goose Up
--
-- EL VEHÍCULO SE VINCULA AL TELÉFONO — Jose, 04/11/2026.
--
-- «El link debe mandar el vehículo que se usa para eso y ese vehículo se vincula a ese dispositivo, pero se puede quitar de ese dispositivo,
-- desvincularlo desde Reparto para agregar otro. Desvincularlo quitará toda la información del dispositivo en la APK y se quedará vacía, pero
-- nosotros en servidor mantendremos todo con el id del dispositivo y así estaremos guardando históricos.»
--
--  * Un vínculo vivo (`hasta IS NULL`) une UN vehículo con UN teléfono: ni el vehículo puede estar en dos teléfonos, ni el teléfono en dos vehículos.
--  * Desvincular cierra el vínculo (`hasta`, quién, motivo). NO se borra nada: las rutas completadas conservan su `dispositivo_id`, los puntos de GPS
--    su `dispositivo_id` y el vínculo queda de historia. Las rutas planificadas o en curso del teléfono se sueltan (y sus enlaces se revocan) para
--    mandarlas a otro con un enlace nuevo.
--  * El acceso del teléfono lleva el id de SU vínculo (claim `vinculo`): al cerrarse, el token deja de valer (403 `dispositivo_desvinculado`) y la
--    APK se vacía. Un vínculo nuevo es un token nuevo.

CREATE TABLE vinculos_vehiculo_dispositivo (
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    vehicle_id       uuid NOT NULL REFERENCES vehicles (id),
    dispositivo_id   uuid NOT NULL REFERENCES dispositivos_distribuidor (id),
    branch_id        uuid NOT NULL REFERENCES branches (id),
    desde            timestamptz NOT NULL DEFAULT now(),
    hasta            timestamptz,
    vinculado_por    text,
    desvinculado_por text,
    motivo           text,
    CHECK (hasta IS NULL OR hasta >= desde)
);
CREATE UNIQUE INDEX vinculos_un_vehiculo_vivo   ON vinculos_vehiculo_dispositivo (vehicle_id)     WHERE hasta IS NULL;
CREATE UNIQUE INDEX vinculos_un_dispositivo_vivo ON vinculos_vehiculo_dispositivo (dispositivo_id) WHERE hasta IS NULL;
CREATE INDEX vinculos_por_vehiculo ON vinculos_vehiculo_dispositivo (vehicle_id, desde DESC);

-- +goose Down
DROP TABLE IF EXISTS vinculos_vehiculo_dispositivo;
