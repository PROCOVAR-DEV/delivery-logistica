// EL MAPA DE LA RUTA: el almacen de salida, las paradas en su orden y el
// recorrido — con las calles de verdad cuando hay señal, y sin ellas cuando no.
//
// ═══════════════════════════════════════════════════════════════════════════
// LA DECISION, QUE ES LA UNICA QUE IMPORTA AQUI: SE DIBUJA EN DOS CAPAS
// ═══════════════════════════════════════════════════════════════════════════
//
// El patron (`delivery/src/components/MapComponent.tsx`) monta Leaflet, baja
// teselas de `tile.openstreetmap.org` y le pide el trazado por carretera a
// `router.project-osrm.org`. Las dos cosas son peticiones a internet en el
// momento de pintar, y **si alguna no llega, el mapa deja de contar la ruta**.
//
// Aqui se piden las dos igual, porque Jose las quiere («eso lo quiero»), pero el
// orden esta al reves y eso lo cambia todo:
//
//  1. **PRIMERO se dibuja lo que ya esta en el aparato**: el almacen, las
//     paradas numeradas en su orden y la linea entre ellas. Esto no le pide
//     nada a nadie y sale SIEMPRE, tambien en el patio de un almacen sin
//     cobertura, que es la razon de ser de la APK (`CLAUDE.md` §1).
//  2. **DESPUES, si llegan, se mejora**: las teselas se pintan de fondo y la
//     linea recta se cambia por el recorrido por carretera.
//
// Y esto no es un invento: **el propio patron ya cae a la linea recta** cuando
// OSRM no contesta —su comentario dice `// fallback straight line`—. O sea que
// la decision de «antes que no dibujar nada, la recta» estaba tomada en el
// original. Lo unico que cambia aqui es que la recta deja de ser el plan B de un
// servicio caido y pasa a ser el cimiento, porque en la calle es lo unico que
// hay. Ademas encaja con lo que mide la aplicacion: `geo.dart` calcula los km
// por haversine, o sea **en linea recta**.
//
// Lo que NUNCA puede pasar, y es la regla 4: que el chofer abra el mapa en la
// calle y vea un cuadro gris, o una rueda girando para siempre. Por eso las dos
// peticiones viven detras de una interfaz que **devuelve `null` en vez de
// lanzar** (`datos/mapa_en_vivo.dart`), y por eso la pantalla **dice** cual de
// las dos capas esta viendo (`mapa_de_la_ruta.dart` escribe la frase).
//
// ## Lo que se copia del patron, pieza por pieza
//
//  * el almacen de salida marcado aparte (alli `isOrigin`, pin verde con
//    estrella; aqui un cuadro oscuro con su rotulo);
//  * las paradas **numeradas en su orden de visita**, no todas iguales;
//  * el regreso al deposito **en naranja y a rayas** (`dashArray: '8 10'`);
//  * el globo de cada parada con el nombre y el importe (`priceLabel`);
//  * la leyenda de tres renglones de `routes/page.tsx`.
//
// Lo que no se copia es Leaflet: un `CustomPainter` dibuja todo eso sin una sola
// biblioteca de mapas. La proyeccion es la misma que usan las teselas —Mercator
// web—, que es lo que permite que el fondo y los puntos caigan en el mismo
// sitio.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../diseno/colores.dart';
import '../../pedidos/datos/formato.dart';
import '../datos/geo.dart';
import '../datos/mapa_en_vivo.dart';
import '../datos/recorrido.dart';

/// El lado de una tesela de OSM, en pixeles. Es el numero de siempre.
const ladoDeTesela = 256.0;

/// La vuelta al ecuador en km. De aqui sale la barra de escala.
const vueltaAlEcuadorKm = 40075.016686;

/// Mercator web, eje X: la longitud en `0..1` (`0` = 180° O, `1` = 180° E).
double aLoAncho(double lng) => (lng + 180) / 360;

/// Mercator web, eje Y: la latitud en `0..1`, **creciendo hacia el sur**, que es
/// justo como crecen las coordenadas de pantalla. El norte queda arriba solo.
double aLoAlto(double lat) {
  final seno = math.sin(lat * math.pi / 180);
  return 0.5 - math.log((1 + seno) / (1 - seno)) / (4 * math.pi);
}

/// Con un solo punto no hay nada que encuadrar, asi que se elige una vista de
/// barrio. Antes esto se quedaba «sin escala» y el mapa salia vacio alrededor de
/// la unica parada, sin fondo de calles posible.
const zoomDeUnSoloPunto = 15;

/// CADA CUANTOS PIXELES DE RECORRIDO SE PINTA UNA FLECHA DE SENTIDO.
///
/// 58 px salen de mirarlo: mas juntas se convierten en una linea con textura y
/// dejan de leerse como flechas; mas separadas, un tramo corto entre dos
/// paradas del centro se queda sin ninguna y es justo el sitio donde hace falta,
/// porque ahi la linea se dobla.
const _cadaCuantoUnaFlecha = 58.0;

/// CUANTO ACERCA UNA MUESCA DE LA RUEDA DEL RATON.
///
/// Menos que el boton (que dobla): la rueda se mueve varias muescas de una
/// pasada y con el doble por muesca se pasa de largo en un gesto.
const _pasoDeLaRueda = 1.35;

// Los colores del mapa viven en la paleta (`ColoresDelMapa`), no aquí.

/// EL ALTO DEL MAPA, calculado y **acotado por arriba y por abajo**.
///
/// Jose, 17/09/2026, mirando el original: «me corta parte de abajo, esto hasta
/// del mapa, no solo de la última card, no puedo ver el final».
///
/// Ese fallo tiene una causa de libro y hay que no repetirla: **dentro de algo
/// que se desplaza, un hijo sin alto propio se come la pantalla**. Por eso el
/// mapa NUNCA pide «lo que sobre» —ni `Expanded`, ni `double.infinity`, ni un
/// `AspectRatio` suelto—: pide un numero, y ese numero tiene techo.
///
///  * el **suelo** (190) es lo que hace falta para que se distingan cuatro
///    paradas y su recorrido; por debajo el mapa no cuenta nada y solo estorba;
///  * el **techo** (320) es lo que evita que en una pantalla ancha el mapa
///    empuje la carga, las acciones y las paradas por debajo del borde. Sin
///    techo, a 1400 px de ancho el mapa mediria 875 px de alto el solo.
double altoDelMapa(double ancho) => (ancho * 10 / 16).clamp(190.0, 320.0);

/// Una parada ya colocada dentro del recuadro.
class PuntoDelCroquis {
  const PuntoDelCroquis(this.parada, this.donde);

  final ParadaDelRecorrido parada;
  final Offset donde;
}

/// DONDE CAE CADA COSA, y **que teselas tapan el fondo**.
///
/// Es Dart y `dart:ui` y nada mas: se prueba sin montar ningun widget, que es lo
/// unico que hace comprobable un dibujo.
class Trazado {
  const Trazado({
    required this.paradas,
    required this.centroAncho,
    required this.centroAlto,
    required this.escala,
    required this.tamano,
    required this.latMedia,
    this.origen,
  });

  static const vacio = Trazado(
    paradas: [],
    centroAncho: 0,
    centroAlto: 0,
    escala: 0,
    tamano: Size.zero,
    latMedia: 0,
  );

  /// El almacen de salida, si la ruta lo tiene.
  final Offset? origen;

  /// Las paradas dibujables, **en orden de visita**.
  final List<PuntoDelCroquis> paradas;

  /// El centro de la vista, en coordenadas de mundo `0..1`.
  final double centroAncho;
  final double centroAlto;

  /// Pixeles por unidad de mundo. El mundo entero mide [escala] pixeles de
  /// ancho, que es exactamente lo que significa un nivel de zoom de teselas.
  final double escala;

  final Size tamano;
  final double latMedia;

  bool get estaVacio => origen == null && paradas.isEmpty;

  /// La ida: almacen → parada 1 → parada 2 → … Sin cerrar el circuito, igual
  /// que `tramos()` en `geo.dart`.
  List<Offset> get ida => [?origen, for (final p in paradas) p.donde];

  /// Donde cae un punto cualquiera. Lo usa la linea por carretera, que trae
  /// cientos de puntos que no son paradas.
  Offset de(Punto p) => Offset(
    tamano.width / 2 + (aLoAncho(p.lng) - centroAncho) * escala,
    tamano.height / 2 + (aLoAlto(p.lat) - centroAlto) * escala,
  );

  /// Cuantos km mide un pixel, a la latitud de esta ruta. `0` cuando no hay nada
  /// dibujado.
  double get kmPorPixel => escala <= 0
      ? 0
      : vueltaAlEcuadorKm * math.cos(latMedia * math.pi / 180) / escala;

  /// EL NIVEL DE TESELA QUE ENCAJA. Se coge el de **debajo** (`floor`) para que
  /// una tesela nunca se dibuje mas pequena de lo que se hizo: ampliarla un poco
  /// se ve borroso, encogerla mucho se ve sucio y se leen peor las calles.
  int get zoom => escala <= 0
      ? zoomDeUnSoloPunto
      : (math.log(escala / ladoDeTesela) / math.ln2).floor().clamp(0, 19);

