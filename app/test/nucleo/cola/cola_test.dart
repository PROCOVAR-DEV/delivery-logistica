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

    test('un `repetido` CON MOTIVO sigue rechazado: el «Reintentar» no lo blanquea',
        () async {
      // EL CASO DE JOSE, 01/10/2026, probado en su telefono.
      //
      // Mueve un pedido sin red. Cuando vuelve la senal, el servidor lo rechaza
      // porque ese pedido ya iba en otra ruta. El rechazo queda en la bandeja
      // con su motivo, como tiene que ser.
      //
      // Y entonces se pulsa **«Reintentar»**, que es el boton que pulsa
      // cualquiera —«a lo mejor ahora pasa»—. El servidor reconoce la clave,
      // contesta `repetido` y **reenvia el motivo de entonces a proposito**,
      // porque no puede volver a intentarlo: la clave lo impide por diseno.
      //
      // Hasta hoy ese motivo se tiraba: el apunte pasaba a `aplicado`, la
      // aplicacion decia «1 apunte subido» de algo que NO subio, el rechazo
      // desaparecia de la bandeja y **no quedaba constancia de que decidio
      // nadie**. El §4 por los dos lados: nada se descarta en silencio, y una
      // decision de una persona se ESCRIBE, no se borra.
      final clave = await cola.encolar(
        metodo: 'PUT',
        ruta: '/api/board/placements/f83f1be6-5566-448e-96e3-b4c58af1892f',
        cuerpo: const {'columnaId': 'zona-1', 'posicion': 1},
      );

      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.rechazado,
          motivo: 'Ese pedido ya está en una ruta',
        ),
      );
      expect((await cola.porClave(clave))!.estado, EstadoApunte.rechazado);

      // EL «REINTENTAR» DE VERDAD, que es lo que hace el boton: devuelve el
      // apunte a la cola. Sin este paso el apunte sigue en `rechazado` y
      // `resolver` se corta en seco al principio —«ya estaba resuelto»—, asi que
      // la prueba NO ejercitaria la guarda y saldria verde con el fallo puesto.
      // Comprobado: la primera version de esta prueba se escribio sin esto y la
      // mutacion paso.
      await cola.reintentar(clave);
      expect((await cola.porClave(clave))!.estado, EstadoApunte.pendiente);

      // Y el servidor contesta `repetido` arrastrando el motivo de entonces,
      // porque no puede volver a intentarlo: la clave lo impide por diseno.
      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.repetido,
          motivo: 'Ese pedido ya está en una ruta',
        ),
      );

      final apunte = await cola.porClave(clave);
      expect(
        apunte!.estado,
        EstadoApunte.rechazado,
        reason: 'el rechazo se blanqueó: la aplicación va a decir «1 apunte '
            'subido» de algo que no subió, y la bandeja se vacía sin que quede '
            'constancia de qué decidió la persona',
      );
      expect(
        apunte.motivo,
        'Ese pedido ya está en una ruta',
        reason: 'el motivo que el servidor se molestó en reenviar se tiró',
      );
    });

    test('un `repetido` SIN motivo sigue siendo una aplicación', () async {
      // La otra mitad, y es la que no se puede romper al arreglar lo de arriba:
      // `repetido` se invento para la respuesta que se pierde por el camino. Ahi
      // el apunte SI entro y la clave es justo lo que evita duplicarlo.
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes',
        cuerpo: const {'nombre': 'Bayamo'},
      );

      await cola.resolver(
        clave,
        const ResultadoApunte(estado: EstadoResultado.repetido, id: 'cm2xzzz'),
      );

      expect((await cola.porClave(clave))!.estado, EstadoApunte.aplicado);
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
