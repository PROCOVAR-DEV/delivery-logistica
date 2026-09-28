// EL CAJON DE «MANDAR A UNA ZONA», PINTADO.
//
// Lo que un test de datos no puede ver: que el gesto EXISTA en la barra de lo
// marcado —que es la queja de Jose, «sigo sin ver, cuando escojo los pedidos,
// seleccionar un tablero»—, que se abra en cajón y no en modal, que su ✕ esté
// ahí, que sólo enseñe las zonas de la sucursal que se está mirando, y que al
// terminar diga qué pasó y la marca se vaya.
//
// ## LA TRAMPA QUE COSTO LA TARDE: SEMBRAR EN EL `setUp`
//
// Estas pruebas se colgaban —no fallaban, se colgaban— y el cajón se quedaba
// diciendo que no había ninguna zona encima de un tablero con dos. El motivo no
// estaba en el código del cajón: la base se sembraba en el `setUp`, que corre
// **fuera del reloj falso de `testWidgets`**. Lo que Drift deja empezado allí no
// avanza cuando la prueba ya está dentro, y la consulta de las zonas no termina
// jamás.
//
// La regla, que es pariente de la del `CLAUDE.md` §5: **en un `testWidgets`, la
// base se abre donde sea pero se ESCRIBE y se LEE dentro del cuerpo.** Por eso
// `preparar()` se llama en cada prueba y no en el `setUp`.
//
// Las dos primeras montan Pedidos entera —es la única manera de comprobar que el
// gesto está donde Jose lo buscaba y que el flujo completo funciona—; las demás
// montan el cajón solo, que es el mismo widget con los mismos providers y deja
// la prueba en lo que mira.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_mandar_al_tablero.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'sembrar.dart';