  /// Que teselas hacen falta para tapar el recuadro. Salen dos o tres por lado,
  /// nunca un mosaico: el zoom se elige justo para eso.
  List<({int z, int x, int y})> teselasQueHacenFalta() {
    if (escala <= 0 || tamano.isEmpty) return const [];
    final z = zoom;
    final cuantas = 1 << z;

    int desde(double centro, double mitad) =>
        ((centro - mitad / escala) * cuantas).floor();
    int hasta(double centro, double mitad) =>
        ((centro + mitad / escala) * cuantas).floor();

    final salida = <({int z, int x, int y})>[];
    for (
      var x = desde(centroAncho, tamano.width / 2);
      x <= hasta(centroAncho, tamano.width / 2);
      x++
    ) {
      for (
        var y = desde(centroAlto, tamano.height / 2);
        y <= hasta(centroAlto, tamano.height / 2);
        y++
      ) {
        if (x < 0 || y < 0 || x >= cuantas || y >= cuantas) continue;
        salida.add((z: z, x: x, y: y));
      }
    }
    return salida;
  }

  /// El hueco que le toca a una tesela dentro del recuadro.
  Rect recuadroDe(int z, int x, int y) {
    final cuantas = 1 << z;
    final lado = escala / cuantas;
    return Rect.fromLTWH(
      tamano.width / 2 + (x / cuantas - centroAncho) * escala,
      tamano.height / 2 + (y / cuantas - centroAlto) * escala,
      lado,
      lado,
    );
  }
}

/// Coloca [recorrido] dentro de una caja de [tamano].
///
/// **Mercator web, la misma proyeccion que las teselas.** Antes era una
/// proyeccion propia con la longitud encogida por `cos(latitud)`, que dibujaba
/// bien pero no cuadraba con ningun mapa del mundo: con Mercator, el fondo de
/// calles y los pines caen en el mismo sitio, y eso es lo unico que permite
/// tener las dos capas a la vez.
///
/// La escala es la MISMA en los dos ejes, y eso es a proposito: estirar cada eje
/// por su cuenta llenaria mejor el recuadro y **mentiria sobre las distancias**,
/// que es lo unico que este dibujo tiene que contar bien.
/// [acercamiento] multiplica la escala del encuadre: `1` es «que quepa todo»,
/// que es como nace el mapa. Los botones de `+` y `−` lo mueven.
///
/// **Botones y no pellizco**, y es una decisión, no una carencia: un
/// reconocedor de pellizco o de arrastre dentro de una lista le gana el gesto
/// al desplazamiento, y entonces no se puede bajar la pantalla con el dedo
/// encima del mapa. Con botones se puede acercar Y se puede seguir bajando.
Trazado trazar(
  Recorrido recorrido,
  Size tamano, {
  double margen = 26,
  double acercamiento = 1,
  Offset arrastre = Offset.zero,
}) {
  final puntos = <Punto>[
    ?recorrido.origen,
    for (final p in recorrido.dibujables) p.punto!,
  ];
  if (puntos.isEmpty || tamano.isEmpty) return Trazado.vacio;

  final anchos = [for (final p in puntos) aLoAncho(p.lng)];
  final altos = [for (final p in puntos) aLoAlto(p.lat)];
  final minAncho = anchos.reduce(math.min);
  final maxAncho = anchos.reduce(math.max);
  final minAlto = altos.reduce(math.min);
  final maxAlto = altos.reduce(math.max);

  final util = Size(
    math.max(1, tamano.width - 2 * margen),
    math.max(1, tamano.height - 2 * margen),
  );
  final anchoMundo = maxAncho - minAncho;
  final altoMundo = maxAlto - minAlto;

  // Con un solo punto —o con todas las paradas en el mismo sitio— no hay nada
  // que encuadrar: se centra y se ensena el barrio. Lo que NO se hace es dividir
  // entre cero y pintar `NaN`, que es como se ve un dibujo roto.
  final escala = (anchoMundo == 0 && altoMundo == 0)
      ? ladoDeTesela * (1 << zoomDeUnSoloPunto)
      : math.min(
          anchoMundo == 0 ? double.infinity : util.width / anchoMundo,
          altoMundo == 0 ? double.infinity : util.height / altoMundo,
        );

  final encuadre = Trazado(
    paradas: const [],
    // El arrastre se resta del centro: mover el mapa a la derecha es mirar un
    // trozo que está más a la izquierda.
    centroAncho:
        (minAncho + maxAncho) / 2 - arrastre.dx / (escala * acercamiento),
    centroAlto: (minAlto + maxAlto) / 2 - arrastre.dy / (escala * acercamiento),
    escala: escala * acercamiento,
    tamano: tamano,
    latMedia: puntos.map((p) => p.lat).reduce((a, b) => a + b) / puntos.length,
  );

  return Trazado(
    origen: recorrido.origen == null ? null : encuadre.de(recorrido.origen!),
    paradas: [
      for (final p in recorrido.dibujables)
        PuntoDelCroquis(p, encuadre.de(p.punto!)),
    ],
    centroAncho: encuadre.centroAncho,
    centroAlto: encuadre.centroAlto,
    // **`encuadre.escala`, NO `escala`.** Aquí estaba el fallo del zoom que
    // Jose vio tres veces: `escala` es la del encuadre que cabe, sin acercar.
    // Las paradas sí se movían —salen de `encuadre.de(...)`, que ya lleva el
    // acercamiento— pero la escala del trazado devuelto no, y de ella salen
    // **las teselas que se piden, la barra de kilómetros y dónde cae el
    // globo**. Resultado: los círculos se separaban y el mapa de debajo se
    // quedaba clavado, con la barra diciendo los mismos 10 km.
    //
    // O sea: el botón no estaba roto ni el repintado tampoco. Lo que estaba
    // roto era que el zoom llegaba a la mitad del dibujo.
    escala: encuadre.escala,
    tamano: tamano,
    latMedia: encuadre.latMedia,
  );
}

/// CUAL DE LAS DOS CAPAS SE ESTA VIENDO. El mapa lo reporta hacia arriba para
/// que la pantalla pueda **decirlo**, en vez de dejar que se adivine.
typedef QueSeVe = ({bool conCalles, bool recorridoPorCarretera});

/// EL MAPA.
///
/// Guarda tres cosas: que parada tiene el globo abierto, las teselas que han
/// llegado, y el recorrido por carretera si llego. Las dos ultimas son mejoras:
/// el dibujo esta completo sin ellas.
class CroquisDeRuta extends StatefulWidget {
  const CroquisDeRuta({
    required this.recorrido,
    required this.fondo,
    required this.porCalles,
    this.onQueSeVe,
    this.aPantallaCompleta = false,
    super.key,
  });

  final Recorrido recorrido;

  /// De donde salen las teselas. Inyectado: en las pruebas es [SinCalles] y **no
  /// sale ni una peticion**, que ademas es regla de la casa en este PC.
  final FondoDeCalles fondo;

  /// Quien sabe por donde van las calles. Inyectado, por lo mismo.
  final RecorridoPorCalles porCalles;

  /// Se avisa cuando cambia lo que se esta viendo, para que la pantalla lo diga.
  final void Function(QueSeVe)? onQueSeVe;

  /// A PANTALLA COMPLETA NO HAY LISTA DEBAJO, y eso cambia los gestos.
  ///
  /// Dentro del detalle de la ruta el mapa vive en medio de una lista que se
  /// desplaza, asi que **un dedo es de la lista** y el mapa solo atiende dos
  /// dedos: si no, arrastrar sobre el mapa deja al chofer sin poder llegar al
  /// final de la pantalla (pasó, 17/09/2026). Abierto a pantalla completa no hay
  /// nada debajo que pueda perder el gesto, asi que **un dedo mueve el mapa**,
  /// que es lo que hace cualquier mapa del mundo.
  final bool aPantallaCompleta;

  /// La clave con la que la prueba lo encuentra. Buscarlo por su tipo ataria la
  /// prueba a como esta hecho el dibujo.
  static const clave = ValueKey('croquis-de-la-ruta');

  @override
  State<CroquisDeRuta> createState() => _CroquisDeRutaState();
}

/// LO YA TRAIDO, GUARDADO FUERA DEL WIDGET.
///
/// Jose, 17/09/2026: «cada vez que me muevo por los tabs se hace el recálculo
/// de la ruta; ¿por qué razón, si eso ya tiene que estar fijo?».
///
/// Tenia toda la razon y el motivo era este: las teselas y el recorrido por
/// carretera vivian en el `State` del widget. Cambiar de pestana **destruye el
/// widget**, asi que al volver nacia uno nuevo con los dos vacios y lo pedia
/// todo otra vez. Con la conexion de Cuba eso son megas tirados cada vez que
/// alguien toca una pestana, y ademas se ve: el mapa parpadea del croquis a las
/// calles a cada vuelta.
///
/// Se guardan aqui, a nivel de modulo, para que sobrevivan a que el widget vaya
/// y venga. **No se vacian solos**: son una pantalla de rutas de un dia, no un
/// navegador. El recorrido va por id de ruta, que es lo que lo identifica;
/// las teselas por su `z/x/y`, que es lo mismo en todas las rutas.
final _teselasTraidas = <String, ui.Image>{};

/// CUANTAS TESELAS SE HAN GUARDADO YA, en total y desde que arrancó.
///
/// Existe porque el almacén de arriba es **de módulo**: el pintor viejo y el
/// nuevo sostienen el MISMO objeto, así que `viejo.teselas.length !=
/// teselas.length` compara un mapa consigo mismo y **siempre da falso**. El
/// resultado, visto en el teléfono el 21/09/2026 con el mapa de Cuba bajado y
/// el avión puesto: una sola tesela dibujada arriba a la izquierda y el resto
/// del recuadro en blanco, mientras el texto decía «Mapa de calles». Las
/// teselas llegaban; nadie volvía a pintar.
///
/// Un contador que sólo sube es lo que hace comparable un almacén compartido:
/// no dice cuáles hay, dice **que hay una más que antes**, que es justo lo que
/// `shouldRepaint` necesita saber.
///
/// Lo rompí yo el 17/09 al mover las teselas fuera del `State` para no volver a
/// pedirlas al cambiar de pestaña. La ganancia era real; el precio, que la
/// única señal de cambio que había dejó de cambiar.
int _selloDeLasTeselas = 0;
final _recorridosTraidos = <String, List<Punto>>{};
final _regresosTraidos = <String, List<Punto>>{};

