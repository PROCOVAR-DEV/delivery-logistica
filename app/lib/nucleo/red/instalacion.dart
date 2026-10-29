import 'package:dio/dio.dart';

import 'id_del_aparato.dart';

/// Pone `X-Aparato-Id` (el UUID v7 de ESTA instalación, el mismo que Accesos enseña en «Dispositivos») en cada petición de [ClienteApi].
///
/// Es lo que une al aparato con su fila en el sincronizador (`aparatos.instalacion_id`) y por tanto el enlace «Ver actividad» de Accesos
/// con la pantalla de actividad (`/dispositivos?aparato=<id>`). Solo identifica: nada del servidor le da alcance ni permiso por llevarla.
/// En la web no hay id (`null`) y no sale; si leerlo falla, la petición sale igual.
class InterceptorDeInstalacion extends Interceptor {
  InterceptorDeInstalacion({Future<String?> Function()? id})
    : _id = id ?? idDelAparato;

  final Future<String?> Function() _id;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final id = await _id();
      if (id != null) options.headers['X-Aparato-Id'] = id;
    } on Object {
      // Sin id la petición sale como siempre: una constancia no vale una subida.
    }
    handler.next(options);
  }
}
