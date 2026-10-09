/// Los modelos de Almacenes.
///
/// Los almacenes **viven en Accesos**, no en la base del reparto: esta pantalla
/// los lee y los escribe alli. Por eso son objetos de JSON y no tablas de
/// Drift — la copia local que si existe (`warehouses`) la escribe la bajada y
/// sirve para medir distancias, no para editar.
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
  /// tiene; `''` = se vació A PROPÓSITO y Accesos lo quita. Solo viaja si es
  /// distinto de `null` (ver [aJson]): quien no conoce el código no puede
  /// borrárselo a otro que lo puso entre medias.
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

  AlmacenDeAccesos copiar({
    String? nombre,
    Object? codigo = _sinTocar,
    Object? direccion = _sinTocar,
    Object? latitud = _sinTocar,
    Object? longitud = _sinTocar,
    bool? principal,
    bool? activo,
  }) => AlmacenDeAccesos(
    id: id,
    nombre: nombre ?? this.nombre,
    codigo: codigo == _sinTocar ? this.codigo : codigo as String?,
    direccion: direccion == _sinTocar ? this.direccion : direccion as String?,
    latitud: latitud == _sinTocar ? this.latitud : latitud as double?,
    longitud: longitud == _sinTocar ? this.longitud : longitud as double?,
    principal: principal ?? this.principal,
    activo: activo ?? this.activo,
  );

  static const _sinTocar = Object();

  Map<String, Object?> aJson() => <String, Object?>{
    if (id != null) 'id': id,
    'nombre': nombre,
    if (codigo != null) 'codigo': codigo,
    'direccion': direccion,
    'latitud': latitud,
    'longitud': longitud,
    'principal': principal,
    'activo': activo,
  };
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

/// Sólo puede haber **un** principal. Se resuelve aqui, sobre la lista entera,
/// porque lo que se manda a Accesos es la lista entera: marcar uno sin desmarcar
/// los demas deja dos principales y entonces el punto desde el que se mide
/// depende del orden en que vuelvan.
List<AlmacenDeAccesos> conUnSoloPrincipal(
  List<AlmacenDeAccesos> lista,
  int cual,
) => [
  for (final (indice, a) in lista.indexed) a.copiar(principal: indice == cual),
];
