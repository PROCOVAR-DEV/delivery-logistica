import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/frescura.dart';
import '../../../nucleo/red/cliente_api.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/reloj.dart';
import 'esquema.dart';

/// LA BAJADA DEL TABLERO: `GET /api/board`, una sola ida y vuelta.
///
/// Una y no cinco porque la conexion de alla no da para mas: columnas con sus
/// totales, tarjetas puestas, avisos y la primera pagina de sin colocar vienen
/// juntas. Aqui sólo se guardan las columnas y las colocaciones — los pedidos
/// ya los trae la sincronizacion normal, y copiarlos otra vez seria tener dos
/// versiones del mismo pedido en el mismo aparato.
///
/// **Quien pinta no llama a esto.** La pantalla mira siempre la base local; esto
/// es lo que la rellena cuando hay senal.
class ServicioTablero {
  ServicioTablero(
    this._base,
    this._cliente,
    this._frescura, {
    Reloj reloj = relojDelAparato,
  }) : _reloj = reloj;

  final BaseLocal _base;
  final ClienteApi _cliente;
  final RegistroDeFrescura _frescura;
  final Reloj _reloj;

  /// Baja el tablero de una sucursal y lo deja en la base local.
  ///
  /// **Si queda trabajo que no esta arriba, no se baja nada, y se DICE.** Es la
  /// regla que impide el peor fallo posible de esta pantalla: la foto del
  /// servidor, que todavia no sabe nada de las cuarenta tarjetas que se movieron
  /// esta tarde, borraria las cuarenta de golpe y en silencio.
  ///
  /// ## La guarda preguntaba lo que no era — 16/09/2026
  ///
  /// Miraba `cuantosPendientes()`: «¿queda algo EN LA COLA?». Y eso no es lo
  /// mismo que «¿hay algo aqui que no este arriba?». La zona «Vista» de Jose,
  /// con sus cinco pedidos, ya no tenia apunte —se habia descartado—, asi que la
  /// cola estaba a cero, la guarda dejo pasar y el `DELETE` de aqui abajo se la
  /// llevo entera. Sus palabras: «si le doy al boton de actualizar me borra todo
  /// lo sin conexion y deberia de informarme o algo para decirme lo q voy a
  /// perder si le doy al boton».
  ///
  /// Ahora se pregunta por las dos cosas: lo que esta en la cola **y** lo que
  /// quedo huerfano (`nucleo/sincro/huerfanos.dart`). Y se devuelve POR QUE no
  /// se bajo, para poder ponerlo en la pantalla en vez de en un registro que no
  /// lee nadie.
  ///
  /// **El trabajo sin conexion no se pierde por ninguna circunstancia.** Es la
  /// unica regla que no se negocia aqui.
  Future<ResultadoDeBajarElTablero> descargar(String sucursalId) async {
    await EsquemaTablero.asegurar(_base);

    // EN LA WEB NO HAY NADA QUE PROTEGER, y por eso no se protege.
    //
    // Toda la guarda de aqui abajo existe para una razon: que la foto del
    // servidor no borre el trabajo que se hizo sin senal y todavia no ha subido.
    // **En un navegador ese trabajo no existe.** La web esta en el servidor y
    // siempre tiene conexion; lo que se hace ahi sale en el momento.
    //
    // Dejarle la guarda no la protegia de nada y si la rompia: un solo apunte
    // atascado congelaba el tablero indefinidamente, enseñando una foto vieja
    // mientras el telefono subia sin problema. Hora y media el 16/09/2026.
    //
    // Es la regla 1 de la casa, la que Jose ha repetido cinco veces: «el desktop
    // y las apks tienen su propia base de datos para trabajar sin conexion; la
    // web siempre esta con conexion porque esta en el servidor».
    if (!Destino.trabajaSinConexion) {
      return _traerLaFoto(sucursalId);
    }

    final pendientes = await _base.cuantosPendientes();
    if (pendientes > 0) {
      Registro.info(
        'tablero: $pendientes apuntes sin subir, no se baja para no pisarlos',
      );
      return ResultadoDeBajarElTablero.esperando(
        '$pendientes ${pendientes == 1 ? 'cambio' : 'cambios'} sin subir',
      );
    }

    // Y LO QUE NACIO AQUI Y NO ESTA ARRIBA.
    //
    // Un apunte descartado —o rechazado, que tampoco cuenta como pendiente—
    // deja su fila local ahi, a la vista y sin nada que la suba: para la cola no
    // existe, pero el `DELETE` de abajo se la llevaria igual.
    //
    // **No se pregunta por el prefijo del id.** Se probo y no vale: desde que el
    // aparato pone el id definitivo (UUIDv7), `local-…` no distingue nada. Lo
    // unico que lo sabe de verdad es `nacio_aqui`, que pone quien crea la fila
    // de este lado y limpia la propia bajada.
    final propias = await _loQueNacioAqui(sucursalId);
    if (propias.$1 > 0 || propias.$2 > 0) {
      Registro.aviso(
        'tablero: hay ${_enPalabras(propias)} que no está en el servidor; no se '
        'baja para no borrarlo',
      );
      return ResultadoDeBajarElTablero.esperando(
        '${_enPalabras(propias)} que no está en el servidor',
      );
    }

    return _traerLaFoto(sucursalId);
  }

