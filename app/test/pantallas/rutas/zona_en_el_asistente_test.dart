// ELEGIR UNA ZONA DEL TABLERO DESDE EL ASISTENTE, Y QUE VENGA CON SU CAMIÓN.
//
// Jose, 22/09/2026:
//
//   «recuerda desde la ruta poder utilizar estos tableros q sean como los
//   pedidos pero q tengo un seleccionar con dropdown q tenga todos los pedidos y
//   de ahi selecciono el tablero y ya selecciono los pedidos de ese tablero ya
//   tendria el camion preparado»
//
// Lo que se mide aquí son las tres reglas que el gesto añade y que
// `repartirLaZona` —el reparto, que NO se reescribe— no cubre: qué zonas se
// pueden ofrecer, cómo queda la lista al elegir una, y **qué pasa con el camión
// cuando la zona trae uno y la persona ya había elegido otro**.
//
// Van en pareja a propósito: elegir zona acota y trae camión; no elegir ninguna
// deja todo exactamente como estaba.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/zona_en_el_asistente.dart';
import 'package:reparto/pantallas/rutas/vista/selector_de_zona.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';

Pedido _pedido(String id, {double kg = 10}) => Pedido(
  id: id,
  customerName: 'Cliente $id',
  address: 'Calle $id',
  weight: kg,
  status: 'pending',
  tripLeg: 'ida',
  archivado: false,
);

Vehiculo _camion(String id, String nombre, {String? sucursal = 'stg'}) =>
    Vehiculo(
      id: id,
      name: nombre,
      capacity: 1000,
      usarParaDomicilio: false,
      status: 'available',
      branchId: sucursal,
    );

TarjetaPedido _tarjeta(String id) => TarjetaPedido(
  pedidoId: id,
  customerName: 'Cliente $id',
  address: 'Calle $id',
  weight: 10,
  kmAlAlmacen: 1,
  mismoCliente: 1,
);

ColumnaTablero _columna(
  String id,
  String nombre, {
  required int pedidos,
  double pesoKg = 100,
  String? vehiculoId,
  String? vehiculoNombre,
}) => ColumnaTablero(
  id: id,
  branchId: 'stg',
  nombre: nombre,
  posicion: 0,
  pedidos: pedidos,
  pesoKg: pesoKg,
  costoUsd: 0,
  vehiculoId: vehiculoId,
  vehiculoNombre: vehiculoNombre,
);

Tablero _tablero({
  String sucursalId = 'stg',
  required List<ColumnaTablero> columnas,
  required List<TarjetaColocada> colocados,
}) => Tablero(
  sucursalId: sucursalId,
  sucursalNombre: 'Santiago',
  almacen: const AlmacenOrigen(id: 'a1', nombre: 'Central', lat: 20, lng: -75),
  columnas: columnas,
  colocados: colocados,
  avisos: const AvisosTablero(),
  sinColocar: const MitadIzquierda(pedidos: <TarjetaPedido>[], total: 0),
  desaparecidos: const <PedidoDesaparecido>[],
);

TarjetaColocada _puesta(String pedidoId, String columnaId, int posicion) =>
    TarjetaColocada(
      pedido: _tarjeta(pedidoId),
      columnaId: columnaId,
      posicion: posicion,
    );

/// Un tablero de Santiago con dos zonas: «Vista» con tres pedidos y camión
/// previsto, y «Carretera» con dos y sin camión.
Tablero _tableroDeSantiago() => _tablero(
  columnas: [
    _columna(
      'z1',
      'Vista',
      pedidos: 3,
      pesoKg: 340,
      vehiculoId: 'v-hab',
      vehiculoNombre: 'Vehiculo HAB',
    ),
    _columna('z2', 'Carretera', pedidos: 2, pesoKg: 80),
  ],
  colocados: [
    _puesta('p3', 'z1', 0),
    _puesta('p1', 'z1', 1),
    _puesta('p2', 'z1', 2),
    _puesta('p8', 'z2', 0),
    _puesta('p9', 'z2', 1),
  ],
);

