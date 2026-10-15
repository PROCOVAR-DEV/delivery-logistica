// LA CAJA DE BÚSQUEDA ENCUENTRA POR EL NÚMERO DE FACTURA — issue 10 de Amado, 15/10/2026.
//
// «Busca por el número de pedido entre otros, pero la factura no está incluida.» La
// factura es `facturaNumero` (Ventra, `47061`), NO `operationNumber` (el folio). Un pedido
// cubierto por dos facturas las lleva juntas («47061, 47062») y buscar la segunda tiene que
// encontrarlo. Las tres búsquedas de pedidos de la base local (APK y escritorio): Pedidos,
// la lista de disponibles del asistente de nueva ruta y «Sin colocar» del Tablero. En
// pareja: la factura propia encuentra, la ajena no. Los folios se siembran DISTINTOS de las
// facturas: con el mismo valor, buscar por el folio saldría verde.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';

import '../apoyo/base_de_prueba.dart';
import 'tablero/apoyo.dart';

void main() {
  late BaseLocal base;

  setUp(() async {
    base = baseDePrueba();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(
      base,
      id: 'dos',
      cliente: 'Bodega La Esquina',
      operacion: 'PTB25-261005-1479',
      facturaNumero: '47061, 47062',
    );
    await sembrarPedido(
      base,
      id: 'otra',
      cliente: 'Kiosco El Sol',
      operacion: 'PTB25-261005-1480',
      facturaNumero: '50000',
      aGrados: 0.02,
    );
  });

  tearDown(() => base.close());

  // Lo que encuentra cada una de las tres búsquedas con [q].
  Future<Map<String, List<String>>> buscar(String q) async {
    final pedidos = ConsultasPedidos(base);
    final filtros = const FiltrosPedidos.sinNada().copiarCon(q: q);
    final tablero = ConsultasTablero(base);
    return {
      'Pedidos': [
        for (final p
            in await pedidos.pagina(filtros, sucursalId: sucursalStg).first)
          p.id,
      ],
      'Pedidos (contador)': [
        '${await pedidos.contar(filtros, sucursalId: sucursalStg).first}',
      ],
      'asistente de nueva ruta': [
        for (final p in await ConsultasRutas(
          base,
        ).disponibles(sucursalId: sucursalStg, q: q))
          p.id,
      ],
      'Tablero, sin colocar': [
        for (final p in (await tablero.sinColocar(
          sucursalStg,
          await tablero.almacenDe(sucursalStg),
          filtros: FiltrosSinColocar(q: q),
        )).pedidos)
          p.pedidoId,
      ],
    };
  }

  void esperar(Map<String, List<String>> real, String q, String id) {
    for (final MapEntry(key: donde, value: ids) in real.entries) {
      expect(
        ids,
        donde == 'Pedidos (contador)' ? ['1'] : [id],
        reason:
            '$donde con «$q» tenía que dar sólo «$id»: la búsqueda no mira '
            'el número de factura (facturaNumero)',
      );
    }
  }

  test(
    'la SEGUNDA de dos facturas encuentra su pedido, y no el otro',
    () async {
      esperar(await buscar('47062'), '47062', 'dos');
    },
  );

  test('la primera, también', () async {
    esperar(await buscar('47061'), '47061', 'dos');
  });

  test(
    'la factura de otro pedido trae ESE pedido, no el de dos facturas',
    () async {
      esperar(await buscar('50000'), '50000', 'otra');
    },
  );

  test('una factura que no es de nadie no encuentra nada', () async {
    final real = await buscar('47063');
    for (final MapEntry(key: donde, value: ids) in real.entries) {
      expect(
        ids,
        donde == 'Pedidos (contador)' ? ['0'] : isEmpty,
        reason: '$donde encontró algo con «47063»',
      );
    }
  });
}
