import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/datos/servicio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// ACTUALIZAR NO PUEDE BORRAR TRABAJO SIN SUBIR. NUNCA.
///
/// `descargar` reemplaza la foto entera del tablero: borra las columnas y las
/// colocaciones de esa sucursal y pone las del servidor. Si se ejecuta con
/// trabajo de aquí que allí no está, ese trabajo desaparece — y desaparece en
/// silencio, que es lo peor.
///
/// La guarda existía, pero **preguntaba lo que no era**: miraba
/// `cuantosPendientes()`, o sea «¿queda algo EN LA COLA?». La zona «Vista» de
/// Jose, con sus cinco pedidos, ya no tenía apunte —se había descartado—, así
/// que la cola estaba a cero, la guarda dejó pasar y el `DELETE` se la llevó.
/// Sus palabras, 16/09/2026: «si le doy al boton de actualizar me borra todo lo
/// sin conexion y deberia de informarme o algo para decirme lo q voy a perder si
/// le doy al boton… eso no lo puede perder por ninguna circunstancia por q es
/// trabajo perdido».
void main() {
  late BaseLocal base;
  late ServicioTablero servicio;
  var llamadas = 0;

  const sucursal = 'hab-1';

  setUp(() async {
    base = baseDePrueba();
    await EsquemaTablero.asegurar(base);
    llamadas = 0;
    final servidor = ServidorFalso((peticion) async {
      llamadas++;
      // El servidor no sabe nada de lo de aquí: devuelve un tablero VACÍO, que
      // es exactamente el caso que borraba.
      return RespuestaFalsa(200, const {
        'columnas': <Object?>[],
        'colocados': <Object?>[],
      });
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = servidor;
    servicio = ServicioTablero(
      base,
      ClienteApi(dio: dio, esperas: const <Duration>[]),
      RegistroDeFrescura(base),
    );
  });

  tearDown(() => base.close());

  /// Una zona que NACIÓ AQUÍ: existe en este aparato y en ningún otro sitio.
  ///
  /// `nacio_aqui = 1` es lo que lo dice, y no el id. Se probó a mirar el prefijo
  /// `local-…` y no vale: desde que el aparato pone el id definitivo —un
  /// UUIDv7— ese prefijo no distingue nada, y la guarda quedaba ciega justo para
  /// todo lo que se cree a partir de ahora.
  Future<void> zonaLocal(String id, {List<String> pedidos = const []}) async {
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES (?1, ?2, 'Vista', 1, '2026-09-16T10:00:00.000', "
      "'2026-09-16T10:00:00.000', 1)",
      [id, sucursal],
    );
    for (var i = 0; i < pedidos.length; i++) {
      await base
          .into(base.orders)
          .insertOnConflictUpdate(
            OrdersCompanion.insert(
              id: pedidos[i],
              customerName: 'Cliente ${pedidos[i]}',
              address: 'Calle 1',
            ),
          );
      await base.customStatement(
        'INSERT INTO board_placements (order_id, column_id, posicion, colocado_at, '
        'updated_at, nacio_aqui) '
        "VALUES (?1, ?2, ?3, '2026-09-16T10:00:00.000', "
        "'2026-09-16T10:00:00.000', 1)",
        [pedidos[i], id, i],
      );
    }
  }

  Future<int> cuantasZonas() async {
    final f = await base
        .customSelect('SELECT count(*) AS n FROM board_columns')
        .getSingle();
    return f.read<int>('n');
  }

  test(
    'con la zona HUÉRFANA —sin apunte que la suba— no se baja nada',
    () async {
      // Éste es el caso de Jose, exacto: el apunte se descartó, la cola está a
      // cero, y la zona sigue aquí con sus cinco pedidos.
      await zonaLocal('local-vista', pedidos: ['p1', 'p2', 'p3', 'p4', 'p5']);
      expect(await base.cuantosPendientes(), 0, reason: 'la cola está vacía');

      final r = await servicio.descargar(sucursal);

      expect(r.seBajo, isFalse);
      expect(
        await cuantasZonas(),
        1,
        reason: 'la zona sigue aquí: actualizar NO puede llevarse trabajo',
      );
      expect(
        llamadas,
        0,
        reason: 'ni siquiera se le pregunta al servidor: se corta antes',
      );
    },
  );

  test('y DICE qué lo impide, con nombre', () async {
    await zonaLocal('local-vista', pedidos: ['p1']);
    final r = await servicio.descargar(sucursal);

    // Sin esto, pulsar «actualizar» no hacía nada visible y quien estaba delante
    // no sabía si es que no había cambios o que la aplicación se estaba
    // protegiendo. Volvía a pulsar.
    expect(r.porQue, isNotNull);
    expect(
      r.porQue,
      contains('zona del tablero'),
      reason: 'tiene que nombrar QUÉ se perdería, no decir «hay cambios»',
    );
  });

  test('con la cola llena tampoco, y lo dice', () async {
    final cola = ColaDeSalida(base);
    await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=$sucursal',
      cuerpo: const {'nombre': 'Vista'},
      provisional: 'local-vista',
    );
    await zonaLocal('local-vista');

    final r = await servicio.descargar(sucursal);
    expect(r.seBajo, isFalse);
    expect(r.porQue, contains('sin subir'));
    expect(await cuantasZonas(), 1);
  });

  test(
    'sin nada pendiente SÍ se baja: es lo normal estando en línea',
    () async {
      // La guarda no puede pasarse de lista: con todo arriba, actualizar tiene que
      // traer la foto del servidor, que es para lo que está el botón.
      final r = await servicio.descargar(sucursal);

      expect(r.seBajo, isTrue);
      expect(r.porQue, isNull);
      expect(llamadas, 1);
    },
  );

  test('una zona YA SUBIDA no impide actualizar', () async {
    // ## Esta prueba EXIGÍA la pérdida, y por eso está escrita así ahora
    //
    // Nació sembrando `018f2c7e-…-7000-…` —la forma exacta del UUIDv7 que pone el
    // aparato— con el comentario «id de verdad y sin apuntes: esto está arriba»,
    // y exigiendo que se borrara. Pero ese id ya no significa «está arriba»: es
    // justo el que lleva una zona recién creada sin señal. La prueba consagraba
    // el fallo que venía a impedir.
    //
    // Lo que de verdad significa «ya subió» es `nacio_aqui = 0`, que pone la
    // propia bajada al escribir lo del servidor.
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES ('018f2c7e-0000-7000-8000-000000000001', ?1, 'Ya subida', 1, "
      "'2026-09-16T10:00:00.000', '2026-09-16T10:00:00.000', 0)",
      [sucursal],
    );

    final r = await servicio.descargar(sucursal);
    expect(r.seBajo, isTrue);
    expect(
      await cuantasZonas(),
      0,
      reason:
          'vino del servidor y el servidor ya no la tiene: se va, y eso SÍ '
          'es correcto — la borró otra persona',
    );
  });

  test('una zona con UUIDv7 recién creada aquí SÍ está protegida', () async {
    // El caso que el prefijo `local-…` dejaba pasar. Es el mismo id de la prueba
    // de arriba; lo único que cambia es quién lo escribió.
    await zonaLocal('018f2c7e-0000-7000-8000-000000000001', pedidos: ['p1']);

    final r = await servicio.descargar(sucursal);
    expect(r.seBajo, isFalse);
    expect(await cuantasZonas(), 1);
  });

  test('una TARJETA arrastrada aquí, sobre una zona ya subida, también', () async {
    // Las colocaciones no tienen id propio —su clave es el pedido—, así que
    // mirando ids no había forma de protegerlas. Se perdían enteras.
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES ('c-arriba', ?1, 'Ya subida', 1, '2026-09-16T10:00:00.000', "
      "'2026-09-16T10:00:00.000', 0)",
      [sucursal],
    );
    await base
        .into(base.orders)
        .insertOnConflictUpdate(
          OrdersCompanion.insert(
            id: 'p9',
            customerName: 'Cliente',
            address: 'Calle 1',
          ),
        );
    await base.customStatement(
      'INSERT INTO board_placements (order_id, column_id, posicion, colocado_at, '
      'updated_at, nacio_aqui) '
      "VALUES ('p9', 'c-arriba', 0, '2026-09-16T10:00:00.000', "
      "'2026-09-16T10:00:00.000', 1)",
      [],
    );

    final r = await servicio.descargar(sucursal);
    expect(r.seBajo, isFalse);
    expect(r.porQue, contains('tarjeta'));
  });

  test('un RECHAZO que espera a una persona tampoco se borra', () async {
    // `cuantosPendientes()` sólo cuenta los pendientes, así que un apunte
    // rechazado —el estado hecho para ser visible y esperar a que alguien
    // decida— dejaba la guarda ciega. Se borraba con un botón y sin avisar.
    final cola = ColaDeSalida(base);
    await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=$sucursal',
      cuerpo: const {'nombre': 'Vista'},
      provisional: 'local-vista',
    );
    await base.customStatement(
      "UPDATE apuntes SET estado = 'rechazado', motivo = 'el servidor dijo que no'",
    );
    await zonaLocal('local-vista', pedidos: ['p1']);

    expect(
      await base.cuantosPendientes(),
      0,
      reason: 'rechazado no es pendiente',
    );
    final r = await servicio.descargar(sucursal);
    expect(r.seBajo, isFalse);
    expect(await cuantasZonas(), 1);
  });

  /// DE PUNTA A PUNTA, por el camino de verdad.
  ///
  /// Las de arriba siembran las filas a mano, así que comprueban la GUARDA pero no
  /// que quien crea de verdad marque la fila. Con ellas solas, cambiar el `1` por
  /// un `0` en `RepositorioTablero.crearColumna` pasaba en verde y el trabajo se
  /// volvía a perder. Ésta cierra el círculo: se crea con el repositorio y se
  /// arrastra con él, como hace la pantalla.
  group('creado por el camino de verdad', () {
    test('una zona creada con el repositorio queda protegida', () async {
      final repo = RepositorioTablero(base, ColaDeSalida(base));
      await repo.crearColumna(sucursalId: sucursal, nombre: 'Reparto Norte');

      // Se vacía la cola: es el caso de Jose, con el apunte ya descartado.
      await base.customStatement('DELETE FROM apuntes');
      expect(await base.cuantosPendientes(), 0);

      final r = await servicio.descargar(sucursal);
      expect(
        r.seBajo,
        isFalse,
        reason: 'la creó este aparato y arriba no está: actualizar la borraría',
      );
      expect(await cuantasZonas(), 1);
    });

    test('una tarjeta arrastrada con el repositorio, igual', () async {
      final repo = RepositorioTablero(base, ColaDeSalida(base));
      final id = await repo.crearColumna(
        sucursalId: sucursal,
        nombre: 'Reparto Sur',
      );
      await base
          .into(base.orders)
          .insertOnConflictUpdate(
            OrdersCompanion.insert(
              id: 'p7',
              customerName: 'Cliente',
              address: 'Calle 1',
              // Con domicilio cobrado y cotizado: sin ellos `colocar` lo rechaza
              // como el servidor, y aqui se prueba el pestillo, no eso.
              facturaDomicilio: const Value(1),
              pedidoCosto: const Value(1),
            ),
          );
      await repo.colocar(pedidoId: 'p7', columnaId: id);

      // La zona se da por subida para aislar la tarjeta: lo que tiene que
      // proteger aquí es LA COLOCACIÓN, que no tiene id propio.
      await base.customStatement(
        'UPDATE board_columns SET nacio_aqui = 0 WHERE id = ?1',
        [id],
      );
      await base.customStatement('DELETE FROM apuntes');

      final r = await servicio.descargar(sucursal);
      expect(r.seBajo, isFalse);
      expect(r.porQue, contains('tarjeta'));
    });
  });

  /// EL AVISO SE RETIRA. Un aviso que no se va deja de ser un aviso.
  ///
  /// Jose pidió que la aplicación le dijera qué va a perder si pulsa actualizar
  /// («debería de informarme o algo»). La otra mitad de eso es que el cartel
  /// desaparezca cuando ya no es verdad: si se queda pegado, la próxima vez que
  /// diga algo nadie se lo va a creer.
  group('el aviso se retira', () {
    test('cuando ya no queda nada propio, deja de decirlo', () async {
      await zonaLocal('local-vista', pedidos: ['p1']);
      final primera = await servicio.descargar(sucursal);
      expect(primera.porQue, isNotNull);

      // Sube: la bajada del servidor la marcaría como suya, pero aquí basta con
      // que deje de ser propia.
      await base.customStatement('UPDATE board_columns SET nacio_aqui = 0');
      await base.customStatement('UPDATE board_placements SET nacio_aqui = 0');

      final segunda = await servicio.descargar(sucursal);
      expect(
        segunda.porQue,
        isNull,
        reason: 'ya no hay nada que perder: el cartel no puede seguir ahí',
      );
    });
  });

  /// TODO LO QUE ESCRIBE DE ESTE LADO TIENE QUE MARCAR, no sólo lo que crea.
  ///
  /// `nacio_aqui` se puso primero en los dos INSERT —crear una zona y arrastrar una
  /// tarjeta— y eso dejaba fuera cuatro caminos que también escriben aquí: renombrar,
  /// elegir camión, reordenar y mover todo a otra columna. Los cuatro son UPDATE sobre
  /// filas que vinieron del servidor, así que se quedaban a 0 y **el cambio se deshacía
  /// solo al actualizar**, sin decir nada.
  ///
  /// `moverTodo` es el peor de los cuatro: es la salida natural de «esta columna no cabe
  /// en el camión, creo otra y mando lo que sobra», y por ahí pasa también borrar una zona
  /// mandando sus tarjetas a otra.
  group('todo lo que escribe aquí marca', () {
    late RepositorioTablero repo;

    /// Una zona TAL COMO LA DEJA LA BAJADA: vino del servidor, `nacio_aqui = 0`.
    Future<void> zonaDelServidor(
      String id,
      String nombre,
    ) => base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES (?1, ?2, ?3, 1, '2026-09-16T10:00:00.000', "
      "'2026-09-16T10:00:00.000', 0)",
      [id, sucursal, nombre],
    );

    setUp(() => repo = RepositorioTablero(base, ColaDeSalida(base)));

    /// Hace el gesto, vacía la cola —el caso del apunte descartado— y mira si la
    /// bajada se niega.
    Future<bool> seBajaDespuesDe(Future<void> Function() gesto) async {
      await gesto();
      await base.customStatement('DELETE FROM apuntes');
      return (await servicio.descargar(sucursal)).seBajo;
    }

    test('renombrar', () async {
      await zonaDelServidor('c1', 'Centro');
      expect(
        await seBajaDespuesDe(
          () => repo.renombrarColumna('c1', 'Centro Norte'),
        ),
        isFalse,
        reason:
            'actualizar traería «Centro» otra vez y el renombrado se pierde',
      );
    });

    test('elegir camión', () async {
      // Con un camión DE VERDAD: `elegirCamion(c1, null)` sobre una zona que ya
      // no tenía ninguno no cambia nada, y un gesto que no cambia nada no debe
      // marcar — eso se comprueba en el grupo de abajo.
      await zonaDelServidor('c1', 'Centro');
      expect(
        await seBajaDespuesDe(() => repo.elegirCamion('c1', 'v-1')),
        isFalse,
      );
    });

    test('reordenar', () async {
      await zonaDelServidor('c1', 'Centro');
      await zonaDelServidor('c2', 'Vista');
      expect(
        await seBajaDespuesDe(
          () => repo.reordenarColumnas(sucursal, ['c2', 'c1']),
        ),
        isFalse,
        reason: 'el orden decide por dónde empieza el camión',
      );
    });

    test('mover todo a otra columna', () async {
      await zonaDelServidor('c1', 'Centro');
      await zonaDelServidor('c2', 'Vista');
      for (final p in ['p1', 'p2']) {
        await base
            .into(base.orders)
            .insertOnConflictUpdate(
              OrdersCompanion.insert(
                id: p,
                customerName: 'Cliente',
                address: 'Calle 1',
              ),
            );
        await base.customStatement(
          'INSERT INTO board_placements (order_id, column_id, posicion, colocado_at, '
          'updated_at, nacio_aqui) '
          "VALUES (?1, 'c1', 0, '2026-09-16T10:00:00.000', "
          "'2026-09-16T10:00:00.000', 0)",
          [p],
        );
      }

      expect(
        await seBajaDespuesDe(() async {
          await repo.moverTodo('c1', 'c2');
        }),
        isFalse,
        reason: 'el traslado se deshacía en silencio: las dos tarjetas volvían a c1',
      );
    });
  });

  /// EL PESTILLO SE ABRE AL SUBIR. Si no, arregla un caso y rompe el normal.
  ///
  /// `nacio_aqui` lo ponía quien creaba, y lo único que lo quitaba era la bajada del
  /// tablero… que se niega a bajar mientras haya un 1. O sea que **una zona que subía
  /// perfectamente dejaba el tablero congelado para siempre**, con un cartel diciendo «no
  /// está en el servidor» sobre algo que sí estaba.
  ///
  /// Y el ciclo empeoraba las cosas: la veía huérfana, la reencolaba, se creaba una
  /// segunda zona con el mismo nombre, el índice único la rechazaba, y un rechazo no se
  /// reintenta. Atasco permanente y un rechazo falso en la bandeja.
  ///
  /// Es un fallo más grave que el que `nacio_aqui` venía a arreglar: aquél perdía datos en
  /// un caso de esquina, éste rompía el camino normal para todos.
  group('el pestillo se abre al subir', () {
    test(
      'una zona que sube deja de estar marcada, y actualizar funciona',
      () async {
        final cola = ColaDeSalida(base);
        final repo = RepositorioTablero(base, cola);
        final id = await repo.crearColumna(
          sucursalId: sucursal,
          nombre: 'Reparto Norte',
        );
        expect(
          (await servicio.descargar(sucursal)).seBajo,
          isFalse,
          reason: 'todavía no ha subido: se protege, y eso está bien',
        );

        // El servidor dice que sí. Con el id del aparato, devuelve el mismo.
        final apunte = (await cola.lote()).first;
        await cola.resolver(
          apunte.clave,
          ResultadoApunte(estado: EstadoResultado.aplicado, id: id),
        );

        expect(
          (await servicio.descargar(sucursal)).seBajo,
          isTrue,
          reason: 'ya está arriba: el tablero TIENE que poder actualizarse',
        );
      },
    );

    test('una tarjeta que sube, igual', () async {
      final cola = ColaDeSalida(base);
      final repo = RepositorioTablero(base, cola);
      final id = await repo.crearColumna(
        sucursalId: sucursal,
        nombre: 'Reparto Sur',
      );
      await base
          .into(base.orders)
          .insertOnConflictUpdate(
            OrdersCompanion.insert(
              id: 'p5',
              customerName: 'Cliente',
              address: 'Calle 1',
              // Con domicilio cobrado y cotizado: sin ellos `colocar` lo rechaza
              // como el servidor, y aqui se prueba el pestillo, no eso.
              facturaDomicilio: const Value(1),
              pedidoCosto: const Value(1),
            ),
          );
      await repo.colocar(pedidoId: 'p5', columnaId: id);

      for (final a in await cola.lote()) {
        await cola.resolver(
          a.clave,
          ResultadoApunte(
            estado: EstadoResultado.aplicado,
            id: a.provisional == null ? null : id,
          ),
        );
      }

      expect((await servicio.descargar(sucursal)).seBajo, isTrue);
    });
  });

  /// Los gestos que NO cambian nada no marcan.
  ///
  /// Abrir el desplegable del camión y elegir «ninguno» sobre una zona que ya no tenía, o
  /// arrastrar una columna y soltarla donde estaba, congelaba el tablero. Marcaban por
  /// ejecutarse, no por cambiar algo.
  group('un gesto que no cambia nada no marca', () {
    test(
      'renombrar al mismo nombre, elegir el mismo camión, mismo orden',
      () async {
        final repo = RepositorioTablero(base, ColaDeSalida(base));
        await base.customStatement(
          'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
          'updated_at, nacio_aqui) '
          "VALUES ('c1', ?1, 'Centro', 1, '2026-09-16T10:00:00.000', "
          "'2026-09-16T10:00:00.000', 0)",
          [sucursal],
        );

        await repo.renombrarColumna('c1', 'Centro');
        await repo.elegirCamion('c1', null);
        await repo.reordenarColumnas(sucursal, ['c1']);
        await base.customStatement('DELETE FROM apuntes');

        expect(
          (await servicio.descargar(sucursal)).seBajo,
          isTrue,
          reason: 'no cambió nada: no hay nada que proteger',
        );
      },
    );
  });
}
