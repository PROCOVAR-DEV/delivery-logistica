import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/almacenes/vista/pantalla_almacenes.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_almacenes.dart';

/// Almacenes tambien es de sólo con conexion, y aqui mentir sale mas caro que en
/// ningun sitio: una frase falsa sobre un sistema que no se puede consultar desde
/// la calle. Desde el 20/10/2026 la pantalla ademas es de SOLO LECTURA: lo que se
/// prueba es como se cuenta que la lectura fallo, y que nunca sale una escritura.
void main() {
  Future<void> pintar(WidgetTester tester, Banco banco) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaAlmacenes())),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('sin conexión lo dice, no inventa un «Guardado» y no deja nada '
      'en el aparato', (tester) async {
    final banco = Banco.sinRed();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    expect(find.textContaining('Sin conexión.'), findsOneWidget);
    expect(find.textContaining('Guardado'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
    // Ni cola ni copia local: la pantalla solo lee.
    expect(await banco.base.cuantosPendientes(), 0);
    expect(await banco.base.select(banco.base.warehouses).get(), isEmpty);
    expect(banco.servidor.vistas.where((p) => p.metodo != 'GET'), isEmpty);

    await desmontar(tester);
  });

  testWidgets('en la WEB el mismo fallo se cuenta con otras palabras: no se '
      'manda a mirar la señal a quien está en la oficina', (tester) async {
    // «Cuando haya red» es lo correcto en el patio de un almacén, donde la red
    // vuelve sola. En un navegador no: si la página cargó, conexión hay, y el
    // que no contesta es el servidor (`TextosDeCaida.queHacer`).
    await Destino.comoSiFueraWeb(() async {
      final banco = Banco.sinRed();
      addTearDown(banco.cerrar);
      await pintar(tester, banco);

      expect(find.textContaining('La página cargó'), findsOneWidget);
      expect(find.textContaining('cuando haya red'), findsNothing);
      expect(
        find.textContaining('no ha descargado los almacenes todavía'),
        findsNothing,
        reason: 'en la web no hay aparato al que traerle el día',
      );

      await desmontar(tester);
    });
  });

  testWidgets('el rechazo del servidor se enseña literal', (tester) async {
    final banco = Banco(
      (p) async => RespuestaFalsa(403, {'error': 'Sin acceso a esa sucursal'}),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    expect(find.text('Sin acceso a esa sucursal'), findsOneWidget);

    await desmontar(tester);
  });
}
