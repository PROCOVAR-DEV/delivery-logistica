import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';

/// LO QUE EL APARATO HIZO SIN CONEXIÓN Y NO IBA A SUBIR SOLO.
///
/// El sincronizador reenviaba una COLA y nunca comparaba los dos lados. En cuanto un
/// apunte desaparecía —descartado a mano, o perdido— el dato local se quedaba huérfano:
/// existía en el teléfono, no existía arriba, y nada lo volvía a intentar jamás.
///
/// Visto el 16/09/2026 con tres pantallas diciendo cosas distintas del mismo aparato: el
/// Tablero enseñaba la zona «Vista» con sus cinco pedidos y su marca «sin subir»; entregar
/// el día decía «Todo entregado»; el Panel decía «Todo al día». Y el servidor, que era el
/// único que tenía razón: «Galaxy A16 de Jose — nunca ha subido».
///
/// Palabras de Jose: «el sync es el encargado de eso, para controlar los desfases de cada
/// lado… si no, siempre van a estar desfasadas la online, que es la de verdad, contra la
/// offline, que se fue sin conexión con unos datos que después tiene que incorporar».
void main() {
  late BaseLocal base;
  late Huerfanos huerfanos;
  late ColaDeSalida cola;

  setUp(() async {
    base = baseDePrueba();
    // Las tablas del tablero no son de Drift: las crea el propio Tablero la
    // primera vez que se abre. Aqui se piden a mano porque esta prueba las mira
    // sin pasar por esa pantalla.
    await EsquemaTablero.asegurar(base);
    huerfanos = Huerfanos(base);
    cola = ColaDeSalida(base);
  });

  tearDown(() => base.close());

  Future<void> zonaLocal(
    String id, {
    String sucursal = 'hab-1',
    String nombre = 'Vista',
    List<String> pedidos = const [],
  }) async {
    // `nacio_aqui = 1`: la creó este aparato. Es lo que dice «esto no está
    // arriba», y NO el prefijo del id — desde que el aparato pone el id
    // definitivo (UUIDv7), `local-…` no distingue nada.
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES (?1, ?2, ?3, 1, '2026-09-16T10:00:00.000', "
      "'2026-09-16T10:00:00.000', 1)",
      [id, sucursal, nombre],
    );
    for (var i = 0; i < pedidos.length; i++) {
      // El pedido tiene que existir: `board_placements` apunta a `orders`.
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

  test('una zona local SIN apunte que la suba es trabajo huérfano', () async {
    await zonaLocal('local-abc', pedidos: ['p1', 'p2']);

    final visto = await huerfanos.mirar();
    expect(visto.hayAlguno, isTrue);
    expect(visto.total, 1);
    expect(
      visto.texto,
      '1 zona del tablero',
      reason: 'el aviso tiene que nombrar QUÉ hay que ir a mirar',
    );
  });

  test('con su apunte pendiente NO está huérfana: va a subir sola', () async {
    await zonaLocal('local-abc');
    await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=hab-1',
      cuerpo: const {'nombre': 'Vista'},
      provisional: 'local-abc',
    );

    expect((await huerfanos.mirar()).hayAlguno, isFalse);
  });

  test('con su apunte RECHAZADO tampoco: está esperando a una persona', () async {
    // Un rechazo se queda a la vista con su motivo hasta que alguien decida, y esa persona
    // todavía puede reintentarlo. Contarlo como huérfano sería volver a encolarlo por
    // detrás cada cinco minutos: un bucle contra un servidor que ya dijo que no.
    await zonaLocal('local-abc');
    await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=hab-1',
      cuerpo: const {'nombre': 'Vista'},
      provisional: 'local-abc',
    );
    // Marcado rechazado como lo deja la subida al recibir un «no» del servidor.
    await base.customStatement(
      "UPDATE apuntes SET estado = 'rechazado', motivo = ?1 "
      'WHERE provisional = ?2',
      ['el servidor dijo que no', 'local-abc'],
    );

    expect(
      (await huerfanos.mirar()).hayAlguno,
      isFalse,
      reason: 'reintentarlo solo sería un bucle, no una defensa',
    );
  });

  test(
    'una zona YA SUBIDA no es huérfana: la bajada le quitó la marca',
    () async {
      await zonaLocal('col-de-verdad-1');
      await base.customStatement('UPDATE board_columns SET nacio_aqui = 0');
      expect((await huerfanos.mirar()).hayAlguno, isFalse);
    },
  );

  test('una zona con UUIDv7 creada aquí SÍ es huérfana', () async {
    // El caso que el prefijo `local-…` dejaba pasar, y que dejaba el tablero en
    // un callejón sin salida: protegida para siempre —la bajada se negaba a
    // borrarla, bien— y sin nada que la subiera, porque esto no la veía. Lo
    // único que limpia la marca es una bajada, y la bajada estaba bloqueada.
    await zonaLocal('018f2c7e-0000-7000-8000-000000000001', pedidos: ['p1']);

    expect((await huerfanos.mirar()).hayAlguno, isTrue);
    expect(
      await huerfanos.volverAEncolar(cola),
      2,
      reason:
          'el ciclo la reencola, sube, la bajada la limpia y el atasco se '
          'deshace solo',
    );
  });

  test(
    'en un aparato sin Tablero no revienta: contesta que no hay nada',
    () async {
      // Las tablas del Tablero las crea la propia pantalla la primera vez que se abre, así
      // que en un aparato recién estrenado NO EXISTEN. Sin esta guarda, el ciclo entero
      // moría con «no such table: board_columns» en cuanto alguien entraba sin pasar por
      // ahí: ni subía su cola, ni bajaba el día. Comprobar la diferencia es una ayuda;
      // subir y bajar es la razón de ser, y una ayuda no puede tumbar la razón de ser.
      final virgen = baseDePrueba();
      addTearDown(virgen.close);
      final sinTablero = Huerfanos(virgen);

      expect((await sinTablero.mirar()).hayAlguno, isFalse);
      expect(await sinTablero.volverAEncolar(ColaDeSalida(virgen)), 0);
    },
  );

  group('volver a encolar', () {
    test('rehace la zona Y sus pedidos, en su orden', () async {
      await zonaLocal('local-abc', pedidos: ['p1', 'p2', 'p3']);

      final puestos = await huerfanos.volverAEncolar(cola);
      expect(puestos, 4, reason: '1 zona + 3 pedidos');

      final apuntes = await base.select(base.apuntes).get();
      expect(apuntes.first.metodo, 'POST');
      expect(apuntes.first.ruta, '/board/columns?branchId=hab-1');
      expect(
        apuntes.first.provisional,
        'local-abc',
        reason:
            'sin el provisional, las colocaciones de detrás acaban en una columna '
            'que no existe en ningún sitio',
      );
      expect(
        apuntes.skip(1).map((a) => a.ruta).toList(),
        [
          '/board/placements/p1',
          '/board/placements/p2',
          '/board/placements/p3',
        ],
        reason: 'y en el orden en que se colocaron, que es el orden de visita',
      );
    });

    test('una zona vacía sube sola, sin inventarse pedidos', () async {
      await zonaLocal('local-vacia');
      expect(await huerfanos.volverAEncolar(cola), 1);
    });

    test('NO la vuelve a encolar en la vuelta siguiente', () async {
      // Ésta es la guarda contra el bucle. El ciclo corre cada pocos minutos: si cada
      // vuelta volviera a encolar lo mismo, la cola crecería sola hasta reventar.
      await zonaLocal('local-abc', pedidos: ['p1']);

      expect(await huerfanos.volverAEncolar(cola), 2);
      expect(
        await huerfanos.volverAEncolar(cola),
        0,
        reason: 'ya tiene apunte vivo: dejó de estar huérfana',
      );
      expect((await base.select(base.apuntes).get()).length, 2);
    });

    test('no toca lo que ya tiene apunte', () async {
      await zonaLocal('local-con-apunte');
      await cola.encolar(
        metodo: 'POST',
        ruta: '/board/columns?branchId=hab-1',
        cuerpo: const {'nombre': 'Vista'},
        provisional: 'local-con-apunte',
      );
      await zonaLocal('local-huerfana', nombre: 'Otra');

      expect(await huerfanos.volverAEncolar(cola), 1);
      final nuevos = (await base.select(base.apuntes).get()).where(
        (a) => a.provisional == 'local-huerfana',
      );
      expect(nuevos.length, 1);
    });
  });

  /// UNA TARJETA HUÉRFANA SOBRE UNA ZONA QUE SÍ ESTÁ ARRIBA.
  ///
  /// Es el mismo atasco de las zonas, por el otro lado, y se quedó abierto: se arrastra una
  /// tarjeta sin señal sobre una zona que ya existe en el servidor, su apunte se descarta, y
  /// entonces no hay nada que la suba. La bajada se niega para no borrarla —bien—, pero lo
  /// único que limpia su marca es una bajada… que está bloqueada. Tablero parado sin salida,
  /// igual que el de la zona «Vista» del 16/09 y por la misma razón.
  ///
  /// El bucle de las zonas no las coge: va por zonas, y una tarjeta sobre una zona que ya
  /// subió no está dentro de ninguna zona huérfana.
  group('tarjetas sueltas', () {
    /// Una zona que YA SUBIÓ: `nacio_aqui = 0`.
    Future<void> zonaDelServidor(String id) => base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES (?1, ?2, 'Centro', 1, '2026-09-17T09:00:00.000', "
      "'2026-09-17T09:00:00.000', 0)",
      [id, 'hab-1'],
    );

    Future<void> tarjetaLocal(String pedido, String zona, int sitio) async {
      await base
          .into(base.orders)
          .insertOnConflictUpdate(
            OrdersCompanion.insert(
              id: pedido,
              customerName: 'Cliente',
              address: 'Calle 1',
            ),
          );
      await base.customStatement(
        'INSERT INTO board_placements (order_id, column_id, posicion, colocado_at, '
        'updated_at, nacio_aqui) '
        "VALUES (?1, ?2, ?3, '2026-09-17T09:00:00.000', "
        "'2026-09-17T09:00:00.000', 1)",
        [pedido, zona, sitio],
      );
    }

    test('se vuelve a encolar, con su zona y su sitio', () async {
      await zonaDelServidor('c-arriba');
      await tarjetaLocal('p1', 'c-arriba', 3);

      expect(await huerfanos.volverAEncolar(cola), 1);

      final apunte = (await base.select(base.apuntes).get()).single;
      expect(apunte.metodo, 'PUT');
      expect(apunte.ruta, '/board/placements/p1');
      expect(
        apunte.cuerpo,
        contains('"posicion":3'),
        reason: 'el sitio importa: es el orden de visita del camión',
      );
      expect(apunte.cuerpo, contains('"columnaId":"c-arriba"'));
    });

    test('NO la vuelve a encolar en la vuelta siguiente', () async {
      await zonaDelServidor('c-arriba');
      await tarjetaLocal('p1', 'c-arriba', 0);

      expect(await huerfanos.volverAEncolar(cola), 1);
      expect(
        await huerfanos.volverAEncolar(cola),
        0,
        reason: 'el ciclo corre cada pocos minutos: la cola crecería sola',
      );
    });

    test('una tarjeta que ya subió no se toca', () async {
      await zonaDelServidor('c-arriba');
      await tarjetaLocal('p1', 'c-arriba', 0);
      await base.customStatement('UPDATE board_placements SET nacio_aqui = 0');

      expect(await huerfanos.volverAEncolar(cola), 0);
    });

    test('las de una zona huérfana NO se encolan dos veces', () async {
      // Ésas ya salen detrás de su zona, con el orden que les toca.
      await zonaLocal('local-vista', pedidos: ['p1', 'p2']);

      expect(
        await huerfanos.volverAEncolar(cola),
        3,
        reason: '1 zona + 2 tarjetas, no 5',
      );
    });

    test('en un aparato sin Tablero no revienta', () async {
      final virgen = baseDePrueba();
      addTearDown(virgen.close);
      expect(await Huerfanos(virgen).volverAEncolar(ColaDeSalida(virgen)), 0);
    });
  });

  // LA BANDEJA DE REVISIÓN (09/10/2026, `docs/bandeja-de-revision.md` B.5).
  //
  // `huerfanos.dart` decide qué filas locales están «vivas» con listas de estados, y son
  // TRES consultas distintas (`_esHuerfana`, `_sePuedeReencolar`, `_tarjetasSueltas`).
  // Lo entregado a revisión (`enRevision`) y lo que el revisor descartó
  // (`descartadoPorRevisor`) tienen que estar en ellas, o el ciclo reencola como huérfano
  // lo que ya está en una bandeja: el bucle del 29/09/2026 con otro nombre. Una prueba por
  // consulta, para que quitar el estado de UNA sola salga roja.
  group('la bandeja de revisión', () {
    Future<String> apunteDe(String ruta, EstadoApunte estado, {String? provisional}) async {
      final clave = await cola.encolar(
        metodo: ruta.startsWith('/board/placements') ? 'PUT' : 'POST',
        ruta: ruta,
        cuerpo: const {'a': 1},
        provisional: provisional,
      );
      await base.customStatement(
        'UPDATE apuntes SET estado = ?1 WHERE clave = ?2',
        [estado.name, clave],
      );
      return clave;
    }

    Future<void> zonaDelServidor(String id) => base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES (?1, 'hab-1', ?1, 1, '2026-10-08T09:00:00.000', "
      "'2026-10-08T09:00:00.000', 0)",
      [id],
    );

    Future<void> tarjetaLocal(String pedido, String zona) async {
      await base.into(base.orders).insertOnConflictUpdate(
        OrdersCompanion.insert(id: pedido, customerName: 'C', address: 'Calle 1'),
      );
      await base.customStatement(
        'INSERT INTO board_placements (order_id, column_id, posicion, colocado_at, '
        'updated_at, nacio_aqui) '
        "VALUES (?1, ?2, 0, '2026-10-08T09:00:00.000', '2026-10-08T09:00:00.000', 1)",
        [pedido, zona],
      );
    }

    // --- SQL 1: `_esHuerfana`. ---
    test('SQL 1 · una zona con su apunte ENTREGADO no está huérfana ni se reencola', () async {
      await zonaLocal('local-abc', pedidos: ['p1']);
      await apunteDe(
        '/board/columns?branchId=hab-1',
        EstadoApunte.enRevision,
        provisional: 'local-abc',
      );

      expect(
        (await huerfanos.mirar()).hayAlguno,
        isFalse,
        reason: 'está en la bandeja de un administrador: ni se avisa ni se repite',
      );
      expect(await huerfanos.idsParaReencolar(Huerfanos.zonasDelTablero), isEmpty);
      expect(await huerfanos.volverAEncolar(cola), 0);
      expect(
        (await base.select(base.apuntes).get()).length,
        1,
        reason: 'no se encoló nada nuevo: reentregarlo duplicaría el trabajo en la bandeja',
      );
    });

    // --- SQL 2: `_sePuedeReencolar`. ---
    test('SQL 2 · lo que el REVISOR descartó se avisa como huérfano pero NO se reencola', () async {
      await zonaLocal('local-abc', pedidos: ['p1']);
      await apunteDe(
        '/board/columns?branchId=hab-1',
        EstadoApunte.descartadoPorRevisor,
        provisional: 'local-abc',
      );

      expect(
        (await huerfanos.mirar()).hayAlguno,
        isTrue,
        reason: 'sigue sin estar arriba: apagar el aviso sería cambiar un error por un silencio',
      );
      expect(
        await huerfanos.idsParaReencolar(Huerfanos.zonasDelTablero),
        isEmpty,
        reason: 'una decisión se ESCRIBE: reencolarlo devolvería el trabajo a la bandeja',
      );
      expect(await huerfanos.volverAEncolar(cola), 0);
    });

    // --- SQL 3: `_tarjetasSueltas`. ---
    for (final estado in [EstadoApunte.enRevision, EstadoApunte.descartadoPorRevisor]) {
      test('SQL 3 · una tarjeta suelta con su apunte ${estado.name} NO se reencola', () async {
        await zonaDelServidor('c-arriba');
        await tarjetaLocal('p1', 'c-arriba');
        await apunteDe('/board/placements/p1', estado);

        expect(await huerfanos.volverAEncolar(cola), 0);
        expect((await base.select(base.apuntes).get()).length, 1);
      });
    }

    test('SQL 3 · la pareja: la misma tarjeta SIN apunte sí se reencola', () async {
      await zonaDelServidor('c-arriba');
      await tarjetaLocal('p1', 'c-arriba');

      expect(await huerfanos.volverAEncolar(cola), 1);
    });

    // --- TODO estado del enum está clasificado. ---
    //
    // Es la guarda del día que alguien añada un estado: tiene que decidir aquí, con una
    // fila en esta tabla, qué hacen con él las tres consultas. Sin la fila falla el primer
    // `expect`; con la fila mal puesta fallan los de abajo.
    test('cada valor de EstadoApunte está clasificado, para las tres consultas', () async {
      // estado: (¿se AVISA como huérfano?, ¿se REENCOLA?, ¿se reencola su tarjeta suelta?)
      const clasificado = <EstadoApunte, (bool, bool, bool)>{
        EstadoApunte.pendiente: (false, false, false),
        EstadoApunte.rechazado: (false, false, false),
        EstadoApunte.enRevision: (false, false, false),
        EstadoApunte.descartado: (true, false, false),
        EstadoApunte.descartadoPorRevisor: (true, false, false),
        // Un aplicado sin equivalencia (el servidor no devolvió id) no tiene dueño.
        EstadoApunte.aplicado: (true, true, true),
      };
      expect(
        clasificado.keys.toSet(),
        EstadoApunte.values.toSet(),
        reason: 'se añadió un estado y nadie decidió qué hace con lo huérfano',
      );

      for (final MapEntry(key: estado, value: esperado) in clasificado.entries) {
        final z = 'local-${estado.name}';
        await zonaLocal(z);
        await apunteDe('/board/columns?branchId=hab-1', estado, provisional: z);
        final porZona = await huerfanos.mirar();
        expect(porZona.hayAlguno, esperado.$1, reason: 'se avisa: ${estado.name}');
        expect(
          (await huerfanos.idsParaReencolar(Huerfanos.zonasDelTablero)).contains(z),
          esperado.$2,
          reason: 'se reencola: ${estado.name}',
        );
        // Limpio para el siguiente estado.
        await base.customStatement('DELETE FROM board_columns');
        await base.customStatement('DELETE FROM apuntes');
      }

      for (final estado in clasificado.keys) {
        await zonaDelServidor('c-${estado.name}');
        await tarjetaLocal('p-${estado.name}', 'c-${estado.name}');
        await apunteDe('/board/placements/p-${estado.name}', estado);
      }
      // Todas juntas: solo se encola la tarjeta de los estados que no tienen dueño.
      final antes = (await base.select(base.apuntes).get()).map((a) => a.clave).toSet();
      final esperadas = {
        for (final e in clasificado.entries)
          if (e.value.$3) '/board/placements/p-${e.key.name}',
      };
      expect(await huerfanos.volverAEncolar(cola), esperadas.length);
      final nuevos = (await base.select(base.apuntes).get())
          .where((a) => !antes.contains(a.clave))
          .map((a) => a.ruta)
          .toSet();
      expect(nuevos, esperadas);
    });
  });

  test('sin nada colgado, el texto es VACÍO y no revienta', () {
    // `partes.sublist(0, -1)` con la lista vacía lanza un `RangeError`, y esto
    // se pinta justo donde lo normal es que no haya nada: la franja de estado y
    // el cajón de entregar el día, en las siete pantallas.
    expect(const <TrabajoHuerfano>[].texto, isEmpty);
    expect(const <TrabajoHuerfano>[].hayAlguno, isFalse);
    expect(const <TrabajoHuerfano>[].total, 0);
  });
}
