import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

/// «SE VEN 200 DE 300» TENÍA QUE LLEVAR A ALGÚN SITIO.
///
/// El aviso decía «afina con los filtros», y eso no era una salida: la lista va
/// ordenada, así que los que se quedaban fuera eran **los últimos** — entonces
/// los más lejanos al almacén, desde el 14/10/2026 los de factura más reciente —,
/// justo los que no se encuentran afinando, porque quien los busca no sabe ni qué
/// municipio mirar.
///
/// Medido en producción el 17/09/2026: La Habana tenía 300 pedidos sin colocar y
/// 100 de ellos no se podían ver de ninguna manera. Es el §3 del CLAUDE.md —
/// pedir un tope y no dejar pedir la tanda siguiente— y aquí sale barato, porque
/// los pedidos ya están todos en la base de este aparato.
void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    // Doce pedidos de facturas de horas distintas, cada uno más reciente que el
    // anterior, para que el orden cronológico sea el de verdad y el último de la
    // lista sea el más reciente. (Y a distancias que crecen igual: da lo mismo
    // el orden que se mire, que es lo que esta prueba NO quiere medir; el orden
    // propiamente dicho vive en `sin_colocar_test.dart`.)
    for (var i = 0; i < 12; i++) {
      await sembrarPedido(
        base,
        id: 'p-$i',
        aGrados: 0.01 * (i + 1),
        facturaAt: DateTime(2026, 9, 14, 8).add(Duration(hours: i)),
      );
    }
  });

  tearDown(() => base.close());

  Future<MitadIzquierda> conTope(int limite) async {
    final almacen = await consultas.almacenDe(sucursalStg);
    return consultas.sinColocar(
      sucursalStg,
      almacen,
      filtros: FiltrosSinColocar(limite: limite),
    );
  }

  test(
    'con el tope corto se avisa, y el total sigue diciendo la verdad',
    () async {
      final vista = await conTope(5);

      expect(vista.pedidos.length, 5);
      expect(vista.total, 12, reason: 'el total NO es lo que se pinta');
      expect(vista.truncada, isTrue);
    },
  );

  test('subiendo el tope una tanda salen los que faltaban, y son los de la '
      'cola', () async {
    final corta = await conTope(5);
    final entera = await conTope(5 + FiltrosSinColocar.tanda);

    expect(entera.pedidos.length, 12);
    expect(entera.truncada, isFalse, reason: 'ya no falta ninguno');

    // Y lo que aparece es exactamente lo que antes no se podía ver.
    final antes = corta.pedidos.map((p) => p.pedidoId).toSet();
    final ahora = entera.pedidos.map((p) => p.pedidoId).toList();
    expect(
      ahora.where((id) => !antes.contains(id)).toList(),
      ['p-5', 'p-6', 'p-7', 'p-8', 'p-9', 'p-10', 'p-11'],
      reason:
          'los que faltaban eran los de la cola de la lista, que es justo por '
          'lo que «afina con los filtros» no servía de nada',
    );
  });

  test('la tanda es de 200: ni cero, que no avanzaría, ni una, que serían '
      'cien toques', () async {
    expect(FiltrosSinColocar.tanda, greaterThanOrEqualTo(50));
  });
}
