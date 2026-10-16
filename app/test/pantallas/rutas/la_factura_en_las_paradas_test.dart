// LA FACTURA Y SU FECHA, EN TODO LUGAR DONDE SE VE UN PEDIDO — issue 17 de Amado, 16/10/2026.
//
// «En el CARD de Paradas de la ruta, es necesario también poner el número de factura y la fecha
// de la facturación. Ponlo siempre como un valor primario de referencia… El cliente recomienda
// que el número de factura esté presente en todos los lugares que se visualice un pedido.»
//
// Ayer y hoy se hizo en las tarjetas del Tablero y de Pedidos (`la_factura_manda_en_la_tarjeta_
// test.dart`). Aquí van los sitios de las RUTAS: la tarjeta de la parada (detalle y cajón «Ver
// paradas»), la parada del cierre, el globo del croquis (el modelo `recorridoDe`) y la hoja
// impresa del post-despacho. La pregunta de «Quitar de la ruta» y la fila del asistente se atan
// en `quitar_de_ruta_test.dart` y `asistente_wizard_test.dart`, y el globo en
// `croquis_de_ruta_test.dart`.
//
// Cada sitio en pareja: con factura (número en el estilo primario y su fecha en día de Cuba) y
// sin ella (la frase de siempre, «Sin número de factura»). 390 y 1440 px, sin excepciones.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:reparto/idioma.dart';
import 'package:reparto/impresion/armar_post_despacho.dart';
import 'package:reparto/impresion/post_despacho.dart';
import 'package:reparto/impresion/vista_previa.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../impresion/los_dos_pesos_del_pre_despacho_test.dart'
    show leerElPapel;
import '../pedidos/sembrar.dart';
import 'cierre_widget_test.dart' show asentar, desmontar;

const _sinNumero = 'Sin número de factura';

