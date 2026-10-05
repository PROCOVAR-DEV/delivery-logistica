// LA ACTUALIZACIÓN SE BAJA DENTRO, Y SE VE QUE SE BAJA DENTRO.
//
// Jose, 05/10/2026: «el mapa sí me funciona dentro de la aplicación, pero la APK
// me manda a descargarla al navegador en vez de actualizar ahí mismo en la
// aplicación sin necesidad de salir».
//
// Las pruebas van **en pareja**, que es la regla de §3-quinquies del `CLAUDE.md`:
//
//  * con tamaño y huella anunciados, el cajón baja aquí dentro y **no abre el
//    navegador**;
//  * sin ellos —una api anterior al 22/09/2026— **sigue abriendo el navegador**,
//    porque sin `bytes` no hay barra honesta y sin `sha256` no hay forma de saber
//    si llegó entero. Quitar la única forma que funciona hoy sería cambiar un
//    problema por otro.
//
// Y la tercera, que es la que se olvida: **la franja cuenta la descarga cuando el
// cajón ya está cerrado**. El cajón se cierra, la descarga no.

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/aviso_de_version_nueva.dart';
import 'package:reparto/nucleo/actualizacion/bajada_de_la_actualizacion.dart';
import 'package:reparto/nucleo/actualizacion/comprobador.dart';
import 'package:reparto/nucleo/actualizacion/instalador.dart';
import 'package:reparto/nucleo/actualizacion/version_publicada.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/descarga/almacen_de_bajadas.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../apoyo/base_de_prueba.dart';

final elApk = Uint8List.fromList(List.generate(40000, (i) => (i * 13 + 5) % 251));
final suHuella = sha256.convert(elApk).toString();

const laUrl = 'https://archivos.procovar.cloud/reparto/apk/reparto-1.5.0.apk';

/// UN SERVIDOR QUE GOTEA: la prueba decide cuándo llega cada trozo, así que se
/// puede mirar la pantalla **con la descarga a medias**, que es justo el estado
/// que había que enseñar bien.
class ServidorQueGotea implements HttpClientAdapter {
  final StreamController<Uint8List> grifo = StreamController<Uint8List>();
  var peticiones = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? cuerpo,
    Future<void>? cancelar,
  ) async {
    peticiones++;
    // Sin `content-length`, como el de verdad.
    return ResponseBody(grifo.stream, 200);
  }

  @override
  void close({bool force = false}) {}
}

class InstaladorQuieto implements Instalador {
  InstaladorQuieto({this.hayPermiso = true});

  /// `false` es el estado del primer dia en TODOS los telefonos: el ajuste de
  /// «instalar aplicaciones desconocidas» no esta dado hasta que alguien lo da.
  final bool hayPermiso;

  var rutas = <String>[];
  var vecesQueSeAbrioElAjuste = 0;

  @override
  Future<bool> sePuedeInstalarDesdeAqui() async => hayPermiso;

  @override
  Future<ComoFueInstalar> instalar(String ruta) async {
    rutas.add(ruta);
    if (!hayPermiso) return const FaltaElPermisoDeInstalar();
    return const ElInstaladorEstaDelante();
  }

  @override
  Future<void> abrirElAjusteDelPermiso() async => vecesQueSeAbrioElAjuste++;
}

