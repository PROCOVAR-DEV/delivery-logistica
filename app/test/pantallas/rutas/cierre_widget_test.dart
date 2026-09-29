import 'dart:async';
// El cierre de ruta, pintado. Lo que aqui se comprueba no se ve en un test de
// datos: que pulsar dos veces el mismo boton DESMARCA, que `Todas:` marca de
// golpe, que la ✕ de cerrar esta siempre, y —lo que mas importa— que **al
// reabrir se parte de lo ya guardado**.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// Un indicador giratorio es una animacion que no para, asi que `pumpAndSettle`
/// no terminaria nunca. Se bombean unos fotogramas y basta.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Al desmontarse, los `watch()` de Drift programan un temporizador de cero para
/// cerrarse. Si el test acaba antes de que corra, el marco lo cuenta como
/// pendiente y falla.
///
/// **Hacen falta DOS pasadas, no una.** El temporizador lo crea el propio desmontaje, al
/// final del primer fotograma, así que con un solo `pump` todavía no ha nacido y no llega
/// a dispararse. Con uno solo esto no fallaba: **colgaba la suite entera diez minutos**,
/// que es peor, porque el que la corre piensa que se le trabó el equipo.
///
/// Es el mismo `desmontar()` de `test/pantallas/tablero/pantalla_test.dart`.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final laHoraDelPatio = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-20260914-001',
    );
    for (final (i, nombre) in <String>['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: nombre,
        rutaId: 'R1',
        orden: i + 1,
      );
      await sembrarRenglon(
        base,
        id: 'ri${i + 1}',
        pedidoId: 'p${i + 1}',
        producto: 'Arroz',
        unidades: 10,
        empaques: 2,
      );
    }
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => laHoraDelPatio),
        ],
        // El cajon se monta SOBRE un `Scaffold`, igual que en la aplicacion:
        // alli lo pone el armazon (`navegacion/armazon.dart`) y el cajon se abre
        // encima como una ruta modal. Sin el, `ScaffoldMessenger.showSnackBar`
        // no encuentra de donde colgar el aviso y revienta —que es exactamente
        // lo que pasaba aqui al guardar—. Montar el widget desnudo probaba una
        // pantalla que no existe en ningun sitio.
        child: const MaterialApp(
          home: Scaffold(body: CierreDeRuta(rutaId: 'R1')),
        ),
      ),
    );
    await asentar(tester);
  }

  /// El boton de una parada concreta. Hacen falta indices porque `Entregado`
  /// aparece cuatro veces: una por parada y una en la fila de atajos.
  Finder botonDeParada(String texto, int parada) =>
      find.widgetWithText(OutlinedButton, texto).at(parada + 1);

  testWidgets('la cabecera, la ✕ y el pie salen con su texto literal', (
    tester,
  ) async {
    await pintar(tester);

    expect(find.text('Cierre de ruta'), findsOneWidget);
    expect(find.text('RT-20260914-001 · 3 parada(s)'), findsOneWidget);
    expect(find.text(CierreDeRuta.cabecera), findsOneWidget);
    // La ✕ que nunca desaparece: esta fuera del cuerpo desplazable.
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    // Con 0 marcadas, Guardar esta deshabilitado.
    expect(find.text('Guardar 0 marcada(s)'), findsOneWidget);
    final guardar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Guardar 0 marcada(s)'),
    );
    expect(guardar.onPressed, isNull);
    // Las tres sin marcar cuentan como que siguen arriba.
    expect(
      find.text('3 sin marcar · cuentan como que siguen en el camión'),
      findsOneWidget,
    );
    await desmontar(tester);
  });

  testWidgets('pulsar el mismo boton dos veces DESMARCA', (tester) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    expect(find.text('Guardar 1 marcada(s)'), findsOneWidget);

    // Otra vez el mismo: se desmarca. Es como se corrige un dedazo sin recargar
    // nada.
    await tester.tap(find.widgetWithText(FilledButton, 'Entregado'));
    await asentar(tester);
    expect(find.text('Guardar 0 marcada(s)'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('`Devuelto` pide el motivo y `Todas:` marca de golpe', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Devuelto', 0));
    await asentar(tester);
    expect(
      find.text(
        '¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)',
      ),
      findsOneWidget,
    );

    // El atajo es el PRIMER `Entregado` de la pantalla: la fila `Todas:`.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Entregado').first);
    await asentar(tester);
    expect(find.text('Guardar 3 marcada(s)'), findsOneWidget);
    // Con todo entregado no queda nada en el camion.
    expect(find.text('Nada: se entregó todo lo que salió.'), findsOneWidget);
    // Y el campo de motivo desaparece, porque ya no hay ninguna devuelta.
    expect(
      find.text(
        '¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)',
      ),
      findsNothing,
    );
    await desmontar(tester);
  });

  testWidgets('la vista previa dice lo que QUEDA, incluido lo sin marcar', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    // Salieron 6 empaques de arroz; se entrego 1 parada (2), quedan 4: los 2 de
    // la devuelta... o mas bien los 4 de las dos sin marcar.
    expect(find.text('Arroz ×4'), findsOneWidget);
    await desmontar(tester);
  });

  // EL «ATRÁS» NO SE LLEVA LAS MARCAS SIN PREGUNTAR — 29/09/2026.
  //
  // Se vio probando el cierre en el teléfono de Jose: dos paradas marcadas, sin
  // guardar, y el botón de atrás cerró el cajón llevándoselas. La pantalla lo
  // avisaba —el pie dice «Salir sin guardar (2 sin guardar)»— pero eso es el
  // rótulo de un botón que nadie pulsó. En Android el atrás se hace sin mirar,
  // con el gesto del borde, y ahí se va una jornada entera de marcas.
  //
  // No se bloquea: irse sin guardar es legítimo y un cajón que no deja salir es
  // peor. Lo que no puede pasar es que se pierda **en silencio** (§4).
  testWidgets('con marcas sin guardar, el atrás PREGUNTA en vez de llevárselas',
      (tester) async {
    await pintar(tester);
    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    await tester.tap(botonDeParada('Entregado', 1));
    await asentar(tester);
    expect(find.textContaining('2 sin guardar'), findsOneWidget);

    // El gesto de atrás del sistema, que es el que se hace sin mirar.
    //
    // SIN `await`, y hace falta: con un `PopScope` que pregunta, ese future no
    // se completa hasta que alguien conteste la pregunta — y quien la contesta
    // es esta misma prueba, dos líneas más abajo. Esperarlo aquí es esperarse a
    // uno mismo: la prueba **se cuelga en vez de fallar**, que es la trampa del
    // §5 del CLAUDE.md.
    unawaited(tester.binding.handlePopRoute());
    await asentar(tester);

    expect(
      find.textContaining('Tienes 2 sin guardar'),
      findsOneWidget,
      reason:
          'el atrás cerró el cajón con dos marcas puestas y no preguntó nada. '
          'Doce paradas marcadas en el patio del almacén se van con un gesto '
          'del borde de la pantalla',
    );
    expect(
      find.text('Cierre de ruta'),
      findsOneWidget,
      reason: 'además cerró la hoja: ya no hay a dónde volver aunque se diga no',
    );

    await desmontar(tester);
  });

  testWidgets('y si dice que sigue marcando, no se pierde ninguna', (
    tester,
  ) async {
    await pintar(tester);
    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    unawaited(tester.binding.handlePopRoute());
    await asentar(tester);

    await tester.tap(find.byKey(const ValueKey('cierre-seguir-marcando')));
    await asentar(tester);

    expect(
      find.textContaining('1 sin guardar'),
      findsOneWidget,
      reason:
          'dijo que seguía marcando y la marca ya no está: la pregunta salió '
          'para nada',
    );

    await desmontar(tester);
  });

  // Y LA OTRA MITAD, la que evita cambiar un fallo por un estorbo: sin nada que
  // perder, el atrás no pregunta. Un aviso que sale siempre deja de leerse, y
  // entonces tampoco se lee el día que importa (§3-quinquies).
  testWidgets('sin nada sin guardar, el atrás NO pregunta', (tester) async {
    await pintar(tester);

    unawaited(tester.binding.handlePopRoute());
    await asentar(tester);

    expect(
      find.textContaining('Tienes'),
      findsNothing,
      reason:
          'pregunta sin que haya nada que perder. A la tercera vez nadie lee '
          'esa pregunta, y entonces tampoco la leerá el día que sí importa',
    );

    await desmontar(tester);
  });

  testWidgets('guardar encola el cierre y AL REABRIR se ve marcado', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    await tester.tap(botonDeParada('Devuelto', 1));
    await asentar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Guardar 2 marcada(s)'));
    await asentar(tester);

    // El cierre esta en la cola, con la hora del aparato, sin haber hablado con
    // ningun servidor.
    //
    // Se lee con `lote()` —una consulta que termina— y DENTRO de `runAsync`.
    // `pendientes()` es un flujo de Drift y su primer valor llega por un
    // temporizador; en un test de widget el tiempo no corre solo, asi que
    // `await ….first` se quedaba esperando un temporizador que nadie dispara y
    // **colgaba la suite entera** en vez de fallar. `runAsync` saca esta lectura
    // del tiempo simulado y la deja correr de verdad.
    final cola = ColaDeSalida(base, reloj: () => laHoraDelPatio);
    final pendientes = (await tester.runAsync(cola.lote))!;
    expect(pendientes.length, 1);
    expect(pendientes.single.ruta, '/routes/R1/results');
    expect(pendientes.single.hechoAt, laHoraDelPatio);

    // Y se le dice a la persona lo que paso, con el texto del pliego.
    expect(find.text(CierreDeRuta.exito), findsOneWidget);

    await desmontar(tester);

    // Se vuelve a abrir el cajon: **se parte de lo ya guardado**, no de cero.
    await pintar(tester);
    expect(find.text('Guardar 2 marcada(s)'), findsOneWidget);
    expect(
      find.text('1 sin marcar · cuentan como que siguen en el camión'),
      findsOneWidget,
    );
    await desmontar(tester);
  });
}
