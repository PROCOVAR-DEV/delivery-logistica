import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/lista_que_se_recoloca.dart';

/// Jose, 15/10/2026: «que no sea una cosa pegada ahí y rígida». Al reordenarse,
/// la tarjeta se DESLIZA de su sitio viejo al nuevo; no salta.
Widget _lista(List<String> ids, {bool sinAnimaciones = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: sinAnimaciones),
    child: Scaffold(
      body: ListaQueSeRecoloca(
        claves: ids,
        child: ListView.builder(
          itemCount: ids.length,
          itemBuilder: (_, i) => SeRecoloca(
            key: ValueKey(ids[i]),
            clave: ids[i],
            child: SizedBox(height: 50, child: Text(ids[i])),
          ),
        ),
      ),
    ),
  ),
);

double _y(WidgetTester tester, String texto) =>
    tester.getTopLeft(find.text(texto)).dy;

void main() {
  testWidgets('la que cambia de puesto pasa ENTRE el sitio viejo y el nuevo', (
    tester,
  ) async {
    await tester.pumpWidget(_lista(['a', 'b', 'c']));
    final vieja = _y(tester, 'c');
    final nueva = _y(tester, 'a');

    await tester.pumpWidget(_lista(['c', 'a', 'b']));
    await tester.pump(const Duration(milliseconds: 120));
    final aMitad = _y(tester, 'c');
    expect(
      aMitad,
      allOf(greaterThan(nueva), lessThan(vieja)),
      reason:
          'A los 120 ms «c» tiene que ir de camino ($vieja → $nueva) y está '
          'en $aMitad: si ya está en $nueva, saltó sin deslizarse.',
    );

    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect(_y(tester, 'c'), nueva, reason: 'Al terminar, en su sitio nuevo.');
  });

  testWidgets('la que entra aparece con un fundido, sin desplazarse', (
    tester,
  ) async {
    await tester.pumpWidget(_lista(['a', 'b']));
    await tester.pumpWidget(_lista(['a', 'nueva', 'b']));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_y(tester, 'nueva'), 50);
    expect(
      find.byType(Opacity).evaluate().isEmpty,
      isTrue,
      reason: 'El fundido es de pintura, no un widget que reconstruya.',
    );
    await tester.pumpAndSettle();
    expect(_y(tester, 'nueva'), 50);
  });

  testWidgets('con «reducir animaciones» va directa a su sitio', (
    tester,
  ) async {
    await tester.pumpWidget(_lista(['a', 'b', 'c'], sinAnimaciones: true));
    final nueva = _y(tester, 'a');
    await tester.pumpWidget(_lista(['c', 'a', 'b'], sinAnimaciones: true));
    expect(_y(tester, 'c'), nueva);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('los toques van a donde se VE la tarjeta mientras se desliza', (
    tester,
  ) async {
    final tocadas = <String>[];
    Widget lista(List<String> ids) => MaterialApp(
      home: Scaffold(
        body: ListaQueSeRecoloca(
          claves: ids,
          child: ListView(
            children: [
              for (final id in ids)
                SeRecoloca(
                  key: ValueKey(id),
                  clave: id,
                  child: GestureDetector(
                    onTap: () => tocadas.add(id),
                    child: SizedBox(height: 50, child: Text(id)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(lista(['a', 'b', 'c']));
    await tester.pumpWidget(lista(['c', 'a', 'b']));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('c'));
    expect(tocadas, ['c']);
    await tester.pumpAndSettle();
  });
}
