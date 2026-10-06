import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

const tarea = TareaDelManual(
  ancla: 'diagnostico',
  titulo: 'Alta',
  camino: 'apk/prueba.md',
  tituloDeLaPagina: 'Prueba',
  cuerpo: '',
  pasos: [
    PasoGuiado(cual: 1, deCuantos: 2, texto: 'Abrir', senala: 'abrir'),
    PasoGuiado(cual: 2, deCuantos: 2, texto: 'Nombre', senala: 'nombre'),
  ],
);

void main() {
  for (final alignment in [Alignment.topCenter, Alignment.center]) {
    for (final larga in [false, true]) {
      testWidgets(
        'la tarjeta deja sus mandos por encima del teclado (nota larga: $larga; posición: $alignment)',
        (tester) async {
          addTearDown(Recorrido.salir);
          addTearDown(RegistroDeControles.vaciar);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.reset);
          late BuildContext contexto;
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  contexto = context;
                  return Scaffold(
                    body: Align(
                      alignment: alignment,
                      child: ControlSenalado(
                        nombre: 'abrir',
                        child: TextField(),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.tap(find.byType(TextField));
          await tester.pump();
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
          );
          final manual = larga
              ? TareaDelManual(
                  ancla: tarea.ancla,
                  titulo: tarea.titulo,
                  camino: tarea.camino,
                  tituloDeLaPagina: tarea.tituloDeLaPagina,
                  cuerpo: '',
                  pasos: [
                    PasoGuiado(
                      cual: 1,
                      deCuantos: 1,
                      texto: List.filled(
                        40,
                        'Escribe el nombre del vehículo y comprueba los datos.',
                      ).join(' '),
                      senala: 'abrir',
                    ),
                  ],
                )
              : tarea;
          Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), manual);
          await tester.pumpAndSettle();
          expect(find.byKey(ClavesDelRecorrido.foco), findsOneWidget);
          expect(
            tester.getRect(find.byKey(ClavesDelRecorrido.tarjeta)).bottom,
            lessThanOrEqualTo(544),
            reason: 'La tarjeta debe quedar dentro de la altura visible encima de viewInsets.bottom=300',
          );
          expect(tester.takeException(), isNull);
          expect(
            tester
                .getRect(find.byKey(ClavesDelRecorrido.tarjeta))
                .overlaps(tester.getRect(find.byKey(ClavesDelRecorrido.foco))),
            isFalse,
            reason:
                'La explicación no debe cubrir el campo que hay que rellenar',
          );
          for (final clave in [
            ClavesDelRecorrido.salir,
            ClavesDelRecorrido.siguiente,
          ]) {
            expect(
              tester.getRect(find.byKey(clave)).bottom,
              lessThanOrEqualTo(544),
            );
          }
          await tester.tap(find.byKey(ClavesDelRecorrido.salir));
          await tester.pumpAndSettle();
          expect(find.byKey(ClavesDelRecorrido.tarjeta), findsNothing);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
