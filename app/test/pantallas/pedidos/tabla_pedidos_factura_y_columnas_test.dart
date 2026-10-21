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
// de marcar. La celda `Factura` llevó, junto al número, «Dom. $0.46» en verde o
// «Domicilio sin precio puesto»; sólo con factura `igual` o `cambiado`.
// **Desde el 21/10/2026 esas marcas viven SÓLO en la tarjeta del teléfono**: en la
// tabla partían la fila en dos líneas, y el domicilio de la parada va en la
// columna «Precio» (el importe, o «sin precio» en gris).
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
import 'package:reparto/pantallas/pedidos/vista/kit.dart' show Insignia;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cajon_detalle_pedido.dart';
import 'package:reparto/pantallas/pedidos/vista/tabla_pedidos.dart';

void main() {
  const alto = 900.0;

  /// El tooltip del aviso, que desde el 16/10/2026 (TEMPORAL, Jose) sólo INFORMA: no impide ir
  /// a una ruta, y el aviso es gris, no ámbar.
  const consecuencia =
      'La factura trae la línea ENTREGA A DOMICILIO pero con el precio en \$0: '
      'no se puso el precio. No impide ir a una ruta.';

  Pedido pedido({
    String id = 'p1',
    String numero = 'F-1001',
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
    puntoManual: false,
    estado: EstadoEnPedido.completada,
    pedidoCosto: costo,
    deliveredAt: entregadoAt,
    resultado: resultado,
    facturaEstado: estadoFactura,
    facturaNumero: numero,
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
          'Fecha factura',
          'Pedido',
          'Cliente',
          'Ruta',
          'Artículos',
          'Peso',
          'Domicilio',
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

  // DISEÑO DEL 21/10/2026 (Jose: «la primera fila se baja sus datos una encima de otro»).
  // En la TABLA (>= 768 px) la celda «Factura» lleva SÓLO el número, y el domicilio de la
  // parada va en la columna «Precio»: el importe, o «sin precio» en gris si no hay costo.
  // La TARJETA del teléfono (390 px) conserva las marcas «Dom. $x» y «Domicilio sin precio
  // puesto». Cada «sale» de abajo tiene su «no sale» en el otro diseño.
  const anchoTarjeta = 390.0;
  const anchoTabla = 1440.0;

  group('la tabla: el domicilio va en la columna «Precio», no en la celda «Factura»', () {
    for (final estadoFactura in const [
      EstadoFactura.igual,
      EstadoFactura.cambiado,
    ]) {
      group('con la factura «$estadoFactura»', () {
        testWidgets(
          'con domicilio cobrado: «\$0.46» en Precio y ninguna marca',
          (tester) async {
            await pintar(
              tester,
              ancho: anchoTabla,
              pedidos: [
                pedido(
                  estadoFactura: estadoFactura,
                  domicilio: 0.46,
                  costo: null,
                ),
              ],
            );

            expect(find.text('\$0.46'), findsOneWidget);
            expect(find.text('sin precio'), findsNothing);
            expect(find.textContaining('Dom.'), findsNothing);
            expect(find.text('Domicilio sin precio puesto'), findsNothing);
            expect(
              find.byTooltip(consecuencia),
              findsNothing,
              reason: 'con el domicilio cobrado no hay consecuencia que contar',
            );
            final texto = tester.widget<Text>(find.text('\$0.46'));
            expect(texto.style?.color, Colores.tinta);
          },
        );

        for (final (nombre, valor) in const [('nulo', null), ('cero', 0.0)]) {
          testWidgets(
            'con el domicilio $nombre y sin costo: «sin precio» en gris, con '
            'su consecuencia, y ninguna marca apilada',
            (tester) async {
              await pintar(
                tester,
                ancho: anchoTabla,
                pedidos: [
                  pedido(
                    estadoFactura: estadoFactura,
                    domicilio: valor,
                    costo: null,
                  ),
                ],
              );

              expect(find.text('sin precio'), findsOneWidget);
              expect(find.byTooltip(consecuencia), findsOneWidget);
              expect(find.text('Domicilio sin precio puesto'), findsNothing);
              expect(find.textContaining('Dom.'), findsNothing);
              final texto = tester.widget<Text>(find.text('sin precio'));
              expect(texto.style?.color, Colores.tintaSuave);
            },
          );
        }

        testWidgets('la celda «Factura» lleva sólo el número', (tester) async {
          await pintar(
            tester,
            ancho: anchoTabla,
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

    // La pareja de «sin precio»: con costo (de Entrega o de la factura) NO sale.
    testWidgets(
      'con el costo de Entrega, Precio dice ese costo y no «sin precio»',
      (tester) async {
        await pintar(
          tester,
          ancho: anchoTabla,
          pedidos: [pedido(domicilio: null, costo: 3.5)],
        );
        expect(find.text('\$3.50'), findsOneWidget);
        expect(find.text('sin precio'), findsNothing);
        expect(find.byTooltip(consecuencia), findsNothing);
      },
    );

    for (final (nombre, estadoFactura) in const [
      ('sin facturar', EstadoFactura.sinFactura),
      ('sin cotejar', null),
    ]) {
      for (final domicilio in const [null, 0.46]) {
        testWidgets(
          'con la factura $nombre no sale ninguna marca del domicilio '
          '(domicilio: $domicilio)',
          (tester) async {
            await pintar(
              tester,
              ancho: anchoTabla,
              pedidos: [
                pedido(estadoFactura: estadoFactura, domicilio: domicilio),
              ],
            );

            // La celda sigue diciendo lo suyo...
            expect(find.text(nombre), findsOneWidget);
            // ...y nada más.
            expect(find.textContaining('Dom.'), findsNothing);
            expect(find.text('Domicilio sin precio puesto'), findsNothing);
            expect(find.byTooltip(consecuencia), findsNothing);
          },
        );
      }
    }
  });

  group(
    'la tarjeta del teléfono conserva la marca del cobro del domicilio',
    () {
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
              ancho: anchoTarjeta,
              pedidos: [pedido(estadoFactura: estadoFactura, domicilio: 0.46)],
            );

            expect(find.text('Dom. \$0.46'), findsOneWidget);
            expect(find.text('Domicilio sin precio puesto'), findsNothing);
            expect(
              find.byTooltip(consecuencia),
              findsNothing,
              reason: 'con el domicilio cobrado no hay consecuencia que contar',
            );
            final texto = tester.widget<Text>(find.text('Dom. \$0.46'));
            expect(texto.style?.color, Colores.verde);
          });

          for (final (nombre, valor) in const [('nulo', null), ('cero', 0.0)]) {
            testWidgets(
              'con el domicilio $nombre: «Domicilio sin precio puesto» en '
              'gris y con su consecuencia',
              (tester) async {
                await pintar(
                  tester,
                  ancho: anchoTarjeta,
                  pedidos: [
                    pedido(estadoFactura: estadoFactura, domicilio: valor),
                  ],
                );

                expect(
                  find.text('Domicilio sin precio puesto'),
                  findsOneWidget,
                );
                expect(find.textContaining('Dom.'), findsNothing);
                expect(find.byTooltip(consecuencia), findsOneWidget);
                final texto = tester.widget<Text>(
                  find.text('Domicilio sin precio puesto'),
                );
                expect(texto.style?.color, Colores.gris);
              },
            );
          }

          testWidgets(
            'el número de factura sigue en la cabecera de la tarjeta',
            (tester) async {
              await pintar(
                tester,
                ancho: anchoTarjeta,
                pedidos: [
                  pedido(estadoFactura: estadoFactura, domicilio: 0.46),
                ],
              );
              expect(find.text('Factura F-1001'), findsOneWidget);
              expect(
                find.text(
                  estadoFactura == EstadoFactura.igual ? 'Cuadra' : 'Cambió !',
                ),
                findsOneWidget,
              );
            },
          );
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
              ancho: anchoTarjeta,
              pedidos: [
                pedido(estadoFactura: estadoFactura, domicilio: domicilio),
              ],
            );

            expect(find.text(nombre), findsOneWidget);
            expect(find.textContaining('Dom.'), findsNothing);
            expect(find.text('Domicilio sin precio puesto'), findsNothing);
            expect(find.byTooltip(consecuencia), findsNothing);
          });
        }
      }
    },
  );

  group('el aviso sólo sale si ESE es lo que frena al pedido (tarjeta del teléfono)', () {
    // Amado, 08/10/2026: «Domicilio sin precio puesto» sólo se dice de un pedido que podría
    // ir a una ruta. En uno que ya va en una ruta, ya se entregó o está archivado es falso,
    // y un aviso que sale siempre deja de leerse (CLAUDE.md §3-quinquies). La regla no se
    // copia: se le pregunta a `porQueNoSePuedeColocar`, la pieza del arrastre. Desde el
    // 21/10/2026 la marca vive sólo en la tarjeta; la tabla la sustituyó por la columna Precio.
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
          ancho: anchoTarjeta,
          pedidos: [p],
          rutas: const {'R1': ruta},
        );
        expect(find.text('Factura F-1001'), findsOneWidget);
        expect(find.text('Domicilio sin precio puesto'), findsNothing);
        expect(find.byTooltip(consecuencia), findsNothing);
        expect(find.textContaining('Dom.'), findsNothing);
      });
    }

    testWidgets('uno que ya va en una ruta CON domicilio cobrado sí enseña el '
        'verde', (tester) async {
      await pintar(
        tester,
        ancho: anchoTarjeta,
        pedidos: [pedido(routeId: 'R1', domicilio: 0.46)],
        rutas: const {'R1': ruta},
      );
      expect(find.text('Dom. \$0.46'), findsOneWidget);
      expect(find.text('Domicilio sin precio puesto'), findsNothing);
    });

    testWidgets('el colocable sin cobro SÍ lleva el aviso', (tester) async {
      await pintar(tester, ancho: anchoTarjeta, pedidos: [pedido()]);
      expect(find.text('Domicilio sin precio puesto'), findsOneWidget);
    });

    for (final resultado in const ['devuelto', 'cancelado']) {
      testWidgets('un $resultado, que se puede reasignar, SÍ lo lleva', (
        tester,
      ) async {
        await pintar(
          tester,
          ancho: anchoTarjeta,
          pedidos: [pedido(resultado: resultado)],
        );
        expect(find.text('Domicilio sin precio puesto'), findsOneWidget);
      });
    }

    testWidgets('sin cotizar pero con el domicilio cobrado: verde, no aviso '
        '(lo que le falta es la cotización, no la factura)', (tester) async {
      await pintar(
        tester,
        ancho: anchoTarjeta,
        pedidos: [pedido(domicilio: 0.46, costo: null)],
      );
      expect(find.text('Dom. \$0.46'), findsOneWidget);
      expect(find.text('Domicilio sin precio puesto'), findsNothing);
    });

    // En la tabla, en cambio, «sin precio» es un dato de la columna Precio: no depende de si
    // el pedido va en una ruta (sólo de que no haya ningún costo).
    testWidgets('la tabla dice «sin precio» también en uno que ya va en una '
        'ruta, y nunca la marca', (tester) async {
      await pintar(
        tester,
        ancho: anchoTabla,
        pedidos: [pedido(routeId: 'R1', costo: null)],
        rutas: const {'R1': ruta},
      );
      expect(find.text('sin precio'), findsOneWidget);
      expect(find.text('Domicilio sin precio puesto'), findsNothing);
    });
  });

  group('lo que se pinta no desborda ni invade a su vecina', () {
    // 1024 es el ancho MÁS estrecho donde la tabla enseña `Factura`. 390 es el teléfono,
    // que pinta tarjetas.
    testWidgets(
      '«Domicilio sin precio puesto» a 390 px, dentro de la tarjeta',
      (tester) async {
        await pintar(tester, ancho: 390, pedidos: [pedido(domicilio: null)]);

        final marca = tester.getRect(find.text('Domicilio sin precio puesto'));
        expect(
          marca.right,
          lessThanOrEqualTo(390),
          reason: 'la marca llega a x=${marca.right} en 390 px',
        );
        expect(marca.left, greaterThanOrEqualTo(0));
        // Una palabra es más ancha que alta; partida letra a letra es al revés.
        expect(marca.width, greaterThan(marca.height));
        final tarjeta = tester.getRect(
          find.byKey(const ValueKey('tarjeta-p1')),
        );
        expect(marca.right, lessThanOrEqualTo(tarjeta.right));
        expect(tester.takeException(), isNull);
      },
    );

    for (final ancho in const [1024.0, 1440.0, 1536.0, 1920.0]) {
      testWidgets('«sin precio» a ${ancho.round()} px: en una línea y sin '
          'pisar la columna Entrega', (tester) async {
        await pintar(
          tester,
          ancho: ancho,
          pedidos: [pedido(domicilio: null, costo: null)],
        );

        final precio = tester.getRect(find.text('sin precio'));
        expect(precio.right, lessThanOrEqualTo(ancho));
        expect(precio.left, greaterThanOrEqualTo(0));
        expect(precio.width, greaterThan(precio.height));
        final entrega = tester.getRect(find.text('Sin entregar'));
        expect(
          precio.right,
          lessThanOrEqualTo(entrega.left),
          reason: '«sin precio» ($precio) pisa la columna Entrega ($entrega)',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('«Dom. \$0.46» y el número caben juntos en el teléfono', (
      tester,
    ) async {
      await pintar(tester, ancho: 390, pedidos: [pedido(domicilio: 0.46)]);

      // El número ya no va en la insignia de la tarjeta sino en su cabecera, con el
      // rótulo «Factura» (Amado, issue 8, 14/10/2026): ver
      // `el_numero_de_factura_en_los_pedidos_test.dart`.
      expect(find.text('Factura F-1001'), findsOneWidget);
      final marca = tester.getRect(find.text('Dom. \$0.46'));
      expect(marca.right, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
    });
  });

  group(
    'la fila de la tabla NO se parte en dos líneas por la celda «Factura»',
    () {
      // Jose, 21/10/2026: «la primera fila se baja sus datos una encima de otro». La celda
      // apilaba el número y una marca; ahora lleva sólo la insignia, también con DOS facturas.
      // Se compara contra la misma fila con UN número: partida en dos líneas, la insignia y la
      // fila serían más altas, y «< 2x el texto» solo no lo vería (el texto partido también
      // crece).
      for (final ancho in const [1440.0, 1920.0]) {
        testWidgets('con dos números («47359, 47360») a ${ancho.round()} px: '
            'una sola línea y sin desbordar', (tester) async {
          Future<({Rect insignia, Rect texto, Rect fila})> medir(
            String numero,
          ) async {
            await pintar(
              tester,
              ancho: ancho,
              conSucursal: true,
              pedidos: [pedido(numero: numero, domicilio: 0.46, costo: null)],
            );
            final texto = find.text(numero);
            return (
              insignia: tester.getRect(
                find.ancestor(of: texto, matching: find.byType(Insignia)),
              ),
              texto: tester.getRect(texto),
              fila: tester.getRect(
                find.ancestor(of: texto, matching: find.byType(InkWell)),
              ),
            );
          }

          final uno = await medir('47359');
          final dos = await medir('47359, 47360');

          expect(
            dos.insignia.height,
            lessThan(2 * dos.texto.height),
            reason:
                'la insignia (${dos.insignia}) ocupa más de una línea de '
                'su texto (${dos.texto})',
          );
          expect(dos.texto.height, closeTo(uno.texto.height, 0.5));
          expect(dos.insignia.height, closeTo(uno.insignia.height, 0.5));
          expect(
            dos.fila.height,
            closeTo(uno.fila.height, 0.5),
            reason:
                'la fila con dos facturas es más alta que con una: se partió',
          );
          expect(dos.insignia.right, lessThanOrEqualTo(ancho));
          expect(tester.takeException(), isNull);
        });
      }
    },
  );
}
