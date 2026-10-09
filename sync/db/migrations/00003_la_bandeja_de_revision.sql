-- LA BANDEJA DE REVISIÓN — qué pasa con la cola de quien pierde `delivery.entrar`.
--
-- Diseño: ../../../docs/bandeja-de-revision.md (B.2). Quien pierde la llave conserva su cola en el
-- aparato pero sin token no puede subirla. Accesos le da un token de entrega (10 minutos, un solo
-- ámbito) y con él el aparato deja cada apunte AQUÍ, tal como vino, SIN APLICARLO. Lo aplica o lo
-- descarta una persona (S2). Esta migración es sólo la contabilidad: nada de aquí toca pedidos,
-- rutas ni tablero, que son de `reparto-api`.
--
-- LA REGLA QUE MANDA SOBRE TODO ESTO (CLAUDE.md §4): **una decisión de una persona se ESCRIBE, no se
-- borra**. Por eso la base — no sólo el Go — impide:
--   * cualquier DELETE y cualquier TRUNCATE de las tres tablas;
--   * cambiar el ORIGINAL de un apunte entregado (método, ruta, cuerpo, huella, hora del aparato…);
--   * reescribir un apunte ya decidido (`aplicado` o `descartado`);
--   * tocar el libro de decisiones, que SÓLO se añade.
-- y exige que un descarte lleve quién, cuándo y un motivo escrito de verdad.
--
-- Sin claves ajenas hacia el reparto, igual que el resto de este esquema (ver la 00001).

-- +goose Up

-- `en_revision`: entregado, esperando a una persona. `aplicando`: un revisor lo reclamó y se está
-- reenviando al reparto (el candado: dos revisores, un solo ganador). `aplicado`/`descartado`: decisión
-- final. `rechazado`: el reparto dijo que no al aplicar; sigue vivo y a la vista con su motivo literal.
CREATE TYPE revision_estado AS ENUM ('en_revision', 'aplicando', 'aplicado', 'rechazado', 'descartado');

-- ---------------------------------------------------------------------------
-- 1 · Las entregas — una por token de entrega (una pulsación del botón)
-- ---------------------------------------------------------------------------

-- Agrupa y da el contexto: quién entregó (el `sub` y el `name` del token VERIFICADO, nunca del cuerpo),
-- desde qué aparato, y con qué token (su `jti`; el token en sí no se guarda NUNCA, ni cabeceras de
-- autorización). La app manda los apuntes de uno en uno, así que varias peticiones con el mismo token
-- caen en la MISMA entrega: UNIQUE (aparato_id, token_jti).
CREATE TABLE revision_entregas (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aparato_id     uuid NOT NULL REFERENCES aparatos(id) ON DELETE RESTRICT,
    persona        text NOT NULL CHECK (btrim(persona) <> ''),
    persona_nombre text,
    -- La sucursal del aparato, que tiene que ser la del token. Es por la que filtra el revisor.
    branch_id      uuid NOT NULL,
    token_jti      text NOT NULL CHECK (btrim(token_jti) <> ''),
    -- Constancia de auditoría, recortada; no es un dato de seguridad (la IP sale del proxy).
    desde_ip       text,
    agente         text,
    version_app    text,
    entregada_at   timestamptz NOT NULL DEFAULT now(),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (aparato_id, token_jti)
);
CREATE INDEX revision_entregas_persona_idx  ON revision_entregas (persona);
CREATE INDEX revision_entregas_sucursal_idx ON revision_entregas (branch_id);
CREATE TRIGGER trg_revision_entregas_updated BEFORE UPDATE ON revision_entregas
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- 2 · Los apuntes entregados
-- ---------------------------------------------------------------------------

