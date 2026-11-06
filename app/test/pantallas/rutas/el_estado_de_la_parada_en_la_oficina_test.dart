// EL ESTADO DE LA PARADA EN LA OFICINA (issue 26 de Amado, 06/11/2026): la tarjeta de «Ver paradas» y
// la parada del cierre de ruta dicen si la entrega esta pendiente, entregada (cobrada o no), no
// entregada (con su motivo) o cancelada. El estado sale de UNA funcion (`estadoDeParada`); aqui se
// ata que cada sitio la usa y que el cobro baja de `orders.cobro_entrega` (esquema 18).
//
// Dentro del cuerpo de cada prueba se siembra (§5 del CLAUDE.md).
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'cierre_widget_test.dart' show asentar, desmontar;

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 11, 6, 10);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Cinco paradas, una por estado. R1 completada: el cierre se MIRA (solo lectura).
  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', estado: EstadoRuta.completada);
    final casos = <(String, String?, String?, String?)>[
      ('p1', null, null, null),
      ('p2', 'entregado', 'cobrado', null),
      ('p3', 'entregado', 'no_cobrado', null),
      ('p4', 'devuelto', 'no_cobrado', 'El cliente cerró'),
      ('p5', 'cancelado', null, 'Se anuló'),
    ];
    for (final (i, (id, resultado, cobro, nota)) in casos.indexed) {
      await sembrarPedido(
        base,
        id: id,
        cliente: 'Cliente ${i + 1}',
        rutaId: 'R1',
        ultimaRutaId: 'R1',
        orden: i + 1,
        endLat: 21.1 + i,
        endLng: -77.1,
      );
      await (base.update(base.orders)..where((o) => o.id.equals(id))).write(
        OrdersCompanion(
          resultado: Value(resultado),
          cobroEntrega: Value(cobro),
          resultadoNota: Value(nota),
          resultadoAt: Value(resultado == null ? null : ahora),
        ),
      );
    }
  }

  Finder en(String texto, Finder dentro) =>
      find.descendant(of: dentro, matching: find.text(texto));

  testWidgets(
    'la tarjeta de la parada pone la etiqueta de cada estado, con el motivo si no se entrego',
    (tester) async {
      await sembrar();
      final filas = {
        for (final p in await base.select(base.orders).get()) p.id: p,
      };
      tester.view.physicalSize = const Size(420, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final (i, id) in ['p1', 'p2', 'p3', 'p4', 'p5'].indexed)
                    TarjetaDeParada(
                      key: ValueKey('t-$id'),
                      numero: i + 1,
                      parada: filas[id]!,
                      lineas: const [],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      Finder t(String id) => find.byKey(ValueKey('t-$id'));
      expect(en('Pendiente', t('p1')), findsOneWidget);
      expect(en('Entregada · cobrada', t('p2')), findsOneWidget);
      expect(en('Entregada · sin cobrar', t('p3')), findsOneWidget);
      // Un devuelto NO muestra cobro aunque traiga `no_cobrado`; y dice por que.
      expect(en('No entregada', t('p4')), findsOneWidget);
      expect(en('El cliente cerró', t('p4')), findsOneWidget);
      expect(
        find.descendant(of: t('p4'), matching: find.textContaining('cobr')),
        findsNothing,
      );
      expect(en('Cancelada', t('p5')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'el cierre de ruta (completada) dice el estado de cada parada con la misma etiqueta',
    (tester) async {
      await sembrar();
      tester.view.physicalSize = const Size(420, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.soloLectura),
            ),
          ),
        ),
      );
      await asentar(tester);

      expect(find.text('Pendiente'), findsOneWidget);
      // «Sin marcar» en una ruta cerrada sigue diciendo que siguio en el camion.
      expect(find.text('Sin marcar · siguió en el camión'), findsOneWidget);
      expect(find.text('Entregada · cobrada'), findsOneWidget);
      expect(find.text('Entregada · sin cobrar'), findsOneWidget);
      expect(find.text('No entregada'), findsOneWidget);
      expect(find.text('Cancelada'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await desmontar(tester);
    },
  );
}
