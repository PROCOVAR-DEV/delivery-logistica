// EL FILTRO DE CLIENTES: EN EL TELÉFONO, CAJÓN. EN ESCRITORIO, EL MENÚ.
//
// Jose, 28/09/2026, mirando la aplicación en el móvil:
//
//     «recuerda que este modal en el movil debe ser un drawer, el calendario,
//      todo lo que salga asi como modal que sobresalga, los dropdowns creo que
//      seria mejor ponerlos como drawer, todo eso para las opciones y queda
//      mucho mas comodo»
//
// Dijo «los dropdowns», en plural. El común de `lib/diseno/selector.dart` y el
// calendario se hicieron ese mismo día (`en_el_telefono_son_cajones_test.dart`);
// éste —el de los seis filtros de Clientes— seguía siendo menú a cualquier
// ancho, y un filtro que se comporta distinto según la pantalla es peor que los
// cuatro mal igual.
//
// **TODO LO DE AQUÍ VA EN PAREJA, y no es por gusto.** «Ahora es un cajón» se
// cumple perfectamente rompiendo el escritorio: basta con quitar el `if` del
// ancho y dejar el cajón siempre. Lo que se rompería entonces es el arreglo del
// 25/09/2026 —el menú anclado que sigue al botón al desplazar la lista de
// clientes— y no lo cazaría nadie. Así que cada guarda se prueba a 390 **y** a
// 1200.
//
// Ojo con el ancho de serie: un `testWidgets` mide 800x600, que cae POR DEBAJO
// del corte. Por eso los dos anchos se ponen siempre con `tester.view` y se
// devuelven con `addTearDown(tester.view.reset)`: sin eso el ancho se le queda
// pegado a la prueba siguiente del mismo fichero.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/anchos.dart';
import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/pantallas/clientes/vista/selector.dart';

/// El teléfono de Jose. Por debajo de `Anchos.escritorio` (1024).
const telefono = Size(390, 800);

/// Escritorio de verdad, por encima del corte.
const escritorio = Size(1200, 900);

/// La pantalla de debajo lleva esta marca. Si desaparece, es que lo que se
/// abrió se llevó por delante la pantalla de Clientes — el fallo del
/// 25/09/2026, que con el cajón vuelve a estar en juego porque el cajón SÍ es
/// una ruta.
const marcaDeLaPantalla = 'ESTA PANTALLA SIGUE AQUÍ';

/// El rótulo del filtro, que es además el título del cajón.
const rotulo = 'Municipio del cliente';

/// Lo que se lee en la caja cuando no hay filtro puesto.
const textoTodos = 'Todos los municipios';

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
/// fondo a la vista, que es exactamente lo que pasa en la aplicación, donde
/// Clientes cuelga del enrutador y siempre tiene algo debajo.
///
/// Y el cuerpo es un `ListView` largo a propósito: en producción Clientes tiene
/// 8.578 filas, o sea que lo que se abra se abre SIEMPRE encima de algo
/// desplazable.
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

List<OpcionSelector<String>> municipios(int cuantos) => [
  for (var i = 0; i < cuantos; i++)
    OpcionSelector<String>(
      valor: 'm$i',
      etiqueta: 'Municipio $i',
      nota: '${i * 7}',
    ),
];

