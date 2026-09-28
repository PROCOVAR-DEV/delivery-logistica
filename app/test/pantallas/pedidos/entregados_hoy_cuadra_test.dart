// «ENTREGADOS HOY» Y LA LISTA A LA QUE LLEVA TIENEN QUE DECIR EL MISMO NÚMERO.
//
// `CLAUDE.md` §3-bis: cuando dos consultas contestan lo mismo —una cifra y su
// detalle— se atan con una prueba, no con un comentario. Ya pasó con «Sin
// colocar (722)» encima de una lista de 293: el comentario que había encima del
// contador lo avisaba con esas mismas palabras y no sirvió de nada, porque un
// comentario no falla.
//
// Aquí las dos partes son:
//
//  * el contador, `ConsultasPanel.cifras().entregadosHoy` — SQL a mano, en
//    `panel/datos/consultas_panel.dart`;
//  * la lista, `ConsultasPedidos.contar(filtrosDeEntregadosDesde(medianoche))`,
//    que es literalmente lo que abre la tarjeta del Panel al tocarla.
//
// Y se comprueba el camino entero, no sólo los filtros en memoria: el enlace se
// escribe en la dirección, se vuelve a leer de ahí y se cuenta con lo que salió.
// Si el viaje por la URL pierde o cambia algo, la lista diría otro número que la
// tarjeta y nadie lo vería.
//
// Los siete pedidos sembrados no son un juego bonito: cada uno cae en un lado de
// una frontera que YA se ha cruzado mal alguna vez en este repositorio.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_en_la_url.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;
  late ConsultasPanel panel;
  late ConsultasPedidos pedidos;

  // El aparato son las 19:44 del 28/09/2026, que es la hora a la que se entregó
  // el pedido por el que Jose preguntó.
  final ahora = DateTime(2026, 9, 28, 19, 44);

  setUp(() async {
    base = baseDePrueba();
    panel = ConsultasPanel(base, reloj: RelojFalso(ahora).leer);
    pedidos = ConsultasPedidos(base);
    await sembrarCatalogo(base);
  });

  tearDown(() => base.close());

  Future<void> sembrarLosSiete() async {
    // La ruta de Jose: SALIÓ y no se ha cerrado. Por eso el Historial de Rutas
    // está vacío y por eso preguntó.
    await sembrarRuta(base, id: 'RT-20260928-001', estado: EstadoRuta.enCurso);
    // Y una cerrada, para que el caso «ya está en el Historial» también exista.
    await sembrarRuta(
      base,
      id: 'RT-20260927-009',
      estado: EstadoRuta.completada,
    );

    // 1. EL DE JOSE. Pedido del día 25, entregado el 28 a las 19:44, en una ruta
    //    que sigue en curso. Es el que hace imposible acotar con `desde`/`hasta`:
    //    ésas miran la fecha DEL PEDIDO, y por la fecha del pedido éste es del
    //    25.
    await sembrarPedido(
      base,
      id: 'e1',
      cliente: 'El de Jose',
      folio: 'POR26-260925-3700',
      fecha: DateTime(2026, 9, 25),
      rutaId: 'RT-20260928-001',
      resultado: ResultadoParada.entregado,
      entregadoAt: DateTime(2026, 9, 28, 19, 44),
    );

    // 2. ARCHIVADO y entregado hoy. El contador del Panel no mira `archivado`,
    //    así que si el enlace saliera con el arranque de la pantalla —que acota
    //    a `sin archivar`— la tarjeta diría uno más que la lista.
    await sembrarPedido(
      base,
      id: 'e2',
      cliente: 'Archivado',
      archivado: true,
      entregadoAt: DateTime(2026, 9, 28, 8, 0),
    );

    // 3. SIN COTEJAR (`factura_estado` NULL) y entregado hoy. El otro filtro del
    //    arranque: `con_factura` lo dejaría fuera de la lista y dentro de la
    //    tarjeta.
    await sembrarPedido(
      base,
      id: 'e3',
      cliente: 'Sin cotejar',
      facturaEstado: null,
      entregadoAt: DateTime(2026, 9, 28, 9, 30),
    );

    // 4. ENTREGADO AYER a las 23:59. Un minuto fuera: la frontera de la
    //    medianoche por abajo.
    await sembrarPedido(
      base,
      id: 'e4',
      cliente: 'De ayer',
      rutaId: 'RT-20260927-009',
      entregadoAt: DateTime(2026, 9, 27, 23, 59, 59),
    );

    // 5. SIN ENTREGAR. `delivered_at` nulo no entra en ninguna de las dos: en
    //    SQL la comparación contra NULL da NULL, y eso es lo que se quiere.
    await sembrarPedido(base, id: 'e5', cliente: 'Todavía en el camión');

    // 6. DE OTRA SUCURSAL, entregado hoy. Con Camagüey mirada no sale en
    //    ninguna; sin sucursal, en las dos.
    await sembrarPedido(
      base,
      id: 'e6',
      cliente: 'De Holguín',
      sucursal: 'B2',
      entregadoAt: DateTime(2026, 9, 28, 12, 0),
    );

    // 7. ENTREGADO «MAÑANA». No es un error de datos: el `delivered_at` lo pone
    //    el reloj del aparato del repartidor, que no es éste. El contador no
    //    tiene techo (`>= medianoche` y nada más), así que el filtro tampoco
    //    puede tenerlo o la lista diría 0 debajo de un 1.
    await sembrarPedido(
      base,
      id: 'e7',
      cliente: 'Con el reloj adelantado',
      entregadoAt: DateTime(2026, 9, 29, 0, 20),
    );
  }

  /// Lo que dicen las dos, con la sucursal que se esté mirando.
  Future<(int tarjeta, int lista)> lasDos(String? sucursalId) async {
    final cifras = await panel.cifras(sucursalId: sucursalId).first;
    final total = await pedidos
        .contar(
          filtrosDeEntregadosDesde(panel.medianoche),
          sucursalId: sucursalId,
        )
        .first;
    return (cifras.entregadosHoy, total);
  }

  test('la tarjeta y la lista cuentan lo mismo, con los siete casos frontera', () async {
    await sembrarLosSiete();

    final (tarjeta, lista) = await lasDos('B1');

    expect(
      tarjeta,
      4,
      reason:
          'De los siete sembrados, en Camagüey se entregaron HOY cuatro: el de '
          'Jose, el archivado, el sin cotejar y el del reloj adelantado. Si sale '
          'otro número, el que cambió es el contador del Panel '
          '(`entregados_hoy` en consultas_panel.dart).',
    );
    expect(
      lista,
      tarjeta,
      reason:
          'El Panel dice «Entregados hoy: $tarjeta» y la lista a la que lleva '
          'esa tarjeta enseña $lista. Son la misma pregunta contestada dos '
          'veces: o el contador o `filtrosDeEntregadosDesde` dejaron de decir lo '
          'mismo. Mira si el enlace volvió a partir del arranque acotado '
          '(factura/archivado) o si al filtro le pusieron techo.',
    );
  });

  test('sin sucursal elegida, las dos crecen igual', () async {
    await sembrarLosSiete();

    final (tarjeta, lista) = await lasDos(null);

    expect(tarjeta, 5, reason: 'los cuatro de Camagüey más el de Holguín');
    expect(
      lista,
      tarjeta,
      reason:
          'Con «todas las sucursales» arriba, la tarjeta dice $tarjeta y la '
          'lista $lista. El alcance lo pone `sucursalMirada` en las dos, no el '
          'enlace: si divergen, alguna de las dos dejó de usarlo.',
    );
  });

  test('sin nada entregado hoy, las dos dicen cero', () async {
    await sembrarPedido(
      base,
      id: 'v1',
      cliente: 'De ayer',
      entregadoAt: DateTime(2026, 9, 27, 10, 0),
    );

    final (tarjeta, lista) = await lasDos('B1');
    expect(tarjeta, 0);
    expect(
      lista,
      0,
      reason: 'la tarjeta dice 0 y la lista tiene que salir vacía',
    );
  });

  test('el enlace sobrevive al viaje por la dirección y sigue contando igual', () async {
    await sembrarLosSiete();

    final filtros = filtrosDeEntregadosDesde(panel.medianoche);
    final direccion = FiltrosEnLaUrl.direccion(filtros);

    expect(
      direccion,
      contains('entregado_desde=2026-09-28'),
      reason:
          'La dirección es lo que se pega en un chat y lo que queda en la barra '
          'del navegador: sin el día escrito, recargar devuelve la lista entera.',
    );

    final leido = FiltrosEnLaUrl.leer(Uri.parse(direccion).queryParameters);
    expect(
      leido.noSePudieron,
      isEmpty,
      reason:
          'El propio enlace del Panel no puede traer un filtro que la pantalla '
          'no entienda: eso sacaría la franja ámbar de «no se pudo aplicar» '
          'nada más llegar.',
    );
    expect(
      leido.filtros,
      filtros,
      reason:
          'Ida y vuelta por la URL: lo que se leyó ($leido) no es lo que se '
          'escribió ($filtros).',
    );

    final porLaUrl = await pedidos
        .contar(leido.filtros, sucursalId: 'B1')
        .first;
    final cifras = await panel.cifras(sucursalId: 'B1').first;
    expect(
      porLaUrl,
      cifras.entregadosHoy,
      reason:
          'Abriendo el enlace tal cual —que es lo que hace el Panel— la lista '
          'dice $porLaUrl y la tarjeta ${cifras.entregadosHoy}.',
    );
  });

  test(
    'la lista que se abre trae al pedido por el que Jose preguntó',
    () async {
      await sembrarLosSiete();

      final pagina = await pedidos
          .pagina(filtrosDeEntregadosDesde(panel.medianoche), sucursalId: 'B1')
          .first;

      expect(
        pagina.map((p) => p.operationNumber),
        contains('POR26-260925-3700'),
        reason:
            'Es el pedido entero de la queja: entregado hoy a las 19:44, pero '
            'HECHO el día 25. Si sólo se acotara por la fecha del pedido, este '
            'pedido no saldría y la lista contradiría a la tarjeta.',
      );
      expect(
        pagina.map((p) => p.id),
        isNot(contains('e4')),
        reason: 'el de ayer no es de hoy',
      );
      expect(
        pagina.map((p) => p.id),
        isNot(contains('e5')),
        reason: 'el que sigue en el camión no se ha entregado',
      );
    },
  );
}
