-- Clientes: espejo de Ventra vía PEDIDO. Sólo los GEOLOCALIZADOS — sin coordenadas no se
-- cotiza y no hay parada que visitar.
--
-- EL ALCANCE AQUÍ VA POR CÓDIGO, NO POR `branch_id`.
--
-- `customers` no tiene `branch_id`: tiene `sucursal_codigo`, que es el código de Ventra
-- (CAM, HAB, STG...). Quien llama traduce su sucursal a código —`branches.external_id`—
-- y lo pasa en `sucursal_del_alcance`. El filtro deja pasar además los clientes SIN
-- código: son los que no vinieron de ninguna sucursal concreta, y esconderlos haría
-- desaparecer clientes que sí se atienden, sin decir nada.
--
-- Si la sucursal del alcance NO tiene `external_id`, el llamante debe pasar NULL aquí:
-- pasar el uuid de la sucursal como si fuera un código no da error, da CERO CLIENTES.

-- ---------------------------------------------------------------------------
-- La lista  (GET /api/customers)
-- ---------------------------------------------------------------------------

-- La página de clientes con todos sus filtros.
--
-- El filtro por distancia va en DOS pasos y sólo el primero está aquí: la CAJA
-- (`lat`/`lng` entre unos grados) es lo único que un índice puede resolver. La distancia
-- exacta se calcula después, sólo sobre las 50 filas de la página. Meter el haversine en
-- el WHERE obliga a recorrer los siete mil clientes fila a fila en cada búsqueda.
-- Los grados vienen ya calculados de Go: `km/111` en latitud y `km/(111*cos(lat))` en
-- longitud, que es donde el meridiano se estrecha.
-- name: ListarClientes :many
SELECT
    c.id, c.source, c.external_id, c.name, c.phone, c.address, c.municipio,
    c.zona, c.lat, c.lng, c.sucursal_codigo, c.codigo, c.vendedor, c.synced_at
FROM customers c
WHERE
    -- alcance por sucursal, traducido a código; los manuales (sin código) se ven siempre
    (sqlc.narg('sucursal_del_alcance')::text IS NULL
     OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
     OR c.sucursal_codigo IS NULL)
    -- filtro de la query: estrecha dentro del alcance, nunca lo amplía
    AND (sqlc.narg('sucursal_codigo')::text IS NULL
         OR c.sucursal_codigo = sqlc.narg('sucursal_codigo')::text)
    AND (
        sqlc.narg('q')::text IS NULL
        OR c.name      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.address   ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.municipio ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.zona      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.phone     ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.codigo    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.vendedor  ILIKE '%' || sqlc.narg('q')::text || '%'
    )
    AND (sqlc.narg('municipio')::text IS NULL OR c.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('zona')::text      IS NULL OR c.zona      = sqlc.narg('zona')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR c.vendedor  = sqlc.narg('vendedor')::text)
    -- `origen`: 'pedido' = vino del espejo; 'manual' = alta a mano, que es `source` NULL.
    -- NULL no se compara con `=`, así que la rama del manual se nombra a mano o no sale.
    AND (
        sqlc.narg('origen')::text IS NULL
        OR (sqlc.narg('origen')::text = 'pedido' AND c.source = 'pedido')
        OR (sqlc.narg('origen')::text = 'manual' AND c.source IS NULL)
    )
    -- «Sin teléfono» incluye la cadena vacía: un campo en blanco no es un teléfono.
    AND (
        sqlc.narg('con_telefono')::boolean IS NULL
        OR (sqlc.narg('con_telefono')::boolean AND c.phone IS NOT NULL AND c.phone <> '')
        OR (NOT sqlc.narg('con_telefono')::boolean AND (c.phone IS NULL OR c.phone = ''))
    )
    -- caja previa del filtro por kilómetros (el haversine exacto va después, en Go)
    AND (sqlc.narg('lat_min')::double precision IS NULL OR c.lat >= sqlc.narg('lat_min')::double precision)
    AND (sqlc.narg('lat_max')::double precision IS NULL OR c.lat <= sqlc.narg('lat_max')::double precision)
    AND (sqlc.narg('lng_min')::double precision IS NULL OR c.lng >= sqlc.narg('lng_min')::double precision)
    AND (sqlc.narg('lng_max')::double precision IS NULL OR c.lng <= sqlc.narg('lng_max')::double precision)
