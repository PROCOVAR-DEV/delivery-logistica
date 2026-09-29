import 'package:drift/drift.dart';

import '../base/base.dart';
import '../cola/cola_salida.dart';
import '../registro/registro.dart';

/// LO QUE EL APARATO HIZO SIN CONEXION Y **NO VA A SUBIR SOLO**.
///
/// ## El agujero que tapa, en una frase
///
/// La subida es una COLA, no una comprobacion. Reenvia apuntes; nunca compara lo
/// que este aparato tiene contra lo que hay arriba. Asi que en cuanto un apunte
/// desaparece —se descarto a mano, o se perdio por un fallo— **el dato local se
/// queda huerfano: existe aqui, no existe en ningun otro sitio, y nada lo va a
/// volver a intentar nunca.**
///
/// Palabras de Jose, 16/09/2026, mirandolo en su telefono: «entonces ahi el sync
/// no esta haciendo su trabajo, ahi el movil esta adelante por q tiene cosas q
/// el web no tiene, o sea q no esta funcionando para comprobar lo q hay arriba
/// contra lo q esta offline».
///
/// ## Como se veia
///
/// Tres pantallas diciendo cosas distintas del mismo aparato, todas de buena fe:
///
///  * el Tablero: la zona «Vista», con sus cinco pedidos y su marca «sin subir»;
///  * entregar el dia: «Todo entregado. No queda nada por subir»;
///  * el Panel: «Todo al dia. No queda nada sin enviar».
///
/// Y el servidor, que es el unico que tenia razon: «Galaxy A16 de Jose — nunca
/// ha subido». Las tres primeras miran LA COLA, y la cola estaba vacia porque el
/// apunte que creaba la zona se habia descartado. El trabajo seguia ahi, a la
/// vista, y ya no tenia forma de salir del telefono.
///
/// ## Como se detecta
///
/// Por el id. Lo que se crea sin conexion lleva un id `local-…` hasta que el
/// servidor devuelve el suyo (`nucleo/cola/provisionales.dart`), asi que **una
/// fila con id provisional es, por definicion, algo que todavia no existe
/// arriba**. Si ademas no le queda ningun apunte vivo en la cola, nadie la va a
/// subir: eso es un huerfano.
///
/// No hace falta preguntarle nada al servidor, y es a proposito: esto tiene que
/// poder contestarse **sin conexion**, que es justo cuando se acumula el
/// trabajo.
/// La tabla donde se anotan las renuncias. Va por nombre porque no es de Drift:
/// la crea `BaseLocal` al abrir (`tablaDeRenuncias`), igual que las del Tablero.
const tablaDeRenuncias = 'renuncias';

class Huerfanos {
  const Huerfanos(this._base);

  final BaseLocal _base;

  /// Donde puede quedar trabajo huerfano, y como se llama para una persona.
  ///
  /// Va como lista y no a mano en la consulta por lo mismo que `Provisionales.
  /// _dondeMirar`: el dia que se pueda crear otra cosa sin conexion, esto es lo
  /// unico que hay que tocar.
  ///
  /// `board_columns` estaba fuera de aquella lista —las zonas no sustituyen id
  /// por esa via, lo hace el propio apunte— y es justo la que se quedo colgada.
  static const _dondeMirar = <Sitio>[
    // EL TABLERO SE PREGUNTA POR `nacio_aqui`, NO POR EL PREFIJO DEL ID.
    //
    // Y ese detalle deshace un atasco que si no no tiene salida. Desde que el
    // aparato pone el id definitivo —un UUIDv7— `local-…` no distingue nada, asi
    // que esto devolvia 0: una zona creada sin senal cuyo apunte se descarto
    // quedaba **protegida para siempre y sin nada que la subiera**. La bajada se
    // negaba a borrarla (bien), pero lo unico que limpia la marca es una bajada,
    // y el ciclo no la reencolaba porque no la veia. El tablero de ese aparato no
    // se actualizaba nunca mas y el cartel decia «se sube primero» cuando no
    // habia nada que subiera.
    //
    // Mirando la marca, el ciclo la reencola, sube, la bajada la pone a 0 y el
    // atasco se deshace solo.
    Sitio('board_columns', 'zona del tablero', 'zonas del tablero',
        condicion: 'nacio_aqui = 1', seReconstruye: true),
    // Las demas siguen con el provisional: ahi el servidor todavia no deja que
    // el aparato ponga el id, asi que `local-…` sigue siendo la senal buena.
    //
    // Y ninguna de las tres se reconstruye: `volverAEncolar` sabe rehacer el
    // cuerpo de una zona del tablero desde la base, y de estas no. Por eso son
    // las unicas que se pueden dar por perdidas a mano — a una zona no hay que
    // renunciar, sube sola en cuanto haya senal.
    Sitio('routes', 'ruta', 'rutas'),
    Sitio('vehicles', 'vehículo', 'vehículos'),
    Sitio('warehouses', 'almacén', 'almacenes'),
  ];

