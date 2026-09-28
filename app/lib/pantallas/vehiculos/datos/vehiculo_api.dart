/// Los modelos de Vehiculos, leidos del JSON de la API.
///
/// **No son tablas de Drift a proposito.** Vehiculos es una pantalla de sólo
/// con conexion: se configura una vez, en la oficina, y lo que se ve sale
/// siempre del servidor. Guardar una copia local abriria la puerta a ensenar
/// una flota de anteayer y a tener que decidir quien gana cuando las dos
/// difieran, y eso es complejidad a cambio de nada.
library;

import 'package:collection/collection.dart';

/// Lee un numero venga como venga: la API manda unos como numero y otros como
/// texto segun por donde pasaron.
double? _numero(Object? valor) => switch (valor) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// En que anda un camion. Se DEDUCE de sus rutas: ver `VehiculoDeLaApi.andar`.
enum AndarDelCamion { libre, asignado, enRuta, enMantenimiento }

/// La ruta viva de un vehiculo, para la caja azul `Ruta activa`.
class RutaDelVehiculo {
  const RutaDelVehiculo({this.id, this.nombre, this.codigo, this.estado});

  factory RutaDelVehiculo.deJson(Map<String, Object?> j) => RutaDelVehiculo(
    id: j['id'] as String?,
    nombre: j['name'] as String?,
    codigo: j['routeCode'] as String?,
    estado: j['status'] as String?,
  );

  final String? id;
  final String? nombre;
  final String? codigo;

  /// `routes.status`: `planned` o `in_progress`. Las cerradas y las canceladas no
  /// llegan aqui — el servidor solo manda las ABIERTAS.
  ///
  /// Hace falta porque `planned` y `in_progress` son dos respuestas distintas a
  /// «¿esta libre?»: una ruta planificada es un camion COMPROMETIDO para
  /// manana, y una en curso es un camion que no esta. Juntarlas en «ocupado»
  /// es lo que hace que alguien salga a buscar un camion que si podia usar.
  final String? estado;

  /// Esta rodando AHORA. Lo otro es «lo tiene cogido, pero no ha salido».
  bool get enCurso => estado == 'in_progress';

  /// Nombre, si no codigo, si no el respaldo del pliego.
  String get titulo {
    final n = nombre?.trim();
    if (n != null && n.isNotEmpty) return n;
    final c = codigo?.trim();
    if (c != null && c.isNotEmpty) return c;
    return 'sin nombre';
  }
}

class VehiculoDeLaApi {
  const VehiculoDeLaApi({
    required this.id,
    required this.nombre,
    required this.capacidad,
    required this.estado,
    this.tipo,
    this.placa,
    this.costoKmUsd,
    this.usarParaDomicilio = false,
    this.notas,
    this.rutas = 0,
    this.pedidos = 0,
    this.rutaActiva,
  });

  factory VehiculoDeLaApi.deJson(Map<String, Object?> j) {
    final cuenta = j['_count'] as Map<String, Object?>?;
    final rutas = (j['routes'] as List<Object?>?) ?? const [];
    return VehiculoDeLaApi(
      id: j['id']! as String,
      nombre: (j['name'] as String?) ?? '',
      capacidad: _numero(j['capacity']) ?? 1000,
      estado: (j['status'] as String?) ?? 'available',
      tipo: j['type'] as String?,
      placa: j['plate'] as String?,
      costoKmUsd: _numero(j['costoKmUsd']),
      usarParaDomicilio: j['usarParaDomicilio'] == true,
      notas: j['notes'] as String?,
      rutas: (_numero(cuenta?['routes']) ?? 0).toInt(),
      pedidos: (_numero(cuenta?['orders']) ?? 0).toInt(),
      // `routes` trae CERO O UNA ruta, la abierta que manda. La lista viene del
      // servidor ordenada —primero la que esta en curso— asi que `first` es la
      // que tiene el camion cogido ahora mismo.
      rutaActiva: rutas.isEmpty
          ? null
          : RutaDelVehiculo.deJson(rutas.first! as Map<String, Object?>),
    );
  }

  final String id;
  final String nombre;
  final double capacidad;
  final String estado;
  final String? tipo;
  final String? placa;
  final double? costoKmUsd;
  final bool usarParaDomicilio;
  final String? notas;
  final int rutas;
  final int pedidos;
  final RutaDelVehiculo? rutaActiva;

