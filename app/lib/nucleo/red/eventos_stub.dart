import 'eventos.dart' show PulsoDelCanal;

/// SIN CANAL EN VIVO. Hoy no lo usa ningun destino.
///
/// Era el de la APK y el escritorio hasta el 17/09/2026, cuando dejaron de ir a
/// golpe de temporizador y pasaron a tener el suyo (`eventos_io.dart`). Se queda
/// como valor por defecto de la importacion condicional: un destino que no sea
/// ni la web ni `dart:io` —hoy no hay ninguno— se encuentra esto y no el fallo
/// de compilar.
///
/// Devuelve un stream que se cierra al momento: quien escuche no se queda
/// esperando un aviso que no va a llegar, y manda el temporizador del vigia.
Stream<String> escucharEventos(
  String urlBase,
  Future<String?> Function() token, {
  Future<void> Function()? renovarSesion,
  PulsoDelCanal? pulso,
}) => const Stream<String>.empty();

bool get hayCanalDeEventos => false;
