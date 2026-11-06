// LOS ESTADOS DE LAS PARADAS EN LA RUTA DEL DISTRIBUIDOR (issue 26 de Amado, 06/11/2026): la ruta
// guiada enseña TODAS las paradas con su etiqueta, y al marcar una la etiqueta cambia YA, sin esperar
// a subir (el cobro vive en `cobros_de_entrega`, lo que se marco en este aparato).
//
// La base se siembra DENTRO del cuerpo de cada prueba (§5 del CLAUDE.md).
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/estado_de_parada.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/distribuidor/modo_distribuidor.dart';
import 'package:reparto/distribuidor/paradas_de_la_ruta.dart';
import 'package:reparto/distribuidor/gps/servicio_de_ubicacion.dart';
import 'package:reparto/distribuidor/ruta_guiada.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';

import '../apoyo/base_de_prueba.dart';
import '../pantallas/pedidos/sembrar.dart';
import 'apoyo_distribuidor.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 11, 6, 10, 30);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

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

  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-001',
      creada: ahora,
    );
    await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
      RoutesCompanion(
        startedAt: Value(ahora.subtract(const Duration(minutes: 20))),
      ),
    );
    for (final (i, c) in ['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: c,
        rutaId: 'R1',
        orden: i + 1,
        facturaNumero: 'FA-100${i + 1}',
        endLat: 21.38 + i,
        endLng: -77.91,
      );
    }
  }

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          modoDistribuidorProvider.overrideWithValue(true),
          abrirYCompartirProvider.overrideWithValue(AparatoFalso()),
          servicioDeUbicacionProvider.overrideWithValue(UbicacionFalsa()),
        ],
        child: MaterialApp(
          theme: temaDeReparto(),
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(
            body: SingleChildScrollView(child: RutaGuiada(rutaId: 'R1')),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> toca(WidgetTester tester, String clave) async {
    final f = find.byKey(ValueKey(clave));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await asentar(tester);
  }

  Finder enLaFila(String id, Finder que) =>
      find.descendant(of: find.byKey(claveDeLaFilaDeParada(id)), matching: que);

  testWidgets(
    'la ruta enseña TODAS las paradas, pendientes, y marca la de ahora',
    (tester) async {
      await sembrar();
      await pintar(tester);

      expect(find.text('Paradas de la ruta (3)'), findsOneWidget);
      for (final id in ['p1', 'p2', 'p3']) {
        expect(
          enLaFila(id, find.text('Pendiente')),
          findsOneWidget,
          reason: 'la parada $id sale en la lista con su estado',
        );
      }
      expect(enLaFila('p1', find.text('Ahora')), findsOneWidget);
      expect(enLaFila('p2', find.text('Ahora')), findsNothing);
      await desmontar(tester);
    },
  );

  testWidgets(
    'al marcar, la etiqueta cambia YA (sin subir): no entregada con su motivo, cobrada, sin cobrar',
    (tester) async {
      await sembrar();
      await pintar(tester);

      // 1. No entregada, con motivo: sale el motivo y NINGUN cobro.
      await toca(tester, 'guia-noEntregada');
      await tester.enterText(
        find.byKey(const ValueKey('guia-nota')),
        'cerrado',
      );
      await tester.pump();
      await toca(tester, 'guia-guardar');
      expect(enLaFila('p1', find.text('No entregada')), findsOneWidget);
      expect(enLaFila('p1', find.text('cerrado')), findsOneWidget);
      expect(enLaFila('p1', find.textContaining('cobr')), findsNothing);
      expect(enLaFila('p2', find.text('Ahora')), findsOneWidget);

      // 2. Entregado y cobrado.
      await toca(tester, 'guia-entregado');
      await toca(tester, 'guia-cobrado');
      await toca(tester, 'guia-guardar');
      expect(enLaFila('p2', find.text('Entregada · cobrada')), findsOneWidget);
      expect(enLaFila('p3', find.text('Pendiente')), findsOneWidget);
      expect(enLaFila('p3', find.text('Ahora')), findsOneWidget);

      // Todo esto sin subir: el cobro esta en la tabla del aparato.
      final fila = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p2'))).getSingle();
      expect(
        fila.cobroEntrega,
        isNull,
        reason: 'aun no ha bajado del servidor',
      );
      await desmontar(tester);
    },
  );

  testWidgets('entregada sin marcar el cobro sale «Entregada · sin cobrar»', (
    tester,
  ) async {
    await sembrar();
    await pintar(tester);
    await toca(tester, 'guia-entregado');
    await toca(tester, 'guia-guardar');
    expect(enLaFila('p1', find.text('Entregada · sin cobrar')), findsOneWidget);
    await desmontar(tester);
  });

  test(
    'el cobro que baja del servidor se ve; el marcado aqui manda sobre el',
    () async {
      await sembrar();
      await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
        const OrdersCompanion(
          resultado: Value('entregado'),
          cobroEntrega: Value('cobrado'),
        ),
      );
      final p1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle();
      expect(estadoDeLaParada(p1, const {}), EstadoDeParada.entregadaCobrada);
      expect(
        estadoDeLaParada(p1, const {'p1': false}),
        EstadoDeParada.entregadaSinCobrar,
        reason: 'lo que marco el distribuidor aqui manda hasta que suba',
      );
      expect(
        estadoDeLaParada(p1, const {'otra': true}),
        EstadoDeParada.entregadaCobrada,
      );
    },
  );
}
