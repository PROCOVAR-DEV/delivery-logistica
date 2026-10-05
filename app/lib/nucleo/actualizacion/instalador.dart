// QUIEN LE PIDE A ANDROID QUE INSTALE EL APK QUE SE ACABA DE BAJAR.
//
// ## Lo que esto NO puede hacer, y se dice en la interfaz
//
// **Instalar.** Lo instala Android, y antes de instalar enseña **su** pantalla de
// «¿quieres instalar esta aplicación?». Eso no se puede saltar desde dentro de
// una aplicación que no es del sistema, y no hay truco que lo evite: lo único que
// se puede hacer es llegar hasta esa pantalla sin salir de aquí. Por eso el cajón
// lo avisa antes de empezar (`navegacion/aviso_de_version_nueva.dart`): quien
// pulsa «Instalar» tiene que saber que va a ver una pantalla del sistema, o la
// lee como un error y la cancela.
//
// Lo que sí cambia respecto a lo de antes —abrir el navegador— es todo lo demás:
// la descarga la hace la aplicación, con su barra de verdad, reanudable y
// comprobada, y al final es **un toque** en vez de buscar el fichero en la
// carpeta de Descargas.
//
// ## Los dos permisos, que no son el mismo
//
//  1. `REQUEST_INSTALL_PACKAGES` en el manifiesto. Es de instalación: se concede
//     al instalar la APK y no se pide a nadie.
//  2. **«Permitir instalar aplicaciones desconocidas» para ESTA aplicación**, que
//     en Android 8 y posteriores es un ajuste por aplicación y lo da la persona.
//     `sePuedeInstalarDesdeAqui` es justo esa pregunta, y la respuesta es `false`
//     la primera vez en todos los teléfonos.
//
// El segundo es el caso que **tenía que estar resuelto antes de escribir nada**,
// porque es el estado normal el primer día: sin él no se puede instalar, así que
// la pantalla ofrece las dos salidas —ir al ajuste, o bajarlo por el navegador
// como siempre— en vez de un «no se pudo instalar» sin nada que tocar
// (`CLAUDE.md` §4: un aviso sin acción es un aviso que se queda puesto para
// siempre).
//
// ## Por qué un canal propio y no un plugin
//
// Porque ya hay un canal escrito en este proyecto por lo mismo
// (`VeredictoDeRed`, el «!» del wifi) y porque un plugin para esto trae un
// `FileProvider` más, un permiso más y versiones que mantener para resolver
// quince líneas de Kotlin que queremos leer. Lo nuestro está en
// `android/app/src/main/kotlin/cloud/procovar/reparto/InstaladorDeApk.kt`.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../registro/registro.dart';
import 'version_publicada.dart';

/// EL CANAL, y los códigos que contesta.
///
/// Están aquí y en el Kotlin, o sea escritos dos veces, que es lo que siempre
/// acaba en que uno cambia y el otro no. Por eso no hay un comentario pidiendo
/// que se mantengan iguales: hay una prueba que abre el fichero de Kotlin y el
/// manifiesto y lo comprueba
/// (`test/nucleo/actualizacion/el_lado_de_android_cuadra_test.dart`). Un
/// comentario no falla.
abstract final class CanalDelInstalador {
  static const nombre = 'cloud.procovar.reparto/instalar_apk';

  /// ¿Puede esta aplicación pedir una instalación? (el ajuste por aplicación)
  static const sePuede = 'sePuede';

  /// Abre la pantalla del sistema para instalar el fichero.
  static const instalar = 'instalar';

  /// Lleva al ajuste de «permitir instalar aplicaciones desconocidas».
  static const ajusteDelPermiso = 'ajusteDelPermiso';

  // ── Lo que contesta `instalar`.

  /// El instalador de Android está delante. Lo que pase ya no es nuestro.
  static const abierto = 'abierto';

  /// Falta el ajuste por aplicación.
  static const sinPermiso = 'sinPermiso';

  /// El fichero no está donde se dijo, o no es de esta aplicación.
  static const noEstaElFichero = 'noEstaElFichero';

  /// No se pudo ofrecer el fichero al instalador, o no había quien lo abriera.
  /// Es el caso de un `FileProvider` que no cubre esa carpeta.
  static const noSeCompartio = 'noSeCompartio';
}

/// CÓMO FUE PEDIR LA INSTALACIÓN. Sellado: quien lo mire trata los cuatro casos,
/// que es lo que impide que «no hay permiso» se pinte como «ya está instalando».
sealed class ComoFueInstalar {
  const ComoFueInstalar();
}

/// Android está enseñando su pantalla de «¿instalar?».
class ElInstaladorEstaDelante extends ComoFueInstalar {
  const ElInstaladorEstaDelante();
}

/// Falta el ajuste de «permitir instalar aplicaciones desconocidas».
class FaltaElPermisoDeInstalar extends ComoFueInstalar {
  const FaltaElPermisoDeInstalar();
}

/// Aquí no se instala nada: la web, y el escritorio, donde una actualización es
/// otra cosa (un `.zip` o un `.tar.gz` que se descomprime a mano).
class AquiNoSeInstala extends ComoFueInstalar {
  const AquiNoSeInstala();
}

