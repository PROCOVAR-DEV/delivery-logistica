// CUÁNTAS FACTURAS HAY EN CADA ESTADO DE REPARTO (21/10/2026, Jose: «no vi los estados de las
// facturas»): es la nota que lleva cada opción del filtro «Estado de reparto». Tiene que contar lo
// MISMO que la lista cuando se elige esa opción, con el resto de filtros puestos, y repintarse sola
// cuando entra algo (en la web la base nace vacía).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;
  late ProviderContainer c;

  setUp(() async {
    base = baseDePrueba();
    await sembrarLosOnce(base);
    c = ProviderContainer(overrides: [baseProvider.overrideWithValue(base)]);
  });

  tearDown(() async {
    c.dispose();
    await base.close();
  });

  /// El valor del proveedor cuando ya salió: se escucha (un proveedor sin oyente no se queda vivo) y se
  /// espera en tiempo real a que la base conteste.
  Future<Map<RepartoFiltro, int>> conteo() async {
    c.listen(conteoPorRepartoProvider, (_, _) {});
    for (var i = 0; i < 100; i++) {
      final v = c.read(conteoPorRepartoProvider).value;
      if (v != null) return v;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('el conteo no salió en 5 s');
  }

  test('cada estado cuenta lo mismo que la lista al elegirlo', () async {
    final cuenta = await conteo();
    final consultas = ConsultasPedidos(base);

    for (final r in RepartoFiltro.values) {
      final esperado = await consultas
          .contar(const FiltrosPedidos().copiarCon(reparto: r))
          .first;
      expect(cuenta[r], esperado, reason: 'estado ${r.param}');
    }
    // No es un cero de relleno: hay facturas en algún estado.
    expect(cuenta[RepartoFiltro.cualquiera], greaterThan(0));
  });

  test('respeta el resto de filtros puestos', () async {
    c
        .read(filtrosPedidosProvider.notifier)
        .cambiar((f) => f.copiarCon(municipio: 'Florida'));
    final cuenta = await conteo();
    final todas = const FiltrosPedidos().copiarCon(municipio: 'Florida');
    final esperado = await ConsultasPedidos(base).contar(todas).first;

    expect(cuenta[RepartoFiltro.cualquiera], esperado);
    expect(
      cuenta[RepartoFiltro.cualquiera],
      lessThan(
        await ConsultasPedidos(base).contar(const FiltrosPedidos()).first,
      ),
      reason: 'con un municipio puesto salen menos que sin él',
    );
  });
}
