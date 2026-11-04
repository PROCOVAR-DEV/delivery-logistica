// «SIN LOGIN»: el enlace de la ruta, el dispositivo y su acceso. Contra un doble del
// servidor (el servidor de verdad lo hace otra sesion): `POST /api/d/reclamar` y
// `POST /api/d/renovar`, SIN Authorization.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/distribuidor/dispositivo/anadir_ruta.dart';
import 'package:reparto/distribuidor/dispositivo/cliente_de_dispositivo.dart';
import 'package:reparto/distribuidor/dispositivo/enlace_de_ruta.dart';
import 'package:reparto/distribuidor/dispositivo/renovador_de_dispositivo.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../apoyo/apoyo_sesion.dart';
import '../apoyo/servidor_falso.dart';

void main() {
  const token = 'abcDEF123456_-xyz';

  group('el enlace', () {
    test('se saca el token de la URL, de la ruta interna o pegado a secas', () {
      expect(tokenDelEnlace('https://reparto.procovar.cloud/r/$token'), token);
      expect(
        tokenDelEnlace('  https://reparto.procovar.cloud/r/$token/?x=1 '),
        token,
      );
      expect(tokenDelEnlace('/r/$token'), token);
      expect(tokenDelEnlace(token), token);
    });

    test('lo que no es de Reparto no vale', () {
      expect(tokenDelEnlace('https://otro.sitio/r/$token'), isNull);
      expect(
        tokenDelEnlace('https://reparto.procovar.cloud/otra/$token'),
        isNull,
      );
      expect(tokenDelEnlace('hola mundo'), isNull);
      expect(tokenDelEnlace(''), isNull);
      expect(tokenDelEnlace(null), isNull);
      expect(tokenDelEnlace('abc'), isNull);
      expect(
        tokenDelEnlace(
          '  https://reparto.procovar.cloud/r/AbC123xyz?utm=1#x \n',
        ),
        'AbC123xyz',
      );
      expect(tokenDelEnlace('AbC123xyz?x=1'), 'AbC123xyz');
      expect(
        tokenDelEnlace(
          'mira \nhttps://reparto.procovar.cloud/r/AbC123xyz gracias',
        ),
        'AbC123xyz',
      );
    });
  });

  group('reclamar y renovar contra el doble del servidor', () {
    late ServidorFalso servidor;
    late ClienteDeDispositivo cliente;
    RespuestaFalsa Function(PeticionVista) contesta = (_) =>
        RespuestaFalsa(500);

    setUp(() {
      servidor = ServidorFalso((p) async => contesta(p));
      cliente = ClienteDeDispositivo(
        Dio(BaseOptions(baseUrl: 'https://ejemplo.test/api'))
          ..httpClientAdapter = servidor,
      );
    });

    test('reclamar manda token, dispositivoId, nombre y secreto, SIN Authorization', () async {
      contesta = (_) => RespuestaFalsa(200, {
        'acceso': tokenDePrueba(sub: 'd-1', roles: const ['DISTRIBUIDOR']),
        'secreto': 's3cr3to',
        'expira': '2027-05-01T00:00:00Z',
        'rutaId': 'R1',
        'sucursal': 'S1',
      });
      final r = await cliente.reclamar(
        token: token,
        dispositivoId: 'd-1',
        nombre: 'Galaxy A16',
      );
      expect(r.rutaId, 'R1');
      expect(r.secreto, 's3cr3to');
      final peticion = servidor.vistas.single;
      expect(peticion.metodo, 'POST');
      expect(peticion.ruta, endsWith('/d/reclamar'));
      expect(peticion.cuerpo, {
        'token': token,
        'dispositivoId': 'd-1',
        'nombre': 'Galaxy A16',
      });
      expect(
        peticion.cabeceras.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('los «no» del servidor salen con palabras', () async {
      Future<String> pide(int codigo, [Object? cuerpo]) async {
        contesta = (_) => RespuestaFalsa(codigo, cuerpo);
        try {
          await cliente.reclamar(token: token, dispositivoId: 'd', nombre: 'n');
        } on EnlaceRechazado catch (e) {
          return e.mensaje;
        }
        return 'no lanzo';
      }

      expect(
        await pide(403, {'error': 'ruta_de_otro_dispositivo'}),
        'Esta ruta ya está asignada a otro teléfono.',
      );
      expect(
        await pide(404, {'error': 'enlace_no_valido'}),
        contains('no es válido'),
      );
      expect(
        await pide(410, {'error': 'enlace_revocado'}),
        contains('ya no vale'),
      );
    });

    test(
      'sin red es un FalloDeRed (hace falta conexion para reclamar)',
      () async {
        servidor = ServidorFalso((_) async => null);
        cliente = ClienteDeDispositivo(
          Dio(BaseOptions(baseUrl: 'https://ejemplo.test/api'))
            ..httpClientAdapter = servidor,
        );
        await expectLater(
          cliente.reclamar(token: token, dispositivoId: 'd', nombre: 'n'),
          throwsA(isA<FalloDeRed>()),
        );
      },
    );

    test('renovar: 401 = SesionMuerta', () async {
      contesta = (_) => RespuestaFalsa(401);
      await expectLater(
        cliente.renovar(dispositivoId: 'd', secreto: 's'),
        throwsA(isA<SesionMuerta>()),
      );
    });
  });

  group('añadir una ruta', () {
    late AlmacenEnMemoria almacen;
    late List<String> reclamos;
    late Map<String, Object?> ultimaPeticion;
    late String? idGuardado;
    late List<Sesion> entradas;
    late int bajadas;
    String? secretoDelServidor;

    AnadirRuta servicio() {
      final servidor = ServidorFalso((p) async {
        ultimaPeticion = Map<String, Object?>.from(p.cuerpo! as Map);
        reclamos.add(ultimaPeticion['token']! as String);
        return RespuestaFalsa(200, {
          'acceso': tokenDePrueba(sub: 'x', roles: const ['DISTRIBUIDOR']),
          'secreto': ?secretoDelServidor,
          'expira': '2027-05-01T00:00:00Z',
          'rutaId': 'R-${reclamos.length}',
          'sucursal': 'S1',
        });
      });
      return AnadirRuta(
        cliente: ClienteDeDispositivo(
          Dio(BaseOptions(baseUrl: 'https://ejemplo.test/api'))
            ..httpClientAdapter = servidor,
        ),
        almacen: almacen,
        leerId: () async => idGuardado,
        guardarId: (id) async => idGuardado = id,
        nombreDelTelefono: () async => 'Galaxy A16',
        esperarAlArranque: () async {},
        entrar: (s) async => entradas.add(s),
        bajarRutas: () async => bajadas++,
      );
    }

    setUp(() {
      almacen = AlmacenEnMemoria();
      reclamos = [];
      idGuardado = null;
      entradas = [];
      bajadas = 0;
      secretoDelServidor = 'secreto-del-servidor';
    });

    test('el primer enlace genera el dispositivoId, guarda acceso y secreto y ENTRA', () async {
      final id = await servicio().anadir(
        'https://reparto.procovar.cloud/r/$token',
      );
      expect(id, 'R-1');
      expect(idGuardado, isNotNull);
      expect(idGuardado!.length, 36, reason: 'UUIDv7');
      expect(ultimaPeticion['dispositivoId'], idGuardado);
      expect(
        ultimaPeticion.containsKey('secreto'),
        isFalse,
        reason: 'aun no tiene',
      );
      final guardada = (await almacen.leer())!;
      expect(guardada.refresh, 'secreto-del-servidor');
      expect(
        guardada.sub,
        idGuardado,
        reason: 'su base local es del dispositivo',
      );
      expect(guardada.tieneAlguno(const ['DISTRIBUIDOR']), isTrue);
      expect(entradas.single.sub, idGuardado);
      expect(bajadas, 0);
    });

    test('el segundo enlace manda el secreto, no vuelve a entrar y pide bajar la ruta', () async {
      final s = servicio();
      await s.anadir(token);
      secretoDelServidor =
          null; // el servidor solo da secreto al dispositivo NUEVO
      final primero = idGuardado;
      await s.anadir('${token}2');
      expect(ultimaPeticion['secreto'], 'secreto-del-servidor');
      expect(ultimaPeticion['dispositivoId'], primero);
      expect((await almacen.leer())!.refresh, 'secreto-del-servidor');
      expect(entradas.length, 1);
      expect(bajadas, 1);
      expect(reclamos, [token, '${token}2']);
    });

    test(
      'un servidor que no da secreto al dispositivo nuevo es un error claro',
      () async {
        secretoDelServidor = null;
        await expectLater(
          servicio().anadir(token),
          throwsA(isA<EnlaceRechazado>()),
        );
        expect(await almacen.leer(), isNull);
        expect(entradas, isEmpty);
      },
    );

    test('lo que no es un enlace ni se envia al servidor', () async {
      await expectLater(
        servicio().anadir('hola'),
        throwsA(isA<EnlaceRechazado>()),
      );
      expect(reclamos, isEmpty);
    });
  });

  group('el renovador del dispositivo', () {
    late AlmacenEnMemoria almacen;
    late ServidorFalso servidor;
    late RenovadorDeDispositivo renovador;
    final ahora = DateTime(2026, 11, 4, 12);
    RespuestaFalsa Function(PeticionVista) contesta = (_) =>
        RespuestaFalsa(500);

    Sesion con({required int iat, required int exp}) => sesionDeDispositivo(
      acceso: tokenDePrueba(
        sub: 'd-1',
        roles: const ['DISTRIBUIDOR'],
        iat: iat,
        exp: exp,
      ),
      secreto: 'el-secreto',
      dispositivoId: 'd-1',
      pedidoA: ahora,
    );

    setUp(() {
      almacen = AlmacenEnMemoria();
      servidor = ServidorFalso((p) async => contesta(p));
      renovador = RenovadorDeDispositivo(
        ClienteDeDispositivo(
          Dio(BaseOptions(baseUrl: 'https://ejemplo.test/api'))
            ..httpClientAdapter = servidor,
        ),
        almacen,
        reloj: () => ahora,
      );
      contesta = (_) => RespuestaFalsa(200, {
        'acceso': tokenDePrueba(sub: 'd-1', roles: const ['DISTRIBUIDOR']),
        'expira': '2027-12-01T00:00:00Z',
      });
    });

    final dia = const Duration(days: 1).inSeconds;

    test('al arrancar NO renueva si le quedan mas de 30 dias', () async {
      final s = con(iat: 0, exp: 90 * dia);
      await almacen.guardar(s);
      final r = await renovador.alArrancar(s);
      expect(r.token, s.token);
      expect(servidor.vistas, isEmpty);
    });

    test('al arrancar renueva si le quedan menos de 30 dias, y el secreto no cambia', () async {
      final s = con(iat: 0, exp: 10 * dia);
      await almacen.guardar(s);
      final r = await renovador.alArrancar(s);
      expect(r.token, isNot(s.token));
      expect(r.refresh, 'el-secreto');
      expect(r.sub, 'd-1');
      expect(servidor.vistas.single.ruta, endsWith('/d/renovar'));
      expect(servidor.vistas.single.cuerpo, {
        'dispositivoId': 'd-1',
        'secreto': 'el-secreto',
      });
      expect((await almacen.leer())!.token, r.token);
    });

    test('tras un 401 de una llamada normal renueva SIEMPRE', () async {
      final s = con(iat: 0, exp: 90 * dia);
      await almacen.guardar(s);
      final r = await renovador.renovar(s);
      expect(r.token, isNot(s.token));
      expect(servidor.vistas.length, 1);
    });

    test(
      'si el servidor ya no lo reconoce, la sesion muere y se borra',
      () async {
        final s = con(iat: 0, exp: 10 * dia);
        await almacen.guardar(s);
        contesta = (_) => RespuestaFalsa(401);
        await expectLater(renovador.renovar(s), throwsA(isA<SesionMuerta>()));
        expect(await almacen.leer(), isNull);
      },
    );

    test('sin red conserva el acceso que tiene', () async {
      final s = con(iat: 0, exp: 10 * dia);
      await almacen.guardar(s);
      servidor = ServidorFalso((_) async => null);
      renovador = RenovadorDeDispositivo(
        ClienteDeDispositivo(
          Dio(BaseOptions(baseUrl: 'https://ejemplo.test/api'))
            ..httpClientAdapter = servidor,
        ),
        almacen,
        reloj: () => ahora,
      );
      await expectLater(renovador.alArrancar(s), throwsA(isA<FalloDeRed>()));
      expect((await almacen.leer())!.token, s.token);
    });
  });
}
