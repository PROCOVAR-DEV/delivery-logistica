// LA FECHA DE LA FACTURA, EN HORA DE CUBA, CONTRA LOS CASOS COMPARTIDOS — issue 16 de Amado,
// 16/10/2026.
//
// `docs/fecha-de-la-factura.casos.json` es EL MISMO fichero que lee el servidor
// (`fecha_de_la_factura_motor_real_test.go` contra Postgres y
// `fecha_de_la_factura_casos_compartidos_test.go` por HTTP): si alguien cambia un lado, el
// otro se pone rojo. Aquí: el día de Cuba de cada instante (con sus cambios de hora), el
// inicio de cada día, y cada caso contra la base local, que es donde filtran la web, la APK
// y el escritorio. Incluye el caso de Amado: seis facturas del día 15 de pedidos de los días
// 14 y 15 → las seis salen con «del 15 al 15».
//
// Se corre también con el huso del aparato en Cuba (`TZ=America/Havana`): la regla no puede
// depender de él.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/fecha_de_la_factura.dart';

import '../apoyo/base_de_prueba.dart';
import '../pantallas/tablero/apoyo.dart';

const _ruta = '../docs/fecha-de-la-factura.casos.json';

DateTime? _instante(Object? crudo) =>
    crudo == null ? null : DateTime.parse(crudo as String);

DateTime _dia(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]); // un día "de calendario", como el que elige el selector
}

void main() {
  final f = jsonDecode(File(_ruta).readAsStringSync()) as Map<String, dynamic>;
  final pedidos = (f['pedidos'] as List).cast<Map<String, dynamic>>();
  final casos = (f['casos'] as List).cast<Map<String, dynamic>>();
  final instantes = (f['instantes'] as List).cast<Map<String, dynamic>>();
  final inicios = (f['iniciosDeDia'] as List).cast<Map<String, dynamic>>();

  test('el fichero trae lo que hace falta para que la prueba valga', () {
    expect(pedidos, isNotEmpty);
    expect(casos, isNotEmpty);
    expect(instantes, isNotEmpty);
    expect(inicios, isNotEmpty);
  });

  test('el día de Cuba de cada instante, con los cambios de hora', () {
    for (final c in instantes) {
      final d = diaEnCuba(_instante(c['instante'])!);
      expect(
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        c['dia'],
        reason: '${c['instante']} ${c['nota'] ?? ''}',
      );
    }
  });

  test('a qué instante empieza cada día de Cuba', () {
    for (final c in inicios) {
      expect(
        inicioDelDiaEnCuba(_dia(c['dia'] as String)),
        _instante(c['inicio']),
        reason: '${c['dia']} ${c['nota'] ?? ''}',
      );
    }
  });

  group('cada caso, contra la base local', () {
    late BaseLocal base;
    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    for (final c in casos) {
      test(c['nombre'] as String, () async {
        await sembrarSucursal(base);
        for (final p in pedidos) {
          await sembrarPedido(base, id: p['nombre'] as String);
          await (base.update(base.orders)
                ..where((o) => o.id.equals(p['nombre'] as String)))
              .write(
                OrdersCompanion(
                  facturaAt: Value(_instante(p['facturaAt'])),
                  orderDate: Value(_instante(p['orderDate'])),
                  createdAt: Value(_instante(p['createdAt'])),
                ),
              );
        }
        final desde = c['desde'] == null ? null : _dia(c['desde'] as String);
        final hasta = c['hasta'] == null ? null : _dia(c['hasta'] as String);
        final cond = fechaDeLaFacturaEntre(base.orders, desde, hasta);
        final consulta = base.select(base.orders);
        if (cond != null) consulta.where((_) => cond);
        final salen = [for (final o in await consulta.get()) o.id]..sort();
        final esperado = [...(c['esperado'] as List).cast<String>()]..sort();
        expect(salen, esperado, reason: c['nota'] as String? ?? '');
      });
    }
  });
}
