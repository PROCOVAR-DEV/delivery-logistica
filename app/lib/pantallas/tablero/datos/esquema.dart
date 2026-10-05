import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/registro/registro.dart';

/// Las dos tablas del tablero EN LA BASE LOCAL, calcadas de
/// `api/db/migrations/00002_tablero.sql`.
///
/// **Por qué van en SQL suelto y no como tablas de Drift.** El esquema del
/// nucleo (`nucleo/base/tablas/`) es el espejo de lo que baja la
/// sincronizacion y no es de esta pantalla; el tablero se monta entero dentro
/// de su carpeta. Creando las tablas aqui, con `CREATE TABLE IF NOT EXISTS`,
/// el tablero vive en LA MISMA base y por tanto en la MISMA transaccion que la
/// cola de salida — que es el requisito que manda: arrastrar escribe la
/// colocacion y encola su apunte de una vez, o no escribe ninguna de las dos.
/// Con una segunda base serian dos transacciones y el dia que la segunda
/// fallara, la tarjeta se habria movido sin que nadie lo fuera a subir.
///
/// Las dos claves ajenas son las reglas de la especificacion, no un adorno:
///
///  * `order_id … ON DELETE CASCADE` (§7.5): si el pedido se borra de verdad,
///    la colocacion no puede sobrevivir — una tarjeta apuntando a un pedido que
///    no existe es una parada fantasma que la ruta cargaria sin renglones.
///  * `column_id … ON DELETE RESTRICT` (§7.6): borrar una columna con pedidos
///    dentro TIENE que doler. Con cascade las tarjetas volverian a «sin
///    colocar» sin decir nada y quien borro «Centro» creyendola vacia se entera
///    al dia siguiente, cuando a la ruta le faltan ocho paradas.
///
/// Van encendidas porque `BaseLocal.migration` pone `PRAGMA foreign_keys = ON`.
abstract final class EsquemaTablero {
  static const columnas = 'board_columns';
  static const colocaciones = 'board_placements';
  static const desaparecidos = 'board_desaparecidos';

  /// Las dos colecciones que la sincronizacion gana en `cambios`
  /// (`docs/tablero.md` §9). Se usan como clave en la tabla `frescura`, que es
  /// texto libre, para poder decir «visto por ultima vez a las 9:14».
  static const coleccionColumnas = 'boardColumns';
  static const coleccionColocaciones = 'boardPlacements';

  /// LAS DOS, EN UNA SOLA LISTA. Es de donde sale «de cuando son los datos» del
  /// Tablero, y sale de **un** sitio a proposito.
  ///
  /// Lo miran dos piezas: el `vistoAtProvider` de la propia pantalla y la franja
  /// de estado del armazon, via `PantallaRegistrada.colecciones`
  /// (`pantallas/tablero/registro.dart`). Escritas dos veces se separarian sin
  /// que salte nada, y entonces la franja y la cabecera dirian dos horas
  /// distintas en la misma ventana — que es exactamente el fallo del 01/10/2026
  /// que las junto (§3-bis).
  ///
  /// No estan en `Colecciones` porque no son de la bajada por diferencias: el
  /// tablero se pide aparte con `GET /api/board`.
  static const colecciones = <String>[coleccionColumnas, coleccionColocaciones];