  /// La foto del servidor, escrita encima de lo que haya. Sin preguntar nada:
  /// quien llama ya decidio que se puede.
  Future<ResultadoDeBajarElTablero> _traerLaFoto(String sucursalId) async {
    final datos = await _cliente.pedir<Map<String, Object?>>(
      '/board',
      // Las inactivas TAMBIEN bajan: se guardan con `activa = 0` para poder
      // enseñarlas y activarlas sin conexion; las lecturas del tablero las filtran.
      params: <String, Object?>{
        'branchId': sucursalId,
        'incluirInactivas': '1',
      },
    );

    final columnas = (datos['columnas'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    final colocados = (datos['colocados'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();

    // Fuera de la transaccion para poder devolverlo: lo de dentro se descarta si
    // algo revienta, y entonces no hay nada que reintentar.
    var sinPedido = 0;

    await _base.transaction(() async {
      // Las colocaciones ANTES que las columnas: `ON DELETE RESTRICT` no deja
      // borrar una columna con tarjetas dentro, y eso es lo que se quiere en
      // todas partes menos aqui, donde se esta reemplazando la foto entera.
      await _base.customStatement(
        'DELETE FROM ${EsquemaTablero.colocaciones} WHERE column_id IN '
        '(SELECT id FROM ${EsquemaTablero.columnas} WHERE branch_id = ?1)',
        [sucursalId],
      );
      // Y las que no cupieron la vez anterior: se vuelven a contar enteras.
      await _base.customStatement(
        'DELETE FROM ${EsquemaTablero.sinPedido} WHERE column_id IN '
        '(SELECT id FROM ${EsquemaTablero.columnas} WHERE branch_id = ?1)',
        [sucursalId],
      );
      await _base.customStatement(
        'DELETE FROM ${EsquemaTablero.columnas} WHERE branch_id = ?1',
        [sucursalId],
      );

      for (final c in columnas) {
        await _base.customStatement(
          'INSERT INTO ${EsquemaTablero.columnas} '
          // `nacio_aqui = 0`: esto viene del servidor, asi que por definicion
          // ya esta arriba. Es lo que hace que una zona creada aqui se limpie
          // sola en cuanto sube, sin que nadie tenga que acordarse.
          '(id, branch_id, nombre, posicion, vehicle_id, creado_por, '
          ' created_at, updated_at, nacio_aqui, almacen_id, activa) '
          'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10)',
          [
            c['id'] as String,
            (c['branchId'] as String?) ?? sucursalId,
            c['nombre'] as String,
            (c['posicion'] as num?)?.toInt() ?? 0,
            c['vehiculoId'] as String?,
            c['creadoPor'] as String?,
            _fecha(c['createdAt'] as String?),
            _fecha(c['updatedAt'] as String?),
            // El punto de salida. La foto es entera en cada bajada, asi que las
            // zonas que ya estaban lo traen la proxima vez sin rebajar nada.
            // "" es «sin punto», igual que en el servidor.
            switch (c['almacenId']) {
              final String id when id.isNotEmpty => id,
              _ => null,
            },
            // Sin el campo (servidor anterior a la 00022) = activa.
            c['activa'] == false ? 0 : 1,
          ],
        );
      }

      var huerfanas = 0;
      for (final t in colocados) {
        // El `WHERE EXISTS` es lo que impide que la bajada reviente entera por
        // una tarjeta de un pedido que este aparato todavia no tiene: se cuenta
        // y se dice, que es distinto de callarselo.
        await _base.customStatement(
          'INSERT INTO ${EsquemaTablero.colocaciones} '
          '(order_id, column_id, posicion, colocado_por, colocado_at, updated_at, '
          ' nacio_aqui) '
          'SELECT ?1, ?2, ?3, ?4, ?5, ?5, 0 '
          'WHERE EXISTS (SELECT 1 FROM orders WHERE id = ?1)',
          [
            t['pedidoId'] as String,
            t['columnaId'] as String,
            (t['posicion'] as num?)?.toInt() ?? 1,
            t['colocadoPor'] as String?,
            _fecha(t['colocadoAt'] as String?),
          ],
        );
        final cuantas = await _base
            .customSelect(
              'SELECT count(*) AS n FROM ${EsquemaTablero.colocaciones} '
              'WHERE order_id = ?1',
              variables: [Variable<String>(t['pedidoId'] as String)],
            )
            .getSingle();
        if (cuantas.read<int>('n') == 0) {
          huerfanas++;
          // No cabe, pero sigue puesta arriba: se APUNTA para poder contarla al
          // borrar la zona (`board_sin_pedido`, esquema.dart).
          await _base.customStatement(
            'INSERT OR REPLACE INTO ${EsquemaTablero.sinPedido} '
            '(order_id, column_id) VALUES (?1, ?2)',
            [t['pedidoId'] as String, t['columnaId'] as String],
          );
        }
      }
      if (huerfanas > 0) {
        Registro.aviso(
          'tablero: $huerfanas tarjetas de pedidos que este aparato no tiene',
        );
      }
      sinPedido = huerfanas;
    });

    // La hora del SERVIDOR, tal cual vino: es la que se ensena como «visto por
    // ultima vez a las 9:14».
    final vistoAt = datos['vistoAt'] as String?;
    for (final coleccion in const [
      EsquemaTablero.coleccionColumnas,
      EsquemaTablero.coleccionColocaciones,
    ]) {
      await _frescura.marcar(
        coleccion,
        hasta: vistoAt,
        bajadaAt: _reloj(),
        completa: true,
      );
    }
    EsquemaTablero.avisarDeCambio(_base);
    return ResultadoDeBajarElTablero.bajado(tarjetasSinPedido: sinPedido);
  }

  /// La marca del servidor, pasada al formato en el que guarda las fechas el
  /// resto de la base. La conversion la hace Drift, no esta clase.
  Object? _fecha(String? iso) {
    if (iso == null) return null;
    final fecha = DateTime.tryParse(iso);
    return fecha == null ? null : _base.typeMapping.mapToSqlVariable(fecha);
  }

  /// Cuantas zonas y cuantas tarjetas de esta sucursal existen SOLO aqui.
  ///
  /// Dos numeros y no uno: se arreglan igual —subiendo— pero se leen distinto, y
  /// «3 cosas sin subir» no le dice a nadie que ir a mirar.
  Future<(int zonas, int tarjetas)> _loQueNacioAqui(String sucursalId) async {
    final z = await _base
        .customSelect(
          'SELECT count(*) AS n FROM ${EsquemaTablero.columnas} '
          'WHERE branch_id = ?1 AND nacio_aqui = 1',
          variables: [Variable<String>(sucursalId)],
        )
        .getSingle();
    final t = await _base
        .customSelect(
          'SELECT count(*) AS n FROM ${EsquemaTablero.colocaciones} p '
          'JOIN ${EsquemaTablero.columnas} c ON c.id = p.column_id '
          'WHERE c.branch_id = ?1 AND p.nacio_aqui = 1',
          variables: [Variable<String>(sucursalId)],
        )
        .getSingle();
    return (z.read<int>('n'), t.read<int>('n'));
  }

  /// «1 zona del tablero», «2 tarjetas», «1 zona del tablero y 2 tarjetas».
  static String _enPalabras((int, int) cuenta) {
    final (zonas, tarjetas) = cuenta;
    final partes = <String>[
      if (zonas > 0)
        '$zonas ${zonas == 1 ? 'zona del tablero' : 'zonas del tablero'}',
      if (tarjetas > 0) '$tarjetas ${tarjetas == 1 ? 'tarjeta' : 'tarjetas'}',
    ];
    return partes.join(' y ');
  }
}

/// COMO QUEDO el intento de bajar el tablero. Tres cosas distintas, y las tres
/// hay que poder decirlas:
///
///  * **bajado** — se reemplazo la foto con la del servidor.
///  * **esperando** — NO se bajo a proposito, porque aqui hay trabajo que arriba
///    no esta. Lleva [porQue] para poder ponerlo en la pantalla.
///
/// Antes esto era un `bool` y el «no» se escribia en el registro. Quien estaba
/// delante pulsaba actualizar, no pasaba nada, y no habia forma de saber si era
/// que no habia cambios o que la aplicacion se estaba negando.
class ResultadoDeBajarElTablero {
  const ResultadoDeBajarElTablero.bajado({this.tarjetasSinPedido = 0})
    : porQue = null;

  const ResultadoDeBajarElTablero.esperando(String this.porQue)
    : tarjetasSinPedido = 0;

  /// `null` cuando se bajo. Con texto, lo que hay aqui y no esta arriba.
  final String? porQue;

  /// CUANTAS TARJETAS TRAJO EL SERVIDOR QUE NO SE PUDIERON PONER — 17/09/2026.
  ///
  /// Una colocacion apunta a un pedido (`order_id REFERENCES orders(id)`), asi
  /// que no se puede escribir si ese pedido todavia no esta en esta base. Eso se
  /// contaba en una variable local y se escribia en el registro, donde no lo lee
  /// nadie.
  ///
  /// Y no era un caso raro: es lo que pasa en la web CADA VEZ que se abre.
  /// Su base nace vacia; el tablero pide `/board` nada mas pintarse y los
  /// pedidos llegan despues, por el ciclo, que es otro camino. Asi que las
  /// tarjetas llegan primero y se tiran todas. Luego llegan los pedidos, el
  /// tablero **ya no vuelve a bajar** —esta guardado para no bajar dos veces por
  /// sucursal— y la zona se queda a cero con sus pedidos en «Sin colocar».
  ///
  /// Lo vio Jose el 17/09/2026: la zona «Vista» con 6 pedidos en el telefono y
  /// «Vista (0)» en la web, con las 6 colocaciones bien puestas en el servidor.
  ///
  /// Sale por aqui para que quien llama pueda VOLVER A PEDIRLA cuando lleguen
  /// los pedidos que faltaban. Inventar el pedido con lo que trae la tarjeta no
  /// vale: quedaria una fila a medias que el resto de la aplicacion leeria como
  /// un pedido de verdad.
  final int tarjetasSinPedido;

  bool get seBajo => porQue == null;
}
