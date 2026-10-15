// «SIN COLOCAR» SE FILTRA DE UN DÍA A OTRO — issue 13 de Amado, 15/10/2026.
//
// «El filtro de pedidos necesita que tenga un rango de fecha desde/hasta, además
// de la del día que existe hoy.» Pedidos ya lo tenía; el cajón de filtros de la
// mitad izquierda del Tablero sólo tenía «Día del pedido». Ahora lleva los
// mismos controles que Pedidos (`RangoDeFechas`): `Desde`, `Hasta`, `sólo ese
// día` —el día suelto de antes— y la ✕.
//
// Se pinta en un teléfono de 390 px y en escritorio: un desborde en cualquiera
// de los dos tumba la prueba. Lo que filtra de verdad la base lo prueban
// `sin_colocar_test.dart` (el aparato) y la pareja del servidor.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/rango_de_fechas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/panel_sin_colocar.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  for (final (donde, tamano) in [
    ('un teléfono de 390 px', const Size(390, 844)),
    ('escritorio', const Size(1440, 900)),
  ]) {
    testWidgets('desde, hasta, sólo ese día y la ✕ en $donde', (tester) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final contenedor = ProviderContainer.test(
        overrides: [
          baseProvider.overrideWithValue(base),
          // El calendario se abre por el mes de HOY, el de la aplicación.
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
                  sucursalId: 'suc-stg',
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
      FiltrosSinColocar filtros() => contenedor.read(filtrosTableroProvider);

      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Desde (fecha del pedido)'), findsOneWidget);
      expect(find.text('Hasta (fecha del pedido)'), findsOneWidget);
      expect(
        find.text('Día del pedido'),
        findsNothing,
        reason: 'el día suelto de antes es ahora `sólo ese día`',
      );

      await tester.tap(find.text('Desde (fecha del pedido)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').last);
      await tester.pumpAndSettle();
      expect(filtros().desde, DateTime(2026, 9, 12));
      expect(
        filtros().hasta,
        isNull,
        reason: 'sólo desde: hasta queda abierto',
      );

      await tester.tap(find.text('Hasta (fecha del pedido)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14').last);
      await tester.pumpAndSettle();
      expect(filtros().desde, DateTime(2026, 9, 12));
      expect(filtros().hasta, DateTime(2026, 9, 14));
      expect(find.text('12/9/2026'), findsOneWidget);
      expect(find.text('14/9/2026'), findsOneWidget);

      await tester.tap(find.text('sólo ese día'));
      await tester.pumpAndSettle();
      expect(filtros().hasta, DateTime(2026, 9, 12), reason: 'un día = desde');

      await tester.tap(find.byTooltip(RangoDeFechas.tooltipQuitar));
      await tester.pumpAndSettle();
      expect([filtros().desde, filtros().hasta], [null, null]);
      expect(filtros().hayAlguno, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      contenedor.dispose();
    });
  }
}
