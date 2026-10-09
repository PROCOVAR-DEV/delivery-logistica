import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../base/base.dart';
import '../reloj.dart';

const _uuid = Uuid();

/// Los identificadores provisionales: `local-9f3a2b7c` → `cm2x…`.
///
/// Una ruta armada sin conexion no tiene identificador —lo pone la base de
/// datos— pero la pantalla necesita uno YA para poder ensenarla, imprimir el
/// despacho y cerrarla despues. Asi que el aparato se inventa uno.
///
/// **Y aqui esta el agujero por el que se pierde el dia entero.** Cuando el
/// apunte que crea la ruta sube, la respuesta trae el id de verdad; si no se
/// sustituye en todo lo que quedara en la cola detras, el cierre de la tarde se
/// va a `POST /api/routes/local-9f3a/results`, que no existe en ningun sitio, y
/// el trabajo se pierde JUSTO DESPUES de haberlo subido (caso S4).
class Provisionales {
  Provisionales(this._base, {Reloj reloj = relojDelAparato}) : _reloj = reloj;

  final BaseLocal _base;
  final Reloj _reloj;

  /// Las columnas donde puede haber un id provisional.
  ///
  /// Va como lista y no a mano en la consulta porque sin red no sólo se arman
  /// rutas: tambien se crean vehiculos y almacenes (PLAN.md §3.4 y §3.5), y el
  /// dia que se anada otro, esto es lo unico que hay que tocar.
  static const _dondeMirar = <(String tabla, String columna)>[
    ('routes', 'id'),
    ('routes', 'vehicle_id'),
    ('orders', 'route_id'),
    ('orders', 'ultima_ruta_id'),
    ('vehicles', 'id'),
    ('warehouses', 'id'),
    // EL TABLERO, que faltaba y costo caro. Sus dos tablas NO son de Drift —las
    // crea la propia pantalla la primera vez que se abre— y por eso se quedaron
    // fuera de esta lista.
    //
    // La consecuencia no era cosmetica: una zona que SUBIA BIEN se quedaba con
    // su `local-…` en la base hasta que alguien volviera a abrir el Tablero, que
    // es lo unico que llamaba a `asentarProvisionales()`. Para todo lo demas
    // —incluida la comprobacion de lo que no ha subido— esa zona parecia no
    // haber subido nunca. Quien la creo sin senal, llego al almacen, subio el
    // dia y se fue a Rutas, se quedaba con la marca «sin subir» puesta sobre un
    // trabajo que estaba arriba.
    //
    // Aqui la sustitucion la hace el SINCRONIZADOR, en cuanto el servidor
    // contesta, sin depender de que nadie entre en ninguna pantalla.
    ('board_columns', 'id'),
    ('board_placements', 'column_id'),
  ];

  /// Las tablas que NO son de Drift. Se actualizan igual, pero hay que avisar a
  /// mano de que cambiaron y hay que saltarlas si todavia no existen.
  static const _fueraDeDrift = {'board_columns', 'board_placements'};

  /// Un id provisional nuevo. `local-` delante para que se reconozca de un
  /// vistazo en un registro, en la barra de direcciones o en un cuerpo JSON.
  ///
  /// **Para lo que el servidor todavia no deja nombrar.** Donde el servidor
  /// acepta el id del aparato —hoy las zonas del tablero— se usa [nuevoIdReal],
  /// que es mejor en todo.
  static String nuevoId() =>
      'local-${_uuid.v4().replaceAll('-', '').substring(0, 8)}';

  /// UN ID DEFINITIVO, PUESTO POR EL APARATO. UUIDv7.
  ///
  /// Es la forma de quitarse de encima toda la maquinaria de arriba, y no un
  /// adorno: con un id que el aparato ya sabe, **subir dos veces no crea dos
  /// cosas**. El servidor lo usa tal cual y una segunda subida con el mismo id
  /// devuelve lo que ya habia. Eso convierte «¿llego o no llego?» —la pregunta
  /// que no tiene respuesta cuando la red se cae justo despues de escribir— en
  /// una pregunta que no hace falta hacer.
  ///
  /// **v7 y no v4** porque lleva la hora dentro y por eso ORDENA. Cuatro
  /// telefonos sin senal creando zonas toda la manana producen ids que, al
  /// juntarse, quedan en el orden en que se crearon de verdad. Con v4 quedarian
  /// barajados, y el orden de creacion es lo unico que hay para deshacer un
  /// empate entre dos aparatos que no se vieron.
  static String nuevoIdReal() => _uuid.v7();

  static bool esProvisional(String? id) =>
      id != null && id.startsWith('local-');

  /// Cambia `provisional` por `real` en TODO: la equivalencia, los apuntes que
  /// quedan por subir y las filas locales.
  ///
  /// Va entero en UNA transaccion. A medias es peor que nada: la ruta ya subida
  /// con su id bueno y el cierre de la tarde apuntando a un id que no existe.
  /// LAS EQUIVALENCIAS, EN VIVO: `local-…` → el id de verdad.
  ///
  /// Hace falta porque una pantalla abierta puede estar mirando un id
  /// provisional **en el momento en que ese id deja de existir**. Pasó el
  /// 21/09/2026, con Jose delante: armó una ruta con cinco pedidos, el detalle
  /// se abrió solo con el id provisional, la ruta subió en ese instante y los
  /// pedidos se engancharon al id de verdad. La pantalla se quedó mirando el
  /// viejo y decía **«Ver paradas (0)»** encima de una ruta de cinco paradas,
  /// con sus 27 km y sus 616 kg al lado. Cerrar y volver a abrir lo arreglaba,
  /// que es la peor forma de un fallo: el dato estaba bien y la pantalla mentía.
  ///
  /// Jose: «no, eso no puede pasar, eso es al momento».
  Stream<Map<String, String>> mirar() => _base
      .select(_base.equivalencias)
      .watch()
      .map((filas) => {for (final f in filas) f.provisional: f.idReal});

