// Armar una ruta SIN conexion: orden de visita, km, peso, precio, el codigo de
// ruta del aparato y los seis rechazos con su texto literal.
//
// **Los mensajes se comparan caracter a caracter contra el pliego a proposito.**
// Un rechazo local y uno remoto tienen que leerse igual: si aqui dice «no se
// pudo» y el servidor dice «3 de los 8 pedidos ya están en otra ruta», la persona
// aprende que la aplicacion miente a veces.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;
  late RelojFalso reloj;

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime.utc(2026, 9, 14, 16, 5));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(
      base,
      cola,
      reloj: reloj.leer,
      sufijoAparato: 'MSI',
    );
    await sembrarCatalogo(base);

    // Tres paradas en el ecuador, a 0.1 / 0.3 / 0.2 grados de longitud del
    // origen (0,0): asi los km se pueden comprobar a mano.
    await sembrarPedido(
      base,
      id: 'q1',
      cliente: 'Ana',
      folio: 'F-001',
      peso: 100,
      endLat: 0,
      endLng: 0.1,
    );
    await sembrarPedido(
      base,
      id: 'q2',
      cliente: 'Beto',
      folio: 'F-002',
      peso: 200,
      endLat: 0,
      endLng: 0.3,
    );
    await sembrarPedido(
      base,
      id: 'q3',
      cliente: 'Carla',
      folio: 'F-003',
      peso: 300,
      endLat: 0,
      endLng: 0.2,
    );
  });

  tearDown(() => base.close());

  /// Arma y comprueba el mensaje **carácter a carácter**. Es a propósito: el
  /// mismo «no» llega por dos caminos —aquí al armar, o en la bandeja de
  /// rechazados horas después— y leerlo distinto enseña que la aplicación miente
  /// a veces.
  Future<void> esperaRechazo(List<String> pedidoIds, String mensaje) async {
    await expectLater(
      () => acciones.armar(
        vehiculoId: 'V1',
        pedidoIds: pedidoIds,
        origenLat: 0,
        origenLng: 0,
      ),
      throwsA(isA<RechazoLocal>().having((r) => r.mensaje, 'mensaje', mensaje)),
    );
  }

  Future<String> armarLasTres() => acciones.armar(
    vehiculoId: 'V1',
    pedidoIds: ['q1', 'q2', 'q3'],
    origenLat: 0,
    origenLng: 0,
    origenDireccion: 'Almacén central',
    sucursalId: 'B1',
    nombre: 'Reparto de la mañana',
  );

  test('la ruta se arma entera en el aparato y sale con id local', () async {
    final rutaId = await armarLasTres();
    expect(rutaId, startsWith('local-'));

    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();

    // El codigo lleva el sufijo del aparato: sin el, dos sucursales sin red el
    // mismo dia generarian los dos `RT-20260914-001`.
    expect(ruta.routeCode, 'RT-20260914-001-MSI');
    expect(ruta.totalWeight, 600);
    // 10 + 60 + 30 (los `pedidoCosto` sembrados son 10 por defecto) — aqui los
    // tres valen 10, asi que el total es 30.
    expect(ruta.totalPrice, 30);
    // 0.1 + 0.1 + 0.1 (ida por 0.1 → 0.2 → 0.3) + 0.3 de regreso = 0.6 grados.
    expect(ruta.totalDistance, closeTo(11.1195 * 6, 0.05));
    expect(ruta.optimized, isTrue);
    expect(ruta.status, EstadoRuta.planificada);
  });

  test('el orden de visita es el del vecino mas proximo', () async {
    final rutaId = await armarLasTres();
    final paradas = await (base.select(
      base.orders,
    )..where((o) => o.ultimaRutaId.equals(rutaId))).get();
    final porOrden = {for (final p in paradas) p.stopOrder: p.id};
    expect(porOrden[1], 'q1'); // 0.1
    expect(porOrden[2], 'q3'); // 0.2
    expect(porOrden[3], 'q2'); // 0.3

    // `segmentKm` es la distancia RADIAL desde el origen, no la del tramo.
    final q2 = paradas.firstWhere((p) => p.id == 'q2');
    expect(q2.segmentKm, closeTo(11.1195 * 3, 0.05));

    // Y los tres quedan ocupados por la ruta, en las DOS columnas.
    for (final parada in paradas) {
      expect(parada.routeId, rutaId);
      expect(parada.ultimaRutaId, rutaId);
    }
  });

  test(
    'el apunte queda en la cola con el id provisional como bisagra',
    () async {
      final rutaId = await armarLasTres();
      final pendientes = await cola.pendientes().first;
      expect(pendientes.length, 1);

      final apunte = pendientes.single;
      expect(apunte.metodo, 'POST');
      expect(apunte.ruta, '/routes');
      expect(apunte.provisional, rutaId);
      // La hora del APARATO, escrita al encolar.
      expect(apunte.hechoAt, reloj.ahora);

      final cuerpo = ColaDeSalida.cuerpoDe(apunte)! as Map<String, Object?>;
      expect(cuerpo['orderIds'], ['q1', 'q3', 'q2']);
      expect(cuerpo['vehicleId'], 'V1');
      expect(cuerpo['branchId'], 'B1');
    },
  );

  group('los rechazos, con el texto literal del servidor', () {
    test('sin coordenadas de partida', () async {
      expect(
        () => acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: ['q1'],
          origenLat: null,
          origenLng: null,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Las coordenadas del punto de partida son requeridas',
          ),
        ),
      );
    });

    test('sin vehiculo', () async {
      expect(
        () => acciones.armar(
          vehiculoId: null,
          pedidoIds: ['q1'],
          origenLat: 0,
          origenLng: 0,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Se requiere un vehículo para crear la ruta',
          ),
        ),
      );
    });

    test('sin pedidos, con las comillas invertidas del literal', () async {
      expect(
        () => acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: const [],
          origenLat: 0,
          origenLng: 0,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`.',
          ),
        ),
      );
    });

    test('uno que no existe: no se dice si es de otra sucursal', () async {
      // «No existe» y «no es tuyo» se contestan igual a propósito: decir «existe
      // pero es de Holguín» ya es contar algo de Holguín.
      await esperaRechazo(
        const ['no-existe'],
        'El pedido elegido no puede ir en esta ruta: '
        'no-existe (no existe o no es de tu sucursal).',
      );
    });

    // EL MENSAJE QUE MENTÍA — 22/09/2026.
    //
    // Aquí decía siempre «N de los M pedidos ya están en otra ruta. Vuelve a
    // elegirlos.», y la criba descarta por SEIS motivos distintos. El servidor
    // lo arregló el 21/09 y el aparato se quedó con el literal viejo, así que
    // cinco de cada seis veces el aviso señalaba el sitio equivocado.
    //
    // Cada motivo tiene su prueba porque cada uno se arregla de una forma
    // distinta, y ése es justo el punto: «vuelve a elegirlos» sólo vale para
    // uno de los seis.
    group('el motivo que se dice es el de VERDAD', () {
      test('ya va en otra ruta, Y SE NOMBRA la ruta', () async {
        // «Ya va en la ruta RT-20260922-003» dice dónde mirar; «ya va en otra
        // ruta» deja quince rutas que abrir.
        await sembrarRuta(base, id: 'R9', codigo: 'RT-20260922-003');
        await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
          const OrdersCompanion(routeId: Value('R9')),
        );

        await esperaRechazo(
          const ['q1', 'q2', 'q3'],
          '1 de los 3 pedidos elegidos no puede ir en esta ruta: '
          'F-002 (ya va en la ruta RT-20260922-003).',
        );
      });

      test('ya se entregó: va ANTES que la ruta', () async {
        // Un entregado conserva su `routeId`. Mirando la ruta primero se le
        // contaría al logístico que «otro lo subió a un camión» cuando ese
        // pedido ya está en casa del cliente, y lo que hay que hacer es otra
        // cosa. El orden de los motivos no es decorativo.
        await sembrarRuta(base, id: 'R9', codigo: 'RT-20260922-003');
        await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
          OrdersCompanion(
            routeId: const Value('R9'),
            deliveredAt: Value(DateTime.utc(2026, 9, 22)),
          ),
        );

        await esperaRechazo(
          const ['q1', 'q2', 'q3'],
          '1 de los 3 pedidos elegidos no puede ir en esta ruta: '
          'F-002 (ya se entregó y no puede volver a un camión).',
        );
      });

      test('PEDIDO lo archivó', () async {
        // Volver a elegirlo NO lo arregla: hay que desarchivarlo en PEDIDO.
        await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
          const OrdersCompanion(archivado: Value(true)),
        );

        await esperaRechazo(
          const ['q1', 'q2', 'q3'],
          '1 de los 3 pedidos elegidos no puede ir en esta ruta: '
          'F-002 (PEDIDO lo archivó).',
        );
      });

      test('sin coordenadas de entrega', () async {
        await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
          const OrdersCompanion(endLat: Value(null), endLng: Value(null)),
        );

        await esperaRechazo(
          const ['q1', 'q2', 'q3'],
          '1 de los 3 pedidos elegidos no puede ir en esta ruta: '
          'F-002 (sin coordenadas de entrega).',
        );
      });

      test('no vino de PEDIDO', () async {
        await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
          const OrdersCompanion(source: Value('manual')),
        );

        await esperaRechazo(
          const ['q1', 'q2', 'q3'],
          '1 de los 3 pedidos elegidos no puede ir en esta ruta: '
          'F-002 (no vino de PEDIDO).',
        );
      });

      test('varios a la vez, cada uno con el suyo', () async {
        // Dos motivos distintos en el mismo aviso. Si esto se leyera «2 ya están
        // en otra ruta», quien lo lee arreglaría uno y el otro seguiría ahí.
        await sembrarRuta(base, id: 'R9', codigo: 'RT-20260922-003');
        await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
          const OrdersCompanion(routeId: Value('R9')),
        );
        await (base.update(base.orders)..where((o) => o.id.equals('q3'))).write(
          const OrdersCompanion(archivado: Value(true)),
        );

        await esperaRechazo(
          const ['q1', 'q2', 'q3'],
          '2 de los 3 pedidos elegidos no pueden ir en esta ruta: '
          'F-002 (ya va en la ruta RT-20260922-003), F-003 (PEDIDO lo archivó).',
        );
      });

      test('un id repetido no cuenta como un conflicto', () async {
        // Mandar dos veces el mismo id es una lista mal hecha, no un conflicto.
        // Contarlo mandaría a buscar una ruta que no existe.
        await sembrarRuta(base, id: 'R9', codigo: 'RT-20260922-003');
        await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
          const OrdersCompanion(routeId: Value('R9')),
        );

        await esperaRechazo(
          const ['q1', 'q2', 'q2', 'q3'],
          '1 de los 4 pedidos elegidos no puede ir en esta ruta: '
          'F-002 (ya va en la ruta RT-20260922-003).',
        );
      });

      // LA PAREJA DE LA DE ARRIBA, Y ES LA QUE FALTABA — 22/09/2026.
      //
      // La de arriba manda un repetido Y un conflicto de verdad, así que sale
      // un rechazo de todas formas y sólo comprueba el NÚMERO. Con un repetido
      // y nada más, el corte era `pedidos.length < pedidoIds.length`: tres ids
      // devolvían dos filas, `2 < 3` se cumplía, y salía un aviso literalmente
      // vacío —«0 de los 3 pedidos elegidos no pueden ir en esta ruta: .»—
      // sobre dos pedidos libres. Y el servidor los arma, así que el aparato
      // decía que no a lo que la nube dice que sí.
      test('un repetido y NADA MÁS: la ruta se arma', () async {
        final rutaId = await acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: const ['q1', 'q2', 'q2'],
          origenLat: 0,
          origenLng: 0,
          sucursalId: 'B1',
        );

        expect(rutaId, startsWith('local-'));
        // Y cada pedido entra UNA vez: si el repetido se colara como parada, la
        // hoja de ruta mandaría al camión dos veces a la misma puerta.
        final paradas = await (base.select(
          base.orders,
        )..where((o) => o.routeId.equals(rutaId))).get();
        expect(paradas.map((p) => p.id).toList()..sort(), ['q1', 'q2']);
      });
    });

    // `cambiado` NO ENTRA — Jose, 07/10/2026: «en el camión sólo sube lo que
    // cuadra con la factura». Codex lo había dejado pasar (968679f) y esta
    // prueba se reescribió para darle la razón; aquí vuelve la de siempre, con
    // el literal del servidor (`mensajeNoFacturados`, `api/internal/api/
    // rutas.go`). Los textos van escritos a mano, no copiados del código.
    test('en una ruta sólo entra lo facturado y que cuadre', () async {
      await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
        const OrdersCompanion(facturaEstado: Value(EstadoFactura.cambiado)),
      );
      await (base.update(base.orders)..where((o) => o.id.equals('q3'))).write(
        const OrdersCompanion(facturaEstado: Value(null)),
      );

      await esperaRechazo(
        ['q1', 'q2', 'q3'],
        'En una ruta sólo entra lo facturado y que cuadre. 2 no cumplen: '
        'F-002 (cambió en la factura), F-003 (sin cotejar).',
      );
    });

    test('UNA factura cambiada sola tampoco entra', () async {
      // La pareja de la de arriba: sin ella, un `cambiado` que dejara pasar a
      // todos menos al no cotejado seguiria en verde.
      await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
        const OrdersCompanion(facturaEstado: Value(EstadoFactura.cambiado)),
      );
      await esperaRechazo(
        ['q1', 'q2', 'q3'],
        'En una ruta sólo entra lo facturado y que cuadre. 1 no cumplen: '
        'F-002 (cambió en la factura).',
      );
      expect(
        await base.select(base.routes).get(),
        isEmpty,
        reason: 'un rechazo no deja una ruta a medias',
      );
    });

    // LO NUEVO DE AMADO SE CONSERVA (07/10/2026, incidencias 2 y 6): factura con
    // domicilio cobrado y domicilio cotizado en Entrega.
    test('sin domicilio cobrado en la factura no entra', () async {
      await (base.update(base.orders)..where((o) => o.id.equals('q1'))).write(
        const OrdersCompanion(facturaDomicilio: Value(0)),
      );
      await (base.update(base.orders)..where((o) => o.id.equals('q3'))).write(
        const OrdersCompanion(facturaDomicilio: Value(null)),
      );
      await esperaRechazo(
        ['q1', 'q2', 'q3'],
        'En una ruta sólo entra lo facturado con domicilio cobrado. '
        '2 no cumplen: F-001, F-003.',
      );
    });

    test('sin cotizar el domicilio en Entrega no entra', () async {
      await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
        const OrdersCompanion(pedidoCosto: Value(null)),
      );
      await esperaRechazo(
        ['q1', 'q2', 'q3'],
        'No se puede crear la ruta: 1 pedidos no tienen cotizado el '
        'domicilio en Entrega: F-002.',
      );
    });

    test('un domicilio cotizado en CERO si entra: cero es un precio', () async {
      await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
        const OrdersCompanion(pedidoCosto: Value(0)),
      );
      expect(await armarLasTres(), startsWith('local-'));
    });

    // UN CAMION DE BAJA NO SALE — Amado, 07/10/2026 (incidencia 4).
    test('un camión inactivo se rechaza con el literal del servidor', () async {
      await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
        const VehiclesCompanion(isActive: Value(false)),
      );
      await esperaRechazo([
        'q1',
        'q2',
        'q3',
      ], 'El vehículo está inactivo y no se puede asignar a una ruta.');
      // Nada a medias: ni ruta, ni pedidos enganchados, ni apunte en la cola.
      expect(await base.select(base.routes).get(), isEmpty);
      final q1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('q1'))).getSingle();
      expect(q1.routeId, isNull);
      expect(await cola.lote(), isEmpty);
    });

    test('y con el camión activo se arma: la pareja de la anterior', () async {
      // Sin esta, rechazar SIEMPRE dejaria la de arriba en verde.
      await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
        const VehiclesCompanion(isActive: Value(true)),
      );
      expect(await armarLasTres(), startsWith('local-'));
    });

    test(
      'sobrepeso: el peso a un decimal y la capacidad sin formatear',
      () async {
        await (base.update(base.vehicles)..where((v) => v.id.equals('V1')))
            .write(const VehiclesCompanion(capacity: Value(500)));

        expect(
          armarLasTres,
          throwsA(
            isA<RechazoLocal>().having(
              (r) => r.mensaje,
              'mensaje',
              'Peso total (600.0 kg) supera la capacidad del vehículo (500 kg)',
            ),
          ),
        );
      },
    );

    test('igualar la capacidad exacta SI pasa', () async {
      await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
        const VehiclesCompanion(capacity: Value(600)),
      );
      // La comparacion es `>` estricta, como en el servidor.
      await expectLater(armarLasTres(), completes);
    });

    test('un rechazo NO deja nada a medias', () async {
      await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
        const VehiclesCompanion(capacity: Value(500)),
      );
      await expectLater(armarLasTres(), throwsA(isA<RechazoLocal>()));

      expect(await base.select(base.routes).get(), isEmpty);
      expect(await cola.pendientes().first, isEmpty);
    });
  });

  test('los numeros de ruta se van sucediendo en el aparato', () async {
    await armarLasTres();
    await sembrarPedido(
      base,
      id: 'q4',
      cliente: 'Dani',
      peso: 10,
      endLat: 0,
      endLng: 0.4,
    );
    final segunda = await acciones.armar(
      vehiculoId: 'V1',
      pedidoIds: ['q4'],
      origenLat: 0,
      origenLng: 0,
    );
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(segunda))).getSingle();
    expect(ruta.routeCode, 'RT-20260914-002-MSI');
  });
}
