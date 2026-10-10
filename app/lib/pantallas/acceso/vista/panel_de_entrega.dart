import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/portero.dart';
import '../../../nucleo/cola/apunte.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/sincro/entrega_a_revision.dart';
import '../../../nucleo/sincro/escucha_de_revision.dart';
import '../../../nucleo/sincro/flujo_de_revision.dart';
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

  /// Llegó un aviso en vivo mientras había una consulta o una entrega en vuelo.
  /// No se descarta (la decisión pudo tomarse DESPUÉS de que esa consulta leyera)
  /// ni se lanza otra encima: se apunta y se hace UNA vuelta más al acabar.
  bool _otraVuelta = false;

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
    if (_otraVuelta) unawaited(alAvisoDeRevision());
    return r;
  }

  /// «Actualizar estados», con un toque.
  Future<void> actualizar() => _consultar(deOficio: false);

  /// El servidor avisó en vivo de que se decidió un apunte de esta persona, o el
  /// flujo acaba de (re)abrirse y hay que ponerse al día (`EscuchaDeRevision`): la
  /// MISMA consulta que «Actualizar estados», sin que nadie pulse. **Solo habla
  /// cuando cambia algo o falla de verdad**: es una consulta automática, y un «Sin
  /// novedades.» que sale solo se deja de leer. Idempotente: dos avisos seguidos no
  /// hacen dos consultas a la vez.
  Future<void> alAvisoDeRevision() => _consultar(deOficio: true);

  Future<void> _consultar({required bool deOficio}) async {
    if (state.ocupado) {
      if (deOficio) _otraVuelta = true;
      return;
    }
    var enSilencio = deOficio;
    do {
      _otraVuelta = false;
      final antes = state;
      // De oficio no se borra lo que la persona está leyendo mientras se consulta.
      state = enSilencio
          ? EstadoDeEntrega(
              ocupado: true,
              mensaje: antes.mensaje,
              resultado: antes.resultado,
            )
          : const EstadoDeEntrega(ocupado: true);
      final r = await ref.read(entregaARevisionProvider).actualizarEstados();
      // El panel pudo desmontarse mientras se preguntaba.
      if (!ref.mounted) return;
      state = enSilencio && r.bien && r.cambiaron == 0 && !r.truncado
          ? antes
          : EstadoDeEntrega(mensaje: _textoDe(r), resultado: r.resultado);
      // Las vueltas de más son siempre de oficio: nadie pulsó nada.
      enSilencio = true;
    } while (_otraVuelta);
  }

  static String _textoDe(ResumenDeConsulta r) {
    final espera = r.esperar == null
        ? ''
        : ' Vuelve a intentarlo en ${r.esperar!.inSeconds} s.';
    return r.bien
        ? (r.truncado
              ? 'Hay más entregas de las que caben en la lista: puede que '
                    'alguna ya decidida no se vea todavía.'
              : (r.cambiaron == 0
                    ? 'Sin novedades.'
                    : '${r.cambiaron} ${r.cambiaron == 1 ? "cambio" : "cambios"} '
                          'de estado.'))
        : '${r.error ?? ""}$espera'.trim();
  }
}

final controlDeEntregaProvider =
    NotifierProvider.autoDispose<ControlDeEntrega, EstadoDeEntrega>(
      ControlDeEntrega.new,
    );

/// Cómo se abre el flujo del aviso en vivo. Aparte para poder cambiarlo en una
/// prueba: el de verdad va contra `Entorno.syncUrl`, que es una constante de
/// compilación (y trae producción de valor por defecto).
final abridorDeFlujoDeRevisionProvider = Provider<AbridorDeFlujoDeRevision>(
  (ref) => abrirFlujoDeRevision,
);

/// EL AVISO EN VIVO de `/sin-permiso`: cuándo vive la escucha. Lo explica el
/// porqué de [EscuchaDeRevision]; aquí solo está CUÁNDO, y son cuatro cosas a la vez:
///
///  1. **Es el aparato**: la web no tiene cola ni entrega (CLAUDE.md §1), así que
///     no abre nada, ni mira la base.
///  2. **La persona sigue en `sinPermiso`.** Si recupera el permiso, cierra sesión o
///     la sesión muere, el portero cambia de estado y esto se vuelve a calcular:
///     la escucha se suelta aunque el panel siguiera montado un instante.
///  3. **Hay algo `enRevision`.** Sin nada que esperar no hay a quién avisar, y se
///     paga una conexión (la de allá es cara). Al decidirse el último, se cierra.
///  4. **El panel está montado**: el panel hace `watch` de esto, y al ser
///     `autoDispose` se cierra al desmontarlo.
///
/// Devuelve `null` cuando no toca abrir. Una prueba que no va de esto lo pone a
/// `null` (una escucha «sin servidor»).
final escuchaDeRevisionProvider = Provider.autoDispose<EscuchaDeRevision?>((ref) {
  if (!ref.watch(trabajaSinConexionProvider)) return null;

  final portero = ref.read(porteroProvider);
  void alCambiarElPortero() {
    if (portero.estado != EstadoDeAcceso.sinPermiso) ref.invalidateSelf();
  }

  portero.addListener(alCambiarElPortero);
  ref.onDispose(() => portero.removeListener(alCambiarElPortero));
  if (portero.estado != EstadoDeAcceso.sinPermiso) return null;

  final hayAlgoEnRevision = ref.watch(
    enRevisionDeLaPersonaProvider.select((v) => v.value?.isNotEmpty ?? false),
  );
  if (!hayAlgoEnRevision) return null;

  final escucha = EscuchaDeRevision(
    abrir: ref.watch(abridorDeFlujoDeRevisionProvider),
    credenciales: () => ref.read(entregaARevisionProvider).paraElAvisoEnVivo(),
    alAviso: () =>
        unawaited(ref.read(controlDeEntregaProvider.notifier).alAvisoDeRevision()),
  )..iniciar();
  ref.onDispose(escucha.parar);
  return escucha;
});

/// El panel de `/sin-permiso`.
///
///  * Con cambios sin enviar: lo dice y ofrece «Entregar a revisión».
///  * Ya entregado: dice en que esta cada uno («Entregado…», «Aplicado por…»,
///    «Descartado por…: motivo», «No se pudo aplicar…») y ofrece «Actualizar
///    estados».
///  * **Sin nada de eso, no sale.**
///
/// **Se entera solo** de que un revisor decidio: mientras esta montado y hay algo
/// `enRevision`, [escuchaDeRevisionProvider] mantiene UNA conexion SSE y consulta
/// lo mismo que «Actualizar estados» cuando el servidor avisa y al (re)abrirse el
/// flujo (`docs/sin-permiso.md`, «El aviso en vivo»). El boton se queda de
/// respaldo, y no hay sondeo.
///
/// **No navega a ningun sitio**: se queda en `/sin-permiso`. Lo unico que saca de
/// aqui es volver a entrar, y lo hace la persona con su boton.
class PanelDeEntrega extends ConsumerWidget {
  const PanelDeEntrega({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El aviso en vivo vive mientras este panel esté montado (aunque no pinte
    // nada: sin cola ni entregas devuelve un hueco, pero el widget sigue aquí).
    ref.watch(escuchaDeRevisionProvider);
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
