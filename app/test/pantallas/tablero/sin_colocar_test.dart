import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late RepositorioTablero repo;
  late AlmacenOrigen origen;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    repo = RepositorioTablero(base, ColaDeSalida(base));
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    origen = await consultas.almacenDe(sucursalStg);
  });

  tearDown(() => base.close());

  group('el almacén desde el que se mide', () {
    test('gana el principal con coordenadas', () async {
      await sembrarAlmacen(
        base,
        id: 'alm-2',
        nombre: 'Patio',
        principal: false,
        lat: 21,
      );
      final elegido = await consultas.almacenDe(sucursalStg);
      expect(elegido.nombre, 'Almacén principal');
    });

    test('si ninguno es principal, vale el primero con coordenadas', () async {
      await base.delete(base.warehouses).go();
      await sembrarAlmacen(
        base,
        id: 'alm-2',
        nombre: 'Patio',
        principal: false,
      );
      final elegido = await consultas.almacenDe(sucursalStg);
      expect(elegido.nombre, 'Patio');
    });

    test(
      'sin ninguno con coordenadas NO HAY TABLERO, y se dice cuál',
      () async {
        await base.delete(base.warehouses).go();
        await sembrarAlmacen(base, id: 'alm-3', lat: null, lng: null);
        expect(
          () => consultas.almacenDe(sucursalStg),
          throwsA(
            isA<SinAlmacenConCoordenadas>().having(
              (e) => e.mensaje,
              'mensaje',
              'Santiago no tiene ningún almacén con coordenadas',
            ),
          ),
        );
      },
    );

    test('(0,0) no son coordenadas: es el golfo de Guinea', () async {
      await base.delete(base.warehouses).go();
      await sembrarAlmacen(base, id: 'alm-4', lat: 0, lng: 0);
      expect(
        () => consultas.almacenDe(sucursalStg),
        throwsA(isA<SinAlmacenConCoordenadas>()),
      );
    });
  });

  // EL ORDEN DE «SIN COLOCAR» ES CRONOLÓGICO DESDE EL 14/10/2026.
  //
  // Amado, issue 6, punto 2: «la lista de facturas (pedidos) debe salir ordenada
  // cronológicamente de lo más viejo a lo más reciente». Hasta ese día iba por
  // cercanía al almacén. La fecha es la de la factura (`facturaAt`) y, si no la
  // trae, la del pedido; sin ninguna va al final; el desempate es el id. Es el
  // mismo `ORDER BY` que el del servidor (`ListarPedidosSinColocar`).
  //
  // Los datos de cada prueba están hechos para que ningún otro orden —el de
  // cercanía de antes, el del id, el de inserción— dé lo esperado: cada una
  // tiene su pareja en la propia siembra.
  group('el orden: del más viejo al más reciente por la fecha de la factura', () {
    List<String> ids(MitadIzquierda m) =>
        m.pedidos.map((p) => p.pedidoId).toList();

    test(
      'es cronológico, NO por cercanía: el más lejano y más viejo va primero',
      () async {
        // Por cercanía saldría cerca, medio, lejos. Aquí el más lejano es el
        // más VIEJO, y tiene que ser el primero.
        await sembrarPedido(
          base,
          id: 'cerca',
          aGrados: 0.01,
          fecha: DateTime(2026, 9, 14, 18),
        );
        await sembrarPedido(
          base,
          id: 'medio',
          aGrados: 0.10,
          fecha: DateTime(2026, 9, 14, 12),
        );
        await sembrarPedido(
          base,
          id: 'lejos',
          aGrados: 0.30,
          fecha: DateTime(2026, 9, 14, 6),
        );

        final izquierda = await consultas.sinColocar(sucursalStg, origen);
        expect(ids(izquierda), ['lejos', 'medio', 'cerca']);
        // La cercanía ya no ordena, pero se sigue calculando: la tarjeta la enseña.
        expect(
          izquierda.pedidos.first.kmAlAlmacen,
          closeTo(gradoKm * 0.30, 0.5),
        );
      },
    );

    test('la fecha de la FACTURA manda sobre la del pedido', () async {
      // El pedido más viejo (el 1) se facturó el 9, y el más nuevo (el 14)
      // se facturó el 3: por factura va primero el segundo. Por fecha de
      // pedido saldría al revés.
      await sembrarPedido(
        base,
        id: 'pedido-viejo-facturado-tarde',
        fecha: DateTime(2026, 10, 1, 9),
        facturaAt: DateTime(2026, 10, 9, 9),
      );
      await sembrarPedido(
        base,
        id: 'pedido-nuevo-facturado-pronto',
        fecha: DateTime(2026, 10, 14, 9),
        facturaAt: DateTime(2026, 10, 3, 9),
      );

      final izquierda = await consultas.sinColocar(sucursalStg, origen);
      expect(ids(izquierda), [
        'pedido-nuevo-facturado-pronto',
        'pedido-viejo-facturado-tarde',
      ]);
    });

    test(
      'sin fecha de factura vale la del pedido, mezclado con los que la tienen',
      () async {
        await sembrarPedido(
          base,
          id: 'con-factura-el-9',
          fecha: DateTime(2026, 10, 1, 9),
          facturaAt: DateTime(2026, 10, 9, 9),
        );
        // Sin `facturaAt`: entra con la fecha de su pedido, el 5, y va ANTES.
        await sembrarPedido(
          base,
          id: 'sin-factura-pedido-el-5',
          fecha: DateTime(2026, 10, 5, 9),
        );
        // Y el del 12 va detrás de los dos.
        await sembrarPedido(
          base,
          id: 'sin-factura-pedido-el-12',
          fecha: DateTime(2026, 10, 12, 9),
        );

        final izquierda = await consultas.sinColocar(sucursalStg, origen);
        expect(ids(izquierda), [
          'sin-factura-pedido-el-5',
          'con-factura-el-9',
          'sin-factura-pedido-el-12',
        ]);
      },
    );

    test('un pedido SIN NINGUNA fecha va al final, no al principio', () async {
      await sembrarPedido(base, id: 'aa-sin-fecha');
      await sembrarPedido(
        base,
        id: 'zz-con-fecha',
        fecha: DateTime(2026, 10, 14, 9),
      );
      // `sembrarPedido` siempre pone fecha de pedido: se la quita después.
      await (base.update(
        base.orders,
      )..where((t) => t.id.equals('aa-sin-fecha'))).write(
        const OrdersCompanion(orderDate: Value(null), createdAt: Value(null)),
      );

      final izquierda = await consultas.sinColocar(sucursalStg, origen);
      // Por id (aa < zz) o por «un null es el más viejo» saldría primero el
      // sin fecha. Tiene que salir el último.
      expect(ids(izquierda), ['zz-con-fecha', 'aa-sin-fecha']);
    });

    test('el sin fecha va el ÚLTIMO por el ORDEN DEL APARATO, no porque la base '
        'ya lo dé así (`NULLS LAST`, como el servidor)', () async {
      // La de arriba no basta, y no por floja: la consulta recorre
      // `orders_sucursal_fecha_idx` (`order_date DESC`), que ya entrega los sin
      // fecha DETRÁS, y un `sort` que los pusiera delante no los mueve: con el
      // índice, cambiar el `return 1` de `_porFechaDeFactura` por `-1` sale en
      // verde. Sin el índice la base los da en orden de siembra, y aquí el sin
      // fecha se siembra el PRIMERO: lo que lo manda al final es el `sort`, que
      // es lo que promete `sinColocar` («el orden se hace aquí, no en la
      // consulta»).
      await base.customStatement('DROP INDEX orders_sucursal_fecha_idx');
      await sembrarPedido(base, id: 'm-sin-fecha');
      await sembrarPedido(
        base,
        id: 'a-con-fecha-el-14',
        fecha: DateTime(2026, 10, 14, 9),
      );
      await sembrarPedido(
        base,
        id: 'z-con-fecha-el-2',
        fecha: DateTime(2026, 10, 2, 9),
      );
      await (base.update(
        base.orders,
      )..where((t) => t.id.equals('m-sin-fecha'))).write(
        const OrdersCompanion(
          orderDate: Value(null),
          createdAt: Value(null),
          facturaAt: Value(null),
        ),
      );

      final izquierda = await consultas.sinColocar(sucursalStg, origen);
      expect(ids(izquierda), [
        'z-con-fecha-el-2',
        'a-con-fecha-el-14',
        'm-sin-fecha',
      ]);
    });

    test('a la misma fecha el desempate es estable: el id', () async {
      // Dos facturas anotadas en el mismo instante. Sin un segundo criterio
      // las tarjetas bailan entre dos lecturas delante de quien las está
      // arrastrando. Se siembran en orden inverso al del id.
      final mismoInstante = DateTime(2026, 10, 9, 9);
      await sembrarPedido(base, id: 'b', facturaAt: mismoInstante);
      await sembrarPedido(base, id: 'a', facturaAt: mismoInstante);

      final una = await consultas.sinColocar(sucursalStg, origen);
      final otra = await consultas.sinColocar(sucursalStg, origen);
      expect(ids(una), ['a', 'b']);
      expect(ids(otra), ids(una));
    });

    test(
      'el tope corta la cola, no la cabeza: se ven los más viejos',
      () async {
        // `limite` pinta de una vez y `total` dice cuántos hay. Con el orden
        // cronológico lo que queda fuera son los de factura MÁS RECIENTE.
        for (var i = 1; i <= 4; i++) {
          await sembrarPedido(
            base,
            id: 'p$i',
            fecha: DateTime(2026, 10, i, 9),
            // Cuanto más viejo, más lejos: la cercanía iría al revés.
            aGrados: 0.5 - i * 0.1,
          );
        }

        final izquierda = await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: const FiltrosSinColocar(limite: 2),
        );
        expect(ids(izquierda), ['p1', 'p2']);
        expect(izquierda.total, 4);
        expect(izquierda.truncada, isTrue);
      },
    );
  });

  group('qué entra y qué no en la mitad izquierda', () {
    test(
      'las cinco condiciones del armador, ni una más ni una menos',
      () async {
        await sembrarPedido(base, id: 'bueno');
        await sembrarPedido(base, id: 'con-ruta', rutaId: 'r1');
        await sembrarPedido(base, id: 'sin-coords', conCoordenadas: false);
        await sembrarPedido(base, id: 'sin-cotejar', facturaEstado: null);
        await sembrarPedido(
          base,
          id: 'sin-factura',
          facturaEstado: EstadoFactura.sinFactura,
        );
        await sembrarPedido(base, id: 'a-mano', fuente: null);
        await sembrarPedido(base, id: 'de-otra', sucursal: 'suc-hol');
        // `cambiado` SI se puede repartir: lo que sube al camion son las lineas
        // de la factura.
        await sembrarPedido(
          base,
          id: 'cambiado',
          facturaEstado: EstadoFactura.cambiado,
        );

        final izquierda = await consultas.sinColocar(sucursalStg, origen);
        expect(izquierda.pedidos.map((p) => p.pedidoId).toSet(), {
          'bueno',
          'cambiado',
        });
      },
    );

    test('lo que ya está colocado sale de la lista', () async {
      await sembrarPedido(base, id: 'p1');
      await sembrarPedido(base, id: 'p2');
      final columna = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      await repo.colocar(pedidoId: 'p1', columnaId: columna);

      final izquierda = await consultas.sinColocar(sucursalStg, origen);
      expect(izquierda.pedidos.map((p) => p.pedidoId).toList(), ['p2']);
      expect(izquierda.total, 1);
    });
  });

  group('los filtros', () {
    setUp(() async {
      await sembrarPedido(
        base,
        id: 'p1',
        cliente: 'Bodega La Palma',
        municipio: 'Songo',
        vendedor: 'Ana',
        aGrados: 0.02,
      );
      await sembrarPedido(
        base,
        id: 'p2',
        cliente: 'Cafetería Central',
        municipio: 'Santiago de Cuba',
        vendedor: 'Luis',
        aGrados: 0.40,
        fecha: DateTime(2026, 9, 13, 10),
      );
      await sembrarRenglon(
        base,
        id: 'r1',
        pedidoId: 'p2',
        descripcion: 'Malta Bucanero 24u',
      );
    });

    test('la búsqueda mira también el contenido de los renglones', () async {
      final izquierda = await consultas.sinColocar(
        sucursalStg,
        origen,
        filtros: const FiltrosSinColocar(q: 'malta'),
      );
      expect(izquierda.pedidos.single.pedidoId, 'p2');
    });

    test('la búsqueda mira el cliente', () async {
      final izquierda = await consultas.sinColocar(
        sucursalStg,
        origen,
        filtros: const FiltrosSinColocar(q: 'palma'),
      );
      expect(izquierda.pedidos.single.pedidoId, 'p1');
    });

    test('municipio, vendedor y corte por kilómetros', () async {
      expect(
        (await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: const FiltrosSinColocar(municipio: 'Songo'),
        )).pedidos.single.pedidoId,
        'p1',
      );
      expect(
        (await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: const FiltrosSinColocar(vendedores: ['Luis']),
        )).pedidos.single.pedidoId,
        'p2',
      );
      // VARIOS vendedores = la unión (issue 18 de Amado, 16/10/2026): «pueden haber
      // pocos domicilios y se combinan los de ambos».
      Future<List<String>> con(List<String> vendedores) async => [
        for (final p in (await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: FiltrosSinColocar(vendedores: vendedores),
        )).pedidos)
          p.pedidoId,
      ]..sort();
      expect(await con(['Ana', 'Luis']), ['p1', 'p2']);
      expect(await con(['Luis', 'Nadie']), ['p2']);
      expect(await con(['Nadie']), isEmpty);
      expect(await con([]), ['p1', 'p2']);
      expect(
        (await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: const FiltrosSinColocar(kmMax: 10),
        )).pedidos.single.pedidoId,
        'p1',
      );
    });

    // DESDE/HASTA Y NO UN DÍA (issue 13 de Amado, 15/10/2026). `p2` es del 13
    // a las 10 y `p1` del 14 a las 8: los dos bordes entran, lo de fuera no.
    group(
      'la fecha del pedido, de desde a hasta con los dos días incluidos',
      () {
        Future<List<String>> salen(DateTime? desde, DateTime? hasta) async {
          final izquierda = await consultas.sinColocar(
            sucursalStg,
            origen,
            filtros: FiltrosSinColocar(desde: desde, hasta: hasta),
          );
          expect(
            izquierda.total,
            izquierda.pedidos.length,
            reason: 'el número de arriba es el de la misma lista',
          );
          return [for (final p in izquierda.pedidos) p.pedidoId]..sort();
        }

        test('entra lo de dentro, en los dos bordes', () async {
          expect(await salen(DateTime(2026, 9, 13), DateTime(2026, 9, 14)), [
            'p1',
            'p2',
          ]);
          expect(await salen(DateTime(2026, 9, 14), null), ['p1']);
          expect(await salen(null, DateTime(2026, 9, 13)), ['p2']);
        });

        test('un día suelto es desde = hasta, el día entero', () async {
          expect(await salen(DateTime(2026, 9, 13), DateTime(2026, 9, 13)), [
            'p2',
          ]);
        });

        test('no entra lo de fuera, por arriba ni por abajo', () async {
          expect(await salen(DateTime(2026, 9, 15), null), isEmpty);
          expect(await salen(null, DateTime(2026, 9, 12)), isEmpty);
        });

        test('sin fecha de PEDIDO va por la de copia, no desaparece', () async {
          await sembrarPedido(base, id: 'p3', cliente: 'Sin fecha');
          await (base.update(
            base.orders,
          )..where((o) => o.id.equals('p3'))).write(
            OrdersCompanion(
              orderDate: const Value(null),
              createdAt: Value(DateTime(2026, 9, 12, 23, 30)),
            ),
          );
          expect(await salen(DateTime(2026, 9, 12), DateTime(2026, 9, 12)), [
            'p3',
          ]);
          expect(await salen(DateTime(2026, 9, 13), null), ['p1', 'p2']);
          // Y el hasta también lo corta a él: creado el 12, fuera de «hasta el 11».
          expect(await salen(null, DateTime(2026, 9, 11)), isEmpty);
        });

        test('con sólo desde o sólo hasta HAY filtro puesto', () {
          // Es lo que enciende el punto del embudo y cambia «No queda ningún
          // pedido por colocar» por «Ningún pedido con estos filtros».
          expect(
            FiltrosSinColocar(desde: DateTime(2026, 9, 13)).hayAlguno,
            isTrue,
          );
          expect(
            FiltrosSinColocar(hasta: DateTime(2026, 9, 13)).hayAlguno,
            isTrue,
          );
          expect(const FiltrosSinColocar().hayAlguno, isFalse);
        });
      },
    );

    test('el total es el de los mismos filtros, no el de la página', () async {
      final izquierda = await consultas.sinColocar(
        sucursalStg,
        origen,
        filtros: const FiltrosSinColocar(limite: 1),
      );
      expect(izquierda.pedidos.length, 1);
      expect(izquierda.total, 2);
      expect(izquierda.truncada, isTrue);
    });
  });

  test('dos pedidos del mismo cliente son DOS tarjetas, y se dice', () async {
    // El sufijo del folio es nuestro: X-2992 y X-2992-2 son dos pedidos, con su
    // peso y su domicilio cada uno.
    await sembrarPedido(
      base,
      id: 'x1',
      cliente: 'Bodega La Palma',
      operacion: 'X-2992',
    );
    await sembrarPedido(
      base,
      id: 'x2',
      cliente: 'Bodega La Palma',
      operacion: 'X-2992-2',
    );

    final izquierda = await consultas.sinColocar(sucursalStg, origen);
    expect(izquierda.pedidos.length, 2, reason: 'no se funden');
    expect(izquierda.pedidos.every((p) => p.mismoCliente == 2), isTrue);
    // Y caen seguidas, que es lo que hace que se vean juntas.
    expect(
      izquierda.pedidos.map((p) => p.operationNumber).toList(),
      containsAll(<String>['X-2992', 'X-2992-2']),
    );
  });

  // EL TABLERO SOLO OFRECE LO QUE VA A DOMICILIO, Y LO QUE LO DICE ES EL COBRO.
  //
  // Desde el 25/09/2026 lo decia la casilla del vendedor (`requiereDomicilio`):
  // con los datos de Santiago se ofrecian 246 pedidos de los que 183 no eran de
  // domicilio (Jose: «sin domicilio no los pongas, por que eso no lleva
  // domicilio»). Desde el 07/10/2026 hay una prueba mejor, la linea «ENTREGA A
  // DOMICILIO» cobrada en la factura (`facturaDomicilio > 0`), y el 15/10/2026
  // (issue 10 de Amado) la casilla dejo de mandar: PBF26-2610131268 venia SIN
  // marcar, con 1.31 de domicilio cobrado, y no salia nunca en el tablero.
  //
  // LAS PRUEBAS VAN EN PAREJA: con solo la mitad de «no sale» se cumpliria igual
  // devolviendo SIEMPRE cero.
  group('sin domicilio cobrado SÍ se coloca (TEMPORAL 16/10/2026, Jose)', () {
    test('el que cobro el domicilio sale, y el que no, también', () async {
      await sembrarPedido(base, id: 'con-domicilio');
      await sembrarPedido(base, id: 'sin-domicilio', facturaDomicilio: null);

      final mitad = await consultas.sinColocar(sucursalStg, origen);
      final ids = mitad.pedidos.map((p) => p.pedidoId).toSet();

      expect(
        ids,
        contains('con-domicilio'),
        reason:
            'el pedido que SI va a domicilio no sale: el tablero se queda sin '
            'nada que preparar',
      );
      expect(
        ids,
        contains('sin-domicilio'),
        reason: 'por ahora entra todo lo facturado, cobrado o no',
      );
    });

    // EL CASO REAL DEL ISSUE 10: sin marcar (falso o nulo, «nadie lo marco») y
    // sin cotizar en Entrega —que solo cotiza los marcados—, con el domicilio
    // cobrado. Sale. Y la pareja: el MARCADO y sin cotizar no sale.
    for (final marca in const [false, null]) {
      test('sin marcar ($marca), cobrado y sin cotizar SI sale', () async {
        await sembrarPedido(
          base,
          id: 'sin-marcar',
          domicilio: marca,
          costo: null,
          facturaEstado: EstadoFactura.cambiado,
          facturaDomicilio: 1.31,
        );
        await sembrarPedido(base, id: 'marcado-sin-cotizar', costo: null);

        final mitad = await consultas.sinColocar(sucursalStg, origen);
        final ids = mitad.pedidos.map((p) => p.pedidoId).toSet();

        expect(
          ids,
          contains('sin-marcar'),
          reason:
              'PBF26-2610131268 otra vez: sin marcar y cobrado no sale en el '
              'tablero, y no hay otra forma de ponerlo en una ruta',
        );
        expect(
          ids,
          contains('marcado-sin-cotizar'),
          reason: 'la cotizacion se dejo de exigir tambien a los marcados',
        );
      });
    }
  });
}
