// «SIN COLOCAR» FILTRA POR UNO O VARIOS VENDEDORES — issue 18 de Amado, 16/10/2026.
//
// «En el filtro de pedidos del tablero ajustar el filtro de vendedores para que sea
// de múltiple selección, es decir que él pueda escoger uno o más vendedores, porque
// pueden haber pocos domicilios y se combinan los de ambos.»
//
// Estas pruebas son de la PANTALLA: el cajón de filtros del Tablero lleva un
// `SelectorMultiple` (cajón con casillas, «Todos los vendedores» para limpiar y un
// resumen en el botón). Lo que filtra de verdad la base lo prueba `sin_colocar_test.dart`
// y el enlace, `filtros_en_la_url_test.dart`. Se pinta en un teléfono de 390 px y en
// escritorio, con un nombre largo a propósito (el que desbordaba el desplegable de antes).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/panel_sin_colocar.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

const _largo = 'Luis Alberto Dominguez Hernandez';

void main() {
  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  for (final (donde, tamano) in [
    ('un teléfono de 390 px', const Size(390, 844)),
    ('escritorio', const Size(1440, 900)),
  ]) {
    testWidgets('se marcan varios, se resume y «Todos» limpia en $donde', (
      tester,
    ) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await sembrarSucursal(base);
        await sembrarPedido(base, id: 'p1', vendedor: 'Ana');
        await sembrarPedido(base, id: 'p2', vendedor: _largo);
        await sembrarPedido(base, id: 'p3', vendedor: 'Marta');
        await sembrarPedido(base, id: 'p4', vendedor: 'Pedro');
      });

      final contenedor = ProviderContainer.test(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 10)),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: contenedor,
          child: MaterialApp(
            home: Scaffold(
              body: PanelSinColocar(
                tablero: Tablero(
                  sucursalId: sucursalStg,
                  sucursalNombre: 'Santiago',
                  almacen: const AlmacenOrigen(
                    id: 'a1',
                    nombre: 'Principal',
                    lat: 20,
                    lng: -75,
                  ),
                  columnas: const <ColumnaTablero>[],
                  colocados: const <TarjetaColocada>[],
                  avisos: const AvisosTablero(),
                  sinColocar: const MitadIzquierda(pedidos: [], total: 0),
                  desaparecidos: const <PedidoDesaparecido>[],
                ),
                alPulsarTarjeta: (_) {},
                alDevolver: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      List<String> puestos() =>
          contenedor.read(filtrosTableroProvider).vendedores;

      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();

      // La caja dice «todos» mientras no haya nada marcado.
      final caja = find.byKey(const ValueKey('Vendedor del pedido'));
      expect(caja, findsOneWidget);
      expect(
        find.descendant(of: caja, matching: find.text('Todos los vendedores')),
        findsOneWidget,
      );

      // Se abre el cajón de las casillas: una por vendedor y «Todos» arriba.
      await tester.tap(caja);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
      expect(
        find.byKey(const ValueKey('selector-multiple-todos')),
        findsOneWidget,
      );

      // UNO.
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      expect(puestos(), ['Ana']);

      // DOS (con el de nombre largo): el cajón sigue abierto y los dos quedan marcados.
      await tester.tap(find.text(_largo));
      await tester.pumpAndSettle();
      expect(puestos(), unorderedEquals(['Ana', _largo]));
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .where((c) => c.value ?? false),
        hasLength(2),
      );

      // Se cierra el cajón del selector: la caja resume «2 vendedores».
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: caja, matching: find.text('2 vendedores')),
        findsOneWidget,
      );

      // Se vuelve a abrir con lo marcado todavía marcado, se desmarca uno y queda el
      // nombre de ese, no un «1 vendedores».
      await tester.tap(caja);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      expect(puestos(), [_largo]);

      // «Todos» limpia.
      await tester.tap(find.byKey(const ValueKey('selector-multiple-todos')));
      await tester.pumpAndSettle();
      expect(puestos(), isEmpty);
      expect(contenedor.read(filtrosTableroProvider).hayAlguno, isFalse);

      expect(tester.takeException(), isNull, reason: 'sin overflow en $donde');
      await tester.pumpWidget(const SizedBox.shrink());
      contenedor.dispose();
    });
  }
}
