// EL PRE-DESPACHO DE LA RUTA — issue 8 de Amado.
//
// Amado: «la información de predespacho no se muestra igual cuando se crea la
// ruta manual y cuando se genera de los paneles; la que está en la manual es la
// más correcta, pero además vamos a añadirle otra tabla por factura, porque la
// rebaja de las cantidades de las tarjetas de estiba se hace por cantidades y
// facturas. Ej.: se sacaron 20 blister, 10 de una factura y 10 de otra; en la
// tarjeta no se pone 20, se ponen 10 y 10 poniendo la factura que provocó la
// salida de inventario».
//
// ## Qué difería, y qué ata esto
//
// El pre-despacho sólo existía en el paso 4 del asistente. La ruta que sale del
// tablero no pasa por el asistente y su detalle sólo traía la «Carga total». La
// salida es que el detalle de CUALQUIER ruta pinte la misma vista con la misma
// suma, y eso se ata aquí con pruebas y no con un comentario (`CLAUDE.md`
// §3-bis):
//
//  * el camino del asistente y el de la ruta dan las MISMAS líneas y la misma
//    hoja;
//  * la tabla «Por producto y factura» cuadra con la de producto a producto y con
//    «Carga total» (el subtotal de cada producto es su fila de arriba);
//  * lo que se ve en la pantalla es lo que se imprime.
//
// Los números de los pedidos están sacados a mano, a propósito: una prueba que
// los calculara con el código que prueba comprobaría la cuenta contra sí misma.
//
// LOS DATOS son LA HOJA QUE AMADO ESCRIBIÓ A MANO en el issue (la tarjeta de
// estiba es por producto; dentro, una fila por factura y el subtotal):
//
//   46226  Cerv 500   5  15 kg      46226  Cerv 330  10  20 kg
//   46228  Cerv 500  10  30 kg             subtotal  10  20
//   46229  Cerv 500   5  15 kg      46226  Cerv 1,5  10  90 kg
//          subtotal  20  60                subtotal  10  90
//                                   46230  Arroz R.   2  20 kg
//                                          subtotal   2  20
//
// Una diferencia con su hoja, y es a propósito: Cerv 330 y Cerv 1,5 empatan a 10
// y aquí salen por nombre (Cerv 1,5 primero), que es como desempata la tabla de
// arriba; en la hoja escrita a mano ese orden no significa nada.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/impresion/hoja.dart' as papel;
import 'package:reparto/impresion/por_producto_y_factura.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/vista_pre_despacho.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/pre_despacho_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart'
    show preDespachoDeLoElegidoEnElAsistenteProvider;
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/tabla_por_producto_y_factura.dart';
import 'package:reparto/impresion/vista_previa.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../impresion/los_dos_pesos_del_pre_despacho_test.dart'
    show leerElPapel;
import '../pedidos/sembrar.dart';

final _ahora = DateTime(2026, 10, 15, 9, 0);

Future<void> _sembrarLasFacturas(BaseLocal base) async {
  await sembrarCatalogo(base);
  await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: _ahora);
  await _sembrarLosPedidos(base);
  await _sembrarLosRenglones(base);
}

Future<void> _sembrarLosPedidos(BaseLocal base) async {
  // La factura es el número de Ventra, no el folio: los dos distintos a propósito
  // para que la tabla no pueda salir del folio. Y el orden de las paradas
  // (0..3) NO es el de las facturas: la tabla va por número de factura.
  for (final (id, factura, orden) in const [
    ('o1', '46226', 2),
    ('o2', '46228', 0),
    ('o3', '46229', 3),
    ('o4', '46230', 1),
  ]) {
    await sembrarPedido(
      base,
      id: id,
      cliente: 'Cliente $id',
      folio: 'PTB25-261015-000${id.substring(1)}',
      facturaNumero: factura,
      rutaId: 'R1',
      orden: orden,
      peso: 50,
    );
  }
}

Future<void> _sembrarLosRenglones(BaseLocal base) async {
  Future<void> r(
    String id,
    String pedido,
    int linea,
    String producto,
    double unidades,
    double empaques,
    double? peso,
  ) => sembrarRenglon(
    base,
    id: id,
    pedidoId: pedido,
    linea: linea,
    producto: producto,
    unidades: unidades,
    empaques: empaques,
    pesoLinea: peso,
  );

  await r('r1', 'o1', 1, 'Cerv 500', 120, 5, 15);
  await r('r2', 'o1', 2, 'Cerv 330', 240, 10, 20);
  await r('r3', 'o1', 3, 'Cerv 1,5', 60, 10, 90);
  await r('r4', 'o2', 1, 'Cerv 500', 240, 10, 30);
  await r('r5', 'o3', 1, 'Cerv 500', 120, 5, 15);
  await r('r6', 'o4', 1, 'Arroz R.', 20, 2, 20);
}

