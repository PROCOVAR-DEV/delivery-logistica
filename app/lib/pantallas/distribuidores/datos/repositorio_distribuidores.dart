import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/red/cliente_api.dart';

/// Un distribuidor tal como lo cuenta `GET /api/distribuidores`.
///
/// Es la persona responsable de la entrega y de devolver las facturas entregadas
/// (issue 7 de Amado, 14/10/2026): el chofer mismo si va en triciclo, un empleado
/// de Procovar si el vehiculo es rentado. Es un nombre que cada sucursal mantiene
/// en su lista, no una persona de Accesos.
class DistribuidorDelServidor {
  const DistribuidorDelServidor({
    required this.id,
    required this.nombre,
    required this.activo,
    this.sucursalId,
    this.sucursal,
    this.rutas = 0,
  });

  factory DistribuidorDelServidor.deJson(Map<Object?, Object?> j) =>
      DistribuidorDelServidor(
        id: j['id']! as String,
        nombre: (j['nombre'] as String?) ?? '',
        // Ausente es ACTIVO, como en la bajada: solo un `false` explicito es un
        // retiro.
        activo: j['activo'] != false,
        sucursalId: j['sucursalId'] as String?,
        sucursal: j['sucursal'] as String?,
        rutas: (j['rutas'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String nombre;
  final bool activo;
  final String? sucursalId;

  /// El nombre de la sucursal. Para quien ve las ocho listas, que de otro modo no
  /// distingue a dos «Juan» de sucursales distintas.
  final String? sucursal;

  /// Cuantas rutas lo usan. Con alguna, quitarlo lo RETIRA en vez de borrarlo.
  final int rutas;
}

/// Lo que paso con un `DELETE`: el servidor lo borra de verdad si ninguna ruta lo
/// usa y lo RETIRA si alguna lo usa, y la pantalla tiene que poder decir cual de
/// las dos porque no son lo mismo.
enum ResultadoDeQuitar { borrado, retirado }

/// El nomenclador de distribuidores, contra el servidor.
///
/// **Se mantiene CON CONEXION**, igual que la flota y los tipos de vehiculo: es
/// una lista que la sucursal configura una vez, y encolar altas de personas es
/// complejidad (ids provisionales, rechazos tardios por un nombre repetido) a
/// cambio de nada. Lo que SI funciona sin conexion es ELEGIRLO al crear la ruta:
/// el nomenclador baja con el dia (`Colecciones.distribuidores`).
///
/// Cada escritura que el servidor confirma se copia TAMBIEN a la tabla local con lo
/// que el servidor devolvio, y no con lo que se mando. No inventa nada que la
/// bajada no vaya a traer despues igual (`insertOnConflictUpdate`): lo unico que
/// hace es que el selector de «Nueva ruta», que mira la base, lo vea en el acto y
/// no cuando termine el ciclo que dispara el aviso en vivo.
class RepositorioDistribuidores {
  RepositorioDistribuidores(this._api, this._base);

  final ClienteApi _api;
  final BaseLocal _base;

  /// Todos, activos y retirados: el cajon tiene que ver lo retirado para volver
  /// a activarlo.
  Future<List<DistribuidorDelServidor>> listar() async {
    final datos = await _api.pedir<List<Object?>>('/distribuidores');
    return [
      for (final d in datos.whereType<Map<Object?, Object?>>())
        DistribuidorDelServidor.deJson(d),
    ];
  }

  Future<DistribuidorDelServidor> crear(String nombre) async {
    final dato = await _api.mandar<Map<String, Object?>>(
      'POST',
      '/distribuidores',
      <String, Object?>{'nombre': nombre},
    );
    return _guardado(dato);
  }

  /// Renombra y/o activa o retira. Solo se manda lo que se cambia.
  Future<DistribuidorDelServidor> cambiar(
    String id, {
    String? nombre,
    bool? activo,
  }) async {
    final dato = await _api.mandar<Map<String, Object?>>(
      'PATCH',
      '/distribuidores/$id',
      <String, Object?>{'nombre': ?nombre, 'activo': ?activo},
    );
    return _guardado(dato);
  }

  /// Borra si ninguna ruta lo usa; si no, lo retira. El servidor decide, y la
  /// respuesta lo dice.
  Future<ResultadoDeQuitar> quitar(String id) async {
    final dato = await _api.mandar<Map<String, Object?>>(
      'DELETE',
      '/distribuidores/$id',
      null,
    );
    final retirado = dato['retirado'] == true;
    if (retirado) {
      await (_base.update(_base.distribuidores)..where((d) => d.id.equals(id)))
          .write(const DistribuidoresCompanion(activo: Value(false)));
    } else {
      await (_base.delete(_base.distribuidores)..where((d) => d.id.equals(id)))
          .go();
    }
    return retirado ? ResultadoDeQuitar.retirado : ResultadoDeQuitar.borrado;
  }

  Future<DistribuidorDelServidor> _guardado(Map<Object?, Object?> dato) async {
    final d = DistribuidorDelServidor.deJson(dato);
    await _base
        .into(_base.distribuidores)
        .insertOnConflictUpdate(
          DistribuidoresCompanion.insert(
            id: d.id,
            nombre: d.nombre,
            activo: Value(d.activo),
            branchId: Value(d.sucursalId),
            updatedAt: Value(DateTime.tryParse('${dato['updatedAt']}')?.toLocal()),
          ),
        );
    return d;
  }
}
