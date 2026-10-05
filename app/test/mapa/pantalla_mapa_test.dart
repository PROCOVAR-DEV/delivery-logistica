// LA PANTALLA DEL MAPA SIN CONEXIÓN.
//
// Lo que se comprueba aquí son las cuatro promesas, no que se pinte algo:
//
//  1. **EL TAMAÑO SE DICE ANTES DE BAJAR NADA.**
//  2. **En la web no hay nada de esto** (regla 1).
//  3. **Si falla, sale el motivo literal**, no «no se pudo».
//  4. **La atribución de OpenStreetMap se ve**, también sin conexión.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/carpeta_del_mapa.dart';
import 'package:reparto/mapa/proveedores_de_mapa.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/pantallas/mapa/pantalla_mapa_sin_conexion.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';

/// Un servidor que anuncia lo que se le diga y sirve lo que se le diga.
class _Servidor implements HttpClientAdapter {
  _Servidor({this.anuncio, this.codigoDelFichero = 200});

  final Object? anuncio;
  final int codigoDelFichero;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? cuerpo,
    Future<void>? cancelar,
  ) async {
    if (o.path.endsWith('/mapa')) {
      return ResponseBody.fromString(
        jsonEncode(anuncio ?? {'niveles': null}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (codigoDelFichero != 200) {
      return ResponseBody.fromString('no', codigoDelFichero);
    }
    // Un fichero vacío: lo que importa aquí es que la pantalla lo cuente, no
    // que el mapa se descargue — eso está probado en `descarga_test.dart`.
    return ResponseBody.fromBytes(const [], 200);
  }

  @override
  void close({bool force = false}) {}
}

Widget _montaje(
  _Servidor servidor, {
  required bool enElAparato,
  CarpetaEnMemoria? carpeta,
}) => ProviderScope(
  overrides: [
    // Ésta es la única línea que separa la APK de la web, y es a propósito.
    trabajaSinConexionProvider.overrideWithValue(enElAparato),
    carpetaDelMapaProvider.overrideWith(
      (ref) async => carpeta ?? CarpetaEnMemoria(),
    ),
    dioDelMapaProvider.overrideWith(
      (ref) => Dio()..httpClientAdapter = servidor,
    ),
  ],
  // Con `Scaffold` puesto POR LA PRUEBA: la pantalla no lo lleva, que es lo que
  // manda el contrato de registro (`navegacion/pantalla_registrada.dart`) —
  // devolver otro dejaría dos barras superiores y rompería el selector de
  // sucursal.
  child: const MaterialApp(home: Scaffold(body: PantallaMapaSinConexion())),
);

Map<String, Object?> _anuncioDeDos() => {
  'niveles': [
    {
      'nivel': 'basico',
      'version': '260916',
      'bytes': 2375346,
      'sha256': 'a' * 64,
      'url': 'https://x/cuba-basico.pmtiles',
    },
    {
      'nivel': 'completo',
      'version': '260916',
      'bytes': 25763142,
      'sha256': 'b' * 64,
      'url': 'https://x/cuba-completo.pmtiles',
    },
  ],
};

void main() {
  testWidgets('el tamaño se dice ANTES de bajar nada', (tester) async {
    await tester.pumpWidget(
      _montaje(_Servidor(anuncio: _anuncioDeDos()), enElAparato: true),
    );
    await tester.pumpAndSettle();

    // Los dos números, en el botón. Nadie baja 25,8 MB sin saber que son 25,8
    // MB, y menos con los datos de Cuba.
    expect(find.text('Sólo carreteras — 2,4 MB'), findsOneWidget);
    expect(find.text('Completo, con calles — 25,8 MB'), findsOneWidget);

    // Y no se ha bajado nada solo: se ofrece, decide la persona.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('en la web no hay nada de esto', (tester) async {
    await tester.pumpWidget(
      _montaje(_Servidor(anuncio: _anuncioDeDos()), enElAparato: false),
    );
    await tester.pumpAndSettle();

    expect(find.text(TextosDelMapaGuardado.enLaWeb), findsOneWidget);
    // Ni un botón de descargar: quien abre un navegador tiene servidor detrás,
    // siempre, y guardarse Cuba en el navegador no le ahorra nada a nadie.
    expect(find.byKey(claveDeBajar('basico')), findsNothing);
    expect(find.byKey(claveDeBajar('completo')), findsNothing);
  });

  testWidgets('sin nada colgado se dice, y no se ofrece nada', (tester) async {
    await tester.pumpWidget(_montaje(_Servidor(), enElAparato: true));
    await tester.pumpAndSettle();

    expect(find.text(TextosDelMapaGuardado.nadaColgado), findsOneWidget);
  });

  testWidgets('la atribución de OpenStreetMap se ve', (tester) async {
    await tester.pumpWidget(
      _montaje(_Servidor(anuncio: _anuncioDeDos()), enElAparato: true),
    );
    await tester.pumpAndSettle();

    final letrero = tester.widget<Text>(find.byKey(claveDeAtribucionDelMapa));
    expect(letrero.data, contains('OpenStreetMap'));
    expect(
      letrero.data,
      contains('ODbL'),
      reason: 'la licencia la exige donde se enseñe el mapa',
    );
  });

  testWidgets('lo primero que se lee es que el mapa NO hace falta', (
    tester,
  ) async {
    // Jose creía que sin mapa no se pueden crear rutas, y en esta aplicación no
    // es verdad. La pantalla lo dice con esas palabras.
    await tester.pumpWidget(_montaje(_Servidor(), enElAparato: true));
    await tester.pumpAndSettle();

    expect(find.text(TextosDelMapaGuardado.noHaceFalta), findsOneWidget);
  });

  testWidgets('si la descarga falla sale el MOTIVO, no «no se pudo»', (
    tester,
  ) async {
    await tester.pumpWidget(
      _montaje(
        _Servidor(anuncio: _anuncioDeDos(), codigoDelFichero: 503),
        enElAparato: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(claveDeBajar('basico')));
    await tester.pumpAndSettle();

    final aviso = find.byKey(claveDeAvisoDeDescarga);
    expect(aviso, findsOneWidget);
    final texto = tester.widget<Text>(
      find.descendant(of: aviso, matching: find.byType(Text)),
    );
    expect(
      texto.data,
      contains('503'),
      reason:
          'el código es lo que permite distinguir un servidor caído de una '
          'descarga cortada, y decide a quién hay que avisar',
    );
  });

  testWidgets('un nivel que la aplicación no entiende se AVISA', (
    tester,
  ) async {
    await tester.pumpWidget(
      _montaje(
        _Servidor(
          anuncio: {
            'niveles': [
              {
                'nivel': 'basico',
                'version': '260916',
                'bytes': 2375346,
                'sha256': 'a' * 64,
                'url': 'https://x/b.pmtiles',
              },
              // Sin sha256: no se puede bajar con seguridad.
              {
                'nivel': 'completo',
                'version': '260916',
                'bytes': 25763142,
                'url': 'https://x/c.pmtiles',
              },
            ],
          },
        ),
        enElAparato: true,
      ),
    );
    await tester.pumpAndSettle();

    // NADA SE DESCARTA EN SILENCIO: el que no se entiende no desaparece sin más.
    expect(find.text(TextosDelMapaGuardado.ilegibles(1)), findsOneWidget);
  });

  testWidgets('con DOS niveles ofrecidos la Guía señala el primer botón', (
    tester,
  ) async {
    // El paso 2 de «Descargar el mapa de Cuba» apunta a «Completo, con calles —
    // 49,2 MB», y aquí hay UN botón por nivel ofrecido. Marcar los dos no rompe
    // la pantalla: deja `donde` en `null` y el paso sale **sin foco** con el
    // resto de este fichero en verde. Con un solo nivel ofrecido la prueba
    // pasaría igual teniendo la marca en todos, así que se piden dos.
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);

    await tester.pumpWidget(
      _montaje(_Servidor(anuncio: _anuncioDeDos()), enElAparato: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(claveDeBajar('basico')), findsOneWidget);
    expect(find.byKey(claveDeBajar('completo')), findsOneWidget);

    final puesto = RegistroDeControles.donde(Senalado.mapaBajar);
    expect(
      puesto,
      isNotNull,
      reason:
          'con dos niveles ofrecidos no hay a cuál señalar: la marca está en los '
          'dos botones y dos a la vez no se distinguen.',
    );
    expect(
      puesto!.rect,
      tester.getRect(find.byKey(claveDeBajar('basico'))),
      reason:
          'el foco no está en el PRIMER botón de la lista, que es el que se '
          'marcó y el que nombra el paso',
    );
  });

  testWidgets('con el detallado puesto NO se ofrecen los más pequeños', (
    tester,
  ) async {
    // Jose, 21/09/2026: «ya descargué el detallado, ¿por qué me pide descargar
    // los otros? No me debería dejar si ya con eso tengo todo».
    //
    // Los niveles son uno dentro de otro: el detallado trae lo del completo y
    // el completo lo del básico. Ofrecerlos después de tener el grande es
    // ofrecer QUITAR cosas con la cara de una mejora, y cobrar los megas otra
    // vez.
    final carpeta = CarpetaEnMemoria()
      ..sembrar('cuba-detallado.pmtiles', List<int>.filled(30, 7))
      ..sembrar(
        'cuba-detallado.json',
        utf8.encode(
          jsonEncode({
            'nivel': 'detallado',
            'version': '260916',
            'bytes': 30,
            'sha256': 'a' * 64,
            'guardadoAt': '2026-09-21T10:00:00.000Z',
          }),
        ),
      );

    await tester.pumpWidget(
      _montaje(
        _Servidor(anuncio: _anuncioMenudo()),
        enElAparato: true,
        carpeta: carpeta,
      ),
    );
    await tester.pumpAndSettle();

    // No hay botón para ninguno de los dos pequeños.
    expect(
      find.byKey(claveDeBajar('basico')),
      findsNothing,
      reason:
          'SE OFRECE UN NIVEL MÁS PEQUEÑO QUE EL QUE YA HAY. El detallado lo '
          'contiene: bajar el básico encima sería quitar detalle pagando los '
          'megas.',
    );
    expect(find.byKey(claveDeBajar('completo')), findsNothing);
  });

  // LA SALIDA CUANDO EL MAPA ESTÁ AL DÍA — 22/09/2026.
  //
  // Con el detallado bajado y nada nuevo colgado, la pantalla se quedaba **sin
  // un solo botón**: sólo «Está al día». Bien mientras todo vaya bien, y sin
  // salida el día que no —un fichero corrupto, un disco que se llenó a mitad,
  // un mapa que se dibuja a trozos—. La única forma de rehacerlo era
  // desinstalar, y desinstalar se lleva la base local: el trabajo del día que
  // no haya subido.
  testWidgets('con el mapa al día se puede volver a bajar el que se tiene', (
    tester,
  ) async {
    final carpeta = CarpetaEnMemoria()
      ..sembrar('cuba-detallado.pmtiles', List<int>.filled(30, 7))
      ..sembrar(
        'cuba-detallado.json',
        utf8.encode(
          jsonEncode({
            'nivel': 'detallado',
            'version': '260916',
            'bytes': 30,
            'sha256': 'a' * 64,
            'guardadoAt': '2026-09-21T10:00:00.000Z',
          }),
        ),
      );

    await tester.pumpWidget(
      _montaje(
        _Servidor(anuncio: _anuncioMenudo()),
        enElAparato: true,
        carpeta: carpeta,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Está al día.'), findsOneWidget);
    expect(
      find.byKey(claveDeVolverABajar),
      findsOneWidget,
      reason:
          'SIN SALIDA. Con el mapa al día no queda un solo botón: un fichero '
          'corrupto sólo se arregla desinstalando, y desinstalar se lleva el '
          'trabajo del día que no haya subido.',
    );
    // Y se dice que no hace falta si lo que hay está bien: es una salida, no
    // una mejora que ofrecer, y gasta los mismos megas.
    expect(
      find.textContaining('Si lo que hay está bien, no hace falta'),
      findsOneWidget,
    );
  });

  testWidgets('sin mapa guardado NO se ofrece volver a bajar', (tester) async {
    // La pareja: la salida sólo aparece donde hacía falta. Con la pantalla
    // llena de botones de descargar, uno más es ruido.
    await tester.pumpWidget(
      _montaje(_Servidor(anuncio: _anuncioDeDos()), enElAparato: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(claveDeVolverABajar), findsNothing);
  });
}

// ────────────────────────────────────────────────────────────────────────────

/// Tres niveles con tamaños DE JUGUETE pero en el mismo orden que los de
/// verdad. Pequeños a propósito: `paqueteGuardadoProvider` comprueba que el
/// fichero pese lo que dice su apunte —y hace bien: un apunte que promete un
/// mapa encima de una carpeta vacía es peor que no tener nada— así que la
/// prueba tiene que poder sembrar un fichero de ese tamaño.
Map<String, Object?> _anuncioMenudo() => {
  'niveles': [
    for (final (nivel, bytes) in const [
      ('basico', 10),
      ('completo', 20),
      ('detallado', 30),
    ])
      {
        'nivel': nivel,
        'version': '260916',
        'bytes': bytes,
        'sha256': 'a' * 64,
        'url': 'https://x/cuba-\$nivel.pmtiles',
      },
  ],
};
