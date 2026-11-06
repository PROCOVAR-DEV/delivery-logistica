// LA PANTALLA «DISTRIBUCIÓN»: lo que la oficina ve de lo que hacen los distribuidores en la calle.
//
// Tres pestañas: «Dónde están» (el último punto de cada uno, ahora), «Por revisar» (las rutas que cerraron desde su teléfono y
// esperan la segunda llave) y «Teléfonos» (los dispositivos de los distribuidores, para desvincularlos). El historial por vehículo vive en Vehículos; el recorrido real de cada ruta, en su detalle.
// Siempre en vivo contra el servidor (también en la APK y en Windows): sin red lo dice.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/pestanas.dart';
import '../datos/api_distribucion.dart';
import 'donde_estan_ahora.dart';
import 'revision_de_rutas.dart';
import 'telefonos_de_distribuidores.dart';

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
    final telefonos = ref.watch(telefonosProvider).value;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PestanasQueCaben(
              indice: _pestana,
              etiquetas: [
                'Dónde están',
                'Por revisar ($pendientes)',
                // Sin número hasta que el servidor conteste: un (0) de mentira diría que no hay ninguno vinculado.
                telefonos == null
                    ? 'Teléfonos'
                    : 'Teléfonos (${cuantosVinculados(telefonos)})',
              ],
              anchoParaTodas: 300,
              alCambiar: (i) => setState(() => _pestana = i),
            ),
          ),
          Expanded(
            child: switch (_pestana) {
              0 => const DondeEstanAhora(),
              1 => const ListaPorRevisar(),
              _ => const TelefonosDeDistribuidores(),
            },
          ),
        ],
      ),
    );
  }
}
