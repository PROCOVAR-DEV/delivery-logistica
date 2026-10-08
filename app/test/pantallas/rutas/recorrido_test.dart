// DE LA BASE AL DIBUJO: `recorridoDe` es lo unico de todo este trozo que sabe
// que existe Drift, asi que es lo unico que se prueba contra una base de verdad.
//
// Y hay una cosa que SOLO se puede comprobar aqui: que el croquis y la lista de
// paradas cuentan la misma ruta en el mismo orden. Son dos pantallas que
// contestan a lo mismo, y dos respuestas sobre lo mismo se separan sin que salte
// nada (`CLAUDE.md` §3-bis) — salvo que haya una prueba que las ate.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'rutas_a_mano.dart';

void main() {
  group('lo que sale de la base', () {
    late BaseLocal base;

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    test('las paradas llegan al croquis en el orden de la ruta', () async {
      await sembrarCatalogo(base);
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: 'R1',
              routeCode: const Value('RT-001'),
              branchId: const Value('B1'),
              originLat: const Value(21.38),
              originLng: const Value(-77.91),
            ),
          );
      // Se siembran a proposito EN DESORDEN: si el croquis pintara en el orden
      // en que estan en la tabla —o alfabetico— esto lo caza.
      await sembrarPedido(
        base,
        id: 'o3',
        cliente: 'Ana',
        // Van EN la ruta (`routeId`): solo con `ultimaRutaId` y sin resultado
        // un pedido es una parada QUITADA, y no sale en la hoja.
        rutaId: 'R1',
        orden: 3,
        endLat: 21.3,
        endLng: -77.3,
      );
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Zoe',
        // Van EN la ruta (`routeId`): solo con `ultimaRutaId` y sin resultado
        // un pedido es una parada QUITADA, y no sale en la hoja.
        rutaId: 'R1',
        orden: 1,
        endLat: 21.1,
        endLng: -77.1,
      );
      await sembrarPedido(
        base,
        id: 'o2',
        cliente: 'Beto',
        // Van EN la ruta (`routeId`): solo con `ultimaRutaId` y sin resultado
        // un pedido es una parada QUITADA, y no sale en la hoja.
        rutaId: 'R1',
        orden: 2,
        endLat: 21.2,
        endLng: -77.2,
      );

      final ruta = await ConsultasRutas(base).rutaConTodo('R1').first;
      final recorrido = recorridoDe(ruta!);

      expect(
        [for (final p in recorrido.paradas) p.etiqueta],
        ['Zoe', 'Beto', 'Ana'],
      );
      // Y el orden del dibujo es el mismo que el de la lista de paradas del
      // detalle, que sale de esta misma consulta.
      expect(
        [for (final p in recorrido.paradas) p.id],
        [for (final p in ruta.paradas) p.id],
      );
      expect(recorrido.origen!.lat, 21.38);
      expect(recorrido.nombreDelOrigen, 'Camagüey');
    });

    test('una ruta sin coordenadas de origen no inventa ninguna', () async {
      await sembrarCatalogo(base);
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(id: 'R2', branchId: const Value('B1')),
          );

      final ruta = await ConsultasRutas(base).rutaConTodo('R2').first;
      final recorrido = recorridoDe(ruta!);

      // Ni un `0,0` de relleno, que cae en el Golfo de Guinea y dibuja una ruta
      // de nueve mil kilometros.
      expect(recorrido.origen, isNull);
      expect(recorrido.hayAlgoQueDibujar, isFalse);
    });
  });

  group('la conversion', () {
    test('numera TODAS las paradas, tengan coordenadas o no', () {
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [
            paradaAMano(id: 'a', cliente: 'Ana', lat: 21.1, lng: -77.1),
            paradaAMano(id: 'b', cliente: 'Beto'),
            paradaAMano(id: 'c', cliente: 'Carla', lat: 21.3, lng: -77.3),
          ],
        ),
      );

      expect([for (final p in recorrido.paradas) p.numero], [1, 2, 3]);
      expect([for (final p in recorrido.dibujables) p.numero], [1, 3]);
      expect(recorrido.sinCoordenadas, 1);
    });

    test('una parada a medias —lat sin lng— no se dibuja', () {
      // Media coordenada es peor que ninguna: se pinta en el meridiano cero.
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [paradaAMano(id: 'a', cliente: 'Ana', lat: 21.1)],
        ),
      );

      expect(recorrido.dibujables, isEmpty);
      expect(recorrido.sinCoordenadas, 1);
    });

    test('se sabe cual esta entregada y cual va en el regreso', () {
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [
            paradaAMano(
              id: 'a',
              cliente: 'Ana',
              lat: 21.1,
              lng: -77.1,
              resultado: ResultadoParada.entregado,
            ),
            paradaAMano(
              id: 'b',
              cliente: 'Beto',
              lat: 21.2,
              lng: -77.2,
              tramo: Tramo.regreso,
            ),
            paradaAMano(
              id: 'c',
              cliente: 'Carla',
              lat: 21.3,
              lng: -77.3,
              resultado: ResultadoParada.devuelto,
            ),
          ],
        ),
      );

      expect(recorrido.paradas[0].entregada, isTrue);
      expect(recorrido.paradas[1].esRegreso, isTrue);
      // `devuelto` NO es `entregado`: se pinta como pendiente, que es lo que es.
      expect(recorrido.paradas[2].entregada, isFalse);
    });

    /// EL IMPORTE DEL GLOBO SON DOS COLUMNAS, NO UNA — 23/09/2026.
    ///
    /// Esto miraba `price` a secas y daba por bueno un `price = 0` sin
    /// `pedidoCosto`. No lo es: `orders.price` es una COPIA de `pedidoCosto`
    /// que se hace al enganchar el pedido a la ruta, y el servidor la guarda con
    /// `price = coalesce(sqlc.narg('price'), 0)`
    /// (`api/db/queries/routes.sql:283`). O sea que en cuanto una parada SIN
    /// COTIZAR entra en una ruta, su `price` vale 0 y ya nunca es nulo: el globo
    /// decia **`$0.00`** mientras la hoja de paradas del detalle —que lee
    /// `pedidoCosto`— decia «sin cotizar» sobre la MISMA parada.
    ///
    /// La regla es la de `ConsultasInformes.ingresoDe`, y se usa DE ALLI y no
    /// copiada (`CLAUDE.md` §3-bis). Las parejas estan tambien en
    /// `el_cero_que_se_escribe_test.dart`.
    test('el importe nulo se queda nulo y no se convierte en cero', () {
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [
            paradaAMano(id: 'a', cliente: 'Ana', lat: 21.1, lng: -77.1),
            // Un domicilio GRATIS de verdad: `pedidoCosto = 0` es una cifra.
            paradaAMano(
              id: 'b',
              cliente: 'Beto',
              lat: 21.2,
              lng: -77.2,
              precio: 0,
              costo: 0,
            ),
            // SIN COTIZAR y ya enganchada a una ruta: el `price = 0` de aqui es
            // el `coalesce` del servidor, no un precio.
            paradaAMano(
              id: 'c',
              cliente: 'Carla',
              lat: 21.3,
              lng: -77.3,
              precio: 0,
            ),
            // Cotizada desde la APK de Entrega despues de engancharla: un
            // `price` distinto de cero no puede venir del `coalesce`, asi que
            // es un cobro de verdad y tirarlo seria perderlo.
            paradaAMano(
              id: 'd',
              cliente: 'Dani',
              lat: 21.4,
              lng: -77.4,
              precio: 7.5,
            ),
          ],
        ),
      );

      expect(recorrido.paradas[0].importe, isNull);
      // Un cero de verdad sigue siendo un cero: lo que no vale es fabricarlo.
      expect(recorrido.paradas[1].importe, 0);
      expect(
        recorrido.paradas[2].importe,
        isNull,
        reason:
            'un `price` de cero sin `pedidoCosto` es el coalesce del servidor '
            'sobre una parada sin cotizar: pintarlo como \$0.00 dice que el '
            'reparto salio gratis',
      );
      expect(recorrido.paradas[3].importe, 7.5);
    });
  });
}
