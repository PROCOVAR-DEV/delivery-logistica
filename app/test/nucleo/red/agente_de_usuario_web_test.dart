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
// Se corre a mano (el `@TestOn('browser')` la deja fuera del `flutter test` de la
// maquina virtual, y por eso no entra en `./comprobar.sh`). Chrome sin ventana,
// sin red a ningun dominio de Procovar (el Dio habla con un adaptador falso):
//
//     CHROME_EXECUTABLE=/usr/bin/google-chrome-stable timeout 300 \
//       flutter test --platform chrome test/nucleo/red/agente_de_usuario_web_test.dart
//
// Hay que lanzarla al tocar `agente_de_usuario.dart`.
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
      // Sin parametros: el cableado que va a produccion, `kIsWeb` de verdad. Si
      // intentara leer la version (`PackageInfo`) ya habria puesto la cabecera.
      ..interceptors.add(InterceptorDeAgente());

    await dio.post<Object?>('/token', data: <String, Object?>{});

    expect(servidor.vistas, hasLength(1));
    expect(
      servidor.vistas.single.cabeceras.containsKey('User-Agent'),
      isFalse,
      reason: 'el navegador pone el suyo; el nuestro rompe CORS (preflight)',
    );
  });
}