void main() {
  // ---------------------------------------------------------------------------
  // Qué zonas se pueden ofrecer
  // ---------------------------------------------------------------------------

  test('las zonas que salen son las del tablero de ESTA sucursal', () {
    final zonas = zonasParaArmar(_tableroDeSantiago(), 'stg');

    expect(zonas.map((z) => z.nombre), ['Vista', 'Carretera']);
    expect(zonas.first.ids, [
      'p3',
      'p1',
      'p2',
    ], reason: 'en el orden de visita que dejó el logístico, no por id');
    expect(zonas.first.vehiculoId, 'v-hab');
  });

  test('el tablero de OTRA sucursal no ofrece ni una zona', () {
    // La pareja de la de arriba. El tablero cargado es el de Santiago —el de la
    // barra de arriba— y la ruta se está armando para La Habana: ofrecer esas
    // zonas sería meter pedidos que no son de esta ruta, y el servidor los
    // rechaza al guardar.
    expect(zonasParaArmar(_tableroDeSantiago(), 'hab'), isEmpty);
    expect(zonasParaArmar(_tableroDeSantiago(), null), isEmpty);
    expect(zonasParaArmar(null, 'stg'), isEmpty);
    expect(
      zonasParaArmar(const Tablero.imposible('Elige una sucursal'), 'stg'),
      isEmpty,
    );
  });

  test('una zona vacía no se ofrece', () {
    final zonas = zonasParaArmar(
      _tablero(
        columnas: [
          _columna('z1', 'Vista', pedidos: 1),
          _columna('z2', 'Vacía', pedidos: 0),
        ],
        colocados: [_puesta('p1', 'z1', 0)],
      ),
      'stg',
    );

    expect(zonas.map((z) => z.nombre), ['Vista']);
  });

  test('la etiqueta dice lo que lleva la zona', () {
    final zonas = zonasParaArmar(_tableroDeSantiago(), 'stg');

    expect(zonas.first.etiqueta, 'Vista · 3 pedidos · 340 kg');
    expect(
      zonasParaArmar(
        _tablero(
          columnas: [_columna('z1', 'Vista', pedidos: 1, pesoKg: 12)],
          colocados: [_puesta('p1', 'z1', 0)],
        ),
        'stg',
      ).single.etiqueta,
      'Vista · 1 pedido · 12 kg',
      reason: 'con uno solo, «1 pedido», no «1 pedidos»',
    );
  });

  // ---------------------------------------------------------------------------
  // La lista de disponibles, acotada
  // ---------------------------------------------------------------------------

  test(
    'con zona elegida la lista queda sólo con sus pedidos y en su orden',
    () {
      final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
      final acotada = soloDeLaZona([
        _pedido('p1'),
        _pedido('p2'),
        _pedido('p3'),
        _pedido('p7'),
        _pedido('p8'),
      ], zona);

      expect(
        acotada.map((p) => p.id),
        ['p3', 'p1', 'p2'],
        reason: 'el orden de la zona es el de visita que propuso el logístico',
      );
    },
  );

  test('sin zona elegida la lista es exactamente la de siempre', () {
    // La pareja. El tablero es opcional: quien no lo use no puede perder la
    // lista completa por que exista este filtro.
    final todos = [_pedido('p1'), _pedido('p7'), _pedido('p8')];

    expect(soloDeLaZona(todos, null), same(todos));
  });

  test('lo que está en la zona y ya no se puede repartir no se inventa', () {
    final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
    // `p1` se lo llevó otra ruta entre que se armó el tablero y ahora.
    final acotada = soloDeLaZona([_pedido('p3'), _pedido('p2')], zona);

    expect(acotada.map((p) => p.id), ['p3', 'p2']);
  });

  // ---------------------------------------------------------------------------
  // El camión
  // ---------------------------------------------------------------------------

  final flota = [_camion('v-hab', 'Vehiculo HAB'), _camion('v-350', 'F-350')];

  test('sin camión elegido, la zona trae el suyo', () {
    final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
    final r = camionDeLaZona(
      zona: zona,
      elegidoId: null,
      elegidoNombre: null,
      elegidoAMano: false,
      vehiculosDeLaRuta: flota,
    );

    expect(r.vehiculoId, 'v-hab');
    expect(r.cambia, isTrue);
    expect(r.choca, isFalse);
    expect(r.parte, contains('Vehiculo HAB'));
  });

  test('una zona SIN camión no toca el que estuviera elegido', () {
    // La pareja de la de arriba, y la que impide el peor atajo: «la zona manda»
    // borraría un camión elegido a cambio de un «todavía no se sabe».
    final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').last;
    final r = camionDeLaZona(
      zona: zona,
      elegidoId: 'v-350',
      elegidoNombre: 'F-350',
      elegidoAMano: true,
      vehiculosDeLaRuta: flota,
    );

    expect(r.vehiculoId, 'v-350');
    expect(r.cambia, isFalse);
    expect(r.choca, isFalse);
    expect(r.parte, isNull);
  });

  test('el camión elegido A MANO se cambia, pero NUNCA en silencio', () {
    // Al paso 4 no se llega sin camión —el paso 3 no deja pasar sin uno—, así
    // que aquí siempre hay uno puesto a mano. Una regla de «lo que puso la
    // persona no se toca» dejaría el camión de la zona sin traerse jamás, que
    // es justo lo que Jose pidió. Se cambia, y se dice, con vuelta atrás.
    final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
    final r = camionDeLaZona(
      zona: zona,
      elegidoId: 'v-350',
      elegidoNombre: 'F-350',
      elegidoAMano: true,
      vehiculosDeLaRuta: flota,
    );

    expect(r.vehiculoId, 'v-hab', reason: 'el camión preparado de la zona');
    expect(r.cambia, isTrue);
    expect(r.choca, isTrue, reason: 'hay que decirlo');
    expect(r.devuelve, 'v-350', reason: 'para el botón de «Dejar el mío»');
    // Los DOS nombres: un aviso que no dice cuál es cuál obliga a abrir el paso
    // 3 y el tablero para entenderlo.
    expect(r.parte, contains('Vehiculo HAB'));
    expect(r.parte, contains('F-350'));
    expect(r.parte, contains('Vista'));
  });

  test('el camión que trajo una zona anterior se cambia sin decir nada', () {
    // La pareja de la de arriba: lo que separa las dos es quién lo puso. Éste
    // no era la decisión de nadie, así que no hay nada que advertir ni nada que
    // deshacer.
    final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
    final r = camionDeLaZona(
      zona: zona,
      elegidoId: 'v-350',
      elegidoNombre: 'F-350',
      elegidoAMano: false,
      vehiculosDeLaRuta: flota,
    );

    expect(r.vehiculoId, 'v-hab');
    expect(r.cambia, isTrue);
    expect(r.choca, isFalse);
    expect(r.devuelve, isNull);
  });

  test('el mismo camión no dice nada ni cambia nada', () {
    final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
    final r = camionDeLaZona(
      zona: zona,
      elegidoId: 'v-hab',
      elegidoNombre: 'Vehiculo HAB',
      elegidoAMano: true,
      vehiculosDeLaRuta: flota,
    );

    expect(r.vehiculoId, 'v-hab');
    expect(r.cambia, isFalse);
    expect(r.choca, isFalse);
    expect(r.parte, isNull);
  });

  test(
    'un camión previsto que no es de esta sucursal no se trae, y se dice',
    () {
      // Un camión de Granma en una ruta de La Habana es un camión que no está
      // donde sale la ruta; y el selector del paso 3 no podría ni enseñarlo.
      final zona = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
      final r = camionDeLaZona(
        zona: zona,
        elegidoId: 'v-350',
        elegidoNombre: 'F-350',
        elegidoAMano: false,
        vehiculosDeLaRuta: [_camion('v-350', 'F-350')],
      );

      expect(r.vehiculoId, 'v-350');
      expect(r.cambia, isFalse);
      expect(r.choca, isFalse);
      expect(r.parte, contains('no es de esta sucursal'));
    },
  );

  // ---------------------------------------------------------------------------
  // El desplegable
  // ---------------------------------------------------------------------------

  Future<void> montarSelector(
    WidgetTester tester, {
    required List<ZonaParaArmar> zonas,
    required void Function(ZonaParaArmar?) alElegir,
    String? zonaId,
  }) async {
    // A 1200 px, Y HAY QUE PONERLO A MANO.
    //
    // Un `testWidgets` sin tocar `tester.view` mide **800x600**, que está POR
    // DEBAJO de `Anchos.escritorio` (1024). Desde el 28/09/2026 el `Selector`
    // del kit —el que hay debajo de este selector de zona— abre un CAJÓN por
    // debajo de ese corte, y allí las opciones son `ListTile` y no
    // `MenuItemButton`. Estas tres pruebas no van del ancho: van de qué ofrece
    // el desplegable y de qué devuelve al elegir, así que se quedan midiendo el
    // menú de escritorio, que es donde se escribieron.
    //
    // Que el mismo desplegable sea cajón en el teléfono lo vigila
    // `test/diseno/el_selector_del_kit_es_cajon_test.dart`, en pareja 390/1200.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [zonasParaArmarProvider('stg').overrideWithValue(zonas)],
        child: MaterialApp(
          home: Scaffold(
            body: SelectorDeZonaDelTablero(
              sucursalId: 'stg',
              zonaId: zonaId,
              alElegir: alElegir,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// El botón cerrado enseña la opción elegida —«Todas las zonas» o la zona—,
  /// así que abrirlo por su texto sería abrirlo por lo que se está midiendo.
  Future<void> abrir(WidgetTester tester) async {
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
  }

  testWidgets('el desplegable enseña cada zona con lo que lleva y su camión', (
    tester,
  ) async {
    await montarSelector(
      tester,
      zonas: zonasParaArmar(_tableroDeSantiago(), 'stg'),
      alElegir: (_) {},
    );

    await abrir(tester);

    expect(
      find.widgetWithText(MenuItemButton, 'Vista · 3 pedidos · 340 kg'),
      findsOneWidget,
    );
    expect(find.text('Camión: Vehiculo HAB'), findsOneWidget);
    expect(
      find.widgetWithText(MenuItemButton, 'Carretera · 2 pedidos · 80 kg'),
      findsOneWidget,
    );
    expect(
      find.text('Sin camión previsto'),
      findsOneWidget,
      reason: 'un hueco en blanco se lee como «no lo sé»',
    );
    expect(
      find.widgetWithText(MenuItemButton, SelectorDeZonaDelTablero.todas),
      findsOneWidget,
      reason: 'no filtrar por zona tiene que seguir siendo una opción',
    );
  });

  testWidgets('elegir una zona la devuelve entera, con su camión', (
    tester,
  ) async {
    ZonaParaArmar? elegida;
    var llamadas = 0;
    await montarSelector(
      tester,
      zonas: zonasParaArmar(_tableroDeSantiago(), 'stg'),
      alElegir: (z) {
        llamadas++;
        elegida = z;
      },
    );

    await abrir(tester);
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Vista · 3 pedidos · 340 kg'),
    );
    await tester.pumpAndSettle();

    expect(llamadas, 1);
    expect(elegida?.id, 'z1');
    expect(elegida?.ids, ['p3', 'p1', 'p2']);
    expect(elegida?.vehiculoId, 'v-hab');
  });

  testWidgets('volver a «todas las zonas» devuelve null', (tester) async {
    // La pareja: quitar el filtro tiene que ser tan fácil como ponerlo, y lo
    // que llega al asistente es «ninguna», no una zona vacía.
    ZonaParaArmar? elegida = zonasParaArmar(_tableroDeSantiago(), 'stg').first;
    var llamadas = 0;
    await montarSelector(
      tester,
      zonaId: 'z1',
      zonas: zonasParaArmar(_tableroDeSantiago(), 'stg'),
      alElegir: (z) {
        llamadas++;
        elegida = z;
      },
    );

    await abrir(tester);
    await tester.tap(
      find.widgetWithText(MenuItemButton, SelectorDeZonaDelTablero.todas),
    );
    await tester.pumpAndSettle();

    expect(llamadas, 1);
    expect(elegida, isNull);
  });

  testWidgets('sin zonas que ofrecer no se pinta ningún desplegable', (
    tester,
  ) async {
    // Un desplegable con una sola opción que no hace nada engaña: parece que
    // hay zonas preparadas y no las hay.
    await montarSelector(tester, zonas: const [], alElegir: (_) {});

    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text(SelectorDeZonaDelTablero.todas), findsNothing);
  });
}
