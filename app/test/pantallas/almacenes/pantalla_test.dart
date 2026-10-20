/// LO QUE SE VE EN ALMACENES CUANDO NO HAY NADA.
///
/// Son tres situaciones que hasta ahora se pintaban casi igual y no lo son:
///
///  1. Accesos contesta y esa sucursal no tiene ninguno → **vacio de verdad**:
///     se dice que se da de alta en el CRM (sin boton: la pantalla es de lectura).
///  2. No hay red y el aparato **nunca** bajo los almacenes → no es que no
///     haya: es que no estan aqui, y se arregla trayendo el dia.
///  3. No hay red pero el aparato **si** tiene la copia bajada → con esa copia
///     se sigue midiendo el domicilio, y decirlo evita dar la mañana por
///     perdida.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/almacenes/vista/pantalla_almacenes.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_almacenes.dart';

void main() {
  Future<void> pintar(WidgetTester tester, Banco banco) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
        ],
        // El `Scaffold` lo pone el armazon, no la pantalla.
        child: const MaterialApp(home: Scaffold(body: PantallaAlmacenes())),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  /// Los `Stream` de Drift dejan un temporizador de cero al cerrarse: se
  /// desmonta dentro de la prueba para que se apague aqui y no despues.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> sembrarAlmacenBajado(BaseLocal base, {int cuantos = 1}) async {
    for (var i = 0; i < cuantos; i++) {
      await base
          .into(base.warehouses)
          .insertOnConflictUpdate(
            WarehousesCompanion.insert(
              id: 'w$i',
              sucursalCodigo: 'STG',
              nombre: 'Almacén $i',
              lat: const Value(20.02),
              lng: const Value(-75.82),
            ),
          );
    }
    await base
        .into(base.frescura)
        .insertOnConflictUpdate(
          FrescuraCompanion.insert(
            coleccion: Colecciones.almacenes,
            bajadaAt: Value(DateTime(2026, 9, 15, 8)),
            completa: const Value(true),
          ),
        );
  }

  testWidgets('la sucursal sin almacenes: un vacío que explica, sin botón', (
    tester,
  ) async {
    final banco = Banco(
      (_) async => RespuestaFalsa(200, const <String, Object?>{
        'sucursales': [
          {'codigo': 'STG', 'nombre': 'Santiago', 'almacenes': <Object?>[]},
        ],
      }),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    // Dice QUE ES un almacen para quien reparte, no para la base.
    expect(
      find.textContaining('el sitio del que sale el camión'),
      findsOneWidget,
    );
    // Dice QUE SE ROMPE mientras siga vacio.
    expect(find.textContaining('salen sin precio'), findsOneWidget);
    // Y conserva el literal del pliego, con a dónde ir.
    expect(
      find.textContaining('sus domicilios no se pueden cotizar'),
      findsOneWidget,
    );
    expect(find.textContaining('Se dan de alta en el CRM'), findsOneWidget);
    expect(find.text('Nuevo almacén'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    // NO el texto de «no se ha descargado»: Accesos contestó.
    expect(find.textContaining('no ha descargado los almacenes'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('sin red y SIN bajar: no es que no haya, es que no están aquí', (
    tester,
  ) async {
    final banco = Banco.sinRed();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    expect(find.textContaining('Sin conexión.'), findsOneWidget);
    expect(
      find.textContaining('no ha descargado los almacenes todavía'),
      findsOneWidget,
    );
    // Y no se dice que falten: eso no arregla esto.
    expect(
      find.textContaining('sus domicilios no se pueden cotizar'),
      findsNothing,
    );

    await desmontar(tester);
  });

  testWidgets('sin red pero CON la copia bajada: dice qué tiene dentro', (
    tester,
  ) async {
    final banco = Banco.sinRed();
    addTearDown(banco.cerrar);
    await sembrarAlmacenBajado(banco.base, cuantos: 2);
    await pintar(tester, banco);

    expect(find.textContaining('Sin conexión.'), findsOneWidget);
    expect(
      find.textContaining('tiene 2 almacén(es) de la última bajada'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no ha descargado los almacenes todavía'),
      findsNothing,
    );

    await desmontar(tester);
  });

  testWidgets('sin ninguna sucursal con código: se dice dónde se arregla', (
    tester,
  ) async {
    final banco = Banco(
      (_) async => RespuestaFalsa(200, const <String, Object?>{
        'sucursales': <Object?>[],
      }),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    expect(
      find.text('No hay ninguna sucursal a la vista con código en Accesos.'),
      findsOneWidget,
    );
    expect(find.textContaining('Se arregla en Accesos'), findsOneWidget);
    // Sin botón: desde aquí el código de la sucursal no se toca.
    expect(find.byType(FilledButton), findsNothing);

    await desmontar(tester);
  });
}
