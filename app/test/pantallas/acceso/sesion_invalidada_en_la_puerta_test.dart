// QUE VE LA PERSONA CUANDO ACCESOS LE CIERRA LA SESION (solo la web) — 08/10/2026.
//
// De punta a punta, con la aplicacion de verdad montada: el aviso entra por el
// canal (un doble que empuja strings, sin red), el embudo se lo da al portero y
// la puerta de acceso lo dice y se va a Accesos.
//
//  * el mensaje se VE antes de irse (3 s, o «Entrar ahora»);
//  * la navegacion a Accesos es UNA, aunque lleguen dos eventos y se pulse el boton;
//  * un 401 de una peticion (la cookie ya era invalida) va al login igualmente,
//    sin mensaje y sin esperar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/eventos.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_acceso.dart';

import '../../apoyo/apoyo_accesos.dart';
import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

const _bajadaVacia = <String, Object?>{
  'hasta': '2026-10-08T08:00:00Z',
  'completa': true,
  'truncado': false,
  'cambios': <String, Object?>{},
  'sucursales': <Object?>[],
};

const _irAAccesos = '$baseApiDePrueba/auth/entrar';

/// La aplicacion web montada y DENTRO (con sesion de Accesos).
class _WebDentro {
  _WebDentro(this.c, this.navegador, this.canal);

  final ProviderContainer c;
  final NavegadorFalso navegador;
  final StreamController<String> canal;
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<_WebDentro> montarDentro(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = baseDePrueba();
    addTearDown(base.close);
    await aparatoYaConfigurado(base);

    final navegador = NavegadorFalso();
    final canal = StreamController<String>.broadcast();
    addTearDown(canal.close);

    final c = ProviderContainer(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(false),
        navegadorProvider.overrideWithValue(navegador),
        entradaPorAccesosProvider.overrideWithValue(
          entradaFalsa(
            navegador,
            (p) async => RespuestaFalsa(
              200,
              respuestaDeApiMe(token: tokenDePrueba(sub: 'u-7')),
            ),
          ),
        ),
        almacenSesionProvider.overrideWithValue(AlmacenEnMemoria()),
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 8, 8, 30)),
        dioAuthProvider.overrideWithValue(
          dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
        ),
        escuchaDeEventosProvider.overrideWithValue(
          (_, _, {renovarSesion, pulso}) => canal.stream,
        ),
      ],
    );
    final web = _WebDentro(c, navegador, canal);
    Future<RespuestaFalsa?> api(PeticionVista p) async =>
        RespuestaFalsa(200, _bajadaVacia);
    c.read(clienteApiProvider).dio.httpClientAdapter = ServidorFalso(api);
    c.read(clienteSyncProvider).dio.httpClientAdapter = ServidorFalso(api);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const RepartoApp()),
    );
    await tester.pumpAndSettle();
    expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
    expect(find.text('Panel'), findsWidgets);
    return web;
  }

  /// Desmontar aqui y no en un `tearDown`: las consultas de Drift sueltan un
  /// temporizador al cancelarse y flutter_test lo comprueba ANTES de los
  /// `tearDown`.
  Future<void> desmontar(WidgetTester tester, _WebDentro web) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    web.c.dispose();
    // Drift deja un temporizador a cero al soltar sus consultas: se deja correr.
    await tester.pump(Duration.zero);
  }

  testWidgets('sesion-cerrada: se ve el mensaje, se espera, y va a Accesos UNA '
      'vez aunque lleguen dos eventos', (tester) async {
    final web = await montarDentro(tester);

    web.canal
      ..add(avisoDeSesionInvalidada('{"tipo":"sesion-cerrada"}'))
      ..add(avisoDeSesionInvalidada('{"tipo":"permisos-cambiados"}'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PantallaAcceso), findsOneWidget);
    expect(
      find.text('Tu sesión se cerró en Accesos. Vuelve a entrar.'),
      findsOneWidget,
      reason: 'la persona tiene que leer por que la sacaron',
    );
    expect(find.text('Tus permisos cambiaron. Vuelve a entrar.'), findsNothing);
    expect(web.navegador.visitados, isEmpty, reason: 'primero se lee');

    await tester.pump(const Duration(seconds: 2));
    expect(web.navegador.visitados, isEmpty);
    await tester.pump(const Duration(seconds: 2));

    expect(web.navegador.visitados, [_irAAccesos]);
    await desmontar(tester, web);
  });

  testWidgets('permisos-cambiados: el otro mensaje (PAREJA)', (tester) async {
    final web = await montarDentro(tester);

    web.canal.add(avisoDeSesionInvalidada('{"tipo":"permisos-cambiados"}'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Tus permisos cambiaron. Vuelve a entrar.'),
      findsOneWidget,
    );
    expect(find.textContaining('se cerró en Accesos'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(web.navegador.visitados, [_irAAccesos]);
    await desmontar(tester, web);
  });

  testWidgets(
    '«Entrar ahora» va YA, y el reloj de despues no navega otra vez',
    (tester) async {
      final web = await montarDentro(tester);
      web.canal.add(avisoDeSesionInvalidada('{"tipo":"sesion-cerrada"}'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Entrar ahora'));
      await tester.pump();
      expect(web.navegador.visitados, [_irAAccesos]);

      await tester.pump(const Duration(seconds: 5));
      expect(web.navegador.visitados, [
        _irAAccesos,
      ], reason: 'dos redirecciones a la vez son una pantalla rota');
      await desmontar(tester, web);
    },
  );

  testWidgets('PAREJA: un 401 de una peticion va al login AL INSTANTE, sin '
      'mensaje ni espera', (tester) async {
    final web = await montarDentro(tester);

    // Lo que hace `InterceptorSesion` con un 401 que no se puede renovar. La
    // peticion real contra el cliente real esta atada en
    // `test/navegacion/portero_sesion_invalidada_test.dart`: aqui no se puede
    // esperar a una peticion sin salir del reloj falso, y fuera de el los canales
    // de plataforma no existen.
    web.c.read(porteroProvider).murio();
    await tester.pump();
    await tester.pump();

    expect(
      web.navegador.visitados,
      [_irAAccesos],
      reason:
          'el 401 con la cookie ya invalida lleva al login unico, como '
          'siempre: la web no se queda con una pantalla vieja',
    );
    expect(find.textContaining('Vuelve a entrar'), findsNothing);
    await desmontar(tester, web);
  });
}
