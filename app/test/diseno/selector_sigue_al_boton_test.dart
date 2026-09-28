// EL SELECTOR NO VUELVE A ABRIR UN MENÚ FLOTANTE. NUNCA, A NINGÚN ANCHO.
//
// Este fichero guarda un incidente que ya no puede repetirse de la misma forma,
// y por eso lo que comprueba cambió el 28/09/2026. La historia entera, porque es
// lo que da sentido a lo que hay abajo:
//
// **25/09/2026.** Jose, en el teléfono:
//
//     «los select tambien son modales no se por q se mueven en la vista si me
//      muevo con el scrool en ves de quedarse debajo de su input select»
//
// La causa era exacta: el selector abría con `showMenu`, que calcula la posición
// UNA SOLA VEZ —con el `RenderBox` del botón en el instante de abrirse— y deja el
// menú clavado en el `Overlay`, en coordenadas de pantalla. Al desplazar la
// página el botón se va y el menú se queda flotando sobre cualquier otra cosa.
// Se cambió a `MenuAnchor`, que sí lo ancla, y esta prueba medía que lo seguía.
//
// **28/09/2026, por la mañana.** El selector pasó a abrirse como cajón por debajo
// de `Anchos.escritorio`. Esta prueba se movió de 390 px a 1200, porque a 390 ya
// no quedaba menú que pudiera seguir a nada.
//
// **28/09/2026, por la tarde.** Se quitó el corte: cajón SIEMPRE, también en
// escritorio. Dos motivos, y los dos valen más que el corte:
//
//   1. el §4 del `CLAUDE.md` de la raíz lo dice desde el 05/09/2026 —«**Cajón
//      siempre**, también en escritorio»— y el corte lo contradecía;
//   2. Jose lo vio en su monitor ese mismo día, con el selector de sucursal de
//      Almacenes flotando y descolocado sobre la página: «q te dije de los
//      dropdowns flotantes q los pusieras como drawer».
//
// # Y ENTONCES, ¿QUÉ SE COMPRUEBA AQUÍ AHORA?
//
// El incidente del 25/09 **ya no puede pasar**: un cajón es una ruta a pantalla
// completa, no está anclado a nada, así que no hay a qué seguir ni de qué
// despegarse. Borrar el fichero sería lo cómodo, y sería perder la guarda: lo que
// de verdad protegía no era el anclaje, era que **el selector no abriera un panel
// suelto que flota sobre la página**.
//
// Eso es lo que se ata aquí, en su forma nueva: que no vuelva ni `MenuAnchor` ni
// `showMenu` ni ningún otro menú flotante, a ningún ancho. Si alguien devuelve el
// corte de escritorio «porque en un monitor se ve mejor», esta prueba lo dice
// antes de que llegue a la pantalla de Jose.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/diseno/selector.dart';

void main() {
  Future<void> montar(WidgetTester tester, {required double ancho}) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Selector<String>(
              tooltip: 'Municipio del cliente',
              etiquetaVacia: 'Todos los municipios',
              valor: '',
              opciones: const [
                OpcionSelector(valor: '', etiqueta: 'Todos los municipios'),
                OpcionSelector(valor: 'cam', etiqueta: 'Camagüey'),
                OpcionSelector(valor: 'stg', etiqueta: 'Santiago de Cuba'),
              ],
              alElegir: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // LOS DOS ANCHOS, Y A PROPÓSITO EN PAREJA. Con uno solo, devolver el corte
  // dejaría la mitad en verde y la regla se perdería por donde nadie mira.
  for (final (nombre, ancho) in const [
    ('el teléfono de Jose', 390.0),
    ('un monitor', 1400.0),
  ]) {
    testWidgets('en $nombre el selector abre CAJÓN y no un menú flotante', (
      tester,
    ) async {
      await montar(tester, ancho: ancho);

      expect(
        find.byType(MenuAnchor),
        findsNothing,
        reason:
            'a $ancho px el selector trae un `MenuAnchor` puesto. Es el panel '
            'que flota sobre la página, el que Jose pidió quitar el 28/09/2026 '
            'y el que el §4 del CLAUDE.md prohíbe desde el 05/09',
      );

      await tester.tap(find.text('Todos los municipios'));
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsOneWidget,
        reason:
            'a $ancho px no se abrió un cajón: la regla es «cajón siempre, '
            'también en escritorio», no «cajón cuando la pantalla es pequeña»',
      );
      expect(
        find.text('Camagüey'),
        findsOneWidget,
        reason: 'el cajón se abrió sin las opciones dentro',
      );
    });
  }

  // Y LA MITAD QUE MIRA AL INCIDENTE VIEJO: que el panel no se quede flotando
  // cuando la página se mueve. Con un cajón esto es cierto por construcción —es
  // una ruta a pantalla completa— y justo por eso hay que comprobarlo: el día
  // que alguien lo cambie por algo anclado, lo del 25/09/2026 vuelve.
  testWidgets('desplazar la página por detrás no despega el cajón', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final desplazamiento = ScrollController();
    addTearDown(desplazamiento.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: desplazamiento,
            children: [
              const SizedBox(height: 400),
              Selector<String>(
                tooltip: 'Municipio del cliente',
                etiquetaVacia: 'Todos los municipios',
                valor: '',
                opciones: const [
                  OpcionSelector(valor: '', etiqueta: 'Todos los municipios'),
                  OpcionSelector(valor: 'cam', etiqueta: 'Camagüey'),
                ],
                alElegir: (_) {},
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Todos los municipios'));
    await tester.pumpAndSettle();
    final antes = tester.getRect(find.byType(Cajon));

    desplazamiento.jumpTo(600);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(Cajon)),
      antes,
      reason:
          'el cajón se movió al desplazar lo de debajo. Un cajón es una ruta a '
          'pantalla completa y no debe enterarse de nada de eso: si se mueve, '
          'es que alguien lo ancló a algo y vuelve el incidente del 25/09/2026',
    );
    expect(
      find.text('Camagüey'),
      findsOneWidget,
      reason: 'el cajón se cerró solo al desplazar la página de debajo',
    );
  });
}
