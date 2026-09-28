// EL PRE-DESPACHO EN UN TELÉFONO. Medido, no leído.
//
// El 22/09/2026, en el teléfono de Jose (1080x2340 físicos = 390 px lógicos), la
// hoja de pre-despacho de Pedidos era una tabla de escritorio metida en 390 px:
//
//  - de las cuatro columnas —Producto, Empaques, Unidades, kg— **sólo se veía
//    `Producto`**. Medido sobre el código de entonces: la tabla pedía 502.1 px
//    de ancho, `Empaques` empezaba en x=306.4, `Unidades` se cortaba contra el
//    borde (385.2 → 434.2) y **`kg` caía entera fuera, en x=473.5**. Una hoja de
//    pre-despacho sin las cantidades no sirve para nada;
//  - cada fila medía **76.0 px** para una sola línea de texto —el
//    `dataRowMaxHeight` de `temaDeTabla`—, así que cinco productos llenaban la
//    pantalla y hay veinticuatro;
//  - y el encabezado —«Pre-despacho de lo filtrado · 24 producto(s) · 23150
//    empaques · sin peso en los pedidos»— se partía en CUATRO líneas con el
//    botón «Ver e imprimir» encajado en medio.
//
// POR QUÉ ESTAS PRUEBAS MIDEN COORDENADAS. Un fallo de colocación no rompe
// ninguna consulta: el texto ESTÁ en el árbol, con su literal exacto, y
// `findsOneWidget` sale verde con la aplicación inservible. Lo único que
// distingue «se lee» de «está fuera de la pantalla» es `rect.right` contra el
// ancho del aparato.
//
// Y van EN PAREJA: a 390 px tarjetas, a 1440 px la tabla de siempre. Una prueba
// que sólo mira el teléfono se queda tan verde con un escritorio que ha perdido
// sus cuatro columnas.
//
// NADA DE DRIFT AQUÍ. Los `TotalesPreDespacho` se construyen a mano: dentro de
// un `testWidgets` una consulta de Drift **cuelga la prueba en vez de fallar**
// (`CLAUDE.md` §5), y lo que se mide aquí es sólo colocación.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/vista_pre_despacho.dart';

