import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reparto/diseno/cajon.dart';

void main() {
  late GoRouter enrutador;

  Widget marco(String ruta) => Builder(
        builder: (contexto) => Column(
          children: [
            Text('PANTALLA $ruta'),
            TextButton(
              onPressed: () => abrirCajon<void>(contexto,
                  titulo: 'El cajon', cuerpo: (_) => const Text('dentro')),
              child: const Text('abrir'),
            ),
          ],
        ),
      );

  setUp(() {
    enrutador = GoRouter(
      initialLocation: '/lista',
      routes: [
        ShellRoute(
          builder: (c, s, hijo) => Scaffold(body: hijo),
          routes: [
            GoRoute(path: '/lista', builder: (c, s) => marco('LISTA')),
            GoRoute(path: '/detalle', builder: (c, s) => marco('DETALLE')),
          ],
        ),
      ],
    );
  });

  testWidgets('el ATRAS DEL NAVEGADOR (cambio de URL) con cajon abierto', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: enrutador));
    await tester.pumpAndSettle();
    enrutador.go('/detalle');
    await tester.pumpAndSettle();

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byType(Cajon), findsOneWidget);

    // Esto es lo que hace el boton atras del NAVEGADOR en web: no dispara
    // `popRoute`, cambia la direccion.
    enrutador.go('/lista');
    await tester.pumpAndSettle();

    debugPrint('cajon sigue: ${find.byType(Cajon).evaluate().length}');
    debugPrint('LISTA: ${find.text('PANTALLA LISTA').evaluate().length}');
    debugPrint('DETALLE: ${find.text('PANTALLA DETALLE').evaluate().length}');
  });

  testWidgets('dos cajones apilados y un atras', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: enrutador));
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final fue = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    debugPrint('UNA SOLA pantalla: atras devolvio $fue, cajon=${find.byType(Cajon).evaluate().length}, pantalla=${find.text('PANTALLA LISTA').evaluate().length}');
  });
}
