/// El pre-despacho, en papel.
///
/// El almacen no mira una pantalla: alguien baja con una hoja y va sacando. Por
/// eso se imprime, y por eso lleva los totales grandes al final — es lo que se
/// comprueba cuando el camion ya esta cargado.
///
/// En Next esto era una ventana de 900x700 con HTML escrito a mano. Aqui no hay
/// ventana nueva ni impresora del navegador en Android, asi que se genera el
/// PDF y se ensena en un cajon con `VistaPreviaPdf`.
///
/// Estructura literal: `../docs/pantallas.md` §10.1.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'estilo.dart';
import 'hoja.dart';
import 'piezas.dart';

/// Los literales de la hoja. Van en espanol y nunca pasaron por la capa de
/// idiomas que hubo en `lib/textos/` (quitada entera el 24/09/2026,
/// ver `lib/idioma.dart`): este papel es el punto de paridad con la hoja de Next
/// y se compara palabra a palabra con ella. Los vigila
/// `test/impresion/literales_de_las_hojas_test.dart`.
abstract final class TextoPreDespacho {
  static const String titulo = 'Pre-despacho';
  static const String pedidosDel = 'Pedidos del ';

  /// El `(s)` va DENTRO del literal, tal cual lo escribe el pliego. Nada de
  /// pluralizar con ICU: en cuanto se hace, el texto deja de ser identico.
  static const String pedidos = ' pedido(s)';
  static const String kg = ' kg';

  static const String colProducto = 'Producto';
  static const String colEmpaques = 'Empaques';
  static const String colUnidades = 'Unidades';
  static const String colKg = 'kg';
  static const String colSacado = 'Sacado';
  static const String total = 'Total';

  static const String firmaSaco = 'Sacó del almacén';
  static const String firmaRecibio = 'Recibió (chofer)';

  /// LOS DOS RÓTULOS DE LOS PESOS. Son **los mismos que los de la pantalla**
  /// (`TotalesDelPreDespacho.pesoDeLosProductos` y `.pesoDeLosPedidos`), letra
  /// por letra y a propósito: quien mira el papel y la pantalla tiene que ver
  /// lo mismo. Atados con una prueba, no con este comentario
  /// (`test/impresion/los_dos_pesos_del_pre_despacho_test.dart`).
  static const String pesoDeLosProductos = 'Peso de los productos';
  static const String pesoDeLosPedidos = 'Peso de los pedidos';

  /// La frase de debajo, también igual que en la pantalla: es lo único que
  /// impide restar las dos cifras a ojo.
  static const String noSonElMismoNumero =
      'No son el mismo número: el de arriba suma renglón a renglón, y el de '
      'abajo es el peso que trae cada pedido entero.';

  /// Cuando NINGÚN producto trae peso. Si sólo faltan algunos se dice cuántos,
  /// que es lo que convierte una raya muda en algo que alguien puede ir a
  /// arreglar.
  static const String sinPesoEnElCatalogo = 'sin peso en los pedidos';
}

/// El peso **de los productos** tal como sale en el papel: la suma de la
/// columna `kg`, o lo que falta para poder darla.
///
/// Es el mismo texto que escribe la pantalla en `pesoDelPreDespacho`
/// (`pantallas/pedidos/vista/vista_pre_despacho.dart`). No se puede compartir
/// el código porque cada lado tiene su propio tipo de totales —el papel no
/// depende de la capa de pantallas—, así que se comparan con una prueba.
String pesoDeLosProductosEnPapel(TotalesPreDespacho t) {
  final peso = t.pesoDeLosProductos;
  if (peso != null) return '${pesoTotal(peso)}${TextoPreDespacho.kg}';
  return t.sinPeso == t.productos
      ? TextoPreDespacho.sinPesoEnElCatalogo
      : '${t.sinPeso} de ${t.productos} productos sin peso';
}

/// El peso **de los pedidos**: éste siempre se sabe, porque viene en el propio
/// pedido y no del catálogo.
String pesoDeLosPedidosEnPapel(TotalesPreDespacho t) =>
    '${pesoTotal(t.pesoDeLosPedidos)}${TextoPreDespacho.kg}';

/// El ancho de la columna que se marca a mano: los 70 px del HTML pasados a
/// papel (70/96 de pulgada = 18.5 mm). Se fija y no se deja al contenido porque
/// el contenido es NADA: sin un ancho de verdad la columna se cierra y no cabe
/// el numero que hay que escribir dentro.
final pw.FixedColumnWidth anchoSacado = pw.FixedColumnWidth(
  18.5 * PdfPageFormat.mm,
);

