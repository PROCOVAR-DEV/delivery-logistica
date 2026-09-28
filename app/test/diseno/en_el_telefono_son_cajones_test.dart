// EN EL TELÉFONO, CAJÓN. EN ESCRITORIO, EL MENÚ DE SIEMPRE.
//
// Jose, 28/09/2026, con Pedidos abierto en el móvil y el calendario flotando
// encima de la tabla:
//
//     «recuerda que este modal en el movil debe ser un drawer, el calendario,
//      todo lo que salga asi como modal que sobresalga, los dropdowns creo que
//      seria mejor ponerlos como drawer, todo eso para las opciones y queda
//      mucho mas comodo»
//
// Y es la regla de la casa de Procovar, ya escrita para TODOS los proyectos:
// cajón en móvil, modal en escritorio, y la ✕ de cerrar no puede desaparecer.
//
// **TODO LO DE AQUÍ VA EN PAREJA, y no es por gusto.** «Ahora es un cajón» se
// cumple perfectamente rompiendo el escritorio: basta con quitar el `if` del
// ancho y dejar el cajón siempre. Lo que se rompería entonces es el arreglo del
// 25/09/2026 —el menú anclado que sigue al botón al desplazar la página— y no
// lo cazaría nadie, porque las pruebas de aquello miden lo suyo y darían por
// bueno un cajón que no se mueve. Así que cada guarda se prueba a 390 **y** a
// 1200.
//
// Los dos anchos se ponen con `tester.view` y se devuelven SIEMPRE con
// `addTearDown(tester.view.reset)`: sin eso el ancho se le queda pegado a la
// prueba siguiente del mismo fichero y media suite mide otra pantalla.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/anchos.dart';
import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/diseno/rango_de_fechas.dart';
import 'package:reparto/diseno/selector.dart';

/// El teléfono de Jose. Por debajo de `Anchos.escritorio` (1024).
const telefono = Size(390, 800);

/// Escritorio de verdad, por encima del corte.
const escritorio = Size(1200, 900);

/// La pantalla de debajo lleva esta marca. Si desaparece, es que lo que se abrió
/// se llevó por delante la pantalla — el fallo del 25/09/2026, que con el cajón
/// vuelve a estar en juego porque el cajón SÍ es una ruta.
const marcaDeLaPantalla = 'ESTA PANTALLA SIGUE AQUÍ';

void anchoDe(WidgetTester tester, Size tamano) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = tamano;
  addTearDown(tester.view.reset);
}

