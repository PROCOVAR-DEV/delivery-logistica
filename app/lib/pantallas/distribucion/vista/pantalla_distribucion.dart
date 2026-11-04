// LA PANTALLA «DISTRIBUCIÓN»: lo que la oficina ve de lo que hacen los distribuidores en la calle.
//
// Dos pestañas: «Dónde están» (el último punto de cada uno, ahora) y «Por revisar» (las rutas que cerraron desde su teléfono y
// esperan la segunda llave). El historial por vehículo vive en Vehículos; el recorrido real de cada ruta, en su detalle.
// Siempre en vivo contra el servidor (también en la APK y en Windows): sin red lo dice.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/pestanas.dart';
import '../datos/api_distribucion.dart';
import 'donde_estan_ahora.dart';
import 'revision_de_rutas.dart';

class PantallaDistribucion extends ConsumerStatefulWidget {
  const PantallaDistribucion({super.key});

  static const ruta = '/distribution';

  @override
  ConsumerState<PantallaDistribucion> createState() =>
      _PantallaDistribucionState();
}

class _PantallaDistribucionState extends ConsumerState<PantallaDistribucion> {
  var _pestana = 0;

  @override
  Widget build(BuildContext context) {
    final pendientes = cuantasPendientes(
      ref.watch(revisionesProvider).value ?? const [],
    );
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PestanasQueCaben(
              indice: _pestana,
              etiquetas: ['Dónde están', 'Por revisar ($pendientes)'],
              anchoParaTodas: 300,
              alCambiar: (i) => setState(() => _pestana = i),
            ),
          ),
          Expanded(
            child: _pestana == 0
                ? const DondeEstanAhora()
                : const ListaPorRevisar(),
          ),
        ],
      ),
    );
  }
}
