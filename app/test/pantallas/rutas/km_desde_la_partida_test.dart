// «— DESDE PARTIDA» EN LAS TRES PARADAS DE UNA RUTA QUE SÍ SE PODÍA MEDIR.
//
// Jose, en el teléfono el 28/09/2026, con `RT-20260928-001` (3 paradas,
// Santiago): cada parada del cajón de «Ver paradas» decía «— desde partida», y
// no era un tirón de red. La insignia leía `orders.segment_km` **y nada más**, y
// esa columna se queda nula en el camino que más se usa: armar la ruta de una
// zona desde el Tablero en el aparato (`pantallas/tablero/datos/repositorio.dart`
// escribe `routeId`, `ultimaRutaId`, `vehicleId` y `stopOrder`, y ahí se acaba).
//
// Lo que hace esta tanda de pruebas, y por qué cada una:
//
//  1. **Que el número salga sin la columna.** Las coordenadas están en el
//     aparato —son las que pintan el mapa— y la cuenta es la de siempre.
//  2. **Que sea EL MISMO número que el Tablero.** El Tablero ya mide esto para
//     cada tarjeta (`kmAlAlmacen`, la radial del almacén al cliente) y lo pinta
//     al lado. Dos pantallas midiendo lo mismo con dos cuentas distintas es el
//     §3-bis del `CLAUDE.md`, y aquí hay de verdad **dos haversine escritas
//     aparte** —`rutas/datos/geo.dart` con `atan2` y `tablero/datos/geo.dart`
//     con `asin`—, así que esto no es simetría de adorno: es lo único que las
//     ata. El propio `tablero/datos/geo.dart` lo dice: «Lo que NO puede haber
//     son dos medidas distintas de cuán lejos está este cliente».
//  3. **Que cuando no se sabe, se diga por qué.** Una raya muda no vale. Y son
//     dos motivos distintos —falta el almacén, o falta el cliente— que llevan a
//     sitios distintos a arreglarlo.
//
// La tarjeta se prueba SUELTA, sin `ProviderScope` y sin base: dentro de un
// `testWidgets` una consulta de Drift cuelga la prueba en vez de fallarla
// (`CLAUDE.md` §5). Por eso `TarjetaDeParada` es pública, igual que
// `LineaDeDatosDeLaRuta`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/formato_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
// El vecino con el que hay que cuadrar. Se importa a propósito: si el Tablero
// cambia de cuenta o de formato, esto se pone rojo y nos enteramos aquí.
import 'package:reparto/pantallas/tablero/datos/geo.dart' as tablero;
import 'package:reparto/pantallas/tablero/vista/kit.dart' as tablero_kit;

import 'rutas_a_mano.dart';

/// El almacén de Santiago y tres clientes suyos, con coordenadas de verdad.
const almacenLat = 20.0217;
const almacenLng = -75.8294;

