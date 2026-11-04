// LA COSTURA CON EL GPS DEL APARATO, detras de una interfaz para que los tests
// metan un falso (como `AbrirYCompartir`). La de verdad es
// `servicio_geolocator.dart`, la unica que importa `geolocator`.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'puntos_locales.dart';
import 'servicio_geolocator.dart';

enum PermisoDeUbicacion {
  concedido,
  denegado,

  /// Lo bloqueo para siempre: solo se arregla en los ajustes del telefono.
  denegadoParaSiempre,

  /// El GPS del telefono esta apagado.
  gpsApagado;

  bool get funciona => this == concedido;

  /// Lo que se le DICE a la persona (no impide trabajar).
  String? get aviso => switch (this) {
    concedido => null,
    denegado =>
      'Sin permiso de ubicación: la oficina no verá tu recorrido. '
          'Puedes seguir trabajando.',
    denegadoParaSiempre =>
      'La ubicación está bloqueada para Reparto: la oficina no verá tu recorrido. '
          'Actívala en los ajustes del teléfono. Puedes seguir trabajando.',
    gpsApagado =>
      'El GPS del teléfono está apagado: la oficina no verá tu recorrido. '
          'Puedes seguir trabajando.',
  };
}

abstract interface class ServicioDeUbicacion {
  /// Como esta el permiso AHORA, sin preguntar nada.
  Future<PermisoDeUbicacion> permiso();

  /// Pide el permiso (y el de notificaciones) si falta.
  Future<PermisoDeUbicacion> pedirPermiso();

  /// Arranca UN solo flujo con el servicio en primer plano y su notificacion fija.
  /// Llamarlo dos veces no abre dos flujos.
  Future<void> empezar(void Function(Posicion) alLlegar);

  /// Apaga el flujo y la notificacion.
  Future<void> parar();

  /// Una posicion para un punto de evento; `null` si no hay (sin permiso, sin senal).
  Future<Posicion?> posicionAhora();
}

final servicioDeUbicacionProvider = Provider<ServicioDeUbicacion>(
  (ref) => ServicioGeolocator(),
);
