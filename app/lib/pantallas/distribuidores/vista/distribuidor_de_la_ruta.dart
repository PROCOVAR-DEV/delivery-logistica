import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../diseno/colores.dart';
import '../datos/distribuidor_de_la_ruta.dart';
import '../estado/proveedores_distribuidores.dart';

/// «Distribuidor: Juan Pérez» — UN renglon con quien reparte una ruta, para
/// enchufarlo donde haga falta (el detalle de la ruta, la hoja de cierre).
///
/// Existe aparte porque `detalle_ruta.dart` lo tiene en las manos otro trabajo a la
/// vez que este (issue 7, 14/10/2026): en vez de editar ese fichero, el detalle
/// importa esta pieza y la pone con una linea,
///
///     DistribuidorDeLaRuta(distribuidorId: ruta.distribuidorId)
///
/// Resuelve el nombre contra la base local, que es un `Stream` (`CLAUDE.md` §3-ter):
/// en la web llega un segundo despues de pintar, y con una respuesta unica el
/// renglon se quedaria en «sin descargar».
class DistribuidorDeLaRuta extends ConsumerWidget {
  const DistribuidorDeLaRuta({required this.distribuidorId, super.key});

  /// `routes.distribuidor_id`. Nulo = sin distribuidor (una ruta historica).
  final String? distribuidorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conocidos = {
      for (final d
          in ref.watch(distribuidoresDeLaBarraProvider).value ??
              const <Distribuidor>[])
        d.id: d,
    };
    final texto = textoDelDistribuidor(distribuidorId, conocidos);
    final sinNadie = distribuidorId == null || distribuidorId!.isEmpty;
    return Row(
      children: [
        Icon(Icons.badge_outlined, size: 14, color: Colores.gris),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            sinNadie ? texto : 'Distribuidor: $texto',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
