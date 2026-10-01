import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late RelojFalso reloj;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 14, 16));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  // El alta del aparato tiene su propio fichero. Aqui se da por hecha para que
  // estas pruebas miren la subida y no otra cosa.
  setUp(() => aparatoYaDeAlta(base));

  tearDown(() => base.close());

  ({Subida subida, ServidorFalso servidor}) montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder,
  ) {
    final servidor = ServidorFalso(responder);
    final almacen = AlmacenEnMemoria(
      const Sesion(token: 't', refresh: 'r0', sub: 'u1'),
    );
    final auth = Dio()..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://sync.test',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;
    return (
      subida: Subida(
        cliente: cliente,
        cola: cola,
        aparato: IdentidadDelAparato(base),
        base: base,
        quienEsta: () async => (await almacen.leer())?.sub,
      ),
      servidor: servidor,
    );
  }

  test('sube UNO POR PETICION, en orden, y nunca dos a la vez', () async {
    // El cambio del 01/10/2026: veinte apuntes son veinte peticiones, una
    // detras de otra. No es el caso I1 —eso son veinte A LA VEZ—, y la ultima
    // comprobacion de esta prueba es justamente la que separa las dos cosas.
    final mandados = <Map<String, Object?>>[];
    final m = montar((p) async {
      final cuerpo = p.cuerpo! as Map<String, Object?>;
      mandados.add(cuerpo);
      final apuntes = cuerpo['apuntes']! as List<Object?>;
      return RespuestaFalsa(200, {
        'resultados': [
          for (final a in apuntes)
            {
              'clave': (a! as Map<String, Object?>)['clave'],
              'estado': 'aplicado',
            },
        ],
      });
    });

    for (var i = 1; i <= 20; i++) {
      await cola.encolar(metodo: 'POST', ruta: '/api/x/$i', cuerpo: {'n': i});
    }

    expect(await m.subida.ciclo(), 20);
    expect(
      m.servidor.vistas,
      hasLength(20),
      reason:
          'veinte apuntes son veinte peticiones: una grande que se corta al '
          '90 % no deja nada arriba',
    );
    expect(
      mandados.map((c) => (c['apuntes']! as List<Object?>).length).toSet(),
      {1},
      reason: 'uno por peticion, ni dos ni cero',
    );
    // El identificador es el que dio el SERVIDOR en el alta, no uno inventado
    // aqui: uno inventado por el telefono podria repetirse entre dos
    // instalaciones y entonces dos aparatos compartirian cola y claves de
    // idempotencia (`sync/internal/sincro/aparato.go`).
    expect(mandados.map((c) => c['aparato']).toSet(), {
      '9f3a0d2e-0000-4000-8000-000000000001',
    });
    expect(
      [
        for (final c in mandados)
          ((c['apuntes']! as List<Object?>).single as Map<String, Object?>)['ruta'],
      ],
      [for (var i = 1; i <= 20; i++) '/api/x/$i'],
      reason: 'y EN ORDEN: al reves, la correccion de una parada se pierde',
    );
    expect(await cola.lote(), isEmpty);
  });

  test('los resultados se casan por clave, no por posicion', () async {
    final primera = await cola.encolar(
      metodo: 'POST',
      ruta: '/a',
      cuerpo: const {},
    );
    final segunda = await cola.encolar(
      metodo: 'POST',
      ruta: '/b',
      cuerpo: const {},
    );

    // El servidor contesta al reves. Fiarse de la posicion marcaria el apunte
    // equivocado como rechazado, y eso no da ningun error: sólo trabajo perdido
    // en el sitio que no es.
    final m = montar(
      (p) async => RespuestaFalsa(200, {
        'resultados': [
          {'clave': segunda, 'estado': 'rechazado', 'motivo': 'no cuadra'},
          {'clave': primera, 'estado': 'aplicado'},
        ],
      }),
    );

    await m.subida.ciclo();

    expect((await cola.porClave(primera))!.estado, EstadoApunte.aplicado);
    final mala = await cola.porClave(segunda);
    expect(mala!.estado, EstadoApunte.rechazado);
    expect(mala.motivo, 'no cuadra');
  });

  test('sin red la cola se queda ENTERA', () async {
    await cola.encolar(metodo: 'POST', ruta: '/a', cuerpo: const {});
    await cola.encolar(metodo: 'POST', ruta: '/b', cuerpo: const {});
    final m = montar((p) async => null);

    await expectLater(m.subida.ciclo(), throwsA(isA<FalloDeRed>()));
    expect(await cola.lote(), hasLength(2));
  });

  test('con la cola vacia no se molesta al servidor', () async {
    final m = montar((p) async => RespuestaFalsa(200, const {}));
    expect(await m.subida.ciclo(), 0);
    expect(m.servidor.vistas, isEmpty);
  });

  test(
    'el cierre de la tarde sube a la ruta de verdad, no al local-…',
    () async {
      // El caso S4 entero, de punta a punta.
      const provisional = 'local-9f3a2b7c';
      final armado = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes',
        cuerpo: const {'routeCode': 'PAL-01'},
        provisional: provisional,
      );
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/$provisional/results',
        cuerpo: const {'rutaId': provisional},
      );

      // Primera subida: sólo cabe uno (el servidor lo corta ahi).
      final rutasVistas = <String>[];
      final m = montar((p) async {
        final cuerpo = p.cuerpo! as Map<String, Object?>;
        final apuntes = (cuerpo['apuntes']! as List<Object?>)
            .cast<Map<String, Object?>>();
        rutasVistas.addAll(apuntes.map((a) => a['ruta']! as String));
        return RespuestaFalsa(200, {
          'resultados': [
            for (final a in apuntes)
              {
                'clave': a['clave'],
                'estado': 'aplicado',
                if (a['clave'] == armado) 'id': 'cm2xreal000',
              },
          ],
        });
      });

      await m.subida.ciclo(maximo: 1);
      await m.subida.ciclo();

      expect(rutasVistas, ['/api/routes', '/api/routes/cm2xreal000/results']);
    },
  );
}
