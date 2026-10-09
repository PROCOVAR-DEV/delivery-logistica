// LA APK Y EL ESCRITORIO SE ENTERAN DE LO QUE PASO EN ACCESOS — 08/10/2026.
//
// Jose: «la web es la web y las APK son la APK; que al conectarse la APK ya
// automatico se entere». Tres cosas, todas con el portero, el renovador y el
// ciclo de verdad y un servidor de auth de mentira (nada sale de este ordenador):
//
//  A. `sesion-invalidada` por el canal NO echa a ciegas: renueva YA y el refresco
//     decide (401 -> «Tu sesion se cerro»; 403 sin_permiso -> pantalla de sin
//     permiso; 200 o sin red -> nada). La cola y la base no se tocan jamas.
//  B. Al volver la red el vigia lanza un ciclo, que renueva primero: una sesion
//     que Accesos cerro mientras no habia señal se descubre SOLA.
//  C. Cerrar sesion SIN red deja el refresco «por revocar», aparte, y se revoca
//     en cuanto hay red; se borra solo cuando el servidor confirma, y jamas sirve
//     para entrar.
//
// En pareja (CLAUDE.md §3-quinquies): cada «pasa» con su «no pasa».

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/eventos.dart';

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

Future<RespuestaFalsa?> _todoBien(PeticionVista p) async =>
    RespuestaFalsa(200, _bajadaVacia);

