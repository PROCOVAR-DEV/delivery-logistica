import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/proveedores.dart';
import 'acciones.dart';
import 'kit.dart';

/// EL CAJÓN «ZONAS INACTIVAS» — issue 15 de Amado, 16/10/2026.
///
/// Una zona que ya no se usa pero que tiene historia (rutas armadas desde ella)
/// no se borra: se INACTIVA. Deja de salir en el tablero, al colocar y al armar, y
/// se conserva con su nombre, su camión y su punto de salida. Aquí se ven y se
/// ACTIVAN otra vez; vuelve vacía, porque sus pedidos ya volvieron a «Sin colocar».
Future<void> abrirLasZonasInactivas(
  BuildContext context, {
  required String sucursalId,
}) => mostrarCajon<void>(
  context: context,
  titulo: 'Zonas inactivas',
  contenido: (_) => _ZonasInactivas(sucursalId: sucursalId),
);

class _ZonasInactivas extends ConsumerWidget {
  const _ZonasInactivas({required this.sucursalId});

  final String sucursalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonas = ref.watch(zonasInactivasProvider(sucursalId)).value;
    if (zonas == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (zonas.isEmpty) {
      return const Text(
        'No hay ninguna zona inactiva. Una zona se inactiva desde «Borrar la '
        'columna», cuando no se quiere perder su nombre ni su historia.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'No salen en el tablero ni al colocar. Al activar una vuelve vacía.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final z in zonas)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.view_column_outlined),
            title: Text(z.nombre),
            trailing: TextButton.icon(
              onPressed: () => unawaited(
                AccionesTablero.hacer(
                  context,
                  ref,
                  () => ref.read(tableroProvider.notifier).activarColumna(z.id),
                ),
              ),
              icon: Icon(Icons.restore, size: 18, color: Colores.primario),
              label: Text('Activar', style: TextStyle(color: Colores.primario)),
            ),
          ),
      ],
    );
  }
}
