// «UBICAR LA ENTREGA» DESDE LA TARJETA DE LA PARADA (issue 19 de Amado).
//
// El detalle de la ruta ofrece el MISMO cajón de la ficha del pedido junto a
// «Quitar de ruta», con la misma regla de cuándo: sólo si la parada no está
// entregada y la ruta no está completada. Y la parada con el punto a mano lo dice
// con su etiqueta. Se monta con la base VACÍA y se siembra DESPUÉS (§3-ter).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/mapa/ubicacion/geocodificar.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 20, 9);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
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
          relojProvider.overrideWithValue(() => ahora),
          geocodificadorProvider.overrideWithValue(const SinGeocodificar()),
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
          recorridoPorCallesProvider.overrideWithValue(
            const SinCallesQueSeguir(),
          ),
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

  Future<void> llegaLaRuta(String estado) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', estado: estado);
    for (final (id, cliente, orden) in [('p1', 'Ana', 1), ('p2', 'Beto', 2)]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: cliente,
        rutaId: 'R1',
        orden: orden,
        endLat: 21.38,
        endLng: -77.91,
      );
    }
  }

  Future<void> verLasParadas(WidgetTester tester) async {
    await tester.tap(find.text('Ver paradas (2)'));
    await asentar(tester);
  }

  final ubicar = find.text('Ubicar la entrega');
  final etiquetaDeAna = find.byKey(const ValueKey('parada-punto-manual-p1'));
  final etiquetaDeBeto = find.byKey(const ValueKey('parada-punto-manual-p2'));

  testWidgets('en una ruta planificada cada parada ofrece «Ubicar la entrega»; '
      'pulsarlo abre el cajón', (tester) async {
    await pintar(tester);
    await llegaLaRuta(EstadoRuta.planificada);
    await asentar(tester);

    await verLasParadas(tester);
    expect(ubicar, findsNWidgets(2), reason: 'una por parada');
    expect(etiquetaDeAna, findsNothing);

    await tester.tap(ubicar.first);
    await asentar(tester);
    expect(find.text('Guardar punto'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('la etiqueta sale en la parada que la bajada marca como manual, '
      'sin reabrir la hoja', (tester) async {
    await pintar(tester);
    await llegaLaRuta(EstadoRuta.planificada);
    await asentar(tester);
    await verLasParadas(tester);
    expect(etiquetaDeAna, findsNothing);

    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(puntoManual: Value(true)),
    );
    await asentar(tester);

    expect(etiquetaDeAna, findsOneWidget);
    expect(etiquetaDeBeto, findsNothing, reason: 'solo la que es manual');
    await desmontar(tester);
  });

  testWidgets('en una ruta COMPLETADA no se ofrece', (tester) async {
    await pintar(tester);
    await llegaLaRuta(EstadoRuta.completada);
    await asentar(tester);

    await verLasParadas(tester);
    expect(find.text('Paradas y precio por cliente (2)'), findsOneWidget);
    expect(ubicar, findsNothing);
    await desmontar(tester);
  });

  testWidgets('una parada ENTREGADA no lo ofrece, la otra sí', (tester) async {
    await pintar(tester);
    await llegaLaRuta(EstadoRuta.enCurso);
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(resultado: Value(ResultadoParada.entregado)),
    );
    await asentar(tester);

    await verLasParadas(tester);
    expect(ubicar, findsOneWidget, reason: 'solo la de Beto');
    await desmontar(tester);
  });
}
