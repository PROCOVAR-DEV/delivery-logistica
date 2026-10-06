// QUE BOTON SALE EN CADA ESTADO DE LA RUTA, Y QUE HACE EL DE COMPLETAR.
//
// Esta prueba la escribe quien NO escribio la pantalla, a proposito: una guarda
// que rompe el mismo que la puso no es una guarda (`CLAUDE.md`, la regla de los
// agentes). El cajon del cierre por dentro lo cubre
// `cierre_al_completar_test.dart`; aqui se mira lo de fuera.
//
// La regla, de Jose el 17/09/2026: «ese estado se pone cuando están en ruta, no
// completados; ahí el cierre ya viene con el estado de cuando le van a dar a
// completado, es que se pregunta ese estado».
//
//   planificada  → `Iniciar ruta`. Ni cierre ni completar: no hay nada que
//                  cerrar de una ruta que no ha salido.
//   en curso     → `Cierre (N)` —N es lo que queda por marcar, o sea una tarea—
//                  y `Marcar como completada`.
//   completada   → `Ver cierre`, **sin la cuenta**, y nada mas. En una ruta
//                  cerrada «sin marcar» no es una tarea: es como acabo.
//
// Y el gesto que lo une todo: con paradas sin marcar, `Marcar como completada`
// **pregunta antes** en vez de cerrar la ruta a espaldas de nadie.

import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';

import 'package:drift/drift.dart' show OrderingTerm, Value;

