// EL ENLACE DE LA RUTA: el `https://www.google.com/maps/dir/?api=1…` que abre el
// recorrido en Google Maps, y el texto con el que se le manda al chofer.
//
// ## Lo que se manda, y por que asi
//
// Origen = el almacen, paradas en orden como `waypoints`, y **destino = el mismo
// almacen**, porque el camion vuelve. Es la misma geometria que mide
// `geo.dart` (`kmDelCircuito` cierra el circuito) y la misma que ensena el
// croquis, para que los tres cuenten la misma ruta.
//
// ## AQUI, Y EN NINGUN OTRO SITIO
//
// Hubo un rato en que esto estuvo duplicado: `vista/detalle_ruta.dart` tenia su
// propio `enlaceDeGoogleMaps(RutaConTodo)`, escrito cuando este fichero no
// existia. Ya no: la copia se borro al enchufar el mapa, y **no se vuelve a
// abrir otra**. Dos funciones que contestan lo mismo se separan sin que salte
// nada, que es el §3-bis del `CLAUDE.md` entero.
//
// ## Lo que esta version hace y la vieja no
//
// La vieja devolvia una cadena SIEMPRE, tambien cuando la ruta no tenia
// coordenadas de origen: salia `origin=null,null`, un enlace roto que se copia,
// se manda por WhatsApp y falla en el telefono del chofer, lejos de aqui. Esta
// devuelve el motivo en vez del enlace, para que la pantalla lo diga (regla 4:
// si algo falla, la pantalla no se queda verde).
//
// Y cuenta **las dos** formas de quedarse fuera: pasarse del tope y no tener
// coordenadas. La vieja solo avisaba de la primera.

import 'recorrido.dart';

/// Google admite 25 paradas en un enlace. Mas alla se recortan y **se dice**
/// cuantas quedan fuera.
///
/// El porque, con las palabras del patron: *un enlace que se come cinco paradas
/// en silencio manda al chofer a dar media vuelta*. El recorte en si no se puede
/// evitar —el tope lo pone Google—; lo que si se puede evitar es que nadie se
/// entere, y eso es el §3 del `CLAUDE.md` entero: si pides un tope, comprueba si
/// lo alcanzaste, y si no puedes seguir, dilo nombrando lo que se quedo fuera.
///
const topeDeParadasEnElEnlace = 25;

/// El resultado de intentar armar el enlace: o la direccion, o el motivo por el
/// que no la hay. Nunca las dos, nunca ninguna.
///
/// Es UNA sola funcion y UN solo objeto —y no un `enlace()` mas un
/// `porQueNoHayEnlace()`— porque dos funciones que contestan sobre lo mismo se
/// separan sin que salte nada (`CLAUDE.md` §3-bis).
class EnlaceDeLaRuta {
  const EnlaceDeLaRuta._({
    required this.paradasEnElEnlace,
    required this.fueraPorElTope,
    required this.fueraSinCoordenadas,
    this.url,
    this.motivo,
  });

  /// La direccion, o `null` si no se pudo armar (entonces [motivo] la explica).
  final String? url;

  /// Por que no hay enlace. No es `null` exactamente cuando [url] lo es.
  final String? motivo;

  /// Cuantas paradas viajan de verdad dentro del enlace.
  final int paradasEnElEnlace;

  /// Cuantas se quedan fuera por pasarse del tope de Google.
  final int fueraPorElTope;

  /// Cuantas se quedan fuera por no tener coordenadas guardadas.
  final int fueraSinCoordenadas;

  bool get hay => url != null;

  /// La frase que la pantalla ensena cuando algo no viaja en el enlace, o `null`
  /// cuando van todas. **Nombra lo que se queda fuera y por que**, que es la
  /// regla del §3 (un truncamiento en silencio es el fallo que mas caro sale).
  String? get loQueQuedaFuera {
    final trozos = <String>[
      if (fueraPorElTope > 0)
        'Google admite $topeDeParadasEnElEnlace paradas en un enlace: '
            '${_paradas(fueraPorElTope)} ${_quedan(fueraPorElTope)} fuera.',
      if (fueraSinCoordenadas > 0)
        '${_paradas(fueraSinCoordenadas)} no ${_tienen(fueraSinCoordenadas)} '
            'coordenadas y no ${_entran(fueraSinCoordenadas)} en el enlace.',
    ];
    return trozos.isEmpty ? null : trozos.join(' ');
  }

