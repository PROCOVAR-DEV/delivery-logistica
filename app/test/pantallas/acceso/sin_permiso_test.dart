// LA PANTALLA «NO TIENES PERMISO PARA ENTRAR A REPARTO» y cómo se llega a ella.
//
// Jose, 08/10/2026: «a los que no tienen permiso Reparto les diga no tienes permiso y que
// se dirijan a Accesos, a su inicio con la ruta rápida».
//
// En pareja (CLAUDE.md §5): web y aparato, permitido y no permitido. La única diferencia
// entre las dos mitades de cada pareja es el destino o el estado, nunca otra cosa.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/aviso_de_version_nueva.dart'
    show abridorDeLaDescargaProvider;
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/sincro/entrega_a_revision.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_sin_permiso.dart';
import 'package:reparto/nucleo/sincro/flujo_de_revision.dart'
    show sucesoAbierto;
import 'package:reparto/pantallas/acceso/vista/panel_de_entrega.dart'
    show abridorDeFlujoDeRevisionProvider, escuchaDeRevisionProvider;

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

/// La entrega, sin red: cuenta cuántas veces se la llamó y deja el estado en la cola
/// como lo haría la de verdad.
class _EntregaFalsa extends Fake implements EntregaARevision {
  _EntregaFalsa(this.cola);

  final ColaDeSalida cola;
  int entregas = 0;
  int consultas = 0;
  ResumenDeEntrega respuesta = const ResumenDeEntrega(
    ResultadoDeEntrega.entregado,
    entregados: 3,
  );

  @override
  Future<ResumenDeEntrega> entregar() async {
    entregas++;
    if (respuesta.resultado == ResultadoDeEntrega.entregado) {
      for (final a in await cola.lote()) {
        await cola.marcarEnRevision(a.clave, entrega: 'ent-1');
      }
    }
    return respuesta;
  }

  @override
  Future<ResumenDeConsulta> actualizarEstados() async {
    consultas++;
    return const ResumenDeConsulta(ResultadoDeEntrega.entregado);
  }

  /// Solo lo usa la escucha de verdad (`conEscucha`).
  @override
  Future<({Uri url, String token})?> paraElAvisoEnVivo() async => (
    url: Uri.parse('https://sync.test/revision/eventos?aparato=ap-1'),
    token: 'tok',
  );
}

