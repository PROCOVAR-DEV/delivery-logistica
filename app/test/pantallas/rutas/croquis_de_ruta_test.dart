// EL MAPA: las dos capas, y sobre todo la de abajo — la que SI se ve en el
// patio del almacen.
//
// La decision esta contada en `croquis_de_ruta.dart`: primero se dibuja lo que
// ya esta en el aparato, y las calles y el recorrido por carretera se piden
// despues y MEJORAN el dibujo si llegan. Aqui se comprueban las dos mitades:
//
//  * que la colocacion es correcta —lo unico que un dibujo puede hacer mal sin
//    que se note es poner las paradas donde no van—, en seco y con numeros;
//  * que el mapa **no depende** de que llegue nada: con `SinCalles` y
//    `SinCallesQueSeguir`, que es exactamente el patio del almacen, sigue
//    entero.
//
// **Ni una peticion sale de aqui.** Las dos fuentes van inyectadas, que es la
// razon de que sean interfaces: en este PC no se cargan teselas de ningun
// servicio.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/vista/croquis_de_ruta.dart';

ParadaDelRecorrido parada(
  int n, {
  double? lat,
  double? lng,
  double? precio,
  String? factura,
  bool entregada = false,
  bool regreso = false,
  bool manual = false,
}) => ParadaDelRecorrido(
  id: 'p$n',
  numero: n,
  etiqueta: 'Cliente $n',
  factura: factura,
  punto: (lat == null || lng == null) ? null : Punto(lat, lng),
  importe: precio,
  entregada: entregada,
  esRegreso: regreso,
  manual: manual,
);

const caja = Size(320, 200);

/// Un cuadradito gris que hace de tesela. Se fabrica aqui dentro: **no se baja
/// nada**, que es la regla de este PC.
Future<ui.Image> unaTesela() {
  final espera = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(List.filled(256 * 256 * 4, 200)),
    256,
    256,
    ui.PixelFormat.rgba8888,
    espera.complete,
  );
  return espera.future;
}

/// Un fondo que SI trae teselas, y apunta cuales le pidieron.
///
/// La imagen se le da ya hecha: decodificarla dentro de un `testWidgets` la deja
/// a medias, porque ahi el reloj lo manda el `tester` y lo que empezo fuera no
/// avanza dentro (`CLAUDE.md` §5). Se fabrica con `tester.runAsync` y se pasa.
class FondoQueSiTrae implements FondoDeCalles {
  FondoQueSiTrae(this.imagen);

  final ui.Image imagen;
  final pedidas = <String>[];

  @override
  Future<ui.Image?> tesela(int z, int x, int y) async {
    pedidas.add('$z/$x/$y');
    return imagen;
  }
}

/// Un fondo que se queda esperando y contesta cuando se le dice. Sirve para
/// mirar qué pasa **en el momento en que llega** una tesela, que es donde se
/// decide si el mapa se repinta.
class UnaTeselaQueLlega implements FondoDeCalles {
  UnaTeselaQueLlega(this.imagen);

  final ui.Image imagen;
  final _pendientes = <Completer<ui.Image?>>[];

  @override
  Future<ui.Image?> tesela(int z, int x, int y) {
    final c = Completer<ui.Image?>();
    _pendientes.add(c);
    return c.future;
  }

  int get cuantasPendientes => _pendientes.length;

  void contesta() {
    for (final c in _pendientes) {
      if (!c.isCompleted) c.complete(imagen);
    }
    _pendientes.clear();
  }
}

/// Un enrutador que SI contesta, y apunta por donde le mandaron pasar.
class CallesQueSiContestan implements RecorridoPorCalles {
  CallesQueSiContestan(this.linea);

  final List<Punto> linea;
  List<Punto>? pedido;

  /// TODAS las peticiones, en orden. Desde el 17/09/2026 son **dos**: la ida y
  /// el regreso por separado, para poder pintarlos distinto.
  final peticiones = <List<Punto>>[];

  @override
  Future<List<Punto>?> entre(List<Punto> puntos) async {
    pedido = puntos;
    peticiones.add(puntos);
    return linea;
  }
}

