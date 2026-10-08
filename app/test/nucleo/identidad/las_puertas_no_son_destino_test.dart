import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';

/// «A DÓNDE IBA» NUNCA ES UNA PUERTA. Si lo fuera, volver de Accesos aterrizaría en
/// la puerta y no en la pantalla que la persona pidió: un bucle o una pantalla muerta.
///
/// La lista de `EntradaPorAccesos._puertas` está escrita aparte de la del portero
/// (`navegacion/portero.dart`, para no meter la navegación dentro del nucleo), así que
/// esta prueba las ata: cada puerta del portero tiene que ser una puerta aquí. La de
/// `/sin-permiso` se había quedado fuera.
void main() {
  const puertas = <String>[
    rutaDeAcceso,
    rutaDeArranque,
    rutaDeConfiguracion,
    rutaDeSinPermiso,
  ];

  for (final puerta in puertas) {
    test('$puerta no es un destino, ni suelta ni dentro de volverA', () {
      expect(
        EntradaPorAccesos.destinoEnLaDireccion(
          Uri.parse('https://x.test$puerta'),
        ),
        isNull,
      );
      expect(
        EntradaPorAccesos.destinoEnLaDireccion(
          Uri.parse(
            'https://x.test/arranque?volverA=${Uri.encodeComponent(puerta)}',
          ),
        ),
        isNull,
      );
    });
  }

  test('PAREJA: una pantalla de verdad con su filtro sí es destino', () {
    expect(
      EntradaPorAccesos.destinoEnLaDireccion(
        Uri.parse('https://x.test/orders?municipio=Centro'),
      ),
      '/orders?municipio=Centro',
    );
  });
}