/// Se intentó y no salió. [motivo] es literal, para la pantalla.
class NoSePudoInstalar extends ComoFueInstalar {
  const NoSePudoInstalar(this.motivo);

  final String motivo;
}

/// EL PUERTO. Es un puerto y no una llamada al canal a pelo para poder probar los
/// tres caminos que no son el feliz **sin un teléfono delante**: sin permiso, con
/// el fichero que no está, y en un destino donde esto no existe.
abstract interface class Instalador {
  /// ¿Está dado el ajuste por aplicación? En Android 7 y anteriores no existe ese
  /// ajuste por aplicación y contesta `true`.
  Future<bool> sePuedeInstalarDesdeAqui();

  /// Abre la pantalla del sistema para instalar [ruta].
  Future<ComoFueInstalar> instalar(String ruta);

  /// Lleva a la persona al ajuste del permiso. No lo concede: lo concede ella.
  Future<void> abrirElAjusteDelPermiso();
}

/// EL DE ANDROID, por el canal.
class InstaladorDeAndroid implements Instalador {
  const InstaladorDeAndroid([
    this._canal = const MethodChannel(CanalDelInstalador.nombre),
  ]);

  final MethodChannel _canal;

  @override
  Future<bool> sePuedeInstalarDesdeAqui() async {
    try {
      return await _canal.invokeMethod<bool>(CanalDelInstalador.sePuede) ??
          false;
    } on Object catch (e) {
      // Que no se pueda preguntar no es que no se pueda instalar, pero tampoco se
      // puede dar por bueno: se contesta `false`, que es lo que lleva a ofrecer
      // el ajuste y el navegador. Lo contrario sería intentar instalar y dejar a
      // alguien mirando una pantalla que no llega.
      Registro.aviso('no se pudo preguntar por el permiso de instalar: $e');
      return false;
    }
  }

  @override
  Future<ComoFueInstalar> instalar(String ruta) async {
    final String? codigo;
    try {
      codigo = await _canal.invokeMethod<String>(CanalDelInstalador.instalar, {
        'ruta': ruta,
      });
    } on PlatformException catch (e) {
      Registro.fallo('el instalador de Android no arrancó', e);
      return NoSePudoInstalar(
        'Android no pudo abrir el instalador (${e.code}). El fichero está '
        'descargado: prueba otra vez, o ábrelo en el navegador.',
      );
    } on Object catch (e) {
      Registro.fallo('el instalador de Android no arrancó', e);
      return const NoSePudoInstalar(
        'Android no pudo abrir el instalador. El fichero está descargado: '
        'prueba otra vez, o ábrelo en el navegador.',
      );
    }
    return switch (codigo) {
      CanalDelInstalador.abierto => const ElInstaladorEstaDelante(),
      CanalDelInstalador.sinPermiso => const FaltaElPermisoDeInstalar(),
      CanalDelInstalador.noEstaElFichero => const NoSePudoInstalar(
        'El fichero descargado ya no está en el aparato. Hay que volver a '
        'descargarlo: toca «Empezar de nuevo».',
      ),
      CanalDelInstalador.noSeCompartio => const NoSePudoInstalar(
        'Este Android no dejó abrir el instalador con el fichero descargado. '
        'Ábrelo en el navegador, que sigue funcionando, y avisa a la oficina.',
      ),
      // Un código que esta versión no conoce NO se da por bueno: darlo por
      // «abierto» dejaría a alguien esperando una pantalla que no va a salir.
      _ => NoSePudoInstalar(
        'Android contestó algo que esta versión no entiende («$codigo»). El '
        'fichero está descargado: ábrelo en el navegador.',
      ),
    };
  }

  @override
  Future<void> abrirElAjusteDelPermiso() async {
    try {
      await _canal.invokeMethod<void>(CanalDelInstalador.ajusteDelPermiso);
    } on Object catch (e) {
      Registro.aviso('no se pudo abrir el ajuste del permiso: $e');
    }
  }
}

/// EL DE LOS DEMÁS DESTINOS: ninguno.
///
/// En la web no hay nada que instalar (`CLAUDE.md` §1) y en el escritorio una
/// actualización es un `.zip` o un `.tar.gz` que se descomprime a mano, no un
/// paquete que el sistema instale solo. Los dos se quedan con el navegador, que
/// es lo que ya funcionaba.
class AquiNoSeInstalaNada implements Instalador {
  const AquiNoSeInstalaNada();

  @override
  Future<bool> sePuedeInstalarDesdeAqui() async => false;

  @override
  Future<ComoFueInstalar> instalar(String ruta) async =>
      const AquiNoSeInstala();

  @override
  Future<void> abrirElAjusteDelPermiso() async {}
}

/// El instalador de ESTE aparato.
///
/// Se decide con [Plataforma.deEsteAparato] y no con `Platform.isAndroid`, por lo
/// mismo que está escrito allí: en la web `defaultTargetPlatform` devuelve el
/// sistema del navegador —`android` en un teléfono— y sin eso la web abierta en
/// un móvil se creería una APK.
final instaladorProvider = Provider<Instalador>((ref) {
  if (Plataforma.deEsteAparato() == Plataforma.android) {
    return const InstaladorDeAndroid();
  }
  return const AquiNoSeInstalaNada();
});
