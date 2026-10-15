// LA TABLA «POR PRODUCTO Y FACTURA», EN PANTALLA — Amado, issue 8.
//
// La tarjeta de estiba es por producto y sus salidas se rebajan por cantidad Y
// factura: de 20 blister que salieron, 10 son de una factura y 10 de otra, y la
// tarjeta lleva «10» y «10» con la factura que provocó cada salida. Esta tabla es
// esa cuenta, como la hoja de Amado: un bloque por producto, una fila por factura
// y el subtotal del producto.
//
// ## NO DECIDE NADA: PINTA LO QUE DICE LA LISTA DE COLUMNAS
//
// Los rótulos, el orden de las columnas y el texto de cada celda salen de
// `columnasPorProductoYFactura` y `filasPorProductoYFactura`
// (`impresion/por_producto_y_factura.dart`), que es lo mismo que lee el PDF. Aquí
// sólo se decide el dibujo, y por eso lo que se ve en la pantalla y lo que sale en
// el papel no pueden separarse sin que salte una prueba
// (`test/pantallas/rutas/el_pre_despacho_de_la_ruta_test.dart`).
//
// ## Y por debajo de 640 px deja de ser una tabla
//
// Misma regla y mismo número que la tabla de producto a producto
// (`PreDespacho.enTarjetasBajo`): se pinta una TARJETA POR PRODUCTO —el nombre
// arriba, y debajo cada factura con sus cifras y su rótulo pegado— en vez de
// obligar a desplazar de lado una tabla donde la factura queda fuera de la vista.

import 'package:flutter/material.dart';

import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../../../impresion/hoja.dart';
import '../../../impresion/por_producto_y_factura.dart';
import '../../pedidos/vista/kit.dart';
import '../../pedidos/vista/vista_pre_despacho.dart' show PreDespacho;

/// Los literales y las claves de la tabla, en un solo sitio: los buscan las
/// pruebas y los lee quien está delante.
abstract final class PorProductoYFactura {
  /// El título de la sección. Es el mismo del papel
  /// (`TextoPreDespacho.porProductoYFactura`), y lo ata una prueba.
  static const titulo = 'Por producto y factura';

  static const sinFacturas = 'Esta ruta no lleva ninguna factura todavía.';

  static const claveDeLaTabla = ValueKey('tabla-por-producto-y-factura');
  static const claveDeLasTarjetas = ValueKey('tarjetas-por-producto-y-factura');
}

class TablaPorProductoYFactura extends StatelessWidget {
  const TablaPorProductoYFactura({
    required this.productos,
    required this.facturas,
    super.key,
  });

  /// Las líneas de la tabla de arriba: dan el orden de los bloques.
  final List<LineaPreDespacho> productos;
  final List<FacturaDelPreDespacho> facturas;

  @override
  Widget build(BuildContext context) {
    final filas = filasPorProductoYFactura(productos, facturas);
    if (filas.isEmpty) {
      return const EstadoVacio(PorProductoYFactura.sinFacturas);
    }
    return LayoutBuilder(
      builder: (contexto, medidas) =>
          medidas.maxWidth < PreDespacho.enTarjetasBajo
          ? _Tarjetas(filas: filas)
          : _Tabla(filas: filas),
    );
  }
}

class _Tabla extends StatelessWidget {
  const _Tabla({required this.filas});

  final List<FilaPorProductoYFactura> filas;

  @override
  Widget build(BuildContext context) {
    // Se desplaza la tabla si un nombre largo la ensancha, no la página.
    return SingleChildScrollView(
      key: PorProductoYFactura.claveDeLaTabla,
      scrollDirection: Axis.horizontal,
      child: Theme(
        data: Theme.of(context).copyWith(
          dataTableTheme: temaDeTabla(context).copyWith(
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 44,
            columnSpacing: 20,
            horizontalMargin: Aire.md,
          ),
        ),
        child: DataTable(
          columns: [
            for (final c in columnasPorProductoYFactura)
              DataColumn(label: cabecera(c.titulo), numeric: c.alDerecha),
          ],
          rows: [
            for (final fila in filas)
              DataRow(
                // El subtotal se distingue por el fondo y la negrita: se ve dónde
                // acaba un producto y empieza otro.
                color: fila.subtotal
                    ? WidgetStatePropertyAll(Colores.papel)
                    : null,
                cells: [
                  for (final (i, c) in columnasPorProductoYFactura.indexed)
                    DataCell(
                      Text(
                        fila.celdas[i],
                        style: c.alDerecha
                            ? Tipos.mono(
                                tamano: 13,
                                color: Colores.tinta,
                                peso: _peso(fila),
                              )
                            : Tipos.texto(tamano: 13, peso: _peso(fila)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

FontWeight _peso(FilaPorProductoYFactura fila) =>
    fila.subtotal ? FontWeight.w700 : FontWeight.w400;

/// UNA TARJETA POR PRODUCTO, para el teléfono.
class _Tarjetas extends StatelessWidget {
  const _Tarjetas({required this.filas});

  final List<FilaPorProductoYFactura> filas;

  @override
  Widget build(BuildContext context) {
    // Una tarjeta acaba en su subtotal; las facturas sin renglones van juntas al
    // final, en una tarjeta sin subtotal.
    final tarjetas = <List<FilaPorProductoYFactura>>[];
    var abierta = <FilaPorProductoYFactura>[];
    for (final fila in filas) {
      abierta.add(fila);
      if (fila.subtotal) {
        tarjetas.add(abierta);
        abierta = <FilaPorProductoYFactura>[];
      }
    }
    if (abierta.isNotEmpty) tarjetas.add(abierta);

    return Column(
      key: PorProductoYFactura.claveDeLasTarjetas,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final t in tarjetas) _Tarjeta(filas: t)],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.filas});

  final List<FilaPorProductoYFactura> filas;

  @override
  Widget build(BuildContext context) {
    final producto = filas
        .first
        .celdas[columnasPorProductoYFactura.indexWhere((c) => c.esElProducto)];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colores.linea)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Aire.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            producto,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Tipos.texto(tamano: 13.5, peso: FontWeight.w700),
          ),
          const SizedBox(height: Aire.xs),
          for (final fila in filas) _Renglon(fila: fila),
        ],
      ),
    );
  }
}

/// Un renglón de la tarjeta: la factura y, a su lado, las cifras, cada una con su
/// rótulo pegado. En un `Wrap` y no en columnas con `Expanded`: un `Expanded`
/// reparte el ancho a partes y le puede tocar una celda de 39 px, que es como se
/// rompe una palabra letra a letra.
class _Renglon extends StatelessWidget {
  const _Renglon({required this.fila});

  final FilaPorProductoYFactura fila;

  @override
  Widget build(BuildContext context) {
    final negrita = fila.subtotal;
    final partes = <Widget>[];
    for (final (i, c) in columnasPorProductoYFactura.indexed) {
      final texto = fila.celdas[i];
      if (c.esElProducto || texto.isEmpty) continue;
      partes.add(
        c.esLaFactura
            ? Text(
                texto,
                style: Tipos.texto(
                  tamano: 13,
                  peso: negrita ? FontWeight.w700 : FontWeight.w600,
                ),
              )
            : _Cifra(texto, c.titulo, negrita: negrita),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: Aire.md,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: partes,
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.valor, this.rotulo, {required this.negrita});

  final String valor;
  final String rotulo;
  final bool negrita;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: valor,
          style: Tipos.mono(
            tamano: 13,
            color: Colores.tinta,
            peso: negrita ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        TextSpan(
          text: ' ${rotulo.toLowerCase()}',
          style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
