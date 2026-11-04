// EL HISTORIAL DE UN VEHÍCULO (tarea 4): «la vida de distribución» de cada vehículo.
//
// Sus rutas por fecha, quién las hizo, cuántas paradas, entregadas, devueltas y cobradas, los km y lo que duraron; y al tocar una,
// su recorrido real. `GET /api/vehicles/{id}/historial`, siempre en vivo. Se abre desde la tarjeta del vehículo en Vehículos.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../pedidos/datos/formato.dart';
import '../../rutas/datos/enlace_de_la_ruta.dart' show cuantasParadas;
import '../../pedidos/vista/kit.dart' show EstadoVacio, Insignia;
import '../datos/api_distribucion.dart';
import '../datos/modelos.dart';
import 'recorrido_real.dart';
import 'vinculo_del_vehiculo.dart';

abstract final class TextosDelHistorial {
  static const vacio = 'Este vehículo todavía no ha hecho ninguna ruta.';
  static const sinGps = 'Sin recorrido del GPS';
  static String estado(String? e) => switch (e) {
    'completed' => 'Completada',
    'in_progress' => 'En curso',
    'planned' => 'Planificada',
    'cancelled' => 'Cancelada',
    _ => e ?? '',
  };
}

Key claveDeLaRutaDelHistorial(String id) => ValueKey('historial-ruta-$id');

Future<void> abrirHistorialDelVehiculo(
  BuildContext contexto,
  String vehiculoId,
  String nombre,
) => abrirCajon<void>(
  contexto,
  titulo: 'Historial · $nombre',
  subtitulo: 'Sus rutas, de la más reciente a la más antigua',
  cuerpo: (c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Teléfono',
        style: Theme.of(c).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      VinculoDelVehiculo(vehiculoId: vehiculoId, nombre: nombre),
      const SizedBox(height: 8),
      HistorialDeVinculos(vehiculoId: vehiculoId),
      const SizedBox(height: 20),
      Text(
        'Rutas',
        style: Theme.of(c).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      HistorialDelVehiculo(vehiculoId: vehiculoId),
    ],
  ),
);

class HistorialDelVehiculo extends ConsumerWidget {
  const HistorialDelVehiculo({required this.vehiculoId, super.key});

  final String vehiculoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(
    historialDelVehiculoProvider(vehiculoId),
  )) {
    AsyncValue(:final error?) => EstadoVacio(
      'No se pudo leer el historial: ${motivoDelFallo(error)}',
      accion: OutlinedButton.icon(
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Reintentar'),
        onPressed: () =>
            ref.invalidate(historialDelVehiculoProvider(vehiculoId)),
      ),
    ),
    AsyncData(:final value) when value.isEmpty => const EstadoVacio(
      TextosDelHistorial.vacio,
    ),
    AsyncData(:final value) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r
            in ([...value]..sort(
              (a, b) =>
                  (b.fecha ?? DateTime(0)).compareTo(a.fecha ?? DateTime(0)),
            )))
          _Fila(r),
      ],
    ),
    _ => const EstadoVacio('Cargando el historial…'),
  };
}

class _Fila extends StatelessWidget {
  const _Fila(this.r);

  final RutaDelHistorial r;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final titulo = [?r.codigo, ?r.nombre].join(' · ');
    return Card(
      key: claveDeLaRutaDelHistorial(r.id),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: r.puntos > 0
            ? () => abrirRecorridoReal(
                context,
                r.id,
                titulo: 'Recorrido real · ${r.codigo ?? ''}',
                subtitulo: r.distribuidor,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${fechaCorta(r.fecha)}${titulo.isEmpty ? '' : ' · $titulo'}',
                      style: tema.textTheme.titleSmall,
                    ),
                  ),
                  Insignia(
                    TextosDelHistorial.estado(r.estado),
                    color: r.estado == 'completed'
                        ? ColoresDelMapa.salida
                        : ColoresDelMapa.recorrido,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                r.distribuidor == null
                    ? 'Sin distribuidor anotado'
                    : 'Lo hizo ${r.distribuidor}',
                style: tema.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                '${cuantasParadas(r.paradas)} · ${r.entregadas} entregadas · ${r.devueltas} devueltas · ${r.cobradas} cobradas',
                style: tema.textTheme.bodySmall,
              ),
              Text(
                '${km(r.km)} · ${cuantoDura(r.duracion)}'
                '${r.inicio == null ? '' : ' · salió ${horaDe(r.inicio)}'}'
                '${r.fin == null ? '' : ' · llegó ${horaDe(r.fin)}'}',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    r.puntos > 0 ? Icons.timeline : Icons.location_off_outlined,
                    size: 16,
                    color: Colores.tintaSuave,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    r.puntos > 0
                        ? 'Ver el recorrido real'
                        : TextosDelHistorial.sinGps,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: Colores.tintaSuave,
                    ),
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
