// LA PESTAÑA «HISTORIAL» del distribuidor y el detalle de una ruta cerrada.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/tema.dart';
import '../nucleo/base/base.dart';
import '../pantallas/pedidos/datos/formato.dart';
import '../pantallas/pedidos/vista/kit.dart';
import '../pantallas/rutas/datos/repositorio_rutas.dart' show PestanaRutas;
import '../pantallas/rutas/estado/proveedores_rutas.dart';
import 'historial.dart';
import 'parada_actual.dart';

String _hora(DateTime? t) => t == null ? '—' : fechaYHora(t);

class ListaDelHistorial extends ConsumerWidget {
  const ListaDelHistorial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutas = ref.watch(rutasDePestanaProvider(PestanaRutas.historial));
    if (rutas.isEmpty) return const EstadoVacio('Sin rutas terminadas aún.');
    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [for (final r in rutas) _TarjetaDelHistorial(ruta: r)],
    );
  }
}

class _TarjetaDelHistorial extends ConsumerWidget {
  const _TarjetaDelHistorial({required this.ruta});

  final Ruta ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paradas = ref.watch(paradasDeRutaProvider(ruta.id)).value;
    final cobros = ref.watch(cobrosDeEntregaProvider).value ?? const {};
    final resumen = paradas == null
        ? null
        : resumirLaRuta(ruta, paradas, cobros);
    final cancelada = ruta.status == EstadoRuta.cancelada;
    final revision = textoDeRevision(ruta);
    final pendiente = ref.watch(pendienteDeEnviarProvider(ruta.id)).value;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
        side: BorderSide(color: Colores.linea),
      ),
      child: InkWell(
        key: ValueKey('historial-${ruta.id}'),
        onTap: () => ref.read(rutaElegidaProvider.notifier).elegir(ruta.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${ruta.routeCode ?? ruta.id} · '
                      '${fechaCorta(ruta.finishedAt ?? ruta.deliveryDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Insignia(
                    cancelada ? 'Cancelada' : 'Completada',
                    color: cancelada ? Colores.rojo : Colores.verde,
                  ),
                ],
              ),
              if (resumen != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${resumen.paradas} paradas · ${resumen.entregadas} entregadas · '
                  '${resumen.noEntregadas} no entregadas · '
                  '${resumen.cobradas} cobradas',
                  key: ValueKey('historial-cuentas-${ruta.id}'),
                ),
                Text(
                  'Salió ${_hora(resumen.inicio)} · terminó ${_hora(resumen.fin)}'
                  '${resumen.duracion == null ? '' : ' · ${_duracion(resumen.duracion!)}'}',
                ),
              ],
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  if (pendiente != null)
                    Insignia(
                      pendiente ? 'Pendiente de enviar' : 'Enviada ✓',
                      key: ValueKey('historial-envio-${ruta.id}'),
                      color: pendiente ? Colores.ambar : Colores.verde,
                    ),
                  if (revision != null)
                    Insignia(
                      revision,
                      key: ValueKey('historial-revision-${ruta.id}'),
                      color: ruta.revisadaAt != null
                          ? Colores.verde
                          : Colores.gris,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _duracion(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? '${h}h ${m}min' : '${m}min';
}

/// Abrir una ruta cerrada: sus paradas con lo que marco y a que hora.
class DetalleDelHistorial extends ConsumerWidget {
  const DetalleDelHistorial({required this.rutaId, super.key});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruta = ref.watch(rutaConTodoProvider(rutaId)).value?.ruta;
    final paradas = ref.watch(paradasDeRutaProvider(rutaId)).value;
    if (ruta == null || paradas == null) return const SizedBox.shrink();
    final cobros = ref.watch(cobrosDeEntregaProvider).value ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TarjetaDelHistorial(ruta: ruta),
        const SizedBox(height: 8),
        for (final p in enOrdenDeVisita(paradas))
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              key: ValueKey('historial-parada-${p.id}'),
              title: Text(p.customerName),
              subtitle: Text(
                '${_resultado(p, cobros)} · ${_hora(p.resultadoAt)}'
                '${(p.resultadoNota ?? '').isEmpty ? '' : '\n${p.resultadoNota}'}',
              ),
              isThreeLine: (p.resultadoNota ?? '').isNotEmpty,
            ),
          ),
      ],
    );
  }

  static String _resultado(Pedido p, Map<String, bool> cobros) {
    if (p.resultado == null) return 'Sin marcar';
    if (p.resultado == ResultadoParada.entregado) {
      final c = cobros[p.id];
      return c == null
          ? 'Entregada'
          : (c ? 'Entregada · cobrada' : 'Entregada · sin cobrar');
    }
    return 'No entregada';
  }
}
