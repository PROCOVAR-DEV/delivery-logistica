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
//  * la tabla «Por factura» cuadra con la de producto a producto (la suma de las
//    facturas es la tabla de arriba);
//  * «Carga total», que se queda, dice lo mismo que la tabla;
//  * lo que se ve en la pantalla es lo que se imprime.
//
// Los números de los pedidos están sacados a mano, a propósito: una prueba que
// los calculara con el código que prueba comprobaría la cuenta contra sí misma.
//
// LOS DATOS (dos facturas, el ejemplo de Amado: 10 blister de MALTA en cada una):
//
//   F-100  MALTA BLISTER 6U   10 blister   60 uds   50,0 kg
//          ARROZ 25KG          4 blister   40 uds  100,0 kg
//   F-200  MALTA BLISTER 6U   10 blister   60 uds   50,0 kg
//          VODKA REGIO         3 blister   18 uds   (sin peso)
//          ARROZ 25KG          2 blister   20 uds   50,0 kg
//
//   Por producto: MALTA 20 · ARROZ 6 · VODKA 3  =  29 blister, 198 uds,
//   ≥ 250,0 kg con 1 renglón sin peso.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/impresion/hoja.dart' as papel;
import 'package:reparto/impresion/por_factura.dart';
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
import 'package:reparto/pantallas/rutas/vista/tabla_por_factura.dart';
import 'package:reparto/impresion/vista_previa.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../impresion/los_dos_pesos_del_pre_despacho_test.dart'
    show leerElPapel;
import '../pedidos/sembrar.dart';

final _ahora = DateTime(2026, 10, 14, 9, 0);

Future<void> _sembrarLasFacturas(BaseLocal base) async {
  await sembrarCatalogo(base);
  await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: _ahora);
  await _sembrarLosPedidos(base);
  await _sembrarLosRenglones(base);
}

Future<void> _sembrarLosPedidos(BaseLocal base) async {
  await sembrarPedido(
    base,
    id: 'o1',
    cliente: 'Ana',
    // La factura es el número de Ventra, no el folio: los dos distintos a
    // propósito para que la tabla «Por factura» no pueda salir del folio.
    folio: 'PTB25-261015-0001',
    facturaNumero: 'F-100',
    rutaId: 'R1',
    orden: 1,
    peso: 150,
  );
  // El segundo pedido va PRIMERO en la parada y SEGUNDO en la tabla: la tabla
  // se ordena por factura, no por parada.
  await sembrarPedido(
    base,
    id: 'o2',
    cliente: 'Beto',
    folio: 'PTB25-261015-0002',
    facturaNumero: 'F-200',
    rutaId: 'R1',
    orden: 0,
    peso: 100,
  );
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

  await r('r1', 'o1', 1, 'MALTA BLISTER 6U', 60, 10, 50);
  await r('r2', 'o1', 2, 'ARROZ 25KG', 40, 4, 100);
  await r('r3', 'o2', 1, 'MALTA BLISTER 6U', 60, 10, 50);
  await r('r4', 'o2', 2, 'ARROZ 25KG', 20, 2, 50);
  await r('r5', 'o2', 3, 'VODKA REGIO', 18, 3, null);
}

/// Lo que dice la tabla «Por factura» con los datos de arriba, escrito a mano.
/// La cabecera va primero.
const _laTablaDeAmado = <List<String>>[
  ['Factura', 'Producto', 'Blister', 'Unidades', 'Peso (kg)'],
  ['F-100', 'MALTA BLISTER 6U', '10', '60', '50.0'],
  ['F-100', 'ARROZ 25KG', '4', '40', '100.0'],
  ['F-100', 'Subtotal', '14', '100', '150.0'],
  ['F-200', 'MALTA BLISTER 6U', '10', '60', '50.0'],
  ['F-200', 'VODKA REGIO', '3', '18', '—'],
  ['F-200', 'ARROZ 25KG', '2', '20', '50.0'],
  // Una factura con un renglón sin peso: su subtotal es un MÍNIMO, y se dice.
  ['F-200', 'Subtotal', '15', '98', '≥ 100.0'],
  ['Total', '', '29', '198', '≥ 250.0'],
];

/// Un tercer pedido SIN `factura_numero` y con folio, que es la PRIMERA parada:
/// la tabla lo pone «Sin número» y AL FINAL. Ni cae al folio (`NumeroDeFactura`,
/// decisión de Jose) ni sube delante por ser la primera parada.
const _folioSinFactura = 'PTB25-261015-0003';

