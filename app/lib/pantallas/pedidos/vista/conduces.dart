// LOS CONDUCES EN LA PANTALLA DE FACTURAS (`docs/conduces.md`, 27/10/2026).
//
// Tres piezas:
//
//  * [PestanaConduces]: el texto de siempre, los conduces que hay (principal, cliente, facturas, peso,
//    estado) con «Deshacer conduce» y «Sacar» por miembro, y «Crear conduce» con lo marcado.
//  * [abrirCrearConduce]: el cajón que confirma «La principal será 47313 (Cliente). Las demás irán con
//    ella». Si no se puede juntar DICE por qué y el botón se apaga.
//  * [BotonDeshacerConduce]: el mismo gesto, en la ficha de la principal.
//
// Escribe `AccionesDeConduce` (web: al servidor y espera; APK y escritorio: base local y cola). Un
// rechazo se dice con su motivo LITERAL (CLAUDE.md §3-quinquies); nada se calla.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/conduce.dart';
import '../../../nucleo/numero_de_factura.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../rutas/datos/acciones_rutas.dart' show RechazoLocal;
import '../datos/estado_reparto.dart';
import '../datos/formato.dart';
import '../estado/proveedores_pedidos.dart';
import 'kit.dart' show EstadoVacio, Insignia;

/// Los textos que lee quien está delante. Literales aquí para que las pruebas busquen lo mismo.
abstract final class TextosDeConduces {
  /// El texto de la pestaña (literal de Jose, 27/10/2026).
  static const explicacion =
      'Un conduce es lo que sale con el camión y puede juntar varias facturas; '
      'la primera que marques es la que lo crea y dice a qué cliente va dedicado.';

  static const pestana = 'Conduces';
  static const crear = 'Crear conduce';
  static const deshacer = 'Deshacer conduce';
  static const sacar = 'Sacar';
  static const vacio = 'Aún no hay conduces en esta sucursal.';

  /// «La principal será 47313 (Cliente). Las demás irán con ella».
  static String laPrincipalSera(Pedido principal) =>
      'La principal será ${numeroParaDecir(principal)} (${principal.customerName}). '
      'Las demás irán con ella';
}

/// El número con el que se nombra una factura en una frase.
String numeroParaDecir(Pedido p) =>
    NumeroDeFactura.de(p.facturaNumero) ?? p.operationNumber ?? p.customerName;

// ---------------------------------------------------------------------------
// «Crear conduce»: el cajón
// ---------------------------------------------------------------------------

Future<void> abrirCrearConduce(BuildContext context) =>
    abrirPanel<void>(context, (_) => const CajonCrearConduce());

class CajonCrearConduce extends ConsumerStatefulWidget {
  const CajonCrearConduce({super.key});

  @override
  ConsumerState<CajonCrearConduce> createState() => _CajonCrearConduceState();
}

class _CajonCrearConduceState extends ConsumerState<CajonCrearConduce> {
  bool _creando = false;

  /// El «no» del servidor (o del aparato), literal, dentro del cajón.
  String? _rechazo;