/// Lo que dice la tabla con los datos de arriba, escrito a mano. La cabecera va
/// primero. Sin columna de unidades: Amado no la pone.
const _laTablaDeAmado = <List<String>>[
  ['Factura', 'Producto', 'Cant.', 'Kg'],
  ['46226', 'Cerv 500', '5', '15.0'],
  ['46228', 'Cerv 500', '10', '30.0'],
  ['46229', 'Cerv 500', '5', '15.0'],
  ['Subtotal', '', '20', '60.0'],
  ['46226', 'Cerv 1,5', '10', '90.0'],
  ['Subtotal', '', '10', '90.0'],
  ['46226', 'Cerv 330', '10', '20.0'],
  ['Subtotal', '', '10', '20.0'],
  ['46230', 'Arroz R.', '2', '20.0'],
  ['Subtotal', '', '2', '20.0'],
];

/// Un quinto pedido SIN `factura_numero` y con folio, que es la PRIMERA parada,
/// con un renglón de arroz sin peso: sale «Sin número» AL FINAL del bloque del
/// arroz, ni cae al folio (`NumeroDeFactura`, decisión de Jose) ni sube delante
/// por ser la primera parada; y el subtotal del arroz pasa a ser un mínimo.
const _folioSinFactura = 'PTB25-261015-0005';

Future<void> _sembrarUnoSinFactura(BaseLocal base) async {
  await sembrarPedido(
    base,
    id: 'o5',
    cliente: 'Cliente o5',
    folio: _folioSinFactura,
    facturaNumero: null,
    rutaId: 'R1',
    orden: -1,
    peso: 10,
  );
  await sembrarRenglon(
    base,
    id: 'r7',
    pedidoId: 'o5',
    linea: 1,
    producto: 'Arroz R.',
    unidades: 10,
    empaques: 1,
    pesoLinea: null,
  );
}

/// [_laTablaDeAmado] con el pedido sin factura en el bloque del arroz.
final _laTablaConUnoSinFactura = <List<String>>[
  ..._laTablaDeAmado.take(_laTablaDeAmado.length - 1),
  ['Sin número', 'Arroz R.', '1', '—'],
  ['Subtotal', '', '3', '≥ 20.0'],
];

/// Lo que dicen las tarjetas del teléfono, en orden: el producto de encabezado
/// (una vez) y cada factura con sus cifras y su rótulo pegado.
const _lasTarjetasDeAmado = <String>[
  'Cerv 500',
  '46226',
  '5 cant.',
  '15.0 kg',
  '46228',
  '10 cant.',
  '30.0 kg',
  '46229',
  '5 cant.',
  '15.0 kg',
  'Subtotal',
  '20 cant.',
  '60.0 kg',
  'Cerv 1,5',
  '46226',
  '10 cant.',
  '90.0 kg',
  'Subtotal',
  '10 cant.',
  '90.0 kg',
  'Cerv 330',
  '46226',
  '10 cant.',
  '20.0 kg',
  'Subtotal',
  '10 cant.',
  '20.0 kg',
  'Arroz R.',
  '46230',
  '2 cant.',
  '20.0 kg',
  'Subtotal',
  '2 cant.',
  '20.0 kg',
];

