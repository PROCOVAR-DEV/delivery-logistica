// SE LLEGA AL FINAL DE LA PANTALLA. EN UN TELÉFONO.
//
// Jose, 17/09/2026: «me corta parte de abajo, esto hasta del mapa, no solo de la
// última card, no puedo ver el final».
//
// No es un sitio, es una CLASE de fallo: hay pantallas cuyo último elemento cae
// por debajo del borde y no hay gesto que lo alcance. Y no se había visto nunca
// porque **todas las pruebas de pantalla montan a 1200x1600 o más**, donde cabe
// todo. Aquí se monta a 390x844 —un teléfono de verdad— y con la barra de gestos
// del sistema declarada, que es la otra mitad de lo que tapa.
//
// Las cuatro guardas de este fichero, y cada una vigila un fallo distinto:
//
//  1. **Informes, el pie**: dos desplazamientos verticales, uno dentro del otro.
//     El de dentro se queda con el dedo y el de fuera no llega a moverse nunca,
//     así que el pie del informe («Totales:») no se podía ver.
//  2. **Informes, la caja**: y la causa de lo anterior — una caja de 560 px
//     fijos que se pintaba entera aunque 163 de ellos cayeran por debajo del
//     borde de la pantalla.
//  3. **El cajón de Pedidos sin pie**: su cuerpo terminaba por debajo de la
//     barra de gestos, porque quien apartaba el panel de esa barra era el pie —
//     y el cajón de detalle de un pedido no tiene pie.
//  4. **Cualquier cajón con teclado**: el cajón vive en el `Overlay`, no en el
//     `body` del `Scaffold`, así que nadie le quitaba el alto del teclado y el
//     «Guardar» del pie se quedaba trescientos píxeles por debajo de las teclas.
//
// POR QUÉ LAS COMPROBACIONES SON GEOMÉTRICAS Y NO `findsOneWidget`. Un widget
// fuera de pantalla **existe igual** en el árbol, y en un test ni la barra de
// gestos ni el teclado tapan de verdad: son datos del `MediaQuery`. Lo único que
// distingue «se ve» de «está ahí pero no se alcanza» es DÓNDE cae su rectángulo
// después de arrastrar con el dedo. Por eso cada guarda arrastra primero y mira
// el rectángulo después.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/cajon.dart' as diseno;
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/registro.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart' as pedidos;

import '../../apoyo/base_de_prueba.dart';

/// El teléfono de referencia: 390x844, un píxel por píxel lógico.
const anchoDelTelefono = 390.0;
const altoDelTelefono = 844.0;

/// La barra de gestos de un Android moderno. No es adorno: es lo que convierte
/// «la última fila se ve rara» en «la última fila no se lee».
const barraDeGestos = 34.0;

