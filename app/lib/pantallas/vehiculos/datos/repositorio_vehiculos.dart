import 'package:reparto/nucleo/red/cliente_api.dart';

import 'vehiculo_api.dart';

/// Vehiculos, contra el servidor y **sólo contra el servidor**.
///
/// Esta pantalla NO tiene base local y NO tiene cola, y eso es una decision, no
/// un descuido: la flota se configura una vez y en la oficina. Encolar altas de
/// camiones es complejidad —identificadores provisionales, sustituciones,
/// rechazos que llegan tarde— a cambio de nada, porque nadie da de alta un
/// camion en la calle. Sin red la pantalla lo dice; no finge que guardo.
///
/// La verdad de si hay red **es si la peticion salio**: un `FalloDeRed` de
/// `ClienteApi`. `connectivity_plus` es una pista y aqui ni se mira.
class RepositorioVehiculos {
  RepositorioVehiculos(this._api);

  final ClienteApi _api;

  Future<List<VehiculoDeLaApi>> listar() async {
    final datos = await _api.pedir<List<Object?>>('/vehicles');
    return [
      for (final v in datos) VehiculoDeLaApi.deJson(v! as Map<String, Object?>),
    ];
  }

  Future<AjustesDeLaApi> ajustes() async {
    final datos = await _api.pedir<Map<String, Object?>>('/settings');
    return AjustesDeLaApi.deJson(datos);
  }

  Future<void> crear(DatosVehiculo datos) =>
      _api.mandar<Object?>('POST', '/vehicles', datos.aJson());

  Future<void> editar(String id, DatosVehiculo datos) =>
      _api.mandar<Object?>('PATCH', '/vehicles/$id', datos.aJson());

  /// El servidor desasocia de rutas y pedidos antes de borrar, asi que el
  /// historico de lo repartido no se va con el camion.
  ///
  /// Eso no quita la pregunta, y aqui decia que si: «sin confirmacion, como la
  /// de Next». La pregunta la pone la pantalla desde el 01/10/2026
  /// (`_Rejilla._borrarPreguntando`). Lo que el servidor conserva es el
  /// historico; lo que no devuelve nadie es el camion.
  Future<void> eliminar(String id) =>
      _api.mandar<Object?>('DELETE', '/vehicles/$id', null);

  Future<void> marcarDisponible(String id) => _api.mandar<Object?>(
    'PATCH',
    '/vehicles/$id',
    <String, Object?>{'status': 'available'},
  );

  /// La exclusividad —un solo vehiculo por tipo y sucursal— la resuelve el
  /// servidor en su transaccion. Aqui no se desmarca nada a mano: dos sitios
  /// decidiendo lo mismo es como se acaba con dos marcados.
  Future<void> usarParaDomicilio(String id) => _api.mandar<Object?>(
    'PATCH',
    '/vehicles/$id',
    <String, Object?>{'usarParaDomicilio': true},
  );

  Future<void> guardarTipos(List<TipoDeVehiculo> tipos) =>
      _api.mandar<Object?>('PUT', '/settings', <String, Object?>{
        'tiposVehiculo': [for (final t in tipos) t.aJson()],
      });
}
