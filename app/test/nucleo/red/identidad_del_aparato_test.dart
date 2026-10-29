// LA IDENTIDAD DEL APARATO EN LAS PETICIONES A ACCESOS — 29/10/2026.
//
// `X-Aparato-Id` (UUID v7) y `X-Aparato-Nombre` salen en cada petición del Dio de
// Accesos; sin id (web o un fallo del disco) no sale nada y la petición sigue.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/agente_de_usuario.dart';
import 'package:reparto/nucleo/red/id_del_aparato_nativo.dart';

import '../../apoyo/servidor_falso.dart';

const _v7 = '0192f3c4-8a3b-7d0e-9d62-6a1f3b6f2c10';

void main() {
  Future<Map<String, dynamic>> cabeceras({
    required Future<String?> Function() id,
    Future<String?> Function()? nombre,
    Future<String?> Function()? huella,
  }) async {
    late PeticionVista visto;
    final servidor = ServidorFalso((p) async {
      visto = p;
      return RespuestaFalsa(200);
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
      ..httpClientAdapter = servidor
      ..interceptors.add(
        InterceptorDeAparato(
          id: id,
          nombre: nombre ?? () async => null,
          huella: huella ?? () async => null,
        ),
      );
    await dio.post('/refresh');
    return visto.cabeceras;
  }

  test('manda el id y el nombre', () async {
    final h = await cabeceras(
      id: () async => _v7,
      nombre: () async => 'Samsung SM-A166B',
    );
    expect(h['X-Aparato-Id'], _v7);
    expect(h['X-Aparato-Nombre'], 'Samsung SM-A166B');
  });

  test(
    'sin id (la web, o el disco falló) no pone nada y la petición sale',
    () async {
      final h = await cabeceras(id: () async => null);
      expect(h.containsKey('X-Aparato-Id'), isFalse);
      expect(h.containsKey('X-Aparato-Nombre'), isFalse);
    },
  );

  test('si leer la identidad lanza, la petición SALE igual', () async {
    final h = await cabeceras(id: () async => throw StateError('disco'));
    expect(h.containsKey('X-Aparato-Id'), isFalse);
  });

  test('la huella sale con el id y el nombre', () async {
    final huella = huellaDe('9774d56d682e549c');
    final h = await cabeceras(id: () async => _v7, huella: () async => huella);
    expect(h['X-Aparato-Huella'], huella);
  });

  test('la huella es EXACTAMENTE sha256("procovar:" + id) en hexadecimal', () {
    // El mismo cálculo que hace el CRM: si estos dos difieren, Accesos no junta nada.
    expect(
      huellaDe('9774d56d682e549c'),
      '9e73f291146144e99441d0e2d3be12dd012f004fa7906cb6c1f1840cb39828ba',
    );
    expect(huellaDe('x'), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('sin huella (web o no se pudo leer) el id sale igual', () async {
    final h = await cabeceras(id: () async => _v7);
    expect(h['X-Aparato-Id'], _v7);
    expect(h.containsKey('X-Aparato-Huella'), isFalse);
  });

  test('sin nombre NO pone la cabecera de nombre (ni la pone vacía)', () async {
    final h = await cabeceras(id: () async => _v7, nombre: () async => null);
    expect(h.containsKey('X-Aparato-Nombre'), isFalse);
  });

  test(
    'un id, nombre o huella COLGADOS no dejan sin salir la petición',
    () async {
      late PeticionVista visto;
      final servidor = ServidorFalso((p) async {
        visto = p;
        return RespuestaFalsa(200);
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
        ..httpClientAdapter = servidor
        ..interceptors.add(
          InterceptorDeAparato(
            id: () async => _v7,
            nombre: () => Completer<String?>().future, // no termina nunca
            huella: () async => 'a' * 64,
            plazo: const Duration(milliseconds: 200),
          ),
        );
      await dio.post('/refresh').timeout(const Duration(seconds: 3));
      expect(visto.ruta, endsWith('/refresh'));
      expect(visto.cabeceras.containsKey('X-Aparato-Id'), isFalse);
    },
  );

  group('el id de la instalación', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('aparato_id_'));
    tearDown(() => tmp.deleteSync(recursive: true));
    Future<File> fichero() async => File('${tmp.path}/aparato-id');

    test('se crea UNA vez como v7 y es estable', () async {
      final a = await leerOCrearId(fichero);
      final b = await leerOCrearId(fichero);
      expect(
        a,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab]')),
      );
      expect(b, a);
    });

    test(
      'un fichero corrupto, vacío o con un v4 se regenera como v7',
      () async {
        for (final malo in [
          'basura\x00',
          '',
          'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        ]) {
          await File('${tmp.path}/aparato-id').writeAsString(malo);
          final id = await leerOCrearId(fichero);
          expect(id, matches(RegExp(r'-7[0-9a-f]{3}-')), reason: 'con «$malo»');
          expect(id, isNot('f47ac10b-58cc-4372-a567-0e02b2c3d479'));
        }
      },
    );

    test('si no hay carpeta, no lanza: devuelve null', () async {
      final id = await leerOCrearId(
        () async => File('${tmp.path}/no-existe/aparato-id'),
      );
      expect(id, isNull);
    });
  });

  group('el nombre en la cabecera', () {
    test(
      'quita saltos de línea y lo no ASCII, pero no las letras con tilde',
      () {
        expect(
          nombreParaCabecera('MÁQUINA de Ñandú\r\nX'),
          'MAQUINA de Nandu X'.replaceAll(' X', 'X'),
        );
        expect(nombreParaCabecera('Samsung\tA14\u{1F600}'), 'SamsungA14');
      },
    );
  });
}
