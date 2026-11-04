// EL MAPA DEL DISTRIBUIDOR NO SALE A LA RED: ni teselas de OpenStreetMap ni OSRM.
// Dibuja con el paquete instalado (`fondo_del_paquete.dart`, `calles_del_paquete.dart`)
// y, donde el paquete no llega, el croquis a secas.
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mapa/calles_del_paquete.dart';
import '../../mapa/fondo_del_paquete.dart';
import '../../mapa/proveedores_de_mapa.dart';
import '../../pantallas/rutas/datos/geo.dart';
import '../../pantallas/rutas/datos/mapa_en_vivo.dart';

class FondoSinRed implements FondoDeCalles {
  const FondoSinRed();

  @override
  Future<ui.Image?> tesela(int z, int x, int y) async => null;
}

class RecorridoSinRed implements RecorridoPorCalles {
  const RecorridoSinRed();

  @override
  Future<List<Punto>?> entre(List<Punto> puntos) async => null;
}

final fondoSoloLocalProvider = Provider<FondoDeCalles>((ref) {
  final paquete = ref.watch(paqueteAbiertoProvider).value;
  return paquete == null ? const FondoSinRed() : FondoDelPaquete(paquete);
});

final recorridoSoloLocalProvider = Provider<RecorridoPorCalles>((ref) {
  final paquete = ref.watch(paqueteAbiertoProvider).value;
  return paquete == null ? const RecorridoSinRed() : CallesDelPaquete(paquete);
});
