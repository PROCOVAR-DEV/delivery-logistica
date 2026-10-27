// LOS CONDUCES EN PANTALLA (`docs/conduces.md`, 27/10/2026), a 390 px (teléfono, tarjetas) y a 1440 px
// (escritorio, tabla).
//
// Forma del §3-ter de CLAUDE.md: se monta con la base VACÍA y se siembra DESPUÉS, dentro del cuerpo y
// sin volver a montar. Lo que se mira es lo que lee quien está delante:
//
//  * la fila de la principal dice «Conduce 47313 + 47314» y el miembro NO sale como fila;
//  * con dos facturas marcadas aparece «Crear conduce» en la franja; el cajón dice «La principal será
//    47313 (Cliente). Las demás irán con ella» y la crea;
//  * con clientes distintos el cajón lo DICE y el botón está apagado;
//  * la pestaña «Conduces» lleva el texto literal, los conduces con «Deshacer conduce» y «Sacar»;
//  * «Deshacer conduce» también en la ficha de la principal.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/conduces.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 27, 9);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<ProviderContainer> pintar(WidgetTester tester, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(PantallaPedidos)),
    );
  }

  /// La bajada que llega DESPUÉS de montar: a, b (miembro de a, si [hecho]), c del mismo cliente y d de otro.
  Future<void> llegaLaBajada(WidgetTester tester, {bool hecho = false}) async {
    await sembrarCatalogo(base);
    for (final (id, numero, cliente, peso) in [
      ('a', '47313', 'Bodega La Rica', 100.0),
      ('b', '47314', 'Bodega La Rica', 50.0),
      ('c', '47315', 'Bodega La Rica', 25.0),
      ('d', '47400', 'Otro Cliente', 10.0),
    ]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: cliente,
        facturaNumero: numero,
        peso: peso,
        endLat: 21.38,
        endLng: -77.91,
        conducePrincipalId: hecho && id == 'b' ? 'a' : null,
      );
    }
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
    await asentar(tester);
  }

  /// Una prueba de widget que DESMONTA al final: los `watch` de Drift dejan un temporizador al cancelarse
  /// y, sin pasar el reloj, el marco de pruebas lo da por colgado.
  void prueba(String nombre, Future<void> Function(WidgetTester) cuerpo) =>
      testWidgets(nombre, (tester) async {
        await cuerpo(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
      });

  Future<Pedido> fila(String id) =>
      (base.select(base.orders)..where((o) => o.id.equals(id))).getSingle();

  final confirmar = find.byKey(const ValueKey('crear-conduce-confirmar'));
  bool encendido(Finder f) => botonDe(f).onPressed != null;

  for (final (nombre, tamano) in [
    ('390 px (tarjetas)', const Size(390, 1800)),
    ('1440 px (tabla)', const Size(1440, 1400)),
  ]) {
    group(nombre, () {
      prueba('la principal dice «Conduce 47313 + 47314» y el miembro no es una fila', (
        tester,
      ) async {
        await pintar(tester, tamano);
        await llegaLaBajada(tester, hecho: true);

        expect(
          find.text('Conduce 47313 + 47314'),
          findsOneWidget,
          reason: 'la principal enseña los números unidos, la principal primero',
        );
        expect(find.text('Conduce 47313 + 47314'), findsOneWidget);
        // El miembro no sale con su propio número en ninguna fila.
        expect(find.textContaining('47314'), findsOneWidget);
        expect(find.textContaining('47315'), findsWidgets);
        expect(find.textContaining('150'), findsWidgets, reason: 'el peso es el de todo el conduce');
      });

      prueba('marcar dos: «Crear conduce» en la franja, el cajón dice quién es la principal y la crea', (
        tester,
      ) async {
        final contenedor = await pintar(tester, tamano);
        await llegaLaBajada(tester);

        final marcas = contenedor.read(seleccionPedidosProvider.notifier);
        marcas.alternar('a');
        await asentar(tester);
        expect(find.text(TextosDeConduces.crear), findsNothing, reason: 'con una sola no hay conduce');
        marcas.alternar('c');
        await asentar(tester);

        await tester.tap(find.byKey(const ValueKey('barra-crear-conduce')));
        await asentar(tester);

        expect(
          find.text('La principal será 47313 (Bodega La Rica). Las demás irán con ella'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('crear-conduce-motivo')), findsNothing);
        expect(encendido(confirmar), isTrue);

        await tester.tap(confirmar);
        await asentar(tester);

        expect((await fila('c')).conducePrincipalId, 'a');
        expect((await fila('a')).conducePrincipalId, isNull);
        expect(
          contenedor.read(seleccionPedidosProvider),
          isEmpty,
          reason: 'las que se juntaron dejan de estar marcadas',
        );
        expect(find.text('Conduce 47313 + 47315'), findsOneWidget);
      });

      prueba('el ORDEN de marcado manda: la primera marcada es la principal aunque sea la segunda de la lista', (
        tester,
      ) async {
        final contenedor = await pintar(tester, tamano);
        await llegaLaBajada(tester);
        final marcas = contenedor.read(seleccionPedidosProvider.notifier);
        marcas.alternar('c');
        marcas.alternar('a');
        await asentar(tester);

        await tester.tap(find.byKey(const ValueKey('barra-crear-conduce')));
        await asentar(tester);

        expect(
          find.text('La principal será 47315 (Bodega La Rica). Las demás irán con ella'),
          findsOneWidget,
        );
        await tester.tap(confirmar);
        await asentar(tester);
        expect((await fila('a')).conducePrincipalId, 'c');
      });

      prueba('con clientes distintos el cajón lo DICE y el botón está apagado', (
        tester,
      ) async {
        final contenedor = await pintar(tester, tamano);
        await llegaLaBajada(tester);
        final marcas = contenedor.read(seleccionPedidosProvider.notifier);
        marcas.alternar('a');
        marcas.alternar('d');
        await asentar(tester);

        await tester.tap(find.byKey(const ValueKey('barra-crear-conduce')));
        await asentar(tester);

        expect(find.text(
            'La factura 47400 es de otro cliente (Bodega La Rica): un conduce junta '
            'facturas de un solo cliente',
          ), findsOneWidget);
        expect(encendido(confirmar), isFalse, reason: 'no deja crear');
        expect(find.textContaining('La principal será'), findsNothing);
        expect((await fila('d')).conducePrincipalId, isNull);
      });

      prueba('la pestaña «Conduces»: el texto literal, el conduce, «Sacar» y «Deshacer conduce»', (
        tester,
      ) async {
        await pintar(tester, tamano);
        await llegaLaBajada(tester, hecho: true);

        // En el teléfono las pestañas son un carrusel (se pasa con la flecha); en el escritorio, dos botones.
        if (tamano.width < 900) {
          await tester.tap(find.byKey(ClavesDePestanas.adelante));
        } else {
          await tester.tap(find.text(TextosDeConduces.pestana));
        }
        await asentar(tester);

        expect(
          find.text(
            'Un conduce es lo que sale con el camión y puede juntar varias facturas; '
            'la primera que marques es la que lo crea y dice a qué cliente va dedicado.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('conduce-etiqueta-a')), findsOneWidget);
        expect(find.text('Conduce 47313 + 47314'), findsOneWidget);
        expect(find.text('Bodega La Rica'), findsOneWidget);
        expect(find.byKey(const ValueKey('sacar-b')), findsOneWidget);
        // Sin dos marcadas el botón de crear está apagado y dice por qué.
        expect(find.byKey(const ValueKey('conduces-crear-motivo')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('sacar-b')));
        await asentar(tester);
        expect((await fila('b')).conducePrincipalId, isNull);
        expect(find.byKey(const ValueKey('conduce-etiqueta-a')), findsNothing);
      });

      prueba('«Deshacer conduce»: suelta a los miembros; con la principal en ruta está apagado y lo dice', (
        tester,
      ) async {
        await pintar(tester, tamano);
        await llegaLaBajada(tester, hecho: true);
        if (tamano.width < 900) {
          await tester.tap(find.byKey(ClavesDePestanas.adelante));
        } else {
          await tester.tap(find.text(TextosDeConduces.pestana));
        }
        await asentar(tester);

        // La principal entra en una ruta: ya no se puede deshacer.
        await sembrarRuta(base, id: 'R1');
        await (base.update(base.orders)..where((o) => o.id.equals('a'))).write(
          const OrdersCompanion(routeId: Value('R1')),
        );
        await asentar(tester);
        final deshacer = find.byKey(const ValueKey('deshacer-a'));
        expect(deshacer, findsOneWidget);
        expect(botonDe(deshacer).onPressed, isNull);
        expect(find.text('La factura 47313 ya va en la ruta RT-R1'), findsOneWidget);

        // Fuera de la ruta, se deshace.
        await (base.update(base.orders)..where((o) => o.id.equals('a'))).write(
          const OrdersCompanion(routeId: Value(null)),
        );
        await asentar(tester);
        await tester.tap(deshacer);
        await asentar(tester);
        expect((await fila('b')).conducePrincipalId, isNull);
      });

      prueba('la ficha de la principal deja «Deshacer conduce»', (tester) async {
        await pintar(tester, tamano);
        await llegaLaBajada(tester, hecho: true);
        // Se abre como se abre de verdad: tocando la fila de la principal.
        await tester.tap(find.text('Conduce 47313 + 47314'));
        await asentar(tester);

        // En el teléfono la ficha es larga y la sección queda más abajo: se baja hasta ella.
        final seccion = find.byKey(const ValueKey('ficha-conduce'));
        expect(seccion, findsOneWidget);
        final deshacer = find.byKey(const ValueKey('deshacer-a'));
        await tester.ensureVisible(deshacer);
        await asentar(tester);
        await tester.tap(deshacer);
        await asentar(tester);
        expect((await fila('b')).conducePrincipalId, isNull);
      });
    });
  }
}

/// El botón de abajo del `Finder`: los de la casa son `FilledButton`/`OutlinedButton` con icono.
ButtonStyleButton botonDe(Finder f) => find
    .descendant(of: f, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
    .evaluate()
    .map((e) => e.widget as ButtonStyleButton)
    .followedBy(
      f.evaluate().map((e) => e.widget).whereType<ButtonStyleButton>(),
    )
    .first;
