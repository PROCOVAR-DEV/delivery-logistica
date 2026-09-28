/// Que las dos hojas salgan **sin red** y con los numeros que tienen que salir.
///
/// La prueba fuerte de este fichero es `sin red`: se tumba la pila de HTTP del
/// proceso entero y se genera el PDF igual. Si algun dia alguien cambia Roboto
/// por `PdfGoogleFonts`, esto revienta aqui y no en el patio de un almacen de
/// Camagüey con el camion cargado.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/impresion/armar_post_despacho.dart';
import 'package:reparto/impresion/estilo.dart';
import 'package:reparto/impresion/hoja.dart';
import 'package:reparto/impresion/post_despacho.dart';
import 'package:reparto/impresion/pre_despacho.dart';

/// Una pila de HTTP que no deja pasar nada. Cualquier intento de salir a la red
/// —bajar una fuente, pedir un icono— revienta con un mensaje que se entiende.
class _SinRed extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('la hoja intentó salir a la red');
}

final DateTime _impresoEn = DateTime(2026, 9, 14, 17, 20, 30);

HojaPreDespacho _pre({List<LineaPreDespacho>? lineas, String? dia}) =>
    HojaPreDespacho(
      sucursal: 'Camagüey',
      vehiculo: 'Camión #1',
      dia: dia,
      pedidos: 7,
      pesoKg: 412.5,
      lineas:
          lineas ??
          const <LineaPreDespacho>[
            LineaPreDespacho(
              producto: 'Arroz',
              formatos: 18,
              unidades: 360,
              pesoKg: 180,
            ),
            LineaPreDespacho(
              producto: 'Azúcar',
              formatos: 12,
              unidades: 240,
              pesoKg: 120,
            ),
            LineaPreDespacho(
              producto: 'Etiquetas',
              formatos: 2,
              unidades: 200,
              pesoKg: 0,
            ),
          ],
    );

HojaPostDespacho _post() => armarPostDespacho(
  const DatosDeRuta(
    ruta: 'R-014',
    sucursal: 'Camagüey',
    vehiculo: 'Camión #1',
    salida: '14/9/2026, 7:30:00',
    regreso: '14/9/2026, 15:05:00',
  ),
  const <PedidoDeRuta>[
    PedidoDeRuta(
      customerName: 'Bodega La Plaza',
      resultado: 'entregado',
      items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 10)],
    ),
    PedidoDeRuta(
      customerName: 'Cafetería El Puente',
      resultado: 'devuelto',
      resultadoNota: 'Cerrado, nadie recibió',
      items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 6)],
    ),
    PedidoDeRuta(
      customerName: 'Mercado Sur',
      items: <ItemDePedido>[ItemDePedido(name: 'Azúcar', packs: 9)],
    ),
  ],
);