  /// ¿Existe esa tabla en esta base?
  ///
  /// Las del Tablero no son de Drift: las crea la propia pantalla la primera vez
  /// que se abre (`pantallas/tablero/datos/esquema.dart`). En un aparato recien
  /// estrenado, o en el de alguien que nunca entra ahi, sencillamente no estan.
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

  /// QUE ES ESTAR HUERFANO, escrito UNA vez.
  ///
  /// Vive en una constante y no copiado en las dos consultas a proposito: son la
  /// misma pregunta —«¿que hay que volver a encolar?» y «¿cuanto hay?»— y dos
  /// copias que se separen darian un aviso que no cuadra con lo que se encola.
  ///
  /// Son TRES condiciones, y las tres hicieron falta:
  ///
  ///  1. **Id provisional.** Lo que se crea sin conexion lleva `local-…` hasta
  ///     que el servidor devuelve el suyo.
  ///
  ///  2. **Sin equivalencia.** Esta es la que faltaba y la que convertia esto en
  ///     un bucle. Un `local-…` con equivalencia YA SUBIO: el servidor contesto
  ///     y se anoto su id de verdad. Que la fila local siga con el provisional
  ///     no quiere decir nada — hasta hoy las zonas del tablero no se sustituian
  ///     hasta que alguien volviera a abrir esa pantalla. Sin esta condicion, una
  ///     zona subida y bien subida se volvia a encolar cada pocos minutos, y lo
  ///     unico que evitaba una zona repetida arriba era el nombre repetido: un
  ///     rechazo falso en la bandeja por un trabajo que SI habia llegado.
  ///
  ///  3. **Sin apunte que hable de ella.** Y son TRES estados, no dos:
  ///     `pendiente` va a subir sola; `rechazado` esta esperando a que una
  ///     persona decida y se puede reintentar a mano —volver a encolarla por
  ///     detras seria insistirle a un servidor que ya dijo que no—; y
  ///     `descartado` es esa persona habiendo decidido ya.
  ///
  ///     **`descartado` es el que faltaba, y su ausencia hacia un circulo.** Al
  ///     descartar un rechazo el apunte desaparecia, la fila se quedaba sin nada
  ///     vivo que la nombrara, esto la daba por huerfana y la volvia a encolar,
  ///     el servidor repetia su no y el rechazo estaba otra vez en la bandeja.
  ///     Jose lo vio como lo unico que se ve desde fuera: «los errores se
  ///     acumulan y nunca se borran» (29/09/2026). Un trabajo que una persona ha
  ///     dado por cerrado no esta colgado: esta cerrado.
  ///
  ///  4. **Sin renunciar.** La cuarta, del 29/09/2026. Las zonas del tablero
  ///     las reconstruye [volverAEncolar]; una ruta, un vehiculo o un almacen
  ///     no, asi que se quedaban contados en el aviso ambar de las siete
  ///     pantallas **para siempre y sin un boton**. El §4 del `CLAUDE.md` dice
  ///     que eso espera «hasta que una persona decida», y no habia con que
  ///     decidir. Ahora se puede dar por perdido ([darPorPerdido]), y esa
  ///     decision se anota en `renuncias`.
  static String _esHuerfana(Sitio sitio) =>
      '${sitio.condicion} '
      'AND NOT EXISTS (SELECT 1 FROM equivalencias e WHERE e.provisional = t.id) '
      'AND NOT EXISTS ('
      '  SELECT 1 FROM apuntes a WHERE a.provisional = t.id '
      "  AND a.estado IN ('pendiente', 'rechazado')"
      ') '
      'AND NOT EXISTS ('
      "  SELECT 1 FROM renuncias r WHERE r.tabla = '${sitio.tabla}' "
      '  AND r.id = t.id'
      ')';

