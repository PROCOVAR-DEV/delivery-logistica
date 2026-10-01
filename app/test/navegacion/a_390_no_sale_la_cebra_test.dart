// A 390 PX NO SE SALE NADA. Medido, no leído.
//
// Los tres sitios donde Jose vio la cebra amarilla y negra en su teléfono
// —1080x2340 físicos, o sea **390 px lógicos**— eran tres pantallas distintas
// con UN solo culpable: la barra superior del armazón, que sale en las siete.
// Por eso hay una prueba por cada sitio donde se vio y no una sola: si mañana el
// desborde vuelve por otro camino —una tarjeta del Panel, un filtro de
// Pedidos—, el que falla dice en qué pantalla mirar.
//
// LO QUE SE MIDE. Un desborde no rompe nada que un `findsOneWidget` pueda ver:
// el texto está en el árbol, con su literal exacto, y la pantalla «funciona».
// Lo único que lo delata es que la suma de los hijos de una fila sea mayor que
// la fila. Flutter lo marca en el propio objeto de pintura (`OVERFLOWING`), y
// eso es lo que se barre aquí: TODO el árbol, no un widget elegido a mano,
// porque el que se salga mañana no va a ser el que uno esté mirando hoy.
//
// LOS DATOS SON LOS DE PRODUCCIÓN, y sin ellos esto no falla. Con la base vacía
// la barra cabe de sobra: el selector de sucursal no se pinta —no hay ninguna—,
// y la moneda es la pastilla corta. El desborde aparece con las OCHO sucursales,
// una elegida —ahí la caja llega a su tope— y la moneda en CUP con la tasa del
// 9 de septiembre, que Accesos da por vieja y añade su reloj de aviso. Sumaban
// 376,9 px en una barra de 366: casi once de más, y lo que se comía era el
// avatar, o sea el menú de la cuenta y «Salir».
//
// NADA DE `ClipRect` para taparlo, ni de bajar la letra: lo que se arregló es
// que el grupo de la derecha sepa cuánto sitio hay (`barra_superior.dart`), y lo
// que se acorta cuando no llega es la ETIQUETA de la sucursal, con sus puntos
// suspensivos. La sucursal y la moneda no se esconden nunca (§11): son las que
// cambian los números.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/banner_de_gesto.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/registro.dart';
import 'package:reparto/pantallas/panel/registro.dart';
import 'package:reparto/pantallas/panel/vista/estado_del_dia.dart';
import 'package:reparto/pantallas/pedidos/registro.dart';

import '../apoyo/base_de_prueba.dart';
import '../pantallas/pedidos/sembrar.dart';

/// El teléfono de Jose en píxeles lógicos.
const anchoDelTelefono = 390.0;
const altoDelTelefono = 844.0;

