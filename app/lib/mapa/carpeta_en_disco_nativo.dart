import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../nucleo/descarga/carpeta_en_disco_nativo.dart';
import 'carpeta_del_mapa.dart';
import 'pmtiles.dart';

/// Android, Windows y Linux: una carpeta `mapa/` dentro de los datos de la
/// aplicacion.
///
/// POR QUE AHI Y NO EN LA TARJETA O EN DESCARGAS: es la carpeta que el sistema
/// borra al desinstalar y que ninguna otra aplicacion toca. Un `.pmtiles` de 26
/// MB suelto en Descargas se lo lleva por delante cualquier limpiador de los que
/// vienen instalados en los telefonos de alla, y el mapa desaparece sin que
/// nadie sepa por que.
class CarpetaEnDisco extends CarpetaDeBajadasEnDisco implements CarpetaDelMapa {
  CarpetaEnDisco(super.raiz);

  /// LO UNICO QUE EL MAPA AÑADE: leer teselas sueltas sin cargar el fichero.
  ///
  /// Todo lo demas —añadir al final, renombrar, el texto del apunte, los trozos
  /// para el `sha256`— lo hace [CarpetaDeBajadasEnDisco], que es la misma pieza
  /// que usa la actualizacion de la APK desde el 05/10/2026.
  @override
  Future<LeerPorRangos> porRangos(String nombre) async =>
      _RangosDeFichero(await ficheroDe(nombre).open());
}

class _RangosDeFichero implements LeerPorRangos {
  _RangosDeFichero(this._f);

  final RandomAccessFile _f;

  /// UNA LECTURA CADA VEZ, Y AQUI ESTA LA RAZON.
  ///
  /// Un `RandomAccessFile` tiene **una sola posicion**, y leer un rango son dos
  /// pasos con un `await` en medio: colocarse y leer. Si dos lecturas se
  /// solapan, la segunda mueve la posicion mientras la primera esta esperando, y
  /// la primera lee desde donde no es. No falla: **devuelve otros bytes**, que
  /// es peor.
  ///
  /// Y se solapan siempre, no de vez en cuando: el mapa pide TODAS las teselas
  /// de la vista de golpe (`croquis_de_ruta.dart`, `_pedirLasMejoras`: un bucle
  /// con `.then` y sin `await`), y desde el 21/09/2026 el enrutador por calles
  /// lee el mismo fichero al mismo tiempo para armar su grafo.
  ///
  /// Lo que se veia en el telefono de Jose, con el mapa de Cuba bajado y el
  /// avion puesto: **una sola tesela dibujada arriba a la izquierda y el resto
  /// del recuadro en blanco**. La que ganaba la carrera salia; las demas leian
  /// bytes de otro sitio, no decodificaban y se quedaban en nada. «No todo el
  /// mapa como deberia de ser».
  ///
  /// No se ve en ninguna prueba de las de siempre porque en las pruebas y en la
  /// web el paquete se lee de memoria (`RangosEnMemoria`), donde no hay posicion
  /// que compartir. Es un fallo que solo existe en el aparato.
  Future<void> _turno = Future<void>.value();

  @override
  Future<Uint8List> leer(int desde, int largo) {
    final mio = _turno.then((_) => _leerEnSuTurno(desde, largo));
    // La cola NO puede romperse cuando una lectura falla: si `_turno` se queda
    // en un futuro con error, todas las siguientes fallan tambien y el mapa se
    // queda en blanco para siempre. Por eso se traga el error AQUI —quien pidio
    // la lectura sigue recibiendolo por `mio`—.
    _turno = mio.then((_) {}, onError: (Object _) {});
    return mio;
  }

  Future<Uint8List> _leerEnSuTurno(int desde, int largo) async {
    await _f.setPosition(desde);
    final salida = await _f.read(largo);
    if (salida.length != largo) {
      // Pedir mas alla del final es un fichero corrupto, no un caso normal: se
      // dice, no se devuelve medio trozo.
      throw const PaqueteIlegible(
        'el fichero del mapa se acaba antes de lo que dice su cabecera',
      );
    }
    return salida;
  }

  @override
  Future<void> cerrar() => _f.close();
}

/// Abre —y crea si hace falta— la carpeta del mapa.
Future<CarpetaDelMapa> abrirLaCarpetaDelMapa() async {
  final datos = await getApplicationSupportDirectory();
  final carpeta = Directory('${datos.path}${Platform.pathSeparator}mapa');
  if (!await carpeta.exists()) await carpeta.create(recursive: true);
  return CarpetaEnDisco(carpeta);
}
