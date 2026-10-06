import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import 'el_tablero_conecta_el_destino_real_test.dart' show TableroFalso;

class TableroQueAnota extends TableroFalso {
  final nombres = <String>[];
  @override
  Future<String> crearColumna(String nombre, {String? vehiculoId}) async {
    nombres.add(nombre);
    return "zona-prueba";
  }
}

void main() {
  final manual = Manual.desdeElPaquete(
    File('assets/manual/manual.txt').readAsStringSync(),
    pantallas: const [PantallaDelMenu('/board', 'Tablero')],
  );
  final tarea = manual
      .paraLaForma(FormaDeLaAplicacion.web)
      .tareas
      .singleWhere(
        (t) =>
            t.camino == 'web/1-el-dia-en-la-web.md' &&
            t.titulo == '4.1 Crear una zona',
      );
  testWidgets(
    'Nueva columna real conserva la Guía encima del cajón y avanza al campo',
    (tester) async {
      RegistroDeControles.vaciar();
      addTearDown(RegistroDeControles.vaciar);
      addTearDown(Recorrido.salir);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 800);
      addTearDown(tester.view.reset);
      late OverlayState capa;
      final mando = TableroQueAnota();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tableroProvider.overrideWith(() => mando),
            monedaEfectivaProvider.overrideWithValue('USD'),
            tasaDeLaMiradaProvider.overrideWithValue(
              const TasaDeLaMirada.no('sin tasa en prueba'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (contexto) {
                  capa = Overlay.of(contexto, rootOverlay: true);
                  return const PantallaTablero();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Recorrido.empezarEn(capa, tarea);
      await tester.pumpAndSettle();
      expect(find.text('1 de 3'), findsOneWidget);
      await tester.tap(find.text('Columna'));
      await tester.pumpAndSettle();
      expect(find.text('Nueva columna'), findsOneWidget);
      expect(find.text('Nombre de la zona'), findsOneWidget);
      await tester.tap(
        find.byKey(ClavesDelRecorrido.siguiente),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('2 de 3'),
        findsOneWidget,
        reason: 'Siguiente debe seguir accesible ENCIMA del DialogRoute del cajón real',
      );
      expect(
        find.text('Nombre de la zona'),
        findsOneWidget,
        reason:
            'avanzar la Guía no debe tocar el ModalBarrier ni cerrar el cajón',
      );
      final campoNombre = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Nombre de la zona',
      );
      final focoCampo = tester.getRect(find.byKey(ClavesDelRecorrido.foco));
      expect(
        focoCampo.contains(tester.getCenter(campoNombre)),
        isTrue,
        reason: 'el foco del paso 2 debe envolver EL CAMPO del cajón real',
      );
      await tester.tap(campoNombre);
      await tester.enterText(campoNombre, 'Zona del piloto');
      await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
      await tester.pumpAndSettle();
      expect(find.text('3 de 3'), findsOneWidget);
      final focoGuardar = tester.getRect(find.byKey(ClavesDelRecorrido.foco));
      expect(
        focoGuardar.contains(tester.getCenter(find.text('Guardar'))),
        isTrue,
        reason: 'el último foco debe envolver Guardar dentro del cajón',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        mando.nombres,
        ['Zona del piloto'],
        reason: 'el nombre que escribió la persona debe salir del cajón real al notifier',
      );
      expect(find.text('Nueva columna'), findsNothing);
      await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
      await tester.pumpAndSettle();
      expect(
        Recorrido.enMarcha,
        isFalse,
        reason: 'Ya está debe terminar el recorrido después de guardar',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
