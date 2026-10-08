// EL CIERRE DE RUTA SALE DE VERDAD, Y NO PIERDE UNA NOTA EDITADA — 08/10/2026.
//
// Auditoría del arreglo del issue 2 de Amado («Tienes 0 sin guardar»): las pruebas
// de `cierre_parcial_se_acusa_test.dart` montan el cierre como ÚNICA ruta, y un pop
// sobre la única ruta no hace nada, así que no demostraban que tras guardar bien el
// cajón SE CIERRA (quitar el `volver.pop()` del arreglo dejaba todo en verde).
//
// Aquí el cajón se abre con `abrirCajon` sobre una pantalla de debajo (inicio →
// PANTALLA 2 → cajón): tras guardar se tiene que ver el cajón fuera, ninguna
// pregunta, y PANTALLA 2 intacta (un pop de más la cerraría también).
//
// Y el fallo previo que salió de la misma auditoría: editar SÓLO la nota de una marca
// ya guardada y dar atrás salía SIN preguntar (escribir en el campo no redibujaba,
// `canPop` seguía con el valor del último dibujo) y la nota se perdía en silencio.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart' show abrirCajon;
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
  final hora = DateTime(2026, 10, 8, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', estado: EstadoRuta.enCurso, codigo: 'RT-1');
    for (final (i, n) in <String>['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(base, id: 'p${i + 1}', cliente: n, rutaId: 'R1', orden: i + 1);
    }
  }

  var alCompletarLlamado = false;

  /// Tres pisos: inicio -> PANTALLA 2 -> cajon del cierre. Un pop de mas se ve
  /// porque PANTALLA 2 desaparece.
  Future<void> montar(
    WidgetTester tester, {
    required ModoDelCierre modo,
    bool web = true,
    Future<RespuestaFalsa?> Function(PeticionVista)? dice,
  }) async {
    alCompletarLlamado = false;
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    final responde = dice ?? (p) async => RespuestaFalsa(200);
    servidor = ServidorFalso(responde);
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => hora),
          if (web)
            accionesDeRutaProvider.overrideWith(
              (ref) => AccionesDeRuta(
                base,
                ref.watch(colaProvider),
                reloj: () => hora,
                sufijoAparato: 'WEB',
                enVivo: EscrituraEnVivo(ClienteApi(dio: dio, esperas: const <Duration>[])),
              ),
            ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Column(
                children: [
                  const Text('INICIO'),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).push(
                      MaterialPageRoute<void>(
                        builder: (c2) => Scaffold(
                          body: Column(
                            children: [
                              const Text('PANTALLA 2'),
                              TextButton(
                                onPressed: () => abrirCajon<void>(
                                  c2,
                                  (_) => CierreDeRuta(
                                    rutaId: 'R1',
                                    modo: modo,
                                    alCompletar: () => alCompletarLlamado = true,
                                  ),
                                ),
                                child: const Text('ABRIR'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('IR'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
    await tester.tap(find.text('IR'));
    await asentar(tester);
    await tester.tap(find.text('ABRIR'));
    await asentar(tester);
    expect(find.text('Cierre de ruta'), findsOneWidget);
  }

  Finder botonDeParada(String t, int i) => find.widgetWithText(OutlinedButton, t).at(i + 1);

  Future<void> marcarDos(WidgetTester tester) async {
    await tester.tap(botonDeParada('Entregado', 0));
    await tester.tap(botonDeParada('Entregado', 1));
    await asentar(tester);
  }

  Future<void> pulsar(WidgetTester tester, String boton) async {
    await tester.tap(find.widgetWithText(FilledButton, boton));
    await asentar(tester);
  }

  void cajonCerradoYPantalla2(String quien) {
    expect(find.text('Cierre de ruta'), findsNothing, reason: '$quien: el cajon sigue abierto');
    expect(find.textContaining('sin guardar'), findsNothing, reason: '$quien: pregunta');
    expect(find.text('PANTALLA 2'), findsOneWidget, reason: '$quien: pop de mas o de menos');
  }

  RespuestaFalsa parcial() => RespuestaFalsa(409, <String, Object?>{
        'error': 'Se guardaron 1 de 2',
        'aplicados': [
          {'orderId': 'p1', 'resultado': 'entregado'},
        ],
        'rechazados': [
          {'orderId': 'p2', 'numeroOperacion': 'OP-2', 'motivo': 'no va en esta ruta'},
        ],
      });

  testWidgets('guardar y completar bien: el cajón sale, sin pregunta, y la pantalla de debajo sigue', (tester) async {
    await sembrar();
    await montar(tester, modo: ModoDelCierre.alCompletar);
    await marcarDos(tester);
    await pulsar(tester, 'Guardar y completar');
    cajonCerradoYPantalla2('completar');
    expect(alCompletarLlamado, isTrue);
    await desmontar(tester);
  });

  testWidgets('guardar SIN completar bien: el cajón sale, sin pregunta, y la pantalla de debajo sigue', (tester) async {
    await sembrar();
    await montar(tester, modo: ModoDelCierre.marcar);
    await marcarDos(tester);
    await pulsar(tester, 'Guardar 2 marcada(s)');
    cajonCerradoYPantalla2('guardar');
    await desmontar(tester);
  });

  testWidgets('sin conexión (cola): guardar cierra el cajón sin preguntar y deja el apunte encolado', (tester) async {
    await sembrar();
    await montar(tester, modo: ModoDelCierre.marcar, web: false);
    await marcarDos(tester);
    await pulsar(tester, 'Guardar 2 marcada(s)');
    cajonCerradoYPantalla2('guardar sin conexión');
    final cola = ColaDeSalida(base, reloj: () => hora);
    final pend = (await tester.runAsync(cola.lote))!;
    expect(pend.length, 1);
    await desmontar(tester);
  });

  testWidgets('sin conexión (cola): completar cierra el cajón sin preguntar y avisa a la lista', (tester) async {
    await sembrar();
    await montar(tester, modo: ModoDelCierre.alCompletar, web: false);
    await marcarDos(tester);
    await pulsar(tester, 'Guardar y completar');
    cajonCerradoYPantalla2('completar sin conexión');
    expect(alCompletarLlamado, isTrue);
    await desmontar(tester);
  });

  testWidgets('cierre parcial al completar: tras «Entendido» sale un piso sin preguntar', (tester) async {
    await sembrar();
    await montar(
      tester,
      modo: ModoDelCierre.alCompletar,
      dice: (p) async => p.metodo == 'POST' ? parcial() : RespuestaFalsa(200),
    );
    await marcarDos(tester);
    await pulsar(tester, 'Guardar y completar');
    await tester.tap(find.widgetWithText(FilledButton, 'Entendido'));
    await asentar(tester);
    cajonCerradoYPantalla2('parcial al completar');
    expect(alCompletarLlamado, isTrue);
    await desmontar(tester);
  });

  testWidgets('editar SÓLO la nota de una marca guardada y dar atrás PREGUNTA (no se pierde en silencio)', (tester) async {
    await sembrar();
    await (base.update(base.orders)..where((o) => o.id.equals('p1')))
        .write(const OrdersCompanion(
      resultado: Value(ResultadoParada.devuelto),
      resultadoNota: Value('viejo'),
    ));
    await montar(tester, modo: ModoDelCierre.marcar);
    await tester.enterText(find.byType(TextField).first, 'nuevo motivo');
    await asentar(tester);
    unawaited(tester.binding.handlePopRoute());
    await asentar(tester);
    expect(find.textContaining('Tienes 1 sin guardar'), findsOneWidget,
        reason: 'editar la nota y dar atrás no preguntaba: `canPop` se quedaba en true');
    await desmontar(tester);
  });
}
