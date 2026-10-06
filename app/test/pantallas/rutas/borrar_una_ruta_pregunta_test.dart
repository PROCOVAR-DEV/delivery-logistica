// BORRAR UNA RUTA PREGUNTA ANTES, Y UN GESTO ES UN BORRADO — 01/10/2026.
//
// Dos fallos del mismo patrón en el mismo botón, el «Eliminar» de la tarjeta de
// `lista_rutas.dart`, y los dos ya estaban resueltos en otra pantalla ese mismo
// día (Vehículos):
//
//  1. **No preguntaba nada.** Un toque y la ruta se iba. La casa había decidido
//     lo contrario el 25/09/2026 con «Borrar la columna» del tablero, cuando
//     Jose vio una zona desaparecer de un toque. Aquí se quedó sin hacer, y es
//     la pantalla donde más duele: la semana que viene el logístico de Santiago
//     prueba esto solo, a 900 km, y una ruta borrada por error es una mañana de
//     armado tirada.
//
//  2. **Era reentrante.** El `onPressed` llamaba directo a
//     `accionesDeRutaProvider.eliminar`, sin guarda de «ya voy». En el navegador
//     el mismo clic llega por dos caminos —los eventos de puntero y el nodo de
//     accesibilidad del botón—, y eso se midió en Vehículos con un espía de
//     ratón delante: UN `click`, DOS `DELETE` a 113 ms, el primero `200` y el
//     segundo `404`. Aquí el «no» del segundo se pinta LITERAL por el §4, así
//     que lo que se ve es un fallo en rojo **encima de un borrado que sí
//     funcionó**.
//
// Desde el 06/10/2026, sólo completar convierte la ruta en histórico. Las
// marcas provisionales no impiden pedir confirmación ni borrar la ruta viva.

import 'dart:io';

