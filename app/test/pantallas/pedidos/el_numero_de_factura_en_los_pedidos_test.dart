// EL NÚMERO DE FACTURA EN LAS TARJETAS DE PEDIDOS, Y LA FICHA CON EMPAQUES — 14/10/2026.
//
// Amado, issue 8: «en las pantallas de los pedidos los logísticos operan con número de
// factura, debe ser una información importante a mostrar en los CARDS de pedidos». Y
// issue 6, punto 1: el detalle debe llevar «la fecha de facturación y el número de
// factura», con las cantidades «en blíster, que es como cargan y transportan».
//
// ## Qué número es
//
// `facturaNumero` (el de Ventra), no el folio (`X-2992`, el «conduce»). Aquí se siembran
// distintos a propósito: con el mismo valor en los dos, pintar uno por otro saldría en
// verde. El porqué, en `numeroDeFactura` (`pedidos/datos/formato.dart`).
//
// ## Tres sitios, tres formas
//
//  · Teléfono (< 768 px): una tarjeta por pedido. El número sube a la cabecera con su
//    rótulo «Factura» y la insignia de abajo se queda SÓLO con el estado (`Cuadra`,
//    `Cambió !`), para no escribirlo dos veces en 390 px.
//  · Tabla (≥ 1024 px): la columna «Factura» de siempre, con el número en su insignia.
//    Aquí NO se repite.
//  · Tabla estrecha (768–1023 px): la columna se esconde, y con ella desaparecía el
//    número. Baja a la celda del cliente, bajo el folio.
//
// Los `Pedido` se construyen a mano y no se abre ninguna base: dentro de un `testWidgets`
// una consulta de Drift cuelga la prueba en vez de fallar (CLAUDE.md §5). Y van EN PAREJA:
// sale cuando toca / no sale cuando no. Los literales están escritos a mano, sin
// importarlos del código.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/numero_de_factura.dart';
import 'package:reparto/pantallas/pedidos/datos/formato.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_detalle_pedido.dart';
import 'package:reparto/pantallas/pedidos/vista/tabla_pedidos.dart';

