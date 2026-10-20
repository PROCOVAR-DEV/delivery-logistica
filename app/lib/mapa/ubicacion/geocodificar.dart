// Reutilizable para elegir un punto en el mapa (hoy sin pantalla que lo use: Reparto ya no
// edita almacenes; lo aprovechara poner a mano el punto de entrega de un pedido).
//
// LA GEOCODIFICACION: las dos vias de poner un punto que NECESITAN RED, y lo
// que se dice exactamente cuando no la hay.
//
// ═══════════════════════════════════════════════════════════════════════════
// POR QUE EXISTE ESTE FICHERO: se habian perdido dos de las tres vias
// ═══════════════════════════════════════════════════════════════════════════
//
// El patron (`delivery/src/components/LocationInput.tsx` + `src/lib/geocode.ts`)
// da TRES formas de poner el punto de un almacen:
//
//  1. escribir la direccion y buscarla  → geocodificacion directa;
//  2. pegar `"lat, lng"`                → `leerCoordenadas`, sin red;
//  3. pulsar en el mapa                 → geocodificacion inversa, que rellena
//     la direccion.
//
// Aqui se habia quedado sólo la 2. `coordenadas.dart` explica muy bien por que
// la 2 tiene que existir siempre; lo que nadie escribio nunca es por que se
// habian ido la 1 y la 3 — y por el §2 del `CLAUDE.md`, una separacion del
// patron sin motivo escrito no es una decision, es un olvido. Vuelven las dos.
//
// Y es la pantalla donde mas duele: de este punto salen los kilometros de cada
// cliente de la sucursal, y de esos kilometros sale lo que se le cobra a cada
// domicilio todos los dias. Un punto puesto a ojo con dos digitos cambiados se
// lee perfectamente bien y esta mal.
//
// ═══════════════════════════════════════════════════════════════════════════
// DE DONDE SALE LA GEOCODIFICACION, Y POR QUE DESDE EL APARATO
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo primero que se miro fue el servidor, que es donde esta la regla de la casa
// sobre salir a servicios de fuera. Lo que hay hoy en `api/internal/`:
//
//   * `internal/cotizar/geocode.go` traduce §9 de `reglas-negocio.md` pero **sólo
//     la parte que es cuenta** —`FormatCoords`, `ZoomDesdeArea`,
//     `ParsearCoordenadas`—, y su cabecera lo dice con todas las letras:
//     «`forwardGeocode` y `reverseGeocode` salen a Nominatim y NO VIVEN AQUI».
//   * no hay ninguna ruta de geocodificacion en `servidor.go`. El camino no
//     existe todavia; no es que estuviera y no se usara.
//   * `internal/api/mapa.go` es el precedente que si hay de «hablar con OSM», y
//     esta escrito al reves a proposito: el servidor **no** baja teselas, porque
//     bajarlas en bloque va contra la politica de uso de OSM y el castigo es un
//     bloqueo por IP — «ya nos paso con Hostinger el 04/08/2026».
//
// Asi que el camino que SI existe hoy es el de esta misma aplicacion:
// `pantallas/rutas/datos/mapa_en_vivo.dart` ya sale a `tile.openstreetmap.org`
// y a `router.project-osrm.org` desde el aparato, detras de una interfaz que
// **nunca lanza** y que en las pruebas se sustituye por una falsa para que **no
// salga ni una peticion**. Esto se monta igual, pieza por pieza. Cuando haga
// falta un `/api/geocode` en el servidor —una sola IP, un solo `User-Agent` y
// una cache compartida son mejores vecinos que diez aparatos— se cambia el
// implementador y esta pantalla no se entera: para eso es un puerto.
//
// ═══════════════════════════════════════════════════════════════════════════
// LA DIFERENCIA QUE TIENE QUE SOBREVIVIR A TODO: «no lo encuentro» ≠ «no pude
// preguntar»
// ═══════════════════════════════════════════════════════════════════════════
//
// El patron devuelve `null` para las dos cosas (`catch { return null }`) y su
// inversa devuelve las coordenadas formateadas cuando falla, o sea que **sin
// red contesta como si hubiera geocodificado**. Eso aqui no se puede copiar: la
// mitad del proyecto es trabajar sin senal (`CLAUDE.md` §1) y la regla 4 dice
// que nada se descarta en silencio y que la pantalla no se queda verde.
//
// Por eso la respuesta es un tipo sellado con los cuatro casos separados. El
// que manda es [NoSePudoPreguntar]: mientras se pueda distinguir, la pantalla
// puede decir «no se pudo preguntar, escribe las coordenadas a mano» en vez de
// «esa direccion no existe», que es mentira, o de quedarse girando.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nucleo/plataforma.dart';
import '../../nucleo/registro/registro.dart';
import 'coordenadas.dart';

/// Nominatim, sin clave de API. Las mismas constantes de `reglas-negocio.md` §9.
const nominatim = 'https://nominatim.openstreetmap.org';
const agenteDeNominatim = 'ProCovarDelivery/1.0';

