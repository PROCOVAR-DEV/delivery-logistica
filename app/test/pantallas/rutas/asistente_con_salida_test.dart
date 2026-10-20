// Un paso del asistente que no se puede terminar TIENE que llevar al sitio
// donde se arregla.
//
// Antes decía «Crea o libera uno en Vehículos» y ahí te dejaba: quien está
// armando la ruta de la mañana tenía que salir, buscar el menú, dar de alta el
// camión, volver y empezar el asistente otra vez desde el paso 1.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';

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
    // Una sucursal sola: el paso 1 se autocompleta y no estorba.
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
  });

  tearDown(() => base.close());

  /// Un router de dos páginas: la del asistente y la de destino. Sin un router
  /// de verdad esto no probaría nada — el botón podría «llevar» a ningún sitio
  /// y el test no lo notaría.
  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (contexto, _) => Scaffold(
            body: Builder(
              builder: (interior) => TextButton(
                onPressed: () => showGeneralDialog<void>(
                  context: interior,
                  pageBuilder: (_, _, _) => const AsistenteNuevaRuta(),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/vehicles',
          builder: (contexto, _) =>
              const Scaffold(body: Text('AQUÍ SE DAN DE ALTA LOS CAMIONES')),
        ),
        GoRoute(
          path: '/warehouses',
          builder: (contexto, _) =>
              const Scaffold(body: Text('AQUÍ SE PONE EL ALMACÉN')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp.router(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          routerConfig: router,
        ),
      ),
    );
    await asentar(tester);
    await tester.tap(find.text('abrir'));
    await asentar(tester);
  }

  testWidgets('sin almacén con ubicación, el paso 2 lleva a Almacenes', (
    tester,
  ) async {
    await pintar(tester);

    // Paso 1: la sucursal ya viene puesta, sólo hay que seguir.
    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await asentar(tester);

    expect(find.text(AsistenteNuevaRuta.sinAlmacenes), findsOneWidget);
    // Los almacenes se editan en el CRM (20/10/2026): el botón lleva a la CONSULTA y
    // no promete «poner» nada, y el texto dice dónde se ponen. Los literales a mano,
    // porque comparar la constante consigo misma no caza que vuelvan a mentir.
    expect(AsistenteNuevaRuta.irAAlmacenes, 'Ver los almacenes');
    expect(AsistenteNuevaRuta.sinAlmacenes, contains('se ponen en el CRM'));
    expect(AsistenteNuevaRuta.sinAlmacenes, isNot(contains('Se pone en')));
    await tester.tap(
      find.widgetWithText(FilledButton, AsistenteNuevaRuta.irAAlmacenes),
    );
    await asentar(tester);

    // El asistente se cierra y se llega de verdad.
    expect(find.text('AQUÍ SE PONE EL ALMACÉN'), findsOneWidget);
    expect(find.text('Nueva Ruta'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('sin vehículos, el paso 3 lleva a Vehículos', (tester) async {
    // Con almacén con ubicación el asistente arranca ya en el paso 3.
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

    await pintar(tester);

    // En qué paso se está lo dice la tarjeta que se pinta, no un subtítulo: ahí
    // arriba va ahora la sucursal, que es el dato que manda sobre todo lo demás.
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(3)), findsOneWidget);
    expect(find.text('Camagüey'), findsOneWidget);
    expect(find.text(AsistenteNuevaRuta.sinVehiculos), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, AsistenteNuevaRuta.irAVehiculos),
    );
    await asentar(tester);

    expect(find.text('AQUÍ SE DAN DE ALTA LOS CAMIONES'), findsOneWidget);
    expect(find.text('Nueva Ruta'), findsNothing);

    await desmontar(tester);
  });
}
