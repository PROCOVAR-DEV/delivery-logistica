// LOS MANDOS DE LA LISTA VAN CON LA LISTA — 28/09/2026.
//
// Jose, mirando `/routes` en un monitor ancho:
//
//     «aqui por q el boton se queda a la mitad el de crear una nueva ruta y el
//      en curso osea el del estado por q se queda tmabien a mitad arregla eso»
//
// Lo que había: el título, el reloj, `+ Nueva Ruta`, las tres pastillas de
// estado y la barra de filtros colgaban de una columna a TODO EL ANCHO, y debajo
// la pantalla se partía en dos paneles —lista a la izquierda (~530 px) y detalle
// a la derecha—. O sea que los cinco mandos de la lista vivían encima de los DOS
// paneles: el botón, empujado al extremo derecho por su `Spacer`, acababa
// flotando en mitad del panel del detalle, a mil píxeles de la lista que crea; y
// las pastillas se quedaban colgando a media fila con el resto del renglón
// vacío. Eso es el «se queda a mitad» de las dos frases.
//
// POR QUÉ ESTAS COMPROBACIONES SON GEOMÉTRICAS. `findsOneWidget` no distingue
// «está donde tiene que estar» de «está en la otra punta de la pantalla»: el
// botón existía igual antes y después. Lo único que separa las dos cosas es
// DÓNDE cae su rectángulo respecto a la raya que parte los dos paneles. Es la
// misma razón que ya está escrita en `test/pantallas/movil/se_llega_al_final_test.dart`.
//
// SE MIDE A CINCO ANCHOS, y cada uno es una decisión distinta del trazado:
//
//   390  — el teléfono de verdad, donde se trabaja. Una columna, y la cabecera
//          es estrecha: el botón baja a su línea y ocupa todo el ancho.
//   700  — una columna todavía, pero la cabecera ya es ancha (`Anchos.idioma`):
//          el botón se va al borde derecho, que ahí ES el borde de la lista.
//   1023 — el último píxel antes de partirse en dos paneles (`Anchos.escritorio`
//          = 1024). Sigue siendo una columna.
//   1600 — dos paneles. Es el caso de Jose, y el que estaba mal.
//   2560 — dos paneles y el de la lista ya pasa de `Anchos.idioma`, así que la
//          cabecera vuelve a ser una fila. Es la rama que desbordaba.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/barra_de_filtros.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

final elBoton = find.widgetWithText(FilledButton, '+ Nueva Ruta');
final laBarraDeFiltros = find.byType(BarraDeFiltros);

/// Las pastillas de estado, una por pestaña: la forma que toma
/// `PestanasQueCaben` cuando hay sitio para las tres.
///
/// Se piden por `FilledButton`/`OutlinedButton`, que es lo que monta cada
/// pastilla —la elegida rellena, las otras dos con borde—, y **no** por
/// `ButtonStyleButton`: las flechas del carrusel son `IconButton`, que en
/// Material 3 también es un `ButtonStyleButton`, así que ese tipo devolvería
/// dos «pastillas» en una pantalla que enseña el carrusel.
final lasPastillas = find.descendant(
  of: find.byType(PestanasQueCaben),
  matching: find.byWidgetPredicate((w) => w is FilledButton || w is OutlinedButton),
);