/// Guarda una tesela Y SUBE EL SELLO. **Las dos cosas van juntas siempre**, y
/// por eso es una funcion y no dos lineas sueltas: la primera vez que escribi
/// esto la tesela se guardaba y el sello se quedaba donde estaba, asi que el
/// pintor nuevo y el viejo daban el mismo numero y Flutter se ahorraba el
/// repintado. En el telefono se veia una tesela pintada arriba a la izquierda y
/// el resto del recuadro en blanco.
void _guardarTeselaTraida(String clave, ui.Image imagen) {
  _teselasTraidas[clave] = imagen;
  _selloDeLasTeselas++;
}

/// Para las pruebas: dos casos seguidos no pueden compartir lo traido por el
/// anterior, o el segundo pasa sin pedir nada y no prueba lo que dice.
@visibleForTesting
void olvidarLoTraidoDelMapa() {
  _teselasTraidas.clear();
  _selloDeLasTeselas++;
  _recorridosTraidos.clear();
  _regresosTraidos.clear();
}

/// EL PELLIZCO DEL TELEFONO, y por que es una subclase y no un `GestureDetector`.
///
/// Jose, 21/09/2026, con la APK en la mano: «en el apk los gestos de alejar y
/// acercar en el mapa no estan funcionando tampoco» y «ni me puedo mover en el
/// mapa desde la apk estoy sellado ahi y no me puedo mover». Las dos cosas eran
/// verdad y las dos salian de aqui: el arrastre estaba filtrado a
/// `kind == mouse`, y el pellizco solo se atendia como `PointerScaleEvent`, que
/// es lo que manda un **trackpad**. Un telefono manda dos dedos, y a esos no los
/// miraba nadie. En el movil el mapa estaba sellado: ni acercar, ni mover.
///
/// **UN SOLO RECONOCEDOR PARA LAS DOS COSAS**, y por qué — 22/09/2026.
///
/// Aquí había dos: un `ScaleGestureRecognizer` recortado a dos dedos y un
/// `PanGestureRecognizer` que aceptaba a los 3 px. Los dos en el mismo
/// `RawGestureDetector`, o sea **en la misma subasta de gestos**. Y una subasta
/// tiene un solo ganador: el arrastre aceptaba en el primer fotograma del
/// primer dedo —para eso estaban los 3 px— y al aceptar **expulsaba al
/// pellizco**, que todavía estaba esperando a que llegara el segundo dedo.
///
/// Resultado, y es exactamente lo que Jose siguió viendo después de darlo por
/// arreglado: **mover con un dedo funcionaba y el zoom no llegaba nunca.** Ni un
/// error, ni nada que mirar: el segundo dedo aterrizaba sobre un gesto que ya
/// tenía dueño.
///
/// `ScaleGestureRecognizer` hace las dos cosas él solo —`scale` para el
/// acercamiento y `focalPointDelta` para el arrastre—, que es como lo resuelve
/// el `InteractiveViewer` de Flutter. Con uno solo no hay subasta que perder.
///
/// Lo único que hay que devolverle es **la rapidez en aceptar**, que era lo que
/// daban aquellos 3 px: sin ella el umbral de panorámica (`kPanSlop`, 36 px) es
/// el doble que el de la lista, la lista acepta antes y vuelve el fallo del
/// 17/09 al revés — el mapa sellado. Se le baja con `gestureSettings`, que es la
/// puerta que Flutter deja abierta para esto: `panSlop` sale de `touchSlop * 2`,
/// así que 1,5 px de `touchSlop` son los mismos 3 px de antes.
const _loQueEsUnArrastre = 1.5;

class _CroquisDeRutaState extends State<CroquisDeRuta> {
  String? _abierta;
  Map<String, ui.Image> get _teselas => _teselasTraidas;
  List<Punto>? get _porCarretera {
    final linea = _recorridosTraidos[_claveDelRecorrido];
    // Vacia = «pedido y todavia sin contestar». No es una linea de cero puntos.
    return (linea == null || linea.isEmpty) ? null : linea;
  }

  List<Punto>? get _regreso => _regresosTraidos[_claveDelRecorrido];

  /// CON QUE SE IDENTIFICA UN RECORRIDO YA TRAIDO.
  ///
  /// No el id de la ruta: **las paradas y el origen**. Si a una ruta se le
  /// quita una parada, el recorrido por carretera de antes ya no es el suyo y
  /// hay que volver a pedirlo; con el id como clave se habria quedado el viejo
  /// pintado encima de unas paradas que ya no son esas.
  String get _claveDelRecorrido {
    final origen = widget.recorrido.origen;
    return [
      origen == null ? '-' : '${origen.lat},${origen.lng}',
      for (final p in widget.recorrido.dibujables) p.id,
    ].join('|');
  }

  String? _laVistaQueSePidio;

  /// CUANTO SE HA ACERCADO. `1` es el encuadre que cabe entero, que es como
  /// nace y a donde vuelve el boton de encuadrar.
  double _acercamiento = 1;

  /// CUÁNTO SE HA ARRASTRADO EL MAPA, en píxeles de pantalla.
  ///
  /// Jose, 17/09/2026: «tengo mapa y no lo puedo utilizar; esto es un
  /// OpenStreetMap funcional». Tenía razón: acercar sin poder moverse deja la
  /// mitad de la ruta fuera del recuadro y no hay forma de ir a verla.
  var _arrastre = Offset.zero;

  /// Donde estaba el mapa cuando se posaron los dos dedos. El pellizco se
  /// calcula SIEMPRE contra esto y nunca contra el fotograma anterior: acumular
  /// incrementos redondea y el mapa se va yendo solo.
  double _acercamientoAlEmpezar = 1;
  Offset _arrastreAlEmpezar = Offset.zero;
  Offset _focoAlEmpezar = Offset.zero;

  /// LOS TOPES.
  ///
  /// `1` es el encuadre que cabe. Hacia arriba, 16 son cuatro pasos y llegan a
  /// leer el nombre de una calle.
  ///
  /// **Hacia abajo se aleja hasta 1/16, y esto es una corrección.** Lo tenía
  /// topado en el encuadre con el razonamiento de que «alejar más sólo deja
  /// papel vacío alrededor», y estaba mal: Jose, 17/09/2026, enseñando el
  /// original al lado —«el original me deja alejar más, ¿por qué éste no me
  /// deja alejar?»—. Alejar no es papel vacío, es **dónde cae esta ruta**: ver
  /// que la parada está en Cotorro y no en Marianao es lo que le dice al que
  /// planifica si el camión va a cruzar La Habana entera.
  static const acercamientoMinimo = 1 / 16;
  static const acercamientoMaximo = 16.0;

  /// Lo que se considera «he tocado esa parada». Generoso a proposito: el
  /// circulo mide 10 px de radio y un dedo no es un raton.
  static const _alcanceDelDedo = 22.0;

  @override
  void didUpdateWidget(CroquisDeRuta viejo) {
    super.didUpdateWidget(viejo);
    if (!identical(viejo.recorrido, widget.recorrido)) {
      // Otra ruta: se vuelve a mirar el almacen, que lleva lo suyo por id. No
      // hay nada que borrar — lo de la ruta anterior sigue valiendo para la
      // ruta anterior, y es justo lo que evita pedirlo otra vez al volver.
      _laVistaQueSePidio = null;
    }
    if (_abierta != null &&
        !widget.recorrido.paradas.any((p) => p.id == _abierta)) {
      _abierta = null;
    }
  }

