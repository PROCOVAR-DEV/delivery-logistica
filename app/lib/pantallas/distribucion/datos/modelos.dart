// LO QUE EL SERVIDOR CONTESTA SOBRE LA DISTRIBUCION, leido del JSON (docs/oficina-distribucion.md).
//
// Son pantallas SOLO de la oficina (logistico, administrador, super admin, desarrollador) y SOLO con conexion: el seguimiento del
// GPS y el enlace de cada ruta viven en el servidor, no en la copia del aparato. Por eso no son tablas de Drift.
//
// Todo lo que el servidor puede no mandar es opcional, y quien pinta dice «sin dato»: un hueco que se ve vale mas que un cero
// creible (misma regla que el costo por km sin cotizar).

import '../../rutas/datos/geo.dart';

DateTime? _hora(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
double? _num(Object? v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};
String? _texto(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

// ------------------------------------------------------------------ ENLACE

enum EstadoDelEnlace { sinEnlace, sinReclamar, reclamado }

/// El enlace de una ruta para el distribuidor (`/api/routes/{id}/enlace`).
class EnlaceDeRuta {
  const EnlaceDeRuta({
    required this.estado,
    this.token,
    this.url,
    this.creadoAt,
    this.dispositivoId,
    this.dispositivo,
    this.reclamadoAt,
  });

  factory EnlaceDeRuta.deJson(Map<String, Object?> j) => EnlaceDeRuta(
    estado: switch (j['estado']) {
      'reclamado' => EstadoDelEnlace.reclamado,
      'sin_reclamar' => EstadoDelEnlace.sinReclamar,
      _ => EstadoDelEnlace.sinEnlace,
    },
    token: _texto(j['token']),
    url: _texto(j['url']),
    creadoAt: _hora(j['creadoAt']),
    dispositivoId: _texto(j['dispositivoId']),
    dispositivo: _texto(j['dispositivo']),
    reclamadoAt: _hora(j['reclamadoAt']),
  );

  final EstadoDelEnlace estado;
  final String? token;
  final String? url;
  final DateTime? creadoAt;
  final String? dispositivoId;

  /// El nombre del teléfono que reclamó la ruta (modelo o apodo).
  final String? dispositivo;
  final DateTime? reclamadoAt;

  bool get hayEnlace => estado != EstadoDelEnlace.sinEnlace && url != null;
}

// ------------------------------------------------------------------ RECORRIDO REAL

/// Un punto del GPS del teléfono. [evento]: `inicio`, `parada` o `fin` (nulo = punto de la marcha).
class PuntoGps {
  const PuntoGps({
    required this.lat,
    required this.lng,
    required this.hora,
    this.id,
    this.precision,
    this.velocidad,
    this.rumbo,
    this.evento,
    this.pedidoId,
  });

  factory PuntoGps.deJson(Map<String, Object?> j) => PuntoGps(
    id: _texto(j['id']),
    lat: _num(j['lat']) ?? 0,
    lng: _num(j['lng']) ?? 0,
    precision: _num(j['precision']),
    velocidad: _num(j['velocidad']),
    rumbo: _num(j['rumbo']),
    hora: _hora(j['hora']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    evento: _texto(j['evento']),
    pedidoId: _texto(j['pedidoId']),
  );

  final String? id;
  final double lat;
  final double lng;
  final double? precision;
  final double? velocidad;
  final double? rumbo;
  final DateTime hora;
  final String? evento;
  final String? pedidoId;

  Punto get punto => Punto(lat, lng);
}

/// Una parada tal y como la dejó el distribuidor. La [resultadoAt] es la HORA REAL DEL APARATO, no la de cuando se subió.
class ParadaDelTrack {
  const ParadaDelTrack({
    required this.pedidoId,
    required this.orden,
    this.factura,
    this.cliente,
    this.lat,
    this.lng,
    this.resultado,
    this.resultadoAt,
    this.nota,
    this.cobroEntrega,
    this.cobroEntregaAt,
  });

  factory ParadaDelTrack.deJson(Map<String, Object?> j) => ParadaDelTrack(
    pedidoId: (j['pedidoId'] ?? '') as String,
    orden: (_num(j['orden']) ?? 0).toInt(),
    factura: _texto(j['factura']),
    cliente: _texto(j['cliente']),
    lat: _num(j['lat']),
    lng: _num(j['lng']),
    resultado: _texto(j['resultado']),
    resultadoAt: _hora(j['resultadoAt']),
    nota: _texto(j['nota']),
    cobroEntrega: _texto(j['cobroEntrega']),
    cobroEntregaAt: _hora(j['cobroEntregaAt']),
  );

  final String pedidoId;
  final int orden;
  final String? factura;
  final String? cliente;
  final double? lat;
  final double? lng;

  /// `entregado`, `devuelto`, `no_entregada`… tal cual lo guarda el servidor.
  final String? resultado;
  final DateTime? resultadoAt;
  final String? nota;

  /// `cobrado`, `no_cobrado` o nulo (no se anotó).
  final String? cobroEntrega;
  final DateTime? cobroEntregaAt;

  Punto? get punto => (lat == null || lng == null) ? null : Punto(lat!, lng!);
}

/// La cabecera de la ruta dentro de `/track`.
class RutaDelTrack {
  const RutaDelTrack({
    required this.id,
    this.codigo,
    this.nombre,
    this.estado,
    this.inicio,
    this.fin,
    this.distribuidor,
    this.vehiculo,
  });

  factory RutaDelTrack.deJson(Map<String, Object?> j) => RutaDelTrack(
    id: (j['id'] ?? '') as String,
    codigo: _texto(j['codigo']),
    nombre: _texto(j['nombre']),
    estado: _texto(j['estado']),
    inicio: _hora(j['inicio']),
    fin: _hora(j['fin']),
    distribuidor: _texto(j['distribuidor']),
    vehiculo: _texto(j['vehiculo']),
  );

  final String id;
  final String? codigo;
  final String? nombre;
  final String? estado;
  final DateTime? inicio;
  final DateTime? fin;
  final String? distribuidor;
  final String? vehiculo;
}

/// Cuanto cerca (en metros) tiene que pasar el GPS de una parada para contar que el camión llegó.
const metrosParaDarPorLlegado = 75.0;

/// Si la marca de una parada se hizo a mas de esto de su punto, se avisa: se marcó sin estar allí.
const metrosParaAvisarDeMarcaLejana = 250.0;

/// Una parada con sus tiempos ya calculados.
class ParadaConTiempos {
  const ParadaConTiempos({
    required this.parada,
    required this.numero,
    this.desdeLaAnterior,
    this.enLaParada,
    this.llegada,
    this.metrosDeLaMarca,
  });

  final ParadaDelTrack parada;
  final int numero;

  /// Desde la marca anterior (o desde la salida, en la primera) hasta la marca de esta.
  final Duration? desdeLaAnterior;

  /// Desde que el GPS pasó junto a la parada hasta que se marcó. Nulo = el GPS no pasó por allí (o no hay punto).
  final Duration? enLaParada;
  final DateTime? llegada;

  /// A cuantos metros de su punto se hizo la marca (con el punto GPS del evento `parada` de ese pedido).
  final double? metrosDeLaMarca;

  bool get marcaLejana =>
      metrosDeLaMarca != null &&
      metrosDeLaMarca! > metrosParaAvisarDeMarcaLejana;
}

/// `GET /api/routes/{id}/track`, con las cuentas del recorrido.
class RecorridoReal {
  const RecorridoReal({
    required this.ruta,
    required this.puntos,
    required this.paradas,
    this.truncado = false,
  });

  factory RecorridoReal.deJson(Map<String, Object?> j) => RecorridoReal(
    ruta: RutaDelTrack.deJson(
      (j['ruta'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    puntos: [
      for (final p in (j['puntos'] as List?) ?? const [])
        PuntoGps.deJson((p! as Map).cast<String, Object?>()),
    ]..sort((a, b) => a.hora.compareTo(b.hora)),
    paradas: [
      for (final p in (j['paradas'] as List?) ?? const [])
        ParadaDelTrack.deJson((p! as Map).cast<String, Object?>()),
    ]..sort((a, b) => a.orden.compareTo(b.orden)),
    truncado: j['truncado'] == true,
  );

  final RutaDelTrack ruta;
  final List<PuntoGps> puntos;
  final List<ParadaDelTrack> paradas;

  /// El servidor recortó la traza (demasiados puntos): lo que se ve es una parte.
  final bool truncado;

  bool get hayPuntos => puntos.isNotEmpty;

  /// La salida: la que dice la ruta, y si no, el primer punto del GPS.
  DateTime? get salida => ruta.inicio ?? (hayPuntos ? puntos.first.hora : null);

  /// La llegada: solo cuando la ruta terminó. En una ruta en curso no hay llegada todavía.
  DateTime? get llegada =>
      ruta.fin ??
      (ruta.estado == 'completed' && hayPuntos ? puntos.last.hora : null);

  Duration? get duracionTotal {
    final a = salida;
    final b = llegada;
    if (a == null || b == null || b.isBefore(a)) return null;
    return b.difference(a);
  }

  /// Los km que midió el GPS, sumando punto a punto. Un salto de mas de 5 km entre dos puntos seguidos se cuenta igual: es lo
  /// que hizo el teléfono (un hueco sin señal), y quitarlo escondería el hueco.
  double get kmPorLaTraza {
    var total = 0.0;
    for (var i = 1; i < puntos.length; i++) {
      total += haversineKm(puntos[i - 1].punto, puntos[i].punto);
    }
    return total;
  }

  /// La traza para dibujar.
  List<Punto> get traza => [for (final p in puntos) p.punto];

  /// Las paradas con sus tiempos.
  List<ParadaConTiempos> get conTiempos {
    final salida = this.salida;
    DateTime? marcaAnterior = salida;
    final salidas = <ParadaConTiempos>[];
    for (final (i, p) in paradas.indexed) {
      final marca = p.resultadoAt;
      Duration? desde;
      if (marca != null &&
          marcaAnterior != null &&
          !marca.isBefore(marcaAnterior)) {
        desde = marca.difference(marcaAnterior);
      }

      DateTime? llegada;
      final donde = p.punto;
      if (marca != null && donde != null) {
        for (final g in puntos) {
          if (marcaAnterior != null && g.hora.isBefore(marcaAnterior)) continue;
          if (g.hora.isAfter(marca)) break;
          if (haversineKm(g.punto, donde) * 1000 <= metrosParaDarPorLlegado) {
            llegada = g.hora;
            break;
          }
        }
      }

      double? metros;
      final delEvento = puntos
          .where((g) => g.evento == 'parada' && g.pedidoId == p.pedidoId)
          .firstOrNull;
      if (delEvento != null && donde != null) {
        metros = haversineKm(delEvento.punto, donde) * 1000;
      }

      salidas.add(
        ParadaConTiempos(
          parada: p,
          numero: i + 1,
          desdeLaAnterior: desde,
          llegada: llegada,
          enLaParada: (llegada != null && marca != null)
              ? marca.difference(llegada)
              : null,
          metrosDeLaMarca: metros,
        ),
      );
      if (marca != null) marcaAnterior = marca;
    }
    return salidas;
  }
}

// ------------------------------------------------------------------ HISTORIAL DE UN VEHICULO

class RutaDelHistorial {
  const RutaDelHistorial({
    required this.id,
    this.codigo,
    this.nombre,
    this.estado,
    this.fecha,
    this.inicio,
    this.fin,
    this.km,
    this.distribuidor,
    this.paradas = 0,
    this.entregadas = 0,
    this.devueltas = 0,
    this.cobradas = 0,
    this.puntos = 0,
  });

  factory RutaDelHistorial.deJson(Map<String, Object?> j) => RutaDelHistorial(
    id: (j['id'] ?? '') as String,
    codigo: _texto(j['codigo']),
    nombre: _texto(j['nombre']),
    estado: _texto(j['estado']),
    fecha: _hora(j['fecha']),
    inicio: _hora(j['inicio']),
    fin: _hora(j['fin']),
    km: _num(j['km']),
    distribuidor: _texto(j['distribuidor']),
    paradas: (_num(j['paradas']) ?? 0).toInt(),
    entregadas: (_num(j['entregadas']) ?? 0).toInt(),
    devueltas: (_num(j['devueltas']) ?? 0).toInt(),
    cobradas: (_num(j['cobradas']) ?? 0).toInt(),
    puntos: (_num(j['puntos']) ?? 0).toInt(),
  );

  final String id;
  final String? codigo;
  final String? nombre;
  final String? estado;
  final DateTime? fecha;
  final DateTime? inicio;
  final DateTime? fin;
  final double? km;
  final String? distribuidor;
  final int paradas;
  final int entregadas;
  final int devueltas;
  final int cobradas;

  /// Cuantos puntos de GPS tiene: con cero no hay recorrido que enseñar.
  final int puntos;

  Duration? get duracion {
    if (inicio == null || fin == null || fin!.isBefore(inicio!)) return null;
    return fin!.difference(inicio!);
  }
}

// ------------------------------------------------------------------ DONDE ESTAN AHORA

/// Pasados estos minutos sin noticias del teléfono, se avisa en ámbar.
const minutosSinSenalParaAvisar = 10;

class DistribuidorAhora {
  const DistribuidorAhora({
    required this.distribuidorId,
    required this.lat,
    required this.lng,
    this.distribuidor,
    this.hora,
    this.recibidoAt,
    this.velocidad,
    this.rutaIds = const [],
  });

  factory DistribuidorAhora.deJson(Map<String, Object?> j) => DistribuidorAhora(
    distribuidorId: (j['distribuidorId'] ?? '') as String,
    distribuidor: _texto(j['distribuidor']),
    lat: _num(j['lat']) ?? 0,
    lng: _num(j['lng']) ?? 0,
    hora: _hora(j['hora']),
    recibidoAt: _hora(j['recibidoAt']),
    velocidad: _num(j['velocidad']),
    rutaIds: [for (final r in (j['rutaIds'] as List?) ?? const []) '$r'],
  );

  final String distribuidorId;
  final String? distribuidor;
  final double lat;
  final double lng;

  /// La hora del aparato en el punto.
  final DateTime? hora;

  /// Cuándo llegó al servidor: es el «hace cuánto lo mandó».
  final DateTime? recibidoAt;
  final double? velocidad;
  final List<String> rutaIds;

  /// Desde cuándo no se sabe nada: lo que llegó al servidor, o la hora del punto si el servidor no la dijo.
  DateTime? get ultimaNoticia => recibidoAt ?? hora;

  Duration? haceCuanto(DateTime ahora) {
    final u = ultimaNoticia;
    if (u == null) return null;
    final d = ahora.difference(u);
    return d.isNegative ? Duration.zero : d;
  }

  /// Sin noticias, o con mas de [minutosSinSenalParaAvisar] minutos.
  bool sinSenal(DateTime ahora) {
    final d = haceCuanto(ahora);
    return d == null || d.inMinutes >= minutosSinSenalParaAvisar;
  }
}

// ------------------------------------------------------------------ REVISION

/// De cada ruta de `GET /api/routes`, lo que hace falta para la segunda llave.
///
/// [llevaRevision]: el servidor mandó el campo `revisadaAt` (aunque sea nulo). Si no viene, la ruta no pasa por revisión y no se
/// pinta nada: así este cliente funciona igual con el servidor de antes.
class RevisionDeRuta {
  const RevisionDeRuta({
    required this.id,
    required this.llevaRevision,
    this.codigo,
    this.nombre,
    this.estado,
    this.distribuidor,
    this.vehiculo,
    this.terminada,
    this.revisadaAt,
    this.revisadaPor,
    this.distribuidorId,
    this.vehiculoId,
    this.fecha,
    this.paradas = 0,
  });

  factory RevisionDeRuta.deJson(Map<String, Object?> j) {
    String? nombreDe(Object? o) =>
        o is Map ? _texto(o['nombre'] ?? o['name']) : null;
    return RevisionDeRuta(
      id: (j['id'] ?? '') as String,
      llevaRevision: j.containsKey('revisadaAt'),
      codigo: _texto(j['routeCode']),
      nombre: _texto(j['name']),
      estado: _texto(j['status']),
      distribuidor: nombreDe(j['distribuidor']),
      vehiculo: nombreDe(j['vehicle']),
      terminada: _hora(j['finishedAt']),
      revisadaAt: _hora(j['revisadaAt']),
      revisadaPor: _texto(j['revisadaPor']),
      distribuidorId: _texto(j['distribuidorId']),
      vehiculoId: _texto(j['vehicleId']),
      fecha: _hora(j['deliveryDate']),
      paradas: (j['orders'] as List?)?.length ?? 0,
    );
  }

  final String id;
  final bool llevaRevision;
  final String? codigo;
  final String? nombre;
  final String? estado;
  final String? distribuidor;
  final String? vehiculo;
  final DateTime? terminada;
  final DateTime? revisadaAt;
  final String? revisadaPor;
  final String? distribuidorId;
  final String? vehiculoId;

  /// Día de reparto y cuántas paradas lleva (para escribir el mensaje al distribuidor sin pedir nada más).
  final DateTime? fecha;
  final int paradas;

  bool get completada => estado == 'completed';

  /// Solo se revisa lo completado y que el servidor marca como revisable.
  bool get seRevisa => completada && llevaRevision;
  bool get pendiente => seRevisa && revisadaAt == null;
  bool get revisada => seRevisa && revisadaAt != null;
}

// ------------------------------------------------------------------ VINCULO VEHICULO <-> TELEFONO

/// Un renglón de `GET /api/vehicles/{id}/vinculos`: un teléfono que llevó (o lleva) este vehículo. [hasta] nulo = sigue vinculado.
class VinculoDeVehiculo {
  const VinculoDeVehiculo({
    required this.id,
    this.dispositivoId,
    this.dispositivo,
    this.desde,
    this.hasta,
    this.vinculadoPor,
    this.desvinculadoPor,
    this.motivo,
  });

  factory VinculoDeVehiculo.deJson(Map<String, Object?> j) => VinculoDeVehiculo(
    id: '${j['id'] ?? ''}',
    dispositivoId: _texto(j['dispositivoId']),
    dispositivo: _texto(j['dispositivo']),
    desde: _hora(j['desde']),
    hasta: _hora(j['hasta']),
    vinculadoPor: _texto(j['vinculadoPor']),
    desvinculadoPor: _texto(j['desvinculadoPor']),
    motivo: _texto(j['motivo']),
  );

  final String id;
  final String? dispositivoId;
  final String? dispositivo;
  final DateTime? desde;
  final DateTime? hasta;
  final String? vinculadoPor;
  final String? desvinculadoPor;
  final String? motivo;

  bool get vigente => hasta == null;
}
