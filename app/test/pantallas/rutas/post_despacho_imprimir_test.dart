// El boton `Post-despacho` del cierre de ruta.
//
// La cuenta y el PDF existian los dos y estaban probados; el boton abria una
// tabla en un cajon. Sin papel no hay firma del chofer de lo que volvio en el
// camion, que es justo para lo que sirve esa hoja.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/impresion/vista_previa.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Dos pasadas: el temporizador que cierra los `watch()` de Drift nace al final
/// del primer fotograma del desmontaje. Con una sola la suite no falla, **se
/// cuelga**.
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
        // La tercera parada va SIN empaques a proposito: es la que se contaria
        // 0 si alguien quitara el respaldo a `quantity`, y entonces la hoja del
        // almacen diria que del camion no baja nada de ese bulto.
        empaques: i == 2 ? null : 2,
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
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.marcar)),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets('`Post-despacho` abre la HOJA imprimible, no una tabla', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Post-despacho'));
    await asentar(tester);

    expect(find.byType(VistaPreviaPdf), findsOneWidget);
    // La cabecera del cajon dice como acabo cada parada: sin marcar nada, las
    // tres siguen en el camion.
    expect(
      find.text('0 entregadas · 0 devueltas · 0 canceladas · 3 sin marcar'),
      findsOneWidget,
    );

    // Y lo que abre es el PDF que ya existia, armado sin salir a la red.
    final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
    final bytes = await vista.armar(PdfPageFormat.a4);
    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');

    await desmontar(tester);
  });

  testWidgets('la hoja lleva lo marcado AHORA, aunque no se haya guardado', (
    tester,
  ) async {
    await pintar(tester);

    // La primera parada, entregada. (El `Entregado` de la fila de atajos es el
    // primero; el de cada parada va detras.)
    await tester.tap(find.widgetWithText(OutlinedButton, 'Entregado').at(1));
    await asentar(tester);
    // Todavia sin guardar: `Guardar 1 marcada(s)` sigue ahi.
    expect(find.text('Guardar 1 marcada(s)'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Post-despacho'));
    await asentar(tester);

    expect(
      find.text('1 entregadas · 0 devueltas · 0 canceladas · 2 sin marcar'),
      findsOneWidget,
    );
    await desmontar(tester);
  });
}
