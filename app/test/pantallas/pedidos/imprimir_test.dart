// Los dos caminos al papel del almacen desde Pedidos: lo MARCADO a mano y lo
// FILTRADO.
//
// No falta ninguna funcion: el PDF del pre-despacho existe y esta probado
// (`test/impresion/pdf_test.dart`). Lo que faltaba era el boton que lo llama, y
// sin el no hay papel con el que bajar al almacen. Por eso esto se comprueba
// **hasta los bytes**: que el boton salga no vale de nada si lo que abre no es
// una hoja de verdad.
//
// ## El camino cambio el 22/09/2026, la comprobacion no
//
// Antes el pre-despacho era un bloque en la pagina —uno plegable para lo
// filtrado y una franja para lo marcado— con su tabla dentro y su
// `Ver e imprimir` al lado del titulo. Ahora es **un boton que abre la vista**,
// igual que el post-despacho del cierre de ruta, y el `Ver e imprimir` vive en
// el pie de ese cajon. Son dos cajones apilados: la VISTA (`Pre-despacho`) y,
// encima, la HOJA (`Hoja de pre-despacho`).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/impresion/hoja.dart' as papel;
import 'package:reparto/impresion/vista_previa.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/vista_pre_despacho.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

/// `pumpAndSettle` no vale: el indicador giratorio es una animacion que no para
/// nunca. Se bombean unos fotogramas y basta.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
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
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarLosOnce(base);
    for (final coleccion in const [
      Colecciones.pedidos,
      Colecciones.renglones,
      Colecciones.productos,
    ]) {
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(coleccion, hasta: null, bajadaAt: ahora);
    }
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
        // Con los idiomas montados, como en `lib/app.dart`: la vista previa
        // del PDF lee sus etiquetas de ahi y sin ellos revienta al pintarse.
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets(
    'marcando un pedido sale su pre-despacho y de ahi sale la hoja del almacen',
    (tester) async {
      await pintar(tester);

      // Sin nada marcado no hay franja de lo elegido: el unico boton de
      // pre-despacho que hay es el de lo filtrado.
      expect(
        find.byKey(PreDespacho.claveDelBotonDeLoFiltrado),
        findsOneWidget,
      );
      expect(find.byKey(PreDespacho.claveDelBotonDeLoElegido), findsNothing);
      // Y el `Ver e imprimir` NO esta en la pagina: vive dentro de la vista.
      expect(find.text(PreDespacho.verEImprimir), findsNothing);

      // La casilla de la cabecera marca toda la pagina: 8 pedidos, que con el
      // arranque acotado es lo que puede subir a un camion.
      await tester.tap(find.byType(Checkbox).first);
      await asentar(tester);

      expect(find.byKey(PreDespacho.claveDelBotonDeLoElegido), findsOneWidget);
      expect(find.textContaining('8 pedido(s) elegidos'), findsOneWidget);

      await tester.tap(find.byKey(PreDespacho.claveDelBotonDeLoElegido));
      await asentar(tester);

      // Se abre LA VISTA, con su titulo. `find.text` a secas no vale aqui:
      // detras del cajon sigue el boton de lo filtrado, que dice exactamente
      // `Pre-despacho` mientras no ha sumado nada.
      expect(
        find.widgetWithText(Cajon, PreDespacho.titulo),
        findsOneWidget,
      );
      expect(find.byType(VistaPreDespacho), findsOneWidget);

      // Y de ahi, la hoja: otro cajon encima, con su propio titulo.
      await tester.tap(find.text(PreDespacho.verEImprimir));
      await asentar(tester);

      expect(find.text(PreDespacho.tituloDeLaHoja), findsOneWidget);
      expect(find.byType(VistaPreviaPdf), findsOneWidget);

      // La prueba de que llama al PDF que ya existe: se le pide la hoja a la
      // propia vista y sale un PDF de verdad, sin salir a la red.
      final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
      final bytes = await vista.armar(PdfPageFormat.a4);
      expect(latin1.decode(bytes.take(5).toList()), '%PDF-');

      await desmontar(tester);
    },
  );

  testWidgets('el pre-despacho de lo filtrado tambien se imprime', (
    tester,
  ) async {
    await pintar(tester);

    // Sin abrir la vista no se ha sumado nada todavia, y por eso el rotulo no
    // inventa un numero: es pulsarlo lo que dispara la suma (§7.2 del PLAN:
    // sumar doce mil pedidos al pintar la pantalla es trabajo que nadie mira).
    final abrir = find.byKey(PreDespacho.claveDelBotonDeLoFiltrado);
    expect(find.text(PreDespacho.rotulo), findsOneWidget);

    await tester.tap(abrir);
    await asentar(tester);

    // Con la suma dentro, `Ver e imprimir` se enciende. Una hoja en blanco no
    // es una hoja, asi que antes de tenerla el boton esta apagado.
    final imprimir = find.widgetWithText(FilledButton, PreDespacho.verEImprimir);
    expect(tester.widget<FilledButton>(imprimir).onPressed, isNotNull);

    await tester.tap(imprimir);
    await asentar(tester);

    expect(find.text(PreDespacho.tituloDeLaHoja), findsOneWidget);
    expect(find.byType(VistaPreviaPdf), findsOneWidget);
    await desmontar(tester);
  });

  group('la hoja que se manda al PDF', () {
    test('lleva la sucursal, el dia y la cabecera de la de Next', () {
      final totales = TotalesPreDespacho(
        const [
          LineaPreDespacho(
            producto: 'Arroz',
            empaques: 5,
            unidades: 50,
            pesoKg: 125,
          ),
          // Sin peso resuelto: al papel va `null`, NUNCA cero. Un cero se lee
          // como «no pesa» y en la hoja del almacén eso cuadra mal.
          LineaPreDespacho(producto: 'Frijol', empaques: 1, unidades: 10),
        ],
        pedidos: 2,
        pesoDeLosPedidos: 300,
      );

      final hoja = hojaDePreDespacho(
        totales: totales,
        sucursal: 'Camagüey',
        dia: '2026-09-03',
      );

      expect(hoja.sucursal, 'Camagüey');
      // Pedidos no sabe de camiones: la hoja sale del almacen, no de una ruta.
      expect(hoja.vehiculo, '');
      expect(hoja.dia, '2026-09-03');
      expect(hoja.pedidos, 2);
      expect(hoja.pesoKg, 300);
      expect(hoja.lineas.first.formatos, 5);
      // Sin peso resuelto va `null` al papel, NO cero: antes se mandaba cero
      // «que es lo que pesa lo que no sabemos», y en la hoja del almacén un
      // cero no se distingue de un producto que de verdad no pesa. Lo pinta
      // `pesoDeFila` como `—`.
      expect(hoja.lineas.last.pesoKg, isNull);
    });

    // LOS CONTADORES TIENEN QUE LLEGAR AL PAPEL — 28/09/2026.
    //
    // Es el punto exacto por donde las dos hojas del mismo filtro se pueden
    // separar: la pantalla suma lo que sabe y lo marca con `≥` porque tiene el
    // contador de renglones delante; si en este traspaso se cae, el papel
    // imprime la MISMA cifra **sin la marca** y ahí ya es un total. Se vería
    // `26320.0 kg` en el papel y `≥ 26320.0 kg` en la pantalla del mismo
    // filtro, y quien baja al almacén se queda con el papel.
    test('los contadores de renglones viajan a la hoja, y cuentan igual', () {
      final totales = TotalesPreDespacho(
        const [
          // La forma de MALTA GUAJIRA: 21 renglones de 1.149 sin peso.
          LineaPreDespacho(
            producto: 'MALTA GUAJIRA 1500 ML BLISTER 6U',
            empaques: 4949,
            unidades: 29694,
            pesoKg: 26320,
            lineasSinPeso: 21,
          ),
          // Y uno que no sabe nada en ninguno de sus 6.
          LineaPreDespacho(
            producto: 'VODKA REGIO BLISTER 6U',
            empaques: 364,
            unidades: 2184,
            lineasSinPeso: 6,
          ),
        ],
        pedidos: 264,
        pesoDeLosPedidos: 29835.4,
      );

      final hoja = hojaDePreDespacho(
        totales: totales,
        sucursal: 'La Habana',
        dia: null,
      );

      expect(
        hoja.lineas.first.lineasSinPeso,
        21,
        reason:
            'El contador se quedó en el camino: sin él la fila imprime '
            '26320.0 como si fuera el peso entero de 4.949 empaques.',
      );
      expect(hoja.lineas.first.pesoCompleto, isFalse);
      expect(hoja.lineas.last.lineasSinPeso, 6);

      // Y el total del papel cuenta LOS MISMOS renglones que la pantalla: 27,
      // no 2. Dos números distintos para la misma pregunta es el §3-bis.
      final enElPapel = papel.TotalesPreDespacho.de(hoja);
      expect(
        enElPapel.sinPeso,
        totales.sinPeso,
        reason:
            'La pantalla cuenta ${totales.sinPeso} renglones sin peso y el '
            'papel ${enElPapel.sinPeso}, con las mismas líneas.',
      );
      expect(enElPapel.sinPeso, 27);
      expect(enElPapel.pesoCompleto, isFalse);
    });

    test('el dia sólo se escribe cuando el rango ES un dia', () {
      final unDia = DateTime(2026, 9, 3);
      expect(
        diaDeLaHoja(FiltrosPedidos(desde: unDia, hasta: unDia)),
        '2026-09-03',
      );
      // Un rango de varios dias no escribe ninguno: poner uno de los dos seria
      // mentir sobre lo que hay debajo.
      expect(
        diaDeLaHoja(FiltrosPedidos(desde: unDia, hasta: DateTime(2026, 9, 5))),
        isNull,
      );
      expect(diaDeLaHoja(const FiltrosPedidos()), isNull);
    });
  });
}
