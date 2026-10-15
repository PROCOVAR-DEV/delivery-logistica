// EL TABLERO EN UN TELÉFONO: FLECHAS Y DEDO.
//
// Jose, 17/09/2026: «mejora los tabs en tablero y en todos donde haya tabs,
// ponlo con flecha a los lados y que se pueda hacer modo slice para moverse
// entre las columnas».
//
// Lo que se comprueba aquí es lo que hace el dedo sobre la pantalla de verdad,
// no que el widget exista:
//
//  * deslizando se va de «Sin colocar» a la primera zona, de una zona a la
//    siguiente, y de vuelta;
//  * las flechas hacen lo mismo, y en los dos extremos están apagadas;
//  * por encima de `anchoDeDosMitades` no sale NADA de esto, porque ahí no hay
//    pestañas: se ven las dos mitades a la vez.
//
// La regla que esto no puede pisar —que por debajo de 900 no se arrastra, y que
// con el dedo el arrastre es con pulsación larga— vive en
// `sin_arrastre_en_movil_test.dart` y `arrastre_segun_puntero_test.dart`. Que el
// deslizamiento no se coma ese arrastre se prueba en
// `deslizar_no_se_come_el_arrastre_test.dart`.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/kit.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  setUp(() async {
    base = BaseLocal.con(_enMemoria());
    servidor = ServidorFalso((peticion) async => null);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
  });

  tearDown(() => base.close());

  /// El mismo tope corto que en `pantalla_test.dart`: sin él, algo que no se
  /// asienta cuelga la prueba diez minutos en vez de fallar y contar por qué.
  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget montar() {
    final dio = Dio()..httpClientAdapter = servidor;
    return ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// Dos zonas y un pedido sin colocar: lo mínimo para que haya cuatro páginas
  /// —sin colocar, Centro, Vedado y la de crear otra— y se note cuál se ve.
  Future<void> sembrarDosZonas() async {
    final repo = RepositorioTablero(base, ColaDeSalida(base));
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Vedado');
    await sembrarPedido(base, id: 'p1', operacion: 'SC06-1257');
  }

  /// Un teléfono: por debajo de `anchoDeDosMitades`.
  Future<void> enUnTelefono(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> deslizarALaIzquierda(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await asentar(tester);
  }

  Future<void> deslizarALaDerecha(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(250, 0), 1000);
    await asentar(tester);
  }

  IconButton flecha(WidgetTester tester, Key cual) =>
      tester.widget<IconButton>(find.byKey(cual));

  testWidgets(
    'deslizando se pasa de «Sin colocar» a una zona y a la siguiente',
    (tester) async {
      await enUnTelefono(tester);
      await sembrarDosZonas();

      await tester.pumpWidget(montar());
      await asentar(tester);

      // De partida: la mitad de «sin colocar», con su pedido.
      expect(find.text('SC06-1257'), findsOneWidget);
      expect(find.text('Centro (0)'), findsNothing);

      await deslizarALaIzquierda(tester);
      expect(
        find.text('Centro (0)'),
        findsOneWidget,
        reason:
            'el primer deslizamiento pasa de «sin colocar» a la primera zona',
      );
      expect(find.text('SC06-1257'), findsNothing);

      // Y ESTO ES LO QUE MÁS LE INTERESA: de una zona a la siguiente sin volver
      // a la pestaña.
      await deslizarALaIzquierda(tester);
      expect(
        find.text('Vedado (0)'),
        findsOneWidget,
        reason:
            'dentro de zonas, deslizar tiene que llevar a la zona de al lado: '
            'es lo que pidió Jose con «moverse entre las columnas»',
      );
      expect(find.text('Centro (0)'), findsNothing);

      // De vuelta, por el mismo camino.
      await deslizarALaDerecha(tester);
      expect(find.text('Centro (0)'), findsOneWidget);
      await deslizarALaDerecha(tester);
      expect(find.text('SC06-1257'), findsOneWidget);

      await desmontar(tester);
    },
  );

  testWidgets(
    'sólo se ve la pestaña en la que estás, y el rótulo sigue al dedo',
    (tester) async {
      await enUnTelefono(tester);
      await sembrarDosZonas();

      await tester.pumpWidget(montar());
      await asentar(tester);

      expect(find.text('Sin colocar (1)'), findsOneWidget);
      expect(
        find.text('Zonas (2)'),
        findsNothing,
        reason:
            'la otra pestaña NO se enseña: «que salga la que está» y las bolitas '
            'dicen que hay más',
      );

      await deslizarALaIzquierda(tester);
      expect(
        find.text('Zonas (2)'),
        findsOneWidget,
        reason: 'el rótulo tiene que enterarse de lo que hizo el dedo abajo',
      );
      expect(find.text('Sin colocar (1)'), findsNothing);

      // Y en la SEGUNDA zona sigue diciendo «Zonas»: cuál de las dos es lo dicen
      // las bolitas y la cabecera de la columna, que está ahí mismo.
      await deslizarALaIzquierda(tester);
      expect(find.text('Zonas (2)'), findsOneWidget);

      await desmontar(tester);
    },
  );

  testWidgets('hay una bolita por página y la marcada sigue al dedo', (
    tester,
  ) async {
    await enUnTelefono(tester);
    await sembrarDosZonas();

    await tester.pumpWidget(montar());
    await asentar(tester);

    // Cuatro sitios: sin colocar, Centro, Vedado y la de crear otra.
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ClavesDePestanas.bola(i)), findsOneWidget);
    }
    expect(find.byKey(ClavesDePestanas.bola(4)), findsNothing);

    double bola(int i) => tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(ClavesDePestanas.bola(i)),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .first
        .constraints!
        .maxWidth;

    expect(bola(0) > bola(1), isTrue);

    await deslizarALaIzquierda(tester);
    expect(
      bola(1) > bola(0),
      isTrue,
      reason: 'la marca tiene que moverse con el dedo, o marca donde no estás',
    );

    await desmontar(tester);
  });

  testWidgets('las flechas llevan de una a otra', (tester) async {
    await enUnTelefono(tester);
    await sembrarDosZonas();

    await tester.pumpWidget(montar());
    await asentar(tester);

    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await asentar(tester);
    expect(find.text('Centro (0)'), findsOneWidget);

    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await asentar(tester);
    expect(find.text('Vedado (0)'), findsOneWidget);

    await tester.tap(find.byKey(ClavesDePestanas.atras));
    await asentar(tester);
    expect(find.text('Centro (0)'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('en los extremos la flecha está apagada', (tester) async {
    await enUnTelefono(tester);
    await sembrarDosZonas();

    await tester.pumpWidget(montar());
    await asentar(tester);

    // Primera página: por la izquierda no hay nada.
    expect(
      flecha(tester, ClavesDePestanas.atras).onPressed,
      isNull,
      reason:
          'una flecha encendida que no hace nada enseña a no fiarse de las '
          'flechas',
    );
    expect(flecha(tester, ClavesDePestanas.adelante).onPressed, isNotNull);

    // Hasta la última: sin colocar, Centro, Vedado y la de crear otra.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await asentar(tester);
    }
    expect(find.text('Fin de las zonas.'), findsOneWidget);
    expect(
      flecha(tester, ClavesDePestanas.adelante).onPressed,
      isNull,
      reason: 'detrás de la de crear otra zona no hay nada',
    );
    expect(flecha(tester, ClavesDePestanas.atras).onPressed, isNotNull);

    await desmontar(tester);
  });

  testWidgets('deslizar hacia ABAJO desplaza la lista y no cambia de pestaña', (
    tester,
  ) async {
    await enUnTelefono(tester);
    final repo = RepositorioTablero(base, ColaDeSalida(base));
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
    // Pedidos de sobra para que la lista se salga de la pantalla.
    for (var i = 0; i < 20; i++) {
      await sembrarPedido(
        base,
        id: 'p$i',
        operacion: 'SC06-${1000 + i}',
        aGrados: 0.01 * (i + 1),
      );
    }

    await tester.pumpWidget(montar());
    await asentar(tester);

    expect(find.text('SC06-1000'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(0, -500));
    await asentar(tester);

    expect(
      find.text('SC06-1000'),
      findsNothing,
      reason:
          'la lista de «sin colocar» se baja con el dedo todo el día: si el '
          'deslizamiento entre pestañas se come ese gesto, se cambió un '
          'fallo por otro',
    );
    expect(
      find.text('Centro (0)'),
      findsNothing,
      reason: 'y arriba o abajo NO es cambiar de pestaña',
    );

    await desmontar(tester);
  });

  testWidgets(
    'por encima de `anchoDeDosMitades` no hay ni pestañas ni flechas',
    (tester) async {
      await tester.binding.setSurfaceSize(
        const Size(anchoDeDosMitades + 100, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sembrarDosZonas();

      await tester.pumpWidget(montar());
      await asentar(tester);

      // Las dos mitades a la vez: el pedido sin colocar Y las dos zonas.
      expect(find.text('SC06-1257'), findsOneWidget);
      expect(find.text('Centro (0)'), findsOneWidget);
      expect(find.text('Vedado (0)'), findsOneWidget);

      expect(
        find.byType(CuerpoDeslizable),
        findsNothing,
        reason:
            'con las dos mitades a la vista no hay pestañas, así que no hay '
            'entre qué deslizar',
      );
      expect(find.byKey(ClavesDePestanas.atras), findsNothing);
      expect(find.byKey(ClavesDePestanas.adelante), findsNothing);

      await desmontar(tester);
    },
  );
}

QueryExecutor _enMemoria() => NativeDatabase.memory();
