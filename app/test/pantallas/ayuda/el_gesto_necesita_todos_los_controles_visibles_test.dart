import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/demostracion_del_gesto.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

void main() {
  testWidgets(
    'no demuestra ni repite un arrastre cuyo destino está fuera de pantalla',
    (tester) async {
      RegistroDeControles.vaciar();
      addTearDown(RegistroDeControles.vaciar);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
      const tarea = TareaDelManual(
        camino: 'prueba',
        tituloDeLaPagina: 'Prueba',
        titulo: 'Arrastra',
        ancla: 'arrastra',
        cuerpo: '',
        pasos: [
          PasoGuiado(
            cual: 1,
            deCuantos: 1,
            texto: 'Lleva el origen al destino.',
            senala: 'origen-visible',
            senalaTambien: ['destino-fuera'],
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
                    nombre: 'origen-visible',
                    child: SizedBox(
                      width: 100,
                      height: 60,
                      child: Text('Origen visible'),
                    ),
                  ),
                ),
                const Positioned(
                  left: 1200,
                  top: 200,
                  child: ControlSenalado(
                    nombre: 'destino-fuera',
                    child: SizedBox(
                      width: 100,
                      height: 60,
                      child: Text('Destino fuera'),
                    ),
                  ),
                ),
                CapaDelRecorrido(tarea: tarea, alSalir: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(RegistroDeControles.donde('origen-visible'), isNotNull);
      expect(
        RegistroDeControles.donde('destino-fuera'),
        isNotNull,
        reason: 'el control existe: lo que falla es su visibilidad después de recortar',
      );
      expect(
        find.byKey(DemostracionDelGesto.mano),
        findsNothing,
        reason: 'un arrastre con un solo extremo visible no debe convertirse en una demostración de pulsación',
      );
      expect(
        find.text('Ver el gesto otra vez'),
        findsNothing,
        reason: 'no hay un gesto completo visible que repetir',
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
