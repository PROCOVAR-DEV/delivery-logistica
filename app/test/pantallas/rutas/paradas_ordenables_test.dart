// ARRASTRAR LAS PARADAS (issue 11 de Amado): el gesto, a 390 px con el dedo y
// en escritorio con el ratón, y lo que NO se ofrece en una ruta completada.
//
// La pieza se prueba suelta, sin Drift ni proveedores (CLAUDE.md §5): lo que
// hace el gesto con la base y con el servidor lo prueba
// `reordenar_paradas_test.dart`.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/formato_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/paradas_ordenables.dart';

void main() {
  Pedido parada(String id, int orden, {String rutaId = 'R1'}) => Pedido(
    id: id,
    operationNumber: 'OP-$id',
    customerName: 'Cliente $id',
    address: 'Calle $id',
    weight: 10,
    status: 'pending',
    tripLeg: 'ida',
    archivado: false,
    puntoManual: false,
    routeId: rutaId,
    stopOrder: orden,
    createdAt: DateTime(2026, 10, 15),
  );
  final tres = [parada('p1', 1), parada('p2', 2), parada('p3', 3)];

  /// Lo que la pantalla le pidió a las acciones: un orden, o `null` = cercanía.
  late List<List<String>?> pedidos;

  Future<void> pintar(
    WidgetTester tester, {
    required Size tamano,
    String estado = EstadoRuta.planificada,
    Future<void> Function({List<String>? orden})? alReordenar,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pedidos = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Como dentro del cajón: el cuerpo se desplaza y la lista va dentro.
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ParadasOrdenables(
                rutaId: 'R1',
                estado: estado,
                optimizada: false,
                paradas: tres,
                alReordenar:
                    alReordenar ??
                    ({orden}) async {
                      pedidos.add(orden);
                    },
                tarjeta: (p, numero, asa) => TarjetaDeParada(
                  numero: numero,
                  parada: p,
                  lineas: const [],
                  asa: asa,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double alto(WidgetTester tester, String id) =>
      tester.getCenter(find.byKey(ValueKey(id))).dy;

  /// Arrastra el asa de [id] al sitio de [detras], la siguiente, a pasos (la
  /// lista anima). A 390 px una tarjeta mide ~276 px y sólo se ven dos: por eso
  /// la lista se desplaza ella sola (ver `ParadasOrdenables`).
  Future<void> llevarDetras(
    WidgetTester tester,
    String id,
    String detras,
    PointerDeviceKind tipo,
  ) async {
    final desde = tester.getCenter(find.byKey(claveDelAsa(id)));
    // Una tarjeta hacia abajo: lo que mide la de detrás, y un poco más.
    final hasta =
        desde.dy + tester.getSize(find.byKey(ValueKey(detras))).height + 5;
    final gesto = await tester.startGesture(desde, kind: tipo);
    await tester.pump(kLongPressTimeout ~/ 10);
    for (var y = desde.dy; y < hasta; y += 20) {
      await gesto.moveTo(Offset(desde.dx, y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesto.moveTo(Offset(desde.dx, hasta));
    await tester.pump(const Duration(milliseconds: 16));
    await gesto.up();
    await tester.pumpAndSettle();
  }

  for (final (nombre, tamano, tipo) in [
    (
      'teléfono de 390 px, con el dedo',
      const Size(390, 844),
      PointerDeviceKind.touch,
    ),
    (
      'escritorio, con el ratón',
      const Size(1280, 800),
      PointerDeviceKind.mouse,
    ),
  ]) {
    testWidgets('$nombre: arrastrar por el asa pide el orden nuevo', (
      tester,
    ) async {
      await pintar(tester, tamano: tamano);
      expect(find.byKey(claveDelAsa('p1')), findsOneWidget);
      expect(find.byKey(claveDeOrdenarPorCercania), findsOneWidget);

      await llevarDetras(tester, 'p1', 'p2', tipo);

      expect(pedidos, [
        ['p2', 'p1', 'p3'],
      ]);
      // Y se pinta ya en el orden nuevo, sin esperar a que vuelva la base.
      expect(alto(tester, 'p2'), lessThan(alto(tester, 'p1')));
      expect(
        tester.takeException(),
        isNull,
        reason: 'nada se desborda a $nombre',
      );
    });
  }

  testWidgets('«Ordenar por cercanía» pide el orden a la máquina', (
    tester,
  ) async {
    await pintar(tester, tamano: const Size(390, 844));
    await tester.tap(find.byKey(claveDeOrdenarPorCercania));
    await tester.pumpAndSettle();
    expect(pedidos, [null]);
  });

  testWidgets('un «no» se dice con su motivo y la parada vuelve a su sitio', (
    tester,
  ) async {
    const elNo =
        'El nuevo orden no coincide con las paradas de la ruta (falta OP-p3). '
        'Vuelve a abrir la ruta y ordénala otra vez.';
    await pintar(
      tester,
      tamano: const Size(390, 844),
      alReordenar: ({orden}) async => throw const RechazoLocal(elNo),
    );
    await llevarDetras(tester, 'p1', 'p2', PointerDeviceKind.touch);

    // DENTRO del cajón, no sólo en el aviso de abajo: en el teléfono el cajón lo tapa.
    expect(
      find.descendant(
        of: find.byType(ParadasOrdenables),
        matching: find.text(elNo),
      ),
      findsOneWidget,
    );
    expect(
      alto(tester, 'p1'),
      lessThan(alto(tester, 'p2')),
      reason: 'rechazado: no se mueve nada',
    );
  });

  // MIENTRAS VA UN GESTO, NO SE OFRECE OTRO. `AccionesDeRuta.reordenar` deja una
  // sola petición por ruta a la vez y al segundo gesto le devuelve el MISMO
  // futuro: si la pantalla dejara arrastrar, ese segundo orden se perdería en
  // silencio.
  testWidgets('con un orden en camino no se arrastra ni se pulsa otra vez', (
    tester,
  ) async {
    final enCamino = Completer<void>();
    await pintar(
      tester,
      tamano: const Size(390, 844),
      alReordenar: ({orden}) => enCamino.future,
    );
    await tester.tap(find.byKey(claveDeOrdenarPorCercania));
    await tester.pump();
    expect(find.byKey(claveDelAsa('p1')), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(claveDeOrdenarPorCercania))
          .onPressed,
      isNull,
    );
    enCamino.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(claveDelAsa('p1')), findsOneWidget, reason: 'y vuelve');
  });

  // EL «PRINCIPIO» SE LEE DE LA FIRMA `optimized`, en pareja y con su literal.
  test('la línea del orden dice quién ordenó', () {
    expect(
      comoEstaOrdenada(optimizada: true),
      'Orden de visita: por cercanía al punto de salida',
    );
    expect(
      comoEstaOrdenada(optimizada: false),
      'Orden de visita: a mano (el de la zona del tablero, o arrastrado)',
    );
  });

  // LA PAREJA: en una ruta completada ni asa ni botón. Es histórico.
  testWidgets('completada: ni se arrastra ni se ofrece ordenar', (
    tester,
  ) async {
    await pintar(
      tester,
      tamano: const Size(390, 844),
      estado: EstadoRuta.completada,
    );
    expect(find.text('Cliente p1'), findsOneWidget);
    expect(find.byKey(claveDelAsa('p1')), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byKey(claveDeOrdenarPorCercania), findsNothing);
  });
}
