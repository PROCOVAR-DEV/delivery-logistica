// LA TABLA DE PEDIDOS: SIN «VEHÍCULO» Y CON EL COBRO DEL DOMICILIO A LA VISTA.
//
// Dos incidencias de Amado, 08/10/2026, la misma pantalla.
//
// ## 3 · «Eliminar columna Vehículo»
//
// Desde la 1.0.28 `orders.vehicle_id` ya no existe, y la celda de la tabla era
// un marcador mudo (`·` o `—` según la RUTA tuviera camión) que además no
// coincidía con lo que Amado veía en el detalle. Se quitó entera: cabecera,
// celda, umbral y parámetro. **El detalle del pedido conserva su línea de
// vehículo**, que sí sale de la ruta; esa mitad también se ata aquí, porque
// «quitar algo es quitarlo ENTERO» no incluye llevarse lo que sigue vivo.
//
// ## 4 · «Manda a una zona del tablero da error al incluir pedidos»
//
// La validación era correcta: la factura cuadraba pero NO traía la línea
// «ENTREGA A DOMICILIO» (`factura_domicilio` nulo), y la regla del 07/10 no deja
// entrar ese pedido en una ruta ni en una zona. Lo que faltaba era VERLO antes
// de marcar. La celda `Factura` lleva ahora, junto al número, «Dom. $0.46» en
// verde o «Sin cobro de domicilio» en ámbar. Sólo con factura `igual` o
// `cambiado`: `sin facturar` y `sin cotejar` ya lo dicen todo, y añadirles
// «sin cobro» sería decir dos veces lo mismo con dos colores.
//
// ## CÓMO SE PRUEBA
//
// Los `Pedido` se construyen a mano y no se abre ninguna base: dentro de un
// `testWidgets` una consulta de Drift cuelga la prueba en vez de fallar
// (CLAUDE.md §5). Lo que se mide es qué se pinta, y en qué sitio.
//
// Van EN PAREJA, como todo lo de esta carpeta: sale con cobro / sale sin cobro,
// y tras cada «sale» hay un «no sale» para `sin facturar` y `sin cotejar`.
// Los literales están escritos a propósito, sin importarlos del código: una
// prueba que lee la frase del propio widget no caza que alguien la cambie.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_detalle_pedido.dart';
import 'package:reparto/pantallas/pedidos/vista/tabla_pedidos.dart';

