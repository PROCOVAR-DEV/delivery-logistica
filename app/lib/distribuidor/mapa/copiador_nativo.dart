// El copiador de verdad: el canal de plataforma de Kotlin
// (`android/.../MapaIncluido.kt`). Copia por trozos con `context.assets.open`, sin
// cargar el fichero en memoria. Solo existe en Android.
import 'package:flutter/services.dart';

import 'instalador_del_mapa.dart';

class CopiadorNativo implements CopiadorDeAsset {
  CopiadorNativo() {
    _canal.setMethodCallHandler((llamada) async {
      if (llamada.method == 'avance') {
        _alAvanzar?.call(llamada.arguments as int);
      }
    });
  }

  static const _canal = MethodChannel('cloud.procovar.reparto/mapa_incluido');

  void Function(int)? _alAvanzar;

  @override
  Future<String?> leerTexto(String asset) =>
      _canal.invokeMethod<String>('leerTexto', {'asset': asset});

  @override
  Future<void> copiar({
    required String asset,
    required String destino,
    required int desde,
    required void Function(int copiados) alAvanzar,
  }) async {
    _alAvanzar = alAvanzar;
    try {
      await _canal.invokeMethod<void>('copiar', {
        'asset': asset,
        'destino': destino,
        'desde': desde,
      });
    } on PlatformException catch (e) {
      throw MapaIncluidoFallo(
        'No se pudo copiar el mapa de Cuba: ${e.message ?? e.code}. '
        'Comprueba que el teléfono tiene espacio libre (unos 100 MB).',
      );
    } finally {
      _alAvanzar = null;
    }
  }
}
