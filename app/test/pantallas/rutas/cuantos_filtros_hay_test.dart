// CUÁNTOS FILTROS HAY PUESTOS — lo que dice el encabezado de la sección de
// filtros cuando está plegada (issue 6 de Amado, punto 3).
//
// Plegar la sección no puede esconder que la lista está acotada, y el número del
// encabezado sale de aquí. Cada filtro cuenta UNO —las dos fechas, cada una—, y
// se prueba filtro a filtro: un `cuantos` que se olvidara de uno solo dejaría el
// encabezado en «Filtros» con la lista recortada por ese filtro, que es justo lo
// que el encabezado viene a impedir.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';

void main() {
  final dia = DateTime(2026, 10, 1);

  test('sin filtros hay cero, y el encabezado dice sólo «Filtros»', () {
    const f = FiltrosRutas();
    expect(f.cuantos, 0);
    expect(f.hayAlguno, isFalse);
    expect(TextosDeLosFiltrosDeRutas.encabezado(0), 'Filtros');
  });

  for (final (nombre, f) in <(String, FiltrosRutas)>[
    ('el buscador', const FiltrosRutas(q: 'RT')),
    ('el camión', const FiltrosRutas(vehiculoId: 'V1')),
    ('la ubicación de salida', const FiltrosRutas(ubicacionSalida: 'PV-STGO')),
    ('la fecha desde', FiltrosRutas(desde: dia)),
    ('la fecha hasta', FiltrosRutas(hasta: dia)),
  ]) {
    test('$nombre cuenta UNO', () {
      expect(f.cuantos, 1);
      expect(f.hayAlguno, isTrue);
    });
  }

  test('los cinco juntos son cinco, y el encabezado concuerda en número', () {
    final todos = FiltrosRutas(
      q: 'RT',
      vehiculoId: 'V1',
      ubicacionSalida: 'PV-STGO',
      desde: dia,
      hasta: dia,
    );
    expect(todos.cuantos, 5);
    expect(TextosDeLosFiltrosDeRutas.encabezado(1), 'Filtros · 1 activo');
    expect(TextosDeLosFiltrosDeRutas.encabezado(2), 'Filtros · 2 activos');
    expect(TextosDeLosFiltrosDeRutas.encabezado(5), 'Filtros · 5 activos');
  });
}
