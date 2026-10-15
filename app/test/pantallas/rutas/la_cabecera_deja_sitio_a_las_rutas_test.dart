// LA CABECERA DEJA SITIO A LAS RUTAS — issue 13 de Amado (punto 2), 15/10/2026.
//
// Amado: «la interfaz de Rutas en el desktop es muy grande: los botones se llevan
// casi la mitad de la pantalla, además del filtro que ya expandes y contraes;
// si se expande desaparecen por completo [las rutas]».
//
// QUÉ SE MIDE, y por qué así. `findsOneWidget` no distingue «la tarjeta se ve»
// de «la tarjeta existe debajo del borde»: la queja ES que existían y no se
// veían. Se mide en píxeles —lo que se llevan los mandos— y en TARJETAS ENTERAS
// dentro de la ventana, con las tipografías y el tema de verdad (con la `Ahem`
// de las pruebas cada letra es un cuadrado y las pastillas parten de renglón
// donde la aplicación no lo hace). La pantalla se monta con lo que le quita el
// armazón: la barra superior (64 px) y, en escritorio, la lateral (256).
//
// Antes → después (cabecera = de arriba de la pantalla al principio de la
// lista; tarjetas = enteras a la vista; cada tarjeta mide ~195 px):
//
//   tamaño        plegada              desplegada
//   1366x768      265 → 176 px  2 → 2  446 → 352 px  1 → 1
//   1920x1080     209 → 120 px  4 → 4  397 → 308 px  3 → 3
//   1366x600      265 → 176 px  1 → 1  446 → 296 px  0 → 1   (ese portátil, en el navegador)
//   390x844       225 → 225 px  2 → 2  402 → 402 px  1 → 1   (el teléfono, sin cambios)
//
// 1366x600 es lo que de verdad le queda a la página en un portátil de 1366x768
// con la barra de tareas y la del navegador: ahí estaba el «desaparecen por
// completo». A 768 de ventana entera la tarjeta que se gana es la mitad de una
// (89 px): la lista pasa de 439 a 528 px plegada.
//
// LOS NÚMEROS DEL TOPE (a), de dónde salen. En escritorio la cabecera es aire 8 +
// el renglón de título y `+ Nueva Ruta` (48) + 8 + las pastillas con `Filtros`
// (48 si caben en un renglón, 104 si van en dos) + 8. En una columna de ~370 px
// (1366) las tres pastillas no caben juntas —miden ~370 con sus cuentas— y van
// en dos renglones: 176. En la de ~555 (1920) va todo en uno: 120. El teléfono
// no cambia (225, como estaba).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/barra_de_filtros.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../capturas/capturas_rutas.dart' show cargarTipografias;
import '../pedidos/sembrar.dart';
import 'desplegar_los_filtros.dart';

const _cuantas = 18;
const _enCurso = 'RT-EN-CURSO';

String _codigo(int i) => 'RT-${i.toString().padLeft(3, '0')}';

/// La barra superior del armazón (`Anchos.altoBarraSuperior`).
const _barraSuperior = 64.0;

typedef _Tamano = ({
  double ancho,
  double alto,
  double lateral,
  double topeDeLaCabecera,
});

