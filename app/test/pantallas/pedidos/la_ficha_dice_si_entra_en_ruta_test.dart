// LA FICHA DEL PEDIDO DICE «NO ENTRA A UNA RUTA» SOLO CUANDO NO ENTRA — issue 10
// de Amado, 15/10/2026.
//
// La captura de Amado (Reparto Windows, PBF26-2610131268) decia en la banda de la
// factura «No cuadra con la factura, así que no entra a una ruta» y en la del
// domicilio «Sin calcular todavía … este pedido no tiene precio de domicilio».
// Con la regla nueva ese pedido SI entra: la factura cambio, pero al camion va lo
// facturado, y la cotizacion no se le exige porque el vendedor no marco domicilio.
//
// Van EN PAREJA: el caso real dice que puede ir y no dice «no entra»; el marcado
// sin cotizar y el que no cobro el domicilio dicen «no entra» con su motivo. Y
// la ficha no repite la regla: pregunta a `porQueNoSePuedeColocar` (lo vigila
// que el texto cambie con `requiereDomicilio`, que solo lee la regla compartida).
//
// Los `Pedido` se construyen a mano y no se abre ninguna base: dentro de un
// `testWidgets` una base de Drift se cuelga (CLAUDE.md §5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_detalle_pedido.dart';

void main() {
  Pedido pedido({
    String estado = EstadoFactura.cambiado,
    double? domicilio = 1.31,
    double? costo,
    bool? marcado = false,
    String? rutaId,
    String? itemsOrigen = 'factura',
  }) => Pedido(
    id: 'p1',
    operationNumber: 'PBF26-2610131268',
    customerName: 'Cliente de Santiago',
    address: 'Calle 1',
    weight: 68,
    status: 'pending',
    tripLeg: 'ida',
    archivado: false,
    puntoManual: false,
    endLat: 20.03,
    endLng: -75.82,
    pedidoCosto: costo,
    requiereDomicilio: marcado,
    facturaEstado: estado,
    facturaNumero: '47061',
    facturaDomicilio: domicilio,
    routeId: rutaId,
    itemsOrigen: itemsOrigen,
    sucursalCodigo: 'STG',
    createdAt: DateTime(2026, 10, 15),
  );

  Future<void> abrir(WidgetTester tester, Pedido p) async {
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

  final noEntra = find.textContaining(
    'no entra a una ruta',
    findRichText: true,
  );
  final noEntraMayuscula = find.textContaining('No entra a una ruta');
  final lineaDeRuta = find.byKey(const ValueKey('ficha-ruta'));

  testWidgets(
    'EL CASO REAL: dice que al camión va lo facturado y que puede ir, '
    'y no dice «no entra»',
    (tester) async {
      await abrir(tester, pedido());

      expect(
        find.text(
          'Se facturó algo distinto de lo pedido (factura 47061). Al camión va '
          'lo facturado: los productos de abajo ya son los de la factura.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(lineaDeRuta).data, 'Puede ir a una ruta.');
      expect(noEntra, findsNothing, reason: 'era la frase falsa de la captura');
      expect(noEntraMayuscula, findsNothing);
      // Entrega no cotizó, pero la factura SÍ cobró (1.31): el bloque enseña lo cobrado y de dónde sale,
      // no «sin calcular» (Jose, 21/10/2026).
      expect(find.text('Sin precio puesto'), findsNothing);
      expect(find.text('\$1.31'), findsOneWidget);
      expect(
        find.text(
          'Es el domicilio que cobra la factura. La distancia es del almacén '
          'al cliente.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('hasta entonces'), findsNothing);
      await cerrar(tester);
    },
  );

  // PCC25-261014-1435 (Amado, 16/10/2026): MARCADO y sin cotizar PUEDE ir (antes decía que no).
  testWidgets(
    'MARCADO y sin cotizar: puede ir, y no sugiere que hace falta cotizar',
    (tester) async {
      await abrir(tester, pedido(marcado: true));

      expect(tester.widget<Text>(lineaDeRuta).data, 'Puede ir a una ruta.');
      expect(noEntraMayuscula, findsNothing);
      expect(find.textContaining('hasta entonces'), findsNothing);
      await cerrar(tester);
    },
  );

  // TEMPORAL 16/10/2026 (Jose): sin cobro en la factura también puede ir. La pareja de
  // «no entra» es sólo la factura sin cotejar/sin factura (no se muestra esa línea).
  testWidgets('sin domicilio cobrado en la factura: puede ir', (tester) async {
    await abrir(tester, pedido(domicilio: null));

    expect(tester.widget<Text>(lineaDeRuta).data, 'Puede ir a una ruta.');
    await cerrar(tester);
  });

  testWidgets('igual, marcado y cotizado: puede ir', (tester) async {
    await abrir(
      tester,
      pedido(estado: EstadoFactura.igual, marcado: true, costo: 2),
    );

    expect(tester.widget<Text>(lineaDeRuta).data, 'Puede ir a una ruta.');
    expect(noEntraMayuscula, findsNothing);
    await cerrar(tester);
  });

  // «Los productos de abajo ya son los de la factura» sólo cuando lo son.
  for (final (origen, frase) in const [
    (
      'pedido',
      'Se facturó algo distinto de lo pedido (factura 47061). Al camión va lo '
          'facturado, pero los productos de abajo son los del pedido: la factura '
          'no se pudo atar a este pedido.',
    ),
    (
      null,
      'Se facturó algo distinto de lo pedido (factura 47061). Al camión va lo '
          'facturado.',
    ),
  ]) {
    testWidgets(
      'renglones de origen $origen: no dice que son los de la factura',
      (tester) async {
        await abrir(tester, pedido(itemsOrigen: origen));

        expect(find.text(frase), findsOneWidget);
        expect(find.textContaining('ya son los de la factura'), findsNothing);
        await cerrar(tester);
      },
    );
  }

  testWidgets('ya va en una ruta: la banda no habla de entrar o no', (
    tester,
  ) async {
    await abrir(tester, pedido(rutaId: 'r1'));

    expect(lineaDeRuta, findsNothing);
    await cerrar(tester);
  });
}