void main() {
  /// Monta el filtro y devuelve la lista donde se anota lo elegido.
  ///
  /// Se anota **también el `null`** del «todos», que es como este selector dice
  /// «quita el filtro»: con una `List<String>` ese caso no se podría distinguir
  /// de «no avisó».
  Future<List<String?>> montar(
    WidgetTester tester, {
    required Size tamano,
    List<OpcionSelector<String>>? opciones,
    String? valor,
  }) async {
    anchoDe(tester, tamano);
    final elegido = <String?>[];
    await tester.pumpWidget(
      pantalla(
        SelectorFiltro<String>(
          titulo: rotulo,
          textoTodos: textoTodos,
          icono: Icons.location_city,
          opciones: opciones ?? municipios(3),
          valor: valor,
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
          'en el teléfono el filtro de Clientes tiene que abrirse como cajón, '
          'no como el panel de 280 px anclado al botón (28/09/2026)',
    );
    expect(
      find.text('Municipio 2'),
      findsOneWidget,
      reason: 'el cajón se abrió vacío: no están las opciones',
    );
  });

  testWidgets('a 1200 px sigue saliendo el MENÚ de siempre', (tester) async {
    // La otra mitad, y la que de verdad importa: sin esto, «ahora es cajón» se
    // cumple rompiendo el escritorio y nadie se entera.
    await montar(tester, tamano: escritorio);

    await tester.tap(caja);
    await tester.pumpAndSettle();

    expect(
      find.text('Municipio 2'),
      findsOneWidget,
      reason: 'el menú no llegó a abrirse en escritorio',
    );
    expect(
      find.byType(Cajon),
      findsNothing,
      reason:
          'en escritorio NO se abre cajón: el menú anclado es lo que arregló el '
          '25/09/2026 (que siga al botón al desplazar la lista de clientes) y '
          'no se toca. Ver `selector_sigue_al_boton_test.dart`.',
    );
  });

  testWidgets('el cajón lo titula el rótulo del filtro', (tester) async {
    // En escritorio el rótulo se lee encima de la caja; dentro del cajón esa
    // caja ya no se ve, así que sin el título quedarían seis cajones iguales
    // que dicen «Todos los…» y no se sabría de qué filtro es cada uno. Es el
    // único sitio donde se lee de qué va lo que se está eligiendo.
    await montar(tester, tamano: telefono);

    await tester.tap(caja);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(Cajon), matching: find.text(rotulo)),
      findsOneWidget,
      reason:
          'el cajón se abrió sin decir de qué filtro es: en el teléfono no hay '
          'ratón que saque el tooltip y el rótulo de encima ya no se ve',
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
    // El mismo trío del 25/09/2026 (`los_menus_no_cierran_la_pantalla_test`),
    // pero por el otro camino: allí el peligro era cerrar con `Navigator` algo
    // que no es una ruta; aquí el cajón SÍ lo es, y lo que se puede colar es
    // cerrarlo con un `MenuController` que no existe — entonces el cajón se
    // queda abierto tapando la lista y nada falla.
    final elegido = await montar(tester, tamano: telefono);

    await tester.tap(caja);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Municipio 1'));
    await tester.pumpAndSettle();

    expect(
      elegido,
      ['m1'],
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
          'LA PANTALLA DE CLIENTES SE CERRÓ al tocar un municipio: se hizo un '
          '`pop` de más',
    );
  });

  testWidgets('el «todos» del cajón quita el filtro, y avisa con null', (
    tester,
  ) async {
    // «Todos los municipios» es la salida de vuelta: es lo ÚNICO que quita el
    // filtro, y avisa con `null` porque así está escrito `pantalla_clientes`
    // (`filtros.copiar(municipio: v)`). Si en el cajón avisara con un valor, el
    // filtro no se podría quitar desde el teléfono.
    final elegido = await montar(tester, tamano: telefono, valor: 'm1');

    await tester.tap(caja);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(Cajon), matching: find.text(textoTodos)),
    );
    await tester.pumpAndSettle();

    expect(
      elegido,
      [null],
      reason:
          'tocar «Todos los municipios» en el cajón no quitó el filtro: tiene '
          'que avisar con `null`',
    );
    expect(find.byType(Cajon), findsNothing);
    expect(find.text(marcaDeLaPantalla), findsOneWidget);
  });

  testWidgets('el buscador del cajón filtra, y el «todos» NO se filtra nunca', (
    tester,
  ) async {
    // Las dos mitades de lo mismo. El «todos» va suelto y sin filtrar porque es
    // la salida de vuelta: escondido detrás de tres letras escritas, quien está
    // buscando se queda sin forma de quitar el filtro y tiene que cerrar y
    // volver a abrir.
    final elegido = await montar(
      tester,
      tamano: telefono,
      opciones: municipios(20),
    );

    await tester.tap(caja);
    await tester.pumpAndSettle();

    final buscador = find.descendant(
      of: find.byType(Cajon),
      matching: find.byType(TextField),
    );
    expect(
      buscador,
      findsOneWidget,
      reason: 'con veinte opciones el buscador tiene que salir',
    );

    // Se escribe «17» y no «Municipio 17» a propósito: lo que se teclea queda
    // dentro del `TextField`, y buscar el texto entero encuentra DOS —la opción
    // y lo escrito— y la prueba falla sin que nada esté mal.
    await tester.enterText(buscador, '17');
    await tester.pumpAndSettle();

    expect(find.text('Municipio 17'), findsOneWidget);
    expect(find.text('Municipio 18'), findsNothing, reason: 'no filtró');
    expect(
      find.descendant(of: find.byType(Cajon), matching: find.text(textoTodos)),
      findsOneWidget,
      reason:
          'el buscador se llevó por delante «Todos los municipios»: es la '
          'salida de vuelta y no se filtra nunca',
    );

    await tester.tap(find.text('Municipio 17'));
    await tester.pumpAndSettle();
    expect(elegido, ['m17']);
  });

  testWidgets('con cuarenta opciones se llega a la última desplazando', (
    tester,
  ) async {
    // Un cajón que no baja es PEOR que el menú de antes, porque el menú al
    // menos tenía su propia barra de 360 px.
    final elegido = await montar(
      tester,
      tamano: telefono,
      opciones: municipios(40),
    );

    await tester.tap(caja);
    await tester.pumpAndSettle();

    final ultima = find.text('Municipio 39');
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
      'm39',
    ], reason: 'se llegó a ella pero tocarla no hizo nada');
  });

  testWidgets('abrir el cajón encima de la lista de clientes no revienta', (
    tester,
  ) async {
    // El choque de desplazamientos, otra vez y en el sitio nuevo: el cuerpo del
    // cajón es un `SingleChildScrollView` y en móvil se engancha solo al
    // `PrimaryScrollController` de la pantalla, que es el mismo del `ListView`
    // de debajo. Es el caso de verdad: Clientes tiene 8.578 filas.
    await montar(tester, tamano: telefono, opciones: municipios(40));

    await tester.tap(caja);
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'abrir el cajón sobre la lista de clientes reventó: dos '
          '`ScrollPosition` colgando del mismo `PrimaryScrollController`',
    );
  });

  test('el corte sale de `Anchos.escritorio`, no de un número a mano', () {
    // Si alguien cambia el corte, que lo cambie en un sitio y se entere de que
    // estas pruebas miden a los dos lados de ÉL.
    expect(telefono.width, lessThan(Anchos.escritorio));
    expect(escritorio.width, greaterThanOrEqualTo(Anchos.escritorio));
  });
}
