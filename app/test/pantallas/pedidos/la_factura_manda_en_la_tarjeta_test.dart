// LA FACTURA ES EL TÍTULO DE LA TARJETA Y EL CLIENTE VA DEBAJO — issue 12 de Amado, 15/10/2026.
//
// «El usuario me dice que para él, más importante que el nombre del cliente es la factura.
// Entonces mi sugerencia es que la factura tenga el puntaje que tiene el cliente y bajar el
// cliente al puntaje normal, pero dejarlo bold.»
//
// Dos tarjetas de pedido llevan factura y cliente: la del Tablero (sin colocar y dentro de
// las zonas, la misma) y la del teléfono en Pedidos. Las dos pasan por `FacturaYCliente`
// (`pedidos/vista/kit.dart`), y aquí se mira lo que se PINTA en cada una, no el widget
// suelto: si una dejara de usarlo, su grupo se pone rojo.
//
// Se compara el estilo EFECTIVO (el del `RichText`, ya mezclado con el `DefaultTextStyle`)
// contra el tema de la casa, no contra números escritos aquí: la factura con el tamaño y el
// peso que tenía el cliente (`bodyMedium`, w600) y el cliente al tamaño del cuerpo de la
// tarjeta (`bodySmall`) en negrita. En pareja: con número y sin número.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/vista/tabla_pedidos.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/tarjeta.dart';

const _sinNumero = 'Sin número de factura';

RichText _parrafo(WidgetTester tester, Finder texto) => tester.widget<RichText>(
  find.descendant(of: texto, matching: find.byType(RichText)),
);

TextStyle _efectivo(WidgetTester tester, Finder texto) =>
    _parrafo(tester, texto).text.style!;

bool _seCorto(WidgetTester tester, Finder texto) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: texto, matching: find.byType(RichText)),
    )
    .didExceedMaxLines;

/// Lo que tiene que cumplir cualquier tarjeta CON número.
void _laFacturaMandaSobreElCliente(
  WidgetTester tester, {
  required Finder factura,
  required Finder cliente,
}) {
  expect(factura, findsOneWidget);
  expect(cliente, findsOneWidget);
  final tema = Theme.of(tester.element(factura));
  final f = _efectivo(tester, factura);
  final c = _efectivo(tester, cliente);

  expect(
    f.fontSize,
    tema.textTheme.bodyMedium!.fontSize,
    reason: 'la factura lleva el tamaño que tenía el cliente (bodyMedium)',
  );
  expect(f.fontWeight, FontWeight.w600, reason: 'y su peso de título (w600)');
  expect(
    c.fontSize,
    tema.textTheme.bodySmall!.fontSize,
    reason: 'el cliente baja al tamaño del cuerpo de la tarjeta (bodySmall)',
  );
  expect(c.fontWeight, FontWeight.w700, reason: 'el cliente sigue en negrita');
  expect(
    f.fontSize!,
    greaterThan(c.fontSize!),
    reason: 'la factura se lee antes que el cliente',
  );
  expect(
    tester.getTopLeft(factura).dy,
    lessThan(tester.getTopLeft(cliente).dy),
    reason: 'la factura va encima del cliente',
  );
}

/// Lo que tiene que cumplir cualquier tarjeta SIN número.
void _sinNumeroDiceQueFalta(
  WidgetTester tester, {
  required Finder clave,
  required Finder cliente,
}) {
  final hueco = find.text(_sinNumero);
  expect(hueco, findsOneWidget, reason: 'el título no se queda vacío');
  expect(clave, findsNothing, reason: 'no hay número que llevar la llave');
  expect(find.text('—'), findsNothing, reason: 'nada de una raya grande');
  final tema = Theme.of(tester.element(hueco));
  final h = _efectivo(tester, hueco);
  expect(
    h.fontSize,
    tema.textTheme.bodyMedium!.fontSize,
    reason: 'ocupa el sitio del título, al mismo tamaño',
  );
  expect(
    h.fontWeight,
    tema.textTheme.bodyMedium!.fontWeight,
    reason: 'sin la negrita de un número de verdad',
  );
  expect(
    h.color,
    tema.colorScheme.onSurfaceVariant,
    reason: 'con el color de un dato que falta',
  );
  final c = _efectivo(tester, cliente);
  expect(c.fontSize, tema.textTheme.bodySmall!.fontSize);
  expect(c.fontWeight, FontWeight.w700);
}