  /// Las fechas van como TEXTO ISO-8601, que es como las guarda el resto de la
  /// base (`build.yaml`: `store_date_time_values_as_text`). Un entero de
  /// segundos aqui y texto en `orders` obligaria a convertir en cada `JOIN` y
  /// seria el sitio perfecto para perder una hora por el camino.
  static const _sentencias = <String>[
    '''
CREATE TABLE IF NOT EXISTS $columnas (
  id          TEXT NOT NULL PRIMARY KEY,
  branch_id   TEXT NOT NULL,
  nombre      TEXT NOT NULL,
  posicion    INTEGER NOT NULL,
  vehicle_id  TEXT,
  creado_por  TEXT,
  created_at  TEXT,
  updated_at  TEXT,
  -- NACIO AQUI: 1 mientras esta fila exista SOLO en este aparato.
  --
  -- Es la unica forma honesta de contestar «¿que pierdo si actualizo?», y hasta
  -- el 16/09/2026 se contestaba adivinando: se miraba si el id empezaba por
  -- `local-`. Eso dejo de significar nada el dia que el aparato empezo a poner
  -- el id definitivo —un UUIDv7— al crear la zona, este o no este arriba.
  --
  -- Lo pone a 1 quien crea la fila aqui, y a 0 la bajada del tablero: todo lo
  -- que viene del servidor viene, por definicion, de arriba. Asi que una zona
  -- que sube bien se queda en 0 sola en la siguiente bajada, sin que nadie
  -- tenga que acordarse de limpiarla.
  nacio_aqui  INTEGER NOT NULL DEFAULT 0
)''',
    // Dos «Vista Alegre» en el mismo tablero es colocar la mitad de los pedidos
    // en la equivocada y no enterarse hasta que salen dos camiones al mismo
    // barrio. Sin distinguir mayusculas: «centro» y «Centro» son la misma zona
    // para quien las escribe.
    'CREATE UNIQUE INDEX IF NOT EXISTS board_columns_nombre_idx '
        'ON $columnas (branch_id, lower(nombre))',
    'CREATE INDEX IF NOT EXISTS board_columns_branch_idx '
        'ON $columnas (branch_id, posicion)',
    // OJO: aqui NO va la unica de `(branch_id, posicion)` que si tiene
    // Postgres. Alli es DEFERRABLE y la comprobacion espera al final de la
    // transaccion; SQLite no sabe diferir nada, asi que la misma unica
    // reventaria a mitad del baile de reordenar, cuando hay dos columnas con la
    // misma posicion durante un instante. El orden lo sostiene quien escribe.
    '''
CREATE TABLE IF NOT EXISTS $colocaciones (
  order_id     TEXT NOT NULL PRIMARY KEY
               REFERENCES orders(id) ON DELETE CASCADE,
  column_id    TEXT NOT NULL
               REFERENCES $columnas(id) ON DELETE RESTRICT,
  posicion     INTEGER NOT NULL,
  colocado_por TEXT,
  colocado_at  TEXT,
  updated_at   TEXT,
  -- Igual que en las columnas, y hace la misma falta: una tarjeta arrastrada
  -- sin senal tampoco puede desaparecer al pulsar «actualizar».
  nacio_aqui   INTEGER NOT NULL DEFAULT 0
)''',
    'CREATE INDEX IF NOT EXISTS board_placements_column_idx '
        'ON $colocaciones (column_id, posicion)',
    // Lo que se llevo la cascada, para poder decirlo (§7.5).
    //
    // La cascada es silenciosa, y eso es justo lo que hay que tapar: el pedido
    // se archivo en PEDIDO, la bajada lo trajo en `quitados`, la fila
    // desaparecio y con ella la tarjeta. Sin esto, el logistico vuelve a
    // «Centro» y ve once paradas donde puso doce, sin manera de saber cual
    // falta ni por que.
    '''
CREATE TABLE IF NOT EXISTS $desaparecidos (
  order_id         TEXT NOT NULL PRIMARY KEY,
  operation_number TEXT,
  customer_name    TEXT,
  columna          TEXT,
  visto_at         TEXT
)''',
    // El disparador va sobre `orders` y es BEFORE DELETE porque despues del
    // borrado ya no queda nada que copiar: ni el numero de operacion ni de que
    // columna salio. Sólo escribe si el pedido estaba PUESTO, asi que el
    // barrido normal de pedidos viejos no deja rastro ninguno.
    '''
CREATE TRIGGER IF NOT EXISTS board_pedido_borrado
BEFORE DELETE ON orders
BEGIN
  INSERT OR REPLACE INTO $desaparecidos
    (order_id, operation_number, customer_name, columna, visto_at)
  SELECT OLD.id, OLD.operation_number, OLD.customer_name, c.nombre,
         datetime('now')
  FROM $colocaciones p
  JOIN $columnas c ON c.id = p.column_id
  WHERE p.order_id = OLD.id;
END''',
  ];

  /// Crea lo que falte. Una vez por base abierta: el `Expando` evita cinco
  /// `CREATE TABLE IF NOT EXISTS` por cada pintada de la pantalla.
  static Future<void> asegurar(BaseLocal base) =>
      _listas[base] ??= _crearYOlvidarSiFalla(base);

  /// Un `_crear` que falla NO se queda cacheado.
  ///
  /// `_listas[base] ??= …` guarda el Future, y un Future fallido guardado es un
  /// Tablero muerto hasta reiniciar la aplicacion: todas las llamadas de despues
  /// devuelven el mismo fallo, aunque lo que lo causara ya no este. Borrando la
  /// entrada, el siguiente intento vuelve a probar.
  static Future<void> _crearYOlvidarSiFalla(BaseLocal base) async {
    try {
      await _crear(base);
    } on Object {
      _listas[base] = null;
      rethrow;
    }
  }

