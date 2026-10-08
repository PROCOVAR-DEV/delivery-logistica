// «NO TIENES PERMISO PARA ENTRAR A REPARTO» — la detección y la cola.
//
// Solo ADMINISTRADOR, SUPER ADMIN, DESARROLLADOR y LOGISTICO entran a Reparto. Al resto
// la API le contesta 403 con `{"error": …, "codigo": "sin_permiso_reparto"}` en CUALQUIER
// llamada. Dos cosas que no pueden pasar:
//
//  1. que ese 403 se confunda con los otros (alcance de sucursal: sin `codigo`), que
//     siguen siendo un rechazo normal;
//  2. que la cola de esa persona se convierta en rechazos. Es la PERSONA la que no entra,
//     no el apunte: marcar el apunte `rechazado` destruiría su trabajo. Debe quedar
//     `pendiente` e intacto, como con un 401 (`docs/sin-permiso.md`).
//
// Van en pareja (CLAUDE.md §5): cada «dispara» tiene su «NO dispara».

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/red/interceptor_sesion.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../../apoyo/apoyo_accesos.dart';
import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

/// Lo que escribe el servidor (contrato con el agente API).
const _sinPermiso = <String, Object?>{
  'error': 'No tienes permiso para entrar a Reparto.',
  'codigo': 'sin_permiso_reparto',
};

