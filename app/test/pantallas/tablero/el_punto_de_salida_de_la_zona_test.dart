// EL PUNTO DE SALIDA DE CADA ZONA — Jose, 15/10/2026: «cada columna del tablero
// se pueda configurar de dónde sale, así los tableros quedan preparados para cada
// punto sin estar cambiando arriba de lado a lado».
//
// Lo que se ata aquí, y en pareja (lo que sale y lo que no):
//
//  * la regla, contra `docs/punto-de-salida.casos.json`, el MISMO fichero que lee
//    el servidor (`punto_de_salida_casos_compartidos_test.go`): sin punto = el
//    principal; con punto = ese o un «no» con sus palabras, sin caer al principal;
//  * el gesto en la APK/escritorio va a la COLA con `almacenId` (y `null` viaja,
//    que es «quítamelo»); en la WEB va directo y un 400 se dice con su motivo
//    literal sin mover nada;
//  * una zona nueva nace con el punto que se le dé;
//  * el armado LOCAL sale del punto de SU zona, y no del principal; y si su punto
//    no sirve, dice el mismo «no» que el servidor y antes que «no hay nada»;
//  * los km de lo puesto se miden desde el punto de su zona;
//  * la bajada del tablero guarda el `almacenId` de cada zona;
//  * las zonas van agrupadas por su punto, y cambiar el punto mueve la zona.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/geo.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/punto_de_salida.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/datos/servicio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const rutaDeLosCasos = '../docs/punto-de-salida.casos.json';

Map<String, dynamic> _leerCasos() =>
    jsonDecode(File(rutaDeLosCasos).readAsStringSync()) as Map<String, dynamic>;

/// Los almacenes del fichero, tal cual, como filas de `warehouses` de STG.
Future<void> _sembrarLosDelFichero(BaseLocal base) async {
  for (final a
      in (_leerCasos()['almacenes'] as List).cast<Map<String, dynamic>>()) {
    await base
        .into(base.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: a['id'] as String,
            sucursalCodigo: codigoStg,
            nombre: a['nombre'] as String,
            lat: Value((a['latitud'] as num?)?.toDouble()),
            lng: Value((a['longitud'] as num?)?.toDouble()),
            principal: Value(a['principal'] as bool),
            activo: Value(a['activo'] as bool),
          ),
        );
  }
}