/// El PDF comprime los flujos de dibujo, pero los diccionarios de objetos van en
/// claro: por ahi se puede comprobar el papel y la fuente sin rasterizar nada.
String _enClaro(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

int _paginas(String claro) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(claro).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la hoja se arma SIN RED', () {
    test('el pre-despacho sale con la pila de HTTP tumbada', () async {
      final bytes = await HttpOverrides.runZoned(
        () => pdfPreDespacho(_pre(), impresoEn: _impresoEn),
        createHttpClient: (SecurityContext? c) =>
            throw StateError('la hoja intentó salir a la red'),
      );
      expect(bytes, isNotEmpty);
      expect(_enClaro(bytes.take(5).toList()), '%PDF-');
    });

    test('el post-despacho también', () async {
      final bytes = await HttpOverrides.runZoned(
        () => pdfPostDespacho(_post(), impresoEn: _impresoEn),
        createHttpClient: (SecurityContext? c) =>
            throw StateError('la hoja intentó salir a la red'),
      );
      expect(bytes, isNotEmpty);
      expect(_enClaro(bytes.take(5).toList()), '%PDF-');
    });

    test('y con la pila tumbada para TODO el proceso, no solo para la zona', () async {
      // `runZoned` solo tapa lo que ocurra dentro de la zona; esto tapa tambien
      // lo que se haya quedado colgando de otra.
      final antes = HttpOverrides.current;
      HttpOverrides.global = _SinRed();
      addTearDown(() => HttpOverrides.global = antes);

      // Y sin la cache de fuentes: la primera carga es la que bajaria la fuente.
      olvidarFuentes();

      final pre = await pdfPreDespacho(_pre(), impresoEn: _impresoEn);
      final post = await pdfPostDespacho(_post(), impresoEn: _impresoEn);
      expect(pre, isNotEmpty);
      expect(post, isNotEmpty);
    });
  });

  group('la fuente va EMBEBIDA en el fichero', () {
    late String claro;

    setUpAll(() async {
      claro = _enClaro(await pdfPreDespacho(_pre(), impresoEn: _impresoEn));
    });

    test('el PDF lleva dentro el fichero de la fuente', () {
      // `FontFile2` es como el PDF llama a un TrueType incrustado. Si la fuente
      // fuera de sistema o de red, aqui no habria ninguno.
      expect(claro, contains('/FontFile2'));
      expect(claro, contains('Roboto'));
    });

    test('las dos fuentes salen del propio paquete, no de la red', () async {
      // El origen es el `rootBundle`: ficheros que viajan dentro del APK.
      expect(
        (await rootBundle.load(rutaRegular)).lengthInBytes,
        greaterThan(1000),
      );
      expect(
        (await rootBundle.load(rutaNegrita)).lengthInBytes,
        greaterThan(1000),
      );
    });

    test('nadie dejó una URL de Google Fonts dentro del PDF', () {
      expect(claro, isNot(contains('fonts.gstatic')));
      expect(claro, isNot(contains('fonts.googleapis')));
    });
  });

  group('el papel es el que se imprime, no el de pantalla', () {
    test('A4 con 12 mm de margen', () async {
      // 12 mm en puntos: 12 * 72/25.4 = 34.0157…
      expect(hojaA4.marginLeft, closeTo(34.0157, 0.001));
      expect(hojaA4.marginTop, closeTo(34.0157, 0.001));
      expect(hojaA4.width, PdfPageFormat.a4.width);
      expect(hojaA4.height, PdfPageFormat.a4.height);

      final claro = _enClaro(
        await pdfPreDespacho(_pre(), impresoEn: _impresoEn),
      );
      expect(claro, contains('/MediaBox'));
    });

    test('la columna de marcar a mano tiene ancho de verdad', () {
      // 70 px y 78 px del HTML: 18.5 mm y 20.6 mm. Sin esto la columna se
      // cierra y no cabe el numero que hay que escribir dentro.
      expect(anchoSacado.width, closeTo(18.5 * PdfPageFormat.mm, 0.001));
      expect(anchoBajo.width, closeTo(20.6 * PdfPageFormat.mm, 0.001));
      expect(anchoSacado.width, greaterThan(50)); // > 17 mm, da para un numero
    });

    test('una hoja larga pasa de página sin romperse', () async {
      final muchas = <LineaPreDespacho>[
        for (var i = 0; i < 120; i++)
          LineaPreDespacho(
            producto: 'Producto número $i con nombre largo de almacén',
            formatos: i + 1,
            unidades: (i + 1) * 20,
            pesoKg: (i + 1) * 1.5,
          ),
      ];
      final claro = _enClaro(
        await pdfPreDespacho(_pre(lineas: muchas), impresoEn: _impresoEn),
      );
      expect(_paginas(claro), greaterThan(1));
    });
  });

  group('los totales que se imprimen son los que cuadran el camión', () {
    test('el pre-despacho suma empaques y unidades de todas las líneas', () {
      final t = TotalesPreDespacho.de(_pre());
      expect(t.formatos, 32); // 18 + 12 + 2
      expect(t.unidades, 800); // 360 + 240 + 200
    });

    // EL PESO DE LOS PRODUCTOS Y EL DE LOS PEDIDOS SON DOS CUENTAS —
    // 23/09/2026. Aquí se imprimía `d.pesoKg` —el peso de los PEDIDOS— en el
    // pie de la columna de pesos por PRODUCTO, copiando a la de Next. La suma
    // por producto da 300 y el de los pedidos 412.5, y nada en el papel lo
    // decía. El porqué entero está en `TotalesPreDespacho` (`hoja.dart`); que
    // salgan en dos renglones rotulados lo sujeta
    // `los_dos_pesos_del_pre_despacho_test.dart`.
    test('el peso de los productos y el de los pedidos son dos campos', () {
      final h = _pre();
      final suma = h.lineas.fold<num>(0, (t, l) => t + (l.pesoKg ?? 0));
      expect(suma, 300);

      final t = TotalesPreDespacho.de(h);
      expect(t.pesoDeLosPedidos, 412.5);
      // `Etiquetas` viene a cero, que es lo que la columna imprime como «—»:
      // esa celda no entra en la suma, así que el total es el de las otras
      // dos —300— y **es un mínimo**. Hasta el 28/09/2026 aquí no salía
      // ningún número, y con esa regla la hoja de producción se quedaba en
      // blanco: de los 129 productos de Ventra sólo 57 traen peso.
      expect(t.pesoDeLosProductos, 300, reason: '180 + 120, sin las etiquetas');
      expect(
        t.pesoCompleto,
        isFalse,
        reason:
            'es lo que hace que el papel escriba `≥ 300.0`. En `true` esos '
            '300 kg se firman como el peso entero de la hoja',
      );
      expect(t.sinPeso, 1, reason: 'el renglón de las etiquetas');
      expect(t.productos, 3);
      // Y los dos siguen siendo dos cuentas distintas: 300 contra 412.5.
      expect(t.pesoDeLosProductos, isNot(t.pesoDeLosPedidos));
    });

    test('un producto sin peso imprime una raya, no un cero', () {
      expect(pesoDeFila(0), '—');
      // Y lo que NO se sabe también: `null` no es cero, pero en el papel se
      // lee igual de mal si se imprime un número.
      expect(pesoDeFila(null), '—');
      expect(pesoDeFila(12), '12.0');
      // En el total el cero sí se escribe: es una cifra, no un hueco.
      expect(pesoTotal(0), '0.0');
      expect(pesoTotal(412.5), '412.5');
    });

    // LAS UNIDADES QUE NO SE SABEN TAMBIÉN SON UNA RAYA — 22/09/2026.
    //
    // La hoja decía «SERVILLETA PROSITO PACA 24P · 7 empaques · 4 unidades»:
    // cuatro unidades dentro de siete pacas. Venía de imprimir `SUM(quantity)`,
    // que unas veces trae unidades y otras repite los bultos. Con esta hoja se
    // baja al almacén a sacar mercancía.
    test('las unidades que no se saben imprimen una raya, no un número', () {
      expect(cantidadDeFila(null), '—');
      expect(cantidadDeFila(0), '0');
      expect(cantidadDeFila(1080), '1080');
    });

    // UN TOTAL A MEDIAS NO SE DISTINGUE DE UNO COMPLETO — G3 del auditor,
    // 22/09/2026. Se mutó `_sumaCompleta` para que sumara lo que sabe e
    // ignorara lo que no, y las 105 pruebas siguieron verdes. Con ESTA hoja
    // alguien baja al almacén a sacar mercancía: un total corto se carga de
    // menos y no se descubre hasta que el camión ya se fue.
    test('con TODAS las unidades sabidas, el total es la suma de las líneas', () {
      final h = _pre(
        lineas: const <LineaPreDespacho>[
          LineaPreDespacho(producto: 'Arroz', formatos: 18, unidades: 360, pesoKg: 180),
          LineaPreDespacho(producto: 'Azúcar', formatos: 12, unidades: 240, pesoKg: 120),
          LineaPreDespacho(producto: 'Etiquetas', formatos: 2, unidades: 200, pesoKg: 0),
        ],
      );
      final t = TotalesPreDespacho.de(h);
      expect(t.unidades, 800); // 360 + 240 + 200
      expect(cantidadDeFila(t.unidades), '800');
    });

    test('con UNA sola línea sin saber, el pie sale con `≥` y NUNCA desnudo', () {
      final h = _pre(
        lineas: const <LineaPreDespacho>[
          LineaPreDespacho(producto: 'Arroz', formatos: 18, unidades: 360, pesoKg: 180),
          LineaPreDespacho(producto: 'Azúcar', formatos: 12, unidades: 240, pesoKg: 120),
          // Ésta no se sabe: el catálogo no dice cuántas unidades trae la paca.
          LineaPreDespacho(producto: 'Servilleta paca 24p', formatos: 7, unidades: null, pesoKg: 3),
        ],
      );
      final t = TotalesPreDespacho.de(h);

      // Esta prueba exigía `null` y una raya en el papel. El 28/09/2026 se
      // midió lo que costaba: la raya se comía filas enteras de la hoja
      // —4.949 empaques de MALTA GUAJIRA por 21 renglones de 1.149— y no era
      // pasajero, que de 129 productos de Ventra sólo 57 traen peso. Lo que
      // sale ahora es la suma de lo que se sabe MARCADA COMO MÍNIMO; lo que no
      // puede salir, ni entonces ni ahora, es `600` a secas.
      expect(t.unidades, 600, reason: '360 + 240, y la paca fuera');
      expect(t.unidadesCompletas, isFalse);
      expect(t.sinUnidades, 1);

      // Y lo que de verdad importa: lo que sale IMPRESO en el pie de la hoja.
      final enElPapel = conMinimo(
        cantidadDeFila(t.unidades),
        completo: t.unidadesCompletas,
      );
      expect(
        enElPapel,
        '≥ 600',
        reason:
            'En el pie de la hoja del almacén salió «$enElPapel». Sin el `≥` '
            'ese 600 es el total, y le falta una línea: se saca de menos y no '
            'se descubre hasta que el camión se fue.',
      );
      expect(
        enElPapel,
        isNot('600'),
        reason: 'ése es el total PARCIAL vendido como completo',
      );
      expect(
        enElPapel.startsWith('≥'),
        isTrue,
        reason: 'la marca va DELANTE de la cifra, que es donde se lee',
      );
    });

    // LA PAREJA DEL `≥`: si saliera siempre, no distinguiría nada — 28/09/2026.
    test('con TODO sabido el pie va desnudo, sin `≥`', () {
      final t = TotalesPreDespacho.de(_pre(
        lineas: const <LineaPreDespacho>[
          LineaPreDespacho(producto: 'Arroz', formatos: 18, unidades: 360, pesoKg: 180),
          LineaPreDespacho(producto: 'Azúcar', formatos: 12, unidades: 240, pesoKg: 120),
        ],
      ));
      expect(t.sinUnidades, 0);
      expect(t.sinPeso, 0);
      expect(
        conMinimo(cantidadDeFila(t.unidades), completo: t.unidadesCompletas),
        '600',
        reason:
            'Éstas son las 600 unidades de verdad. Un `≥` aquí es un aviso '
            'que sale siempre, y un aviso que sale siempre deja de leerse.',
      );
      expect(
        conMinimo(pesoDeFila(t.pesoDeLosProductos), completo: t.pesoCompleto),
        '300.0',
      );
    });

    test('sin saber NADA se queda la raya, y sin `≥` delante', () {
      // `≥ —` no es nada, y `≥ 0.0` es peor: es el «0.0 kg» del 22/09/2026 con
      // un símbolo delante. Cuando no se sabe nada se dice que no se sabe.
      final t = TotalesPreDespacho.de(_pre(
        lineas: const <LineaPreDespacho>[
          LineaPreDespacho(producto: 'Servilleta paca 24p', formatos: 7, unidades: null, pesoKg: null),
          LineaPreDespacho(producto: 'Vodka regio', formatos: 3, unidades: null, pesoKg: null),
        ],
      ));
      expect(t.unidades, isNull);
      expect(t.pesoDeLosProductos, isNull);
      expect(
        conMinimo(cantidadDeFila(t.unidades), completo: t.unidadesCompletas),
        '—',
      );
      expect(
        conMinimo(pesoDeFila(t.pesoDeLosProductos), completo: t.pesoCompleto),
        '—',
      );
    });

    test('los números se escriben como en la de Next: 5, no 5.0', () {
      expect(numero(5), '5');
      expect(numero(5.0), '5');
      expect(numero(5.5), '5.5');
    });

    test('el post-despacho suma solo las filas que se imprimen', () {
      final h = _post();
      final t = TotalesPostDespacho.de(h);
      expect(h.lineasConResto.map((l) => l.producto), <String>[
        'Azúcar',
        'Arroz',
      ]);
      expect(t.salio, 25); // 16 de arroz + 9 de azúcar
      expect(t.entregado, 10);
      expect(t.queda, 15); // 6 devueltos + 9 sin marcar
      expect(t.salio, t.entregado + t.queda);
    });
  });

  group('la fecha de impresión es punto de paridad con la de Next', () {
    setUpAll(prepararFechas);

    test('sale como toLocaleString("es")', () {
      expect(
        fechaDeImpresion(DateTime(2026, 9, 14, 17, 20, 30)),
        '14/9/2026, 17:20:30',
      );
    });

    test('la hora no se rellena con cero y los minutos sí', () {
      // `toLocaleString('es')` da `14/9/2026, 9:05:03`.
      expect(
        fechaDeImpresion(DateTime(2026, 9, 14, 9, 5, 3)),
        '14/9/2026, 9:05:03',
      );
    });

    test('la medianoche es 0, no 24 ni 12', () {
      expect(
        fechaDeImpresion(DateTime(2026, 1, 2, 0, 0, 0)),
        '2/1/2026, 0:00:00',
      );
    });
  });

  group('los casos vacíos también salen en papel', () {
    test('una ruta entregada entera imprime «no queda nada»', () async {
      final h = armarPostDespacho(
        const DatosDeRuta(ruta: 'R-1', sucursal: 'Camagüey', vehiculo: ''),
        const <PedidoDeRuta>[
          PedidoDeRuta(
            customerName: 'Uno',
            resultado: 'entregado',
            items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 3)],
          ),
        ],
      );
      expect(h.lineasConResto, isEmpty);
      expect(h.pendientes, isEmpty);

      final bytes = await pdfPostDespacho(h, impresoEn: _impresoEn);
      expect(bytes, isNotEmpty);
    });

    test('un pre-despacho sin líneas no revienta', () async {
      final bytes = await pdfPreDespacho(
        _pre(lineas: const <LineaPreDespacho>[]),
        impresoEn: _impresoEn,
      );
      expect(bytes, isNotEmpty);
      expect(
        TotalesPreDespacho.de(_pre(lineas: const <LineaPreDespacho>[]))
            .formatos,
        0,
      );
    });

    test('con día filtrado y sin él, las dos salen', () async {
      final con = await pdfPreDespacho(
        _pre(dia: '2026-09-14'),
        impresoEn: _impresoEn,
      );
      final sin = await pdfPreDespacho(_pre(), impresoEn: _impresoEn);
      expect(con, isNotEmpty);
      expect(sin, isNotEmpty);
      // La línea del día ocupa: con día la hoja pesa más.
      expect(con.length, greaterThan(sin.length));
    });
  });

  group('lo que se escribe en el detalle de cada parada', () {
    test('productos separados por " · " y con su número', () {
      const p = ParadaPendiente(
        cliente: 'Cafetería El Puente',
        resultado: 'devuelto',
        nota: null,
        productos: <ProductoDeParada>[
          ProductoDeParada(producto: 'Arroz', formatos: 6),
          ProductoDeParada(producto: 'Azúcar', formatos: 2),
        ],
      );
      expect(productosDeParada(p), 'Arroz × 6 · Azúcar × 2');
    });

    test('una parada sin productos imprime una raya', () {
      const p = ParadaPendiente(
        cliente: 'Vacía',
        resultado: null,
        nota: null,
        productos: <ProductoDeParada>[],
      );
      expect(productosDeParada(p), '—');
    });
  });
}
