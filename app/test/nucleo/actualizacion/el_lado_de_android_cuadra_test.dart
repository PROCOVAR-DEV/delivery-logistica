// EL CANAL ESTÁ ESCRITO DOS VECES, Y AQUÍ SE COMPRUEBA QUE DICE LO MISMO.
//
// El nombre del canal, los tres métodos y los cuatro códigos de respuesta viven
// en Dart (`CanalDelInstalador`) y en Kotlin (`InstaladorDeApk.kt`). Eso es
// exactamente la forma de §3-bis del `CLAUDE.md`: **dos sitios que tienen que
// contestar lo mismo se atan con una prueba, no con un comentario** — un
// comentario no falla.
//
// Y lo que fallaría sin esto no se parece a un error: cambiar el nombre del canal
// en un lado deja la aplicación **bajando el APK perfectamente** y sin poder
// instalarlo, con un «Android no pudo abrir el instalador» que apunta a Android.
// Lo mismo con el permiso y con el `FileProvider`: si falta el permiso del
// manifiesto, el sistema contesta que no se puede y nadie sabe por qué; si la
// autoridad del proveedor no es la que busca el Kotlin, la instalación no arranca.
//
// Esto se puede comprobar aquí y no hace falta un teléfono porque son ficheros de
// texto del repositorio. Lo que SÍ hace falta probar en un teléfono es que la
// pantalla de Android sale; eso no lo puede hacer ninguna prueba.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/actualizacion/bajada_de_la_actualizacion.dart';
import 'package:reparto/nucleo/actualizacion/instalador.dart';

/// Se lee FUERA de los `test`, asi que no se puede usar `expect`: lanza, que ahi
/// dentro es lo mismo —el fichero no se carga y se ve el motivo—.
String leer(String ruta) {
  final f = File(ruta);
  if (!f.existsSync()) {
    throw StateError(
      'no está $ruta. Las pruebas corren con la raíz en `app/`; si el fichero '
      'se movió, esta prueba es lo primero que hay que arreglar',
    );
  }
  return f.readAsStringSync();
}

void main() {
  final kotlin = leer(
    'android/app/src/main/kotlin/cloud/procovar/reparto/InstaladorDeApk.kt',
  );
  final manifiesto = leer('android/app/src/main/AndroidManifest.xml');
  final rutasDelProveedor = leer(
    'android/app/src/main/res/xml/ficheros_de_la_actualizacion.xml',
  );
  final actividad = leer(
    'android/app/src/main/kotlin/cloud/procovar/reparto/MainActivity.kt',
  );
  final gradle = leer('android/app/build.gradle.kts');

  test('el nombre del canal es el mismo en los dos lados', () {
    expect(
      kotlin,
      contains('"${CanalDelInstalador.nombre}"'),
      reason:
          'Dart habla por «${CanalDelInstalador.nombre}» y el Kotlin escucha en '
          'otro: el APK se baja entero y la instalación no arranca nunca',
    );
  });

  test('los tres métodos y los cuatro códigos son los mismos', () {
    for (final palabra in [
      CanalDelInstalador.sePuede,
      CanalDelInstalador.instalar,
      CanalDelInstalador.ajusteDelPermiso,
      CanalDelInstalador.abierto,
      CanalDelInstalador.sinPermiso,
      CanalDelInstalador.noEstaElFichero,
      CanalDelInstalador.noSeCompartio,
    ]) {
      expect(
        kotlin,
        contains('"$palabra"'),
        reason:
            'el Kotlin no dice «$palabra» en ninguna parte. Un código que Dart '
            'no reconoce se trata como fallo —bien— pero uno que el Kotlin dejó '
            'de mandar deja un camino muerto sin que nada falle',
      );
    }
  });

  test('el manifiesto trae el permiso de instalar paquetes', () {
    expect(
      manifiesto,
      contains('android.permission.REQUEST_INSTALL_PACKAGES'),
      reason:
          'sin este permiso Android no deja ni pedir la instalación, y lo que se '
          've es la pantalla del sistema que no sale. Es el mismo fallo del '
          '16/09/2026 con INTERNET: se degrada a un estado que parece verdad',
    );
  });

  test('el FileProvider está declarado y es nuestra clase, con sus rutas', () {
    // LA AUTORIDAD, que está en dos ficheros y en ninguno de Dart: el manifiesto
    // la declara con `${'\${applicationId}'}` y el Kotlin la arma pegándole este sufijo al
    // nombre del paquete. El literal vive aquí a propósito —es lo que se compara—
    // y se exige en los dos lados: si sólo se mirara uno, cambiar el otro dejaría
    // la instalación sin arrancar y con un aviso que habla de Android.
    const sufijo = '.ficheros';
    expect(
      manifiesto,
      contains('android:authorities="\${applicationId}$sufijo"'),
      reason:
          'la autoridad del proveedor no es «…$sufijo», que es la que arma el '
          'Kotlin: `getUriForFile` lanza y la instalación no arranca',
    );
    expect(
      kotlin,
      contains('SUFIJO_DE_LA_AUTORIDAD = "$sufijo"'),
      reason: 'el Kotlin busca otra autoridad que la que declara el manifiesto',
    );
    // La clase, NUESTRA: `share_plus` y `printing` ya declaran la suya, y Android
    // exige una clase distinta por `<provider>`.
    expect(manifiesto, contains('android:name=".FicherosDelReparto"'));
    expect(kotlin, contains('class FicherosDelReparto : FileProvider()'));
    // Y las rutas, que son las de esta aplicación y ninguna más.
    expect(rutasDelProveedor, contains('<files-path'));
    expect(
      rutasDelProveedor,
      isNot(contains('root-path')),
      reason:
          'una `root-path` abre el disco entero a quien reciba la URI: un '
          'FileProvider existe justo para no hacer eso',
    );
    expect(
      manifiesto,
      contains('android:resource="@xml/ficheros_de_la_actualizacion"'),
    );
  });

  test('el canal se registra al arrancar, o no existe para nadie', () {
    expect(
      actividad,
      contains('InstaladorDeApk(applicationContext).registrar('),
      reason:
          'el manejador está escrito y nadie lo engancha al motor: cada llamada '
          'contesta `MissingPluginException` y el aviso dice «Android no pudo '
          'abrir el instalador», que manda a mirar donde no es',
    );
  });

  test('androidx.core está pedida: sin ella el Kotlin no compila', () {
    expect(
      gradle,
      contains('androidx.core:core'),
      reason:
          '`FileProvider` sale de androidx.core, y las que traen `share_plus` y '
          '`printing` son `implementation` de SUS módulos: no están en el '
          'classpath de este',
    );
  });

  test('la carpeta del APK es la que cubre el XML del proveedor', () {
    // El APK se baja a `<datos de la aplicación>/<carpeta>/reparto.apk`, y el XML
    // tiene que cubrir esa raíz o `getUriForFile` lanza.
    expect(FicherosDeLaActualizacion.carpeta, 'actualizacion');
    expect(FicherosDeLaActualizacion.apk, endsWith('.apk'));
    expect(
      rutasDelProveedor,
      contains('path="."'),
      reason:
          'el XML declara una subcarpeta concreta y la carpeta de Dart es '
          '«${FicherosDeLaActualizacion.carpeta}»: si dejan de cuadrar, la '
          'instalación no arranca y el único síntoma es un aviso genérico',
    );
  });
}
