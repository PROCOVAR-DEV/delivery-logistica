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

import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';

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

  stdout.writeln(
    'Escrito ${destino.path}: ${paginas.length} paginas, '
    '${(paquete.length / 1024).toStringAsFixed(0)} KB.',
  );

  // LA CUENTA SALE DEL LECTOR DE VERDAD, no de un `grep` de `^## `.
  //
  // Hasta el 05/10/2026 esto contaba los `^## ` del manual y decia «302 tareas».
  // No lo eran: ahi dentro caian «Qué es», «Lo que hay que hacer» y «Los
  // filtros», que son trozos de un documento. Jose las abrio una por una y no le
  // llevaban a ningun sitio. Contar con el mismo lector que usa la pantalla es lo
  // unico que hace que este numero signifique algo.
  // SIN LA LISTA DE PANTALLAS, y a proposito: resolverla obliga a importar
  // `navegacion/`, que arrastra Flutter, y esto corre con `dart run` a pelo. Lo que
  // falta aqui —si la pantalla que nombra cada tarea existe en cada forma— lo
  // comprueba `el_manual_apunta_a_pantallas_que_existen_test.dart`, que si corre
  // dentro de Flutter.
  final manual = Manual.desdeElPaquete(paquete, pantallas: const []);
  for (final forma in FormaDeLaAplicacion.values) {
    final suyas = manual.paraLaForma(forma).tareas;
    final pasos = suyas.fold<int>(0, (a, t) => a + t.pasos.length);
    final senalados = suyas.fold<int>(0, (a, t) => a + t.pasosSenalados);
    stdout.writeln(
      '  ${forma.name.padRight(11)} ${suyas.length} tareas · '
      '${suyas.where((t) => t.pasos.isNotEmpty).length} con pasos · '
      '$pasos pasos, $senalados senalan un control '
      '(${pasos == 0 ? 0 : (senalados * 100 / pasos).round()} %)',
    );
  }

  // LOS NOMBRES QUE EL MANUAL NOMBRA Y NO EXISTEN. Aqui es un aviso; la prueba
  // `los_pasos_senalan_controles_que_existen_test.dart` lo pone rojo.
  final inventados = <String>{};
  for (final tarea in manual.tareas) {
    for (final paso in tarea.pasos) {
      for (final cual in paso.controles) {
        if (!Senalado.todos.contains(cual)) inventados.add(cual);
      }
    }
  }
  if (inventados.isNotEmpty) {
    stderr.writeln(
      'OJO: el manual senala controles que no existen: '
      '${(inventados.toList()..sort()).join(', ')}',
    );
    exitCode = 1;
  }
}
