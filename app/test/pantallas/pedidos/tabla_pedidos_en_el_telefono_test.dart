// LA TABLA DE PEDIDOS EN UN TELÉFONO. Medido, no leído.
//
// El 22/09/2026, en el teléfono de Jose (1080x2340 físicos = 390 px lógicos), la
// tabla de Pedidos partía las palabras **letra a letra**: «Completada» salía
// como `C o m p l e t a d a` en columna vertical, «sin cotizar» igual, y una
// sola fila ocupaba media pantalla. No había ningún error en el registro, ni
// ninguna consulta rota: la aplicación funcionaba y no se podía usar.
//
// POR QUÉ ESTAS PRUEBAS MIDEN COORDENADAS. Un fallo de colocación no rompe nada
// que un `findsOneWidget` pueda ver: el texto ESTÁ, con su literal exacto, en el
// árbol de widgets. Lo único que distingue «se lee» de «está partido en
// vertical» es la forma de su rectángulo — una palabra es más ancha que alta, y
// una palabra partida letra a letra es más alta que ancha. Lo mismo con salirse
// de la pantalla: `rect.right` por encima del ancho del aparato.
//
// Y van EN PAREJA: a 390 px tarjetas, a 1440 px la tabla de siempre. Una prueba
// que sólo mira el teléfono se queda tan verde con una aplicación que ha perdido
// sus doce columnas en el escritorio.
//
// NADA DE DRIFT AQUÍ. Estas pruebas construyen los `Pedido` a mano y no abren
// ninguna base: dentro de un `testWidgets` una consulta de Drift **cuelga la
// prueba en vez de fallar** (CLAUDE.md §5), y una prueba colgada no avisa de
// nada. Lo que se mide aquí es sólo colocación, así que no hace falta.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/vista/tabla_pedidos.dart';