  /// Y LA OTRA PREGUNTA, QUE **NO** ES LA MISMA — 29/09/2026.
  ///
  /// [_esHuerfana] contesta «¿esto existe solo aqui?», que es lo que se AVISA.
  /// Esta contesta «¿esto hay que volver a encolarlo?», que es lo que se HACE. Se
  /// parecen tanto que estuvieron escritas como una sola durante unas horas, y
  /// juntarlas se lleva por delante una de las dos:
  ///
  ///  * si el aviso hereda esta condicion, **descartar un rechazo apaga el
  ///    aviso** — y es mentira: esa ruta sigue sin haber subido y no va a subir.
  ///    Cambiar un error por un silencio no es arreglarlo.
  ///  * si el reencolado hereda la otra, **descartar devuelve el rechazo**: se
  ///    encola, el servidor repite su no, y el mismo error vuelve a la bandeja
  ///    minutos despues. Eso es lo que Jose vio como «los errores se acumulan y
  ///    nunca se borran».
  ///
  /// Asi que son dos, a proposito, y la unica diferencia es `descartado`: una
  /// persona que descarta dice **«no lo vuelvas a intentar»**, no dice «esto ya
  /// esta arriba». Para lo segundo esta [darPorPerdido], que es otro gesto.
  ///
  /// Las dos se atan con una prueba y no con este comentario (§3-bis):
  /// `test/nucleo/cola/descartar_no_lo_devuelve_test.dart`.
  static String _sePuedeReencolar(Sitio sitio) =>
      '${_esHuerfana(sitio)} '
      'AND NOT EXISTS ('
      '  SELECT 1 FROM apuntes a WHERE a.provisional = t.id '
      "  AND a.estado = 'descartado'"
      ')';

  /// Cuenta lo huerfano, por tipo. Vacio = no hay nada colgado.
  Future<List<TrabajoHuerfano>> mirar() async {
    final salida = <TrabajoHuerfano>[];
    for (final sitio in _dondeMirar) {
      try {
        final fila = await _base
            .customSelect(
              'SELECT count(*) AS cuantos FROM ${sitio.tabla} t '
              'WHERE ${_esHuerfana(sitio)}',
            )
            .getSingle();
        final cuantos = fila.read<int>('cuantos');
        if (cuantos > 0) salida.add(TrabajoHuerfano(sitio, cuantos));
      } on Object catch (e) {
        // Una tabla que no existe todavia —una version anterior del esquema— no
        // puede impedir mirar las demas. Lo peor que pasa es no contar esa.
        Registro.aviso('no se pudo mirar ${sitio.tabla} en busca de huérfanos: $e');
      }
    }
    return salida;
  }

  /// DAR POR PERDIDO lo colgado de un sitio. Devuelve cuantos se anotaron.
  ///
  /// Es la decision de una persona y no pasa sola nunca, igual que descartar un
  /// rechazo. Se usa cuando lo que hay aqui **ya no va a subir y ya no importa**:
  /// la ruta se rehizo en la web, el reparto de aquel dia se cerro a mano, el
  /// vehiculo se dio de alta por otro sitio.
  ///
  /// **No borra la fila.** Borrar una ruta local se lleva sus paradas y deja los
  /// pedidos apuntando a algo que no esta; y ademas, lo que se hizo aquel dia
  /// sigue siendo la unica explicacion de por que aquel reparto salio como
  /// salio. Lo que se quita es el aviso, no el dato — el mismo trato que
  /// [ColaDeSalida.darPorLeidoElDescarte] le da a los descartados.
  Future<int> darPorPerdido(Sitio sitio) async {
    final ids = await idsDe(sitio);
    if (ids.isEmpty) return 0;
    final cuando = DateTime.now().toIso8601String();
    for (final id in ids) {
      await _base.customStatement(
        'INSERT OR IGNORE INTO renuncias (tabla, id, cuando) '
        'VALUES (?1, ?2, ?3)',
        [sitio.tabla, id, cuando],
      );
    }
    // AVISO A MANO, porque `renuncias` no es una tabla de Drift: se crea al
    // abrir con SQL suelto (`BaseLocal.tablaDeRenuncias`), asi que un
    // `customStatement` no despierta a nadie. Sin esto el aviso ambar sigue
    // puesto en las siete pantallas hasta el tic siguiente del ciclo, y quien
    // acaba de darle al boton lee que no ha pasado nada.
    _base.notifyUpdates({const TableUpdate(tablaDeRenuncias)});

    // Queda dicho, que es lo unico que lo explica manana.
    Registro.aviso(
      '${ids.length} ${ids.length == 1 ? sitio.uno : sitio.varios} '
      'dados por perdidos a mano: ${ids.join(', ')}',
    );
    return ids.length;
  }

