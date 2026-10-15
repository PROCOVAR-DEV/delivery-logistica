/// LA TABLA «POR PRODUCTO Y FACTURA» — issue 8 de Amado.
///
/// «Se sacaron 20 blister, 10 de una factura y 10 de otra: en la tarjeta no se
/// pone 20, se ponen 10 y 10 poniendo la factura que provocó la salida de
/// inventario.» La tarjeta de estiba es POR PRODUCTO, y el caso de estas pruebas
/// es LA HOJA QUE AMADO ESCRIBIÓ A MANO en el issue:
///
/// ```
/// Fact    Prod.      Cant   Kg
/// 46226   Cerv 500     5    15
/// 46228   Cerv 500    10    30
/// 46229   Cerv 500     5    15
///                     20    60
/// 46226   Cerv 330    10    20
///                     10    20
/// 46226   Cerv 1,5    10    90
///                     10    90
/// 46230   Arroz R.     2    20
///                      2    20
/// ```
///
/// Dos mitades, como en `los_dos_pesos_del_pre_despacho_test.dart`:
///
///  * los TEXTOS (`filasPorProductoYFactura`), que son lo que leen la pantalla y
///    el PDF — se prueban sin dibujar nada, con números sacados a mano;
///  * el PAPEL: se descomprime el PDF y se lee lo que de verdad dice. Una prueba
///    que sólo llamara a `filasPorProductoYFactura` no vería que la hoja se olvida
///    de imprimir la tabla, que es el fallo que importa.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/hoja.dart';
import 'package:reparto/impresion/por_producto_y_factura.dart';
import 'package:reparto/impresion/pre_despacho.dart';

import 'los_dos_pesos_del_pre_despacho_test.dart' show leerElPapel;

final DateTime _impresoEn = DateTime(2026, 10, 15, 9, 0, 0);

LineaPreDespacho _l(String producto, num cant, num? kg, {int sinPeso = 0}) =>
    LineaPreDespacho(
      producto: producto,
      formatos: cant,
      // Las unidades no salen en esta tabla; van distintas de la cantidad a
      // propósito, para que una columna de unidades no pase por la de empaques.
      unidades: cant * 24,
      pesoKg: kg,
      lineasSinPeso: sinPeso,
    );

/// Las cuatro facturas de Amado, ya por número (así llegan de la ruta).
final _facturasDeAmado = <FacturaDelPreDespacho>[
  FacturaDelPreDespacho(
    numero: '46226',
    lineas: [
      _l('Cerv 500', 5, 15),
      _l('Cerv 330', 10, 20),
      _l('Cerv 1,5', 10, 90),
    ],
  ),
  FacturaDelPreDespacho(numero: '46228', lineas: [_l('Cerv 500', 10, 30)]),
  FacturaDelPreDespacho(numero: '46229', lineas: [_l('Cerv 500', 5, 15)]),
  FacturaDelPreDespacho(numero: '46230', lineas: [_l('Arroz R.', 2, 20)]),
];

/// La tabla de arriba (producto a producto), en el orden de la hoja de Amado.
final _productosDeAmado = <LineaPreDespacho>[
  _l('Cerv 500', 20, 60),
  _l('Cerv 330', 10, 20),
  _l('Cerv 1,5', 10, 90),
  _l('Arroz R.', 2, 20),
];

/// La hoja de Amado, celda a celda.
const _laHojaDeAmado = <List<String>>[
  ['46226', 'Cerv 500', '5', '15.0'],
  ['46228', 'Cerv 500', '10', '30.0'],
  ['46229', 'Cerv 500', '5', '15.0'],
  ['Subtotal', '', '20', '60.0'],
  ['46226', 'Cerv 330', '10', '20.0'],
  ['Subtotal', '', '10', '20.0'],
  ['46226', 'Cerv 1,5', '10', '90.0'],
  ['Subtotal', '', '10', '90.0'],
  ['46230', 'Arroz R.', '2', '20.0'],
  ['Subtotal', '', '2', '20.0'],
];

HojaPreDespacho _hoja(List<FacturaDelPreDespacho> facturas) => HojaPreDespacho(
  sucursal: 'Camagüey',
  vehiculo: 'Camión #1',
  pedidos: 4,
  pesoKg: 190,
  lineas: _productosDeAmado,
  facturas: facturas,
);

