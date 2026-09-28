-- EL CAMIÓN EN EL TALLER: el único estado de la flota que NO se puede deducir.
--
-- Jose dijo que sí a «en mantenimiento» el 28/09/2026, y esta migración es lo único que
-- faltaba en la base. Todo lo demás del estado de la flota se dedujo el mismo día y **no
-- lleva ni un campo nuevo**: `libre`, `asignado` (tiene una ruta planificada) y `enRuta`
-- (tiene una en curso) salen de las rutas abiertas del camión
-- (`db/queries/vehicles.sql`, `RutasAbiertasDeLaFlota`). El porqué de deducirlo está
-- escrito ahí y viene de más atrás, de `ContarVehiculosEnRuta`: «se mira la ruta y no
-- `vehicles.status` porque el estado es un campo que alguien puede haber dejado a mano en
-- `available` con la ruta todavía abierta». Un campo que nadie mantiene miente a los dos
-- días.
--
-- El taller es la excepción, y es una excepción de verdad, no una comodidad: **un camión
-- en el taller no tiene ruta, exactamente igual que uno libre**. No hay ninguna fila en
-- ninguna tabla que los distinga, así que o alguien lo dice o no se sabe. Por eso este
-- valor sí se guarda, y por eso es el ÚNICO que se guarda.
--
-- # Lo que NO se hace aquí, y a propósito
--
--   * **Ninguna columna nueva.** El motivo del taller va en `vehicles.notes`, que ya
--     existe desde 00001 y nadie estaba usando para nada mejor.
--   * **Ningún «de baja» ni ningún `activo`.** Un camión que ya no está se borra o se saca
--     de su sucursal. Una bandera más que nadie mantiene miente a los dos días, que es
--     justo el problema que todo esto viene a quitar.
--
-- # POR QUÉ `NO TRANSACTION`
--
-- Un valor nuevo de un enum **no se puede usar en la misma transacción en que se añade**.
-- En Postgres 12+ el `ALTER TYPE ... ADD VALUE` sí entra dentro de una transacción, pero
-- el valor no queda visible hasta que esa transacción confirma: cualquier `UPDATE`,
-- `INSERT` o `CHECK` que lo nombrara a continuación reventaría con
-- «unsafe use of new value of enum type». goose mete cada migración en una transacción
-- salvo que se le diga lo contrario, así que esta va fuera, sola y sin nada más dentro —
-- igual que la 00008, por otro motivo (ver `docs/despliegue.md` §2.5).
--
-- Como va fuera de transacción, esta migración **no es atómica**. No importa: es una sola
-- sentencia idempotente (`IF NOT EXISTS`). Relanzarla no hace nada.
--
-- ===========================================================================
-- EL `Down`: EN POSTGRES UN VALOR DE UN ENUM NO SE PUEDE QUITAR
-- ===========================================================================
--
-- No existe `ALTER TYPE ... DROP VALUE`, ni en 16 ni en 17. Las dos únicas salidas eran:
--
--   (a) un `Down` que no quita el valor, dicho con todas las letras; o
--   (b) recrear el tipo entero: renombrar el viejo, crear uno nuevo con los dos valores de
--       siempre, pasar `vehicles.status` al nuevo con un `USING`, devolver el `DEFAULT` y
--       tirar el viejo.
--
-- **Se elige (a), y el motivo no es la pereza: es que (b) no puede hacerse sin mentir.**
--
-- El `USING (status::text::vehicle_status)` de (b) revienta en cuanto haya UNA fila en
-- `maintenance` —«invalid input value for enum»—, así que para que (b) funcione hay que
-- poner delante un `UPDATE vehicles SET status = 'available' WHERE status = 'maintenance'`.
-- Y eso es exactamente lo que este proyecto no hace: **convierte «está en el taller» en
-- «está libre»**, en silencio, y el camión vuelve a salir ofrecido en el desplegable del
-- asistente y en el «Camión previsto» del tablero. Un dato creíble y equivocado sobre un
-- camión que no puede salir, que es la forma que tiene aquí de salir caro. Una vuelta
-- atrás del ESQUEMA no puede decidir por nadie qué pasa con un camión que está en el
-- taller de verdad.
--
-- Y hay más, todo en contra de (b): reescribe `vehicles` entera con un candado
-- ACCESS EXCLUSIVE (la URL de las migraciones lleva `lock_timeout=5s`, así que con una
-- transacción abierta de la api se cae), hay que acordarse de quitar y devolver el
-- `DEFAULT 'available'` —si no, el `ALTER COLUMN TYPE` falla— y los siete triggers de
-- 00006 miran esa tabla.
--
-- LO QUE CUESTA (a), dicho también: la base se queda con un valor de enum que ninguna fila
-- usa y que ningún código escribe. Es inofensivo. Quien decide qué se puede guardar NO es
-- el tipo, es `estadoValido` (`internal/api/vehiculos.go`), y la versión anterior de la api
-- contesta 400 a `maintenance` como contestaba antes. O sea: **volver atrás el código basta;
-- el tipo sobrante no se ve más que en un `\dT+ vehicle_status`.**
--
-- Y PARA QUE NADIE LEA «OK» COMO «volvió atrás», el `Down` de abajo hace dos cosas:
--
--   1. Si hay camiones marcados `maintenance`, **se niega** con un error que dice cuántos
--      son y qué hay que decidir. Esa decisión —¿este camión está libre, o sigue roto y
--      hay que sacarlo de la sucursal?— la toma una persona mirando, no una vuelta atrás.
--      `docs/despliegue.md` §2.7 ya lo dice: «`ACCION=down` existe porque goose lo tiene.
--      En producción no se usa: deshacer una migración sobre datos reales se decide
--      mirando».
--   2. Si no hay ninguno, avisa de que el valor SE QUEDA en el tipo y sigue adelante, para
--      no atascar la vuelta atrás de todo lo que haya por debajo.

