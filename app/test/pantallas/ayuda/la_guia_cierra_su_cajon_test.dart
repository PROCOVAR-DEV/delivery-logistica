// La Guía enseña su propia lista desde un cajón del navegador raíz. En
// producción, `ShellRoute` pone la página en OTRO Navigator: un pop desde la
// página no cierra el cajón, y cambiar solamente ?tarea tampoco lo cierra.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/datos/proveedores.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/pantalla_guia.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

Future<GoRouter> _montar(
  WidgetTester tester,
  Manual manual,
  FormaDeLaAplicacion forma,
  String id,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  addTearDown(RegistroDeControles.vaciar);
  addTearDown(Recorrido.salir);
  final navegadorDelArmazon = GlobalKey<NavigatorState>();
  final enrutador = GoRouter(
    initialLocation: Uri(
      path: '/guia',
      queryParameters: {'tarea': id},
    ).toString(),
    routes: [
      ShellRoute(
        navigatorKey: navegadorDelArmazon,
        builder: (_, _, hijo) => Scaffold(body: hijo),
        routes: [
          GoRoute(path: '/guia', builder: (_, _) => const PantallaGuia()),
        ],
      ),
    ],
  );
  addTearDown(enrutador.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        formaDeLaAplicacionProvider.overrideWithValue(forma),
        manualProvider.overrideWith((_) => manual),
      ],
      child: MaterialApp.router(
        routerConfig: enrutador,
        builder: (context, hijo) => MediaQuery(
          // Aquí se prueba el toque y la navegación, no la animación.
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: hijo!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  expect(find.byType(Cajon), findsOneWidget);
  expect(
    navegadorDelArmazon.currentState!.canPop(),
    isFalse,
    reason: 'el cajón está en la raíz, no en el Navigator de la página',
  );
  return enrutador;
}

void main() {
  // Fuera del reloj falso; rootBundle dentro de testWidgets puede colgarlo.
  final paquete = File(assetDelManual).readAsStringSync();
  for (final forma in FormaDeLaAplicacion.values) {
    testWidgets('la Guía libera su lista y guía el toque real en ${forma.name}', (
      tester,
    ) async {
      final manual = Manual.desdeElPaquete(
        paquete,
        pantallas: pantallasParaLaGuia(),
      ).paraLaForma(forma);
      final idDeLaGuia = manual.tareas
          .singleWhere(
            (tarea) => tarea.titulo == 'Que la Guía te lleve de la mano',
          )
          .id;
      final enrutador = await _montar(tester, manual, forma, idDeLaGuia);
      await tester.tap(find.byKey(ClavesDeLaGuia.guiarme));
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsNothing,
        reason:
            'el cajón de la tarea no puede tapar la lista que enseña el paso 1',
      );
      expect(enrutador.routeInformationProvider.value.uri.path, '/guia');
      expect(
        enrutador.routeInformationProvider.value.uri.queryParameters,
        isEmpty,
      );
      expect(find.text(TextosDelRecorrido.cualDeCuantos(1, 3)), findsOneWidget);
      final control = RegistroDeControles.donde(Senalado.guiaPrimeraTarea);
      expect(control, isNotNull);
      expect(
        tester
            .getRect(find.byKey(ClavesDelRecorrido.foco))
            .contains(control!.rect.center),
        isTrue,
      );

      // No invocamos onPressed: el dedo atraviesa de verdad el hueco del velo y
      // abre el cajón mediante la URL. Con el cajón viejo encima esto falla.
      await tester.tapAt(control.rect.center);
      await tester.pumpAndSettle();
      final primeraTarea = manual.tareas.first;
      expect(find.byType(Cajon), findsOneWidget);
      expect(
        enrutador.routeInformationProvider.value.uri.queryParameters['tarea'],
        primeraTarea.id,
        reason: 'la limpieza de la URL anterior no debe borrar la tarea recién abierta',
      );
      await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
      await tester.pumpAndSettle();
      expect(find.text(TextosDelRecorrido.cualDeCuantos(2, 3)), findsOneWidget);
      final mando = RegistroDeControles.donde(Senalado.guiaGuiarme);
      expect(mando, isNotNull);
      expect(
        tester
            .getRect(find.byKey(ClavesDelRecorrido.foco))
            .contains(mando!.rect.center),
        isTrue,
        reason: 'el paso 2 tiene que señalar el botón del cajón recién abierto',
      );

      await tester.tap(find.byKey(ClavesDelRecorrido.salir));
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesDelRecorrido.capa), findsNothing);
      expect(find.byType(Cajon), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(Cajon), findsNothing);
      expect(enrutador.routeInformationProvider.value.uri.path, '/guia');
      expect(
        enrutador.routeInformationProvider.value.uri.queryParameters,
        isEmpty,
      );
      // Reabrir prueba que el indicador _nosVamos no se quedó bloqueando la Guía.
      await tester.tap(find.byKey(ClavesDeLaGuia.tarea(primeraTarea.id)));
      await tester.pumpAndSettle();
      expect(find.byType(Cajon), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'sin pantalla de destino cierra la raíz y deja reutilizar la tarea',
    (tester) async {
      final manual = Manual.desdeElPaquete(
        empaquetarManual({
          'comun/franja.md': '''
# Franja
## Mirar la franja
<!-- tarea -->
**Empieza en:** la franja de arriba, desde cualquier pantalla.
1. Mira la franja.
''',
        }),
        pantallas: pantallasParaLaGuia(),
      ).paraLaForma(FormaDeLaAplicacion.apk);
      final tarea = manual.tareas.single;
      expect(tarea.rutaDePantalla, isNull);
      final enrutador = await _montar(
        tester,
        manual,
        FormaDeLaAplicacion.apk,
        tarea.id,
      );
      await tester.tap(find.byKey(ClavesDeLaGuia.guiarme));
      await tester.pumpAndSettle();
      expect(find.byType(Cajon), findsNothing);
      expect(find.byType(PantallaGuia), findsOneWidget);
      expect(
        enrutador.routeInformationProvider.value.uri.queryParameters,
        isEmpty,
      );
      await tester.tap(find.byKey(ClavesDelRecorrido.salir));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ClavesDeLaGuia.tarea(tarea.id)));
      await tester.pumpAndSettle();
      expect(find.byType(Cajon), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
