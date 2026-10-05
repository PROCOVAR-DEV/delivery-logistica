// LA ACTUALIZACIÓN SE BAJA Y SE INSTALA DENTRO DE LA APLICACIÓN — 05/10/2026
//
// Jose, con la 1.0.22 en el teléfono:
//
// > «el mapa sí me funciona dentro de la aplicación, pero la APK me manda a
// >  descargarla al navegador en vez de actualizar ahí mismo en la aplicación sin
// >  necesidad de salir»
//
// Y era una incoherencia nuestra: el mapa de Cuba se baja aquí dentro, con su
// barra, reanudable y comprobado por `sha256`, y la actualización —que pesa el
// triple— te echaba al navegador. **Lo raro era la actualización, no el mapa.**
//
// ## Lo que se perdía al salir al navegador, y por qué importa esta semana
//
// Esta semana empieza a usar esto el logístico de Santiago, con la conexión de
// allá. Medido contra producción el 05/10/2026, sobre el APK colgado en MinIO:
//
//     Petición completa:   HTTP 200 · SIN content-length · sin accept-ranges
//     Pidiendo un trozo:   HTTP 206 · content-range: bytes 0-1023/78485416
//
// O sea: **los rangos funcionan**, pero la respuesta completa no los ofrece, así
// que el gestor de descargas de Android ni lo intenta — y tampoco sabe cuánto
// pesa, porque el `Content-Length` lo quita Cloudflare. Resultado: una barra que
// no sabe cuánto queda, sin reanudar, y un fichero que hay que ir a buscar a
// Descargas. **Una descarga de 75 MB que no se puede reanudar es una descarga que
// no termina.**
//
// Bajándola desde aquí eso deja de importar: se pide por trozos y punto. El
// tamaño sale de lo que anuncia la api (`FicheroPublicado.bytes`, que ya viajaba
// y no lo usaba nadie) y la huella también (`FicheroPublicado.sha256`, lo mismo).
//
// ## Las cuatro reglas de aquí
//
//  1. **El motor es el del mapa**, no otro
//     (`nucleo/descarga/descarga_reanudable.dart`). Dos descargadores que se
//     separan es el fallo clásico de esta casa.
//  2. **Un fichero a medias NO se instala.** Si la huella no cuadra, se dice y se
//     empieza de nuevo. No es celo: un APK cortado «se baja bien» y no instala, y
//     lo que ve la persona es «no se pudo instalar la aplicación», que no explica
//     nada.
//  3. **El navegador sigue estando**, y es la salida cuando no hay permiso,
//     cuando el aparato no lo soporta o cuando la descarga falla tres veces.
//     Quitar la única forma que funciona hoy sería cambiar un problema por otro.
//  4. **No se fuerza nada** (`docs/actualizaciones.md` §1.2). Esto no baja solo:
//     lo arranca un toque.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../descarga/almacen_de_bajadas.dart';
import '../descarga/carpeta_en_disco.dart';
import '../descarga/descarga_reanudable.dart';
import '../descarga/en_megas.dart';
import '../registro/registro.dart';
import 'instalador.dart';
import 'version_publicada.dart';

/// Los tres nombres que hay dentro de la carpeta `actualizacion/`:
///
///	reparto.apk           el fichero bueno, comprobado por sha256
///	reparto.apk.parcial   lo que se lleva bajado y todavía no vale
///	reparto.json          de qué versión es eso: versión, compilación, bytes, huella
///
/// **El apunte no es adorno.** Sin él, un `.parcial` de la 1.0.22 se reanudaría
/// con el `Range` de la 1.0.23: los bytes cuadrarían al final —el tamaño lo dice
/// el anuncio— y lo cazaría el `sha256` **después de haber gastado la descarga
/// entera**, que en la conexión de allá es la tarde. Con el apunte se tira el
/// parcial ajeno ANTES de pedir un solo byte.
abstract final class FicherosDeLaActualizacion {
  static const carpeta = 'actualizacion';
  static const apk = 'reparto.apk';
  static const apunte = 'reparto.json';
}

/// CUÁNTOS FALLOS SEGUIDOS antes de ofrecer el navegador.
///
/// Tres, y no uno: en la conexión de allá un corte es lo normal y lo que hay que
/// hacer es seguir donde iba, no cambiar de camino. Y no diez: si tres intentos
/// seguidos no pasan de ahí, lo que falla no es la señal de este minuto.
const fallosAntesDeOfrecerElNavegador = 3;

