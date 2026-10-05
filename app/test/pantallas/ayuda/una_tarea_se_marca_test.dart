// QUE ES UNA TAREA, Y QUE NO SE PUEDA OLVIDAR EN NINGUNO DE LOS DOS SENTIDOS.
//
// La Guia 1.0.22 listaba **todos los `##` del manual**: 301 filas. Jose las abrio
// y no le llevaban a ningun sitio, porque la mayoria no eran cosas que hacer sino
// trozos de un documento — «Qué es», «Lo que hay que hacer», «Los filtros».
//
//     «me pusiste las tareas pero las tareas no me mueven a ningún lugar
//      enseñándome cómo debería trabajar en tiempo real, como un vídeo»
//
// Ahora una tarea es un encabezado con `<!-- tarea -->` debajo. Y esto son las DOS
// pruebas que hacen que la marca no se pueda olvidar, porque las dos direcciones
// fallan distinto:
//
//  * **marcado sin «Empieza en:»** — la tarea sale en la lista y no puede llevar a
//    ningun sitio. Es la queja de Jose, otra vez.
//  * **«Empieza en:» sin marcar** — la tarea **no sale en la lista** y NADA FALLA.
//    Es el modo de fallo del `CLAUDE.md` §3-bis, y es el peor de los dos: el otro
//    se ve abriendo la Guia; este sólo se ve si alguien echa en falta su tarea.
//
// Se leen de `../docs/manual/` **de verdad**, no de un manual de mentira: lo que
// hay que vigilar es lo que alguien escriba mañana ahi.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';

import '../../../herramientas/manual_del_repositorio.dart';

/// Un encabezado del manual, con lo que hace falta para juzgarlo.
class _Encabezado {
  const _Encabezado({
    required this.camino,
    required this.renglon,
    required this.titulo,
    required this.marcado,
    required this.dondeEmpieza,
  });

  final String camino;
  final int renglon;
  final String titulo;
  final bool marcado;

  /// `true` si debajo del encabezado, antes de cualquier otra cosa, hay un
  /// `**Empieza en:**`.
  final bool dondeEmpieza;

  String get donde => '$camino:$renglon «$titulo»';
}

final _encabezado = RegExp(r'^(#{1,4}) +(.*)$');
final _valla = RegExp(r'^\s{0,3}`{3,}');

List<_Encabezado> _encabezadosDe(String camino, String contenido) {
  final renglones = contenido.split('\n');
  final salida = <_Encabezado>[];
  var dentroDeCodigo = false;
  var primerTitulo = true;

  for (var i = 0; i < renglones.length; i++) {
    if (_valla.hasMatch(renglones[i])) {
      dentroDeCodigo = !dentroDeCodigo;
      continue;
    }
    if (dentroDeCodigo) continue;
    final cabeza = _encabezado.firstMatch(renglones[i]);
    if (cabeza == null) continue;

    // El primer `# ` es el titulo de la pagina, no una tarea. Es la misma regla
    // que aplica el lector (`manual.dart`), y repetirla aqui es a proposito: si
    // alguien la cambia alli, esta prueba deja de cuadrar y se entera.
    if (primerTitulo && cabeza.group(1)!.length == 1) {
      primerTitulo = false;
      continue;
    }

    final marcado =
        i + 1 < renglones.length && renglones[i + 1].trim() == marcaDeTarea;

    // ¿Hay un «Empieza en:» en el preambulo? Se mira hasta el primer renglon que
    // no sea ni la marca, ni un blanco, ni el propio «Empieza en:».
    var dondeEmpieza = false;
    for (var j = i + 1; j < renglones.length; j++) {
      final renglon = renglones[j].trim();
      if (renglon.isEmpty || renglon == marcaDeTarea) continue;
      if (renglonDePantalla.hasMatch(renglones[j])) dondeEmpieza = true;
      break;
    }

    salida.add(
      _Encabezado(
        camino: camino,
        renglon: i + 1,
        titulo: cabeza.group(2)!.trim(),
        marcado: marcado,
        dondeEmpieza: dondeEmpieza,
      ),
    );
  }
  return salida;
}

void main() {
  final paginas = leerElManualDelRepositorio();
  final todos = <_Encabezado>[
    for (final e in paginas.entries) ..._encabezadosDe(e.key, e.value),
  ];

  test('el manual del repositorio se lee y trae encabezados', () {
    // Sin esto, una ruta mal puesta deja las dos pruebas de abajo en verde sobre
    // una lista vacia, que es la trampa de «una respuesta vacia no es una
    // respuesta buena» (`CLAUDE.md` §3).
    expect(paginas, isNotEmpty);
    expect(todos.length, greaterThan(100));
  });

  test('toda tarea marcada dice DONDE EMPIEZA', () {
    final mudas = todos.where((e) => e.marcado && !e.dondeEmpieza).toList();
    expect(
      mudas.map((e) => e.donde).toList(),
      isEmpty,
      reason:
          'estos encabezados llevan «$marcaDeTarea» y no tienen debajo un '
          'renglon «**Empieza en:**». Una tarea que no dice donde empieza sale en '
          'la lista de la Guia y no puede llevar a ningun sitio, que es '
          'exactamente de lo que se quejo Jose el 05/10/2026. Ponle su '
          '«**Empieza en:**» —con «Menú → «Pantalla»» si empieza en una pantalla, o '
          'con el sitio en palabras si no— o quitale la marca.',
    );
  });

  test('todo lo que dice donde empieza ESTA MARCADO como tarea', () {
    final sinMarcar = todos.where((e) => e.dondeEmpieza && !e.marcado).toList();
    expect(
      sinMarcar.map((e) => e.donde).toList(),
      isEmpty,
      reason:
          'estos encabezados tienen su «**Empieza en:**» y les falta '
          '«$marcaDeTarea» en el renglon de debajo, asi que la Guia NO los lista. '
          'Este es el sentido que no se ve: la tarea existe en el manual, no sale '
          'en la aplicacion y nada falla. Pon la marca en el renglon '
          'inmediatamente siguiente al encabezado.',
    );
  });

  /// Y LA MARCA VA PEGADA AL ENCABEZADO, no «en algun sitio debajo».
  ///
  /// El lector sólo mira el renglon siguiente. Una marca a dos renglones no la ve,
  /// y la tarea se cae de la lista sin que ninguna de las dos pruebas de arriba lo
  /// note: no esta marcada, asi que la segunda la pediria… y la encontraria
  /// escrita. Por eso esta tercera mira el fichero en crudo.
  test('no hay marcas de tarea sueltas, fuera del renglon de debajo', () {
    final sueltas = <String>[];
    paginas.forEach((camino, contenido) {
      final renglones = contenido.split('\n');
      for (var i = 0; i < renglones.length; i++) {
        if (renglones[i].trim() != marcaDeTarea) continue;
        final anterior = i == 0 ? '' : renglones[i - 1];
        if (!_encabezado.hasMatch(anterior)) {
          sueltas.add('$camino:${i + 1}');
        }
      }
    });
    expect(
      sueltas,
      isEmpty,
      reason:
          'estas «$marcaDeTarea» no van justo debajo de un encabezado, asi que el '
          'lector no las ve y su tarea no sale en la Guia. La marca va en el '
          'renglon inmediatamente siguiente al `#`, `##` o `###`.',
    );
  });
}
