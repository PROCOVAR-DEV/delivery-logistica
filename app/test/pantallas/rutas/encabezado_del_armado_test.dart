// LA CABECERA DEL «NO» DEL ARMADO SE ESCRIBE DOS VECES, Y TIENE QUE SALIR IGUAL.
//
// Aqui ([encabezadoDelArmado], en `pantallas/rutas/datos/acciones_rutas.dart`) y
// en el servidor (`encabezadoDelArmado`, `api/internal/api/rutas.go`), porque la
// ruta se arma en el patio del almacen sin señal —y ahi el rechazo lo redacta el
// telefono— y con cobertura lo redacta la nube. Si los dos no dicen EXACTAMENTE
// lo mismo, el mismo «no» se lee de dos maneras segun haya red: no falla nada,
// no hay pantalla que lo enseñe, y quien lo sufre acaba aprendiendo dos idiomas
// de error.
//
// Y no es hipotetico. El «1 de los 1 pedidos elegidos no pueden ir en esta ruta»
// —tres faltas en siete palabras, y en el caso mas comun de todos— estuvo mal en
// los DOS lados a la vez y a proposito, porque arreglarlo solo aqui era peor. O
// sea que ya habia un contrato y lo unico que lo sostenia era un comentario en
// cada fichero pidiendo que nadie lo tocara. Un comentario no falla (`CLAUDE.md`
// §3-bis).
//
// POR QUE UN FICHERO COMPARTIDO Y NO UNA TABLA AQUI: una tabla escrita aqui solo
// comprueba que este lado hace lo que esta prueba cree, y se puede cambiar la
// redaccion en los dos sitios de ESTE fichero y salir verde con el servidor ya
// separado. Precedentes identicos: `geo_test.dart` con
// `docs/orden-de-paradas.casos.json` y
// `test/nucleo/almacenes/almacen_de_origen_casos_compartidos_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';

/// El MISMO fichero que lee
/// `api/internal/api/armado_rechazado_casos_compartidos_test.go`, no una copia.
/// Una copia se desincroniza y entonces las dos pruebas salen verdes diciendo
/// cosas distintas, que es justo el fallo que esto cierra.
const rutaDeLosCasosDelArmado = '../docs/armado-rechazado.casos.json';

void main() {
  test('la cabecera del armado es letra por letra la del servidor', () {
    final fichero = File(rutaDeLosCasosDelArmado);
    expect(
      fichero.existsSync(),
      isTrue,
      reason:
          'no esta $rutaDeLosCasosDelArmado. Es el fichero que ata esta '
          'redaccion con la del servidor: sin el, esta prueba no comprueba '
          'nada y el contrato se queda sin vigilante.',
    );

    // Con su tipo puesto: un `List<dynamic>` deja que un error de nombre de campo
    // —`seEligieron` por `seEligeron`— salga NULO en vez de saltar, y entonces
    // esta prueba se pondria verde sobre un fichero que ya no dice nada.
    final casos = ((jsonDecode(fichero.readAsStringSync())
                as Map<String, dynamic>)['casos']
            as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      casos,
      isNotEmpty,
      reason:
          'el fichero de casos esta vacio: una prueba sobre una lista vacia '
          'sale verde sin haber comprobado nada',
    );

    for (final caso in casos) {
      final seCaen = caso['seCaen'] as int;
      final seEligieron = caso['seEligieron'] as int;
      expect(
        encabezadoDelArmado(seCaen, seEligieron),
        caso['encabezado'],
        reason:
            'caso "${caso['nombre']}" ($seCaen de $seEligieron): el servidor '
            'escribe la cabecera del fichero letra por letra '
            '(`encabezadoDelArmado` en api/internal/api/rutas.go). Si la '
            'redaccion tiene que cambiar, se cambian los DOS lados y se '
            'regenera $rutaDeLosCasosDelArmado.\n${caso['nota']}',
      );
    }

    // Y QUE SIGA ESTANDO EL CASO QUE MOTIVO TODO ESTO. Quitarlo del fichero
    // dejaria las dos suites en verde y devolveria el «1 de los 1» por la
    // puerta de al lado.
    expect(
      casos.any((c) => c['seCaen'] == 1 && c['seEligieron'] == 1),
      isTrue,
      reason:
          'el fichero ya no tiene el caso de UN pedido elegido que se cae, que '
          'es el que salia «1 de los 1 pedidos elegidos no pueden ir en esta '
          'ruta» y el mas comun de todos',
    );
  });
}
