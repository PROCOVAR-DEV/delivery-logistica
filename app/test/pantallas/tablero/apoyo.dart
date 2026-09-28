import 'package:drift/drift.dart';
import 'package:reparto/nucleo/base/base.dart';

/// Lo que hace falta sembrar para que haya tablero: la sucursal, su almacen (que
/// es el punto desde el que se mide la cercania) y pedidos repartibles.
///
/// Las coordenadas son las de Santiago de Cuba de verdad: asi los kilometros que
/// salen en las pruebas se pueden comparar con un mapa cuando algo no cuadre.
const sucursalStg = 'suc-stg';
const codigoStg = 'STG';
const almacenLat = 20.0247;
const almacenLng = -75.8219;

/// Un grado de latitud son ~111,19 km. Con esto, un pedido puesto a `0.01` esta
/// a 1,11 km y las pruebas del orden se leen solas.
const gradoKm = 111.19;

Future<void> sembrarSucursal(BaseLocal base) async {
  await base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: sucursalStg,
          name: 'Santiago',
          lat: almacenLat,
          lng: almacenLng,
          externalId: const Value(codigoStg),
        ),
      );
}

Future<void> sembrarAlmacen(
  BaseLocal base, {
  String id = 'alm-1',
  String nombre = 'Almacén principal',
  double? lat = almacenLat,
  double? lng = almacenLng,
  bool principal = true,
  String codigo = codigoStg,
}) => base
    .into(base.warehouses)
    .insert(
      WarehousesCompanion.insert(
        id: id,
        sucursalCodigo: codigo,
        nombre: nombre,
        lat: Value(lat),
        lng: Value(lng),
        principal: Value(principal),
      ),
    );

/// [estado] es `vehicles.status` tal cual. Por defecto `available`, que es lo
/// que trae todo camion nuevo; se pasa `maintenance` para sembrar uno en el
/// taller, que es el unico estado de la flota que se guarda (los demas se
/// deducen de las rutas).
Future<void> sembrarCamion(
  BaseLocal base, {
  required String id,
  String nombre = 'F-350',
  double capacidad = 1000,
  String estado = 'available',
}) => base
    .into(base.vehicles)
    .insert(
      VehiclesCompanion.insert(
        id: id,
        name: nombre,
        capacity: Value(capacidad),
        status: Value(estado),
        branchId: const Value(sucursalStg),
      ),
    );

/// Un pedido repartible por defecto: de PEDIDO, sin ruta, con coordenadas y
/// cotejado. Son las cinco condiciones del armador, ni una mas ni una menos.
Future<void> sembrarPedido(
  BaseLocal base, {
  required String id,
  String cliente = 'Cliente',
  String direccion = 'Calle 1',
  double aGrados = 0.01,
  double peso = 100,

  /// EL COBRO DEL DOMICILIO, que es este y no `deliveryPrice`: lo pone el
  /// repartidor desde Entrega y es el que ensena la tarjeta al lado del peso.
  /// `null` es «todavia no se lo han puesto», que NO es lo mismo que cero: un
  /// domicilio de cero es una decision de alguien.
  double? costo = 5,
  String? operacion,
  String? municipio = 'Santiago de Cuba',
  String? vendedor = 'Ana',
  String? facturaEstado = EstadoFactura.igual,
  bool archivado = false,
  String? rutaId,
  String? fuente = Procedencia.pedido,

  /// SI VA A CASA DEL CLIENTE. Por defecto `true` porque es lo unico que el
  /// tablero ofrece: prepara rutas, y una ruta reparte a domicilio. Se pone a
  /// `false` —o a `null`, que es «nadie lo ha marcado»— para sembrar los que NO
  /// tienen que salir en «sin colocar».
  bool? domicilio = true,
  String sucursal = sucursalStg,
  DateTime? fecha,
  bool conCoordenadas = true,
}) => base
    .into(base.orders)
    .insert(
      OrdersCompanion.insert(
        id: id,
        customerName: cliente,
        address: direccion,
        endAddress: Value(direccion),
        endLat: Value(conCoordenadas ? almacenLat + aGrados : null),
        endLng: Value(conCoordenadas ? almacenLng : null),
        weight: Value(peso),
        pedidoCosto: Value(costo),
        operationNumber: Value(operacion ?? id),
        municipio: Value(municipio),
        vendedor: Value(vendedor),
        facturaEstado: Value(facturaEstado),
        archivado: Value(archivado),
        routeId: Value(rutaId),
        source: Value(fuente),
        requiereDomicilio: Value(domicilio),
        branchId: Value(sucursal),
        orderDate: Value(fecha ?? DateTime(2026, 9, 14, 8)),
        createdAt: Value(fecha ?? DateTime(2026, 9, 14, 8)),
      ),
    );

Future<void> sembrarRenglon(
  BaseLocal base, {
  required String id,
  required String pedidoId,
  required String descripcion,
}) => base
    .into(base.orderItems)
    .insert(
      OrderItemsCompanion.insert(
        id: id,
        orderId: pedidoId,
        linea: 1,
        description: descripcion,
        quantity: 1,
      ),
    );
