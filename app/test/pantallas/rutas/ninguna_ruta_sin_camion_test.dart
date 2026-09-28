// NINGUNA RUTA SIN CAMIÓN — el asistente, 28/09/2026.
//
// Jose, viendo `RT-20260928-001` en producción, «En curso · 3 paradas · Sin
// vehículo»: «por q se creo una ruta sin vehiculo eso no se puede mi broder».
//
// Ese apunte salió del TABLERO, y ahí se cierra en `tablero/datos/
// repositorio.dart` (`armarRuta`) y en `api/internal/api/tablero.go`
// (`msgZonaSinCamion`). Este fichero cubre el OTRO camino, el asistente de
// Rutas, que ya se negaba en dos sitios —`AccionesRutas.armar` con su
// `RechazoLocal` (probado en `armado_test.dart`) y `POST /api/routes` con
// `msgFaltaVehiculo`— pero cuya PUERTA, el «Siguiente» del paso 3, no la medía
// nadie.
//
// Y esa puerta importa porque es la que hace que el «no» no llegue nunca: si se
// puede pasar al paso 4 sin camión, la persona elige veinte pedidos y sólo
// entonces se entera. Un rechazo que llega al final de un formulario largo es un
// rechazo que se lee como un fallo de la aplicación.
//
// VAN EN PAREJA: que el paso esté cerrado sin camión, y que **se abra** en
// cuanto hay uno. Sin la segunda, dejar el botón muerto para siempre —que es
// exactamente lo que pasaba con «Camión previsto», un botón que no abría nada—
// dejaría esta suite en verde.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 28, 9, 0);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Una sucursal, su almacén y UN camión. Con una sola sucursal y un solo
  /// almacén el asistente abre directamente en el paso 3, que es el que aquí se
  /// mide.
  Future<void> sembrarLoBasico() async {
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
  }

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Desmonta el árbol antes de que acabe la prueba.
  ///
  /// Sin esto, los `StreamProvider` de Riverpod se apagan con el `tearDown` y
  /// Drift deja un temporizador de cero al cerrar sus streams, ya fuera del
  /// reloj falso: «A Timer is still pending even after the widget tree was
  /// disposed». Es el mismo ayudante que usa `asistente_wizard_test.dart`.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
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

  /// El «Siguiente» del paso que se esté viendo. `onPressed` nulo es la puerta
  /// cerrada: se mira el widget y no el color, que es lo que de verdad decide.
  bool puedeSeguir(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Siguiente'))
          .onPressed !=
      null;

  testWidgets('sin camión elegido, el paso 3 no deja pasar', (tester) async {
    // La base se llena DENTRO del cuerpo, no en el `setUp`: lo que Drift deja
    // empezado fuera del reloj falso no avanza aquí dentro (CLAUDE.md §5.2).
    await sembrarLoBasico();
    await pintar(tester);

    expect(
      find.byKey(AsistenteNuevaRuta.claveDelPaso(3)),
      findsOneWidget,
      reason: 'con sucursal y almacén resueltos el asistente abre en el paso 3',
    );
    expect(find.text('Elige el vehículo…'), findsOneWidget);
    expect(
      puedeSeguir(tester),
      isFalse,
      reason:
          'si desde aquí se pasa sin camión, la persona elige veinte pedidos y '
          'sólo entonces se entera de que la ruta no se puede crear',
    );

    // Y NO SE HA LLEGADO AL 4. Que el botón esté apagado y el paso siga siendo
    // el 3 son dos cosas distintas: un `setState` suelto podría avanzar igual.
    await tester.tap(
      find.widgetWithText(FilledButton, 'Siguiente'),
      warnIfMissed: false,
    );
    await asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsNothing);
    await desmontar(tester);
  });

  testWidgets('en cuanto se elige el camión, el paso 3 abre', (tester) async {
    await sembrarLoBasico();
    await pintar(tester);

    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    await tester.tap(find.text('Camión 1'));
    await asentar(tester);

    expect(
      puedeSeguir(tester),
      isTrue,
      reason:
          'con camión elegido la puerta se abre; si no, el asistente se queda '
          'muerto en el paso 3 y no se puede armar ninguna ruta',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsOneWidget);
    await desmontar(tester);
  });
}
