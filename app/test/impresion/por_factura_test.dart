/// LA TABLA «POR FACTURA» — issue 8 de Amado.
///
/// «Se sacaron 20 blister, 10 de una factura y 10 de otra: en la tarjeta no se
/// pone 20, se ponen 10 y 10 poniendo la factura que provocó la salida de
/// inventario.»
///
/// Dos mitades, como en `los_dos_pesos_del_pre_despacho_test.dart`:
///
///  * los TEXTOS (`filasPorFactura`), que son lo que leen la pantalla y el PDF —
///    se prueban sin dibujar nada, con números sacados a mano;
///  * el PAPEL: se descomprime el PDF y se lee lo que de verdad dice. Una prueba
///    que sólo llamara a `filasPorFactura` no vería que la hoja se olvida de
///    imprimir la tabla, que es el fallo que importa.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/hoja.dart';
import 'package:reparto/impresion/por_factura.dart';
import 'package:reparto/impresion/pre_despacho.dart';

import 'los_dos_pesos_del_pre_despacho_test.dart' show leerElPapel;

final DateTime _impresoEn = DateTime(2026, 10, 14, 9, 0, 0);

/// El ejemplo de Amado: 10 blister de MALTA en cada una de dos facturas.
const _malta10 = LineaPreDespacho(
  producto: 'MALTA',
  formatos: 10,
  unidades: 60,
  pesoKg: 50,
);

List<FacturaDelPreDespacho> _dosFacturas() => const [
  FacturaDelPreDespacho(
    numero: 'F-100',
    cliente: 'Ana',
    lineas: [
      _malta10,
      LineaPreDespacho(
        producto: 'ARROZ',
        formatos: 4,
        unidades: 40,
        pesoKg: 100,
      ),
    ],
  ),
  FacturaDelPreDespacho(
    numero: 'F-200',
    cliente: 'Beto',
    lineas: [
      _malta10,
      // Sin peso: su subtotal tiene que ser un MÍNIMO, y el total también.
      LineaPreDespacho(
        producto: 'VODKA',
        formatos: 3,
        unidades: 18,
        pesoKg: null,
        lineasSinPeso: 1,
      ),
    ],
  ),
];

HojaPreDespacho _hoja(List<FacturaDelPreDespacho> facturas) => HojaPreDespacho(
  sucursal: 'Camagüey',
  vehiculo: 'Camión #1',
  pedidos: 2,
  pesoKg: 250,
  lineas: const [
    LineaPreDespacho(
      producto: 'MALTA',
      formatos: 20,
      unidades: 120,
      pesoKg: 100,
    ),
    LineaPreDespacho(producto: 'ARROZ', formatos: 4, unidades: 40, pesoKg: 100),
    LineaPreDespacho(
      producto: 'VODKA',
      formatos: 3,
      unidades: 18,
      pesoKg: null,
      lineasSinPeso: 1,
    ),
  ],
  facturas: facturas,
);