const List<_Tamano> _tamanos = [
  (ancho: 1366, alto: 768, lateral: 256, topeDeLaCabecera: 176),
  (ancho: 1920, alto: 1080, lateral: 256, topeDeLaCabecera: 120),
  (ancho: 1366, alto: 600, lateral: 256, topeDeLaCabecera: 176),
  (ancho: 390, alto: 844, lateral: 0, topeDeLaCabecera: 225),
];

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 15, 9, 0);

  setUpAll(cargarTipografias);
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
  Future<void> pintar(WidgetTester tester, _Tamano t) async {
    await sembrarCatalogo(base);
    for (var i = 1; i <= _cuantas; i++) {
      await sembrarRuta(
        base,
        id: 'R$i',
        codigo: _codigo(i),
        creada: DateTime(2026, 9, i),
      );
    }
    await sembrarRuta(
      base,
      id: 'RC',
      codigo: _enCurso,
      estado: EstadoRuta.enCurso,
      vehiculoId: null,
    );
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);

    tester.view.physicalSize = Size(t.ancho, t.alto);
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
          theme: temaDeReparto(),
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: _barraSuperior),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(width: t.lateral),
                      const Expanded(child: PantallaRutas()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Rect laPantalla(WidgetTester tester) =>
      tester.getRect(find.byType(PantallaRutas));
  Rect laLista(WidgetTester tester) =>
      tester.getRect(find.byType(CuerpoDeslizable));
  final laBarra = find.byType(BarraDeFiltros);

  /// LAS TARJETAS QUE SE VEN ENTERAS: su `Card` entera entre el principio de la
  /// lista y el borde de abajo de la ventana.
  int tarjetasEnteras(WidgetTester tester) {
    final lista = laLista(tester);
    var n = 0;
    for (var i = 1; i <= _cuantas; i++) {
      final codigo = find.text(_codigo(i));
      if (codigo.evaluate().isEmpty) continue;
      final tarjeta = tester.getRect(
        find.ancestor(of: codigo, matching: find.byType(Card)).first,
      );
      if (tarjeta.top >= lista.top && tarjeta.bottom <= lista.bottom) n++;
    }
    return n;
  }

  Future<void> plegar(WidgetTester tester) async {
    if (laBarra.evaluate().isEmpty) return;
    await tester.tap(find.byKey(TextosDeLosFiltrosDeRutas.clavePlegar));
    await asentar(tester);
  }

  for (final t in _tamanos) {
    final nombre = '${t.ancho.toInt()}x${t.alto.toInt()}';

    group('a $nombre', () {
      testWidgets('(a) PLEGADA, los mandos miden ≤ ${t.topeDeLaCabecera.toInt()} '
          'px y la lista se queda con el resto', (tester) async {
        await pintar(tester, t);
        await plegar(tester);
        expect(laBarra, findsNothing);

        final cabecera = laLista(tester).top - laPantalla(tester).top;
        expect(
          cabecera,
          lessThanOrEqualTo(t.topeDeLaCabecera),
          reason:
              'LOS MANDOS SE COMEN LA LISTA OTRA VEZ: miden $cabecera px. Amado: '
              '«los botones se llevan casi la mitad de la pantalla». Antes eran '
              '265 a 1366x768 (título, `+ Nueva Ruta` a todo lo ancho, las '
              'pastillas y `Filtros`, cada uno en su renglón)',
        );
        expect(tarjetasEnteras(tester), greaterThanOrEqualTo(1));
        expect(tester.takeException(), isNull);

        await desmontar(tester);
      });

      testWidgets(
        '(b) DESPLEGADA y en su alto mayor (con un filtro puesto sale '
        'también su «Limpiar»), la barra no echa la lista: se ve al menos una '
        'tarjeta entera y la lista conserva 2/3 del sitio',
        (tester) async {
          await pintar(tester, t);
          await desplegarLosFiltros(tester);
          // Un filtro que deja pasar a todas: la barra crece con su «Limpiar» y
          // la lista sigue teniendo las 18.
          await tester.enterText(find.byType(TextField).first, 'RT-');
          await tester.pump(const Duration(milliseconds: 450));
          await asentar(tester);
          expect(laBarra, findsOneWidget);
          expect(
            find.descendant(
              of: laBarra,
              matching: find.widgetWithText(TextButton, 'Limpiar'),
            ),
            findsOneWidget,
          );

          expect(
            tarjetasEnteras(tester),
            greaterThanOrEqualTo(1),
            reason:
                'con los filtros abiertos no se ve ni una ruta entera: es '
                'literalmente la queja (antes, a 1366x600, ninguna)',
          );
          // El sitio que hay debajo de los mandos: desde donde empieza la barra
          // hasta el borde de abajo. La lista se queda, como poco, dos tercios.
          // A 1920x1080 la barra cabe en su tercio y esto se cumple también con
          // ella en el flujo: ahí las dos formas son la misma.
          final bajoLosMandos =
              laPantalla(tester).bottom - tester.getRect(laBarra).top;
          final lista = laLista(tester).height;
          expect(
            lista,
            greaterThanOrEqualTo(bajoLosMandos * 2 / 3 - 0.5),
            reason:
                'LA BARRA DESPLEGADA EMPUJA LA LISTA: le deja $lista de '
                '$bajoLosMandos px. Amado: «si se expande desaparecen por '
                'completo». La barra no puede pasar de un tercio y se desplaza '
                'ella sola',
          );
          expect(tester.takeException(), isNull);

          await desmontar(tester);
        },
      );

      testWidgets(
        'los estados siguen filtrando y «+ Nueva Ruta» sigue abriendo '
        'el asistente',
        (tester) async {
          await pintar(tester, t);
          expect(find.text(_codigo(_cuantas)), findsOneWidget);
          expect(find.text(_enCurso), findsNothing);

          // En escritorio, la pastilla; en el teléfono, la flecha del carrusel.
          final enCurso = find.textContaining('En curso (1)');
          if (find.byKey(ClavesDePestanas.adelante).evaluate().isNotEmpty) {
            await tester.tap(find.byKey(ClavesDePestanas.adelante));
          } else {
            await tester.tap(enCurso);
          }
          await asentar(tester);
          expect(find.text(_enCurso), findsOneWidget);
          expect(find.text(_codigo(_cuantas)), findsNothing);

          await tester.tap(find.widgetWithText(FilledButton, '+ Nueva Ruta'));
          await asentar(tester);
          expect(find.byType(AsistenteNuevaRuta), findsOneWidget);
          expect(tester.takeException(), isNull);

          await desmontar(tester);
        },
      );
    });
  }
}
