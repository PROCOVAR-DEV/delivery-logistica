// TRES COSAS DEL TABLERO QUE JOSE PIDIÓ EL 28/09/2026, atadas aquí.
//
// Las tres salen del mismo sitio —las opciones de una zona y el cajón de mover
// una tarjeta— y las tres son de lo mismo: **que la pantalla no te haga perder
// el tiempo ni te saque de donde estabas**.
//
//  1. «ahi en tablero q cuando le den para mover en ves de solo decir q lo vamos
//     a mover q me salga el detalle de el pedido ok». El cajón de mover enseñaba
//     «cliente · peso · km» y nada más, y ése es el instante en el que alguien
//     decide A QUÉ ZONA va ese bulto: para decidirlo hay que saber qué bulto es.
//
//  2. «ya dio el error pero notifica el campo q hace falta para q relleno no le
//     cierres eso». El bloqueo de «ninguna ruta sin camión» funcionaba, pero el
//     botón hacía `Navigator.pop()` ANTES de intentar nada: el cajón se cerraba
//     pasara lo que pasara y el motivo salía abajo con la pantalla ya cambiada.
//     El aviso estaba y te sacaba del único sitio donde se arregla — «Camión
//     previsto» está en ese mismo cajón, dos dedos más arriba.
//
//  3. «y q cuando cree la ruta nueva por q no voy directo a la ruta por q pierdo
//     el tiempo demostrando q el tablero se vacio mi loco», y después: «q me
//     lleve directo a rutas con la nueva ruta creada con tablero».
//
// VAN POR LA PANTALLA ENTERA Y CON EL DEDO, como las de `el_camion_previsto_se_
// abre_test.dart`, y por el mismo motivo que está escrito allí: el camino que
// falla es el de quien lleva el teléfono, y una prueba que llamara a las
// acciones a pelo sale verde mientras la pantalla no abre nada.

