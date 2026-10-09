import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/tema.dart';
import '../datos/bandeja.dart';
import '../datos/quien_revisa.dart';
import '../estado/proveedores_revision.dart';
import '../datos/que_hace.dart';
import 'cajon_de_descarte.dart';
import 'confirmar_aplicar.dart';
import 'confirmar_reintento.dart';

String _hora(DateTime? t) =>
    t == null ? '' : DateFormat('d/M, H:mm', 'es').format(t);

/// UN APUNTE DE LA COLA DE OTRO, tal como llego.
///
/// Lo que el revisor tiene que poder leer ANTES de pulsar nada: el metodo, la
/// ruta y **el cuerpo exacto** (colapsable, sin reformatear: lo que se ve es lo
/// que se va a aplicar), la hora del aparato y de quien viene (eso lo dice la
/// tarjeta de la entrega, que es la dueña de ese dato).
///
/// [motivoDeQueNo] es `null` si quien mira puede decidir, o el motivo literal de
/// por que no. Si no puede, **no hay botones**: el motivo ya lo dice la tarjeta.
class FilaDeApunte extends ConsumerWidget {
  const FilaDeApunte({
    required this.entrega,
    required this.apunte,
    required this.motivoDeQueNo,
    super.key,
  });

  final EntregaEnRevision entrega;
  final ApunteEnRevision apunte;
  final String? motivoDeQueNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final decisiones = ref.watch(decisionesDelRevisorProvider);
    final clave = claveDeApunte(apunte);
    // Todo lo de la entrega espera mientras se aplica "todo en orden".
    final ocupado =
        decisiones.ocupado(clave) ||
        decisiones.ocupado(claveDeEntrega(entrega));
    final aviso = decisiones.avisos[clave];
    final a = apunte;

    return Container(
      margin: const EdgeInsets.only(top: Aire.sm),
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(Radios.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Aire.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _InsigniaDelEstado(a),
              // Lo que HACE, en palabras, a partir de la forma de la ruta; lo que no
              // se reconoce no lleva texto (se ve solo lo crudo, sin inventar).
              if (queHace(a.metodo, a.ruta) case final texto?)
                Text(
                  texto,
                  style: tema.textTheme.titleSmall?.copyWith(
                    color: a.metodo.toUpperCase() == 'DELETE'
                        ? Colores.rojo
                        : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              // El metodo y la ruta EXACTOS: lo que se va a reenviar al reparto.
              SelectableText(
                '${a.metodo} ${a.ruta}',
                style: Tipos.mono(tamano: 12, color: Colores.tinta),
              ),
            ],
          ),
          if (a.hechoAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Hecho en el aparato el ${_hora(a.hechoAt)}',
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
            ),
          ],
          ..._loQuePaso(context, tema, aviso),
          _CuerpoExacto(cuerpo: a.cuerpo),
          if (a.estado.esperaDecision && motivoDeQueNo == null)
            _Acciones(
              entrega: entrega,
              apunte: a,
              ocupado: ocupado,
              enCurso: decisiones.ocupado(clave),
            ),
          // SOLO un `aplicando` que el servidor marca `interrumpido` (mas de 10
          // minutos) se puede reintentar; uno que se esta aplicando ahora no.
          if (a.estado == EstadoDelApunte.aplicando &&
              a.interrumpido &&
              motivoDeQueNo == null)
            _ReintentarInterrumpido(
              entrega: entrega,
              apunte: a,
              ocupado: ocupado,
            ),
        ],
      ),
    );
  }

  /// Lo que el servidor dijo de este apunte, **con su literal**.
  List<Widget> _loQuePaso(BuildContext context, ThemeData tema, String? aviso) {
    final a = apunte;
    final cuando = _hora(a.decididoAt);
    Widget linea(String texto, {Color? color, bool fuerte = false}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        texto,
        style: tema.textTheme.bodySmall?.copyWith(
          color: color ?? Colores.tinta,
          fontWeight: fuerte ? FontWeight.w600 : null,
        ),
      ),
    );
    return [
      // Lo que acaba de contestar el servidor a una orden de esta visita.
      if (aviso != null) linea(aviso, color: Colores.rojo, fuerte: true),
      switch (a.estado) {
        // El motivo del rechazo guardado, solo si no es el mismo aviso.
        EstadoDelApunte.rechazado when a.motivo != null && a.motivo != aviso =>
          linea(
            'No se pudo aplicar: ${a.motivo}',
            color: Colores.rojo,
            fuerte: true,
          ),
        EstadoDelApunte.aplicado => linea(
          TextosDeRevision.aplicadoPor(a.decididoPorNombre, cuando),
          color: Colores.verde,
        ),
        EstadoDelApunte.descartado => linea(
          '${TextosDeRevision.descartadoPor(a.decididoPorNombre, cuando)}'
          '${a.motivo == null ? '' : ' Motivo: ${a.motivo}'}',
        ),
        EstadoDelApunte.aplicando => linea(
          a.interrumpido
              ? TextosDeRevision.interrumpido
              : TextosDeRevision.aplicandoAhora,
          color: Colores.ambar,
          fuerte: a.interrumpido,
        ),
        _ => const SizedBox.shrink(),
      },
      if (a.estado == EstadoDelApunte.rechazado)
        linea(TextosDeRevision.sigueEsperando, color: Colores.gris),
    ];
  }
}

