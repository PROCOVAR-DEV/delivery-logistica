// Las tablas del DOMINIO: las mismas que el esquema del servidor
// (../api/db/migrations/00001_init.sql), con los MISMOS nombres de columna.
//
// El porque de calcarlas: asi la bajada por diferencias es un
// `insertOnConflictUpdate` del JSON que llega y nada mas. Cualquier renombre aqui
// obliga a un traductor en medio, y un traductor en medio es donde se pierden los
// campos que nadie mira hasta que hacen falta.
//
// Los `id` son TEXTO, no uuid: tienen que poder alojar tambien los provisionales
// `local-…` que el aparato se inventa cuando arma una ruta sin conexion (§2.2).

import 'package:drift/drift.dart';

@DataClassName('Sucursal')
class Branches extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  RealColumn get areaKm2 => real().withDefault(const Constant(1))();
  TextColumn get externalId => text().nullable()();
  BoolColumn get originConfigured =>
      boolean().withDefault(const Constant(false))();
  TextColumn get creadoPor => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// LA TASA DE CAMBIO DE ESTA SUCURSAL, y de ninguna otra.
  ///
  /// Vive aqui, en la sucursal, y no en `settings`. `settings` es GLOBAL —lo dice
  /// la propia API: «son de toda la empresa… la tasa POR SUCURSAL es otra cosa y
  /// vive en Accesos»— y una tasa sola para las ocho es exactamente como Granma
  /// acabo enseñando los 685 de La Habana como si fueran suyos. Un importe asi se
  /// lee bien y esta mal, que es lo peor que le puede pasar a un numero que
  /// alguien va a cobrar.
  ///
  /// **Baja con el dia** (`GET /api/sync/cambios`, coleccion `branches`) porque
  /// esta aplicacion tiene que pintar los importes sin conexion. La cadena entera
  /// es: Entrega pone la tasa → Accesos la guarda por sucursal → la tarea de
  /// fondo de la API la escribe en `branches` → aqui.
  ///
  /// **Los cuatro nacen nulos y no hay ningun 320 por defecto**, al reves que el
  /// `settings.cupRate` viejo. Es la mitad del arreglo: con un valor por defecto,
  /// ver un numero no demuestra que nadie haya puesto la tasa.

  /// Cuantos CUP son 1 USD aqui. `null` = esta sucursal no tiene tasa, que es un
  /// estado normal: hoy, seis de las ocho estan asi.
  RealColumn get cupRate => real().nullable()();

  /// De donde salio (`entrega`, `manual`…), tal como lo da Accesos.
  TextColumn get cupRateFuente => text().nullable()();

  /// Cuando se puso esa tasa en Entrega — el `traidoAt` de Accesos.
  ///
  /// **LA MARCA DE CUANDO, NO EL NUMERO.** Es lo unico que demuestra que la tasa
  /// existe de verdad, y por eso quien la lee la exige. Se llama `traidoAt` y no
  /// `updatedAt` para que no se confunda con el [updatedAt] de la fila, que es
  /// otra cosa: cuando cambio la sucursal.
  DateTimeColumn get cupRateTraidoAt => dateTime().nullable()();

  /// Si ACCESOS la da por fresca (alli son 24 h).
  ///
  /// No se calcula aqui, y eso es deliberado: quien sabe cuando una tasa esta
  /// pasada es quien la mantiene. El aparato copia el booleano y avisa; una
  /// segunda regla de frescura se separaria de la primera el dia que una de las
  /// dos cambie.
  BoolColumn get cupRateFresca => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TipoVehiculo')
