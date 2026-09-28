import 'package:dio/dio.dart';

import 'de_quien_viene.dart';
import 'fallos.dart';

/// Traduce lo que devuelve Dio a los tres tipos de `fallos.dart`. Es la tabla de
/// la regla 5 y nada mas.
///
/// Va DESPUES de `InterceptorSesion`: lo que llega aqui ya no tiene arreglo por
/// renovacion.
class InterceptorFallos extends Interceptor {
  const InterceptorFallos();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Si alguien de mas arriba ya decidio que fallo es, se respeta.
    if (err.error is FalloApi) {
      handler.next(err);
      return;
    }
    handler.next(err.copyWith(error: traducir(err)));
  }

  static FalloApi traducir(DioException error) {
    final respuesta = error.response;
    final codigo = respuesta?.statusCode;

    // La peticion ni salio, o se agoto el tiempo: red.
    if (codigo == null) {
      return FalloDeRed(detalle: error.message ?? error.type.name);
    }

    // 5xx: el servidor esta mal, no nosotros. Se conserva y se reintenta.
    //
    // Va ANTES de mirar quien firma la respuesta, y a proposito: el 502 de
    // nginx y el 503 de Traefik son paginas HTML, y decirle a alguien «esta red
    // no llega al servidor» cuando la red va perfecta y lo que esta mal es el
    // servidor manda a mirar donde no es. Como los dos acaban en `FalloDeRed`,
    // lo unico que cambia entre una rama y otra es la frase.
    if (codigo >= 500) {
      return FalloDeRed(codigo: codigo, detalle: mensajeDelServidor(error));
    }

    // HAY CODIGO, PERO ¿QUIEN LO ESCRIBIO? — 28/09/2026.
    //
    // Aqui abajo estaba el agujero. Un router, un proxy transparente o un
    // filtro de la red contestan por su cuenta con un 200, un 403 o un 404, y
    // todos ellos salian por `Rechazo` — que significa «el servidor entendio la
    // peticion y dijo que no», o sea, prueba de que la peticion LLEGO. Con eso,
    // la salud de la red daba la conexion por buena sin que llegara una sola.
    //
    // Y la puerta la cierra por los dos lados: el 401 de abajo es lo UNICO que
    // saca a alguien a la pantalla de acceso, y algo que no sea nuestro
    // servidor no puede tener ese poder. Antes lo tenia. Ver
    // `ContestoOtroServidor`.
    if (!contestoLoNuestro(respuesta)) {
      return ContestoOtroServidor(
        codigo: codigo,
        tipo: tipoDeContenido(respuesta),
        detalle: error.message ?? error.type.name,
      );
    }

    if (codigo == 401) {
      return SesionMuerta(mensajeDelServidor(error));
    }

    // 4xx que no es 401: el servidor dijo que no, con su motivo.
    return Rechazo(
      codigo,
      mensajeDelServidor(error) ?? 'El servidor rechazó la petición.',
      marca: marcaDelServidor(error),
      // El cuerpo entero, para los «no» que traen una lista nombrada al lado de
      // la frase. Ver [Rechazo.cuerpo].
      cuerpo: error.response?.data,
    );
  }

  /// La marca legible por una maquina, si vino. Ver [Rechazo.marca].
  static String? marcaDelServidor(DioException error) {
    final datos = error.response?.data;
    if (datos is Map) {
      final valor = datos['codigo'];
      if (valor is String && valor.isNotEmpty) return valor;
    }
    return null;
  }

  /// El mensaje del servidor, **literal y en espanol**. Se busca en las claves
  /// que la API usa de verdad (`contratos-api.md`, apendice).
  static String? mensajeDelServidor(DioException error) {
    final datos = error.response?.data;
    if (datos is Map) {
      for (final clave in const ['mensaje', 'error', 'message']) {
        final valor = datos[clave];
        if (valor is String && valor.isNotEmpty) return valor;
      }
    }
    if (datos is String && datos.isNotEmpty) return datos;
    return null;
  }
}
