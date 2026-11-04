/// EL CÓDIGO DE UNA RUTA SALE DE SU UUIDv7 — `AAMMDD-XXXXXX` (04/11/2026).
///
/// Gemela de `codigoDeRutaDe` (`api/internal/api/codigo_de_ruta.go`): el aparato y
/// el servidor calculan SIEMPRE el mismo código a partir del mismo id, y por eso
/// una ruta armada sin señal ya nace con su código completo y el servidor lo
/// respeta. Lo atan los casos de `docs/codigo-de-ruta.casos.json`, que leen las
/// pruebas de los dos lados.
///
///  * `AAMMDD` — la fecha UTC que lleva dentro el propio id (sus 48 bits de
///    milisegundos): sirve para buscar por fecha. UTC y no Cuba a propósito: no
///    depende de la zona horaria de ningún aparato.
///  * `XXXXXX` — los 30 bits bajos de los últimos 4 bytes (aleatorios del todo),
///    en el alfabeto de Crockford (sin I, L, O ni U).
const _alfabeto = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String codigoDeRutaDe(String idV7) {
  final hex = idV7.replaceAll('-', '');
  if (hex.length != 32) {
    throw FormatException('no es un UUID', idV7);
  }
  final ms = int.parse(hex.substring(0, 12), radix: 16);
  final dia = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  // `%` y no `&`: en la web los operadores de bits son de 32 con signo.
  var n = int.parse(hex.substring(24, 32), radix: 16) % (1 << 30);
  final c = List<String>.filled(6, '0');
  for (var i = 5; i >= 0; i--) {
    c[i] = _alfabeto[n % 32];
    n ~/= 32;
  }
  String dos(int v) => v.toString().padLeft(2, '0');
  return '${dos(dia.year % 100)}${dos(dia.month)}${dos(dia.day)}-${c.join()}';
}
