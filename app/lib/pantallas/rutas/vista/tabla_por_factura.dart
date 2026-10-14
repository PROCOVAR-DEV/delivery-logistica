// LA TABLA «POR FACTURA», EN PANTALLA — Amado, issue 8.
//
// El almacén rebaja las tarjetas de estiba por cantidades Y facturas: de 20
// blister que salieron, 10 son de una factura y 10 de otra, y la tarjeta lleva
// «10» y «10» con la factura que provocó cada salida. Esta tabla es esa cuenta:
// una fila por (factura, producto), con el subtotal de cada factura y el total.
//
// ## NO DECIDE NADA: PINTA LO QUE DICE LA LISTA DE COLUMNAS
//
// Los rótulos, el orden de las columnas y el texto de cada celda salen de
// `columnasPorFactura` y `filasPorFactura` (`impresion/por_factura.dart`), que es
// lo mismo que lee el PDF. Aquí sólo se decide el dibujo, y por eso lo que se ve
// en la pantalla y lo que sale en el papel no pueden separarse sin que salte una
// prueba (`test/pantallas/rutas/el_pre_despacho_de_la_ruta_test.dart`).
//
// ## Y por debajo de 640 px deja de ser una tabla
//
// Misma regla y mismo número que la tabla de producto a producto
// (`PreDespacho.enTarjetasBajo`), y por lo mismo: cinco columnas piden más de lo
// que tiene un teléfono. Se pinta una TARJETA POR FACTURA —el número arriba, y
// debajo cada producto con sus cifras y su rótulo pegado— en vez de obligar a
// desplazar de lado una tabla donde la factura queda fuera de la vista.

import 'package:flutter/material.dart';

import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../../../impresion/hoja.dart';
import '../../../impresion/por_factura.dart';
import '../../pedidos/vista/kit.dart';
import '../../pedidos/vista/vista_pre_despacho.dart' show PreDespacho;

/// Los literales y las claves de la tabla, en un solo sitio: los buscan las
/// pruebas y los lee quien está delante.
abstract final class PorFactura {
  /// El título de la sección. Es el mismo del papel
  /// (`TextoPreDespacho.porFactura`), y lo ata una prueba.
  static const titulo = 'Por factura';

  static const sinFacturas = 'Esta ruta no lleva ninguna factura todavía.';

  static const claveDeLaTabla = ValueKey('tabla-por-factura');
  static const claveDeLasTarjetas = ValueKey('tarjetas-por-factura');
}

class TablaPorFactura extends StatelessWidget {
  const TablaPorFactura({required this.facturas, super.key});

  final List<FacturaDelPreDespacho> facturas;

  @override
  Widget build(BuildContext context) {
    final filas = filasPorFactura(facturas);
    if (filas.isEmpty) return const EstadoVacio(PorFactura.sinFacturas);
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

  final List<FilaPorFactura> filas;

  @override
  Widget build(BuildContext context) {
    // Se desplaza la tabla si un nombre largo la ensancha, no la página.
    return SingleChildScrollView(
      key: PorFactura.claveDeLaTabla,
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
            for (final c in columnasPorFactura)
              DataColumn(label: cabecera(c.titulo), numeric: c.alDerecha),
          ],
          rows: [
            for (final fila in filas)
              DataRow(
                // El subtotal y el total se distinguen del detalle por el fondo
                // y la negrita: se ve dónde acaba una factura y empieza otra.
                color: fila.tipo == TipoDeFilaPorFactura.detalle
                    ? null
                    : WidgetStatePropertyAll(Colores.papel),
                cells: [
                  for (final (i, c) in columnasPorFactura.indexed)
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

FontWeight _peso(FilaPorFactura fila) =>
    fila.tipo == TipoDeFilaPorFactura.detalle
    ? FontWeight.w400
    : FontWeight.w700;

/// UNA TARJETA POR FACTURA, para el teléfono.
class _Tarjetas extends StatelessWidget {
  const _Tarjetas({required this.filas});

  final List<FilaPorFactura> filas;

  @override
  Widget build(BuildContext context) {
    // Una tarjeta acaba en su subtotal; el total va aparte, al final.
    final tarjetas = <List<FilaPorFactura>>[];
    var abierta = <FilaPorFactura>[];
    for (final fila in filas) {
      abierta.add(fila);
      if (fila.tipo != TipoDeFilaPorFactura.detalle) {
        tarjetas.add(abierta);
        abierta = <FilaPorFactura>[];
      }
    }
    if (abierta.isNotEmpty) tarjetas.add(abierta);

    return Column(
      key: PorFactura.claveDeLasTarjetas,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final t in tarjetas) _Tarjeta(filas: t)],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.filas});

  final List<FilaPorFactura> filas;

  @override
  Widget build(BuildContext context) {
    final factura = filas.first.factura;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colores.linea)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Aire.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (factura != null) ...[
            Text(
              factura.rotulo,
              style: Tipos.texto(tamano: 13.5, peso: FontWeight.w700),
            ),
            Text(
              factura.cliente,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(tamano: 11.5, color: Colores.tintaSuave),
            ),
            const SizedBox(height: Aire.xs),
          ],
          for (final fila in filas) _Renglon(fila: fila),
        ],
      ),
    );
  }
}

/// Un renglón de la tarjeta: el título (la columna ancha) y debajo las cifras,
/// cada una con su rótulo pegado. En un `Wrap` y no en columnas con `Expanded`:
/// un `Expanded` reparte el ancho a partes y le puede tocar una celda de 39 px,
/// que es como se rompe una palabra letra a letra.
class _Renglon extends StatelessWidget {
  const _Renglon({required this.fila});

  final FilaPorFactura fila;

  @override
  Widget build(BuildContext context) {
    final negrita = fila.tipo != TipoDeFilaPorFactura.detalle;
    String titulo = '';
    final cifras = <Widget>[];
    for (final (i, c) in columnasPorFactura.indexed) {
      final texto = fila.celdas[i];
      if (c.ancha) {
        titulo = texto;
      } else if (!c.esLaFactura && texto.isNotEmpty) {
        cifras.add(_Cifra(texto, c.titulo, negrita: negrita));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titulo.isNotEmpty)
            Text(
              titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(
                tamano: 13,
                peso: negrita ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          if (cifras.isNotEmpty)
            Wrap(
              spacing: Aire.md,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: cifras,
            ),
        ],
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
