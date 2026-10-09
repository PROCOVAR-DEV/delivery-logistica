import 'dart:convert';

import 'package:web/web.dart' as web;

import '../registro/registro.dart';
import 'almacen_sesion.dart';
import 'sesion.dart';

/// Web: el almacen del navegador, **detras de la cookie del login unico**.
///
/// La web entra por Accesos: redireccion y vuelta con una cookie `httpOnly`
/// (`docs/identidad.md`, y `nucleo/identidad/entrada_por_accesos.dart`). Esa
/// cookie NO se puede leer desde aqui —para eso es `httpOnly`— y no hace falta:
/// el navegador la manda sola en cada peticion y quien sabe si vale es el
/// servidor.
///
/// Por eso el de la web es [AlmacenPorCookie] y no este. Este sigue entero, y no
/// es un resto: es **la puerta de respaldo**. Si el login unico no esta —falta
/// la llave, Accesos no contesta— la pantalla de acceso deja entrar con usuario
/// y contrasena, y ese par hay que guardarlo en algun sitio o cada recarga
/// devolveria a la puerta con la aplicacion vacia detras.
///
/// `localStorage` y no `sessionStorage`: el logistico recarga, cierra la pestana
/// y vuelve, y la regla de la casa es que quien entro sigue dentro. Lo que se
/// guarda es exactamente lo mismo que guarda la APK en el Keystore, con la
/// diferencia conocida de que en el navegador no hay Keystore — por eso el
/// acceso dura lo que dura el refresh y un 401 lo borra entero.
AlmacenDeSesion abrirAlmacenDeSesion() =>
    const AlmacenPorCookie(AlmacenDelNavegador());

class AlmacenDelNavegador with PorRevocarEnTexto implements AlmacenDeSesion {
  const AlmacenDelNavegador();

  static const clave = 'reparto.sesion';

  /// **No lanza nunca** — ver la regla en `almacen_sesion.dart`.
  @override
  Future<Sesion?> leer() async {
    final String? crudo;
    try {
      crudo = _caja?.getItem(clave);
    } on Object catch (e) {
      Registro.fallo('el navegador no dejo leer la sesion: $e');
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

  /// Guarda el par **y comprueba que se puede volver a leer**, igual que la
  /// APK. En el navegador el modo de fallo es otro —ventana privada, sitio sin
  /// permiso para guardar, cuota llena— pero el resultado es el mismo: una
  /// promesa de trabajar sin senal que no se cumple. Ver `almacen_sesion.dart`.
  @override
  Future<bool> guardar(Sesion sesion) async {
    final texto = jsonEncode(sesion.aJson());
    final caja = _caja;
    if (caja == null) return false;
    try {
      caja.setItem(clave, texto);
      return caja.getItem(clave) == texto;
    } on Object catch (e) {
      Registro.fallo('el navegador no dejo guardar la sesion: $e');
      return false;
    }
  }

  /// La web no tiene par que revocar (su sesion es la cookie): nada se guarda.
  @override
  Future<String?> leerPorRevocar() async => null;

  @override
  Future<bool> escribirPorRevocar(String? texto) async => true;

  @override
  Future<void> borrar() async {
    try {
      _caja?.removeItem(clave);
    } on Object catch (e) {
      Registro.aviso('el navegador no dejo borrar la sesion: $e');
    }
  }

  @override
  Future<SaludDelAlmacen> comprobar() async {
    final caja = _caja;
    if (caja == null) {
      return const SaludDelAlmacen.rota(
        'Este navegador no deja guardar la sesión.',
      );
    }
    const claveDePrueba = 'reparto.comprobacion';
    final testigo = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      caja.setItem(claveDePrueba, testigo);
      final vuelta = caja.getItem(claveDePrueba);
      caja.removeItem(claveDePrueba);
      if (vuelta == testigo) return const SaludDelAlmacen.bien();
    } on Object catch (e) {
      Registro.aviso('el navegador no sirve para guardar la sesion: $e');
    }
    return const SaludDelAlmacen.rota(
      'Este navegador no deja guardar la sesión.',
    );
  }

  /// `localStorage` puede no estar: en modo privado de algunos navegadores el
  /// acceso lanza. Sin el, la aplicacion se comporta como si no hubiera sesion
  /// guardada —hay que entrar otra vez— en vez de no arrancar.
  static web.Storage? get _caja {
    try {
      return web.window.localStorage;
    } on Object catch (e) {
      Registro.aviso('el navegador no deja guardar la sesion: $e');
      return null;
    }
  }
}
