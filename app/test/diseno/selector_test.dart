// EL DESPLEGABLE, que es la pieza que mas se usa de la aplicacion y no tenia ni
// una prueba.
//
// Sale en la barra superior tres veces —sucursal, idioma y moneda—, en los
// filtros de las siete pantallas y en los cuatro pasos del asistente de rutas.
// Si elegir no llama a `alElegir`, no falla nada: la pantalla se queda como
// estaba y parece que el toque no llego.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/selector.dart';

void main() {
  /// Monta un selector suelto y anota lo que elige.
  ///
  /// **A 1200 px a propósito.** El alto por defecto de una prueba de widget es
  /// 800x600, y 800 está POR DEBAJO de `Anchos.escritorio`: desde el 28/09/2026
  /// eso abre un cajón, no el menú. Estas cinco prueban el menú de escritorio,
  /// que es lo que probaban cuando se escribieron, así que se les fija el ancho
  /// en vez de dejarlo al azar del tamaño por defecto. El cajón del teléfono
  /// tiene las suyas en `en_el_telefono_son_cajones_test.dart`.
  Future<List<String>> montar(
    WidgetTester tester, {
    required List<OpcionSelector<String>> opciones,
    String? valor,
    bool siempreConBuscador = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    final elegido = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Selector<String>(
              opciones: opciones,
              valor: valor,
              etiquetaVacia: 'Todas las sucursales (8)',
              siempreConBuscador: siempreConBuscador,
              alElegir: elegido.add,
            ),
          ),
        ),
      ),
    );
    return elegido;
  }

  /// Las ocho de verdad, con la opcion «todas» delante, que es como la monta la
  /// barra superior.
  List<OpcionSelector<String>> lasOcho() => const [
    OpcionSelector<String>(valor: '', etiqueta: 'Todas las sucursales (8)'),
    OpcionSelector<String>(valor: 'cam', etiqueta: 'Camagüey', nota: 'CAM'),
    OpcionSelector<String>(valor: 'gr', etiqueta: 'Granma', nota: 'GR'),
    OpcionSelector<String>(valor: 'gto', etiqueta: 'Guantánamo', nota: 'GTO'),
    OpcionSelector<String>(valor: 'hol', etiqueta: 'Holguín', nota: 'HOL'),
    OpcionSelector<String>(valor: 'hab', etiqueta: 'La Habana', nota: 'HAB'),
    OpcionSelector<String>(valor: 'tun', etiqueta: 'Las Tunas', nota: 'TUN'),
    OpcionSelector<String>(
      valor: 'ss',
      etiqueta: 'Sancti Spíritus',
      nota: 'SS',
    ),
    OpcionSelector<String>(valor: 'stg', etiqueta: 'Santiago', nota: 'STG'),
  ];

  testWidgets('elegir una sucursal la devuelve', (tester) async {
    // EL CASO DE JOSE, con sus ocho sucursales: abre el desplegable del Tablero,
    // toca «Santiago» y no pasa nada.
    final elegido = await montar(tester, opciones: lasOcho());

    await tester.tap(find.text('Todas las sucursales (8)'));
    await tester.pumpAndSettle();
    expect(find.text('Santiago'), findsOneWidget, reason: 'el menu no abrio');

    // Santiago es la ULTIMA de las ocho y con el buscador puesto no cabe en los
    // 360 px de alto del menu: hay que bajar hasta ella. Que este en el arbol no
    // significa que se pueda tocar.
    await tester.ensureVisible(find.text('Santiago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Santiago'));
    await tester.pumpAndSettle();

    expect(
      elegido,
      ['stg'],
      reason:
          'tocar una sucursal tiene que devolverla: si no, la pantalla se queda '
          'como estaba y parece que el toque no llego',
    );
  });

  testWidgets('con buscador puesto, elegir SIGUE funcionando', (tester) async {
    // Con nueve opciones el buscador sale solo (`desdeCuantasBusca` = 4), y es
    // justo lo que se ve en la captura de Jose: la caja de «Buscar…» encima de
    // la lista. Lo que se comprueba aqui es que esa caja no se come el toque.
    final elegido = await montar(
      tester,
      opciones: lasOcho(),
      siempreConBuscador: true,
    );

    await tester.tap(find.text('Todas las sucursales (8)'));
    await tester.pumpAndSettle();
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'no salio el buscador',
    );

    await tester.tap(find.text('Holguín'));
    await tester.pumpAndSettle();

    expect(elegido, ['hol']);
  });

  testWidgets('buscar y elegir lo que queda', (tester) async {
    final elegido = await montar(
      tester,
      opciones: lasOcho(),
      siempreConBuscador: true,
    );

    await tester.tap(find.text('Todas las sucursales (8)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tun');
    await tester.pumpAndSettle();

    expect(find.text('Las Tunas'), findsOneWidget);
    expect(find.text('Santiago'), findsNothing, reason: 'el filtro no filtro');

    await tester.tap(find.text('Las Tunas'));
    await tester.pumpAndSettle();
    expect(elegido, ['tun']);
  });

  testWidgets('la opcion «todas» tambien se devuelve, y vale cadena vacia', (
    tester,
  ) async {
    // No es un caso de adorno: quien la monta traduce esa cadena vacia a `null`
    // (`barra_superior.dart`), y si no llegara, volver a «todas» seria
    // imposible una vez elegida una sucursal.
    final elegido = await montar(tester, opciones: lasOcho(), valor: 'stg');

    await tester.tap(find.text('Santiago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas las sucursales (8)').last);
    await tester.pumpAndSettle();

    expect(elegido, ['']);
  });

  testWidgets('cerrar sin elegir no elige nada', (tester) async {
    final elegido = await montar(tester, opciones: lasOcho());

    await tester.tap(find.text('Todas las sucursales (8)'));
    await tester.pumpAndSettle();
    // Escape cierra el menu, como pulsar fuera.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(elegido, isEmpty);
  });
}
