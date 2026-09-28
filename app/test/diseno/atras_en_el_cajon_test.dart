// EL «ATRÁS» CON UN CAJÓN ABIERTO ES DEL CAJÓN.
//
// Jose, 28/09/2026, con el asistente de nueva ruta delante:
//
//     «dar atras cuando estoy en un drawer no sale del drawer sigue trabajando
//      atras arregla eso tambien»
//     «y tiene q ir al paso anterior de el drawer»
//
// Son dos cosas:
//
//   1. con un cajón abierto, atrás CIERRA EL CAJÓN y no navega por detrás; y
//   2. si el cajón tiene pasos, atrás va al PASO ANTERIOR, y sólo cierra cuando
//      ya está en el primero.
//
// ## El montaje es `MaterialApp.router` con go_router, y no es un capricho
//
// La aplicación es `MaterialApp.router` (`lib/app.dart`) y todo el «atrás» pasa
// por ahí: el del teléfono entra por el `BackButtonDispatcher` del `Router`, y
// el del navegador **no entra por ningún lado** — cambia la dirección y ya. Con
// un `MaterialApp` normal la segunda mitad no existe y estas pruebas dirían que
// todo está bien mientras en la web el cajón se queda puesto encima de otra
// pantalla, que es literalmente lo que Jose estaba viendo.
//
// ## Hay DOS montajes, y cada uno prueba lo que el otro no puede
//
//   * **`montar`** apila dos rutas de verdad (`push('/detalle')` encima de
//     `/lista`). Es lo que hace comprobable «no se lleva la pantalla de debajo»:
//     con una sola ruta el `Navigator` se niega a dejar la pila vacía, así que un
//     `pop` de más no cierra nada y la prueba **sale verde sin serlo** — pasó el
//     28/09/2026 con los selectores.
//   * **`montarConArmazon`** monta el `ShellRoute` de
//     `lib/navegacion/rutas.dart`, que es donde vive el fallo del cambio de
//     dirección. Con las pantallas sueltas en la raíz, cambiar de dirección
//     rehace la pila de páginas y el cajón se cae solo: el fallo **no existe** y
//     la prueba pasa sin probar nada. Con el armazón la página no se toca y el
//     cajón sobrevive, que es lo que Jose veía.
//
// Cada guarda se prueba a 390 **y** a 1200 px: en este proyecto el cajón sale en
// los dos anchos (excepción aprobada el 05/09/2026) y un arreglo que sólo
// funcione en el teléfono deja el escritorio roto sin que nadie se entere.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:reparto/diseno/anchos.dart';
import 'package:reparto/diseno/cajon.dart';
// El OTRO cajón del proyecto, con prefijo porque los dos tienen una clase
// `Cajon` y un `abrirCajon`. Es el que usa el asistente de nueva ruta, y por eso
// el mecanismo se prueba también con él: si sólo se probara con el de `diseno/`,
// el día que se enganche en el asistente no habría nada que dijera si funciona.
import 'package:reparto/pantallas/pedidos/vista/kit.dart' as kit;

const telefono = Size(390, 800);
const escritorio = Size(1200, 900);

void anchoDe(WidgetTester tester, Size tamano) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = tamano;
  addTearDown(tester.view.reset);
}

/// Una pantalla cualquiera del enrutador, con sus dos botones de abrir.
class _Pantalla extends StatelessWidget {
  const _Pantalla(this.nombre);

  final String nombre;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PANTALLA $nombre'),
          TextButton(
            onPressed: () => abrirCajon<void>(
              context,
              titulo: 'Un cajón cualquiera',
              cuerpo: (_) => const Text('dentro'),
            ),
            child: const Text('abrir el cajón'),
          ),
          TextButton(
            onPressed: () =>
                abrirPanel<void>(context, (_) => const _AsistenteDeMentira()),
            child: const Text('abrir el asistente'),
          ),
          TextButton(
            // Con la puerta del kit, que es la que usa Rutas.
            onPressed: () => kit.abrirCajon<void>(
              context,
              (_) => const _AsistenteConElCajonDelKit(),
            ),
            child: const Text('abrir el asistente del kit'),
          ),
        ],
      ),
    ),
  );
}

