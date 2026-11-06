// EL AVISO DE VERSIÓN NUEVA de «Reparto Distribuidor»: mira SU anuncio (`distribuidor` de GET /api/version), compara con SU versionCode,
// con las mismas tres reglas del comprobador de Reparto, y no se mezcla con el de Reparto (`ultima`) ni al revés.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/distribuidor/modo_distribuidor.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/actualizacion/comprobador.dart';
import 'package:reparto/nucleo/actualizacion/version_publicada.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

import '../apoyo/base_de_prueba.dart';
import '../apoyo/servidor_falso.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const sesion = Sesion(token: 'tok', refresh: 'r0', sub: 'u1');
  const enlace = 'https://descargas.test/reparto-distribuidor-1.0.1.apk';
  const miVersion = VersionInstalada(version: '1.0.0', compilacion: 57);

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Map<String, Object?> anuncio(int compilacion, [String version = '1.0.1']) => {
    'version': version,
    'compilacion': compilacion,
    'notas': 'Arregla el GPS.',
    'descargas': {'android': enlace},
    'ficheros': {
      'android': {'bytes': 180590868, 'sha256': 'a' * 64},
    },
  };

  /// El cuerpo de `GET /api/version`: lo de Reparto (`ultima`) y lo del distribuidor, cada uno por su lado.
  Map<String, Object?> cuerpo({Object? ultima, Object? distribuidor}) => {
    'version': 'api-1',
    'ultima': ultima,
    'distribuidor': distribuidor,
  };

  ({ComprobadorDeActualizacion comprobador, ServidorFalso servidor}) montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder, {
    String clave = 'distribuidor',
    Plataforma plataforma = Plataforma.android,
  }) {
    final servidor = ServidorFalso(responder);
    final almacen = AlmacenEnMemoria(sesion);
    final cliente = ClienteApi.montar(
      baseUrl: 'https://api.test/api',
      almacen: almacen,
      renovador: Renovador(
        Dio(BaseOptions(baseUrl: 'https://auth.test'))
          ..httpClientAdapter = servidor,
        almacen,
      ),
      esperas: ComprobadorDeActualizacion.sinEsperas,
    );
    cliente.dio.httpClientAdapter = servidor;
    return (
      comprobador: ComprobadorDeActualizacion(
        cliente: cliente,
        base: base,
        plataforma: plataforma,
        instalada: () async => miVersion,
        clave: clave,
      ),
      servidor: servidor,
    );
  }

  Future<EstadoDeActualizacion> comprobar(
    Map<String, Object?> respuesta, {
    String clave = 'distribuidor',
  }) => montar(
    (p) async => RespuestaFalsa(200, respuesta),
    clave: clave,
  ).comprobador.comprobar();

  group('lo que dice el comprobador', () {
    test(
      'hay versión nueva: SePuedeActualizar con SU enlace y su tamaño',
      () async {
        final e = await comprobar(cuerpo(distribuidor: anuncio(58)));
        expect(e, isA<SePuedeActualizar>());
        e as SePuedeActualizar;
        expect(e.enlace, enlace);
        expect(e.publicada.version, '1.0.1');
        expect(
          e.publicada.ficheroPara(Plataforma.android)!.bytes,
          180590868,
          reason: 'el tamaño sale del anuncio, para decirlo antes de pulsar',
        );
      },
    );

    test('la misma versión: al día', () async {
      expect(
        await comprobar(cuerpo(distribuidor: anuncio(57, '1.0.0'))),
        isA<AlDia>(),
      );
    });

    test('una versión menor: al día (nunca se baja de versión)', () async {
      expect(
        await comprobar(cuerpo(distribuidor: anuncio(56, '0.9.0'))),
        isA<AlDia>(),
      );
    });

    test('sin anuncio (distribuidor null): al día, no es un fallo', () async {
      expect(await comprobar(cuerpo()), isA<AlDia>());
      expect(
        await comprobar(<String, Object?>{'version': 'api-1', 'ultima': null}),
        isA<AlDia>(),
        reason: 'una api anterior no manda la clave: tampoco es un fallo',
      );
    });

    test('sin red: NoSeSupo, UNA sola petición y sin reintentos', () async {
      final m = montar((p) async => null);
      expect(await m.comprobador.comprobar(), isA<NoSeSupo>());
      expect(m.servidor.vistas, hasLength(1));
    });

    test('REGLA 1: con cola pendiente, PrimeroSube con cuántas', () async {
      final cola = ColaDeSalida(base);
      for (var i = 0; i < 2; i++) {
        await cola.encolar(
          metodo: 'POST',
          ruta: '/api/routes/r$i/results',
          cuerpo: const {'x': 1},
        );
      }
      final e = await comprobar(cuerpo(distribuidor: anuncio(58)));
      expect(e, isA<PrimeroSube>());
      expect((e as PrimeroSube).pendientes, 2);
    });

    test('REGLA 3: en web no aplica y ni se llama al servidor', () async {
      final m = montar(
        (p) async => RespuestaFalsa(200, cuerpo(distribuidor: anuncio(58))),
        plataforma: Plataforma.ninguna,
      );
      expect(await m.comprobador.comprobar(), isA<NoAplica>());
      expect(m.servidor.vistas, isEmpty);
    });

    test('REGLA 2: solo pregunta, no baja nada', () async {
      final m = montar(
        (p) async => RespuestaFalsa(200, cuerpo(distribuidor: anuncio(58))),
      );
      await m.comprobador.comprobar();
      expect(m.servidor.vistas.single.metodo, 'GET');
      expect(m.servidor.vistas.single.ruta, '/version');
    });
  });

  group('Reparto y el distribuidor no se mezclan', () {
    test('un Reparto nuevo (`ultima`) NO avisa al distribuidor', () async {
      final e = await comprobar(
        cuerpo(ultima: anuncio(99, '1.0.99'), distribuidor: anuncio(57)),
      );
      expect(e, isA<AlDia>());
    });

    test('un distribuidor nuevo NO avisa a Reparto', () async {
      final e = await comprobar(
        cuerpo(ultima: anuncio(57), distribuidor: anuncio(99)),
        clave: 'ultima',
      );
      expect(e, isA<AlDia>());
    });

    test(
      'sin `ultima` pero con `distribuidor`, Reparto sigue sin avisar',
      () async {
        expect(
          await comprobar(cuerpo(distribuidor: anuncio(99)), clave: 'ultima'),
          isA<AlDia>(),
        );
      },
    );

    test('el provider elige la clave según el modo', () {
      for (final (modo, clave) in [(true, 'distribuidor'), (false, 'ultima')]) {
        final c = ProviderContainer(
          overrides: [
            modoDistribuidorProvider.overrideWithValue(modo),
            baseProvider.overrideWithValue(base),
            almacenSesionProvider.overrideWithValue(AlmacenEnMemoria(sesion)),
          ],
        );
        addTearDown(c.dispose);
        expect(c.read(comprobadorProvider).clave, clave);
      }
    });
  });

  group('en pantalla (franja del armazón, modo distribuidor)', () {
    List<PantallaRegistrada> pantallas() => <PantallaRegistrada>[
      PantallaRegistrada(
        ruta: '/uno',
        titulo: 'Uno',
        icono: Icons.looks_one_outlined,
        enElMenu: true,
        colecciones: ColeccionesDePantalla.ninguna,
        construir: (contexto, estado) => const Text('cuerpo de uno'),
      ),
    ];

    Future<void> asentar(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> montarApp(
      WidgetTester tester,
      ComprobadorDeActualizacion comprobador,
    ) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            modoDistribuidorProvider.overrideWithValue(true),
            trabajaSinConexionProvider.overrideWithValue(true),
            comprobadorProvider.overrideWithValue(comprobador),
          ],
          child: RepartoApp(
            enrutador: crearEnrutador(pantallas: pantallas(), inicial: '/uno'),
          ),
        ),
      );
      await asentar(tester);
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
    }

    testWidgets(
      'hay versión nueva: la franja la dice y ofrece cómo instalarla',
      (tester) async {
        final m = montar(
          (p) async => RespuestaFalsa(200, cuerpo(distribuidor: anuncio(58))),
        );
        await montarApp(tester, m.comprobador);
        expect(find.text('Hay una versión nueva: 1.0.1'), findsOneWidget);
        expect(find.text('Cómo instalarla'), findsOneWidget);
        await desmontar(tester);
      },
    );

    testWidgets('el cajón enseña el tamaño y el botón de descargar', (
      tester,
    ) async {
      final m = montar(
        (p) async => RespuestaFalsa(200, cuerpo(distribuidor: anuncio(58))),
      );
      await montarApp(tester, m.comprobador);
      await tester.tap(find.text('Cómo instalarla'));
      await asentar(tester);
      expect(find.textContaining('MB'), findsWidgets);
      expect(find.text('Descargar e instalar'), findsOneWidget);
      expect(find.text('Versión 1.0.1'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets(
      'con cola pendiente dice que primero sube, sin botón de instalar',
      (tester) async {
        final cola = ColaDeSalida(base);
        await cola.encolar(
          metodo: 'POST',
          ruta: '/api/routes/r1/results',
          cuerpo: const {'x': 1},
        );
        final m = montar(
          (p) async => RespuestaFalsa(200, cuerpo(distribuidor: anuncio(58))),
        );
        await montarApp(tester, m.comprobador);
        expect(
          find.textContaining('antes hay que subir el trabajo'),
          findsOneWidget,
        );
        expect(find.textContaining('Te queda 1 cosa'), findsOneWidget);
        expect(find.text('Cómo instalarla'), findsNothing);
        await desmontar(tester);
      },
    );

    testWidgets('al día o sin anuncio: no sale nada', (tester) async {
      final m = montar((p) async => RespuestaFalsa(200, cuerpo()));
      await montarApp(tester, m.comprobador);
      expect(find.textContaining('versión nueva'), findsNothing);
      await desmontar(tester);
    });

    testWidgets(
      'sin red al arrancar no sale nada; al volver la red se pregunta UNA vez y sale',
      (tester) async {
        var hayRed = false;
        final m = montar(
          (p) async => hayRed
              ? RespuestaFalsa(200, cuerpo(distribuidor: anuncio(58)))
              : null,
        );
        await montarApp(tester, m.comprobador);
        expect(m.servidor.vistas, hasLength(1));
        expect(find.textContaining('versión nueva'), findsNothing);

        final salud = ProviderScope.containerOf(
          tester.element(find.byType(RepartoApp)),
        ).read(saludDeLaRedProvider.notifier);
        for (var i = 0; i < 3; i++) {
          salud.anotarIntento(llego: false);
        }
        await asentar(tester);
        expect(
          m.servidor.vistas,
          hasLength(1),
          reason: 'la red va mal: no se insiste ni se hace sondeo',
        );

        hayRed = true;
        salud.anotarIntento(llego: true);
        await asentar(tester);
        expect(m.servidor.vistas, hasLength(2));
        expect(find.text('Hay una versión nueva: 1.0.1'), findsOneWidget);

        // Ya sabido: otra buena no vuelve a preguntar.
        salud.anotarIntento(llego: true);
        await asentar(tester);
        expect(m.servidor.vistas, hasLength(2));
        await desmontar(tester);
      },
    );
  });
}
