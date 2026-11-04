// EL MAPA DE CUBA VIENE DENTRO DEL APK del distribuidor (assets NATIVOS de Android,
// `herramientas/distribuidor-assets/`) y en el primer arranque se COPIA a la carpeta
// del mapa de la app, SIN RED y SIN cargar 97 MB en memoria:
//
//  * el copiador (Kotlin, `context.assets.open`) lo pasa por trozos al fichero
//    `cuba-detallado.pmtiles.parcial`; si se mata la app a medias, la proxima vez
//    sigue por donde iba;
//  * al acabar se comprueba el `sha256` contra el `cuba-detallado.json` del APK, y SOLO
//    entonces se renombra a `cuba-detallado.pmtiles` y se escribe el `.json` con el mismo
//    formato que deja la descarga. Con un `sha256` malo no queda NADA bueno a medias;
//  * desde ahi el codigo de siempre (`proveedores_de_mapa`, el lector PMTiles) lo ve
//    como «descargado»;
//  * si ya esta instalado y es la misma version, no hace nada; si el APK trae otra
//    version, reemplaza la vieja (la vieja sigue valiendo hasta el renombrado).
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../mapa/anuncio_de_mapa.dart' show PaqueteGuardado;
import '../../nucleo/descarga/almacen_de_bajadas.dart';
import '../../nucleo/reloj.dart';

const nivelDelMapaIncluido = 'detallado';
const ficheroDelMapa = 'cuba-$nivelDelMapaIncluido.pmtiles';
const apunteDelMapa = 'cuba-$nivelDelMapaIncluido.json';
const parcialDelMapa = '$ficheroDelMapa.parcial';
const huellaDelParcial = '$parcialDelMapa.sha256';

/// Lo unico que hace falta del lado nativo.
abstract interface class CopiadorDeAsset {
  /// El texto de un asset pequeno (el `.json`), o `null` si el APK no lo trae.
  Future<String?> leerTexto(String asset);

  /// Copia [asset] al fichero [destino] A PARTIR DEL BYTE [desde] del asset (anade al
  /// final del destino, que ya tiene [desde] bytes). Avisa del progreso.
  Future<void> copiar({
    required String asset,
    required String destino,
    required int desde,
    required void Function(int copiados) alAvanzar,
  });
}

class MapaIncluidoFallo implements Exception {
  const MapaIncluidoFallo(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

enum ResultadoDeLaInstalacion { instalado, yaEstaba }

class InstaladorDelMapa {
  InstaladorDelMapa(
    this._carpeta,
    this._copiador, {
    Reloj reloj = relojDelAparato,
  }) : _reloj = reloj;

  final AlmacenDeBajadas _carpeta;
  final CopiadorDeAsset _copiador;
  final Reloj _reloj;

  /// [alAvanzar] recibe (copiados, total) en bytes.
  Future<ResultadoDeLaInstalacion> instalar({
    void Function(int copiados, int total)? alAvanzar,
  }) async {
    final traido = _manifiesto(await _copiador.leerTexto(apunteDelMapa));
    if (traido == null) {
      throw const MapaIncluidoFallo(
        'Esta aplicación no trae el mapa de Cuba. Instala la versión completa.',
      );
    }

    final puesto = PaqueteGuardado.deJson(
      await _carpeta.leerTexto(apunteDelMapa),
    );
    if (puesto != null &&
        puesto.sha256 == traido.sha256 &&
        puesto.version == traido.version &&
        await _carpeta.bytes(ficheroDelMapa) == traido.bytes) {
      return ResultadoDeLaInstalacion.yaEstaba;
    }

    // Un parcial de OTRA version (o sin huella) no sirve para seguir: se tira.
    var copiado = await _carpeta.bytes(parcialDelMapa);
    if (copiado > 0 &&
        (copiado > traido.bytes ||
            await _carpeta.leerTexto(huellaDelParcial) != traido.sha256)) {
      await _carpeta.borrar(parcialDelMapa);
      copiado = 0;
    }
    await _carpeta.escribirTexto(huellaDelParcial, traido.sha256);

    if (copiado < traido.bytes) {
      await _copiador.copiar(
        asset: ficheroDelMapa,
        destino: _carpeta.rutaEnDisco(parcialDelMapa)!,
        desde: copiado,
        alAvanzar: (n) => alAvanzar?.call(copiado + n, traido.bytes),
      );
    }

    if (await _carpeta.bytes(parcialDelMapa) != traido.bytes ||
        await _huellaDe(parcialDelMapa) != traido.sha256) {
      await _carpeta.borrar(parcialDelMapa);
      await _carpeta.borrar(huellaDelParcial);
      throw const MapaIncluidoFallo(
        'El mapa que trae la aplicación llegó dañado (la huella no cuadra). '
        'Se ha descartado la copia; vuelve a intentarlo y, si se repite, '
        'reinstala la aplicación.',
      );
    }

    await _carpeta.renombrar(parcialDelMapa, ficheroDelMapa);
    await _carpeta.borrar(huellaDelParcial);
    await _carpeta.escribirTexto(
      apunteDelMapa,
      jsonEncode(
        PaqueteGuardado(
          nivel: traido.nivel,
          version: traido.version,
          bytes: traido.bytes,
          sha256: traido.sha256,
          guardadoAt: _reloj(),
        ).aJson(),
      ),
    );
    return ResultadoDeLaInstalacion.instalado;
  }

  /// El `.json` del APK ({nivel, version, bytes, sha256}, sin `guardadoAt`).
  PaqueteGuardado? _manifiesto(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    try {
      final m = jsonDecode(texto) as Map<String, Object?>;
      return PaqueteGuardado(
        nivel: m['nivel']! as String,
        version: '${m['version']!}',
        bytes: (m['bytes']! as num).toInt(),
        sha256: m['sha256']! as String,
        guardadoAt: _reloj(),
      );
    } on Object {
      return null;
    }
  }

  /// El `sha256` POR TROZOS (97 MB no caben en una lectura).
  Future<String> _huellaDe(String nombre) async {
    final salida = _Huella();
    final entrada = sha256.startChunkedConversion(salida);
    await for (final trozo in _carpeta.porTrozos(nombre)) {
      entrada.add(trozo);
    }
    entrada.close();
    return salida.huella?.toString() ?? '';
  }
}

class _Huella implements Sink<Digest> {
  Digest? huella;

  @override
  void add(Digest data) => huella = data;

  @override
  void close() {}
}
