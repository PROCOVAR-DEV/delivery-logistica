// «1 PEDIDOS», «1 EMPAQUES», «1 UNIDADES» — 28/09/2026, en un SM-A165M.
//
// Son erratas pequeñas y pegadas a un número, que es justo lo que las hace
// caras: quien lee «1 empaques» en una hoja de almacén duda del 1.
//
// El patrón NO se inventa aquí: ya estaba en las rutas —«3 paradas» / «1
// parada», `EnlaceDeLaRuta.cuantasParadas`— y es un ternario sobre `== 1` pegado
// al número. Lo que se hizo fue barrer los que quedaban y traerlos a ése.
//
// LOS TRES CASOS DE CADA UNO, y el tercero es el que se olvida:
//
//   0 -> plural  («0 pedidos», no «0 pedido»)
//   1 -> singular
//   2 -> plural
//
// El cero se cuela porque quien pregunta «¿y si es uno?» mira el uno y da por
// hecho el resto. `n == 1 ? uno : muchos` lo resuelve solo; `n <= 1` no.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/vista_pre_despacho.dart';
import 'package:reparto/pantallas/rutas/datos/enlace_de_la_ruta.dart';

String _dia(DateTime d) => '${d.day}/${d.month}/${d.year}';

TotalesPreDespacho _conProductos(int cuantos, {double empaques = 20}) =>
    TotalesPreDespacho([
      for (var i = 0; i < cuantos; i++)
        LineaPreDespacho(
          producto: 'Producto $i',
          empaques: empaques,
          unidades: 120,
          pesoKg: 10,
        ),
    ]);

void main() {
  group('el patrón de la casa, que es el que se copió', () {
    test('«3 paradas» / «1 parada», y el cero en plural', () {
      expect(EnlaceDeLaRuta.cuantasParadas(0), '0 paradas');
      expect(EnlaceDeLaRuta.cuantasParadas(1), '1 parada');
      expect(EnlaceDeLaRuta.cuantasParadas(3), '3 paradas');
    });
  });

  group('la cabecera de Pedidos', () {
    String conteo(int total) =>
        textoDelConteo(total, const FiltrosPedidos(), _dia);

    test('un solo pedido no son «1 pedidos»', () {
      expect(conteo(1), startsWith('1 pedido,'));
      expect(conteo(1), isNot(contains('1 pedidos')));
    });

    test('y el cero y el resto siguen en plural', () {
      expect(conteo(0), startsWith('0 pedidos,'));
      expect(conteo(299), startsWith('299 pedidos,'));
    });
  });

  group('el pre-despacho', () {
    test('el subtítulo del cajón: ni «producto(s)» ni «1 empaques»', () {
      final uno = _conProductos(1, empaques: 1);
      expect(resumenDelPreDespacho(uno), startsWith('1 producto · 1 empaque · '));
      // El `(s)` se queda en el PAPEL, que es el punto de paridad con la hoja
      // de Next; en la pantalla no hay nada con lo que cuadrar.
      expect(resumenDelPreDespacho(uno), isNot(contains('(s)')));
    });

    test('con más de uno y con ninguno, en plural', () {
      expect(
        resumenDelPreDespacho(_conProductos(3, empaques: 20)),
        startsWith('3 productos · 60 empaques · '),
      );
      expect(
        resumenDelPreDespacho(_conProductos(0)),
        startsWith('0 productos · 0 empaques · '),
      );
    });

    test('el rótulo del botón que abre la vista', () {
      expect(rotuloDelPreDespacho(_conProductos(1)), endsWith('· 1 producto'));
      expect(rotuloDelPreDespacho(_conProductos(2)), endsWith('· 2 productos'));
      expect(rotuloDelPreDespacho(_conProductos(0)), endsWith('· 0 productos'));
    });
  });
}
