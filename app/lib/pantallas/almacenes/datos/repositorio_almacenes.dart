import 'package:reparto/nucleo/red/cliente_api.dart';

import 'almacen_api.dart';

/// Almacenes, de SOLO LECTURA.
///
/// La matriz esta en el CRM (decision de Jose, 20/10/2026): Reparto ya no crea,
/// edita ni borra almacenes, solo los consulta. Se pide a la API en cada visita;
/// no hay cola ni escritura.
class RepositorioAlmacenes {
  RepositorioAlmacenes(this._api);

  final ClienteApi _api;

  Future<List<SucursalDeAccesos>> listar() async {
    final datos = await _api.pedir<Map<String, Object?>>('/almacenes');
    return [
      for (final s in (datos['sucursales'] as List<Object?>?) ?? const [])
        SucursalDeAccesos.deJson(s! as Map<String, Object?>),
    ];
  }
}
