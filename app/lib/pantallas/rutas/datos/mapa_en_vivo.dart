// LO QUE SOLO SE PUEDE TENER CON SEÑAL: el fondo de calles y el recorrido por
// carretera.
//
// El patron (`delivery/src/components/MapComponent.tsx`) pide las dos cosas a
// internet: las teselas a `tile.openstreetmap.org` y el trazado a
// `router.project-osrm.org`. Aqui se piden igual, pero con una diferencia que es
// TODA la diferencia:
//
// > **Ninguna de las dos hace falta para que el mapa sirva.** El croquis se
// > dibuja primero, con lo que ya esta en el aparato, y estas dos lo MEJORAN si
// > llegan.
//
// Jose, 17/09/2026: «eso lo quiero, y sin conexión también, porque esa es la
// idea: que puedan ver la ruta, y que se cree para que se le dé eso al conductor
// para que vea la ruta». El chofer esta en la calle. Si el mapa dependiera de
// que estas dos peticiones lleguen, el mapa no serviria justo donde tiene que
// servir.
//
// ## Por que son interfaces y no un `dio.get` dentro del `CustomPainter`
//
// Por lo mismo que `abrir_y_compartir.dart`: para poder probarlo. Y ademas por
// una regla de la casa que aqui es literal —**nada de cargar teselas de ningun
// servicio desde este PC**—: con la costura puesta, las pruebas inyectan un
// falso y **no sale ni una peticion**.
//
// ## Y por que el fallo NO se cuenta como fallo
//
// Que no lleguen es el caso NORMAL en el patio de un almacen, no una averia. Por
// eso las dos devuelven `null` en vez de lanzar, y quien las llama cambia lo que
// **dice** la pantalla —«trazado aproximado, en línea recta»— en vez de sacar un
// error. Un aviso rojo cada vez que se abre una ruta sin señal se deja de leer
// en dos dias, y entonces tampoco se lee el dia que importa.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/red/agente_de_usuario.dart';
import '../../../nucleo/registro/registro.dart';
import 'geo.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EL FONDO DE CALLES
// ─────────────────────────────────────────────────────────────────────────────

/// De donde salen las teselas del fondo.
abstract interface class FondoDeCalles {
  /// La tesela `z/x/y`, o `null` si no se pudo traer. **Nunca lanza.**
  Future<ui.Image?> tesela(int z, int x, int y);
}

/// OpenStreetMap, como en el patron.
class CallesDeOsm implements FondoDeCalles {
  CallesDeOsm();

  /// Lo que ya se trajo. Vive mientras viva la aplicacion: volver a abrir la
  /// misma ruta no vuelve a pedir nada, que en la conexion de alla se nota.
  final _traidas = <String, ui.Image?>{};

  @override
  Future<ui.Image?> tesela(int z, int x, int y) async {
    final clave = '$z/$x/$y';
    if (_traidas.containsKey(clave)) return _traidas[clave];
    try {
      final imagen = await _bajar(
        'https://tile.openstreetmap.org/$z/$x/$y.png',
      );
      return _traidas[clave] = imagen;
    } on Object catch (e) {
      // Sin señal esto pasa SIEMPRE y no es una averia: es el caso normal del
      // patio del almacen. Se anota y se sigue con el croquis.
      Registro.aviso('tesela $clave no llego: $e');
      // No se cachea el fallo: cuando vuelva la señal, se vuelve a intentar.
      return null;
    }
  }

  Future<ui.Image> _bajar(String url) async {
    final espera = Completer<ui.Image>();
    final flujo = imagenDeTesela(
      url,
      await agenteDeEstaApp(),
    ).resolve(ImageConfiguration.empty);
    late ImageStreamListener oyente;
    oyente = ImageStreamListener(
      (info, _) {
        flujo.removeListener(oyente);
        if (!espera.isCompleted) espera.complete(info.image);
      },
      onError: (error, _) {
        flujo.removeListener(oyente);
        if (!espera.isCompleted) espera.completeError(error);
      },
    );
    flujo.addListener(oyente);
    return espera.future;
  }
}

/// La tesela con SU `User-Agent`: sin él OpenStreetMap contesta «403 Access blocked» (ver [agenteDeEstaApp]). Sin agente (la web) va
/// sin cabeceras: el navegador no deja ponerlas y un `User-Agent` ahí rompería CORS.
ImageProvider imagenDeTesela(String url, String? agente) =>
    NetworkImage(url, headers: agente == null ? null : {'User-Agent': agente});