import 'package:drift/drift.dart' show Value;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/lista_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  // ---------------------------------------------------------------------------
  // 1. LA GUARDA DE «YA VOY»
  // ---------------------------------------------------------------------------

  group('un gesto es un borrado', () {
    late BaseLocal base;
    late ColaDeSalida cola;
    late RelojFalso reloj;
    late ServidorFalso servidor;
    late AccionesDeRuta enLaWeb;
    late AccionesDeRuta enElAparato;
    late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

    setUp(() async {
      base = baseDePrueba();
      reloj = RelojFalso(DateTime.utc(2026, 10, 1, 9, 0));
      cola = ColaDeSalida(base, reloj: reloj.leer);
      contesta = (_) async =>
          RespuestaFalsa(200, const <String, Object?>{'success': true});
      servidor = ServidorFalso((p) => contesta(p));
      final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
        ..httpClientAdapter = servidor;
      enLaWeb = AccionesDeRuta(
        base,
        cola,
        reloj: reloj.leer,
        sufijoAparato: 'WEB',
        // Sin esperas: un fallo de red no se reintenta cuatro veces dentro de
        // una prueba.
        enVivo: EscrituraEnVivo(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
      );
      enElAparato = AccionesDeRuta(
        base,
        cola,
        reloj: reloj.leer,
        sufijoAparato: 'MSI',
      );

      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1', codigo: 'RT-20261001-001');
      await sembrarRuta(base, id: 'R2', codigo: 'RT-20261001-002');
    });

    tearDown(() => base.close());

    test('el mismo borrado dos veces A LA VEZ sale UNA vez', () async {
      // EL GESTO DUPLICADO, tal y como llega del navegador: las dos llamadas
      // **sin esperar** la primera, que es lo que significa «se solapan».
      final primera = enLaWeb.eliminar('R1');
      final segunda = enLaWeb.eliminar('R1');
      await primera;
      await segunda;

      expect(
        servidor.cuantas('DELETE', '/routes/R1'),
        1,
        reason:
            'un gesto duplicado tiene que mandar UN borrado: el segundo recibe '
            'el «no» del servidor sobre una ruta que ya no está, y por el §4 '
            'ese «no» se pinta literal encima de un borrado que sí funcionó',
      );
    });

    test('y en el aparato encola UN solo apunte', () async {
      // Sin red el borrado no se manda, se encola. Dos apuntes de borrado de la
      // misma ruta son dos «no» esperando en la bandeja de rechazados.
      final primera = enElAparato.eliminar('R1');
      final segunda = enElAparato.eliminar('R1');
      await primera;
      await segunda;

      final apuntes = await base.select(base.apuntes).get();
      final borrados = apuntes
          .where((a) => a.metodo == 'DELETE' && a.ruta == '/routes/R1')
          .length;
      expect(
        borrados,
        1,
        reason:
            'un gesto duplicado sin red tiene que dejar UN apunte: el segundo '
            'sube, el servidor contesta que esa ruta no existe y el rechazo se '
            'queda a la vista sin que nadie haya hecho nada mal',
      );
    });

    for (final operacion in ['eliminar', 'iniciar', 'completar', 'cerrar']) {
      test(
        'histórico completado impide $operacion sin tocar ni encolar',
        () async {
          await (base.update(
            base.routes,
          )..where((r) => r.id.equals('R1'))).write(
            const RoutesCompanion(status: Value(EstadoRuta.completada)),
          );
          Future<Object?> actuar() => switch (operacion) {
            'eliminar' => enElAparato.eliminar('R1'),
            'iniciar' => enElAparato.iniciar('R1'),
            'completar' => enElAparato.completar('R1'),
            _ => enElAparato.cerrar('R1', const [
              MarcaDeParada(pedidoId: 'P1', resultado: 'devuelto'),
            ]),
          };
          await expectLater(
            actuar,
            throwsA(
              isA<RechazoLocal>().having(
                (e) => e.mensaje,
                'motivo',
                msgRutaCompletada,
              ),
            ),
          );
          final ruta = await (base.select(
            base.routes,
          )..where((r) => r.id.equals('R1'))).getSingle();
          expect(ruta.status, EstadoRuta.completada);
          expect(await base.select(base.apuntes).get(), isEmpty);
        },
      );
    }

    test('los dos que llegan ven el MISMO resultado, también cuando el '
        'servidor dice que no', () async {
      // Al segundo se le devuelve el MISMO `Future`, no uno nuevo. Si se le
      // contestara «ya está» mientras el primero fallaba, el fallo no lo
      // pintaría nadie: el gesto saldría mudo, que es lo que prohíbe el §4.
      contesta = (_) async =>
          RespuestaFalsa(409, <String, Object?>{'error': msgRutaCompletada});

      final primera = enLaWeb.eliminar('R1');
      final segunda = enLaWeb.eliminar('R1');

      await expectLater(
        () => primera,
        throwsA(isA<RechazoLocal>()),
        reason: 'el 409 del servidor llega a quien pulsó',
      );
      await expectLater(
        () => segunda,
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            msgRutaCompletada,
          ),
        ),
        reason:
            'las dos llamadas son el mismo gesto: una diciendo «hecho» y la '
            'otra «no se pudo» sobre un solo borrado es la mitad del fallo de '
            'origen',
      );
      expect(servidor.cuantas('DELETE', '/routes/R1'), 1);
    });

    test('dos rutas distintas a la vez salen LAS DOS', () async {
      await Future.wait([enLaWeb.eliminar('R1'), enLaWeb.eliminar('R2')]);

      // LA LLAVE ES POR ACCIÓN CONCRETA, no una para toda la pantalla. Con una
      // global, borrar la ruta A y acto seguido la B dejaría la B tirada sin
      // decir nada: el descarte en silencio que prohíbe el §4.
      const porQue =
          'la llave es por ruta, no una global: con una global la segunda ruta '
          'se queda sin borrar y nadie lo dice';
      expect(servidor.cuantas('DELETE', '/routes/R1'), 1, reason: porQue);
      expect(servidor.cuantas('DELETE', '/routes/R2'), 1, reason: porQue);
    });

    test('es «mientras va», no «una sola vez»: el reintento a mano sale', () async {
      // La llave se suelta en cuanto termina. Si no, un fallo de red dejaría el
      // botón muerto para siempre.
      await enLaWeb.eliminar('R1');
      await sembrarRuta(base, id: 'R1', codigo: 'RT-20261001-001');
      await enLaWeb.eliminar('R1');

      expect(
        servidor.cuantas('DELETE', '/routes/R1'),
        2,
        reason:
            'la llave se suelta al terminar: si no, reintentar a mano tras un '
            'fallo de red no saldría nunca',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 2. LA PREGUNTA DE ANTES DE BORRAR
  // ---------------------------------------------------------------------------

  group('la pregunta de antes de borrar', () {
    late BaseLocal base;
    final ahora = DateTime(2026, 10, 1, 9, 30);

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> asentar(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// Si la ruta sigue en la base. **Dentro de `runAsync`**, y no es un adorno:
    /// el borrado que arranca el botón es una transacción de Drift, y esperarla
    /// con el reloj falso del `tester` cuelga la prueba en vez de hacerla
    /// fallar (§5 del `CLAUDE.md`, las dos trampas hermanas). Se vio al mutar:
    /// con el «Eliminar» borrando de un toque —el fallo de origen— esta prueba
    /// se quedaba colgada cuatro minutos en vez de decir que la ruta se había
    /// ido, y una prueba que se cuelga no caza nada.
    Future<bool> sigueLaRuta(WidgetTester tester) async =>
        (await tester.runAsync(
          () async =>
              (await (base.select(
                base.routes,
              )..where((r) => r.id.equals('R1'))).getSingleOrNull()) !=
              null,
        ))!;

    /// Monta la lista con UNA ruta en curso. Se siembra **dentro del cuerpo** y
    /// no en el `setUp`: lo que Drift deja empezado fuera del reloj falso no
    /// avanza dentro, y la prueba se cuelga en vez de fallar (§5).
    ///
    /// [cerradas] son las paradas de esa ruta que ya tienen resultado, que es lo
    /// que hace que el servidor se niegue a borrarla. [abiertas] son paradas de
    /// la misma ruta SIN resultado, que no estorban nada: hacen falta para que
    /// la guarda se ejerza de verdad —contar las paradas en vez de las cerradas
    /// sale verde si la ruta de la prueba no lleva ninguna—.
    Future<void> pintar(
      WidgetTester tester, {
      int cerradas = 0,
      int abiertas = 0,
    }) async {
      await sembrarCatalogo(base);
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
      await sembrarRuta(
        base,
        id: 'R1',
        codigo: 'RT-20261001-001',
        estado: EstadoRuta.enCurso,
        creada: ahora,
      );
      for (var i = 0; i < cerradas; i++) {
        await sembrarPedido(
          base,
          id: 'cerrada$i',
          cliente: 'Cliente cerrado $i',
          folio: 'F-10$i',
          rutaId: 'R1',
          ultimaRutaId: 'R1',
          resultado: ResultadoParada.entregado,
        );
      }
      for (var i = 0; i < abiertas; i++) {
        await sembrarPedido(
          base,
          id: 'abierta$i',
          cliente: 'Cliente abierto $i',
          folio: 'F-20$i',
          rutaId: 'R1',
          ultimaRutaId: 'R1',
        );
      }

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: MaterialApp(
            theme: temaDeReparto(),
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            home: const Scaffold(
              body: ListaDeRutas(deLaPestana: PestanaRutas.enCurso),
            ),
          ),
        ),
      );
      await asentar(tester);
    }

    Future<void> pulsar(WidgetTester tester, String texto) async {
      await tester.tap(find.text(texto));
      await asentar(tester);
    }

    testWidgets('tocar «Eliminar» NO borra: pregunta, y nombra la ruta', (
      tester,
    ) async {
      await pintar(tester);
      await pulsar(tester, 'Eliminar');

      expect(
        await sigueLaRuta(tester),
        isTrue,
        reason: 'una ruta no se va de un toque',
      );
      // El literal de la casa, con el código dentro: «Sí, borrar RT-…» dice qué
      // se va; «Aceptar» no dice nada.
      expect(find.text('Sí, borrar «RT-20261001-001»'), findsOneWidget);
      expect(find.text('No, dejarla'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('y dice QUÉ SE PIERDE, no «¿estás seguro?»', (tester) async {
      await pintar(tester);
      await pulsar(tester, 'Eliminar');

      // Las tres cosas que de verdad pasan, leídas de `borrarRuta`
      // (`api/internal/api/rutas.go`): la ruta se va con lo que se calculó al
      // armarla, los pedidos NO se borran y vuelven a disponibles, y el camión
      // queda libre.
      expect(
        find.textContaining('hay que volver a armarla'),
        findsOneWidget,
        reason:
            'sin esto no se dice lo que cuesta rehacerlo, que es la mitad que '
            'sirve de la pregunta',
      );
      expect(
        find.textContaining('NO se borra son los pedidos'),
        findsOneWidget,
        reason:
            'quien borra una ruta tiene que saber que los pedidos se quedan: si '
            'no, no borra y se queda con una ruta mal armada puesta',
      );
      expect(find.textContaining('el camión se queda libre'), findsOneWidget);
      expect(
        find.textContaining(
          'entregados siguen entregados y no se reparten otra vez',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('seguro'),
        findsNothing,
        reason: '«¿estás seguro?» no es información, es un peaje',
      );

      await desmontar(tester);
    });

    testWidgets('«No, dejarla» no borra nada', (tester) async {
      await pintar(tester);
      await pulsar(tester, 'Eliminar');
      await pulsar(tester, 'No, dejarla');

      expect(
        await sigueLaRuta(tester),
        isTrue,
        reason: 'contestar «No» tiene que dejar la ruta donde estaba',
      );
      expect(find.text('RT-20261001-001'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('cerrar el cajón con la ✕ es NO, no un sí por descuido', (
      tester,
    ) async {
      // `abrirCajon` devuelve `null` al cerrar sin contestar —la ✕, tocar fuera,
      // Escape— y `null` tiene que ser NO. Si fuera «sí», la ruta se iría por
      // cerrar un cajón, que es peor que no haber preguntado.
      await pintar(tester);
      await pulsar(tester, 'Eliminar');
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);

      expect(
        await sigueLaRuta(tester),
        isTrue,
        reason: 'cerrar sin contestar no puede borrar nada',
      );

      await desmontar(tester);
    });

    testWidgets('y al contestar «Sí» se borra', (tester) async {
      await pintar(tester);
      await pulsar(tester, 'Eliminar');
      await pulsar(tester, 'Sí, borrar «RT-20261001-001»');

      expect(
        await sigueLaRuta(tester),
        isFalse,
        reason: 'contestar «Sí» tiene que borrar la ruta',
      );

      await desmontar(tester);
    });

    testWidgets('una ruta CON paradas pero sin cerrar ninguna sí pregunta', (
      tester,
    ) async {
      // EL CASO QUE EJERCE LA GUARDA, y sin él la mutación sale verde: contar
      // las paradas de la ruta en vez de las CERRADAS deja de poder borrarse
      // cualquier ruta con pedidos dentro, que son todas. Una ruta armada por
      // error se borra, y eso es lo normal; lo que se prohíbe es borrar una por
      // la que ya pasó mercancía.
      await pintar(tester, abiertas: 2);
      await pulsar(tester, 'Eliminar');

      expect(
        find.text('Sí, borrar «RT-20261001-001»'),
        findsOneWidget,
        reason:
            'una ruta con dos paradas sin cerrar se borra: sólo completar la convierte en histórico; '
            'una parada CERRADA, no tener paradas',
      );
      expect(
        find.textContaining('no se puede borrar'),
        findsNothing,
        reason: 'ninguna de sus paradas está cerrada: no hay portazo que dar',
      );

      await desmontar(tester);
    });

    testWidgets('en curso con resultados sigue preguntando y puede borrarse', (
      tester,
    ) async {
      await pintar(tester, cerradas: 2, abiertas: 1);
      await pulsar(tester, 'Eliminar');
      expect(find.textContaining('Sí, borrar'), findsOneWidget);
      await pulsar(tester, 'Sí, borrar «RT-20261001-001»');
      expect(await sigueLaRuta(tester), isFalse);
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. EL MISMO «NO», ESCRITO IGUAL EN LOS DOS LADOS
  // ---------------------------------------------------------------------------
  //
  // El motivo lo redacta el servidor cuando hay red y el aparato cuando se dice
  // antes de preguntar. Dos redacciones del mismo «no» es el mismo rechazo
  // leyéndose de dos maneras según la cobertura, y eso no lo enseña ninguna
  // pantalla (§3-bis: se atan con una prueba, no con un comentario).
  //
  // Esta prueba lee el fuente de Go por `../api/…`, como `geo_test.dart` lee sus
  // casos por `../docs/…`. No hace falta copiarlo al `Dockerfile.app`: desde el
  // 26/09/2026 esa imagen sólo corre `flutter analyze`, no la suite. Si la suite
  // volviera a la imagen, este fichero tendría que viajar con ella.
  group('el literal es el del servidor', () {
    final fuente = File('../api/internal/api/rutas.go');

    test('palabra por palabra, con el número dentro', () {
      expect(
        fuente.existsSync(),
        isTrue,
        reason: 'sin ${fuente.path} no hay nada que ate los dos lados',
      );
      final texto = fuente.readAsStringSync();
      final desde = texto.indexOf('msgRutaCompletada = ');
      expect(
        desde,
        isNot(-1),
        reason:
            'no está `msgRutaCompletada` en ${fuente.path}: si le cambiaron '
            'el nombre, hay que mirar si le cambiaron también la redacción',
      );

      // El literal de Go, pegando los trozos: un renglón que acaba en `+`
      // sigue en el siguiente.
      final trozos = <String>[];
      for (final linea in texto.substring(desde).split('\n')) {
        trozos.addAll(
          RegExp(r'"((?:[^"\\]|\\.)*)"')
              .allMatches(linea)
              .map((m) => m.group(1)!),
        );
        if (!linea.trimRight().endsWith('+')) break;
      }
      final literalGo = trozos.join();

      expect(
        msgRutaCompletada,
        literalGo,
        reason:
            'el aparato y el servidor dicen el mismo «no» con otras palabras. '
            'Hay que cambiar los dos lados a la vez: '
            'api/internal/api/rutas.go (msgRutaCompletada) y '
            'app/lib/pantallas/rutas/datos/acciones_rutas.dart '
            '(msgRutaCompletada)',
      );
    });
  });
}
