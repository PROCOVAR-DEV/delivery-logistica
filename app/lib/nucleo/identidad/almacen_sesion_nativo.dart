import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../registro/registro.dart';
import 'almacen_sesion.dart';
import 'almacen_sesion_fichero.dart';
import 'sesion.dart';

/// DONDE GUARDA CADA DESTINO, y por que no es el mismo sitio en todos.
///
/// * **Android** → el almacen del sistema (Keystore). Probado y funcionando.
/// * **Linux** → un fichero propio, cifrado y atado a la maquina
///   ([AlmacenEnFichero]). NO el almacen del sistema: en Linux
///   `flutter_secure_storage` 3.0.3 acepta la escritura y despues no encuentra
///   nada, asi que la aplicacion de escritorio pedia la contrasena en cada
///   arranque — y sin senal eso es no poder entrar. El porque, con el codigo
///   del plugin delante, en `almacen_sesion_fichero.dart`.
/// * **Windows y Apple** → el almacen del sistema (DPAPI, Llavero). Se dejan
///   como estaban: alli el fallo de Linux no aplica, porque es otro codigo
///   nativo distinto. **Windows no se ha comprobado desde este equipo** — no se
///   puede, Flutter no cruza de plataforma—, asi que si alguna vez se ve el
///   mismo cuadro (entrar, cerrar, abrir y que pida la contrasena), la salida
///   es la misma que aqui: este fichero, que no depende de ningun servicio del
///   sistema.
AlmacenDeSesion abrirAlmacenDeSesion() =>
    Platform.isLinux ? AlmacenEnFichero() : AlmacenSeguro();

class AlmacenSeguro with PorRevocarEnTexto implements AlmacenDeSesion {
  AlmacenSeguro([FlutterSecureStorage? caja])
    : _caja =
          caja ??
          const FlutterSecureStorage(
            // Los valores por defecto de la version 11 ya son los buenos:
            // clave envuelta con RSA en el Keystore y datos con AES-GCM. Se
            // dejan a proposito SIN biometria: el logistico abre la aplicacion
            // con guantes en el patio de un almacen.
            aOptions: AndroidOptions(),
          );

  static const _clave = 'reparto.sesion';

  /// La clave de la ida y vuelta de [comprobar]. Aparte de la de la sesion para
  /// no tocarla: comprobar no puede ser lo que rompa lo que se quiere proteger.
  static const _claveDePrueba = 'reparto.comprobacion';

  final FlutterSecureStorage _caja;

  /// La sesion guardada, o `null`. **No lanza nunca** — ver la regla en
  /// `almacen_sesion.dart`.
  ///
  /// El `try` envuelve TAMBIEN la lectura, y ese es el arreglo del 15/09/2026:
  /// antes solo envolvia el `jsonDecode`, asi que un fallo del almacen del
  /// sistema —en Linux, `flutter_secure_storage` habla con el servicio de
  /// secretos por D-Bus y eso se cae de mil maneras— subia hasta el portero,
  /// que lo traducia a «no hay sesion» y dejaba a la persona delante de un
  /// formulario mudo con sus datos en el disco.
  @override
  Future<Sesion?> leer() async {
    final String? crudo;
    try {
      crudo = await _caja.read(key: _clave);
    } on Object catch (e, pila) {
      // Que NO se borre nada aqui. Un almacen que hoy no contesta puede
      // contestar mañana, y borrar el par por un fallo del sistema es dejar a
      // alguien fuera en la calle — la regla 3 de `identidad.md` aplicada al
      // disco en vez de a la red.
      Registro.fallo('el almacen del sistema no dejo leer la sesion', e, pila);
      return null;
    }
    if (crudo == null) return null;
    try {
      return Sesion.deJson(jsonDecode(crudo) as Map<String, Object?>);
    } on Object {
      // Guardado ilegible: se trata como «no hay sesion», no como un fallo. Lo
      // peor que puede pasar es que la persona entre otra vez.
      await borrar();
      return null;
    }
  }

  /// Guarda el par **y comprueba que se puede volver a leer**.
  ///
  /// La comprobacion no sobra. En Linux el almacen acepta la escritura —el
  /// secreto queda en el llavero, se puede leer el fichero— y despues
  /// `read` no encuentra nada: la sesion estaba guardada y perdida a la vez.
  /// Sin leerla de vuelta, eso no se nota hasta el siguiente arranque, que es
  /// justo cuando ya no hay nadie a quien preguntar.
  @override
  Future<bool> guardar(Sesion sesion) async {
    final texto = jsonEncode(sesion.aJson());
    try {
      await _caja.write(key: _clave, value: texto);
      final vuelta = await _caja.read(key: _clave);
      if (vuelta == texto) return true;
      Registro.fallo(
        'el almacen del sistema acepto la sesion y luego no la encuentra: '
        'este aparato no va a poder trabajar sin senal',
      );
      return false;
    } on Object catch (e, pila) {
      Registro.fallo(
        'el almacen del sistema no dejo guardar la sesion',
        e,
        pila,
      );
      return false;
    }
  }

  @override
  Future<void> borrar() async {
    try {
      await _caja.delete(key: _clave);
    } on Object catch (e) {
      // Salir tiene que poder salir. Si el almacen no deja borrar, el par
      // caduca solo y lo que no puede pasar es que la persona se quede dentro.
      Registro.aviso('el almacen del sistema no dejo borrar la sesion: $e');
    }
  }

  /// Aparte de la sesion, a proposito: ver [RefrescoPorRevocar].
  static const _clavePorRevocar = 'reparto.por_revocar';

  @override
  Future<String?> leerPorRevocar() async {
    try {
      return await _caja.read(key: _clavePorRevocar);
    } on Object catch (e) {
      Registro.aviso('el almacen del sistema no dejo leer lo por revocar: $e');
      return null;
    }
  }

  @override
  Future<bool> escribirPorRevocar(String? texto) async {
    try {
      if (texto == null) {
        await _caja.delete(key: _clavePorRevocar);
      } else {
        await _caja.write(key: _clavePorRevocar, value: texto);
      }
      return true;
    } on Object catch (e) {
      Registro.aviso('el almacen del sistema no dejo guardar lo por revocar: $e');
      return false;
    }
  }

  /// Una ida y vuelta de verdad, con su propia clave y limpiando detras.
  ///
  /// No se mira si el plugin esta montado: el caso que se vio en Linux es
  /// exactamente uno en el que el plugin esta montado, contesta que si a la
  /// escritura y devuelve vacio en la lectura.
  @override
  Future<SaludDelAlmacen> comprobar() async {
    // Un valor distinto cada vez: uno fijo no distingue «se leyo lo que acabo
    // de escribir» de «quedo ahi de la vez anterior».
    final testigo = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      await _caja.write(key: _claveDePrueba, value: testigo);
      final vuelta = await _caja.read(key: _claveDePrueba);
      await _caja.delete(key: _claveDePrueba);
      if (vuelta == testigo) return const SaludDelAlmacen.bien();
      return const SaludDelAlmacen.rota(
        'Este aparato acepta guardar la sesión pero después no la encuentra.',
      );
    } on Object catch (e) {
      Registro.aviso('el almacen del sistema no sirve en este aparato: $e');
      return const SaludDelAlmacen.rota(
        'Este aparato no tiene dónde guardar la sesión.',
      );
    }
  }
}
