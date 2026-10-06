import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/cajon.dart';
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
  testWidgets('panel nuevo conserva tutorial accesible', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    addTearDown(Recorrido.salir);
    addTearDown(RegistroDeControles.vaciar);
    late BuildContext contexto;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            contexto = context;
            return Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: ControlSenalado(
                  nombre: 'abrir',
                  child: TextButton(
                    onPressed: () {
                      abrirCajon<void>(
                        context,
                        titulo: 'Ficha',
                        cuerpo: (_) => const ControlSenalado(
                          nombre: 'nombre',
                          child: TextField(),
                        ),
                      );
                    },
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
    await tester.pumpAndSettle();
    await tester.tapAt(RegistroDeControles.donde('abrir')!.rect.center);
    await tester.pumpAndSettle();
    expect(find.byType(Cajon), findsOneWidget);
    expect(
      find.byKey(ClavesDelRecorrido.siguiente).hitTestable(),
      findsOneWidget,
      reason: 'Siguiente debe quedar sobre el cajón recién abierto',
    );
    expect(find.text('2 de 2'), findsOneWidget);
    expect(find.byKey(ClavesDelRecorrido.foco), findsOneWidget);
    expect(tester.takeException(), isNull);
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('control aparece después de la espera', (tester) async {
    addTearDown(Recorrido.salir);
    addTearDown(RegistroDeControles.vaciar);
    late BuildContext contexto;
    late StateSetter cambiar;
    var visible = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            contexto = context;
            cambiar = setState;
            return Scaffold(
              body: visible
                  ? const ControlSenalado(
                      nombre: 'abrir',
                      child: Text('Control tardío'),
                    )
                  : const SizedBox(),
            );
          },
        ),
      ),
    );
    Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    cambiar(() => visible = true);
    await tester.pumpAndSettle();
    expect(RegistroDeControles.donde('abrir'), isNotNull);
    expect(
      find.byKey(ClavesDelRecorrido.foco),
      findsOneWidget,
      reason: 'Al llegar el control real el tutorial debe recuperar el foco sin exigir cambiar de paso',
    );
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el foco sigue al control tras cambiar geometría', (
    tester,
  ) async {
    addTearDown(Recorrido.salir);
    addTearDown(RegistroDeControles.vaciar);
    late BuildContext contexto;
    late StateSetter cambiar;
    var abajo = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            contexto = context;
            cambiar = setState;
            return Scaffold(
              body: Align(
                alignment: abajo ? Alignment.bottomCenter : Alignment.topCenter,
                child: const ControlSenalado(
                  nombre: 'abrir',
                  child: Text('Control móvil'),
                ),
              ),
            );
          },
        ),
      ),
    );
    Recorrido.empezarEn(Overlay.of(contexto, rootOverlay: true), tarea);
    await tester.pumpAndSettle();
    cambiar(() => abajo = true);
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.byKey(ClavesDelRecorrido.foco))
          .contains(RegistroDeControles.donde('abrir')!.rect.center),
      isTrue,
      reason: 'El foco debe seguir donde quedó el botón al cambiar el layout',
    );
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('menú móvil abre y señala al acabar su animación', (
    tester,
  ) async {
    addTearDown(Recorrido.salir);
    addTearDown(RegistroDeControles.vaciar);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    late BuildContext contexto;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            contexto = context;
            return Scaffold(
              appBar: AppBar(
                actions: const [
                  ControlSenalado(
                    nombre: 'cuenta-avatar',
                    child: Icon(Icons.person),
                  ),
                ],
              ),
              drawer: const Drawer(
                child: SafeArea(
                  child: ControlSenalado(
                    nombre: 'menu-clientes',
                    child: Text('Clientes'),
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
    expect(RegistroDeControles.donde('menu-clientes'), isNotNull);
    expect(
      find.byKey(ClavesDelRecorrido.foco),
      findsOneWidget,
      reason: 'Al abrir el menú debe señalar su entrada visible',
    );
    expect(
      tester
          .getRect(find.byKey(ClavesDelRecorrido.foco))
          .contains(RegistroDeControles.donde('menu-clientes')!.rect.center),
      isTrue,
      reason: 'Se mide donde acabó el drawer y no donde comenzó la animación',
    );
    Recorrido.salir();
    await tester.pumpWidget(const SizedBox());
  });
}