  static Future<void> _crear(BaseLocal base) async {
    for (final sentencia in _sentencias) {
      await base.customStatement(sentencia);
    }
    // LAS QUE YA ESTABAN. `CREATE TABLE IF NOT EXISTS` no anade una columna a una
    // tabla que ya existe, asi que los aparatos que ya tienen tablero se
    // quedarian sin `nacio_aqui` y la guarda de «que pierdo si actualizo»
    // reventaria en el unico sitio donde importa: el de alguien con trabajo
    // dentro.
    //
    // Se anade con 0 —«esto ya estaba, se supone que vino del servidor»— y no
    // con 1. Poner 1 dejaria a todo el mundo con el tablero bloqueado sin poder
    // actualizar nunca, por filas que casi siempre SI estan arriba.
    var entroLaColumna = false;
    for (final (tabla, columna) in const [
      (columnas, 'nacio_aqui'),
      (colocaciones, 'nacio_aqui'),
    ]) {
      if (await _tieneColumna(base, tabla, columna)) continue;
      entroLaColumna = true;
      try {
        await base.customStatement(
          'ALTER TABLE $tabla ADD COLUMN $columna INTEGER NOT NULL DEFAULT 0',
        );
      } on Object catch (e) {
        // «duplicate column name»: otra apertura de la misma base llego primero.
        // El `Expando` de aqui abajo es POR `BaseLocal`, no por fichero, asi que
        // dos instancias sobre el mismo sqlite pueden entrar las dos. No es un
        // fallo: la columna esta, que es lo que se queria.
        if (!'$e'.contains('duplicate column')) rethrow;
        Registro.info('la columna $columna de $tabla ya estaba: $e');
      }
    }
    // SOLO CUANDO LA COLUMNA ACABA DE ENTRAR, o sea una vez en la vida de esta
    // base. Corriendolo en cada arranque, un rechazo viejo —que se queda «hasta
    // que una persona decida», y eso son semanas— volvia a marcar cada mañana una
    // tarjeta que ya estaba arriba y ya se habia limpiado.
    if (entroLaColumna) await _rescatarLoQueYaEstabaSinSubir(base);
  }

  /// LO QUE YA ESTÁ EN LOS TELÉFONOS, marcado como lo que es.
  ///
  /// El `ALTER` de arriba entra a 0 —«esto ya estaba, se supone que vino del
  /// servidor»— y eso es lo prudente para la inmensa mayoria de las filas. Pero
  /// hay un subconjunto que **con seguridad NO esta arriba**: el que lleva un id
  /// `local-…`. Ese prefijo significa, por construccion, que el servidor nunca
  /// devolvio el suyo.
  ///
  /// Sin este rescate, la actualizacion que arregla el fallo **se lleva por
  /// delante justo el caso que lo origino**: el telefono de quien lo reporto, con
  /// su zona «Vista» y sus cinco pedidos dentro, en cuanto pulse «actualizar».
  ///
  /// Marcar de mas no puede hacer dano —lo peor que pasa es que el tablero pida
  /// subir antes de refrescar— y marcar de menos es trabajo perdido. Se marca.
  static Future<void> _rescatarLoQueYaEstabaSinSubir(BaseLocal base) async {
    // SALVO LO QUE YA TIENE EQUIVALENCIA. Un `local-…` con equivalencia YA SUBIO:
    // el servidor devolvio su id y se anoto. Hasta ayer el id local no se
    // sustituia hasta que alguien volviera a abrir el Tablero, asi que en los
    // telefonos de hoy las hay a montones.
    //
    // Marcarlas seria dejar el tablero bloqueado por algo que esta perfectamente
    // arriba, y sin salida: la bajada se niega, y el ciclo no las reencola
    // —precisamente porque tienen equivalencia—. «Marcar de mas no hace daño» no
    // se sostiene con un pestillo: marcar de mas ES el atasco.
    await base.customStatement(
      "UPDATE $columnas SET nacio_aqui = 1 WHERE id LIKE 'local-%' "
      'AND NOT EXISTS (SELECT 1 FROM equivalencias e WHERE e.provisional = id)',
    );
    // Las tarjetas de esas zonas, que tampoco estan arriba: su columna no
    // existe alli.
    await base.customStatement(
      'UPDATE $colocaciones SET nacio_aqui = 1 '
      "WHERE column_id LIKE 'local-%'",
    );
    // Y las que tienen un apunte suyo todavia en la cola —pendiente o
    // rechazado—, aunque su zona si este arriba: se arrastraron aqui y no han
    // llegado.
    await base.customStatement(
      'UPDATE $colocaciones SET nacio_aqui = 1 '
      'WHERE order_id IN ('
      '  SELECT replace(a.ruta, \'/board/placements/\', \'\') FROM apuntes a '
      "  WHERE a.ruta LIKE '/board/placements/%' "
      "    AND a.estado IN ('pendiente', 'rechazado')"
      ')',
    );
  }

  static Future<bool> _tieneColumna(
    BaseLocal base,
    String tabla,
    String columna,
  ) async {
    final filas = await base.customSelect('PRAGMA table_info($tabla)').get();
    return filas.any((f) => f.read<String>('name') == columna);
  }

  /// Avisa a Drift de que estas tablas cambiaron. Hace falta a mano porque no
  /// son tablas suyas: sin esto, lo que este mirando la pantalla no se entera
  /// de que la tarjeta se movio.
  static void avisarDeCambio(BaseLocal base) => base.notifyUpdates({
    const TableUpdate(columnas),
    const TableUpdate(colocaciones),
  });
}

final Expando<Future<void>> _listas = Expando<Future<void>>('tablas tablero');