/// **Por debajo de esto no se sale a la red.** Es el corte previo de §9
/// (`query.trim().length < 4`), y ademas lo que evita mandarle a Nominatim una
/// peticion por cada letra.
const minimoParaBuscar = 4;

// ─────────────────────────────────────────────────────────────────────────────
// LO QUE CONTESTA BUSCAR UNA DIRECCION
// ─────────────────────────────────────────────────────────────────────────────

/// El resultado de buscar una direccion. Sellado **para que la pantalla tenga
/// que decidir que dice en cada caso**: con un `null` para todo, el caso de «no
/// hay red» se pinta igual que el de «no existe» y nadie se entera.
sealed class BusquedaDeDireccion {
  const BusquedaDeDireccion();
}

/// Nominatim contesto y hay punto.
class PuntoHallado extends BusquedaDeDireccion {
  const PuntoHallado(this.punto, {this.comoLoLlama});

  final PuntoEnElMapa punto;

  /// El nombre completo que le da Nominatim, si lo trae. Es una **sugerencia**:
  /// no pisa lo que haya escrito una persona (el editor que lo use).
  final String? comoLoLlama;
}

/// Nominatim contesto Y NO CONOCE esa direccion. Esto sólo se devuelve cuando la
/// respuesta se entendio y venia vacia: una respuesta ilegible NO es esto.
class NoHayTalDireccion extends BusquedaDeDireccion {
  const NoHayTalDireccion();
}

/// El texto es demasiado corto para preguntar (§9: menos de 4 caracteres). No se
/// sale a la red y no es un fallo de nadie.
class DemasiadoCorto extends BusquedaDeDireccion {
  const DemasiadoCorto();
}

/// **NO SE PUDO PREGUNTAR.** Sin red, con el servicio caido, o con una respuesta
/// que no se entiende. Lo que nunca puede pasar es que esto se cuente como un
/// punto: el punto se sigue pudiendo escribir a mano, que es la via que no falla
/// nunca.
class NoSePudoPreguntar extends BusquedaDeDireccion {
  const NoSePudoPreguntar(this.motivo);

  final String motivo;
}

// ─────────────────────────────────────────────────────────────────────────────
// LO QUE CONTESTA PREGUNTAR POR UN PUNTO (la geocodificacion INVERSA)
// ─────────────────────────────────────────────────────────────────────────────

/// El resultado de preguntar como se llama un punto.
sealed class BusquedaDePunto {
  const BusquedaDePunto();
}

/// Nominatim contesto y le pone nombre.
class DireccionHallada extends BusquedaDePunto {
  const DireccionHallada(this.texto);

  final String texto;
}

/// Contesto y ese punto no tiene nombre (en medio del campo pasa a menudo). El
/// punto sigue puesto: lo que falta es el rotulo, no la coordenada.
class SinNombreParaEsePunto extends BusquedaDePunto {
  const SinNombreParaEsePunto();
}

/// No se pudo preguntar. **Y no se inventa una direccion.**
///
/// Aqui esta la unica diferencia de fondo con el patron, y es a proposito: su
/// `reverseGeocode` devuelve `formatCoords(lat,lng)` cuando falla, o sea que la
/// caja de la direccion se rellena sola con «20.02470, -75.82190» y la pantalla
/// se ve exactamente igual que si hubiera geocodificado. Un dato inventado que
/// se lee bien es justo lo que esta prohibido aqui (`CLAUDE.md` §4).
class NoSePudoPreguntarElPunto extends BusquedaDePunto {
  const NoSePudoPreguntarElPunto(this.motivo);

  final String motivo;
}

// ─────────────────────────────────────────────────────────────────────────────
// EL PUERTO
// ─────────────────────────────────────────────────────────────────────────────

/// Quien sabe traducir entre direcciones y puntos. **Nunca lanza**: cada fallo
/// tiene su caso en el tipo de vuelta.
abstract interface class Geocodificador {
  Future<BusquedaDeDireccion> buscarDireccion(String texto);

  Future<BusquedaDePunto> comoSeLlamaEstePunto(PuntoEnElMapa punto);
}

/// El de Nominatim, el mismo servicio del patron.
class GeocodificadorDeNominatim implements Geocodificador {
  GeocodificadorDeNominatim([Dio? cliente]) : _cliente = cliente ?? Dio();

  final Dio _cliente;

  /// Corto a proposito, como el de OSRM y por lo mismo: con la conexion de alla,
  /// esperar medio minuto por una direccion deja a alguien mirando una rueda
  /// cuando lo que tiene que hacer es escribir las coordenadas a mano.
  static const plazo = Duration(seconds: 8);

  Options get _opciones => Options(
    receiveTimeout: plazo,
    sendTimeout: plazo,
    headers: {
      // `User-Agent` sólo fuera del navegador: en web es una cabecera prohibida
      // —la pone el navegador y no se deja cambiar—, y mandarla revienta la
      // peticion antes de salir. Alli Nominatim identifica por el `Referer`, que
      // va solo.
      if (Destino.trabajaSinConexion) 'User-Agent': agenteDeNominatim,
      'Accept-Language': 'es',
    },
  );