/// Las 22:00 UTC del 15 son las 18:00 (o 17:00) del 15 en Cuba: el día es el 15 con el huso
/// del aparato que sea.
final _facturadaEl = DateTime.utc(2026, 10, 15, 22);

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 16, 10);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// R1 con dos paradas: Ana CON factura `47061, 47062` (y fecha) y Beto SIN número. **Dentro
  /// del cuerpo de cada prueba**, no en el `setUp` (§5).
  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', estado: EstadoRuta.enCurso);
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Ana',
      rutaId: 'R1',
      orden: 1,
      folio: 'PTB25-1',
      facturaNumero: '47061, 47062',
      endLat: 21.1,
      endLng: -77.1,
    );
    await sembrarPedido(
      base,
      id: 'p2',
      cliente: 'Beto',
      rutaId: 'R1',
      orden: 2,
      folio: 'PTB25-2',
      facturaNumero: null,
      endLat: 21.2,
      endLng: -77.2,
    );
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      OrdersCompanion(facturaAt: Value(_facturadaEl)),
    );
    // Beto tiene una fecha del cotejo SIN número: no se enseña (no es una factura).
    await (base.update(base.orders)..where((o) => o.id.equals('p2'))).write(
      OrdersCompanion(facturaAt: Value(_facturadaEl)),
    );
  }

  /// Lo que tiene que cumplir cualquier sitio CON número: texto, fecha, y el número en el
  /// estilo primario (negrita y mayor que el cliente), encima del cliente.
  void conFactura(WidgetTester tester, Finder factura, Finder cliente) {
    expect(tester.widget<Text>(factura).data, 'Factura 47061, 47062');
    final f = tester.widget<Text>(factura).style!;
    final c = tester.widget<Text>(cliente).style!;
    expect(f.fontWeight, FontWeight.w600, reason: 'la factura va en negrita');
    expect(
      f.fontSize!,
      greaterThan(c.fontSize!),
      reason: 'la factura es mayor que el cliente',
    );
    expect(
      tester.getTopLeft(factura).dy,
      lessThan(tester.getTopLeft(cliente).dy),
    );
    // La fecha, en el día de Cuba, pegada al número.
    expect(find.text('· 15/10/2026'), findsOneWidget);
  }

  group('la tarjeta de la parada (detalle y cajón «Ver paradas»)', () {
    for (final ancho in const [390.0, 1440.0]) {
      testWidgets('a $ancho px, con factura: número en negrita y su fecha', (
        tester,
      ) async {
        await sembrar();
        final p1 = await (base.select(base.orders)..where((o) => o.id.equals('p1'))).getSingle();
        tester.view.physicalSize = Size(ancho, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TarjetaDeParada(numero: 1, parada: p1, lineas: const []),
              ),
            ),
          ),
        );

        conFactura(
          tester,
          find.byKey(const ValueKey('parada-factura-p1')),
          find.text('Ana'),
        );
        expect(find.text(_sinNumero), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a $ancho px, sin número: la frase de siempre y ninguna fecha', (
        tester,
      ) async {
        await sembrar();
        final p2 = await (base.select(base.orders)..where((o) => o.id.equals('p2'))).getSingle();
        tester.view.physicalSize = Size(ancho, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TarjetaDeParada(numero: 2, parada: p2, lineas: const []),
              ),
            ),
          ),
        );

        expect(find.text(_sinNumero), findsOneWidget);
        expect(find.byKey(const ValueKey('parada-factura-p2')), findsNothing);
        expect(find.textContaining('15/10/2026'), findsNothing);
        expect(find.text('Beto'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('la parada del cierre de ruta', () {
    for (final ancho in const [390.0, 1440.0]) {
      testWidgets('a $ancho px: Ana con su factura y fecha, Beto con la frase', (
        tester,
      ) async {
        await sembrar();
        tester.view.physicalSize = Size(ancho, 1600);
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
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.marcar),
              ),
            ),
          ),
        );
        await asentar(tester);

        // La pareja que SÍ: Ana.
        conFactura(
          tester,
          find.byKey(const ValueKey('cierre-factura-p1')),
          find.text('Ana'),
        );
        // La que NO: Beto, con la frase y sin fecha (la del cotejo no es de una factura).
        expect(find.text(_sinNumero), findsOneWidget);
        expect(find.byKey(const ValueKey('cierre-factura-p2')), findsNothing);
        expect(find.text('· 15/10/2026'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await desmontar(tester);
      });
    }
  });

  group('el globo del croquis (el modelo que lo alimenta)', () {
    test('recorridoDe lleva la factura con su fecha, y sin número no lleva nada', () async {
      await sembrar();
      final ruta = await ConsultasRutas(base).rutaConTodo('R1').first;
      final recorrido = recorridoDe(ruta!);

      expect(recorrido.paradas[0].factura, 'Factura 47061, 47062 · 15/10/2026');
      expect(recorrido.paradas[1].factura, isNull);
    });
  });

  group('el post-despacho que arma el cierre', () {
    testWidgets('el papel del cierre lleva la factura de cada parada pendiente, y '
        'la frase donde no hay', (tester) async {
      await sembrar();
      tester.view.physicalSize = const Size(1440, 2400);
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
            home: const Scaffold(
              body: CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.marcar),
            ),
          ),
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.widgetWithText(OutlinedButton, 'Post-despacho'));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
      final papel = leerElPapel(await vista.armar(PdfPageFormat.a4));
      final texto = papel.renglones.map((r) => r.texto).join('\n');

      // Ana y Beto están sin marcar, así que salen en la hoja.
      expect(texto, contains('Factura 47061, 47062 · 15/10/2026'));
      expect(texto, contains(TextoPostDespacho.sinNumeroDeFactura));
      await desmontar(tester);
    });
  });

  group('la hoja impresa del post-despacho', () {
    const ruta = DatosDeRuta(ruta: 'RT-1', sucursal: 'Camagüey', vehiculo: 'Camión 1');
    final pedidos = <PedidoDeRuta>[
      PedidoDeRuta(
        customerName: 'Ana',
        factura: 'Factura 47061 · 15/10/2026',
        items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 2)],
      ),
      PedidoDeRuta(
        customerName: 'Beto',
        items: <ItemDePedido>[ItemDePedido(name: 'Azúcar', packs: 3)],
      ),
    ];

    test('la parada pendiente lleva su factura al modelo de la hoja', () {
      final hoja = armarPostDespacho(ruta, pedidos);
      expect(hoja.pendientes[0].factura, 'Factura 47061 · 15/10/2026');
      expect(hoja.pendientes[1].factura, isNull);
    });

    test('el papel dice la factura encima del cliente, y «Sin número de factura» '
        'cuando no hay', () async {
      final papel = leerElPapel(
        await pdfPostDespacho(
          armarPostDespacho(ruta, pedidos),
          impresoEn: DateTime(2026, 10, 16, 10),
        ),
      );
      final factura = papel.renglonCon('Factura 47061 · 15/10/2026');
      final ana = papel.renglonCon('Ana');
      expect(
        factura.y,
        isNot(ana.y),
        reason: 'la factura va en su propio renglón, aparte del cliente',
      );
      expect(papel.renglonCon(TextoPostDespacho.sinNumeroDeFactura), isNotNull);
      expect(papel.renglonCon('Beto'), isNotNull);
    });
  });
}
