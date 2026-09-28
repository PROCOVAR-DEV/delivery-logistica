// ELEGIR EN UN DESPLEGABLE CIERRA EL MENÚ. NO LA PANTALLA.
//
// El 25/09/2026 los dos selectores pasaron de `showMenu` a `MenuAnchor` para
// que el menú siguiera al botón al desplazar. Ese cambio arrastra otro que no
// se ve: con `showMenu` el menú era una RUTA, así que elegir una opción se
// resolvía con `Navigator.pop`; con `MenuAnchor` el menú vive en la misma
// pantalla, y ese mismo `pop` **cierra la pantalla de debajo**.
//
// El auditor lo comprobó ese día: poniendo `Navigator.of(context).pop()` en el
// `onTap` de cada opción, las **1.656 pruebas del proyecto seguían en verde**
// mientras al tocar un municipio se cerraba la pantalla de Clientes entera. Y
// quitando el cierre, el menú se quedaba abierto tapando la lista, también sin
// que fallara nada.
//
// Por eso las tres cosas se prueban juntas y por separado en los DOS selectores
// —el de `diseno/` y el de Clientes, que son dos ficheros distintos con el mismo
// cambio—:
//
//   1. elegir avisa;
//   2. elegir CIERRA el menú;
//   3. y la pantalla de debajo SIGUE EN PIE.
//
// Y una cuarta, que es la que ya explotó una vez: abrir el menú encima de una
// lista desplazable —el caso real, que Clientes tiene 8.578— no puede dejar dos
// `ScrollPosition` colgando del `PrimaryScrollController`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/selector.dart' as comun;
import 'package:reparto/pantallas/clientes/vista/selector.dart' as clientes;

/// La pantalla de debajo lleva esta marca. Si desaparece, es que el menú se
/// llevó por delante la pantalla, que es justo el fallo que se vigila.
const marcaDeLaPantalla = 'ESTA PANTALLA SIGUE AQUÍ';

/// Un cuerpo con MUCHAS filas: el menú tiene que abrirse encima de algo
/// desplazable, que es donde saltó el choque de desplazamientos.
Widget _pantalla({required Widget selector}) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        const Text(marcaDeLaPantalla),
        selector,
        for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('fila $i')),
      ],
    ),
  ),
);

void main() {
  group('el selector de diseño', () {
    testWidgets('elegir avisa, cierra el menú y NO cierra la pantalla', (
      tester,
    ) async {
      // A 1200 px, que es donde vive el MENÚ. Por debajo de
      // `Anchos.escritorio` el selector de `diseno/` abre un cajón desde el
      // 28/09/2026, y el cajón se cierra con el `Navigator` justo al revés que
      // esto — que es el error que esta prueba vigila, visto desde el otro
      // lado. El cajón tiene su propia pareja en
      // `en_el_telefono_son_cajones_test.dart`.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);

      String? elegido;

      await tester.pumpWidget(
        _pantalla(
          selector: comun.Selector<String>(
            opciones: const [
              comun.OpcionSelector(valor: 'stg', etiqueta: 'Santiago de Cuba'),
              comun.OpcionSelector(valor: 'cam', etiqueta: 'Camagüey'),
            ],
            valor: null,
            etiquetaVacia: 'Todas las sucursales',
            alElegir: (v) => elegido = v,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todas las sucursales'));
      await tester.pumpAndSettle();
      expect(
        find.text('Camagüey'),
        findsOneWidget,
        reason: 'el menú no llegó a abrirse',
      );

      await tester.tap(find.text('Camagüey'));
      await tester.pumpAndSettle();

      expect(elegido, 'cam', reason: 'elegir no avisó de lo elegido');
      expect(
        find.text('Camagüey'),
        findsNothing,
        reason:
            'el menú se quedó ABIERTO tapando lo de debajo: falta cerrarlo al '
            'elegir (`MenuController…close()`)',
      );
      expect(
        find.text(marcaDeLaPantalla),
        findsOneWidget,
        reason:
            'LA PANTALLA SE CERRÓ al elegir una opción. Es el `Navigator.pop` '
            'de cuando el menú era una ruta: con `MenuAnchor` el menú vive en '
            'esta misma pantalla y el `pop` se lleva la pantalla por delante.',
      );
    });
  });

  group('el selector de Clientes', () {
    testWidgets('elegir avisa, cierra el menú y NO cierra la pantalla', (
      tester,
    ) async {
      String? elegido;
      var avisos = 0;

      await tester.pumpWidget(
        _pantalla(
          selector: clientes.SelectorFiltro<String>(
            titulo: 'Municipio del cliente',
            textoTodos: 'Todos los municipios',
            opciones: const [
              clientes.OpcionSelector(valor: 'sc', etiqueta: 'Santiago'),
              clientes.OpcionSelector(valor: 'pa', etiqueta: 'Palma Soriano'),
            ],
            valor: null,
            alElegir: (v) {
              elegido = v;
              avisos++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todos los municipios'));
      await tester.pumpAndSettle();
      expect(
        find.text('Palma Soriano'),
        findsOneWidget,
        reason: 'el menú no llegó a abrirse',
      );

      await tester.tap(find.text('Palma Soriano'));
      await tester.pumpAndSettle();

      expect(elegido, 'pa', reason: 'elegir no avisó de lo elegido');
      expect(avisos, 1, reason: 'avisó más de una vez por un solo toque');
      expect(
        find.text('Palma Soriano'),
        findsNothing,
        reason:
            'el menú se quedó ABIERTO tapando la lista de clientes: falta '
            'cerrarlo al elegir',
      );
      expect(
        find.text(marcaDeLaPantalla),
        findsOneWidget,
        reason:
            'LA PANTALLA DE CLIENTES SE CERRÓ al tocar un municipio. Es el '
            '`Navigator.pop` de cuando el menú era una ruta.',
      );
    });

    testWidgets('abrir el menú sobre una lista larga no revienta', (
      tester,
    ) async {
      // Éste es el caso de verdad: en producción Clientes tiene 8.578 filas, o
      // sea que el menú SIEMPRE se abre encima de algo desplazable. Sin
      // `primary: false` en el menú quedan dos `ScrollPosition` colgando del
      // mismo `PrimaryScrollController` y Flutter lo corta en seco.
      await tester.pumpWidget(
        _pantalla(
          selector: clientes.SelectorFiltro<String>(
            titulo: 'Vendedor que lo atiende',
            textoTodos: 'Todos los vendedores',
            opciones: const [
              clientes.OpcionSelector(valor: 'a', etiqueta: 'Andy'),
              clientes.OpcionSelector(valor: 'b', etiqueta: 'Beatriz'),
              clientes.OpcionSelector(valor: 'c', etiqueta: 'Carlos'),
              clientes.OpcionSelector(valor: 'd', etiqueta: 'Dania'),
              clientes.OpcionSelector(valor: 'e', etiqueta: 'Eddy'),
            ],
            valor: null,
            alElegir: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todos los vendedores'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'abrir el menú sobre una lista desplazable reventó. Es el choque '
            'de desplazamientos: le falta `primary: false` al menú.',
      );
      expect(find.text('Beatriz'), findsOneWidget);
    });
  });
}
