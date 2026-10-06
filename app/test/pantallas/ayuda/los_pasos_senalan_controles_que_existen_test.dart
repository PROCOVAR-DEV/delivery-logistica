// LO QUE ATA EL MANUAL A LOS BOTONES DE VERDAD.
//
// Un paso del manual dice a que control apunta con un comentario al final del
// renglon: `<!-- señala: vehiculos-agregar -->`. Para que eso llegue a ser un foco
// encima de un boton hacen falta TRES cosas, en tres ficheros distintos:
//
//   1. el nombre escrito en el manual (`docs/manual/`);
//   2. el nombre declarado en el catalogo (`datos/controles_senalados.dart`);
//   3. un `ControlSenalado(nombre: ...)` envolviendo el boton en su pantalla.
//
// Tres sitios para una cosa es el `CLAUDE.md` §3-bis con otra cara, y la
// consecuencia de que se separen no es una pantalla en blanco: es un paso que sale
// **sin foco**, que es justo lo que Jose rechazo. Asi que las tres se comparan
// aqui, en las dos direcciones.
//
// Lo que NO comprueba esto, y hay que saberlo: que el control envuelto sea el
// control del que habla el paso. Eso no lo puede decir ninguna prueba —«Guardar» y
// «Guardar» se parecen—; lo dice el recorrido abierto en la pantalla.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';

import '../../../herramientas/manual_del_repositorio.dart';

/// Los `.dart` de `lib/`, para barrerlos buscando envoltorios.
List<File> _losDeLib() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

