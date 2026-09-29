import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// El registro de la aplicacion.
///
/// Existe como pieza propia y no como `print` suelto por una razon del pliego:
/// «nada se descarta en silencio». Un fallo que sólo se ve en la consola de
/// depuracion no se ve en el patio de un almacen, asi que todo lo que pasa por
/// aqui tiene un sitio donde acabar.
///
/// ## Y EN LA APK INSTALADA ESE SITIO ES `logcat` — 29/09/2026
///
/// Hasta hoy no habia ninguno. Se estaba probando la APK 1.0.17 en el telefono
/// de Jose y **no escribia ni una linea**: cero del proceso de la aplicacion,
/// cero con la etiqueta `flutter`, en cuatro mil renglones de `adb logcat`. O
/// sea que no habia forma de saber si un dato bajo **porque lo empujo el canal
/// en vivo o porque toco el reloj**, que es justamente la pregunta que habia que
/// contestar ese dia. Jose: «pues pon en la apk para poder ver por logcat y ya».
///
/// Eran dos cosas a la vez, y las dos habia que arreglarlas:
///
///  1. **`developer.log` no llega a `logcat` en una compilacion de release.**
///     Va al servicio de la maquina virtual de Dart, y en un aparato con la
///     aplicacion instalada no hay nadie escuchando ahi. En depuracion se ve
///     perfectamente, que es lo que hacia creer que funcionaba. Lo que SI llega
///     es la salida estandar: el arrancador de Flutter en Android la vuelca a
///     `logcat` con la etiqueta `flutter`. Por eso ahora se escribe en los dos
///     sitios.
///  2. **`info` se tiraba entero en release**, y `info` es casi todo lo que
///     cuenta la historia: «tocó el reloj», «canal de eventos: …», «almacenes:
///     recientes, no se piden». Sin eso quedaban sólo los fallos, o sea el final
///     de la pelicula.
///
/// Se lee asi:
///
/// ```
/// adb logcat -s flutter | grep reparto
/// ```
///
/// **Si algun dia estorba**, se calla entero sin tocar el codigo:
/// `--dart-define=REGISTRO=callado` al construir. No se deja callado por
/// defecto a proposito: un registro que hay que acordarse de encender es un
/// registro que no esta el dia que hace falta, y este proyecto ya ha perdido
/// tardes por fallos que no dejaban ni una linea.
abstract final class Registro {
  /// `callado` apaga la salida a `logcat`. Cualquier otra cosa la deja puesta.
  static const _comoVa = String.fromEnvironment('REGISTRO', defaultValue: 'hablador');

  static bool get _hablaPorLogcat => _comoVa != 'callado';

  static void info(String mensaje) => _escribir('info', mensaje);

  static void aviso(String mensaje) => _escribir('aviso', mensaje);

  static void fallo(String mensaje, [Object? error, StackTrace? pila]) =>
      _escribir('fallo', mensaje, error, pila);

  static void _escribir(
    String nivel,
    String mensaje, [
    Object? error,
    StackTrace? pila,
  ]) {
    // Para el depurador y para las herramientas de Flutter, igual que antes.
    developer.log(
      mensaje,
      name: 'reparto.$nivel',
      error: error,
      stackTrace: pila,
    );
    if (!_hablaPorLogcat) return;
    // Y para `logcat`, que es lo unico que se puede leer de una APK instalada.
    //
    // `debugPrint` y no `print`: trocea las lineas largas en vez de dejar que
    // Android las corte por la mitad, y ahi es donde se pierde justo el final
    // del mensaje, que suele ser el motivo.
    //
    // La marca `reparto.<nivel>` va delante para poder filtrar con un `grep`
    // sin tener que saberse los nombres de las clases.
    debugPrint('reparto.$nivel: $mensaje');
    if (error != null) debugPrint('reparto.$nivel:   por: $error');
    if (pila != null) debugPrint('reparto.$nivel:   $pila');
  }
}