-- Una fila por APUNTE. La primaria compuesta (aparato_id, clave) es la idempotencia, igual que en
-- `apuntes`: entregar dos veces el mismo apunte es una sola fila.
CREATE TABLE revision_apuntes (
    aparato_id  uuid NOT NULL REFERENCES aparatos(id) ON DELETE RESTRICT,
    clave       text NOT NULL CHECK (btrim(clave) <> ''),
    entrega_id  uuid NOT NULL REFERENCES revision_entregas(id) ON DELETE RESTRICT,
    -- Posición FIFO en la cola del aparato: la pone el servidor por orden de llegada (la app manda de
    -- uno en uno y en orden). «Aplicar todo en orden» recorre (entrega_id, orden).
    orden       integer NOT NULL CHECK (orden >= 0),
    metodo      text NOT NULL,
    ruta        text NOT NULL,
    -- TAL CUAL LLEGÓ: los bytes del JSON, nunca re-serializado. Es lo que el revisor ve y lo que se
    -- reenvía; re-serializarlo cambiaría la huella y el original.
    cuerpo      text,
    provisional text,
    -- La hora del APARATO (no la de la entrega, que es `revision_entregas.entregada_at`).
    hecho_at    timestamptz NOT NULL,
    -- sha256 hex del apunte entero (aparato, clave, método, ruta, cuerpo, hecho): reentregar la misma
    -- clave con otro contenido es una `huella_distinta` y no sobrescribe nada.
    huella      text NOT NULL CHECK (huella ~ '^[0-9a-f]{64}$'),
    -- Ayuda de lectura que dice el aparato. NO vale como dato.
    resumen_del_aparato text,

    estado      revision_estado NOT NULL DEFAULT 'en_revision',
    decidido_por        text,
    decidido_por_nombre text,
    decidido_at         timestamptz,
    -- Descartar: el motivo escrito de quien decide. Rechazado: el LITERAL del reparto. Si no, vacío.
    motivo      text,
    id_creado   uuid,
    descartados jsonb,
    intentos    integer NOT NULL DEFAULT 0 CHECK (intentos >= 0),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (aparato_id, clave),

    -- UN DESCARTE SIN MOTIVO NO EXISTE. Ojo con el `coalesce`: un CHECK que da NULL PASA, así que sin
    -- él un descarte con `motivo` NULL entraba (length(btrim(NULL)) >= 5 es NULL, no falso).
    CONSTRAINT revision_descarte_con_motivo CHECK (
        estado <> 'descartado'
        OR (decidido_por IS NOT NULL AND decidido_at IS NOT NULL
            AND length(btrim(coalesce(motivo, ''))) >= 5)),
    CONSTRAINT revision_aplicado_con_dueno CHECK (
        estado <> 'aplicado' OR (decidido_por IS NOT NULL AND decidido_at IS NOT NULL)),
    -- Quien lo está aplicando consta: el otro revisor recibe «ya lo está aplicando X».
    CONSTRAINT revision_aplicando_con_dueno CHECK (
        estado <> 'aplicando' OR (decidido_por IS NOT NULL AND decidido_at IS NOT NULL)),
    -- Un rechazo sin su motivo literal es exactamente el descarte en silencio que esto viene a impedir.
    CONSTRAINT revision_rechazado_con_motivo CHECK (
        estado <> 'rechazado' OR length(btrim(coalesce(motivo, ''))) >= 1)
);
-- Lo que sigue esperando a una persona, en orden. Parcial: lo decidido ya no se recorre.
CREATE INDEX revision_pendientes_idx ON revision_apuntes (entrega_id, orden)
    WHERE estado IN ('en_revision', 'aplicando', 'rechazado');
-- «¿Qué ha pasado con lo mío?» — `GET /sync/revision/mias`.
CREATE INDEX revision_apuntes_aparato_idx ON revision_apuntes (aparato_id, orden);
CREATE TRIGGER trg_revision_apuntes_updated BEFORE UPDATE ON revision_apuntes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- 3 · El libro de decisiones — SÓLO se añade
-- ---------------------------------------------------------------------------

-- Cada intento de aplicar y cada descarte, con quién, cuándo y cómo acabó. `caida` es un 5xx o un corte
-- de red al aplicar (el apunte vuelve a `en_revision` y no es un rechazo); `interrumpido`, un proceso
-- que murió con el apunte en `aplicando`.
CREATE TABLE revision_decisiones (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aparato_id  uuid NOT NULL,
    clave       text NOT NULL,
    accion      text NOT NULL CHECK (accion IN ('aplicar', 'descartar')),
    por         text NOT NULL CHECK (btrim(por) <> ''),
    por_nombre  text,
    rol         text,
    resultado   text NOT NULL CHECK (resultado IN ('aplicado', 'rechazado', 'descartado', 'interrumpido', 'caida')),
    http_estado integer,
    motivo      text,
    -- `clock_timestamp()` y no `now()`: dentro de una transacción `now()` es SIEMPRE el mismo instante, y varias
    -- decisiones seguidas (un «aplicar todo en orden») empatarían y saldrían del libro en cualquier orden.
    cuando      timestamptz NOT NULL DEFAULT clock_timestamp(),
    FOREIGN KEY (aparato_id, clave) REFERENCES revision_apuntes (aparato_id, clave)
);
CREATE INDEX revision_decisiones_apunte_idx ON revision_decisiones (aparato_id, clave, cuando);

-- ---------------------------------------------------------------------------
-- 4 · Lo que la base impide aunque el Go se equivoque
-- ---------------------------------------------------------------------------

