// EL CAMIÓN EN EL TALLER — 28/09/2026.
//
// Jose dijo que sí a «en mantenimiento». Es lo ÚNICO del estado de la flota que
// se guarda: lo demás —libre, con ruta planificada, en ruta— se deduce de las
// rutas abiertas del camión y no lleva ni un campo nuevo. El taller es la
// excepción porque es lo único que NO se puede deducir: un camión en el taller
// no tiene ruta, exactamente igual que uno libre.
//
// Aquí se cubren las dos mitades de la pantalla:
//
//   1. LA FICHA, donde se pone. El desplegable de Estado se quitó esta misma
//      mañana porque ofrecía «En ruta» y «En mantenimiento» y **las dos daban
//      400 siempre**: no guardaba nada nunca. Vuelve con DOS opciones y sólo
//      dos, y «En ruta» no es una de ellas — eso no es una elección, es un hecho
//      que sale de las rutas.
//   2. LA TARJETA, donde se ve la contradicción: en el taller Y con una ruta
//      abierta. El servidor no cierra la ruta al mandarlo al taller (cerrarla
//      sería darla por repartida), así que la contradicción se queda en pie.
//
// Y van EN PAREJA, como todo aviso de esta casa: que salga cuando toca y que
// **no** salga cuando no. Un aviso que sale siempre deja de leerse, y entonces
// tampoco se lee el día que importa (`CLAUDE.md` §3-quinquies).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/vista/ficha_vehiculo.dart';
import 'package:reparto/pantallas/vehiculos/vista/tarjeta_vehiculo.dart';

