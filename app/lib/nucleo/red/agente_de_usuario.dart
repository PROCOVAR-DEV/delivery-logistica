import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../registro/registro.dart';
import 'id_del_aparato.dart';

/// EL `User-Agent` DE LA APK Y DEL ESCRITORIO — 08/10/2026.
///
/// Accesos enseña en «Dispositivos y sesiones» el aparato a partir del
/// `User-Agent`, y el de Dart (`Dart/3.x (dart:io)`) no dice si es un Android o
/// un Windows: salía «App de Reparto» a secas. Con este sale «App de Reparto en
/// Android». El formato es EXACTAMENTE `ProcovarReparto/<versión> (<plataforma>)`
/// y el parser de Accesos (`auth/src/lib/agente-de-usuario.ts`) lo reconoce por
/// «reparto» y saca la plataforma de la palabra (`Android`, `Windows`, `Linux`).
///
/// (`macOS` e `iOS` salen bien escritos pero ese parser no los conoce todavía:
/// se leerían como «App de Reparto». Hoy no hay compilación para ninguno.)
///
/// **La WEB no lo manda**: el navegador pone el suyo y `User-Agent` es una
/// cabecera que el navegador no deja tocar a un script.
String agenteDeReparto(String version, String plataforma) =>
    'ProcovarReparto/$version ($plataforma)';

/// La plataforma como la escribe el agente, o `null` donde no se manda (web, y
/// cualquier destino que no sea uno de los cinco).
///
/// Pura y con [esWeb] por parametro A PROPOSITO: en la maquina virtual `kIsWeb`
/// es siempre falso, y una guarda que no se puede ejecutar por el lado web no la
/// prueba nadie (quitarla salia en verde). Si el `User-Agent` llegara a salir en
/// la web, deja de ser cabecera segura de CORS y el navegador añade un preflight
/// al login de Accesos. Las dos ramas se prueban en
/// `agente_de_usuario_test.dart`; el cableado con `kIsWeb` de verdad, en Chrome
/// (`agente_de_usuario_web_test.dart`).
String? plataformaDelAgente({
  required bool esWeb,
  required TargetPlatform destino,
}) {
  if (esWeb) return null;
  return switch (destino) {
    TargetPlatform.android => 'Android',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.fuchsia => null,
  };
}

/// [plataformaDelAgente] con la plataforma de verdad.
String? plataformaParaElAgente() =>
    plataformaDelAgente(esWeb: kIsWeb, destino: defaultTargetPlatform);

/// Pone el `User-Agent` propio en cada petición del Dio de Accesos (`/token`,
/// `/refresh`, `/logout`). Si no se puede saber la versión, la petición sale con
/// el de siempre: un agente bonito no vale una petición de renovar que no sale.
class InterceptorDeAgente extends Interceptor {
  /// [plataforma] es una funcion para poder simular un destino en una prueba:
  /// `() => plataformaDelAgente(esWeb: true, destino: …)` ejecuta la rama web de
  /// verdad aunque `kIsWeb` sea falso en la maquina virtual.
  InterceptorDeAgente({
    Future<String> Function()? version,
    String? Function() plataforma = plataformaParaElAgente,
  }) : _version = version ?? _delPaquete,
       _plataforma = plataforma;

  final Future<String> Function() _version;
  final String? Function() _plataforma;
  String? _agente;

  static Future<String> _delPaquete() async =>
      (await PackageInfo.fromPlatform()).version;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final plataforma = _plataforma();
    if (plataforma != null) {
      try {
        // Una vez: la versión instalada no cambia con la aplicación abierta.
        _agente ??= agenteDeReparto(await _version(), plataforma);
        options.headers['User-Agent'] = _agente;
      } on Object catch (e) {
        Registro.aviso('no se pudo leer la versión para el User-Agent: $e');
      }
    }
    handler.next(options);
  }
}

/// Pone `X-Aparato-Id` (UUID v7, estable por instalación) y `X-Aparato-Nombre`
/// en cada petición del Dio de Accesos: así Accesos sabe QUÉ aparato renueva y
/// lo enseña en «Dispositivos». Sin id (web, o un fallo del disco) no pone nada.
class InterceptorDeAparato extends Interceptor {
  InterceptorDeAparato({
    Future<String?> Function()? id,
    Future<String?> Function()? nombre,
    Future<String?> Function()? huella,
    this.plazo = const Duration(seconds: 2),
  }) : _id = id ?? idDelAparato,
       _nombre = nombre ?? nombreDelAparato,
       _huella = huella ?? huellaDelAparato;

  final Future<String?> Function() _id;
  final Future<String?> Function() _nombre;
  final Future<String?> Function() _huella;

  /// Cuánto se espera, como mucho, a que se lea la identidad.
  final Duration plazo;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      // Las tres lecturas a la vez y con TOPE: un `reg` o un disco colgados no
      // pueden dejar sin salir la renovación de la sesión (auditoría 29/10/2026).
      // Pasado el plazo la petición sale sin esas cabeceras; las lecturas siguen
      // y la siguiente petición ya las encuentra hechas (se recuerdan).
      final r = await Future.wait<String?>([_id(), _nombre(), _huella()])
          .timeout(plazo);
      final id = r[0];
      if (id != null) {
        options.headers['X-Aparato-Id'] = id;
        if (r[1] != null) options.headers['X-Aparato-Nombre'] = r[1];
        // Lo que junta esta instalación con las de otras aplicaciones del mismo aparato.
        if (r[2] != null) options.headers['X-Aparato-Huella'] = r[2];
      }
    } on Object catch (e) {
      Registro.aviso('no se pudo poner la identidad del aparato: $e');
    }
    handler.next(options);
  }
}