void main() {
  const alto = 900.0;

  /// Lo que el tooltip del aviso ámbar tiene que explicar: la consecuencia.
  const consecuencia =
      'La factura no trae la línea ENTREGA A DOMICILIO: este pedido no puede ir '
      'a una ruta ni a una zona del tablero hasta que el domicilio se cobre en '
      'la factura.';

  Pedido pedido({
    String id = 'p1',
    String? estadoFactura = EstadoFactura.igual,
    double? domicilio,
    double? costo = 3.5,
    String? routeId,
    DateTime? entregadoAt,
    String? resultado,
    bool archivado = false,
  }) => Pedido(
    id: id,
    operationNumber: 'X-2992',
    customerName: 'Ferretería La Esquina',
    address: 'calle 101 entre Calzada de Güines y Reparto Eléctrico',
    weight: 128.5,
    status: 'pending',
    tripLeg: 'ida',
    archivado: archivado,
    estado: EstadoEnPedido.completada,
    pedidoCosto: costo,
    deliveredAt: entregadoAt,
    resultado: resultado,
    facturaEstado: estadoFactura,
    facturaNumero: 'F-1001',
    facturaDomicilio: domicilio,
    routeId: routeId,
    sucursalCodigo: 'CAM',
    orderDate: DateTime(2026, 10, 8),
    createdAt: DateTime(2026, 10, 8),
  );

  const ruta = Ruta(
    id: 'R1',
    routeCode: 'RT-1',
    status: 'planned',
    totalDistance: 0,
    totalWeight: 0,
    totalPrice: 0,
    optimized: false,
    vehicleId: 'V1',
  );

  Future<void> pintar(
    WidgetTester tester, {
    required double ancho,
    required List<Pedido> pedidos,
    Map<String, Ruta> rutas = const {},
    bool conSucursal = false,
  }) async {
    tester.view.physicalSize = Size(ancho, alto);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TablaPedidos(
              pedidos: pedidos,
              renglones: const {},
              rutas: rutas,
              seleccion: const {},
              conSucursal: conSucursal,
              ahora: DateTime(2026, 10, 8, 10),
              alMarcar: (_) {},
              alMarcarPagina: (ids, marcar) {},
              alAbrir: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('la columna «Vehículo» ya no está en la tabla', () {
    // Los tres anchos que nombra la incidencia: 1440 (la de siempre), 1536 (donde
    // empezaba la columna) y 1920 (pantalla ancha). Con una ruta que SÍ tiene
    // camión, que es el único caso en que la celda vieja pintaba algo.
    for (final ancho in const [1440.0, 1536.0, 1920.0]) {
      testWidgets('a ${ancho.round()} px: ni cabecera ni celda', (
        tester,
      ) async {
        await pintar(
          tester,
          ancho: ancho,
          conSucursal: true,
          pedidos: [pedido(routeId: 'R1', domicilio: 0.46)],
          rutas: const {'R1': ruta},
        );

        expect(find.text('Vehículo'), findsNothing);
        // La celda vieja pintaba `·` si la ruta tenía camión y `—` si no.
        expect(
          find.text('·'),
          findsNothing,
          reason: 'el marcador mudo de la celda de Vehículo',
        );

        // Y la tabla sigue entera: cada columna que tiene que estar, está.
        for (final cabecera in const [
          'Fecha',
          'Pedido',
          'Cliente',
          'Ruta',
          'Artículos',
          'Dirección',
          'Peso',
          'Precio',
          'Factura',
          'Entrega',
        ]) {
          expect(find.text(cabecera), findsOneWidget, reason: cabecera);
        }
        // `Sucursal` sale desde 1536, y a 1440 no (no es de esta incidencia, pero
        // es lo que dice que el escalón de 1536 sigue donde estaba).
        expect(
          find.text('Sucursal'),
          ancho >= 1536 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('la ficha del pedido sigue diciendo el camión de su ruta', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, alto);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            detallePedidoProvider('p1').overrideWith(
              (ref) async => DetallePedido(
                pedido: pedido(routeId: 'R1', domicilio: 0.46),
                renglones: const [],
                ruta: ruta,
                vehiculo: const Vehiculo(
                  id: 'V1',
                  name: 'Camión Azul',
                  capacity: 1000,
                  usarParaDomicilio: false,
                  status: 'available',
                  isActive: true,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CajonDetallePedido(pedidoId: 'p1')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('RT-1'), findsOneWidget);
      expect(
        find.text('Camión Azul'),
        findsOneWidget,
        reason: 'el detalle conserva su línea de vehículo',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('la marca del cobro del domicilio, en la celda «Factura»', () {
    for (final estadoFactura in const [
      EstadoFactura.igual,
      EstadoFactura.cambiado,
    ]) {
      group('con la factura «$estadoFactura»', () {
        testWidgets('con domicilio cobrado: «Dom. \$0.46» en verde', (
          tester,
        ) async {
          await pintar(
            tester,
            ancho: 1440,
            pedidos: [pedido(estadoFactura: estadoFactura, domicilio: 0.46)],
          );

          expect(find.text('Dom. \$0.46'), findsOneWidget);
          expect(find.text('Sin cobro de domicilio'), findsNothing);
          expect(
            find.byTooltip(consecuencia),
            findsNothing,
            reason: 'con el domicilio cobrado no hay consecuencia que contar',
          );
          final texto = tester.widget<Text>(find.text('Dom. \$0.46'));
          expect(texto.style?.color, Colores.verde);
        });

        for (final (nombre, valor) in const [('nulo', null), ('cero', 0.0)]) {
          testWidgets('con el domicilio $nombre: «Sin cobro de domicilio» en '
              'ámbar y con su consecuencia', (tester) async {
            await pintar(
              tester,
              ancho: 1440,
              pedidos: [pedido(estadoFactura: estadoFactura, domicilio: valor)],
            );

            expect(find.text('Sin cobro de domicilio'), findsOneWidget);
            expect(find.textContaining('Dom.'), findsNothing);
            expect(find.byTooltip(consecuencia), findsOneWidget);
            final texto = tester.widget<Text>(
              find.text('Sin cobro de domicilio'),
            );
            expect(texto.style?.color, Colores.ambar);
          });
        }

        testWidgets('el número de factura sigue ahí al lado', (tester) async {
          await pintar(
            tester,
            ancho: 1440,
            pedidos: [pedido(estadoFactura: estadoFactura, domicilio: 0.46)],
          );
          expect(
            find.text(
              estadoFactura == EstadoFactura.igual ? 'F-1001' : 'F-1001 !',
            ),
            findsOneWidget,
          );
        });
      });
    }

    for (final (nombre, estadoFactura) in const [
      ('sin facturar', EstadoFactura.sinFactura),
      ('sin cotejar', null),
    ]) {
      for (final domicilio in const [null, 0.46]) {
        testWidgets('con la factura $nombre no sale nada del domicilio '
            '(domicilio: $domicilio)', (tester) async {
          await pintar(
            tester,
            ancho: 1440,
            pedidos: [
              pedido(estadoFactura: estadoFactura, domicilio: domicilio),
            ],
          );

          // La celda sigue diciendo lo suyo...
          expect(find.text(nombre), findsOneWidget);
          // ...y nada más.
          expect(find.textContaining('Dom.'), findsNothing);
          expect(find.text('Sin cobro de domicilio'), findsNothing);
          expect(find.byTooltip(consecuencia), findsNothing);
        });
      }
    }
  });

  group('el ámbar sólo sale si ESE es lo que frena al pedido', () {
    // Amado, 08/10/2026: «Sin cobro de domicilio» dice que el pedido no puede ir
    // a una ruta ni a una zona. En uno que ya va en una ruta, ya se entregó o está
    // archivado eso es falso, y un aviso que sale siempre deja de leerse
    // (CLAUDE.md §3-quinquies). La regla no se copia: se le pregunta a
    // `porQueNoSePuedeColocar`, la pieza del arrastre.
    final sinNada = <(String, Pedido)>[
      ('ya va en una ruta', pedido(routeId: 'R1')),
      (
        'ya se entregó (deliveredAt)',
        pedido(entregadoAt: DateTime(2026, 10, 7)),
      ),
      ('ya se entregó (resultado)', pedido(resultado: 'entregado')),
      ('está archivado', pedido(archivado: true)),
    ];

    for (final (nombre, p) in sinNada) {
      testWidgets('un pedido que $nombre y no trae domicilio: sólo el número', (
        tester,
      ) async {
        await pintar(
          tester,
          ancho: 1440,
          pedidos: [p],
          rutas: const {'R1': ruta},
        );
        expect(find.text('F-1001'), findsOneWidget);
        expect(find.text('Sin cobro de domicilio'), findsNothing);
        expect(find.byTooltip(consecuencia), findsNothing);
        expect(find.textContaining('Dom.'), findsNothing);
      });
    }

    testWidgets('uno que ya va en una ruta CON domicilio cobrado sí enseña el '
        'verde', (tester) async {
      await pintar(
        tester,
        ancho: 1440,
        pedidos: [pedido(routeId: 'R1', domicilio: 0.46)],
        rutas: const {'R1': ruta},
      );
      expect(find.text('Dom. \$0.46'), findsOneWidget);
      expect(find.text('Sin cobro de domicilio'), findsNothing);
    });

    testWidgets('el colocable sin cobro SÍ lleva el ámbar', (tester) async {
      await pintar(tester, ancho: 1440, pedidos: [pedido()]);
      expect(find.text('Sin cobro de domicilio'), findsOneWidget);
    });

    for (final resultado in const ['devuelto', 'cancelado']) {
      testWidgets('un $resultado, que se puede reasignar, SÍ lo lleva', (
        tester,
      ) async {
        await pintar(
          tester,
          ancho: 1440,
          pedidos: [pedido(resultado: resultado)],
        );
        expect(find.text('Sin cobro de domicilio'), findsOneWidget);
      });
    }

    testWidgets('sin cotizar pero con el domicilio cobrado: verde, no ámbar '
        '(lo que le falta es la cotización, no la factura)', (tester) async {
      await pintar(
        tester,
        ancho: 1440,
        pedidos: [pedido(domicilio: 0.46, costo: null)],
      );
      expect(find.text('Dom. \$0.46'), findsOneWidget);
      expect(find.text('Sin cobro de domicilio'), findsNothing);
    });
  });

  group('la marca no desborda ni invade a su vecina', () {
    // 1024 es el ancho MÁS estrecho donde la tabla enseña `Factura`; es donde
    // la celda es más pequeña y donde «Sin cobro de domicilio» tiene que bajar
    // de línea en vez de salirse. 390 es el teléfono, que pinta tarjetas.
    for (final ancho in const [390.0, 1024.0, 1440.0, 1536.0, 1920.0]) {
      testWidgets('«Sin cobro de domicilio» a ${ancho.round()} px', (
        tester,
      ) async {
        await pintar(tester, ancho: ancho, pedidos: [pedido(domicilio: null)]);

        final marca = tester.getRect(find.text('Sin cobro de domicilio'));
        expect(
          marca.right,
          lessThanOrEqualTo(ancho),
          reason: 'la marca llega a x=${marca.right} en $ancho px',
        );
        expect(marca.left, greaterThanOrEqualTo(0));
        // Una palabra es más ancha que alta; partida letra a letra es al revés.
        expect(marca.width, greaterThan(marca.height));

        if (ancho >= 1024) {
          // En la tabla, además, la marca no entra en la celda de al lado.
          final entrega = tester.getRect(find.text('Sin entregar'));
          expect(
            marca.right,
            lessThanOrEqualTo(entrega.left),
            reason: 'la marca ($marca) pisa la columna Entrega ($entrega)',
          );
        } else {
          // En la tarjeta cae dentro de la propia tarjeta.
          final tarjeta = tester.getRect(
            find.byKey(const ValueKey('tarjeta-p1')),
          );
          expect(marca.right, lessThanOrEqualTo(tarjeta.right));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('«Dom. \$0.46» y el número caben juntos en el teléfono', (
      tester,
    ) async {
      await pintar(tester, ancho: 390, pedidos: [pedido(domicilio: 0.46)]);

      expect(find.text('F-1001'), findsOneWidget);
      final marca = tester.getRect(find.text('Dom. \$0.46'));
      expect(marca.right, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
    });
  });
}
