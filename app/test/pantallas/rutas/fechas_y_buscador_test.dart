// Los filtros de fecha y el buscador de Rutas.
//
// Lo mismo que en Pedidos: `filtrarRutas` ya sabia acotar por `createdAt` y la
// ✕ de limpiar tambien estaba, pero no habia ningun control que pusiera las
// fechas. Y la caja de buscar exigia Intro y se quedaba con el texto puesto
// despues de `Limpiar`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/rango_de_fechas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'desplegar_los_filtros.dart';

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
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      codigo: 'RT-LA-NUEVA',
      creada: DateTime(2026, 9, 10),
    );
    await sembrarRuta(
      base,
      id: 'R2',
      codigo: 'RT-LA-VIEJA',
      creada: DateTime(2026, 9, 2),
    );
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
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
          home: const Scaffold(body: PantallaRutas()),
        ),
      ),
    );
    await asentar(tester);
    // Con los dos paneles la sección de filtros arranca plegada (issue 6 de
    // Amado): se abre, como haría una persona, para tocar las fechas y el buscador.
    await desplegarLosFiltros(tester);
  }

  testWidgets('poner `Desde` deja fuera las rutas mas viejas', (tester) async {
    await pintar(tester);

    expect(find.text('RT-LA-NUEVA'), findsOneWidget);
    expect(find.text('RT-LA-VIEJA'), findsOneWidget);

    await tester.tap(find.byTooltip('Desde'));
    await asentar(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('5'),
      ),
    );
    await asentar(tester);

    expect(find.text('RT-LA-NUEVA'), findsOneWidget);
    expect(find.text('RT-LA-VIEJA'), findsNothing);

    // La ✕ del rango las devuelve.
    await tester.tap(find.byTooltip(RangoDeFechas.tooltipQuitar));
    await asentar(tester);
    expect(find.text('RT-LA-VIEJA'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('`Limpiar` vacia TAMBIEN la caja de buscar', (tester) async {
    await pintar(tester);

    await tester.enterText(find.byType(TextField), 'LA-NUEVA');
    await tester.pump(const Duration(milliseconds: 450));
    await asentar(tester);

    expect(find.text('RT-LA-VIEJA'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Limpiar'));
    await asentar(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
    expect(find.text('RT-LA-VIEJA'), findsOneWidget);

    await desmontar(tester);
  });
}
