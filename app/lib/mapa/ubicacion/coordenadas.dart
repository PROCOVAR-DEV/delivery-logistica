/// `parseCoordInput`, calcado de `reglas-negocio.md` §9.
///
/// Reutilizable para elegir un punto en el mapa (el punto de un almacen cuando Reparto los
/// editaba; hoy queda para poner a mano el punto de entrega de un pedido).
///
/// Sin conexion no hay autocompletado de direccion ni geocodificacion inversa
/// —eso es Nominatim, y Nominatim es red—, asi que **escribir el punto a mano es
/// la unica via que queda siempre**. Por eso la funcion vive aparte y se prueba
/// sola: si acepta un formato de menos, alguien se queda sin poder poner el
/// almacen donde esta.
///
/// Las otras dos vias del patron —buscar la direccion y pulsar en el mapa—
/// viven en `geocodificar.dart` y en `mapa_para_elegir_punto.dart`.
/// Pulsar en el mapa tampoco necesita red (es geometria); buscar la direccion
/// si, y por eso su respuesta separa «no lo encuentro» de «no pude preguntar».
class PuntoEnElMapa {
  const PuntoEnElMapa(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is PuntoEnElMapa && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => '$lat, $lng';
}

/// Maximo 3 digitos enteros, `,` `;` o espacio como separador.
final _formato = RegExp(
  r'^(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$',
);

/// Devuelve el punto o `null`. `null` significa «no se entiende», y la pantalla
/// lo dice; no se inventa un 0,0, que cae en el golfo de Guinea y desde ahi se
/// cotizan domicilios de nueve mil kilometros.
PuntoEnElMapa? leerCoordenadas(String texto) {
  final casa = _formato.firstMatch(texto.trim());
  if (casa == null) return null;
  final lat = double.tryParse(casa.group(1)!);
  final lng = double.tryParse(casa.group(2)!);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return PuntoEnElMapa(lat, lng);
}

/// DECIMALES CON LOS QUE SE ESCRIBE UN PUNTO. Cinco, como `formatCoords` de
/// `reglas-negocio.md` §9 y como `DecimalesDeCoordenadas` del servidor
/// (`api/internal/cotizar/geocode.go`). No es estetica: con cinco decimales se
/// distingue un portal de otro (~1 m); con cuatro ya no.
const decimalesDeCoordenadas = 5;

/// Como se ESCRIBE un punto en la caja de coordenadas: `lat, lng` con cinco
/// decimales, **coma y espacio**.
///
/// Existe porque ahora hay tres vias que escriben en esa caja —la mano, el mapa
/// y la geocodificacion— y las tres tienen que dejar el mismo texto. Si cada una
/// lo formatea a su manera, el mismo punto se lee de dos formas distintas en la
/// misma pantalla, que es justo lo que el servidor se cuida de evitar.
///
/// Lo que escribe esto lo vuelve a leer [leerCoordenadas]: es la ida y la vuelta
/// del mismo dato, y la prueba las hace ir y volver.
String escribirCoordenadas(PuntoEnElMapa punto) =>
    '${punto.lat.toStringAsFixed(decimalesDeCoordenadas)}, '
    '${punto.lng.toStringAsFixed(decimalesDeCoordenadas)}';
