import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../identidad/almacen_sesion.dart';
import '../identidad/renovador.dart';
import 'de_quien_viene.dart';
import 'fallos.dart';

/// Pone la sesion en cada peticion y resuelve el 401.
///
/// El orden importa: este va PRIMERO, antes que `InterceptorFallos`, porque un
/// 401 que se pueda arreglar renovando no es un fallo todavia.
class InterceptorSesion extends Interceptor {
  InterceptorSesion({
    required AlmacenDeSesion almacen,
    required Renovador renovador,
    required Dio dio,
    this.sucursalMirada,
    this.alMorirLaSesion,
    this.alFaltarPermiso,
  }) : _almacen = almacen,
       _renovador = renovador,
       _dio = dio;

  final AlmacenDeSesion _almacen;
  final Renovador _renovador;

  /// El mismo Dio al que esta enganchado: hace falta para reenviar la peticion
  /// despues de renovar.
  final Dio _dio;

  /// La sucursal que el Super Admin esta mirando. `null` = la suya.
  final String? Function()? sucursalMirada;

  /// Se avisa UNA vez, cuando la sesion muere de verdad: un 401 que sigue siendo
  /// 401 despues de renovar, o un refresh que el servidor ya no acepta. Es lo
  /// que lleva a la pantalla de acceso (regla 5).
  ///
  /// Va como aviso y no como navegacion desde aqui a proposito: un interceptor
  /// de red que mueve pantallas es un interceptor que hay que montar entero para
  /// probar cualquier peticion.
  final void Function()? alMorirLaSesion;

  /// Se avisa cuando la API dice «esta PERSONA no entra a Reparto»: un 403 con
  /// `codigo == sin_permiso_reparto` (ver [esSinPermisoDeReparto]). Lo lleva a la
  /// pantalla `/sin-permiso`; ni borra la sesion ni toca la cola.
  ///
  /// Se avisa tantas veces como llegue: quien lo recibe (el portero) es
  /// idempotente, y asi no hay estado aqui que olvidar de soltar.
  final void Function()? alFaltarPermiso;

  /// Marca de «esta peticion ya se reintento». Sin ella, un 401 que sigue siendo
  /// 401 entra en un bucle de renovar-reintentar que no acaba.
  static const _yaReintentada = 'reparto.reintentada';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Web: la sesion la lleva la cookie del login unico de auth. Hace falta que
    // la aplicacion y la API salgan bajo `*.procovar.cloud` para que valga.
    if (kIsWeb) options.extra['withCredentials'] = true;

    final sesion = await _almacen.leer();
    if (sesion != null) {
      options.headers['Authorization'] = 'Bearer ${sesion.token}';
    }

    final sucursal = sucursalMirada?.call();
    if (sucursal != null) options.headers['x-sucursal-id'] = sucursal;

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // ANTES que el 401: es el mismo viaje, con otro destino. Sigue su camino
    // normal (acaba siendo un `Rechazo` 403 con su marca) y la cola no se entera.
    if (esSinPermisoDeReparto(err.response)) alFaltarPermiso?.call();

    final esUn401 = err.response?.statusCode == 401;
    final yaSeIntento = err.requestOptions.extra[_yaReintentada] == true;

    if (!esUn401 || yaSeIntento) {
      handler.next(err);
      return;
    }

    final sesion = await _almacen.leer();
    if (sesion == null) {
      // En web no hay nada que renovar desde aqui: si auth dice 401 con su
      // cookie, la sesion murio.
      handler.reject(
        _comoFallo(err, const SesionMuerta('401 sin sesion que renovar')),
      );
      return;
    }

    try {
      // UNA renovacion. El candado se encarga de que veinte peticiones que
      // lleguen aqui a la vez produzcan una sola llamada a `/refresh`.
      await _renovador.renovar(sesion);
    } on SesionMuerta catch (muerta) {
      handler.reject(_comoFallo(err, muerta));
      return;
    } on FalloDeRed catch (red) {
      // No se pudo renovar por la red: esto NO mata la sesion. Se reintenta
      // luego con los tokens intactos.
      handler.reject(_comoFallo(err, red));
      return;
    }

    // Y se reenvia UNA vez. El `onRequest` de arriba volvera a leer el almacen,
    // asi que sale con el token nuevo.
    final opciones = err.requestOptions..extra[_yaReintentada] = true;
    try {
      final respuesta = await _dio.fetch<Object?>(opciones);
      handler.resolve(respuesta);
    } on DioException catch (segundo) {
      // Si el segundo tambien es 401, la sesion murio de verdad.
      if (segundo.response?.statusCode == 401) {
        handler.reject(
          _comoFallo(segundo, const SesionMuerta('401 despues de renovar')),
        );
        return;
      }
      handler.next(segundo);
    }
  }

  DioException _comoFallo(DioException original, FalloApi fallo) {
    if (fallo is SesionMuerta) alMorirLaSesion?.call();
    return original.copyWith(error: fallo);
  }
}

/// ¿ES ESTE EL 403 DE «NO ENTRAS A REPARTO»? Las TRES cosas a la vez:
///
///  * el código es **403**, no 401 (un 401 es sesión caducada y se renueva);
///  * lo firma **nuestra API** ([contestoLoNuestro]): el 403 de un proxy no vale;
///  * el cuerpo trae `codigo == sin_permiso_reparto`. **Solo ese**: el 403 de
///    alcance de sucursal no trae `codigo`, y otro `codigo` es otra cosa.
bool esSinPermisoDeReparto(Response<dynamic>? respuesta) {
  if (respuesta?.statusCode != 403 || !contestoLoNuestro(respuesta)) {
    return false;
  }
  final cuerpo = respuesta?.data;
  return cuerpo is Map && cuerpo['codigo'] == marcaSinPermisoDeReparto;
}
