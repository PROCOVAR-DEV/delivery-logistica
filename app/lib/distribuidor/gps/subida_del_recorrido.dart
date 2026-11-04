// LA SUBIDA DEL GPS: por lotes de hasta 200, tras la cola de apuntes, cuando hay
// red. `POST /api/track` con `{"puntos":[...]}` -> `{"recibidos":N}`, idempotente
// por el id de cada punto.
//
// **Un fallo no pierde nada**: los puntos se marcan subidos DESPUES de la
// respuesta; si algo falla quedan como estaban y se reintentan en el ciclo
// siguiente. Un fallo del GPS tampoco tumba el ciclo de los apuntes (ya subieron).
import '../../nucleo/red/fallos.dart' show SesionMuerta;
import '../../nucleo/registro/registro.dart';
import 'ajustes_de_gps.dart';
import 'puntos_locales.dart';

typedef EnviarPuntos = Future<void> Function(Map<String, Object?> cuerpo);

class SubidaDelRecorrido {
  SubidaDelRecorrido(this._puntos, this._enviar, {DateTime Function()? reloj})
    : _reloj = reloj ?? DateTime.now;

  final PuntosGpsLocales _puntos;
  final EnviarPuntos _enviar;
  final DateTime Function() _reloj;

  bool _subiendo = false;

  /// Sube todo lo pendiente (lote a lote) y poda lo viejo ya subido. Devuelve
  /// cuantos puntos subieron. No lanza, salvo [SesionMuerta], que es del ciclo.
  Future<int> subir() async {
    if (_subiendo) return 0;
    _subiendo = true;
    var subidos = 0;
    try {
      while (true) {
        final lote = await _puntos.pendientes();
        if (lote.isEmpty) break;
        await _enviar(PuntosGpsLocales.cuerpoDe(lote));
        await _puntos.marcarSubidos([for (final p in lote) p.id]);
        subidos += lote.length;
        if (lote.length < AjustesDeGps.tamanoDelLote) break;
      }
    } on SesionMuerta {
      rethrow;
    } on Object catch (e) {
      Registro.aviso('GPS: la subida de puntos fallo, se reintenta: $e');
    } finally {
      _subiendo = false;
    }
    try {
      await _puntos.podar(_reloj());
    } on Object catch (e) {
      Registro.aviso('GPS: no se pudo podar: $e');
    }
    return subidos;
  }
}
