// LAS LLAMADAS DE LA DISTRIBUCION, siempre EN VIVO contra el servidor (tambien en la APK y en Windows).
//
// Nada de esto se guarda en la base del aparato: el enlace de la ruta y el GPS viven en el servidor, y una copia vieja del enlace
// (que ya se soltó) mandaría al distribuidor a una ruta que ya no es suya. Sin red, el fallo sale con su motivo; no se finge.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/cola/provisionales.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/red/cliente_api.dart';
import '../../../nucleo/red/fallos.dart';
import '../../vehiculos/estado/estado_vehiculos.dart'
    show repositorioVehiculosProvider;
import 'modelos.dart';

/// El texto que se le enseña a la persona cuando una llamada falla: el literal del servidor, o «Sin conexión…».
String motivoDelFallo(Object e) => e is FalloApi ? e.mensaje : '$e';

Map<String, Object?> _mapa(Object? o) =>
    (o as Map?)?.cast<String, Object?>() ?? const {};

class ApiDistribucion {
  ApiDistribucion(this._api);

  final ClienteApi _api;

  /// `GET /api/routes/{id}/enlace`: el enlace vivo, o `sin_enlace`.
  Future<EnlaceDeRuta> enlaceDe(String rutaId) async => EnlaceDeRuta.deJson(
    _mapa(await _api.pedir<Object?>('/routes/$rutaId/enlace')),
  );

  /// `POST /api/routes/{id}/enlace`: crea el enlace (o devuelve el que ya hay). Con [renovar] suelta la ruta de su teléfono y da
  /// uno nuevo. 409 = la ruta ya está cerrada: sale como `Rechazo` con el motivo del servidor.
  Future<EnlaceDeRuta> crearEnlace(
    String rutaId, {
    bool renovar = false,
  }) async => EnlaceDeRuta.deJson(
    _mapa(
      await _api.mandar<Object?>('POST', '/routes/$rutaId/enlace', {
        if (renovar) 'renovar': true,
      }),
    ),
  );

  Future<RecorridoReal> recorrido(String rutaId) async => RecorridoReal.deJson(
    _mapa(await _api.pedir<Object?>('/routes/$rutaId/track')),
  );

  Future<List<RutaDelHistorial>> historialDe(String vehiculoId) async {
    final j = _mapa(
      await _api.pedir<Object?>('/vehicles/$vehiculoId/historial'),
    );
    return [
      for (final r in (j['rutas'] as List?) ?? const [])
        RutaDelHistorial.deJson(_mapa(r)),
    ];
  }

  Future<List<DistribuidorAhora>> dondeEstanAhora() async {
    final j = _mapa(await _api.pedir<Object?>('/tracking/ahora'));
    return [
      for (final d in (j['distribuidores'] as List?) ?? const [])
        DistribuidorAhora.deJson(_mapa(d)),
    ];
  }

  /// Las rutas con su estado de revisión (`GET /api/routes`, el mismo contrato de siempre más `revisadaAt`).
  Future<List<RevisionDeRuta>> revisiones() async {
    final lista = await _api.pedir<Object?>('/routes');
    return [
      for (final r in (lista as List?) ?? const [])
        RevisionDeRuta.deJson(_mapa(r)),
    ];
  }

  /// La segunda llave: `POST /api/routes/{id}/revision {"confirmar":true}`.
  Future<void> confirmarRevision(String rutaId) => _api.mandar<Object?>(
    'POST',
    '/routes/$rutaId/revision',
    {'confirmar': true},
  );
}

final apiDistribucionProvider = Provider<ApiDistribucion>(
  (ref) => ApiDistribucion(ref.watch(clienteApiProvider)),
);

/// El recorrido real de una ruta. `autoDispose`: al cerrar el cajón se suelta, y al abrirlo otra vez se vuelve a pedir (el GPS
/// de una ruta en curso cambia cada pocos segundos).
final recorridoRealProvider = FutureProvider.autoDispose
    .family<RecorridoReal, String>(
      (ref, rutaId) => ref.watch(apiDistribucionProvider).recorrido(rutaId),
    );

final historialDelVehiculoProvider = FutureProvider.autoDispose
    .family<List<RutaDelHistorial>, String>(
      (ref, vehiculoId) =>
          ref.watch(apiDistribucionProvider).historialDe(vehiculoId),
    );

final dondeEstanAhoraProvider =
    FutureProvider.autoDispose<List<DistribuidorAhora>>(
      (ref) => ref.watch(apiDistribucionProvider).dondeEstanAhora(),
    );

final revisionesProvider = FutureProvider.autoDispose<List<RevisionDeRuta>>(
  (ref) => ref.watch(apiDistribucionProvider).revisiones(),
);

/// La revisión de UNA ruta, sacada de la lista. Nula = no se sabe (cargando, sin red) o la ruta no pasa por revisión.
final revisionDeLaRutaProvider = Provider.autoDispose
    .family<RevisionDeRuta?, String>(
      (ref, rutaId) =>
          (ref.watch(revisionesProvider).value ?? const <RevisionDeRuta>[])
              .where((r) => r.id == rutaId && r.seRevisa)
              .firstOrNull,
    );

/// Quién lleva cada vehículo por defecto, leído del servidor (`GET /api/vehicles`, el mismo del listado), tambien en la APK: la copia
/// local de la flota no trae ese campo todavía.
final distribuidorDeCadaVehiculoProvider =
    FutureProvider.autoDispose<Map<String, String?>>(
      (ref) async => {
        for (final v in await ref.watch(repositorioVehiculosProvider).listar())
          v.id: v.distribuidorId,
      },
    );

/// ¿La ruta ya existe en el servidor? Una ruta armada sin red tiene un id `local-…` que el servidor no conoce.
bool rutaYaEstaEnElServidor(String rutaId) =>
    !Provisionales.esProvisional(rutaId);
