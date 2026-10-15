// EL NÚMERO DE FACTURA DE UN PEDIDO, EN UN SOLO SITIO.
//
// Issue 9 de Amado: «Adicionar la factura como elemento de referencia
// importante: adicionar a los reportes la columna de facturas».
//
// ## Cuál de los dos números es
//
// Hay DOS en el pedido y no son lo mismo:
//
//  * `operationNumber` — el número de operación de la factura
//    (`PTB25-261005-1479`). **Es el «conduce» de Amado** (Jose, 07/10/2026:
//    «no hay dato ni columna aparte»), el mismo con el que ya se nombra al pedido
//    en el tablero, en los rechazos del armado y en el cierre de ruta. Viene en
//    TODO pedido del espejo.
//  * `facturaNumero` — el número con el que Ventra cuadró el pedido. Sólo existe
//    cuando hay factura (`facturaEstado` igual o cambiado) y no es el que Amado
//    usa para operar.
//
// Por eso manda `operationNumber` y `facturaNumero` es el RESPALDO, para el
// pedido al que le falte el primero. Si faltan los dos no hay número (`null`):
// nunca un texto inventado.
//
// ## Dos escritos, atados por un fichero (CLAUDE.md §3-bis)
//
// La regla vive también en Go (`api/internal/api/informes.go`,
// `numeroDeFactura`), porque `GET /api/reports` contesta lo mismo que arma esta
// pantalla con su base local. Los dos leen
// `docs/numero-de-factura.casos.json`: si alguien cambia un lado, el otro se
// pone rojo. Cualquier otra pantalla que quiera enseñar «el número de factura»
// tiene que llamar a [NumeroDeFactura.de] y no repetir esta regla.

import 'dart:math' show min;

/// Los números de factura de un grupo de pedidos: los que hay, sin repetir y en
/// el orden en que aparecen, y cuántos pedidos se quedaron sin número.
typedef FacturasDeUnGrupo = ({List<String> facturas, int sinFactura});

abstract final class NumeroDeFactura {
  /// El número de [operationNumber] y, si falta, el de [facturaNumero]. Sin
  /// blancos en los extremos. `null` = el pedido no tiene ninguno.
  static String? de({String? operationNumber, String? facturaNumero}) =>
      _limpio(operationNumber) ?? _limpio(facturaNumero);

  /// Vacío y blancos son «falta», no un número: un `''` que ganara a la
  /// factura dejaría en blanco una columna que se podía rellenar.
  static String? _limpio(String? texto) {
    final recortado = texto?.trim();
    return (recortado == null || recortado.isEmpty) ? null : recortado;
  }

  /// Junta los [numeros] de los pedidos de un camión (o de lo que sea que se
  /// agrupe). Sin repetidos —la ida y la vuelta del mismo pedido llevan el mismo
  /// número— y en el orden de aparición. Un `null` no se descarta: se cuenta en
  /// `sinFactura`, para que quien lea la fila sepa que le falta alguno.
  ///
  /// **No toca las cuentas de órdenes ni los totales**: es sólo la lista de
  /// referencias.
  static FacturasDeUnGrupo agrupar(Iterable<String?> numeros) {
    final vistos = <String>{};
    final facturas = <String>[];
    var sinFactura = 0;
    for (final numero in numeros) {
      if (numero == null) {
        sinFactura++;
      } else if (vistos.add(numero)) {
        facturas.add(numero);
      }
    }
    return (facturas: facturas, sinFactura: sinFactura);
  }

  /// Cómo se dice en una celda la lista de un camión.
  ///
  /// [visibles] `null` = todas (el Excel, que tiene sitio). Con un tope (la
  /// pantalla) se dicen las primeras y **cuántas quedan fuera**: cortar la lista
  /// sin decirlo es esconder facturas. Los pedidos sin número se dicen aparte.
  /// Sin nada que decir, la raya.
  ///
  /// [maxCaracteres] es el techo de una celda de Excel (32.767 letras): una hoja
  /// con una celda más larga NO ABRE («contenido ilegible»), y es peor que una
  /// lista cortada que lo dice. Se corta por números enteros, nunca a mitad de
  /// uno.
  static String texto(
    FacturasDeUnGrupo grupo, {
    String separador = ', ',
    int? visibles,
    int? maxCaracteres,
  }) {
    final todas = grupo.facturas;
    var cuantas = visibles == null ? todas.length : min(visibles, todas.length);
    if (maxCaracteres != null) {
      var largo = 0;
      for (var i = 0; i < cuantas; i++) {
        largo += todas[i].length + separador.length;
        if (largo > maxCaracteres) {
          cuantas = i;
          break;
        }
      }
    }
    final partes = <String>[];
    if (todas.isNotEmpty) {
      final resto = todas.length - cuantas;
      partes.add(
        [
          if (cuantas > 0) todas.take(cuantas).join(separador),
          if (resto > 0) (cuantas > 0 ? 'y $resto más' : '$resto facturas'),
        ].join(' '),
      );
    }
    if (grupo.sinFactura > 0) partes.add('${grupo.sinFactura} sin número');
    return partes.isEmpty ? '—' : partes.join(' · ');
  }
}
