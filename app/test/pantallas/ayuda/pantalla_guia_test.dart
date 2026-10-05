// LA GUIA, MONTADA. Lo que de verdad va a hacer el logistico de Santiago.
//
// Se monta con `MaterialApp.router` y go_router de verdad, y no con un
// `MaterialApp` a secas, por lo mismo que `test/diseno/atras_en_el_cajon_test.dart`:
// aqui lo que se prueba ES la direccion. El boton de «llévame ahí» cambia el camino
// y la vuelta tiene que encontrar la guia donde estaba, y eso no existe sin
// enrutador.
//
// Y a 390 px, que es el ancho del telefono donde se va a abrir.
//
// Las dos trampas del `CLAUDE.md` §5 no aplican aqui y conviene saber por que: esta
// pantalla **no toca la base local** —el manual viene de un asset— asi que no hay
// stream de Drift que esperar ni nada que sembrar en el `setUp`. Lo que si se hace
// es desmontar al final (`tester.pumpWidget(const SizedBox())`) para que el cajon no
// se quede abierto entre pruebas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/datos/proveedores.dart';
import 'package:reparto/pantallas/ayuda/vista/pantalla_guia.dart';

const telefono = Size(390, 800);

/// Las pantallas que «existen» en esta forma de mentira. **El canal con PEDIDO no
/// esta**, a proposito: es el caso real de una tarea cuyo sitio no se puede abrir
/// desde aqui.
const _pantallas = <PantallaDelMenu>[
  PantallaDelMenu('/vehicles', 'Vehículos'),
  PantallaDelMenu('/guia', 'Guía'),
];

final _paginas = <String, String>{
  'apk/3-tareas.md': '''
# Tareas sueltas

«Quiero hacer X»: dónde tocar, paso a paso.

## Dar de alta un camión

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

1. Toca **«Nuevo vehículo»**.
2. Escribe la matrícula.

## Mirar el canal con PEDIDO

**Empieza en:** **Menú → «Canal con PEDIDO»**.

1. Mira la cola.
''',
  'escritorio/3-tareas.md': '''
# Tareas del escritorio

## Entregar el día desde el ordenador

1. Pulsa en la franja de arriba.
''',
  'comun/pantallas/almacenes.md': '''
# Almacenes

La ficha de la pantalla de Almacenes.

## Poner o corregir un almacén

1. Abre la sucursal.
''',
};

final _idDelCamion = 'apk/3-tareas.md~dar-de-alta-un-camión';
final _idDelCanal = 'apk/3-tareas.md~mirar-el-canal-con-pedido';

/// La direccion de una tarea, con el id BIEN CODIFICADO.
///
/// Se arma con `Uri(...)`, igual que la aplicacion: el id lleva acentos y barras, y
/// escribir la direccion a mano en la prueba seria probar otra codificacion que la
/// de verdad.
String _direccionDeTarea(String id) =>
    Uri(path: PantallaGuia.ruta, queryParameters: {'tarea': id}).toString();

Manual _manualDePrueba(FormaDeLaAplicacion forma) => Manual.desdeElPaquete(
  empaquetarManual(_paginas),
  pantallas: _pantallas,
).paraLaForma(forma);

Future<void> _montar(
  WidgetTester tester, {
  String donde = PantallaGuia.ruta,
  FormaDeLaAplicacion forma = FormaDeLaAplicacion.apk,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = telefono;
  addTearDown(tester.view.reset);

  final enrutador = GoRouter(
    initialLocation: donde,
    routes: [
      GoRoute(
        path: PantallaGuia.ruta,
        // Sin `Scaffold` propio dentro de la pantalla: lo pone el armazon, igual
        // que en la aplicacion de verdad (`navegacion/rutas.dart`).
        builder: (_, _) => const Scaffold(body: PantallaGuia()),
      ),
      GoRoute(
        path: '/vehicles',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('AQUI ES VEHICULOS'))),
      ),
    ],
  );
  addTearDown(enrutador.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        formaDeLaAplicacionProvider.overrideWithValue(forma),
        manualProvider.overrideWith((ref) => _manualDePrueba(forma)),
      ],
      child: MaterialApp.router(routerConfig: enrutador),
    ),
  );
  await tester.pumpAndSettle();
  // Desmontar al final: si no, un cajon abierto se arrastra a la prueba siguiente.
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
}

