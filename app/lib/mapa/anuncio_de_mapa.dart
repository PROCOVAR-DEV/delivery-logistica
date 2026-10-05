// QUÉ HAY COLGADO Y QUÉ TENGO YO — la otra mitad del encargo.
//
// Jose, 17/09/2026: «decir servidor del mapa descargado, algo así como datos de
// la APK para saber si sacaron cosas nuevas, para mantener eso hecho».
//
// O sea: lo mismo que el aviso de versión de la aplicación
// (`nucleo/actualizacion/`, `docs/actualizaciones.md`), y por eso se parece
// letra a letra — mismos estados sellados, mismo «no se fuerza nada», misma
// regla de que no saber no es una noticia.
//
// ## Lo que se compara, que no es obvio
//
// Se compara **el nivel que tengo contra el mismo nivel del servidor**. No con
// «el último»: si alguien eligió «Sólo carreteras» porque tiene 2,4 MB y la
// conexión de allá, no se le puede decir que está desactualizado porque haya
// salido uno de 61 MB. Eso no es una versión nueva, es otra decisión, y la toma
// él.
//
// Y hay un caso que parece un detalle y no lo es: **misma versión, otra huella**.
// Significa que alguien volvió a colgar el fichero sin cambiar el número. Se
// avisa igual, y se dice eso mismo: callarlo deja al aparato con un fichero que
// ya no es el que el servidor cree que tiene, para siempre.

import 'dart:convert';

import 'package:dio/dio.dart';

import '../nucleo/registro/registro.dart';

/// `enMegas` SE MUDÓ a `nucleo/descarga/en_megas.dart` el 05/10/2026, porque el
/// motor de bajar —que ahora lo comparten el mapa y la actualización de la APK—
/// tiene que escribir «llegaron 12,0 MB de los 75,0» y no puede depender del
/// mapa para eso.
///
/// Se re-exporta desde aquí **a propósito**: cinco ficheros lo importaban de este
/// y así ninguno se tuvo que tocar. Cambiar de sitio una función no es motivo
/// para ir a mover cinco `import`.
export '../nucleo/descarga/en_megas.dart' show enMegas;

/// UN NIVEL DE DETALLE colgado para descargar, tal y como lo anuncia
/// `GET /api/mapa`.
class NivelDeMapa {
  const NivelDeMapa({
    required this.nivel,
    required this.version,
    required this.bytes,
    required this.sha256,
    required this.url,
    this.fecha,
  });

  /// La clave: `basico`, `completo`, `detallado`. **No se valida contra una
  /// lista** a propósito: si un día se cuelga un nivel nuevo, la aplicación lo
  /// ofrece sin tener que actualizarse. Lo que no sabe es cómo se llama en
  /// bonito, y entonces enseña la clave — ver [titulo].
  final String nivel;

  /// La del ORIGEN de los datos (el sello del `.osm.pbf`), no la de la
  /// aplicación ni la de la api. Son tres números distintos.
  final String version;
  final String? fecha;

  /// Lo que pesa. **Se dice antes de bajar nada.**
  final int bytes;

  /// Lo que separa «bajado» de «bajado entero».
  final String sha256;

  final String url;

  /// El nombre que ve la persona. Los conocidos van traducidos; **uno
  /// desconocido se enseña con su clave y su tamaño, no se esconde**: esconderlo
  /// sería descartar en silencio un nivel que alguien colgó a propósito
  /// (`CLAUDE.md` §4).
  String get titulo => switch (nivel) {
    'basico' => 'Sólo carreteras',
    'completo' => 'Completo, con calles',
    'detallado' => 'Detallado, con caminos',
    _ => 'Nivel «$nivel»',
  };

  String get explicacion => switch (nivel) {
    'basico' =>
      'Las carreteras que unen los pueblos, la costa y los núcleos con su '
          'nombre. Para ver dónde cae cada parada y por dónde se va.',
    'completo' =>
      'Todo lo del básico más las calles de las ciudades con su nombre. Es el '
          'que hace falta para llegar a un domicilio.',
    'detallado' =>
      'Todo lo del completo, un acercamiento más y los caminos de tierra. Sólo '
          'hace falta si se reparte fuera de la ciudad.',
    _ => 'Un nivel de detalle que esta versión de la aplicación no conoce.',
  };