ORDER BY c.name ASC
-- ESTA CONSULTA ES LA DE LA PANTALLA. El `OFFSET` es el de sus páginas y el orden es el
-- alfabético, que es como se busca a ojo. **No sirve para la bajada del aparato**: ahí el
-- orden tiene que ser el de la marca, o «los 2.000 primeros» son 2.000 cualesquiera y no
-- hay última fila servida que devolver como `hasta`. La bajada va por
-- `DiferenciasDeClientes`, más abajo.
LIMIT sqlc.arg('limite') OFFSET sqlc.arg('desplazamiento');

-- ---------------------------------------------------------------------------
-- El padrón de la bajada del aparato  (GET /api/sync/cambios)
-- ---------------------------------------------------------------------------

-- Lo que cambió en el padrón, ORDENADO POR LA MARCA y acotado por un cursor.
--
-- LA MISMA FORMA QUE `DiferenciasDePedidos`, copiada y no reinventada. El 15/09/2026 la
-- bajada dejó **2.000 clientes redondos de 8.034** en el aparato y se dio por buena: se
-- servían los primeros por nombre, se marcaba `truncado` y se devolvía el reloj como
-- `hasta`, así que lo que no cupo quedó por debajo del siguiente `desde` y no lo volvió a
-- pedir nadie. Con el orden por la marca, quien contesta puede devolver la marca de la
-- ÚLTIMA FILA SERVIDA y la tanda siguiente empieza justo ahí.
--
-- EL CURSOR LLEVA MARCA **E ID**, y aquí es donde de verdad hace falta: el traspaso metió
-- los 7.975 clientes de producción en UNA transacción, y `now()` es la del inicio de la
-- transacción — los 7.975 comparten `synced_at` al microsegundo. Con un cursor de sólo
-- marca, un grupo más grande que el tope no se puede servir entero: o se repite para
-- siempre o se salta el resto. Con `(marca, id)` la tanda siguiente empieza exactamente
-- donde acabó la anterior.
--
-- `synced_at` y no `updated_at`, igual que antes: es lo que significa «cuándo lo trajo
-- PEDIDO», que es lo que cambia cuando cambia un cliente.
--
-- El alcance es el mismo que el de la pantalla, incluida la rama de los manuales (sin
-- código de sucursal, los ve todo el mundo). Acotar distinto la bajada que la lista es
-- cómo se le queda a un aparato un cliente que ya no es suyo.
-- name: DiferenciasDeClientes :many
SELECT
    c.id, c.source, c.external_id, c.name, c.phone, c.address, c.municipio,
    c.zona, c.lat, c.lng, c.sucursal_codigo, c.codigo, c.vendedor, c.synced_at
FROM customers c
WHERE
    (sqlc.narg('sucursal_del_alcance')::text IS NULL
     OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
     OR c.sucursal_codigo IS NULL)
    -- `desde` ESTRICTO y `hasta` INCLUSIVO. `hasta` hace falta: sin él se sirven filas por
    -- encima de la ventana y el corte devuelve una marca mayor que el `hasta` de la
    -- respuesta, que es otra forma de dejar filas debajo de la raya.
    AND (sqlc.narg('desde')::timestamptz IS NULL OR c.synced_at > sqlc.narg('desde')::timestamptz)
    AND (sqlc.narg('hasta')::timestamptz IS NULL OR c.synced_at <= sqlc.narg('hasta')::timestamptz)
    AND (
        sqlc.narg('cursor_marca')::timestamptz IS NULL
        OR c.synced_at > sqlc.narg('cursor_marca')::timestamptz
        OR (c.synced_at = sqlc.narg('cursor_marca')::timestamptz
            AND c.id > sqlc.narg('cursor_id')::uuid)
    )
ORDER BY c.synced_at ASC, c.id ASC
LIMIT sqlc.arg('tope');