void main() {
  /// El teléfono de Jose en píxeles lógicos, y un escritorio ancho.
  const anchoDelTelefono = 390.0;
  const altoDelTelefono = 844.0;
  const anchoDeEscritorio = 1440.0;

  /// Nombres de producto de los de verdad: largos, en mayúsculas y sin ningún
  /// sitio cómodo por donde cortar. Son los de la captura de Jose.
  const malta = 'MALTA GUAJIRA 1500 ML BLISTER 6U';
  const cerveza = 'CERVEZA PARRANDA 500 ML BLISTER 6U';
  const vodka = 'VODKA REGIO BLISTER 6U';

  /// Sin ni un peso resuelto, que es lo que pasaba en la captura: el total de
  /// kg es `null` y la franja dice «sin peso en los pedidos», no «0.0 kg».
  final sinPeso = TotalesPreDespacho(
    const [
      LineaPreDespacho(producto: malta, empaques: 1234, unidades: null),
      LineaPreDespacho(producto: cerveza, empaques: 980, unidades: 5880),
      LineaPreDespacho(producto: vodka, empaques: 12, unidades: 72),
    ],
    pedidos: 24,
  );

  final conPeso = TotalesPreDespacho(
    const [
      LineaPreDespacho(producto: malta, empaques: 1234, unidades: 7404, pesoKg: 88.5),
      LineaPreDespacho(producto: cerveza, empaques: 980, unidades: 5880, pesoKg: 11.5),
    ],
    pedidos: 24,
  );

  /// LOS DIEZ PRODUCTOS DE PRODUCCIÓN, copiados de la hoja que QA sacó el
  /// 22/09/2026 (`qa-capturas/22-predespacho-1600.png`): los empaques suman
  /// **4887**, las unidades **34204**, ninguna línea tiene peso en el catálogo
  /// —la columna `kg` son diez guiones— y el peso de los PEDIDOS es
  /// **29835.4**. Ésa es la pantalla en la que tres cifras contestaban a la
  /// misma pregunta.
  final comoEnProduccion = TotalesPreDespacho(
    <LineaPreDespacho>[
      for (final linea in const <(String, int, int)>[
        ('MALTA GUAJIRA 1500 ML BLISTER 6U', 2179, 13074),
        ('MALTA GUAJIRA 330 ML BLISTER 6U', 1986, 11916),
        ('VODKA REGIO BLISTER 6U', 364, 2184),
        ('ARROZ RIVIERA 1 KG PACA 10U', 140, 1400),
        ('PAPEL HIGIENICO LIRIO 44 M PACA 12P DE 4U', 97, 4656),
        ('AZUCAR MORENA 1 KG PACA 10U', 89, 890),
        ('SOPA DE POLLO CAJA 72 P', 15, 14),
        ('SERVILLETA PROSITO PACA 24P', 6, 4),
        ('CREMA DE POLLO CAJA 72 P', 6, 6),
        ('DETERGENTE KAPITAL MULTIUSO 750 ML CAJA 12U', 5, 60),
      ])
        LineaPreDespacho(
          producto: linea.$1,
          empaques: linea.$2 * 1.0,
          unidades: linea.$3 * 1.0,
        ),
    ],
    pedidos: 295,
    pesoDeLosPedidos: 29835.4,
  );

  Future<void> pintar(
    WidgetTester tester,
    Widget hijo, {
    required double ancho,
  }) async {
    tester.view.physicalSize = Size(ancho, altoDelTelefono);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaDeReparto(),
        home: Scaffold(body: SingleChildScrollView(child: hijo)),
      ),
    );
    await tester.pump();
  }

  group('a 390 px —el teléfono de Jose—', () {
    testWidgets('los empaques se ven SIN desplazar de lado', (tester) async {
      await pintar(tester, TablaPreDespacho(totales: sinPeso), ancho: anchoDelTelefono);

      final caja = tester.getRect(find.text('1234 empaques'));
      expect(
        caja.right,
        lessThanOrEqualTo(anchoDelTelefono),
        reason:
            'Los empaques del primer producto llegan hasta '
            'x=${caja.right.toStringAsFixed(1)} en una pantalla de '
            '$anchoDelTelefono px: están fuera, como la columna `Empaques` de '
            'la captura del 22/09/2026 (empezaba en x=306.4 de una tabla de '
            '502.1 px).',
      );
      expect(caja.left, greaterThanOrEqualTo(0));
      // Ancha y baja: una cifra partida letra a letra sería al revés.
      expect(caja.width, greaterThan(caja.height));
    });

    testWidgets('las unidades también, incluso el `—`', (tester) async {
      await pintar(tester, TablaPreDespacho(totales: sinPeso), ancho: anchoDelTelefono);

      // La primera línea no tiene unidades en el catálogo: `—`, nunca un cero.
      final sinUnidades = tester.getRect(find.text('— unidades'));
      expect(sinUnidades.right, lessThanOrEqualTo(anchoDelTelefono));
      expect(sinUnidades.left, greaterThanOrEqualTo(0));

      final conUnidades = tester.getRect(find.text('5880 unidades'));
      expect(
        conUnidades.right,
        lessThanOrEqualTo(anchoDelTelefono),
        reason:
            'Las unidades llegan hasta x=${conUnidades.right.toStringAsFixed(1)}: '
            'la columna `Unidades` volvió a quedarse contra el borde.',
      );
    });

    testWidgets('los kg también, que eran los que caían del todo fuera', (
      tester,
    ) async {
      await pintar(tester, TablaPreDespacho(totales: conPeso), ancho: anchoDelTelefono);

      final caja = tester.getRect(find.text('88.5 kg'));
      expect(
        caja.right,
        lessThanOrEqualTo(anchoDelTelefono),
        reason:
            'Los kg llegan hasta x=${caja.right.toStringAsFixed(1)}. En la '
            'captura del 22/09/2026 la columna `kg` empezaba en x=473.5, o sea '
            '83 px POR FUERA de la pantalla.',
      );
      expect(caja.left, greaterThanOrEqualTo(0));
    });

    testWidgets('no hay tabla: ni `DataTable` ni rótulos de columna', (
      tester,
    ) async {
      await pintar(tester, TablaPreDespacho(totales: conPeso), ancho: anchoDelTelefono);

      expect(
        find.byType(DataTable),
        findsNothing,
        reason:
            'Sigue habiendo una tabla de escritorio metida en 390 px. Ninguna '
            'tabla cabe en un teléfono, por pocas columnas que tenga.',
      );
      // Los rótulos van pegados a cada cifra, no en una cabecera.
      expect(find.text('Producto'), findsNothing);
      expect(find.text('Empaques'), findsNothing);
    });

    testWidgets('una fila de una línea NO mide 76 px', (tester) async {
      await pintar(tester, TablaPreDespacho(totales: conPeso), ancho: anchoDelTelefono);

      final caja = tester.getRect(
        find.byKey(PreDespacho.claveDeLaTarjeta(malta)),
      );
      expect(
        caja.height,
        lessThan(64),
        reason:
            'Un producto ocupa ${caja.height.toStringAsFixed(1)} px. La fila de '
            'la tabla medía 76.0 px para una sola línea de texto, y con eso '
            'cinco productos llenaban la pantalla teniendo veinticuatro.',
      );
      // Y con ese alto caben los 24 de la captura en menos de cinco pantallas.
      expect(caja.height * 24, lessThan(altoDelTelefono * 5));
    });

    testWidgets('el nombre del producto no se parte letra a letra', (
      tester,
    ) async {
      await pintar(tester, TablaPreDespacho(totales: conPeso), ancho: anchoDelTelefono);

      final caja = tester.getRect(find.text(malta));
      expect(
        caja.width,
        greaterThan(caja.height),
        reason:
            '«$malta» mide ${caja.width.toStringAsFixed(1)} x '
            '${caja.height.toStringAsFixed(1)}: más alto que ancho es que está '
            'partido en vertical.',
      );
      expect(caja.right, lessThanOrEqualTo(anchoDelTelefono));
    });

    testWidgets('el encabezado del cajón NO se parte en cuatro líneas', (
      tester,
    ) async {
      // El cajón entero, que es donde vive ahora el encabezado.
      tester.view.physicalSize = const Size(anchoDelTelefono, altoDelTelefono);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaDeReparto(),
          home: CajonDePreDespacho(totales: sinPeso),
        ),
      );
      await tester.pump();

      final resumen = resumenDelPreDespacho(sinPeso);
      expect(
        resumen,
        '3 producto(s) · 2226 empaques · sin peso en los pedidos',
        reason:
            'El texto del 22/09/2026 se queda: nada de «0.0 kg» cuando falta '
            'algún producto por emparejar.',
      );

      final caja = tester.getRect(find.text(resumen));
      // Una línea de 12-13 px con su interlineado no pasa de 24 px de alto.
      // Cuatro líneas, que es lo que había, pasan de 80.
      expect(
        caja.height,
        lessThan(28),
        reason:
            'El encabezado mide ${caja.height.toStringAsFixed(1)} px de alto: '
            'está partido en varias líneas, como en la captura de Jose.',
      );
      expect(caja.right, lessThanOrEqualTo(anchoDelTelefono));

      // Y el `Ver e imprimir` sigue ahí, en el pie y entero.
      final boton = tester.getRect(find.text(PreDespacho.verEImprimir));
      expect(boton.width, greaterThan(boton.height));
      expect(boton.right, lessThanOrEqualTo(anchoDelTelefono));
    });
  });

  group('a 1440 px —el escritorio— sigue siendo la tabla de siempre', () {
    testWidgets('con sus cuatro rótulos de columna', (tester) async {
      await pintar(tester, TablaPreDespacho(totales: conPeso), ancho: anchoDeEscritorio);

      expect(find.byType(DataTable), findsOneWidget);
      for (final rotulo in ['Producto', 'Empaques', 'Unidades', 'kg']) {
        final caja = tester.getRect(find.text(rotulo));
        expect(
          caja.right,
          lessThanOrEqualTo(anchoDeEscritorio),
          reason: 'El rótulo «$rotulo» se sale: $caja',
        );
      }
    });

    testWidgets('y sus filas ya no miden 76 px', (tester) async {
      await pintar(tester, TablaPreDespacho(totales: conPeso), ancho: anchoDeEscritorio);

      final primera = tester.getRect(find.text(malta)).center.dy;
      final segunda = tester.getRect(find.text(cerveza)).center.dy;
      final alto = (segunda - primera).abs();
      expect(
        alto,
        lessThan(64),
        reason:
            'Una fila mide ${alto.toStringAsFixed(1)} px para una línea de '
            'texto. Medido el 22/09/2026 sobre el código de entonces: 76.0.',
      );
    });
  });

  // LOS DOS PESOS, QUE NO SON EL MISMO — 22/09/2026.
  //
  // Medido por QA en producción sobre la HOJA IMPRESA: la columna `kg` salía
  // «—» en las diez líneas y el renglón `Total` ponía **29835.4**. Los dos
  // números son ciertos y cuentan cosas distintas —el «—» es el peso por
  // producto, que el catálogo no sabe; el 29835.4 es el peso de los pedidos—,
  // pero en la misma columna, con la misma unidad y sin nada que lo diga, un
  // total debajo de diez guiones se lee como la suma de esos guiones.
  //
  // Esto vigila LA PANTALLA, que es lo que se podía tocar. **La hoja impresa no
  // se cambia**: es el punto de paridad con la de Next y va dicho en el informe.
  group('en la vista los dos pesos van separados y con su rótulo', () {
    testWidgets('el de los productos vale `—` cuando lo valen sus líneas', (
      tester,
    ) async {
      await pintar(
        tester,
        VistaPreDespacho(totales: comoEnProduccion),
        ancho: anchoDeEscritorio,
      );

      // Con las diez líneas sin peso, el total por producto NO inventa un
      // número: dice que no lo sabe y por qué.
      expect(
        find.text(TotalesDelPreDespacho.pesoDeLosProductos),
        findsOneWidget,
      );
      expect(find.text('sin peso en los pedidos'), findsOneWidget);
      // Y desde luego no sale el de los pedidos en ese renglón.
      expect(
        find.descendant(
          of: find.byType(TotalesDelPreDespacho),
          matching: find.text('29835.4 kg'),
        ),
        findsOneWidget,
        reason: 'El peso de los pedidos tiene que estar, pero en SU renglón.',
      );
    });

    testWidgets('el de los pedidos lleva su propio rótulo', (tester) async {
      await pintar(
        tester,
        VistaPreDespacho(totales: comoEnProduccion),
        ancho: anchoDeEscritorio,
      );

      final rotulo = tester.getRect(
        find.text(TotalesDelPreDespacho.pesoDeLosPedidos),
      );
      final productos = tester.getRect(
        find.text(TotalesDelPreDespacho.pesoDeLosProductos),
      );
      // Renglones distintos: si compartieran línea volverían a leerse como una
      // sola cuenta.
      expect(
        rotulo.top,
        greaterThan(productos.top),
        reason:
            'Los dos pesos están a la misma altura: ${productos.top} y '
            '${rotulo.top}. En la misma línea se vuelven a leer como uno.',
      );
      // Y se dice por qué no cuadran, que es lo que faltaba.
      expect(find.text(TotalesDelPreDespacho.porQueNoSuman), findsOneWidget);
    });

    testWidgets('los empaques y las unidades sí suman, y se dice', (
      tester,
    ) async {
      await pintar(
        tester,
        VistaPreDespacho(totales: comoEnProduccion),
        ancho: anchoDeEscritorio,
      );

      // Las cifras que QA comprobó en producción: 2179+1986+364+140+97+89+15+6+6+5.
      expect(find.text('4887'), findsOneWidget);
      expect(find.text('34204'), findsOneWidget);
    });

    testWidgets('a 390 px los cuatro rótulos caben sin salirse', (
      tester,
    ) async {
      await pintar(
        tester,
        VistaPreDespacho(totales: comoEnProduccion),
        ancho: anchoDelTelefono,
      );

      for (final texto in [
        'Empaques',
        'Unidades',
        TotalesDelPreDespacho.pesoDeLosProductos,
        TotalesDelPreDespacho.pesoDeLosPedidos,
      ]) {
        final caja = tester.getRect(find.text(texto));
        expect(
          caja.right,
          lessThanOrEqualTo(anchoDelTelefono),
          reason: '«$texto» llega hasta x=${caja.right.toStringAsFixed(1)}.',
        );
        expect(caja.width, greaterThan(caja.height), reason: texto);
      }
    });
  });

  group('lo que dicen los rótulos', () {
    test('el botón lleva dentro lo que hay contado', () {
      // Sin nada sumado no se inventa un número.
      expect(rotuloDelPreDespacho(null), 'Pre-despacho');
      expect(rotuloDelPreDespacho(conPeso), 'Pre-despacho · 2 productos');
    });

    test('el peso a medias no se suma: se dice cuántos faltan', () {
      expect(pesoDelPreDespacho(conPeso), '100.0 kg');
      expect(pesoDelPreDespacho(sinPeso), 'sin peso en los pedidos');
      // Y con algunos resueltos y otros no, dice cuántos.
      final aMedias = TotalesPreDespacho(const [
        LineaPreDespacho(producto: malta, empaques: 1, unidades: 1, pesoKg: 2),
        LineaPreDespacho(producto: cerveza, empaques: 1, unidades: 1),
      ]);
      expect(pesoDelPreDespacho(aMedias), '1 de 2 productos sin peso');
    });
  });
}
