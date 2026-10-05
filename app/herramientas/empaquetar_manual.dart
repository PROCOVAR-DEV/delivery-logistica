// EMPAQUETA `docs/manual/` DENTRO DE LA APLICACION.
//
//     cd app && dart run herramientas/empaquetar_manual.dart
//
// Escribe `app/assets/manual/manual.txt`, que es lo que la pantalla de la Guia
// lee con `rootBundle`. Es CODIGO GENERADO y se sube al repositorio, igual que lo
// de `sqlc`: la imagen no tiene que saber regenerarlo y la aplicacion no tiene
// que bajar nada.
//
// SE CORRE CADA VEZ QUE SE TOCA EL MANUAL. Y para que eso no dependa de que
// alguien se acuerde —«un comentario no falla», CLAUDE.md §3-bis—, hay una prueba
// que rehace el paquete y lo compara con el que esta subido:
// `test/pantallas/ayuda/el_manual_no_se_separa_del_repositorio_test.dart`.

import 'dart:io';

import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';

import 'manual_del_repositorio.dart';

void main(List<String> argumentos) {
  final paginas = leerElManualDelRepositorio();

  final faltan = comprobarLasCarpetasDeLasFormas(paginas);
  if (faltan.isNotEmpty) {
    stderr.writeln(
      'Las carpetas de las formas que faltan en $carpetaDelManual: '
      '${faltan.join(', ')}. De esa primera carpeta sale quien ve cada pagina, '
      'asi que con una renombrada la APK se pone a ensenar la guia del '
      'escritorio sin que nada falle.',
    );
    exitCode = 1;
    return;
  }

  final paquete = empaquetarManual(paginas);
  final destino = File('assets/manual/manual.txt');
  destino.parent.createSync(recursive: true);
  destino.writeAsStringSync(paquete);

  final tareas = paginas.values
      .map((t) => RegExp(r'^## ', multiLine: true).allMatches(t).length)
      .fold<int>(0, (a, b) => a + b);
  stdout.writeln(
    'Escrito ${destino.path}: ${paginas.length} paginas, $tareas tareas, '
    '${(paquete.length / 1024).toStringAsFixed(0)} KB.',
  );
}
