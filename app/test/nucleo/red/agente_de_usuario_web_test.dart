// EL `User-Agent` PROPIO NO SALE EN LA WEB, ejecutado en un navegador de verdad.
//
// En la maquina virtual `kIsWeb` es siempre falso, asi que `plataformaParaElAgente`
// (`kIsWeb` + `defaultTargetPlatform`) solo puede probarse por su lado no-web
// y quitar la guarda salia en verde (auditoria del 08/10/2026, mutacion A2). Las
// dos ramas de la decision estan en `agente_de_usuario_test.dart` (funcion pura);
// ESTA prueba cierra lo unico que la pura no ve: que el cableado de verdad pasa
// `kIsWeb` y que el interceptor por defecto no pone cabecera en un navegador.
// Si saliera, `User-Agent` no es cabecera segura de CORS y el navegador añadiria
// un preflight al login de Accesos.
//
// Se corre desde `./comprobar.sh` (bloque «chrome (web)») si hay Chrome, y a mano con (el
// `@TestOn('browser')` la deja fuera del `flutter test` de la maquina virtual). Chrome sin ventana,
// sin red a ningun dominio de Procovar (el Dio habla con un adaptador falso):
//
//     CHROME_EXECUTABLE=/usr/bin/google-chrome-stable timeout 300 \
//       flutter test --platform chrome test/nucleo/red/agente_de_usuario_web_test.dart
//
// Hay que lanzarla al tocar `agente_de_usuario.dart`.
//
// QUE CUBRE CADA PRUEBA (re-auditoria 09/10/2026: la segunda era vacua):
//  1. `plataformaParaElAgente()` con `kIsWeb` de verdad -> `null`. Caza `esWeb: false` puesto a mano
//     o quitar `kIsWeb` del cableado: en Chrome `defaultTargetPlatform` es `linux`, saldria «Linux».
//  2. El `InterceptorDeAgente()` POR DEFECTO, de punta a punta, no pone la cabecera. Caza que el
//     interceptor deje de usar `plataformaParaElAgente` por defecto (p. ej. se le cuela una plataforma
//     fija). Se le da una VERSION de mentira: antes leia `PackageInfo`, que en un navegador de prueba
//     falla, el interceptor se tragaba el error y NUNCA ponia la cabecera, con la guarda rota o sin
//     ella, o sea que no comprobaba nada.
@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/agente_de_usuario.dart';

import '../../apoyo/servidor_falso.dart';

void main() {
  test('en el navegador `kIsWeb` es cierto y NO hay plataforma que decir', () {
    expect(kIsWeb, isTrue, reason: 'esto solo vale dentro de un navegador');
    expect(plataformaParaElAgente(), isNull);
  });

  test('el interceptor POR DEFECTO no pone User-Agent en el navegador', () async {
    final servidor = ServidorFalso((p) async => RespuestaFalsa(200));
    final dio = Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
      ..httpClientAdapter = servidor
      // La plataforma, POR DEFECTO: el cableado que va a produccion, `kIsWeb` de verdad. La version
      // es de mentira (ver arriba): si la guarda fallara, la cabecera SALDRIA y esta prueba lo veria.
      ..interceptors.add(InterceptorDeAgente(version: () async => '9.9.9'));

    await dio.post<Object?>('/token', data: <String, Object?>{});

    expect(servidor.vistas, hasLength(1));
    expect(
      servidor.vistas.single.cabeceras.containsKey('User-Agent'),
      isFalse,
      reason: 'el navegador pone el suyo; el nuestro rompe CORS (preflight)',
    );
  });
}
