import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/cargando.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/identidad/sesion.dart';
import '../datos/bandeja.dart';
import '../datos/quien_revisa.dart';
import '../estado/proveedores_revision.dart';
import 'confirmar_aplicar.dart';
import 'fila_de_apunte.dart';

/// UNA ENTREGA: lo que una persona dejo en revision con una pulsacion.
///
/// Dice **quien** (el nombre del token, nunca el id), **desde que aparato** y
/// **cuando llego**; al abrirla trae los apuntes. Los apuntes no vienen en la
/// lista (pueden ser cientos de KB de cuerpos), asi que solo se piden cuando se
/// abre la entrega.
class TarjetaDeEntrega extends ConsumerStatefulWidget {
  const TarjetaDeEntrega({
    required this.entrega,
    required this.quien,
    super.key,
  });

  final EntregaEnRevision entrega;
  final Sesion? quien;

  @override
  ConsumerState<TarjetaDeEntrega> createState() => _TarjetaDeEntregaState();
}

class _TarjetaDeEntregaState extends ConsumerState<TarjetaDeEntrega> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entrega;
    final tema = Theme.of(context);
    final cuando = e.entregadaAt == null
        ? ''
        : DateFormat('d/M, H:mm', 'es').format(e.entregadaAt!);
    final aparato = e.aparatoNombre ?? 'un aparato';

    return Tarjeta(
      relleno: const EdgeInsets.all(Aire.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _abierta = !_abierta),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.personaNombre ?? 'Una persona sin nombre',
                        style: tema.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Desde $aparato'
                        '${cuando.isEmpty ? '' : ' · entregado el $cuando'}',
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: Colores.gris,
                        ),
                      ),
                      const SizedBox(height: Aire.sm),
                      Wrap(
                        spacing: Aire.sm,
                        runSpacing: 4,
                        children: [
                          if (e.enRevision > 0)
                            Insignia(
                              '${e.enRevision} en revisión',
                              color: Colores.ambar,
                              fondo: Colores.ambarFondo,
                            ),
                          if (e.aplicando > 0)
                            Insignia(
                              '${e.aplicando} aplicándose',
                              color: Colores.ambar,
                              fondo: Colores.ambarFondo,
                            ),
                          if (e.rechazados > 0)
                            Insignia(
                              '${e.rechazados} rechazados',
                              color: Colores.rojo,
                              fondo: Colores.rojoFondo,
                            ),
                          if (e.aplicados > 0)
                            Insignia(
                              '${e.aplicados} aplicados',
                              color: Colores.verde,
                              fondo: Colores.verdeFondo,
                            ),
                          if (e.descartados > 0)
                            Insignia('${e.descartados} descartados'),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  _abierta ? Icons.expand_less : Icons.expand_more,
                  color: Colores.gris,
                ),
              ],
            ),
          ),
          if (_abierta) _Detalle(entrega: e, quien: widget.quien),
        ],
      ),
    );
  }
}

class _Detalle extends ConsumerWidget {
  const _Detalle({required this.entrega, required this.quien});

  final EntregaEnRevision entrega;
  final Sesion? quien;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalle = ref.watch(detalleDeEntregaProvider(entrega.id));
    // El fallo se mira ANTES que el valor: una recarga que no llega no puede
    // dejar en pantalla el estado anterior con pinta de recien traido.
    if (detalle.error case final fallo?) {
      return Padding(
        padding: const EdgeInsets.only(top: Aire.md),
        child: AvisoAmbar(
          'No se pudieron leer los apuntes de esta entrega. $fallo',
          icono: Icons.cloud_off,
        ),
      );
    }
    final datos = detalle.value;
    if (datos == null) {
      return const Cargando(TextosDeRevision.cargando);
    }
    // La cabecera (quien, sucursal) es la de la lista; el detalle trae los
    // apuntes.
    final completa = EntregaEnRevision(
      id: entrega.id,
      aparato: entrega.aparato,
      aparatoNombre: entrega.aparatoNombre,
      persona: entrega.persona,
      personaNombre: entrega.personaNombre,
      sucursal: entrega.sucursal,
      entregadaAt: entrega.entregadaAt,
      apuntes: datos.apuntes,
    );
    final porQueNo = porQueNoPuedeDecidir(quien, completa);
    final decisiones = ref.watch(decisionesDelRevisorProvider);
    final hayAlgunoPorDecidir = datos.apuntes.any(
      (a) => a.estado.esperaDecision,
    );
    final enCursoTodo = decisiones.ocupado(claveDeEntrega(completa));
    final avisoTodo = decisiones.avisos[claveDeEntrega(completa)];
    final parada = decisiones.paradas[claveDeEntrega(completa)];
    final algunoOcupado = decisiones.enCurso.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Aire.md),
        if (porQueNo != null) AvisoAmbar(porQueNo, icono: Icons.lock_outline),
        if (porQueNo == null && hayAlgunoPorDecidir)
          Align(
            alignment: Alignment.centerLeft,
            child: BotonPrincipal(
              texto: enCursoTodo
                  ? TextosDeRevision.enCursoAplicarTodo
                  : TextosDeRevision.aplicarTodo,
              icono: Icons.playlist_add_check,
              // NO aplica: ABRE EL RECUENTO. Aplicar en bloque con un toque deja a un
              // autor hostil ejecutar hasta 500 DELETE con la autoridad del revisor
              // (auditoria de seguridad, M2); solo se sigue si la persona confirma.
              alPulsar: algunoOcupado
                  ? null
                  : () async {
                      final si = await confirmarAplicarTodo(context, completa);
                      if (!si) return;
                      await ref
                          .read(decisionesDelRevisorProvider.notifier)
                          .aplicarTodo(completa);
                    },
            ),
          ),
        if (parada != null)
          _ParadaDeAplicarTodo(parada: parada, entrega: completa),
        if (avisoTodo != null)
          Padding(
            padding: const EdgeInsets.only(top: Aire.sm),
            child: Text(
              avisoTodo,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colores.rojo, fontWeight: FontWeight.w600),
            ),
          ),
        if (datos.apuntes.isEmpty)
          const EstadoVacio(
            'Esta entrega no trae apuntes.',
            icono: Icons.inbox_outlined,
          )
        else
          for (final a in datos.apuntes)
            FilaDeApunte(entrega: completa, apunte: a, motivoDeQueNo: porQueNo),
      ],
    );
  }
}

/// DONDE SE PARO «Aplicar todo en orden», por que (el literal) y cuantos
/// quedaron sin procesar. El servidor se detiene en el primer apunte que no
/// queda aplicado, y callarlo dejaria a la persona creyendo que se aplico todo.
class _ParadaDeAplicarTodo extends StatelessWidget {
  const _ParadaDeAplicarTodo({required this.parada, required this.entrega});

  final ParadaDeAplicarTodo parada;
  final EntregaEnRevision entrega;

  @override
  Widget build(BuildContext context) {
    // El apunte por su metodo y ruta, que es lo que se reconoce; la clave sola no.
    final apunte = entrega.apuntes
        .where((a) => a.clave == parada.clave)
        .firstOrNull;
    final donde = apunte == null
        ? 'el apunte ${parada.clave ?? '?'}'
        : '${apunte.metodo} ${apunte.ruta}';
    return Padding(
      padding: const EdgeInsets.only(top: Aire.sm),
      child: AvisoAmbar(
        '${TextosDeRevision.detenidoEn(donde, parada.sinProcesar)}'
        '${parada.porque == null ? '' : ' Motivo: ${parada.porque}'}',
        icono: Icons.pause_circle_outline,
      ),
    );
  }
}
