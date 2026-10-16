import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import 'flota_local.dart';
import 'vehiculo_api.dart';

/// Vehiculos.
///
/// # EN LA WEB: contra el servidor y sólo contra el servidor
///
/// La web no tiene base local ni cola (`CLAUDE.md` §1). Sin red lo dice; no finge
/// que guardo.
///
/// # EN LA APK Y EL ESCRITORIO: contra la base local y la cola — 16/10/2026
///
/// Decia aqui que la flota «se configura en la oficina y nadie da de alta un camion
/// en la calle». Amado (issue 14) lo desmintio: el logistico de Santiago, con el
/// escritorio de Windows y sin conexion, no veia ni camiones, ni tipos, ni
/// distribuidores, y no podia crear ninguno. Con [_local] puesto, cada gesto escribe
/// la fila local y encola su apunte (`FlotaLocal`). **Una excepcion**: quien ve las
/// ocho sucursales (SUPER ADMIN, DESARROLLADOR) no tiene UNA sucursal a la que
/// atribuir un alta hecha sin red, y la cola sube con su alcance de «todas»: un
/// camion nacido asi saldria compartido. Sus altas van al servidor, como en la web.
///
/// La verdad de si hay red **es si la peticion salio**: un `FalloDeRed` de
/// `ClienteApi`. `connectivity_plus` es una pista y aqui ni se mira.
class RepositorioVehiculos {
  RepositorioVehiculos(this._api, [this._local]);

  final ClienteApi _api;

  /// `null` en la web.
  final FlotaLocal? _local;

  /// ¿Este gesto va a la base local y la cola? Los ALTAS de quien ve las ocho no.
  Future<bool> _alAparato({bool alta = false}) async {
    final local = _local;
    if (local == null) return false;
    return !(alta && await local.veTodas());
  }

  Future<List<VehiculoDeLaApi>> listar() async {
    final datos = await _api.pedir<List<Object?>>('/vehicles');
    return [
      for (final v in datos) VehiculoDeLaApi.deJson(v! as Map<String, Object?>),
    ];
  }

  Future<AjustesDeLaApi> ajustes() async {
    final datos = await _api.pedir<Map<String, Object?>>('/settings');
    return AjustesDeLaApi.deJson(datos, tipos: await _tipos());
  }

  /// TODOS, retirados incluidos: `guardarTipos` necesita ver los retirados para
  /// reactivar uno en vez de chocar con su nombre.
  Future<List<TipoDeVehiculo>> _tipos() async {
    final datos = await _api.pedir<List<Object?>>('/vehicle-types');
    return [
      for (final t in datos) TipoDeVehiculo.deJson(t! as Map<String, Object?>),
    ];
  }

  Future<void> crear(DatosVehiculo datos) async {
    if (await _alAparato(alta: true)) return _local!.crearVehiculo(datos);
    await _api.mandar<Object?>('POST', '/vehicles', datos.aJson());
  }

  Future<void> editar(String id, DatosVehiculo datos) async {
    if (await _alAparato()) return _local!.editarVehiculo(id, datos);
    await _api.mandar<Object?>('PATCH', '/vehicles/$id', datos.aJson());
  }

  /// El servidor desasocia de rutas y pedidos antes de borrar, asi que el
  /// historico de lo repartido no se va con el camion.
  ///
  /// Eso no quita la pregunta, y aqui decia que si: «sin confirmacion, como la
  /// de Next». La pregunta la pone la pantalla desde el 01/10/2026
  /// (`_Rejilla._borrarPreguntando`). Lo que el servidor conserva es el
  /// historico; lo que no devuelve nadie es el camion.
  Future<void> eliminar(String id) async {
    if (await _alAparato()) return _local!.eliminarVehiculo(id);
    await _api.mandar<Object?>('DELETE', '/vehicles/$id', null);
  }

  Future<void> marcarDisponible(String id) async {
    const cambios = <String, Object?>{'status': 'available'};
    if (await _alAparato()) return _local!.cambiarVehiculo(id, cambios);
    await _api.mandar<Object?>('PATCH', '/vehicles/$id', cambios);
  }

  /// La exclusividad —un solo vehiculo por tipo y sucursal— la resuelve el
  /// servidor en su transaccion. Aqui no se desmarca nada a mano: dos sitios
  /// decidiendo lo mismo es como se acaba con dos marcados.
  Future<void> usarParaDomicilio(String id) async {
    const cambios = <String, Object?>{'usarParaDomicilio': true};
    if (await _alAparato()) return _local!.cambiarVehiculo(id, cambios);
    await _api.mandar<Object?>('PATCH', '/vehicles/$id', cambios);
  }

  /// Crea el tipo, o REACTIVA el retirado que ya se llama igual.
  ///
  /// Un tipo retirado (lo uso algun camion y se «quito») sigue en la tabla, asi
  /// que un POST con su nombre daba 409 «ya existe» mientras el desplegable no
  /// lo enseñaba: callejon sin salida. Al reactivarlo **no se manda el costo si
  /// no se escribio uno**: el retirado puede tenerlo guardado y mandar `null`
  /// lo borraba (el costo por km es el que cotiza el domicilio).
  Future<void> crearTipo(TipoDeVehiculo tipo) async {
    if (await _alAparato(alta: true)) return _local!.crearTipo(tipo);
    final retirado = (await _tipos())
        .where((t) => t.nombre == tipo.nombre && !t.activo)
        .firstOrNull;
    if (retirado != null) return _reactivar(retirado, tipo);
    await _api.mandar<Object?>('POST', '/vehicle-types', tipo.aJson());
  }