  /// Los ids de lo que se AVISA: lo que existe solo aqui, se diga lo que se diga
  /// de sus apuntes. Es el conjunto sobre el que decide una persona.
  Future<List<String>> idsDe(Sitio sitio) => _idsCon(sitio, _esHuerfana(sitio));

  /// Los ids de lo que se puede VOLVER A ENCOLAR, que es un subconjunto: de aqui
  /// quedan fuera los que alguien ya descarto. Ver [_sePuedeReencolar].
  Future<List<String>> idsParaReencolar(Sitio sitio) =>
      _idsCon(sitio, _sePuedeReencolar(sitio));

  Future<List<String>> _idsCon(Sitio sitio, String donde) async {
    final filas = await _base
        .customSelect('SELECT t.id AS id FROM ${sitio.tabla} t WHERE $donde')
        .get();
    return filas.map((f) => f.read<String>('id')).toList();
  }

  /// LAS RUTAS, que son el caso de «esto ya no sube y hay que poder cerrarlo».
  ///
  /// Se saca a constante por lo mismo que [zonasDelTablero]: la pantalla y las
  /// pruebas necesitan nombrar el sitio, y escribirlo otra vez a mano seria una
  /// segunda copia de la condicion.
  static const rutas = Sitio('routes', 'ruta', 'rutas');

  /// La zona del tablero, que es la unica que hoy se sabe reconstruir.
  static const zonasDelTablero = Sitio(
    'board_columns',
    'zona del tablero',
    'zonas del tablero',
    condicion: 'nacio_aqui = 1',
  );

  /// VUELVE A ENCOLAR lo que se quedo colgado, reconstruyendo el apunte **desde
  /// la fila local**. Devuelve cuantos apuntes se pusieron.
  ///
  /// Lo llama el ciclo, no una pantalla: comprobar la diferencia entre lo de
  /// aqui y lo de arriba es el trabajo del sincronizador, y tiene que pasar solo
  /// —en cuanto haya senal— sin que nadie se acuerde de pulsar nada.
  ///
  /// **No hace bucle.** Si el servidor vuelve a decir que no, el apunte queda en
  /// `rechazado`, que cuenta como vivo: la vuelta siguiente ya no lo ve huerfano
  /// y no lo encola otra vez. Se queda a la vista con su motivo, esperando a que
  /// una persona decida, que es la regla de la casa.
  ///
  /// Hoy reconstruye **el tablero**, que es el caso que se dio y el unico cuyo
  /// cuerpo se puede rehacer entero desde la base. Los demas se cuentan y se
  /// dicen: es mejor un aviso que nombra lo que hay que mirar que un apunte
  /// inventado a medias.
  /// **Esto no puede tumbar el ciclo NUNCA.** Comprobar la diferencia es una
  /// ayuda; subir y bajar es la razon de ser. Un aparato que todavia no ha
  /// abierto el Tablero no tiene siquiera esas tablas —las crea la pantalla la
  /// primera vez que se abre—, y sin esta guarda el ciclo entero moria con un
  /// «no such table: board_columns» en cuanto alguien entraba y no pasaba por
  /// ahi: ni subia su cola, ni bajaba el dia. Lo cazo `ciclo_test` antes de
  /// salir de aqui, y es exactamente el fallo que este fichero venia a evitar,
  /// del reves.
  Future<int> volverAEncolar(ColaDeSalida cola) async {
    try {
      return await _volverAEncolar(cola);
    } on Object catch (e, pila) {
      Registro.fallo('no se pudo volver a encolar lo huérfano: $e', e, pila);
      return 0;
    }
  }