  /// «3 paradas» / «1 parada». **Es EL patrón de plural de la casa** y por eso
  /// es público: el mensaje al chofer del mapa lo usa también, y una segunda
  /// copia es una segunda forma de decirlo el día que alguien la toque.
  ///
  /// El cero va en plural —«0 paradas»—, que es el que se cuela cuando uno
  /// pregunta por el singular y sólo mira el uno.
  static String cuantasParadas(int n) => n == 1 ? '1 parada' : '$n paradas';

  static String _paradas(int n) => cuantasParadas(n);
  static String _quedan(int n) => n == 1 ? 'queda' : 'quedan';
  static String _tienen(int n) => n == 1 ? 'tiene' : 'tienen';
  static String _entran(int n) => n == 1 ? 'entra' : 'entran';
}

/// Arma el enlace de Google Maps del [recorrido].
///
/// El recorte del tope se hace **sobre la lista entera de paradas**, no sobre
/// las que tienen coordenadas: el tope es «cuantas paradas caben», y una parada
/// sin GPS ocupa su sitio en la ruta igual que las demas. Contarlo al reves
/// haria que anadir una parada sin coordenadas metiera otra en el enlace, que es
/// un numero que cambia por un motivo que nadie relacionaria.
EnlaceDeLaRuta enlaceDeLaRuta(Recorrido recorrido) {
  final primeras = recorrido.paradas.take(topeDeParadasEnElEnlace).toList();
  final conPunto = [
    for (final p in primeras)
      if (p.seDibuja) p,
  ];
  final fueraPorElTope = recorrido.paradas.length - primeras.length;
  final fueraSinCoordenadas = primeras.length - conPunto.length;

  EnlaceDeLaRuta sinEnlace(String motivo) => EnlaceDeLaRuta._(
    paradasEnElEnlace: 0,
    fueraPorElTope: fueraPorElTope,
    fueraSinCoordenadas: fueraSinCoordenadas,
    motivo: motivo,
  );

  final origen = recorrido.origen;
  if (origen == null) {
    return sinEnlace(
      'Esta ruta no tiene guardadas las coordenadas del almacén de salida, '
      'así que no se puede armar el enlace de Google Maps.',
    );
  }
  if (conPunto.isEmpty) {
    return sinEnlace(
      recorrido.paradas.isEmpty
          ? 'Esta ruta todavía no tiene paradas.'
          : 'Ninguna de las ${recorrido.paradas.length} paradas tiene '
                'coordenadas guardadas, así que el enlace no llevaría a ningún '
                'sitio.',
    );
  }

  final desde = '${origen.lat},${origen.lng}';
  final puntos = [for (final p in conPunto) '${p.punto!.lat},${p.punto!.lng}'];
  return EnlaceDeLaRuta._(
    paradasEnElEnlace: conPunto.length,
    fueraPorElTope: fueraPorElTope,
    fueraSinCoordenadas: fueraSinCoordenadas,
    url:
        'https://www.google.com/maps/dir/?api=1'
        '&origin=$desde'
        '&destination=$desde'
        '&waypoints=${puntos.join('|')}'
        '&travelmode=driving&dir_action=navigate',
  );
}

/// EL MENSAJE QUE LE LLEGA AL CHOFER.
///
/// Lleva el enlace **y ademas el texto**, en este orden y no al reves: en
/// WhatsApp el enlace de la ultima linea es el que se convierte en tarjeta con
/// vista previa, y lo que el chofer tiene que poder tocar sin leer nada es el
/// enlace.
///
/// Si algo se queda fuera del enlace, va DENTRO del mensaje. El chofer es quien
/// menos puede permitirse enterarse tarde de que le faltan tres paradas.
String mensajeParaElChofer({
  required String titulo,
  required String resumen,
  required EnlaceDeLaRuta enlace,
}) => [
  titulo,
  resumen,
  if (enlace.loQueQuedaFuera != null) enlace.loQueQuedaFuera!,
  if (enlace.hay) enlace.url! else enlace.motivo!,
].join('\n');

/// El enlace que abre WhatsApp con el mensaje ya escrito.
///
/// `wa.me` sin numero abre el selector de chats: en Android lo coge la
/// aplicacion instalada y en el navegador lo coge WhatsApp Web. Por eso el boton
/// de WhatsApp **no necesita ningun plugin**; el que si lo necesita es el cajon
/// de compartir del sistema.
Uri enlaceDeWhatsApp(String mensaje) =>
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(mensaje)}');
