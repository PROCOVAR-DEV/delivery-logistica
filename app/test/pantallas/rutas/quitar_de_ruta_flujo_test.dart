// «QUITAR DE RUTA», EL GESTO ENTERO DESDE LA PANTALLA — 08/10/2026.
//
// `quitar_de_ruta_test.dart` ata la acción por un lado (la base, la cola, los
// literales) y la pregunta suelta por otro. Entre las dos queda el hueco más
// grande de cobertura de Rutas, y es justo donde se rompe en producción: ver las
// paradas -> tocar «Quitar de ruta» -> el cajón -> «Sí, quitar» -> que
// `quitarParada` se llame de verdad y la parada se vaya de la hoja que se está
// mirando. Un botón que no llega a la acción, o una acción que no repinta la
// hoja, no los ve ninguna de las dos pruebas por separado.
//
// Se monta con la base VACÍA y se siembra DESPUÉS, sin volver a montar: así es
// como llega la bajada en un navegador (`CLAUDE.md` §3-ter). Y cada prueba va
// con su pareja: planificada SÍ ofrece el botón, en curso NO.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// Las acciones de verdad, anotando a qué parada se le pidió quitarse. Lo que se
/// comprueba es que el gesto llega a `quitarParada`, y con los ids de verdad.
class _AccionesQueApuntan extends AccionesDeRuta {
  _AccionesQueApuntan(super.base, super.cola, {super.reloj});

  final llamadas = <(String, String)>[];

  @override
  Future<void> quitarParada(String rutaId, String pedidoId) {
    llamadas.add((rutaId, pedidoId));
    return super.quitarParada(rutaId, pedidoId);
  }
}

void main() {
  late BaseLocal base;
  late _AccionesQueApuntan acciones;
  final ahora = DateTime(2026, 10, 8, 16, 5);

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

  /// Monta el detalle de R1 con la base VACÍA: la ruta llega después.
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
          accionesDeRutaProvider.overrideWith(
            (ref) => acciones = _AccionesQueApuntan(
              base,
              ref.watch(colaProvider),
              reloj: () => ahora,
            ),
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

  /// Llega la bajada con la pantalla ya abierta: R1 con dos paradas.
  Future<void> llegaLaRuta(String estado) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', estado: estado);
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Ana',
      rutaId: 'R1',
      orden: 1,
    );
    await sembrarPedido(
      base,
      id: 'p2',
      cliente: 'Beto',
      rutaId: 'R1',
      orden: 2,
    );
  }

  Future<void> verLasParadas(WidgetTester tester) async {
    await tester.tap(find.text('Ver paradas (2)'));
    await asentar(tester);
  }

  final quitar = find.text('Quitar de ruta');
  final laHoja = find.text('Paradas y precio por cliente (2)');
  final laHojaDeUna = find.text('Paradas y precio por cliente (1)');

  Future<String?> rutaDe(String pedidoId) async =>
      (await (base.select(
            base.orders,
          )..where((o) => o.id.equals(pedidoId))).getSingle())
          .routeId;

  testWidgets('«Sí, quitar»: llama a quitarParada y la parada se va de la hoja', (
    tester,
  ) async {
    await pintar(tester);
    await llegaLaRuta(EstadoRuta.planificada);
    await asentar(tester);

    await verLasParadas(tester);
    expect(laHoja, findsOneWidget);
    expect(quitar, findsNWidgets(2), reason: 'una por parada');

    // La de Ana: la primera tarjeta.
    await tester.tap(quitar.first);
    await asentar(tester);
    // La pregunta, en un cajón, nombrando a quien sale. Nada se ha quitado aún.
    expect(find.text('Quitar de la ruta'), findsOneWidget);
    expect(find.text('Sí, quitar «Ana» de la ruta'), findsOneWidget);
    expect(acciones.llamadas, isEmpty, reason: 'preguntar no quita');

    await tester.tap(find.text('Sí, quitar «Ana» de la ruta'));
    await asentar(tester);

    expect(acciones.llamadas, [('R1', 'p1')]);
    expect(await rutaDe('p1'), isNull);
    expect(await rutaDe('p2'), 'R1');
    // Y la hoja que se está mirando se repinta sin cerrarla ni reabrirla.
    expect(laHojaDeUna, findsOneWidget);
    expect(laHoja, findsNothing);
    expect(quitar, findsOneWidget);
    expect(find.text('Beto'), findsWidgets);
    expect(find.text('Quitar de la ruta'), findsNothing, reason: 'la pregunta se fue');

    await desmontar(tester);
  });

  testWidgets('«No, dejarlo en la ruta»: no se llama a nada y nada cambia', (
    tester,
  ) async {
    await pintar(tester);
    await llegaLaRuta(EstadoRuta.planificada);
    await asentar(tester);

    await verLasParadas(tester);
    await tester.tap(quitar.first);
    await asentar(tester);
    await tester.tap(find.text('No, dejarlo en la ruta'));
    await asentar(tester);

    expect(acciones.llamadas, isEmpty);
    expect(await rutaDe('p1'), 'R1');
    expect(await rutaDe('p2'), 'R1');
    expect(laHoja, findsOneWidget);
    expect(quitar, findsNWidgets(2));
    expect(find.text('Quitar de la ruta'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('en una ruta EN CURSO el botón no existe', (tester) async {
    await pintar(tester);
    await llegaLaRuta(EstadoRuta.enCurso);
    await asentar(tester);

    await verLasParadas(tester);
    // Las paradas sí se ven...
    expect(laHoja, findsOneWidget);
    expect(find.text('Ana'), findsWidgets);
    // ...pero sacar a alguien de un camión que ya salió no se ofrece.
    expect(quitar, findsNothing);
    expect(acciones.llamadas, isEmpty);

    await desmontar(tester);
  });
}
