// LA SECCIÓN DE FILTROS DEL PLANIFICADOR SE PLIEGA — issue 6 de Amado, punto 3.
//
// Amado: «en rutas, en el desktop, el Planificador de rutas: la sección de filtro
// debe contraerse y expandirse; ahora ocupa todo el área y las rutas aparecen muy
// abajo y casi no se pueden hacer scroll, ni se ven».
//
// QUÉ SE COMPRUEBA, y por qué así. `findsOneWidget` no distingue «las rutas se
// ven» de «las rutas existen debajo del pliegue de la pantalla»: la queja ES que
// existían y no se veían. Por eso lo que se mide es CUÁNTAS tarjetas caben en la
// ventana con la sección plegada y con ella abierta, a un monitor de 800 px de
// alto (un portátil de oficina), que es donde se vio.
//
// Los anchos: 1440 y 1024 (con los dos paneles; 1024 es el primer píxel de
// `Anchos.escritorio`) y 390 (el teléfono, donde la sección sigue ABIERTA al
// entrar —ahí nadie se quejó y la pantalla es la que Jose aprobó—, pero también
// se puede plegar). Cualquier desbordamiento es una excepción de Flutter y hace
// fallar la prueba sola.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/barra_de_filtros.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// Más de las que caben en una ventana de 800 px (cada tarjeta mide ~130) y
/// menos de las 20 de una página de la lista (`ConsultasRutas.porPagina`): que
/// haya que desplazar, pero que todas estén en la primera página. Salen de la más
/// nueva a la más vieja, así que la que se ve primera es la última sembrada.
const _cuantas = 18;

