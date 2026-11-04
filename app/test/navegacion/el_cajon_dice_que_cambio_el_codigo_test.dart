import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/cajon_del_cuadre.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/sincro/cuadre.dart';

/// El aviso de que el servidor cambió el código de una ruta hecha en el aparato (04/11/2026): el cajón dice cuál era, cuál es, que la ruta es la
/// misma, y NO habla de «datos quitados» cuando solo cambió un código.
class _Aviso extends AvisoDelCuadre {
  _Aviso(this._r);
  final ResultadoDelCuadre _r;
  @override
  ResultadoDelCuadre? build() => _r;
}

Future<void> abre(WidgetTester t, ResultadoDelCuadre r) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [avisoDelCuadreProvider.overrideWith(() => _Aviso(r))],
      child: const MaterialApp(home: Scaffold(body: CajonDelCuadre())),
    ),
  );
}

void main() {
  testWidgets(
    'solo cambió un código: lo dice con antes y después y no habla de datos quitados',
    (t) async {
      await abre(
        t,
        const ResultadoDelCuadre(
          codigosCambiados: [
            CodigoCambiado(
              rutaId: 'r1',
              antes: '261104-2PF2DB',
              ahora: '261104-9ZZZZZ',
            ),
          ],
        ),
      );
      expect(find.text('Cambió el código de una ruta'), findsOneWidget);
      expect(find.textContaining('261104-2PF2DB'), findsOneWidget);
      expect(find.textContaining('261104-9ZZZZZ'), findsOneWidget);
      expect(find.textContaining('La ruta es la misma'), findsOneWidget);
      expect(
        find.textContaining('guardaba datos que el servidor ya no tiene'),
        findsNothing,
      );
    },
  );

  testWidgets('con facturas quitadas Y un código cambiado dice las dos cosas', (
    t,
  ) async {
    await abre(
      t,
      const ResultadoDelCuadre(
        quitadas: [
          QuitadaDelCuadre(
            coleccion: 'orders',
            id: 'p1',
            etiqueta: 'Factura 1 · Ana',
          ),
        ],
        codigosCambiados: [
          CodigoCambiado(rutaId: 'r1', antes: 'A', ahora: 'B'),
        ],
      ),
    );
    expect(find.text('Se quitaron datos que ya no existen'), findsOneWidget);
    expect(find.textContaining('A  →  B'), findsOneWidget);
    expect(
      find.textContaining('guardaba datos que el servidor ya no tiene'),
      findsOneWidget,
    );
  });
}