-- El total, con el MISMO where. Es el `total` de la respuesta: se cuenta antes del filtro
-- de distancia exacto, igual que en el contrato, y por eso puede ser mayor que `count`.
-- name: ContarClientes :one
SELECT count(*)
FROM customers c
WHERE
    (sqlc.narg('sucursal_del_alcance')::text IS NULL
     OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
     OR c.sucursal_codigo IS NULL)
    AND (sqlc.narg('sucursal_codigo')::text IS NULL
         OR c.sucursal_codigo = sqlc.narg('sucursal_codigo')::text)
    AND (
        sqlc.narg('q')::text IS NULL
        OR c.name      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.address   ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.municipio ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.zona      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.phone     ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.codigo    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR c.vendedor  ILIKE '%' || sqlc.narg('q')::text || '%'
    )
    AND (sqlc.narg('municipio')::text IS NULL OR c.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('zona')::text      IS NULL OR c.zona      = sqlc.narg('zona')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR c.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('origen')::text IS NULL
        OR (sqlc.narg('origen')::text = 'pedido' AND c.source = 'pedido')
        OR (sqlc.narg('origen')::text = 'manual' AND c.source IS NULL)
    )
    AND (
        sqlc.narg('con_telefono')::boolean IS NULL
        OR (sqlc.narg('con_telefono')::boolean AND c.phone IS NOT NULL AND c.phone <> '')
        OR (NOT sqlc.narg('con_telefono')::boolean AND (c.phone IS NULL OR c.phone = ''))
    )
    AND (sqlc.narg('lat_min')::double precision IS NULL OR c.lat >= sqlc.narg('lat_min')::double precision)
    AND (sqlc.narg('lat_max')::double precision IS NULL OR c.lat <= sqlc.narg('lat_max')::double precision)
    AND (sqlc.narg('lng_min')::double precision IS NULL OR c.lng >= sqlc.narg('lng_min')::double precision)
    AND (sqlc.narg('lng_max')::double precision IS NULL OR c.lng <= sqlc.narg('lng_max')::double precision);

-- ---------------------------------------------------------------------------
-- Facetas de clientes
-- ---------------------------------------------------------------------------
--
-- Se calculan sobre TODO el alcance y SIN los filtros de búsqueda, a propósito: los
-- desplegables tienen que seguir ofreciendo a dónde ir después de filtrar. Si se
-- recalcularan con la búsqueda puesta, cada filtro dejaría los demás con una sola opción
-- —la ya elegida— y no habría forma de cambiar de idea sin borrarlo todo.

-- name: FacetasClientesMunicipios :many
SELECT c.municipio AS valor, count(*) AS clientes
FROM customers c
WHERE c.municipio IS NOT NULL
  AND (sqlc.narg('sucursal_del_alcance')::text IS NULL
       OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
       OR c.sucursal_codigo IS NULL)
GROUP BY c.municipio
ORDER BY c.municipio ASC;

-- name: FacetasClientesZonas :many
SELECT c.zona AS valor, count(*) AS clientes
FROM customers c
WHERE c.zona IS NOT NULL
  AND (sqlc.narg('sucursal_del_alcance')::text IS NULL
       OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
       OR c.sucursal_codigo IS NULL)
GROUP BY c.zona
ORDER BY c.zona ASC;

-- name: FacetasClientesVendedores :many
SELECT c.vendedor AS valor, count(*) AS clientes
FROM customers c
WHERE c.vendedor IS NOT NULL
  AND (sqlc.narg('sucursal_del_alcance')::text IS NULL
       OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
       OR c.sucursal_codigo IS NULL)
GROUP BY c.vendedor
ORDER BY c.vendedor ASC;

-- name: FacetasClientesSucursales :many
SELECT c.sucursal_codigo AS valor, count(*) AS clientes
FROM customers c
WHERE c.sucursal_codigo IS NOT NULL
  AND (sqlc.narg('sucursal_del_alcance')::text IS NULL
       OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
       OR c.sucursal_codigo IS NULL)
GROUP BY c.sucursal_codigo
ORDER BY c.sucursal_codigo ASC;

-- Cuántos no tienen a quién llamar. Es un aviso de calidad del espejo, no un filtro más:
-- un cliente sin teléfono es una entrega que, si falla, no se puede avisar.
-- name: ContarClientesSinTelefono :one
SELECT count(*)
FROM customers c
WHERE (c.phone IS NULL OR c.phone = '')
  AND (sqlc.narg('sucursal_del_alcance')::text IS NULL
       OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
       OR c.sucursal_codigo IS NULL);

