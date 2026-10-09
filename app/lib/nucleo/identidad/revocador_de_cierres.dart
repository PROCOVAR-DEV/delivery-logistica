import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';

import '../red/de_quien_viene.dart';
import '../registro/registro.dart';
import 'almacen_sesion.dart';

/// REVOCA EN ACCESOS LOS CIERRES DE SESION QUE SE HICIERON SIN CONEXION.
///
/// Salir sin red no puede avisar a Accesos, y el refresco se quedaba vivo hasta
/// 30 dias sin que nadie lo reintentara (`ServicioDeAcceso.salir`). Ahora ese
/// refresco se guarda aparte ([RefrescoPorRevocar]) y esto lo presenta a
/// `POST /logout` en cuanto hay red: al arrancar, al volver la conexion y al
/// entrar (que ya prueba que la hay).
///
/// ## Cuando se borra lo pendiente, y solo entonces
///
/// Cuando el servidor CONFIRMA, y confirmar es [cierreConfirmado]: un **200**
/// con la forma de `/logout` de Accesos, o un **401** de nuestro servidor (el
/// refresco ya no existe: alguien lo cerro antes, que es lo que se queria).
/// Cualquier otra cosa —sin red, 5xx, un proxy que contesta otra cosa, **un 200
/// de portal cautivo**— lo deja donde estaba para el proximo intento. Nunca se
/// descarta en silencio.
///
/// **Jamas autentica nada**: el refresco solo viaja en el cuerpo de `/logout`.
class RevocadorDeCierres {
  RevocadorDeCierres(this._auth, this._almacen);

  final Dio _auth;
  final AlmacenDeSesion _almacen;

  /// Dos disparos a la vez (arranque y aviso de red) presentarian el mismo
  /// refresco dos veces.
  final _candado = Lock();

  /// Intenta revocar todo lo pendiente. Devuelve **cuantos quedan** sin
  /// confirmar. No lanza nunca.
  Future<int> revocarLoPendiente() => _candado.synchronized(() async {
    final pendientes = await _almacen.porRevocar();
    var quedan = 0;
    for (final p in pendientes) {
      Response<Object?>? respuesta;
      try {
        respuesta = await _auth.post<Object?>(
          '/logout',
          data: <String, Object?>{'refresh_token': p.refresh},
        );
      } on DioException catch (e) {
        respuesta = e.response; // un 401 llega aqui, como excepcion
      } on Object catch (e) {
        Registro.aviso('cierre pendiente: fallo inesperado al revocar: $e');
        quedan++;
        continue;
      }
      if (!cierreConfirmado(respuesta)) {
        Registro.aviso(
          'cierre pendiente: sin confirmar aun (${respuesta?.statusCode ?? 'sin respuesta'} '
          '${tipoDeContenido(respuesta) ?? ''})',
        );
        quedan++;
        continue;
      }
      await _almacen.quitarPorRevocar(p.refresh);
      Registro.info('cierre pendiente: revocado en Accesos');
    }
    return quedan;
  });
}

/// ¿ESTA RESPUESTA DE `POST /logout` LA CONFIRMA **NUESTRO** SERVIDOR?
///
/// Un portal cautivo (hotel, ISP) contesta **200 `text/html`** a cualquier cosa:
/// tomarlo por «revocado» borraba el hueco y dejaba vivo el refresco 30 dias sin
/// que Accesos hubiera visto nada. Por eso «es nuestro servidor» se exige en el
/// 200 igual que en el 401 (CLAUDE.md §4):
///
///  * **200**: `Content-Type` JSON (tiene que venir; aqui no vale el silencio de
///    [contestoLoNuestro]) y cuerpo `{"ok": true}`, que es lo que Accesos
///    contesta SIEMPRE (`auth/src/app/api/auth/logout/route.ts`: «Siempre 200»).
///  * **401**: [contestoLoNuestro].
///  * Todo lo demas, o sin respuesta: no confirma.
bool cierreConfirmado(Response<Object?>? r) {
  if (r == null || !contestoLoNuestro(r)) return false;
  return switch (r.statusCode) {
    401 => true,
    200 =>
      tipoDeContenido(r) != null &&
          r.data is Map &&
          (r.data! as Map)['ok'] == true,
    _ => false,
  };
}
