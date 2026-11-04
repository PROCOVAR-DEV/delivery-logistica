// EL CABLEADO de «Reparto Distribuidor»: la guia de la ruta, el GPS y su subida.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import '../pantallas/rutas/estado/proveedores_rutas.dart';
import 'aviso_de_ubicacion.dart';
import 'gps/puntos_locales.dart';
import 'gps/recorrido_gps.dart';
import 'gps/servicio_de_ubicacion.dart';
import 'gps/subida_del_recorrido.dart';
import 'guia_de_ruta.dart';
import 'modo_distribuidor.dart';

final puntosGpsLocalesProvider = Provider<PuntosGpsLocales>(
  (ref) => PuntosGpsLocales(ref.watch(baseProvider)),
);

/// Como esta el permiso de ubicacion, para DECIRLO con palabras (no impide trabajar).
class PermisoVisto extends Notifier<PermisoDeUbicacion?> {
  @override
  PermisoDeUbicacion? build() => null;

  void poner(PermisoDeUbicacion p) => state = p;
}

final permisoDeUbicacionProvider =
    NotifierProvider<PermisoVisto, PermisoDeUbicacion?>(PermisoVisto.new);

final recorridoGpsProvider = Provider<RecorridoGps>((ref) {
  final recorrido = RecorridoGps(
    puntos: ref.watch(puntosGpsLocalesProvider),
    servicio: ref.watch(servicioDeUbicacionProvider),
    reloj: ref.watch(relojProvider),
    haAceptado: () async =>
        (await ref.read(aceptacionDeUbicacionProvider.future)) != null,
    alVerElPermiso: (p) =>
        ref.read(permisoDeUbicacionProvider.notifier).poner(p),
  );
  // Al cambiar de persona (otra base) o salir, el flujo anterior se apaga.
  ref.onDispose(() => unawaited(recorrido.sincronizar(const {})));
  return recorrido;
});

final guiaDeRutaProvider = Provider<GuiaDeRuta>(
  (ref) => GuiaDeRuta(
    acciones: ref.watch(accionesDeRutaProvider),
    consultas: ref.watch(consultasRutasProvider),
    recorrido: ref.watch(modoDistribuidorProvider)
        ? ref.watch(recorridoGpsProvider)
        : null,
  ),
);

/// La subida de los puntos, que cuelga del ciclo de sincronizacion (tras la cola
/// de apuntes). Solo en el modo distribuidor: la app de siempre no sube puntos.
final subidaDelRecorridoProvider = Provider<SubidaDelRecorrido?>((ref) {
  if (!ref.watch(modoDistribuidorProvider)) return null;
  final cliente = ref.watch(clienteApiProvider);
  return SubidaDelRecorrido(
    ref.watch(puntosGpsLocalesProvider),
    (cuerpo) => cliente.mandar<Object?>('POST', '/track', cuerpo),
    reloj: ref.watch(relojProvider),
  );
});

/// EL MOTOR: mira las rutas en curso y la aceptacion y enciende o apaga el GPS.
/// Se monta una vez (el envoltorio de `main_distribuidor.dart`).
final motorDelGpsProvider = Provider<void>((ref) {
  if (!ref.watch(modoDistribuidorProvider)) return;
  void mirar() {
    final rutas = ref.read(todasLasRutasProvider).value ?? const <Ruta>[];
    unawaited(
      ref.read(recorridoGpsProvider).sincronizar({
        for (final r in rutas)
          if (r.status == EstadoRuta.enCurso) r.id,
      }),
    );
  }

  ref.listen(todasLasRutasProvider, (_, _) => mirar(), fireImmediately: true);
  ref.listen(aceptacionDeUbicacionProvider, (_, _) => mirar());
});