/// LAS PALABRAS DE ESTA DESCARGA.
///
/// Cada una dice **qué pasó y qué hacer**. «Se cortó la conexión, toca para
/// seguir desde donde iba» le sirve a alguien; «error al descargar» no le dice
/// nada (`CLAUDE.md` §4).
class PalabrasDeLaActualizacion extends PalabrasDeLaDescarga {
  const PalabrasDeLaActualizacion();

  @override
  String noSePudoConectar(String motivo) =>
      'No se pudo conectar para bajar la actualización: $motivo. Lo bajado se '
      'guarda: toca «Seguir descargando» cuando haya señal y continúa desde '
      'donde iba.';

  @override
  String elServidorContesto(int codigo) =>
      'El servidor contestó $codigo al pedir la actualización. Es un problema '
      'del servidor, no de la señal: avisa a la oficina.';

  @override
  String noContinuoDondeSePidio(String? rango, int desde) =>
      'El servidor no continuó donde se le pidió (mandó «$rango» y se le pidió '
      'desde $desde). Se ha descartado lo bajado; al volver a intentarlo '
      'empieza de cero.';

  @override
  String seCortoLaConexion() =>
      'Se cortó la conexión bajando la actualización. Lo bajado se guarda: toca '
      '«Seguir descargando» para continuar desde donde iba.';

  @override
  String detenida() =>
      'Descarga detenida. Lo bajado se guarda: toca «Seguir descargando» para '
      'continuar desde donde iba.';

  @override
  String llegoCortada(int bajados, int total) =>
      'La descarga se cortó: llegaron ${enMegas(bajados)} de los '
      '${enMegas(total)} de la actualización. Lo bajado se guarda: toca '
      '«Seguir descargando» para continuar desde donde iba.';

  @override
  String laHuellaNoCuadra() =>
      'La actualización llegó completa pero no es la que el servidor dice tener '
      '(la huella no cuadra). No se instala a medias: un fichero así se baja '
      'bien y después no instala, y entonces nadie sabe por qué. Se ha borrado '
      'lo bajado: hay que empezar de nuevo. Si vuelve a pasar, avisa a la '
      'oficina.';
}

/// EL APUNTE: de qué versión es lo que hay en la carpeta.
class ApunteDeLaBajada {
  const ApunteDeLaBajada({
    required this.version,
    required this.sha256,
    required this.bytes,
  });

  final String version;
  final String sha256;
  final int bytes;

  String aJson() =>
      jsonEncode({'version': version, 'sha256': sha256, 'bytes': bytes});

  static ApunteDeLaBajada? deJson(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    try {
      final m = jsonDecode(texto);
      if (m is! Map) return null;
      final version = m['version'];
      final sha = m['sha256'];
      final bytes = m['bytes'];
      if (version is! String || sha is! String || bytes is! num) return null;
      return ApunteDeLaBajada(
        version: version,
        sha256: sha,
        bytes: bytes.toInt(),
      );
    } on Object {
      return null;
    }
  }
}

/// CÓMO VA LA ACTUALIZACIÓN. Sellado: la pantalla trata los siete casos, y que el
/// compilador lo exija es lo que impide que «falta el permiso» se pinte como «ya
/// está instalando».
sealed class ComoVaLaActualizacion {
  const ComoVaLaActualizacion();
}

/// Nadie ha tocado nada todavía. No se enseña ninguna barra.
class SinEmpezar extends ComoVaLaActualizacion {
  const SinEmpezar();
}

/// BAJANDO, con el número de verdad. [total] sale del anuncio de la api, nunca
/// del `Content-Length` — que es justo el que no llega.
class BajandoLaActualizacion extends ComoVaLaActualizacion {
  const BajandoLaActualizacion({required this.bajados, required this.total});

  final int bajados;
  final int total;

  /// De 0 a 1. Nunca `null`: aquí el tamaño **se sabe** desde antes de empezar,
  /// así que la barra no tiene por qué fingir.
  double get parte => total <= 0 ? 0 : (bajados / total).clamp(0, 1).toDouble();
}

/// El fichero está en el aparato, con su tamaño y su huella comprobados. Es el
/// único estado desde el que se instala.
class BajadaComprobada extends ComoVaLaActualizacion {
  const BajadaComprobada({required this.ruta, required this.bytes});

  final String ruta;
  final int bytes;
}

/// Android está enseñando su pantalla de «¿instalar?». Lo que pase ya no es
/// nuestro.
///
/// **Lleva el fichero igual que los demás, y no es de adorno.** Si alguien cierra
/// esa pantalla del sistema sin instalar —se cancela sin querer, o está
/// conduciendo— el único camino de vuelta es volver a pulsar «Instalar», y sin la
/// ruta aquí ese botón no haría NADA: se queda puesto, se pulsa, y no pasa nada.
/// Un botón muerto es peor que no tener botón.
class ElInstaladorEstaEnPantalla extends ComoVaLaActualizacion {
  const ElInstaladorEstaEnPantalla({required this.ruta, required this.bytes});

