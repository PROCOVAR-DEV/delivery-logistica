// LA PERSONA PIERDE EL PERMISO DE REPARTO A MEDIA JORNADA — el refresco.
//
// Accesos contesta a `POST /api/auth/refresh` (como al login) con
// `403 {"error":"sin_permiso","codigo":"sin_permiso","message":"No tienes permiso para
// entrar a Reparto."}` cuando la cuenta ya no tiene `delivery.entrar`. El token se renueva
// cada vez que se sincroniza, así que es el sitio por el que se entera la APK.
//
// Antes caía en `FalloDeRed`: «sin conexión», reintentado para siempre y en silencio. Ahora:
//
//  * lleva al portero a `sinPermiso` (la pantalla de «no tienes permiso»), NO a
//    `SesionMuerta` / `fuera`;
//  * **la cola y la base se conservan intactas** y el par de tokens se queda (con él se
//    revoca al cerrar sesión): un 401 borra el par, esto no;
//  * un 401 sigue siendo sesión muerta, como siempre.
//
// En pareja (CLAUDE.md §5) y con la cola con apuntes PENDIENTES delante: lo que no puede
// pasar es que perder el permiso se lleve el trabajo del día.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/arranque/arranque.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// Lo que escribe Accesos (contrato con el agente de Accesos).
const _sinPermisoDeAccesos = <String, Object?>{
  'error': 'sin_permiso',
  'codigo': 'sin_permiso',
  'message': 'No tienes permiso para entrar a Reparto.',
};

const _bajadaVacia = <String, Object?>{
  'hasta': '2026-10-08T08:00:00Z',
  'completa': true,
  'truncado': false,
  'cambios': <String, Object?>{},
  'sucursales': <Object?>[],
};

