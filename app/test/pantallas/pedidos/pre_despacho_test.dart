// El pre-despacho: cuanto hay que sacar del almacen.
//
// Es la mitad del valor de la pantalla de Pedidos y es una suma que alguien va a
// comparar contra lo que de verdad saque del almacen. Por eso se comprueba contra
// un caso hecho a mano y no contra otra suma calculada en el propio test.

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

  test(
    'el pre-despacho de lo marcado suma empaques, unidades y kilos',
    () async {
      // o1: Arroz 2 empaques / 20 uds (producto con 25 kg por empaque) + Frijol 1/10
      // o2: Arroz 3 empaques / 30 uds
      final totales = await consultas.preDespachoDe(['o1', 'o2']);

      expect(totales.lineas.length, 2);
      // Lo que mas empaques tiene, primero.
      final arroz = totales.lineas.first;
      expect(arroz.producto, 'Arroz');
      expect(arroz.empaques, 5);
      expect(arroz.unidades, 50);
      // 5 empaques × 25 kg = 125 kg, hecho a mano.
      expect(arroz.pesoKg, 125);

      final frijol = totales.lineas.last;
      expect(frijol.producto, 'Frijol');
      expect(frijol.empaques, 1);
      // El frijol NO está en el catálogo y aun así sabe sus unidades: son las
      // del propio renglón del pedido —10 unidades en 1 empaque—, que es de
      // donde salen desde el 28/09/2026. Lo que sigue prohibido es la línea
      // cuya `quantity` NO son unidades, y ésa se mira por su forma —«7 pacas ·
      // 4 unidades» del 22/09/2026—, no por si el producto está emparejado.
      expect(frijol.unidades, 10);
      // Sin producto emparejado no hay peso resuelto: **null, no cero**. Un cero se
      // leeria como «no pesa» y la hoja del almacen cuadraria mal.
      expect(frijol.pesoKg, isNull);

      expect(totales.productos, 2);
      expect(totales.empaques, 6);
      // Las unidades SÍ se saben enteras: las dos líneas las traen.
      expect(totales.unidades, 60, reason: '50 de arroz + 10 de frijol');
      // EL PESO NO, Y POR ESO ES NULO. Sumar sólo el arroz daría 125 kg, que se
      // lee como el total de la hoja y se queda corto: el mismo cero creíble
      // con otra cara. Falta UNO y ya no hay total.
      expect(totales.pesoKg, isNull);
      expect(totales.sinPeso, 1);
      expect(totales.sinUnidades, 0);
    },
  );

  // ---------------------------------------------------------------------------
  // LA HOJA DEL ALMACEN NO PUEDE SALIR CORTA
  // ---------------------------------------------------------------------------
  //
  // Los empaques de una linea son sus `packs` y, si no los trae, sus
  // `quantity` (`reglas-negocio.md` §12). Sumar `packs` a secas hace que un
  // producto cuya linea viene sin empaques cuente **0**, y entonces la hoja
  // con la que alguien baja al almacen pide menos cajas de las que hay que
  // cargar. Eso no se descubre hasta que el camion ya se fue.
  //
  // El juego de datos: o3 lleva 'Aceite' con 5 unidades y **`packs` nulo**.

  const hojaCorta =
      'LA HOJA DEL ALMACEN SALDRIA CORTA: una linea sin `packs` tiene que '
      'contar sus unidades, no cero. Con cero se cargan menos cajas de las que '
      'hay que cargar y nadie se entera hasta que el camion se fue.';

  test(
    'los empaques de una linea sin `packs` son sus unidades, nunca cero',
    () async {
      final totales = await consultas.preDespachoDe(['o3']);
      expect(totales.lineas.single.producto, 'Aceite');
      // El aceite no está emparejado: no se sabe cuántas unidades trae.
      expect(totales.lineas.single.unidades, isNull);
      expect(totales.lineas.single.empaques, 5, reason: hojaCorta);
    },
  );

  test('el pre-despacho de lo ELEGIDO cuenta los empaques IGUAL que el de lo '
      'FILTRADO cuando `packs` es nulo', () async {
    // La misma linea, contada por los dos caminos. Los dos botones
    // `Ver e imprimir` de la pantalla sacan la MISMA hoja, asi que dos
    // numeros distintos aqui son dos papeles distintos para el mismo almacen.
    final elegido = await consultas.preDespachoDe(['o3']);
    final filtrado = await consultas.preDespachoDeLoFiltrado(
      // Sin filtros: con el arranque acotado o3 no entra (no tiene factura).
      const FiltrosPedidos.sinNada(),
    );
    final aceiteFiltrado = filtrado.lineas.firstWhere(
      (l) => l.producto == 'Aceite',
    );

    expect(
      elegido.lineas.single.empaques,
      aceiteFiltrado.empaques,
      reason: hojaCorta,
    );
    expect(elegido.lineas.single.empaques, 5, reason: hojaCorta);
  });

  test('el peso de la linea usa los MISMOS empaques que la columna de al lado', () async {
    // Una linea sin `packs` pero con producto emparejado: 4 unidades de Arroz,
    // que pesa 25 kg por empaque. Si los empaques se cuentan con el respaldo
    // (4) el peso son 100 kg; si se contaran con `packs` a secas, la fila
    // diria 4 empaques y 0 kg — dos columnas de la misma fila hablando de
    // bultos distintos.
    await sembrarPedido(base, id: 'o12', cliente: 'Lena');
    await sembrarRenglon(
      base,
      id: 'i5',
      pedidoId: 'o12',
      producto: 'Arroz',
      unidades: 4,
      productoId: 'p1',
    );

    final totales = await consultas.preDespachoDe(['o12']);
    expect(totales.lineas.single.empaques, 4, reason: hojaCorta);
    expect(totales.lineas.single.pesoKg, 100);
  });

  test('un `packs` que viene en CERO tampoco cuenta cero', () async {
    // La regla es `packs > 0 ? packs : quantity`, no «si viene, usalo». Un cero
    // explicito es tan mentira como un nulo —hay renglones espejados que llegan
    // asi— y con `packs IS NOT NULL` se colaria tal cual en la hoja.
    await sembrarPedido(base, id: 'o13', cliente: 'Mario');
    await sembrarRenglon(
      base,
      id: 'i6',
      pedidoId: 'o13',
      producto: 'Sal',
      unidades: 7,
      empaques: 0,
    );

    final totales = await consultas.preDespachoDe(['o13']);
    expect(totales.lineas.single.empaques, 7, reason: hojaCorta);
  });

  // ---------------------------------------------------------------------------
  // EL DATO DEL PEDIDO MANDA SOBRE EL DEL CATALOGO — 28/09/2026
  // ---------------------------------------------------------------------------
  //
  // La columna `kg` de la hoja salia entera en blanco porque se calculaba con
  // el catalogo, y el catalogo local no trae el peso de NINGUN producto. El dato
  // si estaba, en el renglon del pedido, que es quien lo sabe de verdad: 7.650
  // de las 7.738 lineas de produccion traen `peso_linea_kg`.

  test('el peso del RENGLON manda sobre el del catalogo', () async {
    // Arroz esta emparejado y el catalogo dice 25 kg por empaque, o sea 50 kg
    // por estos dos. Pero el pedido dice que esta linea pesa 7, y el pedido es
    // el que se va a cargar en el camion.
    await sembrarPedido(base, id: 'o14', cliente: 'Nadia');
    await sembrarRenglon(
      base,
      id: 'i7',
      pedidoId: 'o14',
      producto: 'Arroz',
      unidades: 20,
      empaques: 2,
      productoId: 'p1',
      pesoLinea: 7,
    );

    final totales = await consultas.preDespachoDe(['o14']);
    expect(
      totales.lineas.single.pesoKg,
      7,
      reason:
          'si sale 50 es que se esta usando el catalogo teniendo el peso del '
          'renglon: la hoja del almacen diria un peso que el pedido desmiente',
    );
  });

  test('una `quantity` que NO son unidades no se cuela en la hoja', () async {
    // El caso del 22/09/2026: «SERVILLETA PROSITO PACA 24P · 7 empaques · 4
    // unidades». `quantity` por debajo de `packs` no son unidades de nada, y
    // sumarlas da un numero mas bajo que los propios bultos. Son 437 de las
    // 7.738 lineas de produccion.
    await sembrarPedido(base, id: 'o15', cliente: 'Omar');
    await sembrarRenglon(
      base,
      id: 'i8',
      pedidoId: 'o15',
      producto: 'Servilleta',
      unidades: 4,
      empaques: 7,
    );

    final totales = await consultas.preDespachoDe(['o15']);
    expect(totales.lineas.single.empaques, 7);
    expect(
      totales.lineas.single.unidades,
      isNull,
      reason: 'cuatro unidades dentro de siete pacas no es un dato, es un error',
    );
  });

  test('la cabecera de la hoja: cuantos pedidos y cuantos kilos', () async {
    // Es la esquina derecha del papel (`pantallas.md` §10.1). Cuenta PEDIDOS,
    // no lineas: o1 tiene dos renglones y sigue siendo un pedido.
    final totales = await consultas.preDespachoDe(['o1', 'o2']);
    expect(totales.pedidos, 2);
    // 100 kg de o1 + 200 kg de o2, del peso del PEDIDO, no de la suma por
    // producto (que ahi son 125).
    expect(totales.pesoDeLosPedidos, 300);
  });

  test('el pre-despacho de lo filtrado usa el MISMO where que la lista', () async {
    // Con el arranque acotado, o3 (sin factura) queda fuera: su Aceite no puede
    // aparecer en la hoja de lo que sube al camion.
    final acotado = await consultas.preDespachoDeLoFiltrado(
      const FiltrosPedidos(),
    );
    expect(acotado.lineas.map((l) => l.producto), isNot(contains('Aceite')));

    // Sin filtros, si sale.
    final todo = await consultas.preDespachoDeLoFiltrado(
      const FiltrosPedidos.sinNada(),
    );
    expect(todo.lineas.map((l) => l.producto), contains('Aceite'));
  });

  test('sin nada marcado no hay lineas ni consulta', () async {
    final totales = await consultas.preDespachoDe(const []);
    expect(totales.lineas, isEmpty);
    expect(totales.empaques, 0);
  });
  // ---------------------------------------------------------------------------
  // LA FRANJA Y LA HOJA NO PUEDEN DECIR COSAS DISTINTAS — 22/09/2026
  // ---------------------------------------------------------------------------
  //
  // Con el mismo filtro, la franja de la pantalla decía «10 producto(s) · 3185
  // empaques · **0.0 kg**» y la hoja imprimible decía «264 pedido(s) ·
  // **24891.0 kg**». Los dos números eran ciertos cada uno en su definición
  // —uno suma el peso resuelto por producto, el otro el de los pedidos— y
  // juntos sólo pueden hacer una cosa: que quien carga el camión se crea que no
  // pesa nada.
  //
  // La regla que queda: el total por producto es `null` mientras falte uno, y
  // el de la cabecera —el de los pedidos— sigue siendo un número siempre,
  // porque ése sí se sabe entero.
  group('la franja y la hoja', () {
    test('ningún producto emparejado: el total NO dice 0.0 kg', () async {
      // o3 lleva Aceite, que no está en el catálogo.
      final totales = await consultas.preDespachoDe(['o3']);

      expect(totales.pesoKg, isNull, reason: 'cero se lee como «no pesa»');
      expect(totales.unidades, isNull);
      expect(totales.sinPeso, totales.productos);
    });

    test('la cabecera de la hoja SÍ sabe lo que pesa: sale de los pedidos', () async {
      // Y por eso no es nula aunque no haya ni un producto emparejado: es el
      // peso del conjunto, no la suma por producto.
      final totales = await consultas.preDespachoDe(['o1', 'o2', 'o3']);

      expect(totales.pedidos, 3);
      expect(
        totales.pesoDeLosPedidos,
        greaterThan(0),
        reason: 'es lo que la hoja imprime arriba a la derecha',
      );
      expect(totales.pesoKg, isNull, reason: 'y por producto no se sabe entero');
    });

    test('con TODO emparejado los dos totales son números', () async {
      // o1 y o2 sin el frijol: sólo arroz, que está en el catálogo con sus 25
      // kg y sus 10 unidades por empaque.
      final totales = await consultas.preDespachoDe(['o2']);

      expect(totales.lineas.single.producto, 'Arroz');
      expect(totales.empaques, 3);
      expect(totales.unidades, 30, reason: '3 empaques × 10 unidades');
      expect(totales.pesoKg, 75, reason: '3 empaques × 25 kg');
      expect(totales.sinPeso, 0);
      expect(totales.sinUnidades, 0);
    });
  });

}
