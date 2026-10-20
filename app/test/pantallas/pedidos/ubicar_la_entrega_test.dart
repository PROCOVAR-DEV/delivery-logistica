// «UBICAR LA ENTREGA» EN PANTALLA (issue 19 de Amado, 20/10/2026).
//
// Lo que se comprueba, con la forma que manda el §3-ter de CLAUDE.md —montar con la
// base VACÍA y sembrar DESPUÉS, dentro del cuerpo y sin volver a montar—:
//
//  * la ficha del pedido enseña «Ubicar la entrega» SOLO cuando se puede; cuando
//    no (pedido entregado, ruta completada) no hay botón y se dice por qué;
//  * la etiqueta «Punto puesto a mano» sale cuando llega la bajada;
//  * el cajón guarda por la acción (APK: fila + apunte; web: al servidor) y, si el
//    servidor dice que no, lo dice LITERAL y se queda abierto;
//  * «Volver al punto del cliente» pregunta antes;
//  * en el asistente de rutas, la fila de un pedido tiene su botón, que NO marca
//    ni desmarca la casilla.
//
// Ni una petición sale de aquí: el geocodificador y el fondo del mapa van
// inyectados, y la web habla con un `ServidorFalso`.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/mapa/ubicacion/geocodificar.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_detalle_pedido.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 20, 9);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  final botonDeLaFicha = find.byKey(const ValueKey('ficha-ubicar-la-entrega'));
  final etiqueta = find.byKey(const ValueKey('ficha-punto-manual'));
  final noSePuede = find.byKey(const ValueKey('ficha-no-se-puede-ubicar'));
  final losTextos = find.byType(TextField);

  Future<void> pintar(
    WidgetTester tester, {
    EscrituraEnVivo? enVivo,
    Widget? pantalla,
  }) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Se desmonta pase lo que pase: si un `expect` revienta a mitad, el árbol vivo
    // dejaría los `Stream` de Drift abiertos y `base.close()` colgaría la prueba.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          geocodificadorProvider.overrideWithValue(const SinGeocodificar()),
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
          if (enVivo != null) escrituraEnVivoProvider.overrideWithValue(enVivo),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: Scaffold(
            body: pantalla ?? const CajonDetallePedido(pedidoId: 'p1'),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> sembrarElPedido({String? ruta}) async {
    await sembrarCatalogo(base);
    if (ruta != null) await sembrarRuta(base, id: ruta);
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Bodega El Cruce',
      endLat: 0,
      endLng: 0.05,
      rutaId: ruta,
      orden: ruta == null ? null : 1,
    );
  }

  Future<Pedido> elPedido() =>
      (base.select(base.orders)..where((o) => o.id.equals('p1'))).getSingle();

  group('la ficha (la base empieza VACÍA y se siembra DESPUÉS)', () {
    testWidgets('el botón y la etiqueta salen cuando llega la bajada, y se '
        'apagan según el estado', (tester) async {
      await pintar(tester);
      expect(botonDeLaFicha, findsNothing, reason: 'sin pedido no hay ficha');

      // 1. Llega el pedido: se puede ubicar y no es manual.
      await sembrarElPedido();
      await asentar(tester);
      expect(botonDeLaFicha, findsOneWidget);
      expect(find.text('Ubicar la entrega'), findsOneWidget);
      expect(etiqueta, findsNothing);
      expect(noSePuede, findsNothing);

      // 2. Llega la bajada con el punto a mano: sale la etiqueta.
      await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
        const OrdersCompanion(puntoManual: Value(true)),
      );
      await asentar(tester);
      expect(
        find.text('Punto puesto a mano'),
        findsOneWidget,
        reason: 'la ficha abierta no se enteró de que el punto es a mano',
      );
      expect(botonDeLaFicha, findsOneWidget);

      // 3. Se entrega: ni botón, y se dice por qué.
      await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
        const OrdersCompanion(resultado: Value(ResultadoParada.entregado)),
      );
      await asentar(tester);
      expect(
        botonDeLaFicha,
        findsNothing,
        reason: 'un pedido ENTREGADO no admite punto nuevo',
      );
      expect(
        tester.widget<Text>(noSePuede).data,
        'El pedido ya está entregado: no se le puede cambiar el punto',
      );
    });

    testWidgets(
      'una ruta completada apaga el botón; una planificada lo enciende',
      (tester) async {
        await pintar(tester);
        await sembrarElPedido(ruta: 'R1');
        await asentar(tester);
        expect(botonDeLaFicha, findsOneWidget);

        await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
          const RoutesCompanion(status: Value(EstadoRuta.completada)),
        );
        await asentar(tester);
        expect(botonDeLaFicha, findsNothing);
        expect(
          tester.widget<Text>(noSePuede).data,
          'La ruta ya está completada: no se le puede cambiar el punto a sus '
          'paradas',
        );

        await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
          const RoutesCompanion(status: Value(EstadoRuta.planificada)),
        );
        await asentar(tester);
        expect(botonDeLaFicha, findsOneWidget);
        expect(noSePuede, findsNothing);
      },
    );
  });

  // DECISIÓN ESCRITA (p-ruta-actual, auditoría del 20/10/2026): un pedido DEVUELTO de
  // una ruta ya COMPLETADA queda libre (`route_id` nulo) para repartirse en otra, así
  // que SE LE PERMITE cambiar el punto. El servidor lo deja (`LeerPedidoParaElPunto`
  // mira `route_id`, la ruta ACTUAL) y la app hace lo mismo: `porQueNoSePuedeUbicar`
  // pasa `routeId == null ? null : ficha.ruta`. `DetallePedido.ruta` SÍ trae la ruta
  // completada (la de `ultima_ruta_id`, de la que salió con resultado): mirarla
  // bloquearía de más y la app diría «la ruta ya está completada» de un pedido que el
  // servidor aceptaría. Lo que sigue fija lo que la app hace HOY; si Jose decide otra
  // cosa, se cambia aquí y en el servidor a la vez.
  group('un DEVUELTO de una ruta completada', () {
    testWidgets('se le puede cambiar el punto: la ruta que cuenta es la ACTUAL '
        '(ninguna), no la que lo soltó', (tester) async {
      await pintar(tester);
      await sembrarCatalogo(base);
      await sembrarRuta(
        base,
        id: 'R1',
        codigo: 'RT-COMPLETA',
        estado: EstadoRuta.completada,
      );
      await sembrarPedido(
        base,
        id: 'p1',
        cliente: 'Bodega El Cruce',
        endLat: 0,
        endLng: 0.05,
        rutaId: null,
        ultimaRutaId: 'R1',
        resultado: ResultadoParada.devuelto,
      );
      await asentar(tester);

      // El caso es el de verdad: la ficha SÍ conoce la ruta completada de la que
      // salió (si no, esta prueba pasaría por ser un pedido sin ruta y nada más).
      expect(
        find.textContaining('RT-COMPLETA'),
        findsWidgets,
        reason: 'la ficha trae la ruta de la que salió con resultado',
      );
      expect(botonDeLaFicha, findsOneWidget);
      expect(noSePuede, findsNothing);
    });

    testWidgets(
      'en cuanto vuelve a una ruta completada, otra vez no se puede',
      (tester) async {
        // La otra cara: con `route_id` puesto a una ruta completada, SÍ se bloquea.
        await pintar(tester);
        await sembrarCatalogo(base);
        await sembrarRuta(base, id: 'R1', estado: EstadoRuta.completada);
        await sembrarPedido(
          base,
          id: 'p1',
          cliente: 'Bodega El Cruce',
          endLat: 0,
          endLng: 0.05,
          rutaId: 'R1',
          resultado: ResultadoParada.devuelto,
        );
        await asentar(tester);
        expect(botonDeLaFicha, findsNothing);
        expect(noSePuede, findsOneWidget);
      },
    );
  });

  group('el cajón (APK y escritorio)', () {
    testWidgets('guardar escribe la fila y deja UN apunte; no sale nada', (
      tester,
    ) async {
      await pintar(tester);
      await sembrarElPedido();
      await asentar(tester);

      await tester.tap(botonDeLaFicha);
      await asentar(tester);
      expect(find.text('Guardar punto'), findsOneWidget);
      // Sin tocar nada no hay nada que guardar.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar punto'),
            )
            .onPressed,
        isNull,
      );

      // La caja de coordenadas es el único sitio por el que se escribe el punto.
      await tester.enterText(losTextos.at(0), 'Calle 5 entre 6 y 7');
      await tester.enterText(losTextos.at(1), '0.02, 0.3');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar punto'));
      await asentar(tester);

      final p = await elPedido();
      expect((p.puntoManual, p.endLat, p.endLng), (true, 0.02, 0.3));
      expect(p.endAddress, 'Calle 5 entre 6 y 7');
      expect(p.puntoClienteLng, 0.05, reason: 'a dónde volver');
      final lote = await ColaDeSalida(base).lote();
      expect(lote.single.metodo, 'PUT');
      expect(lote.single.ruta, '/orders/p1/punto');
      // Y el cajón se cerró: la ficha vuelve a verse con su etiqueta.
      expect(find.text('Guardar punto'), findsNothing);
      expect(find.text('Punto puesto a mano'), findsOneWidget);
    });

    testWidgets('unas coordenadas que no se entienden no dejan guardar', (
      tester,
    ) async {
      await pintar(tester);
      await sembrarElPedido();
      await asentar(tester);
      await tester.tap(botonDeLaFicha);
      await asentar(tester);

      await tester.enterText(losTextos.at(1), 'por el parque');
      await tester.pump();
      expect(find.textContaining('No se entiende'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar punto'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('el (0,0) lo rechaza la acción con el literal del servidor y '
        'el cajón sigue abierto', (tester) async {
      await pintar(tester);
      await sembrarElPedido();
      await asentar(tester);
      await tester.tap(botonDeLaFicha);
      await asentar(tester);

      await tester.enterText(losTextos.at(1), '0, 0');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar punto'));
      await asentar(tester);

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ubicar-rechazo'))).data,
        'lat y lng tienen que ser un punto del planeta',
      );
      expect((await elPedido()).puntoManual, isFalse);
      expect(await ColaDeSalida(base).lote(), isEmpty);
    });

    testWidgets('si la ruta se completa con el cajón abierto, el cajón lo dice '
        'y quita el formulario', (tester) async {
      await pintar(tester);
      await sembrarElPedido(ruta: 'R1');
      await asentar(tester);
      await tester.tap(botonDeLaFicha);
      await asentar(tester);
      expect(find.text('Guardar punto'), findsOneWidget);

      await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
        const RoutesCompanion(status: Value(EstadoRuta.completada)),
      );
      await asentar(tester);
      expect(find.text('Guardar punto'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('ubicar-no-se-puede')))
            .data,
        'La ruta ya está completada: no se le puede cambiar el punto a sus '
        'paradas',
      );
    });

    testWidgets('«Volver al punto del cliente» PREGUNTA, y solo si se dice que '
        'sí vuelve', (tester) async {
      await pintar(tester);
      await sembrarElPedido();
      await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
        const OrdersCompanion(
          endLat: Value(0.02),
          endLng: Value(0.3),
          puntoManual: Value(true),
          puntoClienteLat: Value(0),
          puntoClienteLng: Value(0.05),
        ),
      );
      await asentar(tester);
      await tester.tap(botonDeLaFicha);
      await asentar(tester);

      final volver = find.text('Volver al punto del cliente');
      expect(volver, findsOneWidget);
      // En un pedido que NO es manual el botón no existe (lo cubre el primer test
      // del grupo: ahí solo hay «Guardar punto»).
      await tester.tap(volver);
      await asentar(tester);
      // La pregunta, en un cajón encima. Decir que no no toca nada.
      expect(find.text('Sí, volver al punto del cliente'), findsOneWidget);
      await tester.tap(find.text('No, dejar el punto a mano'));
      await asentar(tester);
      expect((await elPedido()).puntoManual, isTrue);
      expect(await ColaDeSalida(base).lote(), isEmpty);

      await tester.tap(volver);
      await asentar(tester);
      await tester.tap(find.text('Sí, volver al punto del cliente'));
      await asentar(tester);
      final p = await elPedido();
      expect((p.puntoManual, p.endLat, p.endLng), (false, 0, 0.05));
      expect((await ColaDeSalida(base).lote()).single.metodo, 'DELETE');
    });
  });

  group('el cajón (web)', () {
    EscrituraEnVivo conServidor(ServidorFalso servidor) => EscrituraEnVivo(
      ClienteApi(
        dio: Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
          ..httpClientAdapter = servidor,
        esperas: const <Duration>[],
      ),
    );

    testWidgets('un 409 del servidor sale LITERAL, no escribe nada y el cajón '
        'se queda abierto', (tester) async {
      const elNo =
          'El pedido cambió mientras se guardaba el punto: vuelve a intentarlo';
      final servidor = ServidorFalso(
        (_) async => RespuestaFalsa(409, const {'error': elNo}),
      );
      await pintar(tester, enVivo: conServidor(servidor));
      await sembrarElPedido();
      await asentar(tester);
      await tester.tap(botonDeLaFicha);
      await asentar(tester);

      await tester.enterText(losTextos.at(1), '0.02, 0.3');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar punto'));
      await asentar(tester);

      final vista = servidor.vistas.single;
      expect('${vista.metodo} ${vista.ruta}', 'PUT /orders/p1/punto');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ubicar-rechazo'))).data,
        elNo,
      );
      expect(find.text('Guardar punto'), findsOneWidget);
      expect((await elPedido()).puntoManual, isFalse);
    });
  });

  group('el asistente de rutas', () {
    testWidgets('cada fila tiene «Ubicar la entrega» y pulsarlo NO marca la '
        'casilla', (tester) async {
      // La sucursal, el almacén y el camión: el asistente abre ya en el paso 3.
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
      await sembrarPedido(
        base,
        id: 'p1',
        cliente: 'Bodega El Cruce',
        endLat: 21.38,
        endLng: -77.91,
        fecha: ahora,
      );
      await pintar(tester, pantalla: const AsistenteNuevaRuta());

      await tester.tap(find.text('Elige el vehículo…'));
      await asentar(tester);
      await tester.tap(find.text('Camión 1'));
      await asentar(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
      await asentar(tester);
      expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsOneWidget);

      final casilla = find.byType(CheckboxListTile);
      expect(tester.widget<CheckboxListTile>(casilla.first).value, isFalse);
      final ubicar = find.byKey(const ValueKey('asistente-ubicar-p1'));
      expect(ubicar, findsOneWidget);
      expect(tester.widget<IconButton>(ubicar).tooltip, 'Ubicar la entrega');

      await tester.tap(ubicar);
      await asentar(tester);

      expect(
        tester.widget<CheckboxListTile>(casilla.first).value,
        isFalse,
        reason: 'el botón pequeño no marca ni desmarca el pedido',
      );
      // Y se abrió EL MISMO cajón.
      expect(find.text('Guardar punto'), findsOneWidget);

      // Desmontar DENTRO del cuerpo: los `Stream` de Drift dejan al cerrarse un
      // temporizador de cero y la comprobación de «no quedan Timer» corre al acabar.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
