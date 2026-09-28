/// Lo que comparten las dos hojas: la pagina, las fuentes, los colores y la
/// forma de escribir numeros y fechas.
///
/// Todo sale de la hoja de estilos del HTML de Next (`imprimirPreDespacho.ts` y
/// `imprimirPostDespacho.ts`) traducido a puntos, que es lo que entiende el PDF:
/// **1 px CSS = 0.75 pt**, porque el navegador imprime a 96 px por pulgada y el
/// PDF trabaja a 72. Por eso los 13 px del cuerpo salen 9.75 pt.
library;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 1 px de CSS en puntos de PDF.
const double px = 0.75;

/// La pagina: A4 con 12 mm de margen, que es lo que pide `@media print` del
/// HTML. Los 24 px de pantalla no se copian: aqui no hay pantalla, solo papel.
final PdfPageFormat hojaA4 = PdfPageFormat.a4.copyWith(
  marginTop: 12 * PdfPageFormat.mm,
  marginBottom: 12 * PdfPageFormat.mm,
  marginLeft: 12 * PdfPageFormat.mm,
  marginRight: 12 * PdfPageFormat.mm,
);

/// Los colores del HTML, uno a uno.
abstract final class Tinta {
  static const PdfColor texto = PdfColor.fromInt(0xFF111111); // body
  static const PdfColor apagado = PdfColor.fromInt(0xFF444444); // .cab p, h2
  static const PdfColor gris = PdfColor.fromInt(0xFF666666); // .nota, .vacio
  static const PdfColor prods = PdfColor.fromInt(0xFF333333); // .prods
  static const PdfColor cabeceraFondo = PdfColor.fromInt(0xFFF4F4F4); // th
  static const PdfColor linea = PdfColor.fromInt(0xFFDDDDDD); // th, td
  static const PdfColor lineaParada = PdfColor.fromInt(0xFFEEEEEE); // .parada
  static const PdfColor lineaGruesa = PdfColor.fromInt(0xFF333333); // tfoot
  static const PdfColor lineaFirma = PdfColor.fromInt(0xFF999999); // .firma
  static const PdfColor bordePildora = PdfColor.fromInt(0xFFDDDDDD); // .resumen

  static const PdfColor devueltoFondo = PdfColor.fromInt(0xFFFDE8E8);
  static const PdfColor devueltoTexto = PdfColor.fromInt(0xFF8A1C1C);
  static const PdfColor canceladoFondo = PdfColor.fromInt(0xFFF1F1F1);
  static const PdfColor canceladoTexto = PdfColor.fromInt(0xFF444444);
  static const PdfColor sinMarcarFondo = PdfColor.fromInt(0xFFFFF4D6);
  static const PdfColor sinMarcarTexto = PdfColor.fromInt(0xFF7A5600);
}

/// Las dos fuentes de la hoja, ya cargadas.
class FuentesDeImpresion {
  const FuentesDeImpresion({required this.normal, required this.negrita});

  final pw.Font normal;
  final pw.Font negrita;

  pw.ThemeData get tema =>
      pw.ThemeData.withFont(
        base: normal,
        bold: negrita,
        italic: normal, // no hay Roboto-Italic embebida; el PDF la inclina solo
        boldItalic: negrita,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(
          font: normal,
          fontBold: negrita,
          fontSize: 13 * px,
          height: 1.4,
          color: Tinta.texto,
        ),
      );
}

/// Las rutas de las dos fuentes. Son ficheros del propio APK/paquete web.
const String rutaRegular = 'assets/fuentes/Roboto-Regular.ttf';
const String rutaNegrita = 'assets/fuentes/Roboto-Bold.ttf';

FuentesDeImpresion? _enCache;

