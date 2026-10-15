/// QUIEN REPARTE SALE EN EL PAPEL QUE SE FIRMA (issue 7 de Amado, 14/10/2026).
///
/// El post-despacho lleva la firma «Entregó (chofer)», y el distribuidor es esa persona: la
/// responsable de la entrega y de devolver las facturas entregadas. Va en el renglon de la ruta de
/// la cabecera, que ya lleva `ruta · sucursal · camion`. Y si la ruta no tiene (una anterior al
/// 14/10/2026, o armada sin elegir) **no se escribe nada**: ni «sin distribuidor», ni un nombre
/// puesto por quien arma la hoja, en un papel que se firma.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/armar_post_despacho.dart';
import 'package:reparto/impresion/hoja.dart' show HojaPostDespacho;
import 'package:reparto/impresion/post_despacho.dart';

HojaPostDespacho _hoja({String distribuidor = ''}) => armarPostDespacho(
  DatosDeRuta(
    ruta: 'RT-20261014-001',
    sucursal: 'Santiago',
    vehiculo: 'Camión 1',
    distribuidor: distribuidor,
  ),
  const <PedidoDeRuta>[],
);

void main() {
  test('con distribuidor, el renglon de la ruta lo dice', () {
    expect(
      lineaDeLaRuta(_hoja(distribuidor: 'Juan Pérez')),
      'RT-20261014-001 · Santiago · Camión 1 · Distribuidor Juan Pérez',
    );
  });

  test('sin distribuidor, el renglon es el de siempre (y no inventa nada)', () {
    expect(
      lineaDeLaRuta(_hoja()),
      'RT-20261014-001 · Santiago · Camión 1',
      reason: 'una ruta historica no puede imprimir «sin distribuidor» en un papel que se firma',
    );
  });

  test('sin camion tambien se dice: el distribuidor no depende del vehiculo', () {
    final h = armarPostDespacho(
      const DatosDeRuta(
        ruta: 'R-1',
        sucursal: 'Holguín',
        vehiculo: '',
        distribuidor: 'Ana Torres',
      ),
      const <PedidoDeRuta>[],
    );
    expect(lineaDeLaRuta(h), 'R-1 · Holguín · Distribuidor Ana Torres');
  });

  test('el dato viaja de los datos de la ruta a la hoja', () {
    expect(_hoja(distribuidor: 'Juan Pérez').distribuidor, 'Juan Pérez');
    expect(_hoja().distribuidor, isEmpty);
  });
}