/// El asistente de mentira: tres pasos dentro de un cajón.
///
/// Es de mentira **a propósito**. El mecanismo de los pasos no sabe nada del
/// asistente de nueva ruta: sólo pregunta «¿te queda paso atrás?» y, si la
/// respuesta es que sí, le pasa el gesto. Probarlo con el asistente de verdad
/// ataría esta prueba a los cuatro pasos, a sus sucursales y a su base local, y
/// dejaría sin probar lo único que hay aquí, que es el mecanismo.
class _AsistenteDeMentira extends StatefulWidget {
  const _AsistenteDeMentira();

  @override
  State<_AsistenteDeMentira> createState() => _AsistenteDeMentiraState();
}

class _AsistenteDeMentiraState extends State<_AsistenteDeMentira> {
  int _paso = 1;

  @override
  Widget build(BuildContext context) => AtrasDelCajon(
    quedaPasoAtras: _paso > 1,
    atras: () => setState(() => _paso -= 1),
    child: Cajon(
      titulo: 'Nueva Ruta',
      child: Column(
        children: [
          Text('PASO $_paso'),
          TextButton(
            onPressed: () => setState(() => _paso += 1),
            child: const Text('siguiente'),
          ),
          TextButton(
            onPressed: () => abrirCajon<void>(
              context,
              titulo: 'El pre-despacho',
              cuerpo: (_) => const Text('papel'),
            ),
            child: const Text('abrir otro cajón encima'),
          ),
        ],
      ),
    ),
  );
}

/// EL ARMAZÓN DE LA APLICACIÓN: un `ShellRoute` con las pantallas dentro.
///
/// Es la forma de `lib/navegacion/rutas.dart`, y **la forma importa**. Con las
/// pantallas sueltas en la raíz, cambiar de dirección rehace la pila de páginas
/// y el cajón —que cuelga de la página de debajo— se cae solo; con el armazón,
/// que es lo que hay de verdad, la página del armazón se queda en su sitio y el
/// cajón **sobrevive al cambio de pantalla**. Ése es el fallo, y con la forma
/// equivocada no existe.
/// El mismo asistente de mentira, pero con el `Cajon` de
/// `pantallas/pedidos/vista/kit.dart`, que es el que usa el asistente de nueva
/// ruta de verdad. Es la forma exacta que va a tener el enganche.
class _AsistenteConElCajonDelKit extends StatefulWidget {
  const _AsistenteConElCajonDelKit();

  @override
  State<_AsistenteConElCajonDelKit> createState() =>
      _AsistenteConElCajonDelKitState();
}

class _AsistenteConElCajonDelKitState
    extends State<_AsistenteConElCajonDelKit> {
  int _paso = 1;

  @override
  Widget build(BuildContext context) => AtrasDelCajon(
    quedaPasoAtras: _paso > 1,
    atras: () => setState(() => _paso -= 1),
    child: kit.Cajon(
      titulo: 'Nueva Ruta',
      cuerpo: Column(
        children: [
          Text('PASO DEL KIT $_paso'),
          TextButton(
            onPressed: () => setState(() => _paso += 1),
            child: const Text('siguiente'),
          ),
        ],
      ),
    ),
  );
}

GoRouter _conArmazon() => GoRouter(
  initialLocation: '/detalle',
  routes: [
    ShellRoute(
      builder: (_, _, hijo) => hijo,
      routes: [
        GoRoute(path: '/lista', builder: (_, _) => const _Pantalla('LISTA')),
        GoRoute(path: '/detalle', builder: (_, _) => const _Pantalla('DETALLE')),
      ],
    ),
  ],
);

/// DOS RUTAS APILADAS DE VERDAD, para poder ver el `pop` de más.
///
/// Con una sola el `Navigator` se niega a dejar la pila vacía y un `pop` de más
/// no cierra nada: la prueba sale verde sin serlo. Aquí se apila `/detalle`
/// encima de `/lista` con `push`, así que si algo popea de más, aparece
/// `PANTALLA LISTA` y se ve.
GoRouter _apiladas() => GoRouter(
  initialLocation: '/lista',
  routes: [
    GoRoute(path: '/lista', builder: (_, _) => const _Pantalla('LISTA')),
    GoRoute(path: '/detalle', builder: (_, _) => const _Pantalla('DETALLE')),
  ],
);

