/// LA TABLA «POR PRODUCTO Y FACTURA» DEL PRE-DESPACHO — Amado, issue 8.
///
/// La tarjeta de estiba es POR PRODUCTO, y sus salidas se rebajan por cantidad Y
/// factura: «se sacaron 20 blister, 10 de una factura y 10 de otra; en la tarjeta
/// no se pone 20, se ponen 10 y 10 poniendo la factura que provocó la salida de
/// inventario». Así que la tabla es la hoja que Amado adjuntó al issue (escrita a
/// mano): **un bloque por producto**, dentro **una fila por cada factura que lo
/// lleva** —factura, producto, cantidad y kg, el producto repetido en cada fila— y
/// **el subtotal del producto**. Sin columna de unidades: Amado no la pone, y
/// «Cant» son EMPAQUES (blister), que es como se carga.
///
/// La del 14/10/2026 iba al revés (un bloque por factura con sus productos dentro)
/// porque la imagen del issue no llegó a quien la escribió.
///
/// ## LAS COLUMNAS SE CAMBIAN AQUÍ Y SÓLO AQUÍ
///
/// **La pantalla** (`rutas/vista/tabla_por_producto_y_factura.dart`) **y el PDF**
/// (`pre_despacho.dart`) leen [columnasPorProductoYFactura] y ninguna otra cosa, y
/// las dos pintan exactamente los textos que salen de [filasPorProductoYFactura]:
/// lo que se ve y lo que se imprime no pueden separarse sin que salte
/// `test/impresion/por_producto_y_factura_test.dart`.
///
/// Este fichero no dibuja nada ni suma nada por su cuenta: reparte las líneas que
/// ya calculó `preDespachoDe` pedido a pedido y suma cada bloque con
/// [TotalesPreDespacho.deLineas], la misma suma (y el mismo `≥`) que la hoja.
library;

import 'estilo.dart';
import 'hoja.dart';

/// Una columna de la tabla: su rótulo y cómo se escribe su celda en una fila de
/// detalle y en la del subtotal.
class ColumnaPorProductoYFactura {
  const ColumnaPorProductoYFactura({
    required this.titulo,
    required this.detalle,
    required this.subtotal,
    this.alDerecha = false,
    this.esLaFactura = false,
    this.esElProducto = false,
  });

  /// El rótulo de la cabecera. En la tarjeta del teléfono es también el rótulo
  /// pegado a cada cifra, así que tiene que leerse solo («Cant.», no «C.»).
  final String titulo;

  /// Las cifras se alinean a la derecha: se leen por la coma, no por la primera
  /// cifra.
  final bool alDerecha;

  /// La columna de la factura: en la tarjeta del teléfono es el título de cada
  /// renglón.
  final bool esLaFactura;

  /// La columna del producto: en la tarjeta del teléfono es el encabezado del
  /// bloque (no se repite en cada renglón), y en el papel se queda con el ancho
  /// que sobra.
  final bool esElProducto;

  /// La celda de una factura dentro del bloque de un producto.
  final String Function(FacturaDelPreDespacho factura, LineaPreDespacho linea)
  detalle;

  /// La celda del subtotal del producto, ya sumado con la regla de la hoja.
  final String Function(TotalesPreDespacho suma) subtotal;
}

/// Lo que dice la columna de la factura en la fila del subtotal.
const String subtotalDelProducto = 'Subtotal';

