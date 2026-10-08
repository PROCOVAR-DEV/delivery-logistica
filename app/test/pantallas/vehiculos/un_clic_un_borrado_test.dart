import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/estado/estado_vehiculos.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_vehiculos.dart';

/// UN CLIC, UN BORRADO — y la pregunta antes.
///
/// Las dos mitades del mismo fallo de Vehículos, medido en producción el
/// 01/10/2026:
///
///  1. un solo clic mandaba **dos** `DELETE` solapados, y el segundo pintaba una
///     franja roja con el «Not found» en inglés del servidor encima de un
///     borrado que sí había funcionado;
///  2. borrar un camión **no preguntaba nada**.
///
/// El porqué de cada una está en `estado_vehiculos.dart` (`_enVuelo`) y en
/// `pantalla_vehiculos.dart` (`_Rejilla._borrarPreguntando`).
void main() {
  /// El camión que se borra en todas estas pruebas.
  Banco bancoConUnCamion({int codigoDelBorrado = 200}) => Banco((p) async {
    if (p.ruta.endsWith('/settings')) {
      return RespuestaFalsa(200, const <String, Object?>{});
    }
    if (p.metodo == 'DELETE') {
      return codigoDelBorrado == 200
          ? RespuestaFalsa(200, const <String, Object?>{'success': true})
          // Lo que contestó de verdad el segundo borrado: el 404 literal del
          // servidor, en inglés (`httpx.MsgNotFound`).
          : RespuestaFalsa(404, const <String, Object?>{'error': 'Not found'});
    }
    return RespuestaFalsa(200, const <Object?>[
      <String, Object?>{
        'id': 'v1',
        'name': 'Camión #1',
        'capacity': 2500,
        'status': 'available',
      },
      <String, Object?>{
        'id': 'v2',
        'name': 'Camión #2',
        'capacity': 1200,
        'status': 'available',
      },
    ]);
  });

  group('la guarda de «ya voy»', () {
    test('el mismo borrado dos veces a la vez sale UNA vez', () async {
      final banco = bancoConUnCamion();
      addTearDown(banco.cerrar);
      final control = banco.contenedor.read(controlVehiculosProvider.notifier);

      // EL GESTO DUPLICADO, tal como llega del navegador: las dos llamadas
      // **sin esperar** la primera, que es lo que significa «se solapan».
      final primera = control.eliminar('v1');
      final segunda = control.eliminar('v1');

      expect(await primera, isTrue);
      expect(await segunda, isTrue);

      expect(
        banco.servidor.cuantas('DELETE', '/vehicles/v1'),
        1,
        reason:
            'un gesto duplicado tiene que mandar UN borrado: el segundo recibe '
            'el 404 de un camión que ya no está y lo pinta como un fallo',
      );
      // Y NO HAY FRANJA ROJA. El aviso que queda es el del borrado que sí fue.
      final aviso = banco.contenedor.read(controlVehiculosProvider);
      expect(aviso?.esFallo, isFalse);
      expect(aviso?.texto, 'Vehículo eliminado.');
    });

    test('los dos que llegan ven el MISMO resultado, también cuando falla', () async {
      // Con el 404 de respuesta las dos tienen que contestar lo mismo: una
      // contestando `false` y la otra `true` sobre un solo borrado es la mitad
      // del fallo original.
      final banco = bancoConUnCamion(codigoDelBorrado: 404);
      addTearDown(banco.cerrar);
      final control = banco.contenedor.read(controlVehiculosProvider.notifier);

      final primera = control.eliminar('v1');
      final segunda = control.eliminar('v1');

      expect(await primera, isFalse);
      expect(
        await segunda,
        isFalse,
        reason:
            'las dos llamadas son el mismo gesto: una contestando «se guardó» '
            'y la otra «no se guardó» sobre un solo borrado es el fallo de '
            'origen',
      );
      expect(banco.servidor.cuantas('DELETE', '/vehicles/v1'), 1, reason:
          'un gesto duplicado tiene que mandar UN borrado');
    });

    test('es «mientras va», no «una sola vez»: el reintento a mano sale', () async {
      final banco = bancoConUnCamion();
      addTearDown(banco.cerrar);
      final control = banco.contenedor.read(controlVehiculosProvider.notifier);

      await control.eliminar('v1');
      await control.eliminar('v1');

      expect(
        banco.servidor.cuantas('DELETE', '/vehicles/v1'),
        2,
        reason:
            'la llave se suelta al terminar: si no, un fallo de red dejaría el '
            'botón muerto para siempre',
      );
    });

    test('dos camiones distintos a la vez salen los dos', () async {
      final banco = bancoConUnCamion();
      addTearDown(banco.cerrar);
      final control = banco.contenedor.read(controlVehiculosProvider.notifier);

      await Future.wait([control.eliminar('v1'), control.eliminar('v2')]);

      // LA GUARDA ES POR ACCIÓN, NO UNA PARA TODA LA PANTALLA. Con una global
      // el segundo camión se quedaría sin borrar y nadie lo diría: el descarte
      // en silencio que prohíbe el §4.
      const porQue =
          'la guarda es por acción, no una para toda la pantalla: con una '
          'global el segundo camión se queda sin borrar y nadie lo dice';
      expect(banco.servidor.cuantas('DELETE', '/vehicles/v1'), 1, reason: porQue);
      expect(banco.servidor.cuantas('DELETE', '/vehicles/v2'), 1, reason: porQue);
    });

    test('el doble «Guardar» no da de alta el camión dos veces', () async {
      final banco = Banco(
        (p) async => p.ruta.endsWith('/settings')
            ? RespuestaFalsa(200, const <String, Object?>{})
            : p.metodo == 'POST'
            ? RespuestaFalsa(200, const <String, Object?>{'id': 'v9'})
            : RespuestaFalsa(200, const <Object?>[]),
      );
      addTearDown(banco.cerrar);
      final control = banco.contenedor.read(controlVehiculosProvider.notifier);

      const datos = DatosVehiculo(nombre: 'Camión #9', capacidad: 1000);
      final primera = control.crear(datos);
      final segunda = control.crear(datos);
      await primera;
      await segunda;

      expect(
        banco.servidor.cuantas('POST', '/vehicles'),
        1,
        reason: 'un doble Guardar no puede dar de alta el camión dos veces',
      );
    });
  });

  group('la pregunta de antes de borrar', () {
    Future<void> pintar(WidgetTester tester, Banco banco) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(banco.base),
            clienteApiProvider.overrideWithValue(
              banco.contenedor.read(clienteApiProvider),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('tocar «Eliminar» NO borra: pregunta, y nombra el camión', (
      tester,
    ) async {
      final banco = bancoConUnCamion();
      addTearDown(banco.cerrar);
      await pintar(tester, banco);

      await tester.tap(find.text('Eliminar').first);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

      expect(
        banco.servidor.cuantas('DELETE', '/vehicles/v1'),
        0,
        reason: 'un camión no se va de un toque',
      );
      // El mismo literal de la zona del tablero, con el nombre dentro: «Sí,
      // borrar X» dice qué se va, «Aceptar» no dice nada.
      expect(find.text('Sí, borrar «Camión #1»'), findsOneWidget);
      expect(find.text('No, dejarlo'), findsOneWidget);
      // Y dice qué se pierde, que es la mitad que sirve.
      // Desde el 07/10/2026 (Amado, incidencia 4) un camión con rutas NO se
      // borra, y la pregunta lo dice y apunta a la salida: marcarlo inactivo.
      // Lo que decía antes («se quedan sin camión») ya no es verdad.
      expect(find.textContaining('se quedan sin camión'), findsNothing);
      expect(
        find.textContaining('NO se puede borrar'),
        findsOneWidget,
        reason: 'un camión con rutas, aunque sean históricas, no se borra',
      );
      expect(find.textContaining('márcalo como inactivo'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('«No, dejarlo» no manda nada', (tester) async {
      final banco = bancoConUnCamion();
      addTearDown(banco.cerrar);
      await pintar(tester, banco);

      await tester.tap(find.text('Eliminar').first);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.text('No, dejarlo'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

      expect(
        banco.servidor.cuantas('DELETE', '/vehicles/v1'),
        0,
        reason: 'contestar «No» tiene que dejar el camión donde estaba',
      );
      expect(find.text('Camión #1'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('cerrar el cajón con la ✕ es NO, no un sí por descuido', (
      tester,
    ) async {
      // `abrirCajon` devuelve `null` cuando se cierra sin contestar —la ✕, tocar
      // fuera, Escape—, y `null` tiene que ser NO. Si fuera «sí», el camión se
      // iría por cerrar un cajón, que es peor que no haber preguntado.
      final banco = bancoConUnCamion();
      addTearDown(banco.cerrar);
      await pintar(tester, banco);

      await tester.tap(find.text('Eliminar').first);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

      expect(
        banco.servidor.cuantas('DELETE', '/vehicles/v1'),
        0,
        reason: 'cerrar sin contestar no puede borrar nada',
      );
      expect(find.text('Camión #1'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('y al contestar «Sí» se borra, una sola vez', (tester) async {
      final banco = bancoConUnCamion();
      addTearDown(banco.cerrar);
      await pintar(tester, banco);

      await tester.tap(find.text('Eliminar').first);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.text('Sí, borrar «Camión #1»'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

      expect(
        banco.servidor.cuantas('DELETE', '/vehicles/v1'),
        1,
        reason: 'contestar «Sí» borra, y una sola vez',
      );
      expect(find.text('Vehículo eliminado.'), findsOneWidget);

      await desmontar(tester);
    });
  });
}