/// Carga Roboto **desde los assets del aparato**.
///
/// Nada de `PdfGoogleFonts`: eso baja el `.ttf` de Google por red la primera vez
/// y esta hoja se imprime en el patio de un almacen, donde no hay senal la mitad
/// del dia. Si la fuente no esta, la hoja no sale, y eso hay que verlo al
/// arrancar, no cuando el camion ya esta cargado.
///
/// Se guarda en cache porque leer y parsear dos `.ttf` de 170 KB por cada hoja
/// impresa se nota en un telefono de almacen.
Future<FuentesDeImpresion> cargarFuentes({AssetBundle? desde}) async {
  // Con un paquete de assets propio (los tests) no se toca la cache: si no, el
  // primer test decide las fuentes de todos los demas.
  if (desde == null && _enCache != null) return _enCache!;

  final paquete = desde ?? rootBundle;
  final normal = pw.Font.ttf(await paquete.load(rutaRegular));
  final negrita = pw.Font.ttf(await paquete.load(rutaNegrita));
  final fuentes = FuentesDeImpresion(normal: normal, negrita: negrita);

  if (desde == null) _enCache = fuentes;
  return fuentes;
}

/// Solo para los tests: olvida las fuentes cargadas.
void olvidarFuentes() => _enCache = null;

bool _fechasListas = false;

/// Carga los nombres de meses y dias en espanol antes de escribir una fecha.
///
/// El arranque de la aplicacion ya lo hace, pero la hoja lo repite por su
/// cuenta: `DateFormat(..., 'es')` revienta si nadie lo llamo, y la hoja se
/// imprime tambien desde un test y desde el cierre de ruta, que pueden no haber
/// pasado por el arranque. La segunda llamada no cuesta nada.
Future<void> prepararFechas() async {
  if (_fechasListas) return;
  await initializeDateFormatting('es');
  _fechasListas = true;
}

/// La fecha y hora de impresion, igual que `toLocaleString('es')` de la de
/// Next. **Es punto de paridad**: se compara con lo que imprime la otra hoja,
/// asi que el patron no se toca sin cambiarlo alli tambien.
String fechaDeImpresion(DateTime cuando) =>
    DateFormat('d/M/y, H:mm:ss', 'es').format(cuando);

/// Escribe un numero como lo escribe JavaScript al interpolarlo: `5`, no `5.0`.
///
/// Los empaques casi siempre son enteros, pero el tipo de Next es `number` y
/// alguna linea llega fraccionada. Si aqui saliera `5.0` la hoja dejaria de ser
/// comparable con la de Next linea a linea.
String numero(num n) {
  if (n is int) return n.toString();
  if (n == n.roundToDouble() && n.isFinite) return n.toInt().toString();
  return n.toString();
}

/// El peso de una fila: un decimal, y una raya si es cero.
///
/// La de Next hace `l.pesoKg ? l.pesoKg.toFixed(1) : '—'`, y en JavaScript el
/// cero es falso. Un producto sin peso no imprime `0.0`, imprime la raya.
String pesoDeFila(num? kg) => (kg == null || kg == 0)
    ? '—'
    : kg.toStringAsFixed(1);

/// UN NÚMERO QUE NO SE SABE SE PINTA `—`, NUNCA CERO — 22/09/2026.
///
/// Es la misma regla de [pesoDeFila] para las unidades. En la hoja del almacén
/// un cero no se distingue de «no lleva»: se saca de menos, se carga el camión,
/// y no se descubre hasta que se fue.
String cantidadDeFila(num? n) => n == null ? '—' : numero(n);

/// LO MISMO, PERO DICIENDO QUE ES UN MÍNIMO — 28/09/2026.
///
/// Cuando a una fila le faltan renglones, su cifra ya no es el total: es lo que
/// se sabe. Con el `≥` delante se puede imprimir sin mentir, y con él la hoja
/// del almacén vuelve a servir — antes salía `—` en los productos que más se
/// mueven porque a 21 renglones de 1.149 les faltaba el dato.
///
/// El `≥` va pegado a la cifra y no en otra columna a propósito: quien lee la
/// hoja en el almacén lee una línea, no una tabla de notas al pie.
String conMinimo(String cifra, {required bool completo}) =>
    completo || cifra == '—' ? cifra : '≥ $cifra';

/// El peso de un total: siempre con su decimal, aunque sea cero.
String pesoTotal(num kg) => kg.toStringAsFixed(1);