void main() {
  const sesion = Sesion(token: 'tok', refresh: 'r0', sub: 'u1');

  ({ClienteApi cliente, List<int> avisos}) montarCliente(
    Future<RespuestaFalsa?> Function(PeticionVista) responder, {
    AlmacenEnMemoria? almacen,
    String baseUrl = 'https://api.test',
    ServidorFalso? servidor,
    List<int>? avisos,
  }) {
    final falso = servidor ?? ServidorFalso(responder);
    final alm = almacen ?? AlmacenEnMemoria(sesion);
    avisos ??= <int>[];
    final cliente = ClienteApi.montar(
      baseUrl: baseUrl,
      almacen: alm,
      renovador: Renovador(Dio()..httpClientAdapter = falso, alm),
      alFaltarPermiso: () => avisos!.add(1),
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = falso;
    return (cliente: cliente, avisos: avisos);
  }

  group('el interceptor: detecta ESE 403 y solo ese', () {
    test(
      '403 con codigo sin_permiso_reparto: avisa UNA vez y sale como Rechazo '
      'con su marca',
      () async {
        final m = montarCliente((p) async => RespuestaFalsa(403, _sinPermiso));

        final fallo = await m.cliente
            .pedir<Map<String, Object?>>('/orders')
            .then<Object>((_) => 'no fallo', onError: (Object e) => e);

        expect(m.avisos, hasLength(1));
        expect(fallo, isA<Rechazo>());
        expect((fallo as Rechazo).codigo, 403);
        expect(fallo.marca, marcaSinPermisoDeReparto);
        expect(fallo.mensaje, 'No tienes permiso para entrar a Reparto.');
      },
    );

    test(
      '403 SIN codigo (alcance de sucursal): Rechazo normal, no avisa',
      () async {
        final m = montarCliente(
          (p) async => RespuestaFalsa(403, <String, Object?>{
            'error': 'Esa sucursal no es la tuya.',
          }),
        );

        await expectLater(
          m.cliente.pedir<Map<String, Object?>>('/orders'),
          throwsA(isA<Rechazo>().having((r) => r.marca, 'marca', isNull)),
        );
        expect(
          m.avisos,
          isEmpty,
          reason: 'no es el 403 de «no entras a Reparto»',
        );
      },
    );

    test('403 con OTRO codigo: no avisa', () async {
      final m = montarCliente(
        (p) async => RespuestaFalsa(403, <String, Object?>{
          'error': 'La cuenta no tiene sucursal.',
          'codigo': 'sin_sucursal',
        }),
      );

      await expectLater(
        m.cliente.pedir<Map<String, Object?>>('/orders'),
        throwsA(isA<Rechazo>()),
      );
      expect(m.avisos, isEmpty);
    });

    test(
      'el MISMO codigo con un 401 no avisa: un 401 es sesion, no permiso',
      () async {
        // Sin sesion guardada el 401 acaba directo en `SesionMuerta`.
        final m = montarCliente(
          (p) async => RespuestaFalsa(401, _sinPermiso),
          almacen: AlmacenEnMemoria(),
        );

        await expectLater(
          m.cliente.pedir<Map<String, Object?>>('/orders'),
          throwsA(isA<SesionMuerta>()),
        );
        expect(m.avisos, isEmpty);
      },
    );

    test('401, renovación y reintento con 403: avisa UNA vez, da Rechazo y no '
        'mata la sesión', () async {
      var avisos = 0;
      var muertes = 0;
      var llamadas = 0;
      final almacen = AlmacenEnMemoria(sesion);
      final falso = ServidorFalso((p) async {
        if (p.ruta.contains('refresh')) {
          return RespuestaFalsa(200, parDeTokens());
        }
        llamadas++;
        return llamadas == 1
            ? RespuestaFalsa(401, const <String, Object?>{})
            : RespuestaFalsa(403, _sinPermiso);
      });
      final cliente = ClienteApi.montar(
        baseUrl: 'https://api.test',
        almacen: almacen,
        renovador: Renovador(Dio()..httpClientAdapter = falso, almacen),
        alFaltarPermiso: () => avisos++,
        alMorirLaSesion: () => muertes++,
        esperar: (_) async {},
      );
      cliente.dio.httpClientAdapter = falso;

      await expectLater(
        cliente.pedir<Map<String, Object?>>('/orders'),
        throwsA(
          isA<Rechazo>().having(
            (r) => r.marca,
            'marca',
            marcaSinPermisoDeReparto,
          ),
        ),
      );

      expect(muertes, 0, reason: 'el permiso no mata la sesión');
      expect(avisos, 1);
      expect(llamadas, 2, reason: 'una vez, y el reintento tras renovar');
    });

    test('un 200 y un 409 con codigo no avisan', () async {
      final bien = montarCliente((p) async => RespuestaFalsa(200, const {}));
      await bien.cliente.pedir<Map<String, Object?>>('/orders');
      expect(bien.avisos, isEmpty);

      final otro = montarCliente((p) async => RespuestaFalsa(409, _sinPermiso));
      await expectLater(
        otro.cliente.pedir<Map<String, Object?>>('/orders'),
        throwsA(isA<Rechazo>()),
      );
      expect(otro.avisos, isEmpty, reason: 'solo el 403');
    });

    test('el 403 de un proxy (no es JSON de nuestra API) no cuenta', () {
      Response<dynamic> r(String tipo, Object? cuerpo, [int codigo = 403]) =>
          Response<dynamic>(
            requestOptions: RequestOptions(),
            statusCode: codigo,
            data: cuerpo,
            headers: Headers.fromMap({
              Headers.contentTypeHeader: [tipo],
            }),
          );

      expect(esSinPermisoDeReparto(r('application/json', _sinPermiso)), isTrue);
      expect(esSinPermisoDeReparto(r('text/html', _sinPermiso)), isFalse);
      expect(
        esSinPermisoDeReparto(r('application/json', _sinPermiso, 401)),
        isFalse,
      );
      expect(
        esSinPermisoDeReparto(r('application/json', 'sin_permiso_reparto')),
        isFalse,
      );
      expect(esSinPermisoDeReparto(null), isFalse);
    });
  });

  group('la web: /api/me con ese 403 no manda a Accesos (bucle)', () {
    test(
      '403 sin_permiso_reparto: SinPermiso, no NoHaySesion ni NoContesta',
      () async {
        final entrada = entradaFalsa(
          NavegadorFalso(),
          (p) async => RespuestaFalsa(403, _sinPermiso),
        );
        expect(await entrada.quienSoy(), isA<SinPermiso>());
      },
    );

    test('PAREJA: un 403 sin codigo sigue siendo «no contesta», y un 401 «no hay sesion»', () async {
      final sinCodigo = entradaFalsa(
        NavegadorFalso(),
        (p) async => RespuestaFalsa(403, <String, Object?>{'error': 'no'}),
      );
      expect(await sinCodigo.quienSoy(), isA<NoContesta>());

      final sinSesion = entradaFalsa(
        NavegadorFalso(),
        (p) async => RespuestaFalsa(401, <String, Object?>{'user': null}),
      );
      expect(await sinSesion.quienSoy(), isA<NoHaySesion>());
    });
  });

  group('la cola: ese 403 no es un rechazo del apunte', () {
    late BaseLocal base;
    late ColaDeSalida cola;

    setUp(() {
      base = baseDePrueba();
      cola = ColaDeSalida(
        base,
        reloj: RelojFalso(DateTime(2026, 10, 8, 9)).leer,
      );
    });
    setUp(() => aparatoYaDeAlta(base));
    tearDown(() => base.close());

    ({Subida subida, List<int> avisos, ServidorFalso servidor}) montar(
      Future<RespuestaFalsa?> Function(PeticionVista) responder,
    ) {
      final servidor = ServidorFalso(responder);
      // Los dos sitios que pueden avisar (el interceptor y la segunda cerradura
      // de la subida) cuentan en la MISMA lista.
      final avisos = <int>[];
      final m = montarCliente(
        responder,
        baseUrl: 'https://sync.test',
        servidor: servidor,
        avisos: avisos,
      );
      return (
        subida: Subida(
          cliente: m.cliente,
          cola: cola,
          aparato: IdentidadDelAparato(base, sync: m.cliente),
          base: base,
          quienEsta: () async => 'u1',
          alFaltarPermiso: () => avisos.add(1),
        ),
        avisos: avisos,
        servidor: servidor,
      );
    }

    Future<String> unCierre() => cola.encolar(
      metodo: 'PATCH',
      ruta: '/routes/r-1',
      cuerpo: <String, Object?>{'status': 'completed'},
    );

    test(
      'PAREJA 1 — un rechazo NORMAL del apunte sigue siendo Rechazo',
      () async {
        final clave = await unCierre();
        final m = montar(
          (p) async => RespuestaFalsa(200, <String, Object?>{
            'resultados': [
              <String, Object?>{
                'clave': clave,
                'estado': 'rechazado',
                'motivo': 'Ese pedido ya va en otra ruta.',
              },
            ],
          }),
        );

        expect(await m.subida.ciclo(), 0);

        final apunte = (await cola.porClave(clave))!;
        expect(apunte.estado, EstadoApunte.rechazado);
        expect(apunte.motivo, 'Ese pedido ya va en otra ruta.');
      },
    );

    test('PAREJA 2 — el 403 sin_permiso_reparto deja el apunte PENDIENTE e '
        'INTACTO, y no se reintenta en bucle', () async {
      final clave = await unCierre();
      final antes = (await cola.porClave(clave))!;
      var subidas = 0;
      final m = montar((p) async {
        subidas++;
        return RespuestaFalsa(403, _sinPermiso);
      });

      await expectLater(
        m.subida.ciclo(),
        throwsA(
          isA<Rechazo>().having(
            (r) => r.marca,
            'marca',
            marcaSinPermisoDeReparto,
          ),
        ),
      );

      final despues = (await cola.porClave(clave))!;
      expect(despues.estado, EstadoApunte.pendiente, reason: 'NO se rechaza');
      expect(despues.motivo, isNull, reason: 'sin motivo de rechazo puesto');
      expect(despues.ruta, antes.ruta);
      expect(despues.metodo, antes.metodo);
      expect(despues.cuerpo, antes.cuerpo);
      expect(subidas, 1, reason: 'una peticion, no un bucle');
      expect(m.avisos, hasLength(1), reason: 'el portero se entera');
    });

    test(
      'PAREJA 2b — el rechazo «sin permiso» DENTRO de un 200 (lo que hoy hace '
      'el sync) tampoco resuelve el apunte',
      () async {
        final clave = await unCierre();
        final m = montar(
          (p) async => RespuestaFalsa(200, <String, Object?>{
            'resultados': [
              <String, Object?>{
                'clave': clave,
                'estado': 'rechazado',
                'motivo': 'No tienes permiso para entrar a Reparto.',
              },
            ],
          }),
        );

        await expectLater(m.subida.ciclo(), throwsA(isA<Rechazo>()));

        expect((await cola.porClave(clave))!.estado, EstadoApunte.pendiente);
        expect((await cola.porClave(clave))!.motivo, isNull);
        expect(m.avisos, hasLength(1));
      },
    );

    test('un 403 a MITAD de cola: el primero queda aplicado, el segundo y el '
        'tercero pendientes e intactos, y se para (2 peticiones)', () async {
      final claves = <String>[
        for (var i = 0; i < 3; i++)
          await cola.encolar(
            metodo: 'PATCH',
            ruta: '/orders/o$i',
            cuerpo: <String, Object?>{'x': i},
          ),
      ];
      var n = 0;
      final m = montar((p) async {
        n++;
        return n == 1
            ? RespuestaFalsa(200, <String, Object?>{
                'resultados': [
                  <String, Object?>{'clave': claves[0], 'estado': 'aplicado'},
                ],
              })
            : RespuestaFalsa(403, _sinPermiso);
      });

      await expectLater(m.subida.ciclo(), throwsA(isA<Rechazo>()));

      expect((await cola.porClave(claves[0]))!.estado, EstadoApunte.aplicado);
      expect((await cola.porClave(claves[1]))!.estado, EstadoApunte.pendiente);
      expect((await cola.porClave(claves[2]))!.estado, EstadoApunte.pendiente);
      expect(
        m.servidor.vistas,
        hasLength(2),
        reason: 'no sigue con el tercero',
      );
      expect(m.avisos, hasLength(1));
    });

    test('un 403 de alcance (sin codigo) en TODA la peticion tampoco rechaza '
        'el apunte, y no avisa al portero', () async {
      final clave = await unCierre();
      final m = montar(
        (p) async => RespuestaFalsa(403, <String, Object?>{
          'error': 'Esa sucursal no es la tuya.',
        }),
      );

      await expectLater(m.subida.ciclo(), throwsA(isA<Rechazo>()));

      expect((await cola.porClave(clave))!.estado, EstadoApunte.pendiente);
      expect(m.avisos, isEmpty);
    });
  });
}
