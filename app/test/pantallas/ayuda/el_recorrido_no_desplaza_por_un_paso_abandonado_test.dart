import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

const tarea = TareaDelManual(
  ancla: 'carrera',
  titulo: 'Carrera',
  camino: 'apk/prueba.md',
  tituloDeLaPagina: 'Prueba',
  cuerpo: '',
  pasos: [
    PasoGuiado(
      cual: 1,
      deCuantos: 2,
      texto: 'Esperar primero',
      senala: 'primero',
    ),
    PasoGuiado(cual: 2, deCuantos: 2, texto: 'Segundo', senala: 'segundo'),
  ],
);
void main() {
  testWidgets(
    'objetivo viejo aparece durante medicion y nunca roba foco del paso actual',
    (t) async {
      addTearDown(Recorrido.salir);
      addTearDown(RegistroDeControles.vaciar);
      late BuildContext contexto;
      late StateSetter cambiar;
      var primero = false;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (c, setState) {
              contexto = c;
              cambiar = setState;
              return Scaffold(
                body: SingleChildScrollView(
                  controller: scroll,
                  child: Column(
                    children: [
                      const ControlSenalado(
                        nombre: 'segundo',
                        child: Text('Objetivo actual'),
                      ),
                      const SizedBox(height: 1600),
                      if (primero)
                        const ControlSenalado(
                          nombre: 'primero',
                          child: Text('Objetivo antiguo tardio'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      await t.tap(find.byKey(ClavesDelRecorrido.siguiente));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('2 de 2'), findsOneWidget);
      cambiar(() => primero = true);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 16));
        expect(
          scroll.offset,
          0,
          reason: 'La medición vieja no puede desplazar la pantalla hacia el paso abandonado',
        );
        final foco = find.byKey(ClavesDelRecorrido.foco);
        if (foco.evaluate().isNotEmpty) {
          expect(
            t
                .getRect(foco)
                .contains(RegistroDeControles.donde('segundo')!.rect.center),
            isTrue,
            reason: 'El objetivo viejo no debe tomar foco ni un fotograma tras cambiar de paso',
          );
        }
      }
      expect(t.takeException(), isNull);
      Recorrido.salir();
      await t.pumpWidget(const SizedBox());
    },
  );
}
