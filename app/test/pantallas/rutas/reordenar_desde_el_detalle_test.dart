// REORDENAR DESDE EL DETALLE (issue 11 de Amado): la pantalla entera, con su
// base de verdad. Lo que se ata aquí y no en las pruebas sueltas es el cableado:
// que «Ver paradas» ofrezca el asa y el botón sólo en una ruta no completada,
// que soltar llegue a la base y a la cola, y que el detalle diga cómo está
// ordenada la ruta sólo donde se puede saber.
//
// La base se escribe DENTRO de cada prueba, nunca en el `setUp` (CLAUDE.md §5).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/formato_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/paradas_ordenables.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> sembrar(String estado) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', estado: estado);
    await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
      const RoutesCompanion(optimized: Value(false)),
    );
    for (var i = 1; i <= 3; i++) {
      await sembrarPedido(
        base,
        id: 'p$i',
        cliente: 'Cliente $i',
        rutaId: 'R1',
        orden: i,
      );
    }
  }

  Future<void> pintar(WidgetTester tester) async {
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
          relojProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: DetalleDeRuta(rutaId: 'R1')),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Se desmonta DENTRO del cuerpo: los flujos de Drift dejan un temporizador
  /// al cerrarse, y si eso pasa después la prueba no falla, se cuelga (§5).
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> verParadas(WidgetTester tester) async {
    await tester.tap(find.text('Ver paradas (3)'));
    await asentar(tester);
  }

  testWidgets('planificada: dice cómo va ordenada y deja arrastrar', (
    tester,
  ) async {
    await sembrar(EstadoRuta.planificada);
    await pintar(tester);
    expect(
      find.byKey(claveDeComoEstaOrdenada),
      findsOneWidget,
      reason: 'la línea del principio, en el detalle',
    );
    expect(find.text(comoEstaOrdenada(optimizada: false)), findsOneWidget);

    await verParadas(tester);
    expect(find.byKey(claveDelAsa('p1')), findsOneWidget);
    expect(find.byKey(claveDeOrdenarPorCercania), findsOneWidget);

    // Soltar p1 en el sitio de p2 llega a la base y a la cola (APK/escritorio).
    final desde = tester.getCenter(find.byKey(claveDelAsa('p1')));
    final alto = tester.getSize(find.byKey(const ValueKey('p2'))).height;
    final gesto = await tester.startGesture(
      desde,
      kind: PointerDeviceKind.mouse,
    );
    for (var y = 0.0; y < alto + 5; y += 20) {
      await gesto.moveTo(desde + Offset(0, y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesto.moveTo(desde + Offset(0, alto + 5));
    await tester.pump(const Duration(milliseconds: 16));
    await gesto.up();
    await asentar(tester);

    final filas = await (base.select(
      base.orders,
    )..where((o) => o.routeId.equals('R1'))).get();
    expect(
      {for (final f in filas) f.id: f.stopOrder},
      {'p2': 1, 'p1': 2, 'p3': 3},
    );
    final apuntes = await base.select(base.apuntes).get();
    expect(
      [for (final a in apuntes) '${a.metodo} ${a.ruta} ${a.cuerpo}'],
      ['PUT /routes/R1/stops {"orden":["p2","p1","p3"]}'],
    );
    await desmontar(tester);
  });

  // LA PAREJA: en una completada, ni línea, ni asa, ni botón.
  testWidgets('completada: ni la línea del orden ni arrastre ni botón', (
    tester,
  ) async {
    await sembrar(EstadoRuta.completada);
    await pintar(tester);
    expect(find.byKey(claveDeComoEstaOrdenada), findsNothing);

    await verParadas(tester);
    expect(find.text('Cliente 1'), findsOneWidget);
    expect(find.byKey(claveDelAsa('p1')), findsNothing);
    expect(find.byKey(claveDeOrdenarPorCercania), findsNothing);
    await desmontar(tester);
  });
}