  Future<void> _reactivar(TipoDeVehiculo retirado, TipoDeVehiculo tipo) =>
      _api.mandar<Object?>('PATCH', '/vehicle-types/${retirado.id}', {
        'activo': true,
        if (tipo.costoKmUsd != null) 'costoKmUsd': tipo.costoKmUsd,
      });

  /// Pone el catalogo como lo deja el cajon, tipo a tipo contra
  /// `/api/vehicle-types` (la tabla; `PUT /settings` ya no guarda tipos).
  ///
  /// [abiertos] es lo que el cajon tenia AL ABRIRSE. De ahi salen las tres
  /// cosas, y por eso es obligatorio:
  ///
  ///  * **Se borran sólo los que estaban y ya no están.** Un tipo que creo otra
  ///    persona mientras el cajon seguia abierto no está en `abiertos` y NO se
  ///    borra por no estar. El servidor decide si se borra de verdad (nadie lo
  ///    usa) o se retira (algun camion lo usa).
  ///  * **Sólo se manda lo que ESTA persona cambio** (nombre y/o costo, y sólo
  ///    ese campo). Comparar con el servidor de ahora hacia que una fila que no
  ///    tocaste pisara el cambio de otra persona: el costo por km que otro subio
  ///    a 1.5 volvia a 0.9 sin que nadie lo viera.
  ///  * Una fila sin `id` es nueva (o un retirado que se vuelve a escribir).
  ///
  /// Y DOS COSAS QUE SE ROMPIAN, cazadas por la auditoria del 14/10/2026:
  ///
  ///  * **Se borra PRIMERO y se vuelve a mirar el servidor DESPUES** para las
  ///    filas nuevas. Quitar `van` y volver a escribir `van` encontraba el viejo
  ///    en la foto de antes de borrar y el tipo se quedaba sin existir.
  ///  * **Un 404 al borrar es «ya estaba borrado»**, no un fallo: si la
  ///    peticion se cayo a medias, el reintento repite el `DELETE`.
  ///
  /// No es atomico (una peticion por tipo). Si una falla cuando otras ya
  /// entraron, se lanza [GuardadoAMedias] para que la pantalla NO diga «no se
  /// guardo nada»: sí se guardó una parte.
  Future<void> guardarTipos(
    List<TipoDeVehiculo> tipos, {
    required List<TipoDeVehiculo> abiertos,
  }) async {
    if (await _alAparato()) {
      return _guardarTiposEnElAparato(_local!, tipos, abiertos);
    }
    final antes = {
      for (final t in abiertos)
        if (t.id != null) t.id!: t,
    };
    final siguen = {for (final t in tipos) t.id};
    var aplicadas = 0;
    try {
      for (final id in antes.keys.where((id) => !siguen.contains(id))) {
        try {
          await _api.mandar<Object?>('DELETE', '/vehicle-types/$id', null);
          aplicadas++;
        } on Rechazo catch (e) {
          if (e.codigo != 404) rethrow;
        }
      }

      List<TipoDeVehiculo>? hay;
      for (final t in tipos) {
        final previo = antes[t.id];
        if (previo != null) {
          final cambios = <String, Object?>{
            if (previo.nombre != t.nombre) 'nombre': t.nombre,
            // `null` SI viaja: es vaciar el costo, que es lo que el usuario
            // hizo al borrar el numero.
            if (previo.costoKmUsd != t.costoKmUsd) 'costoKmUsd': t.costoKmUsd,
          };
          if (cambios.isEmpty) continue;
          await _api.mandar<Object?>(
            'PATCH',
            '/vehicle-types/${t.id}',
            cambios,
          );
          aplicadas++;
          continue;
        }
        // Fila nueva: si ya existe (un reintento, o lo creo otra persona) no se
        // repite; si está retirado se reactiva; si no existe, se crea.
        hay ??= await _tipos();
        final existente = hay.where((x) => x.nombre == t.nombre).firstOrNull;
        if (existente != null && existente.activo) continue;
        if (existente != null) {
          await _reactivar(existente, t);
        } else {
          await _api.mandar<Object?>('POST', '/vehicle-types', t.aJson());
        }
        aplicadas++;
      }
    } on FalloApi catch (e) {
      if (aplicadas > 0) throw GuardadoAMedias(e, aplicadas);
      rethrow;
    }
  }
}

/// Lo mismo que `guardarTipos` contra el servidor, sobre la base local y la cola: se
/// borra lo que estaba y ya no esta, se manda sólo lo que ESTA persona cambio, y lo
/// nuevo se crea (o reactiva). Sin red no hay «a medias»: cada paso es local.
Future<void> _guardarTiposEnElAparato(
  FlotaLocal local,
  List<TipoDeVehiculo> tipos,
  List<TipoDeVehiculo> abiertos,
) async {
  final antes = {
    for (final t in abiertos)
      if (t.id != null) t.id!: t,
  };
  final siguen = {for (final t in tipos) t.id};
  for (final id in antes.keys.where((id) => !siguen.contains(id))) {
    await local.quitarTipo(id);
  }
  for (final t in tipos) {
    final previo = antes[t.id];
    if (previo == null) {
      await local.crearTipo(t);
      continue;
    }
    final cambios = <String, Object?>{
      if (previo.nombre != t.nombre) 'nombre': t.nombre,
      if (previo.costoKmUsd != t.costoKmUsd) 'costoKmUsd': t.costoKmUsd,
    };
    if (cambios.isNotEmpty) await local.cambiarTipo(t.id!, cambios);
  }
}

/// Una escritura se cayo cuando [aplicadas] anteriores ya habian entrado.
class GuardadoAMedias implements Exception {
  const GuardadoAMedias(this.causa, this.aplicadas);

  final FalloApi causa;
  final int aplicadas;
}