  // ---------------------------------------------------------------------------
  // EN QUE ANDA ESTE CAMION — 28/09/2026
  // ---------------------------------------------------------------------------
  //
  // Jose: «si la idea es q salga el vehiculo y ese vehiculo se ponga su estado
  // para q saber como anda ese vehiculo y saber de la flota».
  //
  // ## Sale de su RUTA, no de `vehicles.status`
  //
  // `status` es un campo que alguien pone y alguien tiene que quitar, y un
  // estado que nadie mantiene miente a los dos dias. En el servidor eso ya
  // estaba escrito desde antes, en `ContarVehiculosEnRuta`: «se mira la ruta y
  // no `vehicles.status` porque el estado es un campo que alguien puede haber
  // dejado a mano en `available` con la ruta todavia abierta». Lo que se hizo el
  // 28/09/2026 fue traer esa misma cuenta por camion
  // (`db/queries/vehicles.sql`, `RutasAbiertasDeLaFlota`) y servirla en
  // `routes`, que es el campo que esta clase leia desde el principio y que el
  // servidor **nunca habia mandado**: por eso la caja azul «Ruta activa» de
  // `tarjeta_vehiculo.dart` no salio nunca.
  //
  // Deducirlo tiene dos ventajas que un campo nuevo no puede tener: nace
  // correcto para los camiones que YA existen, y no hay ningun gesto nuevo que
  // alguien tenga que acordarse de hacer.
  //
  // ## Los estados, y por que son estos y no mas
  //
  //   · `enRuta`    — lleva una ruta `in_progress`. Esta fuera AHORA.
  //   · `asignado`  — lleva una ruta `planned`. No ha salido, pero esta cogido.
  //     El servidor lo dice claro en `vehicles.sql`: el camion se marca ocupado
  //     al DESPACHAR la ruta, no al armarla, «entre que se arma la noche
  //     anterior y sale por la mañana el camion sigue disponible para otra
  //     cosa». Asi que ni «libre» ni «en ruta»: es la tercera respuesta, y es la
  //     que evita que dos personas armen dos rutas con el mismo camion.
  //   · `libre`     — ninguna ruta abierta.
  //   · `enMantenimiento` — HOY NO PUEDE LLEGAR: el enum `vehicle_status` de la
  //     base sólo tiene `available` e `in_use`, y `estadoValido` del servidor
  //     rechaza cualquier otra cosa con un 400. Se deja reconocido a proposito,
  //     porque es lo unico de esta lista que NO se puede deducir —un camion en
  //     el taller no tiene ruta, igual que uno libre— y el dia que se guarde de
  //     verdad esta pantalla ya sabe pintarlo. Mientras tanto no miente: nunca
  //     sale.
  //
  // `in_route` se sigue reconociendo porque es lo que decia el pliego y lo que
  // el desplegable de la ficha llego a mandar; para quien mira, es `in_use`.
  RutaDelVehiculo? get rutaAbierta => rutaActiva;

  AndarDelCamion get andar {
    if (enMantenimiento) return AndarDelCamion.enMantenimiento;
    final ruta = rutaActiva;
    if (ruta == null) return AndarDelCamion.libre;
    return ruta.enCurso ? AndarDelCamion.enRuta : AndarDelCamion.asignado;
  }

  /// Esta LIBRE de verdad: es el «que hay libre» de un vistazo que pidio Jose.
  bool get libre => andar == AndarDelCamion.libre;

  /// `in_use` es el del esquema y `in_route` el que mandaba la ficha del pliego.
  /// Es el campo GUARDADO, no lo que el camion hace: se usa para saber si hay
  /// que limpiarlo, no para pintar la insignia.
  bool get enUso => estado == 'in_use' || estado == 'in_route';
  bool get enMantenimiento => estado == 'maintenance';

  /// EL CAMPO GUARDADO DICE «EN USO» Y NO HAY NINGUNA RUTA ABIERTA.
  ///
  /// Es justo la mentira que el §`ContarVehiculosEnRuta` del servidor ya
  /// avisaba: alguien liberó la ruta por otro camino, o la borró, y el camion se
  /// quedo marcado. No se pinta como «ocupado» —seria repetir la mentira— pero
  /// se deja el boton de limpiarlo, porque ese campo todavia lo miran el
  /// desplegable del asistente y el del tablero.
  bool get estadoGuardadoMiente => enUso && rutaActiva == null;