void main() {
  // Las fuentes de la hoja se leen del paquete de assets: hace falta el binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('los textos', () {
    test('UNA FILA POR (FACTURA, PRODUCTO), con el subtotal de cada factura y '
        'el total al final', () {
      final filas = filasPorFactura(_dosFacturas());

      expect(
        [for (final f in filas) f.celdas],
        [
          ['F-100', 'MALTA', '10', '60', '50.0'],
          ['F-100', 'ARROZ', '4', '40', '100.0'],
          ['F-100', 'Subtotal', '14', '100', '150.0'],
          ['F-200', 'MALTA', '10', '60', '50.0'],
          ['F-200', 'VODKA', '3', '18', '—'],
          ['F-200', 'Subtotal', '13', '78', '≥ 50.0'],
          ['Total', '', '27', '178', '≥ 200.0'],
        ],
      );
      expect(
        [for (final f in filas) f.tipo],
        [
          TipoDeFilaPorFactura.detalle,
          TipoDeFilaPorFactura.detalle,
          TipoDeFilaPorFactura.subtotal,
          TipoDeFilaPorFactura.detalle,
          TipoDeFilaPorFactura.detalle,
          TipoDeFilaPorFactura.subtotal,
          TipoDeFilaPorFactura.total,
        ],
      );
    });

    test('LA FACTURA SE REPITE EN CADA FILA: si la tabla se parte en dos '
        'páginas, ninguna fila se queda sin saber de quién es', () {
      final filas = filasPorFactura(_dosFacturas());
      final detalle = filas.where(
        (f) => f.tipo == TipoDeFilaPorFactura.detalle,
      );
      expect(detalle.map((f) => f.celdas.first), [
        'F-100',
        'F-100',
        'F-200',
        'F-200',
      ]);
    });

    test('toda fila tiene UNA celda por columna de la lista, y las columnas son '
        'las que se pueden cambiar en un solo sitio', () {
      expect(
        [for (final c in columnasPorFactura) c.titulo],
        ['Factura', 'Producto', 'Blister', 'Unidades', 'Peso (kg)'],
      );
      for (final fila in filasPorFactura(_dosFacturas())) {
        expect(fila.celdas, hasLength(columnasPorFactura.length));
      }
      // Hay una sola columna de la factura y una sola ancha: las dos de las que
      // depende la tarjeta del teléfono.
      expect(columnasPorFactura.where((c) => c.esLaFactura), hasLength(1));
      expect(columnasPorFactura.where((c) => c.ancha), hasLength(1));
    });

    test(
      'un cero NO es un peso: la celda dice «—» y el subtotal no lo suma',
      () {
        final filas = filasPorFactura(const [
          FacturaDelPreDespacho(
            numero: 'F-1',
            cliente: 'Ana',
            lineas: [
              LineaPreDespacho(
                producto: 'A',
                formatos: 2,
                unidades: 20,
                pesoKg: 0,
              ),
              LineaPreDespacho(
                producto: 'B',
                formatos: 1,
                unidades: 10,
                pesoKg: 5,
              ),
            ],
          ),
        ]);
        expect(filas[0].celdas.last, '—');
        expect(filas[1].celdas.last, '5.0');
        // El cero cuenta como «no se sabe», así que lo que suma es un mínimo.
        expect(filas[2].celdas.last, '≥ 5.0');
      },
    );

    test('una factura SIN número se llama «Sin número»: la tabla no inventa '
        'uno', () {
      final filas = filasPorFactura(const [
        FacturaDelPreDespacho(
          numero: null,
          cliente: 'Carla',
          lineas: [_malta10],
        ),
      ]);
      expect(filas.first.celdas.first, FacturaDelPreDespacho.sinNumero);
      expect(FacturaDelPreDespacho.sinNumero, 'Sin número');
    });

    test('una factura SIN RENGLONES sale, y lo dice: no desaparece de la '
        'tabla', () {
      final filas = filasPorFactura(const [
        FacturaDelPreDespacho(numero: 'F-9', cliente: 'Dani', lineas: []),
        FacturaDelPreDespacho(
          numero: 'F-10',
          cliente: 'Eva',
          lineas: [_malta10],
        ),
      ]);
      expect(filas.first.celdas, ['F-9', facturaSinRenglones, '', '', '']);
      // Y no inventa un subtotal de ceros para ella.
      expect(
        filas.where((f) => f.tipo == TipoDeFilaPorFactura.subtotal),
        hasLength(1),
      );
      expect(filas.last.celdas, ['Total', '', '10', '60', '50.0']);
    });

    test('sin facturas no hay NINGUNA fila, ni siquiera el total', () {
      expect(filasPorFactura(const []), isEmpty);
    });
  });

  group('el papel', () {
    test('LA HOJA CON FACTURAS IMPRIME LA TABLA, fila a fila y con su cabecera', () async {
      final bytes = await pdfPreDespacho(
        _hoja(_dosFacturas()),
        impresoEn: _impresoEn,
      );
      final renglones = [for (final r in leerElPapel(bytes).renglones) r.texto];

      expect(renglones, contains('POR FACTURA'));
      expect(
        renglones,
        contains('FACTURA PRODUCTO BLISTER UNIDADES PESO (KG)'),
      );
      // El papel dice, letra por letra, lo mismo que `filasPorFactura` (que es
      // lo que lee la pantalla).
      for (final fila in filasPorFactura(_dosFacturas())) {
        final esperado = fila.celdas.where((c) => c.isNotEmpty).join(' ');
        expect(renglones, contains(esperado), reason: renglones.join('\n'));
      }
    });

    test('LA HOJA SIN FACTURAS (la de Pedidos) NO TRAE la tabla ni su título', () async {
      final bytes = await pdfPreDespacho(
        _hoja(const []),
        impresoEn: _impresoEn,
      );
      final renglones = [for (final r in leerElPapel(bytes).renglones) r.texto];

      expect(renglones, isNot(contains('POR FACTURA')));
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
        await pdfPreDespacho(_hoja(_dosFacturas()), impresoEn: _impresoEn),
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
            numero: 'F-${1000 + i}',
            cliente: 'Cliente $i',
            lineas: const [
              _malta10,
              LineaPreDespacho(
                producto: 'ARROZ',
                formatos: 4,
                unidades: 40,
                pesoKg: 100,
              ),
            ],
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
      final tabla = tablaPorFactura(muchas);
      expect(tabla.children.first.repeat, isTrue);
      expect(
        tabla.children.skip(1).where((fila) => fila.repeat),
        isEmpty,
        reason:
            'sólo la cabecera se repite: una fila de datos repetida '
            'duplicaría una cifra en la hoja',
      );
      // Y una fila por cada fila de texto, más la cabecera.
      expect(tabla.children, hasLength(filasPorFactura(muchas).length + 1));
    });
  });
}
