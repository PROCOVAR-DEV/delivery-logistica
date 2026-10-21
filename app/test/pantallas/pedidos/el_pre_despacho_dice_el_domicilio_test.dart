// EL PRE-DESPACHO DICE CUÁNTAS FACTURAS SON Y QUÉ SE COBRA CON SU DOMICILIO (21/10/2026, Jose: «en el
// pre-despacho no sale el total ni lo que se va a ganar con el domicilio»). El domicilio de cada parada es
// el precio de Entrega si lo hay y, si no, el que cobró la propia factura; una factura con el domicilio en
// $0 suma cero: no se inventa un precio.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/vista_pre_despacho.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  test('suma el domicilio de cada factura: Entrega si hay, si no la factura, y cero si va en \$0', () async {
    await sembrarCatalogo(base);
    await sembrarPedido(
      base,
      id: 'a',
      cliente: 'A',
      pedidoCosto: null,
      facturaDomicilio: 2.5,
    );
    await sembrarPedido(
      base,
      id: 'b',
      cliente: 'B',
      pedidoCosto: null,
      facturaDomicilio: 0,
    );
    await sembrarPedido(
      base,
      id: 'c',
      cliente: 'C',
      pedidoCosto: 4,
      facturaDomicilio: 1,
    );

    final t = await ConsultasPedidos(base)
        .preDespachoDeLoFiltrado(const FiltrosPedidos.sinNada());

    expect(t.pedidos, 3);
    expect(
      t.domicilioUsd,
      closeTo(6.5, 0.0001),
      reason: '2.5 (factura) + 0 (en \$0) + 4 (Entrega)',
    );
  });

  test('sin facturas, el domicilio es cero y no se inventa nada', () async {
    final t = await ConsultasPedidos(base)
        .preDespachoDeLoFiltrado(const FiltrosPedidos.sinNada());
    expect(t.pedidos, 0);
    expect(t.domicilioUsd, 0);
  });

  testWidgets('la vista lo enseña ARRIBA de la tabla, y no sale sin facturas', (
    tester,
  ) async {
    Future<void> pintar(TotalesPreDespacho t) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: VistaPreDespacho(totales: t)),
        ),
      ),
    );

    await pintar(const TotalesPreDespacho([], pedidos: 3, domicilioUsd: 6.5));
    expect(find.text(ResumenDeLasFacturas.rotuloFacturas), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(ResumenDeLasFacturas.rotuloDomicilio), findsOneWidget);
    expect(find.text('\$6.50'), findsOneWidget);

    await pintar(const TotalesPreDespacho([]));
    expect(find.text(ResumenDeLasFacturas.rotuloDomicilio), findsNothing);
  });
}
