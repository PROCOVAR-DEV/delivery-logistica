// EL GPS: se enciende solo con una ruta en curso Y el aviso aceptado, UN flujo para
// todas las rutas, los puntos llevan `rutaIds`, la subida va por lotes de 200 e
// idempotente, un fallo no pierde nada y la poda NO toca lo que no ha subido.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/distribuidor/gps/ajustes_de_gps.dart';
import 'package:reparto/distribuidor/gps/puntos_locales.dart';
import 'package:reparto/distribuidor/gps/recorrido_gps.dart';
import 'package:reparto/distribuidor/gps/servicio_de_ubicacion.dart';
import 'package:reparto/distribuidor/gps/subida_del_recorrido.dart';
import 'package:reparto/nucleo/base/base.dart';

import '../apoyo/base_de_prueba.dart';
import 'apoyo_distribuidor.dart';

void main() {
  late BaseLocal base;
  late PuntosGpsLocales puntos;
  late UbicacionFalsa gps;
  var aceptado = true;
  final ahora = DateTime(2026, 11, 4, 12);
  PermisoDeUbicacion? visto;

  RecorridoGps nuevo() => RecorridoGps(
    puntos: puntos,
    servicio: gps,
    haAceptado: () async => aceptado,
    reloj: () => ahora,
    alVerElPermiso: (p) => visto = p,
  );

  setUp(() {
    base = baseDePrueba();
    puntos = PuntosGpsLocales(base);
    gps = UbicacionFalsa(posicion: posicionEn(ahora));
    aceptado = true;
    visto = null;
  });
  tearDown(() => base.close());

  group('cuando se enciende', () {
    test('con una ruta en curso y el aviso aceptado, UN flujo', () async {
      final r = nuevo();
      await r.sincronizar({'R1'});
      await r.sincronizar({'R1', 'R2'}); // otra ruta: el mismo flujo
      expect(gps.arranques, 1);
      expect(gps.permisosPedidos, 1);
      expect(r.encendido, isTrue);
    });

    test('sin rutas en curso, no', () async {
      final r = nuevo();
      await r.sincronizar({});
      expect(gps.arranques, 0);
    });

    test('sin aceptar el aviso, no se activa (y se puede trabajar)', () async {
      aceptado = false;
      final r = nuevo();
      await r.sincronizar({'R1'});
      expect(gps.arranques, 0);
      expect(gps.permisosPedidos, 0, reason: 'ni siquiera se pide el permiso');
      await r.evento(EventoDeRecorrido.parada, rutaId: 'R1', pedidoId: 'p1');
      expect(await puntos.cuantosSinSubir(), 0);
    });

    test('se apaga cuando ya no queda ninguna en curso', () async {
      final r = nuevo();
      await r.sincronizar({'R1', 'R2'});
      await r.sincronizar({'R2'});
      expect(gps.paradas, 0, reason: 'queda una en curso');
      await r.sincronizar({});
      expect(gps.paradas, 1);
      expect(r.encendido, isFalse);
    });

    test('sin permiso lo DICE con palabras y no enciende', () async {
      gps.concede = PermisoDeUbicacion.denegado;
      final r = nuevo();
      await r.sincronizar({'R1'});
      expect(gps.arranques, 0);
      expect(visto, PermisoDeUbicacion.denegado);
      expect(visto!.aviso, contains('la oficina no verá tu recorrido'));
      expect(visto!.aviso, contains('seguir trabajando'));
    });
  });

  group('los puntos', () {
    test('cada punto lleva las rutas en curso de ESE instante', () async {
      final r = nuevo();
      await r.sincronizar({'R1'});
      gps.alLlegar!(posicionEn(ahora, lat: 1));
      await r.sincronizar({'R1', 'R2'});
      gps.alLlegar!(posicionEn(ahora.add(const Duration(seconds: 30)), lat: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final p = await puntos.pendientes();
      expect(p.length, 2);
      expect(jsonDecode(p[0].rutaIds), ['R1']);
      expect(jsonDecode(p[1].rutaIds), unorderedEquals(['R1', 'R2']));
      expect(p[0].id.length, 36, reason: 'UUID');
      expect(p[0].evento, isNull);
    });

    test('el fin se guarda con la ruta aunque ya no este en curso', () async {
      final r = nuevo();
      await r.sincronizar({'R1'});
      await r.sincronizar({});
      await r.evento(EventoDeRecorrido.fin, rutaId: 'R1');
      final p = (await puntos.pendientes()).single;
      expect(jsonDecode(p.rutaIds), ['R1']);
      expect(p.evento, 'fin');
    });

    test('sin posicion fresca no se inventa el punto', () async {
      gps.posicion = null;
      await nuevo().evento(EventoDeRecorrido.inicio, rutaId: 'R1');
      expect(await puntos.cuantosSinSubir(), 0);
    });
  });

  group('la subida', () {
    Future<void> sembrar(int n, {DateTime? hora}) async {
      for (var i = 0; i < n; i++) {
        await puntos.guardar(
          posicionEn((hora ?? ahora).add(Duration(seconds: i))),
          rutaIds: ['R1'],
        );
      }
    }

    test('va por lotes de 200 con la forma de /api/track', () async {
      await sembrar(450);
      final lotes = <Map<String, Object?>>[];
      final subida = SubidaDelRecorrido(
        puntos,
        (c) async => lotes.add(c),
        reloj: () => ahora,
      );
      expect(await subida.subir(), 450);
      expect(
        [for (final l in lotes) (l['puntos']! as List).length],
        [200, 200, 50],
      );
      final primero =
          (lotes.first['puntos']! as List).first as Map<String, Object?>;
      expect(
        primero.keys,
        containsAll([
          'id',
          'rutaIds',
          'lat',
          'lng',
          'precision',
          'velocidad',
          'rumbo',
          'hora',
          'evento',
          'pedidoId',
        ]),
      );
      expect(primero['rutaIds'], ['R1']);
      expect(
        (primero['hora']! as String).endsWith('Z'),
        isTrue,
        reason: 'ISO UTC',
      );
      expect(await puntos.cuantosSinSubir(), 0);
      expect(AjustesDeGps.tamanoDelLote, 200);
    });

    test('un fallo NO pierde nada y se reintenta con los mismos ids', () async {
      await sembrar(5);
      final vistos = <String>[];
      var falla = true;
      final subida = SubidaDelRecorrido(puntos, (c) async {
        vistos.addAll([
          for (final p in c['puntos']! as List) (p as Map)['id'] as String,
        ]);
        if (falla) throw StateError('sin red');
      }, reloj: () => ahora);
      expect(await subida.subir(), 0);
      expect(await puntos.cuantosSinSubir(), 5);
      falla = false;
      expect(await subida.subir(), 5);
      expect(vistos.length, 10);
      expect(
        vistos.sublist(0, 5),
        vistos.sublist(5),
        reason: 'idempotente por id',
      );
    });

    test(
      'la poda borra los subidos de mas de 90 dias y NUNCA los no subidos',
      () async {
        final viejo = ahora.subtract(const Duration(days: 91));
        await sembrar(2, hora: viejo); // viejos
        await subida(puntos, ahora).subir(); // los dos viejos suben
        await sembrar(
          1,
          hora: viejo.add(const Duration(hours: 1)),
        ); // viejo y SIN subir
        await sembrar(1, hora: ahora.subtract(const Duration(days: 10)));
        await subida(
          puntos,
          ahora,
          falla: true,
        ).subir(); // intenta, falla, poda
        final quedan = await base.select(base.puntosGps).get();
        expect(quedan.length, 2, reason: 'el viejo sin subir y el reciente');
        expect(quedan.where((p) => !p.subido).length, 2);
      },
    );
  });
}

SubidaDelRecorrido subida(
  PuntosGpsLocales p,
  DateTime ahora, {
  bool falla = false,
}) => SubidaDelRecorrido(p, (c) async {
  if (falla) throw StateError('sin red');
}, reloj: () => ahora);