class VehicleTypes extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  RealColumn get costoKmUsd => real().nullable()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Vehiculo')
class Vehicles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get vehicleTypeId => text().nullable()();
  TextColumn get plate => text().nullable()();
  RealColumn get capacity => real().withDefault(const Constant(1000))();
  RealColumn get costoKmUsd => real().nullable()();

  /// El vehiculo de REFERENCIA de su sucursal para calcular el domicilio.
  /// En el servidor lo limita un indice unico parcial; aqui hay que hacer lo
  /// mismo a mano y EN LA MISMA TRANSACCION, o la pantalla ensena dos marcados
  /// hasta la proxima bajada (PLAN.md §3.4).
  BoolColumn get usarParaDomicilio =>
      boolean().withDefault(const Constant(false))();
  TextColumn get status => text().withDefault(const Constant('available'))();
  TextColumn get notes => text().nullable()();
  TextColumn get branchId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Producto')
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get weight => real().withDefault(const Constant(0))();
  TextColumn get packaging => text().nullable()();
  RealColumn get unitsPerPackage => real().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get sku => text().nullable()();
  TextColumn get sucursalCodigo => text().nullable()();
  RealColumn get price => real().nullable()();
  RealColumn get stock => real().nullable()();
  TextColumn get unit => text().nullable()();

  /// Cuando lo trajo Ventra. No es `updatedAt`: dice si lo que se mira es de hace
  /// diez minutos o de hace tres dias porque la VPN lleva caida desde el lunes.
  DateTimeColumn get traidoAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Cliente')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get source => text().nullable()();
  TextColumn get externalId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get municipio => text().nullable()();
  TextColumn get zona => text().nullable()();
  TextColumn get codigo => text().nullable()();
  TextColumn get vendedor => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get sucursalCodigo => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Pedido')
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get operationNumber => text().nullable()();
  TextColumn get customerName => text()();
  TextColumn get address => text()();
  TextColumn get endAddress => text().nullable()();
  RealColumn get endLat => real().nullable()();
  RealColumn get endLng => real().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  RealColumn get weight => real().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get tripLeg => text().withDefault(const Constant('outbound'))();
  TextColumn get notes => text().nullable()();

  /// La ruta que lo lleva AHORA. Con esto puesto el pedido esta ocupado.
  TextColumn get routeId => text().nullable()();

  /// En que ruta VIAJO. Esto no se libera nunca — un devuelto suelta `routeId`
  /// pero CONSERVA `ultimaRutaId`, o desaparece de la hoja de lo que bajo del
  /// camion.
  TextColumn get ultimaRutaId => text().nullable()();

  TextColumn get vehicleId => text().nullable()();

  RealColumn get price => real().nullable()();
  RealColumn get segmentKm => real().nullable()();
  RealColumn get deliveryPrice => real().nullable()();
  RealColumn get deliveryDistanceKm => real().nullable()();
  TextColumn get branchId => text().nullable()();

  TextColumn get source => text().nullable()();
  TextColumn get externalId => text().nullable()();

  /// La FECHA DEL PEDIDO en PEDIDO, que NO es `createdAt`.
  DateTimeColumn get orderDate => dateTime().nullable()();
  DateTimeColumn get pedidoUpdatedAt => dateTime().nullable()();

  TextColumn get estado => text().nullable()();
  BoolColumn get archivado => boolean().withDefault(const Constant(false))();
  DateTimeColumn get fechaComprometida => dateTime().nullable()();

  BoolColumn get requiereDomicilio => boolean().nullable()();

  /// El costo que le puso la APK de Entrega EN PEDIDO. En la pantalla es
  /// `Precio`. NO es `price` — confundirlos es cobrar uno por el otro.
  RealColumn get pedidoCosto => real().nullable()();

  TextColumn get municipio => text().nullable()();
  TextColumn get vendedor => text().nullable()();
  TextColumn get sucursalCodigo => text().nullable()();

  TextColumn get facturaEstado => text().nullable()();
  TextColumn get facturaNumero => text().nullable()();
  DateTimeColumn get facturaAt => dateTime().nullable()();
  RealColumn get facturaDomicilio => real().nullable()();
  DateTimeColumn get facturaCorregidoAt => dateTime().nullable()();

  /// DE DÓNDE SON LOS RENGLONES, EL PESO Y LAS UNIDADES: `factura` o `pedido`.
  ///
  /// Cuando un pedido se factura distinto de como se tomó, PEDIDO manda **las
  /// líneas de la factura** —descartando las que se pidieron y no se facturaron,
  /// para que nadie cargue un hueco—. O sea que lo que hay aquí YA es lo que
  /// sube al camión. Comprobado contra producción el 26/09/2026: en
  /// `PAT26-260923-1246` el vendedor tomó dos productos y la factura dice uno,
  /// y aquí hay un renglón con los 60 uds y los 24,194 kg de la factura.
  ///
  /// Lo que faltaba era DECIRLO. Salía «Cambió en la factura» y nada más, así
  /// que quien mira un número no sabe cuál de los dos tiene delante. Jose,
  /// 26/09/2026: «se facturó otra cosa, ese pedido ya no representa la cantidad
  /// total»; y cómo se resuelve: «mantenemos el pedido y sólo le añadimos una
  /// factura a ese pedido para saber si cambió o no».
  ///
  /// **Nulo es «no se sabe»**, y entonces la pantalla no dice nada. No se
  /// deduce de [facturaEstado]: un `cambiado` cuyo cotejo no pudo atar la
  /// factura a ESTE pedido se queda con las del pedido, y un `igual` también
  /// trae las de la factura. Son dos preguntas distintas.
  TextColumn get itemsOrigen => text().nullable()();

  TextColumn get customerPhone => text().nullable()();

  IntColumn get stopOrder => integer().nullable()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  TextColumn get resultado => text().nullable()();
  DateTimeColumn get resultadoAt => dateTime().nullable()();
  TextColumn get resultadoNota => text().nullable()();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RenglonPedido')
