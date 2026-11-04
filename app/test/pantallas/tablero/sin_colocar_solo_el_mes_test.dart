// «SIN COLOCAR» ARRANCA EN EL MES EN CURSO — Jose, 04/11/2026.
//
// «Si ya pasaron su fecha no las muestres: debería salir el mes, no ponerle todas». Las pruebas de septiembre y octubre que se quedaron sin
// ruta en La Habana metían ruido a quien arma el día. Se ata: que el filtro inicial es el día 1 del MES DE CUBA (con el reloj del
// aparato en UTC o en cualquier huso), que quien quiere ver más atrás lo puede quitar, y que «Limpiar» vuelve al mes y no a «todo».

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

ProviderContainer _con(DateTime ahora) {
  final c = ProviderContainer(
    overrides: [relojProvider.overrideWithValue(() => ahora)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('arranca en el día 1 del mes en curso, sin «hasta»', () {
    final f = _con(DateTime.utc(2026, 11, 4, 15)).read(filtrosTableroProvider);
    expect(f.desde, DateTime(2026, 11, 1));
    expect(f.hasta, isNull);
  });

  test('el mes es el de CUBA: a las 02:00 UTC del 1 de diciembre aún es noviembre allí', () {
    // 02:00 UTC = 22:00 del 30 de noviembre en Cuba (UTC-4 hasta nov 2027): el mes en curso sigue siendo noviembre.
    final f = _con(DateTime.utc(2026, 12, 1, 2)).read(filtrosTableroProvider);
    expect(f.desde, DateTime(2026, 11, 1));
    // y a las 05:00 UTC ya es 1 de diciembre en Cuba
    final g = _con(DateTime.utc(2026, 12, 1, 5)).read(filtrosTableroProvider);
    expect(g.desde, DateTime(2026, 12, 1));
  });

  test(
    'se puede quitar el «desde» para ver más atrás, y «Limpiar» vuelve al mes',
    () {
      final c = _con(DateTime.utc(2026, 11, 4, 15));
      final n = c.read(filtrosTableroProvider.notifier);
      n.poner(c.read(filtrosTableroProvider).copiaCon(quitarDesde: true));
      expect(c.read(filtrosTableroProvider).desde, isNull);
      n.limpiar();
      expect(c.read(filtrosTableroProvider).desde, DateTime(2026, 11, 1));
    },
  );

  test('los demás filtros siguen sin valor: solo el mes viene puesto', () {
    final f = _con(DateTime.utc(2026, 11, 4, 15)).read(filtrosTableroProvider);
    expect(f.q, isNull);
    expect(f.municipio, isNull);
    expect(f.vendedores, isEmpty);
    expect(f.kmMax, isNull);
    expect(f.conCobroDeDomicilio, isNull);
  });
}