  final String ruta;
  final int bytes;
}

/// LA DESCARGA FALLÓ, con su motivo literal y con lo que se conserva.
class FalloLaBajada extends ComoVaLaActualizacion {
  const FalloLaBajada({
    required this.motivo,
    required this.bajados,
    required this.total,
    required this.sePuedeReanudar,
    required this.fallosSeguidos,
  });

  final String motivo;
  final int bajados;
  final int total;

  /// `true` cuando lo bajado sigue sirviendo. El botón dice «Seguir
  /// descargando»; con `false` dice «Empezar de nuevo», porque prometer que
  /// continúa cuando no continúa es peor que no prometer nada.
  final bool sePuedeReanudar;

  final int fallosSeguidos;

  /// Tras tres fallos seguidos se ofrece el navegador. No antes: en la conexión
  /// de allá un corte es lo normal y lo que hay que hacer es seguir.
  bool get seOfreceElNavegador =>
      fallosSeguidos >= fallosAntesDeOfrecerElNavegador;
}

/// Está bajada y comprobada, pero **falta el ajuste del sistema** para que esta
/// aplicación pueda instalar. Es el estado normal la primera vez, en todos los
/// teléfonos.
class FaltaElPermisoParaInstalar extends ComoVaLaActualizacion {
  const FaltaElPermisoParaInstalar({required this.ruta, required this.bytes});

  final String ruta;
  final int bytes;
}

/// Se pidió instalar y no salió. El fichero sigue bajado: no hay que volver a
/// gastarse los 75 MB.
class NoSePudoInstalarla extends ComoVaLaActualizacion {
  const NoSePudoInstalarla({
    required this.motivo,
    required this.ruta,
    required this.bytes,
  });

  final String motivo;
  final String ruta;
  final int bytes;
}

// ─────────────────────────────────────────────────────────────── el cableado

/// LA CARPETA donde vive el APK bajado. `null` donde no se baja nada: la web, y
/// cualquier destino que no sea Android.
///
/// En el escritorio **no** se baja aquí dentro a propósito: una actualización de
/// escritorio es un `.zip` o un `.tar.gz` que alguien descomprime encima, no un
/// paquete que el sistema instale, así que bajarlo dentro no le ahorraría a nadie
/// el paso de ir a buscarlo. Se queda con el navegador, que es lo que ya
/// funcionaba.
final carpetaDeLaActualizacionProvider = FutureProvider<AlmacenDeBajadas?>((
  ref,
) async {
  if (Plataforma.deEsteAparato() != Plataforma.android) return null;
  return abrirLaCarpetaDeBajadas(FicherosDeLaActualizacion.carpeta);
});

/// El cliente con el que se baja el APK.
///
/// **Es uno propio y no el de las pantallas**, por las mismas dos razones que el
/// del mapa (`mapa/proveedores_de_mapa.dart`): el de las pantallas reintenta a
/// 1 s, 4 s, 15 s y 60 s —aquí sería esperar ochenta segundos antes de enterarse
/// de que no hay señal— y además **éste no lleva la sesión**: el APK es público y
/// mandarle el token a un servidor de estáticos es regalar un token.
final dioDeLaActualizacionProvider = Provider<Dio>((ref) {
  final cliente = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      // Sin plazo de recepción: son 75 MB por una conexión que va y viene.
      receiveTimeout: null,
    ),
  );
  ref.onDispose(cliente.close);
  return cliente;
});

/// CÓMO VA, para quien lo pinte.
///
/// Es un `Notifier` y no un `Future` porque esto cambia con la pantalla delante
/// —cada por ciento de la descarga— y lo que se pinta y puede cambiar va por
/// stream (`CLAUDE.md` §3-ter). Y vive en un proveedor y no en el `State` del
/// cajón por una razón concreta: **el cajón se cierra**. Quien cierra el cajón a
/// mitad de descarga no está cancelándola, y si el estado viviera ahí se iría con
/// él.
final bajadaDeLaActualizacionProvider =
    NotifierProvider<BajadaDeLaActualizacion, ComoVaLaActualizacion>(
      BajadaDeLaActualizacion.new,
    );

/// QUIEN BAJA E INSTALA.
class BajadaDeLaActualizacion extends Notifier<ComoVaLaActualizacion> {
  CancelToken? _cancelar;
  bool _enMarcha = false;
  bool _vivo = false;
  int _fallosSeguidos = 0;

