import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

class MuchasZonas extends TableroDelDia {
  MuchasZonas(this.cuantas);
  int cuantas;
  int pedidos = 0;
  final movimientos = <String>[];
  void cambiar(int nuevas) {
    cuantas = nuevas;
    state = AsyncData(foto());
  }

  @override
  Future<void> colocar({
    required String pedidoId,
    required String columnaId,
    int? posicion,
  }) async {
    movimientos.add('$pedidoId->$columnaId');
  }

  @override
  Future<Tablero> build() async => foto();
  Tablero foto() => Tablero(
    sucursalId: 'b-stg',
    sucursalNombre: 'Santiago',
    almacen: const AlmacenOrigen(
      id: 'a-stg',
      nombre: 'Santiago',
      lat: 20,
      lng: -75,
    ),
    columnas: List.generate(
      cuantas,
      (i) => ColumnaTablero(
        id: 'z$i',
        branchId: 'b-stg',
        nombre: 'Zona $i',
        posicion: i,
        pedidos: 0,
        pesoKg: 0,
        costoUsd: 0,
      ),
    ),
    colocados: List.generate(
      pedidos,
      (i) => TarjetaColocada(
        pedido: TarjetaPedido(
          pedidoId: 'p$i',
          customerName: 'Pedido $i',
          address: 'Calle $i',
          weight: 1,
          kmAlAlmacen: 1,
          mismoCliente: 0,
        ),
        columnaId: 'z0',
        posicion: i,
      ),
    ),
    avisos: const AvisosTablero(),
    sinColocar: const MitadIzquierda(pedidos: [], total: 0),
    desaparecidos: [],
  );
}

