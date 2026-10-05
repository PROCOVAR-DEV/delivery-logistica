// EL GESTO DE ATRÁS NO SACA DE LA APLICACIÓN SIN PREGUNTAR.
//
// Jose, 05/10/2026, probando la 1.0.22 en el teléfono:
//
//     «cuando salga de la aplicacion por el gesto de dar atras por favor q me
//      salga un mensaje q se va a salir ook algo asi como estas seguro q
//      queires salir y si se pierde algo o no por salir esas cosas las
//      necesito»
//     «revisa q no quiero 50 veces despliegues por errores tuyos y esto no
//      funcione haslo bien a la primera revisa q ya nos ah pasado antes creo q
//      con retenless y el gesto de atras sigue sin sacarnos el cartel»
//
// Esa última frase es el encargo de verdad, y es por lo que estas pruebas
// existen: lo que hay que demostrar no es que el cartel salga, es que **sale
// SÓLO cuando el atrás iba a cerrar la aplicación**. Las tres formas de
// equivocarse, y hay una prueba por cada una:
//
//   1. Con un `PopScope` —que es lo primero que uno escribe— el cartel sale
//      también con la ✕ de cualquier cajón y con cualquier `Cancelar`, porque
//      `PopScope` se come todos los `Navigator.maybePop()` de la casa. Eso ya
//      está escrito en `diseno/cajon.dart` y es justo lo que Jose recordaba.
//   2. Sin mirar si hay algo que cerrar, el primer atrás con un cajón abierto
//      pregunta si quieres salir **por encima del cajón**.
//   3. Y la del lado contrario: si el cartel no se pone en el camino del atrás,
//      la aplicación se cierra y el cartel se queda sin ver — que es el estado
//      en el que estaba la 1.0.22.
//
// ## Los dos montajes
//
//   * **`montar`** es el de verdad: `MaterialApp.router` con go_router y la
//     pieza envolviendo al `ShellRoute`, igual que en `navegacion/armazon.dart`.
//     Con un `MaterialApp` normal el atrás entra por otro sitio
//     (`WidgetsApp.didPopRoute`) y estas pruebas dirían que todo está bien
//     mientras en el teléfono no sale nada.
//   * El texto se prueba **suelto**, sin montar pantalla, porque es la mitad del
//     encargo («y si se pierde algo o no») y tiene cuatro casos que no merecen
//     cuatro árboles de widgets.
//
// `handlePopRoute()` es el gesto del teléfono: el mismo que usa
// `test/diseno/atras_en_el_cajon_test.dart`.

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/salir_con_el_gesto.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';

const telefono = Size(390, 800);

