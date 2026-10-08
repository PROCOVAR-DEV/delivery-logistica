// EL LITERAL DE «NO TIENES PERMISO PARA ENTRAR A REPARTO» ESTÁ ESCRITO EN TRES SITIOS.
//
// La API (`api/internal/auth/middleware.go`) y el sincronizador
// (`sync/internal/identidad/identidad.go`) lo mandan; la app lo reconoce
// (`fallos.dart`): el `codigo` en el interceptor y la frase en la segunda cerradura de
// `Subida._aplicar`. Un comentario que dice «tienen que ser el mismo» no falla (CLAUDE.md
// §3-bis): esta prueba LEE los ficheros de Go y falla si alguno se mueve.
//
// Si el fichero no existe, la prueba FALLA: una prueba que se salta sola cuando le falta
// aquello que ata no ata nada.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/fallos.dart';

void main() {
  /// El valor de `const Nombre = "…"` (o dentro de un bloque `const (…)`) en un `.go`.
  String deGo(String fichero, String nombre) {
    final f = File(fichero);
    expect(
      f.existsSync(),
      isTrue,
      reason: 'no está $fichero: desde app/ se espera ../api y ../sync',
    );
    final m = RegExp('$nombre\\s*=\\s*"([^"]+)"')
        .firstMatch(f.readAsStringSync());
    expect(m, isNotNull, reason: '$fichero ya no define $nombre');
    return m!.group(1)!;
  }

  const ficheros = <String>[
    '../api/internal/auth/middleware.go',
    '../sync/internal/identidad/identidad.go',
  ];

  for (final fichero in ficheros) {
    test('la frase de $fichero es la de fallos.dart', () {
      expect(
        deGo(fichero, 'MsgSinPermisoReparto'),
        textoSinPermisoDeReparto,
        reason:
            'la segunda cerradura de `Subida._aplicar` compara este literal; '
            'si el servidor lo cambia, la cola de quien no tiene permiso '
            'volvería a poder marcarse rechazada',
      );
    });

    test('el codigo de $fichero es la marca de fallos.dart', () {
      expect(
        deGo(fichero, 'CodigoSinPermisoReparto'),
        marcaSinPermisoDeReparto,
        reason: 'el interceptor solo avisa con este `codigo`',
      );
    });
  }
}
