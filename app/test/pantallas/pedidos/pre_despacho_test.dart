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
    'el pre-despacho de lo marcado suma lo que sabe y cuenta lo que le falta',
    () async {
      // o1: Arroz 2 empaques / 20 uds (50 kg de linea) + Frijol 1/10, sin peso
      // o2: Arroz 3 empaques / 30 uds (75 kg de linea)
      final totales = await consultas.preDespachoDe(['o1', 'o2']);

      expect(totales.lineas.length, 2);
      // Lo que mas empaques tiene, primero.
      final arroz = totales.lineas.first;
      expect(arroz.producto, 'Arroz');
      expect(arroz.empaques, 5);
      expect(arroz.unidades, 50);
      // 50 + 75 = 125 kg, hecho a mano, y los dos numeros los resolvio el
      // servidor: aqui solo se suman.
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
      // El servidor no le resolvio el peso a esta linea: **null, no cero**. Un
      // cero se leeria como «no pesa» y la hoja del almacen cuadraria mal.
      expect(frijol.pesoKg, isNull);

      expect(totales.productos, 2);
      expect(totales.empaques, 6);
      // Las unidades SÍ se saben enteras: las dos líneas las traen.
      expect(totales.unidades, 60, reason: '50 de arroz + 10 de frijol');
      expect(totales.unidadesCompletas, isTrue);

      // EL PESO NO SE SABE ENTERO, Y AUN ASÍ SE DA — 28/09/2026.
      //
      // Hasta esa mañana esto era `isNull`: faltaba un renglón y se borraba el
      // total. El motivo era bueno —125 kg leídos como el total de la hoja es
      // cargar de menos— y la medida contra producción lo tumbó: **21
      // renglones de 1.149 dejaban sin kg una fila de 4.949 empaques** de MALTA
      // GUAJIRA, y no se arregla llenando datos, que de los 129 productos de
      // Ventra sólo 57 traen peso. Jose, mirando la hoja: «por q me siguen
      // saliendo cosas sin nada por q razon».
      //
      // Lo que sustituye al `null` **no es el número a secas**: es el número
      // MÁS el contador de renglones que faltan, que es lo que la pantalla
      // pinta con el `≥`. Si un día esto vuelve a ser sólo `125`, sin
      // `sinPeso`, la suma a medias vuelve a leerse como completa.
      expect(totales.pesoKg, 125, reason: 'los 125 kg del arroz, que sí se saben');
      expect(
        totales.sinPeso,
        1,
        reason:
            'el renglón de frijol se quedó fuera de esos 125 kg y hay que '
            'decirlo: sin este número, 125 kg es un total mentiroso',
      );
      expect(
        totales.pesoCompleto,
        isFalse,
        reason: 'es lo que hace salir el `≥`; en `true` los 125 kg se firman '
            'como el peso entero de la hoja',
      );
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

  test('una linea sin `packs` cuenta sus unidades Y trae su peso entero', () async {
    // Una linea sin `packs`: 4 unidades de Arroz, y el servidor resolvio 100 kg
    // para ella. Los empaques son 4 —el respaldo— y el peso son los 100 kg del
    // renglon, enteros: la columna `kg` no vuelve a multiplicar por nada.
    //
    // QUE EL PESO SE CALCULE CON LOS MISMOS EMPAQUES QUE LA COLUMNA DE AL LADO
    // sigue siendo cierto, pero ya no se decide aqui: es la rama 2 de
    // `PesosDeRenglones` (`packs > 0 ? packs : quantity`) y la atan los casos
    // «2) pesoKg × packs» y «2) pesoKg × quantity cuando no hay packs» de
    // `api/internal/cotizar/pesos_test.go`.
    await sembrarPedido(base, id: 'o12', cliente: 'Lena');
    await sembrarRenglon(
      base,
      id: 'i5',
      pedidoId: 'o12',
      producto: 'Arroz',
      unidades: 4,
      productoId: 'p1',
      pesoLinea: 100,
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
  // EL CATALOGO LOCAL NO PINTA NADA EN EL PESO — 28/09/2026
  // ---------------------------------------------------------------------------
  //
  // La columna `kg` de la hoja salia entera en blanco porque se calculaba con
  // el catalogo, y el catalogo local no trae el peso de NINGUN producto. El dato
  // si estaba, en el renglon del pedido, que es quien lo sabe de verdad: 7.650
  // de las 7.738 lineas de produccion traen `peso_linea_kg`.
  //
  // El catalogo sigue existiendo —de ahi salen las unidades por empaque— pero
  // ya no es un escalon del peso: el unico que queda esta en el servidor
  // (`PesosDeRenglones`, rama 4), y su resultado llega aqui ya escrito.

  test('el peso sale del RENGLON aunque el catalogo diga otra cosa', () async {
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
          'si sale 50 es que el catalogo volvio a ser un escalon del peso: la '
          'hoja del almacen diria un peso que el pedido desmiente',
    );
  });

  test('sin peso en el renglon, el catalogo NO lo rellena', () async {
    // La otra mitad, y la que se llevo el encargo del 28/09/2026: un renglon
    // emparejado con Arroz —25 kg por empaque en el catalogo— y con el peso del
    // EMPAQUE puesto, pero sin `peso_linea_kg`. El servidor no supo pesarlo.
    //
    // Aqui no se resuelve: se dice que falta. Si un dia vuelve a salir 50 (el
    // catalogo) o 6 (el empaque), es que la cascada volvio al aparato y hay dos
    // sitios contestando la misma pregunta otra vez.
    await sembrarPedido(base, id: 'o16', cliente: 'Rosa');
    await sembrarRenglon(
      base,
      id: 'i9',
      pedidoId: 'o16',
      producto: 'Arroz',
      unidades: 20,
      empaques: 2,
      productoId: 'p1',
      pesoEmpaque: 3,
    );

    final totales = await consultas.preDespachoDe(['o16']);
    expect(totales.pesoKg, isNull, reason: 'no 50 del catalogo ni 6 del empaque');
    expect(
      totales.sinPeso,
      1,
      reason:
          'y se cuenta, que es como se sabe que a ese renglon le falta pasar '
          'otra vez por el espejo',
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
  // La regla que quedó aquel día fue «el total por producto es `null` mientras
  // falte uno». El 28/09/2026 se midió contra producción y era demasiado bruta:
  // 21 renglones de 1.149 borraban los 4.949 empaques de MALTA GUAJIRA, y de
  // los 129 productos de Ventra sólo 57 traen peso, así que media hoja se
  // quedaba en blanco para siempre.
  //
  // LO QUE NO CAMBIÓ es lo único que aquella regla protegía: **una suma
  // incompleta no puede presentarse como completa**. Antes lo garantizaba el
  // `null`; ahora lo garantizan las dos cifras juntas —la suma de lo que se
  // sabe y `sinPeso`/`sinUnidades`, que la pantalla escribe como
  // `≥ 26320.0 kg (21 renglones sin peso)`—. El `null` se queda para cuando no
  // se sabe NADA, y el de la cabecera —el de los pedidos— sigue siendo un
  // número siempre, porque ése sí se sabe entero.
  group('la franja y la hoja', () {
    test('ningún producto emparejado: el total NO dice 0.0 kg NI «≥ 0»', () async {
      // o3 lleva Aceite, al que el servidor no le resolvió el peso.
      final totales = await consultas.preDespachoDe(['o3']);

      // SIN SABER NADA SIGUE SIENDO `null`, y esto es la otra mitad del `≥`.
      // Un `≥ 0.0 kg` es la misma mentira que el «0.0 kg» del 22/09/2026 con
      // un símbolo delante: cierto, inútil, y se lee como que no pesa. La raya
      // se queda exactamente para este caso.
      expect(totales.pesoKg, isNull, reason: 'cero se lee como «no pesa»');
      expect(totales.unidades, isNull);
      expect(totales.sinPeso, 1, reason: 'el único renglón de o3');
      expect(totales.sinUnidades, 1);
    });

    test('la cabecera de la hoja SÍ sabe lo que pesa: sale de los pedidos', () async {
      // Y por eso es un número entero aunque no haya ni un producto emparejado:
      // es el peso del conjunto, no la suma por producto.
      final totales = await consultas.preDespachoDe(['o1', 'o2', 'o3']);

      expect(totales.pedidos, 3);
      expect(
        totales.pesoDeLosPedidos,
        greaterThan(0),
        reason: 'es lo que la hoja imprime arriba a la derecha',
      );
      // Y el de los productos es un MÍNIMO: los 125 kg del arroz, con el
      // frijol y el aceite fuera. Los dos siguen siendo dos cuentas distintas
      // —125 y 350—, que es el fallo del 22/09/2026; lo que impide restarlas a
      // ojo es que una lleve su `≥` y su cuenta de renglones.
      expect(totales.pesoKg, 125, reason: 'lo único que se sabe pesar');
      expect(totales.pesoCompleto, isFalse);
      expect(
        totales.sinPeso,
        2,
        reason: 'el renglón de frijol y el de aceite, que son DOS renglones',
      );
      expect(totales.pesoKg, isNot(totales.pesoDeLosPedidos));
    });

    test('con TODO sabido los dos totales son números Y NO LLEVAN `≥`', () async {
      // LA PAREJA DEL `≥`, y no es un adorno: si el `≥` saliera siempre
      // dejaría de significar nada y volveríamos a no poder distinguir un
      // total de un mínimo — que es el fallo entero, sólo que al revés.
      //
      // o2 no tiene frijol: sólo arroz, con sus 75 kg de linea resueltos y sus
      // 10 unidades por empaque del catálogo.
      final totales = await consultas.preDespachoDe(['o2']);

      expect(totales.lineas.single.producto, 'Arroz');
      expect(totales.empaques, 3);
      expect(totales.unidades, 30, reason: '3 empaques × 10 unidades');
      expect(totales.pesoKg, 75, reason: 'el peso que trae la linea');
      expect(totales.sinPeso, 0);
      expect(totales.sinUnidades, 0);
      expect(
        totales.pesoCompleto,
        isTrue,
        reason:
            'con las dos cifras sabidas no hay nada que avisar: un `≥` aquí '
            'es un aviso que sale siempre, y un aviso que sale siempre no se '
            'lee el día que importa',
      );
      expect(totales.unidadesCompletas, isTrue);
      expect(totales.lineas.single.pesoCompleto, isTrue);
      expect(totales.lineas.single.unidadesCompletas, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // SE CUENTAN RENGLONES, NO PRODUCTOS — 28/09/2026
  // ---------------------------------------------------------------------------
  //
  // «21 renglones de 1.149» y «2 productos de 10» son dos frases distintas, y
  // sólo la primera dice cuánto falta de verdad: un producto con 21 renglones
  // huérfanos y otro con el único que tiene no son el mismo agujero. Contar
  // productos deja el mismo «2 sin peso» tanto si faltan dos renglones como si
  // faltan doscientos, y con eso nadie decide si la hoja sirve.
  group('sinPeso y sinUnidades cuentan RENGLONES', () {
    test('un producto con varios renglones huérfanos cuenta todos', () async {
      // La forma de MALTA GUAJIRA, en pequeño: un producto con muchos
      // renglones y sólo algunos con peso, y otro producto entero sin nada.
      await sembrarPedido(base, id: 'o20', cliente: 'Pepe', peso: 500);
      var linea = 0;
      for (final peso in <double?>[12, null, null, null]) {
        await sembrarRenglon(
          base,
          id: 'malta-${++linea}',
          pedidoId: 'o20',
          producto: 'MALTA GUAJIRA 1500 ML BLISTER 6U',
          unidades: 6,
          empaques: 1,
          linea: linea,
          pesoLinea: peso,
        );
      }
      // Y uno que no trae NADA en ninguno de sus dos renglones.
      for (final _ in <int>[1, 2]) {
        await sembrarRenglon(
          base,
          id: 'vodka-${++linea}',
          pedidoId: 'o20',
          producto: 'VODKA REGIO BLISTER 6U',
          unidades: 6,
          empaques: 1,
          linea: linea,
        );
      }

      final totales = await consultas.preDespachoDe(['o20']);
      expect(totales.productos, 2);

      final malta = totales.lineas.firstWhere(
        (l) => l.producto.startsWith('MALTA'),
      );
      expect(malta.pesoKg, 12, reason: 'el único renglón que trae peso');
      expect(
        malta.lineasSinPeso,
        3,
        reason:
            'los tres renglones que no lo traen. En `1` —«el producto está a '
            'medias»— la hoja no dice si falta un renglón o trescientos',
      );

      expect(
        totales.sinPeso,
        5,
        reason:
            'TRES renglones de MALTA + los DOS de VODKA. Si sale 2 es que se '
            'están contando PRODUCTOS: el mismo número tanto si falta un '
            'renglón como si faltan los mil de la hoja entera.',
      );
      expect(
        totales.sinPeso,
        isNot(totales.productos),
        reason: 'el día que coincidan, este caso dejó de probar lo que prueba',
      );
      // El peso que sí se sabe se da, y marcado: 12 kg de 6 renglones.
      expect(totales.pesoKg, 12);
      expect(totales.pesoCompleto, isFalse);
    });

    test('un producto sin NADA aporta todos sus renglones, no uno', () async {
      // Éste es el que se colaba: el producto que no trae ni un dato contaba
      // como **1** en el papel mientras la pantalla contaba sus renglones, y
      // las dos hojas del mismo filtro decían números distintos.
      await sembrarPedido(base, id: 'o21', cliente: 'Quique', peso: 80);
      for (var i = 1; i <= 4; i++) {
        await sembrarRenglon(
          base,
          id: 'aceite-$i',
          pedidoId: 'o21',
          producto: 'ACEITE GIRASOL 1 L CAJA 12U',
          // `quantity` por debajo de `packs`: tampoco son unidades (la paca del
          // 22/09/2026), así que este producto no sabe ni peso ni unidades.
          unidades: 2,
          empaques: 5,
          linea: i,
        );
      }

      final totales = await consultas.preDespachoDe(['o21']);
      expect(totales.productos, 1);
      expect(totales.pesoKg, isNull, reason: 'no se sabe NADA: raya, no `≥ 0`');
      expect(totales.unidades, isNull);
      expect(
        totales.sinPeso,
        4,
        reason: 'los cuatro renglones. `1` es contar el producto',
      );
      expect(totales.sinUnidades, 4);
    });
  });

}
