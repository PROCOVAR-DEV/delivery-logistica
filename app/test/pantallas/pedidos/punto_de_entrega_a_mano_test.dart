// EL PUNTO DE ENTREGA PUESTO A MANO (issue 19 de Amado, 20/10/2026).
//
// Las dos formas de la aplicación, en pareja (CLAUDE.md §1 y §3-quinquies):
//
//  * APK y escritorio: la fila local se escribe (punto, marca, el punto del
//    cliente guardado, el km de la parada y el total de la ruta) y se encola UN
//    apunte `PUT|DELETE /orders/{id}/punto`. No sale ni una petición.
//  * Web: va al servidor y se pinta lo que él guardó; un «no» sale con su literal
//    y no se escribe ninguna fila.
//
// Los literales de los «no» son los del servidor, copiados A MANO a propósito:
// una prueba que importara la constante de la acción comprobaría la constante
// contra sí misma, y cambiarla no pondría nada en rojo.
//
// Todo se siembra DENTRO de cada prueba (CLAUDE.md §5).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/pedidos/datos/acciones_de_pedido.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late ServidorFalso servidor;
  late AccionesDePedido enElAparato;
  late AccionesDePedido enLaWeb;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

  setUp(() {
    base = baseDePrueba();
    final reloj = RelojFalso(DateTime.utc(2026, 10, 20, 9));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    enElAparato = AccionesDePedido(base, cola, reloj: reloj.leer);
    contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{});
    servidor = ServidorFalso((p) => contesta(p));
    enLaWeb = AccionesDePedido(
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

  // Origen de la ruta (0,0). El pedido p1 va en R1 en (0, 0.05); el p2, también.
  const origen = Punto(0, 0);
  Future<void> sembrar({
    String estadoRuta = EstadoRuta.planificada,
    bool enRuta = true,
    String? resultado,
    DateTime? entregadoAt,
    double? distancia = 7.5,
  }) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', estado: estadoRuta);
    for (final (id, lng, orden) in [('p1', 0.05, 1), ('p2', 0.10, 2)]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: id,
        rutaId: enRuta ? 'R1' : null,
        orden: enRuta ? orden : null,
        endLat: 0,
        endLng: lng,
        distancia: distancia,
        resultado: id == 'p1' ? resultado : null,
        entregadoAt: id == 'p1' ? entregadoAt : null,
      );
    }
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(segmentKm: Value(5.55)),
    );
    await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
      const RoutesCompanion(totalDistance: Value(1)),
    );
  }

  Future<Pedido> elPedido() =>
      (base.select(base.orders)..where((o) => o.id.equals('p1'))).getSingle();
  Future<Ruta> laRuta() =>
      (base.select(base.routes)..where((r) => r.id.equals('R1'))).getSingle();

  Matcher rechazoCon(String literal) =>
      throwsA(isA<RechazoLocal>().having((r) => r.mensaje, 'mensaje', literal));

  group('APK y escritorio', () {
    test('ponerPunto escribe la fila, recalcula LO LOCAL y encola UN apunte', () async {
      await sembrar();
      await enElAparato.ponerPunto(
        'p1',
        lat: 0.02,
        lng: 0.30,
        direccion: '  Calle 5 entre 6 y 7  ',
      );

      final p = await elPedido();
      expect((p.endLat, p.endLng, p.lat, p.lng), (0.02, 0.30, 0.02, 0.30));
      expect(p.endAddress, 'Calle 5 entre 6 y 7');
      expect(p.puntoManual, isTrue);
      expect(p.puntoManualAt, isNotNull);
      // El punto que traía el cliente se guarda, con su dirección.
      expect((p.puntoClienteLat, p.puntoClienteLng), (0, 0.05));
      expect(p.puntoClienteAddress, 'Entrega p1');
      // El km de la parada: la recta desde el origen de la ruta.
      expect(
        p.segmentKm,
        closeTo(haversineKm(origen, const Punto(0.02, 0.30)), 1e-9),
        reason:
            'SIN ESTO la parada sigue cobrándose con los km del punto viejo',
      );
      // Y el total de la ruta: el circuito con la parada ya movida.
      expect(
        (await laRuta()).totalDistance,
        closeTo(
          kmDelCircuito(origen, const [
            Parada('p1', 0.02, 0.30),
            Parada('p2', 0, 0.10),
          ]),
          1e-9,
        ),
      );
      // Lo que el aparato NO sabe medir (el almacén del pedido) se queda hasta
      // que baje el servidor.
      expect(p.deliveryDistanceKm, 7.5);

      final lote = await cola.lote();
      expect(
        [for (final a in lote) '${a.metodo} ${a.ruta} ${a.cuerpo}'],
        [
          'PUT /orders/p1/punto '
              '{"lat":0.02,"lng":0.3,"direccion":"Calle 5 entre 6 y 7"}',
        ],
      );
      expect(servidor.vistas, isEmpty, reason: 'en la APK no sale nada');
    });

    test(
      'sin dirección el apunte no la lleva y la que había se queda',
      () async {
        await sembrar();
        await enElAparato.ponerPunto(
          'p1',
          lat: 0.02,
          lng: 0.30,
          direccion: '  ',
        );
        expect((await elPedido()).endAddress, 'Entrega p1');
        expect((await cola.lote()).single.cuerpo, '{"lat":0.02,"lng":0.3}');
      },
    );

    test('la segunda vez NO pisa el punto del cliente', () async {
      await sembrar();
      await enElAparato.ponerPunto('p1', lat: 0.02, lng: 0.30);
      await enElAparato.ponerPunto('p1', lat: 0.03, lng: 0.40);
      final p = await elPedido();
      expect((p.endLat, p.endLng), (0.03, 0.40));
      expect(
        (p.puntoClienteLat, p.puntoClienteLng),
        (0, 0.05),
        reason: 'guardar el primero manual como «el del cliente» pierde a dónde volver',
      );
    });

    test('la segunda vez NO pisa lat, lng NI dirección del cliente', () async {
      await sembrar();
      await enElAparato.ponerPunto(
        'p1',
        lat: 0.02,
        lng: 0.30,
        direccion: 'Primera',
      );
      await enElAparato.ponerPunto(
        'p1',
        lat: 0.03,
        lng: 0.40,
        direccion: 'Segunda',
      );
      final p = await elPedido();
      expect((p.endLat, p.endLng, p.endAddress), (0.03, 0.40, 'Segunda'));
      // Los TRES campos del cliente siguen siendo los de antes de la primera vez
      // (la dirección «Entrega p1» la siembra el pedido), no los de la mano.
      expect(
        (p.puntoClienteLat, p.puntoClienteLng, p.puntoClienteAddress),
        (0, 0.05, 'Entrega p1'),
        reason:
            'a la segunda, `end*` ya es el de la mano: guardarlo pierde a '
            'dónde volver',
      );
    });

    test('DOBLE CLIC: dos ponerPunto seguidos, sin esperar, son UNO', () async {
      await sembrar();
      // Sin `await` entre medias: es el segundo clic que llega antes de que
      // termine el primero (medido en Vehículos el 01/10/2026).
      final uno = enElAparato.ponerPunto('p1', lat: 0.02, lng: 0.30);
      final dos = enElAparato.ponerPunto('p1', lat: 0.05, lng: 0.50);
      await Future.wait([uno, dos]);

      final lote = await cola.lote();
      expect(
        [for (final a in lote) '${a.metodo} ${a.ruta} ${a.cuerpo}'],
        ['PUT /orders/p1/punto {"lat":0.02,"lng":0.3}'],
        reason: 'SIN `_unaSola` salen DOS apuntes y el segundo pisa al primero',
      );
      final p = await elPedido();
      expect((p.endLat, p.endLng), (0.02, 0.30));
      // Y el cliente guardado es el original, no el del primer clic.
      expect((p.puntoClienteLat, p.puntoClienteLng), (0, 0.05));
    });

    test('un pedido sin ruta no toca ningún km de ruta', () async {
      await sembrar(enRuta: false);
      await enElAparato.ponerPunto('p1', lat: 0.02, lng: 0.30);
      final p = await elPedido();
      expect(p.puntoManual, isTrue);
      expect(p.segmentKm, 5.55, reason: 'sin ruta no hay parada que medir');
      expect((await laRuta()).totalDistance, 1);
    });

    for (final (nombre, lat, lng) in const [
      ('(0,0) es el golfo de Guinea', 0.0, 0.0),
      ('latitud fuera del planeta', 91.0, 10.0),
      ('longitud fuera del planeta', 10.0, -181.0),
      ('NaN', double.nan, 10.0),
    ]) {
      test('$nombre: el literal del servidor y no se escribe nada', () async {
        await sembrar();
        await expectLater(
          () => enElAparato.ponerPunto('p1', lat: lat, lng: lng),
          rechazoCon('lat y lng tienen que ser un punto del planeta'),
        );
        expect((await elPedido()).puntoManual, isFalse);
        expect(await cola.lote(), isEmpty);
      });
    }

    test('un pedido ENTREGADO no admite punto nuevo', () async {
      await sembrar(resultado: ResultadoParada.entregado);
      await expectLater(
        () => enElAparato.ponerPunto('p1', lat: 0.02, lng: 0.30),
        rechazoCon(
          'La factura ya está entregada: no se le puede cambiar el punto',
        ),
      );
      expect((await elPedido()).puntoManual, isFalse);
      expect(await cola.lote(), isEmpty);
    });

    test(
      'con la hora de entrega puesta también cuenta como entregado',
      () async {
        await sembrar(entregadoAt: DateTime.utc(2026, 10, 20, 8));
        await expectLater(
          () => enElAparato.ponerPunto('p1', lat: 0.02, lng: 0.30),
          rechazoCon(
            'La factura ya está entregada: no se le puede cambiar el punto',
          ),
        );
      },
    );

    test('una ruta COMPLETADA es histórico: ni la fila ni el apunte', () async {
      await sembrar(estadoRuta: EstadoRuta.completada);
      await expectLater(
        () => enElAparato.ponerPunto('p1', lat: 0.02, lng: 0.30),
        rechazoCon(
          'La ruta ya está completada: no se le puede cambiar el punto a sus paradas',
        ),
      );
      final p = await elPedido();
      expect((p.puntoManual, p.endLng), (false, 0.05));
      expect(await cola.lote(), isEmpty);
    });

    test(
      'una ruta sin punto de salida no deja medir: el literal del servidor',
      () async {
        await sembrar();
        await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
          const RoutesCompanion(originLat: Value(null)),
        );
        await expectLater(
          () => enElAparato.ponerPunto('p1', lat: 0.02, lng: 0.30),
          rechazoCon(msgRutaSinOrigen),
        );
        expect((await elPedido()).puntoManual, isFalse);
        expect(await cola.lote(), isEmpty);
      },
    );

    test('un pedido que no existe: «No encontrado»', () async {
      await sembrar();
      await expectLater(
        () => enElAparato.ponerPunto('nadie', lat: 0.02, lng: 0.30),
        rechazoCon('No encontrado'),
      );
    });

    test(
      'volver al punto del cliente lo devuelve, recalcula y encola DELETE',
      () async {
        await sembrar();
        await enElAparato.ponerPunto(
          'p1',
          lat: 0.02,
          lng: 0.30,
          direccion: 'Otra',
        );
        await enElAparato.volverAlPuntoDelCliente('p1');

        final p = await elPedido();
        expect((p.endLat, p.endLng, p.lat, p.lng), (0, 0.05, 0, 0.05));
        expect(p.endAddress, 'Entrega p1');
        expect(p.puntoManual, isFalse);
        expect((p.puntoManualPor, p.puntoManualAt), (null, null));
        expect(
          (p.puntoClienteLat, p.puntoClienteLng, p.puntoClienteAddress),
          (null, null, null),
        );
        expect(
          p.segmentKm,
          closeTo(haversineKm(origen, const Punto(0, 0.05)), 1e-9),
        );
        expect(
          (await laRuta()).totalDistance,
          closeTo(
            kmDelCircuito(origen, const [
              Parada('p1', 0, 0.05),
              Parada('p2', 0, 0.10),
            ]),
            1e-9,
          ),
        );
        expect(
          [
            for (final a in await cola.lote())
              '${a.metodo} ${a.ruta} ${a.cuerpo}',
          ],
          [
            'PUT /orders/p1/punto {"lat":0.02,"lng":0.3,"direccion":"Otra"}',
            'DELETE /orders/p1/punto {}',
          ],
        );
        expect(servidor.vistas, isEmpty);
      },
    );

    test('volver sin punto manual: el literal y nada escrito', () async {
      await sembrar();
      await expectLater(
        () => enElAparato.volverAlPuntoDelCliente('p1'),
        rechazoCon('La factura no tiene un punto puesto a mano'),
      );
      expect(await cola.lote(), isEmpty);
    });

    test('volver sin el punto del cliente guardado: el literal', () async {
      await sembrar();
      await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
        const OrdersCompanion(puntoManual: Value(true)),
      );
      await expectLater(
        () => enElAparato.volverAlPuntoDelCliente('p1'),
        rechazoCon(
          'La factura no guardó el punto del cliente: no se puede volver a él',
        ),
      );
      expect((await elPedido()).puntoManual, isTrue);
    });

    test(
      'volver en una ruta completada o con el pedido entregado: rechazo',
      () async {
        await sembrar(estadoRuta: EstadoRuta.completada);
        await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
          const OrdersCompanion(
            puntoManual: Value(true),
            puntoClienteLat: Value(0),
            puntoClienteLng: Value(0.05),
          ),
        );
        await expectLater(
          () => enElAparato.volverAlPuntoDelCliente('p1'),
          rechazoCon(
            'La ruta ya está completada: no se le puede cambiar el punto a sus paradas',
          ),
        );
        expect(await cola.lote(), isEmpty);
      },
    );
  });

  group('web', () {
    Map<String, Object?> respuestaManual() => {
      'id': 'p1',
      'endLat': 0.02,
      'endLng': 0.30,
      'endAddress': 'Calle 5',
      'puntoManual': true,
      'puntoManualPor': 'Marta Pérez',
      'puntoManualAt': '2026-10-20T09:00:00.000Z',
      'deliveryDistanceKm': 33.3,
      'segmentKm': 44.4,
    };

    test(
      'ponerPunto va DIRECTO al servidor y se pinta lo que él guardó',
      () async {
        await sembrar();
        contesta = (_) async => RespuestaFalsa(200, respuestaManual());
        await enLaWeb.ponerPunto(
          'p1',
          lat: 0.02,
          lng: 0.30,
          direccion: 'Calle 5',
        );

        final vista = servidor.vistas.single;
        expect('${vista.metodo} ${vista.ruta}', 'PUT /orders/p1/punto');
        expect(vista.cuerpo, {
          'lat': 0.02,
          'lng': 0.30,
          'direccion': 'Calle 5',
        });
        final p = await elPedido();
        expect((p.endLat, p.endLng), (0.02, 0.30));
        expect(p.endAddress, 'Calle 5');
        expect((p.puntoManual, p.puntoManualPor), (true, 'Marta Pérez'));
        expect(
          (p.deliveryDistanceKm, p.segmentKm),
          (33.3, 44.4),
          reason: 'los km del servidor, no los de aquí',
        );
        expect((p.puntoClienteLat, p.puntoClienteLng), (0, 0.05));
        expect(await cola.lote(), isEmpty, reason: 'la web no tiene cola');
      },
    );

    test(
      'DOBLE CLIC en la web: dos ponerPunto seguidos son UNA petición',
      () async {
        await sembrar();
        // Un servidor lento: la primera petición sigue en el aire cuando llega
        // el segundo clic.
        final suelta = Completer<void>();
        contesta = (_) async {
          await suelta.future;
          return RespuestaFalsa(200, respuestaManual());
        };
        final uno = enLaWeb.ponerPunto('p1', lat: 0.02, lng: 0.30);
        final dos = enLaWeb.ponerPunto('p1', lat: 0.02, lng: 0.30);
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        suelta.complete();
        await Future.wait([uno, dos]);

        expect(servidor.vistas.map((v) => '${v.metodo} ${v.ruta}'), [
          'PUT /orders/p1/punto',
        ], reason: 'SIN `_unaSola` el segundo clic manda otro PUT');
        expect((await elPedido()).puntoManual, isTrue);
      },
    );

    for (final (codigo, elNo) in const [
      (409, 'El pedido ya está entregado: no se le puede cambiar el punto'),
      (
        409,
        'La ruta ya está completada: no se le puede cambiar el punto a sus paradas',
      ),
      (400, 'lat y lng tienen que ser un punto del planeta'),
      (404, 'No encontrado'),
    ]) {
      test(
        'un $codigo se dice con su motivo LITERAL y no escribe nada',
        () async {
          await sembrar();
          contesta = (_) async => RespuestaFalsa(codigo, {'error': elNo});
          await expectLater(
            () => enLaWeb.ponerPunto('p1', lat: 0.02, lng: 0.30),
            rechazoCon(elNo),
          );
          final p = await elPedido();
          expect((p.puntoManual, p.endLng), (false, 0.05));
          expect(await cola.lote(), isEmpty);
        },
      );
    }

    test(
      'volverAlPuntoDelCliente manda el DELETE y refleja el punto del cliente',
      () async {
        await sembrar();
        await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
          const OrdersCompanion(
            endLat: Value(0.02),
            endLng: Value(0.30),
            puntoManual: Value(true),
            puntoClienteLat: Value(0),
            puntoClienteLng: Value(0.05),
            puntoClienteAddress: Value('Entrega p1'),
          ),
        );
        contesta = (_) async => RespuestaFalsa(200, {
          'id': 'p1',
          'endLat': 0,
          'endLng': 0.05,
          'endAddress': 'Entrega p1',
          'puntoManual': false,
          'puntoManualPor': null,
          'puntoManualAt': null,
          'deliveryDistanceKm': 8.1,
          'segmentKm': 5.55,
        });
        await enLaWeb.volverAlPuntoDelCliente('p1');

        final vista = servidor.vistas.single;
        expect('${vista.metodo} ${vista.ruta}', 'DELETE /orders/p1/punto');
        final p = await elPedido();
        expect(
          (p.puntoManual, p.endLng, p.deliveryDistanceKm),
          (false, 0.05, 8.1),
        );
        expect(p.puntoClienteLat, isNull);
        expect(await cola.lote(), isEmpty);
      },
    );

    test('volver: el 409 del servidor sale literal', () async {
      await sembrar();
      await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
        const OrdersCompanion(
          puntoManual: Value(true),
          puntoClienteLat: Value(0),
          puntoClienteLng: Value(0.05),
        ),
      );
      const elNo = 'El pedido no tiene un punto puesto a mano';
      contesta = (_) async => RespuestaFalsa(409, const {'error': elNo});
      await expectLater(
        () => enLaWeb.volverAlPuntoDelCliente('p1'),
        rechazoCon(elNo),
      );
      expect((await elPedido()).puntoManual, isTrue);
    });
  });
}
