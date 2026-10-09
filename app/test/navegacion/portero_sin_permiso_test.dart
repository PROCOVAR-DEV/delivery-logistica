// EL PORTERO REAL ANTE «NO TIENES PERMISO PARA ENTRAR A REPARTO».
//
// `test/pantallas/acceso/sin_permiso_test.dart` prueba la pantalla y el redirector con un
// portero FALSO; aquí va el de verdad, con los proveedores de verdad cableados. Cuatro
// guardas sobrevivían a la mutación porque nadie las ejercitaba con el portero real:
//
//  M1  `_poner` no deja volver de `sinPermiso` a `dentro` / `configurando`;
//  M2  `alFaltarPermiso` cableado en `_cliente` (`nucleo/proveedores.dart`);
//  M3  la rama `porAccesos is SinPermiso` de `arrancar`: sin ella la web cae en `fuera`, va
//      al login único y Accesos la devuelve con la cookie puesta: bucle;
//  M4  `if (_estado == sinPermiso) return;` de `Portero.configurar`.
//
// Y las decisiones de diseño que se fijan con una prueba (para que cambiarlas sea
// deliberado): de `sinPermiso` solo se sale SALIENDO (`salir()` y volver a entrar desde el
// login); `entro()` estando en `sinPermiso` no lleva a `dentro`; y `sinPermiso()` estando
// `fuera` se ignora (un 403 tardío no resucita la pantalla).
//
// NADA de red: a cada cliente se le pone un `ServidorFalso` ANTES de que nadie lo use
// (los proveedores devuelven la misma instancia), porque los de verdad apuntan a
// `reparto.procovar.cloud` y este código corre en el ordenador de Jose.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/arranque/arranque.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../apoyo/apoyo_accesos.dart';
import '../apoyo/apoyo_sesion.dart';
import '../apoyo/base_de_prueba.dart';
import '../apoyo/servidor_falso.dart';

const _sinPermiso = <String, Object?>{
  'error': 'No tienes permiso para entrar a Reparto.',
  'codigo': 'sin_permiso_reparto',
};

/// Lo que contesta un servidor sano a la bajada: nada que bajar.
const _bajadaVacia = <String, Object?>{
  'hasta': '2026-10-08T08:00:00Z',
  'completa': true,
  'truncado': false,
  'cambios': <String, Object?>{},
  'sucursales': <Object?>[],
};

Future<RespuestaFalsa?> _todoSinPermiso(PeticionVista p) async =>
    RespuestaFalsa(403, _sinPermiso);

Future<RespuestaFalsa?> _todoBien(PeticionVista p) async =>
    RespuestaFalsa(200, _bajadaVacia);

