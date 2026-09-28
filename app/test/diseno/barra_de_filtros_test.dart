// La barra de filtros coloca igual en TODAS las listas, y eso se ata aquí.
//
// El 25/09/2026 Jose miró la aplicación en un teléfono y dijo:
//
//     «en movil sigues teniendo los filtros en todas las vistas q tengan
//      filtros lo tienes mal ubicados regados sin uniformidad sin nada»
//
// Tenía razón y era medible: a 390 px la caja de buscar de Pedidos se quedaba
// clavada en 220 dejando 146 px muertos, y los siete controles salían en un
// `Wrap` que los partía en escalones desiguales según lo que midiera cada
// etiqueta.
//
// Un comentario no habría impedido que la próxima pantalla naciera otra vez
// torcida —§3-bis del CLAUDE.md de este repo: lo que tiene que cuadrar se ata
// con una PRUEBA—, así que lo que estas pruebas fijan es lo que se ve:
//
//   1. en el teléfono los filtros salen en DOS COLUMNAS DE LA MISMA ANCHURA,
//      que es lo que endereza el borde derecho;
//   2. un filtro impar NO se queda a media anchura con un hueco al lado;
//   3. la caja de buscar ocupa TODO el ancho, sin el hueco muerto;
//   4. en pantalla grande se vuelve a la fila que fluye, que ahí sí está bien.
//
// AVISO PARA QUIEN VENGA A MUTAR ESTO, porque ya me pasó a mí:
//
// El filtro impar sale a lo ancho por DOS caminos a la vez —el
// `SizedBox(width: double.infinity)` que lo envuelve y el
// `crossAxisAlignment: stretch` de la columna que lo contiene—, así que romper
// UNO SOLO deja la prueba en verde y parece que no sirve. No es que esté hueca:
// es que el otro camino lo tapa. Rompiendo los dos, la prueba canta
// `Expected: <0.0>  Actual: <145.0>`, y esos 145 px de sangrado son justo el
// escalón del que se quejaba Jose.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/barra_de_filtros.dart';