/// Arma el PDF del pre-despacho.
///
/// [impresoEn] entra por parametro y no se lee del reloj aqui dentro para que
/// la hoja sea reproducible: la misma entrada da los mismos bytes, que es lo
/// que permite compararla con la de Next y probarla.
///
/// [paqueteDeAssets] solo lo usan los tests; en la aplicacion las fuentes salen
/// del `rootBundle`, es decir del propio APK, sin tocar la red.
Future<Uint8List> pdfPreDespacho(
  HojaPreDespacho h, {
  required DateTime impresoEn,
  AssetBundle? paqueteDeAssets,
}) async {
  await prepararFechas();
  final fuentes = await cargarFuentes(desde: paqueteDeAssets);
  final totales = TotalesPreDespacho.de(h);

  final doc = pw.Document(theme: fuentes.tema, title: TextoPreDespacho.titulo);

  doc.addPage(
    pw.MultiPage(
      pageFormat: hojaA4,
      theme: fuentes.tema,
      build: (pw.Context ctx) => <pw.Widget>[
        cabecera(
          izquierda: <pw.Widget>[
            titulo(TextoPreDespacho.titulo),
            lineaDeCabecera(
              h.vehiculo.isNotEmpty
                  ? '${h.sucursal} · ${h.vehiculo}'
                  : h.sucursal,
            ),
            if (h.dia != null && h.dia!.isNotEmpty)
              lineaDeCabecera('${TextoPreDespacho.pedidosDel}${h.dia}'),
          ],
          derecha: <pw.Widget>[
            lineaDeCabecera('${h.pedidos}${TextoPreDespacho.pedidos}'),
            // Rotulado, y no «412.5 kg» a secas como en la de Next: en esta
            // hoja hay DOS pesos y el de arriba es el de los pedidos. Una
            // cifra en kg sin rótulo es justo lo que se resta a ojo con la de
            // la tabla.
            lineaDeCabecera(
              '${TextoPreDespacho.pesoDeLosPedidos} '
              '${pesoTotal(h.pesoKg)}${TextoPreDespacho.kg}',
            ),
            lineaDeCabecera(fechaDeImpresion(impresoEn)),
          ],
        ),
        _tabla(h, totales),
        // Sin líneas no hay ninguna de las dos cuentas que separar, igual que
        // en la pantalla, que sólo pinta los totales si hay tabla encima.
        if (h.lineas.isNotEmpty) _losDosPesos(totales),
        firmas(TextoPreDespacho.firmaSaco, TextoPreDespacho.firmaRecibio),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _tabla(HojaPreDespacho h, TotalesPreDespacho t) => pw.Table(
  columnWidths: <int, pw.TableColumnWidth>{
    0: const pw.FlexColumnWidth(),
    1: const pw.IntrinsicColumnWidth(),
    2: const pw.IntrinsicColumnWidth(),
    3: const pw.IntrinsicColumnWidth(),
    4: anchoSacado,
  },
  children: <pw.TableRow>[
    pw.TableRow(
      decoration: decoracionCabecera,
      repeat: true, // si la hoja pasa de pagina, la cabecera va otra vez
      children: <pw.Widget>[
        celdaCabecera(TextoPreDespacho.colProducto),
        celdaCabecera(TextoPreDespacho.colEmpaques, derecha: true),
        celdaCabecera(TextoPreDespacho.colUnidades, derecha: true),
        celdaCabecera(TextoPreDespacho.colKg, derecha: true),
        celdaCabecera(TextoPreDespacho.colSacado),
      ],
    ),
    // Las lineas vienen YA ordenadas de mas a menos empaques; esta hoja no
    // las toca. Si aqui se reordenaran, dejaria de cuadrar con la de Next.
    for (final l in h.lineas)
      pw.TableRow(
        decoration: decoracionFila,
        children: <pw.Widget>[
          celda(l.producto),
          celda(numero(l.formatos), derecha: true),
          celda(cantidadDeFila(l.unidades), derecha: true),
          celda(pesoDeFila(l.pesoKg), derecha: true),
          celdaParaMarcar(),
        ],
      ),
    pw.TableRow(
      decoration: decoracionPie,
      children: <pw.Widget>[
        celda(TextoPreDespacho.total, negrita: true),
        celda(numero(t.formatos), derecha: true, negrita: true),
        celda(cantidadDeFila(t.unidades), derecha: true, negrita: true),
        // EL TOTAL DE LA COLUMNA `kg` ES EL TOTAL DE ESA COLUMNA, y por eso
        // ya no es `h.pesoKg`. Aquí se imprimía el peso de los PEDIDOS debajo
        // de una columna de pesos por PRODUCTO; con diez líneas a `—` encima,
        // el 29.835,4 del pie se leía como la suma de esas diez rayas. Con la
        // misma regla que las líneas (`pesoDeFila`): si falta una, raya.
        celda(pesoDeFila(t.pesoDeLosProductos), derecha: true, negrita: true),
        celdaParaMarcar(),
      ],
    ),
  ],
);

/// LOS DOS PESOS, EN DOS RENGLONES Y CON SU RÓTULO — 23/09/2026.
///
/// El porqué entero está en [TotalesPreDespacho] (`hoja.dart`): son dos cuentas
/// distintas, y hasta hoy compartían columna sin que nada lo dijera. Esto es lo
/// mismo que hace la pantalla desde el 22/09/2026 —`TotalesDelPreDespacho`—,
/// con sus mismos rótulos y su misma frase, para que quien mira las dos vea lo
/// mismo.
///
/// Van en un bloque debajo de la tabla y no en dos filas más del `Table`
/// porque la tabla tiene cinco columnas —una de ellas la de marcar a mano— y un
/// rótulo de veintiún caracteres dentro de la celda `Producto` se lee como un
/// producto más de la lista.
pw.Widget _losDosPesos(TotalesPreDespacho t) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 14 * px),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      _renglonDePeso(
        TextoPreDespacho.pesoDeLosProductos,
        pesoDeLosProductosEnPapel(t),
      ),
      _renglonDePeso(
        TextoPreDespacho.pesoDeLosPedidos,
        pesoDeLosPedidosEnPapel(t),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4 * px),
        child: pw.Text(
          TextoPreDespacho.noSonElMismoNumero,
          style: const pw.TextStyle(fontSize: 11 * px, color: Tinta.gris),
        ),
      ),
    ],
  ),
);

/// Un rótulo y su cifra, en la MISMA línea y cada uno en la suya.
///
/// El rótulo lleva ancho fijo para que las dos cifras queden una debajo de
/// otra: puestas en dos sitios distintos de la hoja, se vuelven a comparar mal.
pw.Widget _renglonDePeso(String rotulo, String valor) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 1.5 * px),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.SizedBox(
        width: 150 * px,
        child: pw.Text(
          rotulo,
          style: const pw.TextStyle(color: Tinta.apagado),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          valor,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      ),
    ],
  ),
);
