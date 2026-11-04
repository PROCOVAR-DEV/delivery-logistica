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
    this.vinculoId,
    this.vehiculoId,
    this.vehiculo,
    this.distribuidor,
  });

  /// El JWT (rol DISTRIBUIDOR, claim `dispositivo`).
  final String acceso;

  /// Solo viene si el dispositivo es NUEVO para el servidor.
  final String? secreto;
  final DateTime? expira;
  final String rutaId;
  final String? sucursal;

  /// El vinculo de este telefono con SU vehiculo (el enlace trae vehiculo y
  /// distribuidor). `distribuidor` solo viene si la ruta lo tiene.
  final String? vinculoId;
  final String? vehiculoId;
  final Map<String, Object?>? vehiculo; // {id, nombre, placa, tipo}
  final Map<String, Object?>? distribuidor; // {id, nombre}
}

/// Un «no» del servidor al enlace, ya con las palabras para la persona.
class EnlaceRechazado implements Exception {
  const EnlaceRechazado(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// El 403 `dispositivo_desvinculado`: la oficina desvinculo este telefono de su vehiculo.
/// Es un `Rechazo` con su marca para que el interceptor y el arranque lo traten como
/// cualquier otro 403 de la API.
class DispositivoDesvinculado extends Rechazo {
  const DispositivoDesvinculado()
    : super(
        403,
        'Este teléfono fue desvinculado de su vehículo.',
        marca: marcaDispositivoDesvinculado,
      );
}

/// El 401 `secreto_incorrecto` al RECLAMAR: el servidor conoce este id de teléfono pero la clave no cuadra. Si el teléfono no tiene ninguna clave
/// guardada es que la respuesta de su primer reclamo se perdió: se estrena otro id (auditoría 04/11/2026).
class SecretoDelTelefonoNoCuadra extends EnlaceRechazado {
  const SecretoDelTelefonoNoCuadra()
    : super('Este teléfono no se reconoce. Pide a tu logístico que lo desvincule y vuelve a abrir el enlace.');
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
        vinculoId: d['vinculoId'] as String?,
        vehiculoId: d['vehiculoId'] as String?,
        vehiculo: _mapa(d['vehiculo']),
        distribuidor: _mapa(d['distribuidor']),
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
      if (_esDesvinculado(e)) throw const DispositivoDesvinculado();
      if (e.response?.statusCode == 401) {
        throw const SesionMuerta('el servidor ya no reconoce a este teléfono');
      }
      throw FalloDeRed(codigo: e.response?.statusCode, detalle: e.message);
    }
  }

  static Map<String, Object?>? _mapa(Object? crudo) =>
      crudo is Map ? Map<String, Object?>.from(crudo) : null;

  static bool _esDesvinculado(DioException e) {
    final cuerpo = e.response?.data;
    return e.response?.statusCode == 403 &&
        cuerpo is Map &&
        (cuerpo['codigo'] ?? cuerpo['error']) == marcaDispositivoDesvinculado;
  }

  Object _traducir(DioException e) {
    if (_esDesvinculado(e)) return const DispositivoDesvinculado();
    final codigo = e.response?.statusCode;
    final cuerpo = e.response?.data;
    final marca = cuerpo is Map ? (cuerpo['error'] ?? cuerpo['codigo']) : null;
    final mensaje = cuerpo is Map
        ? (cuerpo['mensaje'] ?? cuerpo['message'])
        : null;
    // Primero la marca del servidor (es lo que dice POR QUE), luego el numero.
    switch (marca) {
      case 'secreto_incorrecto':
        return const SecretoDelTelefonoNoCuadra();
      case 'telefono_en_alta':
        return const EnlaceRechazado('Este teléfono se está dando de alta: espera un momento y vuelve a abrir el enlace.');
      // El vehiculo/el telefono ya estan vinculados a otro: el mensaje es del servidor.
      case 'vehiculo_de_otro_dispositivo':
        return EnlaceRechazado(
          mensaje is String && mensaje.isNotEmpty ? mensaje : 'Este vehículo ya está vinculado a otro teléfono: pide a tu logístico que lo desvincule.',
        );
      case 'dispositivo_de_otro_vehiculo':
        return EnlaceRechazado(
          mensaje is String && mensaje.isNotEmpty ? mensaje : 'Este teléfono ya está vinculado a otro vehículo: pide a tu logístico que lo desvincule.',
        );
      case 'ruta_sin_vehiculo':
        return EnlaceRechazado(
          mensaje is String && mensaje.isNotEmpty
              ? mensaje
              : 'Esta ruta no tiene vehículo asignado: avisa a tu logístico.',
        );
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
