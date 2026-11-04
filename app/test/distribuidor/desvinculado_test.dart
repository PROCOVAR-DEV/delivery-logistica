// «ESTE TELEFONO FUE DESVINCULADO DE SU VEHICULO»: la oficina lo desvincula y el servidor
// contesta 403 `dispositivo_desvinculado` a cualquier llamada. La app se VACIA, conserva
// SOLO la identidad del telefono (id y secreto), lo dice una vez con lo que se perdio y
// un enlace nuevo funciona. Y el vinculo (vehiculo y distribuidor) que trae el enlace.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/distribuidor/dispositivo/anadir_ruta.dart';
import 'package:reparto/distribuidor/dispositivo/cliente_de_dispositivo.dart';
import 'package:reparto/distribuidor/dispositivo/desvinculador.dart';
import 'package:reparto/distribuidor/dispositivo/renovador_de_dispositivo.dart';
import 'package:reparto/distribuidor/dispositivo/vinculo.dart';
import 'package:reparto/distribuidor/gps/puntos_locales.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../apoyo/apoyo_sesion.dart';
import '../apoyo/base_de_prueba.dart';
import '../apoyo/reloj_falso.dart';
import '../apoyo/servidor_falso.dart';
import '../pantallas/pedidos/sembrar.dart';
import 'apoyo_distribuidor.dart';

const _desvinculado = <String, Object?>{
  'error': 'Este teléfono fue desvinculado de su vehículo.',
  'codigo': 'dispositivo_desvinculado',
};

