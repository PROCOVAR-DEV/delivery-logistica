/// LA TABLA «POR FACTURA» DEL PRE-DESPACHO — Amado, issue 8.
///
/// El almacén rebaja las tarjetas de estiba **por cantidades Y facturas**. Con
/// el ejemplo de Amado: «se sacaron 20 blister, 10 de una factura y 10 de otra;
/// en la tarjeta no se pone 20, se ponen 10 y 10 poniendo la factura que provocó
/// la salida de inventario». La tabla de producto a producto dice «20» y no sirve
/// para eso; esta dice una fila por (factura, producto).
///
/// ## LAS COLUMNAS SE CAMBIAN AQUÍ Y SÓLO AQUÍ
///
/// La imagen que Amado adjuntó al issue no llegó a quien escribió esto, así que
/// las cinco columnas —Factura, Producto, Blister, Unidades, Peso— son una
/// propuesta razonable para un almacenero y no el diseño de Amado. Cuando llegue
/// la imagen, igualarla es tocar [columnasPorFactura]: añadir, quitar, reordenar
/// o renombrar una columna. **La pantalla** (`rutas/vista/tabla_por_factura.dart`)
/// **y el PDF** (`pre_despacho.dart`) leen esta lista y ninguna otra cosa, y las
/// dos pintan exactamente los textos que salen de [filasPorFactura]: lo que se
/// ve en la pantalla y lo que se imprime no pueden separarse sin que salte
/// `test/impresion/por_factura_test.dart`.
///
/// Este fichero no dibuja nada: produce textos. Por eso se prueba sin abrir un
/// PDF ni montar un widget.
library;

import 'estilo.dart';
import 'hoja.dart';

/// Qué es cada fila de la tabla.
enum TipoDeFilaPorFactura {
  /// Un producto de una factura.
  detalle,

  /// Lo que suma una factura.
  subtotal,

  /// Lo que suman todas.
  total,
}

/// Una columna de la tabla: su rótulo y cómo se escribe su celda en cada tipo de
/// fila.
class ColumnaPorFactura {
  const ColumnaPorFactura({
    required this.titulo,
    required this.detalle,
    required this.subtotal,
    required this.total,
    this.alDerecha = false,
    this.esLaFactura = false,
    this.ancha = false,
  });

  /// El rótulo de la cabecera. En la tarjeta del teléfono es también el rótulo
  /// pegado a cada cifra, así que tiene que leerse solo («Blister», no «Bl.»).
  final String titulo;

  /// Las cifras se alinean a la derecha: se leen por la coma, no por la primera
  /// cifra.
  final bool alDerecha;

  /// ¿Es la columna del número de factura? En la tarjeta del teléfono la factura
  /// no se repite en cada renglón: es el encabezado de la tarjeta. Es la única
  /// columna que la pantalla estrecha trata distinto, y lo dice aquí en vez de
  /// adivinarlo por el título.
  final bool esLaFactura;

  /// La columna que se queda con el ancho que sobra (el producto). En la tarjeta
  /// del teléfono es el título del renglón.
  final bool ancha;

  /// La celda de un producto de una factura.
  final String Function(FacturaDelPreDespacho factura, LineaPreDespacho linea)
  detalle;

  /// La celda del subtotal de una factura, ya sumada con la regla de la hoja.
  final String Function(FacturaDelPreDespacho factura, TotalesPreDespacho suma)
  subtotal;

  /// La celda del total de todas las facturas.
  final String Function(TotalesPreDespacho suma) total;
}

/// UNA UNIDAD SIN SABER SE PINTA `—`, Y UNA SUMA INCOMPLETA SE PINTA `≥`: las
/// mismas dos reglas que la tabla de producto a producto (`estilo.dart`).
String _unidades(num? n, {required bool completo}) =>
    conMinimo(cantidadDeFila(n), completo: completo);

String _kg(num? kg, {required bool completo}) =>
    conMinimo(pesoDeFila(kg), completo: completo);

