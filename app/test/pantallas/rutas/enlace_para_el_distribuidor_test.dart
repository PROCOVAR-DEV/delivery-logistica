// EL MENSAJE QUE SE LE MANDA AL DISTRIBUIDOR (04/11/2026).
//
// Ya no hay enlace de Google Maps ni lista de facturas por parada: el distribuidor abre el enlace de su ruta con la app «Reparto
// Distribuidor». Lo que se vigila aqui es lo que le llega al otro lado del telefono, donde nadie de la oficina puede arreglarlo:
//
//  * el enlace va en su propia linea, sin nada pegado, para que WhatsApp lo convierta en tarjeta;
//  * el mensaje dice que app hace falta (si no la tiene, la pagina del enlace le dice como instalarla);
//  * WhatsApp recibe el mensaje escapado y no en crudo.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/enlace_de_la_ruta.dart';

void main() {
  const url = 'https://reparto.procovar.cloud/r/abc123';

  test('el mensaje nombra la ruta, lleva el enlace SOLO en su linea y dice que app hace falta', () {
    final m = mensajeParaElDistribuidor(
      codigo: 'RT-001',
      nombre: 'Reparto Vista',
      fecha: '4/11/2026',
      paradas: 3,
      url: url,
    );
    final lineas = m.split('\n');
    expect(
      lineas.first,
      'Tu ruta RT-001 · Reparto Vista · 4/11/2026 · 3 paradas:',
    );
    expect(lineas[1], url);
    expect(lineas.last, contains('Reparto Distribuidor'));
    expect(lineas.last, contains('el enlace te dice cómo instalarla'));
    expect(m, isNot(contains('google.com/maps')));
  });

  test('sin nombre no deja un hueco, y una sola parada va en singular', () {
    final m = mensajeParaElDistribuidor(
      codigo: 'RT-002',
      fecha: '5/11/2026',
      paradas: 1,
      url: url,
    );
    expect(m.split('\n').first, 'Tu ruta RT-002 · 5/11/2026 · 1 parada:');
  });

  test('WhatsApp recibe el mensaje escapado, no en crudo', () {
    final uri = enlaceDeWhatsApp('Ruta RT-001\nhttps://x/?a=1&b=2');

    expect(uri.host, 'wa.me');
    // El `&` del enlace, sin escapar, partiria el mensaje en dos parametros.
    expect(uri.queryParameters['text'], 'Ruta RT-001\nhttps://x/?a=1&b=2');
    expect(uri.toString(), isNot(contains('&b=2')));
  });
}
