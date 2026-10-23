// EL AVISO DE LA FACTURA CANCELADA EN VENTRA Y QUITADA DE SU RUTA (esquema 15; Jose y Amado,
// 23/10/2026: «quitarla e INFORMAR que esa factura ya fue cancelada»).
//
// Cuatro cosas, cada una en pareja con su contrario:
//
//  1. EL DIBUJO, a 390 y a 1440 px: una línea por factura con cliente, ruta y hora, «Entendido» con su
//     icono, sin desbordar, y SIN botón en el detalle de la ruta.
//  2. LA CONSULTA, contra la base de verdad: la ventana de 7 días, lo ya visto, la sucursal y la ruta.
//  3. §3-ter: el aviso sale cuando la bajada llega con la pantalla YA ABIERTA (base vacía al montar,
//     siembra DESPUÉS) y «Entendido» lo quita, y lo deja visto en este aparato.
//  4. EL DETALLE de la ruta afectada enseña las de esa ruta, vistas o no.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/aviso_de_facturas_canceladas.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 23, 15);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  FacturaCancelada una({
    String id = 'p-1',
    String? numero = '47412',
    String cliente = 'Bodega La Esquina',
    String? ruta = 'Centro',
    DateTime? cuando,
  }) => FacturaCancelada(
    factura: FacturaAnulada(
      id: id,
      numero: numero,
      cliente: cliente,
      branchId: 'B1',
      rutaId: 'R1',
      anuladaAt: cuando ?? DateTime(2026, 10, 23, 8, 25),
    ),
    rutaNombre: ruta,
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  void ancho(WidgetTester tester, double w, [double h = 1200]) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> sembrarAnulada(
    String id, {
    String? numero = '47412',
    DateTime? cuando,
    DateTime? vista,
    String sucursal = 'B1',
    String? ruta = 'R1',
  }) => base
      .into(base.facturasAnuladas)
      .insert(
        FacturasAnuladasCompanion.insert(
          id: id,
          numero: Value(numero),
          cliente: 'Bodega La Esquina',
          branchId: Value(sucursal),
          rutaId: Value(ruta),
          anuladaAt: cuando ?? DateTime(2026, 10, 23, 8, 25),
          vistaAt: Value(vista),
        ),
      );

  // ------------------------------------------------------------------ 1. EL DIBUJO

  for (final w in [390.0, 1440.0]) {
    group('el dibujo a ${w.toInt()} px', () {
      Future<void> pintar(
        WidgetTester tester,
        List<FacturaCancelada> facturas, {
        VoidCallback? alEntender,
      }) async {
        ancho(tester, w);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            home: Scaffold(
              body: Column(
                children: [
                  VistaDeFacturasCanceladas(
                    facturas: facturas,
                    alEntender: alEntender,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
      }

      testWidgets(
        'una línea por factura: número, cliente, ruta y hora; y Entendido con icono',
        (tester) async {
          var pulsado = 0;
          await pintar(tester, [
            una(),
            una(
              id: 'p-2',
              numero: '47415',
              cliente: 'Cafetería Sol',
              ruta: 'Vista Alegre',
            ),
          ], alEntender: () => pulsado++);

          expect(
            find.text(
              'La factura 47412 (Bodega La Esquina) fue cancelada en Ventra y se quitó de la ruta Centro · 23/10 8:25',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              'La factura 47415 (Cafetería Sol) fue cancelada en Ventra y se quitó de la ruta Vista Alegre',
            ),
            findsOneWidget,
          );
          expect(
            find.text('2 facturas canceladas se quitaron de sus rutas'),
            findsOneWidget,
          );
          expect(
            find.byIcon(Icons.done_all),
            findsOneWidget,
            reason: 'su acción lleva icono',
          );
          await tester.tap(find.byKey(claveDeEntendidoDeCanceladas));
          expect(pulsado, 1);
          expect(tester.takeException(), isNull, reason: 'a $w px no desborda');
          final caja = tester.getRect(find.byKey(claveDelAvisoDeCanceladas));
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(w), reason: 'cabe a lo ancho');
          await desmontar(tester);
        },
      );

      testWidgets(
        'con una sola, el título va en singular; sin ruta conocida, dice «de su ruta»',
        (tester) async {
          await pintar(tester, [
            una(ruta: null, numero: null),
          ], alEntender: () {});
          expect(
            find.text('Una factura cancelada se quitó de su ruta'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              'Una factura (Bodega La Esquina) fue cancelada en Ventra y se quitó de su ruta',
            ),
            findsOneWidget,
          );
          await desmontar(tester);
        },
      );

      testWidgets(
        'con muchas, se desplaza DENTRO del aviso y no se come la pantalla',
        (tester) async {
          await pintar(tester, [
            for (var i = 0; i < 12; i++)
              una(id: 'p-$i', numero: '${47400 + i}'),
          ], alEntender: () {});
          expect(tester.takeException(), isNull);
          final caja = tester.getRect(find.byKey(claveDelAvisoDeCanceladas));
          expect(
            caja.height,
            lessThan(260),
            reason: 'doce facturas no pueden dejar la lista de rutas sin sitio',
          );
          // Ninguna se esconde detrás de «y N más»: están todas en el árbol.
          expect(find.textContaining('fue cancelada en Ventra'), findsWidgets);
          await desmontar(tester);
        },
      );

      testWidgets(
        'sin botón (el detalle de la ruta) no sale Entendido; sin facturas no sale nada',
        (tester) async {
          await pintar(tester, [una()]);
          expect(find.byKey(claveDeEntendidoDeCanceladas), findsNothing);
          expect(find.byIcon(Icons.done_all), findsNothing);
          await pintar(tester, const []);
          expect(find.byKey(claveDelAvisoDeCanceladas), findsNothing);
          await desmontar(tester);
        },
      );
    });
  }

  // ------------------------------------------------------------------ 2. LA CONSULTA

  group('la consulta', () {
    late ConsultasRutas consultas;
    setUp(() => consultas = ConsultasRutas(base));

    Future<List<String>> ids(Stream<List<FacturaCancelada>> s) async => [
      for (final c in await s.first) c.factura.id,
    ];

    test(
      'trae las de los últimos 7 días, la más nueva primero, y no las vistas',
      () async {
        await sembrarCatalogo(base);
        await sembrarRuta(base, id: 'R1', codigo: 'RT-001');
        await sembrarAnulada(
          'nueva',
          cuando: ahora.subtract(const Duration(hours: 1)),
        );
        await sembrarAnulada(
          'ayer',
          cuando: ahora.subtract(const Duration(days: 1)),
        );
        await sembrarAnulada(
          'vieja',
          cuando: ahora.subtract(const Duration(days: 8)),
        );
        await sembrarAnulada('vista', vista: ahora);

        expect(await ids(consultas.facturasCanceladas(ahora: ahora)), [
          'nueva',
          'ayer',
        ]);
        expect(
          await ids(
            consultas.facturasCanceladas(ahora: ahora, soloSinVer: false),
          ),
          ['nueva', 'vista', 'ayer'],
          reason:
              'el detalle las enseña vistas o no; la de 8 días no sale nunca',
        );
      },
    );

    test('acota por sucursal y por ruta; sin sucursal, todas', () async {
      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1', codigo: 'RT-001');
      await sembrarRuta(base, id: 'R2', codigo: 'RT-002');
      await sembrarAnulada('a', sucursal: 'B1', ruta: 'R1');
      await sembrarAnulada('b', sucursal: 'B2', ruta: 'R2');

      expect(
        await ids(consultas.facturasCanceladas(ahora: ahora, sucursalId: 'B1')),
        ['a'],
      );
      expect((await ids(consultas.facturasCanceladas(ahora: ahora))).toSet(), {
        'a',
        'b',
      });
      expect(
        await ids(consultas.facturasCanceladas(ahora: ahora, rutaId: 'R2')),
        ['b'],
      );
    });

    test(
      'el nombre de la ruta: su nombre, o su código, o nada si ya no está',
      () async {
        await sembrarCatalogo(base);
        await sembrarRuta(base, id: 'R1', codigo: 'RT-001');
        await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
          const RoutesCompanion(name: Value('Centro')),
        );
        await sembrarRuta(base, id: 'R2', codigo: 'RT-002');
        await sembrarAnulada('con-nombre', ruta: 'R1');
        await sembrarAnulada('con-codigo', ruta: 'R2');
        await sembrarAnulada('borrada', ruta: 'R9');

        final todas = {
          for (final c
              in await consultas.facturasCanceladas(ahora: ahora).first)
            c.factura.id: c.rutaNombre,
        };
        expect(todas, {
          'con-nombre': 'Centro',
          'con-codigo': 'RT-002',
          'borrada': null,
        });
      },
    );

    test('«Entendido» las deja vistas, y solo las que se le dicen', () async {
      await sembrarAnulada('a');
      await sembrarAnulada('b');
      await consultas.marcarVistas(['a'], ahora);
      expect(await ids(consultas.facturasCanceladas(ahora: ahora)), ['b']);
    });
  });

  // ------------------------------------------------------------------ 3. LA BAJADA LLEGA CON LA PANTALLA ABIERTA

  for (final w in [390.0, 1440.0]) {
    testWidgets(
      'a ${w.toInt()} px: la base VACÍA al montar y la bajada llega DESPUÉS: el aviso sale solo, y Entendido lo quita',
      (tester) async {
        ancho(tester, w, 1400);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseProvider.overrideWithValue(base),
              relojProvider.overrideWithValue(() => ahora),
            ],
            child: MaterialApp(
              localizationsDelegates: delegacionesDeIdioma,
              supportedLocales: idiomas,
              home: const Scaffold(body: PantallaRutas()),
            ),
          ),
        );
        await asentar(tester);
        expect(
          find.byKey(claveDelAvisoDeCanceladas),
          findsNothing,
          reason: 'con la base vacía no hay nada que avisar',
        );

        // LLEGA LA BAJADA, sin volver a montar nada.
        await sembrarCatalogo(base);
        await sembrarRuta(base, id: 'R1', codigo: 'RT-001');
        await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
          const RoutesCompanion(name: Value('Centro')),
        );
        await sembrarAnulada('p-1', cuando: DateTime(2026, 10, 23, 8, 25));
        await asentar(tester);

        expect(
          find.textContaining(
            'La factura 47412 (Bodega La Esquina) fue cancelada en Ventra y se quitó de la ruta Centro',
          ),
          findsOneWidget,
          reason: 'un FutureProvider se habría quedado con «no hay ninguna» (§3-ter)',
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(claveDeEntendidoDeCanceladas));
        await asentar(tester);

        expect(
          find.byKey(claveDelAvisoDeCanceladas),
          findsNothing,
          reason: '«Entendido» lo quita',
        );
        final fila = await base.select(base.facturasAnuladas).getSingle();
        expect(
          fila.vistaAt,
          isNotNull,
          reason: 'y queda visto en ESTE aparato',
        );

        // Otra, nueva, vuelve a avisar: «Entendido» no apaga el aviso para siempre.
        await sembrarAnulada('p-2', numero: '47500');
        await asentar(tester);
        expect(find.textContaining('La factura 47500'), findsOneWidget);
        expect(
          find.textContaining('La factura 47412'),
          findsNothing,
          reason: 'la ya vista no vuelve',
        );

        await desmontar(tester);
      },
    );
  }

  // ------------------------------------------------------------------ 4. EL DETALLE

  testWidgets(
    'el detalle de la ruta enseña las que salieron de ELLA, vistas o no, y sin botón',
    (tester) async {
      ancho(tester, 1200, 1600);
      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1', codigo: 'RT-001');
      await sembrarRuta(base, id: 'R2', codigo: 'RT-002');
      await sembrarAnulada('a', numero: '47412', vista: ahora, ruta: 'R1');
      await sembrarAnulada('b', numero: '47999', ruta: 'R2');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: MaterialApp(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            home: const Scaffold(body: DetalleDeRuta(rutaId: 'R1')),
          ),
        ),
      );
      await asentar(tester);

      expect(
        find.textContaining('La factura 47412'),
        findsOneWidget,
        reason: 'la ya vista sigue en SU ruta',
      );
      expect(
        find.textContaining('La factura 47999'),
        findsNothing,
        reason: 'la de otra ruta no',
      );
      expect(find.byKey(claveDeEntendidoDeCanceladas), findsNothing);
      await desmontar(tester);
    },
  );
}
