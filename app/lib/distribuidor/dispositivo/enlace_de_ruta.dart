// EL ENLACE DE UNA RUTA: `https://reparto.procovar.cloud/r/<token>`, que el logistico
// manda por WhatsApp. Tambien se acepta pegar solo el token.

const hostDelEnlace = 'reparto.procovar.cloud';
const prefijoDelEnlace = '/r/';

/// El token de un enlace pegado (o el propio token si se pego solo). `null` si no
/// parece ninguno: una URL de OTRO sitio no vale. Recorta espacios y saltos de linea,
/// y se queda con lo que va despues de `/r/` SIN `?parametros` ni `#ancla`.
String? tokenDelEnlace(String? texto) {
  final crudo = (texto ?? '').trim();
  if (crudo.isEmpty) return null;
  // Si pegaron un mensaje entero de WhatsApp, vale el primer trozo que parezca el enlace.
  final enMensaje = RegExp(
    'https?://${RegExp.escape(hostDelEnlace)}$prefijoDelEnlace\\S+',
  ).firstMatch(crudo)?.group(0);
  final uno = enMensaje ?? crudo.split(RegExp(r'\s+')).first;
  final uri = Uri.tryParse(uno);
  if (uri != null && uri.hasScheme) {
    if (uri.host != hostDelEnlace || !uri.path.startsWith(prefijoDelEnlace)) {
      return null;
    }
    return _limpio(uri.path.substring(prefijoDelEnlace.length));
  }
  // `/r/<token>` (ruta interna del enrutador), con o sin parametros.
  if (uno.startsWith(prefijoDelEnlace)) {
    return _limpio(uno.substring(prefijoDelEnlace.length));
  }
  return _limpio(uno);
}

/// Un token son letras, cifras, `-` y `_`: sin espacios, barras ni parametros.
String? _limpio(String t) {
  final token = t.split(RegExp(r'[?#]')).first.replaceAll(RegExp(r'/+$'), '');
  return RegExp(r'^[A-Za-z0-9_\-.~]{6,}$').hasMatch(token) ? token : null;
}
