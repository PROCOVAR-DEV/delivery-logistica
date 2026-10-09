// EL BEARER EXPLICITO: la web habla con `sync` con el token de `/api/me` y
// NUNCA con la cookie (`docs/bandeja-de-revision.md` B.6, `ClienteApi`).
//
// `sync` solo lee `Authorization: Bearer` (`DeToken`). La web, por defecto, manda
// la cookie del login unico (`withCredentials`); si el cliente de la bandeja
// hiciera lo mismo, `sync` contestaria 401 y el portero rebotaria a Accesos en
// bucle (los treinta `GET /sync/estado` del 22/09/2026). En la maquina virtual
// `kIsWeb` es falso siempre, asi que la rama web se ejercita con `esWeb: true`.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

import '../../apoyo/servidor_falso.dart';

void main() {
  const delAlmacen = Sesion(token: 'tok-almacen', refresh: 'r0', sub: 'u1');

  /// Monta un cliente de `sync` contra un servidor falso que apunta las
  /// opciones con las que SALIO cada peticion (`extra` incluido).
  ({ClienteApi cliente, List<RequestOptions> salidas}) montar({
    required Future<String?> Function()? bearerExplicito,
    required bool esWeb,
    Sesion? almacenado = delAlmacen,
  }) {
    final salidas = <RequestOptions>[];
    final servidor = ServidorFalso((_) async => RespuestaFalsa(200, const {}));
    final almacen = AlmacenEnMemoria(almacenado);
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
      ..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://sync.test/sync',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      bearerExplicito: bearerExplicito,
      esWeb: esWeb,
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;
    cliente.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          salidas.add(o);
          h.next(o);
        },
      ),
    );
    return (cliente: cliente, salidas: salidas);
  }

  test('en la web, con bearer explicito: sale con ESE token y SIN cookie', () async {
    final m = montar(bearerExplicito: () async => 'del-api-me', esWeb: true);
    await m.cliente.pedir<Map<String, Object?>>('/revision');

    final salida = m.salidas.single;
    expect(salida.headers['Authorization'], 'Bearer del-api-me');
    // El token del almacen NO se usa: manda el que se dijo a mano.
    expect(salida.headers['Authorization'], isNot('Bearer tok-almacen'));
    // Y la cookie no viaja: `withCredentials` ni existe.
    expect(salida.extra['withCredentials'], isNot(true));
  });

  test('EN PAREJA: sin bearer explicito la web SI manda la cookie '
      '(lo de siempre no cambia)', () async {
    final m = montar(bearerExplicito: null, esWeb: true);
    await m.cliente.pedir<Map<String, Object?>>('/api/orders');

    expect(m.salidas.single.extra['withCredentials'], isTrue);
    expect(m.salidas.single.headers['Authorization'], 'Bearer tok-almacen');
  });

  test('si no hay token a mano NO se cae a la cookie: sale sin cabecera y sin '
      'cookie', () async {
    final m = montar(bearerExplicito: () async => null, esWeb: true);
    await m.cliente.pedir<Map<String, Object?>>('/revision');

    expect(m.salidas.single.headers.containsKey('Authorization'), isFalse);
    expect(m.salidas.single.extra['withCredentials'], isNot(true));
  });

  test('en la APK y el escritorio el cliente de siempre no cambia', () async {
    final m = montar(bearerExplicito: null, esWeb: false);
    await m.cliente.pedir<Map<String, Object?>>('/revision');

    expect(m.salidas.single.headers['Authorization'], 'Bearer tok-almacen');
    expect(m.salidas.single.extra['withCredentials'], isNot(true));
  });
}
