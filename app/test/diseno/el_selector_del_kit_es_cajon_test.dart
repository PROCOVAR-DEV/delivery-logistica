// EL SELECTOR DEL KIT: EN EL TELÉFONO, CAJÓN. EN ESCRITORIO, EL MENÚ.
//
// Jose, 28/09/2026, mirando la aplicación en el móvil:
//
//     «recuerda que este modal en el movil debe ser un drawer, el calendario,
//      todo lo que salga asi como modal que sobresalga, los dropdowns creo que
//      seria mejor ponerlos como drawer, todo eso para las opciones y queda
//      mucho mas comodo»
//
// Dijo «los dropdowns», en plural, y en la aplicación son CUATRO. El común de
// `lib/diseno/selector.dart` y el calendario se hicieron ese mismo día
// (`en_el_telefono_son_cajones_test.dart`); éste —el de
// `pantallas/pedidos/vista/kit.dart`— es el que más sitios toca: los filtros de
// Pedidos, los de Rutas, el Tablero y los cuatro pasos del asistente.
//
// **Son dos ficheros distintos con la misma clase `Selector`**, así que las
// pruebas del otro no cubren éste — ya pasó el 24/09/2026 con el aviso de «Nada
// que cuadre con…», que estaba en uno y no en el otro.
//
// **TODO LO DE AQUÍ VA EN PAREJA, y no es por gusto.** «Ahora es un cajón» se
// cumple perfectamente rompiendo el escritorio: basta con quitar el `if` del
// ancho y dejar el cajón siempre. Lo que se rompería entonces es el arreglo del
// 25/09/2026 —el menú anclado que sigue al botón al desplazar la página— y no
// lo cazaría nadie. Así que cada guarda se prueba a 390 **y** a 1200.
//
// Ojo con el ancho de serie: un `testWidgets` mide 800x600, que cae POR DEBAJO
// del corte. Por eso los dos anchos se ponen siempre con `tester.view` y se
// devuelven con `addTearDown(tester.view.reset)`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/anchos.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart';

/// El teléfono de Jose. Por debajo de `Anchos.escritorio` (1024).
const telefono = Size(390, 800);

/// Escritorio de verdad, por encima del corte.
const escritorio = Size(1200, 900);

/// La pantalla de debajo lleva esta marca. Si desaparece, es que lo que se
/// abrió se llevó por delante la pantalla — el fallo del 25/09/2026, que con el
/// cajón vuelve a estar en juego porque el cajón SÍ es una ruta.
const marcaDeLaPantalla = 'ESTA PANTALLA SIGUE AQUÍ';

/// El título del filtro: en escritorio es el `tooltip` del botón, y dentro del
/// cajón es la cabecera.
const rotulo = 'Vehículo de la ruta';

/// Lo que se lee en la caja cuando el filtro está sin poner.
const textoTodos = 'Todos los vehículos';

void anchoDe(WidgetTester tester, Size tamano) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = tamano;
  addTearDown(tester.view.reset);
}

/// Una pantalla con algo debajo, para que se note si se cierra.
///
/// **Van DOS rutas apiladas, y es lo que hace comprobable la guarda de «no
/// cierra la pantalla de debajo».** Con una sola ruta el `Navigator` se niega a
/// dejar la pila vacía, así que un `pop` de más no cierra nada y la prueba sale
/// verde pase lo que pase. Con dos, ese `pop` de más se lleva la lista y deja el
/// fondo a la vista, que es lo que pasa en la aplicación, donde toda pantalla
/// cuelga del enrutador y siempre tiene algo debajo.
Widget pantalla(Widget hijo) => MaterialApp(
  initialRoute: '/lista',
  routes: {
    '/': (_) =>
        const Scaffold(body: Center(child: Text('EL FONDO DE LA PILA'))),
    '/lista': (_) => Scaffold(
      body: ListView(
        children: [
          const Text(marcaDeLaPantalla),
          hijo,
          for (var i = 0; i < 40; i++)
            SizedBox(height: 40, child: Text('fila $i')),
        ],
      ),
    ),
  },
);

