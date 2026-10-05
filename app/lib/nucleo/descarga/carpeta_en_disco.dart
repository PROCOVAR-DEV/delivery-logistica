/// La carpeta de verdad, resuelta en tiempo de compilacion.
///
/// Mismo patron que `nucleo/base/conexion/` y que `mapa/carpeta_en_disco.dart`:
/// arriba de esta linea nadie sabe en que destino corre.
library;

export 'carpeta_en_disco_stub.dart'
    if (dart.library.io) 'carpeta_en_disco_nativo.dart';
