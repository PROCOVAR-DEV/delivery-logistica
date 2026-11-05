// LA PESTAÑA «CANCELADAS» DE FACTURAS (issue 25 de Amado, «Facturas devueltas», 05/11/2026): quieren sacar
// reportes con las canceladas por periodo. Una lista de las facturas con resultado `cancelado` (las que
// canceló el chofer o la logística al cerrar una ruta, y las que la oficina canceló desde una devuelta),
// con Desde/Hasta sobre la FECHA DE LA CANCELACIÓN en hora de Cuba, un contador que sale de la misma
// consulta que la lista (`ConsultasCanceladas.donde`) y «Exportar a Excel».
//
// Todo sale de la base local: sin señal funciona entera. El Excel reutiliza la hoja de cálculo y la
// entrega de los Reportes (`informes/datos`): en el teléfono abre el cajón de compartir, en el
// escritorio guarda en Descargas y en la web descarga.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../informes/datos/entrega_del_excel.dart';
import '../../informes/datos/hoja_de_calculo.dart';
import '../datos/canceladas.dart';
import '../datos/formato.dart';
import '../estado/proveedores_pedidos.dart';
import 'cajon_detalle_pedido.dart';
import 'conduces.dart' show numeroParaDecir;
import 'kit.dart' show EstadoVacio, abrirCajon;

abstract final class TextosDeCanceladas {
  static const pestana = 'Canceladas';
  static const explicacion =
      'Las facturas canceladas: las que el cliente canceló después de devolverlas y las que se '
      'cancelaron al cerrar una ruta. Elige el periodo por la fecha de la cancelación.';
  static const exportar = 'Exportar a Excel';
  static const sinNada = 'No hay ninguna factura cancelada en este periodo.';
  static const sinNota = 'Sin nota';

  /// «12 canceladas» / «1 cancelada» (el cero en plural, como el resto de contadores).
  static String conteo(int n) => n == 1 ? '1 cancelada' : '$n canceladas';

  static String recortada(int vistas, int total) =>
      'Se muestran las $vistas más recientes de $total. Acota el periodo para ver el resto; '
      'el Excel lleva todas las del periodo.';
}

class PestanaCanceladas extends ConsumerStatefulWidget {
  const PestanaCanceladas({super.key});

  @override
  ConsumerState<PestanaCanceladas> createState() => _PestanaCanceladasState();
}

class _PestanaCanceladasState extends ConsumerState<PestanaCanceladas> {
  bool _armando = false;

  Future<void> _exportar() async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final p = ref.read(periodoDeCanceladasProvider);
    final entrega = ref.read(entregaDeFicheroProvider);
    final cuando = ref.read(relojProvider)();
    final consultas = ref.read(consultasCanceladasProvider);
    final sucursal = ref.read(sucursalMiradaProvider);

    setState(() => _armando = true);
    Entregado resultado;
    try {
      final filas = await consultas.todas(
        desde: p.desde,
        hasta: p.hasta,
        sucursalId: sucursal,
      );
      final bytes = armarXlsx([
        hojaDeCanceladas(filas, periodo: _periodoEnTexto(p)),
      ]);
      resultado = await entrega.entregar(
        bytes: bytes,
        nombre: nombreDelExcelDeCanceladas(cuando),
        tipoMime: tipoMimeXlsx,
      );
    } on Object catch (e) {
      // Nada falla en silencio: sale el motivo, no un «no se pudo».
      resultado = Entregado.noSePudo('No se pudo armar el Excel: $e');
    } finally {
      if (mounted) setState(() => _armando = false);
    }
    mensajero?.showSnackBar(SnackBar(content: Text(resultado.mensaje)));
  }

  static String _periodoEnTexto(PeriodoDeCanceladas p) {
    if (p.desde == null && p.hasta == null) return '';
    String dia(DateTime? d) => d == null ? '—' : fechaCorta(d);
    return '${dia(p.desde)} - ${dia(p.hasta)}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final periodo = ref.watch(periodoDeCanceladasProvider);
    final lista = ref.watch(canceladasProvider);
    final total = ref.watch(totalDeCanceladasProvider);
    final descargados = ref.watch(pedidosDescargadosProvider);
    final n = total.value ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextosDeCanceladas.explicacion,
          key: const ValueKey('canceladas-explicacion'),
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: Aire.md),
        Wrap(
          spacing: Aire.sm,
          runSpacing: Aire.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RangoDeFechas(
              desde: periodo.desde,
              hasta: periodo.hasta,
              tituloDesde: 'Desde (fecha de la cancelación)',
              tituloHasta: 'Hasta (fecha de la cancelación)',
              hoy: ref.watch(relojProvider)(),
              alCambiar: (d, h) =>
                  ref.read(periodoDeCanceladasProvider.notifier).poner(d, h),
            ),
            ControlSenalado(
              nombre: Senalado.pedidosExportarCanceladas,
              child: OutlinedButton.icon(
                key: const ValueKey('canceladas-exportar'),
                onPressed: _armando || n == 0 ? null : _exportar,
                icon: const Icon(Icons.table_view_outlined, size: 18),
                label: Text(
                  _armando
                      ? 'Armando el Excel...'
                      : TextosDeCanceladas.exportar,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Aire.md),
        Text(
          TextosDeCanceladas.conteo(n),
          key: const ValueKey('canceladas-conteo'),
          style: Tipos.texto(
            tamano: 13,
            peso: FontWeight.w600,
            color: Colores.tintaSuave,
          ),
        ),
        const SizedBox(height: Aire.sm),
        // Una lista vacía de una colección que nunca bajó NO es «no hay ninguna» (CLAUDE.md §3-ter).
        if (descargados.value == false)
          const EstadoVacio(
            'Aún no se han descargado las facturas: cuando bajen saldrán aquí.',
          )
        else if (lista.value == null)
          const EstadoVacio('Cargando...')
        else if (lista.value!.isEmpty)
          const EstadoVacio(TextosDeCanceladas.sinNada)
        else ...[
          for (final p in lista.value!)
            _TarjetaDeCancelada(key: ValueKey('cancelada-${p.id}'), pedido: p),
          if (n > lista.value!.length)
            Padding(
              padding: const EdgeInsets.only(top: Aire.sm),
              child: Text(
                TextosDeCanceladas.recortada(lista.value!.length, n),
                key: const ValueKey('canceladas-recortada'),
                style: tema.textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

class _TarjetaDeCancelada extends StatelessWidget {
  const _TarjetaDeCancelada({required this.pedido, super.key});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nota = (pedido.resultadoNota ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: Aire.md),
      decoration: BoxDecoration(
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radios.lg),
        onTap: () => abrirCajon<void>(
          context,
          (_) => CajonDetallePedido(pedidoId: pedido.id),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Aire.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Factura ${numeroParaDecir(pedido)}',
                style: tema.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                pedido.customerName,
                style: tema.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Cancelada el ${fechaDeLaCancelacion(cuandoSeCancelo(pedido))}',
                key: ValueKey('cancelada-cuando-${pedido.id}'),
                style: tema.textTheme.bodySmall,
              ),
              Text(
                nota.isEmpty ? TextosDeCanceladas.sinNota : nota,
                key: ValueKey('cancelada-nota-${pedido.id}'),
                style: tema.textTheme.bodySmall?.copyWith(
                  color: nota.isEmpty ? Colores.tintaSuave : Colores.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
