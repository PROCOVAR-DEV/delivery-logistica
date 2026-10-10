// EL AVISO EN VIVO EN `/sin-permiso`: cuándo abre, qué hace con un aviso y cuándo cierra.
//
// Jose, 09/10/2026: probado en un móvil real, el administrador aplicó el cambio y el
// teléfono siguió diciendo «Todavía no se ha aplicado nada» hasta pulsar «Actualizar
// estados». «Nada de polling: para eso tenemos SSE.» (`docs/sin-permiso.md`).
//
// Estas pruebas montan la pantalla de verdad (portero, cola, panel y proveedores de
// verdad) y sustituyen SOLO los dos bordes: el flujo (un doble que la prueba abre,
// corta o rechaza a mano) y la entrega (qué contesta la consulta). No sale ni un byte, y
// el tiempo lo manda `tester.pump`. La lógica fina de la espera y de los códigos está en
// `nucleo/sincro/escucha_de_revision_test.dart`; el transporte en
// `flujo_de_revision_test.dart`. Aquí: el enganche.
//
// La que fija el espíritu del sondeo sigue siendo `sin_permiso_test.dart` («Actualizar
// estados» consulta UNA vez, y no hay sondeo): con la escucha «sin servidor» de ese
// fichero, diez minutos de panel son cero consultas; y con la escucha de verdad abierta
// y callada, ninguna más que la de apertura (hay una hermana en ese mismo fichero).
// Aquí lo mismo, y lo que pasa al (re)abrir: el servidor no guarda eventos, así que lo
// decidido con el flujo cerrado solo se sabe preguntando.
//
// Cada regla con su pareja (CLAUDE.md §5): lo que abre y lo que NO abre.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/aviso_de_version_nueva.dart'
    show abridorDeLaDescargaProvider;
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/sincro/entrega_a_revision.dart';
import 'package:reparto/nucleo/sincro/flujo_de_revision.dart';
import 'package:reparto/pantallas/acceso/vista/panel_de_entrega.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_sin_permiso.dart';

import '../../apoyo/apoyo_accesos.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

/// Un portero al que se le dice el estado, sin arrancar nada.
class _PorteroFalso extends Portero {
  _PorteroFalso(super.ref, this._estado);

  EstadoDeAcceso _estado;

  @override
  EstadoDeAcceso get estado => _estado;

  void ponerEstado(EstadoDeAcceso nuevo) {
    _estado = nuevo;
    notifyListeners();
  }
}

/// Una conexión que la prueba maneja: lo que haría el servidor.
class _Conexion {
  _Conexion(this.token);

  final String token;
  final control = StreamController<String>();
  bool cancelada = false;

  void abierto() => control.add(sucesoAbierto);
  void revision() => control.add(sucesoRevision);
  void cortaElServidor() => unawaited(control.close());
  void rechaza(int codigo, {Duration? esperar}) =>
      control.addError(RechazoDelFlujo(codigo, esperar: esperar));
}

/// La entrega, sin red. Cuenta las consultas y cuántas hubo a la vez, y deja la cola
/// como la dejaría la de verdad.
class _EntregaFalsa extends Fake implements EntregaARevision {
  _EntregaFalsa(this.cola);

  final ColaDeSalida cola;
  int tokens = 0;
  int consultas = 0;
  int enVuelo = 0;
  int maximoEnVuelo = 0;

  /// Si está puesta, cada consulta espera a que se complete (para tenerlas en vuelo).
  Completer<void>? puerta;

  /// Lo que la consulta cambia en la cola.
  Future<void> Function()? aplicar;

  ResumenDeConsulta respuesta = const ResumenDeConsulta(
    ResultadoDeEntrega.entregado,
    cambiaron: 1,
  );

  /// Si está puesta, «Entregar a revisión» espera a que se complete.
  Completer<void>? puertaDeEntregar;
  int entregas = 0;

  @override
  Future<ResumenDeEntrega> entregar() async {
    entregas++;
    await puertaDeEntregar?.future;
    return const ResumenDeEntrega(ResultadoDeEntrega.entregado, entregados: 1);
  }

