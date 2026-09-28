// EL MISMO BULTO, «516 kg» EN UNA PANTALLA Y «516.5 kg» EN LA DE AL LADO.
//
// Jose, 28/09/2026: la zona del Tablero decía «516 kg» y el detalle de la ruta
// armada con esa misma zona decía «516.5 kg». No hay dos pesos: hay un `double`
// —516,45 y pico— y dos formatos. El Tablero lo escribe con
// `Numeros.kgRedondeado` (entero, coma de `es`) y el detalle lo escribía con el
// `kg()` de Pedidos (un decimal, punto).
//
// Es el §3-bis del `CLAUDE.md` con otra cara, y por eso esta prueba existe: dos
// cosas que tienen que decir lo mismo **se atan con una prueba, no con un
// comentario**. El 17/09/2026 el comentario que avisaba del «Sin colocar (722)
// encima de una lista de 293» ya estaba escrito encima del contador, y no sirvió
// de nada — un comentario no falla.
//
// Lo que ata esto es que la prueba llama a las DOS funciones, la de Rutas y la
// del Tablero, y las compara. Cambiar cualquiera de las dos la pone roja.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/formato_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
// El vecino con el que hay que cuadrar.
import 'package:reparto/pantallas/tablero/vista/kit.dart' as tablero_kit;

import 'rutas_a_mano.dart';

void main() {
  group('el peso de una ruta se escribe como el de su zona', () {
    // El de Jose el 28/09/2026, y los que suelen romper un formato: el que cae
    // justo en el medio, el de miles (separador), el cero y el redondo.
    const pesos = <double>[516.45, 516.5, 0, 1000, 1234.56, 99.99];

    test('mismo peso, mismas letras, en las dos pantallas', () {
      for (final peso in pesos) {
        expect(
          pesoDeLaRuta(peso),
          tablero_kit.pesoBonito(peso),
          reason:
              'ES EL «516 kg» CONTRA EL «516.5 kg» del 28/09/2026. Con $peso kg '
              'la zona del Tablero escribe «${tablero_kit.pesoBonito(peso)}» y '
              'el detalle de su ruta «${pesoDeLaRuta(peso)}». Son el mismo '
              'bulto y se miran seguidas.',
        );
      }
    });

    test('y ese formato NO lleva decimales, que es lo que se veía de más', () {
      expect(pesoDeLaRuta(516.45), '516 kg');
      expect(
        pesoDeLaRuta(516.45),
        isNot(contains('.')),
        reason:
            'el punto decimal era la marca de que esto venía del `kg()` de '
            'Pedidos y no del formato de la casa',
      );
    });
  });

  group('la cabecera del detalle', () {
    // EL PESO VA EN LA PARADA, no en `routes.total_weight` — 28/09/2026.
    //
    // La cabecera dejo de leer esa columna: se escribe una vez al armar y nadie
    // la recalcula, y con ella decia «420 kg» encima de dos paradas que suman
    // 516,5 (`el_peso_de_la_ruta_test.dart`). Aqui se prueba el FORMATO, asi
    // que el numero tiene que entrar por donde la pantalla lo lee ahora.
    //
    // `rutaAMano(peso: …)` se queda con un valor que NO es el de las paradas a
    // proposito: si alguien devuelve la cabecera a leer la columna, este grupo
    // se pone rojo tambien.
    Future<void> pintar(WidgetTester tester, double peso) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineaDeDatosDeLaRuta(
            ruta: rutaAMano(
              peso: 1,
              paradas: [
                paradaAMano(id: 'p1', cliente: 'Ana', costo: 8.0, peso: peso),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('escribe el peso de la ruta como lo escribe el Tablero', (
      tester,
    ) async {
      await pintar(tester, 516.45);

      expect(
        find.textContaining('516 kg'),
        findsOneWidget,
        reason: 'lo mismo que dice la zona de la que salió esta ruta',
      );
      expect(
        find.textContaining('516.5 kg'),
        findsNothing,
        reason:
            'ES LO QUE JOSE VIO: el mismo bulto con un decimal de más y un punto '
            'donde el resto de la aplicación pone coma.',
      );
    });

    testWidgets('con una ruta vacía escribe «0 kg», que sí es una cifra', (
      tester,
    ) async {
      await pintar(tester, 0);

      expect(find.textContaining('0 kg'), findsOneWidget);
      expect(
        find.textContaining('— kg'),
        findsNothing,
        reason:
            'una ruta sin carga pesa cero de verdad; aquí el cero NO es el «no '
            'se sabe» disfrazado que persigue el §2 del CLAUDE.md',
      );
    });
  });
}