  Future<int> _volverAEncolar(ColaDeSalida cola) async {
    if (!await _hayTabla('board_columns')) return 0;
    var puestos = 0;
    for (final id in await idsParaReencolar(zonasDelTablero)) {
      final columna = await _base
          .customSelect(
            'SELECT branch_id, nombre, vehicle_id FROM board_columns '
            'WHERE id = ?1',
            variables: [Variable<String>(id)],
          )
          .getSingleOrNull();
      if (columna == null) continue;

      final sucursal = columna.read<String>('branch_id');
      // LA ZONA PRIMERO. Lleva su `local-…` como provisional, que es la bisagra:
      // cuando suba y el servidor devuelva el id de verdad, las colocaciones de
      // detras lo llevan sustituido en su cuerpo y no acaban en una columna que
      // no existe en ningun sitio.
      await cola.encolar(
        metodo: 'POST',
        ruta: '/board/columns?branchId=$sucursal',
        cuerpo: <String, Object?>{
          // EL ID VA EN EL CUERPO. Sin el, el servidor pone uno nuevo y esto
          // crea una SEGUNDA zona con el mismo nombre: el indice unico la
          // rechaza, y un rechazo no se reintenta. El desatasco acababa en un
          // rechazo falso y en un atasco permanente.
          'id': id,
          'nombre': columna.read<String>('nombre'),
          'vehiculoId': ?columna.read<String?>('vehicle_id'),
        },
        provisional: id,
      );
      puestos++;

      // Y DETRAS SUS PEDIDOS, en su orden. Sin esto subiria una zona vacia, que
      // es peor que no subir nada: parece que el trabajo llego.
      final dentro = await _base
          .customSelect(
            'SELECT order_id, posicion FROM board_placements '
            'WHERE column_id = ?1 ORDER BY posicion ASC',
            variables: [Variable<String>(id)],
          )
          .get();
      for (final fila in dentro) {
        await cola.encolar(
          metodo: 'PUT',
          ruta: '/board/placements/${fila.read<String>('order_id')}',
          cuerpo: <String, Object?>{
            'columnaId': id,
            'posicion': fila.read<int>('posicion'),
          },
        );
        puestos++;
      }

      Registro.aviso(
        'zona del tablero $id: estaba en el aparato y no en el servidor, y no le '
        'quedaba ningún apunte que la subiera. Se vuelve a encolar con sus '
        '${dentro.length} pedidos',
      );
    }

    puestos += await _tarjetasSueltas(cola);
    return puestos;
  }

  /// LAS TARJETAS HUERFANAS DE ZONAS QUE **SI** ESTAN ARRIBA.
  ///
  /// Es el mismo atasco de las zonas, por el otro lado, y se quedo abierto: se
  /// arrastra una tarjeta sin señal sobre una zona que ya existe en el servidor,
  /// su apunte se descarta —o se pierde—, y entonces no hay nada que la suba. La
  /// bajada se niega para no borrarla (bien), pero lo unico que limpia su marca
  /// es una bajada… que esta bloqueada. **Tablero parado sin salida**, igual que
  /// el de la zona «Vista» del 16/09 y por la misma razon.
  ///
  /// El bucle de arriba no las coge porque va por zonas: una tarjeta sobre una
  /// zona que ya subio no esta dentro de ninguna zona huerfana.
  ///
  /// Se reconstruye lo mismo que escribe `RepositorioTablero.colocar`: la zona y
  /// el sitio. Y NO se tocan las de zonas huerfanas —esas ya van detras de su
  /// zona, con el orden que les toca— para no encolarlas dos veces.
  Future<int> _tarjetasSueltas(ColaDeSalida cola) async {
    if (!await _hayTabla('board_placements')) return 0;
    final filas = await _base
        .customSelect(
          'SELECT p.order_id AS pedido, p.column_id AS zona, p.posicion AS sitio '
          'FROM board_placements p '
          'JOIN board_columns c ON c.id = p.column_id '
          'WHERE p.nacio_aqui = 1 '
          // Su zona SI esta arriba: las de zonas huerfanas ya salieron detras de
          // la suya en el bucle de arriba.
          '  AND c.nacio_aqui = 0 '
          // Y no le queda ningun apunte que hable de ella. Se busca por la
          // ruta, que es donde el apunte nombra al pedido. Los tres estados son
          // los mismos que en `_esHuerfana` y por el mismo motivo: `descartado`
          // es una persona que ya decidio, y volver a encolarlo le devuelve el
          // rechazo que acaba de quitar.
          '  AND NOT EXISTS ('
          '    SELECT 1 FROM apuntes a '
          "    WHERE a.ruta = '/board/placements/' || p.order_id "
          "      AND a.estado IN ('pendiente', 'rechazado', 'descartado')"
          '  )',
        )
        .get();

    for (final f in filas) {
      await cola.encolar(
        metodo: 'PUT',
        ruta: '/board/placements/${f.read<String>('pedido')}',
        cuerpo: <String, Object?>{
          'columnaId': f.read<String>('zona'),
          'posicion': f.read<int>('sitio'),
        },
      );
    }
    if (filas.isNotEmpty) {
      Registro.aviso(
        '${filas.length} tarjetas estaban colocadas en el aparato y no en el '
        'servidor, sin ningún apunte que las subiera. Se vuelven a encolar',
      );
    }
    return filas.length;
  }
}

