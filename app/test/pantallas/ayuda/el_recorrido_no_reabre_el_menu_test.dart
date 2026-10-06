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
  testWidgets('tocar entrada deja cerrado el menú real', (tester) async {
    addTearDown(Recorrido.salir);
    addTearDown(RegistroDeControles.vaciar);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final scaffold = GlobalKey<ScaffoldState>();
    late BuildContext contexto;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            contexto = context;
            return Scaffold(
              key: scaffold,
              appBar: AppBar(
                actions: const [
                  ControlSenalado(
                    nombre: 'cuenta-avatar',
                    child: Icon(Icons.person),
                  ),
                ],
              ),
              drawer: Drawer(
                child: SafeArea(
                  child: Builder(
                    builder: (drawerContext) => ControlSenalado(
                      nombre: 'menu-clientes',
                      child: ListTile(
                        title: const Text('Clientes'),
                        onTap: () => Navigator.of(drawerContext).pop(),
                      ),
                    ),
                  ),
                ),
              ),
              body: const SizedBox(),
            );
          },
        ),
      ),
    );
    const menu = TareaDelManual(
      ancla: 'menu',
      titulo: 'Clientes',
      camino: 'apk/prueba.md',
      tituloDeLaPagina: 'Prueba',
      cuerpo: '',
      pasos: [
        PasoGuiado(
          cual: 1,
          deCuantos: 1,
          texto: 'Clientes',
          senala: 'menu-clientes',
        ),
      ],
    );
    Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), menu);
    await tester.pumpAndSettle();
    expect(scaffold.currentState!.isDrawerOpen, isTrue);
    await tester.tapAt(RegistroDeControles.donde('menu-clientes')!.rect.center);
    await tester.pumpAndSettle();
    expect(
      scaffold.currentState!.isDrawerOpen,
      isFalse,
      reason: 'Después de tocar la entrada el tutorial no debe abrir el menú otra vez',
    );
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });
}