void main() {
  group('la regla, contra el fichero que lee también el servidor', () {
    final doc = _leerCasos();
    final almacenes = [
      for (final a in (doc['almacenes'] as List).cast<Map<String, dynamic>>())
        Almacen(
          id: a['id'] as String,
          sucursalCodigo: codigoStg,
          nombre: a['nombre'] as String,
          lat: (a['latitud'] as num?)?.toDouble(),
          lng: (a['longitud'] as num?)?.toDouble(),
          principal: a['principal'] as bool,
          activo: a['activo'] as bool,
        ),
    ];

    test('el fichero está y trae los casos que importan', () {
      final nombres = [
        for (final c in (doc['casos'] as List).cast<Map<String, dynamic>>())
          c['nombre'],
      ];
      expect(
        nombres,
        containsAll([
          'sin-punto-sale-del-principal',
          'con-punto-sale-de-el',
          'de-otra-sucursal',
          'dado-de-baja',
          'sin-ubicacion',
          'en-el-golfo-de-guinea',
        ]),
        reason:
            'sin estos casos la regla del aparato y la del servidor pueden '
            'separarse sin que salte nada (§3-bis)',
      );
    });

    for (final c in (doc['casos'] as List).cast<Map<String, dynamic>>()) {
      test('${c['nombre']}', () {
        final r = puntoDeSalida(
          almacenId: c['almacenId'] as String?,
          deLaSucursal: almacenes,
          sucursal: doc['sucursal'] as String,
        );
        if (c['saleDe'] case final String id) {
          expect(r.sale?.id, id, reason: '${c['nota'] ?? ''}');
          expect(r.no, isNull);
        } else {
          expect(
            r.sale,
            isNull,
            reason: 'un punto que no sirve NO cae al principal en silencio',
          );
          expect(r.no, c['rechazo']);
          expect(
            noSalePorSuPunto(doc['zona'] as String, r.no!),
            c['rechazoAlArmar'],
          );
        }
      });
    }
  });

  group('el gesto, la bajada y el armado', () {
    late BaseLocal base;
    late ColaDeSalida cola;
    late ConsultasTablero consultas;
    late RepositorioTablero aparato;
    late RepositorioTablero web;
    late ServidorFalso servidor;
    late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

    setUp(() async {
      base = baseDePrueba();
      cola = ColaDeSalida(base);
      consultas = ConsultasTablero(base);
      aparato = RepositorioTablero(base, cola);
      contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{});
      servidor = ServidorFalso((p) => contesta(p));
      final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
        ..httpClientAdapter = servidor;
      web = RepositorioTablero(
        base,
        cola,
        enVivo: EscrituraEnVivo(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
      );
      await sembrarSucursal(base);
      await _sembrarLosDelFichero(base);
    });

    tearDown(() => base.close());

    Future<ColumnaTablero> zona(String id) async =>
        (await consultas.columnas(sucursalStg)).singleWhere((c) => c.id == id);

    test(
      'APK: el punto se guarda, se lee y va a la cola con almacenId',
      () async {
        final centro = await aparato.crearColumna(
          sucursalId: sucursalStg,
          nombre: 'Centro',
        );
        expect(
          (await zona(centro)).sale?.nombre,
          'PV-STGO',
          reason: 'sin punto, sale del principal',
        );

        await aparato.elegirPuntoDeSalida(centro, 'alm-aurora');

        final leida = await zona(centro);
        expect((leida.almacenId, leida.sale?.nombre), ('alm-aurora', 'AURORA'));
        final ultimo = (await cola.lote()).last;
        expect(
          (ultimo.metodo, ultimo.ruta),
          ('PATCH', '/board/columns/$centro'),
        );
        expect(jsonDecode(ultimo.cuerpo), {'almacenId': 'alm-aurora'});

        // Y QUITARLO TAMBIÉN VIAJA: `null` presente es «quítamelo».
        await aparato.elegirPuntoDeSalida(centro, null);
        expect((await zona(centro)).almacenId, isNull);
        expect(jsonDecode((await cola.lote()).last.cuerpo), {
          'almacenId': null,
        });
      },
    );

    test(
      'APK: un punto que el servidor rechazaría NO se encola, y se dice igual',
      () async {
        final centro = await aparato.crearColumna(
          sucursalId: sucursalStg,
          nombre: 'Centro',
        );
        final antes = (await cola.lote()).length;
        await expectLater(
          () => aparato.elegirPuntoDeSalida(centro, 'alm-sin-punto'),
          throwsA(
            isA<RechazoDelTablero>().having(
              (r) => r.mensaje,
              'mensaje',
              '«Parranda Oferta» no tiene la ubicación puesta en Almacenes',
            ),
          ),
        );
        expect(
          (await cola.lote()).length,
          antes,
          reason: 'encolado, el «no» llegaría horas después a la bandeja',
        );
        expect((await zona(centro)).almacenId, isNull);
      },
    );

    test('WEB: va directo al servidor, nada a la cola', () async {
      final centro = await web.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      servidor.vistas.clear();

      await web.elegirPuntoDeSalida(centro, 'alm-aurora');

      expect(servidor.vistas.single.metodo, 'PATCH');
      expect(servidor.vistas.single.ruta, '/board/columns/$centro');
      expect(servidor.vistas.single.cuerpo, {'almacenId': 'alm-aurora'});
      expect(await cola.lote(), isEmpty);
      expect((await zona(centro)).almacenId, 'alm-aurora');
    });

    test(
      'WEB: un 400 se dice con su motivo literal y la zona no cambia',
      () async {
        final centro = await web.crearColumna(
          sucursalId: sucursalStg,
          nombre: 'Centro',
        );
        const elNo = "No existe el almacén 'alm-aurora' en Santiago";
        contesta = (_) async =>
            RespuestaFalsa(400, const <String, Object?>{'error': elNo});

        await expectLater(
          () => web.elegirPuntoDeSalida(centro, 'alm-aurora'),
          throwsA(
            isA<RechazoDelTablero>().having((r) => r.mensaje, 'mensaje', elNo),
          ),
        );
        expect(
          (await zona(centro)).almacenId,
          isNull,
          reason: 'el «no» deshace la transacción: la zona no se movió',
        );
        expect(await cola.lote(), isEmpty);
      },
    );

    test(
      'una zona nueva nace con el punto que se le da, y sin él no lo manda',
      () async {
        final conPunto = await aparato.crearColumna(
          sucursalId: sucursalStg,
          nombre: 'Aurora',
          almacenId: 'alm-aurora',
        );
        expect((await zona(conPunto)).almacenId, 'alm-aurora');
        expect(
          (jsonDecode((await cola.lote()).last.cuerpo) as Map)['almacenId'],
          'alm-aurora',
        );

        await aparato.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
        expect(
          (jsonDecode((await cola.lote()).last.cuerpo) as Map).containsKey(
            'almacenId',
          ),
          isFalse,
          reason: 'ausente es «no lo toques»: sin punto, el principal',
        );
      },
    );

    group('el armado local', () {
      setUp(() async {
        await sembrarCamion(base, id: 'v1');
        await sembrarPedido(base, id: 'p1', aGrados: 0.01);
      });

      Future<Ruta> armarDesde(String? almacenId) async {
        final z = await aparato.crearColumna(
          sucursalId: sucursalStg,
          nombre: 'Centro',
          vehiculoId: 'v1',
          almacenId: almacenId,
        );
        await aparato.colocar(pedidoId: 'p1', columnaId: z);
        final id = await aparato.armarRuta(
          columnaId: z,
          sucursalId: sucursalStg,
        );
        return (base.select(
          base.routes,
        )..where((r) => r.id.equals(id))).getSingle();
      }

      test('sale del punto de SU zona: AURORA, no el principal', () async {
        final ruta = await armarDesde('alm-aurora');
        expect(
          (ruta.originLat, ruta.originLng, ruta.originAddress),
          (20.0311, -75.7902, 'AURORA'),
        );
        final p1 = await (base.select(
          base.orders,
        )..where((o) => o.id.equals('p1'))).getSingle();
        expect(
          p1.segmentKm,
          closeTo(
            kmHaversine(20.0311, -75.7902, almacenLat + 0.01, almacenLng),
            0.05,
          ),
          reason: 'los km de la parada, desde el punto de su zona',
        );
        // EL CIRCUITO, que es lo que se cobra: ida a la única parada y vuelta a
        // AURORA. Desde el principal saldrían 2,2 km y no 6,6.
        final ida = kmHaversine(
          20.0311,
          -75.7902,
          almacenLat + 0.01,
          almacenLng,
        );
        expect(
          ruta.totalDistance,
          closeTo(2 * ida, 1e-6),
          reason:
              'totalDistance tiene que ser el circuito desde AURORA (${2 * ida} '
              'km); desde el principal serían '
              '${2 * kmHaversine(almacenLat, almacenLng, almacenLat + 0.01, almacenLng)}',
        );
      });

      test('y sin punto, del principal (PV-STGO)', () async {
        final ruta = await armarDesde(null);
        expect(
          (ruta.originLat, ruta.originLng, ruta.originAddress),
          (20.0247, -75.8219, 'PV-STGO'),
        );
        expect(
          ruta.totalDistance,
          closeTo(
            2 *
                kmHaversine(
                  almacenLat,
                  almacenLng,
                  almacenLat + 0.01,
                  almacenLng,
                ),
            1e-6,
          ),
        );
      });

      test('un punto que dejó de servir NO cae al principal: el «no» del servidor', () async {
        final z = await aparato.crearColumna(
          sucursalId: sucursalStg,
          nombre: 'Centro',
          vehiculoId: 'v1',
          almacenId: 'alm-aurora',
        );
        // Accesos lo da de baja DESPUÉS de elegirlo.
        await (base.update(base.warehouses)
              ..where((w) => w.id.equals('alm-aurora')))
            .write(const WarehousesCompanion(activo: Value(false)));
        // La zona está VACÍA: el «no» del punto va antes que «no hay nada».
        await expectLater(
          () => aparato.armarRuta(columnaId: z, sucursalId: sucursalStg),
          throwsA(
            isA<RechazoDelTablero>().having(
              (r) => r.mensaje,
              'mensaje',
              'La zona «Centro» no puede salir de su punto de salida: «AURORA» '
                  'está dado de baja en Accesos. Elige otro en «Punto de salida».',
            ),
          ),
        );
        expect(await base.select(base.routes).get(), isEmpty);
      });
    });

    test('los km de lo puesto, desde el punto de su zona', () async {
      await sembrarPedido(base, id: 'p1', aGrados: 0.01);
      await sembrarPedido(base, id: 'p2', aGrados: 0.01);
      final aurora = await aparato.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Aurora',
        almacenId: 'alm-aurora',
      );
      final centro = await aparato.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      await aparato.colocar(pedidoId: 'p1', columnaId: aurora);
      await aparato.colocar(pedidoId: 'p2', columnaId: centro);
      const arriba = AlmacenOrigen(id: 'x', nombre: 'x', lat: 0, lng: 0);

      final km = {
        for (final t in await consultas.colocados(sucursalStg, arriba))
          t.pedido.pedidoId: t.pedido.kmAlAlmacen,
      };
      final destino = (almacenLat + 0.01, almacenLng);
      expect(
        km['p1'],
        closeTo(kmHaversine(20.0311, -75.7902, destino.$1, destino.$2), 1e-9),
      );
      expect(
        km['p2'],
        closeTo(kmHaversine(20.0247, -75.8219, destino.$1, destino.$2), 1e-9),
        reason: 'sin punto, desde el principal: el de arriba no se usa',
      );
    });

    test(
      'la bajada del tablero guarda el almacenId de cada zona ("" = sin punto)',
      () async {
        contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{
          'columnas': [
            {
              'id': 'z1',
              'nombre': 'Aurora',
              'posicion': 1,
              'almacenId': 'alm-aurora',
              'almacen': {'id': 'alm-aurora', 'nombre': 'AURORA'},
            },
            {
              'id': 'z2',
              'nombre': 'Centro',
              'posicion': 2,
              'almacenId': null,
              'almacen': null,
            },
            {'id': 'z3', 'nombre': 'Vacía', 'posicion': 3, 'almacenId': ''},
          ],
          'colocados': <Object?>[],
        });
        final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
          ..httpClientAdapter = servidor;
        await ServicioTablero(
          base,
          ClienteApi(dio: dio, esperas: const <Duration>[]),
          RegistroDeFrescura(base),
        ).descargar(sucursalStg);

        expect(
          {
            for (final c in await consultas.columnas(sucursalStg))
              c.id: c.almacenId,
          },
          {'z1': 'alm-aurora', 'z2': null, 'z3': null},
        );
      },
    );
  });

  group('las zonas van agrupadas por su punto de salida', () {
    const pv = AlmacenOrigen(id: 'alm-pv', nombre: 'PV-STGO', lat: 1, lng: 1);
    const aurora = AlmacenOrigen(
      id: 'alm-aurora',
      nombre: 'AURORA',
      lat: 2,
      lng: 2,
    );

    ColumnaTablero z(String id, {AlmacenOrigen? sale, String? almacenId}) =>
        ColumnaTablero(
          id: id,
          branchId: sucursalStg,
          nombre: id,
          posicion: 0,
          pedidos: 0,
          pesoKg: 0,
          costoUsd: 0,
          almacenId: almacenId,
          sale: sale,
        );

    test(
      'dos de un punto y una de otro salen juntas, el principal primero',
      () {
        final orden = zonasPorPunto([
          z('A', sale: aurora, almacenId: 'alm-aurora'),
          z('B', sale: pv),
          z('C', sale: aurora, almacenId: 'alm-aurora'),
          z('D', sale: pv),
        ], 'alm-pv');
        expect([for (final c in orden) c.id], ['B', 'D', 'A', 'C']);
      },
    );

    test('detrás del principal, cada almacén por su NOMBRE', () {
      // El id de ZETA va ANTES que el de AURORA y ZETA aparece primero: así ni
      // ordenar por id ni por aparición sale igual que ordenar por nombre.
      const zeta = AlmacenOrigen(id: 'alm-a', nombre: 'ZETA', lat: 3, lng: 3);
      final orden = zonasPorPunto([
        z('Z1', sale: zeta, almacenId: 'alm-a'),
        z('A1', sale: aurora, almacenId: 'alm-aurora'),
        z('P', sale: pv),
        z('Z2', sale: zeta, almacenId: 'alm-a'),
      ], 'alm-pv');
      expect(
        [for (final c in orden) c.id],
        ['P', 'A1', 'Z1', 'Z2'],
        reason: 'el principal primero, luego AURORA y luego ZETA, por nombre',
      );
    });

    test('en pareja: con todas del mismo punto, el orden de siempre', () {
      final orden = zonasPorPunto([
        z('C', sale: pv),
        z('A', sale: pv),
        z('B', sale: pv),
      ], 'alm-pv');
      expect([for (final c in orden) c.id], ['C', 'A', 'B']);
    });

    test('cambiar el punto de una zona la lleva a su grupo', () {
      final antes = [
        z('A', sale: pv),
        z('B', sale: aurora, almacenId: 'alm-aurora'),
        z('C', sale: pv),
      ];
      expect(
        [for (final c in zonasPorPunto(antes, 'alm-pv')) c.id],
        ['A', 'C', 'B'],
      );
      final despues = [
        z('A', sale: aurora, almacenId: 'alm-aurora'),
        antes[1],
        antes[2],
      ];
      expect(
        [for (final c in zonasPorPunto(despues, 'alm-pv')) c.id],
        ['C', 'A', 'B'],
      );
    });
  });
}
