// Los filtros del PASO 4 del asistente: que pedidos se le ofrecen a una ruta.
//
// Se prueban contra una base sembrada a mano y comparando NUMEROS concretos,
// igual que los de Pedidos. Lo que se vigila aqui es distinto de lo que vigila
// `filtros_test.dart`: alli el riesgo es ensenar de menos, aqui es **ofrecer lo
// que el armado luego rechaza**. Un pedido que sale en esta lista y no se puede
// meter en una ruta es un rechazo tardio fabricado por nosotros.
//
// Las condiciones fijas (de PEDIDO, sin ruta, con coordenadas y factura que
// cuadra) no son configurables y por eso se comprueban primero: son la red que
// sostiene todo lo demas.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ConsultasRutas consultas;

  /// La hora contra la que se decide `en_proceso` y `expirada`.
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasRutas(base);
    await sembrarCatalogo(base);

    // Cuatro elegibles de Camagüey, todos con coordenadas y factura que cuadra.
    await sembrarPedido(
      base,
      id: 'd1',
      cliente: 'Ana',
      vendedor: 'Luis',
      municipio: 'Camagüey',
      pedidoCosto: 10,
      endLat: 21.38,
      endLng: -77.91,
      fecha: DateTime(2026, 9, 14, 8),
      distancia: 3,
      estado: EstadoEnPedido.enProceso,
    );
    await sembrarPedido(
      base,
      id: 'd2',
      cliente: 'Beto',
      vendedor: 'Marta',
      municipio: 'Florida',
      // Sin cotizar: `pedidoCosto` NULO, que no es lo mismo que cero.
      pedidoCosto: null,
      endLat: 21.5,
      endLng: -78.2,
      fecha: DateTime(2026, 9, 13, 8),
      distancia: 40,
      estado: EstadoEnPedido.completada,
    );
    await sembrarPedido(
      base,
      id: 'd3',
      cliente: 'Carla',
      vendedor: 'Luis',
      municipio: 'Camagüey',
      pedidoCosto: 2,
      endLat: 21.4,
      endLng: -77.9,
      fecha: DateTime(2026, 9, 14, 9),
      distancia: 8,
      // Sin estado en PEDIDO: los NULL cuentan como «no completada».
      fechaComprometida: DateTime(2026, 9, 13),
    );
    await sembrarPedido(
      base,
      id: 'd4',
      cliente: 'Dani',
      vendedor: 'Marta',
      municipio: 'Camagüey',
      pedidoCosto: 30,
      endLat: 21.39,
      endLng: -77.92,
      fecha: DateTime(2026, 9, 14, 10),
      // **Sin domicilio**: no hay que llevarselo a casa.
      requiereDomicilio: false,
    );
  });

  tearDown(() => base.close());

  Future<List<String>> ids({
    String q = '',
    String municipio = '',
    String vendedor = '',
    String estado = '',
    String domicilio = '',
    String cotizado = '',
    DateTime? dia,
    double? kmMax,
    double? costoMin,
  }) async {
    final lista = await consultas.disponibles(
      sucursalId: 'B1',
      q: q,
      municipio: municipio,
      vendedor: vendedor,
      estado: estado,
      domicilio: domicilio,
      cotizado: cotizado,
      dia: dia,
      kmMax: kmMax,
      costoMin: costoMin,
      ahora: ahora,
    );
    return [for (final p in lista) p.id]..sort();
  }

  test('sin ningun filtro salen los pedidos elegibles', () async {
    expect(await ids(), ['d1', 'd3', 'd4']);
  });

  group('domicilio', () {
    test('`1` deja fuera al que no lleva domicilio', () async {
      expect(await ids(domicilio: '1'), ['d1', 'd3']);
    });

    test('`0` es «no lleva», y ahi entran tambien los NULOS', () async {
      // Un pedido al que nadie le dijo si lleva domicilio NO lleva domicilio: es
      // lo que hace el servidor, y tratarlo aqui como «no se sabe» dejaria las
      // dos listas descuadradas.
      await sembrarPedido(
        base,
        id: 'd5',
        cliente: 'Eva',
        endLat: 21.3,
        endLng: -77.8,
        requiereDomicilio: null,
      );
      expect(await ids(domicilio: '0'), ['d4', 'd5']);
    });
  });

  group('cotizado', () {
    test('`1` es «tiene precio puesto»', () async {
      expect(await ids(cotizado: '1'), ['d1', 'd3', 'd4']);
    });

    test(
      'los elegibles ya tienen cotización; cero también cuenta como cotizado',
      () async {
        await sembrarPedido(
          base,
          id: 'd6',
          cliente: 'Fran',
          pedidoCosto: 0,
          endLat: 21.31,
          endLng: -77.81,
        );
        expect(await ids(cotizado: '0'), isEmpty);
        expect(await ids(cotizado: '1'), contains('d6'));
      },
    );
  });

  group('estado en PEDIDO', () {
    test('`completada` es sólo la que lo dice', () async {
      expect(await ids(estado: EstadoEnPedido.completada), isEmpty);
    });

    test('`en_proceso` cuenta los que no tienen estado', () async {
      // `d3` no tiene estado, pero su fecha comprometida ya pasó: es expirada.
      // `d4` tampoco tiene estado ni fecha: sigue en proceso.
      expect(await ids(estado: EstadoEnPedido.enProceso), ['d1', 'd4']);
    });

    test('`expirada` es la que se le pasó la fecha comprometida', () async {
      expect(await ids(estado: EstadoDelPedido.expiradaParam), ['d3']);
    });

    test('un valor que no conocemos NO esconde nada', () async {
      // Esconder por una cadena mal escrita es la peor de las dos opciones: la
      // persona ve una lista corta y no sabe por que.
      expect(await ids(estado: 'lo_que_sea'), ['d1', 'd3', 'd4']);
    });
  });

  test('municipio y vendedor son exactos', () async {
    expect(await ids(municipio: 'Florida'), isEmpty);
    expect(await ids(vendedor: 'Luis'), ['d1', 'd3']);
  });

  test('el dia acota el dia natural entero', () async {
    expect(await ids(dia: DateTime(2026, 9, 13)), isEmpty);
  });

  test('`km máx.` y `costo mín.` recortan por arriba y por abajo', () async {
    expect(await ids(kmMax: 10), ['d1', 'd3', 'd4']);
    expect(await ids(costoMin: 10), ['d1', 'd4']);
  });

  test('los filtros se suman entre si', () async {
    expect(
      await ids(vendedor: 'Luis', domicilio: '1', cotizado: '1', kmMax: 5),
      ['d1'],
    );
  });

  group('lo que NO es configurable', () {
    test('un pedido que ya esta en una ruta no se ofrece', () async {
      await sembrarRuta(base, id: 'R9', estado: EstadoRuta.planificada);
      await sembrarPedido(
        base,
        id: 'd7',
        cliente: 'Gema',
        rutaId: 'R9',
        endLat: 21.32,
        endLng: -77.82,
      );
      expect(await ids(), isNot(contains('d7')));
    });

    test('sin coordenadas de entrega no se puede rutear', () async {
      await sembrarPedido(base, id: 'd8', cliente: 'Hugo');
      expect(await ids(), isNot(contains('d8')));
    });

    test('una factura con líneas cambiadas sigue estando facturada', () async {
      await sembrarPedido(
        base,
        id: 'd9',
        cliente: 'Iris',
        facturaEstado: EstadoFactura.cambiado,
        endLat: 21.33,
        endLng: -77.83,
      );
      expect(await ids(), contains('d9'));
    });
  });
}
