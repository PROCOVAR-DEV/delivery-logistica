import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
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

  for (final estado in ['rechazado', 'repetido']) {
    test(
      '$estado con motivo: hoja rechazada no permite completar la misma ruta ni detiene otra',
      () async {
        final sent = <String>[];
        final m = montar((p) async {
          final cuerpo = p.cuerpo! as Map<String, Object?>;
          final a =
              (cuerpo['apuntes']! as List<Object?>).single
                  as Map<String, Object?>;
          sent.add(a['ruta']! as String);
          return RespuestaFalsa(200, {
            'resultados': [
              {
                'clave': a['clave'],
                'estado': a['ruta'] == '/routes/r1/results'
                    ? estado
                    : 'aplicado',
                if (a['ruta'] == '/routes/r1/results')
                  'motivo': 'La parada ya no pertenece a la ruta.',
              },
            ],
          });
        });
        final hoja = await cola.encolar(
          metodo: 'POST',
          ruta: '/routes/r1/results',
          cuerpo: {
            'resultados': [
              {'orderId': 'p1', 'resultado': 'entregado'},
            ],
          },
        );
        final completa = await cola.encolar(
          metodo: 'PATCH',
          ruta: '/routes/r1',
          cuerpo: {'status': 'completed'},
        );
        await cola.encolar(
          metodo: 'PATCH',
          ruta: '/routes/r2',
          cuerpo: {'status': 'completed'},
        );
        expect(await m.subida.ciclo(), 1);
        expect(
          sent,
          ['/routes/r1/results', '/routes/r2'],
          reason: 'El histórico no puede congelarse después de rechazar sus resultados',
        );
        expect((await cola.porClave(hoja))!.estado, EstadoApunte.rechazado);
        expect(
          (await cola.porClave(hoja))!.motivo,
          'La parada ya no pertenece a la ruta.',
        );
        expect((await cola.porClave(completa))!.estado, EstadoApunte.pendiente);
        sent.clear();
        expect(await m.subida.ciclo(), 0);
        expect(
          sent,
          isEmpty,
          reason: 'El siguiente ciclo tampoco olvida el rechazo anterior',
        );
        await cola.reintentar(hoja);
        sent.clear();
        expect(await m.subida.ciclo(), 0);
        expect(sent, ['/routes/r1/results']);
        expect(
          (await cola.porClave(hoja))!.motivo,
          'La parada ya no pertenece a la ruta.',
        );
        expect((await cola.porClave(completa))!.estado, EstadoApunte.pendiente);
        // Resolver en web y decidir en bandeja es explícito, nunca automático.
        await cola.descartar(hoja);
        sent.clear();
        expect(await m.subida.ciclo(), 1);
        expect(sent, ['/routes/r1']);
        expect((await cola.porClave(hoja))!.estado, EstadoApunte.descartado);
        expect(
          (await cola.porClave(hoja))!.motivo,
          'La parada ya no pertenece a la ruta.',
        );
      },
    );
  }
  test(
    'sin acuse la hoja queda pendiente y sólo completa cuando se acepta',
    () async {
      var confirma = false;
      final sent = <String>[];
      final m = montar((p) async {
        final a =
            ((p.cuerpo! as Map<String, Object?>)['apuntes']! as List<Object?>)
                    .single
                as Map<String, Object?>;
        sent.add(a['ruta']! as String);
        return RespuestaFalsa(200, {
          'resultados': !confirma
              ? <Object?>[]
              : [
                  {'clave': a['clave'], 'estado': 'aplicado'},
                ],
        });
      });
      final hoja = await cola.encolar(
        metodo: 'POST',
        ruta: '/routes/r1/results',
        cuerpo: {},
      );
      final c = await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r1',
        cuerpo: {'status': 'completed'},
      );
      expect(await m.subida.ciclo(), 0);
      expect(sent, ['/routes/r1/results']);
      expect((await cola.porClave(hoja))!.estado, EstadoApunte.pendiente);
      expect((await cola.porClave(c))!.estado, EstadoApunte.pendiente);
      confirma = true;
      sent.clear();
      expect(await m.subida.ciclo(), 2);
      expect(sent, ['/routes/r1/results', '/routes/r1']);
    },
  );
  test(
    'una hoja futura no bloquea completar ni una hoja rechazada impide editar',
    () async {
      final sent = <String>[];
      final m = montar((p) async {
        final a =
            ((p.cuerpo! as Map<String, Object?>)['apuntes']! as List<Object?>)
                    .single
                as Map<String, Object?>;
        sent.add(a['ruta']! as String);
        return RespuestaFalsa(200, {
          'resultados': [
            {
              'clave': a['clave'],
              'estado': a['ruta'] == '/routes/r1/results'
                  ? 'rechazado'
                  : 'aplicado',
              if (a['ruta'] == '/routes/r1/results')
                'motivo': 'Revisar la parada.',
            },
          ],
        });
      });
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r1',
        cuerpo: {'status': 'completed'},
      );
      await cola.encolar(
        metodo: 'POST',
        ruta: '/routes/r1/results',
        cuerpo: {},
      );
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r1',
        cuerpo: {'name': 'Ruta corregida'},
      );
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r1',
        cuerpo: {'status': 'in_progress'},
      );
      expect(await m.subida.ciclo(), 3);
      expect(sent, [
        '/routes/r1',
        '/routes/r1/results',
        '/routes/r1',
        '/routes/r1',
      ]);
    },
  );
  test(
    'un cuerpo antiguo no objeto se entrega para rechazo sin romper otra ruta',
    () async {
      final sent = <String>[];
      final m = montar((p) async {
        final a =
            ((p.cuerpo! as Map<String, Object?>)['apuntes']! as List<Object?>)
                    .single
                as Map<String, Object?>;
        sent.add(a['ruta']! as String);
        return RespuestaFalsa(200, {
          'resultados': [
            {
              'clave': a['clave'],
              'estado': a['ruta'] == '/routes/r1' ? 'rechazado' : 'aplicado',
              if (a['ruta'] == '/routes/r1') 'motivo': 'Cuerpo no válido',
            },
          ],
        });
      });
      final antigua = await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r1',
        cuerpo: {},
      );
      await base.customStatement(
        'UPDATE apuntes SET cuerpo = ? WHERE clave = ?',
        ['[]', antigua],
      );
      await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/r2',
        cuerpo: {'status': 'completed'},
      );
      await expectLater(m.subida.ciclo(), completion(1));
      expect(sent, ['/routes/r1', '/routes/r2']);
    },
  );
}
