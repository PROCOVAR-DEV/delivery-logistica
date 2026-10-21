// DE PEDIDOS SE TIENE QUE PODER SALIR — 24/09/2026.
//
// Pedidos escribe sus filtros en la direccion, y lo hace **despues del
// fotograma** porque un `context.go` en mitad de un `build` reconstruye el arbol
// que se esta construyendo. El problema es lo que pasa cuando entre medias
// alguien navega a otro sitio:
//
//   1. se pulsa «Rutas» en el menu, `context.go('/routes')` hace su trabajo;
//   2. el callback encolado por el ultimo `build` de Pedidos se ejecuta;
//   3. ese callback hace `replace('/orders?...')` y **vuelve a poner Pedidos**.
//
// Desde la silla de quien trabaja: se entra en Pedidos y ya no se sale por el
// menu. Ni error, ni aviso, ni pantalla en blanco — el resto de la pantalla
// sigue respondiendo, asi que ni siquiera parece colgada. Visto dos veces
// seguidas en la aplicacion de escritorio el 24/09/2026.
//
// `mounted` no bastaba: entre el `go` y el callback la pantalla de antes sigue
// montada, que es justo la ventana en la que esto muerde.
//
// LAS DOS PRUEBAS VAN EN PAREJA, y hacen falta las dos: una que se pueda salir,
// y otra que **estando en Pedidos la direccion siga escribiendose**. Sin la
// segunda, «no escribir nunca la direccion» pasaria la primera y se llevaria por
// delante el enlace a la lista filtrada, que es para lo que existe.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 24, 14, 30);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<GoRouter> pintar(
    WidgetTester tester, {
    String desde = '/facturas',
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: desde,
      routes: [
        GoRoute(
          path: '/facturas',
          builder: (_, estado) => Scaffold(
            body: PantallaPedidos(consulta: estado.uri.queryParameters),
          ),
        ),
        GoRoute(
          path: '/routes',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('AQUI ESTAN LAS RUTAS'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return router;
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('salir de Pedidos por el menu lleva a otro sitio y se queda', (
    tester,
  ) async {
    final router = await pintar(tester);

    // Lo que hace el menu de la izquierda (`navegacion/barra_lateral.dart`).
    router.go('/routes');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      router.state.matchedLocation,
      '/routes',
      reason:
          'Pedidos volvio a ponerse encima con su `replace` de los filtros: '
          'desde la silla de quien trabaja, el menu esta muerto',
    );
    expect(find.text('AQUI ESTAN LAS RUTAS'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('y estando EN Pedidos la direccion se sigue escribiendo', (
    tester,
  ) async {
    // El enlace a la lista filtrada es para lo que existe ese `replace`: si la
    // guarda lo apagara del todo, recargar vaciaria los filtros y mandar la
    // lista por WhatsApp dejaria de funcionar.
    final router = await pintar(
      tester,
      desde: '/facturas?municipio=Cama%C3%BCey&pagina=2',
    );

    expect(router.state.matchedLocation, '/facturas');
    expect(
      router.state.uri.queryParameters['municipio'],
      isNotNull,
      reason: 'el filtro del enlace no puede desaparecer de la direccion',
    );
    await desmontar(tester);
  });
}
