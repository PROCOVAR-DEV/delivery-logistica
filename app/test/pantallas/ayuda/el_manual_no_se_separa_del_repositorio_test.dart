// LO QUE IMPIDE QUE EL MANUAL DEL REPOSITORIO Y EL QUE VE LA GENTE DIGAN COSAS
// DISTINTAS.
//
// El manual se escribe en `docs/manual/` y viaja dentro de la aplicacion
// empaquetado en `assets/manual/manual.txt`, que es **codigo generado** (lo
// escribe `herramientas/empaquetar_manual.dart`). O sea: hay dos copias del mismo
// texto, y eso es exactamente el modo de fallo del `CLAUDE.md` §3-bis.
//
// El 17/09/2026 el tablero de La Habana decia «Sin colocar (722)» encima de una
// lista de 293 porque dos consultas que tenian que contestar lo mismo se
// separaron. Encima, el comentario que avisaba estaba escrito y no sirvio de
// nada, **porque un comentario no falla**. La regla que salio de ahi:
//
//   «cuando dos consultas tienen que contestar lo mismo, hay que atarlas con una
//    prueba, no con un comentario»
//
// Esto es esa prueba, para el manual. Lee `../docs/manual/` de verdad, rehace el
// paquete con la MISMA funcion que lo escribio, y lo compara con el que esta
// subido. Si alguien toca una pagina y no regenera, esto se pone rojo y dice la
// orden que hay que correr.
//
// Y lee la carpeta ENTERA y a cualquier profundidad, sin una lista de nombres:
// mientras esto se escribia habia otro agente anadiendo paginas nuevas, y una
// prueba que compare contra los nombres de hoy deja de mirar justo lo que llega
// manana.
//
// NOTA PARA QUIEN MIRE `deploy/Dockerfile.app`: esta prueba lee ficheros de fuera
// de `app/`, como `geo_test.dart` y las otras tres. Ahi no hace falta copiar nada
// porque esa imagen ya **no corre `flutter test`** —se quito el 26/09/2026, con el
// motivo escrito— y solo hace `flutter analyze lib test`. Si algun dia vuelve la
// suite a la imagen, esta prueba necesita `COPY docs/manual /docs/manual`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';

import '../../../herramientas/manual_del_repositorio.dart';

void main() {
  pruebaDelAsset();

  final enElRepositorio = leerElManualDelRepositorio();
  final empaquetado = File(assetDelManual).readAsStringSync();
  final queViaja = desempaquetarManual(empaquetado);

  test('el paquete lleva EXACTAMENTE las paginas que hay en docs/manual', () {
    expect(
      queViaja.keys.toSet(),
      enElRepositorio.keys.toSet(),
      reason:
          'el manual del repositorio y el que viaja dentro de la aplicacion no '
          'tienen las mismas paginas. Corre «$ordenParaRegenerar» desde app/',
    );
  });

  test('y cada pagina dice lo mismo, palabra por palabra', () {
    for (final camino in enElRepositorio.keys.toList()..sort()) {
      expect(
        queViaja[camino],
        normalizarPaginaDelManual(enElRepositorio[camino]!),
        reason:
            'la pagina «$camino» no dice lo mismo en docs/manual que dentro de '
            'la aplicacion. Lo que lee la gente es la de dentro, asi que ahora '
            'mismo el manual miente. Corre «$ordenParaRegenerar» desde app/',
      );
    }
  });

  /// La de arriba compara pagina a pagina; esta compara el fichero entero. Hace
  /// falta porque son dos fallos distintos: una pagina que cambia, y el ORDEN o
  /// el formato del paquete cambiando sin que ninguna pagina cambie. Lo segundo
  /// dejaria un `git diff` enorme en cada regeneracion, que es como se acaba
  /// subiendo un paquete viejo «porque el diff era solo de orden».
  test('el paquete es byte a byte el que sale de empaquetar hoy', () {
    expect(
      empaquetado,
      empaquetarManual(enElRepositorio),
      reason:
          'el paquete subido no es el que sale de empaquetar docs/manual hoy. '
          'Corre «$ordenParaRegenerar» desde app/',
    );
  });

  /// Las tres carpetas de las formas son de donde sale QUIEN VE QUE pagina. Si
  /// alguien renombra `apk/` a `android/`, sus paginas pasan a ser «de todos» y la
  /// APK se pone a ensenar la guia del escritorio **sin que nada falle** — justo
  /// lo que la regla 1 de `CLAUDE.md` prohibe.
  test('las tres carpetas de las formas siguen llamandose igual', () {
    expect(
      comprobarLasCarpetasDeLasFormas(enElRepositorio),
      isEmpty,
      reason:
          'de la primera carpeta de cada pagina sale en que forma se ve. Con una '
          'renombrada, la APK ensena la guia del escritorio y nada se queja',
    );
  });

  test('ninguna pagina lleva dentro la marca que separa ficheros', () {
    // `empaquetarManual` lanza si la encuentra, asi que esto ya lo cubre la
    // prueba de arriba. Se escribe aparte para que el dia que salte se lea POR
    // QUE salta: un renglon que empiece por la marca partiria el paquete en
    // ficheros que no existen.
    expect(
      () => empaquetarManual(enElRepositorio),
      returnsNormally,
      reason:
          'alguna pagina tiene un renglon que empieza por «$marcaDeFichero»',
    );
  });
}

/// Y LA OTRA MITAD, sin la cual todo lo de arriba puede estar verde y la Guia
/// abrirse en blanco: **que el paquete este declarado en el `pubspec.yaml`**.
///
/// Las pruebas de arriba leen el fichero con `dart:io`, o sea del disco. La
/// aplicacion lo lee con `rootBundle`, o sea del paquete que Flutter arma a partir
/// de la lista de `assets:`. Son dos caminos distintos: **borrar la linea del
/// `pubspec.yaml` deja todas las de arriba en verde** y la pantalla diciendo «la
/// guia no se pudo leer», que es el unico fallo que la gente veria.
///
/// ## `tester.runAsync`, y se descubrio colgandose
///
/// `rootBundle.loadString` habla por un canal con el motor, o sea que es
/// **asincrono de verdad**. Dentro del cuerpo de un `testWidgets` el tiempo lo
/// manda el `tester` y el reloj no avanza solo, asi que un `await` sobre eso **no
/// se resuelve nunca: la prueba se cuelga en vez de fallar**, que es lo peor que
/// puede hacer una prueba (`CLAUDE.md` §5). Escrita sin esto, se comio tres
/// intentos y dejo un `flutter_tester` colgado trece minutos — el mismo sintoma
/// que las dos trampas hermanas del §5, con otro origen.
///
/// `tester.runAsync` corre lo de dentro FUERA del reloj falso, que es lo unico que
/// hace esperable una respuesta del motor.
void pruebaDelAsset() {
  testWidgets('el paquete viaja de verdad dentro de la aplicacion', (
    tester,
  ) async {
    final delPaquete = await tester.runAsync(
      () => rootBundle.loadString(assetDelManual),
    );
    expect(
      delPaquete,
      File(assetDelManual).readAsStringSync(),
      reason:
          'el asset «$assetDelManual» no llega igual por `rootBundle`. Mira que '
          'siga declarado en `pubspec.yaml`, bajo `flutter: assets:`',
    );
  });
}
