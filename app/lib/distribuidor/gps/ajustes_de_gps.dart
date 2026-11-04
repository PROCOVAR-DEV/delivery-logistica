// LAS CONSTANTES DEL GPS, juntas para cambiarlas en un solo sitio.
abstract final class AjustesDeGps {
  /// Un punto cada ~30 s...
  static const intervalo = Duration(seconds: 30);

  /// ...o cada ~30 m. NO PROBADO en un telefono real: en Android el servicio de
  /// ubicacion aplica los dos a la vez (intervalo Y distancia), asi que parado en
  /// un almacen no hay puntos; la hora de llegada la da el punto `parada`.
  static const distanciaEnMetros = 30;

  /// Hasta cuantos puntos van en cada `POST /api/track`.
  static const tamanoDelLote = 200;

  /// Los puntos YA SUBIDOS se podan a los 90 dias; los no subidos, nunca.
  static const retencionDeLosSubidos = Duration(days: 90);

  /// Cuanto se espera a una posicion para un punto de evento (`parada`, ...)
  /// antes de renunciar a el.
  static const esperaDelPuntoDeEvento = Duration(seconds: 8);

  /// La notificacion fija del servicio en primer plano.
  static const tituloDeLaNotificacion = 'Reparto: ruta en curso';
  static const textoDeLaNotificacion =
      'Reparto registra tu ubicacion mientras haces la ruta.';
}