void main() {
  // EL ALMACÉN DE TESELAS ES DE MÓDULO —para no volver a pedirlas al cambiar de
  // pestaña— así que sobrevive de una prueba a la siguiente. Sin vaciarlo, una
  // prueba que guarda teselas hace que la de «sin señal» las vea y el mapa se
  // dé por «con calles». Pasó el 21/09/2026.
  setUp(olvidarLoTraidoDelMapa);

  group('donde cae cada parada', () {
    test('van en el orden de visita y con su numero', () {
      final trazado = trazar(
        Recorrido(
          origen: const Punto(21.0, -77.0),
          paradas: [
            parada(1, lat: 21.1, lng: -77.1),
            parada(2, lat: 21.2, lng: -77.2),
            parada(3, lat: 21.3, lng: -77.3),
          ],
        ),
        caja,
      );

      expect([for (final p in trazado.paradas) p.parada.numero], [1, 2, 3]);
      // Y la ida empieza en el almacen: `origen → 1 → 2 → 3`, cuatro puntos.
      expect(trazado.ida, hasLength(4));
      expect(trazado.ida.first, trazado.origen);
      expect(trazado.ida.last, trazado.paradas.last.donde);
    });

    test('todo cae DENTRO del recuadro', () {
      final trazado = trazar(
        Recorrido(
          origen: const Punto(21.0, -77.0),
          paradas: [
            parada(1, lat: 22.9, lng: -79.9),
            parada(2, lat: 20.1, lng: -75.1),
          ],
        ),
        caja,
      );

      for (final punto in trazado.ida) {
        expect(punto.dx, inInclusiveRange(0, caja.width));
        expect(punto.dy, inInclusiveRange(0, caja.height));
      }
    });

    test('el norte queda arriba', () {
      final trazado = trazar(
        Recorrido(
          paradas: [
            parada(1, lat: 21.0, lng: -77.0), // la del sur
            parada(2, lat: 21.5, lng: -77.0), // la del norte
          ],
        ),
        caja,
      );

      expect(
        trazado.paradas[1].donde.dy,
        lessThan(trazado.paradas[0].donde.dy),
      );
    });

    test('NO se estira un eje para llenar el recuadro', () {
      // Tres paradas en cruz, a la misma distancia real del almacen. Si cada eje
      // se escalara por su cuenta, la de arriba y la de la derecha caerian a
      // distinta distancia en pantalla y el dibujo mentiria sobre las
      // distancias, que es lo unico que este dibujo tiene que contar bien.
      const centro = Punto(21.0, -77.0);
      // A 21 °N un grado de longitud mide `cos(21°)` de lo que mide uno de
      // latitud, asi que para que los dos brazos midan lo mismo de verdad el de
      // longitud tiene que ser mas largo en grados.
      const brazoLat = 0.2;
      final brazoLng = 0.2 / 0.93358; // 1 / cos(21°)

      final trazado = trazar(
        Recorrido(
          origen: centro,
          paradas: [
            parada(1, lat: 21.0 + brazoLat, lng: -77.0),
            parada(2, lat: 21.0, lng: -77.0 + brazoLng),
          ],
        ),
        caja,
      );

      final arriba = (trazado.paradas[0].donde - trazado.origen!).distance;
      final derecha = (trazado.paradas[1].donde - trazado.origen!).distance;
      expect(arriba, closeTo(derecha, 1));

      // Y las distancias reales tambien son iguales: si esto se cae, el que
      // esta mal es el juego de datos, no el dibujo.
      expect(
        haversineKm(centro, Punto(21.0 + brazoLat, -77.0)),
        closeTo(haversineKm(centro, Punto(21.0, -77.0 + brazoLng)), 0.1),
      );
    });

    test('la escala dice cuantos km mide un pixel', () {
      final trazado = trazar(
        Recorrido(
          paradas: [
            parada(1, lat: 21.0, lng: -77.0),
            parada(2, lat: 21.5, lng: -77.0),
          ],
        ),
        caja,
      );

      final enPixeles =
          (trazado.paradas[1].donde - trazado.paradas[0].donde).distance;
      expect(
        enPixeles * trazado.kmPorPixel,
        closeTo(
          haversineKm(const Punto(21.0, -77.0), const Punto(21.5, -77.0)),
          0.5,
        ),
      );
    });
  });

  group('los casos en que no hay nada que dibujar, o casi', () {
    test('sin coordenadas de ninguna clase, trazado vacio', () {
      expect(
        trazar(Recorrido(paradas: [parada(1), parada(2)]), caja).estaVacio,
        isTrue,
      );
    });

    test('una sola parada se centra y ensena el barrio, sin dividir entre 0', () {
      final trazado = trazar(
        Recorrido(paradas: [parada(1, lat: 21.0, lng: -77.0)]),
        caja,
      );

      expect(trazado.paradas.single.donde, const Offset(160, 100));
      // Nada de `NaN` de dividir entre cero, que es como se ve un dibujo roto.
      expect(trazado.paradas.single.donde.dx.isNaN, isFalse);
      // Y con escala de verdad, para que se le pueda poner un fondo de calles:
      // una unica parada tambien merece un mapa alrededor.
      expect(trazado.zoom, zoomDeUnSoloPunto);
      expect(trazado.kmPorPixel, greaterThan(0));
      expect(trazado.teselasQueHacenFalta(), isNotEmpty);
    });

    test('el almacen solo, sin paradas, ya se dibuja', () {
      final trazado = trazar(
        Recorrido(origen: const Punto(21.0, -77.0), paradas: []),
        caja,
      );

      expect(trazado.estaVacio, isFalse);
      expect(trazado.origen, const Offset(160, 100));
    });

    test('sin almacen se dibujan las paradas igual', () {
      final trazado = trazar(
        Recorrido(
          paradas: [
            parada(1, lat: 21.0, lng: -77.0),
            parada(2, lat: 21.5, lng: -77.5),
          ],
        ),
        caja,
      );

      expect(trazado.origen, isNull);
      expect(trazado.paradas, hasLength(2));
      expect(trazado.ida, hasLength(2));
    });

    test(
      'las paradas sin coordenadas no se dibujan PERO no roban el numero',
      () {
        final trazado = trazar(
          Recorrido(
            paradas: [
              parada(1, lat: 21.0, lng: -77.0),
              parada(2), // sin GPS
              parada(3, lat: 21.5, lng: -77.5),
            ],
          ),
          caja,
        );

        // Dos puntos, pero numerados 1 y 3: el «3» del croquis tiene que ser el
        // «3» de la hoja de cierre, o nadie entiende de que parada se habla.
        expect([for (final p in trazado.paradas) p.parada.numero], [1, 3]);
      },
    );
  });

  group('en pantalla', () {
    Future<void> pintar(
      WidgetTester tester,
      Recorrido recorrido, {
      FondoDeCalles fondo = const SinCalles(),
      RecorridoPorCalles porCalles = const SinCallesQueSeguir(),
      void Function(QueSeVe)? onQueSeVe,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: caja.width,
                child: CroquisDeRuta(
                  recorrido: recorrido,
                  fondo: fondo,
                  porCalles: porCalles,
                  onQueSeVe: onQueSeVe,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final tresParadas = Recorrido(
      origen: const Punto(21.0, -77.0),
      nombreDelOrigen: 'Camagüey',
      paradas: [
        parada(
          1,
          lat: 21.1,
          lng: -77.1,
          precio: 12.5,
          factura: 'Factura 47061 · 15/10/2026',
        ),
        parada(2, lat: 21.2, lng: -77.2),
        parada(3, lat: 21.3, lng: -77.3, precio: 30, entregada: true),
      ],
    );

    testWidgets('la leyenda dice que es cada color', (tester) async {
      await pintar(tester, tresParadas);

      // **Los mismos TRES renglones del patrón**, ni uno más. Jose, 17/09/2026,
      // enseñando `delivery.procovar.cloud`: «mira cómo lo hace la aplicación».
      // Allí son tres —salida, paradas y regreso— y ya estaba bien: el cuarto
      // que teníamos, «Ya entregada», explicaba un color que sólo sale en una
      // ruta cerrada, así que en las otras ocupaba sitio sin decir nada.
      expect(find.text('Punto de partida'), findsOneWidget);
      expect(find.text('Paradas'), findsOneWidget);
      expect(find.text('Regreso al depósito'), findsOneWidget);
      expect(find.text('Ya entregada'), findsNothing);
      // Y el CUARTO, desde el issue 19 de Amado (20/10/2026): el círculo ROJO de la
      // parada con el punto puesto a mano. Lo dice la nota de la leyenda: si se
      // cambia cómo se dibuja una marca, se cambia aquí.
      expect(find.text('Punto puesto a mano'), findsOneWidget);
    });

    testWidgets(
      'que una parada pase a ser manual REPINTA el mapa (shouldRepaint)',
      (tester) async {
        // Lo único que cambia entre los dos dibujos es `manual`, que viaja DENTRO del
        // recorrido: si `shouldRepaint` dejara de mirar el recorrido, el número se
        // quedaría azul hasta que algo más moviera el mapa.
        Recorrido con({required bool manual}) => Recorrido(
          origen: const Punto(21.0, -77.0),
          paradas: [parada(1, lat: 21.1, lng: -77.1, manual: manual)],
        );
        CustomPainter pintor() => tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((c) => c.painter)
            .whereType<CustomPainter>()
            .firstWhere(
              (p) => p.runtimeType.toString().contains('PintorDelCroquis'),
            );

        await pintar(tester, con(manual: false));
        final antes = pintor();
        await pintar(tester, con(manual: true));
        expect(pintor().shouldRepaint(antes), isTrue);
      },
    );

    testWidgets('el globo de una parada con el punto a mano lo dice; el de las '
        'demás no', (tester) async {
      final conManual = Recorrido(
        origen: const Punto(21.0, -77.0),
        nombreDelOrigen: 'Camagüey',
        paradas: [
          parada(1, lat: 21.1, lng: -77.1, manual: true),
          parada(2, lat: 21.2, lng: -77.2),
        ],
      );
      await pintar(tester, conManual);
      final trazado = trazar(conManual, caja);
      final esquina = tester.getTopLeft(find.byKey(CroquisDeRuta.clave));

      await tester.tapAt(esquina + trazado.paradas[1].donde);
      await tester.pump();
      expect(find.byKey(const ValueKey('globo-punto-manual')), findsNothing);

      await tester.tapAt(esquina + trazado.paradas[0].donde);
      await tester.pump();
      expect(find.byKey(const ValueKey('globo-punto-manual')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('d-leyenda: «Punto puesto a mano» es un renglón de la LEYENDA, '
        'esté o no esa parada en la ruta', (tester) async {
      // Sin ninguna parada manual: la leyenda es fija, no depende de la ruta.
      await pintar(tester, tresParadas);
      final leyenda = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_Leyenda',
      );
      expect(leyenda, findsOneWidget);
      expect(
        find.descendant(
          of: leyenda,
          matching: find.text('Punto puesto a mano'),
        ),
        findsOneWidget,
        reason:
            'la entrada tiene que estar en la leyenda, no en cualquier sitio',
      );
      // Y en su sitio: el cuarto, detrás de los tres del patrón.
      final textos = tester
          .widgetList<Text>(
            find.descendant(of: leyenda, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      expect(textos, [
        'Punto de partida',
        'Paradas',
        'Regreso al depósito',
        'Punto puesto a mano',
      ]);
      // Nada de globo abierto: el texto sale UNA vez, en la leyenda.
      expect(find.text('Punto puesto a mano'), findsOneWidget);
    });

    testWidgets('d-globo: el globo de una parada manual DICE «Punto puesto a '
        'mano» y el de una que no lo es, no', (tester) async {
      final conManual = Recorrido(
        origen: const Punto(21.0, -77.0),
        nombreDelOrigen: 'Camagüey',
        paradas: [
          parada(1, lat: 21.1, lng: -77.1, manual: true),
          parada(2, lat: 21.2, lng: -77.2),
        ],
      );
      await pintar(tester, conManual);
      final trazado = trazar(conManual, caja);
      final esquina = tester.getTopLeft(find.byKey(CroquisDeRuta.clave));
      final globo = find.byKey(const ValueKey('globo-punto-manual'));

      // Una que NO es manual: ni la clave ni el texto en el globo (solo queda el
      // de la leyenda).
      await tester.tapAt(esquina + trazado.paradas[1].donde);
      await tester.pump();
      expect(globo, findsNothing);
      expect(find.text('Punto puesto a mano'), findsOneWidget);

      // La manual: la línea del globo trae el texto, y suma al de la leyenda.
      await tester.tapAt(esquina + trazado.paradas[0].donde);
      await tester.pump();
      expect(globo, findsOneWidget);
      expect(
        tester.widget<Text>(globo).data,
        'Punto puesto a mano',
        reason: 'la línea del globo tiene que decir qué es',
      );
      expect(find.text('Punto puesto a mano'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('d-repaint-simbolo: el pintor del símbolo de la leyenda se '
        'repinta si le cambian el símbolo y no si es el mismo', (tester) async {
      await pintar(tester, tresParadas);
      final pintores = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .where((p) => p.runtimeType.toString() == '_PintorDelSimbolo')
          .toList();
      // Los cuatro renglones de la leyenda, cada uno con SU símbolo.
      expect(pintores, hasLength(4));
      expect(pintores[0].shouldRepaint(pintores[1]), isTrue);
      expect(pintores[3].shouldRepaint(pintores[0]), isTrue);
      expect(pintores[2].shouldRepaint(pintores[2]), isFalse);
    });

    test('acercar cambia la ESCALA del trazado, no sólo las paradas', () {
      // El fallo que Jose vio tres veces seguidas —«le di acercar y sigue sin
      // funcionar»—. Las paradas se separaban pero el mapa de debajo se quedaba
      // clavado y la barra seguía diciendo los mismos kilómetros, porque
      // `trazar` devolvía la escala del encuadre SIN el acercamiento. De esa
      // escala salen las teselas que se piden, la barra y dónde cae el globo.
      //
      // Se mira la escala y no un píxel de una parada a propósito: es lo que
      // usa todo lo demás, y es justo la mitad que se quedaba fuera.
      const caja = Size(400, 300);
      final normal = trazar(tresParadas, caja);
      final cerca = trazar(tresParadas, caja, acercamiento: 4);

      expect(
        cerca.escala,
        closeTo(normal.escala * 4, normal.escala * 0.001),
        reason:
            'EL ZOOM NO LLEGA AL TRAZADO: acercar mueve las paradas pero deja '
            'las teselas y la barra de escala como estaban',
      );
      // Y de ahí sale el nivel de tesela: cuatro veces es dos niveles más.
      expect(cerca.zoom, normal.zoom + 2);
      // La barra de kilómetros también: al acercar, un píxel mide menos.
      expect(cerca.kmPorPixel, lessThan(normal.kmPorPixel));
    });

    testWidgets('cuando LLEGA una tesela, el mapa se repinta', (tester) async {
      // Visto en el teléfono el 21/09/2026, con el mapa de Cuba bajado y el
      // avión puesto: una sola tesela dibujada arriba a la izquierda y el resto
      // del recuadro en blanco, mientras el texto decía «Mapa de calles». Las
      // teselas llegaban y nadie volvía a pintar.
      //
      // La causa: el almacén de teselas es de MÓDULO —para no volver a pedirlas
      // al cambiar de pestaña— así que el pintor viejo y el nuevo sostienen el
      // mismo objeto, y `viejo.teselas.length != teselas.length` compara un
      // mapa consigo mismo. Siempre falso. Ahora hay un sello que sólo sube.
      //
      // La prueba mira el PINTOR, no un píxel: es donde se decide, y un píxel
      // de una tesela de mentira no distingue «no se pintó» de «se pintó gris».
      olvidarLoTraidoDelMapa();
      final calles = UnaTeselaQueLlega((await tester.runAsync(unaTesela))!);
      await pintar(tester, tresParadas, fondo: calles);

      CustomPainter pintorDeAhora() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .first;

      // Las teselas se piden en un `addPostFrameCallback`, así que hace falta
      // un fotograma para que la petición salga siquiera.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final antes = pintorDeAhora();
      calles.contesta();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        pintorDeAhora().shouldRepaint(antes),
        isTrue,
        reason:
            'LLEGÓ UNA TESELA Y EL MAPA NO SE REPINTA: el almacén es compartido, '
            'así que comparar su tamaño compara un objeto consigo mismo. Hace '
            'falta un sello que suba con cada tesela guardada.',
      );
    });

    testWidgets('los botones de acercar y alejar MUEVEN el mapa', (
      tester,
    ) async {
      // Jose, 17/09/2026, dos veces seguidas: «el zoom y el alejar no funcionan
      // aún». Y no funcionaban, pero los botones estaban bien: pulsarlos
      // cambiaba el estado y `setState` corría. Lo que fallaba era el
      // `shouldRepaint` del pintor, que no miraba el acercamiento — así que
      // Flutter se ahorraba el repintado y el mapa se quedaba clavado.
      //
      // Por eso esta prueba NO se conforma con que el botón exista ni con que
      // el estado cambie: coge el pintor de antes y el de después y comprueba
      // que el de después **pide repintarse**. Es lo único que distingue un
      // botón que funciona de uno que parece roto sin estarlo.
      await pintar(tester, tresParadas);

      CustomPainter pintorDeAhora() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .first;

      final antes = pintorDeAhora();
      await tester.tap(find.byTooltip('Acercar (o Ctrl + rueda)'));
      await tester.pump();
      final despues = pintorDeAhora();

      expect(
        despues.shouldRepaint(antes),
        isTrue,
        reason:
            'ACERCAR NO REPINTA: el botón cambia el estado pero el mapa se '
            'queda igual. Todos los campos que lee `paint` tienen que estar en '
            '`shouldRepaint`.',
      );

      // Y el de encuadrar sólo sale cuando hay algo a lo que volver.
      expect(find.byTooltip('Ver la ruta entera'), findsOneWidget);
      await tester.tap(find.byTooltip('Ver la ruta entera'));
      await tester.pump();
      expect(find.byTooltip('Ver la ruta entera'), findsNothing);
    });

    // EL PELLIZCO DE DOS DEDOS, QUE NO LLEGABA NUNCA — 22/09/2026.
    //
    // Jose, después de darlo por arreglado dos veces: «sigo sin poder hacer zoom
    // con los dedos».
    //
    // La causa era la subasta de gestos. Había DOS reconocedores en el mismo
    // `RawGestureDetector`: el arrastre aceptaba a los 3 px —en el primer
    // fotograma del primer dedo— y al aceptar **expulsaba al pellizco**, que
    // todavía estaba esperando al segundo dedo. Mover funcionaba; el zoom no
    // llegaba jamás. Ni un error, ni nada que mirar.
    //
    // Y por eso esta prueba pone DOS dedos de verdad: por cable no se puede
    // —`adb shell input` no hace multitáctil— y por eso el fallo sobrevivió a
    // dos rondas de pruebas en el teléfono. Aquí sí se puede, y es el único
    // sitio donde se puede.
    testWidgets('DOS DEDOS separándose acercan el mapa', (tester) async {
      await pintar(tester, tresParadas);

      CustomPainter pintorDeAhora() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .first;

      // El centro DEL MAPA, no el del widget: `CroquisDeRuta` lleva además la
      // leyenda debajo, y su centro cae fuera del dibujo.
      final elMapa = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString().contains('PintorDelCroquis'),
      );
      final centro = tester.getCenter(elMapa.first);
      final antes = pintorDeAhora();

      // Dos dedos a la vez, separándose. El orden importa: los dos abajo antes
      // de mover ninguno, que es lo que hace un pellizco de verdad.
      final uno = await tester.startGesture(centro - const Offset(20, 0));
      final dos = await tester.startGesture(centro + const Offset(20, 0));
      await tester.pump();
      for (var paso = 0; paso < 6; paso++) {
        await uno.moveBy(const Offset(-12, 0));
        await dos.moveBy(const Offset(12, 0));
        await tester.pump();
      }
      await uno.up();
      await dos.up();
      await tester.pump();

      expect(
        pintorDeAhora().shouldRepaint(antes),
        isTrue,
        reason:
            'EL PELLIZCO NO LLEGA AL MAPA. Con dos dedos separándose el '
            'acercamiento tiene que cambiar; si no, es que otro reconocedor se '
            'llevó el gesto antes de que aterrizara el segundo dedo.',
      );
    });

    testWidgets('UN dedo sigue moviendo el mapa, no la pantalla', (
      tester,
    ) async {
      // La pareja, y es la decisión de Jose del 21/09: «que un dedo mueva el
      // mapa ahí mismo». Al pasar a un solo reconocedor esto se podía haber
      // perdido —`ScaleGestureRecognizer` acepta al doble de distancia que la
      // lista— y por eso se le baja el umbral con `gestureSettings`.
      await pintar(tester, tresParadas);

      CustomPainter pintorDeAhora() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .first;

      // El centro DEL MAPA, no el del widget: `CroquisDeRuta` lleva además la
      // leyenda debajo, y su centro cae fuera del dibujo.
      final elMapa = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString().contains('PintorDelCroquis'),
      );
      final centro = tester.getCenter(elMapa.first);
      final antes = pintorDeAhora();

      final dedo = await tester.startGesture(centro);
      for (var paso = 0; paso < 6; paso++) {
        await dedo.moveBy(const Offset(0, -10));
        await tester.pump();
      }
      await dedo.up();
      await tester.pump();

      expect(
        pintorDeAhora().shouldRepaint(antes),
        isTrue,
        reason:
            'UN DEDO YA NO MUEVE EL MAPA. Es la decisión del 21/09: el dedo '
            'encima del mapa mueve el mapa, y la pantalla se baja tocando '
            'fuera de él.',
      );
    });

    // Y LA LISTA DE DEBAJO NO SE LO LLEVA — la mitad que cuesta.
    //
    // El mapa vive dentro de algo que se desplaza (el detalle de la ruta). Sin
    // bajarle el umbral, `ScaleGestureRecognizer` acepta a los 36 px y la lista
    // a los 18: acepta antes ella, cierra la subasta, y el mapa se queda
    // sellado. Es el fallo del 17/09 al revés, y por eso el `gestureSettings`
    // no es adorno.
    testWidgets('dentro de una lista, el dedo sobre el mapa mueve EL MAPA', (
      tester,
    ) async {
      final controlador = ScrollController();
      addTearDown(controlador.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controlador,
              children: [
                const SizedBox(height: 40),
                SizedBox(
                  width: caja.width,
                  child: CroquisDeRuta(
                    recorrido: tresParadas,
                    fondo: const SinCalles(),
                    porCalles: const SinCallesQueSeguir(),
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      CustomPainter pintorDeAhora() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .firstWhere(
            (p) => p.runtimeType.toString().contains('PintorDelCroquis'),
          );

      final elMapa = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString().contains('PintorDelCroquis'),
      );
      final antes = pintorDeAhora();

      final dedo = await tester.startGesture(tester.getCenter(elMapa.first));
      for (var paso = 0; paso < 5; paso++) {
        await dedo.moveBy(const Offset(0, -8));
        await tester.pump();
      }
      await dedo.up();
      await tester.pump();

      expect(
        controlador.offset,
        0,
        reason:
            'LA LISTA SE LLEVÓ EL GESTO. Con el dedo encima del mapa la '
            'pantalla no se baja: se mueve el mapa (decisión de Jose, '
            '21/09/2026). Si esto falla, el mapa está sellado otra vez.',
      );
      expect(
        pintorDeAhora().shouldRepaint(antes),
        isTrue,
        reason: 'y el mapa sí se movió',
      );
    });

    testWidgets('tocar una parada ensena su nombre y su importe', (
      tester,
    ) async {
      await pintar(tester, tresParadas);

      final trazado = trazar(tresParadas, caja);
      final esquina = tester.getTopLeft(find.byKey(CroquisDeRuta.clave));

      expect(find.textContaining('Cliente 1'), findsNothing);
      await tester.tapAt(esquina + trazado.paradas.first.donde);
      await tester.pump();

      expect(find.text('1. Cliente 1'), findsOneWidget);
      expect(find.text(r'$12.50'), findsOneWidget);
    });

    // ISSUE 17 DE AMADO (16/10/2026): el globo abre con la factura y su fecha, antes que el
    // cliente. En pareja: con factura, y sin ella la frase de siempre.
    testWidgets('el globo abre con la factura y su fecha, en negrita, y el '
        'cliente debajo', (tester) async {
      await pintar(tester, tresParadas);

      final trazado = trazar(tresParadas, caja);
      final esquina = tester.getTopLeft(find.byKey(CroquisDeRuta.clave));
      await tester.tapAt(esquina + trazado.paradas.first.donde);
      await tester.pump();

      final factura = find.byKey(const ValueKey('globo-factura-p1'));
      expect(tester.widget<Text>(factura).data, 'Factura 47061 · 15/10/2026');
      expect(tester.widget<Text>(factura).style!.fontWeight, FontWeight.w800);
      expect(
        tester.getTopLeft(factura).dy,
        lessThan(tester.getTopLeft(find.text('1. Cliente 1')).dy),
        reason: 'la factura va encima del cliente',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('una parada sin factura dice «Sin número de factura» en el '
        'globo', (tester) async {
      await pintar(tester, tresParadas);

      final trazado = trazar(tresParadas, caja);
      final esquina = tester.getTopLeft(find.byKey(CroquisDeRuta.clave));
      await tester.tapAt(esquina + trazado.paradas[1].donde);
      await tester.pump();

      final factura = find.byKey(const ValueKey('globo-factura-p2'));
      expect(tester.widget<Text>(factura).data, 'Sin número de factura');
      expect(tester.widget<Text>(factura).style!.fontWeight, FontWeight.w400);
      expect(find.textContaining('Factura '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una parada sin precio dice «sin cotizar», no cero', (
      tester,
    ) async {
      await pintar(tester, tresParadas);

      final trazado = trazar(tresParadas, caja);
      final esquina = tester.getTopLeft(find.byKey(CroquisDeRuta.clave));
      await tester.tapAt(esquina + trazado.paradas[1].donde);
      await tester.pump();

      // Un `$0.00` se lee como «este domicilio es gratis»: un numero creible y
      // equivocado, que es lo peor que le puede pasar a algo que alguien cobra.
      expect(find.text('2. Cliente 2'), findsOneWidget);
      expect(find.text('sin cotizar'), findsOneWidget);
      expect(find.text(r'$0.00'), findsNothing);
    });

    testWidgets('tocar fuera cierra el globo', (tester) async {
      await pintar(tester, tresParadas);

      final trazado = trazar(tresParadas, caja);
      final esquina = tester.getTopLeft(find.byKey(CroquisDeRuta.clave));
      await tester.tapAt(esquina + trazado.paradas.first.donde);
      await tester.pump();
      expect(find.text('1. Cliente 1'), findsOneWidget);

      await tester.tapAt(esquina + const Offset(4, 4));
      await tester.pump();
      expect(find.text('1. Cliente 1'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // LAS DOS CAPAS
  //
  // La de abajo —el croquis— no le pide nada a nadie. La de arriba —las calles y
  // el recorrido por carretera— llega o no llega, y **el mapa tiene que servir
  // en los dos casos**. Eso es lo que se comprueba aqui, y sin una sola
  // peticion: las dos fuentes van inyectadas.
  // ───────────────────────────────────────────────────────────────────────────
  group('el fondo de calles', () {
    test('las teselas elegidas tapan el recuadro entero', () {
      final trazado = trazar(
        Recorrido(
          origen: const Punto(21.36, -77.92),
          paradas: [
            parada(1, lat: 21.40, lng: -77.88),
            parada(2, lat: 21.38, lng: -77.95),
          ],
        ),
        caja,
      );

      final teselas = trazado.teselasQueHacenFalta();
      expect(teselas, isNotEmpty);

      // Las cuatro esquinas del recuadro caen dentro de alguna de ellas: si
      // faltara una fila, el mapa saldria con una franja de papel a un lado.
      for (final esquina in [
        const Offset(0.5, 0.5),
        Offset(caja.width - 0.5, 0.5),
        Offset(0.5, caja.height - 0.5),
        Offset(caja.width - 0.5, caja.height - 0.5),
      ]) {
        expect(
          teselas.any(
            (t) => trazado.recuadroDe(t.z, t.x, t.y).contains(esquina),
          ),
          isTrue,
          reason: 'la esquina $esquina se queda sin tesela',
        );
      }
    });

    test('el fondo y los pines usan la MISMA proyeccion', () {
      // Si el fondo se colocara con una proyeccion y los pines con otra, el mapa
      // se veria bien y estaria mal: las paradas saldrian en la calle de al
      // lado. Por eso la tesela que le toca a una parada tiene que contenerla.
      const donde = Punto(21.38, -77.91);
      final trazado = trazar(
        Recorrido(
          origen: const Punto(21.30, -77.99),
          paradas: [parada(1, lat: donde.lat, lng: donde.lng)],
        ),
        caja,
      );

      final z = trazado.zoom;
      final cuantas = 1 << z;
      final tx = (aLoAncho(donde.lng) * cuantas).floor();
      final ty = (aLoAlto(donde.lat) * cuantas).floor();

      expect(
        trazado.recuadroDe(z, tx, ty).contains(trazado.paradas.single.donde),
        isTrue,
      );
    });

    test('el zoom no se pasa: una tesela nunca se encoge', () {
      final trazado = trazar(
        Recorrido(
          paradas: [
            parada(1, lat: 21.0, lng: -77.0),
            parada(2, lat: 21.5, lng: -77.5),
          ],
        ),
        caja,
      );

      // Con el zoom elegido, el lado de una tesela en pantalla va de 256 px
      // (inclusive) a 512 px: se amplia como mucho al doble y nunca se encoge,
      // que es lo que emborrona las calles hasta no poder leerlas.
      final lado = trazado.escala / (1 << trazado.zoom);
      expect(lado, greaterThanOrEqualTo(ladoDeTesela));
      expect(lado, lessThan(2 * ladoDeTesela));
    });
  });

  group('con señal y sin ella', () {
    final tresParadas = Recorrido(
      origen: const Punto(21.0, -77.0),
      nombreDelOrigen: 'Camagüey',
      paradas: [
        parada(1, lat: 21.1, lng: -77.1),
        parada(2, lat: 21.2, lng: -77.2),
      ],
    );

    Future<void> pintar(
      WidgetTester tester,
      Recorrido recorrido, {
      FondoDeCalles fondo = const SinCalles(),
      RecorridoPorCalles porCalles = const SinCallesQueSeguir(),
      void Function(QueSeVe)? onQueSeVe,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: caja.width,
                child: CroquisDeRuta(
                  recorrido: recorrido,
                  fondo: fondo,
                  porCalles: porCalles,
                  onQueSeVe: onQueSeVe,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('SIN señal el mapa sale entero y no promete calles', (
      tester,
    ) async {
      // Este es el patio del almacen: ni teselas ni OSRM.
      final visto = <QueSeVe>[];
      await pintar(tester, tresParadas, onQueSeVe: visto.add);

      // El mapa esta ahi, con su leyenda y sus paradas tocables.
      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
      expect(find.text('Punto de partida'), findsOneWidget);

      final trazado = trazar(tresParadas, caja);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(CroquisDeRuta.clave)) +
            trazado.paradas.first.donde,
      );
      await tester.pump();
      expect(find.text('1. Cliente 1'), findsOneWidget);

      // Y NO se avisa de nada que no haya llegado: quien escucha se queda con
      // «ni calles ni carretera», que es la verdad.
      expect(visto.where((q) => q.conCalles), isEmpty);
      expect(visto.where((q) => q.recorridoPorCarretera), isEmpty);
    });

    testWidgets('CON señal se pintan las calles y se avisa', (tester) async {
      final fondo = FondoQueSiTrae((await tester.runAsync(unaTesela))!);
      final visto = <QueSeVe>[];
      await pintar(tester, tresParadas, fondo: fondo, onQueSeVe: visto.add);

      expect(fondo.pedidas, isNotEmpty);
      expect(visto.last.conCalles, isTrue);
    });

    testWidgets('la ida y el REGRESO se piden por separado', (tester) async {
      // Jose, 17/09/2026: «sigue sin entenderse cuándo se va y cuándo se vira».
      // Antes se pedía el circuito cerrado de una vez y OSRM devolvía UNA línea
      // con la ida y la vuelta pegadas: imposible pintarlas distinto, así que la
      // leyenda prometía un «regreso al depósito» que con calles no se dibujaba
      // nunca. Ahora son dos peticiones y dos trazos.
      final calles = CallesQueSiContestan(const [
        Punto(21.0, -77.0),
        Punto(21.2, -77.2),
      ]);
      final visto = <QueSeVe>[];
      await pintar(
        tester,
        tresParadas,
        porCalles: calles,
        onQueSeVe: visto.add,
      );

      expect(
        calles.peticiones.length,
        2,
        reason: 'una la ida, otra el regreso',
      );
      // La ida: origen → paradas en orden, y **sin volver**.
      expect(
        [for (final p in calles.peticiones[0]) '${p.lat},${p.lng}'],
        ['21.0,-77.0', '21.1,-77.1', '21.2,-77.2'],
      );
      // El regreso: última parada → almacén.
      expect(
        [for (final p in calles.peticiones[1]) '${p.lat},${p.lng}'],
        ['21.2,-77.2', '21.0,-77.0'],
      );
      expect(visto.last.recorridoPorCarretera, isTrue);
    });

    testWidgets('si las calles fallan, el mapa no se entera siquiera', (
      tester,
    ) async {
      // `SinCalles` es literalmente lo que devuelve la de verdad cuando no hay
      // señal: `null`, sin lanzar. La pantalla no puede caerse por eso.
      final visto = <QueSeVe>[];
      await pintar(
        tester,
        tresParadas,
        fondo: const SinCalles(),
        porCalles: const SinCallesQueSeguir(),
        onQueSeVe: visto.add,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
    });
  });
}
