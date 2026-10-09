// EL `User-Agent` DE LA APK Y EL ESCRITORIO — 08/10/2026.
//
// Accesos enseña el aparato en «Dispositivos y sesiones» a partir de esta
// cabecera. El de Dart no dice la plataforma; el nuestro sí:
// `ProcovarReparto/<versión> (<plataforma>)`.
//
// En pareja (CLAUDE.md §3-quinquies): en la APK y el escritorio SALE en las tres
// peticiones de Accesos; en la web NO sale (el navegador pone el suyo).

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/agente_de_usuario.dart';

import '../../apoyo/servidor_falso.dart';

/// El parser de Accesos, solo lectura: NO se toca desde aquí.
const _parserDeAccesos = '/mnt/datos/Work/procovar/auth/src/lib';

void main() {
  /// Un Dio de auth de mentira con el interceptor, y el servidor que lo ve todo.
  (Dio, ServidorFalso) montar({
    String? plataforma,
    String? Function()? deDonde,
    String version = '1.0.30',
  }) {
    final servidor = ServidorFalso((p) async => RespuestaFalsa(200));
    final dio = Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
      ..httpClientAdapter = servidor
      ..interceptors.add(
        InterceptorDeAgente(
          version: () async => version,
          plataforma: deDonde ?? () => plataforma,
        ),
      );
    return (dio, servidor);
  }

  group('el formato', () {
    test('es exactamente ProcovarReparto/<version> (<plataforma>)', () {
      expect(
        agenteDeReparto('1.0.30', 'Android'),
        'ProcovarReparto/1.0.30 (Android)',
      );
      expect(
        agenteDeReparto('2.1.0', 'Windows'),
        'ProcovarReparto/2.1.0 (Windows)',
      );
    });

    test('PURA: fuera de la web cada destino dice la suya', () {
      const dicho = {
        TargetPlatform.android: 'Android',
        TargetPlatform.windows: 'Windows',
        TargetPlatform.linux: 'Linux',
        TargetPlatform.macOS: 'macOS',
        TargetPlatform.iOS: 'iOS',
        TargetPlatform.fuchsia: null,
      };
      for (final d in TargetPlatform.values) {
        expect(
          plataformaDelAgente(esWeb: false, destino: d),
          dicho[d],
          reason: '$d',
        );
      }
    });

    test('PURA, rama web: con esWeb el destino da igual, NUNCA hay plataforma '
        '(la guarda que `kIsWeb` no deja ejecutar en la maquina virtual)', () {
      for (final d in TargetPlatform.values) {
        expect(
          plataformaDelAgente(esWeb: true, destino: d),
          isNull,
          reason:
              '$d en la web: el User-Agent no es cabecera segura de CORS y '
              'metería un preflight al login de Accesos',
        );
      }
    });

    test(
      'en la maquina virtual `kIsWeb` es falso y hay plataforma que decir',
      () {
        expect(kIsWeb, isFalse);
        expect(plataformaParaElAgente(), isNotNull);
      },
    );
  });

  group('en la APK y el escritorio sale en las tres peticiones de Accesos', () {
    test('/token, /refresh y /logout llevan el User-Agent propio', () async {
      final (dio, servidor) = montar(plataforma: 'Android');

      await dio.post<Object?>('/token', data: <String, Object?>{});
      await dio.post<Object?>('/refresh', data: <String, Object?>{});
      await dio.post<Object?>('/logout', data: <String, Object?>{});

      expect(servidor.vistas, hasLength(3));
      for (final v in servidor.vistas) {
        expect(
          v.cabeceras['User-Agent'],
          'ProcovarReparto/1.0.30 (Android)',
          reason: '${v.metodo} ${v.ruta} salio sin el agente de Reparto',
        );
      }
    });

    test('cada plataforma pone la suya', () async {
      for (final p in ['Android', 'Windows', 'Linux']) {
        final (dio, servidor) = montar(plataforma: p);
        await dio.post<Object?>('/token', data: <String, Object?>{});
        expect(
          servidor.vistas.single.cabeceras['User-Agent'],
          'ProcovarReparto/1.0.30 ($p)',
        );
      }
    });

    test('el Dio de Accesos de VERDAD lleva el interceptor', () {
      final c = ProviderContainer.test();
      expect(
        c.read(dioAuthProvider).interceptors.whereType<InterceptorDeAgente>(),
        hasLength(1),
        reason:
            'sin esto el login, el refresh y el logout salen con el '
            '`Dart/3.x` de siempre y Accesos no distingue Android de Windows',
      );
    });
  });

  group('PAREJA: donde no se manda, no se manda', () {
    test(
      'la pareja del anterior: esWeb falso, mismo destino, SI sale',
      () async {
        final (dio, servidor) = montar(
          deDonde: () => plataformaDelAgente(
            esWeb: false,
            destino: TargetPlatform.android,
          ),
        );

        await dio.post<Object?>('/token', data: <String, Object?>{});

        expect(
          servidor.vistas.single.cabeceras['User-Agent'],
          'ProcovarReparto/1.0.30 (Android)',
        );
      },
    );

    test('en la web NO se pone ninguna cabecera User-Agent', () async {
      // La rama web DE VERDAD: `esWeb: true` pasa por `plataformaDelAgente`, en
      // un destino que SI tiene plataforma fuera de la web. Con la guarda
      // quitada, esto sale como `(Android)` y la prueba se pone roja.
      final (dio, servidor) = montar(
        deDonde: () =>
            plataformaDelAgente(esWeb: true, destino: TargetPlatform.android),
      );

      await dio.post<Object?>('/token', data: <String, Object?>{});

      expect(
        servidor.vistas.single.cabeceras.containsKey('User-Agent'),
        isFalse,
        reason:
            'el navegador no deja a un script tocar el User-Agent, y '
            'ponerlo rompe CORS',
      );
    });

    test(
      'si no se puede leer la version, la peticion sale igual y sin agente',
      () async {
        final servidor = ServidorFalso((p) async => RespuestaFalsa(200));
        final dio = Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
          ..httpClientAdapter = servidor
          ..interceptors.add(
            InterceptorDeAgente(
              version: () async => throw StateError('sin plugin'),
              plataforma: () => 'Android',
            ),
          );

        await dio.post<Object?>('/refresh', data: <String, Object?>{});

        expect(
          servidor.vistas,
          hasLength(1),
          reason: 'renovar tiene que salir',
        );
        expect(
          servidor.vistas.single.cabeceras.containsKey('User-Agent'),
          isFalse,
        );
      },
    );
  });

  group('Accesos lo entiende (su parser de verdad, solo lectura)', () {
    final hay =
        File('$_parserDeAccesos/agente-de-usuario.ts').existsSync() &&
        File('$_parserDeAccesos/desde-donde.ts').existsSync() &&
        Process.runSync('node', ['--version']).exitCode == 0;

    test(
      'Android, Windows y Linux salen como «App de Reparto en <sistema>»',
      () async {
        final tmp = Directory.systemTemp.createTempSync('agente_accesos');
        addTearDown(() => tmp.deleteSync(recursive: true));
        File('$_parserDeAccesos/desde-donde.ts')
            .copySync('${tmp.path}/desde-donde.ts');
        File('${tmp.path}/agente.ts').writeAsStringSync(
          File('$_parserDeAccesos/agente-de-usuario.ts')
              .readAsStringSync()
              .replaceAll("'@/lib/desde-donde'", "'./desde-donde.ts'"),
        );
        File('${tmp.path}/run.mts').writeAsStringSync(
          "import { describirAgente } from './agente.ts';\n"
          'console.log(JSON.stringify(process.argv.slice(2).map(describirAgente)));\n',
        );

        const sistemas = ['Android', 'Windows', 'Linux'];
        final r = await Process.run('node', [
          '${tmp.path}/run.mts',
          for (final s in sistemas) agenteDeReparto('1.0.30', s),
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');

        final dicho = (jsonDecode(r.stdout as String) as List<Object?>)
            .cast<Map<String, Object?>>();
        for (var i = 0; i < sistemas.length; i++) {
          expect(dicho[i]['texto'], 'App de Reparto en ${sistemas[i]}');
          expect(dicho[i]['tipo'], 'aparato');
          expect(dicho[i]['navegador'], isNull);
        }
      },
      skip: hay
          ? false
          : 'no estan el parser de Accesos o node en esta maquina',
    );
  });
}
