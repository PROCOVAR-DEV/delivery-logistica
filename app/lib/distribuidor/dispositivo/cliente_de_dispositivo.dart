// LAS DOS PUERTAS DEL DISPOSITIVO, sin Authorization (aun no hay acceso, o es lo que
// se esta renovando): `POST /api/d/reclamar` y `POST /api/d/renovar`.
import 'package:dio/dio.dart';

import '../../nucleo/red/fallos.dart';

class RutaReclamada {
  const RutaReclamada({
    required this.acceso,
    required this.rutaId,
    this.secreto,
    this.expira,
    this.sucursal,
  });

  /// El JWT (rol DISTRIBUIDOR, claim `dispositivo`).
  final String acceso;

  /// Solo viene si el dispositivo es NUEVO para el servidor.
  final String? secreto;
  final DateTime? expira;
  final String rutaId;
  final String? sucursal;
}

/// Un «no» del servidor al enlace, ya con las palabras para la persona.
class EnlaceRechazado implements Exception {
  const EnlaceRechazado(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

class ClienteDeDispositivo {
  ClienteDeDispositivo(this._dio);

  final Dio _dio;

  Future<RutaReclamada> reclamar({
    required String token,
    required String dispositivoId,
    required String nombre,
    String? secreto,
  }) async {
    try {
      final r = await _dio.post<Map<String, Object?>>(
        '/d/reclamar',
        data: <String, Object?>{
          'token': token,
          'dispositivoId': dispositivoId,
          'nombre': nombre,
          'secreto': ?secreto,
        },
      );
      final d = r.data ?? const <String, Object?>{};
      final acceso = d['acceso'];
      final rutaId = d['rutaId'];
      if (acceso is! String || rutaId is! String) {
        throw const EnlaceRechazado(
          'El servidor no contestó lo esperado. Inténtalo otra vez.',
        );
      }
      return RutaReclamada(
        acceso: acceso,
        rutaId: rutaId,
        secreto: d['secreto'] as String?,
        expira: DateTime.tryParse('${d['expira'] ?? ''}'),
        sucursal: d['sucursal'] as String?,
      );
    } on DioException catch (e) {
      throw _traducir(e);
    }
  }

  /// Un acceso nuevo. 401 = el servidor ya no reconoce al dispositivo
  /// ([SesionMuerta]); sin red = [FalloDeRed] (se sigue con el acceso que hay).
  Future<({String acceso, DateTime? expira})> renovar({
    required String dispositivoId,
    required String secreto,
  }) async {
    try {
      final r = await _dio.post<Map<String, Object?>>(
        '/d/renovar',
        data: <String, Object?>{
          'dispositivoId': dispositivoId,
          'secreto': secreto,
        },
      );
      final acceso = r.data?['acceso'];
      if (acceso is! String) {
        throw const FalloDeRed(detalle: 'renovar sin acceso');
      }
      return (
        acceso: acceso,
        expira: DateTime.tryParse('${r.data?['expira']}'),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const SesionMuerta('el servidor ya no reconoce a este teléfono');
      }
      throw FalloDeRed(codigo: e.response?.statusCode, detalle: e.message);
    }
  }

  Object _traducir(DioException e) {
    final codigo = e.response?.statusCode;
    final cuerpo = e.response?.data;
    final marca = cuerpo is Map ? (cuerpo['error'] ?? cuerpo['codigo']) : null;
    final mensaje = cuerpo is Map ? cuerpo['mensaje'] : null;
    // Primero la marca del servidor (es lo que dice POR QUE), luego el numero.
    switch (marca) {
      case 'ruta_de_otro_dispositivo':
        return const EnlaceRechazado(
          'Esta ruta ya está asignada a otro teléfono.',
        );
      case 'enlace_no_valido':
        return const EnlaceRechazado(
          'Este enlace no es válido. Pídele a tu logístico que te lo mande otra vez.',
        );
      case 'enlace_revocado':
        return const EnlaceRechazado(
          'Este enlace ya no vale: logística lo anuló. Pídele uno nuevo.',
        );
      case 'ruta_cerrada':
        return const EnlaceRechazado(
          'Esta ruta ya está cerrada: logística la dio por terminada.',
        );
    }
    return switch (codigo) {
      404 => const EnlaceRechazado(
        'Este enlace no es válido. Pídele a tu logístico que te lo mande otra vez.',
      ),
      410 => const EnlaceRechazado(
        'Este enlace ya no vale: logística lo anuló. Pídele uno nuevo.',
      ),
      null => const FalloDeRed(detalle: 'sin conexión'),
      _ => EnlaceRechazado(
        mensaje is String && mensaje.isNotEmpty
            ? mensaje
            : 'No se pudo añadir la ruta${marca is String ? ' ($marca)' : ' ($codigo)'}. Inténtalo otra vez.',
      ),
    };
  }
}
