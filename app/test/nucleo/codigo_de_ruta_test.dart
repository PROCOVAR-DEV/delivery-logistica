// El código de una ruta sale de su UUIDv7 y lo calculan IGUAL el aparato y el
// servidor. Lee el MISMO fichero que `api/internal/api/codigo_de_ruta_test.go`
// (`docs/codigo-de-ruta.casos.json`), sacado de una implementación independiente.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/cola/provisionales.dart';
import 'package:reparto/nucleo/codigo_de_ruta.dart';

void main() {
  final fichero = File('../docs/codigo-de-ruta.casos.json');

  test('el fichero compartido existe y trae casos', () {
    expect(fichero.existsSync(), isTrue, reason: 'sin ${fichero.path} no hay nada que ate los dos lados');
    final casos = (jsonDecode(fichero.readAsStringSync()) as Map)['casos'] as List;
    expect(casos.length, greaterThanOrEqualTo(8));
  });

  final casos = fichero.existsSync()
      ? ((jsonDecode(fichero.readAsStringSync()) as Map)['casos'] as List)
            .cast<Map<String, dynamic>>()
      : const <Map<String, dynamic>>[];
  for (final c in casos) {
    test('${c['nota']}: ${c['id']} -> ${c['codigo']}', () {
      expect(codigoDeRutaDe(c['id'] as String), c['codigo']);
    });
  }

  test('un id nuevo del aparato da un código corto, sin prefijo y con su fecha de hoy', () {
    final id = Provisionales.nuevoIdReal();
    final codigo = codigoDeRutaDe(id);
    expect(RegExp(r'^\d{6}-[0-9A-HJKMNP-TV-Z]{6}$').hasMatch(codigo), isTrue, reason: codigo);
    expect(codigoDeRutaDe(id), codigo);
    final hoy = DateTime.now().toUtc();
    String dos(int v) => v.toString().padLeft(2, '0');
    expect(codigo.substring(0, 6), '${dos(hoy.year % 100)}${dos(hoy.month)}${dos(hoy.day)}');
  });

  test('lo que no es un UUID se rechaza', () {
    expect(() => codigoDeRutaDe('local-9f3a2b7c'), throwsFormatException);
  });
}
