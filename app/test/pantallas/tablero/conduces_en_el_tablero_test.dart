// LOS CONDUCES EN EL TABLERO (`docs/conduces.md` reglas 3 y 4, 27/10/2026).
//
//  * un MIEMBRO no es una tarjeta: ni en «Sin colocar», ni en la zona, ni en su contador;
//  * se coloca la PRINCIPAL y la zona suma el peso y el costo de TODO el conduce;
//  * un miembro suelto no se puede colocar, y lo dice;
//  * armar la ruta desde la zona lleva a los miembros con la principal, sin parada propia, y el peso de la
//    ruta es el de todas las facturas.

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
  late String centro;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    repo = RepositorioTablero(base, ColaDeSalida(base));
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarCamion(base, id: 'v1', capacidad: 2000);
    origen = await consultas.almacenDe(sucursalStg);
    centro = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Centro',
      vehiculoId: 'v1',
    );
    // a (principal, 100 kg, $5) con b (miembro, 50 kg, $5) y c suelta (25 kg).
    await sembrarPedido(base, id: 'a', facturaNumero: '47313', peso: 100);
    await sembrarPedido(base, id: 'b', facturaNumero: '47314', peso: 50);
    await sembrarPedido(base, id: 'c', facturaNumero: '47315', peso: 25);
    await (base.update(base.orders)..where((o) => o.id.equals('b'))).write(
      const OrdersCompanion(conducePrincipalId: Value('a')),
    );
  });
  tearDown(() => base.close());

  test('«Sin colocar» ofrece la principal y la suelta; su total es el de la lista', () async {
    final izquierda = await consultas.sinColocar(sucursalStg, origen);
    expect([for (final t in izquierda.pedidos) t.pedidoId]..sort(), ['a', 'c']);
    expect(izquierda.total, 2);
    final a = izquierda.pedidos.firstWhere((t) => t.pedidoId == 'a');
    expect(a.conduce!.etiqueta, 'Conduce 47313 + 47314');
    expect(a.weight, 150);
  });

  test('colocar la principal: la zona suma el conduce entero y cuenta UNA tarjeta', () async {
    await repo.colocar(pedidoId: 'a', columnaId: centro);
    await repo.colocar(pedidoId: 'c', columnaId: centro);

    final zona = (await consultas.columnas(sucursalStg)).single;
    expect(zona.pedidos, 2, reason: 'una tarjeta por conduce, no una por factura');
    expect(zona.pesoKg, 175, reason: '100 + 50 de a y b, y 25 de c');
    expect(zona.costoUsd, 15, reason: 'el domicilio de las tres facturas');

    final puestas = await consultas.colocados(sucursalStg, origen);
    expect([for (final t in puestas) t.pedido.pedidoId], ['a', 'c']);
    expect(puestas.first.pedido.conduce!.numeros, '47313 + 47314');
    expect((await consultas.avisos(sucursalStg)).colocados, 2);
  });

  test('un miembro suelto NO se puede colocar, y lo dice', () async {
    await expectLater(
      () => repo.colocar(pedidoId: 'b', columnaId: centro),
      throwsA(
        isA<RechazoDelTablero>().having(
          (r) => r.mensaje,
          'mensaje',
          'Esa factura va dentro del conduce 47313: arma el conduce entero',
        ),
      ),
    );
    expect((await consultas.colocados(sucursalStg, origen)), isEmpty);
  });

  test('armar la ruta de la zona lleva a los miembros con la principal', () async {
    await repo.colocar(pedidoId: 'a', columnaId: centro);
    await repo.colocar(pedidoId: 'c', columnaId: centro);

    final rutaId = await repo.armarRuta(
      columnaId: centro,
      sucursalId: sucursalStg,
    );

    final filas = {for (final p in await base.select(base.orders).get()) p.id: p};
    expect(filas['a']!.routeId, rutaId);
    expect(filas['b']!.routeId, rutaId, reason: 'el miembro va con su principal');
    expect(filas['b']!.ultimaRutaId, rutaId);
    expect(filas['b']!.stopOrder, isNull, reason: 'el conduce es UNA parada');
    final ruta = await (base.select(base.routes)..where((r) => r.id.equals(rutaId))).getSingle();
    expect(ruta.totalWeight, 175);
    // Lo que se manda al servidor son las principales; él cascadea.
    final cuerpo = (await ColaDeSalida(base).lote()).last.cuerpo;
    expect(cuerpo, contains('"pedidoIds":["a","c"]'));
    // Y las zonas se vacían.
    expect((await consultas.columnas(sucursalStg)).single.pedidos, 0);
  });
}
