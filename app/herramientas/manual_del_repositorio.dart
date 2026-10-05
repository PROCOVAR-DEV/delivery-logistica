// LEER `docs/manual/` DEL REPOSITORIO. Lo usan DOS, y a proposito.
//
//   * `herramientas/empaquetar_manual.dart`, que escribe el asset; y
//   * `test/pantallas/ayuda/el_manual_no_se_separa_del_repositorio_test.dart`,
//     que rehace el paquete por su cuenta y lo compara con el que viaja dentro
//     de la aplicacion.
//
// Si cada uno recorriera la carpeta a su manera, los dos podrian estar de
// acuerdo sobre un conjunto de ficheros equivocado —por ejemplo, los dos
// saltandose una carpeta nueva— y la prueba seguiria verde con el manual a
// medias. Con una sola funcion, lo unico que la prueba puede decir es «lo que
// hay en el repositorio no es lo que viaja dentro».
//
// Vive en `herramientas/` y no en `lib/` porque usa `dart:io`: la aplicacion se
// compila tambien a web, y un `dart:io` dentro de `lib/` es una trampa esperando
// a que alguien lo importe desde una pantalla.

import 'dart:io';

/// Donde vive el manual, visto desde `app/`. Es la ruta que usan el guion y la
/// prueba, los dos corriendo con `app/` como directorio de trabajo
/// (`flutter test` y `dart run` lo hacen asi).
const carpetaDelManual = '../docs/manual';

/// Las tres formas de la aplicacion tienen su carpeta, y de ahi sale quien ve
/// que. Si alguien las renombra, [comprobarLasCarpetasDeLasFormas] lo dice.
const carpetasDeLasFormas = <String>['apk', 'escritorio', 'web'];

/// Lee todas las paginas del manual, de camino relativo a contenido.
///
/// Recorre **entero y a cualquier profundidad**, y coge **todo lo que acabe en
/// `.md`**: ni una lista de nombres, ni un tope de carpetas. El encargo lo pide
/// con esas palabras —«tu pantalla tiene que coger lo que haya en esa carpeta,
/// sea lo que sea, sin depender de los nombres de hoy»— porque mientras esto se
/// escribia habia otro agente anadiendo paginas nuevas.
Map<String, String> leerElManualDelRepositorio([
  String carpeta = carpetaDelManual,
]) {
  final raiz = Directory(carpeta);
  if (!raiz.existsSync()) {
    throw ManualNoEncontrado(raiz.absolute.path);
  }

  final paginas = <String, String>{};
  for (final cosa in raiz.listSync(recursive: true, followLinks: false)) {
    if (cosa is! File) continue;
    if (!cosa.path.endsWith('.md')) continue;
    // Siempre con `/`, tambien el dia que esto corra en Windows: el camino es
    // una clave que viaja dentro del asset y la comparan dos lados.
    final relativo = cosa.path
        .substring(raiz.path.length + 1)
        .replaceAll(r'\', '/');
    paginas[relativo] = cosa.readAsStringSync();
  }

  if (paginas.isEmpty) {
    throw ManualNoEncontrado(raiz.absolute.path);
  }
  return paginas;
}

/// Que las tres carpetas de las formas sigan llamandose como [carpetasDeLasFormas].
///
/// Devuelve las que FALTAN. No es celo: de esa primera carpeta sale quien ve
/// cada pagina (`FormaDelManual`), asi que renombrar `apk/` a `android/` no
/// rompe nada visible — las paginas pasan a ser «de todos» y la APK se pone a
/// ensenar la guia del escritorio, que es justo lo que no puede pasar.
List<String> comprobarLasCarpetasDeLasFormas(Map<String, String> paginas) {
  final carpetas = {
    for (final camino in paginas.keys)
      if (camino.contains('/')) camino.split('/').first,
  };
  return [
    for (final forma in carpetasDeLasFormas)
      if (!carpetas.contains(forma)) forma,
  ];
}

class ManualNoEncontrado implements Exception {
  const ManualNoEncontrado(this.donde);

  final String donde;

  @override
  String toString() =>
      'No hay ninguna pagina de manual en «$donde». Esto se corre desde «app/», '
      'con el repositorio entero al lado: `cd app && dart run '
      'herramientas/empaquetar_manual.dart`.';
}