void main() {
  final paginas = leerElManualDelRepositorio();
  final manual = Manual.desdeElPaquete(
    // Sin lista de pantallas: aqui no se mira a donde lleva cada tarea —eso es
    // `el_manual_apunta_a_pantallas_que_existen_test.dart`— sino a que control
    // apunta cada paso, y eso no depende del registro.
    _comoPaquete(paginas),
    pantallas: const [],
  );

  final enElManual = <String, List<String>>{};
  for (final tarea in manual.tareas) {
    for (final paso in tarea.pasos) {
      for (final cual in paso.controles) {
        enElManual
            .putIfAbsent(cual, () => <String>[])
            .add('${tarea.camino} «${tarea.titulo}» paso ${paso.cual}');
      }
    }
  }

  final enLasPantallas = <String>{};
  // LAS DOS PUERTAS A `ControlSenalado`, y hacen falta las dos.
  //
  // `nombre:` es el envoltorio a pelo, que es lo normal. `senalado:` es el de
  // `OpcionSelector` (`diseno/selector.dart`), que existe porque hay pasos que
  // apuntan a **una opcion de dentro de un desplegable** —«Elige de la lista. La
  // primera opción es «Todas (8)»», «La opción de CUP lleva la tasa»— y ahi el
  // envoltorio lo pone el selector, no la pantalla: la pantalla solo dice cual.
  //
  // Mirar solo `nombre:` dejaria esos nombres contados como «declarados y sin
  // envolver», que es rojo sobre algo que si esta envuelto. Y al contrario: si
  // manana aparece una tercera puerta y no se anade aqui, esta prueba se queda
  // ciega para ella. **Toda forma de marcar un control tiene que estar en esta
  // lista.**
  final usoDe = RegExp(r'(?:nombre|senalado): Senalado\.(\w+)');
  // De la constante al literal: en las pantallas se escribe
  // `Senalado.vehiculosAgregar` y en el manual `vehiculos-agregar`. El puente es
  // el propio fichero del catalogo.
  final literalDeLaConstante = <String, String>{};
  final declaracion = RegExp(
    r"static const (\w+) =\s*\n?\s*'([a-z0-9-]+)';",
    multiLine: true,
  );
  final catalogo = File('lib/pantallas/ayuda/datos/controles_senalados.dart')
      .readAsStringSync();
  for (final m in declaracion.allMatches(catalogo)) {
    literalDeLaConstante[m.group(1)!] = m.group(2)!;
  }

  for (final fichero in _losDeLib()) {
    // El propio catalogo y el ejemplo del docstring de `ControlSenalado` no son
    // envoltorios de nada.
    if (fichero.path.endsWith('controles_senalados.dart')) continue;
    if (fichero.path.endsWith('control_senalado.dart')) continue;
    for (final m in usoDe.allMatches(fichero.readAsStringSync())) {
      final literal = literalDeLaConstante[m.group(1)!];
      if (literal != null) enLasPantallas.add(literal);
    }
  }

  test('el barrido encuentra manual, catalogo y envoltorios', () {
    // La guarda de «una respuesta vacia no es una respuesta buena»: sin esto, un
    // `lib/` mal resuelto deja las tres pruebas de abajo verdes sobre tres
    // conjuntos vacios.
    expect(paginas, isNotEmpty);
    expect(Senalado.todos.length, greaterThan(50));
    expect(literalDeLaConstante.length, Senalado.todos.length);
    expect(enElManual, isNotEmpty);
    expect(enLasPantallas, isNotEmpty);
  });

  test('el catalogo no se deja ninguna constante fuera de «todos»', () {
    // Dart no sabe enumerar los miembros de una clase, asi que `todos` se escribe
    // a mano. Una constante nueva sin su linea ahi no se puede nombrar desde el
    // manual, y el aviso seria «ese control no existe» sobre uno que si existe.
    expect(
      literalDeLaConstante.values.toSet().difference(Senalado.todos),
      isEmpty,
      reason:
          'estas constantes de `controles_senalados.dart` no estan en '
          '`Senalado.todos`. Anadelas al conjunto.',
    );
  });

  test('todo lo que el manual senala EXISTE en el catalogo', () {
    final inventados = {
      for (final e in enElManual.entries)
        if (!Senalado.todos.contains(e.key)) e.key: e.value,
    };
    expect(
      inventados,
      isEmpty,
      reason:
          'el manual senala controles que no estan en `Senalado.todos`. Un nombre '
          'mal escrito deja el paso SIN FOCO y la tarjeta diciendo «este paso '
          'todavía no tiene su botón marcado», sobre un boton que si lo esta.',
    );
  });

  test('todo lo que el catalogo declara ESTA ENVUELTO en alguna pantalla', () {
    final sinEnvolver = Senalado.todos.difference(enLasPantallas);
    expect(
      sinEnvolver.toList()..sort(),
      isEmpty,
      reason:
          'estos nombres estan declarados y ninguna pantalla los envuelve con '
          '`ControlSenalado`. Es el sentido que se olvida: se declara el nombre, se '
          'escribe el paso del manual, nadie pone el envoltorio, **nada falla** y '
          'el paso sale sin foco. Envuelvelos o quitalos del catalogo.',
    );
  });

  test('el catalogo no acumula nombres que nadie nombra', () {
    // Sobrar no rompe nada hoy, pero un catalogo con nombres muertos es un
    // catalogo en el que nadie se fia de que un nombre quiera decir algo. Se avisa
    // sin romper: es una limpieza, no una averia.
    final nadieLosNombra = Senalado.todos.difference(enElManual.keys.toSet());
    expect(
      nadieLosNombra.toList()..sort(),
      isEmpty,
      reason:
          'estos controles estan marcados en la pantalla y NINGUN paso del manual '
          'los nombra. O le falta su `<!-- señala: … -->` a un paso, o el '
          'envoltorio sobra.',
    );
  });
}

/// Rehace el paquete para poder usar el lector de verdad sobre `docs/manual/`.
///
/// Con `empaquetarManual`, no con una copia del formato: tres copias de un formato
/// son tres formatos dentro de un mes (`datos/empaquetado.dart`).
String _comoPaquete(Map<String, String> paginas) => empaquetarManual(paginas);
