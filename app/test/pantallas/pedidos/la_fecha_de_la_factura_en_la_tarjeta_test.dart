import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/vista/tabla_pedidos.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/tarjeta.dart';


// LA FECHA DE LA FACTURA, DESPUÉS DEL NÚMERO, EN LA TARJETA — issue 16 de Amado, 16/10/2026.
//
// «En el card del pedido (factura) pon después del número de factura la fecha de facturación,
// para que les ayude a identificarlos rápido; ahora hay que entrar al detalle.» Se pinta en la
// tarjeta del Tablero, en la del teléfono de Pedidos y en la tabla de escritorio. El día es el
// de CUBA: una factura de las 23:30 allí es del día en que se emitió aunque en UTC ya sea el
// siguiente. Sin número (o sin fecha) no se pone nada. A 390 px no desborda ni con varias
// facturas.

final _facturadaEl = DateTime.utc(2026, 10, 16, 3, 30); // 23:30 del 15 en Cuba
const _fechaClave = ValueKey('tarjeta-factura-fecha');

void main() {
  group('la tarjeta del tablero', () {
    TarjetaPedido pedido({String? numero = '47061', DateTime? en}) => TarjetaPedido(
      pedidoId: 'p-1',
      customerName: 'Bodega La Esquina',
      address: 'Calle 4 esquina a 7, Reparto Sueño, Santiago de Cuba',
      weight: 128.5,
      kmAlAlmacen: 3.2,
      mismoCliente: 0,
      operationNumber: 'PTB25-261005-1479',
      facturaEstado: 'igual',
      facturaNumero: numero,
      facturaAt: en,
    );

    Future<void> pintar(WidgetTester tester, double ancho, TarjetaPedido t) async {
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasaDeLaMiradaProvider.overrideWithValue(
              const TasaDeLaMirada.no('en estas pruebas no hay tasa'),
            ),
          ],
          child: MaterialApp(
            theme: temaDeReparto(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: ancho >= 900 ? 280 : ancho,
                  child: TarjetaDePedido(pedido: t),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final ancho in const [390.0, 1440.0]) {
      testWidgets('a $ancho px la fecha va después del número, en el día de Cuba', (tester) async {
        await pintar(tester, ancho, pedido(en: _facturadaEl));
        expect(find.text('Factura 47061'), findsOneWidget);
        expect(find.text('· 15/10/2026'), findsOneWidget, reason: 'no el 16 de UTC');
        expect(
          tester.getTopLeft(find.byKey(_fechaClave)).dx,
          greaterThan(tester.getTopLeft(find.text('Factura 47061')).dx),
          reason: 'después del número',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('a $ancho px, sin fecha de factura, no se pone nada', (tester) async {
        await pintar(tester, ancho, pedido());
        expect(find.byKey(_fechaClave), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a $ancho px, sin número, no se pone la fecha', (tester) async {
        await pintar(tester, ancho, pedido(numero: null, en: _facturadaEl));
        expect(find.text('Sin número de factura'), findsOneWidget);
        expect(find.byKey(_fechaClave), findsNothing);
      });
    }

    testWidgets('muchas facturas y la fecha no desbordan a 390 px ni en la columna de 280', (tester) async {
      for (final ancho in const [390.0, 1440.0]) {
        await pintar(
          tester,
          ancho,
          pedido(
            numero: '1024237, 1024240, 1024251, 1024299, 1024300, 1024301, 1024302',
            en: _facturadaEl,
          ),
        );
        expect(find.byKey(_fechaClave), findsOneWidget);
        expect(
          tester.getRect(find.byKey(_fechaClave)).right,
          lessThanOrEqualTo(tester.getRect(find.byType(TarjetaDePedido)).right),
        );
        expect(tester.takeException(), isNull, reason: 'a $ancho px');
      }
    });
  });

  group('Pedidos', () {
    Pedido pedido({String? numero = '47061', DateTime? en}) => Pedido(
      id: 'p1',
      operationNumber: 'X-2992',
      customerName: 'Ferretería La Esquina',
      address: 'calle 101 entre Calzada de Güines y Reparto Eléctrico',
      weight: 128.5,
      status: 'pending',
      tripLeg: 'ida',
      archivado: false,
      puntoManual: false,
      estado: EstadoEnPedido.completada,
      pedidoCosto: 3.5,
      facturaEstado: numero == null ? EstadoFactura.sinFactura : 'igual',
      facturaNumero: numero,
      facturaAt: en,
      facturaDomicilio: 0.46,
      sucursalCodigo: 'CAM',
      orderDate: DateTime(2026, 10, 8),
      createdAt: DateTime(2026, 10, 8),
    );

    Future<void> pintar(WidgetTester tester, double ancho, Pedido p) async {
      tester.view.physicalSize = Size(ancho, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaDeReparto(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TablaPedidos(
                pedidos: [p],
                renglones: const {},
                rutas: const {},
                seleccion: const {},
                conSucursal: false,
                ahora: DateTime(2026, 10, 8, 10),
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

    for (final ancho in const [390.0, 767.0]) {
      testWidgets('teléfono a $ancho px: número y fecha, y sin fecha nada', (tester) async {
        await pintar(tester, ancho, pedido(en: _facturadaEl));
        expect(find.text('Factura 47061'), findsOneWidget);
        expect(find.text('· 15/10/2026'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await pintar(tester, ancho, pedido());
        expect(find.byKey(_fechaClave), findsNothing);
        await pintar(tester, ancho, pedido(numero: null, en: _facturadaEl));
        expect(find.byKey(_fechaClave), findsNothing);
      });
    }

    testWidgets('teléfono a 390 px: varias facturas y la fecha no desbordan', (tester) async {
      await pintar(
        tester,
        390,
        pedido(numero: '1024237, 1024240, 1024251, 1024299, 1024300', en: _facturadaEl),
      );
      expect(find.byKey(_fechaClave), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (ancho, clave) in const [
      (1440.0, 'fila-fecha-factura-p1'),
      (900.0, 'fila-factura-p1'),
    ]) {
      testWidgets('tabla a $ancho px: la fecha de la factura junto al número', (tester) async {
        await pintar(tester, ancho, pedido(en: _facturadaEl));
        final texto = find.byKey(ValueKey(clave));
        expect(texto, findsOneWidget);
        expect(tester.widget<Text>(texto).data, contains('15/10/2026'));
        expect(tester.takeException(), isNull);

        await pintar(tester, ancho, pedido());
        expect(find.textContaining('15/10/2026'), findsNothing);
      });
    }
  });
}
