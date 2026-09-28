// DESDE «ENTREGADOS HOY» SE LLEGA A LO QUE SE ENTREGÓ.
//
// 28/09/2026, Jose delante del Panel y del Historial de Rutas:
//
// > «me dice q entregado uno y en hsitorial me sale vacio eso q se entrego si no
// > se ah completado nada»
//
// Los datos estaban bien: el pedido se entregó a las 19:44 en una ruta que sigue
// EN CURSO, y el Historial cuenta rutas cerradas. No había ningún fallo en los
// números. **El fallo fue que tuvo que preguntarlo**, porque un contador que dice
// «1» y no deja ver CUÁL obliga a adivinar.
//
// Lo que se comprueba aquí es el gesto entero, en los dos anchos de trabajo: que
// la tarjeta lleve a la lista, que llegue acotada y que la dirección aguante —que
// es lo que hace que el enlace se pueda pegar en un chat y que recargar no
// devuelva la lista entera—.
//
// La otra mitad, que la lista diga el MISMO número que la tarjeta, se comprueba
// sin pintar nada en `test/pantallas/pedidos/entregados_hoy_cuadra_test.dart`
// (`CLAUDE.md` §3-bis).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/panel/datos/textos_de_las_cifras.dart';
import 'package:reparto/pantallas/panel/vista/pantalla_panel.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_en_la_url.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  // La base se ABRE en el `setUp` y se SIEMBRA en el cuerpo: `CLAUDE.md` §5.2.
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  final ahora = DateTime(2026, 9, 28, 19, 50);

  Future<void> sucursal() => base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: 'stg',
          name: 'Santiago de Cuba',
          lat: 20.02,
          lng: -75.82,
        ),
      );

  Future<void> ruta(String id, String estado) => base
      .into(base.routes)
      .insert(
        RoutesCompanion.insert(
          id: id,
          routeCode: Value(id),
          status: Value(estado),
          branchId: const Value('stg'),
        ),
      );

  Future<void> pedido(
    String id, {
    required DateTime? entregadoEn,
    String? rutaId,
    String folio = 'F-1',
  }) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          operationNumber: Value(folio),
          branchId: const Value('stg'),
          routeId: Value(rutaId),
          endLat: const Value(20.0),
          facturaEstado: const Value('igual'),
          weight: const Value(10),
          deliveredAt: Value(entregadoEn),
        ),
      );

  /// PEDIDOS NO ASIENTA NUNCA, así que aquí no se puede usar `pumpAndSettle`.
  ///
  /// Es lo mismo que ya hace `test/pantallas/pedidos/de_pedidos_se_puede_salir_test.dart`,
  /// y por el mismo motivo: esa pantalla se reescribe la dirección después de
  /// cada fotograma y tiene un indicador girando mientras sus streams contestan.
  /// `pumpAndSettle` ahí **se cuelga en vez de fallar**, que es lo peor que puede
  /// hacer una prueba (`CLAUDE.md` §5). Unos cuantos fotogramas acotados sí
  /// terminan siempre.
  Future<void> bombear(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  late GoRouter enrutador;

  /// SIN EL ARMAZÓN, y a propósito.
  ///
  /// Aquí se monta el Panel y Pedidos colgando de un `GoRouter` pelado, que es
  /// lo mismo que hace `test/pantallas/pedidos/de_pedidos_se_puede_salir_test.dart`
  /// y por el mismo tipo de motivo: el armazón (barra lateral, barra superior,
  /// franja de estado) **desborda 9,6 px a 390 px** en cuanto tiene más de una
  /// pantalla registrada, y eso es de antes de esta pieza y no vive en el Panel.
  /// Mezclarlo aquí haría fallar esta prueba por un fallo que no es el suyo, y
  /// peor: la dejaría roja para siempre sin decir nada útil.
  ///
  /// Lo que sí es de esta prueba —que la tarjeta se toque y a dónde lleva— se
  /// comprueba entero, en los dos anchos.
  ///
  /// [pedidosDeVerdad] monta la pantalla de Pedidos tal cual, para comprobar que
  /// la dirección del enlace la entiende quien la recibe. A 390 px se usa un
  /// doble, porque esa pantalla arrastra a ese ancho un desborde suyo —la franja
  /// azul del arranque acotado más la rejilla de filtros— que se reproduce
  /// entrando directo a `/orders` sin tocar nada de aquí.
  Future<void> montar(
    WidgetTester tester, {
    required double ancho,
    bool pedidosDeVerdad = true,
  }) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    enrutador = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: PantallaPanel()),
        ),
        GoRoute(
          path: FiltrosEnLaUrl.camino,
          builder: (_, estado) => Scaffold(
            body: pedidosDeVerdad
                ? PantallaPedidos(consulta: estado.uri.queryParameters)
                : const Center(child: Text('AQUÍ ESTÁN LOS PEDIDOS')),
          ),
        ),
      ],
    );
    addTearDown(enrutador.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          // El Panel de la WEB, que es donde mira Jose: sin el aparato de
          // trabajar sin conexión (`CLAUDE.md` §1).
          trabajaSinConexionProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(routerConfig: enrutador),
      ),
    );
    await bombear(tester);
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  final laTarjeta = find.byKey(
    const ValueKey(TextosDeLasCifras.verLosEntregados),
  );

  for (final ancho in [390.0, 1400.0]) {
    testWidgets(
      'a ${ancho.toInt()} px, tocar «Entregados hoy» abre la lista de esos pedidos',
      (tester) async {
        await sucursal();
        await ruta('RT-20260928-001', EstadoRuta.enCurso);
        await pedido(
          'p1',
          folio: 'POR26-260925-3700',
          rutaId: 'RT-20260928-001',
          entregadoEn: DateTime(2026, 9, 28, 19, 44),
        );
        await pedido(
          'p2',
          entregadoEn: DateTime(2026, 9, 27, 10, 0),
          folio: 'F-AYER',
        );
        await pedido('p3', entregadoEn: null, folio: 'F-SIN');

        await montar(tester, ancho: ancho, pedidosDeVerdad: false);

        expect(find.text('Entregados hoy'), findsOneWidget);
        await tester.ensureVisible(laTarjeta);
        await bombear(tester);
        await tester.tap(laTarjeta);
        await bombear(tester);

        expect(
          enrutador.state.uri.path,
          '/orders',
          reason:
              'La tarjeta tiene que llevar a la pantalla que tiene el detalle, '
              'como ya hacen las acciones rápidas de abajo.',
        );
        expect(
          enrutador.state.uri.queryParameters['entregado_desde'],
          '2026-09-28',
          reason:
              'Sin el día en la dirección la lista sale con TODO lo entregado '
              'alguna vez, que es un número creíble y equivocado debajo de una '
              'tarjeta que dice otra cosa.',
        );
        expect(
          enrutador.state.uri.queryParameters['archivado'],
          '',
          reason:
              'El contador del Panel no mira `archivado`, así que el enlace tiene '
              'que quitar el arranque acotado de Pedidos o los dos números se '
              'separan en cuanto haya un archivado entregado hoy.',
        );

        expect(find.text('AQUÍ ESTÁN LOS PEDIDOS'), findsOneWidget);

        // La dirección AGUANTA: la pantalla de Pedidos la reescribe desde sus
        // filtros, así que si el viaje de ida y vuelta perdiera el filtro, aquí ya
        // no estaría.
        await bombear(tester);
        expect(
          enrutador.state.uri.queryParameters['entregado_desde'],
          '2026-09-28',
        );

        await desmontar(tester);
      },
    );
  }

  testWidgets('y la lista que se abre DICE por qué está acotada', (
    tester,
  ) async {
    await sucursal();
    await ruta('RT-20260928-001', EstadoRuta.enCurso);
    await pedido(
      'p1',
      folio: 'POR26-260925-3700',
      rutaId: 'RT-20260928-001',
      entregadoEn: DateTime(2026, 9, 28, 19, 44),
    );
    await pedido(
      'p2',
      entregadoEn: DateTime(2026, 9, 27, 10, 0),
      folio: 'F-AYER',
    );

    // Con la pantalla de Pedidos DE VERDAD, y a 1400 px por lo que dice
    // `montar`: a 390 px esa pantalla arrastra un desborde suyo, anterior a
    // esto.
    await montar(tester, ancho: 1400);
    await tester.ensureVisible(laTarjeta);
    await bombear(tester);
    await tester.tap(laTarjeta);
    await bombear(tester);

    expect(
      find.textContaining('entregados desde el'),
      findsOneWidget,
      reason:
          'La cabecera tiene que decir por qué la lista está acotada. Un '
          'total acotado que no se explica se lee como el total, que es el '
          'mismo fallo que trajo a Jose a preguntar.',
    );

    await desmontar(tester);
  });

  testWidgets(
    'con cero entregados la tarjeta NO se toca: no hay lista que enseñar',
    (tester) async {
      await sucursal();
      await pedido('p1', entregadoEn: null);

      await montar(tester, ancho: 390);

      expect(find.text('Entregados hoy'), findsOneWidget);
      expect(
        laTarjeta,
        findsNothing,
        reason:
            'Un gesto que lleva a una pantalla vacía es peor que ninguno: enseña '
            'una salida que no lleva a nada.',
      );

      await desmontar(tester);
    },
  );

  testWidgets('la línea de arriba dice de qué sucursal son las cifras', (
    tester,
  ) async {
    await sucursal();
    await pedido('p1', entregadoEn: null);

    await montar(tester, ancho: 390);

    expect(
      find.text('Cifras de todas las sucursales'),
      findsOneWidget,
      reason:
          'Parte de la confusión del 28/09/2026 fue ésa: la ruta completada que '
          'buscaba existía, pero era de otra sucursal.',
    );

    await desmontar(tester);
  });
}