/// Un sitio donde puede quedar trabajo sin subir.
class Sitio {
  const Sitio(
    this.tabla,
    this.uno,
    this.varios, {
    this.condicion = "t.id LIKE 'local-%'",
    this.seReconstruye = false,
  });

  final String tabla;

  /// Que significa, EN ESTA TABLA, «esto todavia no esta arriba».
  ///
  /// No es igual en todas y por eso se dice aqui en vez de darlo por hecho. El
  /// tablero tiene su marca propia (`nacio_aqui`) desde que el aparato pone el
  /// id definitivo; las demas siguen con el `local-…` provisional, porque ahi el
  /// servidor todavia no deja que el aparato nombre nada.
  final String condicion;

  /// ¿SABE EL CICLO REHACER ESTO SOLO?
  ///
  /// La zona del tablero si: [Huerfanos.volverAEncolar] reconstruye su cuerpo
  /// desde la base y la sube en cuanto haya senal, asi que su aviso es de paso
  /// y ofrecer «darlo por perdido» seria tirar trabajo que iba a llegar.
  ///
  /// Las demas no, y por eso su aviso se queda puesto hasta que alguien decida.
  final bool seReconstruye;

  /// Como se llama en singular y en plural, para poder DECIRLO. «1 zona del
  /// tablero», «3 vehículos». Un mensaje que diga «3 filas de board_columns» no
  /// se lo puede leer nadie.
  final String uno;
  final String varios;
}

/// Cuanto trabajo colgado hay de un tipo.
class TrabajoHuerfano {
  const TrabajoHuerfano(this._sitio, this.cuantos);

  final Sitio _sitio;
  final int cuantos;

  String get tabla => _sitio.tabla;

  /// El sitio, para poder ofrecer —o no— darlo por perdido desde la pantalla.
  Sitio get sitio => _sitio;

  bool get seReconstruye => _sitio.seReconstruye;

  /// «1 zona del tablero» · «3 vehículos».
  String get texto => '$cuantos ${cuantos == 1 ? _sitio.uno : _sitio.varios}';
}

/// Lo de todos los tipos junto, ya escrito para pintarlo.
extension ResumenDeHuerfanos on List<TrabajoHuerfano> {
  bool get hayAlguno => isNotEmpty;

  int get total => fold(0, (a, h) => a + h.cuantos);

  /// «1 zona del tablero y 2 vehículos». Se nombra CADA tipo: «3 cosas sin
  /// subir» no le dice a nadie que ir a mirar.
  String get texto {
    final partes = map((h) => h.texto).toList();
    // VACIO ES VACIO, y hace falta decirlo: sin esta linea, `partes.sublist(0,
    // -1)` revienta con un `RangeError` en cuanto alguien pinta esto sin mirar
    // antes si hay algo — y lo normal es que no haya nada.
    if (partes.isEmpty) return '';
    if (partes.length == 1) return partes.first;
    return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
  }
}
