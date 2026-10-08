// QUE CAMIONES SE OFRECEN COMO «CAMION PREVISTO» DE UNA ZONA — 07/10/2026.
//
// Segundo de los dos sitios donde se elige camion para una ruta nueva (el otro
// es el paso 3 del asistente: `camiones_que_se_ofrecen_test.dart`). Amado,
// incidencia 4: los camiones inactivos no salen en la seleccion de rutas nuevas;
// y el del taller tampoco, que es lo que dice el servidor al negarse a borrar un
// camion con rutas («…Márcalo como inactivo para impedir que se use en nuevas
// rutas»).
//
// ## Lo que esta prueba reemplaza
//
// Aqui estaba `el_camion_del_taller_en_la_zona_test.dart` (28/09/2026), que
// fijaba lo contrario: el del taller SALIA, marcado «EN EL TALLER», porque
// «sacarlo de la lista seria bloquear con un campo que alguien pone y otro tiene
// que quitar». Ese argumento colgaba del `CLAUDE.md` §2 de entonces, que Amado
// reemplazo el 07/10/2026. Se quita ENTERA, marca incluida.
//
// EN PAREJA, como siempre: el inactivo y el del taller NO salen, y el normal SI.
// Sin la segunda, ocultar TODOS dejaria las dos primeras en verde.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
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

  testWidgets('el camión inactivo y el del taller NO salen; el normal SI', (
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
    await sembrarCamion(
      base,
      id: 'v3',
      nombre: 'Zil de baja',
      capacidad: 2000,
      activo: false,
    );
    await abrirElCajonDelCamion(tester);

    expect(find.text('Camión previsto para «Centro»'), findsOneWidget);
    expect(find.text('F-350'), findsOneWidget);
    expect(
      find.text('Kamaz'),
      findsNothing,
      reason: 'un camión en el taller no se asigna a una ruta nueva',
    );
    expect(
      find.text('Zil de baja'),
      findsNothing,
      reason:
          'un camión inactivo lo rechaza el servidor con 400; la lista no '
          'debe ofrecer lo que luego se niega',
    );
    // Y el cartel del 28/09 se fue ENTERO con la decisión que lo sostenía.
    expect(find.textContaining('EN EL TALLER'), findsNothing);
    await desmontar(tester);
  });

  testWidgets('sin ninguno que ofrecer se dice por qué, y «Sin camión» sigue', (
    tester,
  ) async {
    await sembrarCamion(base, id: 'v1', nombre: 'Kamaz', estado: 'maintenance');
    await sembrarCamion(base, id: 'v2', nombre: 'Zil de baja', activo: false);
    await abrirElCajonDelCamion(tester);

    expect(find.text('Sin camión'), findsOneWidget);
    expect(
      find.textContaining('no tiene vehículos activos y fuera del taller'),
      findsOneWidget,
    );
    expect(find.text('Kamaz'), findsNothing);
    expect(find.text('Zil de baja'), findsNothing);
    await desmontar(tester);
  });

  testWidgets('el que se reactiva con el cajón abierto aparece sin remontar', (
    tester,
  ) async {
    // Lo que cambia con la pantalla delante va por Stream (§3-ter): la bajada
    // trae `isActive: true` y la lista tiene que enterarse sola.
    await sembrarCamion(base, id: 'v1', nombre: 'F-350');
    await sembrarCamion(base, id: 'v2', nombre: 'Zil de baja', activo: false);
    await abrirElCajonDelCamion(tester);
    expect(find.text('Zil de baja'), findsNothing);

    await (base.update(base.vehicles)..where((v) => v.id.equals('v2'))).write(
      const VehiclesCompanion(isActive: Value(true)),
    );
    await pasadasCortas(tester);
    expect(find.text('Zil de baja'), findsOneWidget);
    await desmontar(tester);
  });
}
