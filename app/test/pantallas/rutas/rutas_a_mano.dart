// RUTAS ARMADAS A MANO, sin Drift.
//
// `Ruta` y `Pedido` son `DataClass` de Drift, pero su constructor solo exige
// siete campos: se pueden montar en memoria. Y hacerlo asi es lo correcto para
// lo que prueban el croquis, el enlace y el bloque del mapa, por dos motivos:
//
//  * ninguno de los tres consulta la base. Meter una base de verdad para
//    probarlos seria probar Drift;
//  * dentro de un `testWidgets` el reloj lo manda el `tester`, y lo que Drift
//    deja empezado no avanza solo. Las dos trampas del §5 del `CLAUDE.md` —el
//    `await` sobre un stream y el sembrado en el `setUp`— **cuelgan la prueba en
//    vez de fallarla**, que es lo peor que puede hacer una prueba. Sin base no
//    hay ninguna de las dos.
//
// Lo que SI toca la base es `recorridoDe`, y por eso esa tiene su propia prueba
// con `baseDePrueba()`.

import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

Pedido paradaAMano({
  required String id,
  required String cliente,
  double? lat,
  double? lng,
  double? precio,
  /// `pedidoCosto`, que NO es `price`. `price` es la COPIA que se hace al
  /// enganchar el pedido a la ruta y que pierde el nulo en el servidor
  /// (`price = coalesce(narg, 0)`), asi que quien lee el importe de una parada
  /// necesita los dos: un `price` de cero sin `pedidoCosto` es ese `coalesce`,
  /// no un precio. La regla esta en `ConsultasInformes.ingresoDe`.
  double? costo,
  String tramo = Tramo.ida,
  String? resultado,
  /// `orders.segment_km`, que **por defecto va nulo y eso no es descuido**: es
  /// el caso de verdad. Una ruta armada desde el Tablero en el aparato deja
  /// esta columna sin escribir (`pantallas/tablero/datos/repositorio.dart`), y
  /// con ella nula es como Jose vio `RT-20260928-001` el 28/09/2026: tres
  /// paradas y tres rayas mudas.
  double? segmentKm,
  double peso = 10,
}) => Pedido(
  id: id,
  customerName: cliente,
  address: 'Calle $id',
  endLat: lat,
  endLng: lng,
  price: precio,
  pedidoCosto: costo,
  segmentKm: segmentKm,
  weight: peso,
  status: EstadoPedido.pendiente,
  tripLeg: tramo,
  resultado: resultado,
  archivado: false,
);

RutaConTodo rutaAMano({
  required List<Pedido> paradas,
  String id = 'R1',
  String? codigo = 'RT-001',
  String? nombre,
  double? origenLat = 21.38,
  double? origenLng = -77.91,
  double km = 42.5,
  double peso = 100,
  DateTime? fecha,
  Vehiculo? vehiculo,
  Sucursal? sucursal,
}) => RutaConTodo(
  ruta: Ruta(
    id: id,
    routeCode: codigo,
    name: nombre,
    status: EstadoRuta.planificada,
    originLat: origenLat,
    originLng: origenLng,
    totalDistance: km,
    totalWeight: peso,
    totalPrice: 250,
    deliveryDate: fecha ?? DateTime(2026, 9, 14),
    optimized: true,
  ),
  paradas: paradas,
  vehiculo: vehiculo,
  sucursal: sucursal,
);

Vehiculo camionAMano({
  String nombre = 'Camión 1',
  String? matricula = 'P-001',
}) => Vehiculo(
  id: 'V1',
  name: nombre,
  plate: matricula,
  capacity: 1000,
  usarParaDomicilio: true,
  status: EstadoVehiculo.disponible,
);
