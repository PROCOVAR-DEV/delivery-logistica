// EL HUECO DEL CIERRE PENDIENTE SOLO SE BORRA CON LO QUE CONFIRMA **NUESTRO**
// SERVIDOR — 09/10/2026 (auditoria independiente, SERIO 1).
//
// CLAUDE.md §4: «sólo se borra con 200 o 401 de nuestro servidor». Un portal
// cautivo (hotel, ISP) contesta `200 text/html` a todo: tomarlo por «revocado»
// borraba `reparto.por_revocar` y el refresco seguia vivo 30 dias sin que
// Accesos hubiera visto nada. La guarda del 401 (`contestoLoNuestro`) no la
// probaba nadie porque el servidor falso solo hablaba JSON.
//
// La misma tabla, de las dos puertas por las que un refresco pasa por `/logout`:
//  * `RevocadorDeCierres`: DESPUES, con red, borra el hueco solo si confirma;
//  * `ServicioDeAcceso.salir`: AL SALIR, deja el hueco salvo que confirme.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/revocador_de_cierres.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/pantallas/acceso/datos/servicio_acceso.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/servidor_falso.dart';

/// (que contesta, ¿lo confirma NUESTRO servidor?). `null` es «sin red».
final _casos = <(String, RespuestaFalsa?, bool)>[
  ('200 JSON de nuestro servidor', logoutDeAccesos(), true),
  (
    '401 JSON de nuestro servidor',
    RespuestaFalsa(401, <String, Object?>{'error': 'revoked'}),
    true,
  ),
  ('200 text/html (portal cautivo)', RespuestaFalsa.portal(200), false),
  ('401 text/html (portal cautivo)', RespuestaFalsa.portal(401), false),
  (
    '5xx JSON de nuestro servidor',
    RespuestaFalsa(503, <String, Object?>{'error': 'no disponible'}),
    false,
  ),
  ('5xx text/html', RespuestaFalsa.portal(502), false),
  ('sin red', null, false),
  // Estrictez del 200: JSON, pero no la forma de `/logout`.
  ('200 JSON vacio {}', RespuestaFalsa(200), false),
  (
    '200 JSON {"ok": false}',
    RespuestaFalsa(200, <String, Object?>{'ok': false}),
    false,
  ),
  (
    '200 text/html con un {"ok": true} dentro (manda la cabecera)',
    RespuestaFalsa(200, null, '{"ok": true}', 'text/html'),
    false,
  ),
  ('204 sin cuerpo', RespuestaFalsa(204, null, '', 'application/json'), false),
];

void main() {
  group('RevocadorDeCierres: el hueco se borra SOLO con lo de nuestro '
      'servidor', () {
    for (final (nombre, respuesta, confirma) in _casos) {
      test('$nombre -> ${confirma ? 'BORRA' : 'DEJA'} el hueco', () async {
        final almacen = AlmacenEnMemoria();
        await almacen.dejarPorRevocar(
          const RefrescoPorRevocar(sub: 'u-1', refresh: 'r-1'),
        );
        final auth = ServidorFalso((p) async => respuesta);
        final dio = dioFalso((p) async => null)..httpClientAdapter = auth;

        final quedan = await RevocadorDeCierres(
          dio,
          almacen,
        ).revocarLoPendiente();

        expect(auth.cuantas('POST', '/logout'), 1);
        expect(quedan, confirma ? 0 : 1);
        expect(
          await almacen.porRevocar(),
          confirma ? isEmpty : hasLength(1),
          reason: confirma
              ? 'Accesos lo confirmo: ya no hay nada pendiente'
              : 'Accesos NO lo ha visto: el refresco sigue vivo y el hueco '
                    'tiene que quedarse para el proximo intento',
        );
      });
    }
  });

  group('cierreConfirmado, sobre la respuesta suelta', () {
    Response<Object?> a(int codigo, Object? cuerpo, {String? tipo}) =>
        Response<Object?>(
          requestOptions: RequestOptions(path: '/logout'),
          statusCode: codigo,
          data: cuerpo,
          headers: Headers.fromMap({
            if (tipo != null) Headers.contentTypeHeader: [tipo],
          }),
        );

    test('200 {"ok": true} con Content-Type JSON confirma', () {
      expect(
        cierreConfirmado(
          a(200, {'ok': true}, tipo: 'application/json; charset=utf-8'),
        ),
        isTrue,
      );
    });

    test('PAREJA: el mismo cuerpo SIN Content-Type no confirma (el silencio '
        'que `contestoLoNuestro` perdona en otros sitios, aqui no)', () {
      expect(cierreConfirmado(a(200, {'ok': true})), isFalse);
      expect(cierreConfirmado(null), isFalse);
    });
  });

  group('ServicioDeAcceso.salir: el hueco se DEJA salvo que confirme lo '
      'nuestro', () {
    for (final (nombre, respuesta, confirma) in _casos) {
      test('$nombre -> ${confirma ? 'NO deja' : 'DEJA'} hueco', () async {
        final sesion = sesionDePrueba(refresh: 'r-1');
        final almacen = AlmacenEnMemoria(sesion);
        final dio = dioFalso((p) async => respuesta);

        await ServicioDeAcceso(auth: dio, almacen: almacen).salir(sesion);

        expect(
          await almacen.leer(),
          isNull,
          reason: 'se sale pase lo que pase',
        );
        final pendientes = await almacen.porRevocar();
        expect(
          pendientes.map((r) => r.refresh),
          confirma ? isEmpty : ['r-1'],
          reason: confirma
              ? 'Accesos lo confirmo: nada que revocar despues'
              : 'Accesos NO lo ha visto: el refresco queda por revocar',
        );
      });
    }

    test('una sesion de cookie (sin par) no pide nada ni deja hueco', () async {
      final almacen = AlmacenEnMemoria();
      final auth = ServidorFalso((p) async => null);
      final dio = dioFalso((p) async => null)..httpClientAdapter = auth;

      await ServicioDeAcceso(auth: dio, almacen: almacen).salir(
        Sesion.deLaCookie(token: tokenDePrueba(), usuario: const {'id': 'u-1'}),
      );

      expect(auth.vistas, isEmpty);
      expect(await almacen.porRevocar(), isEmpty);
    });
  });
}
