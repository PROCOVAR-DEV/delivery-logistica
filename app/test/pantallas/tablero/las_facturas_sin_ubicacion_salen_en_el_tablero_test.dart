// LAS FACTURAS SIN PUNTO DE ENTREGA SALEN EN EL TABLERO, para ubicarlas sin salir de él (28/10/2026, Jose).
//
// Sin coordenadas una factura no entra en «Sin colocar» (no se puede colocar ni meter en una ruta) y hasta
// hoy no salía en ninguna parte del tablero: Maikel, de Santiago, no las encontraba. Caso real: la 47636,
// cuyo cliente venía escrito «GONZALES» y el padrón lo tiene «GONZALEZ», y la 47544, sin cliente.
//
//  * salen en `sinUbicar` y NO en `sinColocar`;
//  * en cuanto se les pone el punto, hacen el camino contrario;
//  * lo que no cuenta (con ruta, archivada, otra sucursal, sin factura, miembro de conduce) no sale.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
  });
  tearDown(() => base.close());

  test('sale en «sin ubicar» y no en «Sin colocar»; al ubicarla hace el camino contrario', () async {
    await sembrarPedido(
      base,
      id: 'sin',
      facturaNumero: '47636',
      conCoordenadas: false,
      cliente: 'Yaneidis',
    );
    await sembrarPedido(base, id: 'con', facturaNumero: '47682');
    final origen = await consultas.almacenDe(sucursalStg);

    final faltan = await consultas.sinUbicar(sucursalStg).first;
    expect([for (final f in faltan) f.pedidoId], ['sin']);
    expect(faltan.single.factura, '47636');
    expect(faltan.single.cliente, 'Yaneidis');
    final izquierda = await consultas.sinColocar(sucursalStg, origen);
    expect([for (final t in izquierda.pedidos) t.pedidoId], ['con']);

    // El logístico le pone el punto (lo mismo que escribe «Ubicar la entrega» en la base local).
    await (base.update(base.orders)..where((o) => o.id.equals('sin'))).write(
      const OrdersCompanion(endLat: Value(20.0), endLng: Value(-75.8)),
    );
    expect(await consultas.sinUbicar(sucursalStg).first, isEmpty);
    final ahora = await consultas.sinColocar(sucursalStg, origen);
    expect([for (final t in ahora.pedidos) t.pedidoId]..sort(), ['con', 'sin']);
  });

  test('lo que no cuenta no sale: con ruta, archivada, de otra sucursal, sin factura, miembro', () async {
    await sembrarPedido(
      base,
      id: 'ok',
      facturaNumero: '1',
      conCoordenadas: false,
    );
    await sembrarPedido(
      base,
      id: 'archivada',
      facturaNumero: '2',
      conCoordenadas: false,
      archivado: true,
    );
    await sembrarPedido(
      base,
      id: 'sinfactura',
      facturaNumero: '3',
      conCoordenadas: false,
      facturaEstado: null,
    );
    await sembrarPedido(
      base,
      id: 'otra',
      facturaNumero: '4',
      conCoordenadas: false,
      sucursal: 'otra-suc',
    );
    await sembrarPedido(
      base,
      id: 'miembro',
      facturaNumero: '5',
      conCoordenadas: false,
    );
    await (base.update(base.orders)..where((o) => o.id.equals('miembro')))
        .write(const OrdersCompanion(conducePrincipalId: Value('ok')));

    final faltan = await consultas.sinUbicar(sucursalStg).first;
    expect([for (final f in faltan) f.pedidoId], ['ok']);
  });
}
