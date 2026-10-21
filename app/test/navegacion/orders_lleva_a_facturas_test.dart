// `/orders` YA NO ES UNA PANTALLA: LLEVA A `/facturas`, CON SUS FILTROS.
//
// Jose, 21/10/2026: «ya no son pedidos, son facturas; la URL va a ser facturas». La lista
// vive en `/facturas`, pero hay enlaces pegados en chats y favoritos con `/orders?...`
// (y el portal de Accesos): tienen que seguir valiendo y NO perder los filtros.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/rutas.dart';

void main() {
  Future<GoRouter> irA(WidgetTester tester, String destino) async {
    final router = crearEnrutador(
      inicial: '/facturas',
      pantallas: [
        PantallaRegistrada(
          ruta: '/facturas',
          titulo: 'Facturas',
          colecciones: const [],
          construir: (contexto, estado) =>
              Text('LISTA ${estado.uri.queryParameters}'),
          conArmazon: false,
        ),
        // El armazón exige al menos una pantalla propia; ésta no se visita.
        PantallaRegistrada(
          ruta: '/relleno',
          titulo: 'Relleno',
          colecciones: const [],
          construir: (contexto, estado) => const SizedBox(),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go(destino);
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('/orders a secas va a /facturas', (tester) async {
    final router = await irA(tester, '/orders');
    expect(router.state.uri.toString(), '/facturas');
    expect(find.textContaining('LISTA'), findsOneWidget);
  });

  testWidgets('/orders con filtros va a /facturas y los conserva', (
    tester,
  ) async {
    final router = await irA(tester, '/orders?municipio=Centro&pagina=2');
    expect(router.state.uri.path, '/facturas');
    expect(router.state.uri.queryParameters, {
      'municipio': 'Centro',
      'pagina': '2',
    });
    expect(find.textContaining('municipio: Centro'), findsOneWidget);
  });

  // La gemela: lo que no es `/orders` no se toca.
  testWidgets('/facturas se queda donde está', (tester) async {
    final router = await irA(tester, '/facturas?municipio=Centro');
    expect(router.state.uri.toString(), '/facturas?municipio=Centro');
  });
}
