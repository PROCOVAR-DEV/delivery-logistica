// MARCAR VARIAS FACTURAS Y COLOCARLAS DE UNA VEZ (issue 21 de Maikel, Santiago).
//
// «Cuando son los municipios es poco práctico añadir de 1 en 1.» Se marcan
// casillas en «Sin colocar» —o «marcar todas» las que se ven, con los filtros
// puestos— y se mandan a una zona con el mismo gesto de `MandarAlTablero`.
//
// Lo que se fija:
//  * «marcar todas» marca SÓLO las visibles (el filtro de municipio manda);
//  * se colocan de una vez y se dice cuántas;
//  * lo que no se puede colocar sale NOMBRADO con su motivo, sigue marcado y
//    no frena a las demás (nunca en silencio, `CLAUDE.md` §4);
//  * en la web un «no» del servidor a una factura no aborta el lote.
//
// Por la pantalla entera y con el dedo, como `el_cajon_de_mover_y_el_no_del_
// camion_test.dart`: una prueba que llamara a las acciones a pelo saldría verde
// con una pantalla que no abre nada.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart'
    show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/pedidos/datos/mandar_al_tablero.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late ProviderContainer contenedor;

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
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
    );
    addTearDown(contenedor.dispose);
    return UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// Tablero con zona «Centro» y tres facturas: dos de Santiago y una de Palma.
  Future<void> abrir(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await RepositorioTablero(
      base,
      ColaDeSalida(base),
    ).crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
    await sembrarPedido(base, id: 'p1', cliente: 'Ana', aGrados: 0.01);
    await sembrarPedido(base, id: 'p2', cliente: 'Beto', aGrados: 0.02);
    await sembrarPedido(
      base,
      id: 'p3',
      cliente: 'Carla',
      aGrados: 0.03,
      municipio: 'Palma',
    );
    await tester.pumpWidget(montar());
    await asentar(tester);
    await pasadasCortas(tester);
  }

  Future<int> colocadasEn(String nombre) async {
    final tablero = await contenedor.read(tableroProvider.future);
    return tablero.columnas.firstWhere((c) => c.nombre == nombre).pedidos;
  }

  testWidgets('marcar todas y colocar: van las tres de una vez', (
    tester,
  ) async {
    await abrir(tester);
    expect(find.text('Marcar las 3 que se ven'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('marcar-todas')));
    await pasadasCortas(tester);
    expect(find.text('3 marcadas'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('colocar-marcadas')));
    await pasadasCortas(tester);
    await tester.tap(find.text('Colocar en «Centro»'));
    await pasadasCortas(tester);

    expect(find.text('3 facturas en «Centro»'), findsOneWidget);
    expect(await colocadasEn('Centro'), 3);
    expect(find.text('Ninguna factura con estos filtros.'), findsNothing);
    expect(find.text('No queda ninguna factura por colocar.'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('con el filtro de municipio, «marcar todas» marca SÓLO las que '
      'se ven', (tester) async {
    await abrir(tester);
    contenedor
        .read(filtrosTableroProvider.notifier)
        .poner(const FiltrosSinColocar(municipio: 'Palma'));
    await pasadasCortas(tester);
    expect(find.text('Marcar las 1 que se ven'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('marcar-todas')));
    await pasadasCortas(tester);
    await tester.tap(find.byKey(const ValueKey('colocar-marcadas')));
    await pasadasCortas(tester);
    await tester.tap(find.text('Colocar en «Centro»'));
    await pasadasCortas(tester);

    expect(await colocadasEn('Centro'), 1);
    await desmontar(tester);
  });

  testWidgets('una que ya no se puede colocar sale con su motivo, sigue '
      'marcada y las demás van', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const ValueKey('marcar-p1')));
    await tester.tap(find.byKey(const ValueKey('marcar-p2')));
    await pasadasCortas(tester);
    await tester.tap(find.byKey(const ValueKey('colocar-marcadas')));
    await pasadasCortas(tester);

    // Con el cajón de zonas abierto, otra persona mete p2 en una ruta.
    await (base.update(base.orders)..where((o) => o.id.equals('p2'))).write(
      const OrdersCompanion(routeId: Value('r-ajena')),
    );
    await tester.tap(find.text('Colocar en «Centro»'));
    await pasadasCortas(tester);

    expect(await colocadasEn('Centro'), 1);
    expect(find.text('No se colocaron 1'), findsOneWidget);
    expect(find.text('Colocadas: 1 factura en «Centro».'), findsOneWidget);
    expect(find.textContaining('p2 · Beto: '), findsOneWidget);
    expect(find.textContaining(msgYaVaEnUnaRuta), findsOneWidget);

    await desmontar(tester);
  });

  test(
    'en la web, un «no» del servidor a UNA factura no aborta el lote',
    () async {
      final servidor = ServidorFalso((p) async {
        if (p.ruta.endsWith('/p1')) {
          return RespuestaFalsa(409, <String, Object?>{'error': 'No cabe'});
        }
        return RespuestaFalsa(200, const <String, Object?>{});
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
        ..httpClientAdapter = servidor;
      final repo = RepositorioTablero(
        base,
        ColaDeSalida(base),
        enVivo: EscrituraEnVivo(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
      );
      await sembrarSucursal(base);
      await sembrarAlmacen(base);
      await sembrarPedido(base, id: 'p1', cliente: 'Ana');
      await sembrarPedido(base, id: 'p2', cliente: 'Beto');
      final zona = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );

      final r = await MandarAlTablero(base, repo).mandar(
        pedidoIds: ['p1', 'p2'],
        columnaId: zona,
        sucursalId: sucursalStg,
      );

      expect(r.fueron, ['p2']);
      expect(r.noFueron.single.linea, 'p1 · Ana: No cabe');
    },
  );
}
