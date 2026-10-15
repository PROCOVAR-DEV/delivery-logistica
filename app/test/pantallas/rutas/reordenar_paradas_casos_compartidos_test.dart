// REORDENAR LAS PARADAS: el aparato contra `docs/reordenar-paradas.casos.json`,
// el MISMO fichero que lee el servidor
// (`api/internal/api/reordenar_paradas_casos_compartidos_test.go`). La APK
// reordena sin señal y el servidor vuelve a hacerlo al subir: si el orden por
// cercanía, los km o un literal de rechazo se separan, uno de los dos lados se
// pone rojo.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  final doc = jsonDecode(
    File('../docs/reordenar-paradas.casos.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final tolerancia = (doc['toleranciaKm'] as num).toDouble();
  final o = doc['origen'] as Map<String, dynamic>;
  final origen = Punto(
    (o['lat'] as num).toDouble(),
    (o['lng'] as num).toDouble(),
  );
  final paradas = (doc['paradas'] as List).cast<Map<String, dynamic>>();
  List<String> ids(Object? lista) => (lista as List).cast<String>();

  final conPunto = <Parada>[
    for (final p in paradas)
      if (p['lat'] != null)
        Parada(
          p['id'] as String,
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        ),
  ];
  final sinPunto = [
    for (final p in paradas)
      if (p['lat'] == null) p['id'] as String,
  ];
  List<Parada> recorrido(List<String> orden) => [
    for (final id in orden) ...conPunto.where((p) => p.id == id),
  ];

  test('por cercanía da el orden y los km del fichero compartido', () {
    final esperado = doc['porCercania'] as Map<String, dynamic>;
    final orden = ordenPorCercania(origen, conPunto, sinPunto);
    expect(
      orden,
      ids(esperado['orden']),
      reason:
          'el servidor ordena con el mismo fichero: si cambias uno, cambia '
          'el otro',
    );
    expect(
      kmDelCircuito(origen, recorrido(orden)),
      closeTo((esperado['totalKm'] as num).toDouble(), tolerancia),
    );
  });

  test('a mano mide los km del fichero, y cada parada su recta', () {
    final radial = (doc['radialKm'] as Map).cast<String, num>();
    for (final caso in (doc['aMano'] as List).cast<Map<String, dynamic>>()) {
      expect(
        kmDelCircuito(origen, recorrido(ids(caso['orden']))),
        closeTo((caso['totalKm'] as num).toDouble(), tolerancia),
        reason: caso['nombre'] as String,
      );
    }
    for (final p in conPunto) {
      expect(
        haversineKm(origen, p.punto),
        closeTo(radial[p.id]!.toDouble(), tolerancia),
      );
    }
  });

  test('los rechazos dicen LETRA POR LETRA lo del fichero', () {
    expect(msgRutaSinOrigen, doc['sinOrigen']);
    final cargadas = <ParadaCargada>[
      for (final p in paradas)
        (
          id: p['id'] as String,
          conduce: p['conduce'] as String?,
          cliente: p['cliente'] as String,
        ),
    ];
    for (final caso in (doc['rechazos'] as List).cast<Map<String, dynamic>>()) {
      final no = motivoDelOrden(ids(caso['orden']), cargadas);
      expect(no?.codigo ?? 0, caso['codigo'], reason: caso['nombre'] as String);
      expect(
        no?.motivo ?? '',
        caso['motivo'],
        reason: caso['nombre'] as String,
      );
    }
  });

  // Y EL CAMINO ENTERO DE LA APK: con esos mismos datos en la base local,
  // «Ordenar por cercanía» deja el orden, el km de cada parada y el total del
  // fichero, que es lo que el servidor guardará al subir el apunte.
  group('en la base local del aparato', () {
    late BaseLocal base;
    late AccionesDeRuta acciones;

    setUp(() {
      base = baseDePrueba();
      final reloj = RelojFalso(DateTime.utc(2026, 10, 15, 9));
      acciones = AccionesDeRuta(
        base,
        ColaDeSalida(base, reloj: reloj.leer),
        reloj: reloj.leer,
      );
    });
    tearDown(() => base.close());

    test('por cercanía deja lo mismo que el servidor', () async {
      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1');
      await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
        RoutesCompanion(
          originLat: Value(origen.lat),
          originLng: Value(origen.lng),
        ),
      );
      for (final (i, p) in paradas.indexed) {
        await sembrarPedido(
          base,
          id: p['id'] as String,
          cliente: p['cliente'] as String,
          rutaId: 'R1',
          orden: i + 1,
          endLat: (p['lat'] as num?)?.toDouble(),
          endLng: (p['lng'] as num?)?.toDouble(),
        );
      }

      await acciones.reordenar('R1');

      final filas = await (base.select(
        base.orders,
      )..where((o) => o.routeId.equals('R1'))).get();
      filas.sort((a, b) => a.stopOrder!.compareTo(b.stopOrder!));
      final esperado = doc['porCercania'] as Map<String, dynamic>;
      expect([for (final f in filas) f.id], ids(esperado['orden']));
      final radial = (doc['radialKm'] as Map).cast<String, num>();
      for (final f in filas) {
        if (radial[f.id] == null) {
          expect(f.segmentKm, isNull, reason: 'sin punto, sin km: un hueco');
        } else {
          expect(f.segmentKm, closeTo(radial[f.id]!.toDouble(), tolerancia));
        }
      }
      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('R1'))).getSingle();
      expect(
        ruta.totalDistance,
        closeTo((esperado['totalKm'] as num).toDouble(), tolerancia),
      );
      expect(ruta.optimized, isTrue);
    });
  });
}