  /// Las dos mejoras. **Nunca bloquean el dibujo**: se piden despues de pintar
  /// y, si llegan, repintan.
  void _pedirLasMejoras(Trazado trazado) {
    if (!mounted) return;
    // LO QUE YA ESTABA GUARDADO TAMBIEN CUENTA, y esto es un arreglo de un
    // fallo que metí yo esta misma tarde: al mover las teselas a un almacén de
    // módulo para no volver a pedirlas al cambiar de pestaña, `_avisar` dejó de
    // dispararse cuando ya estaban —sólo corría al LLEGAR una—. Resultado: el
    // mapa pintaba las calles y debajo ponía «el mapa de calles no cargó».
    // Un diagnóstico falso es peor que no decir nada.
    _avisar(trazado);
    final vista =
        '${trazado.zoom}/${trazado.centroAncho}/${trazado.centroAlto}';
    if (_laVistaQueSePidio != vista) {
      _laVistaQueSePidio = vista;
      for (final t in trazado.teselasQueHacenFalta()) {
        final clave = '${t.z}/${t.x}/${t.y}';
        if (_teselas.containsKey(clave)) continue;
        widget.fondo.tesela(t.z, t.x, t.y).then((imagen) {
          if (!mounted || imagen == null) return;
          setState(() => _guardarTeselaTraida(clave, imagen));
          _avisar();
        });
      }
    }

    // **Ya traido = no se vuelve a pedir**, aunque el widget sea otro.
    if (!_recorridosTraidos.containsKey(_claveDelRecorrido)) {
      // SOLO LA IDA: almacen → parada 1 → … → ultima parada.
      //
      // El regreso se pide aparte, y no es capricho. Jose, 17/09/2026: «sigue
      // sin entenderse cuándo se va y cuándo se vira». Tenia razon: se pedia el
      // circuito CERRADO de una vez, asi que OSRM devolvia una sola linea con
      // la ida y la vuelta pegadas y no habia forma de pintarlas distinto —
      // salia todo del mismo color y por las mismas calles. La leyenda
      // prometia un «regreso al deposito» que con calles no se dibujaba nunca.
      final porDonde = <Punto>[
        ?widget.recorrido.origen,
        for (final p in widget.recorrido.dibujables) p.punto!,
      ];
      // Se apunta ANTES de que conteste para que dos fotogramas seguidos no
      // pidan lo mismo dos veces. Si no llega, se borra la marca y se podra
      // reintentar: apuntar un fallo como si fuera un exito dejaria la ruta sin
      // calles para siempre.
      final clave = _claveDelRecorrido;
      _recorridosTraidos[clave] = const [];
      widget.porCalles.entre(porDonde).then((linea) {
        if (linea == null || linea.isEmpty) {
          _recorridosTraidos.remove(clave);
          return;
        }
        _recorridosTraidos[clave] = linea;
        if (!mounted) return;
        setState(() {});
        _avisar();
      });

      // Y EL REGRESO, en su propia peticion: ultima parada → almacen. Dos
      // peticiones en vez de una, y a cambio se ve cual es cual. Se guarda
      // aparte para poder pintarlo a rayas y en ambar, como sin calles.
      final origen = widget.recorrido.origen;
      final ultima = widget.recorrido.dibujables.isEmpty
          ? null
          : widget.recorrido.dibujables.last.punto;
      if (origen != null && ultima != null) {
        widget.porCalles.entre([ultima, origen]).then((linea) {
          if (linea == null || linea.isEmpty) return;
          _regresosTraidos[clave] = linea;
          if (!mounted) return;
          setState(() {});
        });
      }
    }
  }