/// DÓNDE CAE LO QUE DE VERDAD SE PINTA DE LAS PESTAÑAS.
///
/// `PestanasQueCaben` tiene DOS formas y estas pruebas se montan a anchos que
/// dan una y otra: a 390 px el panel es la pantalla entera y sale el carrusel
/// —un rótulo y tres bolitas—; a 1600 y a 2560 el panel pasa del umbral de
/// esta pantalla y salen las tres pastillas.
///
/// Lo que se mide es lo mismo en los dos casos —el rectángulo que ocupan los
/// mandos de estado— y por eso se pregunta por la forma en vez de atar la
/// prueba a una de las dos: lo que se vigila aquí es DÓNDE caen, no cuál sale.
/// Que a 1600 salgan las tres lo dice su propia prueba, más abajo.
///
/// Con las pastillas se junta el rectángulo de las TRES, no el de la primera:
/// van en un `Wrap`, así que la de más a la derecha puede ser cualquiera y en
/// dos renglones la última está abajo. Si alguna se saliera del panel, se sale
/// de esta unión.
Rect dondeCaenLasPestanas(WidgetTester tester) {
  final rotulo = find.byKey(ClavesDePestanas.rotulo);
  if (rotulo.evaluate().isNotEmpty) return tester.getRect(rotulo);

  final cuantas = lasPastillas.evaluate().length;
  expect(
    cuantas,
    greaterThan(0),
    reason:
        'ni rótulo de carrusel ni pastillas: las pestañas de estado no se '
        'están pintando, así que no hay nada que medir',
  );
  var todas = tester.getRect(lasPastillas.first);
  for (var i = 1; i < cuantas; i++) {
    todas = todas.expandToInclude(tester.getRect(lasPastillas.at(i)));
  }
  return todas;
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

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

  /// Dentro del cuerpo, nunca en el `setUp`: allí corre fuera del reloj falso y
  /// lo que Drift deja empezado no avanza dentro (CLAUDE.md §5).
  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: ahora);
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Ana',
      rutaId: 'R1',
      orden: 1,
      endLat: 21.39,
      endLng: -77.92,
    );
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
  }

  Future<void> pintar(WidgetTester tester, Size tamano) async {
    await sembrar();

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
          home: const Scaffold(body: PantallaRutas()),
        ),
      ),
    );
    await asentar(tester);
  }

  // ---------------------------------------------------------------------------
  // 1600: DOS PANELES. El caso de Jose.
  // ---------------------------------------------------------------------------
  group('a 1600 px, con los dos paneles', () {
    /// La raya que parte los dos paneles. Todo lo que manda sobre la lista tiene
    /// que quedar **a su izquierda**.
    double laRaya(WidgetTester tester) =>
        tester.getRect(find.byType(VerticalDivider)).left;

    testWidgets('`+ Nueva Ruta` está DENTRO del panel de la lista, no flotando '
        'sobre el detalle', (tester) async {
      await pintar(tester, const Size(1600, 1400));

      final raya = laRaya(tester);
      final boton = tester.getRect(elBoton);

      expect(
        boton.right,
        lessThanOrEqualTo(raya),
        reason:
            'EL BOTÓN SE QUEDA A MITAD. Estaba en el extremo derecho de la '
            'pantalla, o sea en mitad del panel del detalle, a ~1000 px de la '
            'lista que crea. Jose: «por q el boton se queda a la mitad el de '
            'crear una nueva ruta»',
      );
      expect(
        boton.width,
        greaterThan(400),
        reason:
            'y dentro del panel ocupa su ancho: la cabecera mide ~530 px, o sea '
            'por debajo de `Anchos.idioma`, así que el botón baja a su línea y '
            'se estira — es lo que lo deja pegado a la lista y no colgando de '
            'una esquina',
      );

      await desmontar(tester);
    });

    testWidgets('las pestañas de estado y la barra de filtros, también', (
      tester,
    ) async {
      await pintar(tester, const Size(1600, 1400));

      final raya = laRaya(tester);

      // AQUÍ SALEN LAS TRES PASTILLAS, NO EL CARRUSEL — 28/09/2026.
      //
      // El panel mide ~533 px y las tres etiquetas —`Planificadas (0) · En
      // curso (1) · Historial (0)`— unas 420 juntas: caben. Por eso esta
      // pantalla le pasa a `PestanasQueCaben` un umbral propio
      // (`anchoParaTodas: 460`) en vez del común de 900, que lo comparte con
      // Reportes y el Tablero y que aquí escondería dos de tres detrás de unas
      // bolitas teniendo sitio para verlas.
      //
      // Se comprueba en ESTA prueba y no en otra porque es la única que monta
      // la pantalla al ancho de Jose con los dos paneles: quitar el parámetro
      // devuelve el carrusel justo aquí.
      expect(
        lasPastillas,
        findsNWidgets(3),
        reason:
            'con el panel en ~533 px las tres etiquetas caben: esconder dos '
            'detrás de unas bolitas es quitarle información a quien tiene '
            'sitio para verla',
      );
      expect(
        find.byKey(ClavesDePestanas.rotulo),
        findsNothing,
        reason: 'y por lo mismo no puede salir el rótulo del carrusel',
      );

      expect(
        dondeCaenLasPestanas(tester).right,
        lessThanOrEqualTo(raya),
        reason:
            'Jose: «y el en curso osea el del estado por q se queda tmabien a '
            'mitad». Las pastillas cuentan las rutas de la LISTA: encima del '
            'detalle no cuentan nada',
      );
      expect(
        tester.getRect(laBarraDeFiltros).right,
        lessThanOrEqualTo(raya),
        reason: 'y los filtros filtran la lista, no el detalle',
      );

      await desmontar(tester);
    });

    testWidgets('y el panel del detalle EMPIEZA ARRIBA: encima no lleva nada '
        'que no sea suyo', (tester) async {
      await pintar(tester, const Size(1600, 1400));
      await tester.tap(find.text('RT-001'));
      await asentar(tester);

      expect(
        tester.getRect(find.byType(DetalleDeRuta)).top,
        lessThan(40),
        reason:
            'EL DETALLE ARRANCABA DEBAJO DE LA CABECERA DE LA LISTA: el título, '
            'el reloj, el botón de crear, las pestañas y los filtros le comían '
            '~260 px de alto al mapa y a las paradas, y ninguno de los cinco '
            'habla del detalle',
      );

      await desmontar(tester);
    });

    testWidgets('«Limpiar» sale con los filtros y no en otra parte', (
      tester,
    ) async {
      await pintar(tester, const Size(1600, 1400));

      // Sin filtros puestos no hay botón: un «Limpiar» permanente es un botón
      // que no hace nada la mayor parte del tiempo.
      expect(find.widgetWithText(TextButton, 'Limpiar'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'RT');
      await tester.pump(const Duration(milliseconds: 450));
      await asentar(tester);

      final limpiar = find.widgetWithText(TextButton, 'Limpiar');
      expect(limpiar, findsOneWidget);
      expect(
        find.descendant(of: laBarraDeFiltros, matching: limpiar),
        findsOneWidget,
        reason:
            'estaba suelto DEBAJO de la barra, en un `Align` con margen cero '
            'mientras la barra llevaba el suyo, así que no cuadraba con ningún '
            'filtro. `BarraDeFiltros` tiene un hueco para esto',
      );
      expect(
        tester.getRect(limpiar).right,
        lessThanOrEqualTo(laRaya(tester)),
      );

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 2560: EL PANEL YA ES ANCHO Y LA CABECERA VUELVE A SER UNA FILA
  // ---------------------------------------------------------------------------
  testWidgets('a 2560 px el panel pasa de 640 y la cabecera no desborda', (
    tester,
  ) async {
    // Aquí el panel de la lista mide ~850 px, o sea por encima de
    // `Anchos.idioma`, así que `_CabeceraDeLaLista` monta su FILA. Esa rama es
    // la que desbordaba: el reloj de datos es un `Row(mainAxisSize: min)` sin
    // ningún hijo flexible dentro, no sabe encoger, y con un `Spacer` robándole
    // la mitad del hueco se salía por el lado con la cebra amarilla y negra
    // encima. Medido a 700 px: le tocaban 219,4 y pedía 260,4.
    //
    // **Estas pruebas no llevan `expect` de desbordamiento y no les hace
    // falta**: un `RenderFlex overflowed` es una excepción, y `testWidgets`
    // falla sola con ella. Lo que hacía falta era montar esta pantalla a un
    // ancho donde esa rama se use — que es justo lo que no había, y por eso el
    // fallo llevaba ahí desde siempre sin que nadie lo viera.
    //
    // Medido al mutarlo de vuelta a `Flexible` + `Spacer`: quien lo caza son
    // **las de 700 y 1023 px**, con `A RenderFlex overflowed by 41 pixels`.
    // Aquí, con el panel en ~850, la mitad que le tocaba al reloj eran 294 y le
    // bastaban, así que esta prueba sola habría dejado pasar el fallo. Se queda
    // porque es la única que monta la rama de la FILA **dentro del panel**, que
    // es la combinación nueva.
    await pintar(tester, const Size(2560, 1400));

    final raya = tester.getRect(find.byType(VerticalDivider)).left;
    final boton = tester.getRect(elBoton);
    expect(boton.right, lessThanOrEqualTo(raya));
    expect(
      dondeCaenLasPestanas(tester).right,
      lessThanOrEqualTo(raya),
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 390: EL TELÉFONO. Donde se trabaja de verdad.
  // ---------------------------------------------------------------------------
  group('a 390 px', () {
    testWidgets('sigue igual: una columna, los mandos encima de la lista y el '
        'botón a todo el ancho', (tester) async {
      await pintar(tester, const Size(390, 844));

      // Una sola columna: nada de paneles.
      expect(find.byType(VerticalDivider), findsNothing);

      final boton = tester.getRect(elBoton);
      expect(
        boton.width,
        greaterThan(340),
        reason:
            'Jose, 25/09/2026: «en movil en una esquina y no todo el tamaño que '
            'lleva, le falta width». Con `Aire.lg` a cada lado le tocan 358 de '
            'los 390',
      );

      // EL ORDEN: cabecera, pestañas, filtros y luego la lista. Es lo que hace
      // que este mismo árbol valga para las dos formas de la pantalla.
      final pestanas = dondeCaenLasPestanas(tester);
      final filtros = tester.getRect(laBarraDeFiltros);
      final primeraTarjeta = tester.getRect(find.text('RT-001'));
      expect(boton.bottom, lessThanOrEqualTo(pestanas.top));
      expect(pestanas.bottom, lessThanOrEqualTo(filtros.top));
      expect(filtros.bottom, lessThanOrEqualTo(primeraTarjeta.top));

      // Y nada se sale por el lado: un mando recortado contra el borde es un
      // mando que no se puede tocar.
      expect(filtros.right, lessThanOrEqualTo(390));
      expect(boton.right, lessThanOrEqualTo(390));

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 700 y 1023: UNA COLUMNA TODAVÍA, y el botón al borde de la lista
  // ---------------------------------------------------------------------------
  for (final ancho in [700.0, 1023.0]) {
    testWidgets('a ${ancho.toInt()} px sigue habiendo una sola columna y el '
        'botón acaba en su borde derecho', (tester) async {
      // 1023 es el último píxel antes de `Anchos.escritorio`. Se prueba a
      // propósito: si el corte se moviera un píxel, aquí aparecerían dos
      // paneles en una ventana donde la lista se queda en 340 px.
      await pintar(tester, Size(ancho, 1200));

      expect(
        find.byType(VerticalDivider),
        findsNothing,
        reason: 'por debajo de 1024 no hay sitio para dos columnas',
      );

      final boton = tester.getRect(elBoton);
      expect(
        boton.right,
        greaterThan(ancho - 40),
        reason:
            'con una sola columna el borde derecho de la pantalla ES el de la '
            'lista, así que ahí el botón sí va al extremo: es donde se busca la '
            'acción',
      );
      expect(boton.right, lessThanOrEqualTo(ancho));

      await desmontar(tester);
    });
  }
}
