import 'bandeja.dart';

/// LO QUE UN APUNTE HACE, EN PALABRAS — y cuanto va a hacer una orden de golpe.
///
/// El revisor aplica con SU autoridad lo que otro dejo escrito, y lo que ve es
/// `DELETE /routes/5d6e7f80-…`: un uuid crudo que no dice nada. Auditoria de
/// seguridad de la bandeja, M2 (09/10/2026): un autor hostil puede dejar hasta
/// 500 `DELETE` y «Aplicar todo en orden» los ejecutaba con un toque. Dos
/// remedios, y los dos viven aqui:
///
///  * [queHace]: la ruta dicha en castellano a partir de su FORMA. Lo que no
///    reconoce **devuelve `null` y se muestra crudo**: no se inventa.
///  * [ResumenDeAplicar]: el recuento que se le pone delante al revisor antes de
///    aplicar en bloque, y la regla de cuando hace falta un segundo paso.
///
/// La lista de formas es la que la cola emite de verdad (`acciones_rutas.dart`,
/// `tablero/datos/repositorio.dart`) y la que deja pasar la lista blanca de
/// `sync` (`/routes…` y `/board…`). Un id es cualquier segmento.
final List<({String metodo, RegExp forma, String texto})> _formas = [
  for (final f in <(List<String>, String, String)>[
    (['POST'], r'routes', 'Crear una ruta'),
    (['PATCH', 'PUT'], r'routes/[^/]+', 'Modificar una ruta'),
    (['DELETE'], r'routes/[^/]+', 'Borrar una ruta'),
    (['DELETE'], r'routes/[^/]+/stops/[^/]+', 'Quitar una parada de una ruta'),
    (['POST'], r'routes/[^/]+/results', 'Registrar el resultado de una ruta'),
    (['POST'], r'board/columns', 'Crear una zona'),
    (['PATCH', 'PUT'], r'board/columns/orden', 'Reordenar las zonas'),
    (['PATCH', 'PUT'], r'board/columns/[^/]+', 'Modificar una zona'),
    (['DELETE'], r'board/columns/[^/]+', 'Borrar una zona'),
    (['POST'], r'board/columns/[^/]+/route', 'Crear una ruta desde una zona'),
    (['PUT', 'POST'], r'board/placements/[^/]+', 'Mover un pedido a una zona'),
    (['DELETE'], r'board/placements/[^/]+', 'Sacar un pedido de una zona'),
  ])
    for (final m in f.$1)
      (metodo: m, forma: RegExp('^/(?:api/)?${f.$2}\$'), texto: f.$3),
];

/// «Borrar una ruta», «Crear una zona»… o `null` si la forma no se reconoce
/// (entonces solo se ve el metodo y la ruta crudos).
///
/// Se ignora el `?query` y un `/api` delante; el metodo se compara sin mayusculas.
String? queHace(String metodo, String ruta) {
  final camino = ruta.split('?').first;
  final m = metodo.toUpperCase();
  for (final f in _formas) {
    if (f.metodo == m && f.forma.hasMatch(camino)) return f.texto;
  }
  return null;
}

/// ¿Pide confirmacion UN apunte suelto? Borrar y modificar si; crear, mover y
/// registrar resultados no (son lo corriente de una jornada).
bool pideConfirmacionSuelta(String metodo) {
  final m = metodo.toUpperCase();
  return m == 'DELETE' || m == 'PATCH';
}

/// Hasta aqui (inclusive) «Aplicar todo» no pide escribir el numero.
const maximoSinSegundoPaso = 25;

/// EL RECUENTO DE «APLICAR TODO EN ORDEN»: lo que el servidor va a procesar.
///
/// Cuenta lo que espera decision (`en_revision` y `rechazado`): lo `aplicado` y
/// lo `descartado` el servidor lo salta.
class ResumenDeAplicar {
  ResumenDeAplicar._(this.total, this.porMetodo, this.porTipo, this.rutas);

  factory ResumenDeAplicar.de(List<ApunteEnRevision> apuntes) {
    final pendientes = apuntes.where((a) => a.estado.esperaDecision).toList();
    final porMetodo = <String, int>{};
    final porTipo = <String, int>{};
    final rutas = <String, int>{};
    for (final a in pendientes) {
      final metodo = a.metodo.toUpperCase();
      porMetodo[metodo] = (porMetodo[metodo] ?? 0) + 1;
      final tipo = queHace(a.metodo, a.ruta) ?? '$metodo ${a.ruta}';
      final clave = '$metodo|$tipo';
      porTipo[clave] = (porTipo[clave] ?? 0) + 1;
      final exacta = '$metodo ${a.ruta}';
      rutas[exacta] = (rutas[exacta] ?? 0) + 1;
    }
    return ResumenDeAplicar._(pendientes.length, porMetodo, porTipo, rutas);
  }

  final int total;

  /// `{DELETE: 3, POST: 12}`.
  final Map<String, int> porMetodo;

  /// `{'DELETE|Borrar una ruta': 3, …}`: por tipo legible (o crudo si no se
  /// reconoce).
  final Map<String, int> porTipo;

  /// Las rutas exactas distintas, `'DELETE /routes/<id>'`, con cuantas veces.
  final Map<String, int> rutas;

  int get borrados => porMetodo['DELETE'] ?? 0;

  /// Lo que se destaca en rojo: cualquier DELETE.
  bool get hayBorrados => borrados > 0;

  /// **SEGUNDO PASO**: con cualquier DELETE, o con mas de [maximoSinSegundoPaso]
  /// cambios, no basta pulsar: hay que escribir el numero. Un toque no puede
  /// ejecutar 500 borrados con la autoridad del revisor.
  bool get exigeEscribirElNumero => hayBorrados || total > maximoSinSegundoPaso;

  /// Los metodos en el orden en que se leen: lo que borra primero.
  List<MapEntry<String, int>> get metodosOrdenados {
    const prioridad = {'DELETE': 0, 'PATCH': 1, 'PUT': 2, 'POST': 3};
    return porMetodo.entries.toList()..sort((a, b) {
      final pa = prioridad[a.key] ?? 9;
      final pb = prioridad[b.key] ?? 9;
      return pa != pb ? pa.compareTo(pb) : a.key.compareTo(b.key);
    });
  }
}
