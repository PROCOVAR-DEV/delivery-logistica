// LA GUIA DE LA RUTA, de punta a punta sobre la base y la cola de verdad (en memoria):
// marcar parada por parada, «cobrado», la hora del aparato, completar SOLA al marcar la
// ultima, no completar si falta una, cancelar, y lo que sube a la cola.
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/distribuidor/gps/puntos_locales.dart';
import 'package:reparto/distribuidor/gps/recorrido_gps.dart';
import 'package:reparto/distribuidor/guia_de_ruta.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../apoyo/base_de_prueba.dart';
import '../apoyo/reloj_falso.dart';
import '../pantallas/pedidos/sembrar.dart';
import 'apoyo_distribuidor.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;
  late RelojFalso reloj;
  late UbicacionFalsa gps;
  late RecorridoGps recorrido;
  late GuiaDeRuta guia;

  final salida = DateTime(2026, 11, 4, 8);

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(salida);
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(base, cola, reloj: reloj.leer);
    gps = UbicacionFalsa(posicion: posicionEn(salida));
    recorrido = RecorridoGps(
      puntos: PuntosGpsLocales(base),
      servicio: gps,
      haAceptado: () async => true,
      reloj: reloj.leer,
    );
    guia = GuiaDeRuta(
      acciones: acciones,
      consultas: ConsultasRutas(base),
      recorrido: recorrido,
    );
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', estado: EstadoRuta.planificada);
    for (final (i, c) in ['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: c,
        rutaId: 'R1',
        orden: i + 1,
      );
    }
  });

  tearDown(() => base.close());

  Future<Map<String, Object?>> cuerpoDeResultados(int cual) async {
    final apuntes = (await cola.pendientes().first)
        .where((a) => a.ruta == '/routes/R1/results')
        .toList();
    return ColaDeSalida.cuerpoDe(apuntes[cual])! as Map<String, Object?>;
  }

  test('el distribuidor INICIA la ruta y queda en la cola', () async {
    await guia.iniciar('R1');
    final ruta = await ConsultasRutas(base).rutaConTodo('R1').first;
    expect(ruta!.ruta.status, EstadoRuta.enCurso);
    final a = (await cola.pendientes().first).single;
    expect(a.ruta, '/routes/R1');
    expect((ColaDeSalida.cuerpoDe(a)! as Map)['status'], EstadoRuta.enCurso);
  });

  test(
    'marcar guarda la HORA del aparato, el cobrado y la sube en el cuerpo',
    () async {
      await guia.iniciar('R1');
      reloj.ahora = DateTime(2026, 11, 4, 9, 30);
      await guia.marcar('R1', 'p1', SalidaDeParada.entregado, cobrado: true);

      final p1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle();
      expect(p1.resultado, ResultadoParada.entregado);
      expect(p1.resultadoAt, DateTime(2026, 11, 4, 9, 30));
      final cobro = await base.select(base.cobrosDeEntrega).getSingle();
      expect(cobro.pedidoId, 'p1');
      expect(cobro.cobrado, isTrue);

      final cuerpo = await cuerpoDeResultados(0);
      final marca =
          (cuerpo['resultados']! as List).single as Map<String, Object?>;
      expect(marca['orderId'], 'p1');
      expect(marca['resultado'], 'entregado');
      expect(marca['cobrado'], true);
      expect(
        marca['hora'],
        DateTime(2026, 11, 4, 9, 30).toUtc().toIso8601String(),
      );
    },
  );

  test(
    '«No entregada» exige motivo y viaja como devuelto con su nota',
    () async {
      await guia.iniciar('R1');
      await expectLater(
        guia.marcar(
          'R1',
          'p1',
          SalidaDeParada.noEntregada,
          nota: '   ',
          cobrado: true,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (e) => e.mensaje,
            'mensaje',
            msgFaltaElMotivo,
          ),
        ),
      );
      // Y no se marco nada.
      final p1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle();
      expect(p1.resultado, isNull);

      await guia.marcar(
        'R1',
        'p1',
        SalidaDeParada.noEntregada,
        nota: 'cerrado',
        cobrado: true,
      );
      final marca =
          ((await cuerpoDeResultados(0))['resultados']! as List).single
              as Map<String, Object?>;
      expect(marca['resultado'], 'devuelto');
      expect(marca['nota'], 'cerrado');
      expect(marca['cobrado'], false, reason: 'lo no entregado nunca se cobra');
    },
  );

  test('la ruta se COMPLETA SOLA al marcar la ultima, y no antes', () async {
    await guia.iniciar('R1');
    expect(
      await guia.marcar('R1', 'p1', SalidaDeParada.entregado, cobrado: false),
      isFalse,
    );
    expect(
      await guia.marcar('R1', 'p2', SalidaDeParada.entregado, cobrado: false),
      isFalse,
    );
    var ruta = (await ConsultasRutas(base).rutaConTodo('R1').first)!.ruta;
    expect(ruta.status, EstadoRuta.enCurso, reason: 'falta p3: no se completa');

    reloj.ahora = DateTime(2026, 11, 4, 12);
    expect(
      await guia.marcar(
        'R1',
        'p3',
        SalidaDeParada.noEntregada,
        nota: 'no estaba',
        cobrado: false,
      ),
      isTrue,
    );
    ruta = (await ConsultasRutas(base).rutaConTodo('R1').first)!.ruta;
    expect(ruta.status, EstadoRuta.completada);
    expect(ruta.finishedAt, DateTime(2026, 11, 4, 12));

    // Sin conexion queda en la cola EN ORDEN: iniciar, los tres resultados, completar.
    final rutas = [
      for (final a in await cola.pendientes().first) '${a.metodo} ${a.ruta}',
    ];
    expect(rutas, [
      'PATCH /routes/R1',
      'POST /routes/R1/results',
      'POST /routes/R1/results',
      'POST /routes/R1/results',
      'PATCH /routes/R1',
    ]);
    final ultimo = (await cola.pendientes().first).last;
    expect(
      (ColaDeSalida.cuerpoDe(ultimo)! as Map)['status'],
      EstadoRuta.completada,
    );
  });

  test('una ruta sin paradas no se completa sola', () async {
    await sembrarRuta(base, id: 'R2', estado: EstadoRuta.enCurso);
    expect(await guia.completarSiToca('R2'), isFalse);
  });

  group('cancelar la ruta', () {
    test('pide motivo, la deja cancelada y lo encola', () async {
      await guia.iniciar('R1');
      await expectLater(
        guia.cancelar('R1', motivo: ' '),
        throwsA(isA<RechazoLocal>()),
      );
      await guia.cancelar('R1', motivo: 'el camión se averió');
      final ruta = (await ConsultasRutas(base).rutaConTodo('R1').first)!.ruta;
      expect(ruta.status, EstadoRuta.cancelada);
      final a = (await cola.pendientes().first).last;
      expect(a.ruta, '/routes/R1');
      final cuerpo = ColaDeSalida.cuerpoDe(a)! as Map;
      expect(cuerpo['status'], 'cancelled');
      expect(cuerpo['motivo'], 'el camión se averió');
    });

    test('con una parada ya entregada NO se puede cancelar', () async {
      await guia.iniciar('R1');
      await guia.marcar('R1', 'p1', SalidaDeParada.entregado, cobrado: false);
      await expectLater(
        guia.cancelar('R1', motivo: 'x'),
        throwsA(
          isA<RechazoLocal>().having(
            (e) => e.mensaje,
            'm',
            msgNoSeCancelaConEntregas,
          ),
        ),
      );
      final ruta = (await ConsultasRutas(base).rutaConTodo('R1').first)!.ruta;
      expect(ruta.status, EstadoRuta.enCurso);
    });
  });

  test(
    'el GPS guarda un punto en inicio, en cada parada y en el fin',
    () async {
      await guia.iniciar('R1');
      await guia.marcar('R1', 'p1', SalidaDeParada.entregado, cobrado: false);
      await guia.marcar('R1', 'p2', SalidaDeParada.entregado, cobrado: false);
      await guia.marcar('R1', 'p3', SalidaDeParada.entregado, cobrado: false);
      final puntos = await PuntosGpsLocales(base).pendientes();
      expect(
        [for (final p in puntos) p.evento],
        ['inicio', 'parada', 'parada', 'parada', 'fin'],
      );
      expect(
        [for (final p in puntos) p.pedidoId],
        [null, 'p1', 'p2', 'p3', null],
      );
      expect(puntos.every((p) => p.rutaIds.contains('R1')), isTrue);
    },
  );

  test('sin GPS (sin posicion) se trabaja igual y no hay puntos', () async {
    gps.posicion = null;
    await guia.iniciar('R1');
    await guia.marcar('R1', 'p1', SalidaDeParada.entregado, cobrado: false);
    expect(await PuntosGpsLocales(base).cuantosSinSubir(), 0);
    final p1 = await (base.select(
      base.orders,
    )..where((o) => o.id.equals('p1'))).getSingle();
    expect(p1.resultado, ResultadoParada.entregado);
  });
}
