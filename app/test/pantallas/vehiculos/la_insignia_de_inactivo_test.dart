// LA INSIGNIA «Inactivo» DE LA TARJETA DE UN VEHICULO — 1.0.29.
//
// Amado, 07/10/2026 (incidencia 4): un camion con rutas no se borra, se
// inactiva. La tarjeta lo dice con una insignia (`InsigniaInactivo`, colocada en
// `tarjeta_vehiculo.dart` bajo `if (!vehiculo.activo)`), y era la unica pieza de
// esa incidencia que ninguna prueba pisaba: poner la condicion a `false` o a
// `true` dejaba todo en verde.
//
// EN PAREJA: el inactivo la lleva, y el activo NO. Sin la segunda, pintarla en
// todas las tarjetas dejaria la primera en verde y la insignia dejaria de
// distinguir nada (§3-quinquies: un aviso que sale siempre no se lee).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/vista/tarjeta_vehiculo.dart';

void main() {
  Future<void> pintarTarjeta(WidgetTester tester, VehiculoDeLaApi v) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaVehiculo(
              vehiculo: v,
              importe: (usd) => usd == null ? '—' : '\$$usd',
              alEditar: () {},
              alEliminar: () {},
              alMarcarDisponible: () {},
              alUsarParaDomicilio: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  VehiculoDeLaApi camion({required bool activo, String estado = 'available'}) =>
      VehiculoDeLaApi(
        id: 'v1',
        nombre: 'Camión #1',
        capacidad: 1000,
        estado: estado,
        activo: activo,
        tipo: 'truck',
      );

  testWidgets('el camión INACTIVO lleva la insignia «Inactivo»', (tester) async {
    await pintarTarjeta(tester, camion(activo: false));

    expect(find.byType(InsigniaInactivo), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
  });

  testWidgets('en pareja: el camión ACTIVO NO la lleva', (tester) async {
    await pintarTarjeta(tester, camion(activo: true));

    expect(find.byType(InsigniaInactivo), findsNothing);
    expect(find.text('Inactivo'), findsNothing);
  });

  testWidgets('estar de baja y en el taller son dos cosas: salen las dos', (
    tester,
  ) async {
    // «Un camion puede estar libre Y de baja», y tambien en el taller Y de baja:
    // la insignia de baja no la tapa la de en que anda.
    await pintarTarjeta(tester, camion(activo: false, estado: 'maintenance'));

    expect(find.byType(InsigniaInactivo), findsOneWidget);
    expect(find.text('Mantenimiento'), findsWidgets);
  });

  testWidgets('la insignia va SIN fondo relleno: color, borde e icono', (
    tester,
  ) async {
    // La regla de la casa (§4): lo que se distingue lo hace por color, borde e
    // icono, no por un rectangulo relleno.
    await pintarTarjeta(tester, camion(activo: false));

    final caja = tester.widget<Container>(
      find.descendant(
        of: find.byType(InsigniaInactivo),
        matching: find.byType(Container),
      ),
    );
    final decoracion = caja.decoration! as BoxDecoration;
    expect(decoracion.color, isNull, reason: 'sin fondo');
    expect(decoracion.border, isNotNull, reason: 'con borde');
    expect(
      find.descendant(
        of: find.byType(InsigniaInactivo),
        matching: find.byIcon(Icons.block),
      ),
      findsOneWidget,
      reason: 'con su icono',
    );
  });
}
