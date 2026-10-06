import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporal;
  setUp(() => temporal = Directory.systemTemp.createTempSync('reparto-web-'));
  tearDown(() => temporal.deleteSync(recursive: true));

  Directory build(String nombre) {
    final dir = Directory('${temporal.path}/$nombre')..createSync();
    void escribir(String ruta, String texto) {
      final fichero = File('${dir.path}/$ruta');
      fichero.parent.createSync(recursive: true);
      fichero.writeAsStringSync(texto);
    }

    escribir(
      'index.html',
      '<script src="flutter_bootstrap.js"></script>'
          '<link href="favicon.png"><link href="icons/Icon-192.png">',
    );
    escribir(
      'flutter_bootstrap.js',
      '_flutter.buildConfig={"mainJsPath":"main.dart.js"};\n'
          'const entrada = build.mainJsPath || "main.dart.js";\n'
          '_flutter.loader.load({serviceWorkerSettings:{}});',
    );
    escribir('main.dart.js', 'codigo de la aplicacion');
    escribir(
      'assets/FontManifest.json',
      jsonEncode([
        {
          'family': 'MaterialIcons',
          'fonts': [
            {'asset': 'fonts/MaterialIcons-Regular.otf'},
          ],
        },
      ]),
    );
    escribir(
      'assets/fonts/MaterialIcons-Regular.otf',
      'fuente con el libro nuevo',
    );
    escribir('assets/assets/manual/manual.txt', 'manual nuevo');
    return dir;
  }

  Future<ProcessResult> preparar(Directory dir) =>
      Process.run('sh', ['../deploy/preparar-web.sh', dir.path]);

  String base(Directory dir) {
    final bootstrap = File('${dir.path}/flutter_bootstrap.js')
        .readAsStringSync();
    final match = RegExp("assetBase: '([^']+)'").firstMatch(bootstrap);
    expect(
      match,
      isNotNull,
      reason: 'El motor debe pedir los recursos de este build.',
    );
    return match!.group(1)!;
  }

  test('el motor recibe la fuente nueva aunque la URL antigua siga cacheada', () async {
    final dir = build('nuevo');
    final result = await preparar(dir);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final prefijo = base(dir);
    final manifiesto = jsonDecode(
      File('${dir.path}/${prefijo}assets/FontManifest.json').readAsStringSync(),
    ) as List<Object?>;
    final familia = manifiesto.first! as Map<String, Object?>;
    final fuentes = familia['fonts']! as List<Object?>;
    final fuente = (fuentes.first! as Map<String, Object?>)['asset']! as String;
    // URLs producidas por AssetManager: assetBase + assets/ + clave del asset.
    final urlNueva = '${prefijo}assets/$fuente';
    final cacheAntigua = {'assets/$fuente': 'fuente vieja SIN el libro'};
    final recibido =
        cacheAntigua[urlNueva] ??
        File('${dir.path}/$urlNueva').readAsStringSync();
    expect(
      recibido,
      'fuente con el libro nuevo',
      reason: 'Guía no puede usar la fuente cacheada del despliegue anterior.',
    );
    expect(
      File('${dir.path}/${prefijo}assets/assets/manual/manual.txt')
          .readAsStringSync(),
      'manual nuevo',
    );
    expect(Directory('${dir.path}/assets').existsSync(), isFalse);
    final huella = prefijo.split('/')[1];
    expect(
      File('${dir.path}/index.html').readAsStringSync(),
      contains('flutter_bootstrap.js?v=$huella'),
    );
    expect(
      File('${dir.path}/flutter_bootstrap.js').readAsStringSync(),
      contains('main.dart.js?v=$huella'),
    );
  });

  for (final ruta in [
    'assets/fonts/MaterialIcons-Regular.otf',
    'assets/assets/manual/manual.txt',
    'assets/FontManifest.json',
    'main.dart.js',
  ]) {
    test('cambiar $ruta invalida la dirección, incluso si no cambia el resto', () async {
      final viejo = build('viejo');
      final nuevo = build('nuevo');
      File('${nuevo.path}/$ruta').writeAsStringSync('contenido distinto');
      expect((await preparar(viejo)).exitCode, 0);
      expect((await preparar(nuevo)).exitCode, 0);
      expect(
        base(nuevo),
        isNot(base(viejo)),
        reason:
            'Una caché no debe mezclar los assets viejos con el código nuevo.',
      );
    });
  }

  test('el mismo contenido conserva sus direcciones', () async {
    final a = build('a');
    final b = build('b');
    expect((await preparar(a)).exitCode, 0);
    expect((await preparar(b)).exitCode, 0);
    expect(base(a), base(b));
  });

  for (final ruta in [
    'index.html',
    'main.dart.js',
    'flutter_bootstrap.js',
    'assets/FontManifest.json',
    'assets/fonts/MaterialIcons-Regular.otf',
    'assets/assets/manual/manual.txt',
  ]) {
    test('falta $ruta: detener el despliegue', () async {
      final dir = build('incompleto');
      File('${dir.path}/$ruta').deleteSync();
      expect(
        (await preparar(dir)).exitCode,
        isNot(0),
        reason: 'No publicar una web sin sus recursos esenciales.',
      );
    });
  }

  for (final caso in [
    'sin inicializador',
    'dos inicializadores',
    'dos inicializadores en una línea',
    'dos entradas JS en una línea',
    'entrada JS distinta',
  ]) {
    test('$caso: detener antes de mover los recursos', () async {
      final dir = build('bootstrap-distinto');
      final fichero = File('${dir.path}/flutter_bootstrap.js');
      var texto = fichero.readAsStringSync();
      if (caso == 'sin inicializador') {
        texto = texto.replaceAll('_flutter.loader.load({', 'otro.load({');
      }
      if (caso == 'dos inicializadores') {
        texto += '\n_flutter.loader.load({});';
      }
      if (caso == 'dos inicializadores en una línea') {
        texto += '_flutter.loader.load({});';
      }
      if (caso == 'dos entradas JS en una línea') {
        texto = texto.replaceAll(
          '"mainJsPath":"main.dart.js"',
          '"mainJsPath":"main.dart.js","mainJsPath":"main.dart.js"',
        );
      }
      if (caso == 'entrada JS distinta') {
        texto = texto.replaceAll(
          '"mainJsPath":"main.dart.js"',
          '"mainJsPath":"otra.js"',
        );
      }
      fichero.writeAsStringSync(texto);
      expect(
        (await preparar(dir)).exitCode,
        isNot(0),
        reason: 'Si cambia Flutter, fallar en el build y no en el navegador.',
      );
      expect(Directory('${dir.path}/assets').existsSync(), isTrue);
    });
  }

  for (final caso in ['sin bootstrap en HTML', 'sin favicon en HTML']) {
    test('$caso: detener antes de mover los recursos', () async {
      final dir = build('html-distinto');
      final fichero = File('${dir.path}/index.html');
      final texto = fichero.readAsStringSync();
      fichero.writeAsStringSync(
        texto.replaceAll(
          caso == 'sin bootstrap en HTML'
              ? 'flutter_bootstrap.js'
              : 'favicon.png',
          'otro-fichero',
        ),
      );
      expect(
        (await preparar(dir)).exitCode,
        isNot(0),
        reason: 'No dejar index.html apuntando a recursos que ya no existen.',
      );
      expect(Directory('${dir.path}/assets').existsSync(), isTrue);
    });
  }
}
