// LAS DOS CUENTAS SON DISTINTAS Y LAS DOS ESTÁN BIEN.
//
//  * «Entregados hoy» cuenta **PEDIDOS** con `delivered_at` desde las 00:00;
//  * el Historial de Rutas cuenta **RUTAS** cerradas, sin ventana de tiempo.
//
// Un camión en la calle con una parada hecha sale en la primera y no en el
// segundo, y eso es lo normal. El 28/09/2026 eso dejó a Jose mirando un «1» y un
// Historial vacío sin nada que se lo explicara.
//
// Y por eso las pruebas van EN PAREJA (`CLAUDE.md` §3-quinquies: un aviso que
// sale siempre deja de leerse, y entonces tampoco se lee el día que importa):
// que la frase salga cuando hay entregas de hoy en rutas todavía abiertas, y que
// **no salga** cuando no las hay.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';
import 'package:reparto/pantallas/panel/datos/textos_de_las_cifras.dart';
import 'package:reparto/pantallas/panel/registro.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  // ---------------------------------------------------------------------------
  // LA FRASE, sin pintar nada.
  // ---------------------------------------------------------------------------

  group('el texto de «Entregados hoy»', () {
    test('sale cuando hay entregas de hoy en una ruta sin cerrar', () {
      expect(
        TextosDeLasCifras.entregadosHoy(entregadosHoy: 1, enRutaSinCerrar: 1),
        '1 en una ruta sin cerrar, aún no en el Historial',
      );
    });

    test('en plural cuando son varias rutas', () {
      expect(
        TextosDeLasCifras.entregadosHoy(entregadosHoy: 7, enRutaSinCerrar: 3),
        '3 en rutas sin cerrar, aún no en el Historial',
      );
    });

    test('NO sale con todas las rutas del día ya cerradas', () {
      expect(
        TextosDeLasCifras.entregadosHoy(entregadosHoy: 5, enRutaSinCerrar: 0),
        isNull,
        reason:
            'Ahí las dos cuentas no se contradicen en nada y no hay nada que '
            'explicar. Una frase permanente debajo del número se deja de leer, '
            'y entonces tampoco se lee el día que importa.',
      );
    });

    test('NO sale sin entregas de hoy', () {
      expect(
        TextosDeLasCifras.entregadosHoy(entregadosHoy: 0, enRutaSinCerrar: 0),
        isNull,
      );
    });
  });

  group('de quién son las cifras', () {
    test('con todas, se dice', () {
      expect(
        TextosDeLasCifras.deQuienSon(todas: true, sucursal: null),
        'Cifras de todas las sucursales',
      );
    });

    test('con una, se dice cuál', () {
      expect(
        TextosDeLasCifras.deQuienSon(
          todas: false,
          sucursal: 'Santiago de Cuba',
        ),
        'Cifras de Santiago de Cuba',
      );
    });

    test('mientras el nombre no haya bajado, NO se escribe media línea', () {
      expect(
        TextosDeLasCifras.deQuienSon(todas: false, sucursal: null),
        isNull,
        reason:
            'En la web `branches` llega un segundo después de pintar. «Cifras '
            'de» a secas es peor que nada.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // LA CUENTA de los que siguen en una ruta abierta.
  // ---------------------------------------------------------------------------

  group('entregados hoy que siguen en una ruta sin cerrar', () {
    late BaseLocal base;
    late ConsultasPanel panel;
    final ahora = DateTime(2026, 9, 28, 19, 50);

    setUp(() async {
      base = baseDePrueba();
      panel = ConsultasPanel(base, reloj: RelojFalso(ahora).leer);
      await base
          .into(base.branches)
          .insert(
            BranchesCompanion.insert(
              id: 'stg',
              name: 'Santiago',
              lat: 20.02,
              lng: -75.82,
            ),
          );
    });

    tearDown(() => base.close());

    Future<void> ruta(String id, String estado) => base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: id,
            status: Value(estado),
            branchId: const Value('stg'),
          ),
        );

    Future<void> pedido(String id, {String? rutaId, DateTime? entregadoEn}) =>
        base
            .into(base.orders)
            .insert(
              OrdersCompanion.insert(
                id: id,
                customerName: 'Cliente $id',
                address: 'Calle $id',
                branchId: const Value('stg'),
                routeId: Value(rutaId),
                deliveredAt: Value(entregadoEn),
              ),
            );

    test('el caso de Jose: entregado hoy, ruta en curso', () async {
      await ruta('r1', EstadoRuta.enCurso);
      await pedido(
        'p1',
        rutaId: 'r1',
        entregadoEn: DateTime(2026, 9, 28, 19, 44),
      );

      final c = await panel.cifras(sucursalId: 'stg').first;
      expect(c.entregadosHoy, 1);
      expect(
        c.entregadosHoyEnRutaSinCerrar,
        1,
        reason:
            'Es justo lo que hacía que el Historial de Rutas estuviera vacío '
            'con un entregado en la tarjeta.',
      );
    });

    test('con la ruta ya cerrada, no queda nada que explicar', () async {
      await ruta('r1', EstadoRuta.completada);
      await pedido(
        'p1',
        rutaId: 'r1',
        entregadoEn: DateTime(2026, 9, 28, 9, 0),
      );

      final c = await panel.cifras(sucursalId: 'stg').first;
      expect(c.entregadosHoy, 1);
      expect(
        c.entregadosHoyEnRutaSinCerrar,
        0,
        reason:
            'Ese pedido YA está en el Historial: las dos cuentas cuadran a la '
            'vista y la frase no tiene que salir.',
      );
    });

    test('una ruta PLANIFICADA tampoco está en el Historial', () async {
      await ruta('r1', EstadoRuta.planificada);
      await pedido(
        'p1',
        rutaId: 'r1',
        entregadoEn: DateTime(2026, 9, 28, 9, 0),
      );

      final c = await panel.cifras(sucursalId: 'stg').first;
      expect(
        c.entregadosHoyEnRutaSinCerrar,
        1,
        reason:
            'Lo que hace que el Historial no lo enseñe es que la ruta no esté '
            'CERRADA, no que esté rodando. Con `= in_progress` esto daría 0 y '
            'la pantalla se callaría teniendo la contradicción delante.',
      );
    });

    test('un entregado sin ruta no cuenta como «en ruta sin cerrar»', () async {
      await pedido('p1', entregadoEn: DateTime(2026, 9, 28, 9, 0));

      final c = await panel.cifras(sucursalId: 'stg').first;
      expect(c.entregadosHoy, 1);
      expect(c.entregadosHoyEnRutaSinCerrar, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Y EN LA PANTALLA, la pareja completa.
  // ---------------------------------------------------------------------------

  group('en el Panel', () {
    late BaseLocal base;
    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(
              () => DateTime(2026, 9, 28, 19, 50),
            ),
          ],
          child: RepartoApp(
            enrutador: crearEnrutador(
              pantallas: [registrarPanel()],
              inicial: '/dashboard',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
    }

    Future<void> sembrar(WidgetTester tester, String estadoDeLaRuta) async {
      await base
          .into(base.branches)
          .insert(
            BranchesCompanion.insert(
              id: 'stg',
              name: 'Santiago',
              lat: 20.02,
              lng: -75.82,
            ),
          );
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: 'r1',
              status: Value(estadoDeLaRuta),
              branchId: const Value('stg'),
            ),
          );
      await base
          .into(base.orders)
          .insert(
            OrdersCompanion.insert(
              id: 'p1',
              customerName: 'Cliente',
              address: 'Calle',
              branchId: const Value('stg'),
              routeId: const Value('r1'),
              deliveredAt: Value(DateTime(2026, 9, 28, 19, 44)),
            ),
          );
    }

    testWidgets('con la ruta en curso, la tarjeta lo dice', (tester) async {
      await sembrar(tester, EstadoRuta.enCurso);
      await montar(tester);

      expect(
        find.text('1 en una ruta sin cerrar, aún no en el Historial'),
        findsOneWidget,
      );

      await desmontar(tester);
    });

    testWidgets('LA OTRA MITAD: con la ruta cerrada NO dice nada', (
      tester,
    ) async {
      await sembrar(tester, EstadoRuta.completada);
      await montar(tester);

      expect(find.text('Entregados hoy'), findsOneWidget);
      expect(
        find.textContaining('sin cerrar'),
        findsNothing,
        reason:
            'Sin contradicción no hay frase. Si sale siempre, deja de leerse y '
            'el día que importa tampoco se lee.',
      );

      await desmontar(tester);
    });
  });
}