/// Monta la barra a un ancho concreto de pantalla, que es lo único que decide
/// si se reparte en rejilla o en fila.
Future<void> montar(
  WidgetTester tester, {
  required double ancho,
  required List<Widget> filtros,
  Widget? busqueda,
  List<Widget> anchoCompleto = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(ancho, 900);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BarraDeFiltros(
            margen: EdgeInsets.zero,
            busqueda: busqueda ?? const _Caja('buscar'),
            filtros: filtros,
            anchoCompleto: anchoCompleto,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Un trozo cualquiera con una etiqueta reconocible. Se le pone un ancho
/// natural DISTINTO a cada uno a propósito: es justo lo que hacía que el `Wrap`
/// sacara escalones, así que si la rejilla los iguala, los iguala de verdad.
class _Caja extends StatelessWidget {
  /// La clave de arriba —`super.key`— es la que lee `_peso` para repartir la
  /// fila; la de dentro, `nombre`, es por la que buscan las pruebas. Son dos a
  /// propósito: con una sola, `find.byKey` encontraría dos widgets y `getRect`
  /// no sabría cuál medir. **Y sin la de arriba el reparto no se prueba**: eso
  /// es lo que dejó pasar que en la aplicación de verdad no hubiera ninguna.
  const _Caja(this.nombre, {this.anchoNatural = 100, super.key});

  final String nombre;
  final double anchoNatural;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(nombre),
    height: 40,
    width: anchoNatural,
    color: Colors.amber,
    child: Text(nombre),
  );
}

void main() {
  group('en el teléfono (390 px)', () {
    testWidgets('los filtros salen en dos columnas de la MISMA anchura', (
      tester,
    ) async {
      await montar(
        tester,
        ancho: 390,
        filtros: const [
          _Caja('uno', anchoNatural: 60),
          _Caja('dos', anchoNatural: 180),
          _Caja('tres', anchoNatural: 90),
          _Caja('cuatro', anchoNatural: 210),
        ],
      );

      final uno = tester.getRect(find.byKey(const ValueKey('uno')));
      final dos = tester.getRect(find.byKey(const ValueKey('dos')));
      final tres = tester.getRect(find.byKey(const ValueKey('tres')));
      final cuatro = tester.getRect(find.byKey(const ValueKey('cuatro')));

      // Los dos de cada fila miden lo mismo aunque pidieran 60 y 180.
      expect(uno.width, dos.width);
      expect(tres.width, cuatro.width);

      // Y las dos filas se cortan por el mismo sitio: ESE es el borde derecho
      // recto que no había.
      expect(dos.right, cuatro.right);
      expect(uno.left, tres.left);
    });

    // CADA UNO SE LLEVA LO QUE MIDE, Y ENTRE LOS DOS LLENAN LA FILA — 28/09.
    //
    // Las de arriba fijan el borde derecho recto, que es lo del 25/09. Ésta fija
    // lo otro que pidió Jose mirando Pedidos en el teléfono: «esos campos son de
    // ese mismo tamaño en vez de repartirse para que quepan todos y con su
    // respectivo tamaño». Media caja para cada uno deja al corto con hueco y al
    // largo con los puntos suspensivos.
    //
    // Las dos cosas a la vez, y por eso van juntas en esta prueba: si alguien
    // vuelve al 50/50 se cae el reparto, y si alguien vuelve a `Flexible` se cae
    // el borde.
    testWidgets('el rótulo largo se lleva más sitio, y la fila sigue llena', (
      tester,
    ) async {
      await montar(
        tester,
        ancho: 390,
        filtros: const [
          _Caja('corto', anchoNatural: 30, key: ValueKey('ok')),
          _Caja(
            'largo',
            anchoNatural: 30,
            key: ValueKey('un rotulo bastante largo de verdad'),
          ),
        ],
      );

      final corto = tester.getRect(find.byKey(const ValueKey('corto')));
      final largo = tester.getRect(find.byKey(const ValueKey('largo')));

      expect(
        largo.width,
        greaterThan(corto.width),
        reason:
            'con media caja cada uno, «Cualquier precio» y «Todos los '
            'vendedores» salen igual de anchos y el largo se corta',
      );
      // Y NO SE PIERDE EL BORDE: el de la izquierda empieza en el margen y el de
      // la derecha acaba en el otro, aunque los dos pidieran 30 px.
      expect(corto.left, 0);
      expect(largo.right, 390);
    });

    testWidgets('un filtro impar ocupa la fila entera, no media con un hueco', (
      tester,
    ) async {
      await montar(
        tester,
        ancho: 390,
        filtros: const [
          _Caja('uno'),
          _Caja('dos'),
          _Caja('solo'),
        ],
      );

      final dos = tester.getRect(find.byKey(const ValueKey('dos')));
      final solo = tester.getRect(find.byKey(const ValueKey('solo')));
      final uno = tester.getRect(find.byKey(const ValueKey('uno')));

      // El suelto va de lado a lado: empieza donde la columna izquierda y acaba
      // donde la derecha. Si se quedase a media anchura, `solo.right` sería el
      // de la columna izquierda y volvería el escalón.
      expect(solo.left, uno.left);
      expect(solo.right, dos.right);
      expect(solo.width, greaterThan(uno.width));
    });

    testWidgets('la caja de buscar ocupa todo el ancho, sin hueco muerto', (
      tester,
    ) async {
      await montar(
        tester,
        ancho: 390,
        busqueda: const _Caja('busqueda', anchoNatural: 220),
        filtros: const [_Caja('uno'), _Caja('dos')],
      );

      final busqueda = tester.getRect(find.byKey(const ValueKey('busqueda')));
      final uno = tester.getRect(find.byKey(const ValueKey('uno')));
      final dos = tester.getRect(find.byKey(const ValueKey('dos')));

      // De borde a borde de la rejilla: es lo que quita los 146 px muertos que
      // dejaba la caja de 220 de Pedidos.
      expect(busqueda.left, uno.left);
      expect(busqueda.right, dos.right);
    });

    testWidgets('lo de ancho completo no se parte en media columna', (
      tester,
    ) async {
      await montar(
        tester,
        ancho: 390,
        filtros: const [_Caja('uno'), _Caja('dos')],
        anchoCompleto: const [_Caja('rango', anchoNatural: 120)],
      );

      final uno = tester.getRect(find.byKey(const ValueKey('uno')));
      final dos = tester.getRect(find.byKey(const ValueKey('dos')));
      final rango = tester.getRect(find.byKey(const ValueKey('rango')));

      expect(rango.left, uno.left);
      expect(rango.right, dos.right);
    });
  });

  group('en pantalla grande (1200 px)', () {
    testWidgets('vuelve a ser una fila: dos filtros caben en la misma línea', (
      tester,
    ) async {
      await montar(
        tester,
        ancho: 1200,
        filtros: const [
          _Caja('uno', anchoNatural: 60),
          _Caja('dos', anchoNatural: 180),
        ],
      );

      final uno = tester.getRect(find.byKey(const ValueKey('uno')));
      final dos = tester.getRect(find.byKey(const ValueKey('dos')));

      // Misma línea…
      expect(uno.top, dos.top);
      // …y cada uno con SU ancho, que aquí sobra sitio y forzar columnas
      // iguales desperdiciaría media pantalla.
      expect(uno.width, isNot(dos.width));
      expect(uno.width, 60);
      expect(dos.width, 180);
    });
  });
}