-- ---------------------------------------------------------------------------
-- Un cliente suelto y el espejo
-- ---------------------------------------------------------------------------

-- name: ObtenerCliente :one
SELECT
    c.id, c.source, c.external_id, c.name, c.phone, c.address, c.municipio,
    c.zona, c.codigo, c.vendedor, c.lat, c.lng, c.sucursal_codigo,
    c.synced_at, c.created_at, c.updated_at
FROM customers c
WHERE c.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal_del_alcance')::text IS NULL
       OR c.sucursal_codigo = sqlc.narg('sucursal_del_alcance')::text
       OR c.sucursal_codigo IS NULL);

-- Idempotencia del espejo: `source` + `external_id` es lo que reconoce a un cliente entre
-- pasadas. Sin alcance — el espejo entra con clave de servicio y trae las ocho sucursales.
--
-- UNA SOLA CONSULTA CON `ON CONFLICT`, como en pedidos: `customers_origen_idx` es ÚNICO
-- parcial, y con buscar-y-escribir dos pasadas a la vez crean el mismo cliente dos veces
-- —las dos leen «no existe» antes de que ninguna escriba—. El `WHERE` repite el del índice
-- parcial porque si no Postgres no sabe qué índice inferir.
--
-- `synced_at` es «cuándo lo trajo el origen» y NO es `updated_at`, que lo mueve el trigger
-- al tocar la fila. Confundirlas rompe el espejo: la segunda cambia aunque el dato de
-- Ventra sea de hace tres días porque la VPN lleva caída desde el lunes.
-- name: GuardarClienteDelEspejo :one
INSERT INTO customers (
    source, external_id, name, phone, address, municipio, zona, codigo,
    vendedor, lat, lng, sucursal_codigo, synced_at
) VALUES (
    sqlc.arg('source'), sqlc.narg('external_id'), sqlc.arg('name'), sqlc.narg('phone'),
    sqlc.narg('address'), sqlc.narg('municipio'), sqlc.narg('zona'), sqlc.narg('codigo'),
    sqlc.narg('vendedor'), sqlc.arg('lat'), sqlc.arg('lng'),
    sqlc.narg('sucursal_codigo'), now()
)
ON CONFLICT (source, external_id) WHERE source IS NOT NULL AND external_id IS NOT NULL
DO UPDATE SET
    name            = excluded.name,
    phone           = excluded.phone,
    address         = excluded.address,
    municipio       = excluded.municipio,
    zona            = excluded.zona,
    codigo          = excluded.codigo,
    vendedor        = excluded.vendedor,
    lat             = excluded.lat,
    lng             = excluded.lng,
    sucursal_codigo = excluded.sucursal_codigo,
    synced_at       = now()
-- UNA FILA QUE LLEGA IGUAL NO SE TOCA.
--
-- Esta línea es la que arregla el número más gordo del servidor. Medido el 26/09/2026 en
-- la base de producción:
--
--     customers   8.673 filas  ·  98.037.974 actualizaciones
--
-- **Cada cliente reescrito unas once mil veces con exactamente lo mismo.** El espejo
-- repasa cada minuto, sucursal por sucursal, y además siempre los últimos tres días: sin
-- esta guarda, cada repaso vuelve a escribir las 8.673 filas aunque no haya cambiado
-- nada. Eso es el 36 % de la CPU del Postgres con el servidor parado y nadie trabajando,
-- y arrastra al resto: la búsqueda de pedidos figuraba como la consulta más cara —27
-- horas de CPU acumuladas— cuando medida sola tarda 23 ms. No es lenta: es que compite.
--
-- Con el `WHERE`, una fila idéntica no genera ni escritura, ni WAL, ni trabajo para el
-- `autovacuum`, que es la otra mitad del 36 %.
--
-- `IS DISTINCT FROM` Y NO `<>`: con `<>`, un nulo a cada lado da NULL —ni cierto ni
-- falso—, el `WHERE` no se cumple y la fila no se actualiza NUNCA. Un cliente al que le
-- ponen el teléfono por primera vez se quedaría sin él para siempre, y en silencio, que
-- es peor que las once mil escrituras.
--
-- `synced_at` NO entra en la comparación, y es el detalle del que depende todo: es la
-- hora de la última vez que se miró, así que cambia SIEMPRE. Metiéndolo, la fila siempre
-- sería distinta y esta guarda no serviría para nada mientras parece que sí.
--
-- La señal de que funcionó: `n_tup_upd` de `customers` deja de subir cuando no pasa nada.
-- Hoy sube unas 283 veces por segundo.
WHERE (customers.name, customers.phone, customers.address, customers.municipio,
       customers.zona, customers.codigo, customers.vendedor, customers.lat,
       customers.lng, customers.sucursal_codigo)
   IS DISTINCT FROM
      (excluded.name, excluded.phone, excluded.address, excluded.municipio,
       excluded.zona, excluded.codigo, excluded.vendedor, excluded.lat,
       excluded.lng, excluded.sucursal_codigo)
