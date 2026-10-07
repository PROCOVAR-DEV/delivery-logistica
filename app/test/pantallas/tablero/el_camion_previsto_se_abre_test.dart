// «CAMIÓN PREVISTO» NO ABRÍA NADA — 28/09/2026, en un SM-A165M de verdad.
//
// Jose, con una zona creada y un vehículo dado de alta en la sucursal
// («Vehículos 0 / 1»): tocar «Camión previsto / Sin elegir» en las opciones de
// la columna **cerraba la hoja de opciones y no abría ningún selector**. Dos
// veces seguidas. Ni rueda, ni lista vacía, ni aviso: nada.
//
// Lo que se lleva por delante no es el gesto, es la ruta: la zona se arma y se
// inicia **sin vehículo** sin que nada lo impida, y después el coste por km de
// esa ruta no se puede calcular. Un hueco que nadie ve hasta que el camión ya
// salió.
//
// La causa NO era el teléfono —se reprodujo igual a 1400 px— ni un cajón
// abriéndose encima de otro: era un `await ref.read(camionesProvider.future)`
// delante del cajón que no terminaba nunca, porque nadie estaba mirando ese
// `StreamProvider`. El porqué largo, en `AccionesTablero._elegirCamion`.
//
// Por eso esta prueba va POR LA PANTALLA ENTERA y con el dedo, en los dos
// tamaños: el camino que falló es el de quien lleva el teléfono, y una prueba
// que llamara a `elegirCamion` a pelo habría salido verde todo el rato —de
// hecho `columnas_test.dart` la tiene, y estuvo verde mientras esto no abría.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// El teléfono de Jose y una ventana de escritorio. El fallo salía en los dos,
/// así que se prueban los dos: arreglarlo sólo para el móvil habría dejado la
/// mitad puesta.
const _telefono = Size(390, 844);
const _escritorio = Size(1400, 900);

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  // Aquí SÓLO se abre la base. Sembrar en el `setUp` de un `testWidgets` es la
  // segunda trampa del §5: lo que Drift deja empezado fuera del reloj falso no
  // avanza dentro, y la prueba **se cuelga en vez de fallar**.
  setUp(() {
    base = BaseLocal.con(NativeDatabase.memory());
    servidor = ServidorFalso((peticion) async => null);
  });

  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  /// Pasadas cortas y CONTADAS, para lo que se mira con el cajón del camión
  /// delante.
  ///
  /// Aquí no vale `pumpAndSettle`: mientras la flota no llega, el cajón pinta
  /// una rueda, y una rueda no se asienta nunca. Con `pumpAndSettle` la prueba
  /// moría con «pumpAndSettle timed out», que dice dónde pero no QUÉ: con esto
  /// se llega a la comprobación de verdad y falla diciendo que el camión no
  /// está en la lista.
  Future<void> pasadasCortas(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget montar() {
    final dio = Dio()..httpClientAdapter = servidor;
    return ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        // Sin esperas: aquí no hay servidor y el cliente reintentaría con
        // esperas de verdad, que cuelgan el `pumpAndSettle` (§5).
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// Deja el tablero pintado con una zona llamada «Centro» y la deja a la
  /// vista: en el móvil las zonas no están en la primera página.
  Future<void> abrirElTableroEnCentro(WidgetTester tester, Size tamano) async {
    await tester.binding.setSurfaceSize(tamano);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await RepositorioTablero(
      base,
      ColaDeSalida(base),
    ).crearColumna(sucursalId: sucursalStg, nombre: 'Centro');

    await tester.pumpWidget(montar());
    await asentar(tester);

    if (tamano == _telefono) {
      // En el teléfono la página 0 es «Sin colocar»; «Centro» es la 1.
      await tester.tap(find.byTooltip('Ir a «Centro»'));
      await asentar(tester);
    }
  }

  Future<void> tocarCamionPrevisto(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Opciones de la columna'));
    await asentar(tester);
    expect(find.text('Camión previsto'), findsOneWidget);
    await tester.tap(find.text('Camión previsto'));
    await pasadasCortas(tester);
  }

  for (final (nombre, tamano) in const [
    ('el teléfono', _telefono),
    ('el escritorio', _escritorio),
  ]) {
    testWidgets('en $nombre se puede elegir camión de verdad', (tester) async {
      await abrirElTableroEnCentro(tester, tamano);
      await sembrarCamion(base, id: 'v1', nombre: 'F-350', capacidad: 1500);

      await tocarCamionPrevisto(tester);

      // LO QUE FALLABA: aquí no había absolutamente nada en pantalla.
      expect(
        find.text('Camión previsto para «Centro»'),
        findsOneWidget,
        reason:
            'el cajón del camión tiene que ABRIRSE; cerrar el menú y no abrir '
            'nada deja la zona sin vehículo y sin que nadie se entere',
      );
      expect(
        find.text('F-350'),
        findsOneWidget,
        reason: 'el vehículo de la sucursal tiene que estar en la lista',
      );

      // Y elegirlo tiene que llegar hasta la columna.
      await tester.tap(find.text('F-350'));
      await asentar(tester);

      expect(find.text('Camión: F-350'), findsOneWidget);
      expect(
        (await ColaDeSalida(base).lote()).last.metodo,
        'PATCH',
        reason: 'y sale hacia el servidor, no se queda sólo en la pantalla',
      );

      await desmontar(tester);
    });
  }

  testWidgets('la flota que baja DESPUÉS también aparece, sin cerrar el cajón', (
    tester,
  ) async {
    // Es el caso de la web, donde la base nace vacía en cada carga y los
    // camiones llegan un segundo más tarde (§3-ter). El `StreamProvider` está
    // puesto justo para esto desde el 17/09/2026, y el `read(.future)` que se
    // acaba de quitar lo desactivaba: leía una vez y se quedaba con lo que
    // hubiera, que es siempre «nada».
    await abrirElTableroEnCentro(tester, _escritorio);

    await tocarCamionPrevisto(tester);
    expect(find.text('Camión previsto para «Centro»'), findsOneWidget);
    expect(find.text('F-350'), findsNothing);

    // Con el cajón DELANTE, sin volver a montar nada: es la forma que exige el
    // §3-ter y la única que caza un `Future` congelado.
    await sembrarCamion(base, id: 'v1', nombre: 'F-350', capacidad: 1500);
    await pasadasCortas(tester);

    expect(
      find.text('F-350'),
      findsOneWidget,
      reason:
          'el camión bajó con el cajón abierto: si hay que cerrarlo y volver a '
          'abrirlo, la lista está congelada otra vez',
    );

    await desmontar(tester);
  });

  testWidgets('sin ningún vehículo el cajón se abre igual y DICE por qué', (
    tester,
  ) async {
    // §4: si algo falla la pantalla no se queda verde, y una colección que no
    // está se dice **con lo que se rompe sin ella**. Un cajón mudo con un «Sin
    // camión» suelto se lee como que la pantalla está rota, que es justo lo que
    // Jose vio.
    await abrirElTableroEnCentro(tester, _telefono);

    await tocarCamionPrevisto(tester);

    expect(find.text('Camión previsto para «Centro»'), findsOneWidget);
    expect(
      find.textContaining('no tiene vehículos activos'),
      findsOneWidget,
      reason: 'no se puede dejar el cajón en blanco sin explicar nada',
    );
    expect(
      find.textContaining('coste por km'),
      findsOneWidget,
      reason: 'hay que decir QUÉ se rompe sin camión, no sólo que no hay',
    );
    // Y quitar el camión se puede siempre, haya flota o no.
    expect(find.text('Sin camión'), findsOneWidget);

    await desmontar(tester);
  });
}
