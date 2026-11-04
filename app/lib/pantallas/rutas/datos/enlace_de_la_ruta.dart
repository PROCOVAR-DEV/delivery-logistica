// EL MENSAJE QUE SE LE MANDA AL DISTRIBUIDOR.
//
// Antes aqui se armaba el enlace de Google Maps de la ruta y la lista de facturas por parada. Todo eso se fue (04/11/2026): el
// distribuidor ya no navega con Google Maps ni lee un mensaje largo, sino que abre en su teléfono el enlace de la ruta
// (`https://reparto.procovar.cloud/r/<token>`) con la app «Reparto Distribuidor», que le dice parada a parada qué entregar y qué cobrar.
// El enlace lo crea el servidor (`distribucion/datos/api_distribucion.dart`); aquí solo se escribe la frase que lo acompaña.

/// «3 paradas» / «1 parada». **Es EL patrón de plural de la casa**: lo usan más pantallas, y una segunda copia es una segunda
/// forma de decirlo el día que alguien la toque. El cero va en plural —«0 paradas»—, que es el que se cuela cuando uno pregunta
/// por el singular y solo mira el uno.
String cuantasParadas(int n) => n == 1 ? '1 parada' : '$n paradas';

/// «Tu ruta RT-001 · Reparto Vista · 4/11/2026 · 3 paradas:» + el enlace en su propia línea + qué app hace falta.
///
/// Texto de Jose (04/11/2026): el enlace abre la app Reparto Distribuidor; si no la tiene, la página del enlace (`/r/<token>`) le
/// dice cómo instalarla. Por eso el mensaje lo avisa. El enlace va en su línea y sin punto pegado, para que WhatsApp lo convierta
/// en tarjeta y lo que el distribuidor toque sea solo el enlace.
String mensajeParaElDistribuidor({
  required String codigo,
  required String fecha,
  required int paradas,
  required String url,
  String? nombre,
}) =>
    'Tu ruta ${[codigo, if (nombre != null && nombre.isNotEmpty) nombre, fecha, cuantasParadas(paradas)].join(' · ')}:\n'
    '$url\n'
    'Necesitas la app Reparto Distribuidor; si no la tienes, el enlace te dice cómo instalarla.';

/// El enlace que abre WhatsApp con el mensaje ya escrito.
///
/// `wa.me` sin numero abre el selector de chats: en Android lo coge la aplicacion instalada y en el navegador lo coge WhatsApp
/// Web. Por eso el boton de WhatsApp **no necesita ningun plugin**; el que si lo necesita es el cajon de compartir del sistema.
Uri enlaceDeWhatsApp(String mensaje) =>
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(mensaje)}');
