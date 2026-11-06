import 'package:dio/dio.dart';

import '../actualizacion/version_publicada.dart';
import '../registro/registro.dart';

/// Pone `X-App-Version: <versionName>+<versionCode>` (p. ej. `1.0.0+57`) en cada petición de [ClienteApi].
///
/// Solo la monta la app «Reparto Distribuidor» (`ClienteApi.montar(versionDeLaApp:)`): el servidor apunta qué versión tiene cada
/// teléfono y la pestaña Teléfonos de la oficina avisa de los «Desactualizada». Es un dato de soporte, no de confianza: si leerlo
/// falla, la petición sale igual.
class InterceptorDeVersion extends Interceptor {
  InterceptorDeVersion({Future<VersionInstalada> Function()? leer})
    : _leer = leer ?? VersionInstalada.delPaquete;

  final Future<VersionInstalada> Function() _leer;

  /// Se lee una vez: la versión instalada no cambia mientras la app corre.
  Future<String?>? _valor;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final valor = await (_valor ??= _declarada());
    if (valor != null) options.headers[cabeceraDeVersion] = valor;
    handler.next(options);
  }

  Future<String?> _declarada() async {
    try {
      return (await _leer()).toString();
    } on Object catch (e) {
      Registro.aviso('no se pudo leer la versión para X-App-Version: $e');
      return null;
    }
  }
}

const cabeceraDeVersion = 'X-App-Version';
