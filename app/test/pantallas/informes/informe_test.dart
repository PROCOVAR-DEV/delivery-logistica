import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/informes/datos/consultas_informes.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  late ConsultasInformes informes;

  setUp(() async {
    base = baseDePrueba();
    informes = ConsultasInformes(base);

    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'v1',
            name: 'Ford 600',
            plate: const Value('B-123'),
            branchId: const Value('stg'),
          ),
        );
    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'v2',
            name: 'F-350',
            plate: const Value('B-999'),
            branchId: const Value('stg'),
          ),
        );
    await base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: 'r1',
            routeCode: const Value('STG-0912'),
            vehicleId: const Value('v1'),
            branchId: const Value('stg'),
          ),
        );
    await base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: 'r2',
            name: const Value('Vista Alegre'),
            vehicleId: const Value('v2'),
            branchId: const Value('stg'),
          ),
        );
    // Una ruta SIN vehiculo: sus pedidos suman en el resumen pero NO en
    // «Por Vehículo» (contrato §9).
    await base
        .into(base.routes)
        .insert(RoutesCompanion.insert(id: 'r3', branchId: const Value('stg')));
  });

  tearDown(() => base.close());

  Future<void> pedido(
    String id, {
    String? rutaId,
    double? precio,
    double? costo,
    double peso = 10,
    DateTime? creado,
    String? sucursal = 'stg',
  }) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          routeId: Value(rutaId),
          price: Value(precio),
          pedidoCosto: Value(costo),
          weight: Value(peso),
          createdAt: Value(creado ?? DateTime(2026, 9, 10, 12)),
          branchId: Value(sucursal),
        ),
      );

  group('filtros de factura y de ruta (issue 27)', () {
    Future<void> conFactura(
      String id,
      String? factura, {
      String? rutaId,
    }) async {
      await pedido(id, rutaId: rutaId);
      await (base.update(base.orders)..where((o) => o.id.equals(id))).write(
        OrdersCompanion(facturaNumero: Value(factura)),
      );
    }

    Future<List<String>> ids(FiltroDeInforme f) async =>
        ((await informes.mirar(f).first).filas.map((x) => x.id).toList()
          ..sort());

    test('rango de factura: numérico, los dos extremos incluidos', () async {
      await conFactura('a', '999');
      await conFactura('b', '1000');
      await conFactura('c', '1250');
      await conFactura('d', '1300');
      await conFactura('e', '1301');
      expect(
        await ids(
          const FiltroDeInforme(facturaDesde: '1000', facturaHasta: '1300'),
        ),
        ['b', 'c', 'd'],
      );
      // «999» va antes que «1000»: es número, no texto.
      expect(await ids(const FiltroDeInforme(facturaDesde: '999')), [
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
      expect(await ids(const FiltroDeInforme(facturaHasta: '999')), ['a']);
    });

    test(
      'un pedido con varias facturas entra si UNA cae en el rango',
      () async {
        await conFactura('a', '1024237, 1024240');
        await conFactura('b', '1030000');
        expect(
          await ids(
            const FiltroDeInforme(
              facturaDesde: '1024240',
              facturaHasta: '1024250',
            ),
          ),
          ['a'],
        );
      },
    );

    test('sin factura NO entra en cuanto hay un límite de factura', () async {
      await conFactura('a', null);
      await conFactura('b', '5');
      expect(await ids(const FiltroDeInforme(facturaDesde: '1')), ['b']);
      expect(await ids(const FiltroDeInforme()), ['a', 'b']);
    });

    test('con prefijo se compara como texto, sin mirar mayúsculas', () async {
      await conFactura('a', 'F-001');
      await conFactura('b', 'f-005');
      await conFactura('c', 'F-009');
      expect(
        await ids(
          const FiltroDeInforme(facturaDesde: 'F-002', facturaHasta: 'F-006'),
        ),
        ['b'],
      );
    });

    test('ruta: texto contenido en el código o el nombre, sin tildes ni mayúsculas', () async {
      await conFactura('a', '1', rutaId: 'r1'); // STG-0912
      await conFactura('b', '2', rutaId: 'r2'); // Vista Alegre
      await conFactura('c', '3'); // sin ruta
      expect(await ids(const FiltroDeInforme(ruta: 'stg-09')), ['a']);
      expect(await ids(const FiltroDeInforme(ruta: 'vísta')), ['b']);
      expect(await ids(const FiltroDeInforme(ruta: 'zzz')), isEmpty);
    });

    test('se combinan con el vehículo y entre sí', () async {
      await conFactura('a', '10', rutaId: 'r1');
      await conFactura('b', '20', rutaId: 'r1');
      await conFactura('c', '20', rutaId: 'r2');
      expect(
        await ids(
          const FiltroDeInforme(
            ruta: 'stg',
            facturaDesde: '15',
            vehiculoId: 'v1',
          ),
        ),
        ['b'],
      );
    });

    test('copiar: un texto en blanco quita el límite', () {
      const f = FiltroDeInforme(facturaDesde: '5', ruta: 'x');
      final g = f.copiar(facturaDesde: '  ', ruta: '');
      expect(g.facturaDesde, isNull);
      expect(g.ruta, isNull);
      expect(g.hayAlgoPuesto, isFalse);
      expect(f.copiar(facturaHasta: ' 9 ').facturaHasta, '9');
    });
  });

  group('el ingreso de un pedido', () {
    test('es `price` cuando lo tiene', () async {
      await pedido('a', precio: 25, costo: 9);
      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.single.importe, 25);
    });

    test('es `pedidoCosto` cuando no hay `price`', () async {
      // Es el numero que mas facil se equivoca de todo el pliego.
      await pedido('a', costo: 9);
      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.single.importe, 9);
    });

    // LA GUARDA, y hasta el 22/09/2026 esta prueba decia lo CONTRARIO
    // («es 0, no nulo»), que es el fallo que se midio en produccion: `Pedidos`
    // decia «sin cotizar» en todas sus filas y `Reportes -> Detalle de
    // Órdenes` decia `0,00 USD` en las mismas, con el camion cotizado a 1,50
    // USD/km. Un cero ahi no dice «no hay tarifa»: dice que el reparto fue
    // gratis, y se suma en el total que va a contabilidad.
    test('sin ninguno de los dos es `null` = SIN COTIZAR, nunca 0', () async {
      await pedido('a');
      final i = await informes.mirar(const FiltroDeInforme()).first;
      final salio = i.filas.single.importe;
      expect(
        salio,
        isNull,
        reason:
            'Un pedido SIN COTIZAR salio con importe $salio en vez de `null`: '
            'ese numero se suma entero en Ingresos Totales y en la hoja que se '
            'manda a contabilidad, y nadie se entera de que falta.',
      );
    });

    // El nulo se pierde al enganchar el pedido a una ruta:
    // `price = coalesce(sqlc.narg('price'), 0)` en `EngancharPedidoARuta`. O
    // sea que un `price` de CERO sin `pedidoCosto` no es un precio, es ese
    // `coalesce`. Sin esta guarda, `precio ?? costo` se queda con el cero y ni
    // llega a mirar `pedidoCosto`.
    test('un `price` de CERO sin `pedidoCosto` NO es un precio', () async {
      await pedido('a', precio: 0);
      final i = await informes.mirar(const FiltroDeInforme()).first;
      final salio = i.filas.single.importe;
      expect(
        salio,
        isNull,
        reason:
            'El `0` que deja el `coalesce` del servidor al enganchar la orden '
            'a una ruta se colo como precio ($salio): la orden esta SIN '
            'COTIZAR y el informe la cuenta como un reparto gratis.',
      );
    });

    // Y su contraria, que es la que evita pasarse de frenada: un cero puesto a
    // mano SI es una cifra.
    test('un domicilio GRATIS de verdad sigue valiendo 0', () async {
      await pedido('a', costo: 0);
      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(
        i.filas.single.importe,
        0,
        reason:
            'Un `pedidoCosto` de 0 es un domicilio gratis cotizado: es una '
            'cifra, y borrarla seria inventarse un hueco donde no lo hay.',
      );
    });

    test('sin `pedidoCosto` un `price` distinto de cero se respeta', () async {
      // Ese numero no puede venir del `coalesce`: lo pone la APK de Entrega,
      // que es quien cotiza. Tirarlo seria perder un cobro de verdad.
      await pedido('a', precio: 7.5);
      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.single.importe, 7.5);
    });
  });

  // ---------------------------------------------------------------------
  // UN TOTAL A MEDIAS ES PEOR QUE NINGUNO
  //
  // La pareja que le faltaba a `ConsultasInformes.sumaCompleta`, que es el
  // tercer hermano de `TotalesPreDespacho._sumaCompleta` (`impresion/hoja.dart`
  // y `pedidos/datos/repositorio_pedidos.dart`) y el unico que estaba sin
  // guarda. Siempre en pareja: el total completo cuando estan todas, y el
  // rotulo —no una cifra— cuando falta una.
  // ---------------------------------------------------------------------
  group('UN TOTAL A MEDIAS ES PEOR QUE NINGUNO', () {
    group('sumaCompleta', () {
      test('con TODAS las piezas suma entero', () {
        expect(ConsultasInformes.sumaCompleta(const [10.0, 5.5, 0.0]), 15.5);
      });

      test('con UNA que falta el total es `null`, no la suma de las otras', () {
        final salio = ConsultasInformes.sumaCompleta(const [10.0, null, 5.5]);
        expect(
          salio,
          isNull,
          reason:
              'Falta UNA pieza y aun asi salio un total de $salio. Ese numero '
              'se imprime redondo y creible, y nadie lo desmiente: en la hoja '
              'del almacen es cargar de menos y enterarse cuando el camion ya '
              'se fue.',
        );
      });

      // Y que no valga mirar solo la primera ni solo la ultima: el hueco
      // cuenta este donde este.
      test('da igual donde este el hueco: al principio o al final', () {
        final primera = ConsultasInformes.sumaCompleta(const [null, 10.0, 5.5]);
        final ultima = ConsultasInformes.sumaCompleta(const [10.0, 5.5, null]);
        expect(
          primera,
          isNull,
          reason: 'Con el hueco en la PRIMERA posicion salio $primera.',
        );
        expect(
          ultima,
          isNull,
          reason: 'Con el hueco en la ULTIMA posicion salio $ultima.',
        );
      });

      // La unica diferencia a proposito con `TotalesPreDespacho`: aqui una
      // lista vacia es «no hay ninguna orden en el filtro», y eso SI se sabe y
      // vale cero.
      test('sobre una lista vacia da 0, que si es una cifra', () {
        expect(ConsultasInformes.sumaCompleta(const <double?>[]), 0);
      });
    });

    group('el resumen de la pantalla', () {
      test('con todo cotizado, ingresos y promedio son cifras', () async {
        await pedido('a', rutaId: 'r1', precio: 30, peso: 100);
        await pedido('b', rutaId: 'r1', costo: 10, peso: 50);

        final r = (await informes.mirar(const FiltroDeInforme()).first).resumen;
        expect(r.ingresos, 40);
        expect(r.precioPromedio, 20);
        expect(r.sinCotizar, 0);
      });

      test('UNA sola orden sin cotizar deja los dos en `null`, y dice cuantas '
          'faltan', () async {
        await pedido('a', rutaId: 'r1', precio: 30, peso: 100);
        await pedido('b', rutaId: 'r1', peso: 50); // sin cotizar

        final r = (await informes.mirar(const FiltroDeInforme()).first).resumen;
        expect(
          r.ingresos,
          isNull,
          reason:
              'Con una de las dos ordenes sin cotizar, Ingresos Totales salio '
              '${r.ingresos} — que es lo que vale la OTRA— y se lee como el '
              'ingreso del dia entero.',
        );
        expect(
          r.precioPromedio,
          isNull,
          reason:
              'Precio Promedio salio ${r.precioPromedio} sobre una suma '
              'incompleta: un promedio a medias es un numero creible y '
              'equivocado.',
        );
        // Lo que convierte el rotulo en algo que se puede arreglar.
        expect(r.sinCotizar, 1);
        // Y lo que SI se sabe se sigue diciendo: el peso y el numero de
        // ordenes no se caen con el importe.
        expect(r.totalOrdenes, 2);
        expect(r.peso, 150);
      });
    });

    group('Por Vehículo', () {
      test(
        'con todo cotizado, cada camion tiene su total y su promedio',
        () async {
          await pedido('a', rutaId: 'r1', precio: 30, peso: 100);
          await pedido('b', rutaId: 'r1', precio: 10, peso: 50);

          final v =
              (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;
          expect(v.single.ingresos, 40);
          expect(v.single.promedioPorOrden, 20);
          expect(v.single.sinCotizar, 0);
        },
      );

      test('una orden sin cotizar deja SU camion sin total y sin promedio, '
          'y no lo recupera la siguiente', () async {
        // El orden importa: la sin cotizar entra PRIMERO y la buena despues.
        // Si el nulo se recuperase al seguir acumulando, esto saldria en 30.
        await pedido('a', rutaId: 'r1', peso: 10); // sin cotizar
        await pedido('b', rutaId: 'r1', precio: 30, peso: 20);

        final v =
            (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;
        expect(
          v.single.ingresos,
          isNull,
          reason:
              'El camion salio con ${v.single.ingresos} teniendo una orden sin '
              'cotizar: ese es el total de las OTRAS, y en la tabla ocupa el '
              'sitio del total del camion.',
        );
        expect(v.single.promedioPorOrden, isNull);
        expect(v.single.sinCotizar, 1);
        // El peso y las ordenes si se saben, y se siguen diciendo.
        expect(v.single.ordenes, 2);
        expect(v.single.peso, 30);
      });

      // No se puede ordenar por un numero que no se sabe: colar un camion sin
      // total entre los tres primeros de `Top vehículos` seria decir que es de
      // los que mas trae sin tener con que sostenerlo.
      test('un camion sin total va al FINAL, no arriba', () async {
        await pedido('a', rutaId: 'r1', peso: 10); // v1: sin cotizar
        await pedido('b', rutaId: 'r2', precio: 5, peso: 10); // v2: 5

        final v =
            (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;
        expect(
          v.map((f) => f.id).toList(),
          ['v2', 'v1'],
          reason:
              'El camion SIN total se coló por delante de uno que si lo tiene: '
              'en `Top vehículos` eso lo presenta como el que mas trae.',
        );
        expect(
          v.last.ingresos,
          isNull,
          reason:
              'El camion sin cotizar salio con un total de ${v.last.ingresos}: '
              'un cero puesto donde no se sabe, que ademas es lo que lo manda '
              'al final de la lista por el motivo equivocado.',
        );
      });
    });
  });

  group('las cuatro cifras del resumen', () {
    test('total, ingresos, peso y promedio', () async {
      await pedido('a', rutaId: 'r1', precio: 30, peso: 100);
      await pedido('b', rutaId: 'r1', costo: 10, peso: 50);
      await pedido('c', rutaId: 'r2', precio: 20, peso: 30);

      final r = (await informes.mirar(const FiltroDeInforme()).first).resumen;
      expect(r.totalOrdenes, 3);
      expect(r.ingresos, 60);
      expect(r.peso, 180);
      expect(r.precioPromedio, 20);
    });

    test('sin ordenes el promedio es 0, no NaN', () {
      final r = ConsultasInformes.resumir(const <FilaDeInforme>[]);
      expect(r.precioPromedio, 0);
      expect(r.totalOrdenes, 0);
    });
  });

  group('por vehiculo', () {
    test('agrupa, suma y ordena de mas a menos ingreso', () async {
      await pedido('a', rutaId: 'r1', precio: 30, peso: 100);
      await pedido('b', rutaId: 'r1', precio: 10, peso: 50);
      await pedido('c', rutaId: 'r2', precio: 100, peso: 30);

      final v =
          (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;
      expect(v.map((f) => f.nombre).toList(), ['F-350', 'Ford 600']);
      expect(v.last.ordenes, 2);
      expect(v.last.ingresos, 40);
      expect(v.last.peso, 150);
      expect(v.last.promedioPorOrden, 20);
      expect(v.last.placa, 'B-123');
    });

    // LA GUARDA: la clave del grupo es el ID, nunca el nombre.
    //
    // Se agrupaba por nombre, y entonces dos camiones que se llaman igual —el
    // de siempre y su sustituto, o uno por sucursal— se fundian en UNA fila con
    // los ingresos de los dos sumados. Este error ya se cazo una vez en este
    // proyecto. Si vuelve, esta prueba lo dice con esas palabras.
    test('dos camiones que se llaman igual NO se funden en una fila', () async {
      // `v3` se llama exactamente igual que `v1`. Son dos camiones distintos.
      await base
          .into(base.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'v3',
              name: 'Ford 600',
              plate: const Value('B-777'),
              branchId: const Value('stg'),
            ),
          );
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: 'r4',
              routeCode: const Value('STG-0913'),
              vehicleId: const Value('v3'),
              branchId: const Value('stg'),
            ),
          );

      await pedido('a', rutaId: 'r1', precio: 30, peso: 100); // v1
      await pedido('b', rutaId: 'r4', precio: 70, peso: 20); // v3

      final v =
          (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;

      expect(
        v.length,
        2,
        reason:
            'Los dos «Ford 600» se fundieron en una sola fila: se esta '
            'agrupando por NOMBRE y no por el id del vehiculo. Sus ingresos '
            'quedan sumados en un camion que no existe.',
      );
      expect(v.map((f) => f.id).toSet(), {'v1', 'v3'});
      // Y cada uno con lo suyo, no con la suma de los dos.
      expect({for (final f in v) f.id: f.ingresos}, {'v1': 30.0, 'v3': 70.0});
      expect(
        {for (final f in v) f.id: f.placa},
        {'v1': 'B-123', 'v3': 'B-777'},
      );
    });

    test('los pedidos sin vehiculo NO hacen una fila propia', () async {
      await pedido('a', rutaId: 'r3', precio: 30); // ruta sin vehiculo
      await pedido('b', precio: 30); // sin ruta siquiera

      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.porVehiculo, isEmpty);
      // Pero SI suman en el resumen: el ingreso existio.
      expect(i.resumen.ingresos, 60);
    });
  });

  group('el rango de fechas', () {
    test('`hasta` incluye el DIA ENTERO, contado en UTC', () async {
      // Las 23:00 y las 02:00 UTC: el mismo dia 14 para uno y ya el 15 para el
      // otro. Escritos en UTC a proposito, para que la prueba diga lo mismo
      // este el portatil en Cuba o donde sea.
      await pedido('tarde', creado: DateTime.utc(2026, 9, 14, 23), precio: 5);
      await pedido('manana', creado: DateTime.utc(2026, 9, 15, 2), precio: 5);

      final i = await informes
          .mirar(FiltroDeInforme(hasta: DateTime(2026, 9, 14)))
          .first;
      // Sin el fin del dia, pedir «hasta el 14» dejaria fuera todo el 14.
      // Cortando en hora local entraria ademas el de las 02:00 UTC del 15, que
      // aqui son las 22:00 del 14 — y ese es justo el pedido que el informe
      // del servidor NO cuenta.
      expect(i.filas.map((f) => f.id).toList(), ['tarde']);
    });

    test('`desde` corta por abajo, tambien en UTC', () async {
      await pedido('viejo', creado: DateTime.utc(2026, 9, 9, 22), precio: 5);
      await pedido('nuevo', creado: DateTime.utc(2026, 9, 10, 1), precio: 5);

      final i = await informes
          .mirar(FiltroDeInforme(desde: DateTime(2026, 9, 10)))
          .first;
      // Las 22:00 UTC del 9 son todavia el dia 9, aunque aqui sean las 18:00
      // de ese mismo dia y aunque en un huso al este ya fuera el 10.
      expect(i.filas.map((f) => f.id).toList(), ['nuevo']);
    });

    test('sin rango no se filtra por fecha', () async {
      await pedido('viejo', creado: DateTime(2020, 1, 1));
      await pedido('nuevo', creado: DateTime(2026, 9, 12));

      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.length, 2);
    });

    // LA GUARDA, sin base de por medio: los dos limites son instantes UTC.
    //
    // Es lo que iguala el corte con el de la de Next (`new Date('2026-09-14')`
    // y `new Date(to + 'T23:59:59.999Z')`). En hora local, con Cuba a −4, se
    // colaban o se perdian hasta cinco horas de pedidos en cada extremo, y el
    // informe del aparato y el del servidor daban dos totales distintos para el
    // mismo dia.
    test('los dos limites del rango son UTC, no la hora de aqui', () {
      final desde = ConsultasInformes.comienzoDelDia(DateTime(2026, 9, 14, 3));
      expect(desde!.isUtc, isTrue);
      expect(desde, DateTime.utc(2026, 9, 14));

      final hasta = ConsultasInformes.finDelDia(DateTime(2026, 9, 14, 3));
      expect(hasta!.isUtc, isTrue);
      expect(hasta, DateTime.utc(2026, 9, 14, 23, 59, 59, 999));

      expect(ConsultasInformes.comienzoDelDia(null), isNull);
      expect(ConsultasInformes.finDelDia(null), isNull);
    });
  });

  group('el filtro de vehiculo', () {
    test('filtra por el vehiculo DE LA RUTA', () async {
      await pedido('a', rutaId: 'r1', precio: 30);
      await pedido('b', rutaId: 'r2', precio: 30);

      final i = await informes
          .mirar(const FiltroDeInforme(vehiculoId: 'v2'))
          .first;
      expect(i.filas.map((f) => f.id).toList(), ['b']);
    });
  });

  test('el nombre de ruta es el codigo, y si no lo hay el nombre', () async {
    await pedido('a', rutaId: 'r1');
    await pedido('b', rutaId: 'r2');

    final i = await informes.mirar(const FiltroDeInforme()).first;
    final porId = {for (final f in i.filas) f.id: f.ruta};
    expect(porId['a'], 'STG-0912');
    expect(porId['b'], 'Vista Alegre');
  });

  test('el alcance por sucursal se respeta', () async {
    await pedido('a', precio: 10);
    await pedido('b', sucursal: 'hol', precio: 10);

    final i = await informes
        .mirar(const FiltroDeInforme(), sucursalId: 'hol')
        .first;
    expect(i.filas.map((f) => f.id).toList(), ['b']);
  });
}
