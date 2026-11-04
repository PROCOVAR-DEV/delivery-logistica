// EL RECORRIDO: quien decide cuando se enciende el GPS y guarda los puntos.
//
//  * Se enciende mientras haya AL MENOS UNA ruta en curso y la persona haya
//    aceptado el aviso; se apaga cuando no queda ninguna. UN solo flujo para todas
//    las rutas: cada punto lleva `rutaIds`, las que estaban en curso en ese instante.
//  * Sin permiso o sin aceptar: no hay GPS y SE TRABAJA IGUAL. Nada de aqui lanza
//    hacia fuera (un fallo de ubicacion no puede impedir marcar una parada).
//  * Los puntos van a la base local primero; la subida es de `subida_del_recorrido.dart`.
import 'dart:async';

import '../../nucleo/registro/registro.dart';
import 'puntos_locales.dart';
import 'servicio_de_ubicacion.dart';

class RecorridoGps {
  RecorridoGps({
    required PuntosGpsLocales puntos,
    required ServicioDeUbicacion servicio,
    required Future<bool> Function() haAceptado,
    DateTime Function()? reloj,
    void Function(PermisoDeUbicacion)? alVerElPermiso,
  }) : _puntos = puntos,
       _servicio = servicio,
       _haAceptado = haAceptado,
       _reloj = reloj ?? DateTime.now,
       _alVerElPermiso = alVerElPermiso;

  final PuntosGpsLocales _puntos;
  final ServicioDeUbicacion _servicio;
  final Future<bool> Function() _haAceptado;
  final DateTime Function() _reloj;
  final void Function(PermisoDeUbicacion)? _alVerElPermiso;

  /// Una lectura mas vieja que esto no vale para un punto de evento.
  static const _vejezMaxima = Duration(minutes: 2);

  Set<String> _enCurso = {};
  Posicion? _ultima;
  bool _encendido = false;

  bool get encendido => _encendido;

  /// Las rutas en curso AHORA (o el consentimiento) cambiaron: enciende o apaga.
  Future<void> sincronizar(Set<String> enCurso) async {
    _enCurso = {...enCurso};
    try {
      final quiere = _enCurso.isNotEmpty && await _haAceptado();
      if (quiere && !_encendido) {
        final permiso = await _servicio.pedirPermiso();
        _alVerElPermiso?.call(permiso);
        if (!permiso.funciona) return;
        _encendido = true;
        await _servicio.empezar(_alLlegar);
      } else if (!quiere && _encendido) {
        _encendido = false;
        _ultima = null;
        await _servicio.parar();
      }
    } on Object catch (e, pila) {
      Registro.fallo('GPS: no se pudo encender o apagar', e, pila);
    }
  }

  void _alLlegar(Posicion p) {
    if (!_encendido) return;
    _ultima = p;
    unawaited(
      _puntos
          .guardar(p, rutaIds: _enCurso)
          .then((_) {}, onError: (Object e) => Registro.aviso('GPS: $e')),
    );
  }

  /// Un punto de evento (`inicio`, `parada`, `fin`). [rutaId] va SIEMPRE en
  /// `rutaIds`, aunque ya no este en curso (el `fin` se registra con la ruta ya
  /// completada). Sin aceptar o sin posicion, no hay punto y no pasa nada.
  Future<void> evento(
    String evento, {
    required String rutaId,
    String? pedidoId,
  }) async {
    try {
      if (!await _haAceptado()) return;
      var p = await _servicio.posicionAhora();
      final ultima = _ultima;
      if (p == null &&
          ultima != null &&
          _reloj().difference(ultima.hora) <= _vejezMaxima) {
        p = ultima;
      }
      if (p == null) return;
      await _puntos.guardar(
        p,
        rutaIds: {..._enCurso, rutaId},
        evento: evento,
        pedidoId: pedidoId,
      );
    } on Object catch (e, pila) {
      Registro.fallo('GPS: no se pudo guardar el punto de $evento', e, pila);
    }
  }
}