/// LAS COLUMNAS. Cambiar la tabla es cambiar esta lista.
final List<ColumnaPorProductoYFactura>
columnasPorProductoYFactura = <ColumnaPorProductoYFactura>[
  ColumnaPorProductoYFactura(
    titulo: 'Factura',
    esLaFactura: true,
    // Un pedido con DOS facturas (`1024237, 1024240`) lleva las dos tal cual
    // en su fila: `order_items` no dice qué renglón salió de cuál, y partirlo
    // en dos filas rebajaría dos veces la misma mercancía.
    detalle: (f, l) => f.rotulo,
    subtotal: (t) => subtotalDelProducto,
  ),
  ColumnaPorProductoYFactura(
    titulo: 'Producto',
    esElProducto: true,
    detalle: (f, l) => l.producto,
    subtotal: (t) => '',
  ),
  ColumnaPorProductoYFactura(
    // EMPAQUES (blister), el mismo número de la columna `Empaques` de la tabla
    // de arriba: es como carga quien carga.
    titulo: 'Cant.',
    alDerecha: true,
    detalle: (f, l) => numero(l.formatos),
    subtotal: (t) => numero(t.formatos),
  ),
  ColumnaPorProductoYFactura(
    // UN PESO SIN SABER SE PINTA `—` (nunca 0) Y UNA SUMA INCOMPLETA `≥`: las
    // dos reglas de la tabla de arriba (`estilo.dart`, `CLAUDE.md` §3-sexies).
    titulo: 'Kg',
    alDerecha: true,
    detalle: (f, l) =>
        conMinimo(pesoDeFila(l.pesoKg), completo: l.pesoCompleto),
    subtotal: (t) =>
        conMinimo(pesoDeFila(t.pesoDeLosProductos), completo: t.pesoCompleto),
  ),
];

/// Lo que dice la fila de una factura que no trae ni un renglón. **Se dice**: una
/// factura que desapareciera de la tabla sin decirlo se leería como «esa factura
/// no sacó nada», y puede ser que sus renglones simplemente no hayan llegado.
const String facturaSinRenglones = 'Sin renglones';

/// Una fila ya escrita: una celda de texto por columna de
/// [columnasPorProductoYFactura].
class FilaPorProductoYFactura {
  const FilaPorProductoYFactura({required this.celdas, this.subtotal = false});

  /// ¿Es la fila que cierra el bloque de un producto?
  final bool subtotal;

  /// Los textos, en el orden de [columnasPorProductoYFactura].
  final List<String> celdas;
}

/// Las filas, en el orden en que se imprimen: por cada producto, una fila por
/// factura y su subtotal; al final, las facturas sin renglones.
///
/// [productos] son las líneas de la tabla de arriba (la de producto a producto) y
/// dan **el orden de los bloques**: el mismo de esa tabla, más empaques primero,
/// que es también el de la hoja de Amado. [facturas] llegan ya por número con
/// las «Sin número» al final (`ordenDeLasFacturas`, en
/// `pantallas/rutas/datos/pre_despacho_de_la_ruta.dart`) y dentro de cada bloque
/// se quedan así. Sin facturas no hay filas.
List<FilaPorProductoYFactura> filasPorProductoYFactura(
  List<LineaPreDespacho> productos,
  List<FacturaDelPreDespacho> facturas,
) {
  final porProducto =
      <String, List<(FacturaDelPreDespacho, LineaPreDespacho)>>{};
  for (final f in facturas) {
    for (final l in f.lineas) {
      (porProducto[l.producto] ??= []).add((f, l));
    }
  }
  // Un producto que la tabla de arriba aún no trae (la bajada va por partes) no
  // se pierde: va detrás, en el orden en que aparece.
  final orden = <String>{
    for (final p in productos)
      if (porProducto.containsKey(p.producto)) p.producto,
    ...porProducto.keys,
  };

  final columnas = columnasPorProductoYFactura;
  final filas = <FilaPorProductoYFactura>[];
  for (final producto in orden) {
    final suyas = porProducto[producto]!;
    for (final (f, l) in suyas) {
      filas.add(
        FilaPorProductoYFactura(
          celdas: <String>[for (final c in columnas) c.detalle(f, l)],
        ),
      );
    }
    final suma = TotalesPreDespacho.deLineas([for (final (_, l) in suyas) l]);
    filas.add(
      FilaPorProductoYFactura(
        subtotal: true,
        celdas: <String>[for (final c in columnas) c.subtotal(suma)],
      ),
    );
  }
  for (final f in facturas.where((f) => f.lineas.isEmpty)) {
    filas.add(
      FilaPorProductoYFactura(
        celdas: <String>[
          for (final c in columnas)
            c.esLaFactura
                ? f.rotulo
                : c.esElProducto
                ? facturaSinRenglones
                : '',
        ],
      ),
    );
  }
  return filas;
}