  @override
  Future<BusquedaDeDireccion> buscarDireccion(String texto) async {
    if (texto.trim().length < minimoParaBuscar) return const DemasiadoCorto();
    try {
      final respuesta = await _cliente.get<Object?>(
        '$nominatim/search',
        queryParameters: {
          'format': 'json',
          'q': texto.trim(),
          'limit': 1,
          'accept-language': 'es',
        },
        options: _opciones,
      );
      return leerLaBusqueda(respuesta.data);
    } on Object catch (e) {
      Registro.aviso('Nominatim no contesto a la busqueda: $e');
      return NoSePudoPreguntar('$e');
    }
  }

  @override
  Future<BusquedaDePunto> comoSeLlamaEstePunto(PuntoEnElMapa punto) async {
    try {
      final respuesta = await _cliente.get<Object?>(
        '$nominatim/reverse',
        queryParameters: {
          'format': 'json',
          'lat': punto.lat,
          'lon': punto.lng,
          'accept-language': 'es',
        },
        options: _opciones,
      );
      return leerLaInversa(respuesta.data);
    } on Object catch (e) {
      Registro.aviso('Nominatim no contesto a la inversa: $e');
      return NoSePudoPreguntarElPunto('$e');
    }
  }
}

/// SACA EL PUNTO DE LA RESPUESTA DE NOMINATIM. **Aparte y publica para poder
/// probarla**, igual que `leerLaGeometria` de OSRM: es donde se rompen estas
/// cosas, no en el `get`.
///
/// Todo se comprueba con `is` y NADA con `as`. Un `as` sobre lo que contesta
/// otro servicio lanza, y esto corre con el cajon del editor abierto: una
/// respuesta con otra forma —un error en JSON, un proxy metiendo HTML— tumbaria
/// el cajon en vez de dejar la caja de coordenadas, que es la via que siempre
/// funciona.
BusquedaDeDireccion leerLaBusqueda(Object? cuerpo) {
  // Una lista vacia es la UNICA forma de «no la conozco». Cualquier otra cosa es
  // «no entendi la respuesta», y eso se cuenta como no haber podido preguntar:
  // decir «esa direccion no existe» porque llego un HTML es mentir.
  if (cuerpo is! List) {
    return const NoSePudoPreguntar('la respuesta no es una lista');
  }
  if (cuerpo.isEmpty) return const NoHayTalDireccion();
  final primero = cuerpo.first;
  if (primero is! Map) {
    return const NoSePudoPreguntar('el primer resultado no es un objeto');
  }
  final lat = _numero(primero['lat']);
  final lng = _numero(primero['lon']);
  if (lat == null || lng == null) {
    return const NoSePudoPreguntar('el resultado viene sin coordenadas');
  }
  // EL MISMO RECORTE POR RANGO QUE `leerCoordenadas`, y hace falta: sin el, un
  // servicio equivocado o un proxy que conteste otra cosa coloca el almacen
  // fuera del mundo y desde ahi se cotizan domicilios de nueve mil kilometros.
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return const NoSePudoPreguntar('el resultado cae fuera del mundo');
  }
  final nombre = primero['display_name'];
  return PuntoHallado(
    PuntoEnElMapa(lat, lng),
    comoLoLlama: nombre is String && nombre.trim().isNotEmpty
        ? nombre.trim()
        : null,
  );
}

/// Saca la direccion de la respuesta inversa. Publica por lo mismo.
BusquedaDePunto leerLaInversa(Object? cuerpo) {
  if (cuerpo is! Map) {
    return const NoSePudoPreguntarElPunto('la respuesta no es un objeto');
  }
  final nombre = cuerpo['display_name'];
  if (nombre is String && nombre.trim().isNotEmpty) {
    return DireccionHallada(nombre.trim());
  }
  // Nominatim contesto y no le pone nombre a ese punto. **No se cae a las
  // coordenadas formateadas**: el punto ya esta puesto y escribirlo tambien en
  // la caja de la direccion no anade nada y disfraza un hueco de dato.
  return const SinNombreParaEsePunto();
}

double? _numero(Object? valor) => switch (valor) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// El que no sabe nada y lo dice. Es lo que se inyecta en las pruebas —asi **no
/// sale ni una peticion**, que es regla de la casa en este PC— y ademas deja la
/// pantalla exactamente como se ve sin señal.
class SinGeocodificar implements Geocodificador {
  const SinGeocodificar([this.motivo = 'sin conexión']);

  final String motivo;

  @override
  Future<BusquedaDeDireccion> buscarDireccion(String texto) async =>
      NoSePudoPreguntar(motivo);

  @override
  Future<BusquedaDePunto> comoSeLlamaEstePunto(PuntoEnElMapa punto) async =>
      NoSePudoPreguntarElPunto(motivo);
}

final geocodificadorProvider = Provider<Geocodificador>(
  (ref) => GeocodificadorDeNominatim(),
);
