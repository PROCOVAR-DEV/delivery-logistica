// EL NÚMERO ROJO (issue 19 de Amado, 20/10/2026).
//
// Una parada con el punto de entrega puesto a MANO sale en el mapa con su número en
// ROJO, y en ningún otro color. Es lo que dice, de un vistazo, que esa parada NO
// está donde dice la geolocalización del cliente.
//
//  * El color sale de `lasQueCaenJuntas` —lo que el pintor usa para la chincheta—,
//    que es Dart puro: se comprueba sin montar nada y diciendo QUÉ está mal.
//  * Precedencia: por ENCIMA de entregada y de regreso. Y en un grupo (`2·3`), una
//    manual basta para pintarlo todo rojo (decisión documentada en `_colorDe`).
//  * `recorridoDe` pasa `puntoManual` de la fila a la parada: sin eso el rojo no
//    llega nunca al mapa aunque el color esté bien.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/croquis_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  PuntoDelCroquis enPunto(
    int numero,
    Offset donde, {
    bool manual = false,
    bool entregada = false,
    bool regreso = false,
  }) => PuntoDelCroquis(
    ParadaDelRecorrido(
      id: 'p$numero',
      numero: numero,
      etiqueta: 'Parada $numero',
      entregada: entregada,
      esRegreso: regreso,
      manual: manual,
    ),
    donde,
  );

  Color colorDe(List<PuntoDelCroquis> paradas, {int cual = 0}) =>
      lasQueCaenJuntas(paradas)[cual].color;

  test('la parada manual sale en el rojo del punto a mano; las demás no', () {
    final juntas = lasQueCaenJuntas([
      enPunto(1, const Offset(10, 10), manual: true),
      enPunto(2, const Offset(200, 200)),
      enPunto(3, const Offset(400, 50), entregada: true),
      enPunto(4, const Offset(50, 300), regreso: true),
    ]);
    expect(juntas.map((g) => g.color), [
      ColoresDelMapa.puntoManual,
      ColoresDelMapa.recorrido,
      ColoresDelMapa.salida,
      ColoresDelMapa.regreso,
    ], reason: 'solo la 1 es manual: el rojo no se cuela en las otras');
  });

  test('el rojo del punto a mano NO es el rojo de «impide»', () {
    expect(ColoresDelMapa.puntoManual, isNot(Colores.rojo));
  });

  test('manda sobre entregada y sobre regreso', () {
    expect(
      colorDe([enPunto(1, Offset.zero, manual: true, entregada: true)]),
      ColoresDelMapa.puntoManual,
      reason: 'una entregada que NO estaba donde decía el cliente se ve igual',
    );
    expect(
      colorDe([enPunto(1, Offset.zero, manual: true, regreso: true)]),
      ColoresDelMapa.puntoManual,
    );
  });

  test('en un grupo «2·3», UNA manual basta para pintarlo rojo', () {
    final juntas = lasQueCaenJuntas([
      enPunto(2, const Offset(200, 200)),
      enPunto(3, const Offset(205, 200), manual: true),
    ]);
    expect(juntas, hasLength(1));
    expect(juntas.single.rotulo, '2·3');
    expect(juntas.single.color, ColoresDelMapa.puntoManual);
  });

  test('un grupo sin ninguna manual conserva su color de siempre', () {
    final juntas = lasQueCaenJuntas([
      enPunto(2, const Offset(200, 200), entregada: true),
      enPunto(3, const Offset(205, 200)),
    ]);
    expect(juntas.single.color, ColoresDelMapa.recorrido);
  });

  test('recorridoDe lleva `puntoManual` de la fila a la parada', () async {
    final base = baseDePrueba();
    addTearDown(base.close);
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1');
    for (final (id, orden) in [('a', 1), ('b', 2)]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: id,
        rutaId: 'R1',
        orden: orden,
        endLat: 21.1,
        endLng: -77.1,
      );
    }
    await base.customStatement(
      "UPDATE orders SET punto_manual = 1 WHERE id = 'b'",
    );

    final recorrido = recorridoDe(
      RutaConTodo(
        ruta: await (base.select(
          base.routes,
        )..where((r) => r.id.equals('R1'))).getSingle(),
        paradas: await ConsultasRutas(base).paradasDe('R1'),
      ),
    );
    expect(
      [for (final p in recorrido.paradas) (p.id, p.manual)],
      [('a', false), ('b', true)],
    );
  });
}