void main() {
  /// LO PRIMERO QUE SE VE SON LAS TAREAS. Es lo que se consulta noventa y nueve
  /// veces de cada cien: alguien con el telefono en la mano y una duda concreta.
  testWidgets('al abrir la guia, lo primero son las TAREAS', (tester) async {
    await _montar(tester);

    expect(find.text('Dar de alta un camión'), findsOneWidget);
    expect(find.byKey(ClavesDeLaGuia.tarea(_idDelCamion)), findsOneWidget);

    // Y la otra puerta se ve, no esta escondida: «el documento completo está a un
    // toque, no escondido en un submenú de un submenú».
    expect(find.byKey(ClavesDeLaGuia.documento), findsOneWidget);
    expect(find.byKey(ClavesDeLaGuia.tareas), findsOneWidget);
  });

  testWidgets('la otra puerta ensena las paginas enteras', (tester) async {
    await _montar(tester);

    await tester.tap(find.byKey(ClavesDeLaGuia.documento));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ClavesDeLaGuia.pagina('comun/pantallas/almacenes.md')),
      findsOneWidget,
    );
    // Y las tareas ya no se listan: se cambio de puerta.
    expect(find.byKey(ClavesDeLaGuia.tarea(_idDelCamion)), findsNothing);
  });

  /// LA APK NO ENSENA LA GUIA DEL ESCRITORIO. Regla 1 de `CLAUDE.md`, vista desde
  /// la pantalla y no solo desde el modelo.
  testWidgets('cada forma ensena lo suyo, tambien en la pantalla', (
    tester,
  ) async {
    await _montar(tester);
    expect(find.text('Dar de alta un camión'), findsOneWidget);
    expect(find.text('Entregar el día desde el ordenador'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _montar(tester, forma: FormaDeLaAplicacion.escritorio);
    expect(find.text('Entregar el día desde el ordenador'), findsOneWidget);
    expect(find.text('Dar de alta un camión'), findsNothing);
  });

  /// EL BUSCADOR BUSCA EN LAS DOS Y DICE DE CUAL VIENE CADA RESULTADO. El ejemplo
  /// es el de Jose: «buscar “almacén” tiene que encontrar la tarea de poner el
  /// almacén **y** la ficha de la pantalla de Almacenes».
  testWidgets('buscar encuentra la tarea Y la pagina, y las distingue', (
    tester,
  ) async {
    await _montar(tester);

    await tester.enterText(find.byKey(ClavesDeLaGuia.buscar), 'almacen');
    // La caja busca sola a los 400 ms de dejar de teclear
    // (`diseno/caja_de_busqueda.dart`), no al pulsar Intro.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ClavesDeLaGuia.tarea('comun/pantallas/almacenes.md~poner-o-corregir-un-almacén'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(ClavesDeLaGuia.pagina('comun/pantallas/almacenes.md')),
      findsOneWidget,
    );
    // Y cada resultado dice de cual de las dos viene. «Almacenes» sale dos veces
    // —es el titulo de la pagina y es el «de donde» de la tarea—, asi que lo que
    // se comprueba son las insignias, no el texto.
    expect(find.text('Tarea'), findsOneWidget);
    expect(find.text('Página'), findsOneWidget);
    // Sin tilde se encuentra lo que la lleva: en un teclado de telefono nadie la
    // escribe.
  });

  testWidgets('lo que no esta se dice, y se dice como buscar mejor', (
    tester,
  ) async {
    await _montar(tester);

    await tester.enterText(find.byKey(ClavesDeLaGuia.buscar), 'xilofono');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Nada en la guía cuadra con «xilofono»'),
      findsOneWidget,
    );
  });

  group('una tarea, abierta', () {
    testWidgets('se abre en un cajon con sus pasos numerados', (tester) async {
      await _montar(tester);

      await tester.tap(find.byKey(ClavesDeLaGuia.tarea(_idDelCamion)));
      await tester.pumpAndSettle();

      // El titulo del cajon, y los pasos dentro.
      expect(find.text('Dar de alta un camión'), findsWidgets);
      expect(find.textContaining('Escribe la matrícula'), findsOneWidget);
      // Los numeros de los pasos, que es lo que hace que se sigan con el dedo.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // Y el renglon de «Empieza en» NO desaparece: lleva «Necesita señal», que
      // el boton no puede decir.
      expect(find.textContaining('Necesita señal'), findsOneWidget);
    });

    /// «LLÉVAME AHÍ»: el boton que convierte un manual en una guia.
    testWidgets('lleva a la pantalla de verdad', (tester) async {
      await _montar(tester);

      await tester.tap(find.byKey(ClavesDeLaGuia.tarea(_idDelCamion)));
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesDeLaGuia.llevameAhi), findsOneWidget);
      expect(find.text('Ir a Vehículos'), findsOneWidget);

      await tester.tap(find.byKey(ClavesDeLaGuia.llevameAhi));
      await tester.pumpAndSettle();

      expect(find.text('AQUI ES VEHICULOS'), findsOneWidget);
    });

    /// AL VOLVER, LA GUIA SIGUE DONDE ESTABA. La tarea abierta viaja en la
    /// direccion, asi que la vuelta del atras —del telefono o del navegador—
    /// vuelve a abrir el cajon por donde se iba. Sin esto, «llévame ahí» se paga
    /// buscando la tarea otra vez.
    testWidgets('abrir la direccion de una tarea abre su cajon', (tester) async {
      await _montar(tester, donde: _direccionDeTarea(_idDelCamion));

      expect(find.textContaining('Escribe la matrícula'), findsOneWidget);
      expect(find.byKey(ClavesDeLaGuia.llevameAhi), findsOneWidget);
    });

    /// LA PANTALLA QUE EN ESTA FORMA NO EXISTE SE DICE, no se calla ni se finge.
    /// El canal con PEDIDO solo se registra en la web; en un telefono un boton ahi
    /// llevaria a «No hay ninguna pantalla en /webhook».
    testWidgets('sin pantalla que abrir, se explica por que', (tester) async {
      await _montar(tester, donde: _direccionDeTarea(_idDelCanal));

      expect(find.textContaining('Mira la cola'), findsOneWidget);
      expect(find.byKey(ClavesDeLaGuia.llevameAhi), findsNothing);
      expect(
        find.textContaining('«Canal con PEDIDO» no existe en el teléfono'),
        findsOneWidget,
        reason:
            'sin esta linea el cajon se queda sin pie y nadie sabe por que esta '
            'tarea no tiene boton y la de arriba si',
      );
    });

    testWidgets('una tarea que no existe no deja la pantalla en blanco', (
      tester,
    ) async {
      // Pasa de verdad: un enlace guardado del telefono abierto en la web.
      await _montar(tester, donde: _direccionDeTarea('no/existe.md~x'));

      expect(find.text('Dar de alta un camión'), findsOneWidget);
    });
  });

  testWidgets('una pagina entera se abre en su cajon', (tester) async {
    await _montar(
      tester,
      donde: Uri(
        path: PantallaGuia.ruta,
        queryParameters: const {'pagina': 'comun/pantallas/almacenes.md'},
      ).toString(),
    );

    expect(
      find.textContaining('La ficha de la pantalla de Almacenes'),
      findsOneWidget,
    );
    // El documento oficial lleva sus `##` dentro: es la pagina entera.
    expect(find.text('Poner o corregir un almacén'), findsWidgets);
  });

  testWidgets('a 390 px no se sale nada por los bordes', (tester) async {
    await _montar(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(ClavesDeLaGuia.tarea(_idDelCamion)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
