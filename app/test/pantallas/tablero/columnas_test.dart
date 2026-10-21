import 'dart:convert';

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
  late ColaDeSalida cola;
  late RepositorioTablero repo;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    cola = ColaDeSalida(base);
    repo = RepositorioTablero(base, cola);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
  });

  tearDown(() => base.close());

  group('las columnas las pone el logístico', () {
    test('van al final, con identificador provisional', () async {
      final centro = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      final vista = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista Alegre',
      );

      final columnas = await consultas.columnas(sucursalStg);
      expect(columnas.map((c) => c.nombre).toList(), [
        'Centro',
        'Vista Alegre',
      ]);
      expect(columnas.map((c) => c.posicion).toList(), [1, 2]);

      // EL ID LO PONE EL APARATO Y ES DEFINITIVO: un UUIDv7, no un `local-…`.
      //
      // Es lo que hace que subir dos veces la misma zona no cree dos: el servidor
      // lo usa tal cual, así que un reintento entra una sola vez. Antes el id lo
      // ponía la base y el aparato se inventaba un provisional que había que
      // sustituir después; si la red se caía justo tras escribir, nadie sabía si
      // la zona existía arriba y el reintento creaba otra.
      final uuidv7 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(centro, matches(uuidv7), reason: 'la versión tiene que ser la 7');
      expect(vista, matches(uuidv7));
      // Y v7 ORDENA, que es la otra mitad: lleva la hora dentro, así que cuatro
      // teléfonos sin señal creando zonas toda la mañana producen ids que al
      // juntarse quedan en el orden en que se crearon de verdad. Con v4 quedarían
      // barajados, y el orden de creación es lo único que deshace un empate entre
      // dos aparatos que no se vieron.
      expect(
        centro.compareTo(vista) < 0,
        isTrue,
        reason: '«Centro» se creó antes, así que su id tiene que ordenar antes',
      );

      // EL ID VIAJA EN EL CUERPO. La posicion NO: dos aparatos sin conexion
      // propondrian el mismo numero.
      expect(jsonDecode((await cola.lote()).first.cuerpo), {
        'id': centro,
        'nombre': 'Centro',
      });
    });

    test('dos con el mismo nombre, no: se dice cuál', () async {
      await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
      expect(
        () => repo.crearColumna(sucursalId: sucursalStg, nombre: '  centro '),
        throwsA(
          isA<RechazoDelTablero>().having(
            (e) => e.mensaje,
            'mensaje',
            'Ya hay una columna «centro» en este tablero',
          ),
        ),
      );
      expect((await consultas.columnas(sucursalStg)).length, 1);
    });

    test('una columna sin nombre no es una columna', () async {
      expect(
        () => repo.crearColumna(sucursalId: sucursalStg, nombre: '   '),
        throwsA(isA<RechazoDelTablero>()),
      );
    });

    test('renombrar y elegir camión', () async {
      await sembrarCamion(base, id: 'v1', nombre: 'F-350', capacidad: 500);
      final id = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      await repo.renombrarColumna(id, 'Centro histórico');
      await repo.elegirCamion(id, 'v1');

      final columna = (await consultas.columnas(sucursalStg)).single;
      expect(columna.nombre, 'Centro histórico');
      expect(columna.vehiculoNombre, 'F-350');
      expect(columna.vehiculoCapacidad, 500);

      final apuntes = await cola.lote();
      expect(apuntes.last.metodo, 'PATCH');
      // El campo viaja aunque este vacio: «no me lo toques» y «quitamelo» son
      // dos ordenes distintas.
      await repo.elegirCamion(id, null);
      expect(jsonDecode((await cola.lote()).last.cuerpo), {'vehiculoId': null});
    });

    test('reordenar va en un solo apunte, con la lista entera', () async {
      final a = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'A');
      final b = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'B');
      final c = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'C');

      await repo.reordenarColumnas(sucursalStg, [c, a, b]);

      expect(
        (await consultas.columnas(sucursalStg)).map((x) => x.nombre).toList(),
        ['C', 'A', 'B'],
      );
      final ultimo = (await cola.lote()).last;
      expect(ultimo.metodo, 'PUT');
      expect(ultimo.ruta, '/board/columns/orden?branchId=$sucursalStg');
      expect(jsonDecode(ultimo.cuerpo), {
        'ids': [c, a, b],
      });
    });
  });

  group('borrar una columna con pedidos dentro', () {
    late String centro;

    setUp(() async {
      centro = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      for (var i = 1; i <= 3; i++) {
        await sembrarPedido(base, id: 'p$i', aGrados: 0.01 * i);
        await repo.colocar(pedidoId: 'p$i', columnaId: centro);
      }
    });

    test('la base se niega, y se dice cuántos hay', () async {
      // Con cascade, las tarjetas volverian a «sin colocar» sin decir nada y
      // quien borro «Centro» creyendola vacia se entera al dia siguiente.
      expect(
        () => repo.borrarColumna(centro),
        throwsA(
          isA<RechazoDelTablero>()
              .having(
                (e) => e.mensaje,
                'mensaje',
                '«Centro» tiene 3 facturas puestas',
              )
              .having((e) => e.pedidos, 'pedidos', 3),
        ),
      );
      expect((await consultas.columnas(sucursalStg)).length, 1);
    });

    test('con «vaciar», las tarjetas vuelven a sin colocar', () async {
      await repo.borrarColumna(centro, vaciar: true);
      expect(await consultas.columnas(sucursalStg), isEmpty);
      final origen = await consultas.almacenDe(sucursalStg);
      expect((await consultas.sinColocar(sucursalStg, origen)).total, 3);
    });

    test(
      'con destino, se van a la otra columna y detrás de lo que haya',
      () async {
        final otra = await repo.crearColumna(
          sucursalId: sucursalStg,
          nombre: 'Carretera',
        );
        await sembrarPedido(base, id: 'ya-estaba', aGrados: 0.5);
        await repo.colocar(pedidoId: 'ya-estaba', columnaId: otra);

        await repo.borrarColumna(centro, destinoId: otra);

        final origen = await consultas.almacenDe(sucursalStg);
        final puestas = await consultas.colocados(sucursalStg, origen);
        expect(puestas.map((t) => t.pedido.pedidoId).toList(), [
          'ya-estaba',
          'p1',
          'p2',
          'p3',
        ], reason: 'detrás de lo que ya había y en su orden');
        expect(
          (await consultas.columnas(sucursalStg)).single.nombre,
          'Carretera',
        );
      },
    );
  });

  group('el orden dentro de la columna', () {
    test('soltar en una posición corre a los de abajo, y volver a soltar en '
        'el mismo sitio deja el mismo tablero', () async {
      final centro = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      for (var i = 1; i <= 3; i++) {
        await sembrarPedido(base, id: 'p$i');
        await repo.colocar(pedidoId: 'p$i', columnaId: centro);
      }
      final origen = await consultas.almacenDe(sucursalStg);

      // El tercero pasa a ser el primero.
      await repo.colocar(pedidoId: 'p3', columnaId: centro, posicion: 1);
      var puestas = await consultas.colocados(sucursalStg, origen);
      expect(puestas.map((t) => t.pedido.pedidoId).toList(), [
        'p3',
        'p1',
        'p2',
      ]);
      expect(puestas.map((t) => t.posicion).toList(), [1, 2, 3]);

      // REAPLICABLE: el lote se reintenta, y repetir la misma orden tiene que
      // dar el mismo tablero, no dos tarjetas ni un corrimiento de mas.
      await repo.colocar(pedidoId: 'p3', columnaId: centro, posicion: 1);
      puestas = await consultas.colocados(sucursalStg, origen);
      expect(puestas.map((t) => t.pedido.pedidoId).toList(), [
        'p3',
        'p1',
        'p2',
      ]);
      expect(puestas.map((t) => t.posicion).toList(), [1, 2, 3]);
    });

    test('un pedido está en una columna o en ninguna, nunca en dos', () async {
      final a = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'A');
      final b = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'B');
      await sembrarPedido(base, id: 'p1');
      await repo.colocar(pedidoId: 'p1', columnaId: a);
      await repo.colocar(pedidoId: 'p1', columnaId: b);

      final origen = await consultas.almacenDe(sucursalStg);
      final puestas = await consultas.colocados(sucursalStg, origen);
      expect(puestas.length, 1, reason: 'la clave primaria ES el pedido');
      expect(puestas.single.columnaId, b);
      // El ultimo que llega manda para la colocacion (§7.7).
      expect((await consultas.columnas(sucursalStg)).first.pedidos, 0);
    });

    test('quitar dos veces lo que ya no está no es un error', () async {
      final a = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'A');
      await sembrarPedido(base, id: 'p1');
      await repo.colocar(pedidoId: 'p1', columnaId: a);
      await repo.quitar('p1');
      await repo.quitar('p1');

      final origen = await consultas.almacenDe(sucursalStg);
      expect(await consultas.colocados(sucursalStg, origen), isEmpty);
      // Y sólo se encolo el que quito de verdad: un lote que se reintenta no
      // puede empezar a fallar por esto.
      final quitados = (await cola.lote()).where((a) => a.metodo == 'DELETE');
      expect(quitados.length, 1);
    });
  });
}
