// REORDENAR LAS PARADAS DE UNA RUTA (issue 11 de Amado, 15/10/2026).
//
// Las dos formas de la aplicación, en pareja (CLAUDE.md §1 y §3-quinquies):
//
//  * APK y escritorio: se escribe en la base local (orden, km de cada parada,
//    total y firma) y se encola `PUT /routes/{id}/stops`. No sale ni una
//    petición.
//  * Web: va al servidor y se pinta lo que él guardó; un «no» sale con su
//    motivo literal, no se mueve nada y no se encola nada.
//
// Y «debe impactar en el diseño de la ruta»: el croquis, el enlace de Google
// Maps y los km de la cabecera salen del orden nuevo.
//
// Todo se siembra DENTRO de cada prueba (CLAUDE.md §5).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/enlace_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late ServidorFalso servidor;
  late AccionesDeRuta enElAparato;
  late AccionesDeRuta enLaWeb;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

  setUp(() {
    base = baseDePrueba();
    final reloj = RelojFalso(DateTime.utc(2026, 10, 15, 9));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    enElAparato = AccionesDeRuta(base, cola, reloj: reloj.leer);
    contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{});
    servidor = ServidorFalso((p) => contesta(p));
    enLaWeb = AccionesDeRuta(
      base,
      cola,
      reloj: reloj.leer,
      enVivo: EscrituraEnVivo(
        ClienteApi(
          dio: Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
            ..httpClientAdapter = servidor,
          esperas: const <Duration>[],
        ),
      ),
    );
  });
  tearDown(() => base.close());

  // Origen (0,0); paradas en la recta del ecuador: lejos 0,30 · cerca 0,05 ·
  // medio 0,15. Cargadas en el orden lejos, cerca, medio (el «malo»).
  const origen = Punto(0, 0);
  Future<void> sembrarLaRuta({String estado = EstadoRuta.planificada}) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', estado: estado);
    var n = 0;
    for (final (id, lng) in [
      ('lejos', 0.30),
      ('cerca', 0.05),
      ('medio', 0.15),
    ]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: id,
        folio: 'OP-$id',
        rutaId: 'R1',
        orden: ++n,
        endLat: 0,
        endLng: lng,
      );
    }
    await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
      const RoutesCompanion(totalDistance: Value(1), optimized: Value(true)),
    );
  }

  Future<List<String>> ordenEnLaBase() async => [
    for (final p in await ConsultasRutas(base).paradasDe('R1')) p.id,
  ];
  Future<Ruta> laRuta() =>
      (base.select(base.routes)..where((r) => r.id.equals('R1'))).getSingle();
  double km(List<double> lngs) => kmDelCircuito(origen, [
    for (final (i, l) in lngs.indexed) Parada('$i', 0, l),
  ]);

  group('APK y escritorio', () {
    test(
      'arrastrar mueve el orden, recalcula los km y ENCOLA el apunte',
      () async {
        await sembrarLaRuta();
        await enElAparato.reordenar(
          'R1',
          orden: const ['cerca', 'lejos', 'medio'],
        );

        expect(await ordenEnLaBase(), ['cerca', 'lejos', 'medio']);
        final ruta = await laRuta();
        expect(ruta.totalDistance, closeTo(km([0.05, 0.30, 0.15]), 1e-9));
        expect(ruta.optimized, isFalse, reason: 'el orden lo puso una persona');
        final lejos = await (base.select(
          base.orders,
        )..where((o) => o.id.equals('lejos'))).getSingle();
        expect(
          lejos.segmentKm,
          closeTo(haversineKm(origen, const Punto(0, 0.30)), 1e-9),
          reason: 'el km de la parada es la recta desde el origen',
        );

        final lote = await cola.lote();
        expect(
          [for (final a in lote) '${a.metodo} ${a.ruta} ${a.cuerpo}'],
          ['PUT /routes/R1/stops {"orden":["cerca","lejos","medio"]}'],
        );
        expect(servidor.vistas, isEmpty, reason: 'en la APK no sale nada');
      },
    );

    test(
      'por cercanía: el orden bueno, la firma de la máquina y el apunte',
      () async {
        await sembrarLaRuta();
        await enElAparato.reordenar('R1');

        expect(await ordenEnLaBase(), ['cerca', 'medio', 'lejos']);
        final ruta = await laRuta();
        expect(ruta.totalDistance, closeTo(km([0.05, 0.15, 0.30]), 1e-9));
        expect(ruta.optimized, isTrue);
        final lote = await cola.lote();
        expect(lote.single.cuerpo, '{"porCercania":true}');
      },
    );

    // Una coordenada FUERA DEL PLANETA cuenta como sin punto (`puntoDelPlaneta`,
    // igual que el servidor): al final, sin km, y fuera del circuito. Su NaN se
    // comería los km de la ruta entera.
    test('la parada sin punto medible va al final y sin km', () async {
      await sembrarLaRuta();
      await (base.update(base.orders)..where((o) => o.id.equals('cerca')))
          .write(const OrdersCompanion(endLat: Value(1e308)));
      await enElAparato.reordenar('R1');

      expect(await ordenEnLaBase(), ['medio', 'lejos', 'cerca']);
      final cerca = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('cerca'))).getSingle();
      expect(cerca.segmentKm, isNull);
      expect((await laRuta()).totalDistance, closeTo(km([0.15, 0.30]), 1e-9));
    });

    test(
      'sin punto de salida no se reordena: el literal del servidor',
      () async {
        await sembrarLaRuta();
        await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
          const RoutesCompanion(originLat: Value(null)),
        );
        await expectLater(
          () => enElAparato.reordenar('R1'),
          throwsA(
            isA<RechazoLocal>().having(
              (r) => r.mensaje,
              'mensaje',
              msgRutaSinOrigen,
            ),
          ),
        );
        expect(await ordenEnLaBase(), ['lejos', 'cerca', 'medio']);
        expect(await cola.lote(), isEmpty);
      },
    );

    test('una completada es histórico: no se mueve ni se encola', () async {
      await sembrarLaRuta(estado: EstadoRuta.completada);
      await expectLater(
        () => enElAparato.reordenar(
          'R1',
          orden: const ['cerca', 'lejos', 'medio'],
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            msgRutaCompletada,
          ),
        ),
      );
      expect(await ordenEnLaBase(), ['lejos', 'cerca', 'medio']);
      expect(await cola.lote(), isEmpty);
    });

    test('una lista que no cuadra no reordena a medias', () async {
      await sembrarLaRuta();
      await expectLater(
        () => enElAparato.reordenar('R1', orden: const ['cerca', 'lejos']),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            msgOrdenNoCuadra('falta OP-medio'),
          ),
        ),
      );
      expect(await ordenEnLaBase(), ['lejos', 'cerca', 'medio']);
      expect((await laRuta()).totalDistance, 1);
      expect(await cola.lote(), isEmpty);
    });
  });

  group('web', () {
    Map<String, Object?> laRutaQueDevuelve(List<(String, int)> orden) => {
      'id': 'R1',
      'status': EstadoRuta.planificada,
      'totalDistance': 88.9,
      'optimized': false,
      'orders': [
        for (final (id, n) in orden)
          {'id': id, 'stopOrder': n, 'segmentKm': 4.4},
      ],
    };

    test('va DIRECTO al servidor y se pinta lo que él guardó', () async {
      await sembrarLaRuta();
      contesta = (_) async => RespuestaFalsa(
        200,
        laRutaQueDevuelve([('cerca', 1), ('lejos', 2), ('medio', 3)]),
      );
      await enLaWeb.reordenar('R1', orden: const ['cerca', 'lejos', 'medio']);

      final vista = servidor.vistas.single;
      expect('${vista.metodo} ${vista.ruta}', 'PUT /routes/R1/stops');
      expect(vista.cuerpo, {
        'orden': ['cerca', 'lejos', 'medio'],
      });
      expect(await ordenEnLaBase(), ['cerca', 'lejos', 'medio']);
      final ruta = await laRuta();
      expect(
        ruta.totalDistance,
        88.9,
        reason: 'los km del servidor, no los de aquí',
      );
      expect(ruta.optimized, isFalse);
      expect(await cola.lote(), isEmpty, reason: 'la web no tiene cola');
    });

    test('un 400 se dice con su motivo LITERAL y no mueve nada', () async {
      await sembrarLaRuta();
      const elNo =
          'El nuevo orden repite la parada OP-cerca: cada parada va una sola vez.';
      contesta = (_) async => RespuestaFalsa(400, const {'error': elNo});
      await expectLater(
        () => enLaWeb.reordenar('R1', orden: const ['cerca', 'lejos', 'medio']),
        throwsA(isA<RechazoLocal>().having((r) => r.mensaje, 'mensaje', elNo)),
      );
      expect(await ordenEnLaBase(), ['lejos', 'cerca', 'medio']);
      expect((await laRuta()).totalDistance, 1);
      expect(await cola.lote(), isEmpty);
    });
  });

  // «EL REORDENAMIENTO DEBE IMPACTAR EN EL DISEÑO DE LA RUTA». El croquis, el
  // enlace de Google Maps y el post-despacho leen las paradas de
  // `ConsultasRutas` (por `stopOrder`); la cabecera, `routes.total_distance`.
  test(
    'el croquis, Google Maps y la cabecera salen en el orden nuevo',
    () async {
      await sembrarLaRuta();
      Future<Recorrido> recorridoActual() async => recorridoDe(
        RutaConTodo(
          ruta: await laRuta(),
          paradas: await ConsultasRutas(base).paradasDe('R1'),
        ),
      );
      final antes = enlaceDeLaRuta(await recorridoActual()).url!;
      expect(antes, contains('waypoints=0.0,0.3|0.0,0.05|0.0,0.15'));

      await enElAparato.reordenar('R1');

      final recorrido = await recorridoActual();
      expect(
        [for (final p in recorrido.paradas) '${p.numero}:${p.id}'],
        ['1:cerca', '2:medio', '3:lejos'],
      );
      expect(
        enlaceDeLaRuta(recorrido).url,
        contains('waypoints=0.0,0.05|0.0,0.15|0.0,0.3'),
      );
      expect(
        (await laRuta()).totalDistance,
        closeTo(km([0.05, 0.15, 0.30]), 1e-9),
      );
    },
  );
}
