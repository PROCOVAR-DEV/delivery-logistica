// LA REGLA DE ENTRADA A UNA RUTA DEL APARATO ES LA DEL SERVIDOR — issue 10 de
// Amado, 15/10/2026.
//
// Caso real de Santiago: PBF26-2610131268, factura 47061. Se pidio «PARRANDA
// 0.33L ×20» sin marcar domicilio, Ventra facturo otra cosa (`cambiado`) y cobro
// 1.31 de «ENTREGA A DOMICILIO», y Entrega no lo cotizo (solo cotiza los
// marcados). No se podia poner en ruta y tiene que poderse.
//
// Los casos NO estan escritos aqui: salen de `docs/armado-rechazado.casos.json`
// (`reglaDeEntrada`), el MISMO fichero que leen el servidor
// (`TestLaReglaDeEntradaEsLaDelFichero`) y su SQL contra Postgres
// (`TestMotorReal_LaReglaDeEntradaEsLaDelFichero`). Cada caso se pregunta a
// TODAS las piezas del aparato que deciden si un pedido entra: el asistente (con
// el literal del servidor), la zona del tablero, colocar, «Sin colocar», la
// lista de disponibles y el Panel. Si una se separa, se pone en rojo aqui.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../tablero/apoyo.dart';

/// El MISMO fichero que lee `api/internal/api/armado_rechazado_casos_compartidos_test.go`.
const _rutaDeLosCasos = '../docs/armado-rechazado.casos.json';

void main() {
  final casos =
      (((jsonDecode(File(_rutaDeLosCasos).readAsStringSync())
                      as Map<String, dynamic>)['reglaDeEntrada']
                  as Map<String, dynamic>)['casos']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  test('el fichero trae el caso real entrando y casos de los dos lados', () {
    expect(
      casos.where((c) => c['entra'] == true).map((c) => c['nombre']),
      contains('caso-real-PBF26-2610131268'),
    );
    expect(
      casos.where((c) => c['entra'] == false),
      isNotEmpty,
      reason:
          'una prueba que solo mira lo que entra no distingue «deja '
          'entrar lo bueno» de «deja entrar todo»',
    );
  });

  for (final c in casos) {
    final nombre = c['nombre'] as String;
    final nota = c['nota'] as String;
    final entra = c['entra'] as bool;
    final op = c['operationNumber'] as String;
    final factura = c['facturaEstado'] as String?;
    final domicilio = (c['facturaDomicilio'] as num?)?.toDouble();
    final costo = (c['pedidoCosto'] as num?)?.toDouble();
    final marcado = c['requiereDomicilio'] as bool?;

    test('$nombre: ${entra ? 'ENTRA' : 'no entra'}', () async {
      final base = baseDePrueba();
      addTearDown(base.close);
      await sembrarSucursal(base);
      await sembrarAlmacen(base);
      await sembrarCamion(base, id: 'v1', capacidad: 5000);
      await sembrarPedido(
        base,
        id: 'p',
        operacion: op,
        facturaEstado: factura,
        facturaDomicilio: domicilio,
        costo: costo,
        domicilio: marcado,
      );
      final pedido = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p'))).getSingle();

      // 1. La zona del tablero: la tarjeta de este pedido, con sus datos.
      final tarjeta = TarjetaPedido(
        pedidoId: 'p',
        operationNumber: op,
        customerName: 'Cliente',
        address: 'Calle 1',
        weight: 100,
        kmAlAlmacen: 1,
        mismoCliente: 1,
        facturaEstado: factura,
        facturaDomicilio: domicilio,
        pedidoCosto: costo,
        requiereDomicilio: marcado,
      );
      expect(
        tarjeta.motivoDeNoSubir == null,
        entra,
        reason: 'la zona dice «${tarjeta.motivoDeNoSubir}»\n$nota',
      );

      // 2. «Sin colocar» del tablero.
      final origen = await ConsultasTablero(base).almacenDe(sucursalStg);
      final izquierda = await ConsultasTablero(base)
          .sinColocar(sucursalStg, origen);
      expect(
        izquierda.pedidos.map((t) => t.pedidoId),
        entra ? contains('p') : isNot(contains('p')),
        reason: '«Sin colocar»\n$nota',
      );

      // 3. La lista de disponibles del asistente.
      final disponibles = await ConsultasRutas(base)
          .disponibles(sucursalId: sucursalStg);
      expect(
        disponibles.map((p) => p.id),
        entra ? contains('p') : isNot(contains('p')),
        reason: 'disponibles\n$nota',
      );

      // 4. El Panel: «Pedidos sin ruta».
      final cifras = await ConsultasPanel(base)
          .cifras(sucursalId: sucursalStg)
          .first;
      expect(cifras.sinRuta, entra ? 1 : 0, reason: 'Panel\n$nota');

      // 5. Colocar: no mira la factura (tampoco el servidor), así que sólo se
      //    le pregunta con la factura en regla.
      if (factura == EstadoFactura.igual || factura == EstadoFactura.cambiado) {
        expect(
          porQueNoSePuedeColocar(pedido) == null,
          entra,
          reason: 'colocar dice «${porQueNoSePuedeColocar(pedido)}»\n$nota',
        );
      }

      // 6. El asistente, con el «no» del servidor letra por letra.
      final acciones = AccionesDeRuta(
        base,
        ColaDeSalida(base),
        sufijoAparato: 'MSI',
      );
      Future<String> armar() => acciones.armar(
        vehiculoId: 'v1',
        pedidoIds: ['p'],
        origenLat: almacenLat,
        origenLng: almacenLng,
      );
      if (entra) {
        expect(await armar(), startsWith('local-'), reason: nota);
      } else {
        await expectLater(
          armar,
          throwsA(
            isA<RechazoLocal>().having(
              (r) => r.mensaje,
              'mensaje',
              c['mensaje'] as String,
            ),
          ),
        );
      }
    });
  }
}