/// Las ocho de verdad, con sus nombres de verdad: «Santiago de Cuba» es lo que
/// llena la caja del selector, y con «B1» no se llena.
const _lasOcho = <String, String>{
  'CAM': 'Camagüey',
  'GR': 'Granma',
  'GTO': 'Guantánamo',
  'HAB': 'La Habana',
  'HOL': 'Holguín',
  'SS': 'Sancti Spíritus',
  'STG': 'Santiago de Cuba',
  'TUN': 'Las Tunas',
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Las ocho sucursales con la tasa del 9 de septiembre, que es la que hay en
  /// producción y la que Accesos marca como NO fresca: eso es lo que enciende el
  /// reloj de aviso al lado de la moneda.
  Future<void> sembrarLasOchoSucursales() async {
    var i = 0;
    for (final s in _lasOcho.entries) {
      await base
          .into(base.branches)
          .insert(
            BranchesCompanion.insert(
              id: 'S${i++}',
              name: s.value,
              lat: 20,
              lng: -77,
              externalId: Value(s.key),
              cupRate: const Value(700),
              cupRateTraidoAt: Value(DateTime(2026, 9, 9, 22)),
              cupRateFresca: const Value(false),
              cupRateFuente: const Value('auth'),
            ),
          );
    }
  }

  /// Barre el árbol entero buscando lo que se sale. Nombra el widget y la cadena
  /// de quién lo creó: «se sale» sin decir dónde no sirve de nada.
  void nadaSeSale(WidgetTester tester, String donde) {
    final culpables = <String>[];
    for (final r in tester.allRenderObjects) {
      if (!r.toStringShort().contains('OVERFLOWING')) continue;
      final creador = r.debugCreator;
      culpables.add(
        '${r is RenderBox ? r.size : '?'} — '
        '${creador is DebugCreator ? creador.element.debugGetCreatorChain(8) : r}',
      );
    }
    expect(
      culpables,
      isEmpty,
      reason:
          'A $anchoDelTelefono px, en $donde, hay ${culpables.length} '
          'pieza(s) saliéndose de la pantalla con la cebra amarilla y negra:\n'
          '${culpables.join('\n')}',
    );
  }

  /// Desmontar antes de acabar el cuerpo no es ceremonia: las consultas de Drift
  /// sueltan un temporizador al cancelarse y `flutter_test` lo comprueba ANTES
  /// de los `tearDown`. Sin esto, el primero se lleva por delante a los demás.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  /// Monta la aplicación a 390 px en la ruta que se le diga, con una sucursal
  /// elegida y la moneda en CUP: el estado en el que Jose lo vio.
  Future<void> montar(
    WidgetTester tester, {
    required String inicial,
    required List<PantallaRegistrada> pantallas,
  }) async {
    tester.view.physicalSize = const Size(anchoDelTelefono, altoDelTelefono);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(pantallas: pantallas, inicial: inicial),
        ),
      ),
    );
    await tester.pump();

    final contenedor = ProviderScope.containerOf(
      tester.element(find.byType(RepartoApp)),
    );
    // Santiago, que es la que llena la caja, y CUP, que es donde sale el reloj
    // de la tasa vieja.
    contenedor.read(sucursalMiradaProvider.notifier).mirar('S6');
    contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');
    await tester.pumpAndSettle();
  }

  testWidgets('/orders con los filtros por defecto no saca la cebra', (
    tester,
  ) async {
    await sembrarLosOnce(base);
    await sembrarLasOchoSucursales();

    await montar(
      tester,
      inicial: '/orders',
      pantallas: [registrarPanel(), registrarPedidos(), registrarInformes()],
    );

    nadaSeSale(tester, '/orders con los filtros por defecto');
    await desmontar(tester);
  });

  testWidgets('el Panel con «Estado del día» montado no saca la cebra', (
    tester,
  ) async {
    await sembrarLosOnce(base);
    await sembrarLasOchoSucursales();

    await montar(
      tester,
      inicial: '/dashboard',
      pantallas: [registrarPanel(), registrarPedidos(), registrarInformes()],
    );

    // La pieza tiene que estar puesta: sin ella esta prueba mediría otra
    // pantalla. En la web no se monta —allí no hay día que traer a mano— y por
    // eso el caso es el de la APK y el escritorio, que es lo que corre aquí.
    expect(find.byType(EstadoDelDia), findsOneWidget);
    expect(find.byType(BannerDeGesto), findsOneWidget);

    nadaSeSale(tester, 'el Panel con EstadoDelDia dentro de BannerDeGesto');
    await desmontar(tester);
  });

  testWidgets(
    'el armazón con más de una pantalla registrada no saca la cebra',
    (tester) async {
      await sembrarLasOchoSucursales();

      // Dos de mentira: aquí se mide el armazón, no lo que cada pantalla pinte
      // dentro. Con una sola no habría menú que abrir.
      final dePrueba = <PantallaRegistrada>[
        PantallaRegistrada(
          ruta: '/uno',
          titulo: 'Uno',
          icono: Icons.looks_one_outlined,
          enElMenu: true,
          colecciones: ColeccionesDePantalla.panel,
          construir: (contexto, estado) => const Text('cuerpo de uno'),
        ),
        PantallaRegistrada(
          ruta: '/dos',
          titulo: 'Dos',
          icono: Icons.looks_two_outlined,
          enElMenu: true,
          colecciones: ColeccionesDePantalla.panel,
          construir: (contexto, estado) => const Text('cuerpo de dos'),
        ),
      ];

      await montar(tester, inicial: '/uno', pantallas: dePrueba);
      nadaSeSale(tester, 'el armazón con dos pantallas registradas');

      // Y con el cajón del menú abierto, que es la otra mitad del armazón en un
      // teléfono: la barra lateral vive ahí y no se mide hasta que se abre.
      await tester.tap(find.byTooltip('Menú'));
      await tester.pumpAndSettle();
      nadaSeSale(tester, 'el armazón con el cajón del menú abierto');

      await desmontar(tester);
    },
  );
}