  ///
  /// [reescribirApuntes] es `false` para lo que decide un REVISOR: lo entregado a
  /// revision guarda el original con el `local-…` y es `sync` quien lo traduce al
  /// aplicar (`ids_provisionales`). Reescribir aqui los apuntes que aun esperan
  /// cambiaria su cuerpo, y al entregarlos —o reentregarlos— el servidor vería otro
  /// contenido con la misma clave: `409 huella_distinta`, y ese apunte se quedaria
  /// pendiente para siempre. La equivalencia y las filas locales SI se sustituyen.
  Future<void> sustituir(
    String provisional,
    String real, {
    bool reescribirApuntes = true,
  }) async {
    if (provisional == real) return;

    await _base.transaction(() async {
      // LAS CLAVES FORANEAS, APLAZADAS HASTA EL COMMIT.
      //
      // Cambiar el id de una zona del tablero deja por un instante a sus
      // colocaciones apuntando a un padre que ya no esta, y al reves si se
      // empieza por las hijas: en los dos ordenes hay un momento intermedio que
      // no cuadra, y SQLite lo rechaza al vuelo. Con esto la comprobacion se hace
      // AL CERRAR la transaccion, cuando ya cuadra.
      //
      // Es `defer_foreign_keys` y no `foreign_keys = OFF`: la diferencia importa.
      // Apagarlas dejaria pasar tambien lo que de verdad no cuadre; esto solo
      // mueve la comprobacion al final. Y se apaga sola al cerrar.
      await _base.customStatement('PRAGMA defer_foreign_keys = ON');

      // 1. El rastro. Sirve para leer un registro viejo y para no repetir.
      await _base
          .into(_base.equivalencias)
          .insertOnConflictUpdate(
            EquivalenciasCompanion.insert(
              provisional: provisional,
              idReal: real,
              at: _reloj(),
            ),
          );

      // 2. Los apuntes que AUN NO HAN SUBIDO. Sólo los pendientes: reescribir un
      //    apunte ya aplicado o rechazado seria falsear lo que de verdad se
      //    mando, y esa es la unica prueba que queda de lo que paso.
      if (reescribirApuntes) {
        await _base.customUpdate(
          'UPDATE apuntes SET ruta = replace(ruta, ?1, ?2), '
          'cuerpo = replace(cuerpo, ?1, ?2) '
          "WHERE estado = 'pendiente' AND (ruta LIKE ?3 OR cuerpo LIKE ?3)",
          variables: [
            Variable<String>(provisional),
            Variable<String>(real),
            Variable<String>('%$provisional%'),
          ],
          updates: {_base.apuntes},
        );
      }

      // 3. Las filas locales, para que la pantalla deje de ensenar el `local-…`
      //    sin esperar a la proxima bajada.
      for (final (tabla, columna) in _dondeMirar) {
        if (_fueraDeDrift.contains(tabla)) {
          // Puede no existir: son las del Tablero, que crea su pantalla. En un
          // aparato que nunca ha entrado ahi no hay nada que sustituir, y eso no
          // puede tumbar la sustitucion de todo lo demas.
          if (!await _hayTabla(tabla)) continue;
          await _base.customStatement(
            'UPDATE $tabla SET $columna = ?1 WHERE $columna = ?2',
            [real, provisional],
          );
          _base.notifyUpdates({TableUpdate(tabla)});
          continue;
        }
        await _base.customUpdate(
          'UPDATE $tabla SET $columna = ?1 WHERE $columna = ?2',
          variables: [Variable<String>(real), Variable<String>(provisional)],
          updates: {_base.tablaLlamada(tabla)},
        );
      }
    });
  }

  Future<bool> _hayTabla(String tabla) async {
    final fila = await _base
        .customSelect(
          "SELECT count(*) AS hay FROM sqlite_master "
          "WHERE type = 'table' AND name = ?1",
          variables: [Variable<String>(tabla)],
        )
        .getSingle();
    return fila.read<int>('hay') > 0;
  }

  /// El id de verdad de un provisional, si ya se resolvio.
  Future<String?> real(String provisional) async {
    final fila = await (_base.select(
      _base.equivalencias,
    )..where((f) => f.provisional.equals(provisional))).getSingleOrNull();
    return fila?.idReal;
  }
}

extension on BaseLocal {
  /// Drift necesita saber que tablas toca un `customUpdate` para poder avisar a
  /// los `watch()` que estan mirando. Sin esto la pantalla se queda con el
  /// `local-…` puesto hasta que algo mas la despierte.
  TableInfo<Table, Object?> tablaLlamada(String nombre) =>
      allTables.firstWhere((t) => t.actualTableName == nombre);
}
