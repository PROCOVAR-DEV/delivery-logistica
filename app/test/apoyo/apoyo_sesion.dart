import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

import 'servidor_falso.dart';

/// Un JWT **sin firmar de verdad**: aqui nadie comprueba la firma, y esta bien
/// que sea asi. Quien la comprueba es el servidor en cada peticion; el aparato
/// sólo lee la carga para saber que sucursal pintar en la barra.
String tokenDePrueba({
  String sub = 'u-1',
  String sucursal = 'STG',
  List<String> roles = const ['SUPERVISOR'],
  String nombre = '',
  String correo = '',
  String rol = '',
}) {
  String trozo(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final cabecera = trozo(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'});
  final carga = trozo(<String, Object?>{
    'sub': sub,
    'roles': roles,
    'sucursal': sucursal,
    'branch_id': sucursal,
    // Los tres de ENSENAR. Sólo entran cuando se piden: un token de auth de
    // verdad los trae, pero anadirlos por defecto cambiaria lo que ven las
    // pruebas que ya estaban escritas sin ellos.
    if (nombre.isNotEmpty) 'name': nombre,
    if (correo.isNotEmpty) 'email': correo,
    if (rol.isNotEmpty) 'role': rol,
  });
  return '$cabecera.$carga.firmafalsa';
}

/// Lo que contesta `POST /api/auth/token` de verdad, con los nombres de verdad:
/// `refresh_token` y no `refresh`.
Map<String, Object?> parDeTokens({String refresh = 'refresh-1'}) =>
    <String, Object?>{
      'token': tokenDePrueba(),
      'refresh_token': refresh,
      'token_type': 'Bearer',
      'expires_in': 900,
      'refresh_expires_in': 2592000,
    };

/// Lo que contesta `POST /api/auth/logout` de Accesos de verdad: `200 {"ok":
/// true}` en JSON, SIEMPRE (`auth/src/app/api/auth/logout/route.ts`). Un `200 {}`
/// ya no confirma el cierre (`cierreConfirmado`).
RespuestaFalsa logoutDeAccesos() =>
    RespuestaFalsa(200, <String, Object?>{'ok': true});

Sesion sesionDePrueba({String refresh = 'refresh-1'}) =>
    Sesion.deJson(parDeTokens(refresh: refresh));

/// Un `ClienteApi` contra el servidor falso y **sin esperas**: en un test, los
/// reintentos de 1 s, 4 s, 15 s y 60 s son un temporizador colgado que hace
/// fallar a `pumpAndSettle` por un motivo que no tiene nada que ver con lo que
/// se estaba probando.
ClienteApi clienteFalso(
  Future<RespuestaFalsa?> Function(PeticionVista) responder, {
  String baseUrl = 'https://ejemplo.test/api',
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl))
    ..httpClientAdapter = ServidorFalso(responder);
  return ClienteApi(dio: dio, esperas: const []);
}

/// Un Dio de auth falso, para la pantalla de acceso y para el renovador.
Dio dioFalso(Future<RespuestaFalsa?> Function(PeticionVista) responder) =>
    Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
      ..httpClientAdapter = ServidorFalso(responder);
