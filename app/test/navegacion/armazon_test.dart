import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/barra_lateral.dart';
import 'package:reparto/navegacion/barra_superior.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/navegacion/menu_de_cuenta.dart';
import 'package:reparto/nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../apoyo/base_de_prueba.dart';

/// Dos pantallas de mentira: el armazon se prueba solo, sin arrastrar el Panel
/// ni los Informes a un test de navegacion.
///
/// `colecciones: panel` —o sea las nueve— porque es lo que mide la franja cuando
/// nadie recorta nada, y es con lo que estan escritas las comprobaciones de aqui
/// («Sin descargar todavia» sobre una base vacia). Lo que una pantalla de verdad
/// declara y lo que la franja hace con ello se prueba aparte, en
/// `test/nucleo/frescura/la_franja_mide_lo_de_su_pantalla_test.dart`.
List<PantallaRegistrada> _dePrueba() => <PantallaRegistrada>[
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
    // ESTA DECLARA OTRA LISTA a proposito, y es lo unico que permite comprobar
    // que el armazon le pasa a la franja las colecciones **de la pantalla en la
    // que se esta**. Con las dos iguales, esa prueba saldria verde con el cable
    // cortado.
    colecciones: ColeccionesDePantalla.clientes,
    construir: (contexto, estado) => const Text('cuerpo de dos'),
  ),
  PantallaRegistrada(
    ruta: '/escondida',
    titulo: 'Escondida',
    colecciones: ColeccionesDePantalla.panel,
    construir: (contexto, estado) => const Text('cuerpo escondido'),
  ),
];

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> montar(
    WidgetTester tester,
    Size tamano, {
    bool actualizando = false,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
          if (actualizando) actualizandoProvider.overrideWith((ref) => true),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(pantallas: _dePrueba(), inicial: '/uno'),
        ),
      ),
    );
    // Con algo en vuelo hay una rueda girando, que es una animacion sin fin:
    // `pumpAndSettle` la esperaria para siempre. Dos pasadas bastan para que la
    // pantalla este montada.
    if (actualizando) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    } else {
      await tester.pumpAndSettle();
    }
  }

  /// Desmontar antes de que acabe el cuerpo del test no es ceremonia: las
  /// consultas de Drift que alimentan la franja de estado sueltan un temporizador
  /// al cancelarse, y flutter_test comprueba que no queda ninguno ANTES de los
  /// `tearDown`. Sin esto, el primer test deja el temporizador y se lleva por
  /// delante a todos los demas.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Dos pasadas: la primera desmonta y crea el temporizador de cierre de
    // Drift, la segunda lo deja correr.
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('escritorio: la barra lateral esta fija y no hay boton de menu', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 900));

    expect(find.byType(BarraLateral), findsOneWidget);
    expect(find.byTooltip('Menú'), findsNothing);
    expect(find.text('Uno'), findsWidgets); // titulo + entrada del menu
    expect(find.text('cuerpo de uno'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('movil: la barra se sale de la pantalla y la abre el boton', (
    tester,
  ) async {
    await montar(tester, const Size(390, 800));

    // Fuera de pantalla: el cajon no esta montado hasta que se abre.
    expect(find.byType(BarraLateral), findsNothing);
    expect(find.byTooltip('Menú'), findsOneWidget);

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    expect(find.byType(BarraLateral), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('movil: al elegir una entrada navega Y el cajon se cierra solo', (
    tester,
  ) async {
    await montar(tester, const Size(390, 800));

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dos'));
    await tester.pumpAndSettle();

    expect(find.text('cuerpo de dos'), findsOneWidget);
    // Si el cajon se quedara abierto taparia justo la pantalla a la que se
    // acaba de ir (§8.1).
    expect(find.byType(BarraLateral), findsNothing);
    await desmontar(tester);
  });

  // LA OTRA MITAD DE ESTA PRUEBA VIVE EN `test/la_web_no_se_prepara_test.dart`.
  //
  // Aqui no se sustituye `trabajaSinConexionProvider`, asi que esto corre en el
  // destino de siempre: **la APK y el escritorio**, donde la franja tiene que
  // estar. En web NO va —alli no hay dia que traer a mano— y eso se comprueba
  // alli, en pareja con esta. Las dos juntas son las que fijan la linea; una
  // sola se cumpliria igual borrando la pieza entera.
  testWidgets('la franja de estado esta arriba en las DOS anchuras', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 900));
    expect(find.byType(FranjaDeEstado), findsOneWidget);
    // Base vacia = nunca se bajo nada. Eso se dice, no se calla.
    expect(find.text('Sin descargar todavía'), findsOneWidget);

    await montar(tester, const Size(390, 800));
    expect(find.byType(FranjaDeEstado), findsOneWidget);
    expect(find.text('Sin descargar todavía'), findsOneWidget);
    await desmontar(tester);
  });

  /// LA FRANJA SE MIDE CONTRA LAS COLECCIONES DE SU PANTALLA — 01/10/2026.
  ///
  /// El armazon es el unico que sabe en que pantalla estamos, asi que es el que
  /// se lo pasa. Si ese cable se corta, la franja se queda con su valor por
  /// defecto —las nueve— y vuelve el caso de aquel dia: «Datos de las 8:46»
  /// encima de una pantalla al dia a las 9:07, porque los almacenes se refrescan
  /// una vez por hora a proposito.
  ///
  /// Se comprueba en las DOS pantallas y navegando de una a otra: con una sola,
  /// cualquier valor fijo pasaria.
  testWidgets('la franja recibe las colecciones de la pantalla que hay debajo', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 900));

    List<String> loQueMideLaFranja() => tester
        .widget<FranjaDeEstado>(find.byType(FranjaDeEstado))
        .colecciones;

    expect(
      loQueMideLaFranja(),
      ColeccionesDePantalla.panel,
      reason: '/uno declara las nueve',
    );

    await tester.tap(find.text('Dos'));
    await tester.pumpAndSettle();
    expect(find.text('cuerpo de dos'), findsOneWidget);

    expect(
      loQueMideLaFranja(),
      ColeccionesDePantalla.clientes,
      reason:
          'la franja se quedo midiendo lo de la pantalla anterior —o lo de todas—: '
          'el armazon no le esta pasando `PantallaRegistrada.colecciones`, y '
          'entonces la hora de arriba no es la de lo que se esta viendo',
    );

    await desmontar(tester);
  });

  testWidgets('el grupo de la derecha de la barra llega al borde', (
    tester,
  ) async {
    // Esto se vio a simple vista en un monitor ancho y no lo cazo ninguna
    // prueba: la sucursal, la moneda y el avatar salian flotando en MITAD de la
    // barra. La causa era un `Flexible` con el titulo y un `Spacer` detras, los
    // dos con el mismo peso, asi que el sobrante se repartia a medias y el
    // empujon solo llegaba hasta el centro. En un telefono no se nota porque
    // alli no sobra hueco: por eso se prueba ANCHO.
    await montar(tester, const Size(1440, 900));

    final barra = tester.getRect(find.byType(BarraSuperior));
    final avatar = tester.getRect(find.byType(MenuDeCuenta));

    // El avatar es lo ultimo de la fila: su borde derecho tiene que quedar
    // pegado al de la barra, salvo el relleno de 12 px y el del propio boton.
    expect(
      barra.right - avatar.right,
      lessThan(24),
      reason:
          'el grupo de la derecha se quedo a ${barra.right - avatar.right} px '
          'del borde: vuelve a estar flotando en vez de en su esquina',
    );

    await desmontar(tester);
  });

  testWidgets('«actualizando…» lo dice la barra superior, y SÓLO ella', (
    tester,
  ) async {
    // Este caso vivia en `test/nucleo/frescura/reloj_test.dart`, cuando el
    // reloj de datos tambien lo decia. El resultado en pantalla eran DOS ruedas
    // girando a la vez —una junto al titulo y otra en la franja de debajo—
    // diciendo lo mismo. El sitio es la barra superior, como en la de Next
    // (`Navbar.tsx`), y es el unico. Lo que se comprueba aqui son las dos
    // mitades: que la barra lo dice y que la franja no.
    await montar(tester, const Size(1440, 900), actualizando: true);

    expect(find.text('actualizando…'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BarraSuperior),
        matching: find.text('actualizando…'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(FranjaDeEstado),
        matching: find.text('actualizando…'),
      ),
      findsNothing,
    );
    // Y la franja sigue diciendo lo suyo: de que hora son los datos.
    expect(find.text('Sin descargar todavía'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('lo que queda sin subir se ve arriba, con su numero', (
    tester,
  ) async {
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: '01J8AAAA',
            hechoAt: DateTime(2026, 9, 14, 7),
            metodo: 'POST',
            ruta: '/api/routes',
            cuerpo: '{}',
          ),
        );

    await montar(tester, const Size(390, 800));
    expect(find.text('1 sin subir'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('una pantalla fuera del menu se alcanza por URL', (tester) async {
    final enrutador = crearEnrutador(
      pantallas: _dePrueba(),
      inicial: '/escondida',
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
        ],
        child: RepartoApp(enrutador: enrutador),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('cuerpo escondido'), findsOneWidget);
    // Esta y no sale en la barra lateral: es lo que hace Reportes.
    expect(
      find.descendant(
        of: find.byType(BarraLateral),
        matching: find.text('Escondida'),
      ),
      findsNothing,
    );
    await desmontar(tester);
  });
}
