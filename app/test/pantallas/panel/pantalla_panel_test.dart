import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/registro.dart';
import 'package:reparto/pantallas/panel/registro.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarPanel(), registrarInformes()],
            inicial: '/dashboard',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  // Repartible = lo que ofrece la lista de disponibles de Rutas: de PEDIDO, con
  // punto de entrega, factura que cuadra, domicilio cobrado y cotizado (cero
  // cuenta como cotizado).
  Future<void> pedido(String id, {double peso = 10, double? costo = 0}) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          branchId: const Value('stg'),
          endLat: const Value(20.0),
          endLng: const Value(-75.0),
          source: const Value('pedido'),
          facturaEstado: const Value('igual'),
          facturaDomicilio: const Value(1),
          weight: Value(peso),
          pedidoCosto: Value(costo),
        ),
      );

  testWidgets('las cuatro etiquetas son las LITERALES del pliego', (
    tester,
  ) async {
    await montar(tester);

    expect(find.text('Pedidos sin ruta'), findsOneWidget);
    expect(find.text('Rutas en marcha'), findsOneWidget);
    expect(find.text('Entregados hoy'), findsOneWidget);
    expect(find.text('Vehículos'), findsWidgets);
    expect(find.text('en ruta / total'), findsOneWidget);
    expect(find.text('Pendiente por sucursal'), findsOneWidget);
    expect(find.text('Acciones Rápidas'), findsOneWidget);
    expect(find.text('Domicilios cobrados'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('sin nada pendiente sale el estado vacio, no una lista vacia', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('No queda nada sin ruta.'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('«Pedidos sin ruta» va en AMBAR con > 0 y en primario con 0', (
    tester,
  ) async {
    await montar(tester);
    var cifra = tester.widget<Text>(find.text('0').first);
    expect(cifra.style?.color, isNot(Colores.ambar));
    await desmontar(tester);

    await base.close();
    base = baseDePrueba();
    await pedido('a', peso: 120, costo: 4);
    await pedido('b', peso: 30, costo: 6);
    await montar(tester);

    // Hay dos «2» en la pantalla: la cifra de la tarjeta y el conteo de la
    // sucursal. La de la tarjeta va primera en el arbol.
    cifra = tester.widget<Text>(find.text('2').first);
    expect(cifra.style?.color, Colores.ambar);
    // El subtexto lleva los kg REDONDEADOS.
    expect(find.text('150 kg por mover'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('«Ver Reportes» lleva a /reports, que no esta en el menu', (
    tester,
  ) async {
    await montar(tester);

    await tester.tap(find.text('Ver Reportes'));
    await tester.pumpAndSettle();

    // El titulo de la barra superior cambia: se llego a Reportes.
    expect(find.text('Filtros'), findsOneWidget);
    await desmontar(tester);
  });
}
