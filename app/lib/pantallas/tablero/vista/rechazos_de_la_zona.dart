import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../entregar_el_dia/estado/entregar_el_dia.dart';
import '../../sincronizacion/vista/fila_de_rechazo.dart';
import 'kit.dart';

/// LO QUE EL SERVIDOR NO ACEPTÓ DE UNA ZONA, con su motivo LITERAL y con qué
/// decidir — issue 15 de Amado, 16/10/2026.
///
/// La zona sólo decía «rechazada» y nada más: ni el porqué ni una acción. Amado:
/// «pone un badge de "rechazada" que no sabemos qué significa». El motivo ya
/// estaba guardado —es lo que enseña la bandeja de «Entregar el día»—, pero la
/// persona que mira el tablero no tiene por qué ir a buscarlo allí: aquí está
/// donde lo ve, con **Reintentar** y **Descartar** (§4: «un aviso sin acción es
/// un aviso que se queda puesto para siempre»).
///
/// Qué apuntes son «de esta zona» lo decide [nombraALaZona], la MISMA regla que
/// pinta la insignia (`ConsultasTablero.columnas`, `rechazada`): crea la zona, o
/// la nombra en su ruta, o la nombra en su cuerpo (las colocaciones).
Future<void> abrirLosRechazosDeLaZona(
  BuildContext context, {
  required String columnaId,
  required String nombre,
}) => mostrarCajon<void>(
  context: context,
  titulo: 'Lo que el servidor no aceptó de «$nombre»',
  contenido: (_) => _Rechazos(columnaId: columnaId),
);

/// ¿Este apunte habla de esta zona? Igual que el `EXISTS` de la insignia.
bool nombraALaZona(Apunte a, String columnaId) =>
    a.provisional == columnaId ||
    a.ruta.contains(columnaId) ||
    a.cuerpo.contains(columnaId);

/// Qué hizo la persona, en sus palabras y no en las de la cola.
String loQueSePedia(Apunte a) {
  final deLaZona = RegExp(r'^/board/columns/[^/?]+(\?.*)?$').hasMatch(a.ruta);
  return switch (a.metodo) {
    'DELETE' when deLaZona => 'Borrar la zona',
    'PATCH' when deLaZona => 'Cambiar la zona',
    _ => '${a.metodo} ${a.ruta}',
  };
}

class _Rechazos extends ConsumerWidget {
  const _Rechazos({required this.columnaId});

  final String columnaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final formato = DateFormat('d/M/y, H:mm', 'es');
    // Un stream: Descartar la quita de la lista en el acto, sin cerrar el cajón.
    final todos = ref.watch(rechazadosProvider).value ?? const <Apunte>[];
    final suyos = todos.where((a) => nombraALaZona(a, columnaId)).toList();
    final borrado = suyos.any((a) => a.metodo == 'DELETE');

    if (suyos.isEmpty) {
      return const Text('No queda nada rechazado en esta zona.');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          borrado
              ? 'Descartar deja la zona como está en el servidor. Para '
                    'borrarla, abre «Borrar la columna» y elige qué hacer con '
                    'sus pedidos: Reintentar sin más recibiría el mismo no.'
              : 'Descartar deja la zona como está en el servidor. Reintentar '
                    'lo vuelve a mandar.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final a in suyos)
          FilaDeRechazo(
            motivo: a.motivo ?? 'El servidor lo rechazó sin decir por qué.',
            quien: '',
            horas: <String>[
              'hecho ${formato.format(a.hechoAt)}',
              if (a.resueltoAt != null)
                'rechazado ${formato.format(a.resueltoAt!)}',
            ].join(' · '),
            peticion: loQueSePedia(a),
            alReintentar: () =>
                unawaited(ref.read(colaProvider).reintentar(a.clave)),
            alDescartar: () =>
                unawaited(ref.read(colaProvider).descartar(a.clave)),
          ),
      ],
    );
  }
}
