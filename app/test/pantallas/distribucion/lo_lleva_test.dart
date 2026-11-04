// VEHICULO <-> DISTRIBUIDOR (tarea 7): «Lo lleva» en la ficha del vehículo y la propuesta al armar una ruta.
//
// Lo delicado: la ficha NO puede borrar con un nulo el distribuidor que no pudo leer. Sin red no manda la clave; con red, sí,
// y manda el que se eligió (o nulo si se eligió «Nadie en particular»).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/vista/ficha_vehiculo.dart';

void main() {
  const tipos = [TipoDeVehiculo(nombre: 'truck', costoKmUsd: 1.65)];
  const felix = (id: 'D1', nombre: 'Felix');
  const juan = (id: 'D2', nombre: 'Juan');
  const triciclo = VehiculoDeLaApi(
    id: 'V1',
    nombre: 'Triciclo-Felix',
    capacidad: 300,
    estado: 'available',
    tipo: 'truck',
  );

  Future<void> abrir(WidgetTester tester, {String? loLleva}) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: triciclo,
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            distribuidores: const [felix, juan],
            loLleva: loLleva,
            alGuardar: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'la ficha ofrece «Lo lleva» con los distribuidores y «Nadie en particular»',
    (tester) async {
      await abrir(tester, loLleva: 'D1');
      expect(find.byKey(claveDeLoLleva), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(claveDeLoLleva),
          matching: find.text('Felix'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('guardar sin tocar el selector manda el que ya tenía', (
    tester,
  ) async {
    DatosVehiculo? salida;
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: triciclo,
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            distribuidores: const [felix, juan],
            loLleva: 'D1',
            alGuardar: (d) => salida = d,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
    await tester.pumpAndSettle();

    expect(salida!.distribuidorId, 'D1');
    expect(salida!.aJson()['distribuidorId'], 'D1');
  });

  testWidgets('elegir otro distribuidor lo manda', (tester) async {
    DatosVehiculo? salida;
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: triciclo,
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            distribuidores: const [felix, juan],
            loLleva: 'D1',
            alGuardar: (d) => salida = d,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(claveDeLoLleva));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
    await tester.pumpAndSettle();

    expect(salida!.aJson()['distribuidorId'], 'D2');
  });

  testWidgets(
    'SIN poder leer quién lo lleva NO se manda la clave (no se borra a ciegas) y se dice por qué',
    (tester) async {
      DatosVehiculo? salida;
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FichaVehiculo(
              vehiculo: triciclo,
              tipos: tipos,
              cupRate: 320,
              guardando: false,
              distribuidores: const [felix],
              loLlevaSeSabe: false,
              loLlevaFallo: 'Sin conexión con el servidor.',
              alGuardar: (d) => salida = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(claveDeLoLleva), findsNothing);
      expect(
        find.textContaining(
          'No se pudo leer quién lleva este vehículo: Sin conexión con el servidor.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
      await tester.pumpAndSettle();
      expect(salida!.aJson().containsKey('distribuidorId'), isFalse);
    },
  );

  testWidgets(
    'una pantalla que no ofrece el selector no cambia lo que se manda',
    (tester) async {
      DatosVehiculo? salida;
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FichaVehiculo(
              vehiculo: triciclo,
              tipos: tipos,
              cupRate: 320,
              guardando: false,
              alGuardar: (d) => salida = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(claveDeLoLleva), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
      await tester.pumpAndSettle();
      expect(salida!.aJson().containsKey('distribuidorId'), isFalse);
    },
  );

  test('el vehículo de la API trae su distribuidor, y sin él queda nulo', () {
    expect(
      VehiculoDeLaApi.deJson({'id': 'V', 'name': 'X', 'distribuidorId': 'D1'})
          .distribuidorId,
      'D1',
    );
    expect(
      VehiculoDeLaApi.deJson({'id': 'V', 'name': 'X'}).distribuidorId,
      isNull,
    );
  });
}