Future<void> montar(
  WidgetTester t, {
  int zonas = 12,
  double ancho = 1440,
  MuchasZonas? fixture,
  TargetPlatform plataforma = TargetPlatform.linux,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(ancho, 900);
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        tableroProvider.overrideWith(() => fixture ?? MuchasZonas(zonas)),
        monedaEfectivaProvider.overrideWithValue('USD'),
        tasaDeLaMiradaProvider.overrideWithValue(
          const TasaDeLaMirada.no('fixture'),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: plataforma),
        home: const Scaffold(body: PantallaTablero()),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Finder boton(String nombre) =>
    find.byWidgetPredicate((w) => w is IconButton && w.tooltip == nombre);

Finder barra() => find.byWidgetPredicate(
  (w) =>
      w is Scrollbar && w.scrollbarOrientation == ScrollbarOrientation.bottom,
);
Future<void> cerrar(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void main() {
  for (final ancho in [1440.0, 900.0]) {
    testWidgets('raton y flechas llegan al final y regresan a $ancho', (
      t,
    ) async {
      await montar(t, ancho: ancho);
      expect(find.text('Zona 0 (0)').hitTestable(), findsOneWidget);
      expect(find.text('Zona 11 (0)').hitTestable(), findsNothing);
      expect(
        t.widget<IconButton>(boton('Ver primeras zonas')).onPressed,
        isNull,
      );
      await t.tap(boton('Ver zonas siguientes'));
      await t.pumpAndSettle();
      expect(
        t.widget<IconButton>(boton('Ver zonas anteriores')).onPressed,
        isNotNull,
      );
      await t.tap(boton('Ver zonas anteriores'));
      await t.pumpAndSettle();
      expect(find.text('Zona 0 (0)').hitTestable(), findsOneWidget);
      await t.tap(boton('Ver últimas zonas'));
      await t.pumpAndSettle();
      expect(find.text('Zona 11 (0)').hitTestable(), findsOneWidget);
      expect(
        find.text('Columna').hitTestable(),
        findsOneWidget,
        reason: 'la nueva zona debe poder pulsarse con raton, no quedar fuera de pantalla',
      );
      expect(
        t.widget<IconButton>(boton('Ver zonas siguientes')).onPressed,
        isNull,
      );
      await t.tap(find.text('Columna'));
      await t.pumpAndSettle();
      expect(find.text('Nombre de la zona'), findsOneWidget);
      await cerrar(t);
    });
  }
  testWidgets('arrastrar la barra con raton alcanza la ultima zona', (t) async {
    await montar(t);
    final widget = t.widget<Scrollbar>(barra());
    expect(widget.thumbVisibility, isTrue);
    expect(widget.interactive, isTrue);
    final rect = t.getRect(barra());
    final gesture = await t.startGesture(
      Offset(rect.left + 25, rect.bottom - 4),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(rect.right - 20, rect.bottom - 4));
    await t.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await t.pumpAndSettle();
    expect(
      find.text('Zona 11 (0)').hitTestable(),
      findsOneWidget,
      reason: 'se prueba el gesto sobre la barra pintada, no jumpTo del controlador',
    );
    expect(find.text('Columna').hitTestable(), findsOneWidget);
    await t.tap(boton('Ver primeras zonas'));
    await t.pumpAndSettle();
    expect(find.text('Zona 0 (0)').hitTestable(), findsOneWidget);
    await cerrar(t);
    expect(
      () => widget.controller!.addListener(() {}),
      throwsFlutterError,
      reason: 'Controlador propio liberado al desmontar',
    );
  });
  testWidgets('una sola zona que cabe no ofrece flechas inutiles', (t) async {
    await montar(t, zonas: 1);
    for (final name in [
      'Ver primeras zonas',
      'Ver zonas anteriores',
      'Ver zonas siguientes',
      'Ver últimas zonas',
    ]) {
      expect(t.widget<IconButton>(boton(name)).onPressed, isNull);
    }
    expect(find.text('Zona 0 (0)').hitTestable(), findsOneWidget);
    expect(find.text('Columna').hitTestable(), findsOneWidget);
    await cerrar(t);
  });
  testWidgets(
    'el movil conserva su carrusel, sin barra ni flechas de escritorio',
    (t) async {
      await montar(t, ancho: 390);
      expect(barra(), findsNothing);
      expect(boton('Ver zonas siguientes'), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
      await t.fling(find.byType(PageView), const Offset(-250, 0), 1000);
      await t.pumpAndSettle();
      expect(find.text('Zona 0 (0)').hitTestable(), findsOneWidget);
      await cerrar(t);
    },
  );

  testWidgets('zonas tardias y cambio de ancho actualizan los extremos', (
    t,
  ) async {
    final fixture = MuchasZonas(1);
    await montar(t, fixture: fixture);
    expect(t.widget<IconButton>(boton('Ver últimas zonas')).onPressed, isNull);
    fixture.cambiar(12);
    await t.pumpAndSettle();
    expect(
      t.widget<IconButton>(boton('Ver últimas zonas')).onPressed,
      isNotNull,
    );
    await t.tap(boton('Ver últimas zonas'));
    await t.pumpAndSettle();
    expect(find.text('Columna').hitTestable(), findsOneWidget);
    t.view.physicalSize = const Size(900, 900);
    await t.pumpAndSettle();
    await t.tap(boton('Ver últimas zonas'));
    await t.pumpAndSettle();
    expect(find.text('Columna').hitTestable(), findsOneWidget);
    fixture.cambiar(1);
    await t.pumpAndSettle();
    expect(find.text('Zona 0 (0)').hitTestable(), findsOneWidget);
    for (final name in [
      'Ver primeras zonas',
      'Ver zonas anteriores',
      'Ver zonas siguientes',
      'Ver últimas zonas',
    ]) {
      expect(t.widget<IconButton>(boton(name)).onPressed, isNull);
    }
    await cerrar(t);
  });
  testWidgets('sin zonas permite crear la primera sin barra sobrante', (
    t,
  ) async {
    await montar(t, zonas: 0);
    expect(barra(), findsNothing);
    await t.tap(find.text('Nueva columna'));
    await t.pumpAndSettle();
    expect(find.text('Nombre de la zona'), findsOneWidget);
    await cerrar(t);
  });
  testWidgets(
    'la rueda vertical mantiene la tira y la barra vertical de zona',
    (t) async {
      final fixture = MuchasZonas(12)..pedidos = 30;
      await montar(t, fixture: fixture);
      final horizontal = t.widget<Scrollbar>(barra()).controller!;
      final vertical = find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Scrollbar &&
                  w.scrollbarOrientation != ScrollbarOrientation.bottom,
            ),
          )
          .evaluate()
          .toList();
      expect(
        vertical,
        isNotEmpty,
        reason: 'La zona conserva su barra vertical propia',
      );
      final zona = find.text('Pedido 0').hitTestable();
      expect(zona, findsOneWidget);
      final point = t.getCenter(zona);
      await t.sendEventToBinding(
        PointerScrollEvent(
          position: point,
          scrollDelta: const Offset(0, 450),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await t.pumpAndSettle();
      expect(
        horizontal.offset,
        0,
        reason: 'Rueda vertical no desplaza zonas horizontalmente',
      );
      expect(
        find.text('Pedido 0').hitTestable(),
        findsNothing,
        reason: 'La rueda desplaza pedidos de la zona',
      );
      expect(find.text('Zona 0 (0)').hitTestable(), findsOneWidget);
      await cerrar(t);
    },
  );
  testWidgets('raton mueve pedido entre zonas sin que la tira intercepte', (
    t,
  ) async {
    final fixture = MuchasZonas(12)..pedidos = 1;
    await montar(t, fixture: fixture);
    final horizontal = t.widget<Scrollbar>(barra()).controller!;
    final g = await t.startGesture(
      t.getCenter(find.text('Pedido 0').hitTestable()),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(30, 0));
    await t.pump(const Duration(milliseconds: 30));
    await g.moveTo(
      t.getCenter(find.text('Zona 1 (0)').hitTestable()) + const Offset(0, 80),
    );
    await t.pump(const Duration(milliseconds: 100));
    await g.up();
    await t.pumpAndSettle();
    expect(fixture.movimientos, [
      'p0->z1',
    ], reason: 'La pantalla entrega la operación real al notifier');
    expect(
      horizontal.offset,
      0,
      reason: 'Arrastrar pedido no desplaza la tira',
    );
    await cerrar(t);
  });
  testWidgets(
    'flecha anterior no rebota fuera del inicio con fisica de macOS',
    (t) async {
      await montar(t, plataforma: TargetPlatform.macOS);
      final mando = t.widget<Scrollbar>(barra()).controller!;
      final point =
          t.getCenter(find.text('Zona 0 (0)').hitTestable()) +
          const Offset(0, 150);
      await t.sendEventToBinding(
        PointerScrollEvent(
          position: point,
          scrollDelta: const Offset(100, 0),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await t.pumpAndSettle();
      expect(mando.offset, greaterThan(0));
      await t.tap(boton('Ver zonas anteriores'));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(
        mando.offset,
        greaterThanOrEqualTo(0),
        reason: 'La flecha no lleva la tira fuera del contenido',
      );
      await t.pumpAndSettle();
      await cerrar(t);
    },
  );
}
