// EL BLOQUE DEL MAPA: lo que se ve, lo que DICE que se esta viendo, y lo que
// sale del aparato cuando se pulsa.
//
// Jose, 17/09/2026: «El mapa, ¿por qué no me sale el mapa con la ruta, si
// teníamos hasta para compartir la ruta por WhatsApp?».
//
// Las tres cosas que se vigilan aqui son las tres que fallan lejos de esta
// oficina:
//
//  1. **Que la pantalla diga lo que ensena.** El croquis no lleva calles; quien
//     lo mire tiene que enterarse ahi, no comparandolo con Google Maps.
//  2. **Que la web y el aparato no digan lo mismo** (regla 1): la promesa de
//     «se ve igual sin señal» es de la APK; en un navegador cuenta algo que no
//     pasa nunca.
//  3. **Que los botones manden lo que toca.** Un enlace mal armado no falla
//     aqui: falla en el telefono del chofer.
//
// Nada de esto toca la red. El aparato va inyectado: es la razon de que
// `AbrirYCompartir` sea una interfaz y no un `launchUrl` suelto dentro del
// boton.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/croquis_de_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/pantallas/rutas/vista/mapa_de_la_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'rutas_a_mano.dart';

/// El aparato de mentira: apunta lo que se le pide y contesta lo que le digan.
class AparatoEspia implements AbrirYCompartir {
  AparatoEspia({this.abre = true, this.comparte = true, this.copia = true});

  bool abre;
  bool comparte;
  bool copia;

  final abiertos = <Uri>[];
  final compartidos = <({String texto, String? asunto})>[];
  final copiados = <String>[];

  @override
  Future<bool> abrir(Uri destino) async {
    abiertos.add(destino);
    return abre;
  }

  @override
  Future<bool> compartir({required String texto, String? asunto}) async {
    compartidos.add((texto: texto, asunto: asunto));
    return comparte;
  }

  @override
  Future<bool> copiar(String texto) async {
    copiados.add(texto);
    return copia;
  }
}

RutaConTodo laRutaDeSiempre({int cuantas = 3}) => rutaAMano(
  vehiculo: camionAMano(),
  paradas: [
    for (var i = 1; i <= cuantas; i++)
      paradaAMano(
        id: 'p$i',
        cliente: 'Cliente $i',
        lat: 21 + i / 100,
        lng: -77 - i / 100,
      ),
  ],
);

