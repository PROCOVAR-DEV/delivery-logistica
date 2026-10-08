import '../../../nucleo/base/base.dart';
import '../../vehiculos/datos/vehiculo_api.dart' show estadoEnMantenimiento;

/// EL REPARTO DE UNA ZONA ENTRE «entra» Y «no entra», y por que no entra.
///
/// Es una funcion suelta y no un metodo del asistente por lo de siempre en esta
/// casa: **es una regla**, y una regla metida en un `setState` solo se puede
/// comprobar montando media aplicacion. Aqui lo que hay que comprobar es
/// exactamente el reparto en cuatro montones, que es donde esto puede enganar.
///
/// Y puede enganar mucho: meter nueve de doce **en silencio** es la peor
/// version de este atajo. Quien pulsa la zona cree que lleva la zona entera y se
/// entera en el almacen, cargando el camion.
class RepartoDeLaZona {
  const RepartoDeLaZona({
    required this.entran,
    required this.yaEstaban,
    required this.noDisponibles,
    required this.noCaben,
  });

  /// Los que se meten, en orden y con su peso ya comprobado.
  final List<Pedido> entran;

  /// Ya estaban elegidos: no es un fallo, pero cambia el numero que se dice.
  final int yaEstaban;

  /// Estan en la zona y NO en la lista de disponibles: entraron en otra ruta o
  /// se archivaron desde que se armo el tablero. Meterlos seria fabricar un
  /// rechazo al guardar.
  final int noDisponibles;

  /// No caben en el vehiculo elegido.
  final int noCaben;
}

/// Reparte los pedidos de una zona. No toca nada: devuelve lo que pasaria.
///
/// [capacidad] nula significa que todavia no hay vehiculo, y entonces no se
/// descarta a nadie por peso: el paso del vehiculo va antes, asi que esto solo
/// pasa si alguien vuelve atras.
RepartoDeLaZona repartirLaZona({
  required List<String> ids,
  required List<Pedido> disponibles,
  required Set<String> yaElegidos,
  required double pesoActual,
  required double? capacidad,
}) {
  final porId = {for (final p in disponibles) p.id: p};
  final entran = <Pedido>[];
  var yaEstaban = 0;
  var noDisponibles = 0;
  var noCaben = 0;
  var peso = pesoActual;

  for (final id in ids) {
    if (yaElegidos.contains(id)) {
      yaEstaban++;
      continue;
    }
    final pedido = porId[id];
    if (pedido == null) {
      noDisponibles++;
      continue;
    }
    if (capacidad != null && peso + pedido.weight > capacidad) {
      noCaben++;
      continue;
    }
    entran.add(pedido);
    peso += pedido.weight;
  }

  return RepartoDeLaZona(
    entran: entran,
    yaEstaban: yaEstaban,
    noDisponibles: noDisponibles,
    noCaben: noCaben,
  );
}

/// Lo que se le dice a la persona, con TODOS los montones que no estan vacios.
String parteDeLaZona(String nombre, int total, RepartoDeLaZona r) => <String>[
  '${r.entran.length} de $total de «$nombre»',
  if (r.yaEstaban > 0) '${r.yaEstaban} ya estaban',
  if (r.noDisponibles > 0) '${r.noDisponibles} ya no se pueden repartir hoy',
  if (r.noCaben > 0) '${r.noCaben} no caben en el vehículo',
].join(' · ');

/// ¿SE OFRECE ESTE CAMION PARA UNA RUTA **NUEVA**?
///
/// Un camion se ofrece si esta **activo** y **fuera del taller**. Son dos cosas
/// distintas con la misma consecuencia:
///
///  * `isActive = false` es la baja: Amado, 07/10/2026 (incidencia 4) — un camion
///    con rutas no se borra, se inactiva, y desde ese momento no sale en la
///    seleccion de rutas nuevas. El servidor lo rechaza con 400 si se le manda a
///    mano («El vehículo está inactivo y no se puede asignar a una ruta.»).
///  * `maintenance` es el camion en el taller. Antes se ofrecia con un aviso
///    («aviso, no bloqueo»), con un argumento que colgaba del `CLAUDE.md` §2 de
///    entonces —bloquear con un dato que nadie mantiene deja sin armar a una
///    sucursal—. Ese §2 lo **reemplazo Amado el 07/10/2026**: un camion en el
///    taller no es uno que se pueda mandar a una ruta nueva, y no se ofrece.
///
/// **Esto vale SOLO para elegir camion de una ruta nueva** (el paso 3 del
/// asistente y el «Camion previsto» de una zona). Las listas que miran rutas YA
/// hechas —el filtro de camion de Rutas, los informes, la ficha de un pedido—
/// siguen viendo TODA la flota: una ruta de ayer con un camion que hoy esta de
/// baja tiene que seguir diciendo en que camion fue.
bool seOfreceParaRutasNuevas(Vehiculo v) =>
    v.isActive && v.status != estadoEnMantenimiento;

/// LOS VEHICULOS DE UNA SUCURSAL, y sólo los de esa.
///
/// El paso 1 del asistente lo promete con todas las letras —«los pedidos, los
/// vehiculos y el punto de partida seran los de esta sucursal»— y el paso 3
/// ofrecia los ocho camiones de las ocho. Visto por Jose el 16/09/2026: «me sale
/// la seleccion de todos los vehiculos existentes en ves de solo los q estan en
/// esa sucursal seleccionada».
///
/// Por que pasaba: la lista viene acotada por la sucursal de LA BARRA DE ARRIBA,
/// no por la del asistente. Para quien pertenece a una sucursal son la misma y
/// no se notaba; para un Super Admin mirando «todas» no hay acotado ninguno, y
/// la del paso 1 no la miraba nadie.
///
/// Un camion de Granma en una ruta de La Habana no es un detalle estetico: es un
/// camion que no esta donde sale la ruta.
///
/// Sin sucursal elegida se devuelven todos los que se ofrecen, que es lo unico
/// honesto: todavia no hay por que filtrar por sucursal. **Y solo los que se
/// ofrecen** ([seOfreceParaRutasNuevas]): esta lista es para ELEGIR camion.
List<Vehiculo> vehiculosDeLaSucursal(List<Vehiculo> todos, String? sucursalId) =>
    [
      for (final v in todos)
        if (seOfreceParaRutasNuevas(v) &&
            (sucursalId == null || v.branchId == sucursalId))
          v,
    ];
