import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// ISSUE 14 DE AMADO: la bajada trae y GUARDA los tipos de vehiculo y la ficha entera
/// de cada camion, para poder verlos y mantenerlos sin conexion.
void main() {
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  final ahora = DateTime(2026, 10, 16, 9);

  setUp(() {
    base = baseDePrueba();
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
  });
  tearDown(() => base.close());

  Map<String, Object?> conjunto([
    List<Object?> puestos = const [],
    List<String> quitados = const [],
  ]) => <String, Object?>{'puestos': puestos, 'quitados': quitados};

  Bajada contra(
    List<Map<String, Object?>> cambios,
    List<PeticionVista> vistas,
  ) {
    var vuelta = 0;
    return Bajada(
      cliente: clienteFalso((p) async {
        vistas.add(p);
        final c = cambios[vuelta.clamp(0, cambios.length - 1)];
        vuelta++;
        return RespuestaFalsa(200, <String, Object?>{
          'hasta': '2026-10-16T0$vuelta:00:00.000Z',
          'completa': vuelta == 1,
          'truncado': false,
          'cambios': c,
        });
      }),
      base: base,
      frescura: frescura,
      reloj: () => ahora,
    );
  }

  Future<void> yaSincronizoAyer() async {
    await frescura.rebajarLosPedidosUnaVez();
    await frescura.rebajarLasRutasUnaVez();
    await frescura.rebajarLosPedidosPorSuAlmacen();
    await frescura.marcar(
      Colecciones.distribuidores,
      hasta: null,
      completa: true,
    );
    await frescura.marcar(
      Colecciones.pedidos,
      hasta: '2026-10-15T08:00:00.000Z',
      completa: true,
    );
  }

  test('guarda los tipos (por sucursal) y la ficha entera del camion', () async {
    await contra([
      <String, Object?>{
        'orders': conjunto(),
        'vehicle_types': conjunto([
          <String, Object?>{
            'id': 't1',
            'nombre': 'truck',
            'costoKmUsd': 0.45,
            'activo': true,
            'branchId': 's1',
          },
          <String, Object?>{
            'id': 't2',
            'nombre': 'van',
            'costoKmUsd': null,
            'activo': false,
            'branchId': 's1',
          },
        ]),
        'vehicles': conjunto([
          <String, Object?>{
            'id': 'v1',
            'name': 'Camión 1',
            'type': 'truck',
            'vehicleTypeId': 't1',
            'costoKmUsd': 0.7,
            'usarParaDomicilio': true,
            'notes': 'aceite',
            'branchId': 's1',
          },
        ]),
      },
    ], []).ciclo();

    final tipos = {
      for (final t in await base.select(base.vehicleTypes).get()) t.id: t,
    };
    expect(tipos['t1']!.branchId, 's1');
    expect(tipos['t2']!.costoKmUsd, isNull, reason: 'vacio es vacio, no cero');
    expect(tipos['t2']!.activo, isFalse);
    final v = (await base.select(base.vehicles).get()).single;
    expect(
      (v.vehicleTypeId, v.tipoNombre, v.costoKmUsd, v.usarParaDomicilio, v.notes),
      ('t1', 'truck', 0.7, true, 'aceite'),
    );
    expect(await frescura.seDescargo(Colecciones.tiposDeVehiculo), isTrue);
  });

  test('`quitados` borra el tipo que el servidor borro', () async {
    await contra([
      <String, Object?>{
        'orders': conjunto(),
        'vehicle_types': conjunto([
          <String, Object?>{'id': 't1', 'nombre': 'a'},
        ]),
      },
    ], []).ciclo();
    expect(await base.select(base.vehicleTypes).get(), isNotEmpty);
    await contra([
      <String, Object?>{
        'orders': conjunto(),
        'vehicle_types': conjunto(const [], ['t1']),
      },
    ], []).ciclo();
    expect(await base.select(base.vehicleTypes).get(), isEmpty);
  });

  test('el aparato que ya sincronizo pide tipos y flota ENTEROS una vez; despues no', () async {
    await yaSincronizoAyer();
    final vistas = <PeticionVista>[];
    final bajada = contra([
      <String, Object?>{
        'orders': conjunto(),
        'vehicle_types': conjunto(),
        'vehicles': conjunto(),
      },
    ], vistas);

    await bajada.ciclo();
    expect(
      (vistas.first.parametros['completas'] as String).split(','),
      containsAll([Colecciones.tiposDeVehiculo, Colecciones.vehiculos]),
      reason: 'sin esto, los tipos y los campos nuevos no vuelven a salir NUNCA',
    );
    await bajada.ciclo();
    expect(vistas.last.parametros.containsKey('completas'), isFalse);
  });

  test('una api anterior (sin la coleccion) no deja marcado lo que no bajo', () async {
    await yaSincronizoAyer();
    final vistas = <PeticionVista>[];
    final bajada = contra([
      <String, Object?>{'orders': conjunto(), 'vehicles': conjunto()},
    ], vistas);
    await bajada.ciclo();
    await bajada.ciclo();
    expect(await frescura.seDescargo(Colecciones.tiposDeVehiculo), isFalse);
    expect(
      vistas.last.parametros['completas'] as String,
      contains(Colecciones.vehiculos),
      reason: 'se sigue pidiendo hasta que una api que la sepa servir conteste',
    );
  });
}
