// LOS PUNTOS DE GPS EN LA BASE LOCAL: guardar, leer lo que falta por subir,
// marcar lo subido y podar. La subida de verdad esta en `subida_del_recorrido.dart`.
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../nucleo/base/base.dart';
import '../../nucleo/cola/provisionales.dart';
import 'ajustes_de_gps.dart';

/// Una lectura de ubicacion, venga de donde venga (el servicio o un test).
class Posicion {
  const Posicion({
    required this.lat,
    required this.lng,
    required this.hora,
    this.precision,
    this.velocidad,
    this.rumbo,
  });

  final double lat;
  final double lng;
  final double? precision;
  final double? velocidad;
  final double? rumbo;

  /// La hora del APARATO al leerla.
  final DateTime hora;
}

abstract final class EventoDeRecorrido {
  static const inicio = 'inicio';
  static const parada = 'parada';
  static const fin = 'fin';
}

class PuntosGpsLocales {
  PuntosGpsLocales(this._base);

  final BaseLocal _base;

  Future<String> guardar(
    Posicion p, {
    required Iterable<String> rutaIds,
    String? evento,
    String? pedidoId,
  }) async {
    final id = Provisionales.nuevoIdReal();
    await _base
        .into(_base.puntosGps)
        .insert(
          PuntosGpsCompanion.insert(
            id: id,
            rutaIds: jsonEncode(rutaIds.toSet().toList()),
            lat: p.lat,
            lng: p.lng,
            precision: Value(p.precision),
            velocidad: Value(p.velocidad),
            rumbo: Value(p.rumbo),
            hora: p.hora,
            evento: Value(evento),
            pedidoId: Value(pedidoId),
          ),
        );
    return id;
  }

  /// Los siguientes por subir, del mas viejo al mas nuevo.
  Future<List<PuntoDeRecorrido>> pendientes({
    int limite = AjustesDeGps.tamanoDelLote,
  }) =>
      (_base.select(_base.puntosGps)
            ..where((p) => p.subido.equals(false))
            ..orderBy([(p) => OrderingTerm.asc(p.hora)])
            ..limit(limite))
          .get();

  Future<int> cuantosSinSubir() async {
    final cuenta = _base.puntosGps.id.count();
    final fila =
        await (_base.selectOnly(_base.puntosGps)
              ..addColumns([cuenta])
              ..where(_base.puntosGps.subido.equals(false)))
            .getSingle();
    return fila.read(cuenta) ?? 0;
  }

  Future<void> marcarSubidos(Iterable<String> ids) =>
      (_base.update(_base.puntosGps)..where((p) => p.id.isIn(ids.toList())))
          .write(const PuntosGpsCompanion(subido: Value(true)));

  /// Borra los YA SUBIDOS de hace mas de 90 dias. **Los no subidos no se tocan
  /// jamas**: son lo unico que queda de un recorrido que no ha llegado arriba.
  Future<int> podar(DateTime ahora) =>
      (_base.delete(_base.puntosGps)..where(
            (p) =>
                p.subido.equals(true) &
                p.hora.isSmallerThanValue(
                  ahora.subtract(AjustesDeGps.retencionDeLosSubidos),
                ),
          ))
          .go();

  /// El cuerpo de `POST /api/track` para estos puntos.
  static Map<String, Object?> cuerpoDe(List<PuntoDeRecorrido> puntos) => {
    'puntos': [
      for (final p in puntos)
        {
          'id': p.id,
          'rutaIds': (jsonDecode(p.rutaIds) as List).cast<String>(),
          'lat': p.lat,
          'lng': p.lng,
          'precision': p.precision,
          'velocidad': p.velocidad,
          'rumbo': p.rumbo,
          'hora': p.hora.toUtc().toIso8601String(),
          'evento': p.evento,
          'pedidoId': p.pedidoId,
        },
    ],
  };
}
