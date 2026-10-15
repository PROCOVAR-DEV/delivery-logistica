// LA FECHA DEL PEDIDO ENTRE DOS DÍAS, en UN sitio.
//
// La misma pregunta la hacen Pedidos, «Sin colocar» del Tablero y el paso 4 del asistente
// de nueva ruta. Hasta el 15/10/2026 los dos últimos sólo sabían de UN día y cada uno lo
// escribía a su manera; Amado pidió el rango en los dos (issue 13, punto 1). Tres copias de
// la misma regla son tres sitios donde se separan (`CLAUDE.md` §3-bis).

import 'package:drift/drift.dart';

import 'base/base.dart';

/// `orderDate` entre [desde] y [hasta], **los dos días incluidos**, y `createdAt` cuando el
/// pedido no tiene fecha de PEDIDO: si no, desaparecería de todos los rangos. Cada extremo
/// es opcional; `null` sin ninguno de los dos (no acota). Es el mismo `OR` del servidor.
///
/// Por arriba se corta en la medianoche del día SIGUIENTE (`<`), no a las 23:59:59.999: «del
/// 3 al 3» tiene que traer los del 3 hasta el último instante.
Expression<bool>? fechaDelPedidoEntre(
  $OrdersTable o,
  DateTime? desde,
  DateTime? hasta,
) {
  if (desde == null && hasta == null) return null;
  final inicio = desde == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime(desde.year, desde.month, desde.day);
  final fin = hasta == null
      ? DateTime(9999)
      : DateTime(hasta.year, hasta.month, hasta.day + 1);
  return (o.orderDate.isBiggerOrEqualValue(inicio) &
          o.orderDate.isSmallerThanValue(fin)) |
      (o.orderDate.isNull() &
          o.createdAt.isBiggerOrEqualValue(inicio) &
          o.createdAt.isSmallerThanValue(fin));
}

/// El dia que escribe la hoja del pre-despacho, `AAAA-MM-DD` como la de Next, y
/// **sólo cuando el rango es un dia**: con varios no dice ninguno, porque
/// escribir uno de los dos seria mentir sobre lo que hay debajo. La usan Pedidos
/// y el paso 4 del asistente: dos copias se separan justo al cambiar el filtro.
String? diaDeLaHojaEntre(DateTime? desde, DateTime? hasta) {
  if (desde == null || desde != hasta) return null;
  return '${desde.year.toString().padLeft(4, '0')}-'
      '${desde.month.toString().padLeft(2, '0')}-'
      '${desde.day.toString().padLeft(2, '0')}';
}