/// «Carga total» de los datos de arriba, producto a producto: lo que tienen que
/// decir los subtotales.
const _cargaTotal = <(String, String)>[
  ('Cerv 500', '20'),
  ('Cerv 1,5', '10'),
  ('Cerv 330', '10'),
  ('Arroz R.', '2'),
];

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pintar(WidgetTester tester, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => _ahora),
          // Sin calles: este detalle no va de mapas, y la prueba no sale a la red.
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
          recorridoPorCallesProvider.overrideWithValue(
            const SinCallesQueSeguir(),
          ),
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

  /// Los textos de la tabla, en el orden en que se pintan (los `Text.rich`
  /// también: son las cifras de la tarjeta del teléfono).
  List<String> losTextos(WidgetTester tester, Finder dentroDe) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(of: dentroDe, matching: find.byType(Text)),
    ))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ];

  /// Los renglones del papel que abre «Ver e imprimir».
  Future<List<String>> elPapel(WidgetTester tester) async {
    await tester.tap(find.byKey(claveDeVerEImprimirElPreDespacho));
    await asentar(tester);
    final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
    final bytes = await vista.armar(PdfPageFormat.a4);
    return [for (final r in leerElPapel(bytes).renglones) r.texto];
  }

  /// Los renglones de la tabla en el papel, en el orden en que salen. Desde su
  /// título: el pie de la tabla de arriba también tiene cifras sueltas.
  List<String> laTablaEnElPapel(
    List<String> renglones,
    List<List<String>> tabla,
  ) {
    final esperados = [
      for (final fila in tabla.skip(1))
        fila.where((c) => c.isNotEmpty).join(' '),
    ];
    return renglones
        .skip(renglones.indexOf('POR PRODUCTO Y FACTURA'))
        .where(esperados.contains)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // LA PANTALLA
  // ---------------------------------------------------------------------------
  for (final ancho in [1440.0, 1024.0]) {
    testWidgets(
      'a ${ancho.toInt()} px el detalle trae «Carga total», el '
      'pre-despacho y la tabla «Por producto y factura» de la hoja de Amado',
      (tester) async {
        await _sembrarLasFacturas(base);
        await pintar(tester, Size(ancho, 2400));

        // «Carga total» SE MANTIENE (Amado: «la sección de Carga Total se
        // mantiene»).
        expect(find.text('Carga total'), findsOneWidget);

        // El pre-despacho de siempre, el del asistente.
        expect(find.text(PreDespacho.titulo), findsOneWidget);
        expect(find.byType(VistaPreDespacho), findsOneWidget);
        expect(find.text('Peso de los productos'), findsOneWidget);

        // Y la tabla nueva: UN BLOQUE POR PRODUCTO, UNA FILA POR FACTURA. «10 y
        // 10», no «20».
        expect(find.text(PorProductoYFactura.titulo), findsOneWidget);
        expect(find.byKey(PorProductoYFactura.claveDeLaTabla), findsOneWidget);
        expect(
          find.byKey(PorProductoYFactura.claveDeLasTarjetas),
          findsNothing,
        );
        expect(
          losTextos(tester, find.byKey(PorProductoYFactura.claveDeLaTabla)),
          [for (final fila in _laTablaDeAmado) ...fila],
        );

        await desmontar(tester);
      },
    );
  }

  testWidgets('el subtotal de cada producto es su «Carga total» y su fila de '
      'la tabla de producto a producto', (tester) async {
    await _sembrarLasFacturas(base);
    // A 390 px el pre-despacho es una tarjeta por producto (con su clave), que es
    // donde se puede medir un producto suelto: la fila de un `DataTable` no es
    // un widget y no se deja buscar.
    await pintar(tester, const Size(390, 3600));

    // Tres vistas de la misma cuenta en la misma pantalla: los chips de «Carga
    // total» (`producto ×n`), la cifra de `empaques` del pre-despacho y el
    // subtotal del producto en la tabla nueva. Si se separan, el almacén ve 20 en
    // un sitio y 19 en el otro.
    final tarjetas = losTextos(
      tester,
      find.byKey(PorProductoYFactura.claveDeLasTarjetas),
    );
    for (final (producto, cantidad) in _cargaTotal) {
      expect(find.text('$producto ×$cantidad'), findsOneWidget);
      final tarjeta = find.byKey(PreDespacho.claveDeLaTarjeta(producto));
      expect(
        find.descendant(
          of: tarjeta,
          matching: find.textContaining(
            '$cantidad empaque',
            findRichText: true,
          ),
        ),
        findsOneWidget,
        reason:
            '«Carga total» dice $producto ×$cantidad y la tabla de '
            'pre-despacho dice otra cosa de ese mismo producto',
      );
      // El subtotal es lo que va detrás del «Subtotal» del bloque del producto.
      final bloque = tarjetas.indexOf(producto);
      final subtotal = tarjetas.indexOf('Subtotal', bloque);
      expect(
        tarjetas[subtotal + 1],
        '$cantidad cant.',
        reason:
            '«Carga total» dice $producto ×$cantidad y su subtotal en «Por '
            'producto y factura» dice otra cosa',
      );
    }

    await desmontar(tester);
  });

  testWidgets('a 390 px la tabla es una TARJETA POR PRODUCTO y no se sale de la '
      'pantalla', (tester) async {
    await _sembrarLasFacturas(base);
    await pintar(tester, const Size(390, 3600));

    expect(find.byKey(PorProductoYFactura.claveDeLasTarjetas), findsOneWidget);
    expect(find.byKey(PorProductoYFactura.claveDeLaTabla), findsNothing);

    final tarjetas = find.byKey(PorProductoYFactura.claveDeLasTarjetas);
    // El producto una vez, de encabezado; debajo cada factura con sus cifras, y
    // cada cifra con su rótulo pegado: sin cabecera de columna es lo que dice qué
    // es cada número.
    expect(losTextos(tester, tarjetas), _lasTarjetasDeAmado);

    // Nada se sale por el lado: un número recortado contra el borde no se lee.
    expect(tester.getRect(tarjetas).right, lessThanOrEqualTo(390));

    await desmontar(tester);
  });

  testWidgets('a 390 px se llega al final: el último subtotal se ve', (
    tester,
  ) async {
    await _sembrarLasFacturas(base);
    await pintar(tester, const Size(390, 844));

    // Como en `mapa_de_la_ruta_test`: se arrastra por el borde y no por el
    // centro, que cae sobre el mapa y se queda el gesto. Lo que se vigila es lo
    // mismo que allí: que al final del detalle SE LLEGA, y ahora el final es la
    // tabla nueva, no «Carga total».
    final ultimo = find.descendant(
      of: find.byKey(PorProductoYFactura.claveDeLasTarjetas),
      matching: find.text('Subtotal'),
    );
    bool seVe() {
      if (ultimo.evaluate().length < _cargaTotal.length) return false;
      final donde = tester.getRect(ultimo.last);
      return donde.bottom <= 844 && donde.top >= 0;
    }

    for (var i = 0; i < 40 && !seVe(); i++) {
      await tester.dragFrom(const Offset(382, 700), const Offset(0, -200));
      await tester.pump();
    }
    expect(seVe(), isTrue, reason: 'el final de la tabla no se alcanza');

    await desmontar(tester);
  });

  testWidgets('una ruta SIN paradas no inventa facturas ni deja imprimir una '
      'hoja en blanco', (tester) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: _ahora);
    await pintar(tester, const Size(1440, 2400));

    expect(find.text(PreDespacho.subtituloVacio), findsOneWidget);
    expect(find.byKey(PorProductoYFactura.claveDeLaTabla), findsNothing);
    expect(find.byKey(PorProductoYFactura.claveDeLasTarjetas), findsNothing);
    final boton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(claveDeVerEImprimirElPreDespacho),
        matching: find.byType(FilledButton),
      ),
    );
    expect(boton.onPressed, isNull);

    await desmontar(tester);
  });

  testWidgets('LLEGA LA BAJADA: los renglones que entran DESPUÉS de montar '
      'aparecen sin volver a abrir (el §3-ter)', (tester) async {
    // Montar con la base SIN renglones y sembrarlos DESPUÉS, sin remontar: es
    // lo que pasa en la web, donde `orders` baja antes que `order_items`. Con un
    // `Future` la pantalla se quedaba en «Sin productos» para siempre.
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: _ahora);
    await _sembrarLosPedidos(base);
    await pintar(tester, const Size(1440, 2400));

    expect(find.text(PreDespacho.subtituloVacio), findsOneWidget);
    expect(find.text('Cerv 500'), findsNothing);

    await _sembrarLosRenglones(base);
    await asentar(tester);

    expect(find.text(PreDespacho.subtituloVacio), findsNothing);
    expect(losTextos(tester, find.byKey(PorProductoYFactura.claveDeLaTabla)), [
      for (final fila in _laTablaDeAmado) ...fila,
    ]);

    await desmontar(tester);
  });

  testWidgets('«Ver e imprimir» abre la hoja y la hoja lleva la tabla «Por '
      'producto y factura» con lo MISMO que la pantalla, en el mismo orden', (
    tester,
  ) async {
    await _sembrarLasFacturas(base);
    await pintar(tester, const Size(1440, 2400));

    final renglones = await elPapel(tester);

    // EL PAPEL DICE, FILA A FILA, LO QUE DICE LA PANTALLA. Las celdas se leen en
    // el papel como un renglón (el PDF las dibuja a la misma altura); la cabecera
    // va en versalitas.
    expect(renglones, contains('POR PRODUCTO Y FACTURA'));
    expect(renglones, contains('FACTURA PRODUCTO CANT. KG'));
    expect(laTablaEnElPapel(renglones, _laTablaDeAmado), [
      for (final fila in _laTablaDeAmado.skip(1))
        fila.where((c) => c.isNotEmpty).join(' '),
    ], reason: 'el papel:\n${renglones.join('\n')}');

    await desmontar(tester);
  });

  testWidgets(
    'en pareja: la factura con número sale con su número, y el pedido '
    'SIN factura sale «Sin número» AL FINAL de su producto, en la pantalla y en '
    'el papel; su folio NO hace de factura',
    (tester) async {
      await _sembrarLasFacturas(base);
      await _sembrarUnoSinFactura(base);
      await pintar(tester, const Size(1440, 2400));

      final tabla = losTextos(
        tester,
        find.byKey(PorProductoYFactura.claveDeLaTabla),
      );
      expect(
        tabla,
        [for (final fila in _laTablaConUnoSinFactura) ...fila],
        reason:
            'con número por número y los «Sin número» al final de su producto, '
            'aunque sea la primera parada',
      );
      expect(
        tabla,
        isNot(contains(_folioSinFactura)),
        reason: 'el folio salió como número de factura',
      );
      expect(
        tabla.where((t) => t.startsWith('PTB25-')),
        isEmpty,
        reason: 'un folio salió en la columna de la factura',
      );

      final renglones = await elPapel(tester);
      expect(laTablaEnElPapel(renglones, _laTablaConUnoSinFactura), [
        for (final fila in _laTablaConUnoSinFactura.skip(1))
          fila.where((c) => c.isNotEmpty).join(' '),
      ], reason: 'el papel:\n${renglones.join('\n')}');
      expect(
        renglones.where((r) => r.contains('PTB25-')),
        isEmpty,
        reason: 'un folio salió en el papel como número de factura',
      );

      await desmontar(tester);
    },
  );

  // ---------------------------------------------------------------------------
  // LAS ATADURAS: dos caminos al mismo papel, y una tabla que cuadra con otra
  // ---------------------------------------------------------------------------
  group('las ataduras', () {
    late ProviderContainer contenedor;

    setUp(() {
      contenedor = ProviderContainer(
        overrides: [baseProvider.overrideWithValue(base)],
      );
    });
    tearDown(() => contenedor.dispose());

    /// El pre-despacho de `R1`, esperando a que llegue. Un `listen` mantiene vivo
    /// el provider `autoDispose` mientras se espera.
    Future<PreDespachoDeLaRuta> laDeLaRuta() {
      final c = Completer<PreDespachoDeLaRuta>();
      final sub = contenedor.listen(preDespachoDeLaRutaProvider('R1'), (
        _,
        ahora,
      ) {
        if (ahora.hasValue && !c.isCompleted) c.complete(ahora.requireValue);
      }, fireImmediately: true);
      addTearDown(sub.close);
      return c.future.timeout(const Duration(seconds: 10));
    }

    test(
      'LA RUTA ARMADA A MANO Y LA QUE SALE DEL TABLERO dan el mismo '
      'pre-despacho: por el asistente y por el detalle es la misma suma',
      () async {
        // Local: no hay dos tipos de ruta. Las dos acaban siendo pedidos con
        // `route_id`, y lo que cambiaba era DÓNDE se enseñaba. Lo que se ata es que
        // el camino del asistente (la ruta que se va a armar, por ids) y el del
        // detalle (la ruta ya armada, por sus paradas) lleguen a lo mismo.
        await _sembrarLasFacturas(base);

        final delAsistente = await contenedor.read(
          preDespachoDeLoElegidoEnElAsistenteProvider('o1,o2,o3,o4').future,
        );
        final deLaRuta = await laDeLaRuta();

        expect(
          _comoTexto(deLaRuta.totales),
          _comoTexto(delAsistente),
          reason:
              'el pre-despacho de la ruta y el del asistente dicen cosas '
              'distintas con los mismos pedidos: son DOS papeles para el mismo '
              'almacén',
        );

        // Y la hoja que se imprime por cada camino es la misma, línea a línea.
        final hojaAsistente = hojaDePreDespachoDeLaRuta(
          totales: delAsistente,
          sucursal: 'Camagüey',
          vehiculo: 'Camión 1',
          dia: null,
          pedidos: 4,
          pesoKg: 200,
        );
        final hojaRuta = hojaDePreDespachoDeLaRuta(
          totales: deLaRuta.totales,
          sucursal: 'Camagüey',
          vehiculo: 'Camión 1',
          dia: null,
          pedidos: 4,
          pesoKg: 200,
          facturas: deLaRuta.facturas,
        );
        String linea(papel.LineaPreDespacho l) =>
            '${l.producto}|${l.formatos}|${l.unidades}|${l.pesoKg}|'
            '${l.lineasSinUnidades}|${l.lineasSinPeso}';
        expect(
          hojaRuta.lineas.map(linea).toList(),
          hojaAsistente.lineas.map(linea).toList(),
        );
        // Lo único que la hoja de la ruta tiene de más es la tabla nueva.
        expect(hojaAsistente.facturas, isEmpty);
        expect(hojaRuta.facturas, hasLength(4));
      },
    );

    for (final conUnoSinFactura in [false, true]) {
      test('LA SUMA DE LOS SUBTOTALES POR PRODUCTO ES LA «CARGA TOTAL»: cada '
          'producto, en cantidad y en kg'
          '${conUnoSinFactura ? ', también con un renglón sin peso (≥)' : ''}', () async {
        await _sembrarLasFacturas(base);
        if (conUnoSinFactura) await _sembrarUnoSinFactura(base);
        final pre = await laDeLaRuta();

        final subtotales = filasPorProductoYFactura(
          lineasDelPapel(pre.totales),
          pre.facturas,
        ).where((f) => f.subtotal).toList();
        expect(subtotales, hasLength(pre.totales.lineas.length));

        num cifra(String celda) => num.parse(celda.replaceFirst('≥ ', ''));
        // Bloque a bloque, en el orden de la tabla de arriba: el subtotal de cada
        // producto es su fila de arriba, y el `≥` sale si y sólo si arriba falta
        // algún renglón.
        for (final (i, linea) in pre.totales.lineas.indexed) {
          final celdas = subtotales[i].celdas;
          expect(cifra(celdas[2]), linea.empaques, reason: linea.producto);
          expect(cifra(celdas[3]), linea.pesoKg, reason: linea.producto);
          expect(
            celdas[3].startsWith('≥'),
            !linea.pesoCompleto,
            reason: linea.producto,
          );
        }
        // Y sumados, la «Carga total» entera: 42 blister y 190 kg de la hoja de
        // Amado (43 con el arroz sin factura, que no pesa nada que se sepa).
        expect(
          subtotales.fold<num>(0, (t, f) => t + cifra(f.celdas[2])),
          pre.totales.empaques,
        );
        expect(pre.totales.empaques, conUnoSinFactura ? 43 : 42);
        expect(
          subtotales.fold<num>(0, (t, f) => t + cifra(f.celdas[3])),
          pre.totales.pesoKg,
        );
        expect(pre.totales.pesoKg, 190);
      });
    }

    test('las facturas salen por NÚMERO DE FACTURA, no por el orden de las '
        'paradas', () async {
      await _sembrarLasFacturas(base);
      final pre = await laDeLaRuta();

      // `o2` (46228) es la PRIMERA parada y va segunda.
      expect(pre.facturas.map((f) => f.numero), [
        '46226',
        '46228',
        '46229',
        '46230',
      ]);
    });

    test(
      'la que no tiene número va al FINAL y sin número: no cae al folio',
      () async {
        await _sembrarLasFacturas(base);
        await _sembrarUnoSinFactura(base);
        final pre = await laDeLaRuta();

        // `o5` es la PRIMERA parada (orden -1) y va la última.
        expect(pre.facturas.map((f) => f.numero), [
          '46226',
          '46228',
          '46229',
          '46230',
          null,
        ]);
        expect(pre.facturas.last.rotulo, 'Sin número');
      },
    );
  });
}

/// El pre-despacho de la pantalla como texto comparable.
String _comoTexto(TotalesPreDespacho t) {
  final lineas = t.lineas.map(
    (l) =>
        '${l.producto}|${l.empaques}|${l.unidades}|${l.pesoKg}|'
        '${l.lineasSinUnidades}|${l.lineasSinPeso}',
  );
  return '${t.pedidos} pedidos · ${t.pesoDeLosPedidos} kg\n${lineas.join('\n')}';
}