  /// El texto de la insignia. Sale del [andar], no del campo guardado.
  String get etiquetaEstado => switch (andar) {
    AndarDelCamion.enRuta => 'En ruta',
    AndarDelCamion.asignado => 'Con ruta',
    AndarDelCamion.enMantenimiento => 'Mantenimiento',
    AndarDelCamion.libre => 'Disponible',
  };

  /// Filtra **en el cliente** por nombre y placa, que es lo que hace la de Next.
  bool cuadraCon(String busqueda) {
    final q = busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nombre.toLowerCase().contains(q) ||
        (placa ?? '').toLowerCase().contains(q);
  }
}

/// Un tipo de vehiculo, de `settings.tiposVehiculo`.
class TipoDeVehiculo {
  const TipoDeVehiculo({required this.nombre, this.costoKmUsd});

  factory TipoDeVehiculo.deJson(Map<String, Object?> j) => TipoDeVehiculo(
    nombre: (j['nombre'] as String?) ?? '',
    costoKmUsd: _numero(j['costoKmUsd']),
  );

  final String nombre;
  final double? costoKmUsd;

  Map<String, Object?> aJson() => {'nombre': nombre, 'costoKmUsd': costoKmUsd};

  /// Los tipos que hay que ENSEÑAR en el cajon: los de ajustes **mas los que
  /// ya usan los vehiculos** y todavia no estan en la lista.
  ///
  /// Sin esto, `truck` —el tipo por defecto de todo vehiculo nuevo— no aparece
  /// en ninguna lista donde ponerle su costo por km, y ese costo es el que
  /// cotiza el domicilio que se le cobra al cliente. En produccion los cinco
  /// tipos tenian `costo_km_usd` en NULL por exactamente esto.
  ///
  /// El costo que se siembra sale de un vehiculo de ese tipo que ya lo tenga.
  /// **Si ninguno lo tiene se deja vacio, no en cero**: aqui la de Next pone un
  /// `0`, y un cero guardado se lee como «el kilometro es gratis» —un numero
  /// creible y equivocado— mientras que un hueco se ve y se rellena.
  static List<TipoDeVehiculo> paraElCajon({
    required List<TipoDeVehiculo> deAjustes,
    required List<VehiculoDeLaApi> vehiculos,
  }) {
    final conocidos = {for (final t in deAjustes) t.nombre};
    final sembrados = <TipoDeVehiculo>[];
    for (final v in vehiculos) {
      final nombre = v.tipo?.trim();
      if (nombre == null || nombre.isEmpty) continue;
      if (!conocidos.add(nombre)) continue;
      sembrados.add(
        TipoDeVehiculo(
          nombre: nombre,
          costoKmUsd: vehiculos
              .where((o) => o.tipo == nombre && o.costoKmUsd != null)
              .firstOrNull
              ?.costoKmUsd,
        ),
      );
    }
    return [...deAjustes, ...sembrados];
  }
}

/// Lo que hace falta de `GET /api/settings`: los tipos y la tasa.
class AjustesDeLaApi {
  const AjustesDeLaApi({required this.tipos, required this.cupRate});

  factory AjustesDeLaApi.deJson(Map<String, Object?> j) => AjustesDeLaApi(
    tipos: [
      for (final t in (j['tiposVehiculo'] as List<Object?>?) ?? const [])
        TipoDeVehiculo.deJson(t! as Map<String, Object?>),
    ],
    // 320 por defecto, lo dice el pliego. Sin tasa el ayudante del costo por km
    // no se puede calcular, y quedarse sin ayudante es peor que usar la de la
    // casa diciendo cual es.
    cupRate: _numero(j['cupRate']) ?? 320,
  );

  final List<TipoDeVehiculo> tipos;
  final double cupRate;
}

/// Lo que se manda al crear o editar. Los nombres son los del contrato.
class DatosVehiculo {
  const DatosVehiculo({
    required this.nombre,
    this.tipo,
    this.placa,
    this.capacidad,
    this.estado,
    this.notas,
    this.costoKmUsd,
    this.usarParaDomicilio,
  });

  final String nombre;
  final String? tipo;
  final String? placa;
  final double? capacidad;
  final String? estado;
  final String? notas;
  final double? costoKmUsd;
  final bool? usarParaDomicilio;

  Map<String, Object?> aJson() => <String, Object?>{
    'name': nombre,
    'type': tipo,
    'plate': placa,
    'capacity': capacidad,
    'status': estado,
    'notes': notas,
    'costoKmUsd': costoKmUsd,
    'usarParaDomicilio': usarParaDomicilio,
  };
}
