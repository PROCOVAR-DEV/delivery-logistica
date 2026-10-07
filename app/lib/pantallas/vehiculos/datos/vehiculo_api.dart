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

/// `vehicles.status` = `'maintenance'`: el camion esta en el taller.
///
/// Es el UNICO estado de la flota que se guarda, porque es el unico que no se
/// puede deducir: un camion en el taller no tiene ruta, exactamente igual que
/// uno libre. Lo demas —libre, con ruta planificada, en ruta— sale de las rutas
/// abiertas del camion (ver `VehiculoDeLaApi.andar`).
///
/// LO SUYO SERIA QUE ESTUVIERA AL LADO DE `EstadoVehiculo.disponible` y
/// `.enUso`, en `nucleo/base/tablas/catalogos.dart`, que es el catalogo de los
/// literales de la base. Se queda aqui y queda dicho: moverlo es un cambio de
/// otro fichero y no se hace de paso. Lo importa quien lo necesita —el asistente
/// de Rutas y el «Camion previsto» del tablero leen `Vehiculo.status` de la base
/// local— para que el literal `'maintenance'` este escrito UNA vez.
const estadoEnMantenimiento = 'maintenance';

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
    this.activo = true,
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
      activo: j['isActive'] != false,
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
  final bool activo;
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
  //   · `enMantenimiento` — el camion esta en el taller. Es el UNICO de esta
  //     lista que sale del campo guardado y no de las rutas, y es a proposito:
  //     es lo unico que NO se puede deducir, porque un camion en el taller no
  //     tiene ruta, igual que uno libre. Se guarda desde el 28/09/2026, con la
  //     migracion 00013; hasta ese dia el enum `vehicle_status` sólo tenia
  //     `available` e `in_use` y el servidor contestaba 400, asi que esta rama
  //     estaba escrita y no salia nunca. El motivo del taller va en las NOTAS
  //     del vehiculo, que ya existian: ninguna columna nueva.
  //
  // `in_route` se sigue reconociendo porque es lo que decia el pliego y lo que
  // el desplegable de la ficha llego a mandar; para quien mira, es `in_use`.
  RutaDelVehiculo? get rutaAbierta => rutaActiva;

  // ## QUIEN MANDA CUANDO EL TALLER Y LA RUTA SE CONTRADICEN — 28/09/2026
  //
  // Desde que `maintenance` se puede guardar hay una pareja nueva y real: un
  // camion marcado en el taller **que ademas lleva una ruta abierta**. Pasa sola
  // —se manda al taller a mitad de ruta, o se marca y la ruta de ayer se quedo
  // sin cerrar— y no es un caso raro que se pueda dejar sin contestar.
  //
  // **Manda el TALLER para la insignia**, y el porque no es que un dato sea mas
  // fiable que el otro: es cual de las dos lecturas equivocadas se lee como
  // normal.
  //
  //   · Si ganara la ruta, la tarjeta diria «En ruta» sobre un camion que esta
  //     en el taller. Eso no llama la atencion de nadie: es exactamente lo que
  //     se espera ver, asi que el aviso no se busca, y la ruta sigue su camino
  //     con un camion que no existe.
  //   · Ganando el taller, la tarjeta dice «Mantenimiento» sobre un camion que
  //     tiene una ruta abierta, y eso **si** chirria — y justo debajo se dice
  //     con todas las letras, nombrando la ruta (`enTallerConRutaAbierta`).
  //
  // Es la misma decision que ya estaba tomada para `estadoGuardadoMiente`: entre
  // dos lecturas, se pinta la que hace que alguien mire. Y hay un segundo motivo
  // que apunta al mismo sitio: `maintenance` es el unico de los cuatro estados
  // que alguien tuvo que escribir A PROPOSITO. Nadie manda un camion al taller
  // por descuido; una ruta planificada ayer y nunca cerrada, todos los dias.
  //
  // Y el servidor NO cierra la ruta al mandar el camion al taller, tambien a
  // proposito (`internal/api/vehiculos.go`): cerrarla seria darla por repartida,
  // y una ruta completada es la que llego. La contradiccion se enseña, no se
  // resuelve por nuestra cuenta.
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
  bool get enMantenimiento => estado == estadoEnMantenimiento;

  /// ESTA EN EL TALLER Y ADEMAS LLEVA UNA RUTA ABIERTA.
  ///
  /// Una contradiccion de verdad, no una mentira de un campo viejo: las dos
  /// mitades estan respaldadas —alguien escribio «al taller» a mano y hay una
  /// ruta sin cerrar con su codigo—. Por eso no se elige una y se tira la otra:
  /// se dice, con la ruta nombrada, para que quien lo vea decida si el camion
  /// vuelve a estar disponible o si esa ruta hay que pasarla a otro.
  ///
  /// La insignia la gana el taller; el porque esta arriba, en `andar`.
  bool get enTallerConRutaAbierta => enMantenimiento && rutaActiva != null;

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
    this.activo,
    this.notas,
    this.costoKmUsd,
    this.usarParaDomicilio,
  });

  final String nombre;
  final String? tipo;
  final String? placa;
  final double? capacidad;
  final String? estado;
  final bool? activo;
  final String? notas;
  final double? costoKmUsd;
  final bool? usarParaDomicilio;

  Map<String, Object?> aJson() => <String, Object?>{
    'name': nombre,
    'type': tipo,
    'plate': placa,
    'capacity': capacidad,
    'status': estado,
    'isActive': activo,
    'notes': notas,
    'costoKmUsd': costoKmUsd,
    'usarParaDomicilio': usarParaDomicilio,
  };
}
