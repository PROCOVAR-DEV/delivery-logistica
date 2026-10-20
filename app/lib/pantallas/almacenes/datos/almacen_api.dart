/// Los modelos de Almacenes.
///
/// La matriz de almacenes esta en el CRM y **Reparto solo los lee**: llegan de
/// `GET /api/almacenes` como objetos de JSON, no como tablas de Drift. La copia
/// local que si existe (`warehouses`) la escribe la bajada y sirve para medir
/// distancias.
library;

double? _numero(Object? valor) => switch (valor) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

class AlmacenDeAccesos {
  const AlmacenDeAccesos({
    required this.nombre,
    this.id,
    this.codigo,
    this.direccion,
    this.latitud,
    this.longitud,
    this.principal = false,
    this.activo = true,
  });

  factory AlmacenDeAccesos.deJson(Map<String, Object?> j) => AlmacenDeAccesos(
    id: j['id'] as String?,
    nombre: (j['nombre'] as String?) ?? '',
    codigo: j['codigo'] as String?,
    direccion: j['direccion'] as String?,
    latitud: _numero(j['latitud']),
    longitud: _numero(j['longitud']),
    principal: j['principal'] == true,
    // `activo` ausente se toma como activo: lo que no se dijo no puede
    // desactivar un almacen por el que hoy pasa el camion.
    activo: j['activo'] != false,
  );

  final String? id;
  final String nombre;

  /// El `objectCode` de Ventra: con él Reparto sabe de qué almacén sale cada
  /// pedido (el pedido trae el código, no el nombre). `null` = no se sabe o no
  /// tiene.
  final String? codigo;
  final String? direccion;
  final double? latitud;
  final double? longitud;
  final bool principal;
  final bool activo;

  /// Sin punto no se puede cotizar nada desde aqui.
  bool get sinPunto => latitud == null || longitud == null;

  /// La etiqueta de la lista y del selector.
  String get titulo => nombre.trim().isEmpty ? '(sin nombre)' : nombre.trim();
}

class SucursalDeAccesos {
  const SucursalDeAccesos({
    required this.codigo,
    required this.nombre,
    required this.almacenes,
  });

  factory SucursalDeAccesos.deJson(Map<String, Object?> j) => SucursalDeAccesos(
    codigo: (j['codigo'] as String?) ?? '',
    nombre: (j['nombre'] as String?) ?? '',
    almacenes: [
      for (final a in (j['almacenes'] as List<Object?>?) ?? const [])
        AlmacenDeAccesos.deJson(a! as Map<String, Object?>),
    ],
  );

  final String codigo;
  final String nombre;
  final List<AlmacenDeAccesos> almacenes;
}
