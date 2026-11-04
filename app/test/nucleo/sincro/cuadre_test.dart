import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/sincro/cuadre.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// EL CUADRE DIARIO CON EL SERVIDOR (28/10/2026, Jose: «el sync se hizo para algo»).
///
/// El caso real: el 21/10/2026 el servidor perdió 828 lápidas de facturas de Santiago y el aparato de Maikel siguió
/// enseñando facturas que ya no existen. Aquí se ata que el cuadre las quita, que NO toca lo vivo ni lo que está
/// en uso (lo creado en el aparato, lo que nombra un apunte pendiente), que las guardas frenan una lista dudosa y
/// que un apunte rechazado cuya factura ya no existe se cierra solo, sin borrarse.
void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late List<String> quitadas;

  setUp(() {
    base = baseDePrueba();
    cola = ColaDeSalida(base);
    quitadas = [];
  });
  tearDown(() => base.close());

  Cuadre cuadre(Map<String, Object?> respuesta) => Cuadre(
    cliente: clienteFalso((p) async => RespuestaFalsa(200, respuesta)),
    base: base,
    cola: cola,
    quitar: (coleccion, id) async {
      quitadas.add('$coleccion:$id');
      if (coleccion == Colecciones.pedidos) {
        await base.customStatement("DELETE FROM orders WHERE id = '$id'");
      }
    },
  );

  Future<void> factura(
    String id,
    String numero, {
    String cliente = 'Cliente',
  }) => base.customStatement(
    'INSERT INTO orders (id, customer_name, address, weight, archivado, factura_numero) '
    "VALUES ('$id', '$cliente', 'Calle 1', 10, 0, '$numero')",
  );

  Map<String, Object?> servidor({
    List<String> orders = const [],
    List<String> truncado = const [],
    Map<String, List<String>> otras = const {},
  }) => <String, Object?>{
    'colecciones': <String, Object?>{
      'orders': orders,
      for (final e in otras.entries) e.key: e.value,
    },
    'truncado': truncado,
    'faltan': <String>[],
    'hasta': '2026-10-28T12:00:00Z',
  };

  Future<int> cuantas() async => (await base.select(base.orders).get()).length;

  test('quita la factura fantasma y deja la viva, con su número y su cliente para decirlo', () async {
    await factura('viva', '47682', cliente: 'Yelina');
    await factura('fantasma', '46461', cliente: 'Magela');

    final r = await cuadre(servidor(orders: ['viva'])).cuadrar();

    expect(quitadas, ['orders:fantasma']);
    expect(await cuantas(), 1);
    expect(r.facturas, 1);
    expect(r.quitadas.single.etiqueta, 'Factura 46461 · Magela');
    expect(r.hayQueDecir, isTrue);
  });

  test('NO toca lo creado en este aparato (local-…) ni lo que nombra un apunte pendiente', () async {
    await factura('viva', '1');
    await factura('local-abc', '2');
    await factura('en-ruta-sin-subir', '3');
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: 'k1',
            hechoAt: DateTime(2026, 10, 28),
            metodo: 'PUT',
            ruta: '/board/placements/en-ruta-sin-subir',
            cuerpo: '{}',
          ),
        );

    await cuadre(servidor(orders: ['viva'])).cuadrar();

    expect(
      quitadas,
      isEmpty,
      reason: 'ni lo local ni lo que tiene trabajo sin subir',
    );
    expect(await cuantas(), 3);
  });

  test('una RUTA hecha en el aparato (UUIDv7, sin local-) no se quita mientras su alta sea pendiente, rechazada o en revisión', () async {
    // 04/11/2026: la ruta ya no nace con `local-`. Lo que la protege es que un apunte vivo la nombre; si no, el cuadre
    // se la llevaría aunque su alta siga en la bandeja esperando a una persona.
    const viva = '01a1a72e-6cc0-7abc-8def-0123456789ab';
    const pendiente = '01a1a72e-6cc0-7abc-8def-0123456789ac';
    const rechazada = '01a1a72e-6cc0-7abc-8def-0123456789ad';
    const enRevision = '01a1a72e-6cc0-7abc-8def-0123456789ae';
    const fantasma = '01a1a72e-6cc0-7abc-8def-0123456789af';
    for (final id in [viva, pendiente, rechazada, enRevision, fantasma]) {
      await base.customStatement("INSERT INTO routes (id) VALUES ('$id')");
    }
    var n = 0;
    for (final e in {
      pendiente: EstadoApunte.pendiente,
      rechazada: EstadoApunte.rechazado,
      enRevision: EstadoApunte.enRevision,
    }.entries) {
      await base
          .into(base.apuntes)
          .insert(
            ApuntesCompanion.insert(
              clave: 'k${n++}',
              hechoAt: DateTime(2026, 11, 4),
              metodo: 'POST',
              ruta: '/routes',
              cuerpo: '{"id":"${e.key}"}',
              provisional: Value(e.key),
              estado: Value(e.value),
            ),
          );
    }

    await cuadre(
      servidor(
        orders: ['x'],
        otras: {
          'routes': [viva],
        },
      ),
    ).cuadrar();

    expect(quitadas, [
      'routes:$fantasma',
    ], reason: 'solo la que ningun apunte vivo nombra');
  });

  test('una lista VACÍA o TRUNCADA del servidor no borra nada (es un error, no «no hay nada»)', () async {
    await factura('a', '1');
    await factura('b', '2');

    final vacia = await cuadre(servidor(orders: [])).cuadrar();
    expect(quitadas, isEmpty);
    expect(vacia.noCuadradas.any((m) => m.contains('orders')), isTrue);

    final truncada = await cuadre(servidor(orders: ['a'], truncado: ['orders']))
        .cuadrar();
    expect(
      quitadas,
      isEmpty,
      reason: 'una lista a medias borraría la «b», que está viva',
    );
    expect(truncada.noCuadradas.any((m) => m.contains('orders')), isTrue);
    expect(await cuantas(), 2);
  });

  test(
    'un cuadre que borraría casi todo se frena: algo va mal en la respuesta',
    () async {
      for (var i = 0; i < 30; i++) {
        await factura('f$i', '$i');
      }
      final r = await cuadre(servidor(orders: ['otra-cosa'])).cuadrar();
      expect(quitadas, isEmpty);
      expect(await cuantas(), 30);
      expect(
        r.noCuadradas.any((m) => m.contains('iba a quitar 30 de 30')),
        isTrue,
      );
    },
  );

  test('el apunte RECHAZADO de una factura que ya no existe se cierra solo: descartado, no borrado, con su motivo', () async {
    await factura('fantasma', '46461');
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: 'rechazado-1',
            hechoAt: DateTime(2026, 10, 27),
            metodo: 'PUT',
            ruta: '/board/placements/fantasma',
            cuerpo: '{"columnaId":"c1","posicion":1}',
            estado: const Value(EstadoApunte.rechazado),
            motivo: const Value('Esa factura no existe o no es de tu sucursal'),
          ),
        );
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: 'rechazado-otro',
            hechoAt: DateTime(2026, 10, 27),
            metodo: 'PUT',
            ruta: '/board/placements/otra-que-vive',
            cuerpo: '{}',
            estado: const Value(EstadoApunte.rechazado),
            motivo: const Value('x'),
          ),
        );

    final r = await cuadre(servidor(orders: ['otra-que-vive'])).cuadrar();

    expect(r.apuntesCerrados, 1);
    final a = await (base.select(
      base.apuntes,
    )..where((x) => x.clave.equals('rechazado-1'))).getSingle();
    expect(
      a.estado,
      EstadoApunte.descartado,
      reason: 'una decisión se ESCRIBE, no se borra',
    );
    expect(
      a.motivo,
      'Esa factura no existe o no es de tu sucursal',
      reason: 'el motivo no se toca',
    );
    final otro = await (base.select(
      base.apuntes,
    )..where((x) => x.clave.equals('rechazado-otro'))).getSingle();
    expect(
      otro.estado,
      EstadoApunte.rechazado,
      reason: 'el de una factura que vive sigue a la vista',
    );
  });

  test('cuadra también rutas, clientes y camiones, no sólo facturas', () async {
    await base.customStatement(
      "INSERT INTO routes (id, status) VALUES ('r-viva', 'planned'), ('r-fantasma', 'planned')",
    );
    await base.customStatement(
      "INSERT INTO customers (id, name, lat, lng, synced_at) VALUES ('c-viva', 'A', 0, 0, 0), ('c-fantasma', 'B', 0, 0, 0)",
    );

    final r = await cuadre(
      servidor(
        orders: ['x'],
        otras: {
          'routes': ['r-viva'],
          'customers': ['c-viva'],
        },
      ),
    ).cuadrar();

    expect(quitadas.toSet(), {'routes:r-fantasma', 'customers:c-fantasma'});
    expect(r.quitadas.length, 2);
  });

  test('LO QUE FALTA: si el servidor tiene una factura que el aparato no, lo dice (y la bajada fuerza una carga completa)', () async {
    await factura('viva', '1');

    final r = await cuadre(servidor(orders: ['viva', 'nunca-llego'])).cuadrar();

    expect(r.faltaban, {Colecciones.pedidos: 1});
    expect(r.totalQueFaltaba, 1);
    expect(r.hayQueDecir, isTrue);
    expect(quitadas, isEmpty, reason: 'lo que falta no se «quita»: se pide');
  });

  test('si no falta nada, no dice nada', () async {
    await factura('viva', '1');
    final r = await cuadre(servidor(orders: ['viva'])).cuadrar();
    expect(r.faltaban, isEmpty);
    expect(r.hayQueDecir, isFalse);
  });
}