/// Una pantalla cualquiera con algo debajo, para que se note si se cierra.
///
/// **Van DOS rutas apiladas, y es lo que hace comprobable la guarda de «no
/// cierra la pantalla de debajo».** Con una sola ruta el `Navigator` se niega a
/// dejar la pila vacía, así que un `pop` de más no cierra nada y la prueba sale
/// verde pase lo que pase: mutado el 28/09/2026 —dos `maybePop` seguidos al
/// elegir— y en verde. Con dos rutas, ese `pop` de más se lleva la lista y deja
/// el fondo a la vista, que es exactamente lo que pasa en la aplicación, donde
/// toda pantalla cuelga del enrutador y siempre tiene algo debajo.
/// Las dos salen de `initialRoute: '/lista'`: el `Navigator` de serie parte la
/// ruta y apila `/` y luego `/lista`, así que quedan dos sin montar nada raro.
Widget pantalla(Widget hijo) => MaterialApp(
  initialRoute: '/lista',
  routes: {
    '/': (_) => const Scaffold(body: Center(child: Text('EL FONDO DE LA PILA'))),
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

List<OpcionSelector<String>> vendedores(int cuantos) => [
  const OpcionSelector<String>(valor: '', etiqueta: 'Todos los vendedores'),
  for (var i = 0; i < cuantos; i++)
    OpcionSelector<String>(valor: 'v$i', etiqueta: 'Vendedor $i'),
];

void main() {
  group('el desplegable', () {
    /// Monta el selector y devuelve la lista donde se anota lo elegido.
    Future<List<String>> montar(
      WidgetTester tester, {
      required Size tamano,
      List<OpcionSelector<String>>? opciones,
      String? valor,
    }) async {
      anchoDe(tester, tamano);
      final elegido = <String>[];
      await tester.pumpWidget(
        pantalla(
          Selector<String>(
            opciones: opciones ?? vendedores(3),
            valor: valor,
            etiquetaVacia: 'Todos los vendedores',
            // El tooltip es lo que titula el cajón, y aquí además sirve para
            // distinguir el título de la etiqueta del botón, que si no dicen lo
            // mismo y `find.text` encuentra dos.
            tooltip: 'Vendedor que lo atiende',
            alElegir: elegido.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return elegido;
    }

    testWidgets('a 390 px se abre un CAJÓN', (tester) async {
      await montar(tester, tamano: telefono);

      await tester.tap(find.text('Todos los vendedores'));
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsOneWidget,
        reason:
            'en el teléfono el desplegable tiene que abrirse como cajón, no '
            'como panel flotante anclado al botón (28/09/2026)',
      );
      expect(
        find.text('Vendedor 2'),
        findsOneWidget,
        reason: 'el cajón se abrió vacío: no están las opciones',
      );
    });

    testWidgets('a 1200 px TAMBIÉN es cajón, que es la regla de la casa', (
      tester,
    ) async {
      // ESTO DECÍA LO CONTRARIO HASTA EL 28/09/2026, y por eso está aquí.
      //
      // Durante unas horas hubo un corte en `Anchos.escritorio`: cajón en el
      // teléfono, menú anclado en un monitor. Y esta prueba fijaba ese corte
      // diciendo «en escritorio NO se abre cajón».
      //
      // Estaba mal por dos motivos. El §4 del `CLAUDE.md` de la raíz dice
      // «**Cajón siempre**, también en escritorio (excepción aprobada para este
      // proyecto el 05/09/2026)». Y Jose lo vio en su monitor el mismo día, con
      // el selector de sucursal de Almacenes flotando y descolocado sobre la
      // página: «q te dije de los dropdowns flotantes q los pusieras como
      // drawer».
      //
      // Se queda como la mitad de la pareja, pero afirmando lo otro: que a los
      // DOS anchos sale lo mismo. Si alguien devuelve el corte, esta cae.
      await montar(tester, tamano: escritorio);

      await tester.tap(find.text('Todos los vendedores'));
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsOneWidget,
        reason:
            'a 1200 px volvió a salir el menú flotante: es lo que Jose pidió '
            'quitar y lo que el §4 prohíbe',
      );
      expect(
        find.text('Vendedor 2'),
        findsOneWidget,
        reason: 'el cajón se abrió pero sin las opciones dentro',
      );
    });

    testWidgets('en el cajón la ✕ está, y cierra sin elegir nada', (
      tester,
    ) async {
      final elegido = await montar(tester, tamano: telefono);

      await tester.tap(find.text('Todos los vendedores'));
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

    testWidgets('elegir avisa, cierra el cajón y NO cierra la pantalla', (
      tester,
    ) async {
      // El mismo trío del 25/09/2026 (`los_menus_no_cierran_la_pantalla_test`),
      // pero por el otro camino: allí el peligro era cerrar con `Navigator`
      // algo que no es una ruta; aquí el cajón SÍ lo es, y lo que se puede
      // colar es cerrarlo con un `MenuController` que no existe — entonces el
      // cajón se queda abierto tapando la lista y nada falla.
      final elegido = await montar(tester, tamano: telefono);

      await tester.tap(find.text('Todos los vendedores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vendedor 1'));
      await tester.pumpAndSettle();

      expect(elegido, ['v1'], reason: 'elegir no avisó de lo elegido');
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

    testWidgets('lo que ya está elegido se ve marcado en el cajón', (
      tester,
    ) async {
      await montar(tester, tamano: telefono, valor: 'v1');

      await tester.tap(find.text('Vendedor 1'));
      await tester.pumpAndSettle();

      final marca = find.descendant(
        of: find.byType(Cajon),
        matching: find.byIcon(Icons.check),
      );
      expect(
        marca,
        findsOneWidget,
        reason:
            'sin la marca no hay forma de saber qué filtro está puesto: es lo '
            'que ya hacía el menú y no se puede perder al pasar a cajón',
      );
    });

    testWidgets('con cuarenta opciones se llega a la última desplazando', (
      tester,
    ) async {
      // El caso de Jose: un vendedor con cuarenta opciones. Un cajón que no
      // baja es PEOR que el menú de antes, porque el menú al menos tenía su
      // propia barra.
      final elegido = await montar(
        tester,
        tamano: telefono,
        opciones: vendedores(40),
      );

      await tester.tap(find.text('Todos los vendedores'));
      await tester.pumpAndSettle();

      final ultima = find.text('Vendedor 39');
      expect(ultima, findsOneWidget, reason: 'la última opción no se construyó');

      // Que esté en el árbol no es que se vea: al abrir tiene que estar POR
      // DEBAJO del borde de la pantalla, o esta prueba no está probando nada.
      expect(
        tester.getTopLeft(ultima).dy,
        greaterThan(telefono.height),
        reason:
            'las cuarenta opciones caben de golpe en 800 px: la prueba no '
            'prueba que se pueda desplazar',
      );

      await tester.ensureVisible(ultima);
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(ultima).dy,
        lessThan(telefono.height),
        reason:
            'la lista NO se desplazó: la última opción sigue fuera de la '
            'pantalla y es inalcanzable con el dedo',
      );

      await tester.tap(ultima);
      await tester.pumpAndSettle();
      expect(elegido, ['v39'], reason: 'se llegó a ella pero tocarla no hizo nada');
    });

    testWidgets('el buscador del cajón filtra, y lo que queda se puede elegir', (
      tester,
    ) async {
      final elegido = await montar(
        tester,
        tamano: telefono,
        opciones: vendedores(40),
      );

      await tester.tap(find.text('Todos los vendedores'));
      await tester.pumpAndSettle();

      final buscador = find.descendant(
        of: find.byType(Cajon),
        matching: find.byType(TextField),
      );
      expect(
        buscador,
        findsOneWidget,
        reason: 'con cuarenta opciones el buscador tiene que salir',
      );

      // Se escribe «17» y no «Vendedor 17» a propósito: lo que se teclea queda
      // dentro del `TextField`, y buscar el texto entero encuentra DOS —la
      // opción y lo escrito— y la prueba falla sin que nada esté mal.
      await tester.enterText(buscador, '17');
      await tester.pumpAndSettle();

      expect(find.text('Vendedor 17'), findsOneWidget);
      expect(find.text('Vendedor 18'), findsNothing, reason: 'no filtró');
      // LA SALIDA SE QUEDA, Y ESO CAMBIÓ EL 28/09/2026.
      //
      // Antes esta prueba exigía que sólo hubiera UNA —la del botón de fuera—,
      // porque el buscador se llevaba «Todos los vendedores» como a cualquier
      // otra opción. Y eso era el fallo: la primera opción es la que DESHACE el
      // filtro, así que al escribir desaparecía justo la salida, y para volver
      // atrás había que borrar lo escrito y darse cuenta de que era eso.
      //
      // Ahora son DOS: la del botón de fuera y la de dentro del cajón, que se
      // queda pase lo que pase.
      expect(
        find.text('Todos los vendedores'),
        findsNWidgets(2),
        reason:
            'la opción que DESHACE el filtro no se la puede llevar el buscador: '
            'es la salida, y desaparece justo cuando hace falta',
      );

      await tester.tap(find.text('Vendedor 17'));
      await tester.pumpAndSettle();
      expect(elegido, ['v17']);
    });

    testWidgets('abrir el cajón encima de una lista larga no revienta', (
      tester,
    ) async {
      // El choque de desplazamientos, otra vez y en el sitio nuevo: el cuerpo
      // del cajón es un `SingleChildScrollView` y en móvil se engancha solo al
      // `PrimaryScrollController` de la pantalla, que es el mismo del `ListView`
      // de debajo.
      await montar(tester, tamano: telefono, opciones: vendedores(40));

      await tester.tap(find.text('Todos los vendedores'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'abrir el cajón sobre una lista desplazable reventó: dos '
            '`ScrollPosition` colgando del mismo `PrimaryScrollController`',
      );
    });
  });

  group('el calendario', () {
    Future<List<DateTime>> montar(
      WidgetTester tester, {
      required Size tamano,
    }) async {
      anchoDe(tester, tamano);
      final elegido = <DateTime>[];
      await tester.pumpWidget(
        pantalla(
          CampoDeFecha(
            titulo: 'Desde (fecha del pedido)',
            valor: null,
            // El «hoy» entra por parámetro y no del reloj del sistema: dos
            // relojes son dos «hoy» distintos y la prueba cambiaría de mes sola
            // al pasar la medianoche.
            hoy: DateTime(2026, 9, 28),
            alElegir: elegido.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return elegido;
    }

    testWidgets('a 390 px se abre un CAJÓN', (tester) async {
      await montar(tester, tamano: telefono);

      await tester.tap(find.text('Desde (fecha del pedido)'));
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsOneWidget,
        reason:
            'en el teléfono el calendario tiene que salir en cajón: el panel '
            'de 320x340 se sale por el lado y tapa la tabla que se venía a '
            'filtrar, sin ninguna ✕ con la que salir',
      );
      expect(
        find.byType(CalendarDatePicker),
        findsOneWidget,
        reason: 'el cajón se abrió sin calendario dentro',
      );
    });

    testWidgets('a 1200 px el calendario TAMBIÉN es cajón', (tester) async {
      // La gemela de la del desplegable, y por el mismo motivo: hasta el
      // 28/09/2026 esto afirmaba que en escritorio el calendario seguía en su
      // menú anclado. Lo que NO ha cambiado es el descarte de
      // `showDatePicker` —el modal centrado que el pliego no quiere—: lo que se
      // abre es el cajón de la casa, con su cabecera y su ✕.
      await montar(tester, tamano: escritorio);

      await tester.tap(find.text('Desde (fecha del pedido)'));
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsOneWidget,
        reason: 'a 1200 px volvió a salir el menú flotante del calendario',
      );
      expect(
        find.byType(CalendarDatePicker),
        findsOneWidget,
        reason: 'el cajón se abrió pero sin el calendario dentro',
      );
    });

    testWidgets('en el cajón la ✕ está, y cierra sin poner fecha', (
      tester,
    ) async {
      final elegido = await montar(tester, tamano: telefono);

      await tester.tap(find.text('Desde (fecha del pedido)'));
      await tester.pumpAndSettle();

      final equis = find.descendant(
        of: find.byType(Cajon),
        matching: find.byTooltip('Cerrar'),
      );
      expect(equis, findsOneWidget, reason: 'la ✕ de cerrar no está');

      await tester.tap(equis);
      await tester.pumpAndSettle();

      expect(find.byType(Cajon), findsNothing);
      expect(
        elegido,
        isEmpty,
        reason: 'cerrar el calendario sin tocar un día puso una fecha',
      );
      expect(find.text(marcaDeLaPantalla), findsOneWidget);
    });

    testWidgets('tocar un día avisa, cierra el cajón y no cierra la pantalla', (
      tester,
    ) async {
      final elegido = await montar(tester, tamano: telefono);

      await tester.tap(find.text('Desde (fecha del pedido)'));
      await tester.pumpAndSettle();

      // Septiembre de 2026, día 15. Los días se pintan como texto suelto.
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      expect(
        elegido,
        [DateTime(2026, 9, 15)],
        reason: 'tocar un día en el cajón no devolvió la fecha',
      );
      expect(
        find.byType(Cajon),
        findsNothing,
        reason:
            'el cajón se quedó abierto tapando la lista que se acababa de '
            'filtrar',
      );
      expect(
        find.text(marcaDeLaPantalla),
        findsOneWidget,
        reason: 'LA PANTALLA DE DEBAJO SE CERRÓ al elegir el día',
      );
    });

    testWidgets('dentro del cajón se puede abrir la lista de años', (
      tester,
    ) async {
      // Ésta es la trampa del sitio nuevo. La lista de años es un desplazable
      // vertical sin controlador propio; el cuerpo del cajón es otro, y en
      // móvil los dos se enganchan solos al mismo `PrimaryScrollController`.
      // Flutter lo corta en seco: «The PrimaryScrollController is attached to
      // more than one ScrollPosition». El menú ya lo tenía cortado con
      // `PrimaryScrollController.none`; el cajón lo necesita igual.
      await montar(tester, tamano: telefono);

      await tester.tap(find.text('Desde (fecha del pedido)'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.byIcon(Icons.arrow_drop_down),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'abrir la lista de años dentro del cajón reventó: falta cortar la '
            'herencia del `PrimaryScrollController`',
      );
      expect(
        find.text('2026'),
        findsWidgets,
        reason: 'la lista de años no llegó a salir',
      );
    });

    testWidgets('Escape cierra el cajón sin poner fecha', (tester) async {
      // Lo mismo que hacía el menú, y que §9.2 pide de todo lo que tape:
      // Escape cierra. Lo da el `ModalBarrier` del cajón.
      final elegido = await montar(tester, tamano: telefono);

      await tester.tap(find.text('Desde (fecha del pedido)'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(Cajon), findsNothing);
      expect(elegido, isEmpty);
    });
  });

  test('el corte sale de `Anchos.escritorio`, no de un número a mano', () {
    // Si alguien cambia el corte, que lo cambie en un sitio y se entere de que
    // estas pruebas miden a los dos lados de ÉL.
    expect(telefono.width, lessThan(Anchos.escritorio));
    expect(escritorio.width, greaterThanOrEqualTo(Anchos.escritorio));
  });
}
