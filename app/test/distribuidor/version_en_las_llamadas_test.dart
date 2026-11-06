// X-App-Version: SOLO en «Reparto Distribuidor», con el formato `versionName+versionCode`.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reparto/distribuidor/modo_distribuidor.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/version_de_la_app.dart';

import '../apoyo/servidor_falso.dart';

void main() {
  const sesion = Sesion(token: 'tok', refresh: 'r0', sub: 'u1');

  Future<Map<String, Object?>> cabecerasDe({required bool distribuidor}) async {
    PackageInfo.setMockInitialValues(
      appName: 'Reparto',
      packageName: 'cloud.procovar.reparto',
      version: '1.0.0',
      buildNumber: '57',
      buildSignature: '',
    );
    final servidor = ServidorFalso((p) async => RespuestaFalsa(200, const {}));
    final almacen = AlmacenEnMemoria(sesion);
    final cliente = ClienteApi.montar(
      baseUrl: 'https://api.test',
      almacen: almacen,
      renovador: Renovador(
        Dio(BaseOptions(baseUrl: 'https://auth.test'))
          ..httpClientAdapter = servidor,
        almacen,
      ),
      conVersionDeLaApp: distribuidor,
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;
    await cliente.pedir<Map<String, Object?>>('/api/routes');
    await cliente.mandar<Object?>('POST', '/api/track', const {'puntos': []});
    expect(servidor.vistas, hasLength(2));
    return {
      for (final (i, v) in servidor.vistas.indexed)
        '$i': v.cabeceras['X-App-Version'],
    };
  }

  test('el distribuidor la manda en CADA llamada, como 1.0.0+57', () async {
    expect(await cabecerasDe(distribuidor: true), {
      '0': '1.0.0+57',
      '1': '1.0.0+57',
    });
  });

  test('Reparto de siempre NO la manda', () async {
    expect(await cabecerasDe(distribuidor: false), {'0': null, '1': null});
  });

  test('el cableado: los clientes del modo distribuidor la llevan y los de Reparto no', () {
    bool lleva(ProviderContainer c, Provider<ClienteApi> p) =>
        c.read(p).dio.interceptors.any((i) => i is InterceptorDeVersion);
    for (final modo in [true, false]) {
      final c = ProviderContainer(
        overrides: [
          modoDistribuidorProvider.overrideWithValue(modo),
          almacenSesionProvider.overrideWithValue(AlmacenEnMemoria(sesion)),
        ],
      );
      addTearDown(c.dispose);
      for (final p in [
        clienteApiProvider,
        clienteSyncProvider,
        clienteVersionProvider,
      ]) {
        expect(lleva(c, p), modo, reason: '$p con modo distribuidor = $modo');
      }
    }
  });
}
