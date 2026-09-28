// LA CABECERA DECÍA «420 kg» ENCIMA DE DOS PARADAS QUE SUMAN 516,5.
//
// Medido por Jose el 28/09/2026 en la APK 1.0.13 de un SM-A165M,
// `RT-20260928-003`:
//
//     Planificada · 0.7 km (incl. regreso) · 420 kg · $3.10 · … · Carga total: 2
//     1  POR26-260927-3733   419.7 kg   $2.51
//     2  POR26-260925-3700    96.8 kg   $0.59
//
// **Y sólo fallaba el peso.** El importe sumaba las dos (2,51 + 0,59 = 3,10) y la
// carga total contaba las dos. Ésa es la pista entera: el peso era el ÚNICO
// número de ese renglón que no se sumaba de la lista que hay justo debajo — se
// leía de `routes.total_weight`, una columna que se escribe una vez al armar y
// que nadie vuelve a calcular.
//
// El armado NO es lo que falla, y está comprobado en los dos lados con dos
// pedidos del mismo cliente y la misma dirección:
// `test/pantallas/tablero/dos_pedidos_del_mismo_cliente_test.dart` y
// `api/internal/api/dos_pedidos_del_mismo_cliente_test.go`. Los dos guardan los
// 516,5. Lo que fallaba era leer ese total más tarde como si siguiera siendo
// verdad.
//
// Es el §3-bis del `CLAUDE.md`: dos preguntas sobre lo mismo —el peso de la
// cabecera y el de sus paradas— **se atan con una prueba, no con un
// comentario**.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/peso_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import 'rutas_a_mano.dart';

void main() {
  group('la cabecera del detalle y sus paradas dicen el mismo peso', () {
    /// Las dos paradas de `RT-20260928-003`, con el total guardado que traía la
    /// ruta: el de UNA sola de ellas.
    Future<void> pintarLaDeJose(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineaDeDatosDeLaRuta(
            ruta: rutaAMano(
              // `routes.total_weight` tal y como bajó del servidor.
              peso: 419.7,
              paradas: [
                paradaAMano(
                  id: 'POR26-260927-3733',
                  cliente: 'KIOSKO HABANA CLUB OMAR JIMENEZ MONTOYA L2',
                  peso: 419.7,
                  costo: 2.51,
                ),
                paradaAMano(
                  id: 'POR26-260925-3700',
                  cliente: 'KIOSKO HABANA CLUB OMAR JIMENEZ MONTOYA L2',
                  peso: 96.8,
                  costo: 0.59,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('el peso es el de TODAS sus paradas, no el total guardado', (
      tester,
    ) async {
      await pintarLaDeJose(tester);

      expect(
        find.textContaining('517 kg'),
        findsOneWidget,
        reason:
            'las dos paradas suman 516,5 kg y la cabecera tiene que decirlo: es '
            'el número contra el que se mide si el camión cabe',
      );
      expect(
        find.textContaining('420 kg'),
        findsNothing,
        reason:
            'ES LO QUE JOSE VIO: el peso de la PRIMERA parada haciéndose pasar '
            'por el de la ruta entera. `routes.total_weight` se escribe al armar '
            'y nadie lo recalcula; el importe y la «Carga total» de este mismo '
            'renglón ya se suman de las paradas, y por eso el peso era el único '
            'que podía mentir',
      );
    });

    testWidgets('el importe y la carga siguen contando las dos', (
      tester,
    ) async {
      await pintarLaDeJose(tester);

      // Los dos números que YA salían bien. Van aquí para que el arreglo del
      // peso no se los lleve por delante.
      expect(find.textContaining(r'$3.10'), findsOneWidget);
      expect(find.textContaining('Carga total: 2'), findsOneWidget);
    });
  });

  group('el peso de cada ruta, para la lista', () {
    late BaseLocal base;

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> sembrarParada(
      String id, {
      required String ruta,
      required double peso,
      String? enRuta,
    }) => base
        .into(base.orders)
        .insert(
          OrdersCompanion.insert(
            id: id,
            customerName: 'Cliente',
            address: 'Calle 1',
            weight: Value(peso),
            ultimaRutaId: Value(ruta),
            routeId: Value(enRuta),
          ),
        );

    test('suma las paradas de cada ruta y no mezcla las de otra', () async {
      await sembrarParada('a', ruta: 'R1', peso: 419.7, enRuta: 'R1');
      await sembrarParada('b', ruta: 'R1', peso: 96.8, enRuta: 'R1');
      await sembrarParada('c', ruta: 'R2', peso: 48.4, enRuta: 'R2');

      final pesos = await pesoPorRuta(base).first;
      expect(pesos['R1'], closeTo(516.5, 0.0001));
      expect(pesos['R2'], closeTo(48.4, 0.0001));
    });

    test('un devuelto sigue pesando: se cuenta por `ultima_ruta_id`', () async {
      await sembrarParada('a', ruta: 'R1', peso: 419.7, enRuta: 'R1');
      // Lo que no se entregó suelta su `route_id` para poder ir en la ruta de
      // mañana, y conserva `ultima_ruta_id`. Contando por `route_id`, una ruta
      // cerrada iría perdiendo peso según se marcan los devueltos y acabaría
      // diciendo que el camión salió vacío.
      await sembrarParada('b', ruta: 'R1', peso: 96.8);

      final pesos = await pesoPorRuta(base).first;
      expect(
        pesos['R1'],
        closeTo(516.5, 0.0001),
        reason:
            'la hoja de paradas enseña las dos —lee `ultima_ruta_id`—, así que '
            'el peso tiene que contar las dos o vuelve a haber dos respuestas '
            'para la misma pregunta',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Y LO QUE SOSTIENE LA DECISIÓN: nadie vuelve a leer esa columna
  // ---------------------------------------------------------------------------
  //
  // Calcado de `el_cero_que_se_escribe_test.dart`, que hace lo mismo con
  // `totalPrice` desde el 23/09/2026. Se comprueba sobre el CÓDIGO y no montando
  // pantallas: lo que hay que impedir es que alguien vuelva a escribir
  // `ruta.totalWeight` donde va el peso de una ruta, y eso se ve leyendo.
  test('ninguna pantalla lee `totalWeight`', () {
    // Quien la ESCRIBE la nombra con `totalWeight:` (parámetro con nombre) y
    // puede seguir haciéndolo: la columna se queda como espejo de la aritmética
    // del servidor. Un LECTOR se escribe `.totalWeight`.
    final lectores = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      // El código generado de Drift define la columna y su `copyWith`.
      if (f.path.endsWith('base.g.dart')) continue;
      final lineas = f.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        final l = lineas[i].trimLeft();
        if (l.startsWith('//') || l.startsWith('///')) continue;
        if (lineas[i].contains('.totalWeight')) {
          lectores.add('${f.path}:${i + 1}: ${lineas[i].trim()}');
        }
      }
    }
    expect(
      lectores,
      isEmpty,
      reason:
          'estas líneas LEEN `routes.total_weight`, que se escribe una sola vez '
          '—al armar la ruta— y que nadie recalcula después: es el peso del día '
          'en que se armó, no el de las paradas que la ruta lleva hoy. Con él la '
          'cabecera decía «420 kg» encima de dos paradas que suman 516,5, y el '
          'aviso de sobrepeso medía la capacidad del camión contra ese mismo '
          'número. El peso de una ruta sale de `RutaConTodo.pesoTotal` o de '
          '`pesoPorRuta`, que suman las paradas:\n${lectores.join('\n')}',
    );
  });
}
