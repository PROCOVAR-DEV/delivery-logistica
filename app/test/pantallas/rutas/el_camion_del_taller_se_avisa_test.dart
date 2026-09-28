// EL CAMIÓN DEL TALLER SE AVISA, NO SE BLOQUEA — el asistente, 28/09/2026.
//
// Desde hoy un camión se puede marcar «en mantenimiento» (migración 00013), y
// eso abre la pregunta de qué pasa cuando alguien lo elige para una ruta. La
// respuesta es **aviso**, y aquí está escrito por qué, porque hoy mismo se
// decidió lo contrario para el caso de al lado:
//
//   · SIN CAMIÓN se BLOQUEA (`ninguna_ruta_sin_camion_test.dart`). No es una
//     pega de forma: la capacidad se mide contra la del camión y el costo por km
//     sale de su `costo_km_usd`, así que sin camión la ruta sale con su peso y
//     su importe y **no hay nada con que contrastarlos**. Las dos cuentas se
//     quedan sin denominador.
//   · CON UN CAMIÓN EN EL TALLER las dos cuentas salen bien: tiene capacidad y
//     tiene costo por km. Lo que falta es el camión, no el dato. Y `maintenance`
//     es un campo que pone una persona y tiene que quitar otra —justo el tipo de
//     dato con el que el `CLAUDE.md` §2 prohíbe bloquear, con los 657 de 686
//     domicilios sin costo—; en producción hay sucursales con UN camión, así que
//     un `maintenance` olvidado las dejaría sin poder armar nada, y el arreglo
//     está en OTRA pantalla.
//
// LAS PRUEBAS VAN EN PAREJA: que el aviso salga con el camión del taller, y que
// **no** salga con uno normal. Un aviso que sale siempre deja de leerse. Y la
// tercera, la que de verdad fija la decisión: con el camión del taller elegido,
// **se puede seguir**.

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

  /// Una sucursal, su almacén y UN camión, con el estado que se le diga. Con una
  /// sola sucursal y un solo almacén el asistente abre directamente en el paso
  /// 3, que es el que aquí se mide.
  Future<void> sembrar({required String estado}) async {
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
            status: Value(estado),
            branchId: const Value('B1'),
          ),
        );
  }

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Desmonta el árbol antes de que acabe la prueba: si no, Drift deja un
  /// temporizador colgando fuera del reloj falso.
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

  Future<void> elegirElCamion(WidgetTester tester) async {
    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    await tester.tap(find.text('Camión 1').last);
    await asentar(tester);
  }

  bool puedeSeguir(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Siguiente'))
          .onPressed !=
      null;

  testWidgets('el camión del taller se marca en la lista y se avisa al elegirlo', (
    tester,
  ) async {
    // La base se llena DENTRO del cuerpo, no en el `setUp` (CLAUDE.md §5.2).
    await sembrar(estado: 'maintenance');
    await pintar(tester);

    // 1. EN LA LISTA, al lado de los kilos. Es donde se decide.
    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    expect(
      find.textContaining('en el taller'),
      findsWidgets,
      reason:
          'si la lista no lo marca, el camión roto se elige igual que los '
          'demás y nadie tiene por qué sospecharlo',
    );
    await tester.tap(find.text('Camión 1').last);
    await asentar(tester);

    // 2. Y DELANTE, con el desplegable ya cerrado: la nota de la lista
    //    desaparece al elegir, así que sola no bastaría.
    expect(
      find.textContaining('está marcado EN EL TALLER'),
      findsOneWidget,
      reason:
          'la nota del desplegable se va al cerrarse; el aviso se queda '
          'mientras ese camión siga puesto',
    );
    await desmontar(tester);
  });

  testWidgets('pero NO bloquea: con el camión del taller se sigue armando', (
    tester,
  ) async {
    await sembrar(estado: 'maintenance');
    await pintar(tester);
    await elegirElCamion(tester);

    expect(
      puedeSeguir(tester),
      isTrue,
      reason:
          '`maintenance` lo pone una persona y lo tiene que quitar otra: '
          'bloquear con él deja sin armar NADA a una sucursal de un solo '
          'camión el día que a alguien se le olvide quitarlo, y el arreglo '
          'está en otra pantalla. Es el caso de los 657 de 686 domicilios sin '
          'costo del §2, con otro nombre',
    );

    // Y de verdad se pasa: que el botón esté vivo y que el paso avance son dos
    // cosas distintas.
    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('y con un camión normal no se avisa de nada', (tester) async {
    // La mitad que caza un aviso que sale siempre. Sin ella, pintar el cartel
    // para todos dejaría la primera prueba en verde y el aviso dejaría de
    // leerse justo el día que importa.
    await sembrar(estado: 'available');
    await pintar(tester);
    await elegirElCamion(tester);

    expect(find.textContaining('EN EL TALLER'), findsNothing);
    expect(find.textContaining('en el taller'), findsNothing);
    expect(puedeSeguir(tester), isTrue);
    await desmontar(tester);
  });
}
