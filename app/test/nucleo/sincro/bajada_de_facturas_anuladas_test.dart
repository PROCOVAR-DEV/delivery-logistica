import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// LAS FACTURAS CANCELADAS EN VENTRA QUE SE QUITARON DE SU RUTA BAJAN AL APARATO (esquema 15,
/// 23/10/2026; Jose y Amado: «quitarla e INFORMAR que esa factura ya fue cancelada»).
///
/// El servidor deja la fila ARCHIVADA, así que en `orders` viaja como `quitados` (el aparato la borra y
/// ninguna lista la cuenta) y, aparte, en `facturasAnuladas`, de donde sale la tabla local que alimenta
/// el aviso. Lo que se ata aquí: que se guarda, que `vistaAt` (lo de «Entendido», de ESTE aparato) no
/// lo pisa una bajada, que una factura que VUELVE deja de estar anulada, que a los 7 días se olvida y
/// que un servidor anterior (sin la clave) no rompe nada.
void main() {
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  final ahora = DateTime.utc(2026, 10, 23, 15);

  setUp(() {
    base = baseDePrueba();
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
  });
  tearDown(() => base.close());

  Map<String, Object?> conjunto({
    List<Object?> puestos = const [],
    List<String> quitados = const [],
  }) => <String, Object?>{'puestos': puestos, 'quitados': quitados};

  Map<String, Object?> unaAnulada(
    String id, {
    String? factura = '47412',
    DateTime? cuando,
    String ruta = 'r-centro',
  }) => <String, Object?>{
    'id': id,
    'operationNumber': 'OP-$id',
    'customerName': 'Bodega La Esquina',
    'facturaNumero': factura,
    'branchId': 'suc-stg',
    'anuladaAt': (cuando ?? ahora.subtract(const Duration(hours: 2)))
        .toIso8601String(),
    'anuladaDeRutaId': ruta,
    'updatedAt': ahora.toIso8601String(),
  };

  Future<void> bajar(Map<String, Object?> cambios) async {
    await Bajada(
      cliente: clienteFalso(
        (p) async => RespuestaFalsa(200, <String, Object?>{
          'hasta': '2026-10-23T15:00:00.000Z',
          'completa': false,
          'truncado': false,
          'cambios': cambios,
        }),
      ),
      base: base,
      frescura: frescura,
      reloj: () => ahora,
    ).ciclo();
  }

  Future<void> yaRebajado() async {
    // Que ninguna rebaja una-vez convierta la bajada en completa: lo que se prueba es el contenido.
    await frescura.rebajarLosPedidosUnaVez();
    await frescura.rebajarLasRutasUnaVez();
    await frescura.rebajarLosPedidosPorSuAlmacen();
    await frescura.rebajarLosPedidosPorSuFolio();
    await frescura.rebajarLosPedidosPorLaFacturaDeSusRenglones();
    await frescura.rebajarLasFacturasAnuladas();
  }

  Future<List<FacturaAnulada>> filas() =>
      base.select(base.facturasAnuladas).get();

  test('la anulada se guarda con su número, su cliente, su ruta y su hora, y sale de orders', () async {
    await base.customStatement(
      'INSERT INTO orders (id, customer_name, address, weight, archivado) '
      "VALUES ('p-1', 'Bodega La Esquina', 'Calle 1', 10, 0)",
    );
    await bajar(<String, Object?>{
      'orders': conjunto(quitados: ['p-1']),
      'facturasAnuladas': conjunto(puestos: [unaAnulada('p-1')]),
    });

    final f = (await filas()).single;
    expect(
      (f.id, f.numero, f.cliente, f.rutaId, f.branchId),
      ('p-1', '47412', 'Bodega La Esquina', 'r-centro', 'suc-stg'),
    );
    expect(f.anuladaAt.toUtc(), ahora.subtract(const Duration(hours: 2)));
    expect(f.vistaAt, isNull, reason: 'nadie la ha dado por vista');
    expect(
      await base.select(base.orders).get(),
      isEmpty,
      reason:
          'la fila viva de la factura sale de orders: ninguna lista la cuenta',
    );
  });

  test('sin número de factura cae al número de operación', () async {
    await bajar(<String, Object?>{
      'orders': conjunto(),
      'facturasAnuladas': conjunto(puestos: [unaAnulada('p-1', factura: null)]),
    });
    expect((await filas()).single.numero, 'OP-p-1');
  });

  test(
    'una bajada nueva de la misma anulada NO borra lo visto en este aparato',
    () async {
      await bajar(<String, Object?>{
        'orders': conjunto(),
        'facturasAnuladas': conjunto(puestos: [unaAnulada('p-1')]),
      });
      await (base.update(base.facturasAnuladas)
            ..where((f) => f.id.equals('p-1')))
          .write(FacturasAnuladasCompanion(vistaAt: Value(ahora)));

      await bajar(<String, Object?>{
        'orders': conjunto(),
        'facturasAnuladas': conjunto(puestos: [unaAnulada('p-1')]),
      });

      expect(
        (await filas()).single.vistaAt,
        isNotNull,
        reason: '«Entendido» es de este aparato: si la bajada lo pisara, el aviso volvería cada minuto',
      );
    },
  );

  test(
    'si la factura VUELVE (llega como pedido vivo), ya no está anulada',
    () async {
      await bajar(<String, Object?>{
        'orders': conjunto(),
        'facturasAnuladas': conjunto(puestos: [unaAnulada('p-1')]),
      });
      expect(await filas(), hasLength(1));

      await bajar(<String, Object?>{
        'orders': conjunto(
          puestos: [
            <String, Object?>{
              'id': 'p-1',
              'customerName': 'Bodega La Esquina',
              'address': 'Calle 1',
              'archivado': false,
              'updatedAt': ahora.toIso8601String(),
            },
          ],
        ),
      });

      expect(
        await filas(),
        isEmpty,
        reason: 'el aviso de «se canceló» ya no es verdad',
      );
    },
  );

  test('a los 7 días se olvida, y la de ayer se queda', () async {
    await bajar(<String, Object?>{
      'orders': conjunto(),
      'facturasAnuladas': conjunto(
        puestos: [
          unaAnulada(
            'p-vieja',
            cuando: ahora.subtract(const Duration(days: 8)),
          ),
          unaAnulada('p-ayer', cuando: ahora.subtract(const Duration(days: 1))),
        ],
      ),
    });
    expect((await filas()).map((f) => f.id), ['p-ayer']);
  });

  test(
    'un servidor anterior, sin la clave, no rompe nada ni borra avisos',
    () async {
      await bajar(<String, Object?>{
        'orders': conjunto(),
        'facturasAnuladas': conjunto(puestos: [unaAnulada('p-1')]),
      });
      await bajar(<String, Object?>{'orders': conjunto()});
      expect(await filas(), hasLength(1));
    },
  );

  test('con las rebajas hechas, la bajada por diferencias sigue siendo por diferencias', () async {
    await yaRebajado();
    await frescura.marcar(
      Colecciones.pedidos,
      hasta: '2026-10-23T10:00:00.000Z',
    );
    String? pedido;
    await Bajada(
      cliente: clienteFalso((p) async {
        pedido = p.parametros['desde'] as String?;
        return RespuestaFalsa(200, <String, Object?>{
          'hasta': '2026-10-23T15:00:00.000Z',
          'completa': false,
          'truncado': false,
          'cambios': <String, Object?>{'orders': conjunto()},
        });
      }),
      base: base,
      frescura: frescura,
      reloj: () => ahora,
    ).ciclo();
    expect(pedido, '2026-10-23T10:00:00.000Z');
  });
}
