// LAS CUENTAS DE LA DISTRIBUCION, sin pantalla: tiempos del recorrido, km por la traza, aviso de sin señal, revisión y filtros.
// Y las llamadas: cada una sale con su método y su ruta.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/distribucion/datos/modelos.dart';
import 'package:reparto/pantallas/distribucion/vista/revision_de_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';
import 'package:reparto/pantallas/distribucion/vista/recorrido_real.dart'
    show cuantoDura;
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/pantallas/distribucion/datos/api_distribucion.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  group('el recorrido real y sus cuentas', () {
    final r = RecorridoReal.deJson(trackDeEjemplo());

    test('salida, llegada y duración total salen de la ruta', () {
      expect(r.salida, DateTime.utc(2026, 11, 4, 13).toLocal());
      expect(r.llegada, DateTime.utc(2026, 11, 4, 16).toLocal());
      expect(r.duracionTotal, const Duration(hours: 3));
    });

    test('una ruta en curso NO tiene llegada ni duración total', () {
      final enCurso = RecorridoReal.deJson(
        trackDeEjemplo(estado: 'in_progress'),
      );
      expect(enCurso.llegada, isNull);
      expect(enCurso.duracionTotal, isNull);
    });

    test('los km son los del GPS, punto a punto', () {
      var esperado = 0.0;
      for (var i = 1; i < r.puntos.length; i++) {
        esperado += haversineKm(r.puntos[i - 1].punto, r.puntos[i].punto);
      }
      expect(r.kmPorLaTraza, closeTo(esperado, 1e-9));
      expect(r.kmPorLaTraza, greaterThan(20));
    });

    test('tiempo desde la anterior, llegada y tiempo EN la parada', () {
      final t = r.conTiempos;
      expect(t, hasLength(3));
      // Parada 1: salió a las 13:00, el GPS pasó junto a ella a las 13:20 y la marcó a las 13:40.
      expect(t[0].desdeLaAnterior, const Duration(minutes: 40));
      expect(t[0].llegada, DateTime.utc(2026, 11, 4, 13, 20).toLocal());
      expect(t[0].enLaParada, const Duration(minutes: 20));
      expect(t[0].marcaLejana, isFalse);
      // Parada 2: 50 minutos después de la anterior; el GPS nunca pasó por su punto, así que NO se inventa el tiempo en la parada.
      expect(t[1].desdeLaAnterior, const Duration(minutes: 50));
      expect(t[1].enLaParada, isNull);
      // Y su marca se hizo a más de un kilómetro de su punto: se avisa.
      expect(t[1].marcaLejana, isTrue);
      expect(t[1].metrosDeLaMarca, greaterThan(1000));
      // Parada 3: sin marcar, sin tiempos.
      expect(t[2].desdeLaAnterior, isNull);
      expect(t[2].parada.resultado, isNull);
    });

    test(
      'las paradas llegan en su orden aunque el servidor las mande revueltas',
      () {
        final j = trackDeEjemplo();
        j['paradas'] = (j['paradas']! as List).reversed.toList();
        expect(
          [for (final p in RecorridoReal.deJson(j).paradas) p.orden],
          [1, 2, 3],
        );
      },
    );

    test('sin puntos no hay recorrido, y el aviso de recorte se lee', () {
      expect(
        RecorridoReal.deJson(trackDeEjemplo(conPuntos: false)).hayPuntos,
        isFalse,
      );
      expect(
        RecorridoReal.deJson(trackDeEjemplo(truncado: true)).truncado,
        isTrue,
      );
    });

    test('las palabras de la duración', () {
      expect(cuantoDura(const Duration(minutes: 65)), '1 h 5 min');
      expect(cuantoDura(const Duration(hours: 2)), '2 h');
      expect(cuantoDura(const Duration(seconds: 20)), 'menos de 1 min');
      expect(cuantoDura(null), '—');
    });
  });

  group('dónde están ahora', () {
    final ahora = DateTime.utc(2026, 11, 4, 15);
    DistribuidorAhora con(DateTime? recibido) => DistribuidorAhora(
      distribuidorId: 'D',
      lat: 1,
      lng: 1,
      recibidoAt: recibido,
    );

    test('a 9 minutos todo bien; a 10 se avisa', () {
      expect(
        con(ahora.subtract(const Duration(minutes: 9))).sinSenal(ahora),
        isFalse,
      );
      expect(
        con(ahora.subtract(const Duration(minutes: 10))).sinSenal(ahora),
        isTrue,
      );
    });

    test('sin ninguna hora se avisa también: no se sabe nada de él', () {
      expect(con(null).sinSenal(ahora), isTrue);
    });
  });

  group('la revisión', () {
    RevisionDeRuta ruta(Map<String, Object?> j) =>
        RevisionDeRuta.deJson({'id': 'R', 'status': 'completed', ...j});

    test('revisadaAt nulo = pendiente; con fecha = revisada', () {
      expect(ruta({'revisadaAt': null}).pendiente, isTrue);
      expect(
        ruta({'revisadaAt': utc(15, 0), 'revisadaPor': 'maikel'}).revisada,
        isTrue,
      );
    });

    test('si el servidor NO manda el campo, la ruta no pasa por revisión', () {
      final r = ruta({});
      expect(r.seRevisa, isFalse);
      expect(r.pendiente, isFalse);
    });

    test('solo se revisa lo completado', () {
      expect(
        RevisionDeRuta.deJson({
          'id': 'R',
          'status': 'in_progress',
          'revisadaAt': null,
        }).seRevisa,
        isFalse,
      );
    });

    test('el filtro: pendientes por defecto, buscador por distribuidor, y las más recientes primero', () {
      final todas = [
        ruta({
          'id': 'a',
          'routeCode': 'RT-1',
          'revisadaAt': null,
          'finishedAt': utc(10, 0),
          'distribuidor': {'nombre': 'Felix'},
        }),
        ruta({
          'id': 'b',
          'routeCode': 'RT-2',
          'revisadaAt': null,
          'finishedAt': utc(12, 0),
          'distribuidor': {'nombre': 'Juan'},
        }),
        ruta({
          'id': 'c',
          'routeCode': 'RT-3',
          'revisadaAt': utc(13, 0),
          'finishedAt': utc(11, 0),
        }),
        ruta({'id': 'd', 'routeCode': 'RT-4', 'finishedAt': utc(9, 0)}),
      ];
      expect([for (final r in filtrarRevisiones(todas)) r.id], ['b', 'a']);
      expect(
        [for (final r in filtrarRevisiones(todas, q: 'felix')) r.id],
        ['a'],
      );
      expect(
        [
          for (final r in filtrarRevisiones(
            todas,
            filtro: FiltroDeRevision.revisadas,
          ))
            r.id,
        ],
        ['c'],
      );
      expect(
        [
          for (final r in filtrarRevisiones(
            todas,
            filtro: FiltroDeRevision.todas,
          ))
            r.id,
        ],
        ['b', 'c', 'a'],
      );
      expect(cuantasPendientes(todas), 2);
    });
  });

  group('el estado del enlace', () {
    test('los tres estados', () {
      expect(
        EnlaceDeRuta.deJson({'estado': 'sin_enlace'}).estado,
        EstadoDelEnlace.sinEnlace,
      );
      final sin = EnlaceDeRuta.deJson({
        'token': 't',
        'url': 'u',
        'estado': 'sin_reclamar',
      });
      expect(sin.estado, EstadoDelEnlace.sinReclamar);
      expect(sin.hayEnlace, isTrue);
      final con = EnlaceDeRuta.deJson({
        'url': 'u',
        'estado': 'reclamado',
        'dispositivo': 'Tel',
        'dispositivoId': 'd1',
        'reclamadoAt': utc(14, 0),
      });
      expect(con.estado, EstadoDelEnlace.reclamado);
      expect(con.dispositivo, 'Tel');
    });
  });

  group('las llamadas', () {
    late ApiDePrueba api;
    setUp(
      () => api = ApiDePrueba(
        (_) async => RespuestaFalsa(200, <String, Object?>{}),
      ),
    );

    test('cada una sale con su método y su ruta', () async {
      api.contesta = (p) async => RespuestaFalsa(200, switch (p.ruta) {
        '/routes/R1/track' => trackDeEjemplo(),
        '/vehicles/V1/historial' => {
          'vehiculoId': 'V1',
          'rutas': [
            {
              'id': 'R1',
              'codigo': 'RT-001',
              'estado': 'completed',
              'paradas': 3,
              'entregadas': 2,
              'devueltas': 1,
              'cobradas': 2,
              'puntos': 40,
              'km': 12.5,
            },
          ],
        },
        '/tracking/ahora' => {
          'distribuidores': [
            {
              'distribuidorId': 'D1',
              'distribuidor': 'Felix',
              'lat': 23.1,
              'lng': -82.4,
              'recibidoAt': utc(15, 0),
              'rutaIds': ['R1'],
            },
          ],
        },
        _ => <String, Object?>{},
      });
      expect((await api.api.recorrido('R1')).ruta.distribuidor, 'Felix');
      final h = await api.api.historialDe('V1');
      expect(h.single.entregadas, 2);
      expect(h.single.km, 12.5);
      expect((await api.api.dondeEstanAhora()).single.rutaIds, ['R1']);
      expect(
        [for (final v in api.servidor.vistas) '${v.metodo} ${v.ruta}'],
        [
          'GET /routes/R1/track',
          'GET /vehicles/V1/historial',
          'GET /tracking/ahora',
        ],
      );
    });

    test('confirmar la revisión manda {"confirmar":true}', () async {
      await api.api.confirmarRevision('R1');
      final v = api.servidor.vistas.single;
      expect('${v.metodo} ${v.ruta}', 'POST /routes/R1/revision');
      expect(v.cuerpo, {'confirmar': true});
    });

    test(
      'un 403 sale con la frase del servidor y la red caída con la suya',
      () async {
        api.contesta = (_) async =>
            RespuestaFalsa(403, {'error': 'sin_permiso_reparto'});
        await expectLater(api.api.recorrido('R1'), throwsA(isA<Rechazo>()));
        api.contesta = (_) async => null;
        try {
          await api.api.dondeEstanAhora();
          fail('tenía que fallar');
        } on Object catch (e) {
          expect(motivoDelFallo(e), 'Sin conexión con el servidor.');
        }
      },
    );
  });
}
