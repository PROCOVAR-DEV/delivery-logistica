import 'package:dio/dio.dart';

/// ¿ESTA RESPUESTA LA ESCRIBIÓ NUESTRO SERVIDOR, O ALGO QUE SE CRUZÓ EN MEDIO?
///
/// ## Un código HTTP no dice de quién es — 28/09/2026
///
/// Entre el teléfono y nuestra API hay cacharros, y algunos **contestan por su
/// cuenta**: el propio router con su página de configuración, un proxy
/// transparente del proveedor, un filtro de la red del cliente, una redirección
/// a cualquier sitio. Ninguno de ellos es nuestro servidor, pero todos mandan
/// un código HTTP de vuelta — un 200, un 302, un 403, un 404—, y hasta hoy eso
/// bastaba para que el aparato diera la petición por llegada: había respuesta,
/// luego la red iba.
///
/// La diferencia entre esas dos cosas no está en que haya respuesta, está en
/// **quién la firma**. Nuestra API contesta JSON siempre —`httpx.JSON` pone
/// `application/json; charset=utf-8` en TODAS, también en las que no llevan
/// cuerpo—; lo que se cruza en medio contesta HTML o texto suelto, porque lo
/// suyo es que lo lea un navegador. Ésa es la firma, y es la que se mira aquí.
///
/// Esto **no es el aviso de «no hay internet»**, que es otra cosa y la sabe el
/// sistema operativo (ver `salud.dart`). Esto es la línea que separa «el
/// servidor dijo que no» de «no llegué al servidor», y de ella cuelgan dos
/// decisiones caras: si la salud de la red cuenta el intento como bueno, y si
/// un 401 **echa a alguien a la pantalla de acceso**. Un 401 que no escribió
/// nuestro servidor no puede tener ese poder; antes lo tenía.
///
/// ## Por qué esto vale más que preguntarle a nuestro dominio
///
/// Porque no hace una petición de más. La comprobación va sobre la respuesta
/// que ya vino, en el camino que ya se recorría; con la conexión de allá, cada
/// petición extra son segundos de rueda y batería, y encima se podría caer ella
/// sola y decidir por su cuenta que no hay red.
///
/// ## La cabecera manda sobre el cuerpo, y el silencio se cree
///
/// El orden de abajo no es casual:
///
///  1. **Si viene `Content-Type`, decide él.** Algo que dijera `text/html` y
///     mandara un JSON dentro seguiría sin ser nuestro servidor.
///  2. **Si no viene ninguna, se mira la forma del cuerpo**: un `Map` o una
///     lista ya son JSON decodificado; un texto que empieza por `{` o por `[`
///     lo es sin decodificar (pasa en las pruebas, con adaptadores que no se
///     molestan en poner cabeceras); uno que empieza por `<` es una página.
///  3. **Un cuerpo vacío y sin cabecera se da por NUESTRO.** Es la única puerta
///     que se deja abierta a propósito, y el motivo es el §3-quinquies: un
///     aviso que salta en falso deja de leerse, y entonces tampoco se lee el
///     día que de verdad no hay señal. Quien se cruza en medio contesta para
///     que alguien lea algo, así que cero bytes no es su forma de fallar; sí es
///     la de una respuesta nuestra sin cuerpo.
bool contestoLoNuestro(Response<dynamic>? respuesta) {
  if (respuesta == null) return false;
  return loNuestro(tipo: tipoDeContenido(respuesta), cuerpo: respuesta.data);
}

/// El `Content-Type` de la respuesta, o `null` si no vino ninguno.
///
/// Se saca aparte porque además de decidir sirve para **contarlo**: cuando esto
/// dice que no, lo primero que hace falta saber es qué llegó en vez de lo
/// nuestro, y `text/html` en el registro es media investigación hecha.
String? tipoDeContenido(Response<dynamic>? respuesta) {
  final valor = respuesta?.headers.value(Headers.contentTypeHeader);
  if (valor == null || valor.trim().isEmpty) return null;
  return valor;
}

/// La regla de [contestoLoNuestro] sobre las dos piezas sueltas, para poder
/// probarla sin montar un `Response` entero.
bool loNuestro({String? tipo, Object? cuerpo}) {
  if (tipo != null) return _esJson(tipo);

  // Sin cabecera, la forma del cuerpo. `Map` y `List` ya vienen decodificados
  // por Dio, que sólo decodifica cuando el tipo era JSON.
  if (cuerpo is Map || cuerpo is List) return true;
  if (cuerpo is String) {
    final texto = cuerpo.trimLeft();
    // Vacío: ver el punto 3 de la explicación de arriba.
    if (texto.isEmpty) return true;
    return texto.startsWith('{') || texto.startsWith('[');
  }
  // `null` es la respuesta sin cuerpo. Cualquier otra cosa (bytes sueltos, un
  // `ResponseBody` en crudo) no pasa por aquí: los flujos y las descargas del
  // mapa van por su propio Dio, sin interceptores.
  return cuerpo == null;
}

/// `application/json`, `text/json` y los `…+json` (`application/problem+json`).
///
/// Se compara a mano y no con `MediaType` para no arrastrar otra dependencia
/// por tres cadenas; los parámetros (`; charset=utf-8`) se cortan antes.
bool _esJson(String tipo) {
  final mime = tipo.split(';').first.trim().toLowerCase();
  return mime == 'application/json' ||
      mime == 'text/json' ||
      mime.endsWith('+json');
}
