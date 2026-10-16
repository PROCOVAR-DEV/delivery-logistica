// LA FECHA DE LA FACTURA ENTRE DOS DÍAS, EN HORA DE CUBA, en UN sitio — issue 16 de Amado,
// 16/10/2026.
//
// «Debería ser por la FECHA DE FACTURACIÓN: [el cliente] tiene 6 facturas el día 15, pero se
// generaron de pedidos creados los días 14 (4) y el 15 (2). Cuando se busca lo que hay que
// entregar el 15 solo salen 2 en lugar de 6.» Pedidos, «Sin colocar» del Tablero y el paso de
// pedidos del asistente filtraban por la fecha DEL PEDIDO; el logístico trabaja contra la
// factura. Ahora los tres filtran por `coalesce(factura_at, order_date, created_at)` y el día
// es el de CUBA, no el de UTC ni el del huso del aparato (la web en un navegador de fuera, o
// una prueba en UTC, contarían otro día). La misma regla en el servidor
// (`api/db/queries/*.sql`); las ata `docs/fecha-de-la-factura.casos.json` (CLAUDE.md §3-bis).

import 'package:drift/drift.dart';

import 'base/base.dart';

const _horaDelCambio = 5; // los dos cambios de hora de Cuba son a las 05:00 UTC

/// El `n`-ésimo domingo de [mes] de [anio], a las 05:00 UTC.
DateTime _domingo(int anio, int mes, int n) {
  final primero = DateTime.utc(anio, mes, 1);
  final hastaElDomingo = (7 - primero.weekday) % 7; // weekday: lunes 1 … domingo 7
  return DateTime.utc(anio, mes, 1 + hastaElDomingo + 7 * (n - 1), _horaDelCambio);
}

/// UTC-4 con el horario de verano de Cuba —del segundo domingo de marzo al primer domingo
/// de noviembre— y UTC-5 el resto. Los cambios de `America/Havana` que usa Postgres.
Duration _desfaseDeCuba(DateTime instanteUtc) {
  final anio = instanteUtc.year;
  final verano =
      !instanteUtc.isBefore(_domingo(anio, 3, 2)) &&
      instanteUtc.isBefore(_domingo(anio, 11, 1));
  return Duration(hours: verano ? -4 : -5);
}

/// El DÍA de Cuba de un instante, como `DateTime.utc(año, mes, día)` a medianoche (sólo vale
/// el día: comparar con `==` con otro de estos). No depende del huso del aparato.
DateTime diaEnCuba(DateTime instante) {
  final u = instante.toUtc();
  final c = u.add(_desfaseDeCuba(u));
  return DateTime.utc(c.year, c.month, c.day);
}

/// El primer instante (UTC) del [dia] de Cuba: el que ya es de ese día y cuyo anterior no.
/// De los dos candidatos (medianoche con UTC-4 y con UTC-5) vale el primero que cae en ese
/// día: así el día del cambio de marzo (la 00:00 no existe) empieza a la 01:00 y el de
/// noviembre (la 00:00 se repite) en la primera.
DateTime inicioDelDiaEnCuba(DateTime dia) {
  final base = DateTime.utc(dia.year, dia.month, dia.day);
  final mismo = DateTime.utc(dia.year, dia.month, dia.day);
  for (final horas in const [4, 5]) {
    final candidato = base.add(Duration(hours: horas));
    if (diaEnCuba(candidato) == mismo) return candidato;
  }
  return base.add(const Duration(hours: 5));
}

/// La fecha de la factura de un pedido entre [desde] y [hasta], **los dos días incluidos**:
/// `coalesce(facturaAt, orderDate, createdAt)` —sin factura manda la fecha del pedido, y sin
/// ninguna la de su copia— pasada al día de Cuba. Cada extremo es opcional; `null` sin
/// ninguno de los dos (no acota). [desde] y [hasta] son DÍAS (sólo cuentan año, mes y día).
///
/// Por arriba se corta en el inicio del día SIGUIENTE (`<`), no a las 23:59:59.999: «del 3
/// al 3» tiene que traer el 3 hasta el último instante. Un pedido sin ninguna fecha queda
/// fuera en cuanto hay un extremo.
Expression<bool>? fechaDeLaFacturaEntre(
  $OrdersTable o,
  DateTime? desde,
  DateTime? hasta,
) {
  if (desde == null && hasta == null) return null;
  final cuando = coalesce<DateTime>([o.facturaAt, o.orderDate, o.createdAt]);
  final inicio = desde == null ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true) : inicioDelDiaEnCuba(desde);
  final fin = hasta == null
      ? DateTime.utc(9999)
      : inicioDelDiaEnCuba(DateTime.utc(hasta.year, hasta.month, hasta.day + 1));
  return cuando.isBiggerOrEqualValue(inicio) & cuando.isSmallerThanValue(fin);
}

/// El día de la factura como se enseña en una tarjeta, `15/10/2026` (el formato de
/// `fechaCorta`), contado en Cuba. `null` si no hay fecha.
String? diaDeLaFacturaEnCuba(DateTime? facturadaEl) {
  if (facturadaEl == null) return null;
  final d = diaEnCuba(facturadaEl);
  return '${d.day}/${d.month}/${d.year}';
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