RETURNING id, source, external_id, name, sucursal_codigo, synced_at;

-- Los que ya no vienen de PEDIDO: borrados allá, o dejaron de tener coordenadas.
--
-- SÓLO los de `source = 'pedido'`. El alta MANUAL del reparto no tiene origen ni id
-- externo, y llevársela por delante sería borrar un cliente que nadie puede recuperar
-- porque no está en ningún otro sitio.
--
-- Quien llame tiene que haber recorrido TODAS las páginas de PEDIDO antes: con media
-- lista —un corte de la VPN a mitad del recorrido— esto vacía el espejo entero y el
-- logístico se queda sin a quién repartir, con un 200 y sin un solo error.
-- name: BorrarClientesDelEspejoQueYaNoVienen :execrows
DELETE FROM customers
WHERE source = sqlc.arg('source')::procedencia
  AND NOT (external_id = ANY(sqlc.arg('external_ids')::text[]));

-- LOS PUNTOS DE LOS CLIENTES DE UNA SUCURSAL, para ponerle coordenadas a una entrega que nace
-- de una FACTURA (issue 20, Fase A). Ventra no trae coordenadas: el cliente de la factura se
-- empareja con el espejo de clientes de PEDIDO por su CÓDIGO (`customerReference`, la nota
-- `C-…` de la venta) y, si eso no es un código, por su nombre. Los clientes siguen en PEDIDO
-- hasta nueva orden de Jose (20/10/2026). Va sin alcance: es del espejo, que entra con clave
-- de servicio, y la sucursal la pone quien llama. Solo los de PEDIDO (`source`).
-- name: PuntosDeClientesDeLaSucursal :many
SELECT codigo, name, lat, lng
FROM customers
WHERE source = 'pedido' AND sucursal_codigo = sqlc.arg('sucursal_codigo')::text;

-- LOS PUNTOS QUE EL LOGÍSTICO UBICÓ (00030): se suman a los clientes del padrón al buscar el punto de una factura.
-- name: PuntosGuardadosDeLaSucursal :many
SELECT nombre, lat, lng FROM puntos_de_clientes WHERE sucursal_codigo = sqlc.arg('sucursal_codigo')::text;

-- GUARDA (o corrige) EL PUNTO DE UN CLIENTE al ubicar una entrega a mano. La sucursal sale de la sucursal de la
-- factura; sin código de Accesos no se guarda (cero filas, y no pasa nada).
-- name: GuardarPuntoDeCliente :exec
INSERT INTO puntos_de_clientes (sucursal_codigo, clave, nombre, lat, lng, direccion, puesto_por)
SELECT b.external_id, sqlc.arg('clave')::text, sqlc.arg('nombre')::text, sqlc.arg('lat')::double precision,
       sqlc.arg('lng')::double precision, sqlc.narg('direccion')::text, sqlc.narg('por')::text
FROM branches b
WHERE b.id = sqlc.arg('branch_id')::uuid AND b.external_id IS NOT NULL
ON CONFLICT (sucursal_codigo, clave) DO UPDATE SET
    nombre = EXCLUDED.nombre, lat = EXCLUDED.lat, lng = EXCLUDED.lng,
    direccion = coalesce(EXCLUDED.direccion, puntos_de_clientes.direccion), puesto_por = EXCLUDED.puesto_por;
