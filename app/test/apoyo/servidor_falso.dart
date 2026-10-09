import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Una peticion que llego al servidor falso.
class PeticionVista {
  PeticionVista(
    this.metodo,
    this.ruta,
    this.cabeceras,
    this.cuerpo, [
    this.parametros = const <String, Object?>{},
  ]);

  final String metodo;
  final String ruta;
  final Map<String, Object?> cabeceras;
  final Object? cuerpo;

  /// Lo que iba en la direccion. La bajada manda ahi el `desde`, que es la
  /// marca que dio el SERVIDOR: si se mandara otra cosa, el aparato se saltaria
  /// cambios para siempre sin que nadie lo note.
  final Map<String, Object?> parametros;

  @override
  String toString() => '$metodo $ruta';
}

/// Lo que el servidor falso contesta.
///
/// Por defecto habla JSON, como nuestra API. Para fingir lo que contesta algo
/// que NO es nuestro servidor (portal cautivo de un hotel o de un ISP, un proxy),
/// [texto] manda ese cuerpo tal cual y [tipo] su `Content-Type`
/// (`text/html` si no se dice): `RespuestaFalsa(200, null, '<html>…', 'text/html')` o `RespuestaFalsa.portal(200)`.
class RespuestaFalsa {
  RespuestaFalsa(this.codigo, [this.cuerpo, this.texto, this.tipo]);

  /// Un portal cautivo: `codigo` con una pagina `text/html`.
  RespuestaFalsa.portal(this.codigo)
    : cuerpo = null,
      texto = '<html><body>Bienvenido a la red del hotel</body></html>',
      tipo = 'text/html; charset=utf-8';

  final int codigo;
  final Object? cuerpo;
  final String? texto;
  final String? tipo;
}

/// El servidor falso.
///
/// Escrito a mano y no con un ayudante generico a proposito: lo que estas
/// pruebas comprueban no es el cuerpo de la respuesta, es **CUANTAS VECES se
/// pidio `/refresh`**. Eso hace falta contarlo, y contarlo aqui.
class ServidorFalso implements HttpClientAdapter {
  ServidorFalso(this.responder);

  /// `null` para que la peticion falle como si no hubiera red.
  final Future<RespuestaFalsa?> Function(PeticionVista) responder;

  final List<PeticionVista> vistas = <PeticionVista>[];

  int cuantas(String metodo, String ruta) =>
      vistas.where((p) => p.metodo == metodo && p.ruta.endsWith(ruta)).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? cuerpoStream,
    Future<void>? cancelar,
  ) async {
    final peticion = PeticionVista(
      opciones.method,
      opciones.path,
      Map<String, Object?>.from(opciones.headers),
      opciones.data,
      Map<String, Object?>.from(opciones.queryParameters),
    );
    vistas.add(peticion);

    final respuesta = await responder(peticion);
    if (respuesta == null) {
      throw DioException.connectionError(
        requestOptions: opciones,
        reason: 'sin red (servidor falso)',
      );
    }

    return ResponseBody.fromString(
      respuesta.texto ??
          jsonEncode(respuesta.cuerpo ?? const <String, Object?>{}),
      respuesta.codigo,
      headers: {
        Headers.contentTypeHeader: [respuesta.tipo ?? Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
