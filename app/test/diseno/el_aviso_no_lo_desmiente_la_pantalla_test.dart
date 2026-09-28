// «NADA QUE CUADRE CON «TODA»» ENCIMA DE «TODAS (8)» — 28/09/2026.
//
// Jose, en un SM-A165M, escribiendo `toda` en el buscador de un desplegable:
// salía el aviso de que no cuadraba nada y **dos líneas más abajo estaba
// `Todas (8)`**, que a la vista de quien lee cuadra perfectamente.
//
// El porqué de que esa opción siga ahí es correcto y NO se toca: la primera
// —la de «todos»— es la que DESHACE el filtro, y el buscador se la llevaba
// justo cuando hacía falta. Lo que estaba mal era el aviso, que decía una cosa
// que la propia pantalla desmentía.
//
// Y son DOS piezas distintas con el mismo nombre de clase —`lib/diseno/
// selector.dart` y `lib/pantallas/pedidos/vista/kit.dart`—, así que esto se
// comprueba en las dos: arreglar una y dejar la otra es el §3-bis.
//
// En pareja, como manda el §3-quinquies: el aviso se explica cuando toca y **no
// sale** cuando el buscador sí encuentra algo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/selector.dart' as comun;
import 'package:reparto/pantallas/pedidos/vista/kit.dart' as kit;

void main() {
  // La primera es la salida —la que quita el filtro—, y las otras tres son las
  // buscables. Ninguna contiene `toda`: ése es el caso de Jose.
  const salida = 'Todas (8)';

  Future<void> abrirElComun(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: comun.Selector<String>(
              opciones: const [
                comun.OpcionSelector(valor: '', etiqueta: salida),
                comun.OpcionSelector(valor: 'a', etiqueta: 'Camagüey'),
                comun.OpcionSelector(valor: 'b', etiqueta: 'Holguín'),
                comun.OpcionSelector(valor: 'c', etiqueta: 'Santiago'),
              ],
              valor: null,
              alElegir: (_) {},
              etiquetaVacia: salida,
              siempreConBuscador: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(salida).first);
    await tester.pumpAndSettle();
  }

  Future<void> abrirElDelKit(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: kit.Selector<String>(
              titulo: 'Sucursal',
              valor: '',
              opciones: const [
                kit.OpcionSelector('', salida),
                kit.OpcionSelector('a', 'Camagüey'),
                kit.OpcionSelector('b', 'Holguín'),
                kit.OpcionSelector('c', 'Santiago'),
              ],
              alElegir: (_) {},
              buscadorSiempre: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(salida).first);
    await tester.pumpAndSettle();
  }

  /// Lo que se lee de verdad en el cartel, juntando el `Text` que lo pinta.
  String elAviso(WidgetTester tester) {
    final textos = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) => t.contains('Nada que cuadre con'));
    expect(
      textos,
      isNotEmpty,
      reason: 'no salió ningún aviso, y con «toda» tiene que salir',
    );
    return textos.first;
  }

  for (final caso in <(String, Future<void> Function(WidgetTester))>[
    ('el común de lib/diseno', abrirElComun),
    ('el del kit de Pedidos', abrirElDelKit),
  ]) {
    final (cual, abrir) = caso;

    testWidgets('$cual: el aviso NOMBRA lo que queda debajo y para qué sirve', (
      tester,
    ) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextField).first, 'toda');
      await tester.pumpAndSettle();

      // La salida SIGUE en la lista: eso es lo que está bien y lo que no se
      // toca. Si un día desaparece, quitar el filtro deja de tener camino.
      expect(
        find.text(salida),
        findsWidgets,
        reason:
            'la opción de «todos» es la que DESHACE el filtro y el buscador no '
            'se la puede llevar (28/09/2026)',
      );

      final aviso = elAviso(tester);
      expect(
        aviso,
        contains('«toda»'),
        reason: 'con lo que se escribió, para que se vea la errata',
      );
      // LO QUE SE ARREGLÓ: el aviso nombra la opción que queda debajo y dice
      // para qué está. Sin esto, el cartel afirma que no cuadra nada teniendo
      // «Todas (8)» a dos líneas, y un aviso que la pantalla desmiente se deja
      // de leer — y entonces tampoco se lee el día que dice la verdad.
      expect(
        aviso,
        contains('«$salida»'),
        reason:
            'el aviso tiene que NOMBRAR la opción que sigue en pantalla; si no, '
            'dice una cosa que la propia pantalla desmiente dos líneas más abajo',
      );
      expect(
        aviso,
        contains('quita el filtro'),
        reason:
            'nombrarla no basta: hay que decir PARA QUÉ está ahí, que es lo que '
            'convierte la contradicción en una explicación',
      );
    });

    testWidgets('$cual: LA OTRA MITAD — con resultados no hay aviso ninguno', (
      tester,
    ) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextField).first, 'hol');
      await tester.pumpAndSettle();

      expect(find.text('Holguín'), findsOneWidget);
      expect(
        find.textContaining('Nada que cuadre con'),
        findsNothing,
        reason: 'un aviso que sale siempre deja de leerse (§3-quinquies)',
      );
      // Y tampoco se cuela la coletilla suelta por ningún lado.
      expect(find.textContaining('quita el filtro'), findsNothing);
    });
  }
}
