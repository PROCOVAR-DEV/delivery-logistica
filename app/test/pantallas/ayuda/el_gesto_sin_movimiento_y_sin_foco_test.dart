import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/demostracion_del_gesto.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

const origen = Rect.fromLTWH(40, 40, 100, 60);
const destino = Rect.fromLTWH(450, 180, 100, 60);

Widget ejemplo(List<Rect> focos, {bool reducir = false, VoidCallback? tocar}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reducir,
        ),
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fromRect(
                rect: origen,
                child: TextButton(
                  onPressed: tocar,
                  child: const Text('Control real'),
                ),
              ),
              DemostracionDelGesto(focos: focos),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'el arrastre mantiene pulsado antes de moverse y muestra dos ciclos',
    (tester) async {
      await tester.pumpWidget(ejemplo([origen, destino]));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (tester.getCenter(find.byKey(DemostracionDelGesto.mano)) -
                origen.center)
            .distance,
        lessThan(2),
        reason: 'los primeros 600 ms enseñan mantener pulsado',
      );
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        (tester.getCenter(find.byKey(DemostracionDelGesto.mano)) -
                destino.center)
            .distance,
        lessThan(2),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        (tester.getCenter(find.byKey(DemostracionDelGesto.mano)) -
                origen.center)
            .distance,
        lessThan(2),
        reason: 'el segundo ciclo vuelve al origen',
      );
      await tester.pump(const Duration(milliseconds: 1600));
      expect(
        (tester.getCenter(find.byKey(DemostracionDelGesto.mano)) -
                destino.center)
            .distance,
        lessThan(2),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
    },
  );
  testWidgets('sin focos no inventa una mano ni lanza', (tester) async {
    await tester.pumpWidget(ejemplo([]));
    await tester.pumpAndSettle();
    expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'activar reducir movimiento detiene la demostración que ya corría',
    (tester) async {
      await tester.pumpWidget(ejemplo([origen, destino]));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(DemostracionDelGesto.mano), findsOneWidget);
      await tester.pumpWidget(ejemplo([origen, destino], reducir: true));
      await tester.pumpAndSettle();
      expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
  Widget capaExtra({bool reducir = false, bool marcado = true}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        disableAnimations: reducir,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            if (marcado)
              const Positioned(
                left: 40,
                top: 40,
                child: ControlSenalado(
                  nombre: 'control-extra',
                  child: SizedBox(
                    width: 100,
                    height: 60,
                    child: Text('Control extra'),
                  ),
                ),
              ),
            CapaDelRecorrido(
              alSalir: () {},
              tarea: const TareaDelManual(
                camino: 'prueba',
                tituloDeLaPagina: 'Prueba',
                titulo: 'Dos pasos',
                ancla: 'dos',
                cuerpo: '',
                pasos: [
                  PasoGuiado(
                    cual: 1,
                    deCuantos: 2,
                    texto: 'Explicación primera.',
                    senala: 'control-extra',
                  ),
                  PasoGuiado(
                    cual: 2,
                    deCuantos: 2,
                    texto: 'Explicación segunda.',
                    senala: 'control-extra',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  testWidgets('cambiar de paso después del fin vuelve a enseñar el gesto', (
    tester,
  ) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    await tester.pumpWidget(capaExtra());
    await tester.pumpAndSettle();
    expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
    await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Explicación segunda.'), findsOneWidget);
    expect(
      find.byKey(DemostracionDelGesto.mano),
      findsOneWidget,
      reason:
          'el segundo paso no hereda el controlador ya terminado del primero',
    );
    await tester.pumpAndSettle();
  });
  testWidgets(
    'reducir movimiento conserva explicación y foco sin ofrecer repetir',
    (tester) async {
      RegistroDeControles.vaciar();
      addTearDown(RegistroDeControles.vaciar);
      await tester.pumpWidget(capaExtra(reducir: true));
      await tester.pumpAndSettle();
      expect(find.text('Explicación primera.'), findsOneWidget);
      expect(find.byKey(ClavesDelRecorrido.foco), findsOneWidget);
      expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
      expect(
        find.text('Ver el gesto otra vez'),
        findsNothing,
        reason: 'reducir movimiento no debe ofrecer un control de animación',
      );
    },
  );
  testWidgets('sin control marcado no ofrece repetir un gesto inexistente', (
    tester,
  ) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    await tester.pumpWidget(capaExtra(marcado: false));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
    expect(find.text('Ver el gesto otra vez'), findsNothing);
  });
}
