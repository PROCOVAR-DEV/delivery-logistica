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
      // Sin cotizar: `pedidoCosto` NULO, que no es lo mismo que cero. Y SIN FACTURA, para que
      // no salga nunca (desde el 16/10/2026 sin cotizar ya no esconde a nadie: lo prueban
      // `d13` y `d15` abajo); así los filtros de aquí no cambian de lista.
      pedidoCosto: null,
      facturaEstado: EstadoFactura.sinFactura,
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
    DateTime? desde,
    DateTime? hasta,
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
      desde: desde,
      hasta: hasta,
      kmMax: kmMax,
      costoMin: costoMin,
      ahora: ahora,
    );
    return [for (final p in lista) p.id]..sort();
  }

  test('sin ningun filtro salen los pedidos elegibles', () async {
    expect(await ids(), ['d1', 'd3', 'd4']);
  });

  // El caso por caso, con el real del issue 10, está en
  // `el_filtro_de_domicilio_cuenta_lo_cobrado_test.dart`.
  group('domicilio', () {
    test(
      '`1` cuenta lo cobrado en la factura: el SIN MARCAR también sale',
      () async {
        // `d4` no está marcado, pero su factura cobra el domicilio (issue 10 de
        // Amado, 15/10/2026). Con sólo la casilla, el arranque del asistente lo
        // escondía.
        expect(await ids(domicilio: '1'), ['d1', 'd3', 'd4']);
      },
    );

    test('`0` es el contrario exacto, y aqui sale vacío', () async {
      // Todo lo que se ofrece trae el domicilio cobrado (regla de entrada), así
      // que nada de esta lista va «sin domicilio», tampoco un NULO cobrado.
      await sembrarPedido(
        base,
        id: 'd5',
        cliente: 'Eva',
        endLat: 21.3,
        endLng: -77.8,
        requiereDomicilio: null,
      );
      expect(await ids(), contains('d5'));
      expect(await ids(domicilio: '0'), isEmpty);
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

  // DESDE/HASTA Y NO UN DÍA (issue 13 de Amado, 15/10/2026). Los elegibles son
  // del 14 a las 8, 9 y 10; `d2` (del 13) no es elegible y no sale nunca.
  group('la fecha del pedido, de desde a hasta con los dos días incluidos', () {
    test('entra lo de dentro, y un día suelto es desde = hasta', () async {
      final dia = DateTime(2026, 9, 14);
      expect(await ids(desde: dia, hasta: dia), ['d1', 'd3', 'd4']);
      expect(await ids(desde: DateTime(2026, 9, 1), hasta: dia), [
        'd1',
        'd3',
        'd4',
      ]);
      expect(await ids(desde: dia), ['d1', 'd3', 'd4']);
      expect(await ids(hasta: dia), ['d1', 'd3', 'd4']);
    });

    test('no entra lo de fuera, por arriba ni por abajo', () async {
      expect(await ids(desde: DateTime(2026, 9, 15)), isEmpty);
      expect(await ids(hasta: DateTime(2026, 9, 13)), isEmpty);
      expect(
        await ids(desde: DateTime(2026, 9, 10), hasta: DateTime(2026, 9, 13)),
        isEmpty,
      );
    });
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

    test('la factura cambiada SÍ se ofrece: al camión va lo facturado', () async {
      // Issue 10 de Amado (15/10/2026): `cambiado` entra a una ruta porque sus
      // renglones ya son los de la factura, y el servidor lo ofrece igual
      // (`ListarPedidosDisponibles`). La pareja es la de abajo (sin factura).
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

    test('sin factura no se ofrece', () async {
      await sembrarPedido(
        base,
        id: 'd9b',
        cliente: 'Iris B',
        facturaEstado: EstadoFactura.sinFactura,
        endLat: 21.331,
        endLng: -77.831,
      );
      expect(await ids(), isNot(contains('d9b')));
    });

    test('sin cotejar tampoco: NULL no es «cuadra»', () async {
      await sembrarPedido(
        base,
        id: 'd10',
        cliente: 'Juan',
        facturaEstado: null,
        endLat: 21.34,
        endLng: -77.84,
      );
      expect(await ids(), isNot(contains('d10')));
    });

    // TEMPORAL 16/10/2026 (Jose): entra todo lo facturado; ni el cobro ni la cotización se
    // exigen (CLAUDE.md §2). La pareja es "sin factura no se ofrece", arriba.
    test('sin domicilio cobrado en la factura SÍ se ofrece', () async {
      await sembrarPedido(
        base,
        id: 'd11',
        cliente: 'Kira',
        facturaDomicilio: 0,
        endLat: 21.35,
        endLng: -77.85,
      );
      await sembrarPedido(
        base,
        id: 'd12',
        cliente: 'Lola',
        facturaDomicilio: null,
        endLat: 21.36,
        endLng: -77.86,
      );
      expect(await ids(), containsAll(['d11', 'd12']));
    });

    test('sin cotizar el domicilio SÍ se ofrece (Amado, PCC25-261014-1435)', () async {
      await sembrarPedido(
        base,
        id: 'd13',
        cliente: 'Mario',
        pedidoCosto: null,
        endLat: 21.37,
        endLng: -77.87,
      );
      expect(await ids(), contains('d13'));
    });

    test('sin cotizar y SIN MARCAR domicilio sí se ofrece (issue 10)', () async {
      // Entrega sólo cotiza los marcados: exigírselo a uno sin marcar lo dejaba
      // fuera para siempre. La pareja es la de arriba (marcado y sin cotizar).
      await sembrarPedido(
        base,
        id: 'd14',
        cliente: 'Nora',
        pedidoCosto: null,
        requiereDomicilio: false,
        endLat: 21.38,
        endLng: -77.88,
      );
      expect(await ids(), contains('d14'));
    });
  });
}
