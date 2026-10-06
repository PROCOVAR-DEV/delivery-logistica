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
  testWidgets('sin objetivo deja tocar la aplicación y recupera el foco', (
    tester,
  ) async {
    addTearDown(Recorrido.salir);
    addTearDown(RegistroDeControles.vaciar);
    late BuildContext contexto;
    late StateSetter cambiar;
    var abierto = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            contexto = context;
            cambiar = setState;
            return Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: abierto
                    ? const ControlSenalado(
                        nombre: 'abrir',
                        child: Text('Campo que espera el tutorial'),
                      )
                    : TextButton(
                        onPressed: () => cambiar(() => abierto = true),
                        child: const Text('Preparar formulario'),
                      ),
              ),
            );
          },
        ),
      ),
    );
    Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(ClavesDelRecorrido.foco), findsNothing);
    await tester.tap(find.text('Preparar formulario'));
    await tester.pumpAndSettle();
    expect(
      abierto,
      isTrue,
      reason: 'La capa no debe impedir preparar el objetivo ausente',
    );
    expect(
      find.byKey(ClavesDelRecorrido.foco),
      findsOneWidget,
      reason: 'El tutorial retoma la marca al aparecer el formulario',
    );
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cambiar de paso durante desplazamiento nunca marca paso viejo', (
    tester,
  ) async {
    addTearDown(Recorrido.salir);
    addTearDown(RegistroDeControles.vaciar);
    late BuildContext contexto;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            contexto = context;
            return Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: const [
                    ControlSenalado(
                      nombre: 'nombre',
                      child: Text('Segundo objetivo'),
                    ),
                    SizedBox(height: 1600),
                    ControlSenalado(
                      nombre: 'abrir',
                      child: Text('Primer objetivo'),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final foco = find.byKey(ClavesDelRecorrido.foco);
      if (foco.evaluate().isNotEmpty) {
        expect(
          tester
              .getRect(foco)
              .contains(RegistroDeControles.donde('nombre')!.rect.center),
          isTrue,
          reason: 'El paso 2 no puede recibir la medida pendiente del paso 1',
        );
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('2 de 2'), findsOneWidget);
    expect(find.byKey(ClavesDelRecorrido.foco), findsOneWidget);
    expect(tester.takeException(), isNull);
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });
}
