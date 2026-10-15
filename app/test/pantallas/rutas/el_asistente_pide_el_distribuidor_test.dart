// EL ASISTENTE «NUEVA RUTA» PIDE EL DISTRIBUIDOR — issue 7 de Amado, 14/10/2026.
//
// Va en el paso del vehiculo (el 3), opcional y a la vista, y lo elegido llega a la ruta. Esta prueba
// recorre el asistente de verdad con el dedo —camion, distribuidor, pedido, «Generar Ruta»— porque lo
// que falla en una pantalla no es una consulta: es que el selector no este, o que lo que se elige no
// llegue a `armar`.
//
// EN PAREJA: elegido, la ruta lo lleva; sin elegir, sale sin el.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/distribuidores/vista/selector_de_distribuidor.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 14, 9);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// UNA sucursal, un almacen con coordenadas, un camion, un pedido armable y dos distribuidores
  /// (uno retirado). Con una sola sucursal el asistente abre ya en el paso 3.
  Future<void> sembrarTodo() async {
    await base.into(base.branches).insert(
      BranchesCompanion.insert(
        id: 'B1', name: 'Camagüey', lat: 21.38, lng: -77.91, externalId: const Value('CAM'),
      ),
    );
    await base.into(base.warehouses).insert(
      WarehousesCompanion.insert(
        id: 'W1', sucursalCodigo: 'CAM', nombre: 'Almacén central',
        lat: const Value(21.38), lng: const Value(-77.91), principal: const Value(true),
      ),
    );
    await base.into(base.vehicles).insert(
      VehiclesCompanion.insert(
        id: 'V1', name: 'Camión 1', capacity: const Value(1000),
        plate: const Value('P-001'), branchId: const Value('B1'),
      ),
    );
    await sembrarPedido(
      base, id: 'p0', cliente: 'Cliente 000', endLat: 21.38, endLng: -77.91, fecha: ahora,
    );
    for (final (id, nombre, activo) in const [
      ('d-juan', 'Juan Pérez', true),
      ('d-pedro', 'Pedro Gil', false),
    ]) {
      await base.into(base.distribuidores).insert(
        DistribuidoresCompanion.insert(
          id: id, nombre: nombre, activo: Value(activo), branchId: const Value('B1'),
        ),
      );
    }
    await RegistroDeFrescura(base, reloj: () => ahora).marcar(
      Colecciones.distribuidores, hasta: null, bajadaAt: ahora, completa: true,
    );
  }

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: AsistenteNuevaRuta()),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Del paso 3 hasta pulsar «Generar Ruta»: camion, [distribuidor] si se pide, pedido.
  Future<void> generar(WidgetTester tester, {String? distribuidor}) async {
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(3)), findsOneWidget);
    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    await tester.tap(find.text('Camión 1'));
    await asentar(tester);

    if (distribuidor != null) {
      await tester.tap(find.byKey(SelectorDeDistribuidor.claveDelSelector));
      await asentar(tester);
      await tester.tap(find.text(distribuidor));
      await asentar(tester);
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Generar Ruta'));
    await asentar(tester);
  }

  testWidgets('el paso del vehiculo ofrece el distribuidor, con SOLO los de la sucursal y en activo', (tester) async {
    await sembrarTodo();
    await pintar(tester);

    expect(find.byKey(SelectorDeDistribuidor.claveDelSelector), findsOneWidget,
        reason: 'sin el selector en el paso 3, el distribuidor no se puede elegir al crear la ruta');

    await tester.tap(find.byKey(SelectorDeDistribuidor.claveDelSelector));
    await asentar(tester);
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('Pedro Gil'), findsNothing, reason: 'uno retirado no se asigna a una ruta nueva');
    await desmontar(tester);
  });

  testWidgets('elegido: la ruta que sale lo lleva, local y en el apunte', (tester) async {
    await sembrarTodo();
    await pintar(tester);
    await generar(tester, distribuidor: 'Juan Pérez');

    final rutas = (await tester.runAsync(() => base.select(base.routes).get()))!;
    expect(rutas.single.distribuidorId, 'd-juan');
    final apunte = (await tester.runAsync(() => ColaDeSalida(base).pendientes().first))!.single;
    expect((ColaDeSalida.cuerpoDe(apunte)! as Map)['distribuidorId'], 'd-juan');
    await desmontar(tester);
  });

  testWidgets('sin elegir: la ruta sale igual, sin distribuidor (es opcional)', (tester) async {
    await sembrarTodo();
    await pintar(tester);
    await generar(tester);

    final rutas = (await tester.runAsync(() => base.select(base.routes).get()))!;
    expect(rutas.single.distribuidorId, isNull);
    final apunte = (await tester.runAsync(() => ColaDeSalida(base).pendientes().first))!.single;
    expect((ColaDeSalida.cuerpoDe(apunte)! as Map).containsKey('distribuidorId'), isFalse);
    await desmontar(tester);
  });

  testWidgets('el elegido se RECUERDA: la proxima ruta de esa sucursal ya lo trae puesto', (tester) async {
    await sembrarTodo();
    await pintar(tester);
    await generar(tester, distribuidor: 'Juan Pérez');
    await desmontar(tester);

    await pintar(tester);
    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    await tester.tap(find.text('Camión 1'));
    await asentar(tester);
    // El selector muestra al de la ultima ruta elegido, sin tocar nada.
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.byKey(SelectorDeDistribuidor.claveDelAvisoSinElegir), findsNothing);
    await desmontar(tester);
  });
}