void main() {
  const sesion = Sesion(token: 't', refresh: 'r0', sub: 'u1');
  late BaseLocal base;
  late AlmacenEnMemoria almacen;

  setUp(() {
    base = baseDePrueba();
    almacen = AlmacenEnMemoria(sesion);
  });
  tearDown(() => base.close());

  Renovador renovador(
    Future<RespuestaFalsa?> Function(PeticionVista) refresh, {
    void Function()? alFaltarPermiso,
  }) => Renovador(dioFalso(refresh), almacen, alFaltarPermiso: alFaltarPermiso);

  group('el Renovador', () {
    test('403 sin_permiso: Rechazo con la marca, avisa UNA vez y NO borra el '
        'par', () async {
      var avisos = 0;
      final r = renovador(
        (p) async => RespuestaFalsa(403, _sinPermisoDeAccesos),
        alFaltarPermiso: () => avisos++,
      );

      await expectLater(
        r.renovar(sesion),
        throwsA(
          isA<Rechazo>()
              .having((x) => x.codigo, 'codigo', 403)
              .having((x) => x.marca, 'marca', marcaSinPermisoDeReparto)
              .having(
                (x) => x.mensaje,
                'mensaje',
                'No tienes permiso para entrar a Reparto.',
              ),
        ),
      );

      expect(avisos, 1);
      expect(
        await almacen.leer(),
        isNotNull,
        reason: 'el par se queda: con él se revoca al cerrar sesión',
      );
      expect((await almacen.leer())!.refresh, 'r0');
    });

    test('PAREJA 1 — un 401 sigue siendo sesión muerta: borra el par y no '
        'avisa del permiso', () async {
      var avisos = 0;
      final r = renovador(
        (p) async => RespuestaFalsa(401, const <String, Object?>{
          'error': 'refresh_invalido',
        }),
        alFaltarPermiso: () => avisos++,
      );

      await expectLater(r.renovar(sesion), throwsA(isA<SesionMuerta>()));

      expect(avisos, 0);
      expect(await almacen.leer(), isNull);
    });

    test('PAREJA 2 — un 403 SIN la marca no es «sin permiso»: sigue como '
        'hasta hoy (red), con los tokens', () async {
      var avisos = 0;
      final r = renovador(
        (p) async =>
            RespuestaFalsa(403, const <String, Object?>{'error': 'otra_cosa'}),
        alFaltarPermiso: () => avisos++,
      );

      await expectLater(r.renovar(sesion), throwsA(isA<FalloDeRed>()));

      expect(avisos, 0);
      expect(await almacen.leer(), isNotNull);
    });

    test('la marca de Accesos no es la de la API, ni la de sin_sucursal', () {
      Response<dynamic> r(Object? cuerpo, [int codigo = 403]) =>
          Response<dynamic>(
            requestOptions: RequestOptions(),
            statusCode: codigo,
            data: cuerpo,
            headers: Headers.fromMap({
              Headers.contentTypeHeader: ['application/json'],
            }),
          );

      expect(esSinPermisoDeAccesos(r(_sinPermisoDeAccesos)), isTrue);
      expect(
        esSinPermisoDeAccesos(r(const {'error': 'sin_permiso'})),
        isTrue,
        reason: 'basta con `error`',
      );
      expect(
        esSinPermisoDeAccesos(r(const {'codigo': 'sin_permiso'})),
        isTrue,
        reason: 'o con `codigo`',
      );
      expect(
        esSinPermisoDeAccesos(r(const {'error': 'sin_sucursal'})),
        isFalse,
      );
      expect(esSinPermisoDeAccesos(r(const {'error': 'revoked'})), isFalse);
      expect(
        esSinPermisoDeAccesos(r(const {'codigo': 'sin_permiso_reparto'})),
        isFalse,
        reason: 'esa es la de la API de Reparto, otra puerta',
      );
      expect(esSinPermisoDeAccesos(r(_sinPermisoDeAccesos, 401)), isFalse);
      expect(esSinPermisoDeAccesos(null), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // CON LOS PROVEEDORES DE VERDAD Y LA COLA CON TRABAJO DENTRO
  // ---------------------------------------------------------------------------

  /// Dos cierres sin subir, en la cola de verdad.
  Future<void> sembrarCola(ProviderContainer c) async {
    for (var i = 0; i < 2; i++) {
      await c
          .read(colaProvider)
          .encolar(
            metodo: 'PATCH',
            ruta: '/routes/r-$i',
            cuerpo: <String, Object?>{'status': 'completed'},
          );
    }
  }

  /// La cola tal cual: dos apuntes, `pendiente`, con su ruta.
  Future<void> colaIntacta(ProviderContainer c) async {
    final lote = await c.read(colaProvider).lote();
    expect(lote.map((a) => a.ruta), ['/routes/r-0', '/routes/r-1']);
    expect(await c.read(baseProvider).cuantosPendientes(), 2);
  }

  /// `refresh` es lo que contesta Accesos a `/refresh`; el resto del servidor
  /// (api y sync) responde bien: lo único que falla es el permiso.
  ProviderContainer montar(
    Future<RespuestaFalsa?> Function(PeticionVista) refresh, {
    Future<RespuestaFalsa?> Function(PeticionVista)? api,
  }) {
    final c = ProviderContainer.test(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(true),
        almacenSesionProvider.overrideWithValue(almacen),
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 8, 8)),
        dioAuthProvider.overrideWithValue(dioFalso(refresh)),
      ],
    );
    addTearDown(c.dispose);
    c.read(clienteApiProvider).dio.httpClientAdapter = ServidorFalso(
      api ?? (p) async => RespuestaFalsa(200, _bajadaVacia),
    );
    c.read(clienteSyncProvider).dio.httpClientAdapter = ServidorFalso(
      api ?? (p) async => RespuestaFalsa(200, _bajadaVacia),
    );
    return c;
  }

  group('el cableado, con la cola con apuntes pendientes', () {
    test(
      'una llamada que da 401 y cuyo refresco da 403 sin_permiso: Rechazo '
      '(no SesionMuerta), portero en sinPermiso, cola y par intactos',
      () async {
        var llamadas = 0;
        final c = montar(
          (p) async => RespuestaFalsa(403, _sinPermisoDeAccesos),
          api: (p) async {
            llamadas++;
            return RespuestaFalsa(401, const <String, Object?>{});
          },
        );
        await sembrarCola(c);

        await expectLater(
          c.read(clienteApiProvider).pedir<Map<String, Object?>>('/orders'),
          throwsA(
            isA<Rechazo>().having(
              (r) => r.marca,
              'marca',
              marcaSinPermisoDeReparto,
            ),
          ),
        );

        expect(c.read(porteroProvider).estado, EstadoDeAcceso.sinPermiso);
        expect(await almacen.leer(), isNotNull);
        expect(llamadas, 1, reason: 'no reintenta tras el 403 de renovar');
        await colaIntacta(c);
      },
    );

    test('PAREJA — con un refresco que da 401 es sesión muerta: el portero va '
        'a fuera y el par se borra (la cola, en su fichero, sigue)', () async {
      final c = montar(
        (p) async => RespuestaFalsa(401, const <String, Object?>{}),
        api: (p) async => RespuestaFalsa(401, const <String, Object?>{}),
      );
      await sembrarCola(c);

      await expectLater(
        c.read(clienteApiProvider).pedir<Map<String, Object?>>('/orders'),
        throwsA(isA<SesionMuerta>()),
      );

      expect(c.read(porteroProvider).estado, EstadoDeAcceso.fuera);
      expect(await almacen.leer(), isNull);
    });

    test('el ciclo de sincronización: renovar da 403 sin_permiso y no sube ni '
        'baja nada; el portero a sinPermiso; la cola intacta', () async {
      await aparatoYaConfigurado(base);
      await aparatoYaDeAlta(base);
      var refrescos = 0;
      final c = montar((p) async {
        refrescos++;
        return RespuestaFalsa(403, _sinPermisoDeAccesos);
      });
      await sembrarCola(c);
      final portero = c.read(porteroProvider);
      // Dentro, como quien trabaja: así el ciclo tiene sesión con la que correr.
      await portero.entro(sesion);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(portero.estado, EstadoDeAcceso.dentro);
      final antes = refrescos;

      final resumen = await c
          .read(cicloProvider)
          .ahora(motivo: 'el token se renueva al sincronizar');

      expect(refrescos, antes + 1);
      expect(resumen.fallo, isA<Rechazo>());
      expect(resumen.subidos, 0);
      expect(portero.estado, EstadoDeAcceso.sinPermiso);
      expect(await almacen.leer(), isNotNull);
      await colaIntacta(c);
    });

    test('el arranque: con el par guardado y el refresco en 403 sin_permiso, '
        'Arranque.sinPermiso con la sesión; comprobar() no la tira', () async {
      final c = montar((p) async => RespuestaFalsa(403, _sinPermisoDeAccesos));
      await sembrarCola(c);

      final resultado = await arrancar(c.read(_ref));
      expect(resultado.como, Arranque.sinPermiso);
      expect(
        resultado.sesion?.sub,
        'u1',
        reason: 'para poder revocar al salir',
      );

      final portero = c.read(porteroProvider);
      await portero.comprobar();
      expect(portero.estado, EstadoDeAcceso.sinPermiso);
      expect(portero.sesion?.sub, 'u1');
      expect(await almacen.leer(), isNotNull);
      await colaIntacta(c);
    });

    test(
      'PAREJA — el arranque con el refresco en 401 sigue yendo a fuera',
      () async {
        final c = montar(
          (p) async => RespuestaFalsa(401, const <String, Object?>{}),
        );
        await sembrarCola(c);

        final portero = c.read(porteroProvider);
        await portero.comprobar();

        expect(portero.estado, EstadoDeAcceso.fuera);
        expect(await almacen.leer(), isNull);
      },
    );
  });
}

final _ref = Provider<Ref>((ref) => ref);
