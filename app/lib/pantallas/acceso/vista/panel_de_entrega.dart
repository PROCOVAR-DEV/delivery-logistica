import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/portero.dart';
import '../../../nucleo/cola/apunte.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/sincro/entrega_a_revision.dart';
import '../datos/textos_de_entrega.dart';

/// LO ENTREGADO A REVISION y lo que falta por entregar, solo APK y escritorio.
/// `docs/bandeja-de-revision.md`, B.5. La web no tiene cola ni entrega
/// (CLAUDE.md §1): quien monta este panel —`PantallaSinPermiso`— no lo monta alli.
final enRevisionDeLaPersonaProvider = StreamProvider.autoDispose<List<Apunte>>(
  (ref) => ref.watch(colaProvider).enRevision(),
);

final decididosPorRevisionProvider = StreamProvider.autoDispose<List<Apunte>>(
  (ref) => ref.watch(colaProvider).decididosPorRevision(),
);

/// Lo que se ve de la ultima entrega o consulta. Vive aparte del widget para que
/// «Cerrar sesión» —que esta fuera del panel y tambien puede entregar— cuente lo
/// que paso en el mismo sitio.
class EstadoDeEntrega {
  const EstadoDeEntrega({this.ocupado = false, this.mensaje, this.resultado});

  final bool ocupado;

  /// El texto ya escrito de lo ultimo que paso.
  final String? mensaje;
  final ResultadoDeEntrega? resultado;
}

class ControlDeEntrega extends Notifier<EstadoDeEntrega> {
  @override
  EstadoDeEntrega build() => const EstadoDeEntrega();

  /// Entrega. **Solo se llama con un toque**: nada en este fichero la dispara por
  /// su cuenta (la persona puede haberse quedado sin permiso por un error de un
  /// administrador, y con un toque queda consentido, contado y reversible).
  Future<ResumenDeEntrega> entregar() async {
    state = const EstadoDeEntrega(ocupado: true);
    final r = await ref.read(entregaARevisionProvider).entregar();
    state = EstadoDeEntrega(
      mensaje: TextosDelPanel.resultado(r),
      resultado: r.resultado,
    );
    return r;
  }

  Future<void> actualizar() async {
    state = const EstadoDeEntrega(ocupado: true);
    final r = await ref.read(entregaARevisionProvider).actualizarEstados();
    final espera = r.esperar == null
        ? ''
        : ' Vuelve a intentarlo en ${r.esperar!.inSeconds} s.';
    state = EstadoDeEntrega(
      mensaje: r.bien
          ? (r.truncado
                ? 'Hay más entregas de las que caben en la lista: puede que '
                      'alguna ya decidida no se vea todavía.'
                : (r.cambiaron == 0
                      ? 'Sin novedades.'
                      : '${r.cambiaron} ${r.cambiaron == 1 ? "cambio" : "cambios"} '
                            'de estado.'))
          : '${r.error ?? ""}$espera'.trim(),
      resultado: r.resultado,
    );
  }
}

final controlDeEntregaProvider =
    NotifierProvider.autoDispose<ControlDeEntrega, EstadoDeEntrega>(
      ControlDeEntrega.new,
    );

/// El panel de `/sin-permiso`.
///
///  * Con cambios sin enviar: lo dice y ofrece «Entregar a revisión».
///  * Ya entregado: dice en que esta cada uno («Entregado…», «Aplicado por…»,
///    «Descartado por…: motivo», «No se pudo aplicar…») y ofrece «Actualizar
///    estados».
///  * **Sin nada de eso, no sale.**
///
/// **No navega a ningun sitio**: se queda en `/sin-permiso`. Lo unico que saca de
/// aqui es volver a entrar, y lo hace la persona con su boton.
class PanelDeEntrega extends ConsumerWidget {
  const PanelDeEntrega({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref.watch(sinSubirProvider).value ?? 0;
    final enRevision = ref.watch(enRevisionDeLaPersonaProvider).value ?? const <Apunte>[];
    final decididos = ref.watch(decididosPorRevisionProvider).value ?? const <Apunte>[];
    final control = ref.watch(controlDeEntregaProvider);

    if (pendientes == 0 && enRevision.isEmpty && decididos.isEmpty) {
      return const SizedBox.shrink();
    }

    final cuerpo = Tipos.texto(tamano: 14, color: Colores.tintaSuave, alto: 1.45);
    final aReentrar = control.resultado != null &&
        TextosDelPanel.seArreglaEntrandoDeNuevo(control.resultado!);

    return Container(
      margin: const EdgeInsets.only(bottom: Aire.xl),
      padding: const EdgeInsets.all(Aire.lg),
      decoration: BoxDecoration(
        border: Border.all(color: Colores.borde),
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pendientes > 0) ...[
            Text(TextosDelPanel.cambiosSinEnviar(pendientes), style: cuerpo),
            const SizedBox(height: Aire.md),
            BotonPrincipal(
              texto: TextosDelPanel.entregar,
              icono: Icons.outbox,
              alPulsar: control.ocupado
                  ? null
                  : () => unawaited(
                      ref.read(controlDeEntregaProvider.notifier).entregar(),
                    ),
            ),
            const SizedBox(height: Aire.sm),
            Text(
              TextosDelPanel.aviso,
              style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
            ),
          ],
          if (control.mensaje != null && control.mensaje!.isNotEmpty) ...[
            const SizedBox(height: Aire.md),
            // Se anuncia al aparecer: es el resultado de lo que se acaba de pulsar.
            Semantics(
              liveRegion: true,
              child: Text(
                control.mensaje!,
                style: Tipos.texto(
                  tamano: 13,
                  peso: FontWeight.w600,
                  color: Colores.tinta,
                ),
              ),
            ),
          ],
          if (aReentrar) ...[
            const SizedBox(height: Aire.md),
            BotonPrincipal(
              texto: TextosDelPanel.reentrar,
              icono: Icons.login,
              // Salir NO borra la cola: al volver a entrar, lo pendiente sube.
              alPulsar: () => unawaited(ref.read(porteroProvider).salir()),
            ),
          ],
          if (enRevision.isNotEmpty || decididos.isNotEmpty) ...[
            const SizedBox(height: Aire.lg),
            for (final a in [...enRevision, ...decididos])
              _FilaDeApunte(apunte: a),
            const SizedBox(height: Aire.sm),
            TextButton.icon(
              onPressed: control.ocupado
                  ? null
                  : () => unawaited(
                      ref.read(controlDeEntregaProvider.notifier).actualizar(),
                    ),
              icon: const Icon(Icons.update),
              label: const Text(TextosDelPanel.actualizar),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaDeApunte extends StatelessWidget {
  const _FilaDeApunte({required this.apunte});

  final Apunte apunte;

  @override
  Widget build(BuildContext context) {
    final estado = TextosDelPanel.estadoDe(apunte);
    if (estado == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Aire.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextosDelPanel.queEs(apunte),
            style: Tipos.texto(tamano: 13, peso: FontWeight.w600, color: Colores.tinta),
          ),
          const SizedBox(height: Aire.xs),
          Text(
            estado,
            style: Tipos.texto(tamano: 13, color: Colores.tintaSuave, alto: 1.4),
          ),
        ],
      ),
    );
  }
}