class _InsigniaDelEstado extends StatelessWidget {
  const _InsigniaDelEstado(this.apunte);

  final ApunteEnRevision apunte;

  @override
  Widget build(BuildContext context) => switch (apunte.estado) {
    EstadoDelApunte.enRevision => Insignia(
      'En revisión',
      color: Colores.ambar,
      fondo: Colores.ambarFondo,
    ),
    EstadoDelApunte.aplicando => Insignia(
      'Aplicándose',
      color: Colores.ambar,
      fondo: Colores.ambarFondo,
    ),
    EstadoDelApunte.aplicado => Insignia(
      'Aplicado',
      color: Colores.verde,
      fondo: Colores.verdeFondo,
    ),
    EstadoDelApunte.rechazado => Insignia(
      'Rechazado',
      color: Colores.rojo,
      fondo: Colores.rojoFondo,
    ),
    EstadoDelApunte.descartado => Insignia('Descartado'),
    // Lo que no se conoce se pinta con su palabra, no se esconde.
    EstadoDelApunte.desconocido => Insignia(
      apunte.estadoTexto.isEmpty ? 'Estado desconocido' : apunte.estadoTexto,
    ),
  };
}

/// El cuerpo TAL CUAL llego, colapsado: casi siempre basta con el metodo y la
/// ruta, y cuando no, un toque lo abre. Sin reformatear ni recortar.
class _CuerpoExacto extends StatelessWidget {
  const _CuerpoExacto({required this.cuerpo});

  final String? cuerpo;

  @override
  Widget build(BuildContext context) => Theme(
    // Sin las lineas de arriba y abajo que Material le pone a un ExpansionTile.
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: Aire.sm),
      dense: true,
      title: Text(
        'Cuerpo exacto',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Aire.md),
          decoration: BoxDecoration(
            color: Colores.fondo,
            borderRadius: BorderRadius.circular(Radios.sm),
          ),
          child: SelectableText(
            cuerpo ?? '(este apunte no lleva cuerpo)',
            style: Tipos.mono(tamano: 12, color: Colores.tinta),
          ),
        ),
      ],
    ),
  );
}

class _Acciones extends ConsumerWidget {
  const _Acciones({
    required this.entrega,
    required this.apunte,
    required this.ocupado,
    required this.enCurso,
  });

  final EntregaEnRevision entrega;
  final ApunteEnRevision apunte;
  final bool ocupado;
  final bool enCurso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yaRechazado = apunte.estado == EstadoDelApunte.rechazado;
    return Wrap(
      spacing: Aire.md,
      runSpacing: Aire.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BotonPrincipal(
          texto: enCurso
              ? TextosDeRevision.aplicando
              : (yaRechazado
                    ? TextosDeRevision.reintentar
                    : TextosDeRevision.aplicar),
          icono: yaRechazado ? Icons.refresh : Icons.done_outlined,
          alPulsar: ocupado
              ? null
              : () async {
                  // Borrar y modificar piden confirmacion corta, con el metodo y
                  // la ruta delante. Crear, mover y registrar resultados, no.
                  if (pideConfirmacionSuelta(apunte.metodo) &&
                      !await confirmarAplicarSuelto(context, apunte)) {
                    return;
                  }
                  await ref
                      .read(decisionesDelRevisorProvider.notifier)
                      .aplicar(entrega, apunte);
                },
        ),
        BotonDestructivo(
          texto: TextosDeRevision.descartar,
          icono: Icons.block_outlined,
          alPulsar: ocupado
              ? null
              : () => descartarConMotivo(context, entrega, apunte),
        ),
      ],
    );
  }
}

/// El reintento de un apunte `interrumpido`: pide CONFIRMAR, porque si el reparto
/// llego a aplicarlo, reintentar lo aplica dos veces (la API no lee `X-Apunte`).
class _ReintentarInterrumpido extends ConsumerWidget {
  const _ReintentarInterrumpido({
    required this.entrega,
    required this.apunte,
    required this.ocupado,
  });

  final EntregaEnRevision entrega;
  final ApunteEnRevision apunte;
  final bool ocupado;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: Aire.sm),
    child: Align(
      alignment: Alignment.centerLeft,
      child: BotonPrincipal(
        texto: TextosDeRevision.reintentarInterrumpido,
        icono: Icons.restart_alt,
        alPulsar: ocupado
            ? null
            : () async {
                final lo = await confirmarReintentoInterrumpido(context);
                if (!lo) return;
                await ref
                    .read(decisionesDelRevisorProvider.notifier)
                    .aplicar(entrega, apunte, reintentarInterrumpido: true);
              },
      ),
    ),
  );
}
