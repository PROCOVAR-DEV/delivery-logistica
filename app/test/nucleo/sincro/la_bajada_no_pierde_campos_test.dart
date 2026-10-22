// LO QUE EL SERVIDOR MANDA Y EL APARATO NO LEE.
//
// La gemela de `api/internal/api/la_bajada_no_pierde_campos_test.go`, del otro lado del
// cable. El fallo tiene dos mitades y **cada una se puede romper sola**: el 17/09/2026 se
// pudieron quitar los campos de `espejo.go` sin que saltara la suite de Go, y los de
// `bajada.dart` sin que saltara la de Flutter. 283 pruebas verdes con el arreglo
// deshecho entero.
//
// Lo que se ve cuando esto falla: `$0.00` en una ruta de 720 USD, «Sin punto de partida»
// teniendo almacén, los 8.000 clientes del padrón marcados como «Manual», y los pedidos
// sin `orderDate` cayéndose de todos los filtros por fecha. Ni un error, ni una pantalla
// en blanco: números creíbles y equivocados.
//
// Por eso esto **mete el JSON entero y lee la base**: comprobar que la función existe no
// prueba nada; lo que se rompe es que un campo no se copie.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime.utc(2026, 9, 15, 8, 30);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Bajada conEsto(Map<String, Object?> cambios) => Bajada(
    cliente: clienteFalso((PeticionVista p) async {
      if (p.ruta.endsWith('/almacenes')) {
        return RespuestaFalsa(200, <String, Object?>{
          'sucursales': <Object?>[],
        });
      }
      return RespuestaFalsa(200, <String, Object?>{
        'hasta': '2026-09-15T08:00:00.000Z',
        'completa': true,
        'truncado': false,
        'cambios': cambios,
      });
    }),
    base: base,
    frescura: RegistroDeFrescura(base, reloj: () => ahora),
    reloj: () => ahora,
  );

  Map<String, Object?> conjunto(List<Object?> puestos) => <String, Object?>{
    'puestos': puestos,
    'quitados': <String>[],
  };

  test('la ruta llega con su importe, su dirección y sus fechas', () async {
    await conEsto(<String, Object?>{
      'routes': conjunto([
        <String, Object?>{
          'id': 'r-1',
          'name': 'Minas',
          'routeCode': 'RT-001',
          'status': EstadoRuta.completada,
          'originAddress': 'Almacén Camagüey, Carretera Central km 3',
          'originLat': 21.38,
          'originLng': -77.91,
          'totalDistance': 33.6,
          'totalWeight': 800.0,
          'totalPrice': 720.0,
          'deliveryDate': '2026-09-14T10:00:00.000Z',
          'startedAt': '2026-09-14T11:00:00.000Z',
          'finishedAt': '2026-09-14T16:05:00.000Z',
          'createdAt': '2026-09-14T09:00:00.000Z',
          'updatedAt': '2026-09-14T16:05:00.000Z',
        },
      ]),
    }).ciclo();

    final r = await (base.select(
      base.routes,
    )..where((t) => t.id.equals('r-1'))).getSingle();

    // EL IMPORTE. Es el que Jose vio en cero sobre una ruta de 720.
    expect(
      r.totalPrice,
      720.0,
      reason:
          'LA RUTA LLEGA CON \$0.00: el servidor manda `totalPrice` y la '
          'bajada no lo lee. Un cero se lee bien y está mal.',
    );
    expect(
      r.originAddress,
      'Almacén Camagüey, Carretera Central km 3',
      reason:
          'sin esto la tarjeta dice «Sin punto de partida» teniendo almacén',
    );
    expect(r.deliveryDate, isNotNull, reason: 'la fecha sale como una raya');
    // Salida y regreso: son la línea de horario de la hoja del post-despacho.
    expect(r.startedAt, isNotNull);
    expect(r.finishedAt, isNotNull);
  });

  test('el pedido llega con `createdAt`, que es su red de la fecha', () async {
    await conEsto(<String, Object?>{
      'orders': conjunto([
        <String, Object?>{
          'id': 'p-1',
          'customerName': 'Bodega El Cruce',
          'address': 'Km 8',
          'weight': 800.0,
          'status': 'pending',
          // **SIN `orderDate`**, que es el caso de verdad: PEDIDO lo manda
          // nulo (es `narg` en `GuardarPedidoDelEspejo`).
          'createdAt': '2026-09-14T09:00:00.000Z',
          'updatedAt': '2026-09-14T09:00:00.000Z',
        },
      ]),
    }).ciclo();

    final p = await (base.select(
      base.orders,
    )..where((t) => t.id.equals('p-1'))).getSingle();

    expect(
      p.createdAt,
      isNotNull,
      reason:
          'UN PEDIDO SIN FECHA SE CAE DE TODOS LOS RANGOS: `repositorio_'
          'pedidos.dart` acota por `orderDate` y, si no lo trae, por '
          '`createdAt`. Con esto nulo esa rama no puede ser cierta nunca, y el '
          'pedido desaparece de cualquier filtro por fecha en la APK y el '
          'escritorio — mientras el servidor y la web sí lo devuelven.',
    );
  });

  test(
    'el pedido llega con su factura: el número Y cuándo se facturó',
    () async {
      // Amado, issues 6 y 8 (14/10/2026): el detalle dice cuándo se facturó y «Sin
      // colocar» va por la fecha de la factura. `orders.factura_at` existía y NADIE la
      // escribía: valía NULL en todo el aparato y todo lo anterior caía, sin un error, a
      // la fecha del pedido.
      await conEsto(<String, Object?>{
        'orders': conjunto([
          <String, Object?>{
            'id': 'p-1',
            'customerName': 'Bodega El Cruce',
            'address': 'Km 8',
            'weight': 800.0,
            'status': 'pending',
            'facturaEstado': 'igual',
            'facturaNumero': '1024237',
            'facturaAt': '2026-10-12T09:30:00.000Z',
            'updatedAt': '2026-10-12T09:30:00.000Z',
          },
        ]),
      }).ciclo();

      final p = await (base.select(
        base.orders,
      )..where((t) => t.id.equals('p-1'))).getSingle();

      expect(p.facturaNumero, '1024237');
      expect(
        p.facturaAt?.toUtc(),
        DateTime.utc(2026, 10, 12, 9, 30),
        reason:
            '`facturaAt` no se copia: la columna se queda nula, el detalle no puede '
            'decir cuándo se facturó y «Sin colocar» se ordena por la fecha del pedido.',
      );
    },
  );

  test('el pedido llega con el almacén del que sale (15/10/2026)', () async {
    // Con él, «Sin colocar» pone primero los del almacén elegido arriba también sin
    // señal. Sin copiarlo, la columna se queda nula y la APK ordena distinto que la web.
    await conEsto(<String, Object?>{
      'orders': conjunto([
        <String, Object?>{
          'id': 'p-1',
          'customerName': 'Bodega El Cruce',
          'address': 'Km 8',
          'weight': 800.0,
          'status': 'pending',
          'almacenSalidaCodigo': '2',
          'updatedAt': '2026-10-12T09:30:00.000Z',
        },
      ]),
    }).ciclo();

    final p = await (base.select(
      base.orders,
    )..where((t) => t.id.equals('p-1'))).getSingle();
    expect(p.almacenSalidaCodigo, '2');
  });

  test('el renglón llega con la factura de la que sale (issue 22)', () async {
    // Sin copiarla, `facturaNumero` se queda nulo y «Por producto y factura» deja juntas
    // las facturas de la entrega: la fila de Maikel, «47359, 47360» con cantidad 50.
    // Y el renglón que no la trae queda NULO: no hereda la de otro ni la de la entrega.
    await conEsto(<String, Object?>{
      'orders': conjunto([
        <String, Object?>{
          'id': 'p-1',
          'customerName': 'Bodega El Cruce',
          'address': 'Km 8',
          'weight': 800.0,
          'status': 'pending',
          'facturaNumero': '47359, 47360',
          'updatedAt': '2026-10-12T09:30:00.000Z',
          'items': <Object?>[
            <String, Object?>{
              'id': 'r-1',
              'linea': 1,
              'description': 'CERVEZA',
              'quantity': 30,
              'facturaNumero': '47359',
            },
            <String, Object?>{
              'id': 'r-2',
              'linea': 2,
              'description': 'CERVEZA',
              'quantity': 42,
              'facturaNumero': '47360',
            },
            <String, Object?>{
              'id': 'r-3',
              'linea': 3,
              'description': 'MALTA',
              'quantity': 6,
              'facturaNumero': null,
            },
          ],
        },
      ]),
    }).ciclo();

    final r = await (base.select(
      base.orderItems,
    )..orderBy([(t) => OrderingTerm.asc(t.linea)])).get();
    expect(r.map((x) => x.facturaNumero), ['47359', '47360', null]);
  });

  test('el pedido llega con su punto de entrega a mano (issue 19)', () async {
    // Sin copiarlos, la etiqueta «Punto puesto a mano» no sale nunca, el número de la
    // parada no se pinta en rojo y «Volver al punto del cliente» no sabe a dónde volver.
    await conEsto(<String, Object?>{
      'orders': conjunto([
        <String, Object?>{
          'id': 'p-1',
          'customerName': 'Bodega El Cruce',
          'address': 'Km 8',
          'weight': 800.0,
          'status': 'pending',
          'puntoManual': true,
          'puntoManualPor': 'Marta Pérez',
          'puntoManualAt': '2026-10-20T09:30:00.000Z',
          'folio': 'PSS26-261020-0731',
          'puntoClienteLat': 21.38,
          'puntoClienteLng': -77.91,
          'puntoClienteAddress': 'Km 8, Carretera Central',
          'updatedAt': '2026-10-20T09:30:00.000Z',
        },
        <String, Object?>{
          'id': 'p-2',
          'customerName': 'Bodega La Rica',
          'address': 'Km 9',
          'weight': 10.0,
          'status': 'pending',
          'updatedAt': '2026-10-20T09:30:00.000Z',
        },
      ]),
    }).ciclo();

    final p = await (base.select(
      base.orders,
    )..where((t) => t.id.equals('p-1'))).getSingle();
    expect(
      p.puntoManual,
      isTrue,
      reason: 'sin esto no hay etiqueta ni número rojo',
    );
    expect(p.puntoManualPor, 'Marta Pérez');
    expect(p.puntoManualAt, isNotNull);
    expect(p.folio, 'PSS26-261020-0731');
    expect(
      (p.puntoClienteLat, p.puntoClienteLng, p.puntoClienteAddress),
      (21.38, -77.91, 'Km 8, Carretera Central'),
      reason: 'sin el punto del cliente, volver a él sin red no tiene a dónde',
    );

    // Ausente es «no es manual»: el servidor de antes no los manda.
    final q = await (base.select(
      base.orders,
    )..where((t) => t.id.equals('p-2'))).getSingle();
    expect((q.puntoManual, q.puntoClienteLat), (false, null));
  });

  test('el almacén llega con su código, que no es el de la sucursal', () async {
    final bajada = Bajada(
      cliente: clienteFalso((PeticionVista p) async {
        return RespuestaFalsa(200, <String, Object?>{
          'sucursales': <Object?>[
            <String, Object?>{
              'codigo': 'STG',
              'almacenes': <Object?>[
                <String, Object?>{
                  'id': 'alm-aurora',
                  'codigo': '2',
                  'nombre': 'AURORA',
                  'latitud': 20.05,
                  'longitud': -75.78,
                },
              ],
            },
          ],
        });
      }),
      base: base,
      frescura: RegistroDeFrescura(base, reloj: () => ahora),
      reloj: () => ahora,
    );
    await bajada.almacenes();

    final a = await base.select(base.warehouses).getSingle();
    expect((a.sucursalCodigo, a.codigo), ('STG', '2'));
  });

  test('el cliente llega con su origen, y no como «Manual»', () async {
    await conEsto(<String, Object?>{
      'customers': conjunto([
        <String, Object?>{
          'id': 'c-1',
          'name': 'Ferretería La Nueva',
          'lat': 21.38,
          'lng': -77.91,
          'sucursalCodigo': 'CAM',
          'source': 'pedido',
          'syncedAt': '2026-09-14T09:00:00.000Z',
        },
      ]),
    }).ciclo();

    final c = await (base.select(
      base.customers,
    )..where((t) => t.id.equals('c-1'))).getSingle();

    expect(
      c.source,
      'pedido',
      reason:
          'LOS 8.000 DEL PADRÓN SALEN COMO «MANUAL»: la insignia de '
          '`tabla_clientes.dart` lee esta columna, y el filtro de origen '
          'contesta al revés — cero para «de PEDIDO» y los ocho mil para '
          '«manual». Una lista creíble y del revés.',
    );
  });

  // `isActive` — Amado, 07/10/2026 (incidencia 4). El servidor lo manda en la
  // bajada de vehiculos; si la bajada no lo lee, TODOS quedan activos y la baja
  // de un camion no sirve de nada. Y un servidor viejo no lo manda: ausente es
  // ACTIVO, o toda la flota desapareceria de los selectores de golpe.
  test('el vehículo llega con `isActive`, y ausente es ACTIVO', () async {
    await conEsto(<String, Object?>{
      'vehicles': conjunto([
        <String, Object?>{
          'id': 'v-baja',
          'name': 'Camión de baja',
          'isActive': false,
          'status': 'available',
        },
        <String, Object?>{
          'id': 'v-alta',
          'name': 'Camión activo',
          'isActive': true,
          'status': 'available',
        },
        <String, Object?>{
          'id': 'v-viejo',
          'name': 'Camión de un servidor viejo',
          'status': 'available',
        },
      ]),
    }).ciclo();

    Future<bool> activo(String id) async => (await (base.select(
      base.vehicles,
    )..where((v) => v.id.equals(id))).getSingle()).isActive;

    expect(
      await activo('v-baja'),
      isFalse,
      reason: 'la baja se pierde al bajar',
    );
    expect(await activo('v-alta'), isTrue);
    expect(
      await activo('v-viejo'),
      isTrue,
      reason:
          'sin el campo es activo: leerlo con `== true` da de baja la flota',
    );
  });
}
