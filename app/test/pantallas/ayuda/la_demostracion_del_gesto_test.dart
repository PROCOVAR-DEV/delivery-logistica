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
  testWidgets('la mano recorre desde el control de origen al de destino', (
    tester,
  ) async {
    await tester.pumpWidget(ejemplo([origen, destino]));
    await tester.pump(const Duration(milliseconds: 100));
    final primero = tester.getCenter(find.byKey(DemostracionDelGesto.mano));
    expect((primero - origen.center).distance, lessThan(30));
    await tester.pump(const Duration(milliseconds: 1600));
    final ultimo = tester.getCenter(find.byKey(DemostracionDelGesto.mano));
    expect((ultimo - destino.center).distance, lessThan(50));
    expect(
      (ultimo - primero).distance,
      greaterThan(300),
      reason: 'un dibujo fijo no enseña el arrastre',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(DemostracionDelGesto.mano),
      findsNothing,
      reason: 'tras dos demostraciones la mano se aparta',
    );
  });

  testWidgets('un solo control pulsa en su sitio y deja tocar de verdad', (
    tester,
  ) async {
    var tocado = 0;
    await tester.pumpWidget(ejemplo([origen], tocar: () => tocado++));
    await tester.pump(const Duration(milliseconds: 100));
    final pequeno = tester.getRect(find.byKey(DemostracionDelGesto.mano));
    await tester.pump(const Duration(milliseconds: 500));
    final grande = tester.getRect(find.byKey(DemostracionDelGesto.mano));
    expect(grande.width, greaterThan(pequeno.width));
    expect(grande.center, origen.center);
    await tester.tapAt(origen.center);
    expect(
      tocado,
      1,
      reason: 'la ilustración no puede comerse el toque del control real',
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'respeta reducir movimiento y no mantiene animaciones pendientes',
    (tester) async {
      await tester.pumpWidget(ejemplo([origen, destino], reducir: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'la explicación sigue visible y el gesto puede repetirse por paso',
    (tester) async {
      RegistroDeControles.vaciar();
      addTearDown(RegistroDeControles.vaciar);
      const tarea = TareaDelManual(
        camino: 'prueba',
        tituloDeLaPagina: 'Prueba',
        titulo: 'Tocar',
        ancla: 'tocar',
        cuerpo: '',
        pasos: [
          PasoGuiado(
            cual: 1,
            deCuantos: 2,
            texto: 'Pulsa el control para abrirlo.',
            senala: 'control',
          ),
          PasoGuiado(
            cual: 2,
            deCuantos: 2,
            texto: 'Comprueba el resultado antes de terminar.',
            senala: 'control',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned(
                  left: 40,
                  top: 40,
                  child: ControlSenalado(
                    nombre: 'control',
                    child: SizedBox(
                      width: 100,
                      height: 60,
                      child: Text('Control'),
                    ),
                  ),
                ),
                CapaDelRecorrido(tarea: tarea, alSalir: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pulsa el control para abrirlo.'), findsOneWidget);
      expect(find.byKey(DemostracionDelGesto.mano), findsNothing);
      await tester.tap(find.text('Ver el gesto otra vez'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(DemostracionDelGesto.mano), findsOneWidget);
      await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Comprueba el resultado antes de terminar.'),
        findsOneWidget,
      );
      expect(
        find.byKey(DemostracionDelGesto.mano),
        findsOneWidget,
        reason: 'cada paso debe mostrar su propia demostración',
      );
      await tester.pumpAndSettle();
    },
  );
}
