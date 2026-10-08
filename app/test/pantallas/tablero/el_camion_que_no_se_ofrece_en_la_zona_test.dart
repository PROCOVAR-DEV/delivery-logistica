// QUE CAMIONES NO SE OFRECEN COMO «CAMION PREVISTO» DE UNA ZONA: el INACTIVO.
// 07/10/2026, corregido el 08/10/2026 (1.0.29).
//
// Segundo de los dos sitios donde se elige camion para una ruta nueva (el otro
// es el paso 3 del asistente: `camiones_que_se_ofrecen_test.dart`). Amado,
// incidencia 4: los camiones inactivos no salen en la seleccion de rutas nuevas
// (el servidor los rechaza con 400: «El vehículo está inactivo y no se puede
// asignar a una ruta.»).
//
// ## Lo que NO hace esta prueba
//
// El camion del TALLER no se oculta: sale marcado «EN EL TALLER»
// (`el_camion_del_taller_en_la_zona_test.dart`). 1.0.28 lo ocultaba tambien, con
// un argumento que no era de Amado, y el servidor sigue aceptandolo.
//
// EN PAREJA, como siempre: el inactivo NO sale, y el normal y el del taller SI.
// Sin la segunda, ocultar TODOS dejaria la primera en verde.

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

  testWidgets('el camión inactivo NO sale; el normal y el del taller SI', (
    tester,
  ) async {
    await abrirElCajonDelCamion(tester);
    // Se siembra DESPUES de abrir el cajon: la flota baja con la pantalla delante.
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
    await pasadasCortas(tester);

    expect(find.text('Camión previsto para «Centro»'), findsOneWidget);
    expect(find.text('F-350'), findsOneWidget);
    expect(
      find.text('Kamaz'),
      findsOneWidget,
      reason: 'el del taller se avisa, no se oculta (aviso, no bloqueo)',
    );
    expect(
      find.text('Zil de baja'),
      findsNothing,
      reason:
          'un camión inactivo lo rechaza el servidor con 400; la lista no '
          'debe ofrecer lo que luego se niega',
    );
    await desmontar(tester);
  });

  testWidgets('sin ninguno activo se dice por qué, y «Sin camión» sigue', (
    tester,
  ) async {
    await abrirElCajonDelCamion(tester);
    await sembrarCamion(base, id: 'v2', nombre: 'Zil de baja', activo: false);
    await pasadasCortas(tester);

    expect(find.text('Sin camión'), findsOneWidget);
    expect(
      find.text('Esta sucursal no tiene vehículos activos en este aparato.'),
      findsOneWidget,
    );
    // Un solo nombre para la pantalla: «Vehículos», no «Flota».
    expect(find.textContaining('se activan en Vehículos'), findsOneWidget);
    expect(find.textContaining('Flota'), findsNothing);
    expect(find.text('Zil de baja'), findsNothing);
    await desmontar(tester);
  });

  testWidgets('el que se reactiva con el cajón abierto aparece sin remontar', (
    tester,
  ) async {
    // Lo que cambia con la pantalla delante va por Stream (§3-ter): la bajada
    // trae `isActive: true` y la lista tiene que enterarse sola.
    await abrirElCajonDelCamion(tester);
    await sembrarCamion(base, id: 'v1', nombre: 'F-350');
    await sembrarCamion(base, id: 'v2', nombre: 'Zil de baja', activo: false);
    await pasadasCortas(tester);
    expect(find.text('Zil de baja'), findsNothing);

    await (base.update(base.vehicles)..where((v) => v.id.equals('v2'))).write(
      const VehiclesCompanion(isActive: Value(true)),
    );
    await pasadasCortas(tester);
    expect(find.text('Zil de baja'), findsOneWidget);
    await desmontar(tester);
  });
}
