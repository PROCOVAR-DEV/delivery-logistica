// LA DE VERDAD: `geolocator` 14.0.1. NO PROBADA EN UN TELEFONO REAL (hasta
// instalar el APK no se sabe si el fabricante mata el servicio, ver
// `docs/app-distribuidor.md`).
import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../nucleo/registro/registro.dart';
import 'ajustes_de_gps.dart';
import 'puntos_locales.dart';
import 'servicio_de_ubicacion.dart';

class ServicioGeolocator implements ServicioDeUbicacion {
  StreamSubscription<Position>? _flujo;

  static PermisoDeUbicacion _de(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => PermisoDeUbicacion.concedido,
    LocationPermission.deniedForever => PermisoDeUbicacion.denegadoParaSiempre,
    _ => PermisoDeUbicacion.denegado,
  };

  @override
  Future<PermisoDeUbicacion> permiso() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return PermisoDeUbicacion.gpsApagado;
      }
      return _de(await Geolocator.checkPermission());
    } on Object catch (e) {
      Registro.aviso('GPS: no se pudo mirar el permiso: $e');
      return PermisoDeUbicacion.denegado;
    }
  }

  @override
  Future<PermisoDeUbicacion> pedirPermiso() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      final r = _de(p);
      return r.funciona && !await Geolocator.isLocationServiceEnabled()
          ? PermisoDeUbicacion.gpsApagado
          : r;
    } on Object catch (e) {
      Registro.aviso('GPS: no se pudo pedir el permiso: $e');
      return PermisoDeUbicacion.denegado;
    }
  }

  static Posicion _posicion(Position p) => Posicion(
    lat: p.latitude,
    lng: p.longitude,
    precision: p.accuracy,
    velocidad: p.speed,
    rumbo: p.heading,
    hora: DateTime.now(), // la del APARATO, no la del satelite
  );

  @override
  Future<void> empezar(void Function(Posicion) alLlegar) async {
    if (_flujo != null) return;
    _flujo =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: AjustesDeGps.distanciaEnMetros,
            intervalDuration: AjustesDeGps.intervalo,
            // El servicio en primer plano: sin esta notificacion Android mata el
            // flujo en cuanto la app pasa a segundo plano.
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: AjustesDeGps.tituloDeLaNotificacion,
              notificationText: AjustesDeGps.textoDeLaNotificacion,
              enableWakeLock: true,
              setOngoing: true,
            ),
          ),
        ).listen(
          (p) => alLlegar(_posicion(p)),
          onError: (Object e) => Registro.aviso('GPS: el flujo fallo: $e'),
        );
  }

  @override
  Future<void> parar() async {
    final f = _flujo;
    _flujo = null;
    await f?.cancel();
  }

  @override
  Future<Posicion?> posicionAhora() async {
    try {
      if (!(await permiso()).funciona) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: AjustesDeGps.esperaDelPuntoDeEvento,
        ),
      );
      return _posicion(p);
    } on Object catch (e) {
      Registro.aviso('GPS: sin posicion para el evento: $e');
      return null;
    }
  }
}
