/// EL MANUAL VIAJA DENTRO DE LA APLICACION, EN UN SOLO FICHERO.
///
/// ## Por que, y la condicion que lo decide todo
///
/// El manual se escribe en `docs/manual/` y hasta hoy se quedaba ahi: el
/// logistico de Santiago no tiene el repositorio, y la semana que viene empieza a
/// usar esto. Asi que el manual tiene que estar **dentro** de la aplicacion.
///
/// Y dentro de verdad: no se baja, no se pide a la red y no se abre en un
/// navegador. Quien mas necesita la ayuda es justo quien esta en el patio de un
/// almacen sin cobertura, que es la razon de existir de este proyecto
/// (`CLAUDE.md` §1). Un manual que hay que bajar es un manual que no esta.
///
/// ## Por que UN fichero y no 37 ficheros sueltos en `assets/`
///
/// Las dos formas funcionan, pero una se rompe sola y la otra no:
///
///  * Un `assets/manual/` con sus carpetas obliga a declarar **una linea por
///    carpeta** en el `pubspec.yaml` (las entradas de directorio de Flutter no
///    entran en las subcarpetas). El dia que alguien anada
///    `docs/manual/puesta-en-marcha/`, el manual del repositorio crece y el de la
///    aplicacion **no**, y nada falla: la pantalla sigue abriendo, con un trozo
///    menos. Ese es el modo de fallo del §3-bis con otra cara.
///  * Un solo fichero empaquetado no tiene carpetas que declarar. La lista de lo
///    que lleva dentro **sale del propio fichero**, asi que una carpeta nueva
///    entra sin tocar el `pubspec.yaml` ni esta pantalla.
///
/// ## Y lo que impide que las dos copias se separen: una PRUEBA
///
/// El fichero empaquetado es **codigo generado**, como lo de `sqlc`: se escribe
/// con `dart run herramientas/empaquetar_manual.dart` y se sube al repositorio.
/// Un comentario que pida acordarse de regenerarlo no vale para nada —«un
/// comentario no falla», §3-bis—, asi que lo que lo ata es
/// `test/pantallas/ayuda/el_manual_no_se_separa_del_repositorio_test.dart`:
/// rehace el paquete leyendo `../docs/manual/` y lo compara con el que viaja en
/// la aplicacion. Si alguien toca el manual y no regenera, **la prueba se pone
/// roja y dice la orden que hay que correr**.
///
/// Por eso el empaquetado y el desempaquetado viven aqui y no en el guion: el
/// guion que escribe el paquete, la pantalla que lo lee y la prueba que los
/// compara llaman **a la misma funcion**. Tres copias de un formato son tres
/// formatos dentro de un mes.
library;

/// LA MARCA QUE SEPARA UN FICHERO DEL SIGUIENTE.
///
/// Empieza por `#@` a proposito: en Markdown un `#` sin espacio detras no es un
/// encabezado, asi que esta linea no puede salir de nada que alguien escriba
/// queriendo. Y para que no sea una suposicion, [empaquetarManual] **se niega** a
/// empaquetar un fichero que lleve una linea asi ([ManualConMarcaDentro]).
const marcaDeFichero = '#@ FICHERO ';

/// El camino del paquete dentro de los assets. En UN solo sitio: lo nombran el
/// `pubspec.yaml`, el guion que lo escribe, la pantalla que lo lee y la prueba
/// que los compara.
const assetDelManual = 'assets/manual/manual.txt';

/// La orden que regenera el paquete. Va en el mensaje de la prueba que falla,
/// porque un fallo que no dice como se arregla cuesta media hora.
const ordenParaRegenerar = 'dart run herramientas/empaquetar_manual.dart';

/// Lo que se le hace al texto de un fichero antes de empaquetarlo.
///
/// Dos cosas, y las dos para que la comparacion de la prueba sea una compara
/// cion de TEXTO y no de bytes de final de linea:
///
///  * `\r\n` a `\n`. En este repositorio hay ficheros con finales de linea de
///    Windows y ya han hecho fallar reemplazos en silencio (`CLAUDE.md` §6).
///  * un solo salto de linea al final. Que un editor deje o quite la linea vacia
///    del final no es una diferencia del manual, y una prueba que se pone roja
///    por eso es una prueba que la gente aprende a ignorar.
///
/// Lo que **no** se toca es nada de dentro: si una palabra cambia, la prueba lo
/// ve.
String normalizarPaginaDelManual(String texto) =>
    '${texto.replaceAll('\r\n', '\n').trimRight()}\n';

/// Se lanza cuando una pagina del manual lleva dentro una linea que empieza por
/// [marcaDeFichero]. No ha pasado nunca y no deberia pasar; si pasa, el paquete
/// no se escribe, porque un paquete con una marca de mas se desempaqueta en
/// ficheros que no existen.
class ManualConMarcaDentro implements Exception {
  const ManualConMarcaDentro(this.camino, this.linea);

  final String camino;
  final int linea;

  @override
  String toString() =>
      'La pagina «$camino» tiene en la linea $linea un renglon que empieza por '
      '«$marcaDeFichero», que es la marca que separa un fichero del siguiente '
      'dentro del paquete. Cambia ese renglon: tal cual, el manual se '
      'desempaquetaria partido.';
}

/// Empaqueta las paginas en el texto que viaja como asset.
///
/// [paginas] va de camino relativo (`apk/3-tareas.md`) a contenido. El orden de
/// salida es **alfabetico por camino**, no el del mapa: asi dos maquinas
/// escriben el mismo fichero y un `git diff` solo ensena lo que de verdad
/// cambio.
String empaquetarManual(Map<String, String> paginas) {
  final caminos = paginas.keys.toList()..sort();
  final salida = StringBuffer();
  for (final camino in caminos) {
    final contenido = normalizarPaginaDelManual(paginas[camino]!);
    final renglones = contenido.split('\n');
    for (var i = 0; i < renglones.length; i++) {
      if (renglones[i].startsWith(marcaDeFichero)) {
        throw ManualConMarcaDentro(camino, i + 1);
      }
    }
    salida
      ..write(marcaDeFichero)
      ..write(camino)
      ..write('\n')
      ..write(contenido);
  }
  return salida.toString();
}

/// Lo contrario de [empaquetarManual]: del asset al mapa de paginas.
///
/// Lo que haya ANTES de la primera marca se tira: no pertenece a ningun fichero.
/// Hoy no hay nada, y si algun dia lo hay es basura, no una pagina sin nombre.
Map<String, String> desempaquetarManual(String paquete) {
  final paginas = <String, String>{};
  String? camino;
  var cuerpo = StringBuffer();

  void cerrar() {
    final cual = camino;
    if (cual != null) paginas[cual] = cuerpo.toString();
  }

  for (final renglon in paquete.split('\n')) {
    if (renglon.startsWith(marcaDeFichero)) {
      cerrar();
      camino = renglon.substring(marcaDeFichero.length).trim();
      cuerpo = StringBuffer();
      continue;
    }
    if (camino == null) continue;
    cuerpo
      ..write(renglon)
      ..write('\n');
  }
  cerrar();

  // El `split('\n')` de un texto que acaba en `\n` deja un trozo vacio al final,
  // y ese trozo le anade un salto de mas a la ultima pagina. Se le quita a
  // todas por igual con la misma normalizacion con la que se escribieron, que es
  // lo que hace que `desempaquetar(empaquetar(x)) == x` para cualquier x ya
  // normalizado.
  return {
    for (final e in paginas.entries)
      e.key: normalizarPaginaDelManual(e.value),
  };
}
