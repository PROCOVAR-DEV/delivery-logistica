// El renglon de una ruta EN CURSO en la lista de «Mis rutas»: cuantas lleva y
// cual es la siguiente. Con varias rutas en curso a la vez, es lo que dice a
// cual ir primero sin abrir ninguna.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/colores.dart';
import '../pantallas/rutas/estado/proveedores_rutas.dart';
import 'parada_actual.dart';

class SiguienteParadaEnLaLista extends ConsumerWidget {
  const SiguienteParadaEnLaLista({required this.rutaId, super.key});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paradas = ref.watch(paradasDeRutaProvider(rutaId)).value;
    if (paradas == null) return const SizedBox.shrink();
    final siguiente = siguienteParada(paradas);
    final texto = siguiente == null
        ? 'Todas las paradas marcadas (${paradas.length})'
        : '${paradasHechas(paradas)} de ${paradas.length} hechas · '
              'Siguiente: ${siguiente.customerName}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.navigation_outlined, size: 16, color: Colores.primario),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              key: ValueKey('siguiente-parada-$rutaId'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
