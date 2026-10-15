import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show QueryExecutor, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// La pantalla, con el dedo.
///
/// Arrastrar de verdad no se puede probar a ciegas en un test de widget sin
/// atarlo a coordenadas de pixel, que es lo primero que se rompe al cambiar un
/// margen. Lo que si se prueba es el camino que de verdad usa quien lleva un
/// telefono: **tocar la tarjeta y elegir la columna**, que llama exactamente a
/// lo mismo.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  setUp(() async {
    base = BaseLocal.con(_enMemoria());
    servidor = ServidorFalso((peticion) async => null);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
  });

  tearDown(() => base.close());

  /// Deja que la pantalla se asiente, con un tope corto.
  ///
  /// El tope por defecto de `pumpAndSettle` son diez minutos: si algo no
  /// termina de asentarse, la prueba se queda colgada y no dice nada. Con diez
  /// segundos falla y cuenta por que.
  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  /// Desmonta el arbol DENTRO de la prueba.
  ///
  /// Los `Stream` de Drift dejan un temporizador de cero al cerrarse, y si el
  /// arbol se desmonta cuando la prueba ya termino, el test falla por «queda un
  /// Timer» sin que haya nada roto. Desmontar aqui deja que se apague.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Dos pasadas: el temporizador lo crea el propio desmontaje, al final del
    // primer fotograma, asi que hace falta otro para que llegue a dispararse.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget montar() {
    final dio = Dio()..httpClientAdapter = servidor;
    return ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        // SIN ESPERAS. El tablero pide la foto del servidor al abrirse —con
        // conexión manda el servidor, no la copia— y aquí no hay servidor: el
        // cliente reintentaría con esperas de verdad y `pumpAndSettle` se cuelga
        // en vez de fallar. Es la trampa del `CLAUDE.md` §5.
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
      // La pantalla NO lleva `Scaffold`: lo pone el armazon. Aqui se envuelve a
      // mano para poder pintarla suelta, sin arrastrar la navegacion entera.
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  testWidgets('pinta las dos mitades y mueve una tarjeta con el dedo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = RepositorioTablero(base, ColaDeSalida(base));
    await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
    await sembrarPedido(
      base,
      id: 'cerca',
      operacion: 'SC06-1257',
      aGrados: 0.01,
    );
    await sembrarPedido(
      base,
      id: 'lejos',
      operacion: 'SC06-0431',
      aGrados: 0.30,
    );

    await tester.pumpWidget(montar());
    await asentar(tester);

    expect(find.text('Sin colocar (2)'), findsOneWidget);
    expect(find.text('Centro (0)'), findsOneWidget);
    // El más cerca del almacén, primero.
    final tarjetas = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(
      tarjetas.indexWhere((t) => t.data == 'SC06-1257') <
          tarjetas.indexWhere((t) => t.data == 'SC06-0431'),
      isTrue,
    );
    expect(find.textContaining('1,1 km'), findsOneWidget);

    await tester.tap(find.text('SC06-1257'));
    await asentar(tester);
    expect(find.text('Colocar en «Centro»'), findsOneWidget);

    await tester.tap(find.text('Colocar en «Centro»'));
    await asentar(tester);

    expect(find.text('Centro (1)'), findsOneWidget);
    expect(find.text('Sin colocar (1)'), findsOneWidget);

    // Y no se llamó a nadie: quedó en la cola.
    expect(servidor.vistas, isEmpty);
    final apuntes = await ColaDeSalida(base).lote();
    expect(apuntes.last.ruta, '/board/placements/cerca');

    await desmontar(tester);
  });

  testWidgets('lo que dejó de servir se ve marcado, no desaparece', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = RepositorioTablero(base, ColaDeSalida(base));
    final centro = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Centro',
    );
    await sembrarPedido(base, id: 'p1', operacion: 'SC06-1257');
    await repo.colocar(pedidoId: 'p1', columnaId: centro);
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(facturaEstado: Value(EstadoFactura.sinFactura)),
    );

    await tester.pumpWidget(montar());
    await asentar(tester);

    expect(find.text('SC06-1257'), findsOneWidget, reason: 'sigue en la zona');
    expect(find.text('Sin factura'), findsWidgets);
    expect(find.textContaining('sin factura o sin cotejar'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('sin columnas lo dice, y lo del camión no se inventa', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(montar());
    await asentar(tester);

    expect(find.text('Las zonas las pones tú.'), findsOneWidget);
    expect(find.text('Nueva columna'), findsOneWidget);
    expect(find.textContaining('Visto por última vez'), findsNothing);
    expect(find.text('Sin descargar todavía'), findsOneWidget);

    await desmontar(tester);
  });
}

/// La base en memoria, con el mismo Dart y el mismo SQL que en el aparato.
QueryExecutor _enMemoria() => NativeDatabase.memory();
