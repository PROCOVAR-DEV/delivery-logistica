// QUE CAMIONES SE OFRECEN PARA UNA RUTA NUEVA — el asistente, 07/10/2026.
//
// Amado, incidencia 4: un camion con rutas no se borra, se INACTIVA, y los
// inactivos no salen en la seleccion de rutas nuevas. Y el camion del taller
// tampoco: el servidor, al negarse a borrar un camion con rutas, dice «Ponlo en
// mantenimiento para impedir que se use en nuevas rutas».
//
// ## Lo que esta prueba reemplaza
//
// Aqui estaba `el_camion_del_taller_se_avisa_test.dart` (28/09/2026), que fijaba
// justo lo contrario: el camion del taller SE OFRECIA, con un aviso ambar, y «no
// bloquea». Su argumento colgaba del `CLAUDE.md` §2 de entonces —los avisos del
// armador son aviso, no bloqueo, por los 657 de 686 domicilios sin costo—, que
// Amado reemplazo el 07/10/2026. Se quita ENTERA, aviso incluido, no a medias.
//
// EN PAREJA, como siempre: el inactivo y el del taller NO salen; el normal SI.
// Sin la segunda, ocultar TODOS dejaria las dos primeras en verde.
//
// Las listas que miran rutas ya hechas siguen viendo TODA la flota: eso lo ata
// `vehiculosQueVeLaListaDeRutas` abajo.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 7, 9, 0);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Una sucursal y su almacen. Con una sola sucursal y un solo almacen el
  /// asistente abre directamente en el paso 3, que es el que aqui se mide.
  Future<void> sembrarLaSucursal() async {
    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'B1',
            name: 'Camagüey',
            lat: 21.38,
            lng: -77.91,
            externalId: const Value('CAM'),
          ),
        );
    await base
        .into(base.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: 'W1',
            sucursalCodigo: 'CAM',
            nombre: 'Almacén central',
            lat: const Value(21.38),
            lng: const Value(-77.91),
            principal: const Value(true),
          ),
        );
  }

  Future<void> sembrarCamion(
    String id,
    String nombre, {
    String estado = 'available',
    bool activo = true,
  }) => base
      .into(base.vehicles)
      .insert(
        VehiclesCompanion.insert(
          id: id,
          name: nombre,
          capacity: const Value(1000),
          plate: Value('P-$id'),
          status: Value(estado),
          isActive: Value(activo),
          branchId: const Value('B1'),
        ),
      );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Desmonta el árbol antes de que acabe la prueba: si no, Drift deja un
  /// temporizador colgando fuera del reloj falso.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// MONTA CON LA BASE VACIA: lo que se siembre va DESPUES, dentro de la prueba
  /// y sin volver a montar (`CLAUDE.md` §3-ter y §5.2).
  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: AsistenteNuevaRuta()),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> abrirLaLista(WidgetTester tester) async {
    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
  }

  testWidgets('un camión inactivo NO sale en la lista, el activo SI', (
    tester,
  ) async {
    await pintar(tester);
    // Se siembra DESPUES de montar: la bajada llega con la pantalla delante.
    await sembrarLaSucursal();
    await sembrarCamion('V1', 'Camión activo');
    await sembrarCamion('V2', 'Camión de baja', activo: false);
    await asentar(tester);

    await abrirLaLista(tester);
    expect(find.text('Camión activo'), findsWidgets);
    expect(
      find.text('Camión de baja'),
      findsNothing,
      reason:
          'un camión inactivo no se asigna a una ruta nueva: el servidor lo '
          'rechaza con 400, y la lista no debe ofrecer lo que luego se niega',
    );
    await desmontar(tester);
  });

  testWidgets('el camión del taller tampoco sale: ya no se avisa, no se ofrece', (
    tester,
  ) async {
    await pintar(tester);
    await sembrarLaSucursal();
    await sembrarCamion('V1', 'Camión sano');
    await sembrarCamion('V2', 'Camión del taller', estado: 'maintenance');
    await asentar(tester);

    await abrirLaLista(tester);
    expect(find.text('Camión sano'), findsWidgets);
    expect(find.text('Camión del taller'), findsNothing);
    // Y el cartel del 28/09 se fue ENTERO con la decisión que lo sostenía.
    expect(find.textContaining('en el taller'), findsNothing);
    expect(find.textContaining('EN EL TALLER'), findsNothing);
    await desmontar(tester);
  });

  testWidgets('el camión que vuelve a estar activo reaparece sin remontar', (
    tester,
  ) async {
    // Lo que cambia con la pantalla delante va por Stream (§3-ter): dar de alta
    // otra vez el camión desde la ficha llega por la bajada, no por un montaje.
    await pintar(tester);
    await sembrarLaSucursal();
    // Con otro activo al lado: si el de baja fuera el único, no habría lista.
    await sembrarCamion('V0', 'Camión de siempre');
    await sembrarCamion('V1', 'Camión de baja', activo: false);
    await asentar(tester);
    await abrirLaLista(tester);
    expect(find.text('Camión de baja'), findsNothing);
    // Se cierra el desplegable antes de cambiar el dato.
    await tester.tapAt(const Offset(5, 5));
    await asentar(tester);

    await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
      const VehiclesCompanion(isActive: Value(true)),
    );
    await asentar(tester);

    await abrirLaLista(tester);
    expect(find.text('Camión de baja'), findsWidgets);
    await desmontar(tester);
  });

  testWidgets(
    'si la sucursal sólo tiene camiones sin ofrecer, se dice por qué',
    (tester) async {
      await pintar(tester);
      await sembrarLaSucursal();
      await sembrarCamion('V1', 'Camión de baja', activo: false);
      await asentar(tester);

      // No dice «no tiene ningún vehículo»: tiene uno, está de baja.
      expect(find.textContaining('inactivos o en el taller'), findsOneWidget);
      expect(find.textContaining('no tiene ningún vehículo'), findsNothing);
      await desmontar(tester);
    },
  );

  test('la lista de Rutas (filtros, informes) SIGUE viendo toda la flota', () async {
    // El filtro de camión de una lista de rutas ya hechas tiene que poder
    // nombrar un camión que hoy esta de baja: la ruta de ayer fue en el.
    await sembrarLaSucursal();
    await sembrarCamion('V1', 'Camión activo');
    await sembrarCamion('V2', 'Camión de baja', activo: false);
    await sembrarCamion('V3', 'Camión del taller', estado: 'maintenance');

    final contenedor = ProviderContainer.test(
      overrides: [baseProvider.overrideWithValue(base)],
    );
    final oyente = contenedor.listen(vehiculosProvider, (_, _) {});
    addTearDown(oyente.close);
    final todos = await contenedor.read(vehiculosProvider.future);
    expect(todos.map((v) => v.id).toSet(), {'V1', 'V2', 'V3'});
  });
}