/// Lo más abajo que se puede pintar algo y que se siga leyendo.
const bordeUtil = altoDelTelefono - barraDeGestos;

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  /// Deja el `tester` en un teléfono, con su barra de gestos declarada.
  void enUnTelefono(WidgetTester tester, {double teclado = 0}) {
    tester.view.physicalSize = const Size(anchoDelTelefono, altoDelTelefono);
    tester.view.devicePixelRatio = 1;
    // Con el teclado fuera, el sistema deja de reportar la barra de gestos en
    // `padding` y la pone en `viewInsets`. Se imita igual aquí para que la
    // prueba mida lo que mide el aparato.
    tester.view.padding = FakeViewPadding(
      bottom: teclado > 0 ? 0 : barraDeGestos,
    );
    tester.view.viewPadding = const FakeViewPadding(bottom: barraDeGestos);
    tester.view.viewInsets = FakeViewPadding(bottom: teclado);
    addTearDown(tester.view.reset);
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  /// Arrastra hacia arriba con el dedo puesto EN MEDIO de [zona], hasta que el
  /// contenido deje de moverse.
  ///
  /// El punto se calcula UNA vez y no se mueve: es lo que hace un dedo de
  /// verdad. Apuntar a un widget del contenido no sirve —en cuanto se desplaza,
  /// el siguiente arrastre empieza fuera de la pantalla y no mueve nada—, y
  /// tirar del `Scrollable` a mano tampoco: eso elige a cuál de los dos se le
  /// da el gesto, que es justo lo que esta prueba tiene que dejar decidir a
  /// Flutter.
  Future<void> bajarConElDedo(WidgetTester tester, Finder zona) async {
    final dedo = tester.getCenter(zona);
    for (var i = 0; i < 20; i++) {
      await tester.dragFrom(dedo, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
  }

  // ---------------------------------------------------------------------------
  // 1. INFORMES
  // ---------------------------------------------------------------------------

  group('Informes en un teléfono', () {
    final ahora = DateTime(2026, 9, 14, 10, 0);
    late BaseLocal base;

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> sembrar(int cuantos) async {
      for (final coleccion in Colecciones.todas) {
        await base
            .into(base.frescura)
            .insert(
              FrescuraCompanion.insert(
                coleccion: coleccion,
                bajadaAt: Value(ahora),
                hasta: Value(ahora.toIso8601String()),
              ),
            );
      }
      for (var i = 0; i < cuantos; i++) {
        await base
            .into(base.orders)
            .insert(
              OrdersCompanion.insert(
                id: 'o$i',
                customerName: 'Cliente $i',
                address: 'Calle $i',
                price: const Value(10),
                createdAt: Value(DateTime(2026, 9, 13)),
              ),
            );
      }
    }

    Future<void> montar(WidgetTester tester) async {
      enUnTelefono(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: RepartoApp(
            enrutador: crearEnrutador(
              pantallas: [registrarInformes()],
              inicial: '/reports',
            ),
          ),
        ),
      );
      // LAS TIPOGRAFÍAS, ANTES DEL PRIMER FOTOGRAMA PINTADO.
      //
      // La misma línea que ya está en `informes/exportar_test.dart` y en
      // `informes/flechas_en_las_pestanas_test.dart`, y por el mismo motivo:
      // `google_fonts` saca los .ttf embebidos por `rootBundle`, que es
      // asíncrono DE VERDAD, y dentro del reloj falso de un `testWidgets` esa
      // carga no avanza nunca. Sin esto el primer fotograma se MIDE con la
      // tipografía de respaldo y se PINTA con la buena, y Flutter lo caza con
      // `'debugSize == size': is not true`.
      //
      // Aquí saltó el 21/09/2026 al meter `Exportar a Excel` en los filtros:
      // una etiqueta más en el primer fotograma y ya bastó. **No es lo que esta
      // prueba vigila** —lo medido con las tipografías puestas es que el pie
      // «Totales:» sí se alcanza— y encima tapaba el rojo de verdad, porque el
      // volcado del árbol revienta al describir el párrafo a medio medir. Las
      // comprobaciones geométricas de abajo no se han tocado.
      //
      // Va aquí y no en el `setUpAll` porque allí no hay `tester`.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets('el pie de «Detalle de Órdenes» se alcanza con el dedo', (
      tester,
    ) async {
      // Veinte filas: lo justo para que la tabla no quepa y haya que bajar.
      await sembrar(20);
      await montar(tester);

      // A la tercera pestaña, que es la larga.
      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Totales:'),
        findsOneWidget,
        reason: 'la pestaña de detalle tiene que estar pintada con su pie',
      );

      // El dedo cae sobre la tabla, que es donde cae de verdad.
      await bajarConElDedo(tester, find.byType(TabBarView));

      final pie = tester.getRect(find.textContaining('Totales:'));
      expect(
        pie.bottom,
        lessThanOrEqualTo(bordeUtil),
        reason:
            'EL FINAL DEL INFORME NO SE VE. Con el dedo sobre la tabla, el pie '
            '«Totales:» se queda en y=${pie.bottom.toStringAsFixed(0)} y la '
            'pantalla útil acaba en $bordeUtil. Es el fallo de los dos '
            'desplazamientos verticales anidados: el de dentro se queda con el '
            'gesto y el de fuera no se mueve nunca, así que lo que cae por '
            'debajo del borde no se alcanza ni bajando. La pantalla tiene que '
            'tener UN solo desplazamiento vertical por delante (hoy, el '
            '`NestedScrollView` que pone de acuerdo la cabecera con la lista '
            'de la pestaña).',
      );
      expect(
        pie.top,
        greaterThanOrEqualTo(0),
        reason: 'y tampoco puede quedarse por encima del borde de arriba',
      );

      await desmontar(tester);
    });

    // LA OTRA MITAD, Y LA CAUSA: la caja de las pestañas no puede medir más que
    // la pantalla. Antes medía 560 px fijos dentro de un `ListView`, así que se
    // pintaba entera aunque 163 de esos píxeles cayeran POR DEBAJO del borde —
    // y lo que se desplaza dentro de una caja así no llega a verse nunca, por
    // mucho que se baje.
    testWidgets('la caja de las pestañas cabe en la pantalla, y su última fila '
        'también', (tester) async {
      await sembrar(20);
      await montar(tester);

      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await tester.pumpAndSettle();

      final caja = tester.getRect(find.byType(TabBarView));
      expect(
        caja.bottom,
        lessThanOrEqualTo(altoDelTelefono),
        reason:
            'LA CAJA DE LAS PESTAÑAS SE SALE DE LA PANTALLA: acaba en '
            'y=${caja.bottom.toStringAsFixed(0)} y la pantalla mide '
            '$altoDelTelefono. Lo que se desplace dentro sólo podrá enseñarse '
            'hasta ese borde de mentira, así que el final de la tabla queda '
            'fuera de alcance. La caja tiene que medir LO QUE HAY de pantalla '
            '(`Expanded`), no un alto fijo.',
      );

      await bajarConElDedo(tester, find.byType(TabBarView));
      final ultima = tester.getRect(find.text('Cliente 19'));
      expect(
        ultima.bottom,
        lessThanOrEqualTo(bordeUtil),
        reason:
            'LA ÚLTIMA FILA SE QUEDA DEBAJO DEL BORDE ÚTIL. Acaba en '
            'y=${ultima.bottom.toStringAsFixed(0)} y el borde está en '
            '$bordeUtil, con el desplazamiento ya al final: no hay forma de '
            'bajar más. O la caja de las pestañas no cabe, o falta quien '
            'aparte la pantalla de la barra de gestos (el `SafeArea` del '
            'armazon, `navegacion/armazon.dart`).',
      );

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. EL CAJÓN DE PEDIDOS, SIN PIE
  // ---------------------------------------------------------------------------

  testWidgets('el cajón de Pedidos sin pie no mete su última línea debajo de '
      'la barra de gestos', (tester) async {
    enUnTelefono(tester);

    // Es el cajón que usa el DETALLE DE UN PEDIDO, que se abre sin pie: ahí el
    // último renglón de productos era el que se perdía.
    await tester.pumpWidget(
      MaterialApp(
        theme: temaDeReparto(),
        home: Scaffold(
          body: pedidos.Cajon(
            titulo: 'Detalle del pedido',
            cuerpo: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 30, child: Text('renglón $i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await bajarConElDedo(tester, find.byType(pedidos.Cajon));

    final ultimo = tester.getRect(find.text('renglón 39'));
    expect(
      ultimo.bottom,
      lessThanOrEqualTo(bordeUtil),
      reason:
          'EL ÚLTIMO RENGLÓN DEL CAJÓN QUEDA DEBAJO DE LA BARRA DE GESTOS. '
          'Acaba en y=${ultimo.bottom.toStringAsFixed(0)} y la pantalla útil '
          'termina en $bordeUtil, con el desplazamiento ya al final: no hay '
          'forma de bajar más. Quien apartaba el panel de esa barra era el '
          'pie, y este cajón —el del detalle de un pedido— no tiene pie, así '
          'que el relleno de abajo del cuerpo tiene que sumar '
          '`MediaQuery.paddingOf(context).bottom`.',
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 3. EL CAJÓN Y EL TECLADO
  // ---------------------------------------------------------------------------

  testWidgets('con el teclado fuera, el «Guardar» del pie del cajón sigue '
      'a la vista y se puede pulsar', (tester) async {
    // 336 px de teclado sobre 844 de pantalla: lo que ocupa el de Android.
    const alturaDelTeclado = 336.0;
    const bordeDelTeclado = altoDelTelefono - alturaDelTeclado;

    enUnTelefono(tester);

    var guardado = false;
    late BuildContext contexto;
    await tester.pumpWidget(
      MaterialApp(
        theme: temaDeReparto(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              contexto = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // Se abre como se abre de verdad: `showGeneralDialog`, o sea en el
    // `Overlay`. Ahí está la gracia — al `body` del `Scaffold` le quitan el alto
    // del teclado, al `Overlay` no.
    unawaited(
      diseno.abrirCajon<void>(
        contexto,
        titulo: 'Nuevo cliente',
        cuerpo: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.all(8),
                child: TextField(
                  decoration: InputDecoration(labelText: 'Un campo'),
                ),
              ),
          ],
        ),
        pie: (_) => FilledButton(
          onPressed: () => guardado = true,
          child: const Text('Guardar'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Alguien toca un campo y sale el teclado.
    tester.view.padding = const FakeViewPadding();
    tester.view.viewInsets = const FakeViewPadding(bottom: alturaDelTeclado);
    await tester.pumpAndSettle();

    final boton = tester.getRect(find.text('Guardar'));
    expect(
      boton.bottom,
      lessThanOrEqualTo(bordeDelTeclado),
      reason:
          'EL «GUARDAR» SE QUEDA DEBAJO DEL TECLADO. Está en '
          'y=${boton.bottom.toStringAsFixed(0)} y el teclado tapa desde '
          'y=$bordeDelTeclado. El cajón se abre con `showGeneralDialog`, así '
          'que vive en el `Overlay` y NADIE le quita el alto del teclado: hay '
          'que apartarlo a mano con `MediaQuery.viewInsetsOf(context).bottom`. '
          'Y no se arregla desplazando, porque el cuerpo tampoco ha encogido.',
    );

    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(guardado, isTrue, reason: 'y con el teclado fuera se puede pulsar');

    await desmontar(tester);
  });
}
