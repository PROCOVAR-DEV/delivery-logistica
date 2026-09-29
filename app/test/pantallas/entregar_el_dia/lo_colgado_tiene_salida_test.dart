// LO QUE SE QUEDÓ COLGADO TIENE QUE PODER CERRARSE.
//
// Jose, 29/09/2026, sobre el cajón de entregar el día:
//
//     «los errores se acumulan y nunca se borran se mantienen aunq se allan
//      borrado las cosas y solucionado nunca se borran en la parte de entrega
//      del dia»
//
// Ahí dentro hay tres avisos, y el que no tenía salida ninguna era éste: «Sólo
// en este aparato». Cuenta trabajo hecho sin señal que **no va a subir nunca** —
// una ruta con id `local-…` que se quedó sin ningún apunte detrás.
//
// Para las zonas del tablero está bien que no haya botón: el ciclo las
// reconstruye y suben solas en cuanto hay señal, así que ese aviso es de paso.
// Para una ruta, un vehículo o un almacén nadie sabe rehacerlos, así que el
// ámbar se quedaba puesto en las siete pantallas y no había forma de quitarlo.
//
// El §4 del `CLAUDE.md` dice que un aviso así espera «hasta que una persona
// decida». Lo que faltaba era con qué decidir.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/entregar_el_dia/vista/cajon_entregar_el_dia.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../traer_el_dia/apoyo_traer_el_dia.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  late RelojFalso reloj;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 29, 17, 40));
  });

  tearDown(() => base.close());

  /// Una ruta armada sin señal que se quedó sin nada que la subiera. Es el caso
  /// exacto: id provisional, sin equivalencia y sin apunte.
  Future<void> unaRutaColgada() => base
      .into(base.routes)
      .insert(
        RoutesCompanion.insert(
          id: 'local-r1',
          name: const Value('Ruta del lunes'),
          branchId: const Value('stg-1'),
        ),
      );

  Future<ProviderContainer> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final caja = montarTraerElDia(
      base: base,
      reloj: reloj.leer,
      responder: (p) async => servidorQueTraeElDia(p),
      // Sin pista de red: aquí no se prueba subir nada, y un ciclo corriendo por
      // detrás deja una rueda girando con la que `pumpAndSettle` no vuelve.
      hayPista: false,
    );
    addTearDown(caja.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: caja,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (contexto) => TextButton(
                onPressed: () => abrirCajonDeEntregarElDia(contexto),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return caja;
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('una ruta colgada se puede dar por perdida, y el aviso se va', (
    tester,
  ) async {
    await unaRutaColgada();
    await abrir(tester);

    expect(
      find.textContaining('Sólo en este aparato'),
      findsOneWidget,
      reason: 'el aviso no salió: la prueba no está midiendo nada',
    );

    // PASO 1: se pide la decisión, y no pasa nada todavía.
    await tester.tap(find.byKey(const ValueKey('dar-por-perdido-routes')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sólo en este aparato'),
      findsOneWidget,
      reason:
          'el primer toque ya lo dio por perdido. Esto no pasa solo nunca: '
          'entre el botón y el hecho va una pregunta que dice qué se pierde',
    );
    expect(
      find.textContaining('no se borra nada del aparato'),
      findsOneWidget,
      reason:
          'la pregunta no dice qué NO pasa. «¿Seguro?» a secas sobre algo que '
          'suena a borrar trabajo es una pregunta que nadie contesta que sí',
    );

    // PASO 2: la persona decide.
    await tester.tap(find.byKey(const ValueKey('perder-de-verdad-routes')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Sólo en este aparato'),
      findsNothing,
      reason:
          'se dio por perdida y el aviso sigue ahí. Es exactamente lo que Jose '
          've: los errores no se van nunca',
    );
  });

  testWidgets('darlo por perdido NO borra la ruta del aparato', (tester) async {
    await unaRutaColgada();
    await abrir(tester);
    await tester.tap(find.byKey(const ValueKey('dar-por-perdido-routes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perder-de-verdad-routes')));
    await tester.pumpAndSettle();

    // LO QUE SE QUITA ES EL AVISO, NO EL DATO. Borrar una ruta local se lleva
    // sus paradas y deja los pedidos apuntando a algo que no está; y lo que se
    // hizo aquel día sigue siendo la única explicación de por qué aquel reparto
    // salió como salió.
    expect(
      await base.select(base.routes).get(),
      hasLength(1),
      reason:
          'darlo por perdido borró la ruta. Se prometió en pantalla que no se '
          'borra nada, y encima deja los pedidos apuntando a algo que no está',
    );

    await desmontar(tester);
  });

  // Y LA MITAD QUE EVITA QUE ESTO TIRE TRABAJO BUENO.
  testWidgets('a una zona del tablero NO se le ofrece renunciar', (
    tester,
  ) async {
    await EsquemaTablero.asegurar(base);
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES ('z-1', 'stg-1', 'Centro', 1, '2026-09-29T08:00:00.000', "
      "'2026-09-29T08:00:00.000', 1)",
    );
    await abrir(tester);

    expect(
      find.textContaining('Sólo en este aparato'),
      findsOneWidget,
      reason: 'la zona colgada no se está contando: la prueba no mide nada',
    );
    expect(
      find.byKey(const ValueKey('dar-por-perdido-board_columns')),
      findsNothing,
      reason:
          'se ofrece dar por perdida una zona del tablero. El ciclo sabe '
          'rehacerla y la sube sola en cuanto haya señal: quien le dé al botón '
          'estaría tirando trabajo que iba a llegar',
    );

    await desmontar(tester);
  });

  testWidgets('se puede cambiar de idea antes de decidir', (tester) async {
    await unaRutaColgada();
    await abrir(tester);
    await tester.tap(find.byKey(const ValueKey('dar-por-perdido-routes')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dejarlo como está'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Sólo en este aparato'),
      findsOneWidget,
      reason: 'se dijo que no y aun así se perdió',
    );
    expect(
      find.byKey(const ValueKey('dar-por-perdido-routes')),
      findsOneWidget,
      reason: 'tras decir que no, ya no se puede volver a decidir',
    );

    await desmontar(tester);
  });
}
