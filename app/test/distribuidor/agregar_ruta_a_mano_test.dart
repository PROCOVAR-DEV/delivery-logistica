// «AGREGAR RUTA A MANO»: el respaldo si abrir el enlace de WhatsApp falla. Pegar el
// enlace completo, pegar solo el codigo, codigo vacio y el «no» del servidor, con la
// explicacion de que es el codigo. Contra un doble del servidor.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/distribuidor/dispositivo/anadir_ruta.dart';
import 'package:reparto/distribuidor/dispositivo/cliente_de_dispositivo.dart';
import 'package:reparto/distribuidor/dispositivo/pantalla_anadir_ruta.dart';
import 'package:reparto/distribuidor/dispositivo/proveedores_dispositivo.dart';
import 'package:reparto/distribuidor/modo_distribuidor.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';

import '../apoyo/apoyo_sesion.dart';
import '../apoyo/base_de_prueba.dart';
import '../apoyo/servidor_falso.dart';
import '../pantallas/pedidos/sembrar.dart';

void main() {
  late ServidorFalso servidor;
  late AlmacenEnMemoria almacen;
  RespuestaFalsa Function(PeticionVista) contesta = (_) => RespuestaFalsa(500);
  var entradas = 0;
  final ahora = DateTime(2026, 11, 4, 10);

  AnadirRuta servicio() => AnadirRuta(
    cliente: ClienteDeDispositivo(
      Dio(BaseOptions(baseUrl: 'https://ejemplo.test/api'))
        ..httpClientAdapter = servidor,
    ),
    almacen: almacen,
    leerId: () async => null,
    guardarId: (_) async {},
    nombreDelTelefono: () async => 'Galaxy',
    esperarAlArranque: () async {},
    entrar: (_) async => entradas++,
    bajarRutas: () async {},
  );

  setUp(() {
    servidor = ServidorFalso((p) async => contesta(p));
    almacen = AlmacenEnMemoria();
    entradas = 0;
    contesta = (_) => RespuestaFalsa(200, {
      'acceso': tokenDePrueba(sub: 'd', roles: const ['DISTRIBUIDOR']),
      'secreto': 's',
      'rutaId': 'R1',
    });
  });

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [anadirRutaProvider.overrideWith((ref) => servicio())],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(
            body: SingleChildScrollView(child: FormularioDeRuta()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> escribeYAgrega(WidgetTester tester, String texto) async {
    await tester.enterText(
      find.byKey(const ValueKey('anadir-ruta-enlace')),
      texto,
    );
    await tester.tap(find.byKey(const ValueKey('anadir-ruta-anadir')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('explica que es el codigo', (tester) async {
    await pintar(tester);
    expect(
      find.text(
        'Es la parte final del enlace que te mandaron por WhatsApp. Si te mandaron '
        'https://reparto.procovar.cloud/r/AbC123xyz, el código es AbC123xyz. '
        'También puedes pegar el enlace completo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'pegar el enlace COMPLETO (con espacios, salto de linea y parametros)',
    (tester) async {
      await pintar(tester);
      await escribeYAgrega(
        tester,
        '  https://reparto.procovar.cloud/r/AbC123xyz?utm=wa \n',
      );
      expect(servidor.vistas.single.ruta, endsWith('/d/reclamar'));
      expect((servidor.vistas.single.cuerpo! as Map)['token'], 'AbC123xyz');
      expect(entradas, 1);
    },
  );

  testWidgets('pegar SOLO el codigo', (tester) async {
    await pintar(tester);
    await escribeYAgrega(tester, 'AbC123xyz');
    expect((servidor.vistas.single.cuerpo! as Map)['token'], 'AbC123xyz');
    expect(entradas, 1);
  });

  testWidgets('con el codigo VACIO no se llama al servidor y se dice', (
    tester,
  ) async {
    await pintar(tester);
    await escribeYAgrega(tester, '   ');
    expect(servidor.vistas, isEmpty);
    expect(find.text('Escribe o pega el código de la ruta.'), findsOneWidget);
  });

  for (final (marca, codigo, frase) in <(String, int, String)>[
    ('enlace_no_valido', 404, 'Este enlace no es válido'),
    ('enlace_revocado', 410, 'Este enlace ya no vale'),
    (
      'ruta_de_otro_dispositivo',
      403,
      'Esta ruta ya está asignada a otro teléfono.',
    ),
    ('ruta_cerrada', 409, 'Esta ruta ya está cerrada'),
  ]) {
    testWidgets('el «no» del servidor ($marca) se enseña con su motivo', (
      tester,
    ) async {
      contesta = (_) => RespuestaFalsa(codigo, {'error': marca});
      await pintar(tester);
      await escribeYAgrega(tester, 'AbC123xyz');
      expect(find.byKey(const ValueKey('anadir-ruta-error')), findsOneWidget);
      expect(find.textContaining(frase), findsOneWidget);
      expect(entradas, 0);
    });
  }

  testWidgets(
    '«Mis rutas» ofrece «Agregar ruta a mano» en un CAJON, con y sin rutas',
    (tester) async {
      final base = baseDePrueba();
      addTearDown(base.close);
      await sembrarCatalogo(base);
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
            modoDistribuidorProvider.overrideWithValue(true),
            anadirRutaProvider.overrideWith((ref) => servicio()),
          ],
          child: MaterialApp(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            home: const Scaffold(body: PantallaRutas()),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Sin ninguna ruta, ya esta ahi.
      await tester.tap(find.byKey(const ValueKey('mis-rutas-agregar-a-mano')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.byKey(const ValueKey('anadir-ruta-explicacion')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('anadir-ruta-enlace')),
        'AbC123xyz',
      );
      await tester.tap(find.byKey(const ValueKey('anadir-ruta-anadir')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(entradas, 1);
      // Y el cajon se cierra al conseguirlo.
      expect(
        find.byKey(const ValueKey('anadir-ruta-explicacion')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(
        const Duration(seconds: 10),
      ); // el aviso de «Ruta agregada»
    },
  );
}