void main() {
  const conTamanoYHuella = VersionPublicada(
    version: '1.5.0',
    compilacion: 12,
    descargas: {'android': laUrl},
    // Lo que el aparato necesita para bajarla él: cuánto pesa y con qué cuadra.
    ficheros: {'android': FicheroPublicado(bytes: 40000, sha256: '')},
  );

  /// Monta la franja del aviso con una versión nueva ya detectada, que es el
  /// estado en el que se encuentra el logístico al abrir la aplicación.
  Future<
    ({
      int Function() navegador,
      ServidorQueGotea servidor,
      AlmacenEnMemoria almacen,
      InstaladorQuieto instalador,
      BaseLocal base,
    })
  >
  montar(
    WidgetTester tester, {
    required VersionPublicada publicada,
    bool hayPermiso = true,
  }) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var veces = 0;
    final servidor = ServidorQueGotea();
    addTearDown(() {
      if (!servidor.grifo.isClosed) servidor.grifo.close();
    });
    final almacen = AlmacenEnMemoria();
    final instalador = InstaladorQuieto(hayPermiso: hayPermiso);
    // La base se monta VACIA y se siembra DESPUES, dentro del cuerpo de la prueba
    // (`CLAUDE.md` §3-ter y §5): sembrar antes es justo el caso que una respuesta
    // de una sola vez resuelve bien, y entonces la prueba no comprueba nada.
    final base = baseDePrueba();
    addTearDown(base.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          actualizacionProvider.overrideWith(
            (ref) async =>
                SePuedeActualizar(publicada: publicada, enlace: laUrl),
          ),
          carpetaDeLaActualizacionProvider.overrideWith((ref) async => almacen),
          dioDeLaActualizacionProvider.overrideWithValue(
            Dio()..httpClientAdapter = servidor,
          ),
          instaladorProvider.overrideWithValue(instalador),
          abridorDeLaDescargaProvider.overrideWithValue((_) async {
            veces++;
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: AvisoDeVersionNueva())),
      ),
    );
    await tester.pumpAndSettle();
    return (
      navegador: () => veces,
      servidor: servidor,
      almacen: almacen,
      instalador: instalador,
      base: base,
    );
  }

  /// DESMONTAR NO ES CEREMONIA, y el molde sale de
  /// `aviso_de_version_nueva_test.dart`: la franja mira la cola, o sea un stream
  /// de Drift, y Drift suelta un temporizador al cancelar sus consultas.
  /// `flutter_test` comprueba que no quede ninguno **antes** de los `tearDown`, y
  /// lo que se ve si no es «A Timer is still pending» sobre una prueba que por
  /// dentro pasó entera.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> abrirElCajon(WidgetTester tester) async {
    expect(
      find.text('Cómo instalarla'),
      findsOneWidget,
      reason: 'la franja de «hay una versión nueva» no salió',
    );
    await tester.tap(find.text('Cómo instalarla'));
    await tester.pumpAndSettle();
  }

  testWidgets('se baja AQUÍ DENTRO, con barra de verdad y sin navegador', (
    tester,
  ) async {
    // La huella de verdad del APK de mentira: así la descarga termina bien.
    final publicada = VersionPublicada(
      version: conTamanoYHuella.version,
      compilacion: conTamanoYHuella.compilacion,
      descargas: conTamanoYHuella.descargas,
      ficheros: {
        'android': FicheroPublicado(bytes: elApk.length, sha256: suHuella),
      },
    );
    final m = await montar(tester, publicada: publicada);
    await abrirElCajon(tester);

    // ANTES DE PULSAR SE DICE CUÁNTO PESA Y QUÉ VA A PASAR.
    expect(find.textContaining('40 kB'), findsOneWidget);
    expect(
      find.textContaining('aquí dentro'),
      findsOneWidget,
      reason: 'el cajón tiene que decir que no hay que salir a ningún sitio',
    );
    expect(
      find.textContaining('¿instalar?'),
      findsOneWidget,
      reason:
          'la pantalla del sistema no se puede saltar, así que se avisa antes: '
          'sin avisar se lee como un error y se cancela',
    );

    await tester.tap(find.text('Descargar e instalar'));
    await tester.pump();
    await tester.pump();

    // ── A MEDIAS: la barra sabe cuánto falta y lo dice.
    m.servidor.grifo.add(Uint8List.sublistView(elApk, 0, 10000));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.byKey(claveDeLaBarraDeLaBajada), findsOneWidget);
    final barra = tester.widget<LinearProgressIndicator>(
      find.byKey(claveDeLaBarraDeLaBajada),
    );
    expect(
      barra.value,
      closeTo(0.25, 0.01),
      reason:
          'la barra salió con value=${barra.value}. Un `null` es la rueda que da '
          'vueltas, o sea fingir que no se sabe cuánto falta teniendo el dato: '
          'el tamaño lo anuncia la api',
    );
    // El renglón del cajón, por su clave: el mismo número sale también en la
    // franja de detrás —es la misma descarga contada en dos sitios— y buscarlo por
    // el texto encontraría los dos.
    expect(
      tester.widget<Text>(find.byKey(claveDeLoQueVaBajado)).data,
      'Bajando 10 kB de 40 kB (25 %)',
    );

    // ── Y AL TERMINAR, se instala desde aquí.
    m.servidor.grifo.add(Uint8List.sublistView(elApk, 10000));
    await m.servidor.grifo.close();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // «Instalar» sale en el cajón y en la franja, que es lo correcto: las dos
    // hablan de lo mismo y desde las dos se llega.
    expect(find.text('Instalar'), findsWidgets);
    expect(await m.almacen.bytes('reparto.apk'), elApk.length);
    expect(
      m.navegador(),
      0,
      reason:
          'se abrió el navegador en el camino feliz: eso es justo lo que Jose '
          'pidió que dejara de pasar',
    );

    await tester.tap(find.text('Instalar').last);
    await tester.pumpAndSettle();
    expect(m.instalador.rutas, ['/memoria/reparto.apk']);
    await desmontar(tester);
  });

  testWidgets(
    'sin tamaño ni huella anunciados, SIGUE abriendo el navegador',
    (tester) async {
      // Una api anterior al 22/09/2026: anuncia la URL y nada más.
      const vieja = VersionPublicada(
        version: '1.5.0',
        compilacion: 12,
        descargas: {'android': laUrl},
      );
      final m = await montar(tester, publicada: vieja);
      await abrirElCajon(tester);

      expect(
        find.text('Descargar e instalar'),
        findsNothing,
        reason:
            'sin `bytes` no hay barra honesta y sin `sha256` no hay forma de '
            'saber si llegó entero: bajarlo dentro sería una barra que miente y '
            'un APK que nadie comprueba',
      );
      expect(find.text('Descargar'), findsOneWidget);
      expect(find.textContaining('navegador'), findsOneWidget);

      await tester.tap(find.text('Descargar'));
      await tester.pumpAndSettle();

      expect(m.navegador(), 1);
      expect(m.servidor.peticiones, 0);
      await desmontar(tester);
    },
  );

  testWidgets(
    'SIN PERMISO: se ofrece el ajuste Y el navegador, y nada se pierde',
    (tester) async {
      final publicada = VersionPublicada(
        version: '1.5.0',
        compilacion: 12,
        descargas: const {'android': laUrl},
        ficheros: {
          'android': FicheroPublicado(bytes: elApk.length, sha256: suHuella),
        },
      );
      final m = await montar(tester, publicada: publicada, hayPermiso: false);
      await abrirElCajon(tester);
      await tester.tap(find.text('Descargar e instalar'));
      // VARIAS PASADAS ANTES DE SERVIR UN BYTE, y no es ceremonia: hasta que la
      // descarga no está escuchando el grifo, nadie se lleva lo que se eche. Con
      // un solo `pump` y un `await close()` detrás, la prueba **se cuelga en vez
      // de fallar** —se esperaba a un lector que sólo aparece pumpeando— que es lo
      // peor que puede hacer una prueba (`CLAUDE.md` §5). Pasó escribiéndola.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      m.servidor.grifo.add(elApk);
      unawaited(m.servidor.grifo.close());
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Lo bajado NO se pierde por no tener el permiso: son 75 MB.
      expect(await m.almacen.bytes('reparto.apk'), elApk.length);
      // Y se dice qué pasa, con las tres salidas delante.
      expect(find.byKey(claveDelMotivoDeLaBajada), findsOneWidget);
      expect(find.text('Dar el permiso'), findsWidgets);
      expect(find.text('Ya lo di: instalar'), findsOneWidget);
      expect(
        find.text('Abrir en el navegador'),
        findsOneWidget,
        reason:
            'sin el permiso no se puede instalar desde aquí, y si además se '
            'quita el navegador no queda NINGUNA forma de actualizar: eso es '
            'cambiar un problema por otro',
      );

      await tester.tap(find.text('Abrir en el navegador'));
      await tester.pumpAndSettle();
      expect(m.navegador(), 1);
      await desmontar(tester);
    },
  );

  testWidgets('UN TOQUE, UNA DESCARGA: el doble toque no pide dos veces', (
    tester,
  ) async {
    final publicada = VersionPublicada(
      version: '1.5.0',
      compilacion: 12,
      descargas: const {'android': laUrl},
      ficheros: {
        'android': FicheroPublicado(bytes: elApk.length, sha256: suHuella),
      },
    );
    final m = await montar(tester, publicada: publicada);
    await abrirElCajon(tester);

    // SE LLAMA DOS VECES A LA MISMA FUNCIÓN YA CONSTRUIDA, que es literalmente lo
    // que hace un doble toque: los dos toques caen en el mismo fotograma y el
    // botón que reciben los dos es el MISMO objeto con el MISMO `onPressed`.
    //
    // No vale hacerlo con dos `tester.tap`: entre el primero y el segundo el
    // widget ya se reconstruyó con la barra puesta, así que la prueba saldría
    // verde aunque la guarda no existiera. Es la trampa del 25/09/2026.
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Descargar e instalar'),
    );
    boton.onPressed!();
    boton.onPressed!();
    // Varias pasadas cortas: entre el toque y la petición hay la carpeta, el
    // apunte de la versión y el cliente, o sea varios `await`.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      m.servidor.peticiones,
      1,
      reason:
          'se pidieron ${m.servidor.peticiones} descargas con dos toques. Son 75 '
          'MB cada una: con la conexión de allá eso es media tarde (25/09/2026)',
    );
    await desmontar(tester);
  });

  testWidgets(
    'CON TRABAJO SIN SUBIR el botón de instalar se apaga, y dice por qué',
    (tester) async {
      // `docs/actualizaciones.md` §1.1: instalar encima con cola pendiente puede
      // llevarse la base local, o sea el trabajo del día de una persona. Y el
      // caso que esta prueba cubre es el que se escapaba: **la cola crece DESPUÉS
      // de bajar**, porque se baja por la mañana y se trabaja sin señal todo el
      // día. `actualizacionProvider` se pregunta una vez al arrancar y no se
      // enteraría.
      final publicada = VersionPublicada(
        version: '1.5.0',
        compilacion: 12,
        descargas: const {'android': laUrl},
        ficheros: {
          'android': FicheroPublicado(bytes: elApk.length, sha256: suHuella),
        },
      );
      final m = await montar(tester, publicada: publicada);
      await abrirElCajon(tester);
      await tester.tap(find.text('Descargar e instalar'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      m.servidor.grifo.add(elApk);
      unawaited(m.servidor.grifo.close());
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Con la cola vacía, el botón está vivo. `.last` es el del cajón: el mismo
      // texto sale también en la franja de detrás, que habla de lo mismo.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Instalar').last,
            )
            .onPressed,
        isNotNull,
      );

      // ── Y AHORA SE SIEMBRA, con la pantalla delante y sin volver a montarla.
      await ColaDeSalida(m.base).encolar(
        metodo: 'POST',
        ruta: '/api/routes/r1/close',
        cuerpo: const {'entregados': 3},
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.textContaining('Te quedan 1 cosas por subir'),
        findsOneWidget,
        reason:
            'el cajón no dice que queda trabajo sin subir: un botón apagado sin '
            'motivo enseña a no fiarse del botón',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Instalar').last,
            )
            .onPressed,
        isNull,
        reason:
            'se puede instalar con trabajo sin subir. Es §1.1: instalar encima '
            'puede llevarse la base local, y la base local es el día de una '
            'persona',
      );
      // Y lo bajado NO se pierde: se instala en cuanto suba la cola.
      expect(await m.almacen.bytes('reparto.apk'), elApk.length);
      await desmontar(tester);
    },
  );

  testWidgets('con el cajón cerrado, la franja cuenta cómo va la descarga', (
    tester,
  ) async {
    final publicada = VersionPublicada(
      version: '1.5.0',
      compilacion: 12,
      descargas: const {'android': laUrl},
      ficheros: {
        'android': FicheroPublicado(bytes: elApk.length, sha256: suHuella),
      },
    );
    final m = await montar(tester, publicada: publicada);
    await abrirElCajon(tester);
    await tester.tap(find.text('Descargar e instalar'));
    await tester.pump();
    m.servidor.grifo.add(Uint8List.sublistView(elApk, 0, 10000));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // Se cierra el cajón, que es lo que hace cualquiera para seguir trabajando.
    await tester.tap(find.text('Cerrar y seguir bajando'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Bajando la versión 1.5.0'),
      findsOneWidget,
      reason:
          'cerrar el cajón no cancela la descarga, y sin esto no quedaría una '
          'sola forma de saber cómo va ni de volver a ella',
    );
    expect(find.textContaining('10 kB de 40 kB'), findsOneWidget);

    // Y sigue bajando de verdad: no se quedó parada al cerrar.
    m.servidor.grifo.add(Uint8List.sublistView(elApk, 10000));
    await m.servidor.grifo.close();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.textContaining('está descargada'), findsOneWidget);
    expect(await m.almacen.bytes('reparto.apk'), elApk.length);
    await desmontar(tester);
  });
}
