import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/ubicacion/coordenadas.dart';
import 'package:reparto/mapa/ubicacion/mapa_para_elegir_punto.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

/// EL MAPA DE ELEGIR EL PUNTO.
///
/// Lo que se prueba aqui es **la cuenta que convierte un dedo en coordenadas**,
/// porque es donde esto se rompe sin que se vea: un signo cambiado pone el
/// almacen en el hemisferio de al lado y el mapa se sigue viendo normal. De ese
/// punto salen los kilometros de cada cliente y de ahi lo que se le cobra a cada
/// domicilio.
///
/// Las teselas son [SinCalles]: **no sale ni una peticion**, y ademas deja el
/// mapa exactamente como se ve en el patio de un almacen.
void main() {
  // El recuadro del mapa: `altoDelMapa(512)` son 320 px de alto.
  const anchoDeLaCaja = 512.0;
  const altoDeLaCaja = 320.0;
  const caja = Size(anchoDeLaCaja, altoDeLaCaja);

  group('la proyeccion', () {
    test('el centro del recuadro es el centro del mapa, exactamente', () {
      const centro = PuntoEnElMapa(20.0247, -75.8219);
      final vuelta = puntoDeLaPantalla(
        const Offset(anchoDeLaCaja / 2, altoDeLaCaja / 2),
        centro: centro,
        zoom: 15,
        tamano: caja,
      );
      expect(vuelta.lat, closeTo(centro.lat, 1e-9));
      expect(vuelta.lng, closeTo(centro.lng, 1e-9));
    });

    test('las esquinas del mundo, con los numeros de siempre de Mercator', () {
      // A zoom 1 el mundo entero mide 512 px, asi que con el centro en (0,0) y
      // una caja de 512x512 el recuadro ES el mundo. Los valores son los que
      // sale en cualquier tabla de teselas de OSM y **no se calculan aqui con la
      // misma formula que se esta probando**: estan escritos a mano.
      const mundo = Size(512, 512);
      const centro = PuntoEnElMapa(0, 0);
      final arribaIzquierda = puntoDeLaPantalla(
        Offset.zero,
        centro: centro,
        zoom: 1,
        tamano: mundo,
      );
      expect(arribaIzquierda.lng, closeTo(-180, 1e-9));
      expect(arribaIzquierda.lat, closeTo(85.0511287798066, 1e-9));

      final unCuarto = puntoDeLaPantalla(
        const Offset(128, 128),
        centro: centro,
        zoom: 1,
        tamano: mundo,
      );
      expect(unCuarto.lng, closeTo(-90, 1e-9));
      expect(unCuarto.lat, closeTo(66.51326044311186, 1e-9));
    });

    test('ida y vuelta: lo que se pinta se vuelve a leer en el mismo sitio', () {
      const centro = PuntoEnElMapa(20.0247, -75.8219);
      for (final sitio in const [
        Offset(0, 0),
        Offset(511, 319),
        Offset(37, 211),
        Offset(256, 160),
      ]) {
        final punto = puntoDeLaPantalla(
          sitio,
          centro: centro,
          zoom: 14,
          tamano: caja,
        );
        final vuelta = enLaPantalla(
          punto,
          centro: centro,
          zoom: 14,
          tamano: caja,
        );
        expect(vuelta.dx, closeTo(sitio.dx, 1e-6), reason: 'en $sitio');
        expect(vuelta.dy, closeTo(sitio.dy, 1e-6), reason: 'en $sitio');
      }
    });

    test('fuera del mundo no se devuelve NaN', () {
      // Un arrastre largo se sale del mapa. Un `NaN` se guarda igual de bien que
      // un numero y luego no hay quien lo lea.
      final punto = puntoDeLaPantalla(
        const Offset(-100000, -100000),
        centro: const PuntoEnElMapa(20, -75),
        zoom: 3,
        tamano: caja,
      );
      expect(punto.lat.isNaN, isFalse);
      expect(punto.lng.isNaN, isFalse);
      expect(punto.lat, inInclusiveRange(-90, 90));
      expect(punto.lng, inInclusiveRange(-180, 180));
    });
  });

  group('pulsar en el mapa', () {
    Future<void> pintar(
      WidgetTester tester, {
      required ValueChanged<PuntoEnElMapa> alElegir,
      PuntoEnElMapa? punto,
      void Function(QueSeVeEnElMapa)? alVerse,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: anchoDeLaCaja,
                child: MapaParaElegirPunto(
                  fondo: const SinCalles(),
                  punto: punto,
                  alElegir: alElegir,
                  alVerse: alVerse,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('pulsar donde está la chincheta devuelve SU coordenada', (
      tester,
    ) async {
      // El mapa abre centrado en el punto que ya hay (`defaultCenter` del
      // patron), asi que pulsar en el centro del recuadro tiene que devolver ese
      // mismo punto. Es la comprobacion que no depende de ninguna formula: lo
      // que entra por arriba vuelve a salir por abajo.
      const central = PuntoEnElMapa(20.0247, -75.8219);
      PuntoEnElMapa? elegido;
      await pintar(tester, punto: central, alElegir: (p) => elegido = p);

      final recuadro = find.byKey(MapaParaElegirPunto.clave);
      await tester.tapAt(tester.getCenter(recuadro));
      await tester.pump();

      expect(elegido, isNotNull, reason: 'pulsar en el mapa tiene que elegir');
      expect(elegido!.lat, closeTo(central.lat, 1e-6));
      expect(elegido!.lng, closeTo(central.lng, 1e-6));
    });

    testWidgets('media tesela a la derecha son 180/2^zoom grados de longitud', (
      tester,
    ) async {
      // A zoom 15 una tesela (256 px) vale 360/2^15 grados, asi que media tesela
      // (128 px) vale la mitad. Es la definicion de las teselas de OSM, no una
      // cuenta de este fichero. Media y no una entera porque el recuadro mide
      // 512 px: una tesela entera desde el centro cae justo en el borde.
      const central = PuntoEnElMapa(20.0247, -75.8219);
      PuntoEnElMapa? elegido;
      await pintar(tester, punto: central, alElegir: (p) => elegido = p);

      final centro = tester.getCenter(find.byKey(MapaParaElegirPunto.clave));
      await tester.tapAt(centro + const Offset(128, 0));
      await tester.pump();

      expect(elegido!.lng, closeTo(central.lng + 180 / 32768, 1e-6));
      expect(
        elegido!.lat,
        closeTo(central.lat, 1e-9),
        reason: 'moverse a lo ancho no puede cambiar la latitud',
      );
    });

    testWidgets('DOS DEDOS mueven el mapa: lo que estaba en el centro se va '
        'con ellos', (tester) async {
      // El arrastre y el pellizco del mapa son de DOS dedos. Se comprueba por lo
      // unico que se puede comprobar de verdad: despues de arrastrar, pulsar en
      // el mismo pixel devuelve OTRA coordenada, y exactamente la de al lado.
      const central = PuntoEnElMapa(20.0247, -75.8219);
      PuntoEnElMapa? elegido;
      await pintar(tester, punto: central, alElegir: (p) => elegido = p);

      final centro = tester.getCenter(find.byKey(MapaParaElegirPunto.clave));
      final uno = await tester.startGesture(centro);
      final dos = await tester.startGesture(centro + const Offset(20, 0));
      await tester.pump();
      // A PASITOS, y no de un salto. Un solo `moveBy` grande no prueba nada: el
      // reconocedor acepta el gesto **en ese mismo evento**, o sea que empieza a
      // contar ya movido y el mapa se queda donde estaba. Asi pasan por verdes
      // las pruebas de arrastre que no arrastran.
      for (var i = 0; i < 12; i++) {
        await uno.moveBy(const Offset(16, 0));
        await dos.moveBy(const Offset(16, 0));
        await tester.pump();
      }
      await uno.up();
      await dos.up();
      await tester.pump();

      await tester.tapAt(centro);
      await tester.pump();
      // El mapa se corrio a la derecha, asi que en el centro ahora esta lo que
      // antes quedaba a la IZQUIERDA: una longitud menor.
      //
      // Se mide con horquilla y no con el numero exacto a proposito: el
      // reconocedor de gestos no empieza a contar hasta que acepta el gesto, y
      // lo que se movio antes de aceptar no llega nunca al mapa. La cuenta
      // exacta ya esta atada en las pruebas de la proyeccion y en la de pulsar;
      // lo que se comprueba aqui es que **dos dedos mueven el mapa**, que es
      // otra cosa.
      expect(elegido, isNotNull);
      expect(
        elegido!.lng,
        lessThan(central.lng - 90 / 32768),
        reason: 'con dos dedos el mapa tiene que moverse',
      );
      expect(elegido!.lng, greaterThan(central.lng - 360 / 32768));
      expect(
        elegido!.lat,
        closeTo(central.lat, 1e-6),
        reason: 'no se arrastró a lo alto: la latitud no puede cambiar',
      );
    });

    testWidgets('UN dedo NO mueve el mapa: ese arrastre es del cajón', (
      tester,
    ) async {
      // El mapa vive dentro del cuerpo desplazable de un cajon. Si se quedara el
      // arrastre de un dedo, no habria forma de llegar a los botones de abajo —
      // que es el fallo que ya paso el 17/09/2026 en el detalle de la ruta.
      const central = PuntoEnElMapa(20.0247, -75.8219);
      PuntoEnElMapa? elegido;
      await pintar(tester, punto: central, alElegir: (p) => elegido = p);

      final centro = tester.getCenter(find.byKey(MapaParaElegirPunto.clave));
      final uno = await tester.startGesture(centro);
      await tester.pump();
      // A pasitos, por lo mismo que en la de dos dedos: de un salto, ningun
      // arrastre mueve nada y esta prueba saldria verde aunque el mapa se
      // quedara el gesto.
      for (var i = 0; i < 12; i++) {
        await uno.moveBy(const Offset(16, 0));
        await tester.pump();
      }
      await uno.up();
      await tester.pump();

      await tester.tapAt(centro);
      await tester.pump();
      expect(
        elegido!.lng,
        closeTo(central.lng, 1e-6),
        reason: 'con un dedo el mapa no se mueve: el arrastre es del cajón',
      );
    });

    testWidgets('sin teselas, el mapa DICE que no ha cargado el fondo', (
      tester,
    ) async {
      // Con `SinCalles` no llega ninguna. El recuadro sale liso y eso se reporta
      // hacia arriba para que el editor lo escriba: un mapa en blanco sin
      // explicacion encima de un punto que se va a cobrar es el peor sitio para
      // adivinar.
      final dicho = <bool>[];
      await pintar(
        tester,
        punto: const PuntoEnElMapa(20.0247, -75.8219),
        alElegir: (_) {},
        alVerse: (que) => dicho.add(que.conCalles),
      );
      await tester.pump();
      expect(dicho, isNotEmpty, reason: 'el mapa tiene que decir qué se ve');
      expect(dicho.every((v) => v == false), isTrue);
    });
  });
}
