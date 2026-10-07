// El juego de datos de las pruebas de pantalla.
//
// Se siembra a mano y no con un generador porque lo que se comprueba son NUMEROS
// concretos: «con estos 11 pedidos, este filtro devuelve 3». Un generador da
// totales que hay que recalcular en el propio test, y entonces el test comprueba
// la misma cuenta dos veces en vez de comprobar la consulta.

import 'package:drift/drift.dart';
import 'package:reparto/nucleo/base/base.dart';

/// El dia de referencia de todo el juego.
final hoy = DateTime(2026, 9, 14, 16, 5);

Future<void> sembrarCatalogo(BaseLocal base) async {
  await base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: 'B1',
          name: 'Camagüey',
          lat: 21.38,
          lng: -77.91,
          externalId: const Value('CAM'),
        ),
      );
  await base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: 'B2',
          name: 'Holguín',
          lat: 20.88,
          lng: -76.26,
          externalId: const Value('HOL'),
        ),
      );
  await base
      .into(base.products)
      .insert(
        ProductsCompanion.insert(
          id: 'p1',
          name: 'Arroz',
          // 25 kg por empaque: con esto el peso del pre-despacho es comprobable
          // a mano.
          weight: const Value(25),
          // Y 10 unidades por empaque, que es de donde salen las unidades de la
          // hoja del almacén. Ver `LineaPreDespacho.unidades`: antes salían de
          // `quantity`, que unas veces trae unidades y otras repite los bultos.
          unitsPerPackage: const Value(10),
        ),
      );
  await base
      .into(base.vehicles)
      .insert(
        VehiclesCompanion.insert(
          id: 'V1',
          name: 'Camión 1',
          capacity: const Value(1000),
          plate: const Value('P-001'),
          branchId: const Value('B1'),
        ),
      );
  await base
      .into(base.warehouses)
      .insert(
        WarehousesCompanion.insert(
          id: 'W1',
          sucursalCodigo: 'CAM',
          nombre: 'Almacén central',
          lat: const Value(0),
          lng: const Value(0),
          principal: const Value(true),
        ),
      );
}

/// Un pedido, con lo justo para que los filtros tengan de que agarrarse.
Future<void> sembrarPedido(
  BaseLocal base, {
  required String id,
  required String cliente,
  String? folio,
  String municipio = 'Camagüey',
  String vendedor = 'Luis',
  String? facturaEstado = EstadoFactura.igual,
  bool archivado = false,
  double? pedidoCosto = 10,
  double? facturaDomicilio = 1,
  DateTime? fecha,
  DateTime? creado,
  double peso = 10,
  double? distancia,
  String? rutaId,
  String? ultimaRutaId,
  String? resultado,
  DateTime? entregadoAt,
  String sucursal = 'B1',
  double? endLat,
  double? endLng,
  int? orden,
  // Por defecto **lleva domicilio**: estos son los pedidos que se reparten, y el
  // paso 4 del asistente arranca en `Sólo con domicilio` (pliego §3). Un nulo
  // aqui no es «no se sabe», es «no lleva», asi que dejarlo sin poner sacaria a
  // todo el juego de datos de la lista de elegibles.
  bool? requiereDomicilio = true,
  String? estado,
  DateTime? fechaComprometida,
}) => base
    .into(base.orders)
    .insert(
      OrdersCompanion.insert(
        id: id,
        customerName: cliente,
        address: 'Calle $id',
        operationNumber: Value(folio ?? 'F-$id'),
        endAddress: Value('Entrega $id'),
        endLat: Value(endLat),
        endLng: Value(endLng),
        weight: Value(peso),
        municipio: Value(municipio),
        vendedor: Value(vendedor),
        facturaEstado: Value(facturaEstado),
        facturaNumero: const Value('FA-1'),
        archivado: Value(archivado),
        pedidoCosto: Value(pedidoCosto),
        facturaDomicilio: Value(facturaDomicilio),
        deliveryDistanceKm: Value(distancia),
        orderDate: Value(fecha),
        createdAt: Value(creado ?? fecha ?? hoy),
        routeId: Value(rutaId),
        ultimaRutaId: Value(ultimaRutaId ?? rutaId),
        resultado: Value(resultado),
        deliveredAt: Value(entregadoAt),
        branchId: Value(sucursal),
        sucursalCodigo: const Value('CAM'),
        source: const Value(Procedencia.pedido),
        stopOrder: Value(orden),
        requiereDomicilio: Value(requiereDomicilio),
        estado: Value(estado),
        fechaComprometida: Value(fechaComprometida),
      ),
    );

