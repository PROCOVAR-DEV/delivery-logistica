// EL POST-DESPACHO EN UN TELÉFONO. Medido, no leído.
//
// Jose, el 22/09/2026, sobre el pre-despacho de Pedidos: «y la mierda de
// postdespacho ese q diseño mas horrendo el pre me imagino q este igual». Lo
// primero que hay que hacer con esa frase es COMPROBARLA, no darla por buena:
// esta prueba mide el cierre de ruta a 390 px, que es donde vive el
// post-despacho en pantalla.
//
// LO QUE SALIÓ: el post-despacho **no** estaba igual. Lo que se ve en pantalla
// —«Queda en el camión»— nunca fue una tabla: es un `Wrap` de insignias
// «producto ×N», y un `Wrap` le da a cada hijo el ancho entero y lo baja de
// línea ENTERO cuando no cabe. Por eso no hay nada que se salga por la derecha.
// Lo que sí había que mirar es el **pie del cajón**, que es un `Row` de tres
// botones, y un `Row` no baja nada: aprieta.
//
// POR QUÉ ESTAS PRUEBAS MIDEN COORDENADAS. Un fallo de colocación no rompe
// ninguna consulta: los textos ESTÁN en el árbol y `findsOneWidget` sale verde
// con la pantalla inservible. Lo único que lo distingue es `rect.right` contra
// el ancho del aparato.
//
// AQUÍ SÍ HAY DRIFT, y funciona: es el mismo molde de `cierre_widget_test.dart`,
// con la base abierta en el `setUp` pero **sembrada también ahí** porque el
// cierre lee las paradas de la base y sin ellas no hay nada que medir. Lo que
// cuelga (`CLAUDE.md` §5) es esperar el primer valor de un stream de Drift con
// un `await` dentro del cuerpo del `testWidgets`; esto no lo hace: bombea
// fotogramas con `asentar`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Dos pasadas, no una: el temporizador que cierra los `watch()` de Drift nace
/// al final del primer fotograma del desmontaje. Con una sola pasada la suite
/// no falla — **se cuelga**, que es peor.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  const anchoDelTelefono = 390.0;
  const altoDelTelefono = 844.0;

  /// Un nombre de producto de los de verdad, de los que no caben.
  const producto = 'MALTA GUAJIRA 1500 ML BLISTER 6U';

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
    for (final (i, nombre) in <String>[
      'Ferretería La Esquina',
      'Beto',
      'Carla',
    ].indexed) {
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
        producto: producto,
        unidades: 10,
        empaques: 2,
      );
    }
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(anchoDelTelefono, altoDelTelefono);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => laHoraDelPatio),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.marcar)),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets('el pie del cajón cabe: los tres botones dentro de 390 px', (
    tester,
  ) async {
    await pintar(tester);

    for (final texto in ['Post-despacho', 'Cerrar', 'Guardar 0 marcada(s)']) {
      final caja = tester.getRect(find.text(texto));
      expect(
        caja.right,
        lessThanOrEqualTo(anchoDelTelefono),
        reason:
            'El botón «$texto» llega hasta x=${caja.right.toStringAsFixed(1)} '
            'en una pantalla de $anchoDelTelefono px: el pie del cajón es un '
            '`Row` y un `Row` no baja de línea, aprieta.',
      );
      expect(caja.left, greaterThanOrEqualTo(0));
      // Una palabra es más ancha que alta. Partida letra a letra es al revés.
      expect(
        caja.width,
        greaterThan(caja.height),
        reason:
            '«$texto» mide ${caja.width.toStringAsFixed(1)} x '
            '${caja.height.toStringAsFixed(1)}: está partido en vertical.',
      );
    }

    await desmontar(tester);
  });

  testWidgets('«Queda en el camión» NO es una tabla y no se sale', (
    tester,
  ) async {
    await pintar(tester);

    // Lo que Jose daba por hecho que estaba igual que el pre-despacho. No lo
    // está: aquí nunca hubo `DataTable`.
    expect(
      find.byType(DataTable),
      findsNothing,
      reason:
          'Ha aparecido una tabla de escritorio en el cierre. En 390 px no cabe '
          'ninguna: el post-despacho de pantalla va en insignias dentro de un '
          '`Wrap`.',
    );

    final insignia = tester.getRect(find.textContaining('$producto ×'));
    expect(
      insignia.right,
      lessThanOrEqualTo(anchoDelTelefono),
      reason:
          'La insignia de «$producto» llega hasta '
          'x=${insignia.right.toStringAsFixed(1)}.',
    );
    expect(insignia.left, greaterThanOrEqualTo(0));

    await desmontar(tester);
  });

  testWidgets('la tarjeta de una parada no ocupa media pantalla', (
    tester,
  ) async {
    await pintar(tester);

    // La primera parada, de su nombre al de la segunda: es lo que mide la
    // tarjeta entera con sus tres botones de resultado.
    final primera = tester.getRect(find.text('Ferretería La Esquina')).top;
    final segunda = tester.getRect(find.text('Beto')).top;
    final alto = (segunda - primera).abs();
    expect(
      alto,
      lessThan(altoDelTelefono / 3),
      reason:
          'Una parada ocupa ${alto.toStringAsFixed(1)} px de los '
          '$altoDelTelefono de la pantalla: con eso no caben ni tres.',
    );

    // Y ninguno de los tres botones se sale ni se parte: van en un `Wrap`.
    for (final texto in ['Entregado', 'Devuelto', 'Cancelado']) {
      final caja = tester.getRect(find.text(texto).first);
      expect(caja.right, lessThanOrEqualTo(anchoDelTelefono), reason: texto);
      expect(caja.width, greaterThan(caja.height), reason: texto);
    }

    await desmontar(tester);
  });
}
