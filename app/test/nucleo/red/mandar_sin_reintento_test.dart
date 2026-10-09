// UNA ORDEN DE UNA PERSONA NO SE REPITE SOLA (`ClienteApi.mandar(reintentar:)`).
//
// `ClienteApi` reintenta lo que es red o 5xx, y para la cola de subida es lo
// correcto (cada apunte lleva su clave y el servidor lo reconoce). Pero «aplicar»
// de la bandeja del revisor es una ORDEN: un 502 `reparto_no_disponible` quiere
// decir «el reparto no contesto, vuelve a intentarlo TU», y repetirlo a
// escondidas es aplicar otra vez sin que nadie lo decida (y tras un 500
// `no_se_pudo_anotar` ni se sabe si ya se aplico). Va EN PAREJA: sin la bandera,
// el comportamiento de siempre.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../../apoyo/servidor_falso.dart';

void main() {
  const sesion = Sesion(token: 'tok', refresh: 'r0', sub: 'u1');

  ({ClienteApi cliente, ServidorFalso servidor}) montar() {
    final servidor = ServidorFalso(
      (_) async => RespuestaFalsa(502, {
        'error': 'El reparto no está disponible.',
        'codigo': 'reparto_no_disponible',
      }),
    );
    final almacen = AlmacenEnMemoria(sesion);
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
      ..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://sync.test/sync',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;
    return (cliente: cliente, servidor: servidor);
  }

  test('reintentar: false — un 502 sale a la PRIMERA, con su codigo y su '
      'literal', () async {
    final m = montar();

    await expectLater(
      m.cliente.mandar<Object?>(
        'POST',
        '/revision/a/c/aplicar',
        null,
        reintentar: false,
      ),
      throwsA(
        isA<FalloDeRed>()
            .having((f) => f.codigo, 'codigo', 502)
            .having(
              (f) => f.detalle,
              'detalle',
              'El reparto no está disponible.',
            ),
      ),
    );

    expect(m.servidor.vistas, hasLength(1));
  });

  test(
    'EN PAREJA: por defecto un 5xx se reintenta (cuatro intentos)',
    () async {
      final m = montar();

      await expectLater(
        m.cliente.mandar<Object?>('POST', '/x', null),
        throwsA(isA<FalloDeRed>()),
      );

      expect(m.servidor.vistas, hasLength(4));
    },
  );
}
