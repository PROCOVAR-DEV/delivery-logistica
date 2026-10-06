import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/selector.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

const tarea = TareaDelManual(
  ancla: 'accion',
  titulo: 'Sucursal',
  camino: 'apk/prueba.md',
  tituloDeLaPagina: 'Prueba',
  cuerpo: '',
  pasos: [
    PasoGuiado(
      cual: 1,
      deCuantos: 2,
      texto: 'Abrir selector',
      senala: 'barra-sucursal',
    ),
    PasoGuiado(
      cual: 2,
      deCuantos: 2,
      texto: 'Elegir otra',
      senala: 'barra-elegir-sucursal',
    ),
  ],
);
Future<void> asentar(WidgetTester t) async {
  for (var i = 0; i < 35; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  for (final elegir in [true, false]) {
    testWidgets(
      'selector real ${elegir ? 'segunda opcion completa' : 'cerrar no completa'}',
      (t) async {
        addTearDown(Recorrido.salir);
        addTearDown(RegistroDeControles.vaciar);
        await t.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => t.binding.setSurfaceSize(null));
        late BuildContext contexto;
        var sucursal = '';
        await t.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (c, setState) {
                contexto = c;
                return Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: ControlSenalado(
                      nombre: 'barra-sucursal',
                      child: Selector<String>(
                        valor: sucursal,
                        etiquetaVacia: 'Elegir',
                        senaladoDelCajon: 'barra-elegir-sucursal',
                        opciones: const [
                          OpcionSelector(valor: '', etiqueta: 'Todas'),
                          OpcionSelector(valor: 'hab', etiqueta: 'Habana'),
                          OpcionSelector(valor: 'stg', etiqueta: 'Santiago'),
                        ],
                        alElegir: (v) => setState(() => sucursal = v),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
        await asentar(t);
        final semantics = t.ensureSemantics();
        try {
          t.binding.performSemanticsAction(
            SemanticsActionEvent(
              nodeId: t.getSemantics(find.text('Todas')).id,
              type: SemanticsAction.tap,
              viewId: t.view.viewId,
            ),
          );
          await asentar(t);
          expect(find.text('2 de 2'), findsOneWidget);
          expect(
            RegistroDeControles.donde('barra-elegir-sucursal')!.rect
                .contains(t.getCenter(find.text('Habana'))),
            isTrue,
          );
          if (elegir) {
            await t.tap(find.text('Habana'));
            await asentar(t);
            expect(sucursal, 'hab');
            expect(Recorrido.enMarcha, isFalse);
          } else {
            Navigator.of(contexto).pop();
            await asentar(t);
            expect(sucursal, '');
            expect(Recorrido.enMarcha, isTrue);
            expect(find.text('2 de 2'), findsOneWidget);
          }
          Recorrido.salir();
          await t.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
  for (final tocar in [true, false]) {
    testWidgets(
      'objetivo tardio ${tocar ? 'con toque previo avanza' : 'sin toque no avanza'}',
      (t) async {
        addTearDown(Recorrido.salir);
        addTearDown(RegistroDeControles.vaciar);
        late BuildContext contexto;
        late StateSetter cambiar;
        var visible = false;
        await t.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (c, setState) {
                contexto = c;
                cambiar = setState;
                return Scaffold(
                  body: Column(
                    children: [
                      ControlSenalado(
                        nombre: 'barra-sucursal',
                        child: TextButton(
                          onPressed: () {},
                          child: const Text('Accion'),
                        ),
                      ),
                      if (visible)
                        const ControlSenalado(
                          nombre: 'barra-elegir-sucursal',
                          child: Text('Objetivo tardio'),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
        await asentar(t);
        if (tocar) {
          await t.tap(find.text('Accion'));
          await asentar(t);
          expect(find.text('1 de 2'), findsOneWidget);
        }
        cambiar(() => visible = true);
        await asentar(t);
        expect(find.text(tocar ? '2 de 2' : '1 de 2'), findsOneWidget);
        Recorrido.salir();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
