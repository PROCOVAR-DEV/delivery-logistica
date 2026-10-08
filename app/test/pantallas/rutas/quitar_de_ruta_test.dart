// «QUITAR DE RUTA» Y LA PARADA FANTASMA — Amado, 07/10/2026 (incidencia 2).
//
// Quitar un pedido de una ruta planificada soltaba `routeId` y dejaba
// `ultimaRutaId`: la parada quitada seguia saliendo en la hoja, sumaba en el peso
// y en el importe —que agrupan por esa columna— y a la vez estaba en
// disponibles. Dos sitios a la vez. Ahora se suelta TAMBIEN `ultimaRutaId` y las
// lecturas de «paradas de la ruta R» piden, en la rama del `routeId` nulo, que
// haya `resultado` (un devuelto o cancelado lo tiene; uno quitado, no).
//
// Todo se siembra DENTRO de cada prueba y los textos de los rechazos van
// escritos a mano, iguales a los del servidor (`quitarParadaPlanificada`).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/importe_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/datos/peso_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart' show Cajon;
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;
  late ConsultasRutas consultas;

  setUp(() {
    base = baseDePrueba();
    final reloj = RelojFalso(DateTime.utc(2026, 10, 7, 16));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(base, cola, reloj: reloj.leer);
    consultas = ConsultasRutas(base);
  });
  tearDown(() => base.close());

  /// Una ruta planificada R1 con dos paradas (p1: 100 kg y 10 $, p2: 200 kg y
  /// 20 $), ambas con punto de entrega para poder volver a ofrecerse.
  Future<void> sembrarLaRuta() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1');
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Ana',
      rutaId: 'R1',
      orden: 1,
      peso: 100,
      pedidoCosto: 10,
      endLat: 21.38,
      endLng: -77.91,
    );
    await sembrarPedido(
      base,
      id: 'p2',
      cliente: 'Beto',
      rutaId: 'R1',
      orden: 2,
      peso: 200,
      pedidoCosto: 20,
      endLat: 21.39,
      endLng: -77.92,
    );
  }

  Future<List<String>> hoja() async => [
    for (final p in await consultas.paradasDe('R1')) p.id,
  ];

  test('quitar suelta las DOS columnas y la parada sale de la hoja', () async {
    await sembrarLaRuta();
    expect(await hoja(), ['p1', 'p2']);

    await acciones.quitarParada('R1', 'p1');

    final p1 = await (base.select(
      base.orders,
    )..where((o) => o.id.equals('p1'))).getSingle();
    expect(p1.routeId, isNull);
    expect(p1.ultimaRutaId, isNull, reason: 'ultimaRutaId es la que la ataba');
    expect(await hoja(), ['p2']);
    expect([for (final p in await consultas.mirarParadasDe('R1').first) p.id], [
      'p2',
    ]);
  });

  test('ya no cuenta en el peso, el importe ni las paradas de la ruta', () async {
    await sembrarLaRuta();
    await acciones.quitarParada('R1', 'p1');

    expect((await pesoPorRuta(base).first)['R1'], 200);
    final importe = (await importePorRuta(base).first)['R1']!;
    expect(importe.total, 20);
    expect(importe.paradas, 1);
    expect((await consultas.paradasPorRuta().first)['R1'], 1);
  });

  test('vuelve a la lista de disponibles', () async {
    await sembrarLaRuta();
    expect(
      [for (final p in await consultas.disponibles(sucursalId: 'B1')) p.id],
      isEmpty,
      reason: 'mientras va en la ruta, esta ocupado',
    );

    await acciones.quitarParada('R1', 'p1');

    expect(
      [for (final p in await consultas.disponibles(sucursalId: 'B1')) p.id],
      ['p1'],
    );
  });

  test('y encola el DELETE para subirlo', () async {
    await sembrarLaRuta();
    await acciones.quitarParada('R1', 'p1');
    final lote = await cola.lote();
    expect(lote.map((a) => '${a.metodo} ${a.ruta}').toList(), [
      'DELETE /routes/R1/stops/p1',
    ]);
  });

  // LA PAREJA: lo que SI es parada de la ruta sin tener `routeId`.
  test('un DEVUELTO sigue en su hoja: soltó la ruta pero con resultado', () async {
    await sembrarLaRuta();
    await base.customStatement(
      "UPDATE orders SET route_id = NULL, resultado = 'devuelto' WHERE id = 'p2'",
    );
    expect(await hoja(), ['p1', 'p2']);
    expect((await pesoPorRuta(base).first)['R1'], 300);
  });

  // LA GUARDA QUE NINGUNA PRUEBA DE ARRIBA TOCABA (auditoria del 08/10/2026): quitar
  // por `quitarParada` ya anula LAS DOS columnas, asi que la parada sale por la rama
  // de `routeId` y nunca llega a preguntarse por `resultado`. Esa guarda sólo
  // importa para un fantasma ANTIGUO: `routeId` nulo, `ultimaRutaId = R1` y SIN
  // resultado, que es como lo dejaba el quitar de antes de este arreglo. Se siembra
  // a mano y se mira por LAS DOS lecturas, la de una vez y la de la hoja en vivo:
  // la auditoria mutó sólo la segunda y quedó verde.
  test('un fantasma ANTIGUO (sin ruta, sin resultado) no sale en NINGUNA de las dos hojas',
      () async {
    await sembrarLaRuta();
    await base.customStatement(
      "UPDATE orders SET route_id = NULL, resultado = NULL WHERE id = 'p2'",
    );
    expect(await hoja(), ['p1'],
        reason: 'la hoja de una vez no cuenta lo que no tiene ruta ni resultado');
    expect(
      [for (final p in await consultas.mirarParadasDe('R1').first) p.id],
      ['p1'],
      reason: 'la hoja EN VIVO tampoco: es la que se pinta en pantalla',
    );
    // Y la pareja: con resultado vuelve a ser un devuelto y sí cuenta, en las dos.
    await base.customStatement("UPDATE orders SET resultado = 'devuelto' WHERE id = 'p2'");
    // El SQL a pelo no avisa a los streams de Drift: sin esto la hoja en vivo devuelve
    // la lectura de antes, guardada en su caché, y la prueba miente.
    base.markTablesUpdated({base.orders});
    expect(await hoja(), ['p1', 'p2']);
    expect(
      [for (final p in await consultas.mirarParadasDe('R1').first) p.id],
      ['p1', 'p2'],
    );
  });

  test('cerrar no acepta una marca para la parada QUITADA', () async {
    await sembrarLaRuta();
    await acciones.quitarParada('R1', 'p1');
    // Un fantasma de antes del arreglo: sin `routeId`, `ultimaRutaId` suelto y
    // sin resultado. No es parada de la ruta.
    await base.customStatement(
      "UPDATE orders SET ultima_ruta_id = 'R1' WHERE id = 'p1'",
    );
    expect(await hoja(), ['p2'], reason: 'ni siquiera el fantasma viejo sale');
    await expectLater(
      () => acciones.cerrar('R1', const [
        MarcaDeParada(pedidoId: 'p1', resultado: ResultadoParada.entregado),
      ]),
      throwsA(
        isA<RechazoLocal>().having(
          (r) => r.mensaje,
          'mensaje',
          'No vino ningún resultado',
        ),
      ),
    );
  });

  group('los rechazos son los LITERALES del servidor', () {
    test('en una ruta que ya salió', () async {
      await sembrarLaRuta();
      await base.customStatement(
        "UPDATE routes SET status = 'in_progress' WHERE id = 'R1'",
      );
      await expectLater(
        () => acciones.quitarParada('R1', 'p1'),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Sólo se pueden retirar paradas de una ruta planificada',
          ),
        ),
      );
      expect(await hoja(), ['p1', 'p2'], reason: 'no se toca nada');
    });

    test('un pedido que no va en esa ruta, o ya fue retirado', () async {
      await sembrarLaRuta();
      await acciones.quitarParada('R1', 'p1');
      for (final pedido in ['p1', 'no-existe']) {
        await expectLater(
          () => acciones.quitarParada('R1', pedido),
          throwsA(
            isA<RechazoLocal>().having(
              (r) => r.mensaje,
              'mensaje',
              'El pedido no pertenece a una ruta planificada o ya fue retirado',
            ),
          ),
        );
      }
    });

    test('una parada con resultado puesto no se quita', () async {
      await sembrarLaRuta();
      await base.customStatement(
        "UPDATE orders SET resultado = 'entregado' WHERE id = 'p1'",
      );
      await expectLater(
        () => acciones.quitarParada('R1', 'p1'),
        throwsA(isA<RechazoLocal>()),
      );
      expect(await hoja(), ['p1', 'p2']);
    });
  });

  // A5: LA PREGUNTA VA EN UN CAJON, Y CONTESTAR «NO» O CERRAR NO QUITA NADA.
  group('la pregunta de antes de quitar', () {
    Future<bool?> preguntar(
      WidgetTester tester,
      Future<void> Function() despues,
    ) async {
      bool? respuesta;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (contexto) => TextButton(
                onPressed: () async {
                  respuesta = await preguntarAntesDeQuitar(
                    contexto,
                    cliente: 'Ana',
                    conduce: 'PTB25-261005-1479',
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pump(const Duration(milliseconds: 400));
      await despues();
      return respuesta;
    }

    testWidgets('sale en un CAJON, nombra a quien sale y dice a donde vuelve', (
      tester,
    ) async {
      await preguntar(tester, () async {
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(Cajon), findsOneWidget);
        expect(find.text('Quitar de la ruta'), findsOneWidget);
        expect(find.text('Ana · Conduce: PTB25-261005-1479'), findsOneWidget);
        expect(find.textContaining('vuelve a pedidos disponibles'), findsOne);
        expect(find.text('Sí, quitar «Ana» de la ruta'), findsOneWidget);
        expect(find.text('No, dejarlo en la ruta'), findsOneWidget);
        expect(find.byTooltip('Cerrar'), findsOneWidget);
        await tester.tap(find.text('No, dejarlo en la ruta'));
        await tester.pump(const Duration(milliseconds: 400));
      });
    });

    testWidgets('«No» contesta que no', (tester) async {
      final r = await preguntar(tester, () async {
        await tester.tap(find.text('No, dejarlo en la ruta'));
        await tester.pump(const Duration(milliseconds: 400));
      });
      expect(r, isFalse);
    });

    testWidgets('cerrar con la ✕ sin contestar es NO', (tester) async {
      final r = await preguntar(tester, () async {
        await tester.tap(find.byTooltip('Cerrar'));
        await tester.pump(const Duration(milliseconds: 400));
      });
      expect(r, isFalse);
    });

    testWidgets('«Sí, quitar» contesta que si', (tester) async {
      final r = await preguntar(tester, () async {
        await tester.tap(find.text('Sí, quitar «Ana» de la ruta'));
        await tester.pump(const Duration(milliseconds: 400));
      });
      expect(r, isTrue);
    });
  });

  // Sin esto la importacion de `Value`/`ImporteDeRuta` quedaria sin uso si se
  // retira alguna de arriba: se deja anclada la pareja que importa.
  test('el cero cotizado de una parada sigue sumando 0, no «sin cotizar»', () async {
    await sembrarLaRuta();
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(pedidoCosto: Value(0)),
    );
    final importe = (await importePorRuta(base).first)['R1']!;
    expect(importe.sinCotizar, 0);
    expect(importe.total, 20);
  });
}