void main() {
  Pedido pedido({
    String? estadoFactura = EstadoFactura.igual,
    String? numero = 'F-1001',
    DateTime? facturaAt,
  }) => Pedido(
    id: 'p1',
    operationNumber: 'X-2992',
    customerName: 'Ferretería La Esquina',
    address: 'calle 101 entre Calzada de Güines y Reparto Eléctrico',
    weight: 128.5,
    status: 'pending',
    tripLeg: 'ida',
    archivado: false,
    estado: EstadoEnPedido.completada,
    pedidoCosto: 3.5,
    facturaEstado: estadoFactura,
    facturaNumero: numero,
    facturaAt: facturaAt,
    facturaDomicilio: 0.46,
    sucursalCodigo: 'CAM',
    orderDate: DateTime(2026, 10, 8),
    createdAt: DateTime(2026, 10, 8),
  );

  Future<void> pintar(
    WidgetTester tester, {
    required double ancho,
    required Pedido p,
  }) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
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

  final enTarjeta = find.byKey(const ValueKey('tarjeta-factura-p1'));
  final enFila = find.byKey(const ValueKey('fila-factura-p1'));

  group('la tarjeta del teléfono (390 px)', () {
    testWidgets('lleva «Factura F-1001» en la cabecera y la insignia no lo '
        'repite', (tester) async {
      await pintar(tester, ancho: 390, p: pedido());

      expect(enTarjeta, findsOneWidget);
      expect(tester.widget<Text>(enTarjeta).data, 'Factura F-1001');
      // La insignia dice el ESTADO; el número ya está arriba.
      expect(find.text('Cuadra'), findsOneWidget);
      expect(
        find.text('F-1001'),
        findsNothing,
        reason: 'el número está dos veces en una tarjeta de 390 px',
      );
      // El folio es OTRO número y sigue donde estaba.
      expect(find.text('X-2992'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la factura cambiada, la insignia dice «Cambió !»', (
      tester,
    ) async {
      await pintar(
        tester,
        ancho: 390,
        p: pedido(estadoFactura: EstadoFactura.cambiado),
      );

      expect(tester.widget<Text>(enTarjeta).data, 'Factura F-1001');
      expect(find.text('Cambió !'), findsOneWidget);
      expect(find.text('Cuadra'), findsNothing);
    });

    for (final (nombre, estado) in const [
      ('sin facturar', EstadoFactura.sinFactura),
      ('sin cotejar', null),
    ]) {
      testWidgets('un pedido $nombre y sin número no enseña «Factura»', (
        tester,
      ) async {
        await pintar(
          tester,
          ancho: 390,
          p: pedido(estadoFactura: estado, numero: null),
        );

        expect(enTarjeta, findsNothing);
        expect(find.textContaining('Factura'), findsNothing);
        expect(
          find.text(nombre),
          findsOneWidget,
          reason: 'la insignia de siempre',
        );
      });
    }

    testWidgets('dos facturas juntas caben o saltan de línea, no desbordan', (
      tester,
    ) async {
      await pintar(
        tester,
        ancho: 390,
        p: pedido(numero: '1024237, 1024240, 1024251, 1024299'),
      );

      expect(enTarjeta, findsOneWidget);
      final tarjeta = tester.getRect(find.byKey(const ValueKey('tarjeta-p1')));
      expect(tester.getRect(enTarjeta).right, lessThanOrEqualTo(tarjeta.right));
      expect(tester.takeException(), isNull);
    });
  });

  group('la tabla ancha (1440 px)', () {
    testWidgets('el número sigue en la columna «Factura» y no se escribe '
        'otra vez', (tester) async {
      await pintar(tester, ancho: 1440, p: pedido());

      expect(
        find.text('F-1001'),
        findsOneWidget,
        reason: 'la insignia de la columna',
      );
      expect(enFila, findsNothing);
      expect(enTarjeta, findsNothing);
      expect(find.text('Factura F-1001'), findsNothing);
      expect(
        find.text('Factura'),
        findsOneWidget,
        reason: 'el título de la columna',
      );
    });
  });

  group('la tabla estrecha (768–1023 px), donde la columna se esconde', () {
    for (final ancho in const [768.0, 900.0, 1023.0]) {
      testWidgets('a $ancho px el número baja a la celda del cliente', (
        tester,
      ) async {
        await pintar(tester, ancho: ancho, p: pedido());

        expect(enFila, findsOneWidget);
        expect(tester.widget<Text>(enFila).data, 'Factura F-1001');
        // Sin columna «Factura», ni título ni insignia con el número.
        expect(find.text('Factura'), findsNothing);
        expect(find.text('F-1001'), findsNothing);
        final fila = tester.getRect(enFila);
        expect(fila.left, greaterThanOrEqualTo(0));
        expect(fila.right, lessThanOrEqualTo(ancho));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sin número no baja nada', (tester) async {
      await pintar(
        tester,
        ancho: 900,
        p: pedido(estadoFactura: EstadoFactura.sinFactura, numero: null),
      );
      expect(enFila, findsNothing);
    });

    testWidgets(
      'a 1024 px ya hay columna y la celda del cliente no lo repite',
      (tester) async {
        await pintar(tester, ancho: 1024, p: pedido());
        expect(enFila, findsNothing);
        expect(find.text('F-1001'), findsOneWidget);
      },
    );
  });

  group('la ficha del pedido', () {
    Future<void> abrir(
      WidgetTester tester,
      Pedido p,
      List<RenglonConPeso> r,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            detallePedidoProvider('p1').overrideWith(
              (ref) async => DetallePedido(pedido: p, renglones: r),
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

    RenglonConPeso linea({
      double cantidad = 120,
      double? empaques = 20,
      double? kg = 12.5,
    }) => RenglonConPeso(
      RenglonPedido(
        id: 'i1',
        orderId: 'p1',
        linea: 1,
        description: 'MALTA GUAJIRA 330 ML BLISTER 6U',
        quantity: cantidad,
        packs: empaques,
        pesoLineaKg: kg,
      ),
    );

    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('dice la factura y cuándo se facturó, en grande', (
      tester,
    ) async {
      await abrir(tester, pedido(facturaAt: DateTime(2026, 10, 12, 9, 30)), [
        linea(),
      ]);

      final cabecera = find.byKey(const ValueKey('ficha-factura'));
      expect(cabecera, findsOneWidget);
      expect(
        tester.widget<Text>(cabecera).data,
        'Factura F-1001 · facturada el 12/10/2026',
      );
      await cerrar(tester);
    });

    testWidgets('sin número no hay cabecera de factura, aunque haya fecha del '
        'cotejo', (tester) async {
      await abrir(
        tester,
        pedido(
          estadoFactura: EstadoFactura.sinFactura,
          numero: null,
          facturaAt: DateTime(2026, 10, 12, 9, 30),
        ),
        [linea()],
      );

      expect(find.byKey(const ValueKey('ficha-factura')), findsNothing);
      expect(find.textContaining('facturada el'), findsNothing);
      await cerrar(tester);
    });

    testWidgets('las cantidades van en empaques primero, luego las unidades y '
        'luego el peso', (tester) async {
      await abrir(tester, pedido(), [linea()]);

      expect(
        find.text(
          'MALTA GUAJIRA 330 ML BLISTER 6U · 20 empaques · 120 unidades · 12.5 kg',
        ),
        findsOneWidget,
      );
      await cerrar(tester);
    });

    testWidgets(
      'si `quantity` no llega a los empaques no se enseñan unidades',
      (tester) async {
        await abrir(tester, pedido(), [linea(cantidad: 4, empaques: 7)]);

        expect(
          find.text('MALTA GUAJIRA 330 ML BLISTER 6U · 7 empaques · 12.5 kg'),
          findsOneWidget,
        );
        expect(find.textContaining('unidades'), findsNothing);
        await cerrar(tester);
      },
    );
  });

  group('las funciones que lo deciden', () {
    test(
      'NumeroDeFactura.de: vacío es nulo y la comilla de Excel se quita',
      () {
        expect(NumeroDeFactura.de(null), isNull);
        expect(NumeroDeFactura.de(''), isNull);
        expect(NumeroDeFactura.de('   '), isNull);
        expect(NumeroDeFactura.de('1024237'), '1024237');
        expect(NumeroDeFactura.de(' 1024237 '), '1024237');
        expect(NumeroDeFactura.de("'1024237"), '1024237');
        // Dos facturas juntas, como las escribe el cotejo de PEDIDO.
        expect(NumeroDeFactura.de('1024237, 1024240'), '1024237, 1024240');
      },
    );

    test('etiquetaDeFactura: la fecha sólo sale CON número', () {
      final cuando = DateTime(2026, 10, 12, 9, 30);
      expect(etiquetaDeFactura('1024237'), 'Factura 1024237');
      expect(
        etiquetaDeFactura('1024237', facturadaEl: cuando),
        'Factura 1024237 · facturada el 12/10/2026',
      );
      expect(etiquetaDeFactura(null, facturadaEl: cuando), isNull);
      expect(etiquetaDeFactura('  ', facturadaEl: cuando), isNull);
    });

    RenglonConPeso r(double cantidad, double? empaques) => RenglonConPeso(
      RenglonPedido(
        id: 'i',
        orderId: 'p',
        linea: 1,
        description: 'x',
        quantity: cantidad,
        packs: empaques,
      ),
    );

    test('cantidadEnTexto: empaques primero; unidades sólo si son de fiar', () {
      expect(r(120, 20).cantidadEnTexto(), '20 empaques · 120 unidades');
      expect(r(120, 20).cantidadEnTexto(corto: true), '20 empaques · 120 uds');
      expect(r(6, 1).cantidadEnTexto(), '1 empaque · 6 unidades');
      expect(r(1, 1).cantidadEnTexto(), '1 empaque · 1 unidad');
      expect(r(1, 1).cantidadEnTexto(corto: true), '1 empaque · 1 ud');
      // Los 437 renglones donde `quantity` queda por debajo de los empaques.
      expect(r(4, 7).cantidadEnTexto(), '7 empaques');
      // Sin empaques, o con cero: `quantity` es lo que se cuenta y no hay segunda cifra.
      expect(r(5, null).cantidadEnTexto(), '5 empaques');
      expect(r(5, 0).cantidadEnTexto(), '5 empaques');
      expect(r(2.5, null).cantidadEnTexto(), '2.50 empaques');
    });
  });
}
