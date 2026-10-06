import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('volver al paso cancela apertura pendiente vieja', (t) async {
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
    await t.tap(find.text('Accion'));
    await asentar(t);
    await t.tap(find.byKey(ClavesDelRecorrido.siguiente));
    await asentar(t);
    expect(find.text('2 de 2'), findsOneWidget);
    await t.tap(find.byKey(ClavesDelRecorrido.atras));
    await asentar(t);
    expect(find.text('1 de 2'), findsOneWidget);
    cambiar(() => visible = true);
    await asentar(t);
    expect(
      find.text('1 de 2'),
      findsOneWidget,
      reason: 'Una aparición pendiente del recorrido anterior no adelanta este paso',
    );
    Recorrido.salir();
    await t.pumpWidget(const SizedBox());
  });
}
