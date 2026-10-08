// EL CERO QUE SE ESCRIBE EN LA BASE, que es peor que el que se pinta.
//
// El 22/09/2026 se tapó el `$0.00` de la tarjeta de una ruta: el importe ya no
// se lee de `routes.total_price` sino que se suma de las paradas, que sí saben
// decir `null` (`datos/importe_de_la_ruta.dart`). Pero el mismo `?? 0` seguía
// vivo en los sitios que **escriben**, y un dato guardado mal no lo desmiente
// ninguna pantalla: mañana otro lo lee y se lo cree.
//
// Aquí se atan las cuatro decisiones del 23/09/2026, cada una con su pareja —el
// caso con todo cotizado y el caso con algo sin cotizar—, porque una guarda que
// sólo se prueba por el lado que falla no distingue entre «avisa cuando toca» y
// «avisa siempre» (`CLAUDE.md` §3-quinquies).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/importe_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/pedidos/datos/formato.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';
import 'rutas_a_mano.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;
  late ConsultasRutas consultas;
  late RelojFalso reloj;

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime.utc(2026, 9, 21, 16, 5));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(base, cola, reloj: reloj.leer, sufijoAparato: 'MSI');
    consultas = ConsultasRutas(base);
    await sembrarCatalogo(base);
  });

  tearDown(() => base.close());

  /// Tres paradas en el ecuador, con el costo que se le pase a cada una.
  Future<void> sembrarLasTres({
    double? costo1 = 10,
    double? costo2 = 20,
    double? costo3 = 30,
  }) async {
    await sembrarPedido(base, id: 'q1', cliente: 'Ana', pedidoCosto: costo1,
        endLat: 0, endLng: 0.1);
    await sembrarPedido(base, id: 'q2', cliente: 'Beto', pedidoCosto: costo2,
        endLat: 0, endLng: 0.2);
    await sembrarPedido(base, id: 'q3', cliente: 'Carla', pedidoCosto: costo3,
        endLat: 0, endLng: 0.3);
  }

  Future<String> armarLasTres() => acciones.armar(
    vehiculoId: 'V1',
    pedidoIds: ['q1', 'q2', 'q3'],
    origenLat: 0,
    origenLng: 0,
    origenDireccion: 'Almacén central',
    sucursalId: 'B1',
    nombre: 'Reparto de la mañana',
  );

  // -------------------------------------------------------------------------
  // 1. `orders.price`: el nulo SE ESCRIBE
  // -------------------------------------------------------------------------
  //
  // `orders.price` es `real().nullable()` en el aparato, así que puede decir
  // «sin cotizar» y el `?? 0` que había era quien se lo quitaba: una parada sin
  // cotizar quedaba GRABADA a cero, y de ahí salía el `$0.00` del globo del
  // croquis sobre un domicilio que nadie ha cotizado.

  group('el precio de la parada que se graba', () {
    test('cotizada: se graba su costo, y un cero de verdad sigue siendo cero',
        () async {
      await sembrarLasTres(costo1: 10, costo2: 0, costo3: 30);
      final rutaId = await armarLasTres();
      final paradas = {
        for (final p in await (base.select(base.orders)
              ..where((o) => o.ultimaRutaId.equals(rutaId)))
            .get())
          p.id: p.price,
      };
      expect(paradas['q1'], 10,
          reason: 'el costo cotizado tiene que llegar entero a `price`');
      expect(paradas['q2'], 0,
          reason:
              'un domicilio GRATIS lleva `pedidoCosto = 0` y eso es una cifra: '
              'si esto saliera nulo se estaría tirando un precio puesto');
      expect(paradas['q3'], 30);
    });

    // Hasta el 07/10/2026 una parada SIN COTIZAR entraba y se grababa NULA, nunca
    // con `price = 0`. Desde la regla de Amado (incidencia 6: sólo entra lo
    // facturado, con domicilio cobrado y cotizado en Entrega) esa parada ya NO
    // entra: el armado la rechaza con su número de operación y no escribe nada.
    // La pareja de arriba sigue ahí: un cero COTIZADO sí entra y se queda en cero.
    test('sin cotizar: no entra, se dice cuál y no se graba NADA', () async {
      await sembrarLasTres(costo1: 10, costo2: null, costo3: 30);
      await expectLater(
        armarLasTres,
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            allOf(contains('F-q2'), contains('cotizado el domicilio')),
          ),
        ),
      );
      expect(await base.select(base.routes).get(), isEmpty,
          reason: 'un rechazo no deja una ruta a medias');
      final q2 = await (base.select(base.orders)
            ..where((o) => o.id.equals('q2')))
          .getSingle();
      expect(q2.routeId, isNull);
      expect(q2.price, isNull,
          reason: 'y desde luego no se graba un cero en lo que no se armó');
    });
  });

  // -------------------------------------------------------------------------
  // 2. `routes.total_price`: se escribe el espejo, pero NADIE lo lee
  // -------------------------------------------------------------------------
  //
  // La columna es `NOT NULL DEFAULT 0` aquí y en el servidor, así que no sabe
  // decir «no se sabe». La decisión del 23/09/2026 es que deje de ser el
  // importe: se escribe la misma cuenta que hace el servidor —para poder
  // compararlas— y el importe se saca de las paradas.

  group('el total de la ruta que se graba no es el importe de la ruta', () {
    test('todo cotizado: la columna y el importe dicen lo mismo', () async {
      await sembrarLasTres(costo1: 10, costo2: 20, costo3: 30);
      final rutaId = await armarLasTres();

      final ruta = await (base.select(base.routes)
            ..where((r) => r.id.equals(rutaId)))
          .getSingle();
      expect(ruta.totalPrice, 60);

      final importes = await importePorRuta(base).first;
      expect(importes[rutaId]!.total, 60);
      expect(importes[rutaId]!.sinCotizar, 0);
      expect(importes[rutaId]!.rotulo, '\$60.00');
    });

    test('una ruta ANTIGUA con una sin cotizar: el importe lo dice', () async {
      // Ya no se puede ARMAR una ruta con una parada sin cotizar, pero las rutas
      // armadas antes del 07/10/2026 siguen en la base de cada aparato, con su
      // hueco. Se emula como llegaron: armada entera y, después, sin su costo.
      await sembrarLasTres(costo1: 10, costo2: 20, costo3: 30);
      final rutaId = await armarLasTres();
      await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
        const OrdersCompanion(price: Value(null), pedidoCosto: Value(null)),
      );

      final importes = await importePorRuta(base).first;
      expect(importes[rutaId]!.total, isNull,
          reason:
              'ÉSTE es el número que se pinta, y tiene que ser nulo en cuanto '
              'UNA parada no esté cotizada: los 40 de la columna son un total a '
              'medias que se lee como completo');
      expect(importes[rutaId]!.rotulo, '— (1 de 3 sin cotizar)');
    });

    test('ninguna pantalla lee `totalPrice`, que es lo que sostiene la decisión',
        () {
      // Se comprueba sobre el CÓDIGO y no montando widgets, igual que
      // `test/pantallas/tablero/importes_en_la_moneda_test.dart`: lo que hay que
      // impedir es que alguien vuelva a escribir `ruta.totalPrice` donde va un
      // importe, y eso se ve leyendo.
      //
      // Los que SÍ pueden nombrarla son los que la escriben, y lo hacen con
      // `totalPrice:` (parámetro con nombre). Un LECTOR se escribe `.totalPrice`.
      final lectores = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        // El código generado de Drift define la columna y su `copyWith`.
        if (f.path.endsWith('base.g.dart')) continue;
        final lineas = f.readAsLinesSync();
        for (var i = 0; i < lineas.length; i++) {
          final l = lineas[i].trimLeft();
          if (l.startsWith('//') || l.startsWith('///')) continue;
          if (lineas[i].contains('.totalPrice')) {
            lectores.add('${f.path}:${i + 1}: ${lineas[i].trim()}');
          }
        }
      }
      expect(
        lectores,
        isEmpty,
        reason:
            'estas líneas LEEN `routes.total_price`, que es `NOT NULL DEFAULT 0` '
            'aquí y en el servidor y por tanto no sabe decir «no se sabe»: sobre '
            'una ruta con paradas sin cotizar dan un número corto que se lee '
            'como completo, o un \$0.00 que se lee como reparto gratis. El '
            'importe de una ruta sale de `ImporteDeRuta` / `importePorRuta`, que '
            'suman las paradas:\n${lectores.join('\n')}',
      );
    });

    test('el espejo y el importe son dos cuentas distintas, a propósito', () {
      const costos = <double?>[10, null, 30];
      expect(ImporteDeRuta.espejoDelTotalDelServidor(costos), 40,
          reason: 'el espejo suma lo que hay, como el servidor');
      expect(ImporteDeRuta.deLasParadas(costos).total, isNull,
          reason: 'el importe se tira entero en cuanto falta uno');

      // Y con todo cotizado las dos coinciden, que es la otra mitad: si el
      // espejo devolviera siempre otra cosa, la comparación con el servidor
      // fallaría en TODAS las rutas y esta prueba dejaría de decir nada.
      const todas = <double?>[10, 20, 30];
      expect(ImporteDeRuta.espejoDelTotalDelServidor(todas), 60);
      expect(ImporteDeRuta.deLasParadas(todas).total, 60);
    });
  });

  // -------------------------------------------------------------------------
  // 3. `costoMin`: el descarte es un CONTRATO con el servidor
  // -------------------------------------------------------------------------

  group('el filtro de costo mínimo', () {
    Future<List<String>> conCostoMin(double? costoMin) async {
      final lista = await consultas.disponibles(
        sucursalId: 'B1',
        costoMin: costoMin,
        ahora: DateTime(2026, 9, 21, 16, 5),
      );
      return [for (final p in lista) p.id]..sort();
    }

    test('todo cotizado: pasa el que llega al mínimo y cae el que no', () async {
      await sembrarLasTres(costo1: 10, costo2: 2, costo3: 30);
      expect(await conCostoMin(10), ['q1', 'q3']);
      expect(await conCostoMin(null), ['q1', 'q2', 'q3'],
          reason: 'sin filtro no se cae ninguno');
    });

    test('sin cotizar cuenta como CERO y se cae — y ya ni sale sin filtro',
        () async {
      await sembrarLasTres(costo1: 10, costo2: null, costo3: 30);
      expect(
        await conCostoMin(10),
        ['q1', 'q3'],
        reason:
            'un pedido sin cotizar cuenta como cero para `costoMin` y se cae. '
            'ESTO NO SE CAMBIA SÓLO AQUÍ: es el contrato, escrito en '
            'docs/contratos-api.md:423 y hecho igual en el servidor '
            '(api/internal/api/pedidos.go:544, atado por '
            '`TestDisponiblesCostoMinCuentaElSinCotizarComoCero`). Cambiar un '
            'lado y no el otro deja a la web y a la APK contestando cosas '
            'distintas al mismo filtro, sin que salte nada (CLAUDE.md §3-bis). '
            'Si hay que cambiarlo, se cambian los cuatro sitios a la vez.',
      );
      // Desde el 07/10/2026 (incidencia 6 de Amado) el sin cotizar no aparece NI
      // SIN filtro: la lista de disponibles sólo ofrece lo cotizado en Entrega.
      expect(await conCostoMin(null), ['q1', 'q3'],
          reason: 'lo sin cotizar ya no se ofrece para armar una ruta, '
              'tenga o no filtro de costo');
    });
  });

  // -------------------------------------------------------------------------
  // 4. El globo del croquis
  // -------------------------------------------------------------------------
  //
  // `orders.price` es una COPIA de `pedidoCosto` que pierde el nulo en el
  // servidor (`price = coalesce(narg, 0)`), así que un `price` de cero sin
  // `pedidoCosto` no es un precio: es ese `coalesce`.

  group('el importe del globo del croquis', () {
    Pedido paradaCon({required double? price, required double? costo}) => Pedido(
      id: 'p1',
      customerName: 'Ana',
      address: 'Calle 1',
      endLat: 0,
      endLng: 0.1,
      weight: 10,
      status: EstadoPedido.pendiente,
      tripLeg: Tramo.ida,
      archivado: false,
      price: price,
      pedidoCosto: costo,
    );

    double? importeDe({required double? price, required double? costo}) =>
        recorridoDe(rutaAMano(paradas: [paradaCon(price: price, costo: costo)]))
            .paradas
            .single
            .importe;

    test('cotizada: el globo dice su importe', () {
      expect(importeDe(price: 12, costo: 12), 12);
      expect(usd(importeDe(price: 12, costo: 12)), '\$12.00');
      // Un domicilio gratis de verdad: `pedidoCosto = 0` es una cifra.
      expect(usd(importeDe(price: 0, costo: 0)), '\$0.00');
    });

    test('sin cotizar: el globo dice «sin cotizar», no «\$0.00»', () {
      expect(
        importeDe(price: 0, costo: null),
        isNull,
        reason:
            'ese `price = 0` es el `coalesce` del servidor sobre un pedido sin '
            'cotizar, no un precio: el globo decía «\$0.00» —que se lee como '
            'reparto gratis— mientras la hoja de paradas del detalle decía «sin '
            'cotizar» sobre la MISMA parada',
      );
      expect(usd(importeDe(price: 0, costo: null)), 'sin cotizar');
      // Y el que NO se puede tirar: un `price` distinto de cero sin
      // `pedidoCosto` no puede venir del `coalesce`, así que es un cobro de
      // verdad que lo puso la APK de Entrega.
      expect(importeDe(price: 7.5, costo: null), 7.5,
          reason: 'tirar esto sería perder un cobro puesto a mano');
    });
  });
}
