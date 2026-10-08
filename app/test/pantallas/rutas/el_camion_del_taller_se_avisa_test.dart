// EL CAMIÓN DEL TALLER SE AVISA, NO SE BLOQUEA — el asistente, 28/09/2026,
// RESTAURADA el 08/10/2026 (1.0.29).
//
// Desde el 28/09 un camión se puede marcar «en mantenimiento» (migración 00013), y
// eso abre la pregunta de qué pasa cuando alguien lo elige para una ruta. La
// respuesta es **aviso**:
//
//   · SIN CAMIÓN se BLOQUEA (`ninguna_ruta_sin_camion_test.dart`): la capacidad se
//     mide contra la del camión y el costo por km sale de su `costo_km_usd`, así
//     que sin camión la ruta sale con su peso y su importe y **no hay nada con que
//     contrastarlos**.
//   · CON UN CAMIÓN EN EL TALLER las dos cuentas salen bien: lo que falta es el
//     camión, no el dato. Y `maintenance` es un campo que pone una persona y tiene
//     que quitar otra; en producción hay sucursales con UN camión, así que un
//     `maintenance` olvidado las dejaría sin poder armar nada, y el arreglo está en
//     OTRA pantalla. Es la decisión de Jose del 28/09/2026 («aviso, no bloqueo») y
//     el servidor la sigue aceptando (`vehiculos.go`).
//
// ## Por qué estaba borrada y por qué vuelve
//
// 1.0.28 la borró (con `camiones_que_se_ofrecen_test.dart` fijando lo contrario:
// que el del taller NO se ofrece) creyendo que Amado había reemplazado esa
// decisión. Amado pidió que el INACTIVO no se ofrezca (incidencia 4), no el del
// taller; el revisor de código lo demostró contra el servidor. Ahora existe además
// `isActive`, así que hay una pareja nueva: el inactivo NO sale y el del taller SÍ.
//
// LAS PRUEBAS VAN EN PAREJA: que el aviso salga con el camión del taller, y que
// **no** salga con uno normal. Un aviso que sale siempre deja de leerse. Y la
// tercera, la que de verdad fija la decisión: con el camión del taller elegido,
// **se puede seguir**. Todas montan con la base VACÍA y siembran DESPUÉS.

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
  Future<void> sembrar({required String estado, bool conInactivo = false}) async {
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
    if (conInactivo) {
      await base
          .into(base.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'V2',
              name: 'Camión de baja',
              capacity: const Value(1000),
              plate: const Value('P-002'),
              isActive: const Value(false),
              branchId: const Value('B1'),
            ),
          );
    }
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
    // MONTA VACÍA y se siembra DESPUÉS, con la pantalla delante (§3-ter y §5.2).
    await pintar(tester);
    await sembrar(estado: 'maintenance');
    await asentar(tester);

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
    await pintar(tester);
    await sembrar(estado: 'maintenance');
    await asentar(tester);
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
    await pintar(tester);
    await sembrar(estado: 'available');
    await asentar(tester);
    await elegirElCamion(tester);

    expect(find.textContaining('EN EL TALLER'), findsNothing);
    expect(find.textContaining('en el taller'), findsNothing);
    expect(puedeSeguir(tester), isTrue);
    await desmontar(tester);
  });

  testWidgets('el INACTIVO no se ofrece aunque el del taller sí', (tester) async {
    // La pareja de : el taller se avisa, la baja se oculta. Sin la
    // segunda mitad, ofrecer TODO dejaría la primera en verde y el servidor
    // rechazaría con 400 «El vehículo está inactivo…» lo que la lista ofreció.
    await pintar(tester);
    await sembrar(estado: 'maintenance', conInactivo: true);
    await asentar(tester);

    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    expect(find.text('Camión 1'), findsWidgets);
    expect(
      find.text('Camión de baja'),
      findsNothing,
      reason: 'un camión inactivo NUNCA se ofrece para una ruta nueva',
    );
    await desmontar(tester);
  });
}
