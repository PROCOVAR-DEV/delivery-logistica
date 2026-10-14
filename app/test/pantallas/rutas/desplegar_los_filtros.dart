// DESPLEGAR LOS FILTROS DE RUTAS EN UNA PRUEBA.
//
// Desde el issue 6 de Amado (punto 3) la sección de filtros del Planificador de
// Rutas **arranca plegada con los dos paneles** (`filtrosPlegadosProvider`), así
// que las pruebas de escritorio que tocan un filtro tienen que abrirla antes,
// igual que lo hace una persona. En el teléfono arranca desplegada y esto no
// hace nada: se puede llamar siempre.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/barra_de_filtros.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';

Future<void> desplegarLosFiltros(WidgetTester tester) async {
  if (find.byType(BarraDeFiltros).evaluate().isNotEmpty) return;
  await tester.tap(find.byKey(TextosDeLosFiltrosDeRutas.clavePlegar));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
