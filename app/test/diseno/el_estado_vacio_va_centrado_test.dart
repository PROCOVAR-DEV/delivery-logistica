import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/estado_vacio.dart';

/// «No hay nada esperando revisión» salía pegado a la izquierda de la tarjeta en
/// la web (10/10/2026): la columna se encoge al ancho de su texto y, dentro de un
/// contenedor ancho, se queda en su esquina. Se mide EL CENTRO del texto contra el
/// del contenedor: una prueba que solo mirara que existe pasaba con el fallo.
void main() {
  testWidgets(
    'el texto queda en el centro del contenedor ancho, no en su esquina',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: EstadoVacio(
                  'Nada por aquí',
                  icono: Icons.inbox_outlined,
                ),
              ),
            ),
          ),
        ),
      );
      final texto = tester.getCenter(find.text('Nada por aquí')).dx;
      final icono = tester.getCenter(find.byIcon(Icons.inbox_outlined)).dx;
      expect(
        texto,
        closeTo(300, 1),
        reason: 'el centro del texto es el del contenedor',
      );
      expect(icono, closeTo(300, 1), reason: "y el icono va con él");
    },
  );

  testWidgets('dentro de una lista (alto sin límite) no revienta', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EstadoVacio('Vacío')),
        ),
      ),
    );
    expect(find.text('Vacío'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
