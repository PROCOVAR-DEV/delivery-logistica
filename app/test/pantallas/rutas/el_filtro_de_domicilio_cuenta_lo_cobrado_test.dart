// EL FILTRO DE DOMICILIO CUENTA LO COBRADO EN LA FACTURA — issue 10 de Amado,
// 15/10/2026.
//
// Caso real de Santiago: PBF26-2610131268, factura 47061, sin marcar domicilio
// y con 1.31 de «ENTREGA A DOMICILIO» en la factura. La regla de entrada ya lo
// deja entrar, pero el filtro `domicilio` miraba sólo la casilla del vendedor, y
// el asistente arranca en «Sólo con domicilio»: lo escondía por defecto.
//
// Los casos NO están escritos aquí: salen de `docs/armado-rechazado.casos.json`
// (`filtroDeDomicilio`), el MISMO fichero que lee el servidor contra Postgres
// (`TestMotorReal_ElFiltroDeDomicilioEsElDelFichero`). Se pregunta a la
// definición (`conDomicilio` y su contrario) y a la lista de disponibles del
// asistente, con los tres valores del filtro y con el de arranque.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/regla_de_entrada.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// El MISMO fichero que lee `api/internal/store/sqlc/consultas_motor_real_test.go`.
const _rutaDeLosCasos = '../docs/armado-rechazado.casos.json';

void main() {
  final casos =
      (((jsonDecode(File(_rutaDeLosCasos).readAsStringSync())
                      as Map<String, dynamic>)['filtroDeDomicilio']
                  as Map<String, dynamic>)['casos']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  test(
    'el fichero trae el caso real con domicilio y casos de los dos lados',
    () {
      expect(
        casos.where((c) => c['conDomicilio'] == true).map((c) => c['nombre']),
        contains('caso-real-PBF26-2610131268'),
      );
      expect(
        casos.where((c) => c['conDomicilio'] == false),
        isNotEmpty,
        reason:
            'sin casos «sin domicilio» no se distingue «filtra bien» de «deja '
            'pasar todo»',
      );
    },
  );

  test('el asistente arranca en «Sólo con domicilio»', () {
    expect(const FiltrosDisponibles().domicilio, DomicilioFiltro.soloCon);
    expect(DomicilioFiltro.soloCon.param, '1');
    expect(DomicilioFiltro.soloSin.param, '0');
  });

  for (final c in casos) {
    final nombre = c['nombre'] as String;
    final nota = c['nota'] as String;
    final con = c['conDomicilio'] as bool;

    test('$nombre: ${con ? 'CON' : 'SIN'} domicilio', () async {
      final base = baseDePrueba();
      addTearDown(base.close);
      await sembrarCatalogo(base);
      await sembrarPedido(
        base,
        id: 'p',
        cliente: nombre,
        folio: c['operationNumber'] as String?,
        facturaEstado: c['facturaEstado'] as String?,
        facturaDomicilio: (c['facturaDomicilio'] as num?)?.toDouble(),
        pedidoCosto: (c['pedidoCosto'] as num?)?.toDouble(),
        requiereDomicilio: c['requiereDomicilio'] as bool?,
        endLat: 21.38,
        endLng: -77.91,
      );

      // 1. La definición y su contrario, sobre la tabla entera: uno y sólo uno.
      final conIds = (await (base.select(
        base.orders,
      )..where(conDomicilio)).get()).map((o) => o.id);
      final sinIds = (await (base.select(
        base.orders,
      )..where((o) => conDomicilio(o).not())).get()).map((o) => o.id);
      expect(
        conIds,
        con ? contains('p') : isNot(contains('p')),
        reason: 'conDomicilio\n$nota',
      );
      expect(
        sinIds,
        con ? isNot(contains('p')) : contains('p'),
        reason: 'su contrario\n$nota',
      );

      // 2. La lista de disponibles del asistente con los tres valores: sale si
      //    el filtro casa y además entra a una ruta (la regla de entrada).
      final consultas = ConsultasRutas(base);
      Future<bool> sale(DomicilioFiltro d) async =>
          (await consultas.disponibles(
            sucursalId: 'B1',
            domicilio: d.param,
          )).any((p) => p.id == 'p');
      final entra = await sale(DomicilioFiltro.cualquiera);
      expect(
        await sale(DomicilioFiltro.soloCon),
        entra && con,
        reason: '«Sólo con domicilio»\n$nota',
      );
      expect(
        await sale(DomicilioFiltro.soloSin),
        entra && !con,
        reason: '«Sólo sin domicilio»\n$nota',
      );

      // 3. El caso real, dicho sin rodeos: entra, sale con el filtro de arranque
      //    y no sale en «Sólo sin domicilio».
      if (nombre == 'caso-real-PBF26-2610131268') {
        expect(entra, isTrue, reason: nota);
        expect(
          await sale(const FiltrosDisponibles().domicilio),
          isTrue,
          reason: 'el arranque del asistente lo esconde\n$nota',
        );
        expect(await sale(DomicilioFiltro.soloSin), isFalse, reason: nota);
      }
    });
  }
}
