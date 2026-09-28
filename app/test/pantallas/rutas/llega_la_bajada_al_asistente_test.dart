// LA SONDA DEL §3-ter PARA EL ASISTENTE DE RUTAS.
//
// Cinco providers de `estado/proveedores_rutas.dart` eran `FutureProvider` sin
// `autoDispose`: una sola respuesta, la del instante en que alguien los mira,
// guardada para siempre. En la APK da igual —la base sobrevive y al pintar los
// datos ya están—, pero **en la web la base nace vacía en cada carga** y el
// ciclo la llena un segundo más tarde. Esa única respuesta es siempre la de la
// base vacía.
//
// La forma de la prueba es la que manda el `CLAUDE.md` §3-ter y no otra:
// **montar con la base VACÍA y sembrar DESPUÉS, sin volver a montar.** Sembrar
// en el `setUp` es justo el caso que un `Future` resuelve bien, y por eso las
// pruebas que había —`asistente_wizard_test.dart` lo dice en su `pintar`— no lo
// cazaban.
//
// Y va en pareja: cada caso tiene su gemelo de «cuando de verdad no hay nada,
// se sigue diciendo que no hay nada». Sin eso, «arreglarlo» pintando cualquier
// cosa también pasaría.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// Desmonta el arbol DENTRO del cuerpo.
///
/// Hace falta **aqui y no solo en un `addTearDown`**: la comprobacion de «no
/// quedan temporizadores» corre al acabar el cuerpo, y los `Stream` de Drift
/// dejan uno de cero al cerrarse. El `addTearDown` de [pintar] es la otra mitad,
/// para cuando un `expect` revienta a mitad y el cuerpo no llega hasta aqui.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// La sucursal y el camión, que son lo que baja ANTES: en
  /// `Colecciones.todas`, `branches` y `vehicles` van delante de `warehouses`,
  /// que es la penúltima de las nueve.
  Future<void> loQueBajaPrimero() async {
    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'B1',
            name: 'Camagüey',
            lat: 21.38,
            lng: -77.91,
            externalId: const Value('CAM'),
          ),
        );
    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'V1',
            name: 'Camión 1',
            capacity: const Value(1000),
            plate: const Value('P-001'),
            branchId: const Value('B1'),
          ),
        );
  }

  /// Y los almacenes, que bajan los últimos.
  Future<void> llegaElAlmacen() => base
      .into(base.warehouses)
      .insert(
        WarehousesCompanion.insert(
          id: 'W1',
          sucursalCodigo: 'CAM',
          nombre: 'Almacén central',
          lat: const Value(21.38),
          lng: const Value(-77.91),
          principal: const Value(true),
        ),
      );

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // EL DESMONTAJE VA EN UN `addTearDown` Y NO AL FINAL DEL CUERPO.
    //
    // Si un `expect` falla a mitad, el cuerpo no llega a desmontar y el arbol
    // se queda vivo con los `Stream` de Drift abiertos: entonces el
    // `base.close()` del `tearDown` no vuelve y **la prueba se cuelga en vez de
    // fallar**, que es lo peor que puede hacer una prueba (`CLAUDE.md` §5).
    // Asi se desmonta pase lo que pase.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      // Varias pasadas: cada `Stream` de Drift deja al cerrarse un temporizador
      // de cero, y el propio desmontaje los crea al final de su fotograma. Sin
      // dejarlos dispararse, la prueba falla por «quedan Timer» sin que haya
      // nada roto.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: AsistenteNuevaRuta()),
        ),
      ),
    );
    await asentar(tester);
  }

  // ---------------------------------------------------------------------------
  // 1. `almacenesProvider(codigo)` — el paso 2, «Salida»
  // ---------------------------------------------------------------------------

  testWidgets(
    'los almacenes bajan los últimos y el paso 2 se entera: deja de decir que '
    'no hay ninguno y ofrece el que llegó',
    (tester) async {
      await loQueBajaPrimero();
      await pintar(tester);

      // Paso 1: la sucursal se autocompleta (sólo hay una). Al 2, que es donde
      // se elige de dónde sale el camión.
      await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
      await asentar(tester);
      expect(
        find.text(AsistenteNuevaRuta.sinAlmacenes),
        findsOneWidget,
        reason: 'con `warehouses` vacía esto es la verdad, de momento',
      );

      // Y AHORA baja la colección, con el cajón abierto. Nadie recarga.
      await llegaElAlmacen();
      await asentar(tester);

      expect(
        find.text(AsistenteNuevaRuta.sinAlmacenes),
        findsNothing,
        reason:
            'el almacén ya está en la base: con un `Future` el paso 2 se '
            'quedaba SIN NINGUNA OPCIÓN para siempre, y no se arregla cerrando '
            'y reabriendo el cajón porque el caché es del provider',
      );

      // Y la salida se resolvió sola: `_salida ??= conUbicacion.firstOrNull`
      // encontró el principal, y por eso el asistente sigue de largo al paso 3.
      // Con el `Future` ese `??=` no se resolvía NUNCA.
      expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(3)), findsOneWidget);

      // De vuelta al 2 por su tramo de la barra, que es donde se ve cuál es.
      await tester.tap(find.byKey(AsistenteNuevaRuta.claveDelTramo(2)));
      await asentar(tester);
      expect(find.text('Almacén central'), findsOneWidget);


      await desmontar(tester);
    },
  );

  testWidgets(
    'LA OTRA MITAD: si de verdad no hay ningún almacén, se sigue diciendo',
    (tester) async {
      await loQueBajaPrimero();
      await pintar(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
      await asentar(tester);
      await asentar(tester);

      expect(find.text(AsistenteNuevaRuta.sinAlmacenes), findsOneWidget);
      expect(find.text('Almacén central'), findsNothing);


      await desmontar(tester);
    },
  );

  // ---------------------------------------------------------------------------
  // 2. `disponiblesProvider`, `opcionesDeDisponiblesProvider` y
  //    `renglonesDeDisponiblesProvider` — el paso 4
  // ---------------------------------------------------------------------------

  /// Del arranque al paso 4. Con sucursal y almacén resueltos el asistente abre
  /// ya en el 3, así que sólo queda elegir camión y seguir.
  Future<void> llegarAlPaso4(WidgetTester tester) async {
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(3)), findsOneWidget);
    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Camión 1'));
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsOneWidget);
  }

  testWidgets(
    'los pedidos bajan con el paso 4 delante: deja de decir que no hay '
    'ninguno, y los desplegables se llenan',
    (tester) async {
      await loQueBajaPrimero();
      await llegaElAlmacen();
      await pintar(tester);
      await llegarAlPaso4(tester);

      expect(
        find.text(AsistenteNuevaRuta.sinPedidos),
        findsOneWidget,
        reason: 'la base está vacía: de momento es la verdad',
      );

      // Baja `orders`. Con la pantalla delante y sin remontar.
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Doña Rosa',
        vendedor: 'Chaplin',
        municipio: 'Vertientes',
        endLat: 21.38,
        endLng: -77.91,
        fecha: ahora,
      );
      await asentar(tester);

      expect(
        find.text(AsistenteNuevaRuta.sinPedidos),
        findsNothing,
        reason:
            '«No hay pedidos disponibles para rutear» encima de una sucursal '
            'con pedidos es un cero creíble y equivocado',
      );
      expect(find.textContaining('Doña Rosa'), findsWidgets);

      await desmontar(tester);
    },
  );

  testWidgets(
    'y los dos desplegables del paso 4 se llenan con lo que bajó: es el MISMO '
    'fallo que ya se arregló en los de Pedidos el 17/09 y que no se llevó aquí',
    (tester) async {
      await loQueBajaPrimero();
      await llegaElAlmacen();
      await pintar(tester);
      await llegarAlPaso4(tester);

      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Doña Rosa',
        vendedor: 'Chaplin',
        municipio: 'Vertientes',
        endLat: 21.38,
        endLng: -77.91,
        fecha: ahora,
      );
      await asentar(tester);

      await tester.tap(find.text('Todos los vendedores'));
      await asentar(tester);
      expect(
        find.widgetWithText(ListTile, 'Chaplin'),
        findsOneWidget,
        reason:
            'con un `Future` los desplegables de municipio y vendedor se '
            'quedaban vacíos para siempre y no había forma de filtrar sin '
            'recargar la página',
      );

      await desmontar(tester);
    },
  );

  testWidgets(
    'y los renglones, que bajan DESPUÉS de los pedidos, también: los artículos '
    'de cada fila salen solos',
    (tester) async {
      await loQueBajaPrimero();
      await llegaElAlmacen();
      await base
          .into(base.products)
          .insert(
            ProductsCompanion.insert(
              id: 'p1',
              name: 'Arroz',
              weight: const Value(25),
              unitsPerPackage: const Value(10),
            ),
          );
      await pintar(tester);
      await llegarAlPaso4(tester);

      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Doña Rosa',
        endLat: 21.38,
        endLng: -77.91,
        fecha: ahora,
      );
      await asentar(tester);
      expect(find.textContaining('Arroz'), findsNothing);

      // `order_items` es la SEGUNDA colección de la bajada, pero aquí lo que
      // importa es que llega sin que `orders` se vuelva a tocar: con un
      // `Future` colgado de la lista, esta respuesta no se volvía a pedir nunca.
      await sembrarRenglon(
        base,
        id: 'i1',
        pedidoId: 'o1',
        producto: 'Arroz',
        unidades: 20,
        empaques: 2,
        productoId: 'p1',
      );
      await asentar(tester);

      expect(
        find.textContaining('Arroz'),
        findsWidgets,
        reason: 'el pedido lleva 2 empaques de arroz y la fila no lo decía',
      );


      await desmontar(tester);
    },
  );

  // ---------------------------------------------------------------------------
  // 3. `renglonesDeParadasProvider` — la `Carga total` y el `Queda en el camión`
  // ---------------------------------------------------------------------------
  //
  // Éste no se mira por la pantalla sino por el provider, y con la misma forma:
  // se enciende con la base vacía y se siembra después, sin volver a
  // encenderlo. Sus dos pantallas —`cierre_de_ruta.dart` y `detalle_ruta.dart`—
  // son de otro agente.

  test(
    'los renglones de las paradas llegan después que las paradas y la carga se '
    'entera',
    () async {
      final contenedor = ProviderContainer(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
      );
      addTearDown(contenedor.dispose);
      // Un oyente, que es lo que mantiene el provider vivo: sin él se apagaría
      // entre lectura y lectura y el caché no se vería.
      contenedor.listen(
        renglonesDeParadasProvider('R1'),
        (_, _) {},
        fireImmediately: true,
      );

      await base
          .into(base.products)
          .insert(
            ProductsCompanion.insert(
              id: 'p1',
              name: 'Arroz',
              weight: const Value(25),
              unitsPerPackage: const Value(10),
            ),
          );
      await sembrarRuta(base, id: 'R1');
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Doña Rosa',
        rutaId: 'R1',
        fecha: ahora,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        contenedor.read(renglonesDeParadasProvider('R1')).value?['o1'] ?? [],
        isEmpty,
        reason: 'los renglones todavía no han bajado',
      );

      await sembrarRenglon(
        base,
        id: 'i1',
        pedidoId: 'o1',
        producto: 'Arroz',
        unidades: 20,
        empaques: 2,
        productoId: 'p1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        contenedor.read(renglonesDeParadasProvider('R1')).value?['o1'],
        isNotEmpty,
        reason:
            'de aquí salen la `Carga total` y el `Queda en el camión` del '
            'cierre: un peso en cero encima de un camión cargado',
      );
    },
  );
}