void main() {
  late AparatoEspia aparato;

  setUp(() => aparato = AparatoEspia());

  Future<void> pintar(
    WidgetTester tester,
    RutaConTodo ruta, {
    required bool enElAparato,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // El destino se pone por provider y no compilando para web: es lo que
          // deja ejercitar las dos mitades de la regla 1 en la misma suite.
          trabajaSinConexionProvider.overrideWithValue(enElAparato),
          abrirYCompartirProvider.overrideWithValue(aparato),
          // EL PATIO DEL ALMACEN, por defecto: ni teselas ni OSRM. Ademas de ser
          // el caso que mas importa, es lo que garantiza que **de esta maquina
          // no sale una peticion**.
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
          recorridoPorCallesProvider.overrideWithValue(
            const SinCallesQueSeguir(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: MapaDeLaRuta(ruta: ruta),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // ───────────────────────────────────────────────────────────────────────────
  group('la pantalla dice lo que esta ensenando', () {
    testWidgets('en la APK, sin calles, cuenta que sale del aparato', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(
        find.textContaining(TextosDelMapa.croquisEnElAparato),
        findsOneWidget,
      );
      expect(find.textContaining(TextosDelMapa.croquisEnLaWeb), findsNothing);
    });

    testWidgets('en la web NO se le promete nada sobre la señal', (
      tester,
    ) async {
      // Quien abre un navegador tiene internet, siempre. Contarle que algo «se
      // ve igual sin señal» es explicarle algo que en su caso no pasa nunca, y
      // eso es justo lo que se saca de la web.
      await pintar(tester, laRutaDeSiempre(), enElAparato: false);

      expect(find.textContaining(TextosDelMapa.croquisEnLaWeb), findsOneWidget);
      expect(
        find.textContaining(TextosDelMapa.croquisEnElAparato),
        findsNothing,
      );
      expect(find.textContaining('Sin señal'), findsNothing);
    });

    testWidgets('sin el recorrido por carretera se dice que es aproximado', (
      tester,
    ) async {
      // Lo peor que podria hacer esta pantalla es dibujar una linea recta entre
      // dos paradas y dejar que se lea como «por aquí va la carretera».
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(
        find.textContaining(TextosDelMapa.recorridoAproximado),
        findsOneWidget,
      );
      expect(
        find.textContaining(TextosDelMapa.recorridoPorCarretera),
        findsNothing,
      );
    });

    testWidgets('la frase dice lo que cambia, y NADA MÁS', (tester) async {
      // Jose, 17/09/2026: «sin tanto texto». Antes la frase llevaba pegado un
      // «las paradas van numeradas en su orden de visita; para navegar por la
      // calle: Abrir en Google Maps», que es justo lo que ya dicen la leyenda y
      // el botón que están a dos dedos. El patrón no escribe ni una línea
      // debajo del mapa.
      //
      // Lo que SÍ se sigue diciendo es lo que cambia el diagnóstico: si son
      // calles o croquis, y si el recorrido es el de verdad o una línea recta.
      // Sin eso, una recta se lee como la ruta buena.
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(TextosDelMapa.siempre, isEmpty);
      expect(find.textContaining('Abrir en Google Maps.'), findsNothing);
      // Una de las dos, según haya contestado el servicio de calles o no: lo
      // que no puede pasar es que no diga ninguna.
      expect(
        find
                .textContaining(TextosDelMapa.recorridoPorCarretera)
                .evaluate()
                .length +
            find
                .textContaining(TextosDelMapa.recorridoAproximado)
                .evaluate()
                .length,
        1,
      );
    });
  });

  group('la frase se arma de trozos, y cada estado tiene el suyo', () {
    // Los cuatro cruces, en seco: es donde se ve que ninguna combinacion se
    // queda sin frase ni dice dos cosas a la vez.
    for (final enElAparato in [true, false]) {
      for (final conCalles in [true, false]) {
        for (final porCarretera in [true, false]) {
          test(
            'aparato=$enElAparato calles=$conCalles carretera=$porCarretera',
            () {
              final frase = TextosDelMapa.queSeEstaViendo((
                conCalles: conCalles,
                recorridoPorCarretera: porCarretera,
              ), enElAparato: enElAparato);

              // CON TODO BIEN, NI UNA PALABRA. Jose, 17/09/2026: «hay varios
              // botones que están cortados; podríamos quitar ese texto y que
              // quepan ahí sin necesidad de tener scroll en esa vista». Y es
              // que la frase describía lo que ya se ve.
              if (conCalles && porCarretera) {
                expect(
                  frase,
                  isEmpty,
                  reason:
                      'con calles y recorrido de verdad no hay nada que '
                      'avisar: la frase sobra y empuja los botones fuera',
                );
                return;
              }
              // En los otros tres SÍ se dice, porque cambian el diagnóstico:
              // una línea recta no son los kilómetros del camión, y un croquis
              // no son las calles.
              expect(
                frase,
                contains(
                  porCarretera
                      ? TextosDelMapa.recorridoPorCarretera
                      : TextosDelMapa.recorridoAproximado,
                ),
              );
              if (conCalles) {
                // Con las calles puestas no hay nada que explicar sobre la
                // cobertura, y no se explica.
                expect(frase, contains(TextosDelMapa.conCalles));
                expect(frase, isNot(contains('Sin señal')));
                expect(frase, isNot(contains('no cargó')));
              } else {
                expect(
                  frase,
                  contains(
                    enElAparato
                        ? TextosDelMapa.croquisEnElAparato
                        : TextosDelMapa.croquisEnLaWeb,
                  ),
                );
              }
            },
          );
        }
      }
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('nunca un cuadro gris', () {
    testWidgets('con coordenadas se dibuja el croquis', (tester) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
      expect(find.byKey(claveDeSinRecorrido), findsNothing);
    });

    testWidgets('sin ninguna coordenada sale un recuadro que lo DICE', (
      tester,
    ) async {
      final ruta = rutaAMano(
        origenLat: null,
        origenLng: null,
        paradas: [
          paradaAMano(id: 'p1', cliente: 'Ana'),
          paradaAMano(id: 'p2', cliente: 'Beto'),
        ],
      );
      await pintar(tester, ruta, enElAparato: true);

      expect(find.byKey(CroquisDeRuta.clave), findsNothing);
      expect(find.byKey(claveDeSinRecorrido), findsOneWidget);
      expect(find.textContaining('ninguna de las 2 paradas'), findsOneWidget);
    });

    testWidgets('sin paradas lo dice con sus palabras, no con un hueco', (
      tester,
    ) async {
      await pintar(
        tester,
        rutaAMano(origenLat: null, origenLng: null, paradas: []),
        enElAparato: true,
      );

      expect(find.byKey(claveDeSinRecorrido), findsOneWidget);
      expect(find.textContaining('todavía no tiene paradas'), findsOneWidget);
    });

    testWidgets('sin almacen pero con paradas, se dibuja igual y se avisa', (
      tester,
    ) async {
      final ruta = rutaAMano(
        origenLat: null,
        origenLng: null,
        paradas: [paradaAMano(id: 'p1', cliente: 'Ana', lat: 21.1, lng: -77.1)],
      );
      await pintar(tester, ruta, enElAparato: true);

      // El dibujo sale —es lo que hay— y el motivo de que no haya enlace
      // tambien: son dos cosas distintas y fallan por separado.
      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
      expect(find.textContaining('almacén de salida'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(claveDeAbrirEnGoogleMaps))
            .onPressed,
        isNull,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('lo que sale del aparato al pulsar', () {
    testWidgets('«Abrir en Google Maps» manda las paradas EN ORDEN', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeAbrirEnGoogleMaps));
      await tester.pump();

      expect(aparato.abiertos, hasLength(1));
      final partes = aparato.abiertos.single.queryParameters;
      expect(partes['waypoints'], '21.01,-77.01|21.02,-77.02|21.03,-77.03');
      expect(partes['origin'], '21.38,-77.91');
      expect(partes['destination'], '21.38,-77.91');
    });

    testWidgets('WhatsApp recibe el mensaje, y acaba en el enlace', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeWhatsApp));
      await tester.pump();

      final destino = aparato.abiertos.single;
      expect(destino.host, 'wa.me');
      final mensaje = destino.queryParameters['text']!;
      expect(mensaje, startsWith('Ruta RT-001'));
      expect(mensaje, contains('3 paradas'));
      expect(mensaje, contains('Camión 1 (P-001)'));
      expect(
        mensaje.split('\n').last,
        startsWith('https://www.google.com/maps'),
      );
    });

    testWidgets('«Compartir» saca el cajon del sistema con texto y asunto', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeCompartir));
      await tester.pump();

      expect(aparato.compartidos, hasLength(1));
      expect(aparato.compartidos.single.asunto, 'Ruta RT-001');
      expect(
        aparato.compartidos.single.texto,
        contains('https://www.google.com/maps'),
      );
      // Y no se abre nada por su cuenta: compartir es compartir.
      expect(aparato.abiertos, isEmpty);
    });

    testWidgets('«Copiar» deja el mensaje entero, no solo el enlace', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeCopiar));
      await tester.pump();

      expect(aparato.copiados.single, startsWith('Ruta RT-001'));
      expect(aparato.copiados.single, contains('https://www.google.com/maps'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('si falla, la pantalla NO se queda verde', () {
    testWidgets('no se pudo abrir Google Maps: se dice, y con el motivo', (
      tester,
    ) async {
      aparato.abre = false;
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeAbrirEnGoogleMaps));
      await tester.pump();

      expect(find.text(TextosDelMapa.noSeAbrio), findsOneWidget);
    });

    testWidgets('no se pudo compartir: se dice y se ofrece copiar', (
      tester,
    ) async {
      aparato.comparte = false;
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeCompartir));
      await tester.pump();

      expect(find.text(TextosDelMapa.noSeCompartio), findsOneWidget);
    });

    testWidgets('cuando SI se abre, no sale ningun aviso', (tester) async {
      // La pareja de la de arriba: un aviso que sale siempre deja de leerse, y
      // entonces tampoco se lee el dia que importa (`CLAUDE.md` §3-quinquies).
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeAbrirEnGoogleMaps));
      await tester.pump();

      expect(find.text(TextosDelMapa.noSeAbrio), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('lo que no cabe en el enlace se dice en la pantalla', () {
    testWidgets('con 30 paradas, el aviso esta a la vista', (tester) async {
      await pintar(tester, laRutaDeSiempre(cuantas: 30), enElAparato: true);

      expect(find.byKey(claveDeLoQueQuedaFuera), findsOneWidget);
      expect(find.textContaining('5 paradas quedan fuera'), findsOneWidget);
    });

    testWidgets('con 3 paradas no hay aviso que estorbe', (tester) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(find.byKey(claveDeLoQueQuedaFuera), findsNothing);
    });

    testWidgets('y el chofer se entera tambien por WhatsApp', (tester) async {
      await pintar(tester, laRutaDeSiempre(cuantas: 30), enElAparato: true);
      await tester.tap(find.byKey(claveDeWhatsApp));
      await tester.pump();

      expect(
        aparato.abiertos.single.queryParameters['text'],
        contains('5 paradas quedan fuera'),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // QUE NO SE CORTE POR ABAJO
  //
  // Jose, 17/09/2026: «me corta parte de abajo, esto hasta del mapa, no solo de
  // la última card, no puedo ver el final». Es un fallo del original, no un
  // patron que copiar, y tiene dos causas que dependen de este widget:
  //
  //  1. **un hijo sin alto propio** dentro de algo que se desplaza se come la
  //     pantalla;
  //  2. **un gesto de arrastre** dentro del mapa le gana el arrastre a la lista,
  //     y entonces arrastrar sobre el mapa deja de desplazar.
  //
  // Las dos se comprueban A TAMANO DE TELEFONO. A 1200×1600 cabe todo y esto no
  // se ve nunca: la prueba pasaria en verde con el fallo dentro.
  // ───────────────────────────────────────────────────────────────────────────
  group('a tamaño de teléfono, el detalle llega hasta el final', () {
    const telefono = Size(390, 844);

    /// Una lista con el mapa dentro y **un ultimo renglon al final**, que es la
    /// forma que tiene el detalle de la ruta. La lista de verdad vive en
    /// `detalle_ruta.dart` y hoy no se puede tocar; cuando quede libre, esta
    /// misma prueba se apunta a la pantalla entera.
    Future<void> comoElDetalle(WidgetTester tester) async {
      tester.view.physicalSize = telefono;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trabajaSinConexionProvider.overrideWithValue(true),
            abrirYCompartirProvider.overrideWithValue(aparato),
            fondoDeCallesProvider.overrideWithValue(const SinCalles()),
            recorridoPorCallesProvider.overrideWithValue(
              const SinCallesQueSeguir(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 48),
                children: [
                  const SizedBox(height: 300, child: Placeholder()),
                  MapaDeLaRuta(ruta: laRutaDeSiempre(cuantas: 6)),
                  const SizedBox(height: 300, child: Placeholder()),
                  const Text('el último renglón del detalle'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('el mapa tiene alto PROPIO y con techo', (tester) async {
      await comoElDetalle(tester);

      final alto = tester.getSize(find.byKey(CroquisDeRuta.clave)).height;
      expect(alto, altoDelMapa(390 - 24));
      // Y sobre todo: no se come la pantalla. Un hijo sin alto propio dentro de
      // una lista es exactamente como se corta esto.
      expect(alto, lessThan(telefono.height / 2));
    });

    testWidgets('el techo aguanta una pantalla ancha', (tester) async {
      // A 1400 px de ancho, sin techo el mapa mediria 875 px de alto el solo y
      // empujaria las acciones y las paradas por debajo del borde.
      expect(altoDelMapa(1400), 320);
      expect(altoDelMapa(200), 190);
    });

    testWidgets('arrastrar SOBRE EL MAPA mueve el MAPA, no la lista', (
      tester,
    ) async {
      // ESTA PRUEBA DECIA LO CONTRARIO HASTA EL 21/09/2026, y el cambio es una
      // decision de Jose tomada con el precio delante.
      //
      // Hasta hoy el mapa dejaba pasar el arrastre de un dedo para que la lista
      // del detalle se siguiera desplazando: era el arreglo del 17/09, cuando el
      // mapa se quedaba el gesto y el chofer no podia llegar a los botones del
      // final. Pero entonces el mapa no se podia mover en el telefono, y Jose lo
      // dijo asi: «estoy pasando por el mapa y no me puedo mover por el mapa por
      // q razon».
      //
      // Se le ofrecieron las dos: dejarlo con dos dedos y el boton de pantalla
      // completa, o que un dedo moviera el mapa ahi mismo sabiendo que entonces
      // la pantalla se baja arrastrando FUERA del mapa. Eligio la segunda: «que
      // un dedo mueva el mapa ahi mismo».
      //
      // Lo que vigila esto: que el mapa se entere del arrastre. Que la lista
      // sigue siendo alcanzable lo vigila la prueba de al lado.
      await comoElDetalle(tester);

      CustomPainter delCroquis() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .firstWhere((p) => p.runtimeType.toString().contains('Croquis'));

      final antes = delCroquis();
      await tester.drag(
        find.byKey(CroquisDeRuta.clave),
        const Offset(-60, -40),
      );
      await tester.pump();

      expect(
        delCroquis().shouldRepaint(antes),
        isTrue,
        reason:
            'EL MAPA NO SE MUEVE CON EL DEDO: arrastrar encima del mapa tiene '
            'que moverlo. Es lo que pidió Jose el 21/09/2026 a cambio de tener '
            'que desplazar la pantalla por fuera del mapa.',
      );
    });

    testWidgets('y la pantalla se sigue pudiendo bajar POR FUERA del mapa', (
      tester,
    ) async {
      // La contrapartida del cambio de arriba, y va en pareja a proposito: el
      // mapa se queda el arrastre que empieza ENCIMA de el, pero el detalle
      // entero no puede quedarse sin poder bajarse — eso es el fallo del
      // 17/09/2026 otra vez, y esta vez sin excusa.
      await comoElDetalle(tester);

      final antes = tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy;
      // Un punto que NO es el mapa: justo encima, donde estan los datos de la
      // ruta.
      await tester.dragFrom(
        Offset(telefono.width / 2, antes - 20),
        const Offset(0, -200),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy,
        lessThan(antes),
        reason:
            'LA PANTALLA NO SE PUEDE BAJAR: si el mapa se queda el arrastre Y '
            'por fuera tampoco se desplaza, el chofer no llega a los botones del '
            'final. Es el 17/09/2026 otra vez.',
      );
    });

    testWidgets('DOS DEDOS acercan el mapa en el teléfono', (tester) async {
      // Jose, 21/09/2026, con la APK instalada: «en el apk los gestos de alejar
      // y acercar en el mapa no estan funcionando tampoco». Y era verdad: el
      // pellizco solo se atendia como `PointerScaleEvent`, que es lo que manda
      // un trackpad. Dos dedos de un telefono no los miraba nadie.
      //
      // Se mira el PINTOR, como en las demas: que el mapa cambie de verdad, no
      // que el gesto llegue.
      await comoElDetalle(tester);

      CustomPainter delCroquis() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .firstWhere((p) => p.runtimeType.toString().contains('Croquis'));

      final antes = delCroquis();
      final centro = tester.getRect(find.byKey(CroquisDeRuta.clave)).center;

      final izquierdo = await tester.startGesture(centro - const Offset(20, 0));
      final derecho = await tester.startGesture(centro + const Offset(20, 0));
      await tester.pump();
      // Se separan: de 40 px de distancia a 160. Eso es acercar cuatro veces.
      await izquierdo.moveTo(centro - const Offset(80, 0));
      await derecho.moveTo(centro + const Offset(80, 0));
      await tester.pump();
      await izquierdo.up();
      await derecho.up();
      await tester.pump();

      expect(
        delCroquis().shouldRepaint(antes),
        isTrue,
        reason:
            'EL PELLIZCO NO HACE NADA EN EL MOVIL: dos dedos separandose tienen '
            'que acercar el mapa. Si esto falla, el chofer tiene un mapa sellado '
            'como el del 21/09/2026.',
      );
    });

    testWidgets('un dedo LENTO sobre el mapa tambien mueve el mapa', (
      tester,
    ) async {
      // La trampa que casi se cuela el 21/09/2026: con un `PanGestureRecognizer`
      // tal cual, un tiron RAPIDO movia el mapa y uno LENTO desplazaba la lista,
      // porque el umbral de panoramica es el doble que el de arrastre y la lista
      // aceptaba primero. El mismo gesto hacia dos cosas distintas segun la
      // prisa, y eso en la mano de un chofer es «esto va cuando quiere».
      //
      // Por eso esta prueba mueve el dedo A TROZOS, que es como se mueve un dedo
      // de verdad, en vez de dar un salto de 200 px como `tester.drag`.
      await comoElDetalle(tester);

      CustomPainter delCroquis() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CustomPainter>()
          .firstWhere((p) => p.runtimeType.toString().contains('Croquis'));

      final antes = delCroquis();
      final dedo = await tester.startGesture(
        tester.getRect(find.byKey(CroquisDeRuta.clave)).center,
      );
      for (var i = 0; i < 10; i++) {
        await dedo.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      await dedo.up();
      await tester.pump();

      expect(
        delCroquis().shouldRepaint(antes),
        isTrue,
        reason:
            'UN TIRON LENTO SOBRE EL MAPA NO LO MUEVE: se lo esta quedando la '
            'lista porque su umbral es la mitad. El arrastre del mapa tiene que '
            'aceptar con el mismo umbral que ella.',
      );
    });

    testWidgets('la lista NO se mueve ni un pixel mientras el mapa se mueve', (
      tester,
    ) async {
      // La segunda queja de Jose el 21/09/2026, y es la que importa: «sigo
      // haciendo scroll cuando toco el mapa, cuando toco el mapa no puedo hacer
      // scroll». Las dos frases dicen lo mismo: el gesto hacia LAS DOS COSAS a
      // medias —los primeros pixeles se los llevaba la lista, el resto el mapa—
      // y asi no se sabe nunca que va a pasar.
      //
      // La regla es de una linea y esta prueba es la que la sujeta: **el dedo
      // encima del mapa mueve el mapa y NO mueve la pantalla**.
      await comoElDetalle(tester);

      final antes = tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy;
      final dedo = await tester.startGesture(
        tester.getRect(find.byKey(CroquisDeRuta.clave)).center,
      );
      for (var i = 0; i < 10; i++) {
        await dedo.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      await dedo.up();
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy,
        antes,
        reason:
            'LA PANTALLA SE MOVIO CON EL DEDO ENCIMA DEL MAPA: el gesto se esta '
            'repartiendo entre los dos, que es justo lo que Jose no entendia. O '
            'lo coge el mapa entero, o no lo coge.',
      );
    });

    testWidgets('un TOQUE sobre el mapa sigue siendo un toque', (tester) async {
      // El precio de reclamar el arrastre a los 3 px seria quedarse tambien con
      // el toque, y entonces no se podria abrir el globo de una parada. Un dedo
      // quieto no llega a 3 px; uno que arrastra los pasa en el primer
      // fotograma.
      await comoElDetalle(tester);

      final centro = tester.getRect(find.byKey(CroquisDeRuta.clave)).center;
      final antes = tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy;
      await tester.tapAt(centro);
      await tester.pump();

      // Ni se movio la pantalla ni reventó nada: el toque llegó al mapa.
      expect(tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy, antes);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el mapa se puede abrir a PANTALLA COMPLETA', (tester) async {
      // Donde un dedo si mueve el mapa, porque no hay lista debajo a la que
      // quitarle nada. Jose: «ni me puedo mover en el mapa desde la apk».
      await comoElDetalle(tester);

      await tester.tap(find.byTooltip('Ver el mapa a pantalla completa'));
      await tester.pumpAndSettle();

      expect(find.byType(MapaEnGrande), findsOneWidget);
      expect(find.byTooltip('Cerrar el mapa'), findsOneWidget);
    });

    testWidgets(
      'se llega al último renglón desplazando, no está solo en el árbol',
      (tester) async {
        await comoElDetalle(tester);

        final ultimo = find.text('el último renglón del detalle');
        // Un widget fuera de pantalla TAMBIEN existe en el arbol: comprobar que
        // esta seria comprobar nada. Lo que hay que comprobar es que se llega.
        //
        // Y SE ARRASTRA POR EL BORDE, no por el centro, desde el 21/09/2026:
        // `scrollUntilVisible` tira del centro del `Scrollable`, que a ratos cae
        // justo encima del mapa — y desde hoy el mapa se queda ese arrastre por
        // decision de Jose. Una persona hace exactamente esto: si el mapa no
        // baja la pantalla, pone el dedo al lado. Lo que esta prueba sigue
        // vigilando es lo de siempre: **que al final del detalle se llega**.
        for (var i = 0; i < 20 && ultimo.evaluate().isEmpty; i++) {
          await tester.dragFrom(
            Offset(telefono.width - 8, telefono.height - 120),
            const Offset(0, -200),
          );
          await tester.pump();
        }
        await tester.pump();

        expect(ultimo, findsOneWidget);
        final caja = tester.getRect(ultimo);
        expect(caja.bottom, lessThanOrEqualTo(telefono.height));
        expect(caja.top, greaterThanOrEqualTo(0));
      },
    );

    testWidgets('y también se llega a los cuatro botones', (tester) async {
      await comoElDetalle(tester);

      await tester.scrollUntilVisible(
        find.byKey(claveDeCopiar),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.pump();

      final caja = tester.getRect(find.byKey(claveDeCopiar));
      expect(caja.bottom, lessThanOrEqualTo(telefono.height));
      // Y se puede pulsar de verdad, que es lo que no se podia en el original.
      await tester.tap(find.byKey(claveDeCopiar));
      await tester.pump();
      expect(aparato.copiados, hasLength(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Y QUE ESTE DE VERDAD EN EL DETALLE
  //
  // Todo lo de arriba prueba el bloque suelto. Esto prueba lo otro, que es lo
  // que Jose ve: que al abrir una ruta **sale el mapa**, y que desde ahi se
  // llega hasta el final de la pantalla en un telefono.
  //
  // Sin esta, quitar `MapaDeLaRuta` de la lista de `detalle_ruta.dart` dejaria
  // las 83 pruebas de arriba en verde y la pantalla sin mapa — que es
  // exactamente el fallo del que salio este encargo.
  // ───────────────────────────────────────────────────────────────────────────
  group('el mapa está dentro del detalle de la ruta', () {
    late BaseLocal base;
    final ahora = DateTime(2026, 9, 14, 16, 5);
    const telefono = Size(390, 844);

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> abrirElDetalle(WidgetTester tester) async {
      // SE SIEMBRA AQUI DENTRO, no en el `setUp`: el `setUp` corre fuera del
      // reloj falso del `tester` y lo que Drift deja empezado alli no avanza
      // dentro — la prueba se cuelga en vez de fallar (`CLAUDE.md` §5).
      await sembrarCatalogo(base);
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: 'R1',
              routeCode: const Value('RT-001'),
              branchId: const Value('B1'),
              originLat: const Value(21.38),
              originLng: const Value(-77.91),
            ),
          );
      for (var i = 1; i <= 4; i++) {
        await sembrarPedido(
          base,
          id: 'o$i',
          cliente: 'Cliente $i',
          ultimaRutaId: 'R1',
          orden: i,
          endLat: 21.3 + i / 100,
          endLng: -77.9 - i / 100,
        );
        await sembrarRenglon(
          base,
          id: 'r$i',
          pedidoId: 'o$i',
          producto: 'Arroz',
          unidades: 10,
          empaques: 2,
        );
      }

      tester.view.physicalSize = telefono;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
            fondoDeCallesProvider.overrideWithValue(const SinCalles()),
            recorridoPorCallesProvider.overrideWithValue(
              const SinCallesQueSeguir(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            home: const Scaffold(body: DetalleDeRuta(rutaId: 'R1')),
          ),
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('al abrir una ruta SALE el mapa', (tester) async {
      await abrirElDetalle(tester);

      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
      expect(find.byKey(claveDeAbrirEnGoogleMaps), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('en un teléfono se llega hasta la última tarjeta', (
      tester,
    ) async {
      await abrirElDetalle(tester);

      // `Carga total` es lo ultimo del detalle. Que exista en el arbol no
      // demuestra nada —un widget fuera de pantalla tambien existe—: hay que
      // **llegar** y que quepa dentro de la ventana.
      final ultima = find.text('Carga total');
      // SE ARRASTRA POR EL BORDE, no por el centro, desde el 21/09/2026.
      //
      // `scrollUntilVisible` tira del CENTRO del `Scrollable`, y en un teléfono
      // ese centro cae encima del mapa — que desde esa fecha se queda el
      // arrastre de un dedo por decisión de Jose («que un dedo mueva el mapa
      // ahí mismo»). El resultado era `Bad state: No element`: la lista no se
      // movía nunca y la última tarjeta no llegaba.
      //
      // Una persona hace exactamente esto: si el mapa no baja la pantalla, pone
      // el dedo al lado. Lo que esta prueba vigila sigue siendo lo mismo —**que
      // al final del detalle se llega**—, y de paso ahora vigila que se llega
      // SIN tocar el mapa, que es la única forma que le queda al chofer.
      // SE ARRASTRA HASTA QUE SE VE, NO HASTA QUE EXISTE — 28/09/2026.
      //
      // La condición era `ultima.evaluate().isEmpty`, o sea que paraba en
      // cuanto el widget aparecía en el árbol. Pero un widget puede estar
      // montado y asomando por debajo del borde, y eso es justo lo que esta
      // prueba viene a impedir — lo dice su propio comentario de arriba: «hay
      // que llegar y que quepa dentro de la ventana».
      //
      // Se destapó al alargar la línea de datos de la cabecera —«Sin vehículo»
      // y «2 h 15 min en ruta» ocupan más que dos rayas—: el contenido creció
      // ocho píxeles y la prueba paró un arrastre antes, con la tarjeta medio
      // fuera. El fallo era de la prueba, no del cambio.
      bool seVe() {
        if (ultima.evaluate().isEmpty) return false;
        final donde = tester.getRect(ultima);
        return donde.bottom <= telefono.height && donde.top >= 0;
      }

      for (var i = 0; i < 20 && !seVe(); i++) {
        await tester.dragFrom(
          Offset(telefono.width - 8, telefono.height - 120),
          const Offset(0, -200),
        );
        await tester.pump();
      }
      await tester.pump();

      final caja = tester.getRect(ultima);
      expect(caja.bottom, lessThanOrEqualTo(telefono.height));
      expect(caja.top, greaterThanOrEqualTo(0));

      await desmontar(tester);
    });

    testWidgets('y por debajo queda aire, no la barra del sistema', (
      tester,
    ) async {
      await abrirElDetalle(tester);

      // La lista se busca **como antepasada del mapa** y no por `byType().first`:
      // asi ademas queda dicho que el mapa va DENTRO de lo que se desplaza. Con
      // `first` la prueba cogia cualquier `ListView` del arbol, y con varias
      // pruebas corriendo a la vez no siempre era la misma.
      final lista = tester.widget<ListView>(
        find.ancestor(
          of: find.byKey(CroquisDeRuta.clave),
          matching: find.byType(ListView),
        ),
      );
      expect((lista.padding! as EdgeInsets).bottom, rellenoAlFinalDelDetalle);
      expect(rellenoAlFinalDelDetalle, greaterThanOrEqualTo(48));

      await desmontar(tester);
    });
  });
}