/// El «todos» de este selector **es una opción más de la lista**, con su propio
/// valor: aquí `alElegir` no es nulable. Es una de las dos razones por las que
/// no se puede cambiar por el `Selector` de `lib/diseno/` sin tocar las
/// dieciséis pantallas que lo llaman.
List<OpcionSelector<String>> vehiculos(int cuantos) => [
  const OpcionSelector('', textoTodos),
  for (var i = 0; i < cuantos; i++)
    OpcionSelector('v$i', 'Camión $i', nota: 'P-$i'),
];

void main() {
  /// Monta el selector y devuelve la lista donde se anota lo elegido.
  Future<List<String>> montar(
    WidgetTester tester, {
    required Size tamano,
    List<OpcionSelector<String>>? opciones,
    String valor = '',
  }) async {
    anchoDe(tester, tamano);
    final elegido = <String>[];
    await tester.pumpWidget(
      pantalla(
        Selector<String>(
          titulo: rotulo,
          valor: valor,
          opciones: opciones ?? vehiculos(3),
          alElegir: elegido.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return elegido;
  }

  /// La caja del filtro, que es por donde se abre. Se busca por el botón y no
  /// por su texto porque el texto se repite dentro del cajón.
  final caja = find.byType(OutlinedButton);

  testWidgets('a 390 px se abre un CAJÓN', (tester) async {
    await montar(tester, tamano: telefono);

    await tester.tap(caja);
    await tester.pumpAndSettle();

    expect(
      find.byType(Cajon),
      findsOneWidget,
      reason:
          'en el teléfono este desplegable tiene que abrirse como cajón, no '
          'como el panel de 320x360 anclado al botón (28/09/2026)',
    );
    expect(
      find.text('Camión 2'),
      findsOneWidget,
      reason: 'el cajón se abrió vacío: no están las opciones',
    );
  });

  testWidgets('a 1200 px TAMBIÉN es cajón, que es la regla de la casa', (
    tester,
  ) async {
    // ESTO DECÍA LO CONTRARIO HASTA EL 28/09/2026 POR LA TARDE.
    //
    // Por la mañana se puso un corte en `Anchos.escritorio` —cajón en el
    // teléfono, menú anclado en un monitor— y esta prueba lo fijaba diciendo «en
    // escritorio NO se abre cajón».
    //
    // Estaba mal por dos motivos. El §4 del `CLAUDE.md` de la raíz dice «**Cajón
    // siempre**, también en escritorio (excepción aprobada para este proyecto el
    // 05/09/2026)». Y Jose lo vio en su monitor ese mismo día, con un
    // desplegable flotando y descolocado sobre la página: «q te dije de los
    // dropdowns flotantes q los pusieras como drawer».
    //
    // Se queda como la mitad de la pareja, afirmando lo otro: que a los DOS
    // anchos sale lo mismo. Si alguien devuelve el corte, esta cae.
    await montar(tester, tamano: escritorio);

    await tester.tap(caja);
    await tester.pumpAndSettle();

    expect(
      find.byType(Cajon),
      findsOneWidget,
      reason:
          'a 1200 px volvió a salir el menú flotante: es lo que Jose pidió '
          'quitar y lo que el §4 prohíbe',
    );
    expect(
      find.text('Camión 2'),
      findsOneWidget,
      reason: 'el cajón se abrió pero sin las opciones dentro',
    );
  });

  testWidgets('el cajón lo titula el rótulo del filtro', (tester) async {
    // En escritorio ese rótulo sale como `tooltip` al pasar el ratón, y en un
    // teléfono no hay ratón. Sin el título del cajón, el de vehículo y el de
    // zona del asistente son dos cajones idénticos llenos de nombres.
    await montar(tester, tamano: telefono);

    await tester.tap(caja);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(Cajon), matching: find.text(rotulo)),
      findsOneWidget,
      reason:
          'el cajón se abrió sin decir de qué filtro es: en el teléfono el '
          'tooltip no sale nunca',
    );
  });

  testWidgets('en el cajón la ✕ está, y cierra sin tocar el filtro', (
    tester,
  ) async {
    final elegido = await montar(tester, tamano: telefono);

    await tester.tap(caja);
    await tester.pumpAndSettle();

    final equis = find.descendant(
      of: find.byType(Cajon),
      matching: find.byTooltip('Cerrar'),
    );
    expect(
      equis,
      findsOneWidget,
      reason:
          'la ✕ de cerrar NUNCA puede faltar: con el teclado abierto es la '
          'única salida garantizada',
    );

    await tester.tap(equis);
    await tester.pumpAndSettle();

    expect(find.byType(Cajon), findsNothing, reason: 'la ✕ no cerró el cajón');
    expect(
      elegido,
      isEmpty,
      reason: 'cerrar sin elegir cambió el filtro, y no debe cambiar nada',
    );
    expect(find.text(marcaDeLaPantalla), findsOneWidget);
  });

  testWidgets('Escape cierra el cajón sin tocar el filtro', (tester) async {
    // Lo que ya hacía el menú y lo que §9.2 pide de todo lo que tape. Lo da el
    // `ModalBarrier` de `abrirCajon`.
    final elegido = await montar(tester, tamano: telefono);

    await tester.tap(caja);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(Cajon), findsNothing);
    expect(elegido, isEmpty);
  });

  testWidgets('elegir avisa UNA vez, cierra el cajón y NO cierra la pantalla', (
    tester,
  ) async {
    // El mismo trío del 25/09/2026, pero por el otro camino: allí el peligro
    // era cerrar con `Navigator` algo que no es una ruta; aquí el cajón SÍ lo
    // es, y lo que se puede colar es dejar el `MenuItemButton` del menú, que
    // avisa pero no cierra nada — el cajón se queda tapando la lista que se
    // acababa de filtrar y ninguna prueba del menú se entera.
    final elegido = await montar(tester, tamano: telefono);

    await tester.tap(caja);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camión 1'));
    await tester.pumpAndSettle();

    expect(
      elegido,
      ['v1'],
      reason:
          'elegir no avisó de lo elegido, o avisó más de una vez por un solo '
          'toque',
    );
    expect(
      find.byType(Cajon),
      findsNothing,
      reason:
          'el cajón se quedó ABIERTO tapando la lista que se acababa de '
          'filtrar: falta cerrarlo al elegir',
    );
    expect(
      find.text(marcaDeLaPantalla),
      findsOneWidget,
      reason:
          'LA PANTALLA DE DEBAJO SE CERRÓ al elegir: se hizo un `pop` de más',
    );
  });

  testWidgets('buscar y no encontrar nada SE DICE también en el cajón', (
    tester,
  ) async {
    // 24/09/2026, en el paso 1 del asistente: con `me` escrito, el panel se
    // quedaba con la caja de buscar y NADA debajo. En el cajón sería peor
    // todavía, porque son los 390x800 enteros para no decir nada.
    await montar(tester, tamano: telefono, opciones: vehiculos(5));

    await tester.tap(caja);
    await tester.pumpAndSettle();

    final buscador = find.descendant(
      of: find.byType(Cajon),
      matching: find.byType(TextField),
    );
    await tester.enterText(buscador, 'zzz');
    await tester.pumpAndSettle();

    expect(
      find.textContaining(Selector.nadaQueCuadre),
      findsOneWidget,
      reason: 'un cajón en blanco se lee como «esto está roto»',
    );
    expect(
      find.textContaining('«zzz»'),
      findsOneWidget,
      reason: 'con lo que se escribió, para que se vea la errata',
    );
  });

  testWidgets('LA OTRA MITAD: con resultados el cajón NO avisa de nada', (
    tester,
  ) async {
    // Un aviso que sale siempre deja de leerse, y entonces tampoco se lee el
    // día que importa (CLAUDE.md §3-quinquies).
    final elegido = await montar(
      tester,
      tamano: telefono,
      opciones: vehiculos(5),
    );

    await tester.tap(caja);
    await tester.pumpAndSettle();

    final buscador = find.descendant(
      of: find.byType(Cajon),
      matching: find.byType(TextField),
    );
    await tester.enterText(buscador, 'P-3');
    await tester.pumpAndSettle();

    expect(
      find.text('Camión 3'),
      findsOneWidget,
      reason:
          'el buscador del cajón no mira la NOTA: `P-3` es la chapa del camión, '
          'que es como se le llama',
    );
    expect(find.text('Camión 2'), findsNothing, reason: 'no filtró');
    expect(find.textContaining(Selector.nadaQueCuadre), findsNothing);

    await tester.tap(find.text('Camión 3'));
    await tester.pumpAndSettle();
    expect(elegido, ['v3']);
  });

  testWidgets('con cuarenta opciones se llega a la última desplazando', (
    tester,
  ) async {
    // El caso de Jose: el selector de vendedor del asistente tiene ciento y
    // pico. Un cajón que no baja es PEOR que el menú de antes, porque el menú
    // al menos tenía su propia barra de 360 px.
    final elegido = await montar(
      tester,
      tamano: telefono,
      opciones: vehiculos(40),
    );

    await tester.tap(caja);
    await tester.pumpAndSettle();

    final ultima = find.text('Camión 39');
    expect(ultima, findsOneWidget, reason: 'la última opción no se construyó');

    // Que esté en el árbol no es que se vea: al abrir tiene que estar POR
    // DEBAJO del borde de la pantalla, o esta prueba no está probando nada.
    expect(
      tester.getTopLeft(ultima).dy,
      greaterThan(telefono.height),
      reason:
          'las cuarenta opciones caben de golpe en 800 px: la prueba no prueba '
          'que se pueda desplazar',
    );

    await tester.ensureVisible(ultima);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(ultima).dy,
      lessThan(telefono.height),
      reason:
          'la lista NO se desplazó: la última opción sigue fuera de la pantalla '
          'y es inalcanzable con el dedo',
    );

    await tester.tap(ultima);
    await tester.pumpAndSettle();
    expect(elegido, [
      'v39',
    ], reason: 'se llegó a ella pero tocarla no hizo nada');
  });

  testWidgets('abrir el cajón encima de una lista larga no revienta', (
    tester,
  ) async {
    // El choque de desplazamientos, otra vez y en el sitio nuevo: el cuerpo del
    // cajón es un `SingleChildScrollView` y en móvil se engancha solo al
    // `PrimaryScrollController` de la pantalla, que es el mismo del `ListView`
    // de debajo.
    await montar(tester, tamano: telefono, opciones: vehiculos(40));

    await tester.tap(caja);
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'abrir el cajón sobre una lista desplazable reventó: dos '
          '`ScrollPosition` colgando del mismo `PrimaryScrollController`',
    );
  });

  test('el corte sale de `Anchos.escritorio`, no de un número a mano', () {
    // Si alguien cambia el corte, que lo cambie en un sitio y se entere de que
    // estas pruebas miden a los dos lados de ÉL. `anchoEscritorio` es el que
    // usa el kit y tiene que ser el mismo que el de los otros tres
    // desplegables: dos números distintos para el mismo corte es un teléfono
    // ancho con media regla aplicada.
    expect(anchoEscritorio, Anchos.escritorio);
    expect(telefono.width, lessThan(anchoEscritorio));
    expect(escritorio.width, greaterThanOrEqualTo(anchoEscritorio));
  });
}
