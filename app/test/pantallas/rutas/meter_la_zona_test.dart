import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/meter_la_zona.dart';

/// METER UNA ZONA DEL TABLERO EN LA RUTA, Y DECIR LO QUE SE QUEDA FUERA.
///
/// Jose, 16/09/2026: «no me deja elegir lo q tengo en el tablero q para eso es
/// para yo hacer el tablero con los pedidos... sin necesidad de estar
/// eligiendolos en uno a uno y ya se hizo el estudio antes».
///
/// El atajo es útil y por eso mismo es peligroso: **meter nueve de doce en
/// silencio es su peor versión**. Quien pulsa la zona cree que lleva la zona
/// entera y se entera en el almacén, cargando el camión. Por eso lo que de
/// verdad se comprueba aquí no es que entren, sino que lo que NO entra se
/// cuenta y se nombra.
Pedido _pedido(String id, double kg) => Pedido(
  id: id,
  customerName: 'Cliente $id',
  address: 'Calle $id',
  weight: kg,
  status: 'pending',
  tripLeg: 'ida',
  archivado: false,
);

void main() {
  pruebasDelFiltroDeVehiculos();
  test('una zona entera entra cuando todo está disponible y cabe', () {
    final r = repartirLaZona(
      ids: const ['p1', 'p2', 'p3'],
      disponibles: [_pedido('p1', 10), _pedido('p2', 20), _pedido('p3', 30)],
      yaElegidos: const <String>{},
      pesoActual: 0,
      capacidad: 1000,
    );

    expect(r.entran.map((p) => p.id), ['p1', 'p2', 'p3']);
    expect(r.yaEstaban, 0);
    expect(r.noDisponibles, 0);
    expect(r.noCaben, 0);
    expect(
      parteDeLaZona('Centro', 3, r),
      '3 de 3 de «Centro»',
      reason: 'sin nada que advertir, el parte es una sola frase',
    );
  });

  test('lo que ya no se puede repartir hoy NO entra, y se dice', () {
    // `p2` está en la zona pero ya no está en disponibles: entró en otra ruta o
    // se archivó desde que se armó el tablero. Meterlo sería fabricar un
    // rechazo al guardar.
    final r = repartirLaZona(
      ids: const ['p1', 'p2', 'p3'],
      disponibles: [_pedido('p1', 10), _pedido('p3', 30)],
      yaElegidos: const <String>{},
      pesoActual: 0,
      capacidad: 1000,
    );

    expect(r.entran.length, 2);
    expect(r.noDisponibles, 1);
    expect(
      parteDeLaZona('Centro', 3, r),
      contains('1 ya no se pueden repartir hoy'),
    );
  });

  test('lo que no cabe NO entra, y se dice', () {
    final r = repartirLaZona(
      ids: const ['p1', 'p2'],
      disponibles: [_pedido('p1', 600), _pedido('p2', 600)],
      yaElegidos: const <String>{},
      pesoActual: 0,
      capacidad: 1000,
    );

    expect(r.entran.map((p) => p.id), ['p1']);
    expect(r.noCaben, 1);
    expect(
      parteDeLaZona('Centro', 2, r),
      contains('1 no caben en el vehículo'),
    );
  });

  test('el peso se acumula: no se compara cada uno contra la capacidad', () {
    // Con 400 ya puestos y un camión de 1000, de dos de 400 sólo cabe uno. Si
    // se comparara pedido a pedido contra la capacidad entrarían los dos y el
    // camión saldría con 1200.
    final r = repartirLaZona(
      ids: const ['p1', 'p2'],
      disponibles: [_pedido('p1', 400), _pedido('p2', 400)],
      yaElegidos: const <String>{},
      pesoActual: 400,
      capacidad: 1000,
    );

    expect(r.entran.length, 1);
    expect(r.noCaben, 1);
  });

  test('los que ya estaban elegidos no se cuentan dos veces', () {
    final r = repartirLaZona(
      ids: const ['p1', 'p2'],
      disponibles: [_pedido('p1', 10), _pedido('p2', 20)],
      yaElegidos: const {'p1'},
      pesoActual: 10,
      capacidad: 1000,
    );

    expect(r.entran.map((p) => p.id), ['p2']);
    expect(r.yaEstaban, 1);
    expect(parteDeLaZona('Centro', 2, r), contains('1 ya estaban'));
  });

  test('sin vehículo todavía no se descarta a nadie por peso', () {
    final r = repartirLaZona(
      ids: const ['p1'],
      disponibles: [_pedido('p1', 99999)],
      yaElegidos: const <String>{},
      pesoActual: 0,
      capacidad: null,
    );

    expect(r.entran.length, 1);
    expect(r.noCaben, 0);
  });
}

/// Un camión de una sucursal, para la prueba del filtro del paso 3.
Vehiculo _camion(String id, String nombre, String? sucursal) => Vehiculo(
  id: id,
  name: nombre,
  capacity: 1000,
  status: 'available',
  usarParaDomicilio: false,
  branchId: sucursal,
  isActive: true,
);

void pruebasDelFiltroDeVehiculos() {
  group('los vehículos del paso 3', () {
    final flota = [
      _camion('v1', 'Camión Habana', 'B-HAB'),
      _camion('v2', 'Camión Santiago', 'B-STG'),
      _camion('v3', 'Otro de Habana', 'B-HAB'),
      _camion('v4', 'Sin sucursal', null),
    ];

    test('sólo salen los DE esa sucursal', () {
      final r = vehiculosDeLaSucursal(flota, 'B-HAB');

      expect(r.map((v) => v.id), ['v1', 'v3']);
      expect(
        r.map((v) => v.name),
        isNot(contains('Camión Santiago')),
        reason:
            'un camión de otra sucursal no está donde sale esta ruta, y el '
            'paso 1 promete que serán los de la elegida',
      );
    });

    test('sin sucursal elegida todavía, salen todos', () {
      // No hay por qué filtrar aún: filtrar por `null` dejaría la lista vacía y
      // parecería que no hay camiones.
      expect(vehiculosDeLaSucursal(flota, null).length, flota.length);
    });

    test('un camión sin sucursal no se cuela en ninguna', () {
      expect(vehiculosDeLaSucursal(flota, 'B-STG').map((v) => v.id), ['v2']);
    });
  });
}
