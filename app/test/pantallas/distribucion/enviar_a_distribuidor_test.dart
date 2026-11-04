// «ENVIAR A DISTRIBUIDOR» y el estado del enlace (tareas 1 y 2), contra un servidor de mentira.
//
// Lo que se vigila:
//  * el enlace se pide SIEMPRE al servidor al pulsar (`POST /routes/<id>/enlace`), tambien en la APK y en Windows;
//  * WhatsApp / Compartir / Copiar reciben el mensaje corto con el enlace;
//  * el estado dice «Sin enlace», «Sin reclamar» o «Asignada a <telefono> el <fecha>»;
//  * «Soltar y mandar a otro telefono» pregunta antes y manda `renovar: true`;
//  * sin red, o con la ruta cerrada, la pantalla lo dice con su motivo y no finge.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/distribucion/datos/api_distribucion.dart';
import 'package:reparto/pantallas/distribucion/vista/enviar_a_distribuidor.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/aparato_espia.dart';
import '../../apoyo/servidor_falso.dart';
import '../rutas/rutas_a_mano.dart';

void main() {
  late AparatoEspia aparato;
  late ServidorFalso servidor;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;
  const url = 'https://reparto.procovar.cloud/r/tok1';

  setUp(() {
    aparato = AparatoEspia();
    contesta = (_) async => RespuestaFalsa(200, {'estado': 'sin_enlace'});
    servidor = ServidorFalso((p) => contesta(p));
  });

  RutaConTodo laRuta({
    String id = 'R1',
    String estado = EstadoRuta.planificada,
    bool conVehiculo = true,
  }) {
    final base = rutaAMano(
      id: id,
      nombre: 'Reparto Vista',
      paradas: [
        paradaAMano(id: 'p1', cliente: 'Uno'),
        paradaAMano(id: 'p2', cliente: 'Dos'),
      ],
    );
    return RutaConTodo(
      ruta: base.ruta.copyWith(
        status: estado,
        vehicleId: conVehiculo ? const Value('V1') : const Value(null),
      ),
      paradas: base.paradas,
      vehiculo: conVehiculo ? camionAMano() : null,
    );
  }

  /// Dio contesta con temporizadores: se avanza el reloj falso unos instantes.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pintar(WidgetTester tester, RutaConTodo ruta) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          abrirYCompartirProvider.overrideWithValue(aparato),
          apiDistribucionProvider.overrideWithValue(
            ApiDistribucion(ClienteApi(dio: dio, esperas: const <Duration>[])),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EnviarADistribuidor(ruta: ruta)),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  group('el estado del enlace', () {
    testWidgets('sin enlace', (tester) async {
      await pintar(tester, laRuta());
      expect(find.textContaining('Sin enlace'), findsOneWidget);
      expect(servidor.vistas.single.metodo, 'GET');
      expect(servidor.vistas.single.ruta, '/routes/R1/enlace');
    });

    testWidgets('sin reclamar', (tester) async {
      contesta = (_) async => RespuestaFalsa(200, {
        'token': 't',
        'url': url,
        'estado': 'sin_reclamar',
      });
      await pintar(tester, laRuta());
      expect(find.textContaining('Sin reclamar'), findsOneWidget);
      expect(find.byKey(claveDeSoltarLaRuta), findsNothing);
    });

    testWidgets('asignada a un telefono, con su fecha, y se ofrece soltarla', (
      tester,
    ) async {
      contesta = (_) async => RespuestaFalsa(200, {
        'token': 't',
        'url': url,
        'estado': 'reclamado',
        'dispositivo': 'Samsung A16 de Felix',
        'reclamadoAt': '2026-11-04T15:30:00Z',
      });
      await pintar(tester, laRuta());
      expect(
        find.textContaining('Asignada a Samsung A16 de Felix el'),
        findsOneWidget,
      );
      expect(find.byKey(claveDeSoltarLaRuta), findsOneWidget);
    });

    testWidgets('si no se pudo comprobar, se dice por que', (tester) async {
      contesta = (_) async => null;
      await pintar(tester, laRuta());
      expect(
        find.textContaining(
          'No se pudo comprobar el enlace: Sin conexión con el servidor.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'una ruta armada sin red (id local-) no pregunta al servidor y lo explica',
      (tester) async {
        await pintar(tester, laRuta(id: 'local-ab12'));
        expect(servidor.vistas, isEmpty);
        expect(
          find.textContaining('todavía no ha subido al servidor'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(claveDeEnviarWhatsApp))
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('una ruta cerrada no se puede enviar y se dice', (
      tester,
    ) async {
      await pintar(tester, laRuta(estado: EstadoRuta.completada));
      expect(find.textContaining('ya está cerrada'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(claveDeEnviarWhatsApp))
            .onPressed,
        isNull,
      );
    });
  });

  group('el vehículo de la ruta', () {
    testWidgets('se enseña el vehículo que lleva el enlace', (tester) async {
      await pintar(tester, laRuta());
      expect(find.text('Vehículo: Camión 1 (P-001)'), findsOneWidget);
    });

    testWidgets('una ruta SIN vehículo no se puede enviar y lo dice', (
      tester,
    ) async {
      await pintar(tester, laRuta(conVehiculo: false));
      expect(
        find.textContaining('Esta ruta no tiene vehículo'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(claveDeEnviarWhatsApp))
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'si el servidor da 409 por falta de vehículo, sale su frase literal',
      (tester) async {
        await pintar(tester, laRuta());
        contesta = (_) async => RespuestaFalsa(409, {
          'error': 'Asigna un vehículo a la ruta antes de enviarla.',
        });
        await tester.tap(find.byKey(claveDeEnviarWhatsApp));
        await asentar(tester);
        expect(aparato.abiertos, isEmpty);
        expect(
          find.text('Asigna un vehículo a la ruta antes de enviarla.'),
          findsOneWidget,
        );
      },
    );
  });

  group('lo que sale al pulsar', () {
    setUp(() {
      contesta = (p) async => p.metodo == 'POST'
          ? RespuestaFalsa(201, {
              'token': 'tok1',
              'url': url,
              'estado': 'sin_reclamar',
            })
          : RespuestaFalsa(200, {'estado': 'sin_enlace'});
    });

    testWidgets('WhatsApp crea el enlace en vivo y manda el mensaje corto', (
      tester,
    ) async {
      await pintar(tester, laRuta());
      await tester.tap(find.byKey(claveDeEnviarWhatsApp));
      await asentar(tester);

      final post = servidor.vistas.firstWhere((p) => p.metodo == 'POST');
      expect(post.ruta, '/routes/R1/enlace');
      expect(post.cuerpo, isEmpty);
      final texto = aparato.abiertos.single.queryParameters['text']!;
      expect(
        texto,
        contains('Tu ruta RT-001 · Reparto Vista · 14/9/2026 · 2 paradas:'),
      );
      expect(texto, contains('\n$url\n'));
      expect(texto, contains('Reparto Distribuidor'));
      expect(texto, isNot(contains('google')));
    });

    testWidgets('Compartir y Copiar reciben el mismo mensaje', (tester) async {
      await pintar(tester, laRuta());
      await tester.tap(find.byKey(claveDeEnviarCompartir));
      await asentar(tester);
      await tester.tap(find.byKey(claveDeEnviarCopiar));
      await asentar(tester);

      expect(aparato.compartidos.single.asunto, 'Ruta RT-001');
      expect(aparato.compartidos.single.texto, aparato.copiados.single);
      expect(aparato.copiados.single, contains(url));
    });

    testWidgets('sin red NO se manda nada y se dice por que', (tester) async {
      await pintar(tester, laRuta());
      contesta = (_) async => null;
      await tester.tap(find.byKey(claveDeEnviarWhatsApp));
      await asentar(tester);

      expect(aparato.abiertos, isEmpty);
      expect(find.byKey(claveDeAvisoDelEnlace), findsOneWidget);
      expect(find.text('Sin conexión con el servidor.'), findsOneWidget);
    });

    testWidgets(
      'si el servidor la rechaza (409, cerrada), sale su frase literal',
      (tester) async {
        await pintar(tester, laRuta());
        contesta = (_) async =>
            RespuestaFalsa(409, {'error': 'La ruta ya está cerrada'});
        await tester.tap(find.byKey(claveDeEnviarCopiar));
        await asentar(tester);

        expect(aparato.copiados, isEmpty);
        expect(find.text('La ruta ya está cerrada'), findsOneWidget);
      },
    );
  });

  testWidgets('soltar pregunta antes y renueva el enlace', (tester) async {
    contesta = (p) async => p.metodo == 'POST'
        ? RespuestaFalsa(200, {
            'token': 'nuevo',
            'url': url,
            'estado': 'sin_reclamar',
          })
        : RespuestaFalsa(200, {
            'url': url,
            'estado': 'reclamado',
            'dispositivo': 'Tel',
          });
    await pintar(tester, laRuta());

    await tester.tap(find.byKey(claveDeSoltarLaRuta));
    await tester.pumpAndSettle();
    // Preguntó y todavía no ha hecho nada.
    expect(servidor.vistas.where((p) => p.metodo == 'POST'), isEmpty);

    // Decir que no lo deja como está.
    await tester.tap(find.text('No, dejarla como está'));
    await tester.pumpAndSettle();
    expect(servidor.vistas.where((p) => p.metodo == 'POST'), isEmpty);

    await tester.tap(find.byKey(claveDeSoltarLaRuta));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(claveDeConfirmarSoltar));
    await tester.pumpAndSettle();

    final post = servidor.vistas.singleWhere((p) => p.metodo == 'POST');
    expect(post.cuerpo, {'renovar': true});
    expect(find.textContaining('Ruta soltada'), findsOneWidget);
  });
}
