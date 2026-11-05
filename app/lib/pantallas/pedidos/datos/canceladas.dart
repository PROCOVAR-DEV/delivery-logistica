// LA VISTA «CANCELADAS» (issue 25 de Amado, 05/11/2026): las facturas con resultado `cancelado`, por
// periodo, para sacar reportes. Se lee de la base local como todo (sin conexión funciona entera).
//
// «Cancelada» es el resultado `cancelado` de siempre (`nucleo/cancelada.dart`): entran las que canceló
// el chofer o la logística al cerrar una ruta y las que la oficina canceló desde una devuelta. La fecha
// es `resultadoAt` (hora de Cuba, `nucleo/fecha_de_la_factura.dart`) y la nota `resultadoNota`. Quién la
// canceló NO consta en la fila (sólo en el registro del servidor): no se inventa una columna.
//
// La lista y su contador salen del MISMO [ConsultasCanceladas.donde] (CLAUDE.md §3-bis): una prueba los
// ata, no este comentario.

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/fecha_de_la_factura.dart';
import '../../../nucleo/numero_de_factura.dart';
import '../../informes/datos/hoja_de_calculo.dart';

class ConsultasCanceladas {
  ConsultasCanceladas(this._base);

  final BaseLocal _base;

  /// Cuántas se pintan de una vez; el contador y el Excel llevan TODAS.
  static const porVista = 200;

  /// CUÁNDO se canceló: `resultadoAt` y, si una cancelada de antes de esta versión no lo trae, la última vez
  /// que el servidor tocó la fila (`updatedAt`), que para una cancelada es casi siempre su cancelación.
  /// Mejor eso que perderla de cualquier periodo.
  Expression<DateTime> _cuando($OrdersTable o) =>
      coalesce<DateTime>([o.resultadoAt, o.updatedAt]);

  /// Las canceladas de [sucursalId] (todas si es nulo) cuya cancelación cae entre [desde] y [hasta], los
  /// dos días de Cuba incluidos. Los miembros de un conduce cuentan: cada factura cancelada es una fila
  /// del reporte (se cancelan con su principal).
  Expression<bool> donde({
    DateTime? desde,
    DateTime? hasta,
    String? sucursalId,
  }) {
    final o = _base.orders;
    Expression<bool> todo = o.resultado.equals(ResultadoParada.cancelado);
    if (sucursalId != null && sucursalId.isNotEmpty) {
      todo = todo & o.branchId.equals(sucursalId);
    }
    final fecha = instanteEntreDiasDeCuba(_cuando(o), desde, hasta);
    return fecha == null ? todo : todo & fecha;
  }

  /// La más reciente primero; las que no traen fecha, al final.
  List<OrderingTerm Function($OrdersTable)> get _orden => [
    (o) => OrderingTerm.desc(_cuando(o), nulls: NullsOrder.last),
    (o) => OrderingTerm.asc(o.id),
  ];

  Stream<List<Pedido>> lista({
    DateTime? desde,
    DateTime? hasta,
    String? sucursalId,
  }) =>
      (_base.select(_base.orders)
            ..where(
              (_) => donde(desde: desde, hasta: hasta, sucursalId: sucursalId),
            )
            ..orderBy(_orden)
            ..limit(porVista))
          .watch();

  Stream<int> contar({DateTime? desde, DateTime? hasta, String? sucursalId}) {
    final cuenta = _base.orders.id.count();
    return (_base.selectOnly(_base.orders)
          ..addColumns([cuenta])
          ..where(donde(desde: desde, hasta: hasta, sucursalId: sucursalId)))
        .watchSingle()
        .map((f) => f.read(cuenta) ?? 0);
  }

  /// TODAS las del periodo (sin el tope de la vista), para el Excel.
  Future<List<Pedido>> todas({
    DateTime? desde,
    DateTime? hasta,
    String? sucursalId,
  }) =>
      (_base.select(_base.orders)
            ..where(
              (_) => donde(desde: desde, hasta: hasta, sucursalId: sucursalId),
            )
            ..orderBy(_orden))
          .get();
}

/// Con el mismo respaldo que la consulta: `resultadoAt` y, si falta, `updatedAt`.
DateTime? cuandoSeCancelo(Pedido p) => p.resultadoAt ?? p.updatedAt;

/// La fecha de la cancelación como se enseña, en hora de Cuba: `5/11/2026 14:30`. `—` si no consta
/// (una cancelada de antes de que la bajada trajera la fecha).
String fechaDeLaCancelacion(DateTime? cuando) => cuando == null
    ? '—'
    : DateFormat('d/M/y H:mm', 'es').format(horaDeCuba(cuando));

/// El nombre del fichero, `canceladas-AAAA-MM-DD.xlsx`.
String nombreDelExcelDeCanceladas(DateTime cuando) {
  final aaaa = cuando.year.toString().padLeft(4, '0');
  final mm = cuando.month.toString().padLeft(2, '0');
  final dd = cuando.day.toString().padLeft(2, '0');
  return 'canceladas-$aaaa-$mm-$dd.xlsx';
}

const nombreDeLaHojaDeCanceladas = 'Canceladas';

/// La hoja del Excel (la misma `Hoja` y el mismo `armarXlsx` de los Reportes): factura, cliente, fecha de
/// cancelación, nota, y una fila de total con la cuenta. Un campo que no se sabe va VACÍO, no inventado.
Hoja hojaDeCanceladas(List<Pedido> filas, {String periodo = ''}) => Hoja(
  nombre: nombreDeLaHojaDeCanceladas,
  filas: [
    if (periodo.isNotEmpty) ['Periodo', periodo],
    ['Factura', 'Cliente', 'Fecha de cancelación (hora de Cuba)', 'Nota'],
    for (final p in filas)
      [
        NumeroDeFactura.de(p.facturaNumero) ?? p.operationNumber ?? '—',
        p.customerName,
        cuandoSeCancelo(p) == null
            ? null
            : fechaDeLaCancelacion(cuandoSeCancelo(p)),
        p.resultadoNota,
      ],
    ['Total canceladas', filas.length],
  ],
);