import 'package:dio/dio.dart';
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
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart'
    show PestanaRutas;
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const _escritorio = Size(1400, 900);

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late ProviderContainer contenedor;

  // Aquí SÓLO se abre la base: sembrar en el `setUp` de un `testWidgets` es la
  // segunda trampa del §5 y cuelga la prueba en vez de fallarla.
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

  /// Pasadas cortas y contadas, para mirar con un cajón delante que todavía
  /// puede estar pintando una rueda: una rueda no se asienta nunca y
  /// `pumpAndSettle` moriría con «timed out», que dice dónde pero no qué.
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
    contenedor = ProviderContainer(
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
    );
    addTearDown(contenedor.dispose);
    return UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  Future<void> abrirElTableroEnCentro(
    WidgetTester tester, {
    bool conCamion = false,
  }) async {
    await tester.binding.setSurfaceSize(_escritorio);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await RepositorioTablero(
      base,
      ColaDeSalida(base),
    ).crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Centro',
      vehiculoId: conCamion ? 'v1' : null,
    );

    await tester.pumpWidget(montar());
    await asentar(tester);
  }

  // ---------------------------------------------------------------------------
  // 1. EL CAJÓN DE MOVER ENSEÑA EL PEDIDO
  // ---------------------------------------------------------------------------

  testWidgets('al mover una tarjeta se ve el DETALLE del pedido, no su nombre', (
    tester,
  ) async {
    await abrirElTableroEnCentro(tester);

    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Bodega La Esquina',
      direccion: 'Calle 4 esquina a 7',
    );
    await sembrarRenglon(
      base,
      id: 'i1',
      pedidoId: 'p1',
      descripcion: 'MALTA GUAJIRA 330 ML BLISTER 6U',
    );
    await pasadasCortas(tester);

    await tester.tap(find.text('Bodega La Esquina'));
    await pasadasCortas(tester);

    // LO QUE HABÍA ANTES seguía estando —el peso—, así que no se comprueba eso:
    // se comprueba lo que NO estaba y es lo que deja decidir la zona.
    // La dirección sale DOS veces y está bien: una en la tarjeta de debajo y
    // otra en el cajón. Lo que se comprueba es que está en el cajón, así que se
    // cuentan las dos y se exige que hayan aumentado.
    expect(
      find.textContaining('Calle 4 esquina a 7'),
      findsNWidgets(2),
      reason:
          'el cajón de mover no dice DÓNDE va el pedido, que es justo lo que '
          'decide a qué zona se mueve',
    );
    expect(
      find.textContaining('MALTA GUAJIRA 330 ML BLISTER 6U'),
      findsOneWidget,
      reason:
          'no se ven los artículos: es lo que se carga en el camión y lo único '
          'del detalle que no viajaba ya en la tarjeta',
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 2. EL «NO» DEL CAMIÓN SE QUEDA DENTRO DEL CAJÓN
  // ---------------------------------------------------------------------------

  testWidgets('sin camión, el «no» se dice DENTRO y el cajón NO se cierra', (
    tester,
  ) async {
    await abrirElTableroEnCentro(tester);
    await sembrarPedido(base, id: 'p1', cliente: 'Bodega La Esquina');
    await pasadasCortas(tester);
    await tester.tap(find.text('Bodega La Esquina'));
    await pasadasCortas(tester);
    await tester.tap(find.text('Colocar en «Centro»'));
    await pasadasCortas(tester);

    await tester.tap(find.byTooltip('Opciones de la columna'));
    await asentar(tester);
    await tester.tap(find.text('Armar la ruta de esta zona'));
    await pasadasCortas(tester);

    expect(
      find.byKey(const ValueKey('tablero-no-se-armo')),
      findsOneWidget,
      reason:
          'el motivo no está DENTRO del cajón. Si sale sólo en la franja de '
          'abajo con el cajón ya cerrado, saca a quien lo lee del único sitio '
          'donde se arregla — «Camión previsto» está aquí mismo',
    );
    expect(
      find.text('Camión previsto'),
      findsOneWidget,
      reason:
          'el cajón se cerró: era el `Navigator.pop()` puesto ANTES de intentar '
          'nada, que cerraba pasara lo que pasara',
    );
    expect(
      find.textContaining('Volver a intentarlo'),
      findsOneWidget,
      reason:
          'tras el «no» el botón tiene que decir que se reintenta; el mismo '
          'rótulo de antes se lee como que el botón está roto',
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 3. AL ARMAR, DERECHO A RUTAS Y CON ELLA ELEGIDA
  // ---------------------------------------------------------------------------

  testWidgets('al armar la ruta se elige esa ruta y se va a la pestaña suya', (
    tester,
  ) async {
    await sembrarCamion(base, id: 'v1', nombre: 'F-350', capacidad: 1500);
    await abrirElTableroEnCentro(tester, conCamion: true);
    await sembrarPedido(base, id: 'p1', cliente: 'Bodega La Esquina');
    await pasadasCortas(tester);

    await tester.tap(find.text('Bodega La Esquina'));
    await pasadasCortas(tester);
    await tester.tap(find.text('Colocar en «Centro»'));
    await pasadasCortas(tester);

    // Se deja la pestaña en `historial` a propósito: es el caso que engaña. Una
    // ruta recién armada nace PLANIFICADA, así que llegar a Rutas con la
    // pestaña de antes puesta deja una lista donde esa ruta no está, y eso se
    // lee como que no se creó.
    contenedor.read(pestanaRutasProvider.notifier).elegir(PestanaRutas.historial);

    await tester.tap(find.byTooltip('Opciones de la columna'));
    await asentar(tester);
    await tester.tap(find.text('Armar la ruta de esta zona'));
    await pasadasCortas(tester);

    expect(
      contenedor.read(rutaElegidaProvider),
      isNotNull,
      reason:
          'la ruta recién armada no quedó elegida: al llegar a Rutas no se ve '
          'la que se acaba de crear y hay que buscarla a mano',
    );
    expect(
      contenedor.read(pestanaRutasProvider),
      PestanaRutas.activas,
      reason:
          'se llega a Rutas con la pestaña de antes. Una ruta nueva nace '
          'PLANIFICADA: en «Historial» no está, y eso se lee como que no se creó',
    );

    await desmontar(tester);
  });
}