String _codigo(int i) => 'RT-${i.toString().padLeft(3, '0')}';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 14, 9, 0);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Dentro del cuerpo, nunca en el `setUp` (`CLAUDE.md` §5).
  Future<void> pintar(
    WidgetTester tester,
    Size tamano, {
    double barraLateral = 0,
  }) async {
    await sembrarCatalogo(base);
    for (var i = 1; i <= _cuantas; i++) {
      await sembrarRuta(
        base,
        id: 'R$i',
        codigo: _codigo(i),
        creada: DateTime(2026, 9, i),
      );
    }
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);

    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: Scaffold(
            // La barra lateral del armazón, que en la aplicación se lleva 256 px
            // del ancho de la pantalla: la lista mide lo que mide DESPUÉS de ella.
            body: Row(
              children: [
                SizedBox(width: barraLateral),
                const Expanded(child: PantallaRutas()),
              ],
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  /// CUÁNTAS TARJETAS DE RUTA SE VEN ENTERAS en la ventana: las que están
  /// dibujadas Y caen dentro del alto. Una tarjeta que existe pero asoma por
  /// debajo del borde no se ve, que es justo la queja.
  int tarjetasQueSeVen(WidgetTester tester, double alto) {
    var n = 0;
    for (var i = 1; i <= _cuantas; i++) {
      final f = find.text(_codigo(i));
      if (f.evaluate().isEmpty) continue;
      final r = tester.getRect(f.first);
      if (r.top >= 0 && r.bottom <= alto) n++;
    }
    return n;
  }

  final laBarra = find.byType(BarraDeFiltros);
  final elPliegue = find.byKey(TextosDeLosFiltrosDeRutas.clavePlegar);
  final limpiarDelPliegue = find.byKey(
    TextosDeLosFiltrosDeRutas.claveLimpiarPlegado,
  );

  Future<void> pulsarElPliegue(WidgetTester tester) async {
    await tester.tap(elPliegue);
    await asentar(tester);
  }

  // ---------------------------------------------------------------------------
  // CON LOS DOS PANELES: arranca plegada, y las rutas se ven
  // ---------------------------------------------------------------------------
  // (ventana, barra lateral). `1440 con la barra de 256` es el monitor real: la
  // pantalla de Rutas recibe 1184 px y su lista ~395. Los otros dos son la
  // pantalla a secas, como las demás pruebas de esta carpeta: 1440 y 1024 px de
  // ancho para Rutas.
  for (final (ancho, lateral) in const [
    (1440.0, 256.0),
    (1440.0, 0.0),
    (1024.0, 0.0),
  ]) {
    group('a ${ancho.toInt()} px'
        '${lateral > 0 ? ' con la barra lateral' : ''}, con los dos paneles', () {
      final tamano = Size(ancho, 800);

      testWidgets('arranca PLEGADA: los filtros no se comen la lista, y '
          'desplegar / plegar los muestra y los esconde', (tester) async {
        await pintar(tester, tamano, barraLateral: lateral);

        // Plegada: ni rastro de la barra, y el encabezado dice qué es.
        expect(laBarra, findsNothing);
        expect(elPliegue, findsOneWidget);
        expect(find.text('Filtros'), findsOneWidget);
        final conLaSeccionPlegada = tarjetasQueSeVen(tester, tamano.height);

        await pulsarElPliegue(tester);
        expect(laBarra, findsOneWidget);
        final conLaSeccionAbierta = tarjetasQueSeVen(tester, tamano.height);

        expect(
          conLaSeccionPlegada,
          greaterThan(conLaSeccionAbierta),
          reason:
              'PLEGAR NO LE DEVUELVE SITIO A LAS RUTAS. Con la sección abierta '
              'caben $conLaSeccionAbierta tarjetas y plegada $conLaSeccionPlegada: '
              'es la queja de Amado, «las rutas aparecen muy abajo y casi no se '
              'ven». Si son iguales, el pliegue esconde la barra pero deja su '
              'hueco.',
        );
        // Y que sea un cambio de verdad, no de un píxel: al menos una tarjeta
        // más a la vista.
        expect(conLaSeccionPlegada, greaterThanOrEqualTo(3));

        await pulsarElPliegue(tester);
        expect(laBarra, findsNothing, reason: 'volver a pulsar la pliega');
        expect(
          tarjetasQueSeVen(tester, tamano.height),
          conLaSeccionPlegada,
          reason: 'y plegada otra vez deja el mismo sitio que al entrar',
        );

        await desmontar(tester);
      });

      testWidgets('la lista que queda SE DESPLAZA hasta la última ruta', (
        tester,
      ) async {
        await pintar(tester, tamano, barraLateral: lateral);
        // La más vieja es la última de la lista (salen de la nueva a la vieja), y
        // con 18 tarjetas no se ve al entrar.
        final ultima = find.text(_codigo(1));
        expect(ultima, findsNothing);

        // Arrastrando por la lista, que es lo que se quejaba de no poder:
        // «casi no se pueden hacer scroll».
        for (var i = 0; i < 40 && ultima.evaluate().isEmpty; i++) {
          await tester.dragFrom(
            Offset(lateral + (ancho - lateral) / 6, tamano.height - 100),
            const Offset(0, -300),
          );
          await tester.pump();
        }
        expect(ultima, findsOneWidget);

        await desmontar(tester);
      });

      testWidgets('se RECUERDA: cambiar de pestaña no la repliega', (
        tester,
      ) async {
        await pintar(tester, tamano, barraLateral: lateral);
        await pulsarElPliegue(tester);
        expect(laBarra, findsOneWidget);

        await tester.tap(find.textContaining('Historial'));
        await asentar(tester);
        await tester.tap(find.textContaining('Planificadas'));
        await asentar(tester);

        expect(
          laBarra,
          findsOneWidget,
          reason:
              'la sección se desplegó a mano y cambiar de pestaña la volvió a '
              'plegar: cada vez que se mira otra lista hay que reabrirla',
        );

        await desmontar(tester);
      });

      testWidgets('plegada DICE cuántos filtros hay y se pueden quitar sin '
          'desplegar; desplegada no repite el «Limpiar»', (tester) async {
        await pintar(tester, tamano, barraLateral: lateral);

        // Sin filtros puestos no hay «Limpiar» en el encabezado.
        expect(limpiarDelPliegue, findsNothing);

        // Se pone un filtro con la sección abierta, como haría una persona...
        // (la más nueva es la primera de la lista: las dos que se miran caben
        // en la ventana sin desplazar).
        final laNueva = _codigo(_cuantas);
        final laSiguiente = _codigo(_cuantas - 1);
        await pulsarElPliegue(tester);
        await tester.enterText(find.byType(TextField).first, laNueva);
        await tester.pump(const Duration(milliseconds: 450));
        await asentar(tester);
        // ... y con la sección ABIERTA el «Limpiar» es sólo el de la barra.
        expect(limpiarDelPliegue, findsNothing);
        expect(find.widgetWithText(TextButton, 'Limpiar'), findsOneWidget);
        expect(find.text('Filtros · 1 activo'), findsOneWidget);

        // Se pliega: la lista SIGUE filtrada y el encabezado lo dice.
        await pulsarElPliegue(tester);
        expect(laBarra, findsNothing);
        expect(
          find.text('Filtros · 1 activo'),
          findsOneWidget,
          reason:
              'plegar escondió que la lista está acotada: sin esto una ruta '
              'que falta se lee como «no existe»',
        );
        expect(find.text(laNueva), findsOneWidget);
        expect(find.text(laSiguiente), findsNothing);

        // Y se quita desde el encabezado, sin desplegar nada.
        expect(limpiarDelPliegue, findsOneWidget);
        await tester.tap(limpiarDelPliegue);
        await asentar(tester);
        expect(laBarra, findsNothing);
        expect(find.text('Filtros'), findsOneWidget);
        expect(limpiarDelPliegue, findsNothing);
        expect(find.text(laSiguiente), findsOneWidget);

        await desmontar(tester);
      });
    });
  }

  // ---------------------------------------------------------------------------
  // EL TELÉFONO: sigue como estaba, y también se puede plegar
  // ---------------------------------------------------------------------------
  testWidgets('a 390 px arranca DESPLEGADA —como siempre— y se puede plegar '
      'para ganar sitio', (tester) async {
    const tamano = Size(390, 844);
    await pintar(tester, tamano);

    expect(
      laBarra,
      findsOneWidget,
      reason:
          'el teléfono no cambia: ahí no hubo queja y la pantalla es la que se '
          'aprobó. Sólo los dos paneles arrancan plegados',
    );
    expect(find.text('Filtros'), findsOneWidget);
    final abierta = tarjetasQueSeVen(tester, tamano.height);

    await pulsarElPliegue(tester);
    expect(laBarra, findsNothing);
    expect(
      tarjetasQueSeVen(tester, tamano.height),
      greaterThan(abierta),
      reason: 'plegada, el teléfono también enseña más rutas',
    );

    // Nada se sale por el lado.
    expect(tester.getRect(elPliegue).right, lessThanOrEqualTo(390));

    await desmontar(tester);
  });
}