void main() {
  // ---------------------------------------------------------------------------
  // EL TABLERO
  // ---------------------------------------------------------------------------
  group('la tarjeta del tablero', () {
    TarjetaPedido pedido({String? facturaNumero = '47061'}) => TarjetaPedido(
      pedidoId: 'p-1',
      customerName: 'Bodega La Esquina',
      address: 'Calle 4 esquina a 7, Reparto Sueño, Santiago de Cuba',
      weight: 128.5,
      kmAlAlmacen: 3.2,
      mismoCliente: 0,
      operationNumber: 'PTB25-261005-1479',
      facturaEstado: 'igual',
      facturaNumero: facturaNumero,
    );

    // A 390 px el tablero es de una mitad (sin arrastre); a 1440 son dos y la tarjeta
    // va arrastrable en su columna de 280 px.
    Future<void> pintar(
      WidgetTester tester, {
      required double pantalla,
      required TarjetaPedido tarjeta,
    }) async {
      tester.view.physicalSize = Size(pantalla, 800);
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
                  width: pantalla >= 900 ? 280 : pantalla,
                  child: TarjetaDePedido(pedido: tarjeta),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final factura = find.byKey(const ValueKey('tarjeta-factura'));
    final cliente = find.text('Bodega La Esquina');

    for (final pantalla in const [390.0, 1440.0]) {
      testWidgets('a $pantalla px la factura es el título y el cliente va '
          'debajo, en negrita y al tamaño del cuerpo', (tester) async {
        await pintar(tester, pantalla: pantalla, tarjeta: pedido());

        expect(tester.widget<Text>(factura).data, 'Factura 47061');
        _laFacturaMandaSobreElCliente(
          tester,
          factura: factura,
          cliente: cliente,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('a $pantalla px, sin número, el título dice que falta', (
        tester,
      ) async {
        await pintar(
          tester,
          pantalla: pantalla,
          tarjeta: pedido(facturaNumero: null),
        );

        _sinNumeroDiceQueFalta(tester, clave: factura, cliente: cliente);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a 390 px dos facturas caben enteras', (tester) async {
      await pintar(
        tester,
        pantalla: 390,
        tarjeta: pedido(facturaNumero: '47061, 47062'),
      );

      expect(tester.widget<Text>(factura).data, 'Factura 47061, 47062');
      expect(_seCorto(tester, factura), isFalse, reason: 'cabe sin elipsis');
      expect(tester.takeException(), isNull);
    });

    testWidgets('en la columna de 280 px muchas facturas saltan de línea y se '
        'cortan sin salirse', (tester) async {
      await pintar(
        tester,
        pantalla: 1440,
        tarjeta: pedido(
          facturaNumero:
              '1024237, 1024240, 1024251, 1024299, 1024300, 1024301, 1024302',
        ),
      );

      expect(
        tester.getRect(factura).right,
        lessThanOrEqualTo(tester.getRect(find.byType(TarjetaDePedido)).right),
      );
      expect(_parrafo(tester, factura).maxLines, 2);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // PEDIDOS, LA TARJETA DEL TELÉFONO (< 768 px)
  // ---------------------------------------------------------------------------
  group('la tarjeta del teléfono en Pedidos', () {
    Pedido pedido({String? numero = '47061'}) => Pedido(
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

    final factura = find.byKey(const ValueKey('tarjeta-factura-p1'));
    final cliente = find.text('Ferretería La Esquina');

    for (final ancho in const [390.0, 767.0]) {
      testWidgets('a $ancho px la factura es el título y el cliente va debajo, '
          'en negrita y al tamaño del cuerpo', (tester) async {
        await pintar(tester, ancho: ancho, p: pedido());

        expect(tester.widget<Text>(factura).data, 'Factura 47061');
        _laFacturaMandaSobreElCliente(
          tester,
          factura: factura,
          cliente: cliente,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('a $ancho px, sin número, el título dice que falta', (
        tester,
      ) async {
        await pintar(tester, ancho: ancho, p: pedido(numero: null));

        _sinNumeroDiceQueFalta(tester, clave: factura, cliente: cliente);
        expect(find.text('sin facturar'), findsOneWidget, reason: 'el estado');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a 390 px dos facturas caben enteras', (tester) async {
      await pintar(tester, ancho: 390, p: pedido(numero: '47061, 47062'));

      expect(tester.widget<Text>(factura).data, 'Factura 47061, 47062');
      expect(_seCorto(tester, factura), isFalse, reason: 'cabe sin elipsis');
      expect(tester.takeException(), isNull);
    });
  });
}
