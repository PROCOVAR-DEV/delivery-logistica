// EL ENLACE QUE SE LE MANDA AL CHOFER.
//
// Jose, 17/09/2026: «El mapa, ¿por qué no me sale el mapa con la ruta, si
// teníamos hasta para compartir la ruta por WhatsApp?».
//
// Lo que se vigila aqui es lo que le llega al chofer al otro lado del telefono,
// donde nadie de esta oficina puede arreglarlo:
//
//  * las paradas van **en el orden de visita**, no en el que las devuelva nadie;
//  * el enlace **empieza y acaba en el almacen**, porque el camion vuelve;
//  * el tope de 25 se respeta, y lo que se queda fuera **se dice** — ni el
//    recorte en silencio (§3) ni las paradas sin coordenadas desaparecidas
//    (regla 4);
//  * sin coordenadas de origen NO se arma un enlace roto: se da el motivo.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/enlace_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';

/// Una parada dibujable, con lo justo.
ParadaDelRecorrido parada(int n, {double? lat, double? lng}) =>
    ParadaDelRecorrido(
      id: 'p$n',
      numero: n,
      etiqueta: 'Cliente $n',
      punto: (lat == null || lng == null) ? null : Punto(lat, lng),
    );

Recorrido conParadas(List<ParadaDelRecorrido> paradas, {Punto? origen}) =>
    Recorrido(origen: origen ?? const Punto(21.38, -77.91), paradas: paradas);

