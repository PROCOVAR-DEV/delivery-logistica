// EL VINCULO DE ESTE TELEFONO CON SU VEHICULO: el enlace trae vehiculo y distribuidor
// y el telefono se queda ligado a ese vehiculo hasta que la oficina lo desvincule. Se
// guarda en las preferencias de la base (se va con ella al vaciarse) y se ensena en
// «Mis rutas».
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diseno/colores.dart';
import '../../nucleo/proveedores.dart';
import 'cliente_de_dispositivo.dart';

const claveDelVinculo = 'vinculoDelTelefono';

class VinculoDelTelefono {
  const VinculoDelTelefono({
    this.vinculoId,
    this.vehiculoId,
    this.vehiculo,
    this.placa,
    this.tipo,
    this.distribuidorId,
    this.distribuidor,
  });

  /// Del `POST /api/d/reclamar`; nulo si el servidor no mando vehiculo.
  static VinculoDelTelefono? deLaRespuesta(RutaReclamada r) {
    if (r.vehiculo == null && r.distribuidor == null && r.vinculoId == null) {
      return null;
    }
    return VinculoDelTelefono(
      vinculoId: r.vinculoId,
      vehiculoId: r.vehiculoId ?? r.vehiculo?['id'] as String?,
      vehiculo: r.vehiculo?['nombre'] as String?,
      placa: r.vehiculo?['placa'] as String?,
      tipo: r.vehiculo?['tipo'] as String?,
      distribuidorId: r.distribuidor?['id'] as String?,
      distribuidor: r.distribuidor?['nombre'] as String?,
    );
  }

  final String? vinculoId;
  final String? vehiculoId;
  final String? vehiculo;
  final String? placa;
  final String? tipo;
  final String? distribuidorId;
  final String? distribuidor;

  /// «Camión 1 (P-001) · Juan». Nada si no hay nada que decir.
  String get texto => [
    if ((vehiculo ?? '').isNotEmpty)
      (placa ?? '').isNotEmpty ? '$vehiculo ($placa)' : vehiculo!,
    if ((distribuidor ?? '').isNotEmpty) distribuidor!,
  ].join(' · ');

  String aJson() => jsonEncode({
    'vinculoId': vinculoId,
    'vehiculoId': vehiculoId,
    'vehiculo': vehiculo,
    'placa': placa,
    'tipo': tipo,
    'distribuidorId': distribuidorId,
    'distribuidor': distribuidor,
  });

  static VinculoDelTelefono? deJson(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    try {
      final m = jsonDecode(texto) as Map<String, Object?>;
      return VinculoDelTelefono(
        vinculoId: m['vinculoId'] as String?,
        vehiculoId: m['vehiculoId'] as String?,
        vehiculo: m['vehiculo'] as String?,
        placa: m['placa'] as String?,
        tipo: m['tipo'] as String?,
        distribuidorId: m['distribuidorId'] as String?,
        distribuidor: m['distribuidor'] as String?,
      );
    } on Object {
      return null;
    }
  }
}

/// Lo guardado en ESTA base. Se invalida al guardar uno nuevo.
final vinculoDelTelefonoProvider = FutureProvider<VinculoDelTelefono?>((
  ref,
) async {
  final base = ref.watch(baseProvider);
  return VinculoDelTelefono.deJson(await base.preferencia(claveDelVinculo));
});

/// «Camión 1 (P-001) · Juan» en «Mis rutas». Sin vinculo, no ocupa nada.
class CartelDelVinculo extends ConsumerWidget {
  const CartelDelVinculo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texto = ref.watch(vinculoDelTelefonoProvider).value?.texto ?? '';
    if (texto.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined, size: 16, color: Colores.gris),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              key: const ValueKey('cartel-del-vinculo'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
