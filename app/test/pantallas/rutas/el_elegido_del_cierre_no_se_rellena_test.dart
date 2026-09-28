// «ENTREGADO / DEVUELTO / CANCELADO»: EL ELEGIDO SE MARCA SIN RELLENARSE —
// 28/09/2026.
//
// Los tres botones de cada parada del cierre son el único sitio de la aplicación
// donde el color **no dice jerarquía, dice qué estado es**. Verde es entregado,
// rojo devuelto, gris cancelado; ninguno es más importante que otro. Lo que hay
// que ver de un vistazo es cuál de los tres está marcado.
//
// Hasta hoy eso se veía **rellenando el elegido**: un `FilledButton` con
// `backgroundColor` puesto a mano y el texto forzado a blanco para que se leyera
// encima del verde. Era el último relleno macizo que quedaba en la aplicación, y
// la regla de la casa es que un botón no lleva fondo: lo que lo diferencia es el
// color, el borde y el icono (§4 del `CLAUDE.md` de la raíz).
//
// Así que el marcado se mueve a esos tres:
//
//   · color   — el elegido en SU color fuerte, los otros dos en tinta suave;
//   · borde   — 2 px del color contra 1 px casi transparente;
//   · icono   — el elegido, y sólo él, lleva un visto delante.
//
// El icono es el que sostiene la lectura cuando los tres se ven pequeños, de
// reojo y con sol, o cuando quien mira no separa el verde del rojo. Por eso esta
// prueba lo exige por separado: si mañana alguien quita el `Icons.check`, el
// color y el borde solos siguen «pasando» y la marca se vuelve más difícil de
// leer sin que nada se queje.
//
// Lo que NO se toca: el elegido sigue siendo un `FilledButton` y el suelto un
// `OutlinedButton`. Es por donde los encuentran `cierre_widget_test.dart` y
// `cierre_al_completar_test.dart` para saber cuál está marcado, y cambiar el
// tipo de widget sería romper tres ficheros de pruebas para no ganar nada.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final laHoraDelPatio = DateTime(2026, 9, 28, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Siembra **dentro del cuerpo** y no en el `setUp`: lo que Drift deja
  /// empezado fuera del reloj falso no avanza dentro, y la prueba se cuelga en
  /// vez de fallar (§5 del `CLAUDE.md`).
  Future<void> pintar(WidgetTester tester, double ancho) async {
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-20260928-001',
    );
    await sembrarPedido(base, id: 'p1', cliente: 'Ana', rutaId: 'R1', orden: 1);
    await sembrarRenglon(
      base,
      id: 'ri1',
      pedidoId: 'p1',
      producto: 'Arroz',
      unidades: 10,
      empaques: 2,
    );

    tester.view.physicalSize = Size(ancho, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => laHoraDelPatio),
        ],
        child: MaterialApp(
          theme: temaDeReparto(),
          home: const Scaffold(body: CierreDeRuta(rutaId: 'R1')),
        ),
      ),
    );
    await asentar(tester);
  }

  for (final ancho in [390.0, 1400.0]) {
    testWidgets(
      'a ${ancho.toInt()} px marcar «Entregado» no lo rellena: lo colorea, lo '
      'bordea y le pone un visto',
      (tester) async {
        await pintar(tester, ancho);

        // El de la parada, no el atajo de la fila de arriba.
        final suelto = find.widgetWithText(OutlinedButton, 'Entregado');
        expect(
          suelto,
          findsWidgets,
          reason: 'sin marcar, los tres estados son botones sueltos',
        );
        final antes = tester.widget<OutlinedButton>(suelto.last).style!;
        final fondoAntes = antes.backgroundColor?.resolve(const {});
        expect(
          fondoAntes == null || fondoAntes.a == 0,
          isTrue,
          reason:
              'un estado sin marcar se pinta con un tinte de fondo. Eso es un '
              'fondo, y un botón de esta aplicación no lleva fondo',
        );

        await tester.tap(suelto.last);
        await asentar(tester);

        // Ya marcado: pasa a ser el `FilledButton` de la parada.
        final elegido = find.widgetWithText(FilledButton, 'Entregado');
        expect(
          elegido,
          findsOneWidget,
          reason: 'al pulsar «Entregado» esa parada tiene que quedar marcada',
        );
        final estilo = tester.widget<FilledButton>(elegido).style!;

        // 1. SIN FONDO, en los cinco estados. Éste era el último relleno macizo
        //    que quedaba en la aplicación.
        for (final MapEntry(key: cuando, value: estado)
            in <String, Set<WidgetState>>{
              'en reposo': <WidgetState>{},
              'con el ratón encima': {WidgetState.hovered},
              'pulsado': {WidgetState.pressed},
              'con el foco': {WidgetState.focused},
              'apagado': {WidgetState.disabled},
            }.entries) {
          final fondo = estilo.backgroundColor?.resolve(estado);
          expect(
            fondo == null || fondo.a == 0,
            isTrue,
            reason:
                'el estado marcado se rellena $cuando. El elegido se marca con '
                'color, borde e icono, no rellenándolo (§4 del CLAUDE.md de la '
                'raíz)',
          );
        }

        // 2. EL BORDE, más grueso que el de los que no están marcados.
        final borde = estilo.side?.resolve(const {});
        final bordeSuelto = tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Devuelto').last,
            )
            .style!
            .side
            ?.resolve(const {});
        expect(
          borde?.width,
          greaterThan(bordeSuelto!.width),
          reason:
              'el estado marcado tiene el mismo contorno que los que no lo '
              'están: sin relleno, el grosor es lo que dice cuál está elegido '
              'para quien no separa el verde del rojo',
        );

        // 3. EL VISTO. Y sólo en el elegido.
        expect(
          find.descendant(of: elegido, matching: find.byIcon(Icons.check)),
          findsOneWidget,
          reason:
              'el estado marcado se quedó sin su visto. Es el rasgo que se lee '
              'de reojo, con sol y sin distinguir colores; el color y el borde '
              'solos no lo sustituyen',
        );
        expect(
          find.descendant(
            of: find.widgetWithText(OutlinedButton, 'Devuelto').last,
            matching: find.byIcon(Icons.check),
          ),
          findsNothing,
          reason:
              'un estado SIN marcar lleva el visto: entonces el visto no marca '
              'nada',
        );

        await desmontar(tester);
      },
    );
  }
}