/// El que no trae nada. Es lo que se usa en las pruebas y lo que deja el mapa
/// **exactamente** como se ve en el patio de un almacen.
class SinCalles implements FondoDeCalles {
  const SinCalles();

  @override
  Future<ui.Image?> tesela(int z, int x, int y) async => null;
}

final fondoDeCallesProvider = Provider<FondoDeCalles>((ref) => CallesDeOsm());

// ─────────────────────────────────────────────────────────────────────────────
// EL RECORRIDO POR CARRETERA
// ─────────────────────────────────────────────────────────────────────────────

/// Quien sabe por donde van las calles entre dos puntos.
abstract interface class RecorridoPorCalles {
  /// La linea por carretera que pasa por [puntos] en ese orden, o `null` si no
  /// se pudo traer. **Nunca lanza.**
  Future<List<Punto>?> entre(List<Punto> puntos);
}

/// OSRM publico, el mismo del patron.
class CallesDeOsrm implements RecorridoPorCalles {
  CallesDeOsrm([Dio? cliente]) : _cliente = cliente ?? Dio();

  final Dio _cliente;

  @override
  Future<List<Punto>?> entre(List<Punto> puntos) async {
    if (puntos.length < 2) return null;
    final coordenadas = [for (final p in puntos) '${p.lng},${p.lat}'].join(';');
    try {
      final agente = await agenteDeEstaApp();
      final respuesta = await _cliente.get<Map<String, Object?>>(
        'https://router.project-osrm.org/route/v1/driving/$coordenadas',
        queryParameters: const {'overview': 'full', 'geometries': 'geojson'},
        options: Options(
          // Corto a proposito. Con una conexion que va y viene, esperar medio
          // minuto por una mejora deja al logistico mirando una ruta a medio
          // pintar; el croquis ya esta debajo y no necesita a nadie.
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          // Identificarse también aquí (misma razón que las teselas); en la web no se pone.
          headers: agente == null ? null : {'User-Agent': agente},
        ),
      );
      return leerLaGeometria(respuesta.data);
    } on Object catch (e) {
      Registro.aviso('OSRM no contesto: $e');
      return null;
    }
  }
}

/// Saca la linea de la respuesta de OSRM. **Aparte y publica para poder
/// probarla**: es donde se rompen estas cosas, no en el `get`.
List<Punto>? leerLaGeometria(Map<String, Object?>? cuerpo) {
  // TODO comprobado con `is`, NADA de `as`. Un `as` sobre lo que contesta otro
  // servicio lanza, y esto corre dentro de un `then` que repinta el mapa: una
  // respuesta con otra forma —OSRM devolviendo un error en JSON, un proxy
  // metiendo HTML— tumbaria la pantalla en vez de dejar la linea recta. Es la
  // misma razon por la que `catalogos.dart` guarda el texto tal cual en vez de
  // un `textEnum`: lo desconocido entra, y lo trata quien pinta.
  final rutas = cuerpo?['routes'];
  if (rutas is! List || rutas.isEmpty) return null;
  final primera = rutas.first;
  if (primera is! Map) return null;
  final geometria = primera['geometry'];
  if (geometria is! Map) return null;
  final coordenadas = geometria['coordinates'];
  if (coordenadas is! List || coordenadas.length < 2) return null;
  final linea = <Punto>[];
  for (final par in coordenadas) {
    // OSRM da `[lng, lat]`, al reves que todo lo demas de esta casa. Cambiarlos
    // de sitio dibuja la ruta en el oceano Indico, y se ve raro pero no salta.
    if (par is! List || par.length < 2) return null;
    final lng = (par[0] as num?)?.toDouble();
    final lat = (par[1] as num?)?.toDouble();
    if (lng == null || lat == null) return null;
    linea.add(Punto(lat, lng));
  }
  return linea;
}

/// El que no sabe nada. Deja el recorrido en linea recta, que es a lo que cae el
/// propio patron cuando OSRM no contesta (`// fallback straight line`).
class SinCallesQueSeguir implements RecorridoPorCalles {
  const SinCallesQueSeguir();

  @override
  Future<List<Punto>?> entre(List<Punto> puntos) async => null;
}

final recorridoPorCallesProvider = Provider<RecorridoPorCalles>(
  (ref) => CallesDeOsrm(),
);