  /// El último por ciento que se contó, para no publicar un estado por cada trozo
  /// de 8 kB: son miles de repintados para mover una barra que no se mueve.
  int _ultimoPorciento = -1;

  @override
  ComoVaLaActualizacion build() {
    _vivo = true;
    ref.onDispose(() {
      _vivo = false;
      _cancelar?.cancel();
    });
    return const SinEmpezar();
  }

  /// EMPIEZA O SIGUE la descarga de [fichero] desde [enlace].
  ///
  /// Dos toques no son dos descargas: si ya está en marcha, no hace nada. La
  /// guarda va aquí **y además** en el botón (`aviso_de_version_nueva.dart`),
  /// porque son dos cosas distintas: el botón apagado dice que ya se pulsó, y
  /// esto es lo que impide la segunda bajada.
  Future<void> bajar({
    required String enlace,
    required FicheroPublicado fichero,
    required String version,
  }) async {
    if (_enMarcha) return;
    _enMarcha = true;
    try {
      final carpeta = await ref.read(carpetaDeLaActualizacionProvider.future);
      if (carpeta == null) {
        // No debería llegarse aquí: la pantalla sólo ofrece esto en Android. Si
        // pasa, se dice en vez de dejar una barra que no avanza nunca.
        _poner(
          FalloLaBajada(
            motivo:
                'Este aparato no se actualiza desde dentro de la aplicación. '
                'Ábrelo en el navegador.',
            bajados: 0,
            total: fichero.bytes,
            sePuedeReanudar: false,
            fallosSeguidos: fallosAntesDeOfrecerElNavegador,
          ),
        );
        return;
      }

      await _tirarLoQueEsDeOtraVersion(carpeta, fichero, version);

      // YA ESTABA BAJADA. Pasa más de lo que parece: se baja, Android enseña su
      // pantalla, la persona la cancela porque está conduciendo, y vuelve por la
      // tarde. Volver a gastarse 75 MB ahí sería imperdonable.
      final yaHay = await carpeta.bytes(FicherosDeLaActualizacion.apk);
      if (yaHay == fichero.bytes) {
        await _listaParaInstalar(carpeta, fichero);
        return;
      }

      _ultimoPorciento = -1;
      _poner(BajandoLaActualizacion(bajados: 0, total: fichero.bytes));
      final cancelar = _cancelar = CancelToken();

      final motor = DescargaReanudable(
        ref.read(dioDeLaActualizacionProvider),
        carpeta,
        const PalabrasDeLaActualizacion(),
      );
      final fin = await motor.bajar(
        LoQueSeBaja(
          url: enlace,
          bytes: fichero.bytes,
          sha256: fichero.sha256,
          fichero: FicherosDeLaActualizacion.apk,
        ),
        cancelar: cancelar,
        comoVa: _contar,
      );
      _cancelar = null;

      switch (fin) {
        case BajadaCompleta():
          _fallosSeguidos = 0;
          await _listaParaInstalar(carpeta, fichero);
        case BajadaCortada(
          :final motivo,
          :final bajados,
          :final total,
          :final sePuedeReanudar,
        ):
          _fallosSeguidos++;
          _poner(
            FalloLaBajada(
              motivo: motivo,
              bajados: bajados,
              total: total,
              sePuedeReanudar: sePuedeReanudar,
              fallosSeguidos: _fallosSeguidos,
            ),
          );
      }
    } finally {
      _enMarcha = false;
    }
  }

  /// DETENER no es tirar lo bajado: el `.parcial` se queda donde está y el
  /// siguiente toque continúa desde ahí.
  void detener() => _cancelar?.cancel();