void main() {
  const tipos = [TipoDeVehiculo(nombre: 'truck', costoKmUsd: 1.65)];

  Future<DatosVehiculo?> abrirFicha(
    WidgetTester tester,
    VehiculoDeLaApi? vehiculo, {
    bool guardar = true,
  }) async {
    DatosVehiculo? salida;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: vehiculo,
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            alGuardar: (datos) => salida = datos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!guardar) return null;
    await tester.tap(
      find.widgetWithText(FilledButton, vehiculo == null ? 'Agregar Vehículo' : 'Actualizar'),
    );
    await tester.pumpAndSettle();
    return salida;
  }

  // ---------------------------------------------------------------------------
  // 1 · La ficha: dos opciones y sólo dos
  // ---------------------------------------------------------------------------

  testWidgets('el desplegable de Estado ofrece DOS opciones, y «En ruta» no está', (
    tester,
  ) async {
    const libre = VehiculoDeLaApi(
      id: 'v1',
      nombre: 'Camión #1',
      capacidad: 1000,
      estado: 'available',
      tipo: 'truck',
    );
    await abrirFicha(tester, libre, guardar: false);

    // Cerrado enseña lo elegido; se abre para ver la lista entera.
    await tester.tap(find.text('Disponible').first);
    await tester.pumpAndSettle();

    expect(find.text('En mantenimiento'), findsWidgets);
    expect(
      find.text('En ruta'),
      findsNothing,
      reason:
          '«En ruta» no es una elección: sale de las rutas abiertas del camión. '
          'Ofrecerlo aquí invita a escribir a mano un dato que se calcula, y un '
          'estado que alguien pone y nadie quita miente a los dos días',
    );
  });

  testWidgets('lo elegido llega a `DatosVehiculo` como `maintenance`', (
    tester,
  ) async {
    DatosVehiculo? salida;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: const VehiculoDeLaApi(
              id: 'v1',
              nombre: 'Camión #1',
              capacidad: 1000,
              estado: 'available',
              tipo: 'truck',
            ),
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            alGuardar: (datos) => salida = datos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disponible').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('En mantenimiento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
    await tester.pumpAndSettle();

    expect(
      salida!.estado,
      'maintenance',
      reason:
          'es el literal del enum `vehicle_status`; cualquier otra cosa es el '
          '400 de `estadoValido` y la ficha vuelve a no guardar nada',
    );
    // Y NO se ha tocado nada más por el camino.
    expect(salida!.nombre, 'Camión #1');
    expect(salida!.tipo, 'truck');
  });

  testWidgets('y se puede sacar del taller: vuelve a `available`', (
    tester,
  ) async {
    // La otra mitad. Sin ella, un desplegable que escribiera `maintenance`
    // siempre dejaría la primera en verde y ningún camión podría volver.
    DatosVehiculo? salida;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: const VehiculoDeLaApi(
              id: 'v1',
              nombre: 'Camión #1',
              capacidad: 1000,
              estado: 'maintenance',
              tipo: 'truck',
            ),
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            alGuardar: (datos) => salida = datos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('En mantenimiento').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disponible').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
    await tester.pumpAndSettle();

    expect(salida!.estado, 'available');
  });

  testWidgets('un camión que el despacho tiene cogido NO se reescribe solo', (
    tester,
  ) async {
    // `in_use` no es una de las dos opciones y no puede serlo: lo pone y lo
    // quita el despacho de la ruta. El desplegable se abre sin nada marcado, y
    // guardar sin tocarlo tiene que dejar el campo TAL CUAL — una edición que
    // «arregla» algo por su cuenta se descubre semanas después.
    const ocupado = VehiculoDeLaApi(
      id: 'v1',
      nombre: 'Camión #1',
      capacidad: 1000,
      estado: 'in_use',
      tipo: 'truck',
    );
    final salida = await abrirFicha(tester, ocupado);

    expect(
      salida!.estado,
      'in_use',
      reason:
          'si la ficha lo pisara con «available», una edición de la placa '
          'soltaría el camión de su ruta sin que nadie lo pidiera',
    );
  });

  // ---------------------------------------------------------------------------
  // 2 · La tarjeta: en el taller Y con ruta abierta
  // ---------------------------------------------------------------------------

  Future<void> pintarTarjeta(WidgetTester tester, VehiculoDeLaApi v) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaVehiculo(
              vehiculo: v,
              importe: (usd) => usd == null ? '—' : '\$$usd',
              alEditar: () {},
              alEliminar: () {},
              alMarcarDisponible: () {},
              alUsarParaDomicilio: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  VehiculoDeLaApi camion({
    required String estado,
    Map<String, Object?>? ruta,
  }) => VehiculoDeLaApi.deJson(<String, Object?>{
    'id': 'v1',
    'name': 'Camión #1',
    'capacity': 1000,
    'status': estado,
    'routes': ruta == null ? <Object?>[] : <Object?>[ruta],
  });

  testWidgets('en el taller con ruta abierta: la insignia es Mantenimiento y se dice la ruta', (
    tester,
  ) async {
    await pintarTarjeta(
      tester,
      camion(
        estado: 'maintenance',
        ruta: {
          'id': 'r1',
          'routeCode': 'RT-20260928-007',
          'status': 'in_progress',
        },
      ),
    );

    expect(
      find.text('Mantenimiento'),
      findsOneWidget,
      reason:
          'si ganara la ruta, la insignia diría «En ruta» sobre un camión que '
          'está en el taller: eso se lee como lo normal y nadie mira',
    );
    // Y la ruta NOMBRADA. Sin el código hay que ponerse a buscar cuál es.
    expect(find.textContaining('RT-20260928-007'), findsWidgets);
    expect(find.textContaining('Está en el taller y lleva la ruta'), findsOneWidget);
  });

  testWidgets('en el taller SIN ruta no sale ningún aviso', (tester) async {
    await pintarTarjeta(tester, camion(estado: 'maintenance'));

    expect(find.text('Mantenimiento'), findsOneWidget);
    expect(
      find.textContaining('Está en el taller y lleva la ruta'),
      findsNothing,
      reason:
          'un cartel ámbar permanente en todos los camiones del taller deja de '
          'leerse, y entonces tampoco se lee el día que sí hay contradicción',
    );
  });

  testWidgets('con ruta abierta y sin taller tampoco sale', (tester) async {
    await pintarTarjeta(
      tester,
      camion(
        estado: 'available',
        ruta: {
          'id': 'r1',
          'routeCode': 'RT-20260928-001',
          'status': 'in_progress',
        },
      ),
    );

    expect(find.text('En ruta'), findsOneWidget);
    expect(find.textContaining('Está en el taller'), findsNothing);
  });
}
