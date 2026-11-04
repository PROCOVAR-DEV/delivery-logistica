// «Preparando el mapa de Cuba… (una sola vez)»: lo que se ve en el primer arranque
// mientras se copia el mapa del APK. Reanuda solo; con un fallo se dice y se puede
// reintentar. No toca la red.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diseno/tema.dart';
import '../../mapa/proveedores_de_mapa.dart';
import '../../nucleo/registro/registro.dart';
import 'copiador_nativo.dart';
import 'instalador_del_mapa.dart';

final copiadorDeAssetProvider = Provider<CopiadorDeAsset>(
  (ref) => CopiadorNativo(),
);

class EstadoDeLaPreparacion {
  const EstadoDeLaPreparacion.trabajando({this.copiados = 0, this.total = 0})
    : error = null,
      lista = false;
  const EstadoDeLaPreparacion.lista()
    : copiados = 0,
      total = 0,
      error = null,
      lista = true;
  const EstadoDeLaPreparacion.fallo(String this.error)
    : copiados = 0,
      total = 0,
      lista = false;

  final int copiados;
  final int total;
  final String? error;
  final bool lista;

  double? get avance => total <= 0 ? null : (copiados / total).clamp(0.0, 1.0);
}

class PreparacionDelMapa extends Notifier<EstadoDeLaPreparacion> {
  @override
  EstadoDeLaPreparacion build() {
    unawaited(Future<void>.microtask(_instalar));
    return const EstadoDeLaPreparacion.trabajando();
  }

  Future<void> reintentar() async {
    state = const EstadoDeLaPreparacion.trabajando();
    await _instalar();
  }

  Future<void> _instalar() async {
    try {
      final carpeta = await ref.read(carpetaDelMapaProvider.future);
      if (carpeta == null) {
        state = const EstadoDeLaPreparacion.lista();
        return;
      }
      await InstaladorDelMapa(
        carpeta,
        ref.read(copiadorDeAssetProvider),
      ).instalar(
        alAvanzar: (c, t) {
          // Sin repintar en cada trozo: con ~1 % de diferencia basta.
          final antes = state;
          if (t > 0 && (c - antes.copiados) * 100 < t && c < t) return;
          state = EstadoDeLaPreparacion.trabajando(copiados: c, total: t);
        },
      );
      // El mapa ya esta donde lo busca el resto del codigo.
      ref.invalidate(paqueteGuardadoProvider);
      state = const EstadoDeLaPreparacion.lista();
    } on MapaIncluidoFallo catch (e) {
      Registro.aviso('mapa incluido: $e');
      state = EstadoDeLaPreparacion.fallo(e.mensaje);
    } on Object catch (e, pila) {
      Registro.fallo('mapa incluido: fallo inesperado', e, pila);
      state = EstadoDeLaPreparacion.fallo('No se pudo preparar el mapa: $e');
    }
  }
}

final preparacionDelMapaProvider =
    NotifierProvider<PreparacionDelMapa, EstadoDeLaPreparacion>(
      PreparacionDelMapa.new,
    );

/// La pantalla completa de la primera vez.
class PantallaPreparandoElMapa extends ConsumerWidget {
  const PantallaPreparandoElMapa({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(preparacionDelMapaProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Preparando el mapa de Cuba… (una sola vez)',
                key: ValueKey('preparando-mapa-titulo'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              if (e.error == null)
                LinearProgressIndicator(
                  key: const ValueKey('preparando-mapa-progreso'),
                  value: e.avance,
                )
              else ...[
                Text(
                  e.error!,
                  key: const ValueKey('preparando-mapa-error'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                BotonPrincipal(
                  key: const ValueKey('preparando-mapa-reintentar'),
                  icono: Icons.refresh,
                  texto: 'Reintentar',
                  alPulsar: () => ref
                      .read(preparacionDelMapaProvider.notifier)
                      .reintentar(),
                ),
              ],
              if (e.avance != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${(e.avance! * 100).round()} %',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