  /// PEDIRLE A ANDROID QUE INSTALE lo que ya está comprobado.
  ///
  /// Sólo se instala desde un estado que lleva **un fichero ya comprobado**:
  /// [BajadaComprobada], [FaltaElPermisoParaInstalar], [NoSePudoInstalarla] y
  /// [ElInstaladorEstaEnPantalla]. Desde los demás no se intenta — instalar un
  /// `.parcial` es justo lo que no puede pasar.
  Future<void> instalar() async {
    final (ruta, bytes) = switch (state) {
      BajadaComprobada(:final ruta, :final bytes) => (ruta, bytes),
      FaltaElPermisoParaInstalar(:final ruta, :final bytes) => (ruta, bytes),
      NoSePudoInstalarla(:final ruta, :final bytes) => (ruta, bytes),
      // Y desde aquí también: es el que vuelve después de cerrar la pantalla de
      // Android sin instalar.
      ElInstaladorEstaEnPantalla(:final ruta, :final bytes) => (ruta, bytes),
      // Desde cualquier otro estado no hay nada comprobado que instalar, y no se
      // intenta: el caso que esto impide es instalar un `.parcial`.
      _ => (null, 0),
    };
    if (ruta == null) return;

    final instalador = ref.read(instaladorProvider);
    final como = await instalador.instalar(ruta);
    switch (como) {
      case ElInstaladorEstaDelante():
        _poner(ElInstaladorEstaEnPantalla(ruta: ruta, bytes: bytes));
      case FaltaElPermisoDeInstalar():
        _poner(FaltaElPermisoParaInstalar(ruta: ruta, bytes: bytes));
      case AquiNoSeInstala():
        _poner(
          NoSePudoInstalarla(
            motivo:
                'Este aparato no instala paquetes desde la aplicación. El '
                'fichero está descargado; ábrelo en el navegador.',
            ruta: ruta,
            bytes: bytes,
          ),
        );
      case NoSePudoInstalar(:final motivo):
        _poner(NoSePudoInstalarla(motivo: motivo, ruta: ruta, bytes: bytes));
    }
  }

  /// Lleva al ajuste del sistema. **No concede nada**: lo concede la persona, y
  /// al volver tiene que pulsar «Instalar» otra vez — que es lo que Android
  /// permite, y fingir lo contrario sería dejar a alguien esperando.
  Future<void> pedirElPermiso() =>
      ref.read(instaladorProvider).abrirElAjusteDelPermiso();

  /// Borra lo que haya quedado de OTRA versión antes de pedir un solo byte.
  Future<void> _tirarLoQueEsDeOtraVersion(
    AlmacenDeBajadas carpeta,
    FicheroPublicado fichero,
    String version,
  ) async {
    final apunte = ApunteDeLaBajada.deJson(
      await carpeta.leerTexto(FicherosDeLaActualizacion.apunte),
    );
    if (apunte != null && apunte.sha256 == fichero.sha256) return;

    if (apunte != null) {
      Registro.aviso(
        'en la carpeta hay la ${apunte.version} (${apunte.bytes} bytes) y se '
        'pidió la $version: se tira para no reanudar encima de otra versión',
      );
    }
    await carpeta.borrar('${FicherosDeLaActualizacion.apk}.parcial');
    await carpeta.borrar(FicherosDeLaActualizacion.apk);
    await carpeta.escribirTexto(
      FicherosDeLaActualizacion.apunte,
      ApunteDeLaBajada(
        version: version,
        sha256: fichero.sha256,
        bytes: fichero.bytes,
      ).aJson(),
    );
  }

  /// Comprobada y en el disco: queda ver si se puede instalar desde aquí.
  ///
  /// **El permiso se mira ANTES de ofrecer «Instalar»**, no después de pulsarlo:
  /// la primera vez no está dado en ningún teléfono, y un botón que lleva a una
  /// pantalla que no sale enseña a no fiarse del botón.
  Future<void> _listaParaInstalar(
    AlmacenDeBajadas carpeta,
    FicheroPublicado fichero,
  ) async {
    final ruta = carpeta.rutaEnDisco(FicherosDeLaActualizacion.apk);
    if (ruta == null) {
      _poner(
        NoSePudoInstalarla(
          motivo:
              'La actualización se bajó pero este aparato no sabe dónde '
              'dejarla para instalarla. Ábrela en el navegador.',
          ruta: '',
          bytes: fichero.bytes,
        ),
      );
      return;
    }
    final sePuede = await ref
        .read(instaladorProvider)
        .sePuedeInstalarDesdeAqui();
    _poner(
      sePuede
          ? BajadaComprobada(ruta: ruta, bytes: fichero.bytes)
          : FaltaElPermisoParaInstalar(ruta: ruta, bytes: fichero.bytes),
    );
  }

  /// UN ESTADO POR CADA POR CIENTO, no uno por trozo.
  void _contar({required int bajados, required int total}) {
    if (!_vivo) return;
    final porciento = total <= 0 ? 100 : (bajados * 100) ~/ total;
    if (porciento == _ultimoPorciento && bajados != total) return;
    _ultimoPorciento = porciento;
    state = BajandoLaActualizacion(bajados: bajados, total: total);
  }

  /// Poner estado con el aparato ya desmontado revienta Riverpod, y esto corre
  /// después de `await`: la aplicación se puede haber cerrado mientras bajaba.
  void _poner(ComoVaLaActualizacion nuevo) {
    if (!_vivo) return;
    state = nuevo;
  }
}
