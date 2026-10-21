// EL DETALLE DE UNA FACTURA DICE LO QUE LE FALTA (21/10/2026, Jose): una factura sin pedido no trae el
// punto del cliente, y la ubicación es OBLIGATORIA para meterla en una ruta. El aviso va arriba del todo
// con lo que hay que hacer, y el detalle dice de qué pedido viene (o que de ninguno).
//
// En pareja: sin punto sale el aviso, con punto no; con folio se enseña el folio, sin él se dice que no
// viene de ningún pedido y que la dirección se pone a mano.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_detalle_pedido.dart';

void main() {
  Pedido pedido({String? folio, bool conPunto = false}) => Pedido(
    id: 'p1',
    operationNumber: '47313',
    customerName: 'Lena Perez Font',
    address: 'Garzon No.316 esquina 2da',
    weight: 160,
    status: 'pending',
    tripLeg: 'ida',
    archivado: false,
    puntoManual: false,
    estado: EstadoEnPedido.enProceso,
    facturaEstado: EstadoFactura.igual,
    facturaNumero: '47313',
    folio: folio,
    endLat: conPunto ? 20.02 : null,
    endLng: conPunto ? -75.82 : null,
    sucursalCodigo: 'STG',
    createdAt: DateTime(2026, 10, 20),
  );

  Future<void> abrir(WidgetTester tester, Pedido p) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          detallePedidoProvider('p1').overrideWith(
            (ref) async => DetallePedido(pedido: p, renglones: const []),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CajonDetallePedido(pedidoId: 'p1')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'sin punto de entrega, el detalle dice que la ubicación es obligatoria',
    (tester) async {
      await abrir(tester, pedido());

      expect(
        find.byKey(const ValueKey('ficha-falta-la-ubicacion')),
        findsOneWidget,
      );
      expect(find.textContaining('Es obligatoria'), findsOneWidget);
      expect(find.textContaining('«Ubicar la entrega»'), findsWidgets);
      await cerrar(tester);
    },
  );

  testWidgets('con punto de entrega, el detalle no avisa de nada', (
    tester,
  ) async {
    await abrir(tester, pedido(conPunto: true));

    expect(
      find.byKey(const ValueKey('ficha-falta-la-ubicacion')),
      findsNothing,
    );
    await cerrar(tester);
  });

  testWidgets(
    'sin folio, dice que no viene de ningún pedido y que la dirección se pone a mano',
    (tester) async {
      await abrir(tester, pedido());

      final texto = tester
          .widget<Text>(find.byKey(const ValueKey('ficha-pedido-de-origen')))
          .data;
      expect(texto, contains('no viene de ningún pedido'));
      expect(texto, contains('a mano'));
      await cerrar(tester);
    },
  );

  testWidgets('con folio, el detalle enseña el pedido de origen', (
    tester,
  ) async {
    await abrir(tester, pedido(folio: 'PAT26-261018-1549'));

    final texto = tester
        .widget<Text>(find.byKey(const ValueKey('ficha-pedido-de-origen')))
        .data;
    expect(texto, 'PAT26-261018-1549');
    await cerrar(tester);
  });
}