-- Ni DELETE ni TRUNCATE, en ninguna de las tres. SQLSTATE 23001 (restrict_violation).
-- +goose StatementBegin
CREATE FUNCTION revision_no_se_borra() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'la bandeja de revisión no se borra (%): una decisión de una persona se ESCRIBE, no se borra', TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER trg_revision_entregas_no_delete BEFORE DELETE ON revision_entregas
    FOR EACH ROW EXECUTE FUNCTION revision_no_se_borra();
CREATE TRIGGER trg_revision_apuntes_no_delete BEFORE DELETE ON revision_apuntes
    FOR EACH ROW EXECUTE FUNCTION revision_no_se_borra();
CREATE TRIGGER trg_revision_decisiones_no_delete BEFORE DELETE ON revision_decisiones
    FOR EACH ROW EXECUTE FUNCTION revision_no_se_borra();
CREATE TRIGGER trg_revision_entregas_no_truncate BEFORE TRUNCATE ON revision_entregas
    FOR EACH STATEMENT EXECUTE FUNCTION revision_no_se_borra();
CREATE TRIGGER trg_revision_apuntes_no_truncate BEFORE TRUNCATE ON revision_apuntes
    FOR EACH STATEMENT EXECUTE FUNCTION revision_no_se_borra();
CREATE TRIGGER trg_revision_decisiones_no_truncate BEFORE TRUNCATE ON revision_decisiones
    FOR EACH STATEMENT EXECUTE FUNCTION revision_no_se_borra();

-- El libro de decisiones no se corrige: se añade otra línea.
-- +goose StatementBegin
CREATE FUNCTION revision_decisiones_solo_se_anade() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'el libro de decisiones sólo se añade: una decisión no se reescribe'
        USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd
CREATE TRIGGER trg_revision_decisiones_no_update BEFORE UPDATE ON revision_decisiones
    FOR EACH ROW EXECUTE FUNCTION revision_decisiones_solo_se_anade();

-- EL ORIGINAL NO SE CAMBIA. De un apunte sólo se mueven las columnas de la decisión (estado, quién,
-- cuándo, motivo, lo que creó, los intentos); todo lo demás —método, ruta, cuerpo, huella, hora del
-- aparato, a qué entrega pertenece— es el original y es inmutable. Se escribe como LISTA BLANCA de lo
-- que sí se mueve, no como lista negra de lo que no: una columna nueva nace inmutable.
-- Y un apunte YA DECIDIDO (`aplicado`, `descartado`) no cambia en nada: la decisión se escribió.
-- +goose StatementBegin
CREATE FUNCTION revision_apuntes_original_intacto() RETURNS trigger AS $$
DECLARE
    movibles text[] := ARRAY['estado', 'decidido_por', 'decidido_por_nombre', 'decidido_at', 'motivo',
                             'id_creado', 'descartados', 'intentos', 'updated_at'];
BEGIN
    IF (to_jsonb(NEW) - movibles) IS DISTINCT FROM (to_jsonb(OLD) - movibles) THEN
        RAISE EXCEPTION 'el original de un apunte entregado no se cambia (%, %)', OLD.aparato_id, OLD.clave
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.estado IN ('aplicado', 'descartado')
       AND (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
        RAISE EXCEPTION 'un apunte ya % no se reescribe (%, %)', OLD.estado, OLD.aparato_id, OLD.clave
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd
CREATE TRIGGER trg_revision_apuntes_original BEFORE UPDATE ON revision_apuntes
    FOR EACH ROW EXECUTE FUNCTION revision_apuntes_original_intacto();

-- Lo mismo con quién entregó y con qué token: la constancia no se reescribe.
-- +goose StatementBegin
CREATE FUNCTION revision_entregas_original_intacto() RETURNS trigger AS $$
BEGIN
    IF (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
        RAISE EXCEPTION 'quién entregó, desde dónde y con qué token no se cambia (%)', OLD.id
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd
CREATE TRIGGER trg_revision_entregas_original BEFORE UPDATE ON revision_entregas
    FOR EACH ROW EXECUTE FUNCTION revision_entregas_original_intacto();

-- +goose Down
DROP TABLE IF EXISTS revision_decisiones, revision_apuntes, revision_entregas CASCADE;
DROP FUNCTION IF EXISTS revision_entregas_original_intacto();
DROP FUNCTION IF EXISTS revision_apuntes_original_intacto();
DROP FUNCTION IF EXISTS revision_decisiones_solo_se_anade();
DROP FUNCTION IF EXISTS revision_no_se_borra();
DROP TYPE IF EXISTS revision_estado;
