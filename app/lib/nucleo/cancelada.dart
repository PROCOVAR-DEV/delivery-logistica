/// LA FACTURA DEVUELTA Y LA CANCELADA, EN UN SOLO SITIO — issue 25 de Amado, 05/11/2026.
///
/// Una factura que vuelve del camión (`resultado = devuelto`) puede acabar de dos maneras: en OTRA
/// ruta otro día, o CANCELADA porque el cliente se arrepintió. **«Cancelada» es el resultado
/// `cancelado` que ya existía** (Jose: «la cancelada es el cancelado ese»): no hay columna ni estado
/// nuevo. Cancelada y sin ruta YA NO es repartible; sólo la `devuelto` vuelve al pool.
///
///  * [esDevuelta]: devuelta y esperando otra ruta (la que lleva la marca «Devuelta»).
///  * [esCancelada]: cancelada, con o sin ruta (la de la pestaña «Canceladas»).
///  * [noEstaCancelada] / [noEstaCanceladaSql]: la condición que sacan de TODA lista repartible
///    (se cuela dentro de `entraEnRuta`/`entraEnRutaSql`, `regla_de_entrada.dart`).
///
/// La fecha de la cancelación es `resultadoAt` y la nota `resultadoNota`: quien la canceló no consta
/// en la fila (sólo en el registro del servidor).
library;

import 'package:drift/drift.dart';

import 'base/base.dart';

/// Devuelta del camión y SIN ruta: sigue en el pool y volverá a salir en «Sin colocar».
bool esDevuelta(Pedido p) =>
    p.resultado == ResultadoParada.devuelto && p.routeId == null;

/// Cancelada: lo marcó así quien cerró la ruta o la oficina desde una devuelta.
bool esCancelada(Pedido p) => p.resultado == ResultadoParada.cancelado;

/// «No es cancelada». NULL no es «cancelado»: un `NOT (resultado = 'cancelado')` con el resultado nulo
/// da NULL y dejaría fuera las facturas nuevas, que son la mayoría.
Expression<bool> noEstaCancelada($OrdersTable o) =>
    o.resultado.isNull() | o.resultado.equals(ResultadoParada.cancelado).not();

/// [noEstaCancelada] para el SQL a mano (el alias de `orders` es `o`).
const noEstaCanceladaSql = "o.resultado IS NOT 'cancelado'";

/// Los «no» de cancelar, LETRA POR LETRA los del servidor (`POST /api/orders/{id}/cancelar`, 409/400).
/// `yaCancelada` es el único que no consta literal: el servidor lo marca con `codigo: ya_cancelada` y el
/// sync lo da por hecho. Si el servidor dice otra cosa, manda él (la web enseña su motivo literal).
abstract final class MotivosDeCancelar {
  static const noExiste = 'No encontrado';
  static const yaCancelada = 'La factura ya está cancelada';
  static const enUnaRuta =
      'La factura va en una ruta: sólo se puede cancelar una factura devuelta que ya no esté en ninguna';
  static const noDevuelta =
      'La factura no está devuelta: sólo se puede cancelar una factura que volvió devuelta en el camión';
  static const enUnConduce =
      'La factura va dentro de un conduce: cancela el conduce entero desde su factura principal';
  static const notaLarga = 'La nota no puede pasar de $maxNota caracteres';

  static const maxNota = 500;
}

/// ¿Se puede cancelar? `null` = sí; si no, el literal del porqué. Lo usa la acción para rechazar y el
/// cajón para no ofrecer el botón y DECIR por qué: son la misma pregunta.
String? porQueNoSePuedeCancelar(Pedido p) {
  if (esCancelada(p)) return MotivosDeCancelar.yaCancelada;
  if (p.routeId != null) return MotivosDeCancelar.enUnaRuta;
  if (p.conducePrincipalId != null) return MotivosDeCancelar.enUnConduce;
  if (p.resultado != ResultadoParada.devuelto) {
    return MotivosDeCancelar.noDevuelta;
  }
  return null;
}
