/// Los literales de las hojas impresas, comparados **carácter a carácter**
/// contra el pliego.
///
/// **De dónde sale este fichero.** Es lo único que se salvó de
/// `test/textos/literales_test.dart`, que murió el 24/09/2026 con la traducción
/// al inglés. Aquel fichero comparaba trescientas claves de `Textos` contra el
/// pliego, y eso se fue con los `.arb`; pero tres de sus grupos no miraban los
/// textos traducidos **en absoluto** —miraban las constantes de
/// `impresion/pre_despacho.dart` y `impresion/post_despacho.dart`, que siempre
/// fueron literales en español a propósito—, y perderlos por arrastre habría
/// sido justo el fallo que la limpieza venía a evitar.
///
/// Por qué siguen importando: el papel es el punto de paridad con la de Next.
/// Estas hojas se imprimen, se firman y se comparan a mano con las que sacaba la
/// aplicación vieja; si una columna cambia de nombre o un `(s)` se convierte en
/// un plural, la comparación deja de valer y nadie se entera hasta que alguien
/// tiene las dos hojas encima de la mesa.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/post_despacho.dart';
import 'package:reparto/impresion/pre_despacho.dart';

void main() {
  group('nada de pluralizar lo que el pliego escribe con «(s)»', () {
    test('las hojas conservan el `(s)` DENTRO del texto', () {
      expect(TextoPreDespacho.pedidos, ' factura(s)');
      expect(TextoPostDespacho.entregadas, ' entregada(s)');
      expect(TextoPostDespacho.devueltas, ' devuelta(s)');
      expect(TextoPostDespacho.canceladas, ' cancelada(s)');

      // Y se escriben igual con uno que con muchos: no hay singular aparte.
      expect('1${TextoPreDespacho.pedidos}', '1 factura(s)');
      expect('7${TextoPreDespacho.pedidos}', '7 factura(s)');
    });
  });

  group('las hojas impresas van en español y no dependen de nada', () {
    test('sus literales son constantes', () {
      expect(TextoPreDespacho.titulo, 'Pre-despacho');
      expect(TextoPreDespacho.firmaSaco, 'Sacó del almacén');
      expect(TextoPreDespacho.firmaRecibio, 'Recibió (chofer)');

      expect(TextoPostDespacho.titulo, 'Post-despacho');
      expect(TextoPostDespacho.seccionQueda, 'Tiene que quedar en el camión');
      expect(TextoPostDespacho.seccionDeQuien, 'De quién es lo que vuelve');
      expect(
        TextoPostDespacho.nadaQueda,
        'Nada: se entregó todo lo que salió.',
      );
      expect(
        TextoPostDespacho.todoEntregado,
        'Todas las paradas se entregaron.',
      );
      expect(TextoPostDespacho.firmaEntrego, 'Entregó (chofer)');
      expect(TextoPostDespacho.firmaRecibio, 'Recibió en almacén');
    });

    test('las columnas se llaman como en el pliego', () {
      expect(
        <String>[
          TextoPreDespacho.colProducto,
          TextoPreDespacho.colEmpaques,
          TextoPreDespacho.colUnidades,
          TextoPreDespacho.colKg,
          TextoPreDespacho.colSacado,
        ],
        <String>['Producto', 'Empaques', 'Unidades', 'kg', 'Sacado'],
      );
      expect(
        <String>[
          TextoPostDespacho.colProducto,
          TextoPostDespacho.colSalio,
          TextoPostDespacho.colEntregado,
          TextoPostDespacho.colQueda,
          TextoPostDespacho.colBajo,
        ],
        <String>['Producto', 'Salió', 'Entregado', 'Queda', 'Bajó'],
      );
    });

    test('las etiquetas de una parada que vuelve', () {
      expect(TextoPostDespacho.etiquetaDevuelto, 'Devuelto');
      expect(TextoPostDespacho.etiquetaCancelado, 'Cancelado');
      expect(TextoPostDespacho.etiquetaSinMarcar, 'Sin marcar');
    });
  });
}
