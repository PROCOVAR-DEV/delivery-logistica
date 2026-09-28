// FILTRAR LAS RUTAS POR LA UBICACIÓN DE LA QUE SALIERON — 28/09/2026.
//
// Jose, mirando `/routes`:
//
//     «en las rutas añadir tambien el filtro por la ubicacion q salio para
//      saber de donde saiioo sin necesidad de estar viendo todas juntas»
//
// El dato ya estaba en la tarjeta —el renglón del alfiler, `PV-STGO`— y no había
// forma de acotar por él: se veían las de todos los almacenes juntas.
//
// LO QUE ESTAS PRUEBAS ATAN, y cada una tapa un agujero distinto:
//
//  1. **Que agrupe y cuente bien** lo que hay, sin perder ninguna ruta y con un
//     orden que no dependa de en qué orden vinieran.
//  2. **Que el filtro filtre de verdad**, incluidas las rutas SIN punto de
//     partida — que son las que más importan (una ruta sin origen no se puede
//     medir) y que sin su propia opción sólo se verían en «cualquiera»: eso es
//     descartar trabajo en silencio, §4 del CLAUDE.md.
//  3. **Que las opciones lleguen cuando llega la bajada** (§3-ter): monta con la
//     base VACÍA y siembra DESPUÉS, sin volver a montar. Con un `Future` este
//     desplegable se queda vacío para siempre en la web, que nace con la base
//     vacía en cada carga — el mismo fallo que ya se pagó en los desplegables de
//     Pedidos y en los del paso 4 del asistente.
//  4. **Que la opción «cualquiera» sea la PRIMERA**, que es la regla de todos
//     los desplegables de la casa.
//  5. **Que el filtro se vea también con un solo origen**, y no desaparezca en
//     silencio.
//
// Nada de red: `filtrarRutas` es del cliente y lee de Drift, que es la regla que
// sostiene el día sin conexión.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/barra_de_filtros.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// Una ruta a mano con su origen. `Ruta` es una `DataClass` de Drift y su
/// constructor sólo exige lo imprescindible, así que para las pruebas de
/// `ubicacionesDeSalidaDe` y `filtrarRutas` —que no tocan la base— no hace falta
/// ninguna.
Ruta rutaCon({required String id, String? origen}) => Ruta(
  id: id,
  status: EstadoRuta.planificada,
  originAddress: origen,
  totalDistance: 0,
  totalWeight: 0,
  totalPrice: 0,
  optimized: false,
  createdAt: DateTime(2026, 9, 14),
);

/// Siembra una ruta CON su origen. `sembrarRuta` del común no lo acepta —y no se
/// le añade desde aquí: ese fichero es de Pedidos y lo están escribiendo otros—,
/// así que aquí se escribe la fila entera.
Future<void> sembrarRutaConOrigen(
  BaseLocal base, {
  required String id,
  required String codigo,
  String? origen,
  String sucursal = 'B1',
  DateTime? creada,
}) => base.into(base.routes).insert(
  RoutesCompanion.insert(
    id: id,
    routeCode: Value(codigo),
    status: const Value(EstadoRuta.planificada),
    originAddress: Value(origen),
    vehicleId: const Value('V1'),
    branchId: Value(sucursal),
    createdAt: Value(creada ?? DateTime(2026, 9, 14)),
  ),
);

