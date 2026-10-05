import 'almacen_de_bajadas.dart';

/// EN LA WEB NO HAY CARPETA. Regla 1 (`CLAUDE.md` §1): quien abre un navegador
/// tiene servidor detras, siempre, asi que no hay nada que guardarse — ni el mapa
/// de Cuba, ni un instalador que ahi no se podria instalar.
///
/// Se lanza en vez de devolver una carpeta vacia para que, si esto llega a
/// llamarse en web, se vea y se arregle donde toca — en vez de dejar una pantalla
/// de descargas que no descarga nunca y no dice por que.
Future<AlmacenDeBajadas> abrirLaCarpetaDeBajadas(String nombre) =>
    throw UnsupportedError(
      'bajarse ficheros al aparato es de la APK y del escritorio; en la web no '
      'hay carpeta donde ponerlos («$nombre»)',
    );