Future<void> sembrarRenglon(
  BaseLocal base, {
  required String id,
  required String pedidoId,
  required String producto,
  required double unidades,
  double? empaques,
  String? productoId,
  int linea = 1,

  /// **El peso de la LINEA ya resuelto por el servidor**, que es lo unico que el
  /// aparato lee (`_pesoDeLaLinea` y `RenglonConPeso.pesoLinea`).
  ///
  /// El servidor lo saca de su cascada —`PesosDeRenglones` en
  /// `api/internal/cotizar/pesos.go`— y lo escribe en `peso_linea_kg`. Sembrarlo
  /// nulo es sembrar «el servidor no supo pesar esta linea», que es un caso de
  /// verdad y se cuenta en «sin peso».
  double? pesoLinea,

  /// Lo que pesa UN EMPAQUE, tal como quedo constancia en la 00004.
  ///
  /// **El aparato NO calcula con esto**: es un dato guardado, no un escalon. La
  /// cascada que lo usaba vivia aqui y se fue al servidor el 28/09/2026, que es
  /// de donde salio el fallo de los tres sitios. Se siembra para poder comprobar
  /// justamente eso: que estando puesto, no se cuela en la hoja.
  double? pesoEmpaque,
}) => base
    .into(base.orderItems)
    .insert(
      OrderItemsCompanion.insert(
        id: id,
        orderId: pedidoId,
        linea: linea,
        description: producto,
        quantity: unidades,
        packs: Value(empaques),
        productId: Value(productoId),
        pesoLineaKg: Value(pesoLinea),
        pesoKg: Value(pesoEmpaque),
      ),
    );

Future<void> sembrarRuta(
  BaseLocal base, {
  required String id,
  String estado = EstadoRuta.planificada,
  String? codigo,
  String? vehiculoId = 'V1',
  String? sucursal = 'B1',
  DateTime? creada,
}) => base
    .into(base.routes)
    .insert(
      RoutesCompanion.insert(
        id: id,
        routeCode: Value(codigo ?? 'RT-$id'),
        status: Value(estado),
        vehicleId: Value(vehiculoId),
        branchId: Value(sucursal),
        originLat: const Value(0),
        originLng: const Value(0),
        createdAt: Value(creada ?? hoy),
      ),
    );