-- +goose NO TRANSACTION
-- +goose Up
ALTER TYPE vehicle_status ADD VALUE IF NOT EXISTS 'maintenance';

-- +goose Down
-- No hay `DROP VALUE` en Postgres. Ver el bloque de arriba: esto NO deshace el `ADD VALUE`
-- y no puede hacerlo. Lo que sí hace es no dejar que se dé por deshecho.
-- +goose StatementBegin
DO $$
DECLARE en_el_taller bigint;
BEGIN
    SELECT count(*) INTO en_el_taller FROM vehicles WHERE status = 'maintenance';

    IF en_el_taller > 0 THEN
        RAISE EXCEPTION
            'hay % camión(es) marcados «maintenance» y esta vuelta atrás no puede decidir qué son', en_el_taller
            USING HINT =
                'Un valor de enum no se puede quitar en Postgres, así que lo único que haría '
                'este Down es dejar esas filas apuntando a un valor que el código de antes '
                'rechaza. Pasarlas a «available» a escondidas sería decir que esos camiones '
                'están libres, y volverían a salir ofrecidos en el asistente de Rutas y en el '
                '«Camión previsto» del tablero. Míralos uno por uno (SELECT id, name, notes '
                'FROM vehicles WHERE status = ''maintenance''), decide si vuelven a estar '
                'disponibles o si hay que sacarlos de su sucursal, ponlo a mano, y vuelve a '
                'lanzar el down.';
    END IF;

    RAISE WARNING
        'el valor «maintenance» SE QUEDA en el tipo vehicle_status: Postgres no sabe quitar un valor de un enum'
        USING HINT =
            'No hace daño: quien decide qué se puede guardar es estadoValido, en '
            'internal/api/vehiculos.go, y la api anterior contesta 400 a «maintenance». '
            'El único rastro es un \dT+ vehicle_status con tres valores en vez de dos.';
END
$$;
-- +goose StatementEnd