void main() {
  // Las fuentes de la hoja se leen del paquete de assets: hace falta el binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('los textos', () {
    test('LA HOJA DE AMADO: un bloque por producto, una fila por factura y el '
        'subtotal del producto', () {
      final filas = filasPorProductoYFactura(
        _productosDeAmado,
        _facturasDeAmado,
      );
      expect([for (final f in filas) f.celdas], _laHojaDeAmado);
      expect(
        [for (final f in filas) f.subtotal],
        [false, false, false, true, false, true, false, true, false, true],
      );
    });

    test('las columnas son las de Amado —factura, producto, cantidad, kg— SIN '
        'unidades, y se cambian en un solo sitio', () {
      expect(
        [for (final c in columnasPorProductoYFactura) c.titulo],
        ['Factura', 'Producto', 'Cant.', 'Kg'],
      );
      for (final fila in filasPorProductoYFactura(
        _productosDeAmado,
        _facturasDeAmado,
      )) {
        expect(fila.celdas, hasLength(columnasPorProductoYFactura.length));
        // 5 blister son 120 unidades: si sale un 120 es que volvió la columna.
        expect(fila.celdas, isNot(contains('120')));
      }
      // Una sola columna de la factura y una sola del producto: las dos de las
      // que depende la tarjeta del teléfono.
      expect(
        columnasPorProductoYFactura.where((c) => c.esLaFactura),
        hasLength(1),
      );
      expect(
        columnasPorProductoYFactura.where((c) => c.esElProducto),
        hasLength(1),
      );
    });

    test('LOS BLOQUES VAN EN EL ORDEN DE LA TABLA DE ARRIBA, no en el de las '
        'facturas ni por nombre', () {
      // La tabla de arriba al revés: los bloques la siguen.
      final filas = filasPorProductoYFactura(
        _productosDeAmado.reversed.toList(),
        _facturasDeAmado,
      );
      expect(
        [for (final f in filas.where((f) => !f.subtotal)) f.celdas[1]],
        [
          'Arroz R.',
          'Cerv 1,5',
          'Cerv 330',
          'Cerv 500',
          'Cerv 500',
          'Cerv 500',
        ],
      );
      // Y dentro del bloque, las facturas en el orden en que llegan (por número).
      expect(
        [
          for (final f in filas.where((f) => f.celdas[1] == 'Cerv 500'))
            f.celdas[0],
        ],
        ['46226', '46228', '46229'],
      );
    });

    test(
      'un producto que la tabla de arriba no trae NO se pierde: va detrás',
      () {
        final filas = filasPorProductoYFactura(
          _productosDeAmado.take(1).toList(),
          _facturasDeAmado,
        );
        expect(
          {for (final f in filas.where((f) => !f.subtotal)) f.celdas[1]},
          {'Cerv 500', 'Cerv 330', 'Cerv 1,5', 'Arroz R.'},
        );
        expect(filas.first.celdas[1], 'Cerv 500');
      },
    );

    test('LA SUMA DE LOS SUBTOTALES ES LA TABLA DE ARRIBA (cantidad y kg)', () {
      final subtotales = filasPorProductoYFactura(
        _productosDeAmado,
        _facturasDeAmado,
      ).where((f) => f.subtotal).toList();
      expect(subtotales, hasLength(_productosDeAmado.length));
      for (final (i, p) in _productosDeAmado.indexed) {
        expect(subtotales[i].celdas[2], '${p.formatos}', reason: p.producto);
        expect(
          subtotales[i].celdas[3],
          p.pesoKg!.toStringAsFixed(1),
          reason: p.producto,
        );
      }
      // 20+10+10+2 = 42 blister y 60+20+90+20 = 190 kg, los de la hoja.
      expect(subtotales.fold<num>(0, (t, f) => t + num.parse(f.celdas[2])), 42);
      expect(
        subtotales.fold<num>(0, (t, f) => t + num.parse(f.celdas[3])),
        190,
      );
    });

    test('un peso que no se sabe es «—», NUNCA 0, y el subtotal que lo suma es '
        'un mínimo «≥»', () {
      final filas = filasPorProductoYFactura(
        [_l('Cerv 500', 15, 30, sinPeso: 1)],
        [
          FacturaDelPreDespacho(
            numero: '46226',
            lineas: [_l('Cerv 500', 5, 0)],
          ),
          FacturaDelPreDespacho(
            numero: '46228',
            lineas: [_l('Cerv 500', 10, 30)],
          ),
        ],
      );
      expect(
        [for (final f in filas) f.celdas],
        [
          ['46226', 'Cerv 500', '5', '—'],
          ['46228', 'Cerv 500', '10', '30.0'],
          ['Subtotal', '', '15', '≥ 30.0'],
        ],
      );
    });

    test(
      'en pareja: la factura con número sale con su número, y la que no tiene '
      'sale «Sin número» AL FINAL de su producto',
      () {
        final filas = filasPorProductoYFactura(
          [_l('Arroz R.', 3, null)],
          [
            FacturaDelPreDespacho(
              numero: '46230',
              lineas: [_l('Arroz R.', 2, 20)],
            ),
            FacturaDelPreDespacho(
              numero: null,
              lineas: [_l('Arroz R.', 1, null)],
            ),
          ],
        );
        expect(
          [for (final f in filas) f.celdas],
          [
            ['46230', 'Arroz R.', '2', '20.0'],
            ['Sin número', 'Arroz R.', '1', '—'],
            ['Subtotal', '', '3', '≥ 20.0'],
          ],
        );
        expect(FacturaDelPreDespacho.sinNumero, 'Sin número');
      },
    );

    test('un pedido con DOS facturas lleva las dos tal cual en UNA fila', () {
      final filas = filasPorProductoYFactura(
        [_l('Cerv 500', 5, 15)],
        [
          FacturaDelPreDespacho(
            numero: '1024237, 1024240',
            lineas: [_l('Cerv 500', 5, 15)],
          ),
        ],
      );
      expect(filas.first.celdas, ['1024237, 1024240', 'Cerv 500', '5', '15.0']);
      expect(filas.where((f) => !f.subtotal), hasLength(1));
    });

    test(
      'una factura SIN RENGLONES sale al final, y lo dice: no desaparece',
      () {
        final filas = filasPorProductoYFactura(_productosDeAmado, [
          const FacturaDelPreDespacho(numero: '46231', lineas: []),
          ..._facturasDeAmado,
        ]);
        expect(filas.last.celdas, ['46231', facturaSinRenglones, '', '']);
        expect(
          filas.take(filas.length - 1).map((f) => f.celdas),
          _laHojaDeAmado,
        );
      },
    );

    test('sin facturas no hay NINGUNA fila', () {
      expect(filasPorProductoYFactura(_productosDeAmado, const []), isEmpty);
    });
  });

  group('el papel', () {
    test('LA HOJA CON FACTURAS IMPRIME LA TABLA DE AMADO, fila a fila y con su '
        'cabecera', () async {
      final bytes = await pdfPreDespacho(
        _hoja(_facturasDeAmado),
        impresoEn: _impresoEn,
      );
      final renglones = [for (final r in leerElPapel(bytes).renglones) r.texto];

      expect(renglones, contains('POR PRODUCTO Y FACTURA'));
      expect(renglones, contains('FACTURA PRODUCTO CANT. KG'));
      // El papel dice, letra por letra y EN ESTE ORDEN, la hoja de Amado. Desde
      // el título: el pie de la tabla de arriba también tiene renglones así.
      final esperado = [
        for (final fila in _laHojaDeAmado)
          fila.where((c) => c.isNotEmpty).join(' '),
      ];
      expect(
        renglones
            .skip(renglones.indexOf('POR PRODUCTO Y FACTURA'))
            .where(esperado.contains)
            .toList(),
        esperado,
        reason: renglones.join('\n'),
      );
    });

    test('LA HOJA SIN FACTURAS (la de Pedidos) NO TRAE la tabla ni su título', () async {
      final bytes = await pdfPreDespacho(
        _hoja(const []),
        impresoEn: _impresoEn,
      );
      final renglones = [for (final r in leerElPapel(bytes).renglones) r.texto];

      expect(renglones, isNot(contains('POR PRODUCTO Y FACTURA')));
      expect(
        renglones.where((r) => r.startsWith('FACTURA PRODUCTO')),
        isEmpty,
        reason:
            'la hoja de Pedidos suma lo filtrado y no sabe de qué factura sale '
            'cada cosa: una tabla vacía con su cabecera sería un hueco',
      );
      // La tabla de siempre sigue.
      expect(renglones, contains('PRODUCTO EMPAQUES UNIDADES KG SACADO'));
    });

    test('la tabla de siempre NO CAMBIA al añadir la nueva', () async {
      final con = leerElPapel(
        await pdfPreDespacho(_hoja(_facturasDeAmado), impresoEn: _impresoEn),
      ).renglones.map((r) => r.texto).toList();
      final sin = leerElPapel(
        await pdfPreDespacho(_hoja(const []), impresoEn: _impresoEn),
      ).renglones.map((r) => r.texto).toList();

      // Todo lo que decía la hoja sin la tabla nueva lo sigue diciendo con ella.
      for (final r in sin) {
        expect(con, contains(r));
      }
    });

    test('con muchas facturas la tabla pasa de página, y la cabecera VA OTRA VEZ', () async {
      final muchas = [
        for (var i = 0; i < 60; i++)
          FacturaDelPreDespacho(
            numero: '${46000 + i}',
            lineas: [_l('Cerv 500', 5, 15), _l('Arroz R.', 2, 20)],
          ),
      ];

      // La hoja entera sale, y en varias páginas.
      final bytes = await pdfPreDespacho(_hoja(muchas), impresoEn: _impresoEn);
      final claro = String.fromCharCodes(bytes);
      expect(
        RegExp(r'/Type\s*/Page[^s]').allMatches(claro).length,
        greaterThan(1),
      );

      // Un PDF de varias páginas no se deja leer entero con el lector de estas
      // pruebas, así que lo que se ata es la causa: la fila de la cabecera
      // lleva `repeat`. Sin ella, la segunda página es una columna de cifras
      // sin decir de qué es cada una.
      final tabla = tablaPorProductoYFactura(_productosDeAmado, muchas);
      expect(tabla.children.first.repeat, isTrue);
      expect(
        tabla.children.skip(1).where((fila) => fila.repeat),
        isEmpty,
        reason:
            'sólo la cabecera se repite: una fila de datos repetida '
            'duplicaría una cifra en la hoja',
      );
      // Y una fila por cada fila de texto, más la cabecera.
      expect(
        tabla.children,
        hasLength(
          filasPorProductoYFactura(_productosDeAmado, muchas).length + 1,
        ),
      );
    });
  });
}
