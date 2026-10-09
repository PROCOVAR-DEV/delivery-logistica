// ACCESOS CIERRA LA SESION O CAMBIA LOS PERMISOS Y LA WEB SE ENTERA — 08/10/2026.
//
// Jose: «si cierro sesion o me cambian un permiso en Accesos, que se refleje en
// todas las aplicaciones, sin polling: para eso hay SSE». La api empuja el evento
// `sesion-invalidada` por `/api/eventos` y cierra esa conexion.
//
// Aqui va todo lo que NO necesita un navegador: el aviso que sale del transporte
// de la web (`avisoDeSesionInvalidada`), el embudo (`avisosDelServidorProvider`)
// y el portero real. El transporte mismo —`EventSource`— solo compila para web y
// se prueba en `test/nucleo/red/eventos_web_test.dart` (Chrome sin ventana).
//
// SIN RED: el canal es un doble que empuja strings, y a cada cliente se le pone un
// `ServidorFalso` antes de usarlo (los de verdad apuntan a `reparto.procovar.cloud`).
//
// Todo en PAREJA (`CLAUDE.md` §3-quinquies): en la web echa, en la APK no; un
// evento echa, otro de otro nombre no; dos seguidos son una salida, no dos.

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

import '../apoyo/apoyo_accesos.dart';
import '../apoyo/apoyo_sesion.dart';
import '../apoyo/base_de_prueba.dart';
import '../apoyo/servidor_falso.dart';

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
  const sesion = Sesion(token: 't', refresh: 'r', sub: 'u1');
  late BaseLocal base;
  late StreamController<String> delCanal;

  setUp(() {
    base = baseDePrueba();
    delCanal = StreamController<String>.broadcast();
  });
  tearDown(() async {
    await delCanal.close();
    await base.close();
  });

  /// El portero de verdad, con el embudo de verdad y un canal de mentira.
  ProviderContainer montar({
    bool enWeb = true,
    Future<RespuestaFalsa?> Function(PeticionVista)? api,
  }) {
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
        almacenSesionProvider.overrideWithValue(AlmacenEnMemoria()),
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 8, 8)),
        dioAuthProvider.overrideWithValue(
          dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
        ),
        escuchaDeEventosProvider.overrideWithValue(
          (_, _, {renovarSesion, pulso}) => delCanal.stream,
        ),
      ],
    );
    c.read(clienteApiProvider).dio.httpClientAdapter = ServidorFalso(
      api ?? _todoBien,
    );
    c.read(clienteSyncProvider).dio.httpClientAdapter = ServidorFalso(
      _todoBien,
    );
    return c;
  }

  Future<void> respirar() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Dentro, con el embudo escuchado (como lo escucha el vigia). Devuelve lo que
  /// sale por el embudo hacia el vigia y las pantallas.
  Future<List<String>> dentroYEscuchando(ProviderContainer c) async {
    await c.read(porteroProvider).entro(sesion);
    await respirar();
    expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
    final salida = <String>[];
    final sub = c.read(avisosDelServidorProvider).listen(salida.add);
    addTearDown(sub.cancel);
    await respirar();
    return salida;
  }

  // ---------------------------------------------------------------------------
  // 1 · El aviso que sale del transporte: JSON roto y tipos raros son «cerrada»
  // ---------------------------------------------------------------------------

  group('del `data` crudo al aviso', () {
    test('sesion-cerrada -> sesion-cerrada', () {
      final aviso = avisoDeSesionInvalidada('{"tipo":"sesion-cerrada"}');
      expect(esSesionInvalidada(aviso), isTrue);
      expect(tipoDeSesionInvalidada(aviso), tipoSesionCerrada);
    });

    test(
      'permisos-cambiados -> permisos-cambiados (PAREJA de la anterior)',
      () {
        final aviso = avisoDeSesionInvalidada('{"tipo":"permisos-cambiados"}');
        expect(esSesionInvalidada(aviso), isTrue);
        expect(tipoDeSesionInvalidada(aviso), tipoPermisosCambiados);
      },
    );

    for (final raro in <Object?>[
      '{"tipo":', // JSON roto
      'esto no es json',
      '',
      '{}',
      '{"tipo":"otra-cosa"}', // un tipo que esta version no conoce
      '{"tipo":7}',
      '[1,2]',
      null,
      42,
    ]) {
      test('«$raro» se trata como sesion-cerrada', () {
        final aviso = avisoDeSesionInvalidada(raro);
        expect(
          esSesionInvalidada(aviso),
          isTrue,
          reason:
              'un data raro no puede dejar la sesion viva: el evento ya dijo '
              'que no vale',
        );
        expect(tipoDeSesionInvalidada(aviso), tipoSesionCerrada);
      });
    }

    test('NINGUN tipo del servidor puede confundirse con el aviso', () {
      // Los tipos del servidor son una palabra sin `:`; el aviso lleva el prefijo
      // con `:`. Si algun dia un tipo lo lleva, el embudo se lo tragaria.
      for (final tipo in [
        'pedidos',
        'rutas',
        'tablero',
        'catalogo',
        'clientes',
      ]) {
        expect(esSesionInvalidada(tipo), isFalse);
      }
      expect(esSesionInvalidada(avisoDeQueVolvimos), isFalse);
      expect(prefijoDeSesionInvalidada, contains(':'));
    });
  });

  // ---------------------------------------------------------------------------
  // 2 · El embudo y el portero real
  // ---------------------------------------------------------------------------

  group('en la WEB', () {
    test('sesion-cerrada: el portero pasa a fuera con «Tu sesión se cerró…» y '
        'el aviso no llega al vigia', () async {
      final c = montar();
      final alVigia = await dentroYEscuchando(c);

      delCanal.add(avisoDeSesionInvalidada('{"tipo":"sesion-cerrada"}'));
      await respirar();

      final portero = c.read(porteroProvider);
      expect(portero.estado, EstadoDeAcceso.fuera);
      expect(
        portero.avisoDeSesion,
        'Tu sesión se cerró en Accesos. Vuelve a entrar.',
      );
      expect(portero.sesion, isNull);
      expect(
        alVigia,
        isEmpty,
        reason:
            'el aviso de sesion NO es un cambio: si llegara al vigia '
            'dispararia un ciclo contra una sesion que ya no existe',
      );
    });

    test('permisos-cambiados: el OTRO mensaje (PAREJA)', () async {
      final c = montar();
      await dentroYEscuchando(c);

      delCanal.add(avisoDeSesionInvalidada('{"tipo":"permisos-cambiados"}'));
      await respirar();

      final portero = c.read(porteroProvider);
      expect(portero.estado, EstadoDeAcceso.fuera);
      expect(portero.avisoDeSesion, 'Tus permisos cambiaron. Vuelve a entrar.');
    });

    test('JSON roto: sesion-cerrada, y se echa igual', () async {
      final c = montar();
      await dentroYEscuchando(c);

      delCanal.add(avisoDeSesionInvalidada('{"tipo":'));
      await respirar();

      expect(c.read(porteroProvider).estado, EstadoDeAcceso.fuera);
      expect(c.read(porteroProvider).avisoDeSesion, textoDeSesionCerrada);
    });

    test('dos eventos seguidos son UNA salida: un solo cambio de estado y el '
        'mensaje del primero', () async {
      final c = montar();
      await dentroYEscuchando(c);
      final portero = c.read(porteroProvider);
      var cambios = 0;
      portero.addListener(() => cambios++);

      delCanal
        ..add(avisoDeSesionInvalidada('{"tipo":"sesion-cerrada"}'))
        ..add(avisoDeSesionInvalidada('{"tipo":"permisos-cambiados"}'));
      await respirar();

      expect(portero.estado, EstadoDeAcceso.fuera);
      expect(
        cambios,
        1,
        reason:
            'cada cambio de estado del portero es una navegacion del '
            'enrutador: dos eventos no pueden ser dos',
      );
      expect(
        portero.avisoDeSesion,
        textoDeSesionCerrada,
        reason:
            'el segundo evento llega con la persona ya fuera y no pisa el '
            'mensaje del primero',
      );
    });

    test(
      'PAREJA: un evento de OTRO nombre no echa a nadie y sigue su camino',
      () async {
        final c = montar();
        final alVigia = await dentroYEscuchando(c);

        delCanal
          ..add('tablero')
          ..add(
            'sesion-invalidada',
          ) // sin el `:tipo`: no es el aviso del transporte
          ..add('sesion-cerrada'); // el tipo suelto tampoco
        await respirar();

        final portero = c.read(porteroProvider);
        expect(portero.estado, EstadoDeAcceso.dentro);
        expect(portero.avisoDeSesion, isNull);
        expect(alVigia, [
          'tablero',
          'sesion-invalidada',
          'sesion-cerrada',
        ], reason: 'lo que no es el aviso pasa tal cual hacia las pantallas');
      },
    );

    test('al volver a entrar el mensaje se va', () async {
      final c = montar();
      await dentroYEscuchando(c);
      delCanal.add(avisoDeSesionInvalidada('{"tipo":"permisos-cambiados"}'));
      await respirar();
      expect(c.read(porteroProvider).avisoDeSesion, isNotNull);

      await c.read(porteroProvider).entro(sesion);
      await respirar();

      expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
      expect(c.read(porteroProvider).avisoDeSesion, isNull);
    });
  });

  group('en la APK y el escritorio NO cambia nada', () {
    test(
      'aunque el aviso llegara, el portero no se mueve y el aviso no sigue',
      () async {
        final c = montar(enWeb: false);
        final alVigia = await dentroYEscuchando(c);

        delCanal.add(avisoDeSesionInvalidada('{"tipo":"sesion-cerrada"}'));
        await respirar();

        final portero = c.read(porteroProvider);
        expect(
          portero.estado,
          EstadoDeAcceso.dentro,
          reason:
              'la APK se va al patio de un almacen con su par: solo un 401 '
              'que sigue siendo 401 tras renovar la echa',
        );
        expect(portero.avisoDeSesion, isNull);
        expect(alVigia, isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 3 · Un 401 en la web SIEMPRE llevo al login (ya iba; aqui queda atado)
  // ---------------------------------------------------------------------------

  group('un 401 en una peticion de la web', () {
    test('lleva al portero a fuera, sin mensaje de sesion', () async {
      // Sano al entrar (el ciclo de `entro` tambien pide a la api) y roto despues:
      // la cookie caduca con la pagina abierta.
      var cookieCaducada = false;
      final c = montar(
        api: (p) async => cookieCaducada
            ? RespuestaFalsa(401, const <String, Object?>{
                'error': 'no viene token',
              })
            : RespuestaFalsa(200, _bajadaVacia),
      );
      await c.read(porteroProvider).entro(sesion);
      await respirar();
      expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);

      cookieCaducada = true;
      await expectLater(
        c.read(clienteApiProvider).pedir<Map<String, Object?>>('/orders'),
        throwsA(anything),
      );

      expect(
        c.read(porteroProvider).estado,
        EstadoDeAcceso.fuera,
        reason:
            'la cookie ya era invalida cuando se hizo la peticion: la web '
            'tiene que ir a la puerta (y de ahi a Accesos), no quedarse con un '
            'error mudo',
      );
      expect(c.read(porteroProvider).avisoDeSesion, isNull);
    });

    test('PAREJA: un 200 no echa a nadie', () async {
      final c = montar();
      await c.read(porteroProvider).entro(sesion);
      await respirar();

      await c.read(clienteApiProvider).pedir<Map<String, Object?>>('/orders');

      expect(c.read(porteroProvider).estado, EstadoDeAcceso.dentro);
    });
  });
}
