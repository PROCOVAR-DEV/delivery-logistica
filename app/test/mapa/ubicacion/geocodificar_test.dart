import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/ubicacion/coordenadas.dart';
import 'package:reparto/mapa/ubicacion/geocodificar.dart';

import '../../apoyo/servidor_falso.dart';

/// LA GEOCODIFICACION, y sobre todo LA DIFERENCIA QUE NO SE PUEDE PERDER:
/// «no lo encuentro» y «no pude preguntar» son dos cosas distintas.
///
/// El patron devuelve `null` para las dos y su inversa devuelve las coordenadas
/// formateadas cuando falla, o sea que **sin red contesta como si hubiera
/// geocodificado**. Si eso se cuela aqui, la pantalla dice «esa direccion no
/// existe» sin haber preguntado a nadie, o rellena la caja de la direccion con
/// un dato inventado. De este punto sale lo que se le cobra a cada domicilio.
///
/// Todo con un adaptador falso: **no sale ni una peticion**, que es regla de la
/// casa en este PC.
void main() {
  group('leer lo que contesta Nominatim a una busqueda', () {
    test('un resultado: sale el punto y como lo llama', () {
      final leido = leerLaBusqueda(const [
        {
          'lat': '20.0247',
          'lon': '-75.8219',
          'display_name': 'Almacén central, Santiago de Cuba',
        },
      ]);
      expect(
        leido,
        isA<PuntoHallado>(),
        reason: 'con coordenadas en la respuesta tiene que salir un punto',
      );
      final hallado = leido as PuntoHallado;
      expect(hallado.punto, const PuntoEnElMapa(20.0247, -75.8219));
      expect(hallado.comoLoLlama, 'Almacén central, Santiago de Cuba');
    });

    test('Nominatim manda las coordenadas como TEXTO, y así se leen', () {
      // Es asi de verdad: `{"lat":"20.02","lon":"-75.82"}`. Un `as num` aqui
      // lanzaria con el cajon abierto.
      final hallado = leerLaBusqueda(const [
        {'lat': '20.02', 'lon': '-75.82'},
      ]);
      expect((hallado as PuntoHallado).punto, const PuntoEnElMapa(20.02, -75.82));
    });

    test('lista VACIA es «no la conozco», y sólo eso lo es', () {
      expect(leerLaBusqueda(const <Object?>[]), isA<NoHayTalDireccion>());
    });

    test(
      'una respuesta que no se entiende NO es «no existe»: es no haber podido '
      'preguntar',
      () {
        // Un proxy metiendo HTML, un error en JSON, un servicio cambiado. Decir
        // «esa direccion no existe» porque llego un HTML es mentir, y quien lo
        // lee se pone a buscar otra direccion en vez de escribir el punto.
        for (final cuerpo in <Object?>[
          null,
          '<html>429 Too Many Requests</html>',
          {'error': 'Unable to geocode'},
          [
            {'sin': 'coordenadas'},
          ],
          [
            {'lat': 'no es un numero', 'lon': '-75.8'},
          ],
        ]) {
          expect(
            leerLaBusqueda(cuerpo),
            isA<NoSePudoPreguntar>(),
            reason:
                'con «$cuerpo» no se pudo preguntar de verdad; contarlo como '
                '«no existe esa dirección» es decir una mentira en la pantalla',
          );
        }
      },
    );

    test('un resultado fuera del mundo se rechaza', () {
      // El mismo recorte que `leerCoordenadas`. Sin el, un servicio equivocado
      // coloca el almacen fuera del mundo y desde ahi se cotizan domicilios de
      // nueve mil kilometros.
      expect(
        leerLaBusqueda(const [
          {'lat': '91', 'lon': '0'},
        ]),
        isA<NoSePudoPreguntar>(),
      );
      expect(
        leerLaBusqueda(const [
          {'lat': '0', 'lon': '181'},
        ]),
        isA<NoSePudoPreguntar>(),
      );
    });
  });

  group('leer lo que contesta a la inversa', () {
    test('con nombre, sale el nombre', () {
      expect(
        (leerLaInversa(const {'display_name': 'Calle 5 nº 12, Santiago'})
                as DireccionHallada)
            .texto,
        'Calle 5 nº 12, Santiago',
      );
    });

    test('sin nombre NO se cae a las coordenadas formateadas', () {
      // Es la separacion del patron, y la razon de que este escrita: alli
      // `reverseGeocode` devuelve `formatCoords(lat,lng)` cuando no hay nombre o
      // cuando falla, asi que la caja de la direccion se rellena sola con
      // «20.02470, -75.82190» y la pantalla se ve IGUAL que si hubiera
      // geocodificado. Un hueco disfrazado de dato.
      expect(leerLaInversa(const <String, Object?>{}), isA<SinNombreParaEsePunto>());
      expect(leerLaInversa(const {'display_name': '   '}), isA<SinNombreParaEsePunto>());
      expect(leerLaInversa('<html>'), isA<NoSePudoPreguntarElPunto>());
      expect(leerLaInversa(null), isA<NoSePudoPreguntarElPunto>());
    });
  });

  group('el cliente de Nominatim, con un servidor falso', () {
    ({Dio cliente, ServidorFalso servidor}) montar(
      Future<RespuestaFalsa?> Function(PeticionVista) responder,
    ) {
      final servidor = ServidorFalso(responder);
      final cliente = Dio()..httpClientAdapter = servidor;
      return (cliente: cliente, servidor: servidor);
    }

    test('busca con lo que dice `reglas-negocio.md` §9', () async {
      final banco = montar(
        (_) async => RespuestaFalsa(200, const [
          {'lat': '20.0247', 'lon': '-75.8219'},
        ]),
      );
      final hallado = await GeocodificadorDeNominatim(
        banco.cliente,
      ).buscarDireccion('Almacén central Santiago');

      expect((hallado as PuntoHallado).punto, const PuntoEnElMapa(20.0247, -75.8219));
      final peticion = banco.servidor.vistas.single;
      expect(peticion.ruta, '$nominatim/search');
      // Los tres parametros del §9. `limit=1` es lo que evita traerse veinte
      // resultados para quedarse con el primero.
      expect(peticion.parametros['format'], 'json');
      expect(peticion.parametros['limit'], 1);
      expect(peticion.parametros['q'], 'Almacén central Santiago');
      // La cabecera que pide la politica de uso de Nominatim para no tratarnos
      // de robot anonimo.
      expect(peticion.cabeceras['User-Agent'], agenteDeNominatim);
    });

    test('POR DEBAJO DE 4 LETRAS NO SE SALE A LA RED', () async {
      // El corte previo del §9. No es rendimiento: es no mandarle a Nominatim
      // una peticion por cada letra que alguien teclea.
      final banco = montar((_) async => RespuestaFalsa(200, const <Object?>[]));
      final hallado = await GeocodificadorDeNominatim(
        banco.cliente,
      ).buscarDireccion('Ala');
      expect(hallado, isA<DemasiadoCorto>());
      expect(
        banco.servidor.vistas,
        isEmpty,
        reason: 'con menos de 4 letras no se pregunta a nadie',
      );
    });

    test('SIN RED: no se pudo preguntar, y no se inventa un punto', () async {
      final banco = montar((_) async => null); // el falso lanza como sin red
      final geo = GeocodificadorDeNominatim(banco.cliente);

      final buscado = await geo.buscarDireccion('Almacén central');
      expect(
        buscado,
        isA<NoSePudoPreguntar>(),
        reason:
            'sin red no se encontró nada porque no se preguntó: contarlo como '
            '«no existe» manda a buscar otra dirección en vez de escribir el '
            'punto a mano',
      );

      final inverso = await geo.comoSeLlamaEstePunto(
        const PuntoEnElMapa(20.0247, -75.8219),
      );
      expect(inverso, isA<NoSePudoPreguntarElPunto>());
      // Y lo que NO puede pasar: que salga una direccion.
      expect(inverso, isNot(isA<DireccionHallada>()));
    });

    test('un 500 tampoco es «no existe»', () async {
      final banco = montar((_) async => RespuestaFalsa(500, 'boom'));
      final hallado = await GeocodificadorDeNominatim(
        banco.cliente,
      ).buscarDireccion('Almacén central');
      expect(hallado, isA<NoSePudoPreguntar>());
    });
  });

  test('el falso de las pruebas nunca contesta un punto', () async {
    // `SinGeocodificar` es lo que se inyecta en las pruebas de pantalla: si
    // alguna vez contestara algo, esas pruebas dejarian de probar lo que dicen.
    const sin = SinGeocodificar();
    expect(await sin.buscarDireccion('Almacén central'), isA<NoSePudoPreguntar>());
    expect(
      await sin.comoSeLlamaEstePunto(const PuntoEnElMapa(20, -75)),
      isA<NoSePudoPreguntarElPunto>(),
    );
  });
}