  @override
  Future<({Uri url, String token})?> paraElAvisoEnVivo() async => (
    url: Uri.parse('https://sync.test/revision/eventos?aparato=ap-1'),
    token: 'tok-${++tokens}',
  );

  @override
  Future<ResumenDeConsulta> actualizarEstados() async {
    consultas++;
    enVuelo++;
    if (enVuelo > maximoEnVuelo) maximoEnVuelo = enVuelo;
    try {
      final p = puerta;
      if (p != null) await p.future;
      await aplicar?.call();
      return respuesta;
    } finally {
      enVuelo--;
    }
  }
}

void main() {
  late List<_Conexion> conexiones;
  late _PorteroFalso portero;
  late _EntregaFalsa entrega;
  late ColaDeSalida cola;
  late List<String> claves;

  /// Un apunte ya entregado a revisión (lo que deja `entregar()`).
  Future<String> sembrarEnRevision(int i) async {
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/routes/r-$i/results',
      cuerpo: const <String, Object?>{'a': 1},
    );
    await cola.marcarEnRevision(clave, entrega: 'ent-1');
    return clave;
  }

  /// Monta `/sin-permiso`. [soloElPanel] monta el panel suelto (necesario en la web, donde
  /// la pantalla no lo monta nunca: así se prueba la guarda de la propia escucha).
  Future<void> montar(
    WidgetTester tester, {
    bool enWeb = false,
    bool soloElPanel = false,
    EstadoDeAcceso estado = EstadoDeAcceso.sinPermiso,
    int enRevision = 1,
    int pendientes = 0,
  }) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    conexiones = <_Conexion>[];
    claves = <String>[];
    final base = baseDePrueba();
    addTearDown(base.close);
    // Sembrado DENTRO del cuerpo (CLAUDE.md §5).
    cola = ColaDeSalida(base, reloj: RelojFalso(DateTime(2026, 10, 9, 12)).leer);
    entrega = _EntregaFalsa(cola);
    for (var i = 0; i < enRevision; i++) {
      claves.add(await sembrarEnRevision(i));
    }
    for (var i = 0; i < pendientes; i++) {
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/p-$i',
        cuerpo: <String, Object?>{'status': 'completed'},
      );
    }

    // `ProviderScope` y no `UncontrolledProviderScope` con un contenedor propio: solo el
    // primero suelta un `autoDispose` al desmontar (el otro espera a cerrar el
    // contenedor), y lo que se prueba aquí es justo ese cierre.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trabajaSinConexionProvider.overrideWithValue(!enWeb),
          baseProvider.overrideWithValue(base),
          navegadorProvider.overrideWithValue(NavegadorFalso()),
          abridorDeLaDescargaProvider.overrideWithValue((enlace) async {}),
          porteroProvider.overrideWith((ref) => _PorteroFalso(ref, estado)),
          entregaARevisionProvider.overrideWithValue(entrega),
          // El flujo: nada de red. Cada apertura es una conexión que la prueba maneja.
          abridorDeFlujoDeRevisionProvider.overrideWithValue((url, token) {
            final c = _Conexion(token);
            c.control.onCancel = () => c.cancelada = true;
            conexiones.add(c);
            return c.control.stream;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: soloElPanel
                ? const SingleChildScrollView(child: PanelDeEntrega())
                : const PantallaSinPermiso(),
          ),
        ),
      ),
    );
    portero =
        ProviderScope.containerOf(
              tester.element(find.byType(MaterialApp)),
            ).read(porteroProvider)
            as _PorteroFalso;
    await tester.pump();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// Lo que el revisor hace en el servidor y la consulta trae: aplicar.
  Future<void> aplicadoPorMarta(String clave) => cola.resolverRevision(
    clave,
    DecisionDeRevision(
      estado: EstadoEnRevision.aplicado,
      por: 'Marta Pérez',
      cuando: DateTime(2026, 10, 9, 13, 10),
    ),
  );

  final actualizar = find.text('Actualizar estados');

  group('cuándo abre', () {
    testWidgets('con algo en revisión y el panel montado: UNA conexión, con el token '
        'de entrega', (tester) async {
      await montar(tester);

      expect(conexiones, hasLength(1));
      expect(conexiones.single.token, 'tok-1');
      expect(entrega.tokens, 1);
      expect(
        entrega.consultas,
        0,
        reason: 'sin llegar `abierto` (la conexión no está abierta) no se consulta',
      );
      await desmontar(tester);
    });

    testWidgets('montado con la base VACÍA y entregado DESPUÉS: abre cuando aparece lo '
        'primero en revisión, sin volver a montar', (tester) async {
      await montar(tester, enRevision: 0);
      expect(conexiones, isEmpty);

      await sembrarEnRevision(0);
      await tester.pump(const Duration(milliseconds: 50));

      expect(conexiones, hasLength(1));
      await desmontar(tester);
    });

    testWidgets('PAREJA: sin nada en revisión NO abre (aunque haya cambios sin enviar)', (
      tester,
    ) async {
      await montar(tester, enRevision: 0, pendientes: 2);
      await tester.pump(const Duration(minutes: 5));

      expect(conexiones, isEmpty);
      expect(entrega.tokens, 0, reason: 'ni se pide un token para nada');
      await desmontar(tester);
    });

    testWidgets('PAREJA: en la WEB NO abre, ni con el panel montado y algo en la base '
        '(la web no tiene cola ni entrega)', (tester) async {
      await montar(tester, enWeb: true, soloElPanel: true);
      await tester.pump(const Duration(minutes: 5));

      expect(conexiones, isEmpty);
      expect(entrega.tokens, 0);
      await desmontar(tester);
    });

    testWidgets('PAREJA: en la web, con la pantalla de verdad, tampoco', (tester) async {
      await montar(tester, enWeb: true);
      await tester.pump(const Duration(seconds: 2));

      expect(conexiones, isEmpty);
      await desmontar(tester);
    });

    testWidgets('PAREJA: si el portero ya no está en sinPermiso NO abre', (tester) async {
      await montar(tester, estado: EstadoDeAcceso.dentro, soloElPanel: true);
      await tester.pump(const Duration(minutes: 1));

      expect(conexiones, isEmpty);
      await desmontar(tester);
    });
  });

  group('un aviso', () {
    testWidgets('dispara UNA consulta y el panel pasa a «Aplicado por…» sin pulsar nada', (
      tester,
    ) async {
      await montar(tester);
      entrega.aplicar = () => aplicadoPorMarta(claves.single);
      expect(find.textContaining('Entregado a revisión'), findsOneWidget);
      expect(find.textContaining('Aplicado por'), findsNothing);

      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 1);
      expect(find.textContaining('Aplicado por Marta Pérez'), findsOneWidget);
      expect(find.textContaining('Entregado a revisión'), findsNothing);
      expect(find.text('1 cambio de estado.'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('NO HAY SONDEO: diez minutos de panel abierto y callado son UNA consulta '
        '(la de apertura), no una cada rato', (tester) async {
      await montar(tester);
      conexiones.single.abierto();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.consultas, 1, reason: 'la de ponerse al día al abrir');

      await tester.pump(const Duration(minutes: 10));

      expect(entrega.consultas, 1, reason: 'la conexión de allá se paga: sin sondeo');
      expect(conexiones, hasLength(1));
      await desmontar(tester);
    });

    testWidgets('PAREJA: sin llegar `abierto` NO se consulta, ni en diez minutos', (
      tester,
    ) async {
      await montar(tester);

      await tester.pump(const Duration(minutes: 10));

      expect(entrega.consultas, 0);
      await desmontar(tester);
    });

    testWidgets('sin novedades NO escribe «Sin novedades.» (es una consulta automática)', (
      tester,
    ) async {
      await montar(tester);
      entrega.respuesta = const ResumenDeConsulta(ResultadoDeEntrega.entregado);

      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 1);
      expect(find.text('Sin novedades.'), findsNothing);
      expect(find.textContaining('novedades'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('PAREJA: el botón SÍ lo escribe, y un aviso sin novedades luego no lo '
        'borra', (tester) async {
      await montar(tester);
      entrega.respuesta = const ResumenDeConsulta(ResultadoDeEntrega.entregado);

      await tester.tap(actualizar);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Sin novedades.'), findsOneWidget);

      // Y mientras la consulta de oficio está en vuelo, tampoco: no parpadea.
      entrega.puerta = Completer<void>();
      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.enVuelo, 1);
      expect(find.text('Sin novedades.'), findsOneWidget);

      entrega.puerta!.complete();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.consultas, 2);
      expect(
        find.text('Sin novedades.'),
        findsOneWidget,
        reason: 'lo que la persona estaba leyendo no se pisa',
      );
      await desmontar(tester);
    });

    testWidgets('un fallo DE VERDAD sí se dice', (tester) async {
      await montar(tester);
      entrega.respuesta = const ResumenDeConsulta(
        ResultadoDeEntrega.sinConexion,
        error: TextosDeEntrega.sinConexion,
      );

      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(TextosDeEntrega.sinConexion), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('«lista truncada» también se dice (CLAUDE.md §3: un tope alcanzado '
        'no se calla)', (tester) async {
      await montar(tester);
      entrega.respuesta = const ResumenDeConsulta(
        ResultadoDeEntrega.entregado,
        truncado: true,
      );

      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Hay más entregas de las que caben'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('tres avisos seguidos NO se pisan: una consulta en vuelo, y UNA vuelta '
        'más al acabar', (tester) async {
      await montar(tester);
      entrega.puerta = Completer<void>();

      conexiones.single
        ..revision()
        ..revision()
        ..revision();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.consultas, 1, reason: 'la segunda y la tercera esperan');
      expect(entrega.maximoEnVuelo, 1);

      entrega.puerta!.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 2, reason: 'una vuelta más, no dos');
      expect(entrega.maximoEnVuelo, 1, reason: 'nunca dos consultas a la vez');
      await desmontar(tester);
    });

    testWidgets('un aviso mientras se pulsa «Actualizar estados» no se pisa, y no se '
        'pierde', (tester) async {
      await montar(tester);
      entrega.puerta = Completer<void>();

      await tester.tap(actualizar);
      await tester.pump(const Duration(milliseconds: 50));
      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.consultas, 1);
      expect(entrega.maximoEnVuelo, 1);

      entrega.puerta!.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 2, reason: 'el aviso llegó tarde para la primera');
      expect(entrega.maximoEnVuelo, 1);
      await desmontar(tester);
    });

    testWidgets('un aviso mientras se ENTREGA (otro botón del mismo panel) tampoco se '
        'pierde', (tester) async {
      await montar(tester, pendientes: 1);
      entrega.puertaDeEntregar = Completer<void>();

      await tester.tap(find.text('Entregar a revisión'));
      await tester.pump(const Duration(milliseconds: 50));
      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.entregas, 1);
      expect(entrega.consultas, 0, reason: 'no se pisa a la entrega');

      entrega.puertaDeEntregar!.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 1, reason: 'el aviso se atiende al acabar la entrega');
      await desmontar(tester);
    });

    testWidgets('PAREJA: «Actualizar estados» sigue siendo el respaldo: con el flujo '
        'abierto consulta UNA vez al pulsarlo', (tester) async {
      await montar(tester);
      entrega.respuesta = const ResumenDeConsulta(ResultadoDeEntrega.entregado);

      await tester.tap(actualizar);
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 1);
      expect(find.text('Sin novedades.'), findsOneWidget);
      await desmontar(tester);
    });
  });

  group('al (re)abrir se pone al día', () {
    // El caso que reprodujo la auditoría: el token de entrega caduca (cada 10 min), el
    // revisor decide JUSTO en los 2 s entre el corte y la reapertura, y el servidor no
    // guarda eventos. En `/sin-permiso` nadie más pregunta: sin la consulta al abrir, el
    // panel se quedaba en «Todavía no se ha aplicado nada» con el apunte ya aplicado.
    testWidgets('lo decidido con el flujo CERRADO se ve al reabrir, sin pulsar nada', (
      tester,
    ) async {
      await montar(tester);
      conexiones.single.abierto();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.consultas, 1);
      expect(find.textContaining('Entregado a revisión'), findsOneWidget);

      // Cierra el servidor y, en el hueco, el revisor aplica. Nadie avisa a nadie.
      conexiones.single.cortaElServidor();
      await tester.pump(const Duration(milliseconds: 50));
      entrega.aplicar = () => aplicadoPorMarta(claves.single);
      expect(find.textContaining('Aplicado por'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(conexiones, hasLength(2));
      expect(entrega.consultas, 1, reason: 'abrir la petición todavía no consulta');
      conexiones.last.abierto();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 2);
      expect(find.textContaining('Aplicado por Marta Pérez'), findsOneWidget);
      expect(find.textContaining('Entregado a revisión'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('la PRIMERA apertura también: se monta el panel con algo ya decidido', (
      tester,
    ) async {
      await montar(tester);
      entrega.aplicar = () => aplicadoPorMarta(claves.single);

      conexiones.single.abierto();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 1);
      expect(find.textContaining('Aplicado por Marta Pérez'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('la consulta de apertura es SILENCIOSA: sin novedades no escribe nada', (
      tester,
    ) async {
      await montar(tester);
      entrega.respuesta = const ResumenDeConsulta(ResultadoDeEntrega.entregado);

      conexiones.single.abierto();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 1);
      expect(find.textContaining('novedades'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('la de apertura y un aviso seguidos no se pisan: una en vuelo y UNA vuelta '
        'más', (tester) async {
      await montar(tester);
      entrega.puerta = Completer<void>();

      conexiones.single
        ..abierto()
        ..revision();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.consultas, 1);

      entrega.puerta!.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 2);
      expect(entrega.maximoEnVuelo, 1);
      await desmontar(tester);
    });

    testWidgets('la de apertura con «Actualizar estados» en vuelo tampoco se pisa', (
      tester,
    ) async {
      await montar(tester);
      entrega.puerta = Completer<void>();

      await tester.tap(actualizar);
      await tester.pump(const Duration(milliseconds: 50));
      conexiones.single.abierto();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.consultas, 1);

      entrega.puerta!.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(entrega.consultas, 2);
      expect(entrega.maximoEnVuelo, 1);
      await desmontar(tester);
    });
  });

  group('el panel se desmonta con una consulta en vuelo', () {
    // `ControlDeEntrega._consultar` sigue después de `await actualizarEstados()`: si el
    // panel ya no está, el notificador está desechado y escribir `state` lanzaría. Por
    // eso mira `ref.mounted`. Sin esta prueba quitarlo no ponía nada en rojo.
    testWidgets('al terminar no hay excepción ni segunda vuelta', (tester) async {
      await montar(tester);
      entrega.puerta = Completer<void>();
      entrega.aplicar = () => aplicadoPorMarta(claves.single);

      conexiones.single.revision();
      await tester.pump(const Duration(milliseconds: 50));
      expect(entrega.enVuelo, 1);

      await desmontar(tester);
      entrega.puerta!.complete();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(entrega.enVuelo, 0, reason: 'la consulta terminó');
      expect(entrega.consultas, 1);
    });

    testWidgets('con un aviso apuntado para después: tampoco hay vuelta ni excepción', (
      tester,
    ) async {
      await montar(tester);
      entrega.puerta = Completer<void>();

      conexiones.single
        ..revision()
        ..revision(); // la segunda queda apuntada
      await tester.pump(const Duration(milliseconds: 50));

      await desmontar(tester);
      entrega.puerta!.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(entrega.consultas, 1, reason: 'sin panel no se da la vuelta de más');
    });
  });

  group('cuándo cierra', () {
    testWidgets('al desmontar el panel: cancela la conexión y no queda ningún temporizador', (
      tester,
    ) async {
      await montar(tester);
      conexiones.single.abierto(); // lleva su temporizador de «conexión buena»
      await tester.pump();

      await desmontar(tester);

      expect(conexiones.single.cancelada, isTrue);
      // El binding falla solo si queda un Timer vivo.
    });

    testWidgets('al desmontar con un reintento esperando: tampoco reabre después', (
      tester,
    ) async {
      await montar(tester);
      conexiones.single.cortaElServidor();
      await tester.pump(); // espera 2 s

      await desmontar(tester);
      await tester.pump(const Duration(minutes: 5));

      expect(conexiones, hasLength(1));
      expect(entrega.tokens, 1);
    });

    testWidgets('al quedar a CERO en revisión: sigue abierta mientras quede uno, y '
        'se cierra con el último', (tester) async {
      await montar(tester, enRevision: 2);
      expect(conexiones, hasLength(1));

      await aplicadoPorMarta(claves[0]);
      await tester.pump(const Duration(milliseconds: 50));
      expect(conexiones.single.cancelada, isFalse, reason: 'queda uno por decidir');

      await aplicadoPorMarta(claves[1]);
      await tester.pump(const Duration(milliseconds: 50));
      expect(conexiones.single.cancelada, isTrue);

      await tester.pump(const Duration(minutes: 5));
      expect(conexiones, hasLength(1), reason: 'y no vuelve a abrir');
      await desmontar(tester);
    });

    testWidgets('si el portero sale de sinPermiso (recupera el permiso, cierra sesión, '
        'la sesión muere): se cierra y no reabre', (tester) async {
      await montar(tester);
      expect(conexiones, hasLength(1));

      portero.ponerEstado(EstadoDeAcceso.dentro);
      await tester.pump(const Duration(milliseconds: 50));
      expect(conexiones.single.cancelada, isTrue);

      await tester.pump(const Duration(minutes: 5));
      expect(conexiones, hasLength(1));
      await desmontar(tester);
    });

    testWidgets('PAREJA: un aviso del portero que SIGUE en sinPermiso no cierra ni '
        'reabre nada', (tester) async {
      await montar(tester);

      portero.ponerEstado(EstadoDeAcceso.sinPermiso);
      await tester.pump(const Duration(milliseconds: 50));

      expect(conexiones, hasLength(1));
      expect(conexiones.single.cancelada, isFalse);
      await desmontar(tester);
    });
  });

  group('cuando el flujo se corta', () {
    testWidgets('el servidor cierra (caducó el token de entrega): a los 2 s pide OTRO '
        'token y reabre', (tester) async {
      await montar(tester);
      conexiones.single.abierto();
      await tester.pump(const Duration(minutes: 10));

      conexiones.single.cortaElServidor();
      await tester.pump(const Duration(seconds: 1));
      expect(conexiones, hasLength(1));
      await tester.pump(const Duration(seconds: 1));

      expect(conexiones, hasLength(2));
      expect(conexiones.last.token, 'tok-2');
      expect(entrega.tokens, 2);
      await desmontar(tester);
    });

    testWidgets('429 con Retry-After: respeta lo que pide el servidor', (tester) async {
      await montar(tester);

      conexiones.single.rechaza(429, esperar: const Duration(seconds: 90));
      await tester.pump(const Duration(seconds: 89));
      expect(conexiones, hasLength(1));
      await tester.pump(const Duration(seconds: 1));

      expect(conexiones, hasLength(2));
      await desmontar(tester);
    });

    testWidgets('403 (aparato ajeno): no reintenta, y el botón sigue ahí', (tester) async {
      await montar(tester);

      conexiones.single.rechaza(403);
      await tester.pump(const Duration(minutes: 30));

      expect(conexiones, hasLength(1));
      expect(actualizar, findsOneWidget);
      await desmontar(tester);
    });
  });
}