void main() {
  late BaseLocal base;
  late AlmacenEnMemoria almacen;
  late StreamController<String> canal;
  late StreamController<bool> red;
  late ServidorFalso auth;

  /// Lo que contesta auth, por ruta. Se cambia dentro de cada prueba.
  Future<RespuestaFalsa?> Function(PeticionVista) enRefresh = (p) async =>
      RespuestaFalsa(200, parDeTokens(refresh: 'r-2'));
  Future<RespuestaFalsa?> Function(PeticionVista) enLogout = (p) async =>
      logoutDeAccesos();

  const sesion = Sesion(token: 't', refresh: 'r-1', sub: 'u1');

  setUp(() {
    base = baseDePrueba();
    almacen = AlmacenEnMemoria(sesion);
    canal = StreamController<String>.broadcast();
    red = StreamController<bool>.broadcast();
    enRefresh = (p) async => RespuestaFalsa(200, parDeTokens(refresh: 'r-2'));
    enLogout = (p) async => logoutDeAccesos();
    auth = ServidorFalso(
      (p) => p.ruta.endsWith('/refresh') ? enRefresh(p) : enLogout(p),
    );
  });
  tearDown(() async {
    await canal.close();
    await red.close();
    await base.close();
  });

  ProviderContainer montar({bool enWeb = false}) {
    final c = ProviderContainer.test(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(!enWeb),
        navegadorProvider.overrideWithValue(NavegadorFalso()),
        entradaPorAccesosProvider.overrideWithValue(
          entradaFalsa(
            NavegadorFalso(),
            (p) async => RespuestaFalsa(401, const <String, Object?>{}),
          ),
        ),
        almacenSesionProvider.overrideWithValue(almacen),
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 8, 8)),
        dioAuthProvider.overrideWithValue(
          dioFalso((p) async => null)..httpClientAdapter = auth,
        ),
        escuchaDeEventosProvider.overrideWithValue(
          (_, _, {renovarSesion, pulso}) => canal.stream,
        ),
        avisosDeRedProvider.overrideWithValue(() => red.stream),
      ],
    );
    c.read(clienteApiProvider).dio.httpClientAdapter = ServidorFalso(_todoBien);
    c.read(clienteSyncProvider).dio.httpClientAdapter = ServidorFalso(
      _todoBien,
    );
    return c;
  }

  Future<void> respirar([int veces = 30]) async {
    for (var i = 0; i < veces; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Dentro, con el embudo escuchado como lo escucha el vigia.
  Future<void> dentro(ProviderContainer c) async {
    await c.read(porteroProvider).entro(sesion);
    await respirar();
    expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
    final sub = c.read(avisosDelServidorProvider).listen((_) {});
    addTearDown(sub.cancel);
    await respirar();
  }

  Future<String> unApunte(ProviderContainer c) => c
      .read(colaProvider)
      .encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-1',
        cuerpo: <String, Object?>{'status': 'completed'},
      );

  final avisoCerrada = avisoDeSesionInvalidada('{"tipo":"sesion-cerrada"}');
  final avisoPermisos = avisoDeSesionInvalidada(
    '{"tipo":"permisos-cambiados"}',
  );

  // ---------------------------------------------------------------------------
  // A · `sesion-invalidada` en un aparato: renueva YA y el refresco decide
  // ---------------------------------------------------------------------------

  group('A · el aviso del canal en la APK y el escritorio', () {
    test('refresco 401 (Accesos cerro la sesion): login con «Tu sesion se '
        'cerro», y la cola intacta', () async {
      final c = montar();
      await dentro(c);
      await aparatoYaDeAlta(base);
      final clave = await unApunte(c);
      enRefresh = (p) async =>
          RespuestaFalsa(401, <String, Object?>{'error': 'revoked'});

      canal.add(avisoCerrada);
      await respirar();

      final portero = c.read(porteroProvider);
      expect(auth.cuantas('POST', '/refresh'), 1, reason: 'renueva YA');
      expect(portero.estado, EstadoDeAcceso.fuera);
      expect(portero.avisoDeSesion, textoDeSesionCerrada);
      expect(
        (await c.read(colaProvider).porClave(clave))!.estado,
        EstadoApunte.pendiente,
        reason: 'la cola NO se toca jamas: el trabajo del dia sigue ahi',
      );
    });

    test(
      'refresco 403 sin_permiso: pantalla de sin permiso, sin borrar nada',
      () async {
        final c = montar();
        await dentro(c);
        await aparatoYaDeAlta(base);
        final clave = await unApunte(c);
        enRefresh = (p) async => RespuestaFalsa(403, <String, Object?>{
          'error': 'sin_permiso',
          'codigo': 'sin_permiso',
          'message': 'No tienes permiso para entrar a Reparto.',
        });

        canal.add(avisoPermisos);
        await respirar();

        expect(c.read(porteroProvider).estado, EstadoDeAcceso.sinPermiso);
        expect(c.read(porteroProvider).avisoDeSesion, isNull);
        expect(
          (await c.read(colaProvider).porClave(clave))!.estado,
          EstadoApunte.pendiente,
        );
        expect(await almacen.leer(), isNotNull, reason: 'el par se queda');
      },
    );

    test('PAREJA: refresco 200 (cambiaron permisos pero sigue entrando): no '
        'pasa nada y el par nuevo queda guardado', () async {
      final c = montar();
      await dentro(c);

      canal.add(avisoPermisos);
      await respirar();

      expect(auth.cuantas('POST', '/refresh'), 1);
      expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
      expect(c.read(porteroProvider).avisoDeSesion, isNull);
      expect((await almacen.leer())!.refresh, 'r-2');
    });

    test('PAREJA: sin red para renovar no se echa a nadie', () async {
      final c = montar();
      await dentro(c);
      enRefresh = (p) async => null; // sin red

      canal.add(avisoCerrada);
      await respirar();

      expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
      expect((await almacen.leer())!.refresh, 'r-1', reason: 'par intacto');
    });

    test('PAREJA: en la WEB no se renueva nada, la cookie manda', () async {
      final c = montar(enWeb: true);
      await dentro(c);

      canal.add(avisoCerrada);
      await respirar();

      expect(auth.cuantas('POST', '/refresh'), 0);
      expect(c.read(porteroProvider).estado, EstadoDeAcceso.fuera);
    });
  });

  // ---------------------------------------------------------------------------
  // B · Al volver la red, el aparato se entera solo
  // ---------------------------------------------------------------------------

  group('B · al recuperar la conexion', () {
    test('el vigia lanza un ciclo, que renueva: un refresco cerrado en Accesos '
        'lleva a la puerta SIN que nadie toque nada', () async {
      final c = montar();
      await dentro(c);
      final vigia = c.read(vigiaProvider)..arrancar();
      addTearDown(vigia.parar);
      final antes = auth.cuantas('POST', '/refresh');
      enRefresh = (p) async =>
          RespuestaFalsa(401, <String, Object?>{'error': 'revoked'});

      red.add(true); // vuelve la señal
      await respirar(60);

      expect(auth.cuantas('POST', '/refresh'), antes + 1);
      expect(c.read(porteroProvider).estado, EstadoDeAcceso.fuera);
    });

    test(
      'PAREJA: si Accesos sigue aceptando el refresco, no se echa a nadie',
      () async {
        final c = montar();
        await dentro(c);
        final vigia = c.read(vigiaProvider)..arrancar();
        addTearDown(vigia.parar);
        final antes = auth.cuantas('POST', '/refresh');

        red.add(true);
        await respirar(60);

        expect(
          auth.cuantas('POST', '/refresh'),
          antes + 1,
          reason: 'si renueva',
        );
        expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // C · Cerrar sesion sin conexion: «pendiente de revocar»
  // ---------------------------------------------------------------------------

  group('C · cerrar sesion sin red', () {
    Future<void> salirSinRed(ProviderContainer c) async {
      await dentro(c);
      enLogout = (p) async => null; // sin red
      await c.read(porteroProvider).salir();
      await respirar();
    }

    test('sin red al salir: la sesion local SE BORRA y el refresco queda '
        'pendiente, por persona', () async {
      final c = montar();
      await salirSinRed(c);

      expect(await almacen.leer(), isNull, reason: 'la sesion local se borra');
      final pendientes = await almacen.porRevocar();
      expect(pendientes.map((r) => (r.sub, r.refresh)), [('u1', 'r-1')]);
      expect(c.read(porteroProvider).estado, EstadoDeAcceso.fuera);
    });

    test('PAREJA: con red al salir no queda nada pendiente', () async {
      final c = montar();
      await dentro(c);

      await c.read(porteroProvider).salir();
      await respirar();

      expect(auth.cuantas('POST', '/logout'), 1);
      expect(await almacen.porRevocar(), isEmpty);
    });

    test('con red despues: se revoca y el hueco desaparece', () async {
      final c = montar();
      await salirSinRed(c);
      enLogout = (p) async => logoutDeAccesos();

      red.add(true); // vuelve la señal, con la persona en la puerta
      await respirar();

      expect(
        auth.vistas
            .where((p) => p.ruta.endsWith('/logout') && p.cuerpo != null)
            .last
            .cuerpo,
        {'refresh_token': 'r-1'},
        reason: 'revoca EL refresco que se guardo',
      );
      expect(await almacen.porRevocar(), isEmpty);
    });

    test(
      'si el servidor responde 5xx sigue pendiente, y se reintenta',
      () async {
        final c = montar();
        await salirSinRed(c);
        enLogout = (p) async =>
            RespuestaFalsa(503, <String, Object?>{'error': 'no disponible'});

        red.add(true);
        await respirar();
        expect(
          (await almacen.porRevocar()).length,
          1,
          reason: 'un 5xx NO es confirmacion: se queda para el proximo intento',
        );

        enLogout = (p) async => logoutDeAccesos();
        red.add(true);
        await respirar();
        expect(await almacen.porRevocar(), isEmpty);
      },
    );

    test(
      'un 401 de nuestro servidor es «ya cerrado»: tambien se limpia',
      () async {
        final c = montar();
        await salirSinRed(c);
        enLogout = (p) async =>
            RespuestaFalsa(401, <String, Object?>{'error': 'revoked'});

        red.add(true);
        await respirar();

        expect(await almacen.porRevocar(), isEmpty);
      },
    );

    test('al arrancar la aplicacion tambien se revoca', () async {
      final c = montar();
      await salirSinRed(c);
      enLogout = (p) async => logoutDeAccesos();

      // «Arrancar de nuevo»: un portero nuevo sobre el mismo almacen.
      final otro = montar();
      await otro.read(porteroProvider).comprobar();
      await respirar(60);

      expect(await almacen.porRevocar(), isEmpty);
    });

    test(
      'NO SIRVE PARA ENTRAR: con un refresco pendiente y sin sesion, el '
      'arranque va a la puerta y nunca presenta ese refresco a /refresh',
      () async {
        final c = montar();
        await salirSinRed(c);
        enLogout = (p) async => null; // sigue sin red al arrancar

        final otro = montar();
        await otro.read(porteroProvider).comprobar();
        await respirar(60);

        expect(otro.read(porteroProvider).estado, EstadoDeAcceso.fuera);
        expect(otro.read(porteroProvider).sesion, isNull);
        expect(await almacen.leer(), isNull);
        expect(
          auth.cuantas('POST', '/refresh'),
          0,
          reason: 'el refresco por revocar no autentica NADA, ni renueva',
        );
        expect((await almacen.porRevocar()).length, 1);
      },
    );
  });
}
