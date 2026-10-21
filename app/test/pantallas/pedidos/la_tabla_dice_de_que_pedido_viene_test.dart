// LA TABLA ES DE FACTURAS: LA FACTURA VA PRIMERA Y LA COLUMNA «PEDIDO» DICE DE CUÁL VIENE.
//
// Jose, 21/10/2026: «ya no son pedidos, son facturas, y detallar si esa factura viene de un
// pedido». La fila es la factura de Ventra; el pedido de PEDIDO es un extra enlazado por
// folio (`orders.folio`, 00025). Con folio, la celda lo enseña (y su estado debajo); sin él,
// un guion: esa factura no viene de ningún pedido.
//
// Van EN PAREJA: con folio sale, sin folio no sale. Los literales están escritos a propósito.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/vista/tabla_pedidos.dart';

void main() {
  Pedido pedido({required String id, String? folio, bool conPunto = false}) =>
      Pedido(
        id: id,
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
        orderDate: DateTime(2026, 10, 20),
        createdAt: DateTime(2026, 10, 20),
      );

  Future<void> pintar(WidgetTester tester, List<Pedido> pedidos) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TablaPedidos(
              pedidos: pedidos,
              renglones: const {},
              rutas: const {},
              seleccion: const {},
              conSucursal: false,
              ahora: DateTime(2026, 10, 20, 10),
              alMarcar: (_) {},
              alMarcarPagina: (ids, marcar) {},
              alAbrir: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'la factura es la primera columna y la fecha es la de la factura',
    (tester) async {
      await pintar(tester, [pedido(id: 'p1')]);

      final factura = tester.getTopLeft(find.text('Factura')).dx;
      for (final otra in const ['Fecha factura', 'Pedido', 'Cliente', 'Peso']) {
        expect(
          factura,
          lessThan(tester.getTopLeft(find.text(otra)).dx),
          reason: '«Factura» tiene que ir antes que «$otra»',
        );
      }
      expect(find.text('Fecha pedido'), findsNothing);
    },
  );

  testWidgets('con folio, la celda Pedido lo enseña con su estado', (
    tester,
  ) async {
    await pintar(tester, [pedido(id: 'p1', folio: 'PSS26-261020-0731')]);

    expect(find.byKey(const ValueKey('fila-pedido-p1')), findsOneWidget);
    expect(find.text('PSS26-261020-0731'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
  });

  testWidgets('sin folio no hay pedido: un guion y ningún estado', (
    tester,
  ) async {
    await pintar(tester, [pedido(id: 'p1')]);

    expect(find.byKey(const ValueKey('fila-pedido-p1')), findsNothing);
    expect(find.text('En proceso'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  // UNA FACTURA SIN PEDIDO NO TRAE EL PUNTO DEL CLIENTE: el logístico tiene que saber que la
  // dirección se la pone él. En pareja: sin punto sale el aviso, con punto no sale.
  testWidgets('sin punto de entrega, la fila avisa de que hay que ubicarla', (
    tester,
  ) async {
    await pintar(tester, [pedido(id: 'p1')]);

    expect(find.byKey(const ValueKey('fila-sin-ubicacion-p1')), findsOneWidget);
    expect(
      find.text('Sin ubicación: ponle la dirección en «Ubicar la entrega»'),
      findsOneWidget,
    );
  });

  testWidgets('con punto de entrega, la fila no avisa de nada', (tester) async {
    await pintar(tester, [pedido(id: 'p1', conPunto: true)]);

    expect(find.byKey(const ValueKey('fila-sin-ubicacion-p1')), findsNothing);
  });
}
