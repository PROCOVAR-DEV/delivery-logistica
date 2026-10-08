import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

/// Las cifras del Panel contra una base sembrada con los casos limite.
///
/// El valor de este test no es que sume: es que **no sume lo que no debe**. Las
/// seis combinaciones de abajo son las que se cuelan si la definicion de
/// REPARTIBLE se escribe de memoria en vez de copiarla del contrato.
void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ConsultasPanel panel;

  // El dia que vive la persona, con el reloj del aparato.
  final hoy = DateTime(2026, 9, 14, 10, 0);

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(hoy);
    panel = ConsultasPanel(base, reloj: reloj.leer);

    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'stg',
            name: 'Santiago',
            lat: 20.02,
            lng: -75.82,
          ),
        );
    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'hol',
            name: 'Holguín',
            lat: 20.88,
            lng: -76.26,
          ),
        );
  });

  tearDown(() => base.close());

  Future<void> pedido(
    String id, {
    String? sucursal = 'stg',
    String? rutaId,
    double? endLat = 20.0,
    String? factura = 'igual',
    double peso = 10,
    // Por defecto COTIZADO (en cero): desde el 07/10/2026 lo repartible exige
    // `pedido_costo` no nulo, y un cero no suma en `totalDomicilios` ni en nada.
    double? costo = 0,
    double? domicilioCobrado = 1,
    double? endLng = -75.0,
    String? origen = 'pedido',
    DateTime? entregadoEn,
  }) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          branchId: Value(sucursal),
          routeId: Value(rutaId),
          endLat: Value(endLat),
          endLng: Value(endLng),
          source: Value(origen),
          facturaEstado: Value(factura),
          facturaDomicilio: Value(domicilioCobrado),
          weight: Value(peso),
          pedidoCosto: Value(costo),
          deliveredAt: Value(entregadoEn),
        ),
      );

  Future<void> ruta(
    String id,
    String estado, {
    String? sucursal = 'stg',
    String? vehiculo,
  }) => base
      .into(base.routes)
      .insert(
        RoutesCompanion.insert(
          id: id,
          status: Value(estado),
          branchId: Value(sucursal),
          vehicleId: Value(vehiculo),
        ),
      );

  Future<void> vehiculo(String id, {String? sucursal = 'stg'}) => base
      .into(base.vehicles)
      .insert(
        VehiclesCompanion.insert(
          id: id,
          name: 'Camión $id',
          branchId: Value(sucursal),
        ),
      );

  group('los casos limite de REPARTIBLE', () {
    setUp(() async {
      // 1. repartible de verdad
      await pedido('p1', peso: 100, costo: 5);
      // 2. factura `cambiado`: NO entra a una ruta («en el camion solo sube lo
      //    que cuadra con la factura», Jose 07/10/2026), asi que tampoco cuenta
      await pedido('p2', factura: 'cambiado', peso: 50, costo: 5);
      // 3. sin ruta pero SIN endLat: no se puede repartir lo que no se sabe donde va
      await pedido('p3', endLat: null, peso: 999, costo: 5);
      // 4. factura `sin_factura`: no cuadra, no sale
      await pedido('p4', factura: 'sin_factura', peso: 999, costo: 5);
      // 5. factura NULL: NULL no es «sin factura», es «no cotejado». Tampoco sale
      await pedido('p5', factura: null, peso: 999, costo: 5);
      // 6. ya tiene ruta: esta ocupado
      await pedido('p6', rutaId: 'r1', peso: 999, costo: 5);
      // 7. SIN DOMICILIO COBRADO en la factura (Amado, 07/10/2026)
      await pedido('p7', domicilioCobrado: 0, peso: 999, costo: 5);
      // 8. SIN COTIZAR el domicilio en Entrega (Amado, 07/10/2026)
      await pedido('p8', peso: 999, costo: null);
      // 9. no vino de PEDIDO, y 10. sin punto de entrega completo: la lista de
      //    disponibles de Rutas tampoco los ofrece
      await pedido('p9', origen: null, peso: 999, costo: 5);
      await pedido('p10', endLng: null, peso: 999, costo: 5);
    });

    test('sinRuta cuenta 1, no 10', () async {
      final c = await panel.cifras().first;
      expect(c.sinRuta, 1);
      expect(c.totalPedidos, 10);
    });

    test('pesoPendiente suma SOLO lo repartible', () async {
      final c = await panel.cifras().first;
      expect(c.pesoPendiente, 100);
    });

    test('totalDomicilios suma TODO el alcance, repartible o no', () async {
      // Es lo cobrado en PEDIDO, no lo que queda por mover.
      final c = await panel.cifras().first;
      // p1..p6 a 5, p7 a 5, p9 a 5 y p10 a 5; p8 no esta cotizado y no suma.
      expect(c.totalDomicilios, 45);
    });

    // §3-bis: DOS PREGUNTAS SOBRE LO MISMO SE ATAN CON UNA PRUEBA. El Panel dice
    // «N pedidos sin ruta» y la lista de disponibles del asistente ofrece M: si
    // N != M, el Panel dice «40 por repartir» y el armador ofrece 12.
    test('el Panel cuenta EXACTAMENTE lo que ofrece la lista de disponibles', () async {
      final c = await panel.cifras(sucursalId: 'stg').first;
      final lista = await ConsultasRutas(base).disponibles(sucursalId: 'stg');
      expect(lista.map((p) => p.id).toList(), ['p1']);
      expect(c.sinRuta, lista.length);
      expect(
        c.pesoPendiente,
        lista.fold<double>(0, (suma, p) => suma + p.weight),
      );
    });
  });

  group('entregadosHoy, con el reloj del aparato', () {
    test('ayer a las 23:59 NO cuenta; hoy a las 00:01 SI', () async {
      await pedido('ayer', entregadoEn: DateTime(2026, 9, 13, 23, 59));
      await pedido('hoy', entregadoEn: DateTime(2026, 9, 14, 0, 1));
      await pedido('sinEntregar');

      final c = await panel.cifras().first;
      expect(c.entregadosHoy, 1);
    });

    test('al pasar la medianoche el contador se reinicia solo', () async {
      await pedido('hoy', entregadoEn: DateTime(2026, 9, 14, 0, 1));
      expect((await panel.cifras().first).entregadosHoy, 1);

      // El aparato amanece: lo de ayer deja de ser de hoy.
      reloj.ahora = DateTime(2026, 9, 15, 6, 0);
      expect((await panel.cifras().first).entregadosHoy, 0);
    });
  });

  group('rutas y vehiculos', () {
    // «EN MARCHA» ES LA QUE SALIÓ — 22/09/2026.
    //
    // Esto contaba también las planificadas. En el teléfono de Jose el Panel
    // decía «Rutas en marcha: 6» y Rutas → En curso decía 1: las otras cinco
    // estaban quietas en la oficina. El número que se lee de un vistazo era el
    // que estaba mal.
    test('rutasActivas: SÓLO las que están en curso', () async {
      await ruta('r1', 'planned');
      await ruta('r2', 'in_progress');
      await ruta('r3', 'completed');
      await ruta('r4', 'cancelled');
      await ruta('r5', 'planned');

      final c = await panel.cifras().first;
      expect(
        c.rutasActivas,
        1,
        reason: 'una planificada no ha salido del almacén: no está en marcha',
      );
    });

    // EL CAMIÓN SALE DE LA RUTA, no del pedido.
    //
    // El vehículo asociado al pedido se determina por su ruta, que es la relación
    // canónica del reparto.
    test('vehiculosEnRuta: sale de la RUTA, aunque el pedido no lo traiga', () async {
      await vehiculo('v1');
      await vehiculo('v2');
      await vehiculo('v3');
      await ruta('r1', 'in_progress', vehiculo: 'v1');
      await ruta('r2', 'completed', vehiculo: 'v2');
      // Los pedidos van SIN `vehicle_id`, que es como los deja armar una ruta.
      await pedido('a', rutaId: 'r1');
      await pedido('b', rutaId: 'r1');
      await pedido('c', rutaId: 'r2');

      final c = await panel.cifras().first;
      expect(c.totalVehiculos, 3);
      expect(
        c.vehiculosEnRuta,
        1,
        reason: 'v1 va en una ruta en curso; v2 en una ya cerrada; v3 en ninguna',
      );
    });

    test('un camión con DOS rutas en curso cuenta una vez', () async {
      await vehiculo('v1');
      await ruta('r1', 'in_progress', vehiculo: 'v1');
      await ruta('r2', 'in_progress', vehiculo: 'v1');

      expect((await panel.cifras().first).vehiculosEnRuta, 1);
    });

    // Y la pareja que ata los dos números: una ruta planificada con camión no
    // pone al camión en la calle. Si esto se relaja, el Panel vuelve a decir que
    // hay camiones repartiendo cuando están todos en el patio.
    test('una ruta planificada no pone su camión en ruta', () async {
      await vehiculo('v1');
      await ruta('r1', 'planned', vehiculo: 'v1');

      final c = await panel.cifras().first;
      expect(c.rutasActivas, 0);
      expect(c.vehiculosEnRuta, 0);
    });
  });

  group('alcance por sucursal', () {
    setUp(() async {
      await pedido('s1', peso: 10);
      await pedido('s2', peso: 20);
      await pedido('h1', sucursal: 'hol', peso: 300);
    });

    test('sin sucursal elegida suma todas', () async {
      final c = await panel.cifras().first;
      expect(c.sinRuta, 3);
      expect(c.pesoPendiente, 330);
    });

    test('con una sucursal elegida suma solo la suya', () async {
      final c = await panel.cifras(sucursalId: 'hol').first;
      expect(c.sinRuta, 1);
      expect(c.pesoPendiente, 300);
    });
  });

  group('pendiente por sucursal', () {
    test('ordenado de mas a menos pedidos, con su nombre', () async {
      await pedido('h1', sucursal: 'hol', peso: 5);
      await pedido('h2', sucursal: 'hol', peso: 5);
      await pedido('h3', sucursal: 'hol', peso: 5);
      await pedido('s1', peso: 100);

      final filas = await panel.porSucursal().first;
      expect(filas.map((f) => f.sucursal).toList(), ['Holguín', 'Santiago']);
      expect(filas.first.pedidos, 3);
      expect(filas.first.pesoKg, 15);
    });

    test('un pedido sin sucursal se agrupa y SE DICE, no desaparece', () async {
      // Si se cayera de la agrupacion, la tarjeta no cuadraria con la cifra de
      // arriba y nadie sabria por que.
      await pedido('x', sucursal: null);

      final filas = await panel.porSucursal().first;
      expect(filas.single.sucursal, 'Sin sucursal');
      expect(filas.single.pedidos, 1);
    });

    test('solo lo repartible entra en el desglose', () async {
      await pedido('s1');
      await pedido('s2', rutaId: 'r9');

      final filas = await panel.porSucursal().first;
      expect(filas.single.pedidos, 1);
    });
  });

  // ── EL ALCANCE DE LAS OCHO CIFRAS, NO SÓLO DE LAS DE PEDIDOS ──────────────
  //
  // Arriba ya había alcance para `sinRuta` y `pesoPendiente`. Las otras seis
  // —`totalPedidos`, `totalDomicilios`, `entregadosHoy`, `rutasActivas`,
  // `totalVehiculos` y `vehiculosEnRuta`— no tenían **ni una ruta ni un vehículo
  // de una segunda sucursal** con que comprobarlas: si el filtro por sucursal se
  // cae de cualquiera de esas seis subconsultas, toda la suite sigue verde y el
  // logístico de Camagüey ve los números de las otras siete.
  //
  // No es hipotético en esta casa: ya pasó en delivery (Next), donde un operador
  // de Santiago vio los precios de La Habana. Y es la regla dura del CLAUDE.md
  // §4: **el alcance sale de quién pregunta, no de lo que mande el cliente.**
  //
  // Las cifras están elegidas para que ninguna coincida: lo de Santiago, lo de
  // Camagüey y la suma de las dos son tres números distintos en las OCHO. Así
  // «ver de más» no puede confundirse con «ver lo suyo».
  group('alcance por sucursal de TODAS las cifras', () {
    setUp(() async {
      await base
          .into(base.branches)
          .insert(
            BranchesCompanion.insert(
              id: 'cam',
              name: 'Camagüey',
              lat: 21.38,
              lng: -77.92,
            ),
          );

      // Santiago: 2 pedidos (1 repartible, 1 entregado hoy), 2 rutas (1 en
      // marcha) y 2 camiones (1 en la calle).
      await pedido('s1', peso: 10, costo: 3);
      await pedido(
        's2',
        rutaId: 'rs1',
        peso: 7,
        costo: 4,
        entregadoEn: DateTime(2026, 9, 14, 8, 0),
      );
      await vehiculo('vs1');
      await vehiculo('vs2');
      await ruta('rs1', 'in_progress', vehiculo: 'vs1');
      await ruta('rs2', 'planned', vehiculo: 'vs2');

      // Camagüey: 4 pedidos (2 repartibles, 2 entregados hoy), 3 rutas (2 en
      // marcha) y 4 camiones (2 en la calle).
      await pedido('c1', sucursal: 'cam', peso: 100, costo: 50);
      await pedido('c2', sucursal: 'cam', peso: 200, costo: 60);
      await pedido(
        'c3',
        sucursal: 'cam',
        rutaId: 'rc1',
        peso: 5,
        costo: 70,
        entregadoEn: DateTime(2026, 9, 14, 9, 0),
      );
      await pedido(
        'c4',
        sucursal: 'cam',
        rutaId: 'rc1',
        peso: 5,
        costo: 80,
        entregadoEn: DateTime(2026, 9, 14, 9, 30),
      );
      await vehiculo('vc1', sucursal: 'cam');
      await vehiculo('vc2', sucursal: 'cam');
      await vehiculo('vc3', sucursal: 'cam');
      await vehiculo('vc4', sucursal: 'cam');
      await ruta('rc1', 'in_progress', sucursal: 'cam', vehiculo: 'vc1');
      await ruta('rc2', 'in_progress', sucursal: 'cam', vehiculo: 'vc2');
      await ruta('rc3', 'completed', sucursal: 'cam', vehiculo: 'vc3');
    });

    /// Las ocho cifras de una sucursal, con su nombre, para poder decir en el
    /// mensaje de fallo CUÁL se salió de su sucursal y por cuánto.
    Map<String, num> ocho(CifrasDelPanel c) => {
      'totalPedidos': c.totalPedidos,
      'sinRuta': c.sinRuta,
      'rutasActivas': c.rutasActivas,
      'entregadosHoy': c.entregadosHoy,
      'totalVehiculos': c.totalVehiculos,
      'vehiculosEnRuta': c.vehiculosEnRuta,
      'pesoPendiente': c.pesoPendiente,
      'totalDomicilios': c.totalDomicilios,
    };

    // Lo de cada una, escrito aparte para poder compararlo en los dos sentidos:
    // que cada sucursal vea LO SUYO y que NO vea lo de la otra.
    const deSantiago = {
      'totalPedidos': 2,
      'sinRuta': 1,
      'rutasActivas': 1,
      'entregadosHoy': 1,
      'totalVehiculos': 2,
      'vehiculosEnRuta': 1,
      'pesoPendiente': 10.0,
      'totalDomicilios': 7.0,
    };
    const deCamaguey = {
      'totalPedidos': 4,
      'sinRuta': 2,
      'rutasActivas': 2,
      'entregadosHoy': 2,
      'totalVehiculos': 4,
      'vehiculosEnRuta': 2,
      'pesoPendiente': 300.0,
      'totalDomicilios': 260.0,
    };
    const deLasDos = {
      'totalPedidos': 6,
      'sinRuta': 3,
      'rutasActivas': 3,
      'entregadosHoy': 3,
      'totalVehiculos': 6,
      'vehiculosEnRuta': 3,
      'pesoPendiente': 310.0,
      'totalDomicilios': 267.0,
    };

    test('Santiago ve LO SUYO en las ocho cifras', () async {
      final dio = ocho(await panel.cifras(sucursalId: 'stg').first);
      for (final cifra in deSantiago.keys) {
        expect(
          dio[cifra],
          deSantiago[cifra],
          reason:
              'el Panel de Santiago dice $cifra = ${dio[cifra]} y lo suyo son '
              '${deSantiago[cifra]}. Lo de Camagüey es ${deCamaguey[cifra]} y '
              'las dos juntas ${deLasDos[cifra]}: si salió uno de esos dos, el '
              'filtro por sucursal se cayó de esa subconsulta y Santiago está '
              'viendo números que no son suyos',
        );
      }
    });

    test('Camagüey ve LO SUYO y NO lo de Santiago', () async {
      final dio = ocho(await panel.cifras(sucursalId: 'cam').first);
      for (final cifra in deCamaguey.keys) {
        expect(
          dio[cifra],
          deCamaguey[cifra],
          reason:
              'el Panel de Camagüey dice $cifra = ${dio[cifra]} y lo suyo son '
              '${deCamaguey[cifra]}. Lo de Santiago es ${deSantiago[cifra]} y '
              'las dos juntas ${deLasDos[cifra]}: el logístico de Camagüey no '
              'puede ver las otras siete sucursales (CLAUDE.md §4)',
        );
        expect(
          dio[cifra],
          isNot(deSantiago[cifra]),
          reason:
              '$cifra de Camagüey salió igual que la de Santiago '
              '(${deSantiago[cifra]}): o el filtro no filtra o esta prueba dejó '
              'de distinguir las dos sucursales y ya no comprueba nada',
        );
        expect(
          dio[cifra],
          isNot(deLasDos[cifra]),
          reason:
              '$cifra de Camagüey salió igual que la suma de las dos '
              '(${deLasDos[cifra]}): está viendo lo de Santiago además de lo '
              'suyo',
        );
      }
    });

    test('sin sucursal elegida se suman las dos, y ahí sí', () async {
      // La pareja: el filtro tiene que filtrar cuando se pide y NO filtrar
      // cuando no se pide. Sin esto, «no ver lo de la otra» se aprobaría con una
      // consulta que no devuelve nada.
      final dio = ocho(await panel.cifras().first);
      for (final cifra in deLasDos.keys) {
        expect(
          dio[cifra],
          deLasDos[cifra],
          reason:
              'sin sucursal el Panel dice $cifra = ${dio[cifra]} y tenían que '
              'ser las dos juntas, ${deLasDos[cifra]}',
        );
      }
    });

    test('«Pendiente por sucursal» también se queda en la suya', () async {
      // La tarjeta de debajo de las cifras. Va con ellas porque es la misma
      // pregunta y tiene que dar el mismo alcance: si la lista enseña las ocho
      // sucursales debajo de unas cifras de una, la pantalla se contradice sola.
      final filas = await panel.porSucursal(sucursalId: 'cam').first;

      expect(
        filas.map((f) => f.sucursal).toList(),
        ['Camagüey'],
        reason:
            'el desglose de Camagüey trajo '
            '${filas.map((f) => '${f.sucursal}(${f.pedidos})').join(', ')}',
      );
      expect(filas.single.pedidos, 2);
      expect(filas.single.pesoKg, 300);
    });
  });
}
