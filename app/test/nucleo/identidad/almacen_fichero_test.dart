@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion_fichero.dart';

import '../../apoyo/apoyo_sesion.dart';

/// EL ALMACEN DEL ESCRITORIO — el caso S1 de `docs/pruebas.md` en la mitad que
/// hasta hoy no se cumplia.
///
/// > «con red: abrir, entrar, que baje el dia. sin red: CERRAR la aplicacion y
/// > volver a abrirla ← aqui se rompe»
///
/// En Linux se rompia de verdad, y no por el codigo de la casa: el almacen del
/// sistema acepta la escritura y despues no encuentra nada
/// (`almacen_sesion_fichero.dart` tiene el porque con el C++ delante). La
/// aplicacion de escritorio quedaba descalificada entera, porque «funciona sin
/// conexion» es la razon de ser del proyecto.
///
/// Lo que se prueba aqui es exactamente eso, con ficheros de verdad en el
/// disco: **se guarda, se monta el almacen DE CERO, y lo guardado se lee**. Y
/// las tres cosas que lo rodean: que el par no queda en claro, que el fichero
/// de otra maquina no se abre ni se borra, y que un sitio donde no se puede
/// escribir **lo dice** en vez de prometer un dia entero sin senal.
void main() {
  late Directory carpeta;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('reparto-almacen-');
  });

  tearDown(() async {
    // Que la carpeta quede legible pase lo que pase: una prueba deja 0500 a
    // proposito y sin esto el borrado falla y ensucia /tmp.
    await Process.run('chmod', <String>['700', carpeta.path]);
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  AlmacenEnFichero almacen({String maquina = 'maquina-de-prueba'}) =>
      AlmacenEnFichero(carpeta: carpeta, materialDeLaMaquina: maquina);

  test('lo que se guarda se lee con el almacen montado DE CERO', () async {
    // «De cero» es lo que importa: leer de la misma instancia que acaba de
    // escribir no prueba nada, porque el caso de verdad es cerrar la
    // aplicacion en el almacen y volver a abrirla al dia siguiente, sin senal.
    final sesion = sesionDePrueba(refresh: 'refresh-del-dia');
    expect(await almacen().guardar(sesion), isTrue);

    final otroArranque = almacen();
    final leida = await otroArranque.leer();

    expect(leida, isNotNull);
    expect(leida!.refresh, 'refresh-del-dia');
    expect(leida.token, sesion.token);
    expect(leida.sub, sesion.sub);
    expect(leida.sucursalId, sesion.sucursalId);
    expect(leida.roles, sesion.roles);
  });

  test('sin nada guardado no hay sesion, y no es un fallo', () async {
    expect(await almacen().leer(), isNull);
  });

  test('borrar deja el almacen sin sesion', () async {
    await almacen().guardar(sesionDePrueba());
    await almacen().borrar();
    expect(await almacen().leer(), isNull);
  });

  test('guardar dos veces deja la ultima, no las dos', () async {
    await almacen().guardar(sesionDePrueba(refresh: 'el-viejo'));
    await almacen().guardar(sesionDePrueba(refresh: 'el-nuevo'));
    expect((await almacen().leer())?.refresh, 'el-nuevo');
  });

  group('lo que hay en el disco', () {
    test('el par NO queda en claro en el fichero', () async {
      await almacen().guardar(sesionDePrueba(refresh: 'refresh-en-claro-no'));
      final crudo = await _elFichero(carpeta).readAsString();

      expect(crudo, isNot(contains('refresh-en-claro-no')));
      expect(crudo, isNot(contains('sucursalId')));
      // Y el sobre es lo que dice ser: version, sal, nonce, dato y sello.
      final sobre = jsonDecode(crudo) as Map<String, Object?>;
      expect(sobre['v'], 1);
      expect(
        sobre.keys,
        containsAll(<String>['sal', 'nonce', 'dato', 'sello']),
      );
    });

    test('el fichero queda a 0600', () async {
      // Es lo unico que separa el par de tokens de otra cuenta de este mismo
      // ordenador. El cifrado no vale para eso: la clave se puede rehacer desde
      // esta maquina (ver la nota de seguridad del almacen).
      await almacen().guardar(sesionDePrueba());
      final permisos = await Process.run('stat', <String>[
        '-c',
        '%a',
        _elFichero(carpeta).path,
      ]);
      expect((permisos.stdout as String).trim(), '600');
    });

    test('dos guardados del MISMO par no salen iguales', () async {
      // Sal y nonce nuevos en cada escritura. Si salieran iguales, el keystream
      // se repetiria con la misma clave, que es como se rompen estas cosas.
      await almacen().guardar(sesionDePrueba(refresh: 'igual'));
      final primero = await _elFichero(carpeta).readAsString();
      await almacen().guardar(sesionDePrueba(refresh: 'igual'));
      final segundo = await _elFichero(carpeta).readAsString();
      expect(primero, isNot(segundo));
    });
  });

  // EL HUECO `reparto.por_revocar` EN EL DISCO DE VERDAD — re-auditoria 09/10/2026.
  // Todas las demas pruebas del hueco usan `AlmacenEnMemoria`, que no tiene nombre
  // de fichero ni cifrado: con `_nombreDePorRevocar = 'sesion.caja'` (el hueco
  // escrito encima de la sesion) o con `borrar()` llevandose el hueco, todo seguia
  // en verde. El cierre sin red se perderia en silencio: el refresco vivo 30 dias.
  group('el hueco de lo por revocar (por_revocar.caja)', () {
    const pendiente = RefrescoPorRevocar(sub: 'u-1', refresh: 'r-pendiente');
    File elHueco() => File('${carpeta.path}/por_revocar.caja');

    test('borrar() de la SESION no se lo lleva, y ni la sesion pisa al hueco '
        'ni el hueco a la sesion', () async {
      final a = almacen();
      expect(await a.guardar(sesionDePrueba(refresh: 'r-sesion')), isTrue);
      expect(await a.dejarPorRevocar(pendiente), isTrue);
      // Cada uno en SU fichero: el hueco no escribe encima de la sesion.
      expect((await almacen().leer())?.refresh, 'r-sesion');
      expect(elHueco().existsSync(), isTrue);

      await a.borrar(); // salir

      expect(_elFichero(carpeta).existsSync(), isFalse);
      expect(await almacen().leer(), isNull, reason: 'sin sesion');
      expect((await almacen().porRevocar()).map((r) => r.refresh), [
        'r-pendiente',
      ], reason: 'el cierre sin red sigue pendiente aunque ya no haya sesion');
    });

    test(
      'sobrevive a un arranque nuevo del almacen (montado DE CERO)',
      () async {
        await almacen().dejarPorRevocar(pendiente);

        final otroArranque = almacen();
        expect((await otroArranque.porRevocar()).single.sub, 'u-1');
        expect(await otroArranque.leer(), isNull, reason: 'no es una sesion');
      },
    );

    test(
      'quitarlo lo borra del disco, y guardar una sesion NO lo toca',
      () async {
        final a = almacen();
        await a.dejarPorRevocar(pendiente);
        await a.guardar(sesionDePrueba(refresh: 'r-nueva'));
        expect((await almacen().porRevocar()), hasLength(1));

        await a.quitarPorRevocar('r-pendiente');

        expect(await almacen().porRevocar(), isEmpty);
        expect(elHueco().existsSync(), isFalse);
        expect((await almacen().leer())?.refresh, 'r-nueva');
      },
    );

    test('va cifrado igual que la sesion: ni el refresco ni el sub en claro, '
        'sobre completo y 0600', () async {
      await almacen().dejarPorRevocar(pendiente);
      final crudo = await elHueco().readAsString();

      expect(crudo, isNot(contains('r-pendiente')));
      expect(crudo, isNot(contains('u-1')));
      final sobre = jsonDecode(crudo) as Map<String, Object?>;
      expect(sobre['v'], 1);
      expect(
        sobre.keys,
        containsAll(<String>['sal', 'nonce', 'dato', 'sello']),
      );
      final permisos = await Process.run('stat', <String>[
        '-c',
        '%a',
        elHueco().path,
      ]);
      expect((permisos.stdout as String).trim(), '600');
    });

    test('el de otra maquina no se abre (y no se borra)', () async {
      await almacen(maquina: 'la-buena').dejarPorRevocar(pendiente);

      expect(await almacen(maquina: 'la-mala').porRevocar(), isEmpty);
      expect(elHueco().existsSync(), isTrue);
      expect(await almacen(maquina: 'la-buena').porRevocar(), hasLength(1));
    });
  });

  group('el fichero esta atado a esta maquina', () {
    test('el de otra maquina no se abre', () async {
      await almacen(maquina: 'la-de-la-oficina').guardar(sesionDePrueba());
      expect(await almacen(maquina: 'otra-cualquiera').leer(), isNull);
    });

    test('y NO se borra: puede ser esta maquina manana', () async {
      // Un fichero que hoy no se abre —un `machine-id` que cambio, una carpeta
      // restaurada— no es motivo para tirar el par. La regla 3 de
      // `identidad.md` aplicada al disco.
      await almacen(maquina: 'la-buena').guardar(sesionDePrueba());
      expect(await almacen(maquina: 'la-mala').leer(), isNull);
      expect(_elFichero(carpeta).existsSync(), isTrue);
      expect(await almacen(maquina: 'la-buena').leer(), isNotNull);
    });

    test('un fichero tocado a mano no se cuela', () async {
      await almacen().guardar(sesionDePrueba());
      final fichero = _elFichero(carpeta);
      final sobre =
          jsonDecode(await fichero.readAsString()) as Map<String, Object?>;
      // Un byte del dato cambiado: el sello no cuadra y no se descifra nada.
      final dato = base64.decode(sobre['dato']! as String);
      dato[0] = dato[0] ^ 0xff;
      sobre['dato'] = base64.encode(dato);
      await fichero.writeAsString(jsonEncode(sobre));

      expect(await almacen().leer(), isNull);
    });

    test(
      'un fichero que no es ni JSON se trata como que no hay sesion',
      () async {
        await _elFichero(carpeta).writeAsString('esto no es una caja');
        expect(await almacen().leer(), isNull);
      },
    );
  });

  group('un sitio donde no se puede guardar LO DICE', () {
    // Esta es la prueba que no se puede romper: la promesa de la pantalla de
    // acceso —«una vez dentro puedes trabajar el dia entero sin senal»— solo se
    // hace si el almacen contesta que si. O se cumple, o no se promete.

    test('comprobar dice que si cuando el sitio sirve', () async {
      final salud = await almacen().comprobar();
      expect(salud.guarda, isTrue);
      expect(salud.motivo, isNull);
    });

    test('comprobar no deja basura detras', () async {
      await almacen().comprobar();
      final quedo = carpeta
          .listSync()
          .map((e) => e.path.split('/').last)
          .where((n) => n != 'maquina.sal')
          .toList();
      expect(quedo, isEmpty, reason: 'el fichero de la comprobacion se limpia');
    });

    test('comprobar NO se lleva por delante la sesion guardada', () async {
      await almacen().guardar(sesionDePrueba(refresh: 'r-bueno'));
      await almacen().comprobar();
      expect((await almacen().leer())?.refresh, 'r-bueno');
    });

    // COMO ROOT NO SE PUEDE PROBAR ESTO, Y HAY QUE DECIRLO.
    //
    // Las dos de aquí abajo ponen la carpeta a `500` y comprueban que guardar
    // contesta «no pude» en vez de reventar. Root **se salta los permisos**, así
    // que ahí `chmod` no impide nada: la escritura funciona y las dos fallan sin
    // que haya nada roto.
    //
    // Y eso no es teórico: el build de la imagen corre como root, y estas dos
    // tumbaron el tercer despliegue de la web del 17/09/2026 con 860 pruebas en
    // verde.
    //
    // Se salta con `skip:` y no con un `if`: un `if` deja el fichero en verde
    // fingiendo que comprobó algo. `skip` sale impreso, con su motivo, y quien
    // mire el registro ve qué no se comprobó ahí. Nada se descarta en silencio.
    // Se PRUEBA la premisa en vez de preguntar «¿soy root?». Preguntar por el
    // usuario es adivinar; esto hace el experimento: una carpeta a `500` y un
    // fichero dentro. Si entra, `chmod` no protege nada aquí —da igual si es por
    // root o por cómo esté montado el sistema de ficheros— y estas dos no pueden
    // comprobar lo que dicen.
    final permisosSeRespetan = _losPermisosSeRespetan();
    const porQueSeSalta =
        'aquí `chmod 500` no impide escribir (build como root, o el sistema de '
        'ficheros no respeta los permisos), así que «carpeta de solo lectura» no '
        'se puede reproducir. Se comprueba en una máquina de trabajo, con un '
        'usuario normal.';

    test('carpeta de solo lectura: guardar devuelve false, no lanza', () async {
      await almacen().guardar(sesionDePrueba()); // para que exista la carpeta
      await Process.run('chmod', <String>['500', carpeta.path]);

      expect(
        await almacen().guardar(sesionDePrueba(refresh: 'nuevo')),
        isFalse,
      );
    }, skip: permisosSeRespetan ? null : porQueSeSalta);

    test(
      'carpeta de solo lectura: comprobar lo dice ANTES de la contrasena',
      () async {
        await almacen().comprobar();
        await Process.run('chmod', <String>['500', carpeta.path]);

        final salud = await almacen().comprobar();
        expect(salud.guarda, isFalse);
        expect(salud.motivo, isNotNull);
      },
      skip: permisosSeRespetan ? null : porQueSeSalta,
    );
  });
}

File _elFichero(Directory carpeta) => File('${carpeta.path}/sesion.caja');

/// ¿`chmod 500` impide de verdad escribir en esta máquina?
///
/// Se comprueba haciéndolo, no preguntando quién soy: root se salta los
/// permisos, y hay sistemas de ficheros que directamente no los respetan. Lo que
/// importa no es la identidad, es si el experimento se puede montar.
bool _losPermisosSeRespetan() {
  final carpeta = Directory.systemTemp.createTempSync('permisos_');
  try {
    Process.runSync('chmod', <String>['500', carpeta.path]);
    File('${carpeta.path}/prueba').writeAsStringSync('x');
    return false; // Entró: aquí los permisos no protegen nada.
  } on FileSystemException {
    return true;
  } finally {
    Process.runSync('chmod', <String>['700', carpeta.path]);
    try {
      carpeta.deleteSync(recursive: true);
    } on FileSystemException {
      // Si no se puede borrar, es una carpeta temporal y se la lleva el sistema.
    }
  }
}
