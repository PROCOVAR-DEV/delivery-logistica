import 'package:collection/collection.dart';

import '../../../nucleo/almacenes/almacen_de_referencia.dart';
import '../../../nucleo/base/base.dart';

/// DE QUÉ ALMACÉN SALE UNA ZONA — Jose, 15/10/2026: «cada columna del tablero se
/// pueda configurar de dónde sale, así los tableros quedan preparados para cada
/// punto sin estar cambiando arriba de lado a lado».
///
/// La regla se escribe DOS veces —aquí y en el servidor (`api/internal/api/
/// tablero.go`, `puntoDeSalida`)— porque el aparato arma la ruta sin señal, y
/// las ata `docs/punto-de-salida.casos.json` (§3-bis). En corto:
///
///  1. sin punto (`null` o `""`): el principal, con [AlmacenDeReferencia.elegir]
///     — **no** el elegido arriba en la cabecera, que el servidor no conoce;
///  2. con punto: ESE, si es de la sucursal, está activo y tiene ubicación;
///  3. si no, **no se cae al principal**: se dice por qué, con las palabras del
///     servidor y en ese orden (existe → activo → ubicación).
///
/// [deLaSucursal] son los almacenes de la sucursal de la zona, activos o no.
({Almacen? sale, String? no}) puntoDeSalida({
  required String? almacenId,
  required Iterable<Almacen> deLaSucursal,
  required String sucursal,
}) {
  if (almacenId == null || almacenId.isEmpty) {
    final principal = AlmacenDeReferencia.elegir(deLaSucursal);
    return principal == null
        ? (sale: null, no: '$sucursal no tiene ningún almacén con coordenadas')
        : (sale: principal, no: null);
  }
  final a = deLaSucursal.firstWhereOrNull((w) => w.id == almacenId);
  if (a == null) {
    return (sale: null, no: "No existe el almacén '$almacenId' en $sucursal");
  }
  if (!a.activo) {
    return (sale: null, no: '«${a.nombre}» está dado de baja en Accesos');
  }
  // «Sirve para medir» se pregunta a quien lo sabe, una lista de uno.
  if (AlmacenDeReferencia.elegir([a]) == null) {
    return (
      sale: null,
      no: '«${a.nombre}» no tiene la ubicación puesta en Almacenes',
    );
  }
  return (sale: a, no: null);
}

/// El «no» de armar la ruta de una zona cuyo punto no sirve (409 del servidor).
String noSalePorSuPunto(String zona, String no) =>
    'La zona «$zona» no puede salir de su punto de salida: $no. '
    'Elige otro en «Punto de salida».';