class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  IntColumn get linea => integer()();
  TextColumn get description => text()();
  RealColumn get quantity => real()();

  /// Los bultos, cuando la factura los distingue de las unidades. El numero de
  /// una linea son sus `packs` y si no los trae sus `quantity`, nunca cero
  /// (reglas-negocio §12).
  RealColumn get packs => real().nullable()();

  /// Lo que pesa UN empaque, tal como quedo cuando el pedido entro.
  ///
  /// **ES CONSTANCIA, NO UN ESCALON DEL PESO** — 28/09/2026. El aparato no
  /// calcula con esto: la cascada del peso corre UNA vez, en el servidor
  /// (`PesosDeRenglones`, `api/internal/cotizar/pesos.go`), y lo que se lee es
  /// [pesoLineaKg]. Esta columna se guarda porque es el dato con el que se
  /// facturo —para eso la puso la `00004_peso_por_renglon.sql`— y porque es lo
  /// que permite comprobar despues de donde salio un kilo.
  ///
  /// SON DOS COLUMNAS Y CON NOMBRES DISTINTOS A PROPOSITO: esta es la de un
  /// empaque y [pesoLineaKg] la de la linea entera. Guardar solo la primera
  /// llamandola «el peso» es pedir que alguien se acuerde de multiplicar por los
  /// empaques, y el dia que se olvide el camion sale dividido entre treinta sin
  /// que falle nada.
  ///
  /// HASTA EL 26/09/2026 NO EXISTIAN, y la ficha resolvia el peso contra el
  /// CATALOGO LOCAL. Lo que se veia: un renglon diciendo «sin peso» mientras el
  /// total del mismo pedido decia 72,6 kg, y el pre-despacho —la hoja con la que
  /// se carga el camion— con las catorce filas en raya y «sin peso en el
  /// catalogo» encima de 7.446 empaques. Inservible.
  ///
  /// El peso no es del catalogo de hoy: es el que tenia la mercancia cuando se
  /// facturo. Un producto que hoy no este en el catalogo de esa sucursal no
  /// tiene por que perderlo.
  ///
  /// `null` = **no se sabe**, y la pantalla lo dice con esas palabras. No es
  /// cero: un cero se suma, se ordena y se lee como «no pesa nada».
  RealColumn get pesoKg => real().nullable()();

  /// Lo que pesa la LINEA entera. Ver [pesoKg].
  RealColumn get pesoLineaKg => real().nullable()();
  TextColumn get productId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Ruta')
class Routes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get routeCode => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get originAddress => text().nullable()();
  RealColumn get originLat => real().nullable()();
  RealColumn get originLng => real().nullable()();
  RealColumn get totalDistance => real().withDefault(const Constant(0))();
  RealColumn get totalWeight => real().withDefault(const Constant(0))();
  RealColumn get totalPrice => real().withDefault(const Constant(0))();
  DateTimeColumn get deliveryDate => dateTime().nullable()();
  TextColumn get vehicleId => text().nullable()();
  TextColumn get creadoPor => text().nullable()();
  TextColumn get branchId => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  BoolColumn get optimized => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Los almacenes. No estan en el esquema de la API: viven en Accesos y se leen
/// por `GET /api/almacenes`. Aqui se guarda la copia bajada.
@DataClassName('Almacen')
class Warehouses extends Table {
  TextColumn get id => text()();
  TextColumn get sucursalCodigo => text()();
  TextColumn get nombre => text()();
  TextColumn get direccion => text().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();

  /// El principal de la sucursal: es el punto de partida y el origen desde el
  /// que se miden los km de los clientes.
  BoolColumn get principal => boolean().withDefault(const Constant(false))();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Una sola fila, como en el servidor: dos filas de ajustes es media aplicacion
/// mirando una y media mirando la otra.
@DataClassName('Ajustes')
class Settings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get syncBarridoDia => integer().withDefault(const Constant(0))();
  DateTimeColumn get catalogoTraidoAt => dateTime().nullable()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  RealColumn get cupRate => real().withDefault(const Constant(320))();
  DateTimeColumn get cupRateUpdatedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// AQUI ESTABA `Currencies`, Y SE QUITO ENTERA (15/09/2026).
//
// Era la tabla que leia el selector de moneda de la barra superior, y **no la
// llenaba nadie**: la bajada del dia no la trae, no esta en `Colecciones` y el
// servidor no la sirve en `GET /api/sync/cambios`. Salia vacia siempre, asi que
// la barra se quedaba PERMANENTEMENTE en la pastilla ambar «esta sucursal no
// tiene tasa de cambio todavia», en las ocho sucursales, tuvieran tasa o no.
//
// Era ademas el modelo equivocado: una lista de monedas con una tasa global
// —`CUP = 320`, la misma para las ocho— es justo lo que la regla de la casa
// prohibe. La tasa es POR SUCURSAL y ahora vive donde vive de verdad, en
// [Branches].
//
// La de la BASE DEL SERVIDOR sigue en pie: la usa `PUT /api/settings` desde la
// pantalla de Configuracion → Monedas de `delivery` (la web). Quitarla de alli
// es otro trabajo, con su front detras, y va en el informe.