  /// Lee un nivel del JSON. `null` si le falta algo de lo que hace falta para
  /// bajarlo **con seguridad**: sin tamaño se baja a ciegas y sin huella no hay
  /// forma de saber si llegó entero.
  static NivelDeMapa? deJson(Object? crudo) {
    if (crudo is! Map) return null;
    final nivel = crudo['nivel'];
    final version = crudo['version'];
    final url = crudo['url'];
    final sha = crudo['sha256'];
    final bytes = crudo['bytes'];
    if (nivel is! String || nivel.isEmpty) return null;
    if (version is! String || version.isEmpty) return null;
    if (url is! String || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return null;
    }
    if (sha is! String || sha.length != 64) return null;
    if (bytes is! num || bytes <= 0) return null;
    final fecha = crudo['fecha'];
    return NivelDeMapa(
      nivel: nivel,
      version: version,
      bytes: bytes.toInt(),
      sha256: sha.toLowerCase(),
      url: url,
      fecha: fecha is String && fecha.isNotEmpty ? fecha : null,
    );
  }

  /// El nombre del fichero dentro de la carpeta.
  String get fichero => 'cuba-$nivel.pmtiles';
  String get ficheroParcial => '$fichero.parcial';
  String get apunte => 'cuba-$nivel.json';
}

/// LO QUE HAY EN EL APARATO.
class PaqueteGuardado {
  const PaqueteGuardado({
    required this.nivel,
    required this.version,
    required this.bytes,
    required this.sha256,
    required this.guardadoAt,
  });

  final String nivel;
  final String version;
  final int bytes;
  final String sha256;
  final DateTime guardadoAt;

  String get titulo => NivelDeMapa(
    nivel: nivel,
    version: version,
    bytes: bytes,
    sha256: sha256,
    url: 'https://x',
  ).titulo;

  Map<String, Object?> aJson() => {
    'nivel': nivel,
    'version': version,
    'bytes': bytes,
    'sha256': sha256,
    'guardadoAt': guardadoAt.toIso8601String(),
  };

  static PaqueteGuardado? deJson(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    try {
      final m = jsonDecode(texto);
      if (m is! Map) return null;
      final nivel = m['nivel'];
      final version = m['version'];
      final sha = m['sha256'];
      final bytes = m['bytes'];
      final at = DateTime.tryParse('${m['guardadoAt']}');
      if (nivel is! String || version is! String || sha is! String) return null;
      if (bytes is! num || at == null) return null;
      return PaqueteGuardado(
        nivel: nivel,
        version: version,
        bytes: bytes.toInt(),
        sha256: sha,
        guardadoAt: at,
      );
    } on Object {
      return null;
    }
  }
}

/// LOS CINCO ESTADOS, sellados: la pantalla que los mire tiene que tratarlos
/// todos. Es lo que impide que «no se pudo comprobar» acabe pintado como «lo
/// tienes al día».
sealed class EstadoDelMapa {
  const EstadoDelMapa();
}

/// La web. Aquí no hay paquete y no lo va a haber.
class MapaNoAplica extends EstadoDelMapa {
  const MapaNoAplica();
}

/// No hay nada guardado. [ofertas] es lo que se puede bajar, de menor a mayor.
/// Vacía significa que el servidor no tiene nada colgado todavía.
class SinPaqueteDeMapa extends EstadoDelMapa {
  const SinPaqueteDeMapa(this.ofertas, {this.ilegibles = 0});

  final List<NivelDeMapa> ofertas;

  /// Cuántos niveles anunció el servidor que **no se pudieron leer**. No es
  /// adorno: si el servidor anuncia tres y aquí se entienden dos, la persona
  /// tiene que poder enterarse de que falta uno (`CLAUDE.md` §4).
  final int ilegibles;
}

/// Lo guardado es lo que hay colgado.
class MapaAlDia extends EstadoDelMapa {
  const MapaAlDia(this.tengo, this.ofertas);

  final PaqueteGuardado tengo;

  /// Los otros niveles, por si alguien quiere cambiar de detalle.
  final List<NivelDeMapa> ofertas;
}

/// Hay uno más nuevo del MISMO nivel.
class HayMapaNuevo extends EstadoDelMapa {
  const HayMapaNuevo(this.tengo, this.nuevo, this.motivo, this.ofertas);

  final PaqueteGuardado tengo;
  final NivelDeMapa nuevo;

  /// Por qué se considera nuevo. Se enseña: «hay uno nuevo» sin más no le dice a
  /// nadie si le corre prisa.
  final String motivo;
  final List<NivelDeMapa> ofertas;
}

/// No hubo red, o el servidor contestó algo raro.
///
/// **No se enseña**, igual que el `NoSeSupo` del aviso de versión: no saber si
/// hay mapa nuevo no es una noticia para quien está trabajando. Lo que sí se
/// enseña es lo que se tenga guardado, que sigue sirviendo.
class NoSeSupoDelMapa extends EstadoDelMapa {
  const NoSeSupoDelMapa(this.tengo, this.motivo);

  final PaqueteGuardado? tengo;
  final String motivo;
}

/// QUIEN PREGUNTA AL SERVIDOR.
class AnuncioDeMapa {
  const AnuncioDeMapa(this._cliente, this._api);

