// CANCELAR UNA FACTURA DEVUELTA (issue 25 de Amado, «Facturas devueltas», 05/11/2026).
//
// Una factura que volvió del camión acaba en OTRA ruta otro día o CANCELADA porque el cliente se arrepintió.
// Aquí está lo segundo, en la ficha (cajón): la sección «Devolución» con la marca «Devuelta», la nota de
// la devolución y el botón «Cancelar la factura», que abre un cajón con una nota opcional y la confirmación.
// Una cancelada enseña, en cambio, cuándo se canceló y con qué nota.
//
// Escribe `AccionesDePedido.cancelar` (web: al servidor y ESPERA, con el motivo literal si dice que no;
// APK y escritorio: base local y cola, funciona sin señal). El botón sólo sale para una devuelta
// (`esDevuelta`); quién entra a esta aplicación ya lo decide Auth (sólo oficina), así que no hay otra
// puerta de roles aquí: el servidor es el que manda.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/marca_devuelta.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/cancelada.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../rutas/datos/acciones_rutas.dart' show RechazoLocal;
import '../datos/canceladas.dart' show cuandoSeCancelo, fechaDeLaCancelacion;
import '../estado/proveedores_pedidos.dart';

/// Los textos que lee quien está delante. Literales aquí para que las pruebas busquen lo mismo.
abstract final class TextosDeCancelar {
  static const seccion = 'Devolución';
  static const cancelar = 'Cancelar la factura';
  static const confirmar = 'Cancelar la factura';
  static const volver = 'Volver';
  static const titulo = 'Cancelar la factura';
  static const pregunta =
      'El cliente se arrepintió y esta factura no va a ir en otra ruta. Queda CANCELADA y ya no se '
      'reparte: no sale en Sin colocar, ni en el tablero, ni al armar una ruta. No se puede deshacer '
      'desde aquí.';
  static const campoNota = 'Nota (opcional)';
  static const seccionCancelada = 'Cancelada';
}

class SeccionDeDevolucionDeLaFicha extends StatelessWidget {
  const SeccionDeDevolucionDeLaFicha({required this.pedido, super.key});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nota = (pedido.resultadoNota ?? '').trim();

    if (esCancelada(pedido)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          key: const ValueKey('ficha-cancelada'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TextosDeCancelar.seccionCancelada,
              style: tema.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colores.rojo,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cancelada el ${fechaDeLaCancelacion(cuandoSeCancelo(pedido))}',
              key: const ValueKey('ficha-cancelada-cuando'),
            ),
            Text(
              nota.isEmpty ? 'Sin nota.' : nota,
              key: const ValueKey('ficha-cancelada-nota'),
            ),
          ],
        ),
      );
    }

    if (!esDevuelta(pedido)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        key: const ValueKey('ficha-devuelta'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextosDeCancelar.seccion,
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Align(alignment: Alignment.centerLeft, child: MarcaDevuelta()),
          if (nota.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Motivo de la devolución: $nota'),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ControlSenalado(
              nombre: Senalado.pedidosCancelarDevuelta,
              child: BotonDestructivo(
                key: const ValueKey('ficha-cancelar-la-factura'),
                texto: TextosDeCancelar.cancelar,
                icono: Icons.cancel_outlined,
                alPulsar: () => abrirPanel<void>(
                  context,
                  (_) => CajonCancelarDevuelta(pedidoId: pedido.id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El cajón de confirmación: una nota opcional y «Cancelar la factura». El «no» del servidor (o del
/// aparato) sale AQUÍ, literal, y el cajón no se cierra.
class CajonCancelarDevuelta extends ConsumerStatefulWidget {
  const CajonCancelarDevuelta({required this.pedidoId, super.key});

  final String pedidoId;

  @override
  ConsumerState<CajonCancelarDevuelta> createState() =>
      _CajonCancelarDevueltaState();
}

class _CajonCancelarDevueltaState extends ConsumerState<CajonCancelarDevuelta> {
  final _nota = TextEditingController();
  bool _mandando = false;
  String? _rechazo;

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cancelar() async {
    setState(() {
      _mandando = true;
      _rechazo = null;
    });
    try {
      await ref
          .read(accionesDePedidoProvider)
          .cancelar(widget.pedidoId, nota: _nota.text);
      if (mounted) Navigator.of(context).pop();
    } on RechazoLocal catch (no) {
      if (!mounted) return;
      setState(() {
        _mandando = false;
        _rechazo = no.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Cajon(
      titulo: TextosDeCancelar.titulo,
      pie: Wrap(
        alignment: WrapAlignment.end,
        spacing: Aire.sm,
        runSpacing: Aire.sm,
        children: [
          TextButton(
            onPressed: _mandando
                ? null
                : () => Navigator.of(context).maybePop(),
            child: const Text(TextosDeCancelar.volver),
          ),
          ControlSenalado(
            nombre: Senalado.pedidosConfirmarCancelar,
            child: BotonDestructivo(
              key: const ValueKey('cancelar-confirmar'),
              texto: TextosDeCancelar.confirmar,
              icono: Icons.cancel_outlined,
              alPulsar: _mandando ? null : _cancelar,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TextosDeCancelar.pregunta, style: tema.textTheme.bodyMedium),
          const SizedBox(height: Aire.md),
          TextField(
            key: const ValueKey('cancelar-nota'),
            controller: _nota,
            maxLength: MotivosDeCancelar.maxNota,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: TextosDeCancelar.campoNota,
              border: OutlineInputBorder(),
            ),
          ),
          if (_rechazo != null) ...[
            const SizedBox(height: Aire.sm),
            Text(
              _rechazo!,
              key: const ValueKey('cancelar-rechazo'),
              style: tema.textTheme.bodyMedium?.copyWith(
                color: Colores.rojo,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
