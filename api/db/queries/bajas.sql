-- LO QUE SE FUE, para `quitados` de las colecciones que no son pedidos.
--
-- Los pedidos tienen la suya aparte (`PedidosQueSalieronDelAlcance`, en orders.sql, sobre
-- las lápidas de 00003). Ésta lee `bajas_de_la_bajada`, de 00006, que es la misma idea
-- para las demás: ruta borrada, camión dado de baja, sucursal quitada, zona del tablero
-- borrada desde la web, tarjeta sacada del tablero, producto o cliente que ya no está.
--
-- POR QUÉ NO SE MIRAN LAS TABLAS DE VERDAD, otra vez y para todas: lo borrado ya no tiene
-- fila que consultar, y lo que se mudó de sucursal tiene la suya intacta pero con OTRA
-- sucursal, así que no sale en ninguna consulta acotada a la vieja. En los dos casos el
-- aparato se lo queda para siempre y la lista local sólo crece.

-- name: BajasDeLaBajada :many
SELECT b.coleccion, b.clave, b.branch_id, b.motivo, b.salio_at
FROM bajas_de_la_bajada b
WHERE b.coleccion = sqlc.arg('coleccion')::coleccion_de_la_bajada
  -- `desde` ESTRICTO y `hasta` INCLUSIVO, igual que las diferencias de pedidos: dos
  -- ventanas seguidas no se pisan ni dejan hueco.
  AND (sqlc.narg('desde')::timestamptz IS NULL OR b.salio_at >  sqlc.narg('desde')::timestamptz)
  AND (sqlc.narg('hasta')::timestamptz IS NULL OR b.salio_at <= sqlc.narg('hasta')::timestamptz)
  -- POR LOTES, CON CURSOR (28/10/2026): un grupo de lápidas con la MISMA hora mayor que el tope no cabe sin partirse,
  -- y la marca sola no sabe seguir (el 21/10/2026 se perdieron 828 de facturas así). El cursor es (hora, clave) de la
  -- última servida; con él, quien llama deja `desde` en NULL.
  AND (sqlc.narg('cursor_marca')::timestamptz IS NULL
       OR (b.salio_at, b.clave) > (sqlc.narg('cursor_marca')::timestamptz, sqlc.narg('cursor_clave')::text))
  -- EL ALCANCE PRIMERO, como siempre: aunque quien llama pida otra sucursal, sólo puede
  -- enterarse de lo que se fue de la suya.
  --
  -- `sin_sucursal_tambien` es la diferencia ENTRE COLECCIONES, y no es un adorno: hay
  -- listas que le enseñan a un aparato acotado las filas SIN sucursal y hay listas que no.
  -- `ListarVehiculos` lleva `OR v.branch_id IS NULL` —un camión sin sucursal lo ven los
  -- ocho— y `ListarRutas` no lo lleva. Este parámetro copia esa decisión colección por
  -- colección, y por eso va en `true` para vehículos y en `false` para todo lo demás:
  -- puesto en `false` donde toca `true`, un camión sin sucursal que se da de baja no se le
  -- quita a nadie y se queda en los ocho teléfonos; puesto en `true` donde toca `false`,
  -- se le manda a un aparato acotado una lápida de algo que nunca fue suyo.
  AND (sqlc.narg('sucursal')::uuid IS NULL
       OR b.branch_id = sqlc.narg('sucursal')::uuid
       OR (b.branch_id IS NULL AND sqlc.arg('sin_sucursal_tambien')::boolean))
  -- Y la sucursal PEDIDA, que es otra cosa: el tablero se sirve por sucursal (el Super
  -- Admin dice cuál mira) y sus dos colecciones tienen que acotarse igual que sus listas.
  -- Las demás lo dejan nulo, como sus listas.
  AND (sqlc.narg('branch_id')::uuid IS NULL OR b.branch_id = sqlc.narg('branch_id')::uuid)
  -- SIN NINGUNA SUCURSAL —quien ve las ocho— sólo cuentan los BORRADOS: algo que se mudó
  -- de Santiago a Holguín no se le ha ido de la vista, y mandárselo en `quitados` le
  -- borraría del aparato algo que existe y que está en su lista.
  AND (
      sqlc.narg('sucursal')::uuid  IS NOT NULL
      OR sqlc.narg('branch_id')::uuid IS NOT NULL
      OR b.motivo = 'borrado'
  )
-- POR LA MARCA Y HACIA ADELANTE, que es lo que hace que el tope no pierda nada: lo que no
-- cabe en esta tanda se pide en la siguiente con la marca de la última fila servida. La
-- clave desempata para que dos tandas iguales salgan iguales.
ORDER BY b.salio_at ASC, b.clave ASC
LIMIT sqlc.arg('tope');

-- ---------------------------------------------------------------------------
-- La poda
-- ---------------------------------------------------------------------------
--
-- UNA LÁPIDA NO PUEDE VIVIR PARA SIEMPRE. El aparato pide `?desde=<marca>` y sólo recibe
-- las posteriores a esa marca, así que uno que sincroniza cada día se lleva las de ayer y
-- nada más; pero la tabla sí crece sin techo, y el día que un aparato vuelva con una marca
-- de hace dos años se llevaría los borrados de dos años en una sola bajada, por la
-- conexión de allá. Es el mismo criterio que ya está escrito para los pedidos en
-- `espejo.go` («mandarle los borrados de los últimos dos años es gastarle la conexión»).
--
-- QUIÉN LA LLAMA: NADIE TODAVÍA, y se dice aquí para que no se dé por hecho. No hay tarea
-- de fondo que la dispare; hace falta ejecutarla desde mantenimiento, o darle una. El
-- límite lo pone quien llama —`HorizonteDeLapidas` en `espejo.go`— y la bajada AVISA
-- cuando el `desde` que trae el aparato es anterior a ese horizonte, porque a partir de
-- ahí las diferencias ya no alcanzan y lo que toca es una carga entera.
--
-- Las dos podas van juntas a propósito: las lápidas de pedidos (00003) tampoco se podaban,
-- y dejar sólo la mitad hecha es el tipo de asimetría que luego nadie encuentra.

-- name: PodarBajasDeLaBajada :execrows
DELETE FROM bajas_de_la_bajada
WHERE salio_at < sqlc.arg('anteriores_a')::timestamptz;

-- name: PodarLapidasDePedidos :execrows
DELETE FROM orders_fuera_de_alcance
WHERE salio_at < sqlc.arg('anteriores_a')::timestamptz;