void main() {
  /// Monta la aplicación con las DOS rutas apiladas y devuelve el enrutador.
  Future<GoRouter> montar(WidgetTester tester, Size tamano) async {
    anchoDe(tester, tamano);
    final enrutador = _apiladas();
    await tester.pumpWidget(MaterialApp.router(routerConfig: enrutador));
    await tester.pumpAndSettle();
    // `unawaited`: el futuro de `push` se cumple cuando esa ruta se cierra, o
    // sea nunca dentro de esta prueba. Esperarlo la cuelga.
    unawaited(enrutador.push('/detalle'));
    await tester.pumpAndSettle();
    expect(find.text('PANTALLA DETALLE'), findsOneWidget);
    return enrutador;
  }

  /// Monta la aplicación con su armazón, parada en `/detalle`.
  Future<GoRouter> montarConArmazon(WidgetTester tester, Size tamano) async {
    anchoDe(tester, tamano);
    final enrutador = _conArmazon();
    await tester.pumpWidget(MaterialApp.router(routerConfig: enrutador));
    await tester.pumpAndSettle();
    expect(find.text('PANTALLA DETALLE'), findsOneWidget);
    return enrutador;
  }

  /// El «atrás» del sistema: lo mismo que el gesto del teléfono.
  Future<void> atras(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  group('un cajón sin pasos', () {
    for (final (nombre, tamano) in [
      ('390 px', telefono),
      ('1200 px', escritorio),
    ]) {
      testWidgets('a $nombre, atrás cierra el cajón y no navega por detrás', (
        tester,
      ) async {
        await montar(tester, tamano);

        await tester.tap(find.text('abrir el cajón'));
        await tester.pumpAndSettle();
        expect(find.byType(Cajon), findsOneWidget);

        await atras(tester);

        expect(
          find.byType(Cajon),
          findsNothing,
          reason:
              'atrás no cerró el cajón: se quedó puesto encima mientras la '
              'aplicación seguía trabajando por detrás',
        );
        expect(
          find.text('PANTALLA DETALLE'),
          findsOneWidget,
          reason:
              'atrás se llevó la pantalla de debajo además del cajón: es el '
              '`pop` de más',
        );
        expect(
          find.text('PANTALLA LISTA'),
          findsNothing,
          reason: 'se volvió a la pantalla anterior con el cajón abierto',
        );
      });
    }

    testWidgets('el atrás del NAVEGADOR (la dirección cambia) se lleva el cajón', (
      tester,
    ) async {
      // ESTE ES EL CASO QUE JOSE VIO, y el que ninguna prueba cazaba.
      //
      // En el navegador el botón de atrás **no dispara ningún `popRoute`**:
      // cambia la dirección. go_router repinta la pantalla de debajo con la
      // anterior y el cajón —que es una ruta sin página, fuera del historial
      // del navegador— se queda encima. Reproducido tal cual el 28/09/2026:
      // cajón abierto sobre `/detalle`, atrás del navegador, y quedaba el
      // cajón de `/detalle` flotando sobre `/lista`.
      final enrutador = await montarConArmazon(tester, telefono);

      await tester.tap(find.text('abrir el cajón'));
      await tester.pumpAndSettle();
      expect(find.byType(Cajon), findsOneWidget);

      enrutador.go('/lista');
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsNothing,
        reason:
            'la pantalla de debajo cambió y el cajón se quedó puesto encima: '
            'es el «no sale del drawer, sigue trabajando atrás» del '
            '28/09/2026',
      );
      expect(
        find.text('PANTALLA LISTA'),
        findsOneWidget,
        reason:
            'cerrar el cajón se llevó además la pantalla a la que se acababa '
            'de volver: es el `pop` de más. Al cerrar hay que sacar ESA ruta y '
            'nada más — un `pop` a ciegas se come lo que haya debajo.',
      );
    });

    testWidgets('cambiar sólo los filtros NO cierra el cajón', (tester) async {
      // La otra mitad, y sin ella el arreglo de arriba es peor que el fallo.
      //
      // Los filtros de las listas viajan en la dirección
      // (`/orders?municipio=…`), y en el teléfono hay cajones que existen justo
      // para cambiarlos. Si el cajón se cerrara con CUALQUIER cambio de
      // dirección, tocar un filtro dentro del cajón lo cerraría en la cara. Por
      // eso se mira el camino y no la dirección entera.
      final enrutador = await montarConArmazon(tester, telefono);

      await tester.tap(find.text('abrir el cajón'));
      await tester.pumpAndSettle();

      enrutador.go('/detalle?municipio=palma&vendedor=andy');
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsOneWidget,
        reason:
            'poner un filtro cerró el cajón desde el que se estaba poniendo: '
            'se está comparando la dirección entera en vez del camino',
      );
    });
  });

  group('un cajón CON pasos', () {
    /// Abre el asistente de mentira y lo deja en el paso 3.
    Future<GoRouter> enElPaso3(WidgetTester tester, Size tamano) async {
      final enrutador = await montar(tester, tamano);
      await tester.tap(find.text('abrir el asistente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('PASO 3'), findsOneWidget);
      return enrutador;
    }

    for (final (nombre, tamano) in [
      ('390 px', telefono),
      ('1200 px', escritorio),
    ]) {
      testWidgets('a $nombre, atrás va al paso anterior y no cierra nada', (
        tester,
      ) async {
        await enElPaso3(tester, tamano);

        await atras(tester);

        expect(
          find.text('PASO 2'),
          findsOneWidget,
          reason:
              'atrás no retrocedió un paso. Es lo que Jose pidió: «tiene q ir '
              'al paso anterior de el drawer»',
        );
        expect(
          find.byType(Cajon),
          findsOneWidget,
          reason:
              'atrás cerró el asistente entero estando en el paso 3, y con él '
              'todo lo que ya se había elegido',
        );
        expect(
          find.text('PANTALLA DETALLE'),
          findsOneWidget,
          reason: 'además se llevó la pantalla de debajo',
        );
      });
    }

    testWidgets('en el PRIMER paso, atrás cierra el cajón y sólo el cajón', (
      tester,
    ) async {
      // El final del camino. Un mecanismo que se queda con el atrás para
      // siempre deja a la gente encerrada en el paso 1 sin salida más que la ✕.
      await montar(tester, telefono);
      await tester.tap(find.text('abrir el asistente'));
      await tester.pumpAndSettle();
      expect(find.text('PASO 1'), findsOneWidget);

      await atras(tester);

      expect(
        find.byType(Cajon),
        findsNothing,
        reason:
            'en el primer paso ya no queda paso atrás: el cajón tiene que '
            'soltar el gesto y cerrarse, o se queda encerrado',
      );
      expect(
        find.text('PANTALLA DETALLE'),
        findsOneWidget,
        reason: 'cerrar el asistente se llevó la pantalla de debajo',
      );
      expect(
        find.text('PANTALLA LISTA'),
        findsNothing,
        reason: 'un `pop` de más: se cerró el cajón Y se navegó hacia atrás',
      );
    });

    testWidgets('la ✕ cierra el cajón ENTERO aunque queden pasos', (
      tester,
    ) async {
      // ESTA ES LA PRUEBA QUE DECIDE EL MECANISMO.
      //
      // Lo primero que uno prueba para quedarse con el atrás es un `PopScope`,
      // y con un `PopScope` esta prueba se cae: `PopScope` se engancha al
      // `popDisposition` de la ruta, así que se come TODOS los
      // `Navigator.maybePop()` de la casa — y la ✕ de la cabecera de los dos
      // cajones del proyecto cierra con `maybePop()`. La ✕ del asistente en el
      // paso 3 retrocedería un paso en vez de cerrar, y la ✕ es la única salida
      // garantizada cuando el teclado tapa media pantalla (§9.2).
      //
      // Por eso el gesto se caza en el `BackButtonDispatcher` del `Router`, que
      // es por donde entra sólo el atrás del sistema.
      await enElPaso3(tester, telefono);

      await tester.tap(
        find.descendant(
          of: find.byType(Cajon),
          matching: find.byTooltip('Cerrar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(Cajon),
        findsNothing,
        reason:
            'la ✕ retrocedió un paso en vez de cerrar: el mecanismo de los '
            'pasos se está comiendo los `maybePop` de la casa',
      );
      expect(find.text('PANTALLA DETALLE'), findsOneWidget);
    });

    testWidgets('con otro cajón encima, atrás cierra el de arriba', (
      tester,
    ) async {
      // El asistente de verdad abre otro cajón desde dentro (la vista previa
      // del pre-despacho). Sin mirar quién está arriba, ese atrás retrocedería
      // un paso del asistente **por detrás** de un cajón que sigue puesto, que
      // es el mismo fallo de partida con otra cara.
      await enElPaso3(tester, telefono);

      await tester.tap(find.text('abrir otro cajón encima'));
      await tester.pumpAndSettle();
      expect(find.text('El pre-despacho'), findsOneWidget);

      await atras(tester);

      expect(
        find.text('El pre-despacho'),
        findsNothing,
        reason: 'atrás no cerró el cajón de arriba',
      );
      expect(
        find.text('PASO 3'),
        findsOneWidget,
        reason:
            'el asistente retrocedió un paso por detrás del cajón que estaba '
            'encima',
      );
    });

    testWidgets('sin `Router` en el árbol, el atrás sigue yendo al paso anterior', (
      tester,
    ) async {
      // La red de abajo. La aplicación es `MaterialApp.router`, pero un
      // `MaterialApp` normal no tiene `BackButtonDispatcher` que escuchar: allí
      // el atrás entra por `WidgetsApp.didPopRoute` → `maybePop`, y el único
      // sitio donde cazarlo es el `PopScope`. Sin esta rama, un cajón con pasos
      // montado en un árbol sin `Router` revienta al construirse.
      anchoDe(tester, telefono);
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/lista',
          routes: {
            '/': (_) => const Scaffold(body: Text('EL FONDO DE LA PILA')),
            '/lista': (_) => const _Pantalla('LISTA'),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('abrir el asistente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('PASO 2'), findsOneWidget);

      await atras(tester);

      expect(find.text('PASO 1'), findsOneWidget);
      expect(find.byType(Cajon), findsOneWidget);
      expect(
        find.text('EL FONDO DE LA PILA'),
        findsNothing,
        reason: 'el atrás se coló hasta el `Navigator` y navegó por detrás',
      );
    });
  });

  group('el mismo mecanismo con el `Cajon` del kit', () {
    // ES LA FORMA EXACTA DEL ASISTENTE DE NUEVA RUTA, que no usa el cajón de
    // `diseno/` sino el de `pantallas/pedidos/vista/kit.dart`. Estas dos pruebas
    // son las que dicen que la línea que falta por enganchar allí va a funcionar
    // —y sobre todo que no rompe la ✕, que en ese cajón cierra con `maybePop()`.
    Future<void> enElPaso3(WidgetTester tester) async {
      await montar(tester, telefono);
      await tester.tap(find.text('abrir el asistente del kit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('PASO DEL KIT 3'), findsOneWidget);
    }

    testWidgets('atrás va al paso anterior', (tester) async {
      await enElPaso3(tester);

      await atras(tester);

      expect(
        find.text('PASO DEL KIT 2'),
        findsOneWidget,
        reason:
            'con el cajón del kit el atrás no retrocedió un paso: cerró el '
            'asistente entero',
      );
      expect(find.byType(kit.Cajon), findsOneWidget);
    });

    testWidgets('y su ✕ sigue cerrando el cajón entero', (tester) async {
      // La ✕ del cajón del kit cierra con `Navigator.of(context).maybePop()`, y
      // ese fichero no se toca. Si el mecanismo de los pasos se colgara del
      // `popDisposition` de la ruta (un `PopScope`), esta ✕ retrocedería un
      // paso en vez de cerrar y la gente se quedaría sin la única salida
      // garantizada con el teclado abierto.
      await enElPaso3(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(kit.Cajon),
          matching: find.byTooltip('Cerrar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(kit.Cajon),
        findsNothing,
        reason:
            'la ✕ del cajón del kit retrocedió un paso en vez de cerrar: el '
            'mecanismo de los pasos se está comiendo los `maybePop` de la casa',
      );
      expect(find.text('PANTALLA DETALLE'), findsOneWidget);
    });
  });

  test('los dos anchos caen a los dos lados de `Anchos.escritorio`', () {
    expect(telefono.width, lessThan(Anchos.escritorio));
    expect(escritorio.width, greaterThanOrEqualTo(Anchos.escritorio));
  });
}
