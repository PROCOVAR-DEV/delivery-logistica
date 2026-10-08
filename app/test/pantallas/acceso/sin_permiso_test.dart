// LA PANTALLA «NO TIENES PERMISO PARA ENTRAR A REPARTO» y cómo se llega a ella.
//
// Jose, 08/10/2026: «a los que no tienen permiso Reparto les diga no tienes permiso y que
// se dirijan a Accesos, a su inicio con la ruta rápida».
//
// En pareja (CLAUDE.md §5): web y aparato, permitido y no permitido. La única diferencia
// entre las dos mitades de cada pareja es el destino o el estado, nunca otra cosa.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/aviso_de_version_nueva.dart'
    show abridorDeLaDescargaProvider;
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_sin_permiso.dart';

import '../../apoyo/apoyo_accesos.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

/// Un portero al que se le dice el estado, sin arrancar nada.
class _PorteroFalso extends Portero {
  _PorteroFalso(super.ref, this._estado);

  EstadoDeAcceso _estado;
  int salidas = 0;

  @override
  EstadoDeAcceso get estado => _estado;

  void ponerEstado(EstadoDeAcceso nuevo) {
    _estado = nuevo;
    notifyListeners();
  }

  @override
  Future<void> salir() async => salidas++;
}

void main() {
  // El inicio de Accesos, ESCRITO a mano: una prueba que copia la dirección del código
  // que prueba no comprueba la dirección (CLAUDE.md §5). Es `AUTH_URL` por defecto + `/`.
  const inicioDeAccesosEsperado = 'https://auth.procovar.cloud/';

  late NavegadorFalso navegador;
  late List<String> abiertos;
  late _PorteroFalso portero;

  Future<void> montar(
    WidgetTester tester, {
    required bool enWeb,
    EstadoDeAcceso estado = EstadoDeAcceso.sinPermiso,
    int pendientes = 0,
    bool conRouter = false,
  }) async {
    // Teléfono de 390 px: el caso que importa.
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    navegador = NavegadorFalso();
    abiertos = <String>[];
    final base = baseDePrueba();
    addTearDown(base.close);
    // Sembrado DENTRO del cuerpo (CLAUDE.md §5).
    final cola = ColaDeSalida(
      base,
      reloj: RelojFalso(DateTime(2026, 10, 8)).leer,
    );
    for (var i = 0; i < pendientes; i++) {
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-$i',
        cuerpo: <String, Object?>{'status': 'completed'},
      );
    }

    final contenedor = ProviderContainer(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(!enWeb),
        baseProvider.overrideWithValue(base),
        navegadorProvider.overrideWithValue(navegador),
        abridorDeLaDescargaProvider.overrideWithValue(
          (enlace) async => abiertos.add(enlace),
        ),
        porteroProvider.overrideWith((ref) => _PorteroFalso(ref, estado)),
      ],
    );
    addTearDown(contenedor.dispose);
    portero = contenedor.read(porteroProvider) as _PorteroFalso;

    final Widget app;
    if (conRouter) {
      final enrutador = crearEnrutador(
        portero: portero,
        pantallas: [
          PantallaRegistrada(
            ruta: '/dashboard',
            titulo: 'Panel',
            conArmazon: false,
            colecciones: ColeccionesDePantalla.ninguna,
            construir: (c, e) => const Text('PANEL DE MENTIRA'),
          ),
          // Nunca se visita: el `ShellRoute` no admite cero rutas dentro.
          PantallaRegistrada(
            ruta: '/orders',
            titulo: 'Pedidos',
            colecciones: ColeccionesDePantalla.ninguna,
            construir: (c, e) => const Text('PEDIDOS DE MENTIRA'),
          ),
        ],
      );
      addTearDown(enrutador.dispose);
      app = MaterialApp.router(routerConfig: enrutador);
    } else {
      app = const MaterialApp(home: Scaffold(body: PantallaSinPermiso()));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(container: contenedor, child: app),
    );
    await tester.pump();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  final titulo = find.text('No tienes permiso para entrar a Reparto');
  final explicacion = find.textContaining(
    'Reparto es para el personal de logística y la administración. '
    'Si crees que es un error, pídele acceso a un administrador.',
  );

  group('en la WEB: se va sola a Accesos', () {
    testWidgets('enseña el texto, el contador y el botón, y NO el cierre de '
        'sesión', (tester) async {
      await montar(tester, enWeb: true);

      expect(titulo, findsOneWidget);
      expect(explicacion, findsOneWidget);
      expect(find.textContaining('en 3 s'), findsOneWidget);
      expect(find.text('Ir ahora a Accesos'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsNothing);
      expect(navegador.visitados, isEmpty, reason: 'todavía no se ha ido');
      await desmontar(tester);
    });

    testWidgets('a los 3 s va al INICIO de Accesos (AUTH_URL + «/»), una vez', (
      tester,
    ) async {
      await montar(tester, enWeb: true);

      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('en 2 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('en 1 s'), findsOneWidget);
      expect(navegador.visitados, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(navegador.visitados, [inicioDeAccesosEsperado]);

      await tester.pump(const Duration(seconds: 10));
      expect(navegador.visitados, hasLength(1), reason: 'no insiste');
      await desmontar(tester);
    });

    testWidgets('«Ir ahora a Accesos» va al instante, y el reloj no vuelve a '
        'mandarlo', (tester) async {
      await montar(tester, enWeb: true);

      await tester.tap(find.text('Ir ahora a Accesos'));
      await tester.pump();
      expect(navegador.visitados, [inicioDeAccesosEsperado]);

      await tester.pump(const Duration(seconds: 10));
      expect(navegador.visitados, hasLength(1));
      await desmontar(tester);
    });
  });

  group('accesibilidad de la web', () {
    testWidgets('la salida sola se ANUNCIA una vez y el contador no habla cada '
        'segundo', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, enWeb: true);

      final anuncio = find.bySemanticsLabel(
        'Te llevamos al inicio de Accesos en unos segundos',
      );
      expect(anuncio, findsOneWidget);
      expect(
        tester.getSemantics(anuncio),
        isSemantics(isLiveRegion: true),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'en \d s')),
        findsNothing,
        reason:
            'el contador visual va en ExcludeSemantics: «3, 2, 1» no se lee',
      );
      expect(find.bySemanticsLabel('Ir ahora a Accesos'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel(RegExp(r'en \d s')), findsNothing);
      await desmontar(tester);
      semantica.dispose();
    });

    testWidgets('PAREJA: en el aparato no hay anuncio (no se va sola)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, enWeb: false);

      expect(
        find.bySemanticsLabel(
          'Te llevamos al inicio de Accesos en unos segundos',
        ),
        findsNothing,
      );
      await desmontar(tester);
      semantica.dispose();
    });
  });

  group('en la APK y el escritorio: NO hay redirección automática', () {
    testWidgets('botones «Ir a Accesos» y «Cerrar sesión», sin contador', (
      tester,
    ) async {
      await montar(tester, enWeb: false);

      expect(titulo, findsOneWidget);
      expect(explicacion, findsOneWidget);
      expect(find.text('Ir a Accesos'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.textContaining(' s…'), findsNothing);
      expect(find.text('Ir ahora a Accesos'), findsNothing);

      await tester.pump(const Duration(seconds: 30));
      expect(navegador.visitados, isEmpty, reason: 'no se va sola');
      expect(abiertos, isEmpty);
      await desmontar(tester);
    });

    testWidgets('«Ir a Accesos» abre el inicio de Accesos en el navegador del '
        'sistema', (tester) async {
      await montar(tester, enWeb: false);

      await tester.tap(find.text('Ir a Accesos'));
      await tester.pump();

      expect(abiertos, [inicioDeAccesosEsperado]);
      expect(navegador.visitados, isEmpty);
      await desmontar(tester);
    });

    testWidgets('«Cerrar sesión» sin trabajo pendiente sale directo', (
      tester,
    ) async {
      await montar(tester, enWeb: false);

      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(portero.salidas, 1);
      await desmontar(tester);
    });

    testWidgets('«Cerrar sesión» CON apuntes sin subir pregunta, y «Me quedo» '
        'no sale', (tester) async {
      await montar(tester, enWeb: false, pendientes: 2);

      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Queda trabajo sin subir'), findsOneWidget);
      expect(find.textContaining('Hay 2 apuntes sin subir'), findsOneWidget);
      expect(find.textContaining('Salir NO los borra'), findsOneWidget);
      expect(
        find.textContaining(
          'Suben cuando te den acceso a Reparto y vuelvas a entrar.',
        ),
        findsOneWidget,
        reason: 'la cola es de ESTA persona: suben cuando le den acceso',
      );
      expect(find.textContaining('con esta no'), findsNothing);
      expect(portero.salidas, 0);

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      expect(portero.salidas, 0, reason: 'se quedó');

      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir de todos modos'));
      await tester.pumpAndSettle();
      expect(portero.salidas, 1);
      await desmontar(tester);
    });
  });

  group('cómo se llega: desde cualquier pantalla, y un permitido NUNCA', () {
    testWidgets('con permiso (dentro) se ve la pantalla de siempre y jamás la '
        'del permiso', (tester) async {
      await montar(
        tester,
        enWeb: false,
        estado: EstadoDeAcceso.dentro,
        conRouter: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('PANEL DE MENTIRA'), findsOneWidget);
      expect(titulo, findsNothing);
      await desmontar(tester);
    });

    testWidgets('sin permiso, estando en OTRA pantalla, salta a /sin-permiso', (
      tester,
    ) async {
      await montar(
        tester,
        enWeb: false,
        estado: EstadoDeAcceso.dentro,
        conRouter: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('PANEL DE MENTIRA'), findsOneWidget);

      // Lo que hace el interceptor al ver el 403, en mitad de lo que se estuviera
      // haciendo.
      portero.ponerEstado(EstadoDeAcceso.sinPermiso);
      await tester.pumpAndSettle();

      expect(titulo, findsOneWidget);
      expect(find.text('PANEL DE MENTIRA'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('arrancar ya sin permiso (carga inicial) cae en la pantalla', (
      tester,
    ) async {
      await montar(tester, enWeb: false, conRouter: true);
      await tester.pumpAndSettle();

      expect(titulo, findsOneWidget);
      expect(find.text('PANEL DE MENTIRA'), findsNothing);
      await desmontar(tester);
    });
  });

  group('el redirector del portero', () {
    String? donde(String ruta, EstadoDeAcceso estado, {String? volverA}) =>
        redirigir(
          rutaActual: ruta,
          estado: estado,
          inicio: rutaDeInicio,
          uriEntera: ruta,
          volverA: volverA,
        );

    test('sin permiso: cualquier ruta (incluidas las puertas) va a '
        '/sin-permiso, y ella se queda', () {
      for (final ruta in ['/dashboard', '/orders?x=1', rutaDeArranque]) {
        expect(
          donde(ruta, EstadoDeAcceso.sinPermiso),
          rutaDeSinPermiso,
          reason: ruta,
        );
      }
      expect(donde(rutaDeSinPermiso, EstadoDeAcceso.sinPermiso), isNull);
    });

    test('PAREJA: con sesión normal nadie va a /sin-permiso, y quien está allí '
        'sale al inicio', () {
      expect(donde('/dashboard', EstadoDeAcceso.dentro), isNull);
      expect(donde(rutaDeAcceso, EstadoDeAcceso.dentro), rutaDeInicio);
      expect(donde(rutaDeSinPermiso, EstadoDeAcceso.dentro), rutaDeInicio);
      expect(
        donde(
          rutaDeSinPermiso,
          EstadoDeAcceso.dentro,
          volverA: rutaDeSinPermiso,
        ),
        rutaDeInicio,
      );
    });

    test('cerrar sesión desde allí lleva al acceso, no a un bucle', () {
      expect(donde(rutaDeSinPermiso, EstadoDeAcceso.fuera), rutaDeAcceso);
    });

    test(
      'un ciclo no sincroniza estando sin permiso (la cola se queda quieta)',
      () {
        expect(haySesionParaSincronizar(EstadoDeAcceso.sinPermiso), isFalse);
        expect(haySesionParaSincronizar(EstadoDeAcceso.dentro), isTrue);
      },
    );
  });
}
