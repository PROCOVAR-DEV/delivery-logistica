// UN CIERRE PARCIAL EN LA WEB SE ACUSA, NO SE AVISA — 08/10/2026.
//
// La auditoría de la 1.0.28 (I-3): si el servidor guardaba unas paradas y
// rechazaba otras (409 con `aplicados` y `rechazados`), el cierre lo decía en un
// SNACKBAR de 8 segundos que sustituía a «Ruta completada»; después la ruta se
// completaba (el histórico es inmutable) y la entrega rechazada quedaba sin
// registrar con nadie que la hubiera leído.
//
// Ahora es un cajón que OBLIGA a acusar recibo: «Entendido» es lo único que lo
// cierra y cada parada sale con su conduce. Las pruebas van en pareja con lo que
// no debe pasar: un cierre bueno NO abre cajón, y cerrarlo de cualquier otra
// forma NO cuenta y vuelve a salir.
//
// Se monta la pantalla de verdad contra un servidor falso, para que el 409 pase
// por el parseo real de `AccionesDeRuta.cerrar` y no por un resultado fabricado.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import '../pedidos/sembrar.dart';
import 'cierre_widget_test.dart' show asentar, desmontar;

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;
  final laHoraDelPatio = DateTime(2026, 10, 8, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Catálogo, ruta y tres paradas. **Dentro del cuerpo de cada prueba**, nunca
  /// en el `setUp` (`CLAUDE.md` §5).
  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-20261008-001',
    );
    for (final (i, nombre) in <String>['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: nombre,
        rutaId: 'R1',
        orden: i + 1,
      );
    }
  }

  Future<String?> estadoDeLaRuta() async {
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals('R1'))).getSingleOrNull();
    return ruta?.status;
  }

  /// El 409 parcial de `POST /routes/R1/results`: `p1` guardada, `p2` no.
  /// [rechazadas] son los elementos de `rechazados[]` tal y como los manda el
  /// servidor (`api/internal/api/rutas.go`, `rechazadoDeCierre`).
  RespuestaFalsa parcial(List<Map<String, Object?>> rechazadas) =>
      RespuestaFalsa(409, <String, Object?>{
        'error': 'Se guardaron 1 de las 2 paradas de esta hoja.',
        'aplicados': [
          {'orderId': 'p1', 'resultado': 'entregado'},
        ],
        'rechazados': rechazadas,
      });

  Future<void> pintar(
    WidgetTester tester, {
    required ModoDelCierre modo,
    required Future<RespuestaFalsa?> Function(PeticionVista) servidorDice,
    VoidCallback? alCompletar,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    contesta = servidorDice;
    servidor = ServidorFalso((p) => contesta(p));
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => laHoraDelPatio),
          // EN LA WEB: las acciones van al servidor y esperan.
          accionesDeRutaProvider.overrideWith(
            (ref) => AccionesDeRuta(
              base,
              ref.watch(colaProvider),
              reloj: () => laHoraDelPatio,
              sufijoAparato: 'WEB',
              enVivo: EscrituraEnVivo(
                ClienteApi(dio: dio, esperas: const <Duration>[]),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CierreDeRuta(
              rutaId: 'R1',
              modo: modo,
              alCompletar: alCompletar,
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Finder botonDeParada(String texto, int parada) =>
      find.widgetWithText(OutlinedButton, texto).at(parada + 1);

  /// Entregada la primera y la segunda, y a guardar y completar.
  Future<void> marcarDosYGuardar(WidgetTester tester, String boton) async {
    await tester.tap(botonDeParada('Entregado', 0));
    await tester.tap(botonDeParada('Entregado', 1));
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, boton));
    await asentar(tester);
  }

  final elAcuse = find.widgetWithText(FilledButton, 'Entendido');

  Future<RespuestaFalsa?> Function(PeticionVista) servidorQueRechazaLaSegunda(
    List<Map<String, Object?>> rechazadas,
  ) => (p) async =>
      p.metodo == 'POST' ? parcial(rechazadas) : RespuestaFalsa(200);

  testWidgets('un cierre BUENO no abre cajón: snackbar de siempre y a la lista', (
    tester,
  ) async {
    await sembrar();
    var volvioALaLista = false;
    await pintar(
      tester,
      modo: ModoDelCierre.alCompletar,
      alCompletar: () => volvioALaLista = true,
      servidorDice: (p) async => RespuestaFalsa(200),
    );

    await marcarDosYGuardar(tester, 'Guardar y completar');

    expect(servidor.cuantas('POST', '/routes/R1/results'), 1);
    expect(elAcuse, findsNothing);
    expect(find.textContaining('no se guard'), findsNothing);
    // Issue 2 de Amado, 08/10/2026: tras guardar bien salía «Tienes 0 sin
    // guardar». `PopScope.canPop` seguía con el valor del dibujo anterior al
    // guardado, y la pregunta salía con la hoja ya sin nada que perder.
    expect(find.textContaining('sin guardar'), findsNothing);
    expect(find.text('Salir y perderlas'), findsNothing);
    expect(find.text(CierreDeRuta.exitoAlCompletar), findsOneWidget);
    expect(await estadoDeLaRuta(), EstadoRuta.completada);
    expect(volvioALaLista, isTrue);

    await desmontar(tester);
  });

  testWidgets('guardar SIN completar tampoco pregunta «¿salir sin guardar?»', (
    tester,
  ) async {
    await sembrar();
    await pintar(
      tester,
      modo: ModoDelCierre.marcar,
      servidorDice: (p) async => RespuestaFalsa(200),
    );

    await marcarDosYGuardar(tester, 'Guardar 2 marcada(s)');

    expect(servidor.cuantas('POST', '/routes/R1/results'), 1);
    expect(find.textContaining('sin guardar'), findsNothing);
    expect(find.text('Salir y perderlas'), findsNothing);
    expect(find.text(CierreDeRuta.exito), findsOneWidget);
    expect(await estadoDeLaRuta(), EstadoRuta.enCurso);

    await desmontar(tester);
  });

  testWidgets('un cierre PARCIAL abre el cajón con el conduce y el motivo', (
    tester,
  ) async {
    await sembrar();
    var volvioALaLista = false;
    await pintar(
      tester,
      modo: ModoDelCierre.alCompletar,
      alCompletar: () => volvioALaLista = true,
      servidorDice: servidorQueRechazaLaSegunda([
        {
          'orderId': 'p2',
          'numeroOperacion': 'PTB25-261005-1480',
          'motivo': 'ese pedido no va en esta ruta',
        },
      ]),
    );

    await marcarDosYGuardar(tester, 'Guardar y completar');

    expect(find.text('Ruta completada: 1 parada no se guardó'), findsOneWidget);
    expect(
      find.text('Conduce PTB25-261005-1480: ese pedido no va en esta ruta'),
      findsOneWidget,
    );
    expect(elAcuse, findsOneWidget);
    // El snackbar que sustituía a «Ruta completada» ya no existe.
    expect(find.text(CierreDeRuta.exitoAlCompletar), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Lo guardado vale y la ruta se completó; pero NO se sale hasta acusar.
    expect(await estadoDeLaRuta(), EstadoRuta.completada);
    expect(volvioALaLista, isFalse, reason: 'sin acuse no se va a la lista');

    await tester.tap(elAcuse);
    await asentar(tester);
    expect(elAcuse, findsNothing);
    expect(volvioALaLista, isTrue);

    await desmontar(tester);
  });

  testWidgets('cerrar el cajón de cualquier otra forma NO es acusar: vuelve a salir', (
    tester,
  ) async {
    await sembrar();
    var volvioALaLista = false;
    await pintar(
      tester,
      modo: ModoDelCierre.alCompletar,
      alCompletar: () => volvioALaLista = true,
      servidorDice: servidorQueRechazaLaSegunda([
        {
          'orderId': 'p2',
          'numeroOperacion': 'PTB25-261005-1480',
          'motivo': 'ese pedido no va en esta ruta',
        },
      ]),
    );
    await marcarDosYGuardar(tester, 'Guardar y completar');
    expect(elAcuse, findsOneWidget);

    // Tocar fuera (el velo)...
    await tester.tapAt(const Offset(10, 10));
    await asentar(tester);
    expect(elAcuse, findsOneWidget, reason: 'el velo no es un acuse');

    // ...Escape...
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await asentar(tester);
    expect(elAcuse, findsOneWidget, reason: 'Escape no es un acuse');

    // ...y la ✕ de la cabecera.
    await tester.tap(find.byIcon(Icons.close).last);
    await asentar(tester);
    expect(elAcuse, findsOneWidget, reason: 'la ✕ no es un acuse');
    expect(volvioALaLista, isFalse);

    await tester.tap(elAcuse);
    await asentar(tester);
    expect(elAcuse, findsNothing);
    expect(volvioALaLista, isTrue);

    await desmontar(tester);
  });

  testWidgets('un servidor VIEJO sin numeroOperacion: sale con el orderId', (
    tester,
  ) async {
    await sembrar();
    await pintar(
      tester,
      modo: ModoDelCierre.alCompletar,
      // Sin `numeroOperacion` (servidor viejo) y con `""` (pedido sin número o
      // fuera del alcance): las dos caen al id, y son DOS paradas rechazadas.
      servidorDice: (p) async => p.metodo != 'POST'
          ? RespuestaFalsa(200)
          : RespuestaFalsa(409, <String, Object?>{
              'error': 'Se guardaron 1 de las 3 paradas de esta hoja.',
              'aplicados': [
                {'orderId': 'p1', 'resultado': 'entregado'},
              ],
              'rechazados': [
                {'orderId': 'p2', 'motivo': 'ese pedido no va en esta ruta'},
                {
                  'orderId': 'p3',
                  'numeroOperacion': '',
                  'motivo': 'ese pedido ya va en otra ruta',
                },
              ],
            }),
    );

    await tester.tap(botonDeParada('Entregado', 0));
    await tester.tap(botonDeParada('Entregado', 1));
    await tester.tap(botonDeParada('Entregado', 2));
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar y completar'));
    await asentar(tester);

    expect(find.text('Ruta completada: 2 paradas no se guardaron'), findsOneWidget);
    expect(
      find.text('Conduce p2: ese pedido no va en esta ruta'),
      findsOneWidget,
    );
    expect(
      find.text('Conduce p3: ese pedido ya va en otra ruta'),
      findsOneWidget,
    );

    await tester.tap(elAcuse);
    await asentar(tester);
    await desmontar(tester);
  });

  testWidgets('si sólo se guarda (sin completar) la hoja se queda y el título no dice «Ruta completada»', (
    tester,
  ) async {
    await sembrar();
    await pintar(
      tester,
      modo: ModoDelCierre.marcar,
      servidorDice: servidorQueRechazaLaSegunda([
        {
          'orderId': 'p2',
          'numeroOperacion': 'PTB25-261005-1480',
          'motivo': 'ese pedido no va en esta ruta',
        },
      ]),
    );

    await marcarDosYGuardar(tester, 'Guardar 2 marcada(s)');

    expect(find.text('1 parada no se guardó'), findsOneWidget);
    expect(find.textContaining('Ruta completada'), findsNothing);
    expect(
      find.text('Conduce PTB25-261005-1480: ese pedido no va en esta ruta'),
      findsOneWidget,
    );
    expect(await estadoDeLaRuta(), EstadoRuta.enCurso);

    await tester.tap(elAcuse);
    await asentar(tester);
    expect(elAcuse, findsNothing);
    // La hoja sigue ahí, con la rechazada todavía por guardar.
    expect(find.text('Cierre de ruta'), findsOneWidget);
    expect(find.textContaining('1 sin guardar'), findsOneWidget);

    await desmontar(tester);
  });
}