/// Los 11 pedidos con los que se comprueban los 9 filtros. Cada uno existe para
/// caer en un lado distinto de alguna frontera.
Future<void> sembrarLosOnce(BaseLocal base) async {
  await sembrarCatalogo(base);
  await sembrarRuta(base, id: 'R1');
  await sembrarRuta(base, id: 'R2', estado: EstadoRuta.enCurso);

  await sembrarPedido(
    base,
    id: 'o1',
    cliente: 'Ana',
    fecha: DateTime(2026, 9, 1),
    peso: 100,
    distancia: 5,
  );
  await sembrarPedido(
    base,
    id: 'o2',
    cliente: 'Beto',
    municipio: 'Florida',
    facturaEstado: EstadoFactura.cambiado,
    // Sin cotizar: es el unico, y con el se comprueba `cotizado=0`.
    pedidoCosto: null,
    fecha: DateTime(2026, 9, 2),
    peso: 200,
    distancia: 10,
  );
  await sembrarPedido(
    base,
    id: 'o3',
    cliente: 'Carla',
    vendedor: 'Marta',
    facturaEstado: EstadoFactura.sinFactura,
    pedidoCosto: 30,
    fecha: DateTime(2026, 9, 3),
    peso: 50,
    distancia: 1,
  );
  await sembrarPedido(
    base,
    id: 'o4',
    cliente: 'Dani',
    municipio: 'Nuevitas',
    vendedor: 'Marta',
    // NULL no es `sin_factura`: es «sin cotejar», y por eso va aparte.
    facturaEstado: null,
    pedidoCosto: 40,
    fecha: DateTime(2026, 9, 4),
    peso: 10,
    distancia: 20,
  );
  await sembrarPedido(
    base,
    id: 'o5',
    cliente: 'Eva',
    archivado: true,
    pedidoCosto: 50,
    fecha: DateTime(2026, 9, 5),
    peso: 5,
    distancia: 2,
  );
  await sembrarPedido(
    base,
    id: 'o6',
    cliente: 'Fito',
    municipio: 'Florida',
    vendedor: 'Marta',
    pedidoCosto: 60,
    fecha: DateTime(2026, 9, 6),
    peso: 20,
    distancia: 3,
    rutaId: 'R1',
  );
  await sembrarPedido(
    base,
    id: 'o7',
    cliente: 'Gema',
    pedidoCosto: 70,
    fecha: DateTime(2026, 9, 7),
    peso: 30,
    distancia: 4,
    rutaId: 'R2',
  );
  await sembrarPedido(
    base,
    id: 'o8',
    cliente: 'Hugo',
    municipio: 'Nuevitas',
    vendedor: 'Marta',
    pedidoCosto: 80,
    fecha: DateTime(2026, 9, 8),
    peso: 40,
    distancia: 6,
    ultimaRutaId: 'R2',
    resultado: ResultadoParada.entregado,
    entregadoAt: DateTime(2026, 9, 8, 17),
  );
  await sembrarPedido(
    base,
    id: 'o9',
    cliente: 'Iris',
    municipio: 'Florida',
    pedidoCosto: 90,
    fecha: DateTime(2026, 9, 9),
    peso: 60,
    distancia: 7,
    // Devuelto: solto su `routeId` pero conserva `ultimaRutaId`.
    ultimaRutaId: 'R2',
    resultado: ResultadoParada.devuelto,
  );
  await sembrarPedido(
    base,
    id: 'o10',
    cliente: 'Juan',
    vendedor: 'Otro',
    pedidoCosto: 100,
    fecha: DateTime(2026, 9, 10),
    peso: 70,
    distancia: 8,
    sucursal: 'B2',
  );
  await sembrarPedido(
    base,
    id: 'o11',
    cliente: 'Kira',
    pedidoCosto: 5,
    // SIN `orderDate`: se acota por la fecha en que se copio, o desapareceria de
    // todos los rangos.
    fecha: null,
    creado: DateTime(2026, 8, 15),
    peso: 1,
    distancia: 9,
  );

  // Renglones: con estos se comprueba el pre-despacho y la busqueda por texto de
  // producto.
  // El Arroz llega con su peso RESUELTO, que es como lo escribe el servidor: 25
  // kg por empaque × 2 empaques. Antes salia del catalogo local, y el catalogo
  // local no trae el peso de ningun producto en produccion.
  await sembrarRenglon(
    base,
    id: 'i1',
    pedidoId: 'o1',
    producto: 'Arroz',
    unidades: 20,
    empaques: 2,
    productoId: 'p1',
    pesoLinea: 50,
  );
  await sembrarRenglon(
    base,
    id: 'i2',
    pedidoId: 'o1',
    producto: 'Frijol',
    unidades: 10,
    empaques: 1,
    linea: 2,
  );
  await sembrarRenglon(
    base,
    id: 'i3',
    pedidoId: 'o2',
    producto: 'Arroz',
    unidades: 30,
    empaques: 3,
    productoId: 'p1',
    pesoLinea: 75,
  );
  await sembrarRenglon(
    base,
    id: 'i4',
    pedidoId: 'o3',
    producto: 'Aceite',
    unidades: 5,
  );
}
