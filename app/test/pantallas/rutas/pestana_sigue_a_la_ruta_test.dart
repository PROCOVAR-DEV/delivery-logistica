// La pestaña se va CON la ruta.
//
// Iniciar una ruta la saca de `Activas` —bien: ya no está activa, está en
// curso— y hasta ahora nadie tocaba la pestaña, así que la ruta le desaparecía
// de delante a quien acababa de arrancarla: se quedaba mirando un hueco en
// `Activas` convencido de que el botón no había hecho nada. La de Next lleva a
// la pestaña nueva en los dos casos (`routes/page.tsx:447` y `463-464`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  // VEINTE, NO DOCE. Desde que completar pasa por el cajon del cierre hay una
  // transicion de `showGeneralDialog` por medio, y con 600 ms el `Guardar y
  // completar` todavia no habia nacido: la prueba fallaba diciendo que no
  // encontraba el boton, que es un diagnostico que manda a buscar donde no es.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: ahora);
    await sembrarPedido(base, id: 'p1', cliente: 'Ana', rutaId: 'R1', orden: 1);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
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
    // La ruta, elegida: el detalle con sus botones sale a la derecha.
    await tester.tap(find.text('RT-001'));
    await asentar(tester);
  }

  testWidgets('al INICIAR, la pestaña pasa a `En curso` y la ruta se ve', (
    tester,
  ) async {
    await pintar(tester);

    // ESTA PANTALLA SE MONTA A 1600 px, o sea en un monitor, y ahí salen **las
    // tres pestañas a la vez** (`PestanasQueCaben`): el carrusel es del
    // teléfono, donde tres etiquetas con sus cuentas no caben. Jose, 17/09/2026:
    // «los tabs así como están eran para el móvil, que casi no tiene espacio».
    //
    // Así que lo que se mira no es qué etiquetas existen —existen las tres—
    // sino **cuál está marcada**, que es lo que de verdad dice dónde estás. La
    // marcada va en `FilledButton` y las otras en `OutlinedButton`.
    expect(find.widgetWithText(FilledButton, 'Planificadas (1)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'En curso (0)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta'));
    await asentar(tester);

    // La marca se movió: ahora la encendida es `En curso`, y `Planificadas`
    // pasa a ser una más de la fila.
    expect(find.widgetWithText(FilledButton, 'En curso (1)'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Planificadas (0)'),
      findsOneWidget,
    );
    // ...y lo que importa: **sigue delante**. Si la pestaña no se hubiera
    // movido, la lista de `Activas` estaría vacía y la tarjeta no saldría.
    // (Sale dos veces: la insignia de la tarjeta y la cabecera del detalle.)
    expect(find.text('RT-001'), findsNWidgets(2));
    expect(find.text('Sin rutas activas. Crea la primera.'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('al COMPLETAR, la pestaña pasa a `Historial` y suelta la ruta', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta'));
    await asentar(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Marcar como completada'),
    );
    await asentar(tester);

    // DESDE EL 17/09/2026 COMPLETAR PASA POR EL CIERRE cuando quedan paradas sin
    // marcar, y esta ruta tiene una (`p1`, sin resultado). Jose: «ese estado se
    // pone cuando están en ruta, no completados; ahí el cierre ya viene con el
    // estado de cuando le van a dar a completado, es que se pregunta ese
    // estado». O sea que el camino de verdad es este, y es el que hay que
    // vigilar: el cajon guarda, completa, y **despues** mueve la pestaña.
    //
    // Desde el 23/10/2026 hay que decidir TODAS las paradas antes de completar
    // (el botón sigue apagado mientras falte alguna): atajo «Todas: Entregado».
    await tester.tap(find.widgetWithText(OutlinedButton, 'Entregado').first);
    await asentar(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Guardar y completar'),
    );
    await asentar(tester);

    expect(find.text('Historial (1)'), findsOneWidget);
    expect(find.text('RT-001'), findsOneWidget);
    // Y la ruta elegida se suelta: quedarse con el detalle de algo que ya se
    // cerró deja la pantalla hablando de lo que ya no va.
    expect(
      find.text('Selecciona una ruta para ver el detalle'),
      findsOneWidget,
    );

    await desmontar(tester);
  });
}