/// LAS COLUMNAS. Cambiar la tabla es cambiar esta lista.
final List<ColumnaPorFactura> columnasPorFactura = <ColumnaPorFactura>[
  ColumnaPorFactura(
    titulo: 'Factura',
    esLaFactura: true,
    detalle: (f, l) => f.rotulo,
    subtotal: (f, t) => f.rotulo,
    total: (t) => 'Total',
  ),
  ColumnaPorFactura(
    titulo: 'Producto',
    ancha: true,
    detalle: (f, l) => l.producto,
    subtotal: (f, t) => 'Subtotal',
    total: (t) => '',
  ),
  ColumnaPorFactura(
    // Blister es como lo llama quien carga: es el EMPAQUE, el mismo número de
    // la columna `Empaques` de la tabla de arriba.
    titulo: 'Blister',
    alDerecha: true,
    detalle: (f, l) => numero(l.formatos),
    subtotal: (f, t) => numero(t.formatos),
    total: (t) => numero(t.formatos),
  ),
  ColumnaPorFactura(
    titulo: 'Unidades',
    alDerecha: true,
    detalle: (f, l) => _unidades(l.unidades, completo: l.unidadesCompletas),
    subtotal: (f, t) => _unidades(t.unidades, completo: t.unidadesCompletas),
    total: (t) => _unidades(t.unidades, completo: t.unidadesCompletas),
  ),
  ColumnaPorFactura(
    titulo: 'Peso (kg)',
    alDerecha: true,
    detalle: (f, l) => _kg(l.pesoKg, completo: l.pesoCompleto),
    subtotal: (f, t) => _kg(t.pesoDeLosProductos, completo: t.pesoCompleto),
    total: (t) => _kg(t.pesoDeLosProductos, completo: t.pesoCompleto),
  ),
];

/// Lo que dice la fila de una factura que no trae ni un renglón. **Se dice**: una
/// factura que desapareciera de la tabla sin decirlo se leería como «esa factura
/// no sacó nada», y puede ser que sus renglones simplemente no hayan llegado.
const String facturaSinRenglones = 'Sin renglones';

/// Una fila ya escrita: una celda de texto por columna de [columnasPorFactura].
class FilaPorFactura {
  const FilaPorFactura({
    required this.tipo,
    required this.celdas,
    this.factura,
  });

  final TipoDeFilaPorFactura tipo;

  /// De qué factura es. `null` en la fila del total.
  final FacturaDelPreDespacho? factura;

  /// Los textos, en el orden de [columnasPorFactura].
  final List<String> celdas;
}

/// Las filas de la tabla, en el orden en que se imprimen: por cada factura sus
/// productos y su subtotal, y al final el total.
///
/// No reordena nada: [facturas] llegan en el orden en que se leen (ver
/// `pantallas/rutas/datos/pre_despacho_de_la_ruta.dart`). Sin facturas no hay
/// filas, ni siquiera la del total.
List<FilaPorFactura> filasPorFactura(List<FacturaDelPreDespacho> facturas) {
  if (facturas.isEmpty) return const <FilaPorFactura>[];

  final filas = <FilaPorFactura>[];
  for (final f in facturas) {
    if (f.lineas.isEmpty) {
      filas.add(
        FilaPorFactura(
          tipo: TipoDeFilaPorFactura.detalle,
          factura: f,
          celdas: <String>[
            for (final c in columnasPorFactura)
              c.esLaFactura
                  ? f.rotulo
                  : c.ancha
                  ? facturaSinRenglones
                  : '',
          ],
        ),
      );
      continue;
    }
    for (final l in f.lineas) {
      filas.add(
        FilaPorFactura(
          tipo: TipoDeFilaPorFactura.detalle,
          factura: f,
          celdas: <String>[for (final c in columnasPorFactura) c.detalle(f, l)],
        ),
      );
    }
    final suma = TotalesPreDespacho.deLineas(f.lineas);
    filas.add(
      FilaPorFactura(
        tipo: TipoDeFilaPorFactura.subtotal,
        factura: f,
        celdas: <String>[for (final c in columnasPorFactura) c.subtotal(f, suma)],
      ),
    );
  }

  final todo = TotalesPreDespacho.deLineas(<LineaPreDespacho>[
    for (final f in facturas) ...f.lineas,
  ]);
  filas.add(
    FilaPorFactura(
      tipo: TipoDeFilaPorFactura.total,
      celdas: <String>[for (final c in columnasPorFactura) c.total(todo)],
    ),
  );
  return filas;
}
