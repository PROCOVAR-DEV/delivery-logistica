// DONDE VIVE EL PAQUETE, y cómo se toca.
//
// Es un puerto, no un `File`, por la razón de siempre en esta casa: para poder
// probarlo. **Las pruebas inyectan el fichero, nunca lo bajan** — ni de
// Procovar, ni de OpenStreetMap, ni de Geofabrik.
//
// Y hay una segunda razón que no es de pruebas: `dart:io` no existe en el
// navegador y esta aplicación compila también para web. El paquete de mapa no se
// usa allí (`CLAUDE.md` §1), pero el código tiene que compilar igual en los
// cuatro destinos.
//
// ## Los tres nombres que hay dentro de la carpeta
//
//	cuba-<nivel>.pmtiles           el paquete bueno, comprobado por sha256
//	cuba-<nivel>.pmtiles.parcial   lo que se lleva bajado y todavía no vale
//	cuba-<nivel>.json              qué es lo que hay: versión, bytes y huella
//
// **El parcial se llama distinto a propósito.** Si lo que se está bajando y lo
// que ya vale compartieran nombre, una descarga cortada dejaría el mapa bueno
// pisado a medias: el chofer perdería el mapa que ya tenía por intentar
// actualizarlo, en la conexión de allá, que es donde más se corta. Así, hasta
// que el `sha256` no cuadra, el bueno no se toca.

import 'dart:typed_data';

import '../nucleo/descarga/almacen_de_bajadas.dart';
import 'pmtiles.dart';

/// Lo que hace falta saber hacer con los ficheros del mapa.
///
/// Es [AlmacenDeBajadas] —el puerto que usa el motor de bajar, compartido con la
/// actualizacion de la APK desde el 05/10/2026— **mas una cosa que solo el mapa
/// necesita**: leer teselas sueltas sin cargar el fichero entero.
abstract interface class CarpetaDelMapa implements AlmacenDeBajadas {
  /// Para leer teselas sueltas sin cargar el fichero entero.
  Future<LeerPorRangos> porRangos(String nombre);
}

/// UNA CARPETA EN MEMORIA. Es lo que usan las pruebas, y lo que permite
/// ejercitar la reanudación y el `sha256` **sin una sola petición de red y sin
/// tocar el disco**.
///
/// Todo lo de guardar bytes lo hereda de [AlmacenEnMemoria], que es el mismo que
/// usan las pruebas de la actualización: lo único que añade aquí es la lectura
/// por rangos, que es lo único que el mapa necesita de más.
class CarpetaEnMemoria extends AlmacenEnMemoria implements CarpetaDelMapa {
  @override
  Future<LeerPorRangos> porRangos(String nombre) async =>
      RangosEnMemoria(Uint8List.fromList(bytesCrudos(nombre) ?? const []));
}
