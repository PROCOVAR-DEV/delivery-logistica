import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';

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

  /// Crea el tipo, o REACTIVA el retirado que ya se llama igual.
  ///
  /// Un tipo retirado (lo uso algun camion y se «quito») sigue en la tabla, asi
  /// que un POST con su nombre daba 409 «ya existe» mientras el desplegable no
  /// lo enseñaba: callejon sin salida. Al reactivarlo **no se manda el costo si
  /// no se escribio uno**: el retirado puede tenerlo guardado y mandar `null`
  /// lo borraba (el costo por km es el que cotiza el domicilio).
  Future<void> crearTipo(TipoDeVehiculo tipo) async {
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

/// Una escritura se cayo cuando [aplicadas] anteriores ya habian entrado.
class GuardadoAMedias implements Exception {
  const GuardadoAMedias(this.causa, this.aplicadas);

  final FalloApi causa;
  final int aplicadas;
}
