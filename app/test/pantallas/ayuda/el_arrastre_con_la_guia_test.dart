// Regresión del 06/10: con la tarea real abierta, el origen se podía levantar
// pero el velo se comía el destino. Se ejecuta el gesto, no sólo el registro.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/columna.dart';
import 'package:reparto/pantallas/tablero/vista/tarjeta.dart';

const _pedido = TarjetaPedido(
  pedidoId: 'pedido-a',
  customerName: 'Cliente del pedido',
  address: 'Dirección',
  weight: 10,
  kmAlAlmacen: 2,
  mismoCliente: 1,
);

void main() {
  final manual = Manual.desdeElPaquete(
    File('assets/manual/manual.txt').readAsStringSync(),
    pantallas: const [PantallaDelMenu('/board', 'Tablero')],
  );

  Future<OverlayState> montar(
    WidgetTester tester, {
    required List<String> columnasAceptadas,
    required List<String> pedidosAceptados,
    required VoidCallback alTocarFuera,
    bool conPedido = false,
    int zonas = 2,
  }) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    addTearDown(Recorrido.salir);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    late OverlayState capa;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monedaEfectivaProvider.overrideWithValue('USD'),
          tasaDeLaMiradaProvider.overrideWithValue(
            const TasaDeLaMirada.no('sin tasa en prueba'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (contexto) {
                capa = Overlay.of(contexto, rootOverlay: true);
                return SizedBox(
                  height: 600,
                  child: Row(
                    children: [
                      if (conPedido)
                        SizedBox(
                          width: 280,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ControlSenalado(
                              nombre: Senalado.tableroTarjetaDePedido,
                              child: const TarjetaDePedido(pedido: _pedido),
                            ),
                          ),
                        ),
                      for (var i = 0; i < zonas; i++)
                        ColumnaDelTablero(
                          columna: ColumnaTablero(
                            id: 'z$i',
                            branchId: 'b-stg',
                            nombre: i == 0 ? 'Centro' : 'Carretera',
                            posicion: i,
                            pedidos: 3,
                            pesoKg: 200,
                            costoUsd: 0,
                          ),
                          ancho: 300,
                          esLaPrimera: i == 0,
                          esLaSegunda: i == 1,
                          tarjetas: const [],
                          alSoltar: (p, _) =>
                              pedidosAceptados.add('${p.pedidoId}:z$i'),
                          alPulsarTarjeta: (_) {},
                          alAbrirMenu: () {},
                          alSoltarColumna: (c) =>
                              columnasAceptadas.add('${c.columnaId}:z$i'),
                        ),
                      const SizedBox(width: 30),
                      OutlinedButton(
                        onPressed: alTocarFuera,
                        child: const Text('Otro control'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return capa;
  }

  Future<void> arrastrar(
    WidgetTester tester,
    Offset origen,
    Offset destino,
  ) async {
    final gesto = await tester.startGesture(
      origen,
      kind: PointerDeviceKind.mouse,
    );
    await gesto.moveBy(const Offset(30, 25));
    await tester.pump();
    await gesto.moveTo(destino);
    await tester.pump();
    await gesto.up();
    await tester.pumpAndSettle();
  }

  for (final forma in [
    FormaDeLaAplicacion.web,
    FormaDeLaAplicacion.escritorio,
  ]) {
    final tareas = manual.paraLaForma(forma).tareas;
    final camino = forma == FormaDeLaAplicacion.web
        ? 'web/1-el-dia-en-la-web.md'
        : 'escritorio/2-el-dia-en-el-escritorio.md';
    final reordenar = tareas.singleWhere(
      (t) => t.camino == camino && t.titulo.endsWith('Reordenar las zonas'),
    );
    final repartir = tareas.singleWhere(
      (t) =>
          t.camino == camino &&
          t.titulo.endsWith('Repartir los pedidos — arrastrando'),
    );

    for (final conGuia in [false, true]) {
      testWidgets('${forma.name}: reordenar ${conGuia ? "con" : "sin"} Guía', (
        tester,
      ) async {
        final aceptadas = <String>[];
        var toquesFuera = 0;
        final capa = await montar(
          tester,
          columnasAceptadas: aceptadas,
          pedidosAceptados: [],
          alTocarFuera: () => toquesFuera++,
        );
        if (conGuia) {
          Recorrido.empezarEn(capa, reordenar);
          await tester.pumpAndSettle();
          expect(
            reordenar.pasos,
            hasLength(1),
            reason: 'un arrastre no se corta con Siguiente',
          );
          expect(find.byKey(ClavesDelRecorrido.foco), findsNWidgets(2));
        }
        await arrastrar(
          tester,
          tester.getCenter(find.text('Centro (3)')),
          tester.getRect(find.byType(ColumnaDelTablero).at(1)).center,
        );
        expect(
          aceptadas,
          ['z0:z1'],
          reason:
              'la cabecera debe llegar a OTRA zona con el recorrido abierto',
        );
        await tester.tap(find.text('Otro control'), warnIfMissed: false);
        await tester.pump();
        expect(
          toquesFuera,
          conGuia ? 0 : 1,
          reason: 'el resto del velo sigue bloqueado',
        );
        Recorrido.salir();
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('${forma.name}: repartir ${conGuia ? "con" : "sin"} Guía', (
        tester,
      ) async {
        final aceptadas = <String>[];
        final capa = await montar(
          tester,
          columnasAceptadas: [],
          pedidosAceptados: aceptadas,
          alTocarFuera: () {},
          conPedido: true,
        );
        if (conGuia) {
          // Es el paso 3 real del manual, después del filtro y del buscador.
          Recorrido.empezarEn(capa, repartir);
          await tester.pumpAndSettle();
          for (var i = 0; i < 2; i++) {
            await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
            await tester.pumpAndSettle();
          }
          expect(find.byKey(ClavesDelRecorrido.foco), findsNWidgets(2));
        }
        await arrastrar(
          tester,
          tester.getCenter(find.byType(TarjetaDePedido)),
          tester.getRect(find.byType(ColumnaDelTablero).first).center,
        );
        expect(aceptadas, [
          'pedido-a:z0',
        ], reason: 'el pedido debe llegar al destino en el mismo paso');
        Recorrido.salir();
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets(
      '${forma.name}: con una sola zona se explica que falta el destino',
      (tester) async {
        final capa = await montar(
          tester,
          columnasAceptadas: [],
          pedidosAceptados: [],
          alTocarFuera: () {},
          zonas: 1,
        );
        Recorrido.empezarEn(capa, reordenar);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.byKey(ClavesDelRecorrido.foco), findsNothing);
        expect(find.textContaining('no se puede señalar aquí'), findsOneWidget);
        Recorrido.salir();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('se leen todas las marcas del gesto y se ocultan al pintar', () {
    final pasos = pasosDelCuerpo('''
1. Lleva el origen al destino. <!-- señala: origen -->
   <!-- señala: destino -->
   - Comprueba el destino. <!-- señala: destino -->
''');
    expect(pasos.single.controles, ['origen', 'destino']);
    expect(pasos.single.texto, 'Lleva el origen al destino.');
    expect(pasos.single.detalles, ['Comprueba el destino.']);
  });
}