import 'package:flutter/material.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

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

  /// Siembra **dentro del cuerpo de la prueba**, nunca en el `setUp`: allí corre
  /// fuera del reloj falso y la prueba se cuelga en vez de fallar (§5).
  Future<void> sembrar({
    required String estado,
    int paradas = 3,
    int marcadas = 0,
  }) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', estado: estado);
    for (var i = 0; i < paradas; i++) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: 'Cliente ${i + 1}',
        rutaId: 'R1',
        orden: i + 1,
        resultado: i < marcadas ? ResultadoParada.entregado : null,
      );
    }
  }

  Future<void> pintar(
    WidgetTester tester, {
    Stream<List<Pedido>>? paradas,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          if (paradas != null)
            paradasDeRutaProvider.overrideWith((ref, id) => paradas),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: DetalleDeRuta(rutaId: 'R1')),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<String?> estadoDeLaRuta() async {
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals('R1'))).getSingleOrNull();
    return ruta?.status;
  }

  testWidgets('planificada: ni cierre ni completar', (tester) async {
    await sembrar(estado: EstadoRuta.planificada);
    await pintar(tester);

    expect(find.text('Iniciar ruta'), findsOneWidget);
    expect(find.byKey(claveDelCierre), findsNothing);
    expect(find.byKey(claveDeCompletar), findsNothing);
    expect(find.text('Ver cierre'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('en curso: sólo completar abre los estados, sin cierre previo', (
    tester,
  ) async {
    await sembrar(estado: EstadoRuta.enCurso, marcadas: 1);
    await pintar(tester);

    // Dos de las tres sin marcar: eso es lo que queda por hacer, y se dice.
    expect(find.byKey(claveDelCierre), findsNothing);
    expect(find.textContaining('Cierre ('), findsNothing);
    expect(find.text('Ver cierre'), findsNothing);
    expect(find.byKey(claveDeCompletar), findsOneWidget);
    expect(find.text('Iniciar ruta'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('completada: `Ver cierre` SIN la cuenta, y nada mas', (
    tester,
  ) async {
    await sembrar(estado: EstadoRuta.completada, marcadas: 1);
    await pintar(tester);

    expect(find.text('Ver cierre'), findsOneWidget);
    // **Sin el numero.** Un `Cierre (2)` en una ruta cerrada parece una tarea
    // pendiente que ya nadie puede hacer.
    expect(find.text('Cierre (2)'), findsNothing);
    expect(find.textContaining('Cierre ('), findsNothing);
    // Y no se puede volver a completar ni iniciar.
    expect(find.byKey(claveDeCompletar), findsNothing);
    expect(find.text('Iniciar ruta'), findsNothing);

    // Y ABRE EN SOLO LECTURA, que es la mitad que el texto del boton no
    // demuestra: sin esto, dejarlo abriendo en modo de marcar pasa en silencio
    // y la ruta cerrada se sigue pudiendo tocar.
    await tester.tap(find.byKey(claveDelCierre));
    await asentar(tester);
    expect(find.text(CierreDeRuta.cabeceraSoloLectura), findsOneWidget);
    expect(find.text(CierreDeRuta.cabecera), findsNothing);
    expect(find.textContaining('Guardar'), findsNothing);

    await desmontar(tester);
  });

  testWidgets(
    'con paradas sin marcar, completar PREGUNTA antes de cerrar la ruta',
    (tester) async {
      await sembrar(estado: EstadoRuta.enCurso, marcadas: 1);
      await pintar(tester);

      await tester.tap(find.byKey(claveDeCompletar));
      await asentar(tester);

      // Se abre el cierre en su modo de completar...
      expect(find.text(CierreDeRuta.cabeceraAlCompletar), findsOneWidget);
      expect(find.text('Guardar y completar'), findsOneWidget);
      // ...y la ruta **todavia no se ha completado**. Cerrarla antes de
      // preguntar seria darla por cuadrada sin saber que bajo del camion.
      expect(await estadoDeLaRuta(), EstadoRuta.enCurso);

      await desmontar(tester);
    },
  );

  testWidgets(
    'con marcas anteriores completar abre la hoja y deja corregirlas',
    (tester) async {
      await sembrar(estado: EstadoRuta.enCurso, paradas: 3, marcadas: 3);
      await pintar(tester);
      expect(find.byKey(claveDelCierre), findsNothing);
      await tester.tap(find.byKey(claveDeCompletar));
      await asentar(tester);
      expect(find.text(CierreDeRuta.cabeceraAlCompletar), findsOneWidget);
      expect(await estadoDeLaRuta(), EstadoRuta.enCurso);
      expect(find.widgetWithText(FilledButton, 'Entregado'), findsNWidgets(3));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Devuelto').at(1));
      await asentar(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Guardar y completar'),
      );
      await asentar(tester);
      expect(await estadoDeLaRuta(), EstadoRuta.completada);
      final pedido = await (base.select(
        base.orders,
      )..where((p) => p.id.equals('p1'))).getSingle();
      expect(pedido.resultado, ResultadoParada.devuelto);
      final cola = await (base.select(
        base.apuntes,
      )..orderBy([(a) => OrderingTerm.asc(a.orden)])).get();
      expect(cola.map((a) => a.ruta).toList(), [
        '/routes/R1/results',
        '/routes/R1',
      ]);
      await desmontar(tester);
    },
  );

  testWidgets(
    'ruta vacía confirma en la hoja y completa sin resultados inventados',
    (tester) async {
      await sembrar(estado: EstadoRuta.enCurso, paradas: 0);
      await pintar(tester);
      await tester.tap(find.byKey(claveDeCompletar));
      await asentar(tester);
      expect(find.text('Guardar y completar'), findsOneWidget);
      expect(await estadoDeLaRuta(), EstadoRuta.enCurso);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Guardar y completar'),
      );
      await asentar(tester);
      expect(await estadoDeLaRuta(), EstadoRuta.completada);
      final cola = await base.select(base.apuntes).get();
      expect(cola.length, 1);
      expect(cola.single.metodo, 'PATCH');
      expect(cola.single.ruta, '/routes/R1');
      await desmontar(tester);
    },
  );

  testWidgets('paradas que no han llegado no son una ruta vacía', (
    tester,
  ) async {
    await sembrar(estado: EstadoRuta.enCurso, paradas: 0);
    final llegan = StreamController<List<Pedido>>();
    await pintar(tester, paradas: llegan.stream);
    await tester.tap(find.byKey(claveDeCompletar));
    await asentar(tester);
    FilledButton guardar() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Guardar y completar'),
    );
    expect(
      guardar().onPressed,
      isNull,
      reason: 'no completar mientras no se sabe qué paradas hay',
    );
    expect(await estadoDeLaRuta(), EstadoRuta.enCurso);
    llegan.add(const []);
    await asentar(tester);
    expect(
      guardar().onPressed,
      isNotNull,
      reason: 'vacío confirmado sí permite completar',
    );
    llegan.addError(StateError('No se pudieron leer las paradas'));
    await asentar(tester);
    expect(
      guardar().onPressed,
      isNull,
      reason:
          'el error no convierte el último vacío en una confirmación actual',
    );
    expect(
      find.textContaining('No se pudieron leer las paradas'),
      findsOneWidget,
    );
    llegan.add(const []);
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar y completar'));
    await asentar(tester);
    expect(await estadoDeLaRuta(), EstadoRuta.completada);
    await desmontar(tester);
    await tester.runAsync(llegan.close);
  });
  testWidgets(
    'otra acción completa mientras está la hoja y pasa a sólo lectura',
    (tester) async {
      await sembrar(estado: EstadoRuta.enCurso, marcadas: 1);
      await pintar(tester);
      await tester.tap(find.byKey(claveDeCompletar));
      await asentar(tester);
      expect(find.text('Guardar y completar'), findsOneWidget);
      await (base.update(base.routes)..where((r) => r.id.equals('R1'))).write(
        const RoutesCompanion(status: Value(EstadoRuta.completada)),
      );
      await asentar(tester);
      expect(find.text(CierreDeRuta.cabeceraSoloLectura), findsOneWidget);
      expect(find.text('Guardar y completar'), findsNothing);
      expect(find.text('Todas:'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Devuelto'), findsNothing);
      expect(await base.select(base.apuntes).get(), isEmpty);
      await desmontar(tester);
    },
  );
  testWidgets(
    'accesibilidad confirma abrir, elegir y guardar para los pasos de Guía',
    (tester) async {
      await sembrar(estado: EstadoRuta.enCurso, paradas: 1);
      await pintar(tester);
      final semantics = tester.ensureSemantics();
      try {
        Future<void> accionar(Finder finder) async {
          tester.binding.performSemanticsAction(
            SemanticsActionEvent(
              nodeId: tester.getSemantics(finder).id,
              type: SemanticsAction.tap,
              viewId: tester.view.viewId,
            ),
          );
          await asentar(tester);
        }

        await accionar(find.byKey(claveDeCompletar));
        expect(
          RegistroDeControles.acciones.value?.nombre,
          Senalado.rutasCompletar,
        );
        expect(find.text(CierreDeRuta.cabeceraAlCompletar), findsOneWidget);
        await accionar(find.widgetWithText(OutlinedButton, 'Entregado').at(1));
        expect(
          RegistroDeControles.acciones.value?.nombre,
          Senalado.rutasResultadoDeLaParada,
        );
        expect(find.widgetWithText(FilledButton, 'Entregado'), findsOneWidget);
        await accionar(
          find.widgetWithText(FilledButton, 'Guardar y completar'),
        );
        expect(
          RegistroDeControles.acciones.value?.nombre,
          Senalado.rutasGuardarElCierre,
        );
        expect(await estadoDeLaRuta(), EstadoRuta.completada);
        final cola = await (base.select(
          base.apuntes,
        )..orderBy([(a) => OrderingTerm.asc(a.orden)])).get();
        expect(cola.map((a) => a.ruta).toList(), [
          '/routes/R1/results',
          '/routes/R1',
        ]);
        await desmontar(tester);
      } finally {
        semantics.dispose();
      }
    },
  );
}
