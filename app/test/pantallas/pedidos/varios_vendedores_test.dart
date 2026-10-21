// «PEDIDOS» FILTRA POR UNO O VARIOS VENDEDORES — issue 18 de Amado, 16/10/2026.
//
// El filtro de vendedor del Tablero pasó a ser de varios («pueden haber pocos
// domicilios y se combinan los de ambos») y la misma pregunta se hace aquí, en la
// pantalla de Pedidos: era el mismo desplegable de UNO. Cajón con casillas, y salen
// los pedidos de CUALQUIERA de los marcados.
//
// El filtro está en la dirección: `vendedor=Luis&vendedor=Marta`, y el enlace de
// antes (`vendedor=Luis`) se sigue leyendo (`filtros_en_la_url_test.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarLosOnce(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
  });

  tearDown(() => base.close());

  for (final (donde, tamano) in [
    ('un teléfono de 390 px', const Size(390, 844)),
    ('escritorio', const Size(1600, 1400)),
  ]) {
    testWidgets(
      'se marcan dos vendedores y salen los de cualquiera en $donde',
      (tester) async {
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseProvider.overrideWithValue(base),
              relojProvider.overrideWithValue(() => ahora),
            ],
            child: MaterialApp(
              localizationsDelegates: delegacionesDeIdioma,
              supportedLocales: idiomas,
              home: const Scaffold(body: PantallaPedidos()),
            ),
          ),
        );
        await _asentar(tester);
        final contenedor = ProviderScope.containerOf(
          tester.element(find.byType(PantallaPedidos)),
        );
        List<String> puestos() =>
            contenedor.read(filtrosPedidosProvider).vendedores;

        // La caja del filtro está entre los nueve; en un teléfono se pliegan en un
        // cajón, y el botón de abrirlo es el de «Filtros».
        final caja = find.byKey(const ValueKey('Vendedor de la factura'));
        if (caja.evaluate().isEmpty) {
          await tester.tap(find.byTooltip('Filtros').first);
          await _asentar(tester);
        }
        expect(caja, findsOneWidget);
        expect(
          find.descendant(
            of: caja,
            matching: find.text('Todos los vendedores'),
          ),
          findsOneWidget,
        );

        await tester.tap(caja);
        await _asentar(tester);
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Luis'));
        await _asentar(tester);
        expect(puestos(), ['Luis']);
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Marta'));
        await _asentar(tester);
        expect(puestos(), ['Luis', 'Marta']);

        // La unión: el arranque acotado deja 8; con los dos vendedores marcados, los de
        // cualquiera de los dos (los 8 son de Luis o de Marta en este juego de datos).
        Future<int> contar(List<String> vendedores) async =>
            (await tester.runAsync(
              () => contenedor
                  .read(consultasPedidosProvider)
                  .contar(
                    contenedor
                        .read(filtrosPedidosProvider)
                        .copiarCon(vendedores: vendedores),
                  )
                  .first,
            ))!;
        final soloLuis = await contar(['Luis']);
        final soloMarta = await contar(['Marta']);
        final los2 = await contar(['Luis', 'Marta']);
        expect(los2, soloLuis + soloMarta);
        expect(los2, greaterThan(soloLuis));
        expect(los2, greaterThan(soloMarta));

        // «Todos» limpia.
        await tester.tap(find.byKey(const ValueKey('selector-multiple-todos')));
        await _asentar(tester);
        expect(puestos(), isEmpty);

        expect(
          tester.takeException(),
          isNull,
          reason: 'sin overflow en $donde',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