/// La pantalla de debajo, con un botón que abre un cajón de los de la casa.
class _Pantalla extends StatelessWidget {
  const _Pantalla();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PANTALLA'),
          TextButton(
            onPressed: () => abrirCajon<void>(
              context,
              titulo: 'Un cajón cualquiera',
              cuerpo: (_) => const Text('dentro del cajón'),
            ),
            child: const Text('abrir el cajón'),
          ),
          TextButton(
            onPressed: () => context.push('/panel/detalle'),
            child: const Text('entrar al detalle'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  late BaseLocal base;

  setUp(() => base = BaseLocal.con(NativeDatabase.memory()));
  tearDown(() => base.close());

  /// Lo que el sistema recibió por el canal de plataforma.
  ///
  /// `SystemNavigator.pop()` es la única forma que tiene la aplicación de
  /// cerrarse, así que es lo que hay que espiar para saber si se cerró: en una
  /// prueba no hay proceso que morir.
  late List<String> alSistema;

  setUp(() {
    alSistema = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (llamada) async {
          alSistema.add(llamada.method);
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  /// La aplicación como es: `MaterialApp.router`, go_router, y la pieza
  /// envolviendo al `ShellRoute` igual que en el armazón.
  Future<GoRouter> montar(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = telefono;
    addTearDown(tester.view.reset);

    final enrutador = GoRouter(
      initialLocation: '/panel',
      routes: [
        ShellRoute(
          builder: (_, _, hijo) => SalirConElGesto(child: hijo),
          routes: [
            GoRoute(
              path: '/panel',
              builder: (_, _) => const _Pantalla(),
              routes: [
                GoRoute(
                  path: 'detalle',
                  builder: (_, _) => const Scaffold(body: Text('DETALLE')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [baseProvider.overrideWithValue(base)],
        child: MaterialApp.router(
          theme: temaDeReparto(),
          routerConfig: enrutador,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PANTALLA'), findsOneWidget);
    return enrutador;
  }

  /// El atrás del sistema: el gesto del teléfono.
  ///
  /// `unawaited` Y NO `await`, y no es un detalle de estilo: el futuro de
  /// `handlePopRoute()` se cumple cuando la cadena del atrás **termina**, y aquí
  /// esa cadena se queda esperando a que una persona conteste el cartel. Con
  /// `await` la prueba no falla: **se cuelga para siempre**, que es lo peor que
  /// puede hacer una prueba (§5 del CLAUDE.md) — y se cuelga con el código bien,
  /// así que el rato que se pierde buscándolo es rato tirado.
  ///
  /// `test/diseno/atras_en_el_cajon_test.dart` sí lo espera, y está bien: allí
  /// los `onBackButtonPressed` contestan en el mismo instante y no abren nada.
  Future<void> atras(WidgetTester tester) async {
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  }

  /// Las consultas de Drift sueltan un temporizador al cancelarse y
  /// flutter_test lo comprueba ANTES de los `tearDown`.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> sembrarPendientes(int cuantos) async {
    final cola = ColaDeSalida(base);
    for (var i = 1; i <= cuantos; i++) {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/routes/r-$i/results',
        cuerpo: <String, Object?>{'n': i},
      );
    }
  }

  Future<void> sembrarRechazado(String motivo) async {
    final cola = ColaDeSalida(base);
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/board/move',
      cuerpo: const <String, Object?>{'pedido': 'X-2992'},
    );
    await cola.resolver(
      clave,
      ResultadoApunte(estado: EstadoResultado.rechazado, motivo: motivo),
    );
  }

  group('cuándo sale el cartel', () {
    testWidgets('sin nada que cerrar, el atrás pregunta y NO cierra la '
        'aplicación', (tester) async {
      await montar(tester);

      await atras(tester);

      expect(find.text('¿Salir de Reparto?'), findsOneWidget);
      expect(
        alSistema,
        isNot(contains('SystemNavigator.pop')),
        reason:
            'el cartel no sirve de nada si la aplicación ya se fue: es el '
            'estado en el que estaba la 1.0.22',
      );

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });

    testWidgets('con un cajón abierto, el atrás CIERRA EL CAJÓN y no pregunta '
        'si quieres salir', (tester) async {
      await montar(tester);
      await tester.tap(find.text('abrir el cajón'));
      await tester.pumpAndSettle();
      expect(find.byType(Cajon), findsOneWidget);

      await atras(tester);

      expect(
        find.text('¿Salir de Reparto?'),
        findsNothing,
        reason:
            'preguntar si quieres salir por encima de un cajón abierto es el '
            'fallo de no mirar si había algo que cerrar',
      );
      expect(find.byType(Cajon), findsNothing, reason: 'el cajón se cierra');
      expect(find.text('PANTALLA'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('la ✕ del cajón cierra el cajón y NO saca el cartel de salir', (
      tester,
    ) async {
      // Lo que esta prueba demuestra: que el cartel no se cuela por la puerta
      // de los `maybePop` de la casa, que es por donde se cierran la ✕ de todos
      // los cajones y todos los `Cancelar`.
      //
      // Lo que NO demuestra, y conviene decirlo: **no distingue un
      // `BackButtonListener` de un `PopScope`**. Se comprobó mutándolo el
      // 05/10/2026 y la mutación salió VERDE — un `PopScope` puesto AQUÍ, en el
      // armazón, se engancha a la página del `ShellRoute`, no a la ruta del
      // cajón, así que la ✕ del cajón no pasa por él. La advertencia de
      // `diseno/cajon.dart` sigue siendo cierta donde está escrita (dentro de la
      // misma ruta que se va a cerrar), pero no vale como guarda de esto.
      //
      // Ninguna prueba de este fichero los distingue. Ver el final.
      await montar(tester);
      await tester.tap(find.text('abrir el cajón'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Salir de Reparto?'), findsNothing);
      expect(find.byType(Cajon), findsNothing);
      expect(find.text('PANTALLA'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('dentro de una subruta, el atrás VUELVE y no pregunta si '
        'quieres salir', (tester) async {
      // Las pantallas del armazón tienen subrutas de verdad —`rutas.dart` las
      // registra con `routes: p.subrutas`— y entrar en una las APILA. Estando
      // dentro de una ficha el atrás es para volver, y si el cartel se colara
      // ahí la ficha se quedaría sin salida.
      //
      // Se escribió buscando separar `BackButtonListener` de `PopScope`, y NO lo
      // separa: se mutó el 05/10/2026 y siguió verde. Se queda igual, porque lo
      // que prueba hace falta de todos modos — pero no se le atribuye una guarda
      // que no tiene. Ver el final de este fichero.
      await montar(tester);
      await tester.tap(find.text('entrar al detalle'));
      await tester.pumpAndSettle();
      expect(find.text('DETALLE'), findsOneWidget);

      await atras(tester);

      expect(
        find.text('¿Salir de Reparto?'),
        findsNothing,
        reason:
            'estando dentro de una ficha, el atrás es para volver: preguntar '
            'si quieres salir de la aplicación ahí deja la ficha sin salida',
      );
      expect(find.text('DETALLE'), findsNothing);
      expect(find.text('PANTALLA'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('con el cartel delante, otro gesto lo cierra y TAMPOCO sale', (
      tester,
    ) async {
      // ESTO NO ES «pulsa atrás dos veces para salir», y es a propósito. Con el
      // cartel puesto hay algo que cerrar, así que el segundo gesto lo cierra —
      // y cerrar el cartel sin contestar es QUEDARSE. O sea: **con el gesto
      // solo no se sale nunca**; para salir hay que pulsar «Sí, salir».
      //
      // Es lo que pidió: un cartel, no un atajo. Y es la única forma en que el
      // cartel sirve de algo, porque el atrás repetido es precisamente el gesto
      // con el que uno se sale sin querer.
      await montar(tester);

      await atras(tester);
      expect(find.text('¿Salir de Reparto?'), findsOneWidget);

      await atras(tester);

      expect(find.text('¿Salir de Reparto?'), findsNothing);
      expect(find.text('PANTALLA'), findsOneWidget);
      expect(
        alSistema,
        isNot(contains('SystemNavigator.pop')),
        reason: 'el segundo gesto no se puede escapar por detrás del cartel',
      );

      await desmontar(tester);
    });

    testWidgets('dos gestos en el MISMO instante no apilan dos carteles', (
      tester,
    ) async {
      // La carrera de verdad, y la única forma de provocarla: los dos gestos
      // antes de que el árbol se asiente. Entre el gesto y el cartel hay un
      // `await` a la base —las dos cuentas— y en ese hueco todavía no hay nada
      // que cerrar, así que la comprobación de «¿hay algo que cerrar?» no sirve
      // de red y el segundo gesto apilaría un cartel encima del otro: contestar
      // «Me quedo» dejaría el de debajo puesto, y parece que la aplicación no
      // obedece.
      //
      // Con `pumpAndSettle` por medio esto NO se reproduce, que es lo que hacía
      // esta prueba cuando se escribió mal.
      await montar(tester);

      unawaited(tester.binding.handlePopRoute());
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();

      expect(
        find.text('¿Salir de Reparto?'),
        findsOneWidget,
        reason: 'un cartel, no dos',
      );

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      expect(
        find.text('¿Salir de Reparto?'),
        findsNothing,
        reason:
            'si quedó otro debajo, «Me quedo» no lo quita y la aplicación '
            'parece que no obedece',
      );
      await desmontar(tester);
    });
  });

  group('qué hace cada botón', () {
    testWidgets('«Sí, salir» cierra la aplicación', (tester) async {
      await montar(tester);
      await atras(tester);

      await tester.tap(find.text('Sí, salir'));
      await tester.pumpAndSettle();

      expect(alSistema, contains('SystemNavigator.pop'));
      await desmontar(tester);
    });

    testWidgets('«Me quedo» deja la pantalla donde estaba', (tester) async {
      await montar(tester);
      await atras(tester);

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();

      expect(find.text('¿Salir de Reparto?'), findsNothing);
      expect(find.text('PANTALLA'), findsOneWidget);
      expect(alSistema, isNot(contains('SystemNavigator.pop')));
      await desmontar(tester);
    });

    testWidgets('cerrar el cartel sin contestar es QUEDARSE', (tester) async {
      // Misma regla que al borrar: lo que no se pidió no se hace por un
      // descuido. `abrirCajon` devuelve `null` al tocar fuera o dar Escape.
      await montar(tester);
      await atras(tester);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Salir de Reparto?'), findsNothing);
      expect(find.text('PANTALLA'), findsOneWidget);
      expect(
        alSistema,
        isNot(contains('SystemNavigator.pop')),
        reason: 'cerrar el cartel no es contestar «sí»',
      );
      await desmontar(tester);
    });
  });

  group('el cartel dice lo que hay en el aparato', () {
    testWidgets('sin nada pendiente dice que no se pierde nada', (
      tester,
    ) async {
      await montar(tester);
      await atras(tester);

      expect(find.textContaining('No queda nada sin subir'), findsOneWidget);
      expect(find.textContaining('Salir no pierde nada'), findsOneWidget);

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });

    testWidgets('con la tarde sin subir dice CUÁNTOS y que no se borran', (
      tester,
    ) async {
      // MONTAR PRIMERO Y SEMBRAR DESPUÉS (§3-ter): el trabajo se acumula con la
      // pantalla delante, y una cuenta que sólo se mira al montar se queda
      // clavada en cero, que es el caso que hay que descartar.
      await montar(tester);
      await sembrarPendientes(7);

      await atras(tester);

      expect(find.textContaining('7 apuntes sin subir'), findsOneWidget);
      expect(find.textContaining('Salir no borra nada'), findsOneWidget);

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });

    testWidgets('un rechazado NO se cuenta como que va a subir solo', (
      tester,
    ) async {
      await montar(tester);
      await sembrarRechazado('Ese pedido ya está en una ruta');

      await atras(tester);

      expect(find.textContaining('el servidor rechazó'), findsOneWidget);
      expect(
        find.textContaining('NO suben solos'),
        findsOneWidget,
        reason:
            'prometerle a alguien que su trabajo está en camino cuando el '
            'servidor ya dijo que no es la mentira que cuesta el día',
      );
      expect(
        find.textContaining('1 apunte sin subir'),
        findsNothing,
        reason:
            'un rechazado no está esperando señal: está esperando a una '
            'persona',
      );

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // EL TEXTO, SUELTO. Es la mitad del encargo —«y si se pierde algo o no»— y la
  // que ya salió mal una vez: hasta el 17/09/2026 el aviso de cerrar sesión
  // amenazaba con «ese trabajo se pierde», y era mentira. Un aviso que amenaza
  // con perder lo que no se pierde se lee una vez, se comprueba que era mentira
  // y deja de leerse el día que dice la verdad.
  // ---------------------------------------------------------------------------
  group('el texto contesta «¿se pierde algo?»', () {
    test('con nada dentro, la respuesta es NO y se dice', () {
      final texto = textoDeSalir(pendientes: 0, rechazados: 0);
      expect(texto, contains('Salir no pierde nada'));
    });

    test('con trabajo dentro, la respuesta sigue siendo NO', () {
      final texto = textoDeSalir(pendientes: 3, rechazados: 0);
      expect(texto, contains('Salir no borra nada'));
      expect(texto, contains('3 apuntes sin subir'));
      expect(texto, contains('suben solos'));
      expect(
        texto,
        isNot(contains('se pierden')),
        reason: 'en la APK no se pierden, y decirlo gasta el aviso',
      );
    });

    test('un apunte va en singular', () {
      expect(
        textoDeSalir(pendientes: 1, rechazados: 0),
        contains('1 apunte sin subir'),
      );
      expect(
        textoDeSalir(pendientes: 2, rechazados: 0),
        contains('2 apuntes sin subir'),
      );
    });

    test('pendientes y rechazados se dicen por separado', () {
      final texto = textoDeSalir(pendientes: 4, rechazados: 2);
      expect(texto, contains('4 apuntes sin subir'));
      expect(texto, contains('suben solos'));
      expect(texto, contains('2 apuntes que el servidor rechazó'));
      expect(texto, contains('NO suben solos'));
    });

    test('sólo rechazados: no se habla de señal, se habla de decidir', () {
      final texto = textoDeSalir(pendientes: 0, rechazados: 1);
      expect(texto, contains('1 apunte que el servidor rechazó'));
      expect(texto, contains('decidas tú, en la bandeja'));
      expect(
        texto,
        isNot(contains('la próxima vez que abras con señal')),
        reason: 'un rechazado no sube por tener señal: ya tuvo su respuesta',
      );
    });

    test('EN LA WEB sí se pierde, y ahí el texto lo dice', () async {
      // §1 y §3-quinquies: en la web la cola es un sitio de paso, así que algo
      // dentro no es trabajo guardado — es un cambio que NO se pudo guardar. Es
      // el único sitio donde la respuesta honesta es SÍ.
      await Destino.comoSiFueraWeb(() async {
        expect(
          textoDeSalir(pendientes: 2, rechazados: 0),
          contains('se pierden'),
        );
        expect(
          textoDeSalir(pendientes: 0, rechazados: 0),
          contains('Cerrar no pierde nada'),
        );
      });
    });
  });

  // ---------------------------------------------------------------------------
  // QUE EL ARMAZÓN LO LLEVE PUESTO.
  //
  // Las pruebas de arriba demuestran que la pieza funciona; esto demuestra que
  // está ENCHUFADA, que es la otra mitad y la que se pierde al refactorizar. Y
  // se mira en el fuente a propósito: montar el `Armazon` de verdad arrastra el
  // portero, la barra superior, la franja de estado, el aviso de versión y la
  // bajada del día a una prueba que va de un cartel de dos botones.
  //
  // Esto NO prueba comportamiento, y conviene decirlo en vez de fingir que sí:
  // es una guarda contra que alguien quite la línea. Lo que hace la línea ya lo
  // prueban los widgets de arriba (la pieza) y Flutter (el `Scaffold`).
  // ---------------------------------------------------------------------------
  group('el armazón lo lleva enchufado', () {
    final fuente = File('lib/navegacion/armazon.dart').readAsStringSync();

    test('el armazón envuelve sus pantallas en SalirConElGesto', () {
      expect(
        fuente,
        contains('SalirConElGesto('),
        reason:
            'sin esto el gesto de atrás cierra la aplicación sin preguntar, '
            'que es lo que Jose vio en la 1.0.22',
      );
    });

    test('el arrastre desde el borde NO abre la barra lateral', () {
      // Jose: «cuando hago el gesto de ir atras en el movil me abre tambien el
      // side bar». El arrastre desde el borde del `Scaffold` y el gesto de atrás
      // de Android son el mismo gesto, y el sistema gana: en móvil la barra se
      // abre sólo con el botón de las tres rayas.
      expect(
        fuente,
        contains('drawerEnableOpenDragGesture: false'),
        reason:
            'con el arrastre puesto, ir hacia atrás abre el menú — son el '
            'mismo gesto',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // LO QUE ESTAS PRUEBAS NO CAZAN, dicho aquí para que nadie lo descubra tarde.
  //
  // Cambiar el `BackButtonListener` por un `PopScope(canPop: false)` **no pone
  // ninguna de estas veinte pruebas en rojo**. Se mutó dos veces el 05/10/2026 —
  // una con la prueba de la ✕ y otra añadiendo la de la subruta a propósito— y
  // las dos veces salió verde.
  //
  // El motivo: aquí el envoltorio está en la página del `ShellRoute`, y los
  // `maybePop` que preocupaban en `diseno/cajon.dart` son de OTRAS rutas —la del
  // cajón, la de la subruta—, así que no pasan por él. La advertencia de
  // `cajon.dart` es verdad donde está escrita y no se aplica a esta posición.
  //
  // Entonces, ¿por qué `BackButtonListener` y no `PopScope`? Por dos razones que
  // son de diseño y no de comportamiento medible, y por eso van escritas y no
  // fingidas como prueba:
  //
  //   1. `BackButtonListener` oye **sólo el atrás del sistema**, que es
  //      exactamente el alcance del encargo. `PopScope` habla de popear rutas, y
  //      su alcance depende de en qué ruta esté colgado: hoy coincide, y el día
  //      que el armazón se mueva (a `StatefulShellRoute`, por ejemplo) deja de
  //      coincidir sin que nada avise.
  //   2. Este proyecto ya tiene `PopScope` por pantalla —`cierre_de_ruta.dart` y
  //      `pantalla_rutas.dart`—, y apilar uno más arriba obliga a razonar cómo se
  //      combinan. El otro mecanismo no se mezcla con ésos.
  //
  // Si alguien lo cambia y todo sigue verde: no es que dé igual, es que estas
  // pruebas no miden esa diferencia.
  // ---------------------------------------------------------------------------
}