  /// LO QUE SE ESTÁ VIENDO **EN ESTA VISTA**, no lo que haya en memoria.
  ///
  /// `_teselas.isNotEmpty` era mentira desde que el almacén pasó a ser de
  /// módulo: bastaba una tesela guardada de otra ruta, de otro zoom o de otro
  /// rato con señal para que la pantalla dijera «Mapa de calles» encima de un
  /// recuadro en blanco. Un diagnóstico falso es peor que no decir nada — la
  /// regla 4 de la casa.
  ///
  /// Ahora se pregunta por las teselas que hacen falta **aquí y ahora**, y basta
  /// una: con el resto llegando, el mapa ya no es un croquis.
  void _avisar([Trazado? trazado]) {
    final hacenFalta = trazado?.teselasQueHacenFalta() ?? const [];
    final conCalles = hacenFalta.isEmpty
        ? _teselas.isNotEmpty
        : hacenFalta.any((t) => _teselas.containsKey('${t.z}/${t.x}/${t.y}'));
    widget.onQueSeVe?.call((
      conCalles: conCalles,
      recorridoPorCarretera: _porCarretera != null,
    ));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // A pantalla completa el mapa se come el alto que haya; dentro del detalle
      // mide lo que diga `altoDelMapa`. Un `Expanded` dentro de una lista que se
      // desplaza revienta, y el detalle es justo eso, asi que va con condicion.
      _conElAltoQueToca(
        DecoratedBox(
          key: CroquisDeRuta.clave,
          decoration: BoxDecoration(
            color: Colores.blanco,
            border: Border.all(color: Colores.linea),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LayoutBuilder(
              builder: (context, cajon) {
                final tamano = Size(
                  cajon.maxWidth,
                  widget.aPantallaCompleta && cajon.maxHeight.isFinite
                      ? cajon.maxHeight
                      : altoDelMapa(cajon.maxWidth),
                );
                return SizedBox.fromSize(
                  size: tamano,
                  child: Builder(
                    builder: (context) {
                      final trazado = trazar(
                        widget.recorrido,
                        tamano,
                        acercamiento: _acercamiento,
                        arrastre: _arrastre,
                      );
                      if (!trazado.estaVacio) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _pedirLasMejoras(trazado),
                        );
                      }
                      // SOLO `onTapUp`. **Ni arrastrar ni pellizcar**, y no por
                      // falta de ganas: un reconocedor de arrastre aqui dentro le
                      // gana el gesto a la lista que hay debajo, y entonces
                      // arrastrar sobre el mapa deja de desplazar el detalle —que
                      // es justo como el chofer se queda sin poder llegar al final
                      // de la pantalla. Un toque no compite con un arrastre, asi
                      // que la lista sigue mandando.
                      return Listener(
                        // LA RUEDA DEL RATON ACERCA Y ALEJA.
                        //
                        // Jose, 17/09/2026: «con la rueda del mouse no puedo ni
                        // alejar ni acercar tampoco». En un escritorio es el
                        // gesto natural y los botones no lo sustituyen.
                        //
                        // Va en un `Listener` con `onPointerSignal` y **no** en
                        // un reconocedor de gestos: la rueda es una senal de
                        // puntero, no un arrastre, asi que esto no le quita el
                        // gesto a la lista que hay debajo. Un dedo sigue
                        // desplazando la pantalla como antes — lo vigila la
                        // prueba «arrastrar SOBRE EL MAPA sigue desplazando la
                        // lista», que sigue verde.
                        //
                        // `scrollDelta.dy` negativo es rueda hacia arriba, que en
                        // todos los mapas es acercar.
                        // El arrastre YA NO VIVE AQUI: ver `_ArrastreDelMapa`,
                        // el reconocedor que hay debajo. Aqui se quedan la rueda
                        // y el pellizco del trackpad, que son señales de puntero
                        // y no compiten con nadie.
                        onPointerSignal: (senal) {
                          // EL PELLIZCO DEL TRACKPAD, que NO es una rueda.
                          //
                          // Jose, 17/09/2026: «con el touchpad no hace nada, no
                          // se acerca o se aleja con los gestos». Y es que el
                          // navegador manda el pellizco de dos dedos como un
                          // evento de ESCALA propio (`PointerScaleEvent`), no
                          // como un desplazamiento — yo sólo miraba la rueda, así
                          // que el gesto más natural del portátil no hacía nada.
                          //
                          // Aquí no hace falta Ctrl: un pellizco no es un
                          // desplazamiento, así que no le quita nada a la lista.
                          if (senal is PointerScaleEvent) {
                            final nuevo = (_acercamiento * senal.scale).clamp(
                              acercamientoMinimo,
                              acercamientoMaximo,
                            );
                            if (nuevo != _acercamiento) {
                              setState(() => _acercamiento = nuevo);
                            }
                            return;
                          }
                          if (senal is! PointerScrollEvent) return;
                          // **SOLO CON CTRL**, como los mapas embebidos de toda
                          // la vida. Jose, 17/09/2026: «no sale la parte de abajo
                          // de la card, esos botones que pusiste allá abajo».
                          //
                          // Era culpa de esto: al hacer que la rueda acercara, la
                          // rueda dejo de desplazar la pagina, y el mapa mide 320
                          // px de alto en medio del detalle — o sea que con el
                          // raton encima no habia forma de llegar a los cuatro
                          // botones que hay debajo. Un mapa que secuestra el
                          // desplazamiento deja media pantalla inalcanzable.
                          //
                          // Con Ctrl acerca; sin Ctrl el gesto sigue su camino y
                          // la pagina baja. Los botones de `+` y `−` siguen ahi
                          // para quien no sepa lo del Ctrl, que son casi todos.
                          if (!HardwareKeyboard.instance.isControlPressed &&
                              !HardwareKeyboard.instance.isMetaPressed) {
                            return;
                          }
                          final hacia = senal.scrollDelta.dy < 0
                              ? _acercamiento * _pasoDeLaRueda
                              : _acercamiento / _pasoDeLaRueda;
                          final nuevo = hacia.clamp(
                            acercamientoMinimo,
                            acercamientoMaximo,
                          );
                          if (nuevo != _acercamiento) {
                            setState(() => _acercamiento = nuevo);
                          }
                        },
                        child: RawGestureDetector(
                          gestures: <Type, GestureRecognizerFactory>{
                            ScaleGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  ScaleGestureRecognizer
                                >(ScaleGestureRecognizer.new, (reconocedor) {
                                  reconocedor
                                    // La rapidez en aceptar, que es lo que antes
                                    // daba el reconocedor de arrastre. Ver
                                    // `_loQueEsUnArrastre`.
                                    ..gestureSettings =
                                        const DeviceGestureSettings(
                                          touchSlop: _loQueEsUnArrastre,
                                        )
                                    ..onStart = (gesto) {
                                      _acercamientoAlEmpezar = _acercamiento;
                                      _arrastreAlEmpezar = _arrastre;
                                      _focoAlEmpezar = gesto.localFocalPoint;
                                    }
                                    ..onUpdate = (gesto) =>
                                        _pellizcar(gesto, tamano);
                                }),
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (toque) =>
                                _tocar(trazado, toque.localPosition),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _PintorDelCroquis(
                                      recorrido: widget.recorrido,
                                      teselas: _teselas,
                                      sello: _selloDeLasTeselas,
                                      porCarretera: _porCarretera,
                                      regresoPorCarretera: _regreso,
                                      textos: DefaultTextStyle.of(context)
                                          .style,
                                      acercamiento: _acercamiento,
                                      arrastre: _arrastre,
                                    ),
                                  ),
                                ),
                                ..._globo(trazado, tamano),
                                if (!widget.aPantallaCompleta)
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: _Boton(
                                      icono: Icons.open_in_full,
                                      rotulo: 'Ver el mapa a pantalla completa',
                                      alPulsar: () => abrirElMapaEnGrande(
                                        context,
                                        recorrido: widget.recorrido,
                                        fondo: widget.fondo,
                                        porCalles: widget.porCalles,
                                      ),
                                    ),
                                  ),
                                _BotonesDeZoom(
                                  acercamiento: _acercamiento,
                                  alCambiar: (cuanto) => setState(() {
                                    // Volver al encuadre devuelve TAMBIÉN el
                                    // arrastre: si no, «ver la ruta entera» deja el
                                    // mapa a la escala buena y mirando a otro sitio.
                                    if (cuanto == 1) _arrastre = Offset.zero;
                                    _acercamiento = cuanto;
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const _Leyenda(),
    ],
  );

  Widget _conElAltoQueToca(Widget caja) =>
      widget.aPantallaCompleta ? Expanded(child: caja) : caja;

  /// EL PELLIZCO: acerca **hacia donde estan los dedos**, no hacia el centro.
  ///
  /// Un punto del mapa cae en `centro + mundo·escala·acercamiento + arrastre`.
  /// Si al multiplicar el acercamiento por `k` no se toca el arrastre, lo que
  /// hay bajo los dedos se escapa hacia una esquina y es imposible mirar una
  /// manzana concreta: hay que acercar y correr el mapa a la vez. De ahi sale
  /// esta cuenta, que ademas se lleva gratis el **mover con dos dedos**, porque
  /// usa donde estan los dedos AHORA contra donde se posaron.
  /// EL GESTO DEL MAPA, que son dos cosas con un solo reconocedor.
  ///
  /// Con UN dedo `scale` vale 1 y lo único que cambia es el foco: sale
  /// arrastre puro. Con DOS, `scale` crece o mengua y el foco se mueve: sale
  /// acercamiento **alrededor del punto que se está pellizcando**, que es lo que
  /// hace que el mapa no se escape de debajo de los dedos.
  ///
  /// La misma cuenta sirve para los dos casos y por eso no hay un `if` que los
  /// separe: separarlos fue lo que dejó el zoom sin llegar nunca (ver
  /// `_loQueEsUnArrastre`).
  void _pellizcar(ScaleUpdateDetails gesto, Size caja) {
    final nuevo = (_acercamientoAlEmpezar * gesto.scale).clamp(
      acercamientoMinimo,
      acercamientoMaximo,
    );
    final k = nuevo / _acercamientoAlEmpezar;
    final centro = Offset(caja.width / 2, caja.height / 2);
    final arrastre =
        gesto.localFocalPoint -
        centro -
        (_focoAlEmpezar - centro - _arrastreAlEmpezar) * k;
    if (nuevo == _acercamiento && arrastre == _arrastre) return;
    setState(() {
      _acercamiento = nuevo;
      _arrastre = arrastre;
    });
  }

  void _tocar(Trazado trazado, Offset donde) {
    PuntoDelCroquis? masCerca;
    var minima = double.infinity;
    for (final punto in trazado.paradas) {
      final distancia = (punto.donde - donde).distance;
      if (distancia < minima) {
        minima = distancia;
        masCerca = punto;
      }
    }
    setState(() {
      // Tocar fuera de todo cierra el globo, que es lo que hace un mapa.
      if (masCerca == null || minima > _alcanceDelDedo) {
        _abierta = null;
      } else {
        _abierta = _abierta == masCerca.parada.id ? null : masCerca.parada.id;
      }
    });
  }

  List<Widget> _globo(Trazado trazado, Size tamano) {
    if (_abierta == null) return const [];
    final punto = trazado.paradas
        .where((p) => p.parada.id == _abierta)
        .firstOrNull;
    if (punto == null) return const [];

    // Se ancla por arriba y por la izquierda, y se sujeta dentro del recuadro:
    // una parada en el borde derecho sacaria el globo fuera del dibujo.
    const ancho = 170.0;
    final izquierda = (punto.donde.dx - ancho / 2)
        .clamp(4.0, math.max(4.0, tamano.width - ancho - 4))
        .toDouble();
    final arriba = punto.donde.dy + 16 > tamano.height - 52
        ? punto.donde.dy - 52
        : punto.donde.dy + 16;

    return [
      Positioned(
        left: izquierda,
        top: arriba.clamp(4.0, math.max(4.0, tamano.height - 48)).toDouble(),
        width: ancho,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colores.tinta,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${punto.parada.numero}. ${punto.parada.etiqueta}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colores.blanco,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // EL IMPORTE, EN CLARO. Iba en el verde de la paleta, que está
                // elegido para leerse sobre PAPEL: sobre el negro del globo se
                // apaga y «sin cotizar» desaparecía del todo. Jose, 17/09/2026:
                // «los tooltips no se ven casi, qué mierda es esto en negro».
                Text(
                  usd(punto.parada.importe),
                  style: const TextStyle(
                    color: ColoresDelMapa.importeEnGlobo,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

/// LA LEYENDA, que en el patron vive fuera del mapa (`routes/page.tsx`, los tres
/// renglones `legendStart`, `legendStops` y `legendReturn`).
///
/// Sin ella, tres colores y unas rayas son una decoracion. Con ella, el naranja
/// a rayas dice «esto es el regreso al deposito», que es lo que explica por que
/// los km de la cabecera ponen «incl. regreso».
/// LA LEYENDA. **Los mismos símbolos que dibuja el mapa**, no barritas de
/// colores.
///
/// Jose, 17/09/2026, dos veces: «mejora los iconos de las leyendas, que están
/// macabros» y «los datos de la leyenda no se ven nada bien».
///
/// Tenía razón y el porqué era medible: eran cuatro rectángulos de colores con
/// el texto en gris a 11 px. Dos cosas mal a la vez. La primera, que un
/// rectángulo azul no se parece en nada al círculo numerado que hay dibujado
/// dos dedos más arriba, así que la leyenda no explicaba el mapa: había que
/// adivinar la correspondencia. La segunda, que gris sobre blanco a 11 px es el
/// texto más flojo de toda la aplicación, y encima puesto debajo de un mapa a
/// todo color, que es donde más contraste hace falta.
///
/// Ahora cada renglón **pinta su símbolo de verdad** —el cuadro del almacén, el
/// círculo numerado de la parada, el círculo verde de lo entregado y la raya
/// del regreso—, con el texto en tinta y a 12. Si alguien cambia cómo se dibuja
/// una marca en el mapa, tiene que cambiarla también aquí; por eso los colores
/// salen de las mismas constantes y no de copias.
class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 8,
    children: const [
      _Renglon(simbolo: _Simbolo.almacen, texto: 'Punto de partida'),
      _Renglon(simbolo: _Simbolo.parada, texto: 'Paradas'),
      _Renglon(simbolo: _Simbolo.regreso, texto: 'Regreso al depósito'),
    ],
  );
}

/// Los cuatro símbolos que se dibujan en el mapa.
enum _Simbolo { almacen, parada, entregada, regreso }

class _Renglon extends StatelessWidget {
  const _Renglon({required this.simbolo, required this.texto});

  final _Simbolo simbolo;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 20,
        height: 20,
        child: CustomPaint(painter: _PintorDelSimbolo(simbolo)),
      ),
      const SizedBox(width: 6),
      // `Flexible` y no `Text` a secas: en un telefono estrecho el renglon mas
      // largo de la leyenda no cabe, y un `Row` que no cabe pinta la franja de
      // rayas amarillas encima del mapa.
      Flexible(
        child: Text(
          texto,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.1,
            color: Colores.tinta,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

/// La estrella blanca del alfiler de salida, igual que el patrón.
void _dibujarEstrella(Canvas lienzo, Offset centro, double radio, Color color) {
  final camino = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? radio : radio * 0.44;
    final angulo = -math.pi / 2 + i * math.pi / 5;
    final punto = Offset(
      centro.dx + r * math.cos(angulo),
      centro.dy + r * math.sin(angulo),
    );
    i == 0
        ? camino.moveTo(punto.dx, punto.dy)
        : camino.lineTo(punto.dx, punto.dy);
  }
  camino.close();
  lienzo.drawPath(camino, Paint()..color = color);
}

/// Dibuja el simbolo **igual que el mapa**, a menor tamano.
///
/// Es a proposito que esto repita la forma de `_marca` y `_almacen` en vez de
/// llamarlas: aquellas pintan sobre el lienzo del mapa con sus coordenadas y su
/// letrero debajo. Lo que NO se repite son los colores ni el grosor de la raya,
/// que salen de las mismas constantes.
class _PintorDelSimbolo extends CustomPainter {
  const _PintorDelSimbolo(this.cual);

  final _Simbolo cual;

  @override
  void paint(Canvas lienzo, Size tamano) {
    final centro = Offset(tamano.width / 2, tamano.height / 2);

    switch (cual) {
      // El almacen es un cuadro redondeado con reborde blanco, como en el mapa.
      case _Simbolo.almacen:
        const radio = 6.0;
        final arriba = Offset(centro.dx, centro.dy - 2.5);
        final punta = centro.dy + 8;
        Path gota(double r, Offset c, double p) => Path()
          ..addOval(Rect.fromCircle(center: c, radius: r))
          ..moveTo(c.dx - r * 0.62, c.dy + r * 0.78)
          ..lineTo(c.dx, p)
          ..lineTo(c.dx + r * 0.62, c.dy + r * 0.78)
          ..close();
        lienzo
          ..drawPath(
            gota(radio + 1.2, arriba, punta + 1.2),
            Paint()..color = Colores.blanco,
          )
          ..drawPath(
            gota(radio, arriba, punta),
            Paint()..color = ColoresDelMapa.salida,
          );
        _dibujarEstrella(lienzo, arriba, 3.1, Colores.blanco);

      // La parada es el circulo numerado. Lleva el `1` dentro porque lo que se
      // esta explicando es justamente que van numeradas en orden de visita.
      case _Simbolo.parada:
        _circulo(lienzo, centro, ColoresDelMapa.recorrido);
        _numero(lienzo, centro, '1');

      // Lo entregado es el mismo circulo en verde, con su palomita: el color
      // solo no basta para quien no distingue el verde del azul.
      case _Simbolo.entregada:
        _circulo(lienzo, centro, ColoresDelMapa.salida);
        _palomita(lienzo, centro);

      // El regreso es la raya discontinua, con el mismo paso que el mapa.
      case _Simbolo.regreso:
        final pincel = Paint()
          ..color = ColoresDelMapa.regreso
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        for (var x = 1.0; x < tamano.width - 1; x += 5) {
          lienzo.drawLine(
            Offset(x, centro.dy),
            Offset(math.min(x + 3, tamano.width - 1), centro.dy),
            pincel,
          );
        }
    }
  }

  void _circulo(Canvas lienzo, Offset centro, Color color) => lienzo
    ..drawCircle(centro, 9, Paint()..color = Colores.blanco)
    ..drawCircle(centro, 7.5, Paint()..color = color);

  void _numero(Canvas lienzo, Offset centro, String texto) {
    final pintor = TextPainter(
      text: TextSpan(
        text: texto,
        style: const TextStyle(
          color: Colores.blanco,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pintor.paint(lienzo, centro - Offset(pintor.width / 2, pintor.height / 2));
  }

  void _palomita(Canvas lienzo, Offset centro) {
    final pincel = Paint()
      ..color = Colores.blanco
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    lienzo.drawPath(
      Path()
        ..moveTo(centro.dx - 3.4, centro.dy + 0.2)
        ..lineTo(centro.dx - 1.0, centro.dy + 2.6)
        ..lineTo(centro.dx + 3.6, centro.dy - 2.6),
      pincel,
    );
  }

  @override
  bool shouldRepaint(_PintorDelSimbolo viejo) => viejo.cual != cual;
}

/// UNA CHINCHETA POR SITIO, con todas las paradas que caen en el.
///
/// Ver el comentario largo del paso 3 de `_PintorDelCroquis.paint`: dos paradas
/// en la misma direccion se dibujaban una encima de otra y el mapa ensenaba
/// menos paradas de las que hay.
class ParadasJuntas {
  ParadasJuntas(this.donde, this.rotulo, this.color);

  final Offset donde;

  /// Los numeros de las paradas que hay aqui: `3`, o `2\u00b73`, o `2\u00b73+2`.
  final String rotulo;

  final Color color;
}

/// EL REDONDEO CON EL QUE DOS PARADAS SON «EL MISMO SITIO», en pixeles.
///
/// La chincheta mide 21 px de ancho (radio 10,5). Con menos de eso, dos
/// marcadores se solapan lo bastante como para que uno tape el numero del otro,
/// que es el fallo que esto viene a cerrar — no hace falta que caigan en el
/// pixel exacto.
///
/// No se sube mas: agrupar dos portales de la misma cuadra en una sola chincheta
/// seria mentir por el otro lado, y el chofer tiene que ir a los dos.
const _mismoSitio = 20.0;

/// Cuantos numeros caben en una chincheta antes de que no se lea ninguno.
///
/// Con tres ya va justo (`2\u00b73\u00b74`); a partir de ahi se dice el primero y
/// **cuantos mas hay**, que es la pregunta de quien conduce: «¿cuantas me quedan
/// aqui?».
const _numerosQueCaben = 3;

/// Junta las paradas que caen en el mismo sitio, **en el orden de visita**.
///
/// Es una funcion suelta y no un metodo a proposito: asi se prueba con `Offset`
/// a mano, sin montar un widget ni pintar nada
/// (`test/pantallas/rutas/dos_paradas_en_el_mismo_portal_test.dart`).
List<ParadasJuntas> lasQueCaenJuntas(List<PuntoDelCroquis> paradas) {
  final grupos = <List<PuntoDelCroquis>>[];
  for (final punto in paradas) {
    final juntoA = grupos
        .where((g) => (g.first.donde - punto.donde).distance <= _mismoSitio)
        .firstOrNull;
    if (juntoA == null) {
      grupos.add([punto]);
    } else {
      juntoA.add(punto);
    }
  }

  return [
    for (final g in grupos)
      ParadasJuntas(
        // El sitio es el de la PRIMERA, no el promedio: promediar mueve la
        // chincheta a un punto donde no hay ninguna parada.
        g.first.donde,
        _rotuloDe(g),
        _colorDe(g),
      ),
  ];
}

String _rotuloDe(List<PuntoDelCroquis> grupo) {
  final numeros = [for (final p in grupo) '${p.parada.numero}'];
  if (numeros.length <= _numerosQueCaben) return numeros.join('\u00b7');
  // «2·3·4+5»: los que caben y cuantos mas hay. Un `…` no dice cuantos, y
  // cuantos es justo lo que hace falta para saber si la ruta esta terminada.
  final caben = numeros.take(_numerosQueCaben).join('\u00b7');
  return '$caben+${numeros.length - _numerosQueCaben}';
}

/// EL COLOR DEL GRUPO ES EL DE LO QUE FALTA.
///
/// Con una parada entregada y otra sin entregar en el mismo portal, pintar el
/// grupo en verde —el color de «entregada»— dice «aqui ya esta hecho» sobre una
/// parada que sigue en el camion. Mientras quede una sin entregar, la chincheta
/// es la del recorrido.
Color _colorDe(List<PuntoDelCroquis> grupo) {
  final queda = grupo.where((p) => !p.parada.entregada).toList();
  if (queda.isEmpty) return ColoresDelMapa.salida;
  return queda.any((p) => p.parada.esRegreso)
      ? ColoresDelMapa.regreso
      : ColoresDelMapa.recorrido;
}

class _PintorDelCroquis extends CustomPainter {
  _PintorDelCroquis({
    required this.recorrido,
    required this.teselas,
    required this.sello,
    required this.porCarretera,
    required this.regresoPorCarretera,
    required this.textos,
    required this.acercamiento,
    required this.arrastre,
  });

  final Recorrido recorrido;
  final Map<String, ui.Image> teselas;

  /// Ver [_selloDeLasTeselas]: lo único comparable de un almacén compartido.
  final int sello;
  final List<Punto>? porCarretera;
  final List<Punto>? regresoPorCarretera;
  final TextStyle textos;
  final double acercamiento;
  final Offset arrastre;

  @override
  void paint(Canvas lienzo, Size tamano) {
    final trazado = trazar(
      recorrido,
      tamano,
      acercamiento: acercamiento,
      arrastre: arrastre,
    );
    if (trazado.estaVacio) return;

    // 0. EL FONDO DE CALLES, si llego. Va debajo de todo y no hace falta para
    //    nada: sin el, el resto se pinta igual sobre el papel.
    final hayCalles = _calles(lienzo, trazado);

    // 1. LA IDA. Por carretera si OSRM contesto; en linea recta si no, que es a
    //    lo que cae tambien el patron.
    final ida = porCarretera == null
        ? trazado.ida
        : [for (final p in porCarretera!) trazado.de(p)];
    if (ida.length > 1) {
      lienzo.drawPath(
        Path()..addPolygon(ida, false),
        Paint()
          ..color = ColoresDelMapa.recorrido
          ..strokeWidth = hayCalles ? 4 : 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      // Y ENCIMA, EL SENTIDO DE LA MARCHA.
      _flechas(lienzo, ida, ColoresDelMapa.recorrido, hayCalles);
    }

    // 2. EL REGRESO AL DEPOSITO, a rayas y en naranja, como el `dashArray` del
    //    patron. Solo se pinta aparte cuando la linea es recta: con el recorrido
    //    por carretera el regreso ya viene dentro del trazado que dio OSRM.
    final origen = trazado.origen;
    // Se pinta SIEMPRE, con calles y sin ellas. Antes solo salia sin calles, y
    // entonces la leyenda prometia un regreso que no estaba dibujado.
    if (origen != null && trazado.paradas.isNotEmpty) {
      final pincel = Paint()
        ..color = ColoresDelMapa.regreso
        ..strokeWidth = hayCalles ? 3.5 : 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      // **Corrido a un lado.** Con una sola parada —o con cualquier tramo que
      // se recorre en los dos sentidos— la vuelta va por la misma carretera que
      // la ida, asi que encima se dibujan una sobre otra y la de arriba tapa la
      // de abajo: se ve una sola linea naranja y desaparece la ida. Apartandola
      // unos pixeles se ven las dos en paralelo, que es como se lee en el
      // patron.
      const aparte = 3.5;
      final vuelta = regresoPorCarretera;
      if (vuelta != null && vuelta.length > 1) {
        final puntos = [for (final p in vuelta) trazado.de(p)];
        for (var i = 0; i < puntos.length - 1; i++) {
          final (a, b) = _corrido(puntos[i], puntos[i + 1], aparte);
          _rayas(lienzo, a, b, pincel);
        }
      } else {
        final (a, b) = _corrido(trazado.paradas.last.donde, origen, aparte);
        _rayas(lienzo, a, b, pincel);
      }
    }

    // 3. LAS PARADAS, numeradas en su orden — Y LAS QUE CAEN JUNTAS, CONTADAS.
    //
    // ## El fallo, visto por Jose el 29/09/2026
    //
    // Una ruta con TRES paradas dibujaba DOS chinchetas. «Por qué siguen 2 en vez
    // de 3, son 3 paradas y sólo veo 2.»
    //
    // Las paradas 2 y 3 eran el mismo cliente en la misma direccion
    // —`POR26-260927-3733` y `POR26-260925-3700`, los dos «KIOSKO HABANA CLUB
    // OMAR JIMENEZ MONTOYA L2» en Aguilera/San Agustin y Baranda— asi que sus
    // marcadores caian en el MISMO pixel y el de atras quedaba tapado por el de
    // delante. Este bucle pintaba los dos, uno encima del otro.
    //
    // ## Por que no es cosmetico
    //
    // **Quien lleva el camion cuenta las chinchetas** para saber cuantas paradas
    // le quedan; Jose acaba de hacerlo. Con doce paradas donde cuatro comparten
    // direccion se ven ocho, y se da por hecho que faltan pedidos — o peor, se
    // da la ruta por terminada con cuatro entregas sin hacer.
    //
    // Es la misma familia que lo del 28/09/2026 —dos pedidos del mismo cliente
    // contados como uno en el peso de la ruta— en el mapa en vez de en el peso.
    // Un cliente con dos pedidos el mismo dia no es raro: la tarjeta del tablero
    // lo dice con sus palabras, «2 pedidos de este cliente hoy».
    //
    // ## Lo que se hace
    //
    // Las que caen en el mismo sitio se dibujan **una vez, con sus numeros
    // dentro**: `2·3`. Ninguna se esconde y el numero de chinchetas deja de
    // mentir sobre cuantas paradas hay.
    for (final grupo in lasQueCaenJuntas(trazado.paradas)) {
      _marca(
        lienzo,
        grupo.donde,
        grupo.rotulo,
        // EL COLOR DEL GRUPO ES EL DE LA QUE FALTA, no el de la primera. Con una
        // entregada y otra sin entregar en el mismo portal, pintarlo en verde
        // dice «aqui ya esta hecho» sobre una parada que sigue en el camion.
        grupo.color,
      );
    }

    // 4. EL ALMACEN, el ultimo para que quede encima de todo: es el punto al
    //    que se vuelve y el que no se puede perder de vista.
    if (origen != null) _almacen(lienzo, origen);

    // 5. LA ESCALA. Sin calles no hay nada de donde deducir el tamano de lo que
    //    se esta viendo: sin esta barra, dos manzanas y media provincia se
    //    dibujan exactamente igual.
    _escala(lienzo, tamano, trazado.kmPorPixel);

    // 6. LA ATRIBUCION, que la licencia de OSM EXIGE en cuanto se pinta una
    //    tesela suya. No es adorno: sin ella no se pueden usar.
    if (hayCalles) {
      _letrero(
        lienzo,
        Offset(tamano.width - 96, tamano.height - 10),
        '© OpenStreetMap',
        Colores.gris,
        9,
      );
    }
  }

  bool _calles(Canvas lienzo, Trazado trazado) {
    var alguna = false;
    for (final t in trazado.teselasQueHacenFalta()) {
      final imagen = teselas['${t.z}/${t.x}/${t.y}'];
      if (imagen == null) continue;
      alguna = true;
      lienzo.drawImageRect(
        imagen,
        Rect.fromLTWH(0, 0, imagen.width.toDouble(), imagen.height.toDouble()),
        trazado.recuadroDe(t.z, t.x, t.y),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    if (alguna) {
      // Un velo de papel por encima: sobre un mapa de calles a todo color, una
      // linea azul y unos circulos numerados se pierden. Lo justo para que el
      // recorrido mande y las calles se sigan leyendo.
      lienzo.drawRect(
        Offset.zero & trazado.tamano,
        Paint()..color = Colores.papel.withValues(alpha: 0.28),
      );
    }
    return alguna;
  }

  /// LAS FLECHAS DE SENTIDO, repartidas a lo largo de la linea.
  ///
  /// Jose, 17/09/2026, con el mapa delante: «aquí el mapa se rompe en el punto
  /// dos, no sé a dónde va eso; necesito algo que identifique cómo va a ser el
  /// recorrido para saber cómo sería, necesito entender cómo va avanzando el
  /// viaje».
  ///
  /// Y es justo lo que faltaba: una linea entre dos circulos numerados dice por
  /// donde se pasa, pero **no dice hacia donde**. Con dos paradas todavia se
  /// adivina por los numeros; con ocho, y con el recorrido por carretera dando
  /// vueltas por calles de un solo sentido, no se adivina — hay tramos que se
  /// recorren dos veces y ahi el numero no ayuda.
  ///
  /// Van cada [_cadaCuantoUnaFlecha] pixeles de recorrido, no cada tantos
  /// puntos: OSRM devuelve cientos de puntos muy juntos en las curvas y uno
  /// cada pocos kilometros en la carretera, asi que contar puntos amontonaria
  /// las flechas en las rotondas y dejaria la recta vacia.
  void _flechas(
    Canvas lienzo,
    List<Offset> linea,
    Color color,
    bool hayCalles,
  ) {
    if (linea.length < 2) return;
    final pincel = Paint()
      ..color = color
      ..strokeWidth = hayCalles ? 2.4 : 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final borde = Paint()
      ..color = Colores.blanco
      ..strokeWidth = (hayCalles ? 2.4 : 1.8) + 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Lo que falta para la siguiente flecha. Empieza a medias para que la
    // primera no caiga pegada al almacen, donde ya se sabe que se sale.
    var restante = _cadaCuantoUnaFlecha / 2;
    for (var i = 0; i < linea.length - 1; i++) {
      final desde = linea[i];
      final hasta = linea[i + 1];
      final largo = (hasta - desde).distance;
      if (largo == 0) continue;
      final paso = (hasta - desde) / largo;
      var t = restante;
      while (t <= largo) {
        _puntaDeFlecha(lienzo, desde + paso * t, paso, borde, pincel);
        t += _cadaCuantoUnaFlecha;
      }
      restante = t - largo;
    }
  }

  /// Una punta de flecha: dos rayas en «V» hacia atras desde el punto, con
  /// reborde blanco para que se lea sobre las calles.
  void _puntaDeFlecha(
    Canvas lienzo,
    Offset donde,
    Offset sentido,
    Paint borde,
    Paint pincel,
  ) {
    const largo = 5.5;
    final normal = Offset(-sentido.dy, sentido.dx);
    final cola = donde - sentido * largo;
    final camino = Path()
      ..moveTo(cola.dx + normal.dx * 3.4, cola.dy + normal.dy * 3.4)
      ..lineTo(donde.dx, donde.dy)
      ..lineTo(cola.dx - normal.dx * 3.4, cola.dy - normal.dy * 3.4);
    lienzo
      ..drawPath(camino, borde)
      ..drawPath(camino, pincel);
  }

  /// El mismo tramo, corrido [cuanto] pixeles a un lado.
  (Offset, Offset) _corrido(Offset desde, Offset hasta, double cuanto) {
    final largo = (hasta - desde).distance;
    if (largo == 0) return (desde, hasta);
    final normal = Offset(-(hasta.dy - desde.dy), hasta.dx - desde.dx) / largo;
    return (desde + normal * cuanto, hasta + normal * cuanto);
  }

  void _rayas(Canvas lienzo, Offset desde, Offset hasta, Paint pincel) {
    const raya = 7.0;
    const hueco = 5.0;
    final total = (hasta - desde).distance;
    if (total == 0) return;
    final paso = (hasta - desde) / total;
    for (var t = 0.0; t < total; t += raya + hueco) {
      lienzo.drawLine(
        desde + paso * t,
        desde + paso * math.min(t + raya, total),
        pincel,
      );
    }
  }

  /// LA CHINCHETA DE UNA PARADA — o de varias, si caen en el mismo sitio.
  ///
  /// Con un numero corto es el circulo de siempre. Con un rotulo de grupo
  /// —`2\u00b73`— **se ensancha**: en un circulo de 18 px de diametro no cabe, y
  /// un rotulo que se sale del circulo se lee peor que el fallo que vino a
  /// arreglar. La altura no cambia, asi que sigue siendo la misma chincheta.
  void _marca(Canvas lienzo, Offset donde, String numero, Color color) {
    const alto = 21.0;
    // 6,5 px por caracter es lo que ocupa el texto a tamano 10 con esta fuente,
    // medido; el resto es el aire de los lados.
    final ancho = math.max(alto, numero.length * 6.5 + 11);
    final caja = Rect.fromCenter(center: donde, width: ancho, height: alto);
    final forma = RRect.fromRectAndRadius(
      caja,
      const Radius.circular(alto / 2),
    );
    lienzo
      ..drawRRect(forma, Paint()..color = Colores.blanco)
      ..drawRRect(forma.deflate(1.5), Paint()..color = color);
    _letrero(lienzo, donde, numero, Colores.blanco, 10, centrado: true);
  }

  /// EL ALMACEN DE SALIDA: un alfiler, no un cuadro.
  ///
  /// Jose, 17/09/2026, con el mapa delante: «cómo las muestras en el mapa
  /// también está mal», y antes «los iconos están macabros». Era un cuadrado
  /// de 18 px en tinta —casi negro— plantado sobre un mapa de calles a todo
  /// color: se lee como un agujero en el mapa, no como el sitio de donde sale
  /// el camion.
  ///
  /// Ahora es la forma que todo el mundo reconoce en un mapa —gota con la punta
  /// abajo, apuntando al sitio exacto— y en el verde de la paleta, que es el
  /// que ya significa «bien» en esta aplicacion. El reborde blanco es lo que lo
  /// despega del fondo: sin el, sobre una mancha verde de vegetacion
  /// desaparece.
  ///
  /// La punta cae EN la coordenada, no el centro: un alfiler centrado senala
  /// medio centimetro mas arriba de donde esta el almacen, y a la escala de una
  /// ciudad eso son dos manzanas.
  void _almacen(Canvas lienzo, Offset donde) {
    const radio = 9.0;
    const alto = 23.0;
    final centro = Offset(donde.dx, donde.dy - alto + radio);

    Path gota(double r, Offset c, double punta) => Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..moveTo(c.dx - r * 0.62, c.dy + r * 0.78)
      ..lineTo(c.dx, punta)
      ..lineTo(c.dx + r * 0.62, c.dy + r * 0.78)
      ..close();

    lienzo
      ..drawPath(
        gota(radio + 1.6, centro, donde.dy + 1.6),
        Paint()..color = Colores.blanco,
      )
      ..drawPath(
        gota(radio, centro, donde.dy),
        Paint()..color = ColoresDelMapa.salida,
      );
    _dibujarEstrella(lienzo, centro, 4.6, Colores.blanco);

    _letrero(
      lienzo,
      donde + const Offset(0, 6),
      recorrido.nombreDelOrigen == null
          ? 'Salida'
          : 'Salida · ${recorrido.nombreDelOrigen}',
      Colores.tinta,
      10,
      centrado: true,
    );
  }

  void _escala(Canvas lienzo, Size tamano, double kmPorPixel) {
    if (kmPorPixel <= 0) return;
    // Una barra de un numero redondo: 1, 2, 5, 10, 20, 50… que ocupe como mucho
    // un tercio del ancho.
    final maximo = kmPorPixel * (tamano.width / 3);
    if (maximo <= 0 || !maximo.isFinite) return;
    final potencia = math.pow(10, (math.log(maximo) / math.ln10).floor());
    var km = potencia.toDouble();
    for (final paso in [1, 2, 5]) {
      if (potencia * paso <= maximo) km = potencia * paso.toDouble();
    }
    final largo = km / kmPorPixel;
    final y = tamano.height - 14;
    lienzo.drawLine(
      Offset(12, y),
      Offset(12 + largo, y),
      Paint()
        ..color = Colores.gris
        ..strokeWidth = 2,
    );
    _letrero(
      lienzo,
      Offset(12, y - 13),
      km >= 1 ? '${km.toStringAsFixed(0)} km' : '${(km * 1000).round()} m',
      Colores.gris,
      9,
    );
  }

  void _letrero(
    Canvas lienzo,
    Offset donde,
    String texto,
    Color color,
    double tamano, {
    bool centrado = false,
  }) {
    final pintor = TextPainter(
      text: TextSpan(
        text: texto,
        style: textos.copyWith(
          color: color,
          fontSize: tamano,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pintor.paint(
      lienzo,
      centrado
          ? donde - Offset(pintor.width / 2, pintor.height / 2)
          : donde - Offset(0, pintor.height / 2),
    );
  }

  /// **EL ZOOM Y EL REGRESO TAMBIEN CUENTAN.**
  ///
  /// Jose, 17/09/2026, dos veces: «el zoom y el alejar sigue sin funcionar».
  /// Y no funcionaba, pero no por los botones: pulsarlos cambiaba
  /// `_acercamiento` y `setState` corria, sólo que este `shouldRepaint` no
  /// miraba ese campo, asi que Flutter se ahorraba el repintado y el mapa se
  /// quedaba igual. Un boton que cambia el estado y no cambia el dibujo es
  /// peor que un boton apagado: parece roto sin serlo.
  ///
  /// La regla que sale de aqui: **en `shouldRepaint` van TODOS los campos que
  /// el `paint` lee**. Cada vez que se le anade uno al pintor hay que anadirlo
  /// tambien aqui, y si no, el fallo no salta — simplemente no se ve.
  @override
  bool shouldRepaint(_PintorDelCroquis viejo) =>
      !identical(viejo.recorrido, recorrido) ||
      viejo.sello != sello ||
      !identical(viejo.porCarretera, porCarretera) ||
      !identical(viejo.regresoPorCarretera, regresoPorCarretera) ||
      viejo.acercamiento != acercamiento ||
      viejo.arrastre != arrastre;
}

/// LOS BOTONES DE ACERCAR Y ALEJAR.
///
/// Jose, 17/09/2026, con el mapa delante: «no puedo hacer zoom o alejarlo».
/// Tenia razon y era a proposito a medias: el mapa se dibuja al encuadre que
/// cabe, y no habia forma de mirar de cerca una parada.
///
/// **Botones y no pellizco.** Un reconocedor de pellizco o de arrastre aqui
/// dentro le gana el gesto a la lista del detalle, y entonces el dedo sobre el
/// mapa deja de poder bajar la pantalla — que es como el chofer se queda sin
/// llegar al final. Un toque no compite con un arrastre.
///
/// Arriba a la izquierda, como el patron. Y el de encuadrar **solo sale cuando
/// hay algo a lo que volver**: un boton que no hace nada ensena a desconfiar de
/// los que si hacen.
class _BotonesDeZoom extends StatelessWidget {
  const _BotonesDeZoom({required this.acercamiento, required this.alCambiar});

  final double acercamiento;
  final void Function(double) alCambiar;

  /// Se dobla y se parte por la mitad: son los saltos de un nivel de tesela,
  /// que es como se mueve cualquier mapa.
  static const paso = 2.0;

  @override
  Widget build(BuildContext context) {
    final puedeAcercar = acercamiento < _CroquisDeRutaState.acercamientoMaximo;
    final puedeAlejar = acercamiento > _CroquisDeRutaState.acercamientoMinimo;
    // El de encuadrar sale cuando NO se está en el encuadre, se haya llegado
    // ahí acercando o alejando.
    final fueraDelEncuadre = acercamiento != 1;

    return Positioned(
      left: 8,
      top: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Boton(
            icono: Icons.add,
            rotulo: 'Acercar (o Ctrl + rueda)',
            alPulsar: puedeAcercar
                ? () => alCambiar(
                    (acercamiento * paso).clamp(
                      _CroquisDeRutaState.acercamientoMinimo,
                      _CroquisDeRutaState.acercamientoMaximo,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          _Boton(
            icono: Icons.remove,
            rotulo: 'Alejar',
            alPulsar: puedeAlejar
                ? () => alCambiar(
                    (acercamiento / paso).clamp(
                      _CroquisDeRutaState.acercamientoMinimo,
                      _CroquisDeRutaState.acercamientoMaximo,
                    ),
                  )
                : null,
          ),
          if (fueraDelEncuadre) ...[
            const SizedBox(height: 4),
            _Boton(
              icono: Icons.fit_screen_outlined,
              rotulo: 'Ver la ruta entera',
              alPulsar: () => alCambiar(1),
            ),
          ],
        ],
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    required this.icono,
    required this.rotulo,
    required this.alPulsar,
  });

  final IconData icono;
  final String rotulo;
  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) {
    final apagado = alPulsar == null;
    return Tooltip(
      message: rotulo,
      child: Material(
        color: Colores.blanco,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: alPulsar,
          // El area del dedo, no la del icono: 32 px es lo minimo que se acierta
          // sin mirar, con el telefono en una mano y una caja en la otra.
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icono,
              size: 18,
              color: apagado ? Colores.linea : Colores.tinta,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EL MAPA EN GRANDE
// ─────────────────────────────────────────────────────────────────────────────

/// Abre el mapa a pantalla completa.
///
/// Jose, 21/09/2026, con la APK: «ni me puedo mover en el mapa desde la apk
/// estoy sellado ahi y no me puedo mover». Dentro del detalle el mapa no puede
/// quedarse con el arrastre de un dedo —es el de la lista, y sin el no se llega
/// al final de la pantalla—, asi que con dos dedos se pellizca y se mueve, y
/// para mirar el mapa de verdad se abre aqui: **sin lista debajo, un dedo lo
/// mueve**, como en cualquier mapa.
Future<void> abrirElMapaEnGrande(
  BuildContext context, {
  required Recorrido recorrido,
  required FondoDeCalles fondo,
  required RecorridoPorCalles porCalles,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) =>
        MapaEnGrande(recorrido: recorrido, fondo: fondo, porCalles: porCalles),
  ),
);

/// La pantalla del mapa en grande. **Publica para poder montarla en una prueba**
/// sin tener que navegar hasta ella.
class MapaEnGrande extends StatelessWidget {
  const MapaEnGrande({
    required this.recorrido,
    required this.fondo,
    required this.porCalles,
    super.key,
  });

  final Recorrido recorrido;
  final FondoDeCalles fondo;
  final RecorridoPorCalles porCalles;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colores.blanco,
    appBar: AppBar(
      title: const Text('Mapa de la ruta'),
      // La ✕ nunca puede desaparecer: es regla de la casa en todos los
      // proyectos de Procovar.
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cerrar el mapa',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: CroquisDeRuta(
        recorrido: recorrido,
        fondo: fondo,
        porCalles: porCalles,
        aPantallaCompleta: true,
      ),
    ),
  );
}
