// LA ETIQUETA «Conduce:» SÓLO SALE SI HAY CONDUCE — 08/10/2026.
//
// El conduce de Amado es el número de operación de la factura
// (`orders.operation_number`, Jose 07/10/2026) y se rotula en la hoja de
// paradas y en el cierre. Lo que se ata aquí es la guarda de las dos etiquetas:
// con número sale «Conduce: <número>», y SIN número —nulo o vacío— no sale
// ninguna, ni «Conduce: » a secas, que parece un dato que falta y es uno que no
// existe. Cada afirmación con su pareja.

import 'package:drift/drift.dart' show OrderingTerm, Value;
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
  final ahora = DateTime(2026, 10, 8, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Tres paradas de R1: Ana con conduce, Beto sin (nulo) y Carla con el texto
  /// vacío. **Dentro del cuerpo de cada prueba**, no en el `setUp` (§5).
  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', estado: EstadoRuta.enCurso);
    for (final (i, nombre) in <String>['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: nombre,
        rutaId: 'R1',
        orden: i + 1,
        folio: 'PTB25-${i + 1}',
      );
    }
    await (base.update(base.orders)..where((o) => o.id.equals('p2'))).write(
      const OrdersCompanion(operationNumber: Value(null)),
    );
    await (base.update(base.orders)..where((o) => o.id.equals('p3'))).write(
      const OrdersCompanion(operationNumber: Value('')),
    );
  }

  testWidgets('la tarjeta de la hoja de paradas: con número sale, sin número no', (
    tester,
  ) async {
    await sembrar();
    final paradas = await (base.select(
      base.orders,
    )..orderBy([(o) => OrderingTerm(expression: o.id)])).get();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final (i, parada) in paradas.indexed)
                  TarjetaDeParada(numero: i + 1, parada: parada, lineas: const []),
              ],
            ),
          ),
        ),
      ),
    );

    // La pareja que SÍ: Ana, con su número.
    expect(find.text('Conduce: PTB25-1'), findsOneWidget);
    // La que NO: Beto (nulo) y Carla (vacío) no ponen etiqueta, ni vacía.
    expect(find.textContaining('Conduce'), findsOneWidget);
    expect(find.text('Conduce: '), findsNothing);
    expect(find.text('Conduce: null'), findsNothing);
  });

  testWidgets('el cierre: con número sale, sin número no', (tester) async {
    await sembrar();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.marcar),
          ),
        ),
      ),
    );
    await asentar(tester);

    expect(find.text('Conduce: PTB25-1'), findsOneWidget);
    expect(find.textContaining('Conduce'), findsOneWidget);
    expect(find.text('Conduce: '), findsNothing);
    expect(find.text('Conduce: null'), findsNothing);

    await desmontar(tester);
  });
}
