import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'almacen_de_bajadas.dart';

/// UNA CARPETA DE VERDAD dentro de los datos de la aplicacion.
///
/// POR QUE AHI Y NO EN LA TARJETA O EN DESCARGAS: es la carpeta que el sistema
/// borra al desinstalar y que ninguna otra aplicacion toca. Un fichero de decenas
/// de MB suelto en Descargas se lo lleva por delante cualquier limpiador de los
/// que vienen instalados en los telefonos de alla, y desaparece sin que nadie
/// sepa por que.
///
/// Y para el APK de la actualizacion hay un segundo motivo, que es el que decide:
/// **el instalador de Android tiene que poder leerlo**, y lo unico que se le
/// puede ofrecer sin pedir permisos de almacenamiento es un fichero de los
/// nuestros servido por un `FileProvider` (`android/app/src/main/res/xml/`). La
/// carpeta de Descargas pediria permiso y la tarjeta tambien.
class CarpetaDeBajadasEnDisco implements AlmacenDeBajadas {
  CarpetaDeBajadasEnDisco(this.raiz);

  final Directory raiz;

  /// El fichero de verdad. `protected` de palabra: lo usa esta clase y quien la
  /// extienda para añadirle algo —el mapa le añade la lectura por rangos—.
  File ficheroDe(String nombre) =>
      File('${raiz.path}${Platform.pathSeparator}$nombre');

  @override
  Future<int> bytes(String nombre) async {
    final f = ficheroDe(nombre);
    return await f.exists() ? f.length() : 0;
  }

  @override
  Future<void> anadir(String nombre, List<int> trozo) =>
      ficheroDe(nombre).writeAsBytes(trozo, mode: FileMode.append, flush: false);

  @override
  Future<void> borrar(String nombre) async {
    final f = ficheroDe(nombre);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> renombrar(String de, String a) async {
    await borrar(a);
    await ficheroDe(de).rename(ficheroDe(a).path);
  }

  @override
  Stream<List<int>> porTrozos(String nombre) => ficheroDe(nombre).openRead();

  @override
  Future<void> escribirTexto(String nombre, String texto) =>
      ficheroDe(nombre).writeAsString(texto, flush: true);

  @override
  Future<String?> leerTexto(String nombre) async {
    final f = ficheroDe(nombre);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  String? rutaEnDisco(String nombre) => ficheroDe(nombre).path;
}

/// Abre —y crea si hace falta— una carpeta con [nombre] dentro de los datos de la
/// aplicacion.
Future<AlmacenDeBajadas> abrirLaCarpetaDeBajadas(String nombre) async {
  final datos = await getApplicationSupportDirectory();
  final carpeta = Directory('${datos.path}${Platform.pathSeparator}$nombre');
  if (!await carpeta.exists()) await carpeta.create(recursive: true);
  return CarpetaDeBajadasEnDisco(carpeta);
}
