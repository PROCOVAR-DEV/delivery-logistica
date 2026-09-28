// BUSCAR EN UN DESPLEGABLE Y NO ENCONTRAR NADA SE DICE.
//
// Visto en el navegador el 24/09/2026, en el paso 1 del asistente de rutas: con
// `me` escrito en el buscador de sucursales, el panel se quedaba con la caja de
// buscar y **nada debajo**, encima de un desplegable que tenía las tres
// sucursales dentro. Un panel en blanco es indistinguible de «este desplegable
// está roto» y de «aquí no hay nada que elegir», que es justo lo que no pasaba.
//
// Este `Selector` —el de `pantallas/pedidos/vista/kit.dart`— es el que usan los
// filtros de Pedidos y los cuatro pasos del asistente. Su hermano de
// `lib/diseno/selector.dart` ya decía «Nada que cuadre con…»; a éste no se le
// había traído, y son dos ficheros distintos con el mismo nombre de clase, así
// que la prueba del otro no lo cubría.
//
// En pareja, como manda `CLAUDE.md` §3-quinquies: el aviso cuando toca y **no**
// cuando no.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart';

void main() {
  const sucursales = <OpcionSelector<String>>[
    OpcionSelector('', 'Elige la sucursal…'),
    OpcionSelector('a', 'Camagüey', nota: 'CAM'),
    OpcionSelector('b', 'Holguín', nota: 'HOL'),
    OpcionSelector('c', 'Santiago de Cuba', nota: 'STG'),
  ];

  Future<void> abrir(WidgetTester tester) async {
    // A 1200 px, Y HAY QUE PONERLO A MANO.
    //
    // Un `testWidgets` sin tocar `tester.view` mide **800x600**, que está POR
    // DEBAJO de `Anchos.escritorio` (1024). Desde el 28/09/2026 este `Selector`
    // abre un cajón por debajo de ese corte, así que estas cuatro pruebas
    // —escritas para el MENÚ— pasaban solas a medir un cajón sin que nadie lo
    // pidiera. Habrían seguido en verde, porque el aviso de «Nada que cuadre
    // con…» está en los dos sitios, y entonces el menú de escritorio se habría
    // quedado sin nadie que lo mirara.
    //
    // El cajón tiene su propia pareja en
    // `test/diseno/el_selector_del_kit_es_cajon_test.dart`, que además prueba
    // este mismo aviso dentro del cajón.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Selector<String>(
              titulo: 'Sucursal',
              valor: '',
              opciones: sucursales,
              alElegir: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elige la sucursal…'));
    await tester.pumpAndSettle();
  }

  testWidgets('buscar algo que no está lo DICE, con lo que se escribió', (
    tester,
  ) async {
    await abrir(tester);

    await tester.enterText(find.byType(TextField).first, 'me');
    await tester.pumpAndSettle();

    expect(
      find.textContaining(Selector.nadaQueCuadre),
      findsOneWidget,
      reason: 'un panel en blanco se lee como «esto está roto»',
    );
    expect(
      find.textContaining('«me»'),
      findsOneWidget,
      reason: 'con lo que se escribió, para que se vea la errata',
    );
    // Y ninguna opción, claro.
    expect(find.text('Camagüey'), findsNothing);
  });

  testWidgets('LA OTRA MITAD: con resultados NO sale ningún aviso', (
    tester,
  ) async {
    await abrir(tester);

    await tester.enterText(find.byType(TextField).first, 'hol');
    await tester.pumpAndSettle();

    expect(find.text('Holguín'), findsOneWidget);
    expect(find.textContaining(Selector.nadaQueCuadre), findsNothing);
  });

  testWidgets('y con el buscador vacío tampoco, que es lo normal', (
    tester,
  ) async {
    await abrir(tester);

    expect(find.text('Camagüey'), findsOneWidget);
    expect(find.textContaining(Selector.nadaQueCuadre), findsNothing);
  });

  testWidgets('se busca también por el CÓDIGO de la sucursal', (tester) async {
    // `CAM`, `HOL`, `STG` es como se nombran las sucursales aquí. Buscando sólo
    // por la etiqueta, escribir el código no encontraba nada y el panel se
    // quedaba en blanco — el mismo agujero, por el otro lado.
    //
    // **`STG` y no `CAM`**: `CAM` está dentro de «Camagüey», así que con él la
    // prueba salía verde aunque la nota no se mirara. Un caso que no distingue
    // las dos cosas no prueba ninguna.
    await abrir(tester);

    await tester.enterText(find.byType(TextField).first, 'STG');
    await tester.pumpAndSettle();

    expect(find.text('Santiago de Cuba'), findsOneWidget);
    expect(find.textContaining(Selector.nadaQueCuadre), findsNothing);
  });
}