void main() {
  group('lo que viaja dentro del enlace', () {
    test('las paradas van en el orden de visita, no en otro', () {
      final enlace = enlaceDeLaRuta(
        conParadas([
          parada(1, lat: 21.1, lng: -77.1),
          parada(2, lat: 21.2, lng: -77.2),
          parada(3, lat: 21.3, lng: -77.3),
        ]),
      );

      expect(enlace.hay, isTrue);
      expect(
        Uri.parse(enlace.url!).queryParameters['waypoints'],
        '21.1,-77.1|21.2,-77.2|21.3,-77.3',
      );
      // Y NO en otro orden: si alguien reordena por cercania, por nombre o por
      // lo que devuelva la base, esto lo caza.
      expect(enlace.url, isNot(contains('21.3,-77.3|21.1,-77.1')));
    });

    test('empieza y acaba en el almacen, porque el camion vuelve', () {
      final enlace = enlaceDeLaRuta(
        conParadas([
          parada(1, lat: 21.1, lng: -77.1),
        ], origen: const Punto(20.5, -76.5)),
      );
      final partes = Uri.parse(enlace.url!).queryParameters;

      expect(partes['origin'], '20.5,-76.5');
      expect(partes['destination'], '20.5,-76.5');
      // Y ademas navega, que es la diferencia entre abrir un mapa y salir.
      expect(partes['travelmode'], 'driving');
      expect(partes['dir_action'], 'navigate');
    });
  });

  group('el tope de 25, y lo que se queda fuera', () {
    test('con 30 paradas van 25 y se dice que 5 quedan fuera', () {
      final enlace = enlaceDeLaRuta(
        conParadas([
          for (var i = 1; i <= 30; i++) parada(i, lat: 21 + i / 100, lng: -77),
        ]),
      );

      expect(enlace.paradasEnElEnlace, topeDeParadasEnElEnlace);
      expect(enlace.fueraPorElTope, 5);
      expect(
        Uri.parse(enlace.url!).queryParameters['waypoints']!.split('|'),
        hasLength(25),
      );
      // La 25 entra y la 26 no.
      expect(enlace.url, contains('21.25,-77'));
      expect(enlace.url, isNot(contains('21.26,-77')));
      expect(enlace.loQueQuedaFuera, contains('5 paradas quedan fuera'));
    });

    test('con 25 justas no sobra ninguna y no se dice nada', () {
      final enlace = enlaceDeLaRuta(
        conParadas([
          for (var i = 1; i <= 25; i++) parada(i, lat: 21 + i / 100, lng: -77),
        ]),
      );

      expect(enlace.fueraPorElTope, 0);
      expect(enlace.loQueQuedaFuera, isNull);
    });

    test('las paradas SIN coordenadas tambien se cuentan y se dicen', () {
      // Esto es lo que la copia vieja se comia en silencio: una parada sin GPS
      // desaparecia del enlace y nadie se enteraba.
      final enlace = enlaceDeLaRuta(
        conParadas([
          parada(1, lat: 21.1, lng: -77.1),
          parada(2), // sin coordenadas
          parada(3, lat: 21.3, lng: -77.3),
        ]),
      );

      expect(enlace.paradasEnElEnlace, 2);
      expect(enlace.fueraSinCoordenadas, 1);
      expect(
        enlace.loQueQuedaFuera,
        '1 parada no tiene coordenadas y no entra en el enlace.',
      );
      expect(
        Uri.parse(enlace.url!).queryParameters['waypoints'],
        '21.1,-77.1|21.3,-77.3',
      );
    });

    test('los dos motivos a la vez salen los dos', () {
      final enlace = enlaceDeLaRuta(
        conParadas([
          for (var i = 1; i <= 30; i++)
            parada(
              i,
              lat: i == 2 ? null : 21 + i / 100,
              lng: i == 2 ? null : -77,
            ),
        ]),
      );

      expect(enlace.fueraPorElTope, 5);
      expect(enlace.fueraSinCoordenadas, 1);
      expect(enlace.loQueQuedaFuera, contains('5 paradas quedan fuera'));
      expect(enlace.loQueQuedaFuera, contains('1 parada no tiene coordenadas'));
    });
  });

  group('cuando NO hay enlace, se dice por que', () {
    test('sin coordenadas del almacen no se arma un enlace roto', () {
      final enlace = enlaceDeLaRuta(
        Recorrido(paradas: [parada(1, lat: 21.1, lng: -77.1)]),
      );

      expect(enlace.hay, isFalse);
      expect(enlace.url, isNull);
      // Y el motivo nombra QUE falta, no un «no se pudo» que no dice nada.
      expect(enlace.motivo, contains('almacén de salida'));
    });

    test('con todas las paradas sin coordenadas tampoco', () {
      final enlace = enlaceDeLaRuta(conParadas([parada(1), parada(2)]));

      expect(enlace.hay, isFalse);
      expect(enlace.motivo, contains('Ninguna de las 2 paradas'));
    });

    test('una ruta sin paradas lo dice con sus palabras', () {
      expect(
        enlaceDeLaRuta(conParadas([])).motivo,
        contains('no tiene paradas'),
      );
    });
  });

  group('el mensaje y WhatsApp', () {
    test(
      'el enlace va en la ULTIMA linea, que es la que WhatsApp convierte',
      () {
        final enlace = enlaceDeLaRuta(
          conParadas([parada(1, lat: 21.1, lng: -77.1)]),
        );
        final mensaje = mensajeParaElChofer(
          titulo: 'Ruta RT-001',
          resumen: '1 paradas · 42.5 km (incl. regreso)',
          enlace: enlace,
        );

        expect(mensaje.split('\n').last, enlace.url);
        expect(mensaje, startsWith('Ruta RT-001\n'));
      },
    );

    test('lo que queda fuera viaja DENTRO del mensaje', () {
      final enlace = enlaceDeLaRuta(
        conParadas([
          for (var i = 1; i <= 30; i++) parada(i, lat: 21 + i / 100, lng: -77),
        ]),
      );
      final mensaje = mensajeParaElChofer(
        titulo: 'Ruta RT-001',
        resumen: '30 paradas',
        enlace: enlace,
      );

      // El chofer es el que menos puede permitirse enterarse tarde.
      expect(mensaje, contains('5 paradas quedan fuera'));
    });

    test('sin enlace, el mensaje lleva el motivo y no una linea vacia', () {
      final enlace = enlaceDeLaRuta(
        Recorrido(paradas: [parada(1, lat: 21.1, lng: -77.1)]),
      );
      final mensaje = mensajeParaElChofer(
        titulo: 'Ruta RT-001',
        resumen: '1 paradas',
        enlace: enlace,
      );

      expect(mensaje.split('\n').last, enlace.motivo);
      expect(mensaje, isNot(contains('google.com/maps')));
    });

    test('WhatsApp recibe el mensaje escapado, no en crudo', () {
      final uri = enlaceDeWhatsApp('Ruta RT-001\nhttps://x/?a=1&b=2');

      expect(uri.host, 'wa.me');
      // El `&` del enlace, sin escapar, partiria el mensaje en dos parametros y
      // el chofer recibiria medio enlace.
      expect(uri.queryParameters['text'], 'Ruta RT-001\nhttps://x/?a=1&b=2');
      expect(uri.toString(), isNot(contains('&b=2')));
    });
  });

  group('la lista de facturas por parada (04/11/2026)', () {
    ParadaDelRecorrido conFactura(
      int n, {
      double? lat,
      double? lng,
      String? factura,
      String? direccion,
      double? importe,
    }) => ParadaDelRecorrido(
      id: 'p$n',
      numero: n,
      etiqueta: 'Cliente $n',
      factura: factura,
      direccion: direccion,
      importe: importe,
      punto: (lat == null || lng == null) ? null : Punto(lat, lng),
    );

    test('cada parada lleva su posición en el recorrido, su factura, su cliente y su dirección', () {
      final r = conParadas([
        conFactura(
          1,
          lat: 21.1,
          lng: -77.1,
          factura: 'Factura 47061 · 15/10/2026',
          direccion: 'Calle 3 #45',
          importe: 1.31,
        ),
        conFactura(
          2,
          lat: 21.2,
          lng: -77.2,
          factura: 'Factura 47062 · 15/10/2026',
        ),
      ]);
      final lista = listaDeParadasParaElChofer(r);
      expect(
        lista[0],
        r'1. Factura 47061 · 15/10/2026 · Cliente 1 · Calle 3 #45 · domicilio $1.31',
      );
      expect(lista[1], '2. Factura 47062 · 15/10/2026 · Cliente 2');
    });

    test('sin número de factura lo dice; una parada sin coordenadas no lleva número ni gasta el siguiente', () {
      final r = conParadas([
        conFactura(1, lat: 21.1, lng: -77.1),
        conFactura(2, factura: 'Factura 2'),
        conFactura(3, lat: 21.3, lng: -77.3, factura: 'Factura 3'),
      ]);
      final lista = listaDeParadasParaElChofer(r);
      expect(lista[0], startsWith('1. Sin número de factura'));
      expect(
        lista[1],
        '— Factura 2 · Cliente 2 · sin ubicación: no sale en el mapa',
      );
      expect(
        lista[2],
        startsWith('2. Factura 3'),
        reason: 'la 2.ª parada DEL ENLACE (la que cuenta el chofer en Maps), no la 3.ª de la app',
      );
    });

    test('el número de la lista es la posición de la parada en el enlace', () {
      final r = conParadas([
        for (var i = 1; i <= 25; i++)
          conFactura(i, lat: 21 + i / 100, lng: -77, factura: 'F$i'),
      ]);
      final lista = listaDeParadasParaElChofer(r);
      expect(lista.first, startsWith('1. F1 ·'));
      expect(lista.last, startsWith('25. F25 ·'));
      expect(enlaceDeLaRuta(r).paradasEnElEnlace, 25);
    });

    test('las que se pasan del tope se dicen y no llevan número', () {
      final r = conParadas([
        for (var i = 1; i <= 27; i++)
          conFactura(i, lat: 21 + i / 100, lng: -77, factura: 'F$i'),
      ]);
      final lista = listaDeParadasParaElChofer(r);
      expect(lista[25], contains('no entra en el enlace de Google Maps'));
      expect(lista[25], startsWith('— '));
    });

    test('el mensaje lleva la lista ANTES del enlace, y el enlace sigue siendo la última línea', () {
      final r = conParadas([
        conFactura(1, lat: 21.1, lng: -77.1, factura: 'Factura 47061'),
      ]);
      final enlace = enlaceDeLaRuta(r);
      final mensaje = mensajeParaElChofer(
        titulo: 'Ruta X',
        resumen: '1 parada',
        enlace: enlace,
        paradas: listaDeParadasParaElChofer(r),
      );
      expect(mensaje.split('\n').last, enlace.url);
      expect(mensaje, contains('Qué se entrega en cada parada'));
      expect(
        mensaje.indexOf('Factura 47061'),
        lessThan(mensaje.indexOf('google.com/maps')),
      );
    });

    test('sin lista el mensaje es el de siempre', () {
      final enlace = enlaceDeLaRuta(
        conParadas([conFactura(1, lat: 21.1, lng: -77.1)]),
      );
      expect(
        mensajeParaElChofer(titulo: 'T', resumen: 'R', enlace: enlace),
        isNot(contains('Qué se entrega en cada parada')),
      );
    });
  });

  group('los productos de cada parada (04/11/2026)', () {
    ParadaDelRecorrido parada1(String id, int n, double lat) => ParadaDelRecorrido(
      id: id,
      numero: n,
      etiqueta: 'Cliente $n',
      factura: 'Factura $n',
      punto: Punto(lat, -77),
    );

    test('cada parada lista lo que se baja: cantidad × producto, debajo de su factura', () {
      final r = conParadas([parada1('a', 1, 21.1), parada1('b', 2, 21.2)]);
      final lista = listaDeParadasParaElChofer(
        r,
        productos: {
          'a': [(cantidad: 20.0, producto: 'CERVEZA PARRANDA 500 ML BLISTER 6U'), (cantidad: 2.5, producto: 'MALTA GUAJIRA')],
          'b': [(cantidad: 7.0, producto: 'SERVILLETA PROSITO PACA 24P')],
        },
      );
      expect(lista, [
        '1. Factura 1 · Cliente 1',
        '   · 20 × CERVEZA PARRANDA 500 ML BLISTER 6U',
        '   · 2.50 × MALTA GUAJIRA',
        '2. Factura 2 · Cliente 2',
        '   · 7 × SERVILLETA PROSITO PACA 24P',
      ]);
    });

    test('una factura de muchas líneas se recorta y SE DICE cuántos productos faltan', () {
      final r = conParadas([parada1('a', 1, 21.1)]);
      final lista = listaDeParadasParaElChofer(
        r,
        productos: {
          'a': [for (var i = 1; i <= 15; i++) (cantidad: i.toDouble(), producto: 'P$i')],
        },
      );
      expect(lista.length, 1 + topeDeProductosPorParada + 1);
      expect(lista.last, '   · y 3 productos más');
    });

    test('una parada sin renglones bajados no inventa productos', () {
      final r = conParadas([parada1('a', 1, 21.1)]);
      expect(listaDeParadasParaElChofer(r), ['1. Factura 1 · Cliente 1']);
    });
  });
}