void main() {
  // ---------------------------------------------------------------------------
  // 1. LO QUE HAY: agrupar, contar y ordenar
  // ---------------------------------------------------------------------------
  group('las ubicaciones que hay', () {
    test('agrupa, cuenta y ordena sin distinguir mayúsculas', () {
      final ubicaciones = ubicacionesDeSalidaDe([
        rutaCon(id: '1', origen: 'PV-STGO'),
        rutaCon(id: '2', origen: 'aurora'),
        rutaCon(id: '3', origen: 'PV-STGO'),
        rutaCon(id: '4', origen: 'Zona Franca'),
      ]);

      expect(
        [for (final u in ubicaciones) u.clave],
        ['aurora', 'PV-STGO', 'Zona Franca'],
        reason:
            'ALFABÉTICO Y SIN MIRAR LA CAJA. Ordenando con el `compareTo` de '
            'Dart a secas, `PV-STGO` iría antes que `aurora` porque las '
            'mayúsculas van primero en el orden de los caracteres, y una lista '
            'de sitios que empieza por las que van en mayúsculas no se lee',
      );
      expect([for (final u in ubicaciones) u.rutas], [1, 2, 1]);
    });

    test('recorta los espacios de los dos lados y no parte la misma en dos', () {
      final ubicaciones = ubicacionesDeSalidaDe([
        rutaCon(id: '1', origen: 'PV-STGO'),
        rutaCon(id: '2', origen: '  PV-STGO  '),
      ]);

      expect(
        ubicaciones.length,
        1,
        reason:
            'DOS OPCIONES IDÉNTICAS EN EL DESPLEGABLE, una con un espacio '
            'invisible detrás: se elige una, salen la mitad de las rutas, y no '
            'hay nada en pantalla que explique por qué',
      );
      expect(ubicaciones.single.rutas, 2);
    });

    test('las que no tienen origen van juntas, al final, y sólo si hay', () {
      final conAlguna = ubicacionesDeSalidaDe([
        rutaCon(id: '1', origen: 'PV-STGO'),
        rutaCon(id: '2'),
        // Vacío y en blanco cuentan como «sin origen»: una cadena de espacios
        // no es un sitio, y como opción propia saldría en blanco.
        rutaCon(id: '3', origen: '   '),
      ]);

      expect(conAlguna.last.esSinPuntoDePartida, isTrue);
      expect(conAlguna.last.rutas, 2);
      expect(conAlguna.last.etiqueta, 'Sin punto de partida');

      final todasConOrigen = ubicacionesDeSalidaDe([
        rutaCon(id: '1', origen: 'PV-STGO'),
      ]);
      expect(
        [for (final u in todasConOrigen) u.esSinPuntoDePartida],
        [false],
        reason:
            'sin ninguna así, esa opción no se ofrece: un filtro que no puede '
            'devolver nada es una forma de decir que la pantalla está vacía',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 2. QUE FILTRE
  // ---------------------------------------------------------------------------
  group('filtrar por la ubicación', () {
    final rutas = [
      rutaCon(id: 'A', origen: 'PV-STGO'),
      rutaCon(id: 'B', origen: 'AURORA'),
      rutaCon(id: 'C'),
    ];

    List<String> conFiltro(String ubicacion) => [
      for (final r in filtrarRutas(
        rutas,
        FiltrosRutas(ubicacionSalida: ubicacion),
        vehiculos: const {},
        sucursales: const {},
      ))
        r.id,
    ];

    test('deja sólo las que salieron de ahí', () {
      expect(conFiltro('PV-STGO'), ['A']);
      expect(conFiltro('AURORA'), ['B']);
    });

    test('vacío es «cualquiera» y no quita nada', () {
      expect(conFiltro(''), ['A', 'B', 'C']);
    });

    test('«sin punto de partida» trae exactamente las que no lo tienen', () {
      expect(
        conFiltro(FiltrosRutas.sinPuntoDePartida),
        ['C'],
        reason:
            'ES LA OPCIÓN QUE MÁS IMPORTA: una ruta sin origen no se puede '
            'medir, y sin poder pedirlas no hay forma de encontrarlas entre '
            'trescientas',
      );
    });

    test('y `hayAlguno` la cuenta, que es lo que enciende «Limpiar»', () {
      expect(const FiltrosRutas().hayAlguno, isFalse);
      expect(
        const FiltrosRutas(ubicacionSalida: 'PV-STGO').hayAlguno,
        isTrue,
        reason:
            'sin esto el filtro se queda puesto y no hay botón para quitarlo: '
            'media lista escondida y nada en pantalla que lo diga',
      );
    });

    test('`copiarCon` no se lleva por delante los otros filtros', () {
      // El fallo de familia que este `copiarCon` viene a evitar: cada control
      // rehacía el objeto entero a mano, y con cinco filtros basta olvidarse de
      // uno para que elegir una fecha borre la ubicación sin que salte nada.
      final antes = FiltrosRutas(
        q: 'RT',
        vehiculoId: 'V1',
        ubicacionSalida: 'PV-STGO',
        desde: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 30),
      );
      final despues = antes.copiarCon(q: 'OTRA');

      expect(despues.vehiculoId, 'V1');
      expect(despues.ubicacionSalida, 'PV-STGO');
      expect(despues.desde, DateTime(2026, 9, 1));
      expect(despues.hasta, DateTime(2026, 9, 30));

      // Y la ✕ del rango sí puede borrar las fechas, que sin los `limpiar…`
      // sería imposible: `null` es indistinguible de «no lo toques».
      final sinFechas = antes.copiarCon(
        limpiarDesde: true,
        limpiarHasta: true,
      );
      expect(sinFechas.desde, isNull);
      expect(sinFechas.hasta, isNull);
      expect(sinFechas.ubicacionSalida, 'PV-STGO');
    });
  });

  // ---------------------------------------------------------------------------
  // 3, 4 y 5. LA PANTALLA
  // ---------------------------------------------------------------------------
  group('en la pantalla', () {
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

    /// Se siembra **dentro del cuerpo de la prueba**, nunca en el `setUp`: allí
    /// corre fuera del reloj falso y lo que Drift deja empezado no avanza
    /// dentro — la prueba se cuelga en vez de fallar (CLAUDE.md §5).
    Future<void> sembrarTres() async {
      await sembrarCatalogo(base);
      await sembrarRutaConOrigen(
        base,
        id: 'R1',
        codigo: 'RT-DE-STGO',
        origen: 'PV-STGO',
      );
      await sembrarRutaConOrigen(
        base,
        id: 'R2',
        codigo: 'RT-DE-AURORA',
        origen: 'AURORA',
      );
      await sembrarRutaConOrigen(base, id: 'R3', codigo: 'RT-SIN-ORIGEN');
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
    }

    Future<void> pintar(
      WidgetTester tester, {
      Size tamano = const Size(1600, 1400),
    }) async {
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

    /// El desplegable de la ubicación, buscado por su clave — la MISMA que
    /// `BarraDeFiltros` usa para repartir la fila. Si alguien le quita la clave
    /// para «simplificar», esto se cae y se entiende por qué.
    final elFiltro = find.byKey(
      const ValueKey(TextosDeLosFiltrosDeRutas.tituloUbicacion),
    );

    Future<void> elegir(WidgetTester tester, String opcion) async {
      await tester.tap(elFiltro);
      await asentar(tester);
      // EL CAJÓN PINTA `ListTile`, NO `MenuItemButton` — 28/09/2026.
      //
      // Esta prueba nació cuando el desplegable abría un menú anclado en
      // escritorio. Esa tarde se quitó el corte —cajón siempre, también en
      // monitor, que es el §4 del `CLAUDE.md`— y con el menú se fue el
      // `MenuItemButton`. Lo que se comprueba es lo mismo: pulsar la opción.
      await tester.tap(find.widgetWithText(ListTile, opcion).last);
      await asentar(tester);
    }

    testWidgets('elegir una ubicación deja sólo sus rutas, y «Limpiar» las '
        'devuelve', (tester) async {
      await sembrarTres();
      await pintar(tester);

      expect(find.text('RT-DE-STGO'), findsOneWidget);
      expect(find.text('RT-DE-AURORA'), findsOneWidget);
      expect(find.text('RT-SIN-ORIGEN'), findsOneWidget);

      await elegir(tester, 'PV-STGO');

      expect(find.text('RT-DE-STGO'), findsOneWidget);
      expect(
        find.text('RT-DE-AURORA'),
        findsNothing,
        reason:
            'EL FILTRO NO FILTRA. Es justo lo que Jose pidió: «para saber de '
            'donde salio sin necesidad de estar viendo todas juntas»',
      );
      expect(find.text('RT-SIN-ORIGEN'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Limpiar'));
      await asentar(tester);
      expect(find.text('RT-DE-AURORA'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('«Sin punto de partida» trae las que no lo tienen', (
      tester,
    ) async {
      await sembrarTres();
      await pintar(tester);

      await elegir(tester, 'Sin punto de partida');

      expect(find.text('RT-SIN-ORIGEN'), findsOneWidget);
      expect(find.text('RT-DE-STGO'), findsNothing);
      expect(find.text('RT-DE-AURORA'), findsNothing);

      await desmontar(tester);
    });

    testWidgets('cada opción dice CUÁNTAS rutas salieron de ahí', (
      tester,
    ) async {
      await sembrarTres();
      await sembrarRutaConOrigen(
        base,
        id: 'R4',
        codigo: 'RT-DE-STGO-2',
        origen: 'PV-STGO',
      );
      await pintar(tester);

      await tester.tap(elFiltro);
      await asentar(tester);

      // La cuenta va en la `nota` de la opción, como en los desplegables de
      // Pedidos: contesta «de dónde salieron» sin tener que elegir para
      // averiguarlo.
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'PV-STGO'),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      await desmontar(tester);
    });

    testWidgets('LA OPCIÓN «CUALQUIERA» VA LA PRIMERA, y es la que está puesta '
        'al entrar', (tester) async {
      await sembrarTres();
      await pintar(tester);

      // Se mira la LISTA que la pantalla le pasa al `Selector`, no lo que se
      // pinta: así la guarda no depende de si el desplegable está abierto ni de
      // cuántas opciones hacen salir su buscador. Lo que se ata es la regla de
      // la casa —«todos» va primera y la pone la pantalla, no la pieza—, que es
      // lo que se rompe el día que alguien ordene las ubicaciones metiéndola
      // dentro del bucle.
      final selector = tester.widget<Selector<String>>(elFiltro);
      expect(selector.opciones.first.valor, '');
      expect(
        selector.opciones.first.etiqueta,
        TextosDeLosFiltrosDeRutas.cualquierUbicacion,
      );
      expect(
        selector.valor,
        '',
        reason: 'al entrar no se esconde ninguna ruta',
      );

      // Y con el buscador sin tocar, en el menú también sale primera.
      await tester.tap(elFiltro);
      await asentar(tester);
      final items = find.byType(ListTile);
      expect(
        find.descendant(
          of: items.first,
          matching: find.text(TextosDeLosFiltrosDeRutas.cualquierUbicacion),
        ),
        findsOneWidget,
      );

      await desmontar(tester);
    });

    testWidgets('EL FILTRO SE VE TAMBIÉN CON UN SOLO ALMACÉN', (tester) async {
      // Decisión escrita en `pantalla_rutas.dart`: no se esconde. Un filtro que
      // aparece y desaparece según lo que haya bajado es un filtro que nadie
      // encuentra —en la web la base nace vacía en cada carga—, y esconderlo
      // con un solo almacén dice lo contrario de lo que pasa: que esta pantalla
      // no sabe filtrar por ahí. Jose ya lo pidió al revés con los almacenes:
      // que se vea que existen aunque no estén configurados.
      await sembrarCatalogo(base);
      await sembrarRutaConOrigen(
        base,
        id: 'R1',
        codigo: 'RT-UNICA',
        origen: 'PV-STGO',
      );
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
      await pintar(tester);

      expect(elFiltro, findsOneWidget);
      final selector = tester.widget<Selector<String>>(elFiltro);
      expect(
        [for (final o in selector.opciones) o.etiqueta],
        [TextosDeLosFiltrosDeRutas.cualquierUbicacion, 'PV-STGO'],
        reason: 'y NOMBRA cuál es, que es un dato y no ruido',
      );

      await desmontar(tester);
    });

    testWidgets('§3-ter: LA BAJADA LLEGA CON LA PANTALLA DELANTE y el '
        'desplegable se llena solo', (tester) async {
      // Monta con la base VACÍA y siembra DESPUÉS, sin volver a montar: es la
      // única forma que caza un `Future` donde tiene que haber un `Stream`.
      // Sembrar antes es justo el caso que un `Future` resuelve bien.
      await pintar(tester);

      var selector = tester.widget<Selector<String>>(elFiltro);
      expect(
        selector.opciones.length,
        1,
        reason: 'con la base vacía sólo está «cualquiera», y eso es la verdad',
      );

      await sembrarTres();
      await asentar(tester);

      selector = tester.widget<Selector<String>>(elFiltro);
      expect(
        [for (final o in selector.opciones) o.etiqueta],
        [
          TextosDeLosFiltrosDeRutas.cualquierUbicacion,
          'AURORA',
          'PV-STGO',
          'Sin punto de partida',
        ],
        reason:
            'EL DESPLEGABLE SE QUEDÓ VACÍO PARA SIEMPRE. En la web la base nace '
            'vacía en cada carga de la página y la bajada llega un segundo más '
            'tarde: con una sola respuesta no hay forma de filtrar sin recargar, '
            'y recargar tampoco arregla nada porque vuelve a pasar',
      );

      await desmontar(tester);
    });

    testWidgets('a 390 px el filtro sigue en la barra, con su clave', (
      tester,
    ) async {
      // Donde se trabaja de verdad. Lo que se comprueba es que el filtro nuevo
      // entra por `BarraDeFiltros` —la pieza que existe justamente para que
      // nadie coloque los filtros a su manera— y que lleva su clave, que es de
      // donde esa barra saca el ancho de cada uno.
      await sembrarTres();
      await pintar(tester, tamano: const Size(390, 844));

      expect(find.byType(BarraDeFiltros), findsOneWidget);
      expect(
        find.descendant(of: find.byType(BarraDeFiltros), matching: elFiltro),
        findsOneWidget,
        reason:
            'fuera de la barra volvería el desorden del 25/09: cada pantalla '
            'colocando sus filtros a su manera',
      );

      await desmontar(tester);
    });
  });
}