/// `pumpAndSettle` no vale: mientras una consulta está en vuelo se pinta un
/// indicador giratorio, que es una animación que no para nunca.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late ProviderContainer contenedor;

  /// OJO: aquí no se toca la base, sólo se abre.
  ///
  /// Todo lo que ESCRIBE o LEE de Drift va dentro del cuerpo de la prueba
  /// (`preparar`). Hacerlo en el `setUp` deja ese trabajo en otro reloj —el
  /// `setUp` corre fuera del tiempo falso de `testWidgets`— y las consultas que
  /// vienen después, ya dentro, no terminan nunca: el cajón se queda girando y
  /// la prueba falla diciendo que no encuentra ninguna zona.
  setUp(() {
    base = baseDePrueba();
    // SIN RED: cualquier petición que se escape falla como en la calle.
    servidor = ServidorFalso((peticion) async => null);
  });

  /// El catálogo y las tablas del tablero, ya dentro de la prueba.
  Future<void> preparar() async {
    await sembrarCatalogo(base);
    await EsquemaTablero.asegurar(base);
  }

  /// El contenedor con la sesión de un logístico de Camagüey (`B1`).
  ProviderContainer montarContenedor() {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.invalido'))
      ..httpClientAdapter = servidor;
    return ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: 'B1',
            ),
          ),
        ),
      ],
    );
  }

  /// Monta [que] con [marcados] ya marcados.
  ///
  /// La marca se pone ANTES de pintar, que es como llega de verdad: quien abre
  /// el cajón ya venía de marcar en la lista.
  Future<void> pintar(
    WidgetTester tester,
    Widget que, {
    List<String> marcados = const <String>[],
    String? mirando,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    contenedor = montarContenedor();
    if (mirando != null) {
      contenedor.read(sucursalMiradaProvider.notifier).mirar(mirando);
    }
    if (marcados.isNotEmpty) {
      contenedor
          .read(seleccionPedidosProvider.notifier)
          .marcarPagina(marcados, marcar: true);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        // Las pantallas ya no traen `Scaffold` propio: lo pone el armazón.
        child: MaterialApp(home: Scaffold(body: que)),
      ),
    );
    await asentar(tester);
  }

  /// Desmontar, tirar el contenedor y cerrar la base — TODO DENTRO DEL CUERPO
  /// de la prueba, y en ese orden.
  ///
  /// Cerrar la base en un `tearDown` cuelga la prueba en vez de fallarla: allí
  /// el reloj del test ya no corre y `close()` se queda esperando un trabajo de
  /// Drift que nadie va a mover. Y el `pump` de en medio es el fotograma que
  /// necesitan los `watch()` que se están cerrando: sin él, el marco de pruebas
  /// cuenta un temporizador pendiente.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    contenedor.dispose();
    await tester.pump(Duration.zero);
    await base.close();
  }

  /// Una zona ya bajada, escrita como la escribe la foto del servidor.
  Future<void> sembrarZona(String id, String nombre, String sucursal) =>
      base.customStatement(
        'INSERT INTO ${EsquemaTablero.columnas} '
        '(id, branch_id, nombre, posicion) VALUES (?1, ?2, ?3, 1)',
        [id, sucursal, nombre],
      );

  Future<void> marcar(WidgetTester tester, List<String> ids) async {
    contenedor
        .read(seleccionPedidosProvider.notifier)
        .marcarPagina(ids, marcar: true);
    await asentar(tester);
  }

  // ---------------------------------------------------------------------------
  // EL GESTO, DONDE JOSE LO BUSCABA
  // ---------------------------------------------------------------------------

  testWidgets(
    'con pedidos marcados hay un gesto para mandarlos a una zona, y abre un '
    'cajón con su ✕',
    (tester) async {
      await preparar();
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Ana',
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarZona('z-cam', 'Centro', 'B1');
      await pintar(tester, const PantallaPedidos());

      // Sin nada marcado no hay barra: el gesto aparece con la marca.
      expect(find.text(PantallaPedidos.mandarAUnaZona), findsNothing);

      await marcar(tester, const ['o1']);

      expect(find.text(PantallaPedidos.mandarAUnaZona), findsOneWidget);
      await tester.tap(find.text(PantallaPedidos.mandarAUnaZona));
      await asentar(tester);

      expect(find.text(CajonMandarAlTablero.titulo), findsOneWidget);
      // La ✕ vive fuera del cuerpo desplazable y no se puede ir de la vista.
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      // Cajón, no modal: nada de `AlertDialog` centrado (`CLAUDE.md` §4).
      expect(find.byType(AlertDialog), findsNothing);

      await cerrar(tester);
    },
  );

  // ---------------------------------------------------------------------------
  // EL CAJON
  // ---------------------------------------------------------------------------

  testWidgets(
    'con Camagüey mirada, en el cajón no sale ninguna zona de otra sucursal',
    (tester) async {
      await preparar();
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Ana',
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarZona('z-cam', 'Centro', 'B1');
      await sembrarZona('z-hol', 'Reparto Peralta', 'B2');
      await pintar(
        tester,
        const CajonMandarAlTablero(),
        marcados: const ['o1'],
        mirando: 'B1',
      );

      expect(find.text('Centro'), findsOneWidget);
      expect(
        find.text('Reparto Peralta'),
        findsNothing,
        reason: 'un pedido de Camagüey no puede acabar en una zona de Holguín',
      );

      await cerrar(tester);
    },
  );

  testWidgets(
    'se manda lo marcado, se dice qué pasó con lo que no pudo ir y la marca se '
    'quita',
    (tester) async {
      await preparar();
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Ana',
        folio: 'F-2992',
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarPedido(
        base,
        id: 'o5',
        cliente: 'Eva',
        folio: 'F-ARCH',
        archivado: true,
        endLat: 21.38,
        endLng: -77.91,
      );
      await sembrarZona('z-cam', 'Centro', 'B1');
      // LA PANTALLA ENTERA, de punta a punta: se marca, se abre el cajón desde
      // la barra de lo marcado y se manda. Es el camino de Jose.
      await pintar(
        tester,
        const PantallaPedidos(),
        marcados: const ['o1', 'o5'],
      );
      await tester.tap(find.text(PantallaPedidos.mandarAUnaZona));
      await asentar(tester);

      // Sin zona elegida no se manda nada: el botón está apagado.
      //
      // Se busca por `BotonPrincipal` y no por `ElevatedButton` desde el
      // 28/09/2026: el mando sigue siendo el mismo y sigue siendo de nivel
      // principal, pero ahora entra por el widget que **le obliga a llevar su
      // icono** (`diseno/tema.dart`). El icono es uno de los tres rasgos que
      // separan un botón de otro cuando no hay relleno detrás.
      expect(
        tester
            .widget<BotonPrincipal>(
              find.widgetWithText(BotonPrincipal, CajonMandarAlTablero.mandar),
            )
            .alPulsar,
        isNull,
      );

      await tester.tap(find.text('Centro'));
      await asentar(tester);
      await tester.tap(find.text(CajonMandarAlTablero.mandar));
      await asentar(tester);

      // Cuántos fueron, y a dónde.
      expect(find.text('1 pedido(s) en «Centro»'), findsOneWidget);
      // Y el que no pudo, NOMBRADO y con su motivo. Nada se descarta en
      // silencio (`CLAUDE.md` §4).
      expect(
        find.text('F-ARCH · Eva: Archivado en PEDIDO'),
        findsOneWidget,
        reason:
            'una lista de dos que produce una zona de uno tiene que decir cuál '
            'se cayó y por qué',
      );

      // La marca del que fue se quitó; el que se quedó sigue marcado, para
      // poder hacer algo con él.
      expect(contenedor.read(seleccionPedidosProvider), {'o5'});

      await cerrar(tester);
    },
  );

  testWidgets('se puede crear una zona nueva desde el propio cajón', (
    tester,
  ) async {
    await preparar();
    await sembrarPedido(
      base,
      id: 'o1',
      cliente: 'Ana',
      endLat: 21.38,
      endLng: -77.91,
    );
    await pintar(tester, const CajonMandarAlTablero(), marcados: const ['o1']);

    // Sin ninguna zona, la caja del nombre sale sola: es el caso del primer
    // día, y mandar a «ninguna zona» no es una opción.
    expect(find.text(CajonMandarAlTablero.sinZonas), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Vista Alegre');
    await tester.tap(find.text(CajonMandarAlTablero.crear));
    await asentar(tester);

    await tester.tap(find.text(CajonMandarAlTablero.mandar));
    await asentar(tester);

    expect(find.text('1 pedido(s) en «Vista Alegre»'), findsOneWidget);
    expect(contenedor.read(seleccionPedidosProvider), isEmpty);

    await cerrar(tester);
  });

  // ---------------------------------------------------------------------------
  // LA REGLA DEL §3-ter: LO QUE LLEGA DESPUES
  // ---------------------------------------------------------------------------

  testWidgets(
    'las zonas que llegan DESPUES de abrir el cajón salen solas, sin volver a '
    'abrirlo',
    (tester) async {
      await preparar();
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Ana',
        endLat: 21.38,
        endLng: -77.91,
      );
      // Se monta con la base VACIA de zonas y se siembra DESPUES, que es la
      // única forma de la prueba que caza un `Future` congelado (`CLAUDE.md`
      // §3-ter). En la web la base nace vacía en cada carga y el tablero baja
      // un segundo más tarde.
      await pintar(
        tester,
        const CajonMandarAlTablero(),
        marcados: const ['o1'],
      );
      expect(find.text(CajonMandarAlTablero.sinZonas), findsOneWidget);

      await sembrarZona('z-cam', 'Centro', 'B1');
      EsquemaTablero.avisarDeCambio(base);
      await asentar(tester);

      expect(
        find.text('Centro'),
        findsOneWidget,
        reason: 'la lista de zonas es un stream: se entera de la bajada',
      );

      await cerrar(tester);
    },
  );
}