Future<void> _sembrarUnoSinFactura(BaseLocal base) async {
  await sembrarPedido(
    base,
    id: 'o3',
    cliente: 'Caro',
    folio: _folioSinFactura,
    facturaNumero: null,
    rutaId: 'R1',
    orden: -1,
    peso: 25,
  );
  await sembrarRenglon(
    base,
    id: 'r6',
    pedidoId: 'o3',
    linea: 1,
    producto: 'ARROZ 25KG',
    unidades: 10,
    empaques: 1,
    pesoLinea: 25,
  );
}

/// [_laTablaDeAmado] con el pedido sin factura: sus filas detrás de las de F-200 y
/// el total con su blister, sus unidades y sus kilos.
final _laTablaConUnoSinFactura = <List<String>>[
  ..._laTablaDeAmado.take(_laTablaDeAmado.length - 1),
  ['Sin número', 'ARROZ 25KG', '1', '10', '25.0'],
  ['Sin número', 'Subtotal', '1', '10', '25.0'],
  ['Total', '', '30', '208', '≥ 275.0'],
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

  /// Los textos de la tabla, en el orden en que se pintan.
  List<String> losTextos(WidgetTester tester, Finder dentroDe) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(of: dentroDe, matching: find.byType(Text)),
    ))
      t.data ?? '',
  ];

  // ---------------------------------------------------------------------------
  // LA PANTALLA
  // ---------------------------------------------------------------------------
  for (final ancho in [1440.0, 1024.0]) {
    testWidgets('a ${ancho.toInt()} px el detalle trae «Carga total», el '
        'pre-despacho y la tabla «Por factura» con las cifras de Amado', (
      tester,
    ) async {
      await _sembrarLasFacturas(base);
      await pintar(tester, Size(ancho, 2400));

      // «Carga total» SE MANTIENE (Amado: «la sección de Carga Total se
      // mantiene»).
      expect(find.text('Carga total'), findsOneWidget);
      expect(find.text('MALTA BLISTER 6U ×20'), findsOneWidget);

      // El pre-despacho de siempre, el del asistente.
      expect(find.text(PreDespacho.titulo), findsOneWidget);
      expect(find.byType(VistaPreDespacho), findsOneWidget);
      expect(find.text('Peso de los productos'), findsOneWidget);

      // Y la tabla nueva: UNA FILA POR (FACTURA, PRODUCTO), EN EL ORDEN DE LA
      // FACTURA. «10 y 10», no «20».
      expect(find.text(PorFactura.titulo), findsOneWidget);
      expect(find.byKey(PorFactura.claveDeLaTabla), findsOneWidget);
      expect(find.byKey(PorFactura.claveDeLasTarjetas), findsNothing);
      expect(losTextos(tester, find.byKey(PorFactura.claveDeLaTabla)), [
        for (final fila in _laTablaDeAmado) ...fila,
      ]);

      await desmontar(tester);
    });
  }

  testWidgets('«Carga total» y la tabla de producto a producto dicen lo mismo '
      'de cada producto', (tester) async {
    await _sembrarLasFacturas(base);
    // A 390 px el pre-despacho es una tarjeta por producto (con su clave), que es
    // donde se puede medir un producto suelto: la fila de un `DataTable` no es
    // un widget y no se deja buscar.
    await pintar(tester, const Size(390, 3200));

    // Dos vistas de la misma cuenta, una al lado de otra en la misma pantalla:
    // los chips de «Carga total» (`producto ×n`) y la cifra de `empaques` del
    // pre-despacho. Si se separan, el almacén ve 20 en un sitio y 19 en el otro.
    for (final (producto, empaques) in const [
      ('MALTA BLISTER 6U', '20'),
      ('ARROZ 25KG', '6'),
      ('VODKA REGIO', '3'),
    ]) {
      expect(find.text('$producto ×$empaques'), findsOneWidget);
      final tarjeta = find.byKey(PreDespacho.claveDeLaTarjeta(producto));
      expect(
        find.descendant(
          of: tarjeta,
          matching: find.textContaining(
            '$empaques empaque',
            findRichText: true,
          ),
        ),
        findsOneWidget,
        reason:
            '«Carga total» dice $producto ×$empaques y la tabla de '
            'pre-despacho dice otra cosa de ese mismo producto',
      );
    }

    await desmontar(tester);
  });

  testWidgets('a 390 px la tabla es una TARJETA POR FACTURA y no se sale de la '
      'pantalla', (tester) async {
    await _sembrarLasFacturas(base);
    await pintar(tester, const Size(390, 3200));

    expect(find.byKey(PorFactura.claveDeLasTarjetas), findsOneWidget);
    expect(find.byKey(PorFactura.claveDeLaTabla), findsNothing);

    final tarjetas = find.byKey(PorFactura.claveDeLasTarjetas);
    final textos = losTextos(tester, tarjetas);
    // El número de cada factura una vez, de encabezado, y no repetido en cada
    // renglón; el cliente debajo.
    expect(textos.where((t) => t == 'F-100'), hasLength(1));
    expect(textos.where((t) => t == 'F-200'), hasLength(1));
    expect(textos, containsAll(['Ana', 'Beto']));
    expect(textos.where((t) => t == 'Subtotal'), hasLength(2));
    // Cada cifra lleva su rótulo pegado: sin cabecera de columna es lo que dice
    // qué es cada número.
    expect(find.textContaining('10 blister', findRichText: true), findsWidgets);

    // Nada se sale por el lado: un número recortado contra el borde no se lee.
    expect(tester.getRect(tarjetas).right, lessThanOrEqualTo(390));

    await desmontar(tester);
  });

  testWidgets('a 390 px se llega al final: el total de la tabla se ve', (
    tester,
  ) async {
    await _sembrarLasFacturas(base);
    await pintar(tester, const Size(390, 844));

    // Como en `mapa_de_la_ruta_test`: se arrastra por el borde y no por el
    // centro, que cae sobre el mapa y se queda el gesto. Lo que se vigila es lo
    // mismo que allí: que al final del detalle SE LLEGA, y ahora el final es la
    // tabla nueva, no «Carga total».
    final total = find.textContaining('29 blister', findRichText: true);
    bool seVe() {
      if (total.evaluate().isEmpty) return false;
      final donde = tester.getRect(total.last);
      return donde.bottom <= 844 && donde.top >= 0;
    }

    for (var i = 0; i < 40 && !seVe(); i++) {
      await tester.dragFrom(const Offset(382, 700), const Offset(0, -200));
      await tester.pump();
    }
    expect(seVe(), isTrue, reason: 'el total de «Por factura» no se alcanza');

    await desmontar(tester);
  });

  testWidgets('una ruta SIN paradas no inventa facturas ni deja imprimir una '
      'hoja en blanco', (tester) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: _ahora);
    await pintar(tester, const Size(1440, 2400));

    expect(find.text(PreDespacho.subtituloVacio), findsOneWidget);
    expect(find.byKey(PorFactura.claveDeLaTabla), findsNothing);
    expect(find.byKey(PorFactura.claveDeLasTarjetas), findsNothing);
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
    expect(find.text('MALTA BLISTER 6U'), findsNothing);

    await _sembrarLosRenglones(base);
    await asentar(tester);

    expect(find.text(PreDespacho.subtituloVacio), findsNothing);
    expect(losTextos(tester, find.byKey(PorFactura.claveDeLaTabla)), [
      for (final fila in _laTablaDeAmado) ...fila,
    ]);

    await desmontar(tester);
  });

  testWidgets('«Ver e imprimir» abre la hoja y la hoja lleva la tabla «Por '
      'factura» con lo MISMO que la pantalla', (tester) async {
    await _sembrarLasFacturas(base);
    await pintar(tester, const Size(1440, 2400));

    await tester.tap(find.byKey(claveDeVerEImprimirElPreDespacho));
    await asentar(tester);

    final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
    final bytes = await vista.armar(PdfPageFormat.a4);
    final renglones = [for (final r in leerElPapel(bytes).renglones) r.texto];

    // EL PAPEL DICE, FILA A FILA, LO QUE DICE LA PANTALLA. Las celdas de la
    // tabla de arriba se leen en el papel como un renglón (el PDF las dibuja a la
    // misma altura); la cabecera va en versalitas.
    for (final fila in _laTablaDeAmado.skip(1)) {
      final esperado = fila.where((c) => c.isNotEmpty).join(' ');
      expect(
        renglones,
        contains(esperado),
        reason:
            'el papel no trae el renglón «$esperado» de la tabla «Por '
            'factura»:\n${renglones.join('\n')}',
      );
    }
    expect(renglones, contains('FACTURA PRODUCTO BLISTER UNIDADES PESO (KG)'));
    expect(renglones, contains('POR FACTURA'));

    await desmontar(tester);
  });

  testWidgets('un pedido SIN factura sale «Sin número» y AL FINAL, en la '
      'pantalla y en el papel; su folio NO hace de factura', (tester) async {
    await _sembrarLasFacturas(base);
    await _sembrarUnoSinFactura(base);
    await pintar(tester, const Size(1440, 2400));

    final tabla = losTextos(tester, find.byKey(PorFactura.claveDeLaTabla));
    expect(
      tabla,
      [for (final fila in _laTablaConUnoSinFactura) ...fila],
      reason:
          'con número por número y los «Sin número» al final, aunque sea la '
          'primera parada',
    );
    expect(
      tabla,
      isNot(contains(_folioSinFactura)),
      reason: 'el folio salió como número de factura',
    );

    await tester.tap(find.byKey(claveDeVerEImprimirElPreDespacho));
    await asentar(tester);
    final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
    final renglones = [
      for (final r in leerElPapel(
        await vista.armar(PdfPageFormat.a4),
      ).renglones)
        r.texto,
    ];
    final enElPapel = [
      for (final fila in _laTablaConUnoSinFactura.skip(1))
        fila.where((c) => c.isNotEmpty).join(' '),
    ];
    // Los renglones de «Por factura» en el papel, en el orden en que salen. Desde
    // su título: el pie de la tabla de arriba dice el mismo «Total».
    expect(
      renglones
          .skip(renglones.indexOf('POR FACTURA'))
          .where(enElPapel.contains)
          .toList(),
      enElPapel,
      reason: 'el papel:\n${renglones.join('\n')}',
    );
    expect(
      renglones.where((r) => r.contains(_folioSinFactura)),
      isEmpty,
      reason: 'el folio salió en el papel como número de factura',
    );

    await desmontar(tester);
  });

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
          preDespachoDeLoElegidoEnElAsistenteProvider('o1,o2').future,
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
          pedidos: 2,
          pesoKg: 250,
        );
        final hojaRuta = hojaDePreDespachoDeLaRuta(
          totales: deLaRuta.totales,
          sucursal: 'Camagüey',
          vehiculo: 'Camión 1',
          dia: null,
          pedidos: 2,
          pesoKg: 250,
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
        expect(hojaRuta.facturas, hasLength(2));
      },
    );

    test('LA SUMA DE LAS FACTURAS ES LA TABLA DE ARRIBA: cada producto y cada '
        'total', () async {
      await _sembrarLasFacturas(base);
      final pre = await laDeLaRuta();

      final filas = filasPorFactura(pre.facturas);
      final total = filas.last;
      expect(total.tipo, TipoDeFilaPorFactura.total);

      // Por producto: lo que suman las facturas es lo que dice la tabla.
      for (final producto in pre.totales.lineas) {
        var blister = 0.0;
        var unidades = 0.0;
        for (final f in pre.facturas) {
          for (final l in f.lineas.where(
            (l) => l.producto == producto.producto,
          )) {
            blister += l.formatos;
            unidades += l.unidades ?? 0;
          }
        }
        expect(blister, producto.empaques, reason: producto.producto);
        expect(unidades, producto.unidades ?? 0, reason: producto.producto);
      }

      // Y el total de la tabla nueva es el pie de la de arriba, escrito igual.
      final t = pre.totales;
      expect(total.celdas[2], '${t.empaques.toInt()}');
      expect(total.celdas[3], '${t.unidades!.toInt()}');
      expect(
        total.celdas[4],
        '≥ ${t.pesoKg!.toStringAsFixed(1)}',
        reason:
            'un renglón sin peso: la suma por factura tiene que seguir siendo '
            'un MÍNIMO, igual que la de arriba (`≥`), y no un total',
      );
      expect(t.sinPeso, 1);
    });

    test('las facturas salen por NÚMERO DE FACTURA, no por el orden de las '
        'paradas', () async {
      await _sembrarLasFacturas(base);
      final pre = await laDeLaRuta();

      // `o2` (F-200) es la PRIMERA parada y va segunda en la tabla.
      expect(pre.facturas.map((f) => f.numero), ['F-100', 'F-200']);
      expect(pre.facturas.map((f) => f.cliente), ['Ana', 'Beto']);
    });

    test(
      'la que no tiene número va al FINAL y sin número: no cae al folio',
      () async {
        await _sembrarLasFacturas(base);
        await _sembrarUnoSinFactura(base);
        final pre = await laDeLaRuta();

        // `o3` es la PRIMERA parada (orden -1) y va la última.
        expect(pre.facturas.map((f) => f.numero), ['F-100', 'F-200', null]);
        expect(pre.facturas.map((f) => f.cliente), ['Ana', 'Beto', 'Caro']);
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