void main() {
  // ------------------------------------------------------------- el número
  group('kmDeLaParadaDesdeLaPartida', () {
    test('sin `segment_km` en la base, se mide con las coordenadas', () {
      final km = kmDeLaParadaDesdeLaPartida(
        guardado: null,
        origenLat: 20.0,
        origenLng: -75.0,
        lat: 21.0,
        lng: -75.0,
      );

      expect(
        km,
        isNotNull,
        reason:
            'ES EL FALLO DE RT-20260928-001: `segment_km` nulo no es «no se '
            'sabe dónde está el cliente». El aparato tiene el origen de la ruta '
            'y el punto del cliente, que son los mismos con los que pinta el '
            'mapa, y con eso se mide.',
      );
      // Un grado de latitud son 6371·π/180 km. Va a pelo y no calculado con la
      // misma función que se prueba: una prueba que repite la cuenta del código
      // no comprueba la cuenta.
      expect(km, closeTo(111.1949, 0.001));
    });

    test('con `segment_km` escrito, MANDA el de la base', () {
      final km = kmDeLaParadaDesdeLaPartida(
        guardado: 7.25,
        origenLat: 20.0,
        origenLng: -75.0,
        lat: 21.0,
        lng: -75.0,
      );

      expect(
        km,
        7.25,
        reason:
            'ES EL NÚMERO CON EL QUE SE COBRÓ EL DOMICILIO, y el del cobro no '
            'se recalcula: si el origen de la ruta cambiara después, el de la '
            'base sigue siendo el que se facturó.',
      );
    });

    test('la misma parada mide LO MISMO aquí que en el Tablero', () {
      // Tres clientes de Santiago, del más cercano al más lejano.
      const clientes = [
        (20.0450, -75.8000),
        (20.0100, -75.9000),
        (19.9800, -75.7500),
      ];

      for (final (lat, lng) in clientes) {
        final aqui = kmDeLaParadaDesdeLaPartida(
          origenLat: almacenLat,
          origenLng: almacenLng,
          lat: lat,
          lng: lng,
        );
        final enElTablero = tablero.kmHaversine(
          almacenLat,
          almacenLng,
          lat,
          lng,
        );

        expect(
          aqui,
          closeTo(enElTablero, 1e-9),
          reason:
              'DOS MEDIDAS DE «CUÁN LEJOS ESTÁ ESTE CLIENTE» NO PUEDEN DAR DOS '
              'NÚMEROS. La tarjeta del Tablero y la parada de la ruta se miran '
              'seguidas, y con esta misma distancia se le cobra el domicilio. '
              'Aquí ($lat, $lng): Rutas dice $aqui y el Tablero $enElTablero.',
        );
        // Y el rótulo escribe los kilómetros con el formato del Tablero, no con
        // uno propio: mismo número Y mismas letras.
        expect(
          rotuloDesdeLaPartida(
            origenLat: almacenLat,
            origenLng: almacenLng,
            lat: lat,
            lng: lng,
          ),
          startsWith(tablero_kit.kmBonito(enElTablero)),
          reason:
              'el mismo kilometraje escrito «12,3 km» en una pantalla y '
              '«12.35 km» en la de al lado es el mismo bulto con dos nombres '
              '(CLAUDE.md §3-bis)',
        );
      }
    });
  });

  // --------------------------------------------- la raya nunca es muda
  group('cuando no se puede medir, se dice por qué', () {
    test('sin coordenadas del cliente: «sin ubicar»', () {
      final rotulo = rotuloDesdeLaPartida(
        origenLat: almacenLat,
        origenLng: almacenLng,
        lat: null,
        lng: null,
      );

      expect(
        rotulo,
        'sin ubicar',
        reason:
            'SON LAS MISMAS PALABRAS QUE EL TABLERO usa para un pedido sin '
            'coordenadas (`kmBonito`). Lo que falta aquí es la dirección del '
            'cliente, y se arregla en el pedido, no en la ruta.',
      );
      expect(
        rotulo,
        isNot(contains('—')),
        reason: 'una raya muda no dice qué falta ni a dónde ir a buscarlo',
      );
    });

    test('sin punto de partida de la ruta: se dice que falta el almacén', () {
      final rotulo = rotuloDesdeLaPartida(
        origenLat: null,
        origenLng: null,
        lat: 20.045,
        lng: -75.8,
      );

      expect(
        rotulo,
        'sin punto de partida',
        reason:
            'SON LAS MISMAS PALABRAS QUE LA TARJETA DE LA LISTA DE RUTAS. Y es '
            'un motivo DISTINTO del anterior: aquí el cliente está ubicado y lo '
            'que falta es de dónde salió el camión, que se arregla en la ruta.',
      );
      expect(rotulo, isNot(contains('—')));
    });

    test('los dos motivos no se confunden en un solo mensaje', () {
      expect(
        rotuloDesdeLaPartida(),
        'sin ubicar',
        reason:
            'sin nada de nada se nombra primero lo del cliente, que es lo que '
            'hay que arreglar antes: con el pedido sin ubicar, poner el almacén '
            'no daría ningún número',
      );
    });
  });

  // ------------------------------------------------- y en la tarjeta, pintado
  group('la tarjeta de una parada', () {
    Future<void> pintar(
      WidgetTester tester,
      Widget tarjeta,
    ) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: tarjeta))),
    );

    testWidgets('con `segment_km` nulo PERO con coordenadas, sale el número', (
      tester,
    ) async {
      await pintar(
        tester,
        TarjetaDeParada(
          numero: 1,
          parada: paradaAMano(
            id: 'p1',
            cliente: 'Ana',
            lat: 21.0,
            lng: -75.0,
            costo: 8.0,
          ),
          origenLat: 20.0,
          origenLng: -75.0,
          lineas: const <RenglonConPeso>[],
        ),
      );

      expect(
        find.textContaining('111,2 km en recta desde la partida'),
        findsOneWidget,
        reason:
            'ES LA PARADA DE RT-20260928-001: `segment_km` sin escribir porque '
            'la ruta se armó desde el Tablero, y la distancia perfectamente '
            'medible con lo que ya hay en el aparato.',
      );
      expect(
        find.textContaining('—'),
        findsNothing,
        reason: 'la raya que Jose vio en las tres paradas',
      );
      expect(
        find.textContaining('desde partida'),
        findsNothing,
        reason:
            'EL RÓTULO VIEJO MENTÍA: `segment_km` es la RADIAL del almacén al '
            'cliente, no lo que se lleva andado de ruta. Debajo de unas paradas '
            'numeradas, «desde partida» a secas se lee como la acumulada — que '
            'es otro número y más grande.',
      );
    });

    testWidgets('sin coordenadas, la insignia dice qué falta', (tester) async {
      await pintar(
        tester,
        TarjetaDeParada(
          numero: 2,
          parada: paradaAMano(id: 'p2', cliente: 'Beto', costo: 3.0),
          origenLat: 20.0,
          origenLng: -75.0,
          lineas: const <RenglonConPeso>[],
        ),
      );

      expect(find.textContaining('sin ubicar'), findsOneWidget);
      expect(
        find.textContaining('0,0 km'),
        findsNothing,
        reason:
            'PINTAR CERO KILÓMETROS SOBRE UN CLIENTE QUE NADIE SABE DÓNDE ESTÁ '
            'es peor que no pintar nada: lo pondría el primero de la ruta.',
      );
      expect(find.textContaining('—'), findsNothing);
    });

    testWidgets('con `segment_km` escrito se pinta ÉSE, no el recalculado', (
      tester,
    ) async {
      await pintar(
        tester,
        TarjetaDeParada(
          numero: 3,
          parada: paradaAMano(
            id: 'p3',
            cliente: 'Cira',
            lat: 21.0,
            lng: -75.0,
            segmentKm: 7.25,
            costo: 5.0,
          ),
          origenLat: 20.0,
          origenLng: -75.0,
          lineas: const <RenglonConPeso>[],
        ),
      );

      expect(find.textContaining('7,3 km en recta desde la partida'), findsOneWidget);
      expect(
        find.textContaining('111,2 km'),
        findsNothing,
        reason:
            'el número del cobro no se recalcula por debajo a quien ya lo tiene '
            'escrito',
      );
    });
  });
}
