// EL PASO 4 DEL ASISTENTE SE FILTRA DE UN DÍA A OTRO — issue 13 de Amado,
// 15/10/2026.
//
// «El filtro de pedidos necesita que tenga un rango de fecha desde/hasta, además
// de la del día que existe hoy.» Los pedidos que se ofrecen a una ruta nueva se
// acotaban por UN `Día de los pedidos` con su `Todos los días`. Ahora llevan los
// mismos controles que Pedidos: `Desde`, `Hasta`, `sólo ese día` y la ✕.
//
// En pareja y con la base de verdad: lo del rango SALE y lo de fuera NO. Y a 390
// px y en escritorio: un desborde en cualquiera de los dos tumba la prueba.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/diseno/rango_de_fechas.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/impresion/vista_previa.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../impresion/los_dos_pesos_del_pre_despacho_test.dart'
    show leerElPapel;
import '../pedidos/sembrar.dart';

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// La sucursal, el camión, el almacén y dos pedidos: uno del 14 y otro del 10.
  /// DENTRO del cuerpo, nunca en el `setUp` (`CLAUDE.md` §5).
  Future<void> sembrar() async {
    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'B1',
            name: 'Camagüey',
            lat: 21.38,
            lng: -77.91,
            externalId: const Value('CAM'),
          ),
        );
    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'V1',
            name: 'Camión 1',
            capacity: const Value(1000),
            plate: const Value('P-001'),
            branchId: const Value('B1'),
          ),
        );
    await base
        .into(base.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: 'W1',
            sucursalCodigo: 'CAM',
            nombre: 'Almacén central',
            lat: const Value(21.38),
            lng: const Value(-77.91),
            principal: const Value(true),
          ),
        );
    for (final (id, cliente, dia) in [
      ('o14', 'Doña Rosa', 14),
      ('o10', 'Don Pepe', 10),
    ]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: cliente,
        endLat: 21.38,
        endLng: -77.91,
        fecha: DateTime(2026, 9, dia, 9),
      );
    }
  }

  /// Pinta el asistente a [tamano] y lo lleva al paso 4: con sucursal y almacén
  /// resueltos abre en el 3, y queda elegir camión y seguir.
  Future<void> alPaso4(WidgetTester tester, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Se desmonta pase lo que pase: con los `Stream` de Drift abiertos el
    // `base.close()` no vuelve y la prueba se cuelga en vez de fallar.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
    });

    await sembrar();
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
    await _asentar(tester);

    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(3)), findsOneWidget);
    await tester.tap(find.text('Elige el vehículo…'));
    await _asentar(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Camión 1'));
    await _asentar(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Siguiente'));
    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await _asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsOneWidget);
  }

  Future<void> elegir(WidgetTester tester, String campo, String dia) async {
    await tester.ensureVisible(find.text(campo));
    await tester.tap(find.text(campo));
    await _asentar(tester);
    await tester.tap(find.text(dia).last);
    await _asentar(tester);
  }

  /// Y AQUÍ también, no sólo en el `addTearDown`: la comprobación de «no quedan
  /// temporizadores» corre al acabar el cuerpo.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  // LA HOJA DEL PRE-DESPACHO DICE EL DÍA SÓLO SI EL FILTRO ES UN DÍA, como la de
  // Pedidos (`diaDeLaHojaEntre`). Con un rango no dice ninguno: escribir el
  // primero sería mentir sobre lo que va debajo. En pareja.
  Future<String> laHoja(WidgetTester tester) async {
    await tester.tap(find.byType(CheckboxListTile).first);
    await _asentar(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver e imprimir'));
    await _asentar(tester);
    final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
    final bytes = (await tester.runAsync(() => vista.armar(PdfPageFormat.a4)))!;
    return leerElPapel(bytes).renglones.map((r) => r.texto).join('\n');
  }

  testWidgets('con UN día, la hoja del pre-despacho lo lleva', (tester) async {
    await alPaso4(tester, const Size(1440, 1100));
    await elegir(tester, 'Desde (fecha del pedido)', '14');
    await tester.tap(find.text('sólo ese día'));
    await _asentar(tester);
    expect(await laHoja(tester), contains('Pedidos del 2026-09-14'));
    await desmontar(tester);
  });

  testWidgets('con un RANGO, la hoja no dice ningún día', (tester) async {
    await alPaso4(tester, const Size(1440, 1100));
    await elegir(tester, 'Desde (fecha del pedido)', '10');
    await elegir(tester, 'Hasta (fecha del pedido)', '14');
    final hoja = await laHoja(tester);
    expect(hoja, contains('Camagüey · Camión 1'), reason: 'no se leyó la hoja');
    expect(hoja, isNot(contains('Pedidos del')));
    await desmontar(tester);
  });

  for (final (donde, tamano) in [
    ('un teléfono de 390 px', const Size(390, 844)),
    ('escritorio', const Size(1440, 1600)),
  ]) {
    testWidgets('desde, hasta, sólo ese día y la ✕ en $donde', (tester) async {
      await alPaso4(tester, tamano);

      expect(find.textContaining('Doña Rosa'), findsWidgets);
      expect(find.textContaining('Don Pepe'), findsWidgets);
      expect(find.text('Día de los pedidos'), findsNothing);
      expect(find.text('Todos los días'), findsNothing);

      // Desde el 12: sale el del 14 y NO el del 10.
      await elegir(tester, 'Desde (fecha del pedido)', '12');
      expect(find.textContaining('Doña Rosa'), findsWidgets);
      expect(find.textContaining('Don Pepe'), findsNothing);

      // Hasta el 14, incluido: el del 14 a las 9 sigue.
      await elegir(tester, 'Hasta (fecha del pedido)', '14');
      expect(find.textContaining('Doña Rosa'), findsWidgets);
      expect(find.textContaining('Don Pepe'), findsNothing);

      // `sólo ese día` = el 12, y el 12 no tiene ninguno.
      await tester.ensureVisible(find.text('sólo ese día'));
      await tester.tap(find.text('sólo ese día'));
      await _asentar(tester);
      expect(find.text(AsistenteNuevaRuta.sinPedidos), findsOneWidget);

      // La ✕: vuelven los dos.
      await tester.ensureVisible(find.byTooltip(RangoDeFechas.tooltipQuitar));
      await tester.tap(find.byTooltip(RangoDeFechas.tooltipQuitar));
      await _asentar(tester);
      expect(find.textContaining('Doña Rosa'), findsWidgets);
      expect(find.textContaining('Don Pepe'), findsWidgets);
      await desmontar(tester);
    });
  }
}