  Future<void> _crear(List<Pedido> elegidas) async {
    setState(() {
      _creando = true;
      _rechazo = null;
    });
    try {
      await ref.read(accionesDeConduceProvider).crear([
        for (final p in elegidas) p.id,
      ]);
      // Las que se juntaron dejan de estar marcadas: ya son una sola fila.
      ref.read(seleccionPedidosProvider.notifier).quitarLaMarca();
      if (mounted) Navigator.of(context).pop();
    } on RechazoLocal catch (no) {
      if (!mounted) return;
      setState(() {
        _creando = false;
        _rechazo = no.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final marcadas = ref.watch(facturasMarcadasProvider).value;
    final elegidas = marcadas?.elegidas ?? const <Pedido>[];
    final motivo = marcadas == null
        ? null
        : porQueNoSePuedeJuntar(
            elegidas,
            principalesDeConduce: marcadas.principales,
            codigosDeRuta: marcadas.codigosDeRuta,
            numerosDePrincipal: marcadas.numerosDePrincipal,
          );
    final se = marcadas != null && motivo == null;
    final tema = Theme.of(context);

    return Cajon(
      titulo: TextosDeConduces.crear,
      pie: Wrap(
        alignment: WrapAlignment.end,
        spacing: Aire.sm,
        runSpacing: Aire.sm,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancelar'),
          ),
          ControlSenalado(
            nombre: Senalado.pedidosConfirmarConduce,
            child: BotonPrincipal(
              key: const ValueKey('crear-conduce-confirmar'),
              texto: TextosDeConduces.crear,
              icono: Icons.link,
              alPulsar: se && !_creando ? () => _crear(elegidas) : null,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (marcadas == null)
            const Text('Cargando...')
          else ...[
            if (elegidas.isNotEmpty)
              Text(
                se
                    ? TextosDeConduces.laPrincipalSera(elegidas.first)
                    : 'Marcadas: ${elegidas.length}',
                key: const ValueKey('crear-conduce-principal'),
                style: tema.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: Aire.sm),
            for (final (cual, p) in elegidas.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${cual == 0 ? 'Principal' : 'Con ella'}: '
                  '${numeroParaDecir(p)} · ${p.customerName}',
                  style: tema.textTheme.bodySmall,
                ),
              ),
            // POR QUÉ NO SE PUEDE, a la vista: el botón apagado sin motivo es un mudo.
            if (motivo != null) ...[
              const SizedBox(height: Aire.sm),
              Text(
                motivo,
                key: const ValueKey('crear-conduce-motivo'),
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: Colores.rojo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_rechazo != null) ...[
              const SizedBox(height: Aire.sm),
              Text(
                _rechazo!,
                key: const ValueKey('crear-conduce-rechazo'),
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: Colores.rojo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// «Deshacer conduce» y «Sacar»: gestos compartidos con un solo sitio donde se dice el «no»
// ---------------------------------------------------------------------------

/// «Deshacer conduce», apagado con su motivo cuando no se puede. Lo usan la pestaña y la ficha.
class BotonDeshacerConduce extends ConsumerStatefulWidget {
  const BotonDeshacerConduce({required this.conduce, super.key});

  final ConduceDe conduce;

  @override
  ConsumerState<BotonDeshacerConduce> createState() =>
      _BotonDeshacerConduceState();
}

class _BotonDeshacerConduceState extends ConsumerState<BotonDeshacerConduce> {
  String? _rechazo;

  Future<void> _deshacer() async {
    setState(() => _rechazo = null);
    try {
      await ref
          .read(accionesDeConduceProvider)
          .deshacer(widget.conduce.principal.id);
    } on RechazoLocal catch (no) {
      if (mounted) setState(() => _rechazo = no.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final no = widget.conduce.porQueNoSeToca;
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ControlSenalado(
          nombre: Senalado.pedidosDeshacerConduce,
          child: BotonDestructivo(
            key: ValueKey('deshacer-${widget.conduce.principal.id}'),
            texto: TextosDeConduces.deshacer,
            icono: Icons.link_off,
            alPulsar: no == null ? _deshacer : null,
          ),
        ),
        if (no != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(no, style: tema.textTheme.bodySmall),
          ),
        if (_rechazo != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _rechazo!,
              key: ValueKey('deshacer-rechazo-${widget.conduce.principal.id}'),
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.rojo,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// La pestaña
// ---------------------------------------------------------------------------

class PestanaConduces extends ConsumerWidget {
  const PestanaConduces({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conduces = ref.watch(conducesDeLaSucursalProvider).value;
    final rutas = ref.watch(rutasPorIdProvider).value ?? const {};
    final marcadas = ref.watch(facturasMarcadasProvider).value;
    final motivoDeCrear = marcadas == null
        ? TextosDeConduces.explicacion
        : porQueNoSePuedeJuntar(
            marcadas.elegidas,
            principalesDeConduce: marcadas.principales,
            codigosDeRuta: marcadas.codigosDeRuta,
            numerosDePrincipal: marcadas.numerosDePrincipal,
          );
    final tema = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextosDeConduces.explicacion,
          key: const ValueKey('conduces-explicacion'),
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: Aire.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: Aire.sm,
            runSpacing: Aire.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              BotonPrincipal(
                key: const ValueKey('conduces-crear'),
                texto: TextosDeConduces.crear,
                icono: Icons.link,
                alPulsar: motivoDeCrear == null
                    ? () => abrirCrearConduce(context)
                    : null,
              ),
              if (motivoDeCrear != null)
                Text(
                  (marcadas?.elegidas.length ?? 0) < 2
                      ? 'Marca al menos dos facturas en la pestaña Facturas.'
                      : motivoDeCrear,
                  key: const ValueKey('conduces-crear-motivo'),
                  style: tema.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(height: Aire.lg),
        if (conduces == null)
          const EstadoVacio('Cargando...')
        else if (conduces.isEmpty)
          const EstadoVacio(TextosDeConduces.vacio)
        else
          for (final c in conduces)
            _TarjetaDeConduce(
              key: ValueKey('conduce-${c.principal.id}'),
              conduce: c,
              estadoDeSuRuta: c.principal.routeId == null
                  ? null
                  : rutas[c.principal.routeId]?.status,
            ),
      ],
    );
  }
}

class _TarjetaDeConduce extends ConsumerStatefulWidget {
  const _TarjetaDeConduce({
    required this.conduce,
    required this.estadoDeSuRuta,
    super.key,
  });

  final ConduceDe conduce;
  final String? estadoDeSuRuta;

  @override
  ConsumerState<_TarjetaDeConduce> createState() => _TarjetaDeConduceState();
}

class _TarjetaDeConduceState extends ConsumerState<_TarjetaDeConduce> {
  String? _rechazo;

  Future<void> _sacar(Pedido miembro) async {
    setState(() => _rechazo = null);
    try {
      await ref
          .read(accionesDeConduceProvider)
          .sacar(widget.conduce.principal.id, miembro.id);
    } on RechazoLocal catch (no) {
      if (mounted) setState(() => _rechazo = no.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conduce;
    final tema = Theme.of(context);
    final no = c.porQueNoSeToca;
    final reparto = estadoDeReparto(c.principal, widget.estadoDeSuRuta);
    final domicilio = c.domicilioUsd;

    return Container(
      margin: const EdgeInsets.only(bottom: Aire.md),
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.etiqueta,
            key: ValueKey('conduce-etiqueta-${c.principal.id}'),
            style: tema.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            c.principal.customerName,
            style: tema.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Aire.xs),
          Wrap(
            spacing: Aire.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${c.facturas.length} facturas · ${kg(c.pesoKg)}'
                '${domicilio == null ? '' : ' · ${usd(domicilio)}'}',
                style: tema.textTheme.bodySmall,
              ),
              Insignia(reparto.etiqueta, color: Colores.enCurso),
            ],
          ),
          const SizedBox(height: Aire.sm),
          for (final m in c.miembros)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Con ella: ${numeroParaDecir(m)}',
                    style: tema.textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('sacar-${m.id}'),
                  onPressed: no == null ? () => _sacar(m) : null,
                  icon: const Icon(Icons.output, size: 18),
                  label: const Text(TextosDeConduces.sacar),
                ),
              ],
            ),
          if (_rechazo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _rechazo!,
                key: ValueKey('conduce-rechazo-${c.principal.id}'),
                style: tema.textTheme.bodySmall?.copyWith(
                  color: Colores.rojo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: Aire.sm),
          BotonDeshacerConduce(conduce: c),
        ],
      ),
    );
  }
}

/// LA SECCIÓN «CONDUCE» DE LA FICHA: si la factura es la principal de uno, sus facturas y «Deshacer
/// conduce»; si es un miembro, a qué conduce va (se saca desde la pestaña «Conduces»). Una factura
/// suelta no pinta nada.
class SeccionConduceDeLaFicha extends ConsumerWidget {
  const SeccionConduceDeLaFicha({required this.pedido, super.key});

  final Pedido pedido;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final principalDe = pedido.conducePrincipalId;
    final conduce = principalDe != null
        ? null
        : ref.watch(conduceDeLaFichaProvider(pedido.id)).value;
    if (principalDe == null && conduce == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        key: const ValueKey('ficha-conduce'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conduce',
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (conduce != null) ...[
            Text(conduce.etiqueta),
            for (final f in conduce.facturas)
              Text(
                '${f.id == pedido.id ? 'Principal' : 'Con ella'}: '
                '${numeroParaDecir(f)}',
                style: tema.textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            BotonDeshacerConduce(conduce: conduce),
          ] else
            Text(
              'Esta factura va dentro de un conduce: se mueve con su principal. '
              'Se saca desde la pestaña «Conduces».',
              key: const ValueKey('ficha-conduce-miembro'),
            ),
        ],
      ),
    );
  }
}