void main() {
  final sesion = sesionDeDispositivo(
    acceso: tokenDePrueba(sub: 'tel-1', roles: const ['DISTRIBUIDOR']),
    secreto: 'el-secreto',
    dispositivoId: 'tel-1',
  );

  group('quien avisa de la desvinculacion', () {
    ClienteApi cliente(
      Future<RespuestaFalsa?> Function(PeticionVista) responder,
      AlmacenEnMemoria almacen,
      List<int> avisos,
    ) {
      final servidor = ServidorFalso(responder);
      final c = ClienteApi.montar(
        baseUrl: 'https://api.test',
        almacen: almacen,
        renovador: Renovador(Dio()..httpClientAdapter = servidor, almacen),
        esperar: (_) async {},
        esWeb: false,
        alDesvincular: () => avisos.add(1),
      );
      c.dio.httpClientAdapter = servidor;
      return c;
    }

    test('en una llamada NORMAL (rutas, sync, results, track...): avisa y sale como Rechazo con su marca', () async {
      final avisos = <int>[];
      final c = cliente(
        (p) async => RespuestaFalsa(403, _desvinculado),
        AlmacenEnMemoria(sesion),
        avisos,
      );
      await expectLater(
        c.pedir<Object?>('/routes'),
        throwsA(
          isA<Rechazo>()
              .having((r) => r.codigo, 'codigo', 403)
              .having((r) => r.marca, 'marca', marcaDispositivoDesvinculado),
        ),
      );
      expect(avisos, [1]);
    });

    test('un 403 de otra cosa NO vacia nada', () async {
      final avisos = <int>[];
      final c = cliente(
        (p) async => RespuestaFalsa(403, const {'error': 'sin_permiso'}),
        AlmacenEnMemoria(sesion),
        avisos,
      );
      await expectLater(c.pedir<Object?>('/routes'), throwsA(isA<Rechazo>()));
      expect(avisos, isEmpty);
    });

    test(
      'en RENOVAR: avisa, lanza el Rechazo y no inventa un acceso',
      () async {
        final avisos = <int>[];
        final almacen = AlmacenEnMemoria(sesion);
        final r = RenovadorDeDispositivo(
          ClienteDeDispositivo(
            Dio(BaseOptions(baseUrl: 'https://api.test'))
              ..httpClientAdapter = ServidorFalso(
                (p) async => RespuestaFalsa(403, _desvinculado),
              ),
          ),
          almacen,
          alDesvincular: () => avisos.add(1),
        );
        await expectLater(
          r.renovar(sesion),
          throwsA(
            isA<Rechazo>().having(
              (x) => x.marca,
              'marca',
              marcaDispositivoDesvinculado,
            ),
          ),
        );
        expect(avisos, [1]);
      },
    );

    group('durante la SUBIDA', () {
      late BaseLocal base;
      late ColaDeSalida cola;

      setUp(() async {
        base = baseDePrueba();
        cola = ColaDeSalida(
          base,
          reloj: RelojFalso(DateTime(2026, 11, 4, 9)).leer,
        );
        await aparatoYaDeAlta(base);
      });
      tearDown(() => base.close());

      Subida subida(
        Future<RespuestaFalsa?> Function(PeticionVista) responder,
        List<int> avisos,
      ) {
        final c = cliente(responder, AlmacenEnMemoria(sesion), avisos);
        return Subida(
          cliente: c,
          cola: cola,
          aparato: IdentidadDelAparato(base, sync: c),
          base: base,
          quienEsta: () async => 'tel-1',
          alDesvincular: () => avisos.add(1),
        );
      }

      Future<String> unCierre() => cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r-1',
        cuerpo: const {'status': 'completed'},
      );

      test('un 403 HTTP: avisa y el apunte sigue pendiente', () async {
        final clave = await unCierre();
        final avisos = <int>[];
        await expectLater(
          subida(
            (p) async => RespuestaFalsa(403, _desvinculado),
            avisos,
          ).ciclo(),
          throwsA(isA<Rechazo>()),
        );
        expect(avisos, isNotEmpty);
        expect((await cola.porClave(clave))!.estado, EstadoApunte.pendiente);
      });

      test('el rechazo DENTRO de un 200 (el sync convierte el 4xx): avisa y NO lo da por rechazado', () async {
        final clave = await unCierre();
        final avisos = <int>[];
        final s = subida(
          (p) async => RespuestaFalsa(200, {
            'resultados': [
              {
                'clave': clave,
                'estado': 'rechazado',
                'motivo': 'Este teléfono fue desvinculado de su vehículo.',
              },
            ],
          }),
          avisos,
        );
        await expectLater(s.ciclo(), throwsA(isA<Rechazo>()));
        expect(avisos, [1]);
        expect((await cola.porClave(clave))!.estado, EstadoApunte.pendiente);
      });
    });
  });

  group('vaciarse', () {
    late BaseLocal base;
    late AlmacenEnMemoria almacen;
    late List<String> avisos;
    late Map<String, String> identidad;
    late Desvinculador desvinculador;

    setUp(() async {
      base = baseDePrueba();
      almacen = AlmacenEnMemoria(sesion);
      avisos = [];
      identidad = {};
      desvinculador = Desvinculador(
        baseActual: () => base,
        almacen: almacen,
        cambiarAVacio: (a) async => avisos.add(a),
        guardarIdentidad: (id, secreto) async =>
            identidad = {'id': id, 'secreto': secreto},
      );
      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1', estado: EstadoRuta.enCurso);
      await sembrarPedido(
        base,
        id: 'p1',
        cliente: 'Ana',
        rutaId: 'R1',
        orden: 1,
      );
      await sembrarPedido(
        base,
        id: 'p2',
        cliente: 'Beto',
        rutaId: 'R1',
        orden: 2,
      );
      await base.anotarPreferencia(
        claveDelVinculo,
        const VinculoDelTelefono(vehiculo: 'Camión 1').aJson(),
      );
      await base
          .into(base.cobrosDeEntrega)
          .insert(
            CobrosDeEntregaCompanion.insert(pedidoId: 'p1', cobrado: true),
          );
      final cola = ColaDeSalida(
        base,
        reloj: RelojFalso(DateTime(2026, 11, 4, 9)).leer,
      );
      await cola.encolar(
        metodo: 'POST',
        ruta: '/routes/R1/results',
        cuerpo: const {
          'resultados': [
            {'orderId': 'p1', 'resultado': 'entregado'},
            {'orderId': 'p2', 'resultado': 'devuelto', 'nota': 'x'},
          ],
        },
      );
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/R1',
        cuerpo: const {'status': 'completed'},
      );
      final puntos = PuntosGpsLocales(base);
      for (var i = 0; i < 3; i++) {
        await puntos.guardar(
          posicionEn(DateTime(2026, 11, 4, 9, i)),
          rutaIds: ['R1'],
        );
      }
    });
    tearDown(() => base.close());

    test('borra TODO lo local, conserva id y secreto, y lo dice una vez con lo descartado', () async {
      await desvinculador.vaciar();

      for (final t in base.allTables) {
        final filas = await base
            .customSelect('SELECT COUNT(*) AS n FROM ${t.actualTableName}')
            .getSingle();
        expect(
          filas.read<int>('n'),
          0,
          reason: '${t.actualTableName} debia quedar vacia',
        );
      }
      expect(await almacen.leer(), isNull, reason: 'los accesos se borran');
      expect(identidad, {'id': 'tel-1', 'secreto': 'el-secreto'});
      expect(avisos.length, 1, reason: 'se dice UNA vez');
      expect(avisos.single, startsWith(textoDesvinculado));
      expect(avisos.single, contains('2 marcas'));
      expect(avisos.single, contains('1 cambio de ruta'));
      expect(avisos.single, contains('3 puntos de GPS'));
    });

    test('sin nada pendiente, el mensaje es el simple', () async {
      await base.delete(base.apuntes).go();
      await base.delete(base.puntosGps).go();
      await desvinculador.vaciar();
      expect(avisos.single, textoDesvinculado);
    });

    test('varias llamadas que ven el 403 a la vez vacian UNA vez', () async {
      await Future.wait([
        desvinculador.vaciar(),
        desvinculador.vaciar(),
        desvinculador.vaciar(),
      ]);
      expect(avisos.length, 1);
    });
  });

  group('despues de vaciarse un enlace nuevo funciona', () {
    test('mismo id y mismo secreto, sin sesion; y guarda el vinculo del vehiculo nuevo', () async {
      // Lo que dejo `Desvinculador`: el id y el secreto en las preferencias del telefono.
      const id = 'tel-1';
      const secreto = 'el-secreto';
      final almacen = AlmacenEnMemoria(); // sin sesion
      final vistas = <Map<String, Object?>>[];
      final entradas = <Sesion>[];
      final vinculos = <VinculoDelTelefono>[];
      final servidor = ServidorFalso((p) async {
        vistas.add(Map<String, Object?>.from(p.cuerpo! as Map));
        return RespuestaFalsa(200, {
          'acceso': tokenDePrueba(sub: 'x', roles: const ['DISTRIBUIDOR']),
          'rutaId': 'R9',
          'vinculoId': 'v-1',
          'vehiculoId': 'veh-2',
          'vehiculo': {
            'id': 'veh-2',
            'nombre': 'Triciclo-Juan',
            'placa': 'P-77',
            'tipo': 'Triciclo',
          },
          'distribuidor': {'id': 'dis-1', 'nombre': 'Juan'},
        });
      });
      final servicio = AnadirRuta(
        cliente: ClienteDeDispositivo(
          Dio(BaseOptions(baseUrl: 'https://api.test'))
            ..httpClientAdapter = servidor,
        ),
        almacen: almacen,
        leerId: () async => id,
        guardarId: (_) async {},
        leerSecreto: () async => secreto,
        nombreDelTelefono: () async => 'Galaxy',
        esperarAlArranque: () async {},
        entrar: (s) async => entradas.add(s),
        bajarRutas: () async {},
        guardarVinculo: (v) async => vinculos.add(v),
      );

      expect(await servicio.anadir('AbC123xyz'), 'R9');
      expect(vistas.single['dispositivoId'], id);
      expect(
        vistas.single['secreto'],
        secreto,
        reason: 'es el MISMO telefono para el servidor',
      );
      expect(entradas.single.sub, id);
      expect(
        entradas.single.refresh,
        secreto,
        reason: 'sin secreto nuevo se conserva el de siempre',
      );
      final v = vinculos.single;
      expect(v.vehiculo, 'Triciclo-Juan');
      expect(v.texto, 'Triciclo-Juan (P-77) · Juan');
      expect(VinculoDelTelefono.deJson(v.aJson())!.texto, v.texto);
    });
  });

  group('los errores nuevos de reclamar traen el mensaje del servidor', () {
    for (final (marca, codigo) in <(String, int)>[
      ('vehiculo_de_otro_dispositivo', 403),
      ('dispositivo_de_otro_vehiculo', 403),
      ('ruta_sin_vehiculo', 409),
    ]) {
      test(marca, () async {
        final c = ClienteDeDispositivo(
          Dio(BaseOptions(baseUrl: 'https://api.test'))
            ..httpClientAdapter = ServidorFalso(
              (p) async => RespuestaFalsa(codigo, {
                'codigo': marca,
                'mensaje': 'Texto del servidor para $marca.',
              }),
            ),
        );
        await expectLater(
          c.reclamar(token: 'AbC123xyz', dispositivoId: 'd', nombre: 'n'),
          throwsA(
            isA<EnlaceRechazado>().having(
              (e) => e.mensaje,
              'mensaje',
              'Texto del servidor para $marca.',
            ),
          ),
        );
      });
    }
  });
}
