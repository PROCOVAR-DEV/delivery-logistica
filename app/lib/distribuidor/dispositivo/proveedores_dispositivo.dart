import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navegacion/portero.dart';
import '../../nucleo/proveedores.dart';
import '../../nucleo/red/entorno.dart';
import '../../nucleo/red/id_del_aparato.dart';
import 'anadir_ruta.dart';
import 'cliente_de_dispositivo.dart';
import 'desvinculador.dart';
import 'vinculo.dart';
import 'renovador_de_dispositivo.dart';

/// El Dio **crudo** de la API: sin `InterceptorSesion`. `reclamar` y `renovar` van
/// sin Authorization.
final dioDeDispositivoProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: Entorno.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    ),
  ),
);

final clienteDeDispositivoProvider = Provider<ClienteDeDispositivo>(
  (ref) => ClienteDeDispositivo(ref.watch(dioDeDispositivoProvider)),
);

/// El `renovadorProvider` del modo distribuidor (`main_distribuidor.dart`).
final renovadorDeDispositivoProvider = Provider<RenovadorDeDispositivo>(
  (ref) => RenovadorDeDispositivo(
    ref.watch(clienteDeDispositivoProvider),
    ref.watch(almacenSesionProvider),
    reloj: ref.watch(relojProvider),
    alDesvincular: () => ref.read(alDesvincularseProvider)?.call(),
  ),
);

/// Vacia la app cuando la oficina desvincula el telefono. Se cuelga de
/// [alDesvincularseProvider] en `main_distribuidor.dart`.
final desvinculadorProvider = Provider<Desvinculador>((ref) {
  final portero = ref.watch(porteroProvider);
  return Desvinculador(
    baseActual: () => ref.read(baseProvider),
    almacen: ref.watch(almacenSesionProvider),
    cambiarAVacio: (aviso) async => portero.desvinculado(aviso),
    // Ya sin sesion: la base es la neutra, donde `AnadirRuta` busca el id y el secreto.
    guardarIdentidad: (id, secreto) async {
      final base = ref.read(baseProvider);
      await base.anotarPreferencia(claveDelDispositivoId, id);
      await base.anotarPreferencia(claveDelSecretoDelTelefono, secreto);
    },
  );
});

final anadirRutaProvider = Provider<AnadirRuta>((ref) {
  final portero = ref.watch(porteroProvider);
  return AnadirRuta(
    cliente: ref.watch(clienteDeDispositivoProvider),
    almacen: ref.watch(almacenSesionProvider),
    // Antes de entrar nadie, la base es la neutra: ahi vive el id hasta el primer enlace.
    leerId: () => ref.read(baseProvider).preferencia(claveDelDispositivoId),
    guardarId: (id) =>
        ref.read(baseProvider).anotarPreferencia(claveDelDispositivoId, id),
    leerSecreto: () =>
        ref.read(baseProvider).preferencia(claveDelSecretoDelTelefono),
    guardarVinculo: (v) async {
      await ref
          .read(baseProvider)
          .anotarPreferencia(claveDelVinculo, v.aJson());
      ref.invalidate(vinculoDelTelefonoProvider);
    },
    nombreDelTelefono: nombreDelAparato,
    esperarAlArranque: () async {
      if (portero.estado != EstadoDeAcceso.comprobando) return;
      final listo = Completer<void>();
      void mirar() {
        if (portero.estado != EstadoDeAcceso.comprobando &&
            !listo.isCompleted) {
          listo.complete();
        }
      }

      portero.addListener(mirar);
      try {
        await listo.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        // Si el arranque no acaba, se sigue: reclamar no depende de el.
      } finally {
        portero.removeListener(mirar);
      }
    },
    entrar: portero.entro,
    bajarRutas: () => ref.read(dispararCicloProvider)('ruta añadida'),
    reloj: ref.watch(relojProvider),
  );
});
