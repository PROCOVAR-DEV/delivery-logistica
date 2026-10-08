import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

/// §7.2, §7.3 y §7.5: lo que deja de servir SE MARCA, NO SE ESCONDE.
///
/// Quitar sola una tarjeta que dejo de servir es hacer desaparecer el trabajo de
/// alguien sin decirselo: el logistico vuelve a la columna, ve once paradas
/// donde puso doce y no tiene manera de saber cual falta ni por que.
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
    origen = await consultas.almacenDe(sucursalStg);
    centro = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
  });

  tearDown(() => base.close());

  Future<void> colocar(String id) =>
      repo.colocar(pedidoId: id, columnaId: centro);

  test('un pedido que se factura mal se queda puesto y marcado', () async {
    await sembrarPedido(base, id: 'p1');
    await colocar('p1');

    // A las once, PEDIDO lo coteja contra Ventra y no hay factura.
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(facturaEstado: Value(EstadoFactura.sinFactura)),
    );

    final puestas = await consultas.colocados(sucursalStg, origen);
    expect(puestas.single.pedido.pedidoId, 'p1', reason: 'sigue ahí');
    expect(puestas.single.pedido.marcas, [MarcaTarjeta.sinFactura]);
    expect(puestas.single.pedido.repartible, isFalse);
  });

  test('los cuatro desenlaces del cotejo', () async {
    await sembrarPedido(base, id: 'igual');
    await sembrarPedido(
      base,
      id: 'cambiado',
      facturaEstado: EstadoFactura.cambiado,
    );
    await sembrarPedido(
      base,
      id: 'sin-factura',
      facturaEstado: EstadoFactura.sinFactura,
    );
    await sembrarPedido(base, id: 'sin-cotejar', facturaEstado: null);
    for (final id in ['igual', 'cambiado', 'sin-factura', 'sin-cotejar']) {
      await colocar(id);
    }

    final puestas = {
      for (final t in await consultas.colocados(sucursalStg, origen))
        t.pedido.pedidoId: t.pedido,
    };
    expect(puestas.length, 4, reason: 'ninguna se esconde');
    expect(puestas['igual']!.marcas, isEmpty);
    // `cambiado` TAMPOCO sube (Jose, 07/10/2026: «en el camion solo sube lo
    // que cuadra con la factura»), y hasta 1.0.28 esta prueba decia lo
    // contrario: el aparato armaba con lo que el servidor descarta.
    expect(puestas['cambiado']!.marcas, [MarcaTarjeta.cambiado]);
    expect(puestas['cambiado']!.repartible, isFalse);
    expect(puestas['igual']!.repartible, isTrue);
    expect(puestas['sin-factura']!.repartible, isFalse);
    // NULL NO ES «cuadra»: es «no se sabe». Con un NULL colado se armo una ruta
    // sin facturar el 2/09.
    expect(puestas['sin-cotejar']!.marcas, [MarcaTarjeta.sinCotejar]);
    expect(puestas['sin-cotejar']!.repartible, isFalse);
  });

  test('los avisos se cuentan por separado, que es como se arreglan', () async {
    await sembrarPedido(base, id: 'archivado', archivado: true);
    await sembrarPedido(base, id: 'en-ruta');
    await sembrarPedido(
      base,
      id: 'sin-factura',
      facturaEstado: EstadoFactura.sinFactura,
    );
    await sembrarPedido(
      base,
      id: 'cambiado',
      facturaEstado: EstadoFactura.cambiado,
    );
    for (final id in ['archivado', 'en-ruta', 'sin-factura', 'cambiado']) {
      await colocar(id);
    }
    // El armador de siempre, desde otro aparato, se lleva uno.
    await (base.update(base.orders)..where((o) => o.id.equals('en-ruta')))
        .write(const OrdersCompanion(routeId: Value('r-9')));

    final avisos = await consultas.avisos(sucursalStg);
    expect(avisos.colocados, 4);
    expect(avisos.archivados, 1);
    expect(avisos.enOtraRuta, 1);
    expect(avisos.sinFactura, 1);
    expect(avisos.cambiados, 1);
    expect(avisos.hayAlguno, isTrue);
  });

  group('el exceso de peso avisa, no impide', () {
    test('sin camión previsto el aviso es NULL, que no es «cabe»', () async {
      await sembrarPedido(base, id: 'p1', peso: 5000);
      await colocar('p1');
      final columna = (await consultas.columnas(sucursalStg)).single;
      expect(columna.pesoKg, 5000);
      expect(columna.excedeCamion, isNull);
    });

    test('con camión, deja soltar igual y lo dice', () async {
      await sembrarCamion(base, id: 'v1', capacidad: 1000);
      await repo.elegirCamion(centro, 'v1');
      await sembrarPedido(base, id: 'p1', peso: 700);
      await sembrarPedido(base, id: 'p2', peso: 700);
      await colocar('p1');
      await colocar('p2');

      final columna = (await consultas.columnas(sucursalStg)).single;
      expect(columna.pedidos, 2, reason: 'no se impidió soltar la segunda');
      expect(columna.pesoKg, 1400);
      expect(columna.excedeCamion, isTrue);
    });
  });

  test('el pedido que PEDIDO borró de verdad: la cascada no se calla', () async {
    await sembrarPedido(base, id: 'p1', operacion: 'SC06-1257');
    await sembrarPedido(base, id: 'p2');
    await colocar('p1');
    await colocar('p2');

    // La bajada lo trae en `quitados` y la fila se borra.
    await (base.delete(base.orders)..where((o) => o.id.equals('p1'))).go();

    // La colocación no puede sobrevivir —seria una parada fantasma que la ruta
    // cargaria sin renglones— pero la cascada es silenciosa, y eso es lo que
    // tapa la pantalla.
    final puestas = await consultas.colocados(sucursalStg, origen);
    expect(puestas.map((t) => t.pedido.pedidoId).toList(), ['p2']);

    final idos = await consultas.desaparecidos();
    expect(idos.single.operationNumber, 'SC06-1257');
    expect(idos.single.columna, 'Centro');

    // Se avisa UNA vez.
    await repo.olvidarDesaparecidos();
    expect(await consultas.desaparecidos(), isEmpty);
  });

  test('archivar NO borra la tarjeta: la marca', () async {
    await sembrarPedido(base, id: 'p1');
    await colocar('p1');
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(archivado: Value(true)),
    );

    final puestas = await consultas.colocados(sucursalStg, origen);
    expect(puestas.single.pedido.marcas, contains(MarcaTarjeta.archivado));
    expect(await consultas.desaparecidos(), isEmpty);
  });
}
