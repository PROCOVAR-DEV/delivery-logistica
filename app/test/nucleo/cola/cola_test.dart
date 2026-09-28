import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 14, 16, 4, 22));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  tearDown(() => base.close());

  group('el orden', () {
    test('es el de encolar, aunque el reloj salte hacia atras', () async {
      // El reloj del telefono se fue con la bateria y vuelve puesto en ayer, y
      // luego alguien lo corrige a mano. Si el orden saliera de la hora, la
      // correccion de una parada subiria ANTES que la marca que corrige, y
      // quedaria puesta la marca vieja (caso S3).
      reloj.guion = [
        DateTime(2026, 9, 14, 16, 0),
        DateTime(2026, 9, 13, 8, 0), // ayer
        DateTime(2026, 9, 14, 9, 0), // esta manana
        DateTime(2026, 9, 14, 16, 5),
      ];

      await cola.encolar(metodo: 'POST', ruta: '/a', cuerpo: {'n': 1});
      await cola.encolar(metodo: 'POST', ruta: '/b', cuerpo: {'n': 2});
      await cola.encolar(metodo: 'POST', ruta: '/c', cuerpo: {'n': 3});
      await cola.encolar(metodo: 'POST', ruta: '/d', cuerpo: {'n': 4});

      final lote = await cola.lote();
      expect(lote.map((a) => a.ruta).toList(), [
        '/a',
        '/b',
        '/c',
        '/d',
      ], reason: 'FIFO lo da `orden`, no `hechoAt`');
      // Y las horas SI van desordenadas: el desorden era real.
      expect(lote[1].hechoAt.isBefore(lote[0].hechoAt), isTrue);
    });

    test('`pendientes()` sale en el mismo orden que el lote', () async {
      for (final ruta in ['/1', '/2', '/3']) {
        await cola.encolar(metodo: 'POST', ruta: ruta, cuerpo: const {});
      }
      final pendientes = await cola.pendientes().first;
      expect(pendientes.map((a) => a.ruta).toList(), ['/1', '/2', '/3']);
    });
  });

  group('la hora es la del aparato', () {
    test('se escribe al encolar y NO se toca al resolver', () async {
      final cuandoSeHizo = DateTime(2026, 9, 14, 16, 4, 22);
      reloj.ahora = cuandoSeHizo;

      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r1/results',
        cuerpo: const {'resultado': 'entregado'},
      );

      // Tres horas despues el telefono pilla senal y sube.
      reloj.ahora = DateTime(2026, 9, 14, 19, 30);
      await cola.resolver(
        clave,
        const ResultadoApunte(estado: EstadoResultado.aplicado),
      );

      final apunte = await cola.porClave(clave);
      expect(
        apunte!.hechoAt,
        cuandoSeHizo,
        reason: 'lo que se marca a las cuatro llega como las cuatro (regla 7)',
      );
      expect(apunte.resueltoAt, DateTime(2026, 9, 14, 19, 30));
    });
  });

  group('idempotencia', () {
    test('cada apunte lleva su clave, y son distintas', () async {
      final a = await cola.encolar(
        metodo: 'POST',
        ruta: '/a',
        cuerpo: const {},
      );
      final b = await cola.encolar(
        metodo: 'POST',
        ruta: '/a',
        cuerpo: const {},
      );
      expect(a, isNotEmpty);
      expect(a, isNot(b));
      expect(a.length, 26, reason: 'ULID canonico');
    });

    test('la base impide dos apuntes con la misma clave', () async {
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/a',
        cuerpo: const {},
      );

      // La clave es lo que deja al servidor reconocer un reintento. Si el
      // aparato pudiera tener dos apuntes distintos con la misma, esa garantia
      // se cae y la ruta acaba duplicada (caso S5).
      expect(
        () => base
            .into(base.apuntes)
            .insert(
              ApuntesCompanion.insert(
                clave: clave,
                hechoAt: reloj.ahora,
                metodo: 'POST',
                ruta: '/b',
                cuerpo: '{}',
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('`repetido` se trata como aplicado: no es un error', () async {
      // La subida se corto DESPUES de que el servidor guardara. El reintento
      // llega con la misma clave y el servidor contesta `repetido` con el id que
      // ya habia creado.
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes',
        cuerpo: const {'nombre': 'Palma'},
        provisional: 'local-9f3a2b7c',
      );

      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.repetido,
          id: 'cm2xabc123',
        ),
      );

      final apunte = await cola.porClave(clave);
      expect(apunte!.estado, EstadoApunte.aplicado);
      expect(apunte.motivo, isNull);
      // Y la sustitucion se hizo igual: si no, el cierre de la tarde se iria al
      // `local-…`.
      final equivalencia = await (base.select(
        base.equivalencias,
      )..where((e) => e.provisional.equals('local-9f3a2b7c'))).getSingle();
      expect(equivalencia.idReal, 'cm2xabc123');
    });

    test('resolver dos veces no reescribe nada', () async {
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/a',
        cuerpo: const {},
      );
      await cola.resolver(
        clave,
        const ResultadoApunte(estado: EstadoResultado.aplicado),
      );
      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.rechazado,
          motivo: 'tarde',
        ),
      );

      final apunte = await cola.porClave(clave);
      expect(apunte!.estado, EstadoApunte.aplicado);
      expect(apunte.motivo, isNull);
    });
  });

  group('rechazado', () {
    test('se queda con su motivo y su hora, y NO vuelve al lote', () async {
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes',
        cuerpo: const {},
      );
      reloj.ahora = DateTime(2026, 9, 14, 17, 15);

      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.rechazado,
          motivo:
              '3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.',
        ),
      );

      final apunte = await cola.porClave(clave);
      expect(apunte!.estado, EstadoApunte.rechazado);
      expect(
        apunte.motivo,
        '3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.',
        reason: 'el mensaje del servidor se guarda LITERAL',
      );
      expect(apunte.resueltoAt, DateTime(2026, 9, 14, 17, 15));

      // Ni se reintenta…
      expect(await cola.lote(), isEmpty);
      // …ni se borra: sale en la bandeja (regla 6, caso S6).
      expect((await cola.rechazados().first).single.clave, clave);
    });

    test('la poda nunca se lleva un rechazado', () async {
      final rechazado = await cola.encolar(
        metodo: 'POST',
        ruta: '/r',
        cuerpo: const {},
      );
      final aplicado = await cola.encolar(
        metodo: 'POST',
        ruta: '/a',
        cuerpo: const {},
      );
      await cola.resolver(
        rechazado,
        const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: 'no'),
      );
      await cola.resolver(
        aplicado,
        const ResultadoApunte(estado: EstadoResultado.aplicado),
      );

      // Ocho dias despues.
      reloj.avanzar(const Duration(days: 8));
      expect(await cola.podar(), 1);

      expect(await cola.porClave(aplicado), isNull);
      expect(await cola.porClave(rechazado), isNotNull);
    });

    test('la poda tampoco se lleva un APLICADO con el aviso sin leer', () async {
      // Un apunte que entró y aun así dejó pedidos fuera es lo ÚNICO que
      // explica por qué esa ruta salió con nueve de doce. Borrarlo a los siete
      // días «porque ya subió» es descartarlo en silencio con un temporizador.
      final conAviso = await cola.encolar(
        metodo: 'POST',
        ruta: '/board/columns/z-vista/route',
        cuerpo: const {},
      );
      final limpio = await cola.encolar(
        metodo: 'POST',
        ruta: '/board/columns/z-centro/route',
        cuerpo: const {},
      );
      await cola.resolver(
        conAviso,
        const ResultadoApunte(
          estado: EstadoResultado.aplicado,
          descartados: [
            DescartadoDelServidor(
              pedidoId: 'p2',
              operationNumber: 'X-2992',
              customerName: 'Ana Pérez',
              motivo: 'ya no estaba en esa zona cuando llegó tu apunte',
              queHacer: 'comprueba si se entregó igual',
            ),
          ],
        ),
      );
      await cola.resolver(
        limpio,
        const ResultadoApunte(estado: EstadoResultado.aplicado),
      );

      // El aviso se guarda con el pedido NOMBRADO y con qué hacer: un uuid no
      // le dice nada a nadie.
      final apunte = await cola.porClave(conAviso);
      expect(apunte!.estado, EstadoApunte.aplicado);
      expect(apunte.motivo, contains('X-2992 · Ana Pérez'));
      expect(apunte.motivo, contains('comprueba si se entregó igual'));
      expect((await cola.descartesSinLeer().first).single.clave, conAviso);

      reloj.avanzar(const Duration(days: 8));
      expect(await cola.podar(), 1);
      expect(await cola.porClave(limpio), isNull);
      expect(
        await cola.porClave(conAviso),
        isNotNull,
        reason:
            'mientras nadie lo haya leído, es la única constancia de lo que no '
            'subió a ese camión',
      );

      // Y en cuanto una persona lo da por leído, se poda como cualquier otro.
      await cola.darPorLeidoElDescarte(conAviso);
      expect(await cola.descartesSinLeer().first, isEmpty);
      expect(await cola.podar(), 1);
      expect(await cola.porClave(conAviso), isNull);
    });
  });

  test('el cuerpo se guarda como JSON y vuelve igual', () async {
    final cuerpo = <String, Object?>{
      'pedidos': ['a', 'b'],
      'peso': 1234.5,
      'nota': 'con tildes: camión',
    };
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/api/routes',
      cuerpo: cuerpo,
    );
    final apunte = await cola.porClave(clave);
    expect(jsonDecode(apunte!.cuerpo), cuerpo);
    expect(ColaDeSalida.cuerpoDe(apunte), cuerpo);
  });

  test('`aJson` manda la hora del aparato, no la de la subida', () async {
    reloj.ahora = DateTime.utc(2026, 9, 14, 16, 4, 22);
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/x',
      cuerpo: const {'a': 1},
    );
    final apunte = await cola.porClave(clave);
    final json = apunte!.aJson(ColaDeSalida.cuerpoDe(apunte));

    expect(json['clave'], clave);
    expect(json['hecho'], '2026-09-14T16:04:22.000Z');
    expect(json['metodo'], 'POST');
    expect(json['ruta'], '/x');
    expect(json['cuerpo'], const {'a': 1});
    expect(json.containsKey('provisional'), isFalse);
  });
}
