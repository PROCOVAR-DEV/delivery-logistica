// EL MENÚ DEL SELECTOR SE QUEDA DEBAJO DE SU BOTÓN AUNQUE LA PÁGINA SE MUEVA.
//
// Jose, 25/09/2026, mirando la aplicación en el teléfono:
//
//     «los select tambien son modales no se por q se mueven en la vista si me
//      muevo con el scrool en ves de quedarse debajo de su input select»
//
// Y tenía razón, con una causa exacta: el selector abría con `showMenu`, que
// calcula la posición UNA SOLA VEZ —con el `RenderBox` del botón en el instante
// de abrirse— y deja el menú clavado en el `Overlay`, en coordenadas de
// pantalla. Al desplazar la página el botón se va y el menú se queda flotando
// sobre cualquier otra cosa.
//
// Lo peor es que encima había un comentario que decía «anclado al borde del
// boton». Era verdad sólo durante el primer fotograma, y un comentario no falla
// —§3-bis del CLAUDE.md de este repo—, así que esto se ata aquí: si alguien
// vuelve a `showMenu`, esta prueba lo dice.
//
// ESTA PRUEBA MIDE A 1200 px, Y ANTES MEDÍA A 390. El 28/09/2026 el selector
// pasó a abrirse como CAJÓN por debajo de `Anchos.escritorio` —«los dropdowns
// creo que seria mejor ponerlos como drawer», Jose—, así que a 390 px ya no hay
// ningún menú anclado que pueda seguir a nada: hay un cajón a pantalla completa,
// que es otra cosa y se prueba en `en_el_telefono_son_cajones_test.dart`. El
// ancho se cambió, no el incidente: el menú anclado sigue siendo lo de
// escritorio y sigue teniendo que seguir a su botón.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/selector.dart';

void main() {
  testWidgets('al desplazar la página, el menú sigue pegado a su botón', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);

    final desplazamiento = ScrollController();
    addTearDown(desplazamiento.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: desplazamiento,
            children: [
              // Aire de sobra por arriba y por abajo para que haya de verdad
              // hacia donde desplazarse.
              const SizedBox(height: 300),
              Selector<String>(
                opciones: const [
                  OpcionSelector(valor: 'cam', etiqueta: 'Camagüey'),
                  OpcionSelector(valor: 'stg', etiqueta: 'Santiago de Cuba'),
                ],
                valor: null,
                etiquetaVacia: 'Todas las sucursales',
                alElegir: (_) {},
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Se abre el menú.
    await tester.tap(find.text('Todas las sucursales'));
    await tester.pumpAndSettle();

    final opcion = find.text('Santiago de Cuba');
    expect(opcion, findsOneWidget, reason: 'el menú no llegó a abrirse');

    final botonAntes = tester.getTopLeft(find.text('Todas las sucursales'));
    final menuAntes = tester.getTopLeft(opcion);

    // Y ahora se mueve la página por debajo, que es el gesto de Jose.
    desplazamiento.jumpTo(160);
    await tester.pumpAndSettle();

    final botonDespues = tester.getTopLeft(find.text('Todas las sucursales'));
    final menuDespues = tester.getTopLeft(opcion);

    final seMovioElBoton = botonAntes.dy - botonDespues.dy;
    final seMovioElMenu = menuAntes.dy - menuDespues.dy;

    // El botón se ha ido hacia arriba de verdad: si no, la prueba no estaría
    // probando nada.
    expect(
      seMovioElBoton,
      greaterThan(100),
      reason: 'la página no se desplazó, la prueba no vale',
    );

    // Y el menú se ha ido CON ÉL. Con `showMenu` el menú se quedaba quieto y
    // esta diferencia salía 0 mientras el botón se movía 160.
    expect(
      seMovioElMenu,
      closeTo(seMovioElBoton, 1.0),
      reason:
          'el menú no siguió al botón: se movió $seMovioElMenu mientras el '
          'botón se movía $seMovioElBoton. Eso es el fallo del 25/09/2026, '
          'y vuelve en cuanto alguien cambie `MenuAnchor` por `showMenu`.',
    );
  });
}
