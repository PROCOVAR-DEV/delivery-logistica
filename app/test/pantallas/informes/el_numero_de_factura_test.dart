// EL NÚMERO DE FACTURA DE LOS REPORTES: LA REGLA, ATADA AL SERVIDOR.
//
// Issue 9 de Amado: «Adicionar la factura como elemento de referencia
// importante: adicionar a los reportes la columna de facturas».
//
// La regla (manda `operationNumber`, respalda `facturaNumero`, si faltan los dos
// no hay número) está escrita DOS veces: aquí (`NumeroDeFactura`) y en Go
// (`api/internal/api/informes.go`, `numeroDeFactura`), porque el informe de la
// APK, del escritorio y de la web lo arma esta aplicación con su base local y
// `GET /api/reports` lo arma el servidor. Si se separan, el mismo informe lleva
// un número en la pantalla y otro en el fichero que baja el servidor, y no
// falla nada: se lee igual de bien (CLAUDE.md §3-bis).
//
// Los casos NO están escritos aquí: se leen de `docs/numero-de-factura.casos.json`,
// el MISMO fichero que lee `api/internal/api/numero_de_factura_casos_compartidos_test.go`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/numero_de_factura.dart';

/// El MISMO fichero que lee la prueba del servidor.
const _rutaDeLosCasos = '../docs/numero-de-factura.casos.json';

Map<String, dynamic> _casos() =>
    jsonDecode(File(_rutaDeLosCasos).readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> _lista(String clave) =>
    (_casos()[clave] as List<dynamic>).cast<Map<String, dynamic>>();

void main() {
  group('resolver: la factura es `factura_numero` y sin él no hay número', () {
    final casos = _lista('resolver');

    test('el fichero de casos no está vacío ni le falta el caso principal', () {
      // Una prueba sobre una lista vacía sale verde sin haber comprobado nada,
      // y quitar el caso del JSON no puede dejar la regla sin vigilante.
      expect(casos, isNotEmpty);
      expect(
        casos.map((c) => c['nombre']),
        contains('un número de Ventra se dice tal cual'),
      );
    });

    for (final c in casos) {
      test(c['nombre'] as String, () {
        final salio = NumeroDeFactura.de(c['facturaNumero'] as String?);
        expect(
          NumeroDeFactura.separar(c['facturaNumero'] as String?),
          (c['separadas'] as List<dynamic>).cast<String>(),
        );
        expect(
          salio,
          c['esperado'],
          reason:
              'Con facturaNumero=${jsonEncode(c['facturaNumero'])} el número tiene '
              'que ser ${jsonEncode(c['esperado'])} y salió ${jsonEncode(salio)}. '
              'Es la misma regla que `numeroDeFactura` en '
              'api/internal/api/informes.go: si cambia, cambian los DOS lados y '
              '$_rutaDeLosCasos.',
        );
      });
    }
  });

  group('agrupar: los números de un camión, sin repetir y en su orden', () {
    final casos = _lista('agrupar');

    test('el fichero de casos no está vacío', () => expect(casos, isNotEmpty));

    for (final c in casos) {
      test(c['nombre'] as String, () {
        final numeros = [
          for (final p
              in (c['pedidos'] as List<dynamic>).cast<Map<String, dynamic>>())
            NumeroDeFactura.de(p['facturaNumero'] as String?),
        ];
        final g = NumeroDeFactura.agrupar(numeros);
        expect(g.facturas, (c['facturas'] as List<dynamic>).cast<String>());
        expect(g.sinFactura, c['sinFactura']);
      });
    }
  });

  // Lo que dice la celda. Aquí NO hay fichero compartido: el texto de la
  // pantalla y del Excel es de este lado.
  group('texto: cómo se dice la lista de un camión', () {
    FacturasDeUnGrupo grupo(List<String> facturas, [int sin = 0]) =>
        (facturas: facturas, sinFactura: sin);

    test('con pocas, salen todas', () {
      expect(
        NumeroDeFactura.texto(grupo(['A-1', 'A-2']), visibles: 2),
        'A-1, A-2',
      );
    });

    // La pareja: pasarse del tope NO calla lo que se queda fuera.
    test('con más de las visibles, dice cuántas quedan fuera', () {
      expect(
        NumeroDeFactura.texto(grupo(['A-1', 'A-2', 'A-3', 'A-4']), visibles: 2),
        'A-1, A-2 y 2 más',
        reason:
            'Una lista cortada sin decirlo es esconder facturas: quien la lee '
            'cree que el camión sólo llevó dos.',
      );
    });

    test('sin tope salen todas, que es lo del Excel', () {
      expect(
        NumeroDeFactura.texto(grupo(['A-1', 'A-2', 'A-3', 'A-4'])),
        'A-1, A-2, A-3, A-4',
      );
    });

    test('los pedidos sin número se dicen aparte, no se esconden', () {
      expect(
        NumeroDeFactura.texto(grupo(['A-1'], 2), visibles: 2),
        'A-1 · 2 sin número',
      );
      expect(NumeroDeFactura.texto(grupo([], 3), visibles: 2), '3 sin número');
    });

    test('sin nada que decir, la raya', () {
      expect(NumeroDeFactura.texto(grupo([])), '—');
    });

    // EL TECHO DE UNA CELDA DE EXCEL. 32.767 letras; pasarse hace que el
    // fichero NO ABRA. La pareja de abajo comprueba que, sin pasarse, no se
    // corta nada.
    test('una lista que no cabe en una celda se corta DICIÉNDOLO', () {
      final muchas = [
        for (var i = 0; i < 3000; i++) 'PTB25-261005-${1000 + i}',
      ];
      final texto = NumeroDeFactura.texto(grupo(muchas), maxCaracteres: 30000);
      expect(
        texto.length,
        lessThan(32767),
        reason: 'La celda pasa de 32.767 letras: Excel no abre el fichero.',
      );
      expect(texto, matches(RegExp(r' y \d+ más$')));
      // Por números enteros: ninguno cortado a la mitad.
      final dichas = texto.split(' y ').first.split(', ');
      expect(dichas.every(muchas.contains), isTrue);
      final fuera = int.parse(RegExp(r'y (\d+) más').firstMatch(texto)![1]!);
      expect(dichas.length + fuera, muchas.length);
    });

    test('si cabe, con techo o sin él, no se corta nada', () {
      final pocas = [for (var i = 0; i < 50; i++) 'PTB25-261005-${1000 + i}'];
      expect(
        NumeroDeFactura.texto(grupo(pocas), maxCaracteres: 30000),
        pocas.join(', '),
      );
    });
  });
}
