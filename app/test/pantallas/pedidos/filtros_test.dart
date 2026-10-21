// Los 9 filtros de Pedidos, uno a uno y los 9 juntos, contra una base sembrada.
//
// **Por que se comprueba el TOTAL y no la lista:** el total es el numero que sale
// en la cabecera, el que compara la prueba de paridad contra la de Next, y el que
// delata que un `WHERE` se tradujo mal. Si el total cuadra y la lista no, es un
// fallo de paginacion, que se prueba aparte.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;
  late ConsultasPedidos consultas;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasPedidos(base);
    await sembrarLosOnce(base);
  });

  tearDown(() => base.close());

  Future<int> cuantos(FiltrosPedidos filtros, {String? sucursalId}) =>
      consultas.contar(filtros, sucursalId: sucursalId).first;

  const sinNada = FiltrosPedidos.sinNada();

  test('sin ningun filtro salen los 11', () async {
    expect(await cuantos(sinNada), 11);
  });

  test(
    'el arranque acotado deja fuera lo archivado y lo no facturado',
    () async {
      // Por defecto: `factura=con_factura` (igual o cambiado) y `archivado=0`.
      // Quedan fuera o3 (sin factura), o4 (sin cotejar) y o5 (archivado).
      const porDefecto = FiltrosPedidos();
      expect(porDefecto.arranqueAcotado, isTrue);
      expect(await cuantos(porDefecto), 8);
    },
  );

  test('el alcance por sucursal no es un filtro de la pantalla', () async {
    expect(await cuantos(sinNada, sucursalId: 'B2'), 1);
    expect(await cuantos(sinNada, sucursalId: 'B1'), 10);
  });

  group('uno a uno', () {
    test('q busca tambien en el texto de los productos', () async {
      expect(await cuantos(sinNada.copiarCon(q: 'hugo')), 1);
      // «aceite» sólo esta en un renglon de o3, en ningun campo del pedido.
      expect(await cuantos(sinNada.copiarCon(q: 'aceite')), 1);
      expect(await cuantos(sinNada.copiarCon(q: 'arroz')), 2);
    });

    test('municipio y vendedor son exactos', () async {
      expect(await cuantos(sinNada.copiarCon(municipio: 'Camagüey')), 6);
      expect(await cuantos(sinNada.copiarCon(municipio: 'Florida')), 3);
      expect(await cuantos(sinNada.copiarCon(vendedores: ['Luis'])), 6);
      expect(await cuantos(sinNada.copiarCon(vendedores: ['Marta'])), 4);
      // VARIOS = la unión (issue 18 de Amado): los de cualquiera de los dos.
      expect(
        await cuantos(sinNada.copiarCon(vendedores: ['Luis', 'Marta'])),
        10,
      );
      // Uno sin pedidos suma cero; ninguno es todos.
      expect(
        await cuantos(sinNada.copiarCon(vendedores: ['Luis', 'Nadie'])),
        6,
      );
      expect(await cuantos(sinNada.copiarCon(vendedores: ['Nadie'])), 0);
    });

    test('cotizado mira `pedidoCosto`, y un nulo NO es un cero', () async {
      expect(
        await cuantos(sinNada.copiarCon(cotizado: CotizadoFiltro.conPrecio)),
        10,
      );
      expect(
        await cuantos(sinNada.copiarCon(cotizado: CotizadoFiltro.sinCotizar)),
        1,
      );
    });

    // 21/10/2026: la fila es la factura y el pedido es un extra. En pareja: con folio hay pedido,
    // sin folio no; y lo del pedido (el precio de Entrega) sólo cuenta para las que lo traen.
    test('pedido separa las facturas con pedido de las que no', () async {
      await base.customStatement(
        "UPDATE orders SET folio = NULL WHERE id NOT IN ('o1','o2')",
      );
      expect(
        await cuantos(sinNada.copiarCon(pedido: PedidoFiltro.conPedido)),
        2,
      );
      expect(
        await cuantos(sinNada.copiarCon(pedido: PedidoFiltro.sinPedido)),
        9,
      );
    });

    test(
      'el precio de Entrega sólo cuenta para las facturas con pedido',
      () async {
        // Sólo o1 (con precio) y o2 (sin cotizar) vienen de un pedido.
        await base.customStatement(
          "UPDATE orders SET folio = NULL WHERE id NOT IN ('o1','o2')",
        );
        expect(
          await cuantos(sinNada.copiarCon(cotizado: CotizadoFiltro.conPrecio)),
          1,
          reason:
              'las otras 9 tienen precio puesto pero no vienen de un pedido',
        );
        expect(
          await cuantos(sinNada.copiarCon(cotizado: CotizadoFiltro.sinCotizar)),
          1,
        );
      },
    );

    test('archivado tiene TRES estados, no dos', () async {
      expect(
        await cuantos(sinNada.copiarCon(archivado: ArchivadoFiltro.si)),
        1,
      );
      expect(
        await cuantos(sinNada.copiarCon(archivado: ArchivadoFiltro.no)),
        10,
      );
      expect(await cuantos(sinNada), 11);
    });

    test('factura: `cuadra` es mas duro que `con_factura`', () async {
      expect(
        await cuantos(sinNada.copiarCon(factura: FacturaFiltro.conFactura)),
        9,
      );
      expect(
        await cuantos(sinNada.copiarCon(factura: FacturaFiltro.cuadra)),
        8,
      );
      // NULL es «sin cotejar», y es un pedido, no ninguno.
      expect(
        await cuantos(sinNada.copiarCon(factura: FacturaFiltro.sinCotejar)),
        1,
      );
    });

    test('reparto manda `resultado`, no el estado de la ruta', () async {
      expect(
        await cuantos(sinNada.copiarCon(reparto: RepartoFiltro.enDespacho)),
        1,
      );
      expect(
        await cuantos(sinNada.copiarCon(reparto: RepartoFiltro.enRuta)),
        1,
      );
      expect(
        await cuantos(sinNada.copiarCon(reparto: RepartoFiltro.entregado)),
        1,
      );
      expect(
        await cuantos(sinNada.copiarCon(reparto: RepartoFiltro.devuelto)),
        1,
      );
      // o9 volvio del camion: solto su ruta y vuelve a estar sin entregar.
      expect(
        await cuantos(sinNada.copiarCon(reparto: RepartoFiltro.sinEntregar)),
        8,
      );
    });

    test('las fechas acotan el dia entero, y un pedido sin fecha usa la del espejo', () async {
      expect(
        await cuantos(
          sinNada.copiarCon(
            desde: DateTime(2026, 9, 3),
            hasta: DateTime(2026, 9, 5),
          ),
        ),
        3,
      );
      // «del 3 al 3» tiene que devolver el del dia 3: si `hasta` no incluyera el
      // dia entero, saldria cero y pareceria que no hubo pedidos.
      expect(
        await cuantos(
          sinNada.copiarCon(
            desde: DateTime(2026, 9, 3),
            hasta: DateTime(2026, 9, 3),
          ),
        ),
        1,
      );
      // Cada extremo por su lado (issue 13 de Amado): sólo «hasta el 2» son o1,
      // o2 y o11 (de agosto, por su `createdAt`); sólo «desde el 9», o9 y o10.
      expect(await cuantos(sinNada.copiarCon(hasta: DateTime(2026, 9, 2))), 3);
      expect(await cuantos(sinNada.copiarCon(desde: DateTime(2026, 9, 9))), 2);
      // o11 no tiene `orderDate`: se acota por su `createdAt` de agosto.
      expect(
        await cuantos(
          sinNada.copiarCon(
            desde: DateTime(2026, 8, 1),
            hasta: DateTime(2026, 8, 31),
          ),
        ),
        1,
      );
    });
  });

  test('los 9 juntos', () async {
    // Arranque acotado + municipio + vendedor + reparto + cotizado + fechas +
    // busqueda: tiene que quedar o7 y nada mas.
    final todos = const FiltrosPedidos().copiarCon(
      municipio: 'Camagüey',
      vendedores: ['Luis'],
      reparto: RepartoFiltro.enRuta,
      cotizado: CotizadoFiltro.conPrecio,
      desde: DateTime(2026, 9, 1),
      hasta: DateTime(2026, 9, 30),
      q: 'gema',
    );
    expect(await cuantos(todos), 1);
    final pagina = await consultas.pagina(todos).first;
    expect(pagina.single.id, 'o7');
  });

  test('cambiar un filtro vuelve a la pagina 1', () {
    const enLaSiete = FiltrosPedidos(pagina: 7);
    expect(enLaSiete.copiarCon(municipio: 'Florida').pagina, 1);
    // Pasar de pagina, en cambio, no se pisa a si mismo.
    expect(enLaSiete.copiarCon(pagina: 8).pagina, 8);
  });

  test('las facetas salen de lo local, con su conteo', () async {
    final facetas = await consultas.facetas();
    expect(
      facetas.municipios.map((m) => m.valor),
      containsAll(<String>['Camagüey', 'Florida', 'Nuevitas']),
    );
    expect(
      facetas.municipios.firstWhere((m) => m.valor == 'Florida').pedidos,
      3,
    );
    expect(facetas.vendedores.length, 3);
  });
}