void main() {
  const sesion = Sesion(token: 't', refresh: 'r', sub: 'u1');
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// El portero de verdad, con sus proveedores de verdad. [api] y [sync] son lo que
  /// contesta cada servidor; [apiMe] lo que contesta `/api/me` (solo en la web).
  ProviderContainer montar({
    bool enWeb = false,
    Future<RespuestaFalsa?> Function(PeticionVista)? api,
    Future<RespuestaFalsa?> Function(PeticionVista)? sync,
    Future<RespuestaFalsa?> Function(PeticionVista)? apiMe,
  }) {
    final c = ProviderContainer.test(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(!enWeb),
        navegadorProvider.overrideWithValue(NavegadorFalso()),
        entradaPorAccesosProvider.overrideWithValue(
          entradaFalsa(
            NavegadorFalso(),
            apiMe ??
                (p) async => RespuestaFalsa(401, const <String, Object?>{}),
          ),
        ),
        almacenSesionProvider.overrideWithValue(AlmacenEnMemoria()),
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 8, 8)),
        dioAuthProvider.overrideWithValue(
          dioFalso(
            // `/logout` contesta como Accesos (`200 {"ok": true}`): con un par de
            // tokens no confirma el cierre y queda un refresco por revocar.
            (p) async => p.ruta.endsWith('/logout')
                ? logoutDeAccesos()
                : RespuestaFalsa(200, parDeTokens()),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(clienteApiProvider).dio.httpClientAdapter = ServidorFalso(
      api ?? _todoBien,
    );
    c.read(clienteSyncProvider).dio.httpClientAdapter = ServidorFalso(
      sync ?? _todoBien,
    );
    return c;
  }

  /// Deja que acabe el ciclo que `entro()` lanza por detrás, antes de soltar la base.
  Future<void> dejarAcabar() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // ---------------------------------------------------------------------------
  // M2 · EL CABLEADO: un 403 por el cliente real llega al portero real
  // ---------------------------------------------------------------------------

  group('el cableado de `_cliente` (M2)', () {
    Future<void> sinPermisoPor(
      ClienteApi Function(ProviderContainer) cual,
    ) async {
      final c = montar(api: _todoSinPermiso, sync: _todoSinPermiso);

      await expectLater(
        cual(c).pedir<Map<String, Object?>>('/orders'),
        throwsA(isA<Rechazo>()),
      );

      expect(c.read(porteroProvider).estado, EstadoDeAcceso.sinPermiso);
    }

    test(
      'un 403 sin_permiso_reparto por clienteApiProvider deja al portero en '
      'sinPermiso',
      () => sinPermisoPor((c) => c.read(clienteApiProvider)),
    );

    test(
      'y lo mismo por clienteSyncProvider',
      () => sinPermisoPor((c) => c.read(clienteSyncProvider)),
    );

    test(
      'PAREJA: un 403 SIN codigo (alcance de sucursal) no toca al portero',
      () async {
        final c = montar(
          api: (p) async => RespuestaFalsa(403, const <String, Object?>{
            'error': 'Esa no es tu sucursal.',
          }),
        );
        final antes = c.read(porteroProvider).estado;

        await expectLater(
          c.read(clienteApiProvider).pedir<Map<String, Object?>>('/orders'),
          throwsA(isA<Rechazo>()),
        );

        expect(c.read(porteroProvider).estado, antes);
        expect(antes, isNot(EstadoDeAcceso.sinPermiso));
      },
    );

    /// Un cierre pendiente en la cola de verdad (la del contenedor).
    Future<String> unCierre(ProviderContainer c) => c
        .read(colaProvider)
        .encolar(
          metodo: 'PATCH',
          ruta: '/routes/r-1',
          cuerpo: <String, Object?>{'status': 'completed'},
        );

    test('la subida real: el 403 de /sync/subida deja el apunte pendiente y al '
        'portero en sinPermiso', () async {
      await aparatoYaDeAlta(base);
      final c = montar(sync: _todoSinPermiso);
      final clave = await unCierre(c);

      await expectLater(
        c.read(subidaProvider).ciclo(),
        throwsA(isA<Rechazo>()),
      );

      expect(
        (await c.read(colaProvider).porClave(clave))!.estado,
        EstadoApunte.pendiente,
      );
      expect(c.read(porteroProvider).estado, EstadoDeAcceso.sinPermiso);
    });

    test('la segunda cerradura cableada en subidaProvider: el rechazo «sin '
        'permiso» DENTRO de un 200 también llega al portero', () async {
      await aparatoYaDeAlta(base);
      final claveDelCierre = Completer<String>();
      final c = montar(
        sync: (p) async => RespuestaFalsa(200, <String, Object?>{
          'resultados': [
            <String, Object?>{
              'clave': await claveDelCierre.future,
              'estado': 'rechazado',
              'motivo': textoSinPermisoDeReparto,
            },
          ],
        }),
      );
      final clave = await unCierre(c);
      claveDelCierre.complete(clave);

      await expectLater(
        c.read(subidaProvider).ciclo(),
        throwsA(isA<Rechazo>()),
      );

      expect(
        (await c.read(colaProvider).porClave(clave))!.estado,
        EstadoApunte.pendiente,
      );
      expect(c.read(porteroProvider).estado, EstadoDeAcceso.sinPermiso);
    });
  });

  // ---------------------------------------------------------------------------
  // M3 · LA CARGA INICIAL DE LA WEB
  // ---------------------------------------------------------------------------

  group('la carga inicial de la web (M3)', () {
    test('/api/me con 403 sin_permiso: arrancar da Arranque.sinPermiso y '
        'comprobar() termina en sinPermiso, NO en el login', () async {
      final c = montar(
        enWeb: true,
        apiMe: (p) async => RespuestaFalsa(403, _sinPermiso),
      );

      expect((await arrancar(c.read(_ref))).como, Arranque.sinPermiso);

      final portero = c.read(porteroProvider);
      await portero.comprobar();
      expect(
        portero.estado,
        EstadoDeAcceso.sinPermiso,
        reason:
            'en `fuera` la web iría al login único y Accesos la devolvería con '
            'la cookie puesta: un bucle entre las dos páginas',
      );
    });

    test(
      'lo que pasa de verdad en producción: /api/me contesta 200 (la persona '
      'está) y es la PRIMERA llamada protegida la que da el 403',
      () async {
        final c = montar(
          enWeb: true,
          apiMe: (p) async =>
              RespuestaFalsa(200, respuestaDeApiMe(token: tokenDePrueba())),
          api: _todoSinPermiso,
          sync: _todoSinPermiso,
        );
        final portero = c.read(porteroProvider);

        await portero.comprobar();
        // Entra (`dentro`) y el ciclo de «al entrar» tropieza con el 403 por detrás.
        for (
          var i = 0;
          i < 200 && portero.estado != EstadoDeAcceso.sinPermiso;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(portero.estado, EstadoDeAcceso.sinPermiso);
      },
    );

    test('PAREJA: /api/me con un 403 SIN codigo no es «sin permiso», y un 401 '
        'va al acceso', () async {
      final sinCodigo = montar(
        enWeb: true,
        apiMe: (p) async =>
            RespuestaFalsa(403, const <String, Object?>{'error': 'x'}),
      );
      expect(
        (await arrancar(sinCodigo.read(_ref))).como,
        isNot(Arranque.sinPermiso),
      );

      final sinSesion = montar(
        enWeb: true,
        apiMe: (p) async =>
            RespuestaFalsa(401, const <String, Object?>{'user': null}),
      );
      final portero = sinSesion.read(porteroProvider);
      await portero.comprobar();
      expect(portero.estado, EstadoDeAcceso.fuera);
    });
  });

  // ---------------------------------------------------------------------------
  // M1, M4 · NO SE SALE DE sinPermiso SOLO
  // ---------------------------------------------------------------------------

  group('de sinPermiso no se sale solo (M1, M4)', () {
    test(
      'sinPermiso() deja el estado, y llamarla dos veces notifica UNA vez',
      () {
        final portero = montar().read(porteroProvider);
        var avisos = 0;
        portero.addListener(() => avisos++);

        portero.sinPermiso();
        portero.sinPermiso();

        expect(portero.estado, EstadoDeAcceso.sinPermiso);
        expect(avisos, 1, reason: 'idempotente: el router se redirige una vez');
      },
    );

    test('entro(sesion) NO lo saca a dentro: se traga en silencio, por diseño; '
        'salir() + entro() SÍ', () async {
      await aparatoYaConfigurado(base);
      final c = montar();
      final portero = c.read(porteroProvider);

      portero.sinPermiso();
      await portero.entro(sesion);
      await dejarAcabar();
      expect(
        portero.estado,
        EstadoDeAcceso.sinPermiso,
        reason: 'solo se sale SALIENDO (docs/sin-permiso.md)',
      );

      await portero.salir();
      expect(portero.estado, EstadoDeAcceso.fuera);

      await portero.entro(sesion);
      await dejarAcabar();
      expect(portero.estado, EstadoDeAcceso.dentro);
    });

    test('configurar() estando en sinPermiso no lo saca a configurando ni '
        'deja una configuración a medias', () async {
      final portero = montar().read(porteroProvider);
      portero.sinPermiso();

      await portero.configurar();

      expect(portero.estado, EstadoDeAcceso.sinPermiso);
      expect(
        portero.configuracion?.faltoAlgo,
        isFalse,
        reason:
            'sin la guarda, configurar() deja `aMedias`/`fallo` puesto y la '
            'pantalla de reintentar tendría con qué pintarse debajo',
      );
    });

    test('la carga inicial del APK: el 403 llega EN MITAD de configurar() y '
        'gana la pantalla del permiso', () async {
      // Aparato vacío (base sin sembrar) y entrar = configurar con el ciclo
      // entero, que es donde el interceptor ve el 403.
      final c = montar(api: _todoSinPermiso, sync: _todoSinPermiso);
      final portero = c.read(porteroProvider);

      await portero.entro(sesion);
      await dejarAcabar();

      expect(portero.estado, EstadoDeAcceso.sinPermiso);
      expect(portero.configuracion?.faltoAlgo, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // H2 · UN 403 TARDÍO NO RESUCITA LA PANTALLA
  // ---------------------------------------------------------------------------

  group('estando fuera, sinPermiso() se ignora', () {
    test('tras murio()', () {
      final portero = montar().read(porteroProvider)..murio();
      expect(portero.estado, EstadoDeAcceso.fuera);

      portero.sinPermiso(); // una petición en vuelo que acaba tarde

      expect(portero.estado, EstadoDeAcceso.fuera);
    });

    test('tras salir()', () async {
      final c = montar();
      final portero = c.read(porteroProvider);
      portero.sinPermiso();
      await portero.salir();
      expect(portero.estado, EstadoDeAcceso.fuera);

      portero.sinPermiso();

      expect(portero.estado, EstadoDeAcceso.fuera);
    });

    test('PAREJA: estando dentro sí vale', () async {
      await aparatoYaConfigurado(base);
      final c = montar();
      final portero = c.read(porteroProvider);
      await portero.entro(sesion);
      await dejarAcabar();
      expect(portero.estado, EstadoDeAcceso.dentro);

      portero.sinPermiso();

      expect(portero.estado, EstadoDeAcceso.sinPermiso);
    });
  });
}

final _ref = Provider<Ref>((ref) => ref);