  final Dio _cliente;

  /// La base de la api, la misma que usa el resto (`nucleo/red/entorno.dart`).
  final String _api;

  /// Los niveles colgados, de menor a mayor tamaño. Lanza si no se pudo
  /// preguntar: quien llama decide si eso es una avería o el patio de un almacén.
  Future<({List<NivelDeMapa> niveles, int ilegibles})> loQueHay() async {
    final r = await _cliente.get<Object?>('$_api/mapa');
    final cuerpo = r.data;
    if (cuerpo is! Map) {
      throw const FormatException('el servidor no contestó el contrato de /api/mapa');
    }
    final crudos = cuerpo['niveles'];
    if (crudos == null) return (niveles: const <NivelDeMapa>[], ilegibles: 0);
    if (crudos is! List) {
      throw const FormatException('«niveles» no es una lista');
    }
    final niveles = <NivelDeMapa>[];
    var ilegibles = 0;
    for (final crudo in crudos) {
      final n = NivelDeMapa.deJson(crudo);
      if (n == null) {
        // NADA SE DESCARTA EN SILENCIO. Se cuenta y se anota, y quien llama lo
        // sube a la pantalla.
        ilegibles++;
        Registro.aviso('un nivel de mapa anunciado no se pudo leer: $crudo');
        continue;
      }
      niveles.add(n);
    }
    niveles.sort((a, b) => a.bytes.compareTo(b.bytes));
    return (niveles: niveles, ilegibles: ilegibles);
  }
}

/// LA COMPARACIÓN, aparte y pura para poder probarla sin red ni disco.
EstadoDelMapa compararElMapa({
  required PaqueteGuardado? tengo,
  required List<NivelDeMapa> colgados,
  int ilegibles = 0,
}) {
  if (tengo == null) return SinPaqueteDeMapa(colgados, ilegibles: ilegibles);

  // El MISMO nivel, no «el último». Quien eligió 2,4 MB no está desactualizado
  // porque haya salido uno de 61.
  NivelDeMapa? elMio;
  for (final c in colgados) {
    if (c.nivel == tengo.nivel) elMio = c;
  }
  if (elMio == null) {
    // El servidor ya no cuelga este nivel. Lo guardado sigue sirviendo —el mapa
    // de Cuba de hace un mes es un mapa de Cuba— así que no se borra ni se
    // alarma: se deja como está.
    return MapaAlDia(tengo, colgados);
  }
  if (elMio.version != tengo.version) {
    return HayMapaNuevo(
      tengo,
      elMio,
      'El mapa se actualizó: tienes la versión ${versionComoSeLee(tengo.version)} '
      'y hay la ${versionComoSeLee(elMio.version)}.',
      colgados,
    );
  }
  if (elMio.sha256 != tengo.sha256) {
    // MISMA VERSIÓN Y OTRA HUELLA. Alguien volvió a colgar el fichero sin
    // cambiar el número. Callarlo deja el aparato con algo que el servidor cree
    // que no tiene, para siempre.
    return HayMapaNuevo(
      tengo,
      elMio,
      'El fichero del mapa cambió sin cambiar de versión '
      '(${versionComoSeLee(elMio.version)}). Conviene volver a bajarlo.',
      colgados,
    );
  }
  return MapaAlDia(tengo, colgados);
}

/// LA VERSIÓN, ESCRITA SIEMPRE IGUAL — 22/09/2026.
///
/// En el teléfono de Jose salía esta frase: «tienes la versión **2026-09-21** y
/// hay la **260922**». Las dos son la misma clase de cosa escrita de dos
/// formas, porque los paquetes viejos se guardaron cuando el servidor anunciaba
/// la fecha con guiones y ahora la anuncia como `AAMMDD`. Puestas una al lado
/// de la otra no se pueden ni comparar de un vistazo, que es justo para lo que
/// está la frase.
///
/// **Esto es sólo para escribirla.** La comparación sigue siendo exacta, texto
/// contra texto: una versión es una etiqueta que pone el servidor y no nos toca
/// interpretarla. Normalizar antes de comparar haría que `260922` y
/// `2026-09-22` se dieran por iguales, y entonces un mapa nuevo con la fecha
/// escrita de otra forma no se anunciaría nunca.
String versionComoSeLee(String version) {
  if (version.length != 6) return version;
  final n = int.tryParse(version);
  if (n == null) return version;
  final mes = int.parse(version.substring(2, 4));
  final dia = int.parse(version.substring(4, 6));
  // Si no es una fecha, se deja tal cual: inventarse un mes 17 sería peor que
  // enseñar los seis dígitos.
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return version;
  return '20${version.substring(0, 2)}-${version.substring(2, 4)}-'
      '${version.substring(4, 6)}';
}
