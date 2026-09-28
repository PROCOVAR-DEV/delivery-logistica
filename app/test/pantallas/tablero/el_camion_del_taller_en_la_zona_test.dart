// EL CAMIÓN DEL TALLER EN EL «CAMIÓN PREVISTO» DE UNA ZONA — 28/09/2026.
//
// Desde hoy un camión se puede marcar «en mantenimiento» (migración 00013), y
// este cajón es el segundo de los dos sitios donde se elige camión. La decisión
// es la misma que en el paso 3 del asistente de Rutas: **se ofrece y se marca,
// no se bloquea**.
//
// Por qué, y hoy mismo se decidió lo contrario para el caso de al lado: una zona
// SIN camión sí se bloquea (`repositorio.dart`, `armarRuta`), porque sin camión
// la capacidad y el coste por km se quedan sin denominador y la ruta sale con un
// peso y un importe que no significan nada. Un camión en el taller tiene su
// capacidad y su costo por km: lo que falta es el camión, no el dato. Y
// `maintenance` lo pone una persona y lo tiene que quitar otra — en producción
// hay sucursales con UN camión, y uno que alguien se olvidó de sacar del taller
// las dejaría sin poder armar ni una zona, con el arreglo en otra pantalla.
//
// EN PAREJA, como siempre: el del taller sale marcado, y el normal NO sale
// marcado. Sin la segunda, pintar «EN EL TALLER» en todos dejaría la primera en
// verde y el aviso dejaría de leerse.

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

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  // Aquí SÓLO se abre la base: sembrar en el `setUp` de un `testWidgets` deja lo
  // de Drift empezado fuera del reloj falso y la prueba se cuelga (§5.2).
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

  /// Pasadas cortas y CONTADAS: con el cajón del camión delante hay una rueda
  /// mientras la flota no llega, y una rueda no se asienta nunca.
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

  Future<void> abrirElCajonDelCamion(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await RepositorioTablero(
      base,
      ColaDeSalida(base),
    ).crearColumna(sucursalId: sucursalStg, nombre: 'Centro');

    await tester.pumpWidget(montar());
    await asentar(tester);

    await tester.tap(find.byTooltip('Opciones de la columna'));
    await asentar(tester);
    await tester.tap(find.text('Camión previsto'));
    await pasadasCortas(tester);
  }

  testWidgets('el camión del taller sale en la lista, MARCADO, y se puede elegir', (
    tester,
  ) async {
    await sembrarCamion(base, id: 'v1', nombre: 'F-350', capacidad: 1500);
    await sembrarCamion(
      base,
      id: 'v2',
      nombre: 'Kamaz',
      capacidad: 3000,
      estado: 'maintenance',
    );
    await abrirElCajonDelCamion(tester);

    expect(find.text('Camión previsto para «Centro»'), findsOneWidget);
    expect(
      find.text('Kamaz'),
      findsOneWidget,
      reason:
          'sacarlo de la lista sería bloquear con un campo que alguien pone y '
          'otro tiene que quitar: una sucursal de un camión se quedaría sin '
          'poder armar nada y el arreglo está en otra pantalla',
    );
    expect(
      find.textContaining('EN EL TALLER'),
      findsOneWidget,
      reason:
          'y si no se marca, el camión roto se elige igual que los demás: la '
          'zona se arma con un camión que no puede salir',
    );

    // Y SE PUEDE ELEGIR de verdad: aviso, no bloqueo.
    await tester.tap(find.text('Kamaz'));
    await asentar(tester);
    expect(find.text('Camión: Kamaz'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('y un camión normal NO sale marcado', (tester) async {
    await sembrarCamion(base, id: 'v1', nombre: 'F-350', capacidad: 1500);
    await abrirElCajonDelCamion(tester);

    expect(find.text('F-350'), findsOneWidget);
    expect(
      find.textContaining('EN EL TALLER'),
      findsNothing,
      reason:
          'un cartel que sale en todos los camiones deja de leerse, y entonces '
          'tampoco se lee el día que uno sí está roto',
    );
    await desmontar(tester);
  });
}
