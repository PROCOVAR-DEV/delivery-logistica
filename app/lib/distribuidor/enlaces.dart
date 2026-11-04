// «Navegar a esta parada» y «Llamar al cliente»: los dos enlaces, puros y probados
// sueltos. Se abren por `AbrirYCompartir` (en los tests, un falso que guarda lo que
// se le entrego).
import '../nucleo/base/base.dart';

/// Google Maps solo a ESTE punto, en coche. `null` si la parada no tiene punto.
Uri? enlaceParaNavegar(Pedido parada) {
  final lat = parada.endLat ?? parada.lat;
  final lng = parada.endLng ?? parada.lng;
  if (lat == null || lng == null) return null;
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
  );
}

/// `tel:` con lo que haya de digitos (y un `+` inicial). `null` si no hay telefono.
Uri? enlaceParaLlamar(String? telefono) {
  final crudo = (telefono ?? '').trim();
  final digitos = crudo.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.isEmpty) return null;
  return Uri.parse('tel:${crudo.startsWith('+') ? '+' : ''}$digitos');
}