void main() {
  // El inicio de Accesos, ESCRITO a mano: una prueba que copia la dirección del código
  // que prueba no comprueba la dirección (CLAUDE.md §5). Es `AUTH_URL` por defecto + `/`.
  const inicioDeAccesosEsperado = 'https://auth.procovar.cloud/';

  late NavegadorFalso navegador;
  late List<String> abiertos;
  late _PorteroFalso portero;
  late _EntregaFalsa entrega;
  late ColaDeSalida colaDeLaPrueba;

  /// Los flujos que la escucha de verdad ha abierto (`conEscucha`); la prueba los
  /// maneja a mano.
  late List<StreamController<String>> flujos;

  Future<void> montar(
    WidgetTester tester, {
    required bool enWeb,
    EstadoDeAcceso estado = EstadoDeAcceso.sinPermiso,
    int pendientes = 0,
    Future<void> Function(ColaDeSalida cola)? sembrar,
    bool conRouter = false,
    bool conEscucha = false,
  }) async {
    // Teléfono de 390 px: el caso que importa.
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    navegador = NavegadorFalso();
    abiertos = <String>[];
    flujos = <StreamController<String>>[];
    final base = baseDePrueba();
    addTearDown(base.close);
    // Sembrado DENTRO del cuerpo (CLAUDE.md §5).
    final cola = ColaDeSalida(
      base,
      reloj: RelojFalso(DateTime(2026, 10, 8, 14, 32)).leer,
    );
    colaDeLaPrueba = cola;
    entrega = _EntregaFalsa(cola);
    for (var i = 0; i < pendientes; i++) {
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-$i',
        cuerpo: <String, Object?>{'status': 'completed'},
      );
    }
    if (sembrar != null) await sembrar(cola);

    final contenedor = ProviderContainer(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(!enWeb),
        baseProvider.overrideWithValue(base),
        navegadorProvider.overrideWithValue(navegador),
        abridorDeLaDescargaProvider.overrideWithValue(
          (enlace) async => abiertos.add(enlace),
        ),
        porteroProvider.overrideWith((ref) => _PorteroFalso(ref, estado)),
        entregaARevisionProvider.overrideWithValue(entrega),
        if (conEscucha)
          // LA ESCUCHA DE VERDAD, con el flujo sustituido por un doble: ni un byte sale.
          abridorDeFlujoDeRevisionProvider.overrideWithValue((url, token) {
            final c = StreamController<String>();
            flujos.add(c);
            return c.stream;
          })
        else
          // UNA ESCUCHA «SIN SERVIDOR»: este fichero no va del aviso en vivo, y la de
          // verdad abriría el flujo en cuanto hay algo en revisión. El aviso en vivo
          // tiene el suyo (`aviso_en_vivo_de_revision_test.dart`); aquí solo se
          // comprueba que SIN él no hay sondeo (y, en la hermana de abajo, que CON él
          // abierto tampoco).
          escuchaDeRevisionProvider.overrideWithValue(null),
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
      expect(find.textContaining('Salir NO los borra: se quedan en este aparato'), findsOneWidget);
      // Lo que sustituye al viejo «Suben cuando te den acceso a Reparto y vuelvas a
      // entrar»: la misma verdad, dicha con la salida nueva delante. Sin entregar, nadie
      // ve ese trabajo y solo sube si devuelven el permiso.
      expect(
        find.textContaining('solo subirán si te devuelven el acceso a Reparto y vuelves a entrar'),
        findsOneWidget,
        reason: 'la cola es de ESTA persona: suben cuando le den acceso',
      );
      expect(find.textContaining('nadie los ve'), findsOneWidget);
      expect(portero.salidas, 0);

      await tester.tap(find.text('Me quedo'));
      await tester.pumpAndSettle();
      expect(portero.salidas, 0, reason: 'se quedó');
      expect(entrega.entregas, 0);
      await desmontar(tester);
    });
  });

  // LA BANDEJA DE REVISIÓN (`docs/bandeja-de-revision.md`, B.5 y N3).
  //
  // Quien pierde el permiso con cola ve su trabajo y puede ENTREGARLO a revisión; después
  // ve en qué está cada cosa. Todo en pareja (CLAUDE.md §3-quinquies): con cola sale, sin
  // cola NO; en el aparato sale, en la web NUNCA; entrega al pulsar, NUNCA antes.
  group('la bandeja de revisión', () {
    final entregar = find.text('Entregar a revisión');

    testWidgets('con cola: «Tienes N cambios sin enviar» y el botón; no entrega sola', (
      tester,
    ) async {
      await montar(tester, enWeb: false, pendientes: 3);
      await tester.pump(const Duration(seconds: 5));

      expect(
        find.textContaining('Tienes 3 cambios sin enviar. No se han perdido ni se han aplicado.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('un administrador de tu sucursal los mirará'),
        findsOneWidget,
      );
      expect(entregar, findsOneWidget);
      expect(
        entrega.entregas,
        0,
        reason: 'es una entrega MANUAL: son datos de alguien sin permiso y puede ser un error',
      );
      await desmontar(tester);
    });

    testWidgets('el botón es el principal, con su icono propio', (tester) async {
      await montar(tester, enWeb: false, pendientes: 1);
      expect(find.widgetWithText(FilledButton, 'Entregar a revisión'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(FilledButton, 'Entregar a revisión'),
          matching: find.byIcon(Icons.outbox),
        ),
        findsOneWidget,
      );
      await desmontar(tester);
    });

    testWidgets('SIN cola no sale nada: ni panel, ni botón, ni estados', (tester) async {
      await montar(tester, enWeb: false);

      expect(entregar, findsNothing);
      expect(find.textContaining('sin enviar'), findsNothing);
      expect(find.text('Actualizar estados'), findsNothing);
      expect(find.text('Ir a Accesos'), findsOneWidget, reason: 'lo de siempre sigue');
      await desmontar(tester);
    });

    testWidgets('en la WEB no sale NUNCA, aunque hubiera cola', (tester) async {
      await montar(
        tester,
        enWeb: true,
        pendientes: 3,
        sembrar: (cola) async {
          final clave = await cola.encolar(metodo: 'POST', ruta: '/routes', cuerpo: const {});
          await cola.marcarEnRevision(clave);
        },
      );

      expect(entregar, findsNothing);
      expect(find.textContaining('sin enviar'), findsNothing);
      expect(find.text('Actualizar estados'), findsNothing);
      expect(find.textContaining('Entregado a revisión'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('pulsar entrega UNA vez, dice cuántos y NO se va de /sin-permiso', (
      tester,
    ) async {
      await montar(tester, enWeb: false, pendientes: 3, conRouter: true);
      await tester.pumpAndSettle();

      await tester.tap(entregar);
      await tester.pumpAndSettle();

      expect(entrega.entregas, 1);
      expect(
        find.text('Entregado: 3 cambios están en revisión. Todavía no se ha aplicado nada.'),
        findsOneWidget,
      );
      expect(entregar, findsNothing, reason: 'ya no queda nada por entregar');
      expect(find.textContaining('Entregado a revisión el 8/10, 14:32.'), findsNWidgets(3));
      expect(titulo, findsOneWidget, reason: 'la pantalla no se movió');
      expect(find.text('PANEL DE MENTIRA'), findsNothing);
      expect(portero.salidas, 0);
      expect(navegador.visitados, isEmpty);
      expect(abiertos, isEmpty);
      await desmontar(tester);
    });

    testWidgets('lo que dice cada estado, con el literal de B.5', (tester) async {
      await montar(
        tester,
        enWeb: false,
        sembrar: (cola) async {
          Future<String> uno(String ruta) =>
              cola.encolar(metodo: 'POST', ruta: ruta, cuerpo: const {'a': 1});
          final espera = await uno('/routes/r-1/results');
          final fallida = await uno('/routes/r-2/results');
          final aplicada = await uno('/routes/r-3/results');
          final descartada = await uno('/routes');
          for (final c in [espera, fallida, aplicada, descartada]) {
            await cola.marcarEnRevision(c, entrega: 'ent-1');
          }
          await cola.resolverRevision(
            fallida,
            const DecisionDeRevision(
              estado: EstadoEnRevision.rechazado,
              motivo: 'Ese pedido ya va en otra ruta',
            ),
          );
          await cola.resolverRevision(
            aplicada,
            DecisionDeRevision(
              estado: EstadoEnRevision.aplicado,
              por: 'Marta Pérez',
              cuando: DateTime(2026, 10, 9, 9, 10),
            ),
          );
          await cola.resolverRevision(
            descartada,
            DecisionDeRevision(
              estado: EstadoEnRevision.descartado,
              por: 'Marta Pérez',
              cuando: DateTime(2026, 10, 9, 9, 12),
              motivo: 'Se rehízo en la web',
            ),
          );
        },
      );
      await tester.pump();

      expect(
        find.text(
          'Entregado a revisión el 8/10, 14:32. Todavía no está aplicado: un '
          'administrador de tu sucursal tiene que revisarlo.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('No se pudo aplicar: Ese pedido ya va en otra ruta. Sigue en revisión.'),
        findsOneWidget,
      );
      expect(find.text('Aplicado por Marta Pérez el 9/10, 9:10.'), findsOneWidget);
      expect(
        find.text('Descartado por Marta Pérez el 9/10: Se rehízo en la web.'),
        findsOneWidget,
      );
      expect(find.text('Resultados de entrega de una ruta'), findsNWidgets(3));
      expect(find.text('Ruta nueva'), findsOneWidget);
      expect(entregar, findsNothing, reason: 'no queda nada sin entregar');
      expect(find.text('Actualizar estados'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('«Actualizar estados» consulta UNA vez, y no hay sondeo', (tester) async {
      await montar(
        tester,
        enWeb: false,
        sembrar: (cola) async {
          final c = await cola.encolar(metodo: 'POST', ruta: '/routes', cuerpo: const {});
          await cola.marcarEnRevision(c);
        },
      );
      await tester.pump(const Duration(minutes: 10));
      expect(entrega.consultas, 0, reason: 'la conexión de allá se paga');

      await tester.tap(find.text('Actualizar estados'));
      await tester.pumpAndSettle();

      expect(entrega.consultas, 1);
      expect(find.text('Sin novedades.'), findsOneWidget);
      await desmontar(tester);
    });

    // La hermana de la de arriba, para que el nombre «no hay sondeo» siga vigilando la
    // pieza NUEVA: aquella corre con la escucha «sin servidor» (y por eso no vería un
    // temporizador metido en la escucha de verdad). Con el flujo abierto, la única
    // consulta que no pulsó nadie es la de apertura (ponerse al día: el servidor no
    // guarda eventos); el reloj no pregunta nada.
    group('no hay sondeo ni con la escucha de verdad abierta', () {
      Future<void> montarConAlgoEnRevision(WidgetTester tester) => montar(
        tester,
        enWeb: false,
        conEscucha: true,
        sembrar: (cola) async {
          final c = await cola.encolar(metodo: 'POST', ruta: '/routes', cuerpo: const {});
          await cola.marcarEnRevision(c);
        },
      );

      testWidgets('diez minutos de reloj sin eventos: ninguna consulta más que la de '
          'apertura', (tester) async {
        await montarConAlgoEnRevision(tester);
        await tester.pump(const Duration(milliseconds: 50));
        expect(flujos, hasLength(1), reason: 'la escucha de verdad abrió el flujo');
        expect(entrega.consultas, 0, reason: 'abierta la petición, aún sin `abierto`');

        flujos.single.add(sucesoAbierto);
        await tester.pump(const Duration(milliseconds: 50));
        expect(entrega.consultas, 1, reason: 'la de apertura');

        await tester.pump(const Duration(minutes: 10));

        expect(entrega.consultas, 1, reason: 'la conexión de allá se paga');
        expect(flujos, hasLength(1));
        await desmontar(tester);
      });

      testWidgets('PAREJA: si el flujo no llega a abrir, ni una consulta en diez '
          'minutos', (tester) async {
        await montarConAlgoEnRevision(tester);

        await tester.pump(const Duration(minutes: 10));

        expect(flujos, isNotEmpty);
        expect(entrega.consultas, 0);
        await desmontar(tester);
      });
    });

    group('cuando la entrega no sale', () {
      Future<void> pulsar(WidgetTester tester, ResumenDeEntrega r) async {
        await montar(tester, enWeb: false, pendientes: 2);
        entrega.respuesta = r;
        await tester.tap(entregar);
        await tester.pumpAndSettle();
      }

      testWidgets('sesión terminada: la frase y la salida correcta (entrar de nuevo)', (
        tester,
      ) async {
        await pulsar(
          tester,
          const ResumenDeEntrega(
            ResultadoDeEntrega.sesionTerminada,
            sinEntregar: 2,
            error: TextosDeEntrega.sesionTerminada,
          ),
        );

        expect(find.textContaining('Tu sesión terminó. No se puede entregar.'), findsOneWidget);
        expect(find.text('Cerrar sesión y entrar de nuevo'), findsOneWidget);
        expect(
          await colaDeLaPrueba.lote().then((l) => l.length),
          2,
          reason: 'la cola sigue en el aparato',
        );

        await tester.tap(find.text('Cerrar sesión y entrar de nuevo'));
        await tester.pumpAndSettle();
        expect(portero.salidas, 1);
        await desmontar(tester);
      });

      testWidgets('ya tiene permiso: lo dice y ofrece entrar de nuevo', (tester) async {
        await pulsar(
          tester,
          const ResumenDeEntrega(
            ResultadoDeEntrega.yaTienePermiso,
            sinEntregar: 2,
            error: TextosDeEntrega.yaTienePermiso,
          ),
        );

        expect(
          find.text('Ya tienes permiso: cierra sesión y entra de nuevo.'),
          findsOneWidget,
        );
        expect(find.text('Cerrar sesión y entrar de nuevo'), findsOneWidget);
        await desmontar(tester);
      });

      testWidgets('PAREJA — sin conexión: el literal, SIN botón de entrar de nuevo', (
        tester,
      ) async {
        await pulsar(
          tester,
          const ResumenDeEntrega(
            ResultadoDeEntrega.sinConexion,
            sinEntregar: 2,
            error: TextosDeEntrega.sinConexion,
          ),
        );

        expect(find.textContaining('Sin conexión con el servidor.'), findsOneWidget);
        expect(find.text('Cerrar sesión y entrar de nuevo'), findsNothing);
        expect(entregar, findsOneWidget, reason: 'se puede volver a pulsar');
        await desmontar(tester);
      });

      testWidgets('parcial: cuántos entregados y cuántos quedan, y cuánto esperar', (
        tester,
      ) async {
        await pulsar(
          tester,
          const ResumenDeEntrega(
            ResultadoDeEntrega.parcial,
            entregados: 1,
            sinEntregar: 1,
            error: 'Demasiadas peticiones seguidas.',
            esperar: Duration(seconds: 37),
          ),
        );

        expect(
          find.textContaining('Se entregaron 1 y quedan 1 sin entregar, intactos.'),
          findsOneWidget,
        );
        expect(find.textContaining('Vuelve a intentarlo en 37 s.'), findsOneWidget);
        await desmontar(tester);
      });
    });

    group('«Cerrar sesión» con cola: tres opciones', () {
      Future<void> abrirElCartel(WidgetTester tester) async {
        await montar(tester, enWeb: false, pendientes: 2);
        await tester.tap(find.text('Cerrar sesión'));
        await tester.pumpAndSettle();
      }

      testWidgets('ofrece entregar y salir, salir sin entregar y quedarse', (tester) async {
        await abrirElCartel(tester);

        expect(find.text('Entregar a revisión y salir'), findsOneWidget);
        expect(find.text('Salir sin entregar'), findsOneWidget);
        expect(find.text('Me quedo'), findsOneWidget);
        await desmontar(tester);
      });

      testWidgets('«Salir sin entregar» AVISA de que queda varado, y sale sin entregar', (
        tester,
      ) async {
        await abrirElCartel(tester);

        expect(
          find.textContaining('Si sales SIN entregar, quedan varados en este aparato'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'solo subirán si te devuelven el acceso a Reparto y vuelves a entrar',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Salir NO los borra'), findsOneWidget);

        await tester.tap(find.text('Salir sin entregar'));
        await tester.pumpAndSettle();

        expect(portero.salidas, 1);
        expect(entrega.entregas, 0);
        await desmontar(tester);
      });

      testWidgets('«Entregar a revisión y salir» entrega y, si todo entró, sale', (
        tester,
      ) async {
        await abrirElCartel(tester);

        await tester.tap(find.text('Entregar a revisión y salir'));
        await tester.pumpAndSettle();

        expect(entrega.entregas, 1);
        expect(portero.salidas, 1);
        await desmontar(tester);
      });

      testWidgets('PAREJA — si la entrega NO sale, NO sale de la sesión y se ve por qué', (
        tester,
      ) async {
        await abrirElCartel(tester);
        entrega.respuesta = const ResumenDeEntrega(
          ResultadoDeEntrega.sinConexion,
          sinEntregar: 2,
          error: TextosDeEntrega.sinConexion,
        );

        await tester.tap(find.text('Entregar a revisión y salir'));
        await tester.pumpAndSettle();

        expect(entrega.entregas, 1);
        expect(portero.salidas, 0, reason: 'sin entregar no se sale por la puerta de atrás');
        expect(find.textContaining('Sin conexión con el servidor.'), findsOneWidget);
        await desmontar(tester);
      });

      testWidgets('cerrar el cartel sin contestar es QUEDARSE', (tester) async {
        await abrirElCartel(tester);

        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(portero.salidas, 0);
        expect(entrega.entregas, 0);
        await desmontar(tester);
      });

      testWidgets('lo ya entregado NO cuenta como «sin subir»: cerrar sesión sale directo', (
        tester,
      ) async {
        await montar(
          tester,
          enWeb: false,
          sembrar: (cola) async {
            final c = await cola.encolar(metodo: 'POST', ruta: '/routes', cuerpo: const {});
            await cola.marcarEnRevision(c);
          },
        );

        await tester.tap(find.text('Cerrar sesión'));
        await tester.pumpAndSettle();

        expect(find.text('Queda trabajo sin subir'), findsNothing);
        expect(portero.salidas, 1);
        await desmontar(tester);
      });
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