void main() {
  /// El teléfono de Jose en píxeles lógicos, y un escritorio ancho.
  const anchoDelTelefono = 390.0;
  const altoDelTelefono = 844.0;
  const anchoDeEscritorio = 1440.0;

  /// Una dirección de las de verdad: larga, con nombres propios y sin ningún
  /// sitio cómodo por donde cortar.
  const direccionLarga =
      'calle 101 entre Calzada de Güines y Reparto Eléctrico, '
      'San Miguel del Padrón';

  Pedido pedidoDePrueba({
    String id = 'p1',
    String cliente = 'Ferretería La Esquina',
    String? folio = 'X-2992',
    double? costo,
  }) => Pedido(
    id: id,
    operationNumber: folio,
    customerName: cliente,
    address: direccionLarga,
    weight: 128.5,
    status: 'pending',
    tripLeg: 'ida',
    archivado: false,
    // `Completada` es la palabra que se partía letra a letra.
    estado: EstadoEnPedido.completada,
    // Sin costo se pinta `sin cotizar`, que es la otra que se partía.
    pedidoCosto: costo,
    orderDate: DateTime(2026, 9, 22),
    createdAt: DateTime(2026, 9, 22),
  );

  /// Monta la tabla al ancho que se le diga. Devuelve lo que se fue marcando,
  /// para poder comprobar que los gestos siguen ahí después del cambio de forma.
  Future<({List<String> abiertos, List<String> marcados})> pintar(
    WidgetTester tester, {
    required double ancho,
    List<Pedido>? pedidos,
  }) async {
    tester.view.physicalSize = Size(ancho, altoDelTelefono);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final abiertos = <String>[];
    final marcados = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TablaPedidos(
              pedidos: pedidos ?? [pedidoDePrueba()],
              renglones: const {},
              rutas: const {},
              seleccion: const {},
              conSucursal: false,
              ahora: DateTime(2026, 9, 22, 10),
              alMarcar: marcados.add,
              alMarcarPagina: (ids, marcar) => marcados.addAll(ids),
              alAbrir: (p) => abiertos.add(p.id),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (abiertos: abiertos, marcados: marcados);
  }

  group('a 390 px —el teléfono de Jose—', () {
    testWidgets('«Completada» no se parte letra a letra', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      final caja = tester.getRect(find.text('Completada'));
      // Una palabra es más ancha que alta. Partida en vertical es al revés: son
      // diez renglones de una letra.
      expect(
        caja.width,
        greaterThan(caja.height),
        reason:
            'La palabra «Completada» mide ${caja.width.toStringAsFixed(1)} x '
            '${caja.height.toStringAsFixed(1)}: más alta que ancha es que está '
            'partida letra a letra, como en el teléfono de Jose.',
      );
      expect(caja.right, lessThanOrEqualTo(anchoDelTelefono));
    });

    testWidgets('«sin cotizar» tampoco', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      final caja = tester.getRect(find.text('sin cotizar'));
      expect(
        caja.width,
        greaterThan(caja.height),
        reason:
            '«sin cotizar» mide ${caja.width.toStringAsFixed(1)} x '
            '${caja.height.toStringAsFixed(1)}.',
      );
      expect(caja.right, lessThanOrEqualTo(anchoDelTelefono));
    });

    testWidgets('la dirección no se sale por el borde derecho', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      final caja = tester.getRect(find.text(direccionLarga));
      expect(
        caja.right,
        lessThanOrEqualTo(anchoDelTelefono),
        reason:
            'La dirección llega hasta x=${caja.right.toStringAsFixed(1)} en una '
            'pantalla de $anchoDelTelefono px.',
      );
      expect(caja.left, greaterThanOrEqualTo(0));
      // Dos líneas y elipsis: ancha y baja, nunca una columna de letras.
      expect(caja.width, greaterThan(caja.height));
    });

    testWidgets('un pedido NO ocupa media pantalla', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      final caja = tester.getRect(find.byKey(const ValueKey('tarjeta-p1')));
      expect(
        caja.height,
        lessThan(altoDelTelefono / 3),
        reason:
            'Un pedido ocupa ${caja.height.toStringAsFixed(1)} px de los '
            '$altoDelTelefono de la pantalla: con eso no caben ni tres.',
      );
      expect(caja.width, lessThanOrEqualTo(anchoDelTelefono));
    });

    testWidgets('sin tabla: ni cabecera de columnas ni desbordes', (
      tester,
    ) async {
      await pintar(tester, ancho: anchoDelTelefono);

      // Los rótulos de columna no pintan nada encima de unas tarjetas.
      expect(find.text('Dirección'), findsNothing);
      expect(find.text('Artículos'), findsNothing);
      expect(find.text('Peso'), findsNothing);
    });

    testWidgets('los dos gestos siguen ahí: abrir y marcar la página', (
      tester,
    ) async {
      final visto = await pintar(tester, ancho: anchoDelTelefono);

      // La casilla de arriba marca la página entera; la tarjeta abre el detalle.
      await tester.tap(find.byType(Checkbox).first);
      expect(visto.marcados, ['p1']);

      await tester.tap(find.text('Ferretería La Esquina'));
      expect(visto.abiertos, ['p1']);
    });
  });

  group('a 1440 px —el escritorio— sigue siendo la tabla de siempre', () {
    testWidgets('con sus rótulos de columna', (tester) async {
      await pintar(tester, ancho: anchoDeEscritorio);

      expect(find.text('Dirección'), findsOneWidget);
      expect(find.text('Artículos'), findsOneWidget);
      expect(find.text('Peso'), findsOneWidget);
      expect(find.text('Entrega'), findsOneWidget);
    });

    testWidgets('y ahí tampoco se parte ninguna palabra', (tester) async {
      await pintar(tester, ancho: anchoDeEscritorio);

      for (final texto in ['Completada', 'sin cotizar']) {
        final caja = tester.getRect(find.text(texto));
        expect(
          caja.width,
          greaterThan(caja.height),
          reason: '«$texto» a $anchoDeEscritorio px: $caja',
        );
        expect(caja.right, lessThanOrEqualTo(anchoDeEscritorio));
      }
    });
  });
}
